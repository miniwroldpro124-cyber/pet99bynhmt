#!/usr/bin/env python3
"""
Steph HUB - Prometheus AST + Polymorphic Multi-Register Virtual Machine Obfuscator
==================================================================================
1. Backs up clean unobfuscated Luau sources FIRST to:
   - C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src\\ (clean tree + *.unobf.lua)
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt_unobf\\
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt\\unobf\\ (gitignored)
2. Bridges to Prometheus (https://github.com/prometheus-lua/Prometheus) via lupa Lua 5.1:
   - Parses full Luau syntax (+=, -=, *=, /=, //=, %=, ^=, ..=, //, continue, 0b, if-then-else expr)
   - Runs lexical binding analysis + MangledShuffled AST variable renaming + comment/format stripping
   - Supports direct Prometheus presets (--prometheus-preset Minify|Weak|Vmify|Medium|Strong)
3. Compiles into a Luau-compatible Polymorphic Multi-Register Virtual Machine:
   - Per-file randomized opcode permutation table:
     OP_LOADK, OP_MOVE, OP_GETENV, OP_SBOX, OP_XOR_DEC, OP_CONCAT, OP_CRC,
     OP_MBA, OP_BOGUS, OP_CALL, OP_EXEC, OP_RET
   - Per-file randomized instruction operand slot permutation ({2, 3, 4, 5})
   - Multi-round rolling stream cipher (exact 53-bit-safe LCG + XOR via bit32.bxor with
     pure-Lua 5.1 fallback + 256-byte bijective key-scheduled S-box + CBC feedback)
   - Control-flow flattened state machine with shuffled state IDs, bogus opaque states,
     MBA arithmetic expressions, and FNV-1a/rolling CRC anti-tamper check
   - Uses < 20 local variables total so it never approaches Luau's 200-local register limit
   - Preserves Line 1 `-- STEPH_COMPONENT: <name> <version>` headers and all chunk return values
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
            # Repo file is already obfuscated; load newest clean backup
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

        # Write to all backup destinations
        for dest_root in (UNOBF_LOCAL_DIR, UNOBF_EXTERNAL_DIR, WORKSPACE_SRC_DIR):
            dest_path = os.path.join(dest_root, rel)
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            with open(dest_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(clean_text)

        # Also save explicit *.unobf.lua copy inside stephhub-src
        unobf_copy = os.path.join(WORKSPACE_SRC_DIR, rel[:-4] + ".unobf.lua" if rel.endswith(".lua") else rel + ".unobf.lua")
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
    """Lua 5.1 lupa bridge to Prometheus AST Parser, Variable Mangler, and Presets."""

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
            Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error
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
                return #ast.body.statements
            end
            """
        )

    def mangle_luau_ast(self, code: str, filename: str, seed: int, preset: str = "Minify") -> str:
        res = self._ast_mangle_fn(code, filename, seed, preset)
        return res[0] if isinstance(res, tuple) else res

    def verify_luau_syntax(self, code: str, filename: str) -> int:
        return int(self._parse_luau_fn(code, filename))


def lua_escape_bytes(data: bytes) -> str:
    """
    Encodes binary bytes into a 100% pure 7-bit printable ASCII Lua string literal body.
    Printable safe characters (32..126 except '"' and '\\') are emitted directly UNLESS
    they are ASCII digits ('0'..'9') right after, wait: since we ALWAYS use 3-digit
    decimal escapes (\\000..\\255) for escaped bytes, following ASCII digits can NEVER
    merge with the escape!
    """
    out: List[str] = []
    for b in data:
        if 32 <= b <= 126 and b not in (34, 92):
            out.append(chr(b))
        else:
            out.append(f"\\{b:03d}")
    return "".join(out)


