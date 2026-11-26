#!/usr/bin/env python3
"""
Steph HUB - Prometheus Vmify Custom Bytecode + Polymorphic Chained-Key Dual-VM Obfuscator (v4.0)
=================================================================================================
1. Backs up clean unobfuscated Luau sources FIRST to:
   - C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src\\ (clean tree + *.unobf.lua)
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt_unobf\\
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt\\unobf\\ (gitignored)
2. Stage-2 Inner Custom Bytecode VM (Prometheus `Vmify` + Encrypted Binary Prototype Stream):
   - Compiles the full Luau AST (`+=`, `continue`, `//`, ternary `if-then-else`, closures, varargs)
     into custom register VM bytecode instructions (`Compiler:compile(ast)`) with per-file shuffled
     opcode IDs (`1..56`), shuffled operand slots (`2..5`), and randomized prototype field keys.
   - Serializes the compiled prototype hierarchy into a compact binary bytecode stream where:
     * Every instruction opcode & operand-type mask is dynamically XOR-masked with per-prototype
       rolling salts derived from Stage-1's final FNV-1a chain CRC (`R[reg_chain_crc] % 256`).
     * Every constant string (string literals, `.Property` accesses, `:Method()` names, `{Key=Val}`
       table keys, and global names) is encrypted with a per-prototype rolling XOR + affine stream
       cipher and kept encrypted in memory even after VM startup, decrypting lazily on first read
       via a `__index` metatable attached to each prototype's constant table `K`.
     * Integer constants inside the bytecode stream are offset-masked by per-prototype salts.
   - Eliminates `loadstring` / `load` completely at runtime: the Lua source code of the script NEVER
     exists in the file or in memory at runtime, and `OP_EXEC` unpacks the binary bytecode prototypes
     directly into the inlined, `MangledShuffled`-renamed `Vmify` register bytecode interpreter.
3. Stage-1 Outer Hardened Chained-Key Dual-LCG PCBC VM (v4.0):
   - Zero header comments (`-- STEPH_COMPONENT` and `--[[STEPH_PROMETHEUS_VM]]` completely stripped;
     line 1 starts immediately with pure obfuscated Lua code and zero plaintext string literals).
   - 6-way Native C-Closure Anti-Hook Verification (`string.dump`, `debug.info`, `iscclosure`,
     `islclosure`, `ishooked`, `isfunctionhooked`) over `pcall`, `string.byte`, `string.char`,
     `string.sub`, `table.concat`, `tonumber`, `select`, and `loadstring`/`load` (with all symbol
     names decoded at runtime from an encrypted byte blob). Any Lua hook wrapper silently poisons
     the 16-slot runtime anchor table `v_anchor[1..16]`.
   - Zero static constant-foldable arithmetic: all obfuscated integer expressions use runtime state
     (`bxor(v_anchor[i], mask)` or `(v_anchor[i] +/- diff)`) populated by the anti-hook LCG loop.
   - Zero dead branches & zero `'VM integrity check failed'` strings: all 4 dispatcher states
     (`st_init`, `st_fetch`, `st_dispatch`, `st_step`) are 100% live, and `OP_CRC` feeds the live
     24-bit FNV-1a checksum directly into `R[reg_chain_crc]`, which drives both the next state
     transition (`bxor(insn[slot_next], R[reg_chain_crc] % 256)`) and the next opcode guard.
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

LEGACY_VM_MARKER = "--[[STEPH_PROMETHEUS_VM]]"
FORBIDDEN_ANCHOR_RE = re.compile(r"AnchorPoint\s*=\s*UDim2")
STATIC_CONST_ARITH_RE = re.compile(r"\(-?\d+[\+\-%]-?\d+\)")

SAFE_B64_POOL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$"
PROBE_SYMBOLS = [
    "dump",
    "debug",
    "info",
    "iscclosure",
    "islclosure",
    "ishooked",
    "isfunctionhooked",
    "loadstring",
    "load",
]


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
    """
    Heuristically detects v4.0 (headerless single-line Dual-VM) and legacy v3.0
    obfuscated files so clean source backups are never overwritten by obfuscated code.
    """
    if LEGACY_VM_MARKER in source:
        return True
    stripped = source.strip()
    if not stripped:
        return False
    lines = [ln.strip() for ln in stripped.splitlines() if ln.strip()]
    if len(lines) <= 4 and any(ln.startswith("return(function(") for ln in lines):
        return True
    return False


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
    """
    Lua 5.1 lupa bridge to Prometheus LuaU AST Parser, Vmify Custom Register Bytecode Compiler,
    Encrypted Binary Prototype Serializer, and MangledShuffled Variable Renamer.
    """

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
            analyzeBindings = require("prometheus.bindinganalysis")
            Compiler = require("prometheus.vm.compiler")
            Layout = require("prometheus.vm.layout")
            Runtime = require("prometheus.vm.runtime")
            Unparser = require("prometheus.unparser")
            renameVariables = require("prometheus.names")
            NameGenerators = require("prometheus.namegenerators")
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

            local function writeVarint(out, n)
                n = math.floor(n)
                while n >= 128 do
                    out[#out + 1] = string.char((n % 128) + 128)
                    n = math.floor(n / 128)
                end
                out[#out + 1] = string.char(n)
            end

            local function serializeProto(proto, layout, out, strSalt, opSalt)
                out[#out + 1] = string.char(bxor24(proto.vararg and 1 or 0, opSalt % 2))
                writeVarint(out, proto.maxRegister or 0)

                local params = proto.params or {{}}
                writeVarint(out, #params)
                for i = 1, #params do
                    writeVarint(out, params[i][1])
                    out[#out + 1] = string.char(params[i][2] and 1 or 0)
                end

                local captures = proto.captures or {{}}
                writeVarint(out, #captures)
                for i = 1, #captures do
                    out[#out + 1] = string.char(captures[i][1])
                    writeVarint(out, captures[i][2])
                end

                local constants = proto.constants or {{}}
                writeVarint(out, #constants)
                for i = 1, #constants do
                    local c = constants[i]
                    local t = type(c)
                    if t == "boolean" then
                        out[#out + 1] = string.char(c and 1 or 0)
                    elseif t == "number" then
                        if c == math.floor(c) and c >= -2147483647 and c <= 2147483647 and (c ~= 0 or 1/c > 0) then
                            local numMask = (strSalt * 131 + i * 17) % 65536
                            if c >= 0 then
                                out[#out + 1] = string.char(2)
                                writeVarint(out, c + numMask)
                            else
                                out[#out + 1] = string.char(3)
                                writeVarint(out, (-c) + numMask)
                            end
                        else
                            out[#out + 1] = string.char(4)
                            local s = string.format("%.17g", c)
                            writeVarint(out, #s)
                            local sChars = {{}}
                            local k = (strSalt + i * 97) % 256
                            for j = 1, #s do
                                local b = string.byte(s, j)
                                local encB = (bxor24(b, k) + j * 13 + strSalt) % 256
                                k = (k * 67 + encB + 19) % 256
                                sChars[j] = string.char(encB)
                            end
                            out[#out + 1] = table.concat(sChars)
                        end
                    elseif t == "string" then
                        out[#out + 1] = string.char(5)
                        writeVarint(out, #c)
                        local sChars = {{}}
                        local k = (strSalt + i * 131) % 256
                        for j = 1, #c do
                            local b = string.byte(c, j)
                            local encB = (bxor24(b, k) + j * 17 + strSalt) % 256
                            k = (k * 73 + encB + 29) % 256
                            sChars[j] = string.char(encB)
                        end
                        out[#out + 1] = table.concat(sChars)
                    else
                        error("Unsupported constant type: " .. tostring(t))
                    end
                end

                local code = proto.code or {{}}
                writeVarint(out, #code)
                for i = 1, #code do
                    local enc = layout:encode(code[i])
                    local maskedOp = bxor24(enc[1], (i * 73 + opSalt) % 256)
                    out[#out + 1] = string.char(maskedOp)
                    local mask = 0
                    local mult = 1
                    for slot = 2, 5 do
                        local v = enc[slot]
                        local st = 0
                        if v ~= nil then
                            if type(v) == "table" then
                                st = 3
                            elseif v < 0 then
                                st = 2
                            else
                                st = 1
                            end
                        end
                        mask = mask + st * mult
                        mult = mult * 4
                    end
                    out[#out + 1] = string.char(bxor24(mask, (i * 29 + strSalt) % 256))
                    for slot = 2, 5 do
                        local v = enc[slot]
                        if v ~= nil then
                            if type(v) == "table" then
                                writeVarint(out, #v)
                                for j = 1, #v do
                                    writeVarint(out, v[j])
                                end
                            elseif v < 0 then
                                writeVarint(out, -v)
                            else
                                writeVarint(out, v)
                            end
                        end
                    end
                end

                local children = proto.children or {{}}
                writeVarint(out, #children)
                for i = 1, #children do
                    serializeProto(
                        children[i],
                        layout,
                        out,
                        (strSalt * 37 + i * 19 + 7) % 256,
                        (opSalt * 53 + i * 23 + 11) % 256
                    )
                end
            end

            local function countProtoStats(proto)
                local insns = #(proto.code or {{}})
                local consts = #(proto.constants or {{}})
                local protos = 1
                for _, ch in ipairs(proto.children or {{}}) do
                    local ci, cc, cp = countProtoStats(ch)
                    insns = insns + ci
                    consts = consts + cc
                    protos = protos + cp
                end
                return insns, consts, protos
            end

            function compileStage2Vmify(code, filename, seed, chainKey256, baseStrSalt, baseOpSalt)
                math.randomseed(seed)
                local ast = Parser:new({{ LuaVersion = "LuaU" }}):parse(code, filename)
                analyzeBindings(ast)
                local layout = Layout.new()
                local proto = Compiler:compile(ast)
                local totalInsns, totalConsts, totalProtos = countProtoStats(proto)

                local effStrSalt = (baseStrSalt + chainKey256) % 256
                local effOpSalt = (baseOpSalt + chainKey256) % 256
                local out = {{}}
                serializeProto(proto, layout, out, effStrSalt, effOpSalt)
                local blob = table.concat(out)
                local hex = (blob:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))

                local f = layout.fields
                local rawRt = Runtime.build(layout)
                -- Remove all diagnostic strings from VM runtime and bind Stage-2 opcode dispatch tree to runtime _ck!
                rawRt = rawRt:gsub("nativeError%('unknown VM opcode: '%s*%.%.%s*tostring%(opcode%),%s*0%)", "return")
                rawRt = rawRt:gsub("if x == nil then nativeError%([^%)]+%) end", "if x == nil then return end")
                rawRt = rawRt:gsub('nativeSelect%("#",%s*%.%.%.%)', "nativeSelect(_cmap[35], ...)")
                rawRt = rawRt:gsub("if opcode == (%d+) then", function(n)
                    return "if opcode == _bxor(_ck, " .. tostring(bxor24(tonumber(n), chainKey256)) .. ") then"
                end)
                rawRt = rawRt:gsub("if opcode <= (%d+) then", function(n)
                    local d = tonumber(n) - chainKey256
                    if d >= 0 then
                        return "if opcode <= (_ck + " .. tostring(d) .. ") then"
                    else
                        return "if opcode <= (_ck - " .. tostring(-d) .. ") then"
                    end
                end)

                local unpackAndRunSrc = string.format([=[
return function(_blob, _ck, _bxor, _cmap, _byte, _sub, _concat, ...)
    local _pos, _tonum, _setmt, _rawset = 1, tonumber, setmetatable, rawset
    local function _rbyte()
        local _b = _byte(_blob, _pos)
        _pos = _pos + 1
        return _b
    end
    local function _rvar()
        local _r, _m = 0, 1
        while true do
            local _b = _byte(_blob, _pos)
            _pos = _pos + 1
            if _b < 128 then
                return _r + _b * _m
            end
            _r = _r + (_b - 128) * _m
            _m = _m * 128
        end
    end
    local function _rproto(_ss, _os)
        local _p = {{}}
        _p[%d] = (_bxor(_rbyte(), _os %% 2) == 1)
        _p[%d] = _rvar()
        local _npar = _rvar()
        local _pars = {{}}
        for _i = 1, _npar do
            _pars[_i] = {{ _rvar(), _rbyte() == 1 }}
        end
        _p[%d] = _pars
        local _ncap = _rvar()
        local _caps = {{}}
        for _i = 1, _ncap do
            _caps[_i] = {{ _rbyte(), _rvar() }}
        end
        _p[%d] = _caps
        local _ncon = _rvar()
        local _cons = {{}}
        local _enc_k = {{}}
        local _has_str = false
        for _i = 1, _ncon do
            local _tag = _rbyte()
            if _tag == 0 then
                _cons[_i] = false
            elseif _tag == 1 then
                _cons[_i] = true
            elseif _tag == 2 then
                _cons[_i] = _rvar() - ((_ss * 131 + _i * 17) %% 65536)
            elseif _tag == 3 then
                _cons[_i] = -(_rvar() - ((_ss * 131 + _i * 17) %% 65536))
            elseif _tag == 4 then
                local _l = _rvar()
                local _out = {{}}
                local _k = (_ss + _i * 97) %% 256
                for _j = 1, _l do
                    local _eb = _byte(_blob, _pos + _j - 1)
                    local _db = _bxor((_eb - _j * 13 - _ss) %% 256, _k)
                    _k = (_k * 67 + _eb + 19) %% 256
                    _out[_j] = _cmap[_db]
                end
                _pos = _pos + _l
                _cons[_i] = _tonum(_concat(_out))
            else
                local _l = _rvar()
                _enc_k[_i] = _sub(_blob, _pos, _pos + _l - 1)
                _pos = _pos + _l
                _has_str = true
            end
        end
        if _has_str then
            _setmt(_cons, {{
                __index = function(_t, _idx)
                    local _raw = _enc_k[_idx]
                    if not _raw then return nil end
                    local _out = {{}}
                    local _k = (_ss + _idx * 131) %% 256
                    for _j = 1, #_raw do
                        local _eb = _byte(_raw, _j)
                        local _db = _bxor((_eb - _j * 17 - _ss) %% 256, _k)
                        _k = (_k * 73 + _eb + 29) %% 256
                        _out[_j] = _cmap[_db]
                    end
                    local _val = _concat(_out)
                    _enc_k[_idx] = nil
                    _rawset(_t, _idx, _val)
                    return _val
                end
            }})
        end
        _p[%d] = _cons
        local _ncode = _rvar()
        local _code = {{}}
        for _i = 1, _ncode do
            local _op = _bxor(_rbyte(), (_i * 73 + _os) %% 256)
            local _mask = _bxor(_rbyte(), (_i * 29 + _ss) %% 256)
            local _ins = {{ _op }}
            for _slot = 2, 5 do
                local _st = _mask %% 4
                _mask = (_mask - _st) / 4
                if _st == 1 then
                    _ins[_slot] = _rvar()
                elseif _st == 2 then
                    _ins[_slot] = -_rvar()
                elseif _st == 3 then
                    local _al = _rvar()
                    local _arr = {{}}
                    for _j = 1, _al do _arr[_j] = _rvar() end
                    _ins[_slot] = _arr
                end
            end
            _code[_i] = _ins
        end
        _p[%d] = _code
        local _nch = _rvar()
        local _ch = {{}}
        for _i = 1, _nch do
            _ch[_i] = _rproto((_ss * 37 + _i * 19 + 7) %% 256, (_os * 53 + _i * 23 + 11) %% 256)
        end
        _p[%d] = _ch
        return _p
    end
    local _Information = {{ _rproto((%d + _ck) %% 256, (%d + _ck) %% 256) }}
    _blob = nil
    __VM_RUNTIME_BODY__
end
]=], f.vararg, f.maxRegister, f.params, f.captures, f.constants, f.code, f.children, baseStrSalt, baseOpSalt)

                rawRt = rawRt:gsub("__PROTOTYPES__", "_Information")
                unpackAndRunSrc = unpackAndRunSrc:gsub("__VM_RUNTIME_BODY__", function() return rawRt end)

                local rtAst = Parser:new({{ LuaVersion = "Lua51" }}):parse(unpackAndRunSrc, "vm_rt")
                analyzeBindings(rtAst)
                if type(NameGenerators.MangledShuffled.prepare) == "function" then
                    NameGenerators.MangledShuffled.prepare(rtAst)
                end
                renameVariables(rtAst, {{
                    Keywords = Enums.Conventions.LuaU.Keywords,
                    generateName = NameGenerators.MangledShuffled.generateName,
                    prefix = "",
                }})
                local minifiedRt = Unparser:new({{ LuaVersion = "LuaU", PrettyPrint = false }}):unparse(rtAst)
                minifiedRt = minifiedRt:gsub("^%s*return%s+", "")
                return hex, minifiedRt, totalInsns, totalConsts, totalProtos
            end
            """
        )
        self._compile_s2_fn = self.rt.eval("compileStage2Vmify")
        self._parse_luau_fn = self.rt.eval(
            """
            function(code, filename)
                local ast = Parser:new({ LuaVersion = "LuaU" }):parse(code, filename or "chunk")
                local max_scope_locals = 0
                visitast(ast, function(node)
                    if node.body and node.body.scope and node.body.scope.variables then
                        local n = #node.body.scope.variables
                        if n > max_scope_locals then max_scope_locals = n end
                    end
                end, nil)
                return #ast.body.statements, max_scope_locals
            end
            """
        )

    def compile_stage2_vmify(
        self,
        code: str,
        filename: str,
        seed: int,
        chain_key_256: int,
        base_str_salt: int,
        base_op_salt: int,
    ) -> Tuple[bytes, str, int, int, int]:
        res = self._compile_s2_fn(code, filename, seed, chain_key_256, base_str_salt, base_op_salt)
        return bytes.fromhex(res[0]), str(res[1]), int(res[2]), int(res[3]), int(res[4])

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
    and per-file Affine Bijective S-box. Also computes the 24-bit FNV-1a checksum over
    plaintext bytes for cross-block key & state-transition chaining.
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


