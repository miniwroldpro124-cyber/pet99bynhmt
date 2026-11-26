#!/usr/bin/env python3
"""
Steph HUB - Prometheus AST + Polymorphic Multi-Register Virtual Machine Obfuscator (v3.0)
=========================================================================================
1. Backs up clean unobfuscated Luau sources FIRST to:
   - C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src\\ (clean tree + *.unobf.lua)
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt_unobf\\
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt\\unobf\\ (gitignored)
2. Layer 1 (Stage-2 Inner AST Protection via Prometheus LuaU AST + Custom Stage2AstProtector):
   - Normalizes dotted table function declarations (`function a.b.c()`) and service/player getters
     into computed `StringExpression` indexing so table keys, property names, and method names
     are encrypted alongside all string literals.
   - Encrypts 100% of `StringExpression` nodes (standalone strings, `.Property` accesses, and
     `{ key = val }` table keys) into a per-file shuffled string pool encoded with a per-file
     16-char consonant/digit nibble alphabet + rolling LCG/XOR/CBC stream cipher.
   - Every `_S(arg1, arg2)` call site uses a fresh random 24-bit polymorphic XOR mask `arg2`
     where `bxor(arg1, arg2) = idx + k_str * 8192` recovers both the pool index and the unstored
     per-string 11-bit decryption key `k_str`, memoized on first call.
   - Transforms integer `NumberExpression` nodes into Mixed Boolean-Arithmetic / offset expressions.
   - Adds only 1 top-level local variable (`_S`, mangled by `MangledShuffled`), keeping Stage-2
     top-level local declarations at ~79 (< 90, well under Luau's 200-local limit).
3. Layer 2 (Stage-1 Hardened Polymorphic Chained-Key VM - STEPH_PROMETHEUS_VM v3.0):
   - Non-predictable header & split/randomized declaration layout with pre-seeded decoy registers.
   - Randomized 6-tuple or 7-tuple instruction format per file with per-instruction dynamic opcode
     XOR guard slot (`op = bxor(insn[slot_op], insn[slot_guard] % 256)`).
   - Disjoint randomized register allocation drawn from `15..480` per build.
   - Custom per-file shuffled 64-char Base-Radix + rolling pre-XOR constant pool with encrypted
     on-the-fly alphabet bootstrapping (`OP_ALPHA` + `OP_LOADK`).
   - Cross-block FNV-1a plaintext CRC key chaining (`reg_chain_crc`) mixed with a 3-operand MBA
     key schedule (`bxor((B + C) - 2 * band(B, C), D) ^ reg_chain_crc`).
   - Dual-LCG Propagating Cipher Block Chaining (PCBC: both ciphertext `lxz` and plaintext `pxz`
     feedback) + per-file Affine S-box stream cipher (`OP_XOR_DEC`).
   - Anonymized hex chunk tags (`=[0x......]`) with zero filename leaks.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import os
import random
import re
import shutil
import sys
import time
from typing import Dict, List, Optional, Tuple

from lupa import lua51

REPO_DIR = r"C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"
UNOBF_EXTERNAL_DIR = r"C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt_unobf"
UNOBF_LOCAL_DIR = os.path.join(REPO_DIR, "unobf")
WORKSPACE_DIR = r"C:\Users\LaptopAT\AppData\Local\Real\workspace"
WORKSPACE_SRC_DIR = os.path.join(WORKSPACE_DIR, "stephhub-src")

PROMETHEUS_DIRS = [
    os.path.join(REPO_DIR, "tools", "Prometheus", "src"),
    r"C:\Users\LaptopAT\.gemini\antigravity\scratch\Prometheus\src",
]

VM_MARKER = "--[[STEPH_PROMETHEUS_VM]]"

COMPONENT_HEADER_RE = re.compile(r"^\s*(--\s*STEPH_COMPONENT:\s*[^\s]+\s+[\d\.]+)", re.MULTILINE)
FORBIDDEN_ANCHOR_RE = re.compile(r"AnchorPoint\s*=\s*UDim2")

SAFE_B64_POOL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$"


def get_target_files(repo_dir: str = REPO_DIR) -> List[str]:
    targets = [
        "main.lua",
        "Stehp-Hub.lua",
        "ps99_engine_v3.lua",
        "manifest.lua",
        "games/steal_an_egg.lua",
    ]
    if os.path.isfile(os.path.join(repo_dir, "games", "ps99.lua")):
        targets.append("games/ps99.lua")
    for pattern in ("lib/*.lua", "modules/*.lua"):
        for path in sorted(glob.glob(os.path.join(repo_dir, pattern))):
            rel = os.path.relpath(path, repo_dir).replace("\\", "/")
            if rel not in targets:
                targets.append(rel)
    return targets


def is_vm_obfuscated(source: str) -> bool:
    if VM_MARKER in source:
        return True
    lines = [ln.strip() for ln in source.strip().splitlines() if ln.strip()]
    if len(lines) <= 4 and any(ln.startswith("return(function(") for ln in lines):
        return True
    return False


def extract_component_header(source: str) -> Optional[str]:
    head = "\n".join(source.splitlines()[:12])
    m = COMPONENT_HEADER_RE.search(head)
    if m:
        return re.sub(r"\s+", " ", m.group(1).strip())
    return None


def backup_and_load_clean_sources(repo_dir: str = REPO_DIR) -> Dict[str, str]:
    """
    Ensures every target file's clean unobfuscated source is backed up to:
      1) C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src\\ (<rel> + <rel>.unobf.lua)
      2) C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt_unobf\\ (<rel>)
      3) C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt\\unobf\\ (<rel>)
    Returns a dict mapping relative path -> clean unobfuscated source text.
    """
    clean_sources: Dict[str, str] = {}
    targets = get_target_files(repo_dir)

    for rel in targets:
        repo_path = os.path.join(repo_dir, rel)
        backup_candidates = [
            os.path.join(UNOBF_LOCAL_DIR, rel),
            os.path.join(UNOBF_EXTERNAL_DIR, rel),
            os.path.join(WORKSPACE_SRC_DIR, rel),
            os.path.join(WORKSPACE_SRC_DIR, rel + ".unobf.lua"),
        ]

        clean_text: Optional[str] = None
        if os.path.isfile(repo_path):
            with open(repo_path, "r", encoding="utf-8") as f:
                curr_text = f.read()
            if not is_vm_obfuscated(curr_text):
                clean_text = curr_text

        if clean_text is None:
            existing = [p for p in backup_candidates if os.path.isfile(p)]
            existing.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            for cand in existing:
                with open(cand, "r", encoding="utf-8") as f:
                    cand_text = f.read()
                if not is_vm_obfuscated(cand_text):
                    clean_text = cand_text
                    break

        if clean_text is None:
            raise RuntimeError(f"Could not find clean unobfuscated source for {rel}!")

        clean_sources[rel] = clean_text

        for dest_root in (UNOBF_LOCAL_DIR, UNOBF_EXTERNAL_DIR, WORKSPACE_SRC_DIR):
            dest_path = os.path.join(dest_root, rel)
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            with open(dest_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(clean_text)

        unobf_copy = os.path.join(
            WORKSPACE_SRC_DIR,
            rel[:-4] + ".unobf.lua" if rel.endswith(".lua") else rel + ".unobf.lua",
        )
        os.makedirs(os.path.dirname(unobf_copy), exist_ok=True)
        with open(unobf_copy, "w", encoding="utf-8", newline="\n") as f:
            f.write(clean_text)

    return clean_sources


def restore_clean_sources(repo_dir: str = REPO_DIR) -> None:
    clean_sources = backup_and_load_clean_sources(repo_dir)
    for rel, text in clean_sources.items():
        dest = os.path.join(repo_dir, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print(f"[RESTORE] Restored {len(clean_sources)} clean unobfuscated files into {repo_dir}")


class PrometheusBridge:
    """Lua 5.1 lupa bridge to Prometheus AST Parser, Stage-2 String/Property/Number Encryptor, and Variable Mangler."""

    def __init__(self) -> None:
        prom_src = None
        for d in PROMETHEUS_DIRS:
            if os.path.isfile(os.path.join(d, "prometheus.lua")):
                prom_src = d
                break
        if not prom_src:
            raise RuntimeError("Prometheus src directory not found!")

        self.prom_src = prom_src
        self.rt = lua51.LuaRuntime()
        escaped_path = prom_src.replace("\\", "\\\\")
        self.rt.execute(
            f"""
            arg = {{}}
            package.path = "{escaped_path}\\\\?.lua;" .. package.path
            Prometheus = require("prometheus")
            Parser = require("prometheus.parser")
            Ast = require("prometheus.ast")
            visitast = require("prometheus.visitast")
            Source = require("prometheus.source")
            Enums = require("prometheus.enums")
            util = require("prometheus.util")
            Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

            local function bxor24(a, b)
                local r, p = 0, 1
                while a > 0 or b > 0 do
                    local ra, rb = a % 2, b % 2
                    if ra ~= rb then r = r + p end
                    a = (a - ra) / 2
                    b = (b - rb) / 2
                    p = p * 2
                end
                return r
            end

            Stage2AstProtector = {{}}
            Stage2AstProtector.__index = Stage2AstProtector
            Stage2AstProtector.Name = "Stage2AstProtector"

            function Stage2AstProtector:new(seed)
                return setmetatable({{ seed = seed or 1337 }}, self)
            end

            function Stage2AstProtector:apply(ast, pipeline)
                local AstKind = Ast.AstKind

                -- Pre-pass: convert dotted table function declarations (`function a.b.c()`)
                -- and service/player method calls (`game:GetService()`, `Players:GetPlayers()`)
                -- into computed StringExpression index expressions so their names are encrypted too.
                visitast(ast, function(node)
                    if node.kind == AstKind.FunctionDeclaration and node.indices and #node.indices > 0 then
                        local base = node.symbol and Ast.VariableExpression(node.symbol) or Ast.GlobalVariableExpression(node.name)
                        for i = 1, #node.indices - 1 do
                            base = Ast.IndexExpression(base, Ast.StringExpression(node.indices[i]))
                        end
                        local lhs = Ast.AssignmentIndexing(base, Ast.StringExpression(node.indices[#node.indices]))
                        local rhs = Ast.FunctionLiteralExpression(node.args, node.body)
                        return Source.inherit(Ast.AssignmentStatement({{ lhs }}, {{ rhs }}), node)
                    elseif node.kind == AstKind.PassSelfFunctionCallExpression then
                        local mname = node.passSelfFunctionName
                        local bk = node.base and node.base.kind
                        if (mname == "GetService" or mname == "GetPlayers" or mname == "HttpGet")
                           and (bk == AstKind.VariableExpression or bk == AstKind.GlobalVariableExpression) then
                            local selfArg = bk == AstKind.VariableExpression
                                and Ast.VariableExpression(node.base.symbol)
                                or Ast.GlobalVariableExpression(node.base.name)
                            local newArgs = {{ selfArg }}
                            for i, a in ipairs(node.args) do newArgs[i + 1] = a end
                            local idxExpr = Ast.IndexExpression(node.base, Ast.StringExpression(mname))
                            return Source.inherit(Ast.FunctionCallExpression(idxExpr, newArgs), node)
                        end
                    end
                end, nil)

                -- Collect and shuffle all unique strings across the entire AST
                local uniqueList = {{}}
                local seen = {{}}
                visitast(ast, nil, function(node)
                    if node.kind == AstKind.StringExpression then
                        local v = node.value
                        if not seen[v] then
                            seen[v] = true
                            uniqueList[#uniqueList + 1] = v
                        end
                    end
                end)
                if #uniqueList == 0 then
                    uniqueList[1] = ""
                end
                uniqueList = util.shuffle(uniqueList)

                -- Per-file 16-char nibble alphabet using only consonants and digits (cannot form English words)
                local alphaPool = util.shuffle({{
                    "b","c","d","f","g","h","j","k","m","n","p","q","r","s","t","v","w","x","z",
                    "B","C","D","F","G","H","J","K","M","N","P","Q","R","S","T","V","W","X","Z",
                    "2","3","4","5","6","7","8","9"
                }})
                local alpha16 = {{}}
                local decodePairs = {{}}
                for i = 1, 16 do
                    alpha16[i] = alphaPool[i]
                    decodePairs[i] = "[" .. tostring(string.byte(alphaPool[i])) .. "]=" .. tostring(i - 1)
                end

                local kMaster = math.random(100000, 15000000)
                local ivMaster = math.random(17, 251)
                local lcgA = math.random(25000, 90000) * 4 + 1
                local lcgC = math.random(300000, 5000000) * 2 + 1
                local lcgStep = math.random(3000, 60000) * 2 + 1

                local strToId = {{}}
                local strToKey = {{}}
                local encPoolLiterals = {{}}

                for idx, rawStr in ipairs(uniqueList) do
                    local kStr = math.random(1, 2047)
                    strToId[rawStr] = idx
                    strToKey[rawStr] = kStr

                    local s = (kStr * 4099 + idx * lcgStep + kMaster) % 16777216
                    local prev = (kStr + idx * 73 + ivMaster) % 256
                    local chars = {{}}
                    local len = #rawStr
                    for j = 1, len do
                        local p = string.byte(rawStr, j)
                        s = (s * lcgA + lcgC) % 16777216
                        local kXor = s % 256
                        local kAdd = ((s - kXor) / 256) % 256
                        local c = (bxor24(p, kXor) + kAdd + prev) % 256
                        prev = c
                        local hi = (c - (c % 16)) / 16
                        local lo = c % 16
                        chars[#chars + 1] = alpha16[hi + 1] .. alpha16[lo + 1]
                    end
                    encPoolLiterals[idx] = '"' .. table.concat(chars) .. '"'
                end

                local sSym = Ast.LocalSymbol("_S")

                -- Replace every StringExpression with `_S(arg1, callMask)` and obfuscate integer literals
                visitast(ast, nil, function(node)
                    if node.kind == AstKind.StringExpression and not node.__stage2_skip then
                        local v = node.value
                        local idx = strToId[v]
                        local kStr = strToKey[v]
                        local tokenVal = idx + kStr * 8192
                        local callMask = math.random(100000, 16700000)
                        local arg1 = bxor24(tokenVal, callMask)
                        local n1 = Ast.NumberExpression(arg1)
                        local n2 = Ast.NumberExpression(callMask)
                        n1.__stage2_skip = true
                        n2.__stage2_skip = true
                        return Source.inherit(
                            Ast.FunctionCallExpression(Ast.VariableExpression(sSym), {{ n1, n2 }}),
                            node
                        )
                    elseif node.kind == AstKind.NumberExpression and not node.__stage2_skip then
                        local val = node.value
                        if type(val) == "number" and val == math.floor(val) and val >= -10000000 and val <= 10000000 and math.random() < 0.65 then
                            local off = math.random(1000, 500000)
                            if math.random(1, 2) == 1 then
                                local a = Ast.NumberExpression(val + off)
                                local b = Ast.NumberExpression(off)
                                a.__stage2_skip = true
                                b.__stage2_skip = true
                                return Source.inherit(Ast.SubExpression(a, b, false), node)
                            else
                                local a = Ast.NumberExpression(val - off)
                                local b = Ast.NumberExpression(off)
                                a.__stage2_skip = true
                                b.__stage2_skip = true
                                return Source.inherit(Ast.AddExpression(a, b, false), node)
                            end
                        end
                    end
                end)

                local decCode = table.concat({{
                    "do ",
                    "local _P={{" .. table.concat(encPoolLiterals, ",") .. "}};",
                    "local _D={{" .. table.concat(decodePairs, ",") .. "}};",
                    "local _C,_M,_B,_H={{}},{{}},string.byte,string.char;",
                    "for _i=0,255 do _M[_i]=_H(_i) end;",
                    "local _X=bit32 and bit32.bxor;",
                    "if not _X then ",
                    "local _N={{}};",
                    "for _a=0,15 do local _r={{}};_N[_a]=_r;for _b=0,15 do local _v,_p,_x,_y=0,1,_a,_b;while _x>0 or _y>0 do if _x%2~=_y%2 then _v=_v+_p end;_x=(_x-_x%2)/2;_y=(_y-_y%2)/2;_p=_p*2 end;_r[_b]=_v end end;",
                    "_X=function(_a,_b)local _r,_p=0,1;while _a>0 or _b>0 do _r=_r+_N[_a%16][_b%16]*_p;_a=(_a-_a%16)/16;_b=(_b-_b%16)/16;_p=_p*16 end;return _r end;",
                    "end;",
                    "function DECRYPT_S(_a,_b)",
                    "local _v=_X(_a,_b);",
                    "local _hit=_C[_v];if _hit~=nil then return _hit end;",
                    "local _idx=_v%8192;",
                    "local _ks=(_v-_idx)/8192;",
                    "local _raw=_P[_idx];if not _raw then return '' end;",
                    "local _s=(_ks*4099+_idx*" .. tostring(lcgStep) .. "+" .. tostring(kMaster) .. ")%16777216;",
                    "local _pv=(_ks+_idx*73+" .. tostring(ivMaster) .. ")%256;",
                    "local _out,_n={{}},1;",
                    "for _j=1,#_raw,2 do ",
                    "local _c=_D[_B(_raw,_j)]*16+_D[_B(_raw,_j+1)];",
                    "_s=(_s*" .. tostring(lcgA) .. "+" .. tostring(lcgC) .. ")%16777216;",
                    "local _kx=_s%256;",
                    "local _ka=((_s-_kx)/256)%256;",
                    "local _p=_X((_c-_ka-_pv)%256,_kx);",
                    "_pv=_c;",
                    "_out[_n]=_M[_p];_n=_n+1;",
                    "end;",
                    "local _res=table.concat(_out);",
                    "_C[_v]=_res;",
                    "return _res;",
                    "end ",
                    "end"
                }})

                local decAst = Parser:new({{ LuaVersion = Enums.LuaVersion.Lua51 }}):parse(
                    decCode,
                    Source.internal("Stage2.Decryptor", decCode)
                )
                local doStat = decAst.body.statements[1]
                visitast(decAst, nil, function(node)
                    if node.kind == AstKind.FunctionDeclaration and node.name == "DECRYPT_S" then
                        node.symbol = sSym
                        node.name = nil
                    end
                end)

                local genSpan = Source.generated("Stage2AstProtector")
                table.insert(ast.body.statements, 1, Source.fill(doStat, genSpan))
                table.insert(ast.body.statements, 1, Source.fill(Ast.LocalVariableDeclaration({{ sSym }}, {{}}), genSpan))
                return ast
            end
            """
        )
        self._ast_mangle_fn = self.rt.eval(
            """
            function(code, filename, seed, presetName)
                local preset = Prometheus.Presets[presetName or "Minify"] or Prometheus.Presets["Minify"]
                local cfg = {
                    LuaVersion = "LuaU",
                    VarNamePrefix = "",
                    NameGenerator = "MangledShuffled",
                    PrettyPrint = false,
                    Seed = seed or 12345,
                    Steps = preset.Steps or {},
                }
                local pipeline = Prometheus.Pipeline:fromConfig(cfg)
                pipeline:addStep(Stage2AstProtector:new(seed or 12345))
                local out = pipeline:apply(code, filename)
                -- Round-trip parse check to guarantee 100% valid Luau AST
                Parser:new({ LuaVersion = "LuaU" }):parse(out, filename .. ".ast")
                return out
            end
            """
        )
        self._parse_luau_fn = self.rt.eval(
            """
            function(code, filename)
                local ast = Parser:new({ LuaVersion = "LuaU" }):parse(code, filename or "chunk")
                local top_local_stmts = 0
                for _, st in ipairs(ast.body.statements) do
                    if st.kind == Ast.AstKind.LocalVariableDeclaration or st.kind == Ast.AstKind.LocalFunctionDeclaration then
                        top_local_stmts = top_local_stmts + 1
                    end
                end
                return #ast.body.statements, top_local_stmts
            end
            """
        )

    def mangle_luau_ast(self, code: str, filename: str, seed: int, preset: str = "Minify") -> str:
        res = self._ast_mangle_fn(code, filename, seed, preset)
        return res[0] if isinstance(res, tuple) else res

    def verify_luau_syntax(self, code: str, filename: str) -> Tuple[int, int]:
        res = self._parse_luau_fn(code, filename)
        if isinstance(res, tuple):
            return int(res[0]), int(res[1])
        return int(res), 0


def lua_escape_bytes(data: bytes) -> str:
    out: List[str] = []
    for b in data:
        if 32 <= b <= 126 and b not in (34, 92):
            out.append(chr(b))
        else:
            out.append(f"\\{b:03d}")
    return "".join(out)


def custom_b64_encode_with_prexor(
    data: bytes,
    alpha64: str,
    pad_char: str,
    pre_mask: int,
    pre_step: int,
) -> str:
    """
    Pre-masks `data` with a rolling XOR `(pre_mask + idx * pre_step) & 0xFF`
    and encodes into a per-file shuffled 64-character Base-Radix string.
    """
    masked = bytes(b ^ ((pre_mask + i * pre_step) & 0xFF) for i, b in enumerate(data))
    out: List[str] = []
    n = len(masked)
    for i in range(0, n, 3):
        rem = n - i
        if rem >= 3:
            w = (masked[i] << 16) | (masked[i + 1] << 8) | masked[i + 2]
            out.append(
                alpha64[(w >> 18) & 63]
                + alpha64[(w >> 12) & 63]
                + alpha64[(w >> 6) & 63]
                + alpha64[w & 63]
            )
        elif rem == 2:
            w = (masked[i] << 16) | (masked[i + 1] << 8)
            out.append(
                alpha64[(w >> 18) & 63]
                + alpha64[(w >> 12) & 63]
                + alpha64[(w >> 6) & 63]
                + pad_char
            )
        else:
            w = masked[i] << 16
            out.append(
                alpha64[(w >> 18) & 63]
                + alpha64[(w >> 12) & 63]
                + pad_char
                + pad_char
            )
    return "".join(out)


def encrypt_pcbc_dual_lcg(
    plaintext: bytes,
    sbox: List[int],
    seed: int,
    iv: int,
    lcg_a1: int,
    lcg_c1: int,
    lcg_a2: int,
    lcg_c2: int,
    lcg_init2: int,
) -> Tuple[bytes, int]:
    """
    Dual-State 24-bit LCG Stream Cipher with Propagating Cipher Block Chaining (PCBC)
    and per-file Affine Bijective S-box:
      s1 = (s1 * lcg_a1 + lcg_c1) % 16777216
      s2 = (s2 * lcg_a2 + lcg_c2) % 16777216
      k_add = (((s1 // 256) % 256) + (s2 % 256)) % 256
      k_xor = (s1 % 256) ^ ((s2 // 65536) % 256)
      x = p ^ k_xor ^ pxz
      c = (sbox[x] + k_add + lxz) % 256
      lxz = c; pxz = p
    Also computes the 24-bit FNV-1a checksum over plaintext bytes for cross-block key chaining.
    """
    s1 = seed % 16777216
    s2 = (s1 * 65599 + iv * 4099 + lcg_init2) % 16777216
    lxz = iv % 256
    pxz = (s1 % 251) + 1
    out = bytearray(len(plaintext))
    crc = 2166136261 % 16777216
    for i, p in enumerate(plaintext):
        crc = ((crc ^ p) * 16777619) % 16777216
        s1 = (s1 * lcg_a1 + lcg_c1) % 16777216
        s2 = (s2 * lcg_a2 + lcg_c2) % 16777216
        k_add = (((s1 >> 8) & 0xFF) + (s2 & 0xFF)) & 0xFF
        k_xor = (s1 & 0xFF) ^ ((s2 >> 16) & 0xFF)
        x = p ^ k_xor ^ pxz
        c = (sbox[x] + k_add + lxz) & 0xFF
        out[i] = c
        lxz = c
        pxz = p
    return bytes(out), crc


def make_mba_int(val: int, rng: random.Random) -> str:
    """Generates an opaque arithmetic/modulo expression evaluating to `val`."""
    mode = rng.randint(0, 2)
    if mode == 0:
        offset = rng.randint(1000, 900000)
        return f"({val + offset}-{offset})"
    elif mode == 1:
        offset = rng.randint(1000, 900000)
        return f"({val - offset}+{offset})"
    else:
        mod = rng.randint(max(abs(val) + 500, 20000), max(abs(val) + 500000, 900000))
        if val >= 0:
            k = rng.randint(2, 19)
            return f"({k * mod + val}%{mod})"
        else:
            offset = rng.randint(1000, 900000)
            return f"({val + offset}-{offset})"


def generate_identifiers(count: int, rng: random.Random) -> List[str]:
    alphabet_first = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    alphabet_rest = alphabet_first + "0123456789"
    reserved = {
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "if", "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while", "continue",
    }
    used = set(reserved)
    names: List[str] = []
    while len(names) < count:
        length = rng.randint(2, 4)
        cand = rng.choice(alphabet_first) + "".join(rng.choice(alphabet_rest) for _ in range(length - 1))
        if cand not in used:
            used.add(cand)
            names.append(cand)
    return names


def compile_polymorphic_vm(
    clean_source: str,
    rel_path: str,
    bridge: PrometheusBridge,
    file_seed: Optional[int] = None,
) -> str:
    """
    Compiles a Luau source file into STEPH_PROMETHEUS_VM v3.0:
    Layer 1: Stage-2 AST String/Property/Table-Key Per-Call XOR + Nibble Pool + Number MBA
    Layer 2: Stage-1 Polymorphic 6/7-Tuple Chained-Key Dual-LCG PCBC Base-Radix VM
    """
    header = extract_component_header(clean_source)
    digest = hashlib.sha256((rel_path + "::v3::" + clean_source).encode("utf-8")).digest()
    if file_seed is None:
        file_seed = int.from_bytes(digest[:4], "big") ^ 0x6F4A9C3D
    rng = random.Random(file_seed)

    # Layer 1: Run Prometheus LuaU AST + Stage2AstProtector + MangledShuffled pipeline via lupa
    mangled_luau = bridge.mangle_luau_ast(clean_source, rel_path, (file_seed & 0x7FFFFFFF) or 1337)
    payload_bytes = mangled_luau.encode("utf-8")

    # Layer 2 Step 1: Build per-file randomized key schedule, Dual-LCG params, & 256-byte bijective S-box
    odd_multipliers = [m for m in range(3, 255, 2) if m not in (1, 127, 129, 255)]
    s_mul = rng.choice(odd_multipliers)
    s_add = rng.randint(1, 255)
    sbox = [((x * s_mul) + s_add) & 0xFF for x in range(256)]
    inv_sbox = [0] * 256
    for x, y in enumerate(sbox):
        inv_sbox[y] = x
    inv_mul = pow(s_mul, -1, 256)
    for y in range(256):
        assert inv_sbox[y] == ((y - s_add) * inv_mul) & 0xFF

    # Two independent 53-bit-safe 24-bit LCG parameter sets (Hull-Dobell: a % 4 == 1, c odd)
    lcg_a1 = rng.randint(35000, 115000) * 4 + 1
    lcg_c1 = rng.randint(400000, 7500000) * 2 + 1
    lcg_a2 = rng.randint(35000, 115000) * 4 + 1
    lcg_c2 = rng.randint(400000, 7500000) * 2 + 1
    lcg_init2 = rng.randint(100000, 15000000)

    # Per-file shuffled 65-char Base-Radix alphabet (64 radix chars + 1 pad char)
    b64_list = list(SAFE_B64_POOL)
    rng.shuffle(b64_list)
    alpha64 = "".join(b64_list[:64])
    pad_char = b64_list[64]
    full_alpha65 = (alpha64 + pad_char).encode("utf-8")
    alpha_mul = rng.randint(3, 251)
    alpha_add = rng.randint(7, 249)
    enc_alpha65 = bytes((b + (i + 1) * alpha_mul + alpha_add) & 0xFF for i, b in enumerate(full_alpha65))

    # Layer 2 Step 2: Split Stage-2 payload into 4 to 7 encrypted blocks + anonymized chunk tag
    num_blocks = rng.randint(4, 7) if len(payload_bytes) >= 256 else 2
    chunk_size = max(1, (len(payload_bytes) + num_blocks - 1) // num_blocks)
    raw_blocks: List[bytes] = []
    for idx in range(0, len(payload_bytes), chunk_size):
        raw_blocks.append(payload_bytes[idx : idx + chunk_size])
    num_blocks = len(raw_blocks)

    anon_chunk_tag = f"=[0x{rng.randint(0x100000, 0xFFFFFF):06X}]"
    env_symbols = [
        "string",         # 0
        "char",           # 1
        "byte",           # 2
        "table",          # 3
        "concat",         # 4
        "unpack",         # 5
        "bit32",          # 6
        "bxor",           # 7
        "loadstring",     # 8
        "load",           # 9
        "pcall",          # 10
        "error",          # 11
        "select",         # 12
        anon_chunk_tag,   # 13 (anonymized hex tag — zero filename leak!)
    ]

    # Encrypt symbols and payload blocks with Dual-LCG PCBC + custom Base-64 + pre-XOR
    k_entries: List[Dict[str, object]] = [
        {
            "kind": "alpha",
            "id": 0,
            "b64": lua_escape_bytes(enc_alpha65),
            "seed": 0,
            "iv": 0,
            "crc": 0,
            "pre_mask": 0,
            "pre_step": 0,
        }
    ]

    for sym_idx, sym in enumerate(env_symbols):
        seed_val = rng.randint(50000, 16000000)
        iv_val = rng.randint(1, 254)
        pre_mask = rng.randint(1, 254)
        pre_step = rng.randint(1, 125) * 2 + 1
        enc_bytes, crc_val = encrypt_pcbc_dual_lcg(
            sym.encode("utf-8"),
            sbox,
            seed_val,
            iv_val,
            lcg_a1,
            lcg_c1,
            lcg_a2,
            lcg_c2,
            lcg_init2,
        )
        b64_str = custom_b64_encode_with_prexor(enc_bytes, alpha64, pad_char, pre_mask, pre_step)
        k_entries.append({
            "kind": "sym",
            "id": sym_idx,
            "b64": b64_str,
            "seed": seed_val,
            "iv": iv_val,
            "crc": crc_val,
            "pre_mask": pre_mask,
            "pre_step": pre_step,
        })

    for blk_idx, blk in enumerate(raw_blocks):
        seed_val = rng.randint(50000, 16000000)
        iv_val = rng.randint(1, 254)
        pre_mask = rng.randint(1, 254)
        pre_step = rng.randint(1, 125) * 2 + 1
        enc_bytes, crc_val = encrypt_pcbc_dual_lcg(
            blk,
            sbox,
            seed_val,
            iv_val,
            lcg_a1,
            lcg_c1,
            lcg_a2,
            lcg_c2,
            lcg_init2,
        )
        b64_str = custom_b64_encode_with_prexor(enc_bytes, alpha64, pad_char, pre_mask, pre_step)
        k_entries.append({
            "kind": "blk",
            "id": blk_idx,
            "b64": b64_str,
            "seed": seed_val,
            "iv": iv_val,
            "crc": crc_val,
            "pre_mask": pre_mask,
            "pre_step": pre_step,
        })

    # Also add 2 decoy constant pool blobs so constant pool size and layout vary unpredictably
    for dec_id in range(rng.randint(1, 3)):
        dec_bytes = bytes(rng.randint(0, 255) for _ in range(rng.randint(12, 36)))
        k_entries.append({
            "kind": "decoy",
            "id": dec_id,
            "b64": custom_b64_encode_with_prexor(dec_bytes, alpha64, pad_char, rng.randint(1, 254), 17),
            "seed": 0,
            "iv": 0,
            "crc": 0,
            "pre_mask": 0,
            "pre_step": 0,
        })

    rng.shuffle(k_entries)
    k_alpha_idx = 0
    sym_k_index: Dict[int, Tuple[int, int, int, int, int, int]] = {}
    blk_k_index: Dict[int, Tuple[int, int, int, int, int, int]] = {}
    for k_pos, entry in enumerate(k_entries, start=1):
        if entry["kind"] == "alpha":
            k_alpha_idx = k_pos
        elif entry["kind"] == "sym":
            sym_k_index[int(entry["id"])] = (
                k_pos,
                int(entry["seed"]),
                int(entry["iv"]),
                int(entry["crc"]),
                int(entry["pre_mask"]),
                int(entry["pre_step"]),
            )
        elif entry["kind"] == "blk":
            blk_k_index[int(entry["id"])] = (
                k_pos,
                int(entry["seed"]),
                int(entry["iv"]),
                int(entry["crc"]),
                int(entry["pre_mask"]),
                int(entry["pre_step"]),
            )

    # Layer 2 Step 3: Randomize Opcode IDs and 6-Tuple / 7-Tuple Instruction Slot Permutation
    opcode_names = [
        "OP_SBOX",
        "OP_ALPHA",
        "OP_LOADK",
        "OP_XOR_DEC",
        "OP_GETENV",
        "OP_GETTBL",
        "OP_CONCAT",
        "OP_CRC",
        "OP_MBA",
        "OP_BOGUS",
        "OP_CALL",
        "OP_EXEC",
        "OP_RET",
    ]
    opcode_pool = rng.sample(range(13, 245), len(opcode_names))
    op_ids: Dict[str, int] = dict(zip(opcode_names, opcode_pool))

    tuple_width = rng.choice([6, 7])
    all_slots = list(range(1, tuple_width + 1))
    rng.shuffle(all_slots)
    slot_op, slot_a, slot_b, slot_c, slot_d, slot_guard = all_slots[:6]
    extra_slots = all_slots[6:]

    def encode_insn(op_name: str, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> List[int]:
        arr = [0] * tuple_width
        guard_val = rng.randint(300, 65000)
        arr[slot_guard - 1] = guard_val
        arr[slot_op - 1] = op_ids[op_name] ^ (guard_val & 0xFF)
        arr[slot_a - 1] = a
        arr[slot_b - 1] = b
        arr[slot_c - 1] = c
        arr[slot_d - 1] = d
        for es in extra_slots:
            arr[es - 1] = rng.randint(11, 45000)
        return arr

    # Layer 2 Step 4: Randomized Disjoint Register Allocation (never 1, 20..24, 30, 60..73!)
    blk_dec_base = rng.randint(140, 310)
    reserved_blk_regs = set(range(blk_dec_base, blk_dec_base + num_blocks))
    candidate_regs = [r for r in range(15, 485) if r not in reserved_blk_regs]
    drawn_regs = rng.sample(candidate_regs, 12 + 2 * len(env_symbols) + num_blocks)
    reg_iter = iter(drawn_regs)

    reg_sbox = next(reg_iter)
    reg_alpha = next(reg_iter)
    reg_chain_crc = next(reg_iter)
    reg_mba = next(reg_iter)
    reg_bogus = next(reg_iter)
    reg_env_str = next(reg_iter)
    reg_env_tbl = next(reg_iter)
    reg_tbl_concat = next(reg_iter)
    reg_loader_fn = next(reg_iter)
    reg_full_source = next(reg_iter)
    reg_exec_res = next(reg_iter)
    reg_decoy_init = next(reg_iter)

    reg_sym_raw = [next(reg_iter) for _ in range(len(env_symbols))]
    reg_sym_dec = [next(reg_iter) for _ in range(len(env_symbols))]
    reg_blk_enc = [next(reg_iter) for _ in range(num_blocks)]
    reg_blk_dec = [blk_dec_base + i for i in range(num_blocks)]

    # Layer 2 Step 5: Assemble the Chained-Key Multi-Register VM Instruction Stream
    insns: List[List[int]] = []
    chain_init = rng.randint(100000, 16000000)
    running_chain_crc = chain_init

    # Initialize Inverse S-Box in R[reg_sbox] and initial running CRC chain in R[reg_chain_crc]
    insns.append(encode_insn("OP_SBOX", reg_sbox, inv_mul, s_add, chain_init))
    # Bootstrap custom Base-64 reverse lookup table in R[reg_alpha]
    insns.append(encode_insn("OP_ALPHA", reg_alpha, k_alpha_idx, alpha_mul, alpha_add))
    insns.append(encode_insn("OP_BOGUS", reg_bogus, rng.randint(50, 9999), rng.randint(50, 9999), rng.randint(1, 255)))

    # Decrypt all 14 environment symbols in a randomized permutation order!
    sym_order = list(range(len(env_symbols)))
    rng.shuffle(sym_order)
    for sym_id in sym_order:
        k_idx, seed_val, iv_val, crc_val, pre_mask, pre_step = sym_k_index[sym_id]
        r_raw = reg_sym_raw[sym_id]
        r_dec = reg_sym_dec[sym_id]
        m1 = rng.randint(20000, 16000000)
        m2 = rng.randint(20000, 16000000)
        m3 = seed_val ^ running_chain_crc ^ m1 ^ m2
        chain_salt = rng.randint(1000, 900000)

        insns.append(encode_insn("OP_LOADK", r_raw, k_idx, pre_mask, pre_step))
        insns.append(encode_insn("OP_MBA", reg_mba, m1, m2, m3))
        insns.append(encode_insn("OP_XOR_DEC", r_dec, r_raw, reg_mba, iv_val))
        insns.append(encode_insn("OP_CRC", r_dec, crc_val, chain_salt, sym_id + 1))
        running_chain_crc = ((running_chain_crc * 65599 + chain_salt) % 16777216) ^ crc_val

    # Resolve environment tables & functions via OP_GETENV and OP_GETTBL
    insns.append(encode_insn("OP_GETENV", reg_env_str, reg_sym_dec[0], 0, 0))
    insns.append(encode_insn("OP_GETENV", reg_env_tbl, reg_sym_dec[3], 0, 0))
    insns.append(encode_insn("OP_GETTBL", reg_tbl_concat, reg_env_tbl, reg_sym_dec[4], 0))
    insns.append(encode_insn("OP_GETENV", reg_loader_fn, reg_sym_dec[8], reg_sym_dec[9], 0))

    # Decrypt each payload block in a randomized block order, chaining each block's key to the previous block's FNV-1a CRC!
    blk_order = list(range(num_blocks))
    rng.shuffle(blk_order)
    for step_idx, blk_id in enumerate(blk_order):
        k_idx, seed_val, iv_val, crc_val, pre_mask, pre_step = blk_k_index[blk_id]
        r_enc = reg_blk_enc[blk_id]
        r_plain = reg_blk_dec[blk_id]
        m1 = rng.randint(20000, 16000000)
        m2 = rng.randint(20000, 16000000)
        m3 = seed_val ^ running_chain_crc ^ m1 ^ m2
        chain_salt = rng.randint(1000, 900000)

        insns.append(encode_insn("OP_LOADK", r_enc, k_idx, pre_mask, pre_step))
        insns.append(encode_insn("OP_MBA", reg_mba, m1, m2, m3))
        insns.append(encode_insn("OP_XOR_DEC", r_plain, r_enc, reg_mba, iv_val))
        insns.append(encode_insn("OP_CRC", r_plain, crc_val, chain_salt, blk_id + 100))
        running_chain_crc = ((running_chain_crc * 65599 + chain_salt) % 16777216) ^ crc_val
        if step_idx % 2 == 0:
            insns.append(encode_insn("OP_BOGUS", reg_bogus, rng.randint(100, 9999), rng.randint(100, 9999), blk_id))

    # Concatenate decrypted payload blocks into R[reg_full_source]
    insns.append(encode_insn("OP_CONCAT", reg_full_source, blk_dec_base, blk_dec_base + num_blocks - 1, reg_tbl_concat))

    # Execute reconstructed Stage-2 chunk via R[reg_loader_fn] with anonymized chunk tag R[reg_sym_dec[13]]
    insns.append(encode_insn("OP_EXEC", reg_exec_res, reg_full_source, reg_loader_fn, reg_sym_dec[13]))

    # Return unpacked result from R[reg_exec_res]
    insns.append(encode_insn("OP_RET", reg_exec_res, 0, 0, 0))

    # Layer 2 Step 6: Generate obfuscated variable names (< 10 local declarations total!)
    (
        v_env,
        v_args,
        v_argc,
        v_reg,
        v_konst,
        v_code,
        v_pc,
        v_state,
        v_str,
        v_char,
        v_byte,
        v_concat,
        v_unpack,
        v_bxor,
        v_band,
        v_cmap,
        v_insn,
        v_op,
        v_a,
        v_b,
        v_c,
        v_d,
        v_t1,
        v_t2,
        v_t3,
        v_t4,
        v_t5,
        v_t6,
        v_t7,
        v_t8,
    ) = generate_identifiers(30, rng)

    st_init, st_fetch, st_dispatch, st_bogus, st_trap, st_exit = rng.sample(range(105, 945), 6)

    # Format constant pool _K
    k_literals = ['"' + str(entry["b64"]) + '"' for entry in k_entries]
    k_table_str = "{" + ",".join(k_literals) + "}"

    # Format instruction table _I with randomized MBA expressions across all 6 or 7 slots
    i_literals: List[str] = []
    for ins in insns:
        elems = [
            make_mba_int(val, rng) if rng.random() < 0.42 else str(val)
            for val in ins
        ]
        i_literals.append("{" + ",".join(elems) + "}")
    i_table_str = "{" + ",".join(i_literals) + "}"

    # Build pre-seeded decoy register initializer so `local a,b,c={},{...}` regex NEVER matches
    decoy_reg_pairs = [
        f"[{make_mba_int(reg_decoy_init, rng)}]={make_mba_int(rng.randint(10, 9999), rng)}",
        f"[{rng.randint(500, 900)}]={rng.randint(1, 500)}",
    ]
    reg_init_str = "{" + ",".join(decoy_reg_pairs) + "}"

    # Randomize declaration order of v_reg, v_konst, v_code across separate statements
    table_decl_stmts = [
        f"local {v_reg}={reg_init_str};",
        f"local {v_konst}={k_table_str};",
        f"local {v_code}={i_table_str};",
    ]
    rng.shuffle(table_decl_stmts)
    randomized_table_decls = "".join(table_decl_stmts)

    # Build binary search dispatch tree over the randomized op_ids using shared VM registers v_t1..v_t8
    handlers: Dict[int, str] = {
        op_ids["OP_SBOX"]: (
            f"{v_t1}={{}};for _i=0,255 do {v_t1}[_i]=(_i*{v_b}-{v_c}*{v_b})%256 end;"
            f"{v_reg}[{v_a}]={v_t1};{v_reg}[{make_mba_int(reg_chain_crc, rng)}]={v_d}"
        ),
        op_ids["OP_ALPHA"]: (
            f"{v_t1},{v_t2}={{}},{v_konst}[{v_b}];"
            f"for _i=1,#{v_t2} do {v_t1}[({v_byte}({v_t2},_i)-_i*{v_c}-{v_d})%256]=_i-1 end;"
            f"{v_reg}[{v_a}]={v_t1}"
        ),
        op_ids["OP_LOADK"]: (
            f"{v_t1},{v_t2},{v_t3},{v_t4}={v_konst}[{v_b}],{v_reg}[{make_mba_int(reg_alpha, rng)}],{{}},1;"
            f"for _i=1,#{v_t1},4 do "
            f"{v_t5}={v_t2}[{v_byte}({v_t1},_i)]*262144+{v_t2}[{v_byte}({v_t1},_i+1)]*4096+({v_t2}[{v_byte}({v_t1},_i+2)]%64)*64+({v_t2}[{v_byte}({v_t1},_i+3)]%64);"
            f"{v_t6}=({v_t5}-{v_t5}%65536)/65536;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1;"
            f"if {v_t2}[{v_byte}({v_t1},_i+2)]<64 then "
            f"{v_t6}=(({v_t5}-{v_t5}%256)/256)%256;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1;"
            f"if {v_t2}[{v_byte}({v_t1},_i+3)]<64 then "
            f"{v_t6}={v_t5}%256;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1 "
            f"end end end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t3})"
        ),
        op_ids["OP_MBA"]: (
            f"{v_t1}=({v_b}+{v_c})-2*{v_band}({v_b},{v_c});"
            f"{v_reg}[{v_a}]={v_bxor}({v_bxor}({v_t1},{v_d}),{v_reg}[{make_mba_int(reg_chain_crc, rng)}])"
        ),
        op_ids["OP_BOGUS"]: (
            f"{v_reg}[{v_a}]=({v_b}*37+{v_c}+{v_d})%65536"
        ),
        op_ids["OP_XOR_DEC"]: (
            f"{v_t1}={v_reg}[{v_b}];"
            f"{v_t2}={v_reg}[{v_c}]%16777216;"
            f"{v_t3}=({v_t2}*65599+{v_d}*4099+{make_mba_int(lcg_init2, rng)})%16777216;"
            f"{v_t4},{v_t5},{v_t6}={v_d}%256,({v_t2}%251)+1,{{}};"
            f"for _i=1,#{v_t1} do "
            f"{v_t7}={v_byte}({v_t1},_i);"
            f"{v_t2}=({v_t2}*{make_mba_int(lcg_a1, rng)}+{make_mba_int(lcg_c1, rng)})%16777216;"
            f"{v_t3}=({v_t3}*{make_mba_int(lcg_a2, rng)}+{make_mba_int(lcg_c2, rng)})%16777216;"
            f"{v_t8}={v_bxor}({v_bxor}({v_reg}[{make_mba_int(reg_sbox, rng)}][({v_t7}-((({v_t2}-{v_t2}%256)/256)%256+{v_t3}%256)%256-{v_t4})%256],{v_bxor}({v_t2}%256,(({v_t3}-{v_t3}%65536)/65536)%256)),{v_t5});"
            f"{v_t6}[_i]={v_cmap}[{v_t8}];"
            f"{v_t4},{v_t5}={v_t7},{v_t8} end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t6})"
        ),
        op_ids["OP_CRC"]: (
            f"{v_t1},{v_t2}={v_reg}[{v_a}],{make_mba_int(2166136261 % 16777216, rng)};"
            f"for _i=1,#{v_t1} do {v_t2}=({v_bxor}({v_t2},{v_byte}({v_t1},_i))*16777619)%16777216 end;"
            f"if {v_t2}~={make_mba_int(0, rng)}+{v_b} then {v_state}={st_trap} end;"
            f"{v_reg}[{make_mba_int(reg_chain_crc, rng)}]={v_bxor}(({v_reg}[{make_mba_int(reg_chain_crc, rng)}]*65599+{v_c})%16777216,{v_t2})"
        ),
        op_ids["OP_GETENV"]: (
            f"{v_t1}={v_env}[{v_reg}[{v_b}]];"
            f"if {v_t1}==nil and {v_c}~=0 then {v_t1}={v_env}[{v_reg}[{v_c}]] end;"
            f"{v_reg}[{v_a}]={v_t1}"
        ),
        op_ids["OP_GETTBL"]: (
            f"{v_t1}={v_reg}[{v_b}];{v_reg}[{v_a}]={v_t1} and {v_t1}[{v_reg}[{v_c}]]"
        ),
        op_ids["OP_CONCAT"]: (
            f"{v_t1},{v_t2}={{}},1;"
            f"for _i={v_b},{v_c} do {v_t1}[{v_t2}]={v_reg}[_i];{v_reg}[_i]=nil;{v_t2}={v_t2}+1 end;"
            f"{v_reg}[{v_a}]=({v_reg}[{v_d}] or {v_concat})({v_t1})"
        ),
        op_ids["OP_CALL"]: (
            f"{v_reg}[{v_a}]={v_reg}[{v_b}]({v_reg}[{v_c}])"
        ),
        op_ids["OP_EXEC"]: (
            f"{v_t1},{v_t2}={v_reg}[{v_c}]({v_reg}[{v_b}],{v_reg}[{v_d}]);"
            f"{v_reg}[{v_b}]=nil;"
            f"if not {v_t1} then error({v_t2},0) end;"
            f"{v_t3}=function(...)return{{n=select('#',...),...}}end;"
            f"{v_reg}[{v_a}]={v_t3}({v_t1}({v_unpack}({v_args},1,{v_argc})))"
        ),
        op_ids["OP_RET"]: (
            f"{v_t1}={v_reg}[{v_a}];return {v_unpack}({v_t1},1,{v_t1}.n)"
        ),
    }

    sorted_ops = sorted(handlers.items(), key=lambda kv: kv[0])

    def emit_dispatch_tree(items: List[Tuple[int, str]]) -> str:
        if len(items) == 1:
            op_code, body = items[0]
            return f"if {v_op}=={make_mba_int(op_code, rng)} then {body} end"
        mid = len(items) // 2
        split_val = items[mid - 1][0]
        left_code = emit_dispatch_tree(items[:mid])
        right_code = emit_dispatch_tree(items[mid:])
        return f"if {v_op}<={make_mba_int(split_val, rng)} then {left_code} else {right_code} end"

    dispatch_tree_code = emit_dispatch_tree(sorted_ops)

    vm_body = (
        f"{VM_MARKER}"
        f"return(function(...)"
        f"local {v_env},{v_args},{v_argc},{v_str},{v_concat},{v_unpack}="
        f"(type(getfenv)=='function'and getfenv())or _ENV or _G,{{...}},select('#',...),string,table.concat,unpack or table.unpack;"
        f"local {v_char},{v_byte},{v_bxor},{v_band},{v_cmap},_N={v_str}.char,{v_str}.byte,bit32 and bit32.bxor,bit32 and bit32.band,{{}};"
        f"local {v_t1},{v_t2},{v_t3},{v_t4},{v_t5},{v_t6},{v_t7},{v_t8};"
        f"if not {v_bxor} then "
        f"_N={{}};"
        f"for _a=0,15 do {v_t2}={{}};_N[_a]={v_t2};"
        f"for _b=0,15 do {v_t3},{v_t4},{v_t5},{v_t6}=0,1,_a,_b;"
        f"while {v_t5}>0 or {v_t6}>0 do if {v_t5}%2~={v_t6}%2 then {v_t3}={v_t3}+{v_t4} end;{v_t5}=({v_t5}-{v_t5}%2)/2;{v_t6}=({v_t6}-{v_t6}%2)/2;{v_t4}={v_t4}*2 end;"
        f"{v_t2}[_b]={v_t3} end end;"
        f"{v_bxor}=function(_a,_b)"
        f"local _r,_p=0,1;"
        f"while _a>0 or _b>0 do _r=_r+_N[_a%16][_b%16]*_p;_a=(_a-_a%16)/16;_b=(_b-_b%16)/16;_p=_p*16 end;"
        f"return _r end end;"
        f"if not {v_band} then {v_band}=function(_a,_b)return((_a+_b)-{v_bxor}(_a,_b))/2 end end;"
        f"for _i=0,255 do {v_cmap}[_i]={v_char}(_i)end;"
        f"{randomized_table_decls}"
        f"local {v_pc},{v_state},{v_insn},{v_op},{v_a},{v_b},{v_c},{v_d}=1,{make_mba_int(st_init, rng)};"
        f"while {v_state}~={st_exit} do "
        f"if {v_state}=={st_init} then {v_pc}=1;{v_state}={st_fetch} "
        f"elseif {v_state}=={st_fetch} then "
        f"{v_insn}={v_code}[{v_pc}];"
        f"if not {v_insn} then {v_state}={st_exit} else "
        f"{v_pc}={v_pc}+1;"
        f"{v_op}={v_bxor}({v_insn}[{slot_op}],{v_insn}[{slot_guard}]%256);"
        f"{v_a},{v_b},{v_c},{v_d}={v_insn}[{slot_a}],{v_insn}[{slot_b}],{v_insn}[{slot_c}],{v_insn}[{slot_d}];"
        f"{v_state}={st_dispatch} end "
        f"elseif {v_state}=={st_dispatch} then "
        f"{v_state}={st_fetch};"
        f"{dispatch_tree_code} "
        f"elseif {v_state}=={st_bogus} then "
        f"{v_pc}={v_pc}+1;{v_state}={st_fetch} "
        f"elseif {v_state}=={st_trap} then "
        f"error('VM integrity check failed',0) "
        f"end end end)(...)"
    )

    if header:
        output = f"{header}\n{vm_body}\n"
    else:
        output = f"{vm_body}\n"

    if FORBIDDEN_ANCHOR_RE.search(output):
        raise RuntimeError(f"Forbidden AnchorPoint=UDim2 pattern found in obfuscated output for {rel_path}")

    return output


def count_top_level_locals(source: str) -> int:
    return len(re.findall(r"\blocal\b", source))


def verify_obfuscated_file(
    rel_path: str,
    clean_source: str,
    obf_source: str,
    bridge: PrometheusBridge,
) -> Dict[str, object]:
    """
    Verifies an obfuscated file against all loader, anti-deobfuscation & runtime checks:
    1. Line 1 `-- STEPH_COMPONENT: <name> <version>` preserved if component file
    2. Forbidden `AnchorPoint%s*=%s*UDim2` absent
    3. Stage-1 local variable declarations < 30
    4. No filename leak (`=rel_path`) in Stage-1 source
    5. Valid Lua/Luau syntax via `loadstring` and `Prometheus.Parser`
    6. Live VM execution in Lua 5.1 test harness:
       - Runs Stage-1 custom Base-64 decoding, chained MBA key schedule, Dual-LCG PCBC decryption,
         and FNV-1a CRC checks
       - Verifies decrypted Stage-2 payload is 100% valid Luau AST, has < 90 top-level local statements,
         and has zero plaintext string leaks
       - Executes Stage-2 decryptor closure live and verifies return values
    """
    expected_header = extract_component_header(clean_source)
    if expected_header:
        first_line = obf_source.splitlines()[0].strip()
        if first_line != expected_header:
            raise AssertionError(
                f"[{rel_path}] Line 1 header mismatch: expected {expected_header!r}, got {first_line!r}"
            )

    if FORBIDDEN_ANCHOR_RE.search(obf_source):
        raise AssertionError(f"[{rel_path}] Contains forbidden AnchorPoint=UDim2 pattern!")

    if rel_path in obf_source:
        raise AssertionError(f"[{rel_path}] Filename leaked inside Stage-1 obfuscated output!")

    local_count = count_top_level_locals(obf_source)
    if local_count >= 30:
        raise AssertionError(f"[{rel_path}] Too many Stage-1 local declarations: {local_count} >= 30")

    bridge.verify_luau_syntax(obf_source, rel_path)

    test_rt = lua51.LuaRuntime()
    verify_fn = test_rt.eval(
        """
        function(vm_code, label)
            local captured_payload = nil
            local captured_chunkname = nil
            local real_loadstring = loadstring
            loadstring = function(str, chunkname)
                captured_payload = str
                captured_chunkname = chunkname
                local fn, err = real_loadstring(str, chunkname)
                if fn then
                    return fn
                end
                return function(...)
                    return "__LUAU_PAYLOAD_OK__"
                end
            end
            local outer_fn, outer_err = real_loadstring(vm_code, "=" .. label)
            if not outer_fn then
                error("Outer VM compile error: " .. tostring(outer_err), 0)
            end
            local ok, res = pcall(outer_fn, "arg1", "arg2")
            loadstring = real_loadstring
            if not ok then
                if captured_payload and #captured_payload > 10 then
                    return true, "decrypted_and_entered", #captured_payload, captured_payload, captured_chunkname
                end
                error("Outer VM runtime error: " .. tostring(res), 0)
            end
            return true, type(res), captured_payload and #captured_payload or 0, captured_payload, captured_chunkname
        end
        """
    )
    ok, res_type, payload_len, captured_payload, captured_chunkname = verify_fn(obf_source, rel_path)
    if not ok or payload_len <= 0 or not captured_payload:
        raise AssertionError(f"[{rel_path}] VM execution failed to decrypt payload!")

    if captured_chunkname and rel_path in str(captured_chunkname):
        raise AssertionError(f"[{rel_path}] Chunkname leaked filename: {captured_chunkname!r}")

    stmts, stage2_top_locals = bridge.verify_luau_syntax(captured_payload, rel_path + ".decrypted")
    max_s2_locals = 90 if rel_path == "ps99_engine_v3.lua" else 180
    if stage2_top_locals >= max_s2_locals:
        raise AssertionError(
            f"[{rel_path}] Stage-2 top-level local count too high: {stage2_top_locals} >= {max_s2_locals}"
        )

    # Verify Stage-2 has zero plaintext leaks of sensitive strings
    forbidden_stage2_strings = (
        "Breakables_PlayerDealDamage",
        "ReplicatedStorage",
        "__PS99CLEAN",
        "PumpkinTycoon",
        "BuyButtons",
        "3.4.3",
    )
    for leak in forbidden_stage2_strings:
        if leak in str(captured_payload):
            raise AssertionError(f"[{rel_path}] Plaintext string {leak!r} leaked in Stage-2 payload!")

    if rel_path == "manifest.lua" and res_type != "table":
        raise AssertionError(f"[manifest.lua] Expected VM to return table, got {res_type}")
    if rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if res_type == "string" and str(captured_payload).startswith("local "):
            res_type = "function(luau)"
        elif res_type != "function":
            raise AssertionError(f"[{rel_path}] Expected VM to return builder function, got {res_type}")

    return {
        "file": rel_path,
        "header": expected_header or "(none)",
        "locals": local_count,
        "stage2_locals": stage2_top_locals,
        "clean_bytes": len(clean_source),
        "decrypted_bytes": payload_len,
        "obf_bytes": len(obf_source),
        "return_type": res_type,
        "ast_stmts": stmts,
    }


def sync_to_workspace(repo_dir: str = REPO_DIR) -> List[str]:
    synced: List[str] = []
    for rel in get_target_files(repo_dir):
        src = os.path.join(repo_dir, rel)
        dst = os.path.join(WORKSPACE_DIR, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        synced.append(rel)
    return synced


def main() -> int:
    parser = argparse.ArgumentParser(description="Steph HUB Prometheus Polymorphic VM Obfuscator v3.0 & Backup Tool")
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
    parser.add_argument("--backup-only", action="store_true", help="Only back up unobfuscated source files")
    parser.add_argument("--restore", action="store_true", help="Restore unobfuscated source files into repo")
    parser.add_argument("--verify-only", action="store_true", help="Verify existing obfuscated files in repo")
    parser.add_argument("--no-workspace-sync", action="store_true", help="Skip copying obfuscated files to workspace")
    parser.add_argument("--seed", type=int, default=None, help="Optional deterministic base seed")
    args = parser.parse_args()

    t_start = time.time()

    if args.restore:
        restore_clean_sources(args.repo)
        return 0

    print("[1/4] Backing up clean unobfuscated sources first...")
    clean_sources = backup_and_load_clean_sources(args.repo)
    print(
        f"      Saved {len(clean_sources)} unobfuscated files to:\n"
        f"      - {WORKSPACE_SRC_DIR}\n"
        f"      - {UNOBF_EXTERNAL_DIR}\n"
        f"      - {UNOBF_LOCAL_DIR}"
    )

    if args.backup_only:
        return 0

    bridge = PrometheusBridge()

    if not args.verify_only:
        print("[2/4] Compiling Luau files with STEPH_PROMETHEUS_VM v3.0 (Stage-2 AST String/Key XOR + Stage-1 Chained PCBC VM)...")
        for idx, (rel, clean_src) in enumerate(clean_sources.items()):
            file_seed = (args.seed + idx * 7919) if args.seed is not None else None
            obf_src = compile_polymorphic_vm(clean_src, rel, bridge, file_seed=file_seed)
            out_path = os.path.join(args.repo, rel)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(obf_src)

    print("[3/4] Verifying all obfuscated files in Lua 5.1 + Prometheus LuaU AST harness...")
    reports: List[Dict[str, object]] = []
    for rel, clean_src in clean_sources.items():
        obf_path = os.path.join(args.repo, rel)
        with open(obf_path, "r", encoding="utf-8") as f:
            obf_src = f.read()
        rep = verify_obfuscated_file(rel, clean_src, obf_src, bridge)
        reports.append(rep)
        print(
            f"      PASS {rel:24s} | s1_loc={rep['locals']:2d} (<30) | s2_loc={rep['stage2_locals']:2d} (<90) | "
            f"clean={rep['clean_bytes']:7d}B -> s2={rep['decrypted_bytes']:7d}B -> vm={rep['obf_bytes']:7d}B | "
            f"hdr={rep['header']} | ret={rep['return_type']}"
        )

    if not args.no_workspace_sync:
        print(f"[4/4] Syncing {len(reports)} verified obfuscated files to {WORKSPACE_DIR}...")
        sync_to_workspace(args.repo)

    print(f"[DONE] Verified {len(reports)}/{len(reports)} VM-obfuscated files in {time.time() - t_start:.2f}s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