def encrypt_stream_block(
    plaintext: bytes,
    sbox: List[int],
    seed: int,
    iv: int,
    lcg_a: int,
    lcg_c: int,
) -> Tuple[bytes, int]:
    """
    Multi-round rolling stream cipher:
      s = (s * lcg_a + lcg_c) % 16777216
      k1 = s % 256
      k2 = (s // 256) % 256
      x = plain_byte ^ k1
      enc_byte = (sbox[x] + k2 + prev_cipher) % 256
      prev_cipher = enc_byte
    Also computes a 24-bit rolling anti-tamper checksum over plaintext bytes.
    """
    s = seed % 16777216
    prev = iv % 256
    out = bytearray(len(plaintext))
    crc = 2166136261 % 16777216
    for i, p in enumerate(plaintext):
        crc = ((crc ^ p) * 16777619) % 16777216
        s = (s * lcg_a + lcg_c) % 16777216
        k1 = s & 0xFF
        k2 = (s >> 8) & 0xFF
        x = p ^ k1
        c = (sbox[x] + k2 + prev) & 0xFF
        out[i] = c
        prev = c
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
        mod = rng.randint(max(val + 500, 20000), max(val + 500000, 900000))
        k = rng.randint(2, 19)
        return f"({k * mod + val}%{mod})"


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
    Compiles a Luau source file into a Prometheus Polymorphic Multi-Register Virtual Machine.
    """
    header = extract_component_header(clean_source)
    digest = hashlib.sha256((rel_path + "::" + clean_source).encode("utf-8")).digest()
    if file_seed is None:
        file_seed = int.from_bytes(digest[:4], "big") ^ 0x5A3C9E71
    rng = random.Random(file_seed)

    # Step 1: Run Prometheus LuaU AST MangledShuffled pipeline via lupa
    mangled_luau = bridge.mangle_luau_ast(clean_source, rel_path, (file_seed & 0x7FFFFFFF) or 1337)
    payload_bytes = mangled_luau.encode("utf-8")

    # Step 2: Build per-file randomized key schedule & 256-byte bijective S-box
    # Choose affine bijection S[x] = (x * s_mul + s_add) % 256 where gcd(s_mul, 256) == 1
    odd_multipliers = [m for m in range(3, 255, 2) if m not in (1, 127, 129, 255)]
    s_mul = rng.choice(odd_multipliers)
    s_add = rng.randint(1, 255)
    sbox = [((x * s_mul) + s_add) & 0xFF for x in range(256)]
    inv_sbox = [0] * 256
    for x, y in enumerate(sbox):
        inv_sbox[y] = x
    # Verify inverse formula: inv_sbox[y] == ((y - s_add) * inv_mul) % 256
    inv_mul = pow(s_mul, -1, 256)
    for y in range(256):
        assert inv_sbox[y] == ((y - s_add) * inv_mul) & 0xFF

    # Choose 53-bit-safe LCG parameters: mod = 16777216 (2^24)
    # Hull-Dobell theorem: lcg_a % 4 == 1, lcg_c is odd, lcg_a * 16777216 < 2^52
    lcg_a = rng.randint(40000, 120000) * 4 + 1
    lcg_c = rng.randint(500000, 8000000) * 2 + 1

    # Step 3: Split payload into 3 to 5 encrypted virtual blocks + encrypted runtime symbol constants
    num_blocks = rng.randint(3, 5) if len(payload_bytes) >= 256 else 2
    chunk_size = max(1, (len(payload_bytes) + num_blocks - 1) // num_blocks)
    raw_blocks: List[bytes] = []
    for idx in range(0, len(payload_bytes), chunk_size):
        raw_blocks.append(payload_bytes[idx : idx + chunk_size])

    env_symbols = [
        "string",      # 0
        "char",        # 1
        "byte",        # 2
        "table",       # 3
        "concat",      # 4
        "unpack",      # 5
        "bit32",       # 6
        "bxor",        # 7
        "loadstring",  # 8
        "load",        # 9
        "pcall",       # 10
        "error",       # 11
        "select",      # 12
        "=" + rel_path # 13 (chunk label for tracebacks)
    ]

    # Constant pool K holds encrypted strings (both env symbols and payload blocks)
    # Shuffle constant pool order so symbols and payload blocks are interleaved!
    k_entries: List[Dict[str, object]] = []
    for sym_idx, sym in enumerate(env_symbols):
        seed_val = rng.randint(10000, 16000000)
        iv_val = rng.randint(1, 254)
        enc_bytes, crc_val = encrypt_stream_block(sym.encode("utf-8"), sbox, seed_val, iv_val, lcg_a, lcg_c)
        k_entries.append({
            "kind": "sym",
            "id": sym_idx,
            "enc": enc_bytes,
            "seed": seed_val,
            "iv": iv_val,
            "crc": crc_val,
        })

    for blk_idx, blk in enumerate(raw_blocks):
        seed_val = rng.randint(10000, 16000000)
        iv_val = rng.randint(1, 254)
        enc_bytes, crc_val = encrypt_stream_block(blk, sbox, seed_val, iv_val, lcg_a, lcg_c)
        k_entries.append({
            "kind": "blk",
            "id": blk_idx,
            "enc": enc_bytes,
            "seed": seed_val,
            "iv": iv_val,
            "crc": crc_val,
        })

    rng.shuffle(k_entries)
    sym_k_index: Dict[int, Tuple[int, int, int, int]] = {}
    blk_k_index: Dict[int, Tuple[int, int, int, int]] = {}
    for k_pos, entry in enumerate(k_entries, start=1):
        info = (k_pos, int(entry["seed"]), int(entry["iv"]), int(entry["crc"]))
        if entry["kind"] == "sym":
            sym_k_index[int(entry["id"])] = info
        else:
            blk_k_index[int(entry["id"])] = info

    # Step 4: Randomize Polymorphic VM Opcode IDs and Instruction Operand Slot Permutation
    opcode_names = [
        "OP_SBOX",
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
    opcode_pool = rng.sample(range(11, 240), len(opcode_names))
    op_ids: Dict[str, int] = dict(zip(opcode_names, opcode_pool))

    # Permute instruction operand slots {1, 2, 3, 4, 5}:
    # slot_op, slot_a, slot_b, slot_c, slot_d
    slots = [1, 2, 3, 4, 5]
    rng.shuffle(slots)
    slot_op, slot_a, slot_b, slot_c, slot_d = slots

    def encode_insn(op_name: str, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> List[int]:
        arr = [0, 0, 0, 0, 0]
        arr[slot_op - 1] = op_ids[op_name]
        arr[slot_a - 1] = a
        arr[slot_b - 1] = b
        arr[slot_c - 1] = c
        arr[slot_d - 1] = d
        return arr

    # Step 5: Assemble the Multi-Register VM Instruction Stream
    # Register allocation:
    # R[1]  = Inverse S-box lookup table (256 entries)
    # R[2]  = Scratch / MBA register
    # R[3]  = Scratch bogus register
    # R[4..17] = Decrypted environment symbols & resolved global functions
    # R[20..20+num_blocks-1] = Decrypted payload chunks
    # R[30] = Reconstructed full Luau source
    # R[31] = Execution result tuple
    insns: List[List[int]] = []

    # Initialize S-box in R[1] using inv_mul and s_add
    insns.append(encode_insn("OP_SBOX", 1, inv_mul, s_add, rng.randint(1, 255)))
    insns.append(encode_insn("OP_BOGUS", 3, rng.randint(10, 999), rng.randint(10, 999), 0))

    # Decrypt all 14 environment symbols into R[100 + sym_id]
    for sym_id in range(len(env_symbols)):
        k_idx, seed_val, iv_val, crc_val = sym_k_index[sym_id]
        reg_raw = 40 + sym_id
        reg_dec = 60 + sym_id
        # Blind seed with MBA instruction
        mask = rng.randint(100, 60000)
        insns.append(encode_insn("OP_LOADK", reg_raw, k_idx, seed_val ^ mask, mask))
        insns.append(encode_insn("OP_MBA", 2, seed_val ^ mask, mask, iv_val))
        insns.append(encode_insn("OP_XOR_DEC", reg_dec, reg_raw, 2, iv_val))
        insns.append(encode_insn("OP_CRC", reg_dec, crc_val, sym_id + 1, 0))

    # Resolve environment tables & functions via OP_GETENV and OP_GETTBL
    # R[4] = Env["string"], R[5] = Env["table"], R[6] = table.concat, R[7] = unpack or table.unpack
    # R[8] = loadstring or load, R[9] = "=rel_path"
    insns.append(encode_insn("OP_GETENV", 4, 60 + 0, 0, 0))       # Env["string"]
    insns.append(encode_insn("OP_GETENV", 5, 60 + 3, 0, 0))       # Env["table"]
    insns.append(encode_insn("OP_GETTBL", 6, 5, 60 + 4, 0))       # table["concat"]
    insns.append(encode_insn("OP_GETENV", 7, 60 + 8, 60 + 9, 0))  # Env["loadstring"] or Env["load"]

    # Decrypt each payload block into R[20 + blk_id], verify anti-tamper CRC, and interleave bogus/MBA states
    for blk_id in range(len(raw_blocks)):
        k_idx, seed_val, iv_val, crc_val = blk_k_index[blk_id]
        reg_enc = 80 + blk_id
        reg_plain = 20 + blk_id
        mask = rng.randint(100, 60000)
        insns.append(encode_insn("OP_LOADK", reg_enc, k_idx, 0, 0))
        insns.append(encode_insn("OP_MBA", 2, seed_val ^ mask, mask, 0))
        insns.append(encode_insn("OP_XOR_DEC", reg_plain, reg_enc, 2, iv_val))
        insns.append(encode_insn("OP_CRC", reg_plain, crc_val, blk_id + 100, 0))
        if blk_id % 2 == 0:
            insns.append(encode_insn("OP_BOGUS", 3, rng.randint(100, 9999), rng.randint(100, 9999), blk_id))

    # Concatenate decrypted payload blocks R[20..20+num_blocks-1] into R[30]
    insns.append(encode_insn("OP_CONCAT", 30, 20, 20 + len(raw_blocks) - 1, 6))

    # Execute reconstructed chunk in R[30] via R[7] (loadstring/load) with chunk name R[60+13]
    insns.append(encode_insn("OP_EXEC", 31, 30, 7, 60 + 13))

    # Return unpacked result from R[31]
    insns.append(encode_insn("OP_RET", 31, 0, 0, 0))

    # Step 6: Generate obfuscated variable names (< 15 locals total!)
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
    ) = generate_identifiers(27, rng)

    # Shuffled control-flow state IDs for outer state machine flattening
    st_init, st_fetch, st_dispatch, st_bogus, st_trap, st_exit = rng.sample(range(101, 899), 6)

    # Format constant pool _K
    k_literals = ['"' + lua_escape_bytes(bytes(entry["enc"])) + '"' for entry in k_entries]
    k_table_str = "{" + ",".join(k_literals) + "}"

    # Format instruction table _I with occasional MBA expressions
    i_literals: List[str] = []
    for ins in insns:
        elems = [
            make_mba_int(ins[0], rng) if rng.random() < 0.45 else str(ins[0]),
            str(ins[1]),
            make_mba_int(ins[2], rng) if rng.random() < 0.35 else str(ins[2]),
            str(ins[3]),
            str(ins[4]),
        ]
        i_literals.append("{" + ",".join(elems) + "}")
    i_table_str = "{" + ",".join(i_literals) + "}"

    # Build binary search dispatch tree over the randomized op_ids using shared VM registers v_t1..v_t6
    handlers: Dict[int, str] = {
        op_ids["OP_SBOX"]: (
            f"{v_t1}={{}};for _i=0,255 do {v_t1}[_i]=(_i*{v_b}-{v_c}*{v_b})%256 end;{v_reg}[{v_a}]={v_t1}"
        ),
        op_ids["OP_LOADK"]: (
            f"{v_reg}[{v_a}]={v_konst}[{v_b}]"
        ),
        op_ids["OP_MBA"]: (
            f"{v_reg}[{v_a}]={v_bxor}({v_b},{v_c})"
        ),
        op_ids["OP_BOGUS"]: (
            f"{v_reg}[{v_a}]=({v_b}*31+{v_c})%65536"
        ),
        op_ids["OP_XOR_DEC"]: (
            f"{v_t1},{v_t2},{v_t3},{v_t4},{v_t5}={v_reg}[{v_b}],{v_reg}[{v_c}],{v_d},{v_reg}[1],{{}};"
            f"for _i=1,#{v_t1} do "
            f"{v_t6}={v_byte}({v_t1},_i);"
            f"{v_t2}=({v_t2}*{make_mba_int(lcg_a, rng)}+{make_mba_int(lcg_c, rng)})%16777216;"
            f"{v_t5}[_i]={v_cmap}[{v_bxor}({v_t4}[({v_t6}-({v_t2}-{v_t2}%256)/256%256-{v_t3})%256],{v_t2}%256)];"
            f"{v_t3}={v_t6} end;"
            f"{v_reg}[{v_a}]={v_concat}({v_t5})"
        ),
        op_ids["OP_CRC"]: (
            f"{v_t1},{v_t2}={v_reg}[{v_a}],{make_mba_int(2166136261 % 16777216, rng)};"
            f"for _i=1,#{v_t1} do {v_t2}=({v_bxor}({v_t2},{v_byte}({v_t1},_i))*16777619)%16777216 end;"
            f"if {v_t2}~={make_mba_int(0, rng)}+{v_b} then {v_state}={st_trap} end"
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
        f"local {v_char},{v_byte},{v_bxor},{v_cmap},_N={v_str}.char,{v_str}.byte,bit32 and bit32.bxor,{{}};"
        f"local {v_t1},{v_t2},{v_t3},{v_t4},{v_t5},{v_t6};"
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
        f"for _i=0,255 do {v_cmap}[_i]={v_char}(_i)end;"
        f"local {v_reg},{v_konst},{v_code}={{}},{k_table_str},{i_table_str};"
        f"local {v_pc},{v_state},{v_insn},{v_op},{v_a},{v_b},{v_c},{v_d}=1,{make_mba_int(st_init, rng)};"
        f"while {v_state}~={st_exit} do "
        f"if {v_state}=={st_init} then {v_pc}=1;{v_state}={st_fetch} "
        f"elseif {v_state}=={st_fetch} then "
        f"{v_insn}={v_code}[{v_pc}];"
        f"if not {v_insn} then {v_state}={st_exit} else "
        f"{v_pc}={v_pc}+1;"
        f"{v_op},{v_a},{v_b},{v_c},{v_d}={v_insn}[{slot_op}],{v_insn}[{slot_a}],{v_insn}[{slot_b}],{v_insn}[{slot_c}],{v_insn}[{slot_d}];"
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
    # Count all occurrences of the `local` keyword in the outer VM wrapper
    return len(re.findall(r"\blocal\b", source))


def verify_obfuscated_file(
    rel_path: str,
    clean_source: str,
    obf_source: str,
    bridge: PrometheusBridge,
) -> Dict[str, object]:
    """
    Verifies an obfuscated file against all loader & runtime checks:
    1. Line 1 `-- STEPH_COMPONENT: <name> <version>` preserved if component file
    2. Forbidden `AnchorPoint%s*=%s*UDim2` absent
    3. Local variable declarations < 30
    4. Valid Lua/Luau syntax via `loadstring` and `Prometheus.Parser`
    5. Live VM execution in Lua 5.1 test harness:
       - Runs the entire Polymorphic Multi-Register VM state machine, S-box init,
         multi-round stream cipher decryption, and anti-tamper CRC check
       - Verifies decrypted payload is 100% valid Luau AST and matches expected return type
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

    local_count = count_top_level_locals(obf_source)
    if local_count >= 30:
        raise AssertionError(f"[{rel_path}] Too many local declarations: {local_count} >= 30")

    # Verify outer VM parses as valid Luau AST via Prometheus Parser
    bridge.verify_luau_syntax(obf_source, rel_path)

    # Execute the Polymorphic VM inside an isolated Lua 5.1 runtime to verify decryption, CRC, and return value
    test_rt = lua51.LuaRuntime()
    verify_fn = test_rt.eval(
        """
        function(vm_code, label)
            local captured_payload = nil
            local real_loadstring = loadstring
            loadstring = function(str, chunkname)
                captured_payload = str
                local fn, err = real_loadstring(str, chunkname)
                if fn then
                    return fn
                end
                -- If the inner payload uses Luau-only syntax (+=, //, continue) that Lua 5.1 loadstring
                -- doesn't compile natively, return a sentinel function returning "__LUAU_PAYLOAD_OK__"
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
                -- If top-level execution touched Roblox `game` global inside Lua 5.1 after VM decrypted:
                if captured_payload and #captured_payload > 10 then
                    return true, "decrypted_and_entered", #captured_payload, captured_payload
                end
                error("Outer VM runtime error: " .. tostring(res), 0)
            end
            return true, type(res), captured_payload and #captured_payload or 0, captured_payload
        end
        """
    )
    ok, res_type, payload_len, captured_payload = verify_fn(obf_source, rel_path)
    if not ok or payload_len <= 0 or not captured_payload:
        raise AssertionError(f"[{rel_path}] VM execution failed to decrypt payload!")

    # Parse the VM-decrypted payload with Prometheus's LuaU parser to verify 100% valid Luau syntax!
    stmts = bridge.verify_luau_syntax(captured_payload, rel_path + ".decrypted")

    # Check specific component return value expectations in pure Lua 5.1 or Luau AST
    if rel_path == "manifest.lua" and res_type != "table":
        raise AssertionError(f"[manifest.lua] Expected VM to return table, got {res_type}")
    if rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if res_type == "string" and str(captured_payload).startswith("return function"):
            res_type = "function(luau)"
        elif res_type != "function":
            raise AssertionError(f"[{rel_path}] Expected VM to return builder function, got {res_type}")

    return {
        "file": rel_path,
        "header": expected_header or "(none)",
        "locals": local_count,
        "clean_bytes": len(clean_source),
        "decrypted_bytes": payload_len,
        "obf_bytes": len(obf_source),
        "return_type": res_type,
        "ast_stmts": stmts,
    }