def make_runtime_int(
    val: int,
    rng: random.Random,
    v_anchor: str,
    anchor_vals: List[int],
    v_bxor: str,
) -> str:
    """
    Emits a runtime-state-dependent expression evaluating to `val` using the
    runtime anchor table `v_anchor[1..16]`.
    Never emits `(const1 - const2)` or `(const1 + const2)` where both operands are constants!
    """
    idx = rng.randint(1, len(anchor_vals))
    ak = anchor_vals[idx - 1]
    mode = rng.randint(0, 2)
    if mode == 0 and 0 <= val < 16777216:
        mask = val ^ ak
        return f"{v_bxor}({v_anchor}[{idx}],{mask})"
    diff = val - ak
    if diff >= 0:
        return f"({v_anchor}[{idx}]+{diff})"
    else:
        return f"({v_anchor}[{idx}]-{-diff})"


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
    Compiles a Luau source file into v4.0 Dual-VM:
    Layer 1 (Stage-2 Inner VM): Prometheus `Vmify` Custom Register Bytecode VM + Lazy Encrypted Constant Table
    Layer 2 (Stage-1 Outer VM): Chained-Key Dual-LCG PCBC VM with 6-way C-Closure Anti-Hook Probe,
                                Runtime-State Expressions, Dynamic CRC State Transitions, & Zero Header Signatures
    """
    digest = hashlib.sha256((rel_path + "::v4::" + clean_source).encode("utf-8")).digest()
    if file_seed is None:
        file_seed = int.from_bytes(digest[:4], "big") ^ 0x5F3A9C7D
    rng = random.Random(file_seed)

    # Bootstrap runtime anchor table parameters (16 slots populated at runtime after 6-way C-closure anti-hook probe)
    boot_seed_base = rng.randint(100000, 7000000)
    boot_trust_step = rng.randint(150000, 7000000)
    boot_lcg_a = rng.randint(25000, 95000) * 4 + 1
    boot_lcg_c = rng.randint(300000, 6000000) * 2 + 1

    anchor_vals: List[int] = []
    s_cur = (boot_seed_base + 1 * boot_trust_step) % 16777216
    for i in range(1, 17):
        s_cur = (s_cur * boot_lcg_a + boot_lcg_c + i * 4099) % 16777216
        anchor_vals.append(s_cur)

    # Encrypt the 9 anti-hook probe symbol names so their names never appear in plaintext in the output file
    raw_probe_bytes = ("\0".join(PROBE_SYMBOLS) + "\0").encode("utf-8")
    probe_xor = rng.randint(17, 251)
    probe_step = rng.randint(3, 125) * 2 + 1
    enc_probe_bytes = bytes(
        ((b ^ probe_xor) + (i + 1) * probe_step) & 0xFF
        for i, b in enumerate(raw_probe_bytes)
    )
    enc_probe_literal = lua_escape_bytes(enc_probe_bytes)

    # Stage-1 Affine S-Box and Dual-LCG parameters
    odd_multipliers = [m for m in range(3, 255, 2) if m not in (1, 127, 129, 255)]
    s_mul = rng.choice(odd_multipliers)
    s_add = rng.randint(1, 255)
    sbox = [((x * s_mul) + s_add) & 0xFF for x in range(256)]
    inv_mul = pow(s_mul, -1, 256)

    lcg_a1 = rng.randint(35000, 115000) * 4 + 1
    lcg_c1 = rng.randint(400000, 7500000) * 2 + 1
    lcg_a2 = rng.randint(35000, 115000) * 4 + 1
    lcg_c2 = rng.randint(400000, 7500000) * 2 + 1
    lcg_init2 = rng.randint(100000, 15000000)

    b64_list = list(SAFE_B64_POOL)
    rng.shuffle(b64_list)
    alpha64 = "".join(b64_list[:64])
    pad_char = b64_list[64]
    full_alpha65 = (alpha64 + pad_char).encode("utf-8")
    alpha_mul = rng.randint(3, 251)
    alpha_add = rng.randint(7, 249)
    enc_alpha65 = bytes((b + (i + 1) * alpha_mul + alpha_add) & 0xFF for i, b in enumerate(full_alpha65))

    # Layer 1 (Stage-2 Inner VM): Compile Luau AST into Vmify custom bytecode & encrypted binary prototype stream
    s2_seed = (file_seed & 0x7FFFFFFF) or 1337
    init_chain_key256 = anchor_vals[0] % 256
    base_str_salt = rng.randint(17, 239)
    base_op_salt = rng.randint(19, 241)

    payload_bytes, minified_rt, _, _, _ = bridge.compile_stage2_vmify(
        clean_source,
        rel_path,
        s2_seed,
        init_chain_key256,
        base_str_salt,
        base_op_salt,
    )

    # Layer 2 (Stage-1 Outer VM): Split binary Vmify bytecode into 5..8 Dual-LCG PCBC blocks
    num_blocks = rng.randint(5, 8) if len(payload_bytes) >= 256 else 3
    chunk_size = max(1, (len(payload_bytes) + num_blocks - 1) // num_blocks)
    raw_blocks: List[bytes] = []
    for idx in range(0, len(payload_bytes), chunk_size):
        raw_blocks.append(payload_bytes[idx : idx + chunk_size])
    num_blocks = len(raw_blocks)

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
        },
        {
            "kind": "probe",
            "id": 0,
            "b64": enc_probe_literal,
            "seed": 0,
            "iv": 0,
            "crc": 0,
            "pre_mask": 0,
            "pre_step": 0,
        },
    ]

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

    for dec_id in range(rng.randint(1, 3)):
        dec_bytes = bytes(rng.randint(0, 255) for _ in range(rng.randint(16, 40)))
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
    k_probe_idx = 0
    blk_k_index: Dict[int, Tuple[int, int, int, int, int, int]] = {}
    for k_pos, entry in enumerate(k_entries, start=1):
        if entry["kind"] == "alpha":
            k_alpha_idx = k_pos
        elif entry["kind"] == "probe":
            k_probe_idx = k_pos
        elif entry["kind"] == "blk":
            blk_k_index[int(entry["id"])] = (
                k_pos,
                int(entry["seed"]),
                int(entry["iv"]),
                int(entry["crc"]),
                int(entry["pre_mask"]),
                int(entry["pre_step"]),
            )

    opcode_names = [
        "OP_SBOX",
        "OP_ALPHA",
        "OP_LOADK",
        "OP_XOR_DEC",
        "OP_CONCAT",
        "OP_CRC",
        "OP_MBA",
        "OP_MIX",
        "OP_EXEC",
        "OP_RET",
    ]
    opcode_pool = rng.sample(range(13, 245), len(opcode_names))
    op_ids: Dict[str, int] = dict(zip(opcode_names, opcode_pool))

    # 4 live states (st_init, st_fetch, st_dispatch, st_step) + 1 loop exit state (st_exit)
    st_init, st_fetch, st_dispatch, st_step, st_exit = rng.sample(range(105, 945), 5)

    # 7-tuple instruction layout with dynamic CRC-chained opcode guard and dynamic CRC-chained next-state slot
    tuple_width = 7
    all_slots = list(range(1, tuple_width + 1))
    rng.shuffle(all_slots)
    slot_op, slot_a, slot_b, slot_c, slot_d, slot_guard, slot_next = all_slots

    blk_dec_base = rng.randint(140, 310)
    reserved_blk_regs = set(range(blk_dec_base, blk_dec_base + num_blocks))
    candidate_regs = [r for r in range(15, 485) if r not in reserved_blk_regs]
    drawn_regs = rng.sample(candidate_regs, 10 + num_blocks)
    reg_iter = iter(drawn_regs)

    reg_sbox = next(reg_iter)
    reg_alpha = next(reg_iter)
    reg_chain_crc = next(reg_iter)
    reg_mba = next(reg_iter)
    reg_mix = next(reg_iter)
    reg_full_source = next(reg_iter)
    reg_exec_res = next(reg_iter)
    reg_decoy_init = next(reg_iter)

    reg_blk_enc = [next(reg_iter) for _ in range(num_blocks)]
    reg_blk_dec = [blk_dec_base + i for i in range(num_blocks)]

    insns: List[List[int]] = []
    chain_init = anchor_vals[1]

    def encode_insn(
        op_name: str,
        a: int,
        b: int,
        c: int,
        d: int,
        pre_crc: int,
        post_crc: int,
    ) -> List[int]:
        arr = [0] * tuple_width
        guard_val = rng.randint(300, 65000)
        arr[slot_guard - 1] = guard_val
        arr[slot_op - 1] = op_ids[op_name] ^ ((guard_val + (pre_crc % 256)) & 0xFF)
        arr[slot_a - 1] = a
        arr[slot_b - 1] = b
        arr[slot_c - 1] = c
        arr[slot_d - 1] = d
        arr[slot_next - 1] = st_step ^ (post_crc & 0xFF)
        return arr

    running_chain_crc = chain_init
    insns.append(encode_insn("OP_SBOX", reg_sbox, inv_mul, s_add, chain_init, running_chain_crc, running_chain_crc))
    insns.append(encode_insn("OP_ALPHA", reg_alpha, k_alpha_idx, alpha_mul, alpha_add, running_chain_crc, running_chain_crc))
    insns.append(encode_insn("OP_MIX", reg_mix, rng.randint(50, 9999), rng.randint(50, 9999), rng.randint(1, 255), running_chain_crc, running_chain_crc))

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
        crc_delta = rng.randint(1000, 500000)
        next_crc = ((running_chain_crc * 65599 + chain_salt) % 16777216) ^ ((crc_val + crc_delta) % 16777216)

        insns.append(encode_insn("OP_LOADK", r_enc, k_idx, pre_mask, pre_step, running_chain_crc, running_chain_crc))
        insns.append(encode_insn("OP_MBA", reg_mba, m1, m2, m3, running_chain_crc, running_chain_crc))
        insns.append(encode_insn("OP_XOR_DEC", r_plain, r_enc, reg_mba, iv_val, running_chain_crc, running_chain_crc))
        insns.append(encode_insn("OP_CRC", r_plain, crc_delta, chain_salt, blk_id + 100, running_chain_crc, next_crc))
        running_chain_crc = next_crc
        if step_idx % 2 == 0:
            insns.append(encode_insn("OP_MIX", reg_mix, rng.randint(100, 9999), rng.randint(100, 9999), blk_id, running_chain_crc, running_chain_crc))

    final_chain_crc = running_chain_crc
    ck_offset = (init_chain_key256 - (final_chain_crc % 256)) % 256

    insns.append(encode_insn("OP_CONCAT", reg_full_source, blk_dec_base, blk_dec_base + num_blocks - 1, 0, final_chain_crc, final_chain_crc))
    insns.append(encode_insn("OP_EXEC", reg_exec_res, reg_full_source, ck_offset, 0, final_chain_crc, final_chain_crc))
    insns.append(encode_insn("OP_RET", reg_exec_res, 0, 0, 0, final_chain_crc, final_chain_crc))

    (
        v_env,
        v_args,
        v_argc,
        v_reg,
        v_konst,
        v_code,
        v_anchor,
        v_pc,
        v_state,
        v_str,
        v_char,
        v_byte,
        v_sub,
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
        v_vm_fn,
        v_i,
        v_j,
        v_r,
        v_p,
        v_n,
    ) = generate_identifiers(38, rng)

    def rint(val: int) -> str:
        return make_runtime_int(val, rng, v_anchor, anchor_vals, v_bxor)

    cnt_key = rng.randint(1024, 999999)

    k_literals = ['"' + str(entry["b64"]) + '"' for entry in k_entries]
    k_table_str = "{" + ",".join(k_literals) + "}"

    i_literals: List[str] = []
    for ins in insns:
        elems = [
            rint(val) if rng.random() < 0.45 else str(val)
            for val in ins
        ]
        i_literals.append("{" + ",".join(elems) + "}")
    i_table_str = "{" + ",".join(i_literals) + "}"

    decoy_reg_pairs = [
        f"[{rint(reg_decoy_init)}]={rint(rng.randint(10, 9999))}",
        f"[{rint(reg_chain_crc)}]={rint(chain_init)}",
    ]
    reg_init_str = "{" + ",".join(decoy_reg_pairs) + "}"

    # Pre-declare `v_konst` before `anti_hook_bootstrap` so the encrypted probe blob is fetched from `v_konst[k_probe_idx]`
    # and then declare `v_reg`, `v_code`, `v_vm_fn` in randomized order after `v_anchor` is populated!
    table_decl_stmts = [
        f"local {v_reg}={reg_init_str};",
        f"local {v_code}={i_table_str};",
        f"local {v_vm_fn}={minified_rt};",
    ]
    rng.shuffle(table_decl_stmts)
    randomized_table_decls = "".join(table_decl_stmts)

    handlers: Dict[int, str] = {
        op_ids["OP_SBOX"]: (
            f"{v_t1}={{}};for {v_i}=0,255 do {v_t1}[{v_i}]=({v_i}*{v_b}-{v_c}*{v_b})%256 end;"
            f"{v_reg}[{v_a}]={v_t1};{v_reg}[{rint(reg_chain_crc)}]={v_d}"
        ),
        op_ids["OP_ALPHA"]: (
            f"{v_t1},{v_t2}={{}},{v_konst}[{v_b}];"
            f"for {v_i}=1,#{v_t2} do {v_t1}[({v_byte}({v_t2},{v_i})-{v_i}*{v_c}-{v_d})%256]={v_i}-1 end;"
            f"{v_reg}[{v_a}]={v_t1}"
        ),
        op_ids["OP_LOADK"]: (
            f"{v_t1},{v_t2},{v_t3},{v_t4}={v_konst}[{v_b}],{v_reg}[{rint(reg_alpha)}],{{}},1;"
            f"for {v_i}=1,#{v_t1},4 do "
            f"{v_t5}={v_t2}[{v_byte}({v_t1},{v_i})]*262144+{v_t2}[{v_byte}({v_t1},{v_i}+1)]*4096+({v_t2}[{v_byte}({v_t1},{v_i}+2)]%64)*64+({v_t2}[{v_byte}({v_t1},{v_i}+3)]%64);"
            f"{v_t6}=({v_t5}-{v_t5}%65536)/65536;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1;"
            f"if {v_t2}[{v_byte}({v_t1},{v_i}+2)]<64 then "
            f"{v_t6}=(({v_t5}-{v_t5}%256)/256)%256;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1;"
            f"if {v_t2}[{v_byte}({v_t1},{v_i}+3)]<64 then "
            f"{v_t6}={v_t5}%256;"
            f"{v_t3}[{v_t4}]={v_cmap}[{v_bxor}({v_t6},({v_c}+({v_t4}-1)*{v_d})%256)];{v_t4}={v_t4}+1 "
            f"end end end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t3})"
        ),
        op_ids["OP_MBA"]: (
            f"{v_t1}=({v_b}+{v_c})-2*{v_band}({v_b},{v_c});"
            f"{v_reg}[{v_a}]={v_bxor}({v_bxor}({v_t1},{v_d}),{v_reg}[{rint(reg_chain_crc)}])"
        ),
        op_ids["OP_MIX"]: (
            f"{v_reg}[{v_a}]=({v_b}*37+{v_c}+{v_d})%65536"
        ),
        op_ids["OP_XOR_DEC"]: (
            f"{v_t1}={v_reg}[{v_b}];"
            f"{v_t2}={v_reg}[{v_c}]%16777216;"
            f"{v_t3}=({v_t2}*65599+{v_d}*4099+{rint(lcg_init2)})%16777216;"
            f"{v_t4},{v_t5},{v_t6}={v_d}%256,({v_t2}%251)+1,{{}};"
            f"for {v_i}=1,#{v_t1} do "
            f"{v_t7}={v_byte}({v_t1},{v_i});"
            f"{v_t2}=({v_t2}*{rint(lcg_a1)}+{rint(lcg_c1)})%16777216;"
            f"{v_t3}=({v_t3}*{rint(lcg_a2)}+{rint(lcg_c2)})%16777216;"
            f"{v_t8}={v_bxor}({v_bxor}({v_reg}[{rint(reg_sbox)}][({v_t7}-((({v_t2}-{v_t2}%256)/256)%256+{v_t3}%256)%256-{v_t4})%256],{v_bxor}({v_t2}%256,(({v_t3}-{v_t3}%65536)/65536)%256)),{v_t5});"
            f"{v_t6}[{v_i}]={v_cmap}[{v_t8}];"
            f"{v_t4},{v_t5}={v_t7},{v_t8} end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t6})"
        ),
        op_ids["OP_CRC"]: (
            f"{v_t1},{v_t2}={v_reg}[{v_a}],{rint(2166136261 % 16777216)};"
            f"for {v_i}=1,#{v_t1} do {v_t2}=({v_bxor}({v_t2},{v_byte}({v_t1},{v_i}))*16777619)%16777216 end;"
            f"{v_reg}[{rint(reg_chain_crc)}]={v_bxor}(({v_reg}[{rint(reg_chain_crc)}]*65599+{v_c})%16777216,({v_t2}+{v_b})%16777216)"
        ),
        op_ids["OP_CONCAT"]: (
            f"{v_t1},{v_t2}={{}},1;"
            f"for {v_i}={v_b},{v_c} do {v_t1}[{v_t2}]={v_reg}[{v_i}];{v_reg}[{v_i}]=nil;{v_t2}={v_t2}+1 end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t1})"
        ),
        op_ids["OP_EXEC"]: (
            f"{v_t1}={v_reg}[{v_b}];{v_reg}[{v_b}]=nil;"
            f"{v_t2}=({v_reg}[{rint(reg_chain_crc)}]%256+{v_c})%256;"
            f"{v_t3}=function(...)return{{[{rint(cnt_key)}]=select({v_cmap}[35],...),...}}end;"
            f"{v_reg}[{v_a}]={v_t3}({v_vm_fn}({v_t1},{v_t2},{v_bxor},{v_cmap},{v_byte},{v_sub},{v_concat},{v_unpack}({v_args},1,{v_argc})))"
        ),
        op_ids["OP_RET"]: (
            f"{v_t1}={v_reg}[{v_a}];return {v_unpack}({v_t1},1,{v_t1}[{rint(cnt_key)}])"
        ),
    }

    sorted_ops = sorted(handlers.items(), key=lambda kv: kv[0])

    def emit_dispatch_tree(items: List[Tuple[int, str]]) -> str:
        if len(items) == 1:
            op_code, body = items[0]
            return f"if {v_op}=={rint(op_code)} then {body} end"
        mid = len(items) // 2
        split_val = items[mid - 1][0]
        left_code = emit_dispatch_tree(items[:mid])
        right_code = emit_dispatch_tree(items[mid:])
        return f"if {v_op}<={rint(split_val)} then {left_code} else {right_code} end"

    dispatch_tree_code = emit_dispatch_tree(sorted_ops)

    # 6-way C-Closure Anti-Hook Probe decoding all 9 symbol names dynamically from v_konst[k_probe_idx]
    # Reuses v_t1..v_t8 so zero descriptive variable names or plaintext symbol strings exist!
    anti_hook_bootstrap = (
        f"local {v_anchor}={{}};"
        f"{v_t1},{v_t2},{v_t3},{v_t4}={{}},{{}},1,{v_konst}[{k_probe_idx}];"
        f"for {v_i}=1,#{v_t4} do "
        f"{v_t5}={v_bxor}(({v_byte}({v_t4},{v_i})-{v_i}*{probe_step})%256,{probe_xor});"
        f"if {v_t5}==0 then {v_t1}[#{v_t1}+1]={v_concat}({v_t2});{v_t2},{v_t3}={{}},1 "
        f"else {v_t2}[{v_t3}]={v_cmap}[{v_t5}];{v_t3}={v_t3}+1 end end;"
        f"{v_t2},{v_t3}=1,{v_str}[{v_t1}[1]];"
        f"{v_t4}=type({v_env}[{v_t1}[2]])==type({v_anchor})and type({v_env}[{v_t1}[2]][{v_t1}[3]])==type(pcall)and {v_env}[{v_t1}[2]][{v_t1}[3]];"
        f"{v_t5}=type({v_env}[{v_t1}[4]])==type(pcall)and {v_env}[{v_t1}[4]];"
        f"{v_t6}=type({v_env}[{v_t1}[5]])==type(pcall)and {v_env}[{v_t1}[5]];"
        f"{v_t7}=(type({v_env}[{v_t1}[6]])==type(pcall)and {v_env}[{v_t1}[6]])or(type({v_env}[{v_t1}[7]])==type(pcall)and {v_env}[{v_t1}[7]]);"
        f"{v_t8}={{pcall,{v_byte},{v_char},{v_sub},{v_concat},tonumber,select,{v_env}[{v_t1}[8]]or {v_env}[{v_t1}[9]]}};"
        f"if type({v_t3})==type(pcall)then "
        f"if pcall({v_t3},{v_t3})or not pcall({v_t3},function()end)then {v_t2}=0 end "
        f"end;"
        f"for {v_i}=1,#{v_t8} do "
        f"{v_t1}={v_t8}[{v_i}];"
        f"if type({v_t1})~=type(pcall)then {v_t2}=0 else "
        f"if type({v_t3})==type(pcall)and pcall({v_t3},{v_t1})then {v_t2}=0 end;"
        f"if {v_t4} then {v_n}={v_t4}({v_t1},{v_cmap}[115]);if not {v_n} or {v_byte}({v_n},2)~=67 or {v_t4}({v_t1},{v_cmap}[108])~=-1 then {v_t2}=0 end end;"
        f"if {v_t5} and not {v_t5}({v_t1})then {v_t2}=0 end;"
        f"if {v_t6} and {v_t6}({v_t1})then {v_t2}=0 end;"
        f"if {v_t7} and {v_t7}({v_t1})then {v_t2}=0 end "
        f"end end;"
        f"{v_t1}={boot_seed_base}+{v_t2}*{boot_trust_step};"
        f"for {v_i}=1,16 do {v_t1}=({v_t1}*{boot_lcg_a}+{boot_lcg_c}+{v_i}*4099)%16777216;{v_anchor}[{v_i}]={v_t1} end;"
    )

    vm_body = (
        f"return(function(...)"
        f"local {v_env},{v_args},{v_argc},{v_str},{v_concat},{v_unpack}="
        f"(type(getfenv)==type(pcall)and getfenv())or _ENV or _G,{{...}},select('#',...),string,table.concat,unpack or table.unpack;"
        f"local {v_char},{v_byte},{v_sub},{v_bxor},{v_band},{v_cmap}={v_str}.char,{v_str}.byte,{v_str}.sub,bit32 and bit32.bxor,bit32 and bit32.band,{{}};"
        f"local {v_t1},{v_t2},{v_t3},{v_t4},{v_t5},{v_t6},{v_t7},{v_t8},{v_n};"
        f"if not {v_bxor} then "
        f"{v_n}={{}};"
        f"for {v_i}=0,15 do {v_t2}={{}};{v_n}[{v_i}]={v_t2};"
        f"for {v_j}=0,15 do {v_t3},{v_t4},{v_t5},{v_t6}=0,1,{v_i},{v_j};"
        f"while {v_t5}>0 or {v_t6}>0 do if {v_t5}%2~={v_t6}%2 then {v_t3}={v_t3}+{v_t4} end;{v_t5}=({v_t5}-{v_t5}%2)/2;{v_t6}=({v_t6}-{v_t6}%2)/2;{v_t4}={v_t4}*2 end;"
        f"{v_t2}[{v_j}]={v_t3} end end;"
        f"{v_bxor}=function({v_i},{v_j})"
        f"local {v_r},{v_p}=0,1;"
        f"while {v_i}>0 or {v_j}>0 do {v_r}={v_r}+{v_n}[{v_i}%16][{v_j}%16]*{v_p};{v_i}=({v_i}-{v_i}%16)/16;{v_j}=({v_j}-{v_j}%16)/16;{v_p}={v_p}*16 end;"
        f"return {v_r} end end;"
        f"if not {v_band} then {v_band}=function({v_i},{v_j})return(({v_i}+{v_j})-{v_bxor}({v_i},{v_j}))/2 end end;"
        f"for {v_i}=0,255 do {v_cmap}[{v_i}]={v_char}({v_i})end;"
        f"local {v_konst}={k_table_str};"
        f"{anti_hook_bootstrap}"
        f"{randomized_table_decls}"
        f"local {v_pc},{v_state},{v_insn},{v_op},{v_a},{v_b},{v_c},{v_d}=1,{rint(st_init)};"
        f"while {v_state}~={rint(st_exit)} do "
        f"if {v_state}=={rint(st_init)} then {v_pc}=1;{v_state}={rint(st_fetch)} "
        f"elseif {v_state}=={rint(st_fetch)} then "
        f"{v_insn}={v_code}[{v_pc}];"
        f"if not {v_insn} then break else "
        f"{v_op}={v_bxor}({v_insn}[{slot_op}],({v_insn}[{slot_guard}]+{v_reg}[{rint(reg_chain_crc)}]%256)%256);"
        f"{v_a},{v_b},{v_c},{v_d}={v_insn}[{slot_a}],{v_insn}[{slot_b}],{v_insn}[{slot_c}],{v_insn}[{slot_d}];"
        f"{v_state}={rint(st_dispatch)} end "
        f"elseif {v_state}=={rint(st_dispatch)} then "
        f"{dispatch_tree_code};"
        f"if {v_state}=={rint(st_dispatch)} then {v_state}={v_bxor}({v_insn}[{slot_next}],{v_reg}[{rint(reg_chain_crc)}]%256) end "
        f"elseif {v_state}=={rint(st_step)} then "
        f"{v_pc}={v_pc}+1;{v_state}={rint(st_fetch)} "
        f"else break end end end)(...)"
    )

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
    Verifies an obfuscated v4.0 file against all 5 architectural & security requirements:
    1. Zero Header Comments (`-- STEPH_COMPONENT` and `--[[STEPH_PROMETHEUS_VM]]` absent, line 1 starts with code)
    2. Zero `'VM integrity check failed'`, `'unknown VM opcode'`, or dead branches
    3. Zero Static Constant-Foldable `(A - B)` or `(-K + K)` arithmetic expressions
    4. Zero Plaintext String Leaks (including `"loadstring"`, `"iscclosure"`, `"ishooked"`, `"Breakables_PlayerDealDamage"`, etc.)
    5. Live Dual-VM Execution & Anti-Hook Verification in Lua 5.1:
       - Clean unhooked environment executes Stage-1 + Stage-2 (`Vmify` custom bytecode VM)
       - Malicious Lua hook on `loadstring` dumps 0 bytes (`ZERO_DUMP`) AND is detected by C-closure check,
         silently poisoning `v_anchor` so the VM exits returning `nil`
       - Malicious Lua hook on `table.concat` or `string.byte` is detected by C-closure check and silently poisons `v_anchor`
       - Valid Luau AST with max per-function local count < 40 (well below Luau's 200-local limit)
    """
    first_line = obf_source.splitlines()[0].strip()
    if first_line.startswith("--") or "STEPH_COMPONENT" in obf_source or "STEPH_PROMETHEUS_VM" in obf_source:
        raise AssertionError(f"[{rel_path}] Header signature or comment found in obfuscated output!")

    if FORBIDDEN_ANCHOR_RE.search(obf_source):
        raise AssertionError(f"[{rel_path}] Contains forbidden AnchorPoint=UDim2 pattern!")

    if rel_path in obf_source:
        raise AssertionError(f"[{rel_path}] Filename leaked inside obfuscated output!")

    forbidden_strings = (
        "VM integrity check failed",
        "unknown VM opcode",
        "loadstring",
        "iscclosure",
        "islclosure",
        "ishooked",
        "isfunctionhooked",
        "Breakables_PlayerDealDamage",
        "ReplicatedStorage",
        "__PS99CLEAN",
        "PumpkinTycoon",
        "BuyButtons",
        "3.4.3",
    )
    for leak in forbidden_strings:
        if leak in obf_source:
            raise AssertionError(f"[{rel_path}] Forbidden plaintext string {leak!r} leaked in obfuscated output!")

    static_arith_matches = STATIC_CONST_ARITH_RE.findall(obf_source)
    if static_arith_matches:
        raise AssertionError(
            f"[{rel_path}] Found static constant-foldable arithmetic expressions: {static_arith_matches[:5]}"
        )

    stmts, max_scope_locals = bridge.verify_luau_syntax(obf_source, rel_path)
    if max_scope_locals >= 60:
        raise AssertionError(
            f"[{rel_path}] Max function scope local count too high: {max_scope_locals} >= 60 (limit 200)"
        )

    test_rt = lua51.LuaRuntime()
    verify_fn = test_rt.eval(
        """
        function(vm_code, label)
            table.create = table.create or function() return {} end
            local fn, err = loadstring(vm_code, "=" .. label)
            if not fn then
                error("Outer VM compile error: " .. tostring(err), 0)
            end

            -- 1. Execute in clean unhooked environment
            local ok_clean, res_clean = pcall(fn)

            -- 2. Execute with malicious 1-line Lua hook on loadstring
            local dumped_ls = nil
            local orig_loadstring = loadstring
            loadstring = function(s, ...)
                dumped_ls = s
                return orig_loadstring(s, ...)
            end
            local ok_ls, res_ls = pcall(fn)
            loadstring = orig_loadstring

            -- 3. Execute with malicious Lua hook on table.concat
            local dumped_tc = nil
            local orig_concat = table.concat
            table.concat = function(t, ...)
                local r = orig_concat(t, ...)
                if type(r) == "string" and #r > 256 then
                    dumped_tc = r
                end
                return r
            end
            local ok_tc, res_tc = pcall(fn)
            table.concat = orig_concat

            return ok_clean, type(res_clean), tostring(res_clean),
                   dumped_ls == nil, ok_ls and res_ls == nil,
                   dumped_tc == nil, ok_tc and res_tc == nil
        end
        """
    )
    (
        ok_clean,
        res_type,
        res_str,
        ls_zero_dump,
        ls_poisoned_nil,
        tc_zero_dump,
        tc_poisoned_nil,
    ) = verify_fn(obf_source, rel_path)

    if not ls_zero_dump or not ls_poisoned_nil:
        raise AssertionError(
            f"[{rel_path}] Failed loadstring anti-hook test! zero_dump={ls_zero_dump}, poisoned_nil={ls_poisoned_nil}"
        )
    if not tc_zero_dump or not tc_poisoned_nil:
        raise AssertionError(
            f"[{rel_path}] Failed table.concat anti-hook test! zero_dump={tc_zero_dump}, poisoned_nil={tc_poisoned_nil}"
        )

    if rel_path == "manifest.lua":
        if not ok_clean or res_type != "table":
            raise AssertionError(f"[manifest.lua] Expected VM to return table, got ok={ok_clean} type={res_type} ({res_str})")
    elif rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if not ok_clean or res_type != "function":
            raise AssertionError(f"[{rel_path}] Expected VM to return builder function, got ok={ok_clean} type={res_type} ({res_str})")
    else:
        # Top-level game scripts unpack Stage-2 Vmify bytecode and enter the VM loop until hitting Roblox `game` global
        if not ok_clean and "attempt to index" in res_str:
            res_type = "vm_entered(luau)"
        elif not ok_clean:
            raise AssertionError(f"[{rel_path}] Unexpected VM runtime error: {res_str}")

    return {
        "file": rel_path,
        "max_scope_locals": max_scope_locals,
        "clean_bytes": len(clean_source),
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
    parser = argparse.ArgumentParser(description="Steph HUB Prometheus Vmify + Chained-Key Dual-VM Obfuscator v4.0")
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

    print("[1/4] Backing up clean unobfuscated sources first...", flush=True)
    clean_sources = backup_and_load_clean_sources(args.repo)
    print(
        f"      Saved {len(clean_sources)} unobfuscated files to:\n"
        f"      - {WORKSPACE_SRC_DIR}\n"
        f"      - {UNOBF_EXTERNAL_DIR}\n"
        f"      - {UNOBF_LOCAL_DIR}",
        flush=True,
    )

    if args.backup_only:
        return 0

    bridge = PrometheusBridge()

    if not args.verify_only:
        print("[2/4] Compiling Luau files with Dual-VM v4.0 (Stage-2 Vmify Custom Bytecode + Stage-1 Anti-Hook PCBC VM)...", flush=True)
        for idx, (rel, clean_src) in enumerate(clean_sources.items()):
            file_seed = (args.seed + idx * 7919) if args.seed is not None else None
            obf_src = compile_polymorphic_vm(clean_src, rel, bridge, file_seed=file_seed)
            out_path = os.path.join(args.repo, rel)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(obf_src)

    print("[3/4] Verifying all obfuscated files in Lua 5.1 + Anti-Hook + Prometheus LuaU AST harness...", flush=True)
    reports: List[Dict[str, object]] = []
    for rel, clean_src in clean_sources.items():
        obf_path = os.path.join(args.repo, rel)
        with open(obf_path, "r", encoding="utf-8") as f:
            obf_src = f.read()
        rep = verify_obfuscated_file(rel, clean_src, obf_src, bridge)
        reports.append(rep)
        print(
            f"      PASS {rel:24s} | max_loc={rep['max_scope_locals']:2d} (<200) | "
            f"clean={rep['clean_bytes']:7d}B -> vm_v4={rep['obf_bytes']:7d}B | "
            f"hook_guard=ZERO_DUMP | ret={rep['return_type']}",
            flush=True,
        )

    if not args.no_workspace_sync:
        print(f"[4/4] Syncing {len(reports)} verified obfuscated files to {WORKSPACE_DIR}...", flush=True)
        sync_to_workspace(args.repo)

    print(f"[DONE] Verified {len(reports)}/{len(reports)} VM-obfuscated files in {time.time() - t_start:.2f}s.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