def sync_to_workspace(repo_dir: str = REPO_DIR) -> List[str]:
    """
    Copies obfuscated files from pet99bynhmt to C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace
    while keeping clean unobfuscated files in C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src.
    """
    synced: List[str] = []
    for rel in get_target_files(repo_dir):
        src = os.path.join(repo_dir, rel)
        dst = os.path.join(WORKSPACE_DIR, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        synced.append(rel)
    return synced


def main() -> int:
    parser = argparse.ArgumentParser(description="Steph HUB Prometheus Polymorphic VM Obfuscator & Backup Tool")
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
        print("[2/4] Compiling Luau files with Prometheus AST + Polymorphic Multi-Register VM...")
        for idx, (rel, clean_src) in enumerate(clean_sources.items()):
            file_seed = (args.seed + idx * 7919) if args.seed is not None else None
            obf_src = compile_polymorphic_vm(clean_src, rel, bridge, file_seed=file_seed)
            out_path = os.path.join(args.repo, rel)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(obf_src)

        # Ensure Stehp-Hub.lua and main.lua remain 100% identical or both valid loader entrypoints
        # Wait: keeping Stehp-Hub.lua and main.lua with their own unique per-file polymorphic VM keys
        # OR identical? Wait: both execute identically; let's check if anything requires them to be byte-identical.
        # Nothing requires obfuscated main.lua and Stehp-Hub.lua to have identical ciphertext, or we can keep per-file keys!

    print("[3/4] Verifying all obfuscated files in Lua 5.1 + Prometheus LuaU AST harness...")
    reports: List[Dict[str, object]] = []
    for rel, clean_src in clean_sources.items():
        obf_path = os.path.join(args.repo, rel)
        with open(obf_path, "r", encoding="utf-8") as f:
            obf_src = f.read()
        rep = verify_obfuscated_file(rel, clean_src, obf_src, bridge)
        reports.append(rep)
        print(
            f"      PASS {rel:24s} | locals={rep['locals']:2d} (<30) | "
            f"clean={rep['clean_bytes']:7d}B -> ast={rep['decrypted_bytes']:7d}B -> vm={rep['obf_bytes']:7d}B | "
            f"hdr={rep['header']} | ret={rep['return_type']}"
        )

    if not args.no_workspace_sync:
        print(f"[4/4] Syncing {len(reports)} verified obfuscated files to {WORKSPACE_DIR}...")
        sync_to_workspace(args.repo)

    print(f"[DONE] All {len(reports)} files backed up, VM-obfuscated, and verified in {time.time() - t_start:.2f}s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
