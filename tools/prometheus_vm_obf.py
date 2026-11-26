#!/usr/bin/env python3
"""
Steph HUB - Prometheus Vmify Polymorphic Luau Dual-VM Obfuscator & Bundler Pipeline (v6.0)
==========================================================================================
1. Backs up clean unobfuscated Luau sources FIRST to:
   - C:\\Users\\LaptopAT\\AppData\\Local\\Real\\workspace\\stephhub-src\\ (clean tree + *.unobf.lua)
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt_unobf\\
   - C:\\Users\\LaptopAT\\.gemini\\antigravity\\scratch\\pet99bynhmt\\unobf\\ (gitignored)
2. Unified Payload Encryption (Shuffled Base85 + Xorshift32 with Ciphertext Feedback):
   - Packs Stage-1 VM instructions + Stage-2 serialized prototype hierarchy into ONE continuous
     binary stream with an encrypted 4-byte original byte-length header BEFORE encrypting.
   - Encrypts the unified binary stream with a 32-bit Xorshift32 + Ciphertext Feedback (CFB)
     nonlinear stream cipher (`state * 1664525 + c + 1013904223` mod 2^32, IEEE-754 exact `< 2^53`).
   - Encodes ciphertext using a per-build shuffled 85-character printable ASCII Base85 alphabet
     with cyclic digit rotation and zero padding characters, slicing into random-length segments
     only AFTER Base85 encoding.
3. Polymorphic `--target=luau` Bootstrap & Anti-Pre-Hook Seed Poisoning:
   - Removes Lua 5.1 bitwise fallback tables when `--target=luau`, passing shuffled native `bit32`
     and Luau runtime primitives + randomized dummy arguments into the outer IIFE.
   - Enters a Control-Flow Flattened (`while st ~= 0 do`) state machine immediately at top of IIFE
     with per-build randomized hex state constants and shuffled `if/elseif` branch ordering.
   - Verifies all C primitives via `debug.info(fn, "sla")`, pointer uniqueness, `coroutine.isyieldable`,
     and behavioral metamethod traps, silently poisoning the 32-bit cipher `seed` on any hook/tamper
     with zero diagnostic strings and zero `table.concat` calls across Stage-1 and Stage-2.
4. Stage-2 Polymorphic VM + Bounded <=8-Slot Ring-Buffered Lazy `K(idx)` Constant Pool:
   - Integrates with per-build Stage-2 opcode permutations, 4-group operand slot permutations,
     7 jump-safe fused super-instructions, and 4..6 decoy handlers.
   - Keeps string constants encrypted as byte arrays in `_enc_k`, lazily decrypting on demand via
     Xorshift32+CFB and chunked `string.char(unpack(...))` binary-tree reduction into an 8-slot FIFO ring.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import os
import random
import re
import shutil
import struct
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
FORBIDDEN_MAGIC_NUMS = {23575, 3257, 3008093, 8314969, 5441028}
FORBIDDEN_MAGIC_STRS = ("23575", "3257", "3008093", "8314969", "5441028")

# 90 safe single-byte printable ASCII characters (0x21..0x7E excluding `"`, `'`, `\`, `` ` ``)
# Each build samples & shuffles 85 distinct characters from this pool for padding-free Base85.
BASE85_SAFE_ASCII_POOL = "".join(
    chr(c) for c in range(33, 127) if chr(c) not in ('"', "'", "\\", "`")
)

PROBE_SYMBOLS = [
    "dump",              # 1
    "debug",             # 2
    "info",              # 3
    "getinfo",           # 4
    "iscclosure",        # 5
    "islclosure",        # 6
    "ishooked",          # 7
    "isfunctionhooked",  # 8
    "loadstring",        # 9
    "load",              # 10
    "short_src",         # 11
    "what",              # 12
    "linedefined",       # 13
    "concat",            # 14
]


# =============================================================================
# Luau Mock Runtime Bootstrap for Lua 5.1 (`lupa`) Test Harness
# =============================================================================
TEST_LUAU_ENV_LUA = r"""
local function _install_luau_test_env()
    local orig_debug = debug
    local orig_getinfo = debug and debug.getinfo
    local orig_dump = string.dump
    local orig_byte = string.byte
    local orig_sub = string.sub
    local orig_floor = math.floor
    local orig_select = select
    local orig_unpack = unpack or table.unpack
    local orig_type = type
    local orig_pcall = pcall
    local orig_coro_running = coroutine and coroutine.running

    local MOD32 = 4294967296
    local XOR8 = {}
    for i = 0, 255 do
        local row = {}
        XOR8[i] = row
        for j = 0, 255 do
            local r, p, a, b = 0, 1, i, j
            while a > 0 or b > 0 do
                local ra, rb = a % 2, b % 2
                if ra ~= rb then r = r + p end
                a = (a - ra) / 2
                b = (b - rb) / 2
                p = p * 2
            end
            row[j] = r
        end
    end
    local AND8 = {}
    for i = 0, 255 do
        local row = {}
        AND8[i] = row
        for j = 0, 255 do
            row[j] = ((i + j) - XOR8[i][j]) / 2
        end
    end
    local POW2 = {}
    for k = 0, 31 do POW2[k] = 2 ^ k end

    local function bxor2(a, b)
        a = orig_floor(a % MOD32)
        b = orig_floor(b % MOD32)
        local a0 = a % 256; a = (a - a0) / 256
        local a1 = a % 256; a = (a - a1) / 256
        local a2 = a % 256; local a3 = (a - a2) / 256
        local b0 = b % 256; b = (b - b0) / 256
        local b1 = b % 256; b = (b - b1) / 256
        local b2 = b % 256; local b3 = (b - b2) / 256
        return XOR8[a0][b0] + XOR8[a1][b1] * 256 + XOR8[a2][b2] * 65536 + XOR8[a3][b3] * 16777216
    end

    local function band2(a, b)
        a = orig_floor(a % MOD32)
        b = orig_floor(b % MOD32)
        if b == 255 then return a % 256 end
        if b == 4294967295 then return a end
        if a == 255 then return b % 256 end
        if a == 4294967295 then return b end
        local a0 = a % 256; a = (a - a0) / 256
        local a1 = a % 256; a = (a - a1) / 256
        local a2 = a % 256; local a3 = (a - a2) / 256
        local b0 = b % 256; b = (b - b0) / 256
        local b1 = b % 256; b = (b - b1) / 256
        local b2 = b % 256; local b3 = (b - b2) / 256
        return AND8[a0][b0] + AND8[a1][b1] * 256 + AND8[a2][b2] * 65536 + AND8[a3][b3] * 16777216
    end

    local function bor2(a, b)
        a = orig_floor(a % MOD32)
        b = orig_floor(b % MOD32)
        return (a + b) - band2(a, b)
    end

    local b_bxor = function(a, b, ...)
        if b == nil then
            if a == nil then return 0 end
            return orig_floor(a % MOD32)
        end
        local r = bxor2(a, b)
        local n = orig_select("#", ...)
        for i = 1, n do r = bxor2(r, orig_select(i, ...)) end
        return r
    end

    local b_band = function(a, b, ...)
        if b == nil then
            if a == nil then return 4294967295 end
            return orig_floor(a % MOD32)
        end
        local r = band2(a, b)
        local n = orig_select("#", ...)
        for i = 1, n do r = band2(r, orig_select(i, ...)) end
        return r
    end

    local b_bor = function(a, b, ...)
        if b == nil then
            if a == nil then return 0 end
            return orig_floor(a % MOD32)
        end
        local r = bor2(a, b)
        local n = orig_select("#", ...)
        for i = 1, n do r = bor2(r, orig_select(i, ...)) end
        return r
    end

    local b_bnot = function(a)
        return 4294967295 - orig_floor(a % MOD32)
    end

    local b_lshift = function(a, disp)
        a = orig_floor(a % MOD32)
        disp = orig_floor(disp)
        if disp < 0 then
            disp = -disp
            if disp >= 32 then return 0 end
            return orig_floor(a / POW2[disp])
        end
        if disp >= 32 then return 0 end
        return (a * POW2[disp]) % MOD32
    end

    local b_rshift = function(a, disp)
        a = orig_floor(a % MOD32)
        disp = orig_floor(disp)
        if disp < 0 then
            disp = -disp
            if disp >= 32 then return 0 end
            return (a * POW2[disp]) % MOD32
        end
        if disp >= 32 then return 0 end
        return orig_floor(a / POW2[disp])
    end

    bit32 = {
        bxor = b_bxor,
        band = b_band,
        bor = b_bor,
        bnot = b_bnot,
        lshift = b_lshift,
        rshift = b_rshift,
    }

    local c_isyieldable = function()
        if orig_coro_running then
            return orig_coro_running() ~= nil
        end
        return false
    end
    if orig_type(coroutine) == "table" then
        coroutine.isyieldable = c_isyieldable
    end

    local t_create = function(n, val)
        local out = {}
        if val ~= nil and orig_type(n) == "number" and n > 0 then
            for i = 1, n do out[i] = val end
        end
        return out
    end
    table.create = t_create
    table.unpack = table.unpack or orig_unpack

    local function parse_lua51_arity(fn)
        if not orig_dump then return 0, true end
        local ok, bin = orig_pcall(orig_dump, fn)
        if not ok or orig_type(bin) ~= "string" or #bin < 28 then
            return 0, true
        end
        local sz_int = orig_byte(bin, 8)
        local sz_size_t = orig_byte(bin, 9)
        local pos = 13
        local str_len, mult = 0, 1
        for i = 0, sz_size_t - 1 do
            str_len = str_len + orig_byte(bin, pos + i) * mult
            mult = mult * 256
        end
        pos = pos + sz_size_t + str_len + 2 * sz_int
        if pos + 2 > #bin then return 0, true end
        local numparams = orig_byte(bin, pos + 1)
        local is_vararg = (orig_byte(bin, pos + 2) ~= 0)
        return numparams, is_vararg
    end

    local host_c_set = {
        [b_bxor] = true, [b_band] = true, [b_bor] = true,
        [b_bnot] = true, [b_lshift] = true, [b_rshift] = true,
        [c_isyieldable] = true, [t_create] = true,
    }

    local sim_dump = function(fn, ...)
        if host_c_set[fn] then
            error("unable to dump given function", 0)
        end
        return orig_dump(fn, ...)
    end
    host_c_set[sim_dump] = true
    string.dump = sim_dump

    local sim_debug_info
    sim_debug_info = function(target, what)
        local gi = nil
        local is_c = false
        local fn_ref = nil
        if orig_type(target) == "number" then
            if orig_type(what) ~= "string" then return nil end
            gi = orig_getinfo and orig_getinfo(target + 1, "Snluf") or nil
            if not gi then return nil end
            fn_ref = gi.func
            is_c = (fn_ref and host_c_set[fn_ref]) or (gi.what == "C")
        elseif orig_type(target) == "function" then
            if orig_type(what) ~= "string" then
                error("invalid argument #2 to 'info' (string expected)", 0)
            end
            fn_ref = target
            if host_c_set[target] then
                is_c = true
            elseif orig_getinfo then
                gi = orig_getinfo(target, "Snlu")
                is_c = (gi and gi.what == "C") or false
            end
        else
            error("invalid argument #1 to 'info' (function or number expected)", 0)
        end

        local s, l, a, va, n
        if is_c then
            s, l, a, va, n = "[C]", -1, 0, true, (gi and gi.name) or ""
        else
            s = (gi and gi.short_src and gi.short_src ~= "[C]") and gi.short_src or "[string]"
            if orig_type(target) == "number" then
                l = (gi and gi.currentline and gi.currentline > 0) and gi.currentline
                    or ((gi and gi.linedefined and gi.linedefined > 0) and gi.linedefined or 1)
            else
                l = (gi and gi.linedefined and gi.linedefined > 0) and gi.linedefined or 1
            end
            a, va = parse_lua51_arity(fn_ref)
            n = (gi and gi.name) or ""
        end

        if what == "sl" then return s, l end
        if what == "sla" then return s, l, a, va end
        if what == "s" then return s end
        if what == "l" then return l end

        local out, k = {}, 0
        for i = 1, #what do
            local ch = orig_sub(what, i, i)
            if ch == "s" then k = k + 1; out[k] = s
            elseif ch == "l" then k = k + 1; out[k] = l
            elseif ch == "n" then k = k + 1; out[k] = n
            elseif ch == "f" then k = k + 1; out[k] = fn_ref
            elseif ch == "a" then
                k = k + 1; out[k] = a
                k = k + 1; out[k] = va
            end
        end
        return orig_unpack(out, 1, k)
    end
    host_c_set[sim_debug_info] = true

    debug = {
        info = sim_debug_info,
        traceback = orig_debug and orig_debug.traceback or nil,
    }
    return host_c_set, orig_debug
end
"""


def compute_untampered_seed(build_salt: int, num_funcs: int = 20) -> int:
    """
    Computes the exact 32-bit untampered sponge seed absorbed from:
      - Behavioral metamethod & C-dumper trap (`behav = 3257`, never emitted in code)
      - 2-arg Lua closure canary (`can_val = 42`)
      - Algebraic C-closure probes (`w_cclosure = 23575`, never emitted in code)
      - Function type signature (`tsig = 816`) & pointer uniqueness across `num_funcs` primitives
    Matches IEEE-754 float64 + Luau `bit32` transitions bit-for-bit (`< 2^53`).
    """
    behav = 3257
    can_val = 42
    w_cclosure = 23575
    tsig = 816  # ord('f') * len("function") = 102 * 8
    acc = (((build_salt ^ behav) * 1664525) + can_val * 257 + 1013904223) & 0xFFFFFFFF
    for i in range(1, num_funcs + 1):
        mix = (w_cclosure + tsig + i * 73) & 0xFFFFFF
        acc = (acc ^ ((acc << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
        acc = (acc ^ (acc >> 17)) & 0xFFFFFFFF
        acc = (acc ^ ((acc << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
        acc = (((acc ^ mix) * 1664525) + i * 8191 + 1013904223) & 0xFFFFFFFF
    return acc if acc != 0 else 0x6D2B79F5


def encrypt_xorshift32_cfb(plaintext: bytes, seed: int) -> bytes:
    """
    Nonlinear 32-bit Xorshift32 + Ciphertext Feedback (CFB) stream cipher.
    Exact bit-for-bit match with Luau `bit32`:
      state = bxor(state, lshift(state, 13))
      state = bxor(state, rshift(state, 17))
      state = bxor(state, lshift(state, 5))
      c = band(bxor(plain, state), 0xFF)
      state = band(state * 1664525 + c + 1013904223, 0xFFFFFFFF)
    Note: `0xFFFFFFFF * 1664525 + 255 + 1013904223 = 7,149,067,872,595,153 < 2^53`.
    """
    state = seed & 0xFFFFFFFF
    if state == 0:
        state = 0x6D2B79F5
    out = bytearray(len(plaintext))
    for i, p in enumerate(plaintext):
        state = (state ^ ((state << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
        state = (state ^ (state >> 17)) & 0xFFFFFFFF
        state = (state ^ ((state << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
        c = (p ^ state) & 0xFF
        out[i] = c
        state = (state * 1664525 + c + 1013904223) & 0xFFFFFFFF
    return bytes(out)


def decrypt_xorshift32_cfb(ciphertext: bytes, seed: int) -> bytes:
    """Inverse of `encrypt_xorshift32_cfb`."""
    state = seed & 0xFFFFFFFF
    if state == 0:
        state = 0x6D2B79F5
    out = bytearray(len(ciphertext))
    for i, c in enumerate(ciphertext):
        state = (state ^ ((state << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
        state = (state ^ (state >> 17)) & 0xFFFFFFFF
        state = (state ^ ((state << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
        p = (c ^ state) & 0xFF
        out[i] = p
        state = (state * 1664525 + c + 1013904223) & 0xFFFFFFFF
    return bytes(out)


def base85_encode(data: bytes, alpha85: str) -> str:
    """
    Padding-free Base85 encoder (4 binary bytes -> 5 printable ASCII chars) using
    per-build shuffled 85-char alphabet `alpha85` and cyclic block digit rotation.
    Pads final partial 1..3 bytes with zero bytes ONLY before the 4->5 tuple math;
    callers slice at the exact decrypted 4-byte length header.
    """
    if len(alpha85) != 85 or len(set(alpha85)) != 85:
        raise ValueError("alpha85 must contain exactly 85 unique ASCII characters")
    rem = len(data) % 4
    padded = data + (b"\x00" * (4 - rem) if rem else b"")
    out: List[str] = []
    blk_idx = 0
    for i in range(0, len(padded), 4):
        w = (padded[i] << 24) | (padded[i + 1] << 16) | (padded[i + 2] << 8) | padded[i + 3]
        d4 = w % 85
        w //= 85
        d3 = w % 85
        w //= 85
        d2 = w % 85
        w //= 85
        d1 = w % 85
        d0 = w // 85
        shift = blk_idx % 85
        out.append(
            alpha85[(d0 + shift) % 85]
            + alpha85[(d1 + shift) % 85]
            + alpha85[(d2 + shift) % 85]
            + alpha85[(d3 + shift) % 85]
            + alpha85[(d4 + shift) % 85]
        )
        blk_idx += 1
    return "".join(out)


def base85_decode(text: str, alpha85: str) -> bytes:
    """Inverse of `base85_encode`."""
    if len(text) % 5 != 0:
        raise ValueError("Base85 text length must be a multiple of 5")
    rev = {ch: idx for idx, ch in enumerate(alpha85)}
    out = bytearray()
    blk_idx = 0
    for i in range(0, len(text), 5):
        shift = blk_idx % 85
        d0 = (rev[text[i]] - shift) % 85
        d1 = (rev[text[i + 1]] - shift) % 85
        d2 = (rev[text[i + 2]] - shift) % 85
        d3 = (rev[text[i + 3]] - shift) % 85
        d4 = (rev[text[i + 4]] - shift) % 85
        w = ((((d0 * 85 + d1) * 85 + d2) * 85 + d3) * 85 + d4) & 0xFFFFFFFF
        out.append((w >> 24) & 0xFF)
        out.append((w >> 16) & 0xFF)
        out.append((w >> 8) & 0xFF)
        out.append(w & 0xFF)
        blk_idx += 1
    return bytes(out)


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
    Heuristically detects v6.0 / v5.0 / v4.0 (headerless single-line Dual-VM) and legacy v3.0
    obfuscated files so clean source backups are never overwritten by obfuscated code.
    """
    if LEGACY_VM_MARKER in source:
        return True
    stripped = source.strip()
    if not stripped:
        return False
    lines = [ln.strip() for ln in stripped.splitlines() if ln.strip()]
    if len(lines) <= 4 and any(
        ln.startswith("return(function(") or ln.startswith("return (function(")
        for ln in lines
    ):
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
            existing: List[Tuple[float, str]] = []
            for p in backup_candidates:
                try:
                    if os.path.isfile(p):
                        existing.append((os.path.getmtime(p), p))
                except PermissionError:
                    continue
            existing.sort(key=lambda item: item[0], reverse=True)
            for _, cand in existing:
                try:
                    with open(cand, "r", encoding="utf-8") as f:
                        cand_text = f.read()
                except PermissionError:
                    continue
                if not is_vm_obfuscated(cand_text):
                    clean_text = cand_text
                    break

        if clean_text is None:
            raise RuntimeError(f"Could not find clean unobfuscated source for {rel}!")

        clean_sources[rel] = clean_text

        local_dest = os.path.join(UNOBF_LOCAL_DIR, rel)
        os.makedirs(os.path.dirname(local_dest), exist_ok=True)
        with open(local_dest, "w", encoding="utf-8", newline="\n") as f:
            f.write(clean_text)

        try:
            ext_dest = os.path.join(UNOBF_EXTERNAL_DIR, rel)
            os.makedirs(os.path.dirname(ext_dest), exist_ok=True)
            with open(ext_dest, "w", encoding="utf-8", newline="\n") as f:
                f.write(clean_text)
        except PermissionError:
            pass

        try:
            ws_dest = os.path.join(WORKSPACE_SRC_DIR, rel)
            os.makedirs(os.path.dirname(ws_dest), exist_ok=True)
            with open(ws_dest, "w", encoding="utf-8", newline="\n") as f:
                f.write(clean_text)

            unobf_copy = os.path.join(
                WORKSPACE_SRC_DIR,
                rel[:-4] + ".unobf.lua" if rel.endswith(".lua") else rel + ".unobf.lua",
            )
            os.makedirs(os.path.dirname(unobf_copy), exist_ok=True)
            with open(unobf_copy, "w", encoding="utf-8", newline="\n") as f:
                f.write(clean_text)
        except PermissionError:
            pass

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
    Lua 5.1 lupa bridge to Prometheus LuaU AST Parser, Vmify Polymorphic Bytecode Compiler
    (with super-instructions, per-format operand permutations, & decoy handlers),
    Xorshift32+CFB Lazy Constant Serializer, and MangledShuffled Variable Renamer.
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

            local MOD32 = 4294967296
            local XOR8 = {{}}
            for i = 0, 255 do
                local row = {{}}
                XOR8[i] = row
                for j = 0, 255 do
                    local r, p, a, b = 0, 1, i, j
                    while a > 0 or b > 0 do
                        local ra, rb = a % 2, b % 2
                        if ra ~= rb then r = r + p end
                        a = (a - ra) / 2
                        b = (b - rb) / 2
                        p = p * 2
                    end
                    row[j] = r
                end
            end

            local function bxor32(a, b)
                a = math.floor(a % MOD32)
                b = math.floor(b % MOD32)
                local a0 = a % 256; a = (a - a0) / 256
                local a1 = a % 256; a = (a - a1) / 256
                local a2 = a % 256; local a3 = (a - a2) / 256
                local b0 = b % 256; b = (b - b0) / 256
                local b1 = b % 256; b = (b - b1) / 256
                local b2 = b % 256; local b3 = (b - b2) / 256
                return XOR8[a0][b0] + XOR8[a1][b1] * 256 + XOR8[a2][b2] * 65536 + XOR8[a3][b3] * 16777216
            end

            local function lshift32(a, k)
                return (math.floor(a % MOD32) * (2 ^ k)) % MOD32
            end

            local function rshift32(a, k)
                return math.floor(math.floor(a % MOD32) / (2 ^ k))
            end

            local function encryptConstXorshiftCfb(rawStr, ss, ksalt, idx)
                local st = (ss * 16777619 + ksalt * 65599 + idx * 2654435761 + 2463534242) % MOD32
                if st == 0 then st = 2463534242 end
                local sChars = {{}}
                for j = 1, #rawStr do
                    local b = string.byte(rawStr, j)
                    st = bxor32(st, lshift32(st, 13))
                    st = bxor32(st, rshift32(st, 17))
                    st = bxor32(st, lshift32(st, 5))
                    local encB = bxor32(b, st) % 256
                    st = (st * 1664525 + encB + 1013904223) % MOD32
                    sChars[j] = string.char(encB)
                end
                return table.concat(sChars)
            end

            local function writeVarint(out, n)
                n = math.floor(n)
                while n >= 128 do
                    out[#out + 1] = string.char((n % 128) + 128)
                    n = math.floor(n / 128)
                end
                out[#out + 1] = string.char(n)
            end

            local function serializeProto(proto, layout, out, strSalt, opSalt, ksalt256)
                out[#out + 1] = string.char(bxor32(proto.vararg and 1 or 0, opSalt % 2))
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
                            out[#out + 1] = encryptConstXorshiftCfb(s, strSalt, ksalt256, i)
                        end
                    elseif t == "string" then
                        out[#out + 1] = string.char(5)
                        writeVarint(out, #c)
                        out[#out + 1] = encryptConstXorshiftCfb(c, strSalt, ksalt256, i)
                    else
                        error("Unsupported constant type: " .. tostring(t))
                    end
                end

                local code = proto.code or {{}}
                writeVarint(out, #code)
                for i = 1, #code do
                    local enc = layout:encode(code[i])
                    local maskedOp = bxor32(enc[1], (i * 73 + opSalt) % 256)
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
                    out[#out + 1] = string.char(bxor32(mask, (i * 29 + strSalt) % 256))
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
                        (opSalt * 53 + i * 23 + 11) % 256,
                        ksalt256
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

            function compileStage2Vmify(code, filename, seed, chainKey256, ksalt256, baseStrSalt, baseOpSalt)
                math.randomseed(seed)
                local ast = Parser:new({{ LuaVersion = "LuaU" }}):parse(code, filename)
                analyzeBindings(ast)
                local layout = Layout.new(seed)
                local proto = Compiler:compile(ast)
                local totalInsns, totalConsts, totalProtos = countProtoStats(proto)

                local effStrSalt = (baseStrSalt + chainKey256) % 256
                local effOpSalt = (baseOpSalt + chainKey256) % 256
                local out = {{}}
                serializeProto(proto, layout, out, effStrSalt, effOpSalt, ksalt256)
                local blob = table.concat(out)
                local hex = (blob:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))

                local f = layout.fields
                local rawRt = Runtime.build(layout)
                -- Remove all diagnostic strings from VM runtime and bind Stage-2 opcode dispatch tree to runtime _ck!
                rawRt = rawRt:gsub("__UPV_ERR__%('unknown VM opcode: '%s*%.%.%s*tostring%(opcode%),%s*0%)", "return")
                rawRt = rawRt:gsub("nativeError%('unknown VM opcode: '%s*%.%.%s*tostring%(opcode%),%s*0%)", "return")
                rawRt = rawRt:gsub("if x == nil then __UPV_ERR__%([^%)]+%) end", "if x == nil then return end")
                rawRt = rawRt:gsub("if x == nil then nativeError%([^%)]+%) end", "if x == nil then return end")
                rawRt = rawRt:gsub('__UPV_SEL__%("#",%s*%.%.%.%)', "__UPV_SEL__(_sharp, ...)")
                rawRt = rawRt:gsub('nativeSelect%("#",%s*%.%.%.%)', "__UPV_SEL__(_sharp, ...)")
                rawRt = rawRt:gsub("if opcode == (%d+) then", function(n)
                    return "if opcode == _bxor(_ck, " .. tostring(bxor32(tonumber(n), chainKey256)) .. ") then"
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
return function(_blob, _ck, _ksalt, _bxor, _band, _lshift, _rshift, ...)
    local _sharp = __UPV_CHAR__(35)
    local _pos = 1
    local function _b2s(_arr, _len)
        if _len <= 0 then
            return __UPV_CHAR__()
        elseif _len <= 32 then
            return __UPV_CHAR__(__UPV_UNPACK__(_arr, 1, _len))
        end
        local _parts, _k = {{}}, 0
        for _i = 1, _len, 32 do
            local _j = _i + 31
            if _j > _len then _j = _len end
            _k = _k + 1
            _parts[_k] = __UPV_CHAR__(__UPV_UNPACK__(_arr, _i, _j))
        end
        while _k > 1 do
            local _nk = 0
            for _i = 1, _k, 2 do
                _nk = _nk + 1
                if _i + 1 <= _k then
                    _parts[_nk] = _parts[_i] .. _parts[_i + 1]
                else
                    _parts[_nk] = _parts[_i]
                end
            end
            _k = _nk
        end
        return _parts[1]
    end
    local function _rbyte()
        local _b = _blob[_pos] or 0
        _pos = _pos + 1
        return _b
    end
    local function _rvar()
        local _r, _m = 0, 1
        while true do
            local _b = _blob[_pos] or 0
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
                local _st = (_ss * 16777619 + _ksalt * 65599 + _i * 2654435761 + 2463534242) %% 4294967296
                if _st == 0 then _st = 2463534242 end
                for _j = 1, _l do
                    local _eb = _blob[_pos] or 0
                    _pos = _pos + 1
                    _st = _bxor(_st, _lshift(_st, 13))
                    _st = _bxor(_st, _rshift(_st, 17))
                    _st = _bxor(_st, _lshift(_st, 5))
                    _out[_j] = _band(_bxor(_eb, _st), 255)
                    _st = _band(_st * 1664525 + _eb + 1013904223, 4294967295)
                end
                _cons[_i] = __UPV_TONUM__(_b2s(_out, _l))
            else
                local _l = _rvar()
                local _eb_arr = {{}}
                for _j = 1, _l do
                    _eb_arr[_j] = _blob[_pos] or 0
                    _pos = _pos + 1
                end
                _enc_k[_i] = _eb_arr
            end
        end
        local _ring_k, _ring_v, _ring_pos = {{}}, {{}}, 1
        _p[%d] = function(_idx)
            local _s0, _k0 = _ss, _ksalt
            local _lit = _cons[_idx]
            if _lit ~= nil then return _lit end
            for _slot = 1, 8 do
                if _ring_k[_slot] == _idx and _ring_v[_slot] ~= nil then return _ring_v[_slot] end
            end
            local _raw = _enc_k[_idx]
            if not _raw then return nil end
            local _len = #_raw
            local _out = {{}}
            local _st = (_s0 * 16777619 + _k0 * 65599 + _idx * 2654435761 + 2463534242) %% 4294967296
            if _st == 0 then _st = 2463534242 end
            for _j = 1, _len do
                local _eb = _raw[_j]
                _st = _bxor(_st, _lshift(_st, 13))
                _st = _bxor(_st, _rshift(_st, 17))
                _st = _bxor(_st, _lshift(_st, 5))
                _out[_j] = _band(_bxor(_eb, _st), 255)
                _st = _band(_st * 1664525 + _eb + 1013904223, 4294967295)
            end
            local _val = _b2s(_out, _len)
            _ring_k[_ring_pos], _ring_v[_ring_pos] = _idx, _val
            _ring_pos = (_ring_pos %% 8) + 1
            return _val
        end
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
        ksalt_256: int,
        base_str_salt: int,
        base_op_salt: int,
    ) -> Tuple[bytes, str, int, int, int]:
        res = self._compile_s2_fn(code, filename, seed, chain_key_256, ksalt_256, base_str_salt, base_op_salt)
        return bytes.fromhex(res[0]), str(res[1]), int(res[2]), int(res[3]), int(res[4])

    def verify_luau_syntax(self, code: str, filename: str) -> Tuple[int, int]:
        res = self._parse_luau_fn(code, filename)
        if isinstance(res, tuple):
            return int(res[0]), int(res[1])
        return int(res), 0


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
    Never emits static `(const1 + const2)` arithmetic or forbidden magic constants.
    """
    for _ in range(32):
        idx = rng.randint(1, len(anchor_vals))
        ak = anchor_vals[idx - 1]
        mode = rng.randint(0, 2)
        if mode == 0 and 0 <= val <= 0xFFFFFFFF:
            mask = val ^ ak
            if mask not in FORBIDDEN_MAGIC_NUMS:
                return f"{v_bxor}({v_anchor}[{idx}],{mask})"
        diff = val - ak
        if abs(diff) not in FORBIDDEN_MAGIC_NUMS:
            if diff >= 0:
                return f"({v_anchor}[{idx}]+{diff})"
            else:
                return f"({v_anchor}[{idx}]-{-diff})"
    idx = 1
    ak = anchor_vals[0]
    diff = val - ak
    if diff >= 0:
        return f"({v_anchor}[{idx}]+{diff})"
    return f"({v_anchor}[{idx}]-{-diff})"


def generate_identifiers(count: int, rng: random.Random) -> List[str]:
    alphabet_first = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    alphabet_rest = alphabet_first + "0123456789"
    reserved = {
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "if", "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while", "continue",
        "yip", "seen", "acc", "idx", "tsig", "dup", "mix", "wref",
        "xpen", "scur", "dlen", "pos", "ins", "crc",
    }
    used = set(reserved)
    names: List[str] = []
    while len(names) < count:
        length = rng.randint(3, 4)
        cand = rng.choice(alphabet_first) + "".join(rng.choice(alphabet_rest) for _ in range(length - 1))
        if cand not in used:
            used.add(cand)
            names.append(cand)
    return names


def _slice_base85_random_segments(b85_text: str, rng: random.Random) -> List[str]:
    """
    Slices the ALREADY-ENCRYPTED, ALREADY-BASE85-ENCODED unified stream into 5..8
    random-length segments (each >= 68 chars) so no segment ever has individual padding tails.
    """
    total = len(b85_text)
    max_slices = min(8, max(4, total // 80))
    min_slices = min(5, max_slices)
    num_slices = rng.randint(min_slices, max_slices)
    min_seg = 68
    if total < num_slices * min_seg:
        num_slices = max(1, total // min_seg)
    if num_slices <= 1:
        return [b85_text]

    slack = total - num_slices * min_seg
    weights = [rng.randint(10, 100) for _ in range(num_slices)]
    w_sum = sum(weights)
    extras = [slack * w // w_sum for w in weights]
    rem = slack - sum(extras)
    for i in range(rem):
        extras[i % num_slices] += 1

    slices: List[str] = []
    pos = 0
    for i in range(num_slices):
        seg_len = min_seg + extras[i]
        slices.append(b85_text[pos : pos + seg_len])
        pos += seg_len
    return slices


def compile_polymorphic_vm(
    clean_source: str,
    rel_path: str,
    bridge: PrometheusBridge,
    file_seed: Optional[int] = None,
    target: str = "luau",
) -> str:
    """
    Compiles a Luau source file into v6.0 Dual-VM (`--target=luau` default or `--target=lua51`):
      - Single Unified Binary Stream (4-byte original length header + Stage-1 VM bytecode + Stage-2
        serialized Vmify prototype stream) encrypted in one pass via Xorshift32 + CFB.
      - Per-build shuffled 85-char printable ASCII Base85 encoding with zero padding tails,
        sliced into random-length segments only after Base85 encoding.
      - Shuffled Outer IIFE parameters + dummy arguments + immediate CFF `while st ~= 0 do` loop.
      - `debug.info` / pointer-uniqueness / `coroutine.isyieldable` / behavioral metamethod sponge
        that silently poisons the 32-bit Xorshift32+CFB seed on tampering, with zero `table.concat`.
    """
    if target not in ("luau", "lua51"):
        raise ValueError(f"Unsupported target: {target!r}")

    digest = hashlib.sha256((rel_path + f"::v6::{target}::" + clean_source).encode("utf-8")).digest()
    if file_seed is None:
        file_seed = int.from_bytes(digest[:4], "big") ^ 0x6A09E667
    rng = random.Random(file_seed)

    is_luau = target == "luau"
    num_sponge_funcs = 20 if is_luau else 14

    build_salt = rng.randint(100000, 0x7EFFFFFF)
    while build_salt in FORBIDDEN_MAGIC_NUMS:
        build_salt = rng.randint(100000, 0x7EFFFFFF)

    untampered_seed32 = compute_untampered_seed(build_salt, num_sponge_funcs)

    boot_lcg_a = rng.randint(25000, 95000) * 4 + 1
    boot_lcg_c = rng.randint(300000, 6000000) * 2 + 1
    anchor_vals: List[int] = []
    s_cur = untampered_seed32 % 16777216
    for i in range(1, 17):
        s_cur = (s_cur * boot_lcg_a + boot_lcg_c + i * 4099) % 16777216
        anchor_vals.append(s_cur)

    # Encode PROBE_SYMBOLS as an encrypted numeric byte array (zero string literals leaked)
    raw_probe_bytes = ("\0".join(PROBE_SYMBOLS) + "\0").encode("utf-8")
    probe_xor = rng.randint(17, 251)
    probe_step = rng.randint(3, 125) * 2 + 1
    enc_probe_nums = [
        ((b ^ probe_xor) + (i + 1) * probe_step) & 0xFF
        for i, b in enumerate(raw_probe_bytes)
    ]

    # Sample & shuffle 85 safe printable ASCII characters for padding-free Base85
    alpha85_list = rng.sample(list(BASE85_SAFE_ASCII_POOL), 85)
    rng.shuffle(alpha85_list)
    alpha85 = "".join(alpha85_list)
    alpha_mul = rng.randint(3, 251)
    alpha_add = rng.randint(7, 249)
    enc_alpha_nums = [
        (ord(ch) + (i + 1) * alpha_mul + alpha_add) & 0xFF
        for i, ch in enumerate(alpha85)
    ]

    # Compile Stage-2 Inner Vmify Custom Bytecode + Polymorphic Layout
    s2_seed = (file_seed & 0x7FFFFFFF) or 1337
    init_chain_key256 = anchor_vals[0] % 256
    init_ksalt256 = (anchor_vals[2] + rng.randint(17, 239)) % 256
    base_str_salt = rng.randint(17, 239)
    base_op_salt = rng.randint(19, 241)

    stage2_blob, minified_rt, _, _, _ = bridge.compile_stage2_vmify(
        clean_source,
        rel_path,
        s2_seed,
        init_chain_key256,
        init_ksalt256,
        base_str_salt,
        base_op_salt,
    )

    # Build Stage-1 Polymorphic VM Instructions (per-build randomized opcodes & operand slot permutation)
    s1_op_names = [
        "OP_INIT",
        "OP_MBA",
        "OP_MIX",
        "OP_SLICE_CRC",
        "OP_EXTRACT",
        "OP_EXEC",
        "OP_RET",
    ]
    s1_op_pool = rng.sample(range(13, 245), len(s1_op_names))
    s1_op_ids: Dict[str, int] = dict(zip(s1_op_names, s1_op_pool))

    s1_tuple_width = 6
    s1_slots = list(range(1, s1_tuple_width + 1))
    rng.shuffle(s1_slots)
    slot_op, slot_a, slot_b, slot_c, slot_d, slot_guard = s1_slots

    drawn_regs = rng.sample(range(15, 420), 8)
    reg_chain_crc, reg_mba, reg_mix, reg_s2_arr, reg_exec_res, reg_d1, reg_d2, reg_d3 = drawn_regs

    # Partition `stage2_blob` into 4..6 ranges for Stage-1 rolling FNV-1a verification
    s2_len = len(stage2_blob)
    num_crc_ranges = rng.randint(4, 6) if s2_len >= 64 else 2
    range_bounds: List[Tuple[int, int]] = []
    step_sz = max(1, (s2_len + num_crc_ranges - 1) // num_crc_ranges)
    for r_start in range(0, s2_len, step_sz):
        r_end = min(s2_len, r_start + step_sz)
        range_bounds.append((r_start, r_end))

    def fnv1a_24(segment: bytes) -> int:
        crc = 2166136261 % 16777216
        for b in segment:
            crc = ((crc ^ b) * 16777619) % 16777216
        return crc

    chain_init = anchor_vals[1]
    running_chain_crc = chain_init

    # Pre-plan instruction sequence so we know exact `num_s1_insns` and `s2_start_offset` in `plain_bytes`!
    range_order = list(range(len(range_bounds)))
    rng.shuffle(range_order)

    # Count exact Stage-1 instructions:
    # 1 (OP_INIT) + 1 (OP_MIX) + len(range_order) * 2 (OP_MBA + OP_SLICE_CRC) + (len(range_order)+1)//2 (OP_MIX) + 3 (OP_EXTRACT, OP_EXEC, OP_RET)
    planned_s1_count = 2 + len(range_order) * 2 + ((len(range_order) + 1) // 2) + 3

    # Layout inside `plain_bytes` (1-indexed in Lua):
    #   plain_bytes[1..4]   : 4-byte LE `orig_len = len(inner_bytes)`
    #   plain_bytes[5..6]   : 2-byte LE `num_s1_insns`
    #   plain_bytes[7 .. 6 + num_s1_insns*24] : `num_s1_insns` * 6 * uint32_le
    #   next 4 bytes        : 4-byte LE `s2_len`
    #   next `s2_len` bytes : `stage2_blob` (1-based start in `plain_bytes` is `s2_lua_start = 4 + 2 + num_s1_insns*24 + 4 + 1`)
    #   next 2 + decoy_len  : 2-byte LE `decoy_len` + random decoy tail bytes (ensures unified Base85 >= 680 chars)
    s2_lua_start = 11 + planned_s1_count * 24

    s1_insns: List[List[int]] = []

    def encode_s1(op_name: str, a: int, b: int, c: int, d: int, pre_crc: int) -> List[int]:
        arr = [0] * s1_tuple_width
        guard_val = rng.randint(300, 65000)
        while guard_val in FORBIDDEN_MAGIC_NUMS:
            guard_val = rng.randint(300, 65000)
        arr[slot_guard - 1] = guard_val
        arr[slot_op - 1] = s1_op_ids[op_name] ^ ((guard_val + (pre_crc % 256)) & 0xFF)
        arr[slot_a - 1] = a & 0xFFFFFFFF
        arr[slot_b - 1] = b & 0xFFFFFFFF
        arr[slot_c - 1] = c & 0xFFFFFFFF
        arr[slot_d - 1] = d & 0xFFFFFFFF
        return arr

    s1_insns.append(encode_s1("OP_INIT", reg_chain_crc, chain_init, reg_d1, rng.randint(50, 9999), 0))
    s1_insns.append(encode_s1("OP_MIX", reg_mix, rng.randint(50, 9999), rng.randint(50, 9999), rng.randint(1, 255), running_chain_crc))

    for step_idx, r_idx in enumerate(range_order):
        r_start, r_end = range_bounds[r_idx]
        seg_crc = fnv1a_24(stage2_blob[r_start:r_end])
        lua_lo = s2_lua_start + r_start
        lua_hi = s2_lua_start + r_end - 1
        m1 = rng.randint(20000, 16000000)
        m2 = rng.randint(20000, 16000000)
        chain_salt = rng.randint(1000, 900000)
        m3 = chain_salt ^ running_chain_crc ^ m1 ^ m2
        crc_delta = rng.randint(1000, 500000)
        next_crc = ((running_chain_crc * 65599 + chain_salt) % 16777216) ^ ((seg_crc + crc_delta) % 16777216)

        s1_insns.append(encode_s1("OP_MBA", reg_mba, m1, m2, m3, running_chain_crc))
        s1_insns.append(encode_s1("OP_SLICE_CRC", lua_lo, lua_hi, crc_delta, reg_mba, running_chain_crc))
        running_chain_crc = next_crc
        if step_idx % 2 == 0:
            s1_insns.append(encode_s1("OP_MIX", reg_mix, rng.randint(100, 9999), rng.randint(100, 9999), r_idx + 1, running_chain_crc))

    final_chain_crc = running_chain_crc
    ck_offset = (init_chain_key256 - (final_chain_crc % 256)) % 256
    ksalt_offset = (init_ksalt256 - (final_chain_crc % 256)) % 256

    s1_insns.append(encode_s1("OP_EXTRACT", reg_s2_arr, s2_lua_start, s2_len, 0, final_chain_crc))
    s1_insns.append(encode_s1("OP_EXEC", reg_exec_res, reg_s2_arr, ck_offset, ksalt_offset, final_chain_crc))
    s1_insns.append(encode_s1("OP_RET", reg_exec_res, 0, 0, 0, final_chain_crc))

    assert len(s1_insns) == planned_s1_count

    # Pack ONE unified binary stream BEFORE encrypting!
    inner_buf = bytearray()
    inner_buf.extend(struct.pack("<H", len(s1_insns)))
    for ins in s1_insns:
        inner_buf.extend(struct.pack("<6I", *ins))
    inner_buf.extend(struct.pack("<I", s2_len))
    inner_buf.extend(stage2_blob)

    min_inner_target = 560
    if len(inner_buf) + 2 < min_inner_target:
        decoy_len = (min_inner_target - len(inner_buf)) + rng.randint(16, 64)
    else:
        decoy_len = rng.randint(16, 48)
    inner_buf.extend(struct.pack("<H", decoy_len))
    inner_buf.extend(bytes(rng.randint(0, 255) for _ in range(decoy_len)))

    unified_plaintext = struct.pack("<I", len(inner_buf)) + bytes(inner_buf)
    unified_ciphertext = encrypt_xorshift32_cfb(unified_plaintext, untampered_seed32)
    unified_b85 = base85_encode(unified_ciphertext, alpha85)
    b85_slices = _slice_base85_random_segments(unified_b85, rng)

    # Permute slice storage order in Lua table so slices aren't even stored sequentially
    slice_perm = list(range(len(b85_slices)))
    rng.shuffle(slice_perm)
    stored_slices = [b85_slices[p] for p in slice_perm]
    slice_read_order = [slice_perm.index(i) + 1 for i in range(len(b85_slices))]

    # Generate randomized identifiers (strictly keeping outer scope local count < 35!)
    ids = generate_identifiers(85, rng)
    id_it = iter(ids)

    v_bxor = next(id_it)
    v_band = next(id_it)
    v_lshift = next(id_it)
    v_rshift = next(id_it)
    v_byte = next(id_it)
    v_char = next(id_it)
    v_sub = next(id_it)
    v_pcall = next(id_it)
    v_type = next(id_it)
    v_tonum = next(id_it)
    v_sel = next(id_it)
    v_unpack = next(id_it)
    v_dbginfo = next(id_it)
    v_isyield = next(id_it)
    v_mflr = next(id_it)
    v_err = next(id_it)
    v_smt = next(id_it)
    v_gmt = next(id_it)
    v_rset = next(id_it)
    v_rget = next(id_it)
    v_getfenv = next(id_it)
    v_setfenv = next(id_it)
    v_str_lib = next(id_it)
    v_tbl_lib = next(id_it)
    v_args = next(id_it)
    v_dum1 = next(id_it)
    v_dum2 = next(id_it)
    v_dum3 = next(id_it)

    # Outer function locals (ONLY 3 locals declared at top of outer IIFE!)
    v_st = next(id_it)
    v_ctx = next(id_it)
    v_anchor = next(id_it)

    # Short-lived branch-scoped locals (reused cleanly inside child blocks so scope stays tiny!)
    b_t1 = next(id_it)
    b_t2 = next(id_it)
    b_t3 = next(id_it)
    b_t4 = next(id_it)
    b_t5 = next(id_it)
    b_t6 = next(id_it)
    b_t7 = next(id_it)
    b_t8 = next(id_it)
    b_i = next(id_it)
    b_j = next(id_it)
    b_k = next(id_it)
    b_r = next(id_it)

    # Bind Stage-2 inner lexical upvalue placeholders directly to verified outer IIFE parameters!
    upv_map = {
        "__UPV_TONUM__": v_tonum,
        "__UPV_SEL__": v_sel,
        "__UPV_MFLR__": v_mflr,
        "__UPV_ERR__": v_err,
        "__UPV_UNPACK__": v_unpack,
        "__UPV_GETFENV__": v_getfenv,
        "__UPV_SETFENV__": v_setfenv,
        "__UPV_CHAR__": v_char,
    }
    for placeholder, outer_var in upv_map.items():
        minified_rt = minified_rt.replace(placeholder, outer_var)

    def rint(val: int) -> str:
        return make_runtime_int(val, rng, v_anchor, anchor_vals, v_bxor)

    # Randomized integer field keys in `v_ctx`
    ctx_keys = rng.sample([k for k in range(11, 990) if k not in FORBIDDEN_MAGIC_NUMS], 9)
    k_seed, k_plain, k_plen, k_s1code, k_reg, k_pc, k_vmfn, k_argc, k_insn = ctx_keys

    cnt_key = rng.randint(1024, 999999)
    while cnt_key in FORBIDDEN_MAGIC_NUMS:
        cnt_key = rng.randint(1024, 999999)

    # Choose 6 distinct randomized hex CFF states (`0x1001 .. 0xFFFE`)
    cff_pool = [s for s in rng.sample(range(0x1021, 0xFEEE), 12) if s not in FORBIDDEN_MAGIC_NUMS]
    cff_probe, cff_b85_cfb, cff_unpack_s1, cff_s1_fetch, cff_s1_disp, cff_decoy = cff_pool[:6]

    # Build shuffled outer IIFE parameter & call-argument pairs + 2..3 randomized dummy args
    if is_luau:
        iife_pairs: List[Tuple[str, str]] = [
            (v_bxor, "bit32.bxor"),
            (v_band, "bit32.band"),
            (v_lshift, "bit32.lshift"),
            (v_rshift, "bit32.rshift"),
            (v_byte, "string.byte"),
            (v_char, "string.char"),
            (v_sub, "string.sub"),
            (v_pcall, "pcall"),
            (v_type, "type"),
            (v_tonum, "tonumber"),
            (v_sel, "select"),
            (v_unpack, "unpack or table.unpack"),
            (v_dbginfo, "debug and debug.info"),
            (v_isyield, "coroutine and coroutine.isyieldable"),
            (v_mflr, "math.floor"),
            (v_err, "error"),
            (v_smt, "setmetatable"),
            (v_gmt, "getmetatable"),
            (v_rset, "rawset"),
            (v_rget, "rawget"),
            (v_getfenv, "getfenv"),
            (v_setfenv, "setfenv"),
            (v_str_lib, "string"),
            (v_tbl_lib, "table"),
            (v_args, "{...}"),
        ]
    else:
        iife_pairs = [
            (v_bxor, "bit32 and bit32.bxor"),
            (v_band, "bit32 and bit32.band"),
            (v_lshift, "bit32 and bit32.lshift"),
            (v_rshift, "bit32 and bit32.rshift"),
            (v_byte, "string.byte"),
            (v_char, "string.char"),
            (v_sub, "string.sub"),
            (v_pcall, "pcall"),
            (v_type, "type"),
            (v_tonum, "tonumber"),
            (v_sel, "select"),
            (v_unpack, "unpack or table.unpack"),
            (v_dbginfo, "debug and debug.info"),
            (v_isyield, "coroutine and coroutine.isyieldable"),
            (v_mflr, "math and math.floor"),
            (v_err, "error"),
            (v_smt, "setmetatable"),
            (v_gmt, "getmetatable"),
            (v_rset, "rawset"),
            (v_rget, "rawget"),
            (v_getfenv, "getfenv"),
            (v_setfenv, "setfenv"),
            (v_str_lib, "string"),
            (v_tbl_lib, "table"),
            (v_args, "{...}"),
        ]

    dummy_candidates = [
        "math.ldexp",
        "math.frexp",
        "math.abs",
        "math.ceil",
        "coroutine and coroutine.running",
        str(rng.randint(13, 991)),
        str(rng.randint(1025, 8191)),
    ]
    rng.shuffle(dummy_candidates)
    num_dummies = rng.randint(2, 3)
    dummy_vars = [v_dum1, v_dum2, v_dum3][:num_dummies]
    for dv, d_expr in zip(dummy_vars, dummy_candidates[:num_dummies]):
        iife_pairs.append((dv, d_expr))

    rng.shuffle(iife_pairs)
    iife_params_str = ",".join(p for p, _ in iife_pairs)
    iife_args_str = ",".join(a for _, a in iife_pairs)

    # Optional Lua 5.1 bitwise fallback ONLY when `--target=lua51` (100% absent on `--target=luau`!)
    lua51_fallback_stmt = ""
    if not is_luau:
        lua51_fallback_stmt = (
            f"if not {v_bxor} then "
            f"local {b_t1}={{}};"
            f"for {b_i}=0,255 do local {b_t2}={{}};{b_t1}[{b_i}]={b_t2};"
            f"for {b_j}=0,255 do local {b_r},{b_k},{b_t3},{b_t4}=0,1,{b_i},{b_j};"
            f"while {b_t3}>0 or {b_t4}>0 do local {b_t5},{b_t6}={b_t3}%2,{b_t4}%2;"
            f"if {b_t5}~={b_t6} then {b_r}={b_r}+{b_k} end;"
            f"{b_t3}=({b_t3}-{b_t5})/2;{b_t4}=({b_t4}-{b_t6})/2;{b_k}={b_k}*2 end;"
            f"{b_t2}[{b_j}]={b_r} end end;"
            f"{v_bxor}=function({b_i},{b_j})"
            f"{b_i}={v_mflr}({b_i}%4294967296);{b_j}={v_mflr}({b_j}%4294967296);"
            f"local {b_r},{b_k}=0,1;"
            f"while {b_i}>0 or {b_j}>0 do local {b_t3},{b_t4}={b_i}%256,{b_j}%256;"
            f"{b_r}={b_r}+{b_t1}[{b_t3}][{b_t4}]*{b_k};"
            f"{b_i}=({b_i}-{b_t3})/256;{b_j}=({b_j}-{b_t4})/256;{b_k}={b_k}*256 end;"
            f"return {b_r} end;"
            f"{v_band}=function({b_i},{b_j})"
            f"{b_i}={v_mflr}({b_i}%4294967296);{b_j}={v_mflr}({b_j}%4294967296);"
            f"return(({b_i}+{b_j})-{v_bxor}({b_i},{b_j}))/2 end;"
            f"{v_lshift}=function({b_i},{b_j})return({v_mflr}({b_i}%4294967296)*(2^{b_j}))%4294967296 end;"
            f"{v_rshift}=function({b_i},{b_j})return {v_mflr}({v_mflr}({b_i}%4294967296)/(2^{b_j}))end;"
            f"end;"
        )

    probe_nums_str = "{" + ",".join(str(x) for x in enc_probe_nums) + "}"
    alpha_nums_str = "{" + ",".join(str(x) for x in enc_alpha_nums) + "}"
    slices_tbl_str = "{" + ",".join(f'"{s}"' for s in stored_slices) + "}"
    slice_ord_str = "{" + ",".join(str(idx) for idx in slice_read_order) + "}"

    yip_list_str = (
        f"{{{v_type},{v_pcall},{v_byte},{v_char},{v_sub},{v_tonum},{v_sel},{v_unpack},"
        f"{v_smt},{v_gmt},{v_rset},{v_rget},{v_mflr},{v_err},"
        f"{v_bxor},{v_band},{v_lshift},{v_rshift},{v_dbginfo},{v_isyield}}}"
        if is_luau
        else f"{{{v_type},{v_pcall},{v_byte},{v_char},{v_sub},{v_tonum},{v_sel},{v_unpack},"
        f"{v_smt},{v_gmt},{v_rset},{v_rget},{v_mflr},{v_err}}}"
    )

    # Branch 1 (`cff_probe`): Decode probe symbols via chunked string.char(unpack(...)), run behavioral
    # metamethod trap + `debug.info` / `isyieldable` / pointer-uniqueness sponge -> seed & `v_anchor[1..16]`!
    # Zero error strings, zero early abort — any tamper silently perturbs `acc` (`v_ctx[k_seed]`)!
    isyield_check_lua = (
        f"local {b_t7},{b_t8}=false,nil;"
        f"if {v_type}({v_isyield})=={v_type}({v_pcall})then {b_t7},{b_t8}={v_pcall}({v_isyield})end;"
        f"local {b_k}=(not {b_t7} or {v_type}({b_t8})~={v_type}(true))and 733 or 0;"
        if is_luau
        else f"local {b_k}=0;"
    )

    branch_probe = (
        f"{lua51_fallback_stmt}"
        f"local {b_t1},{b_t2},{b_t3},{b_t4}={{}},{{}},0,{probe_nums_str};"
        f"for {b_i}=1,#{b_t4} do "
        f"local {b_r}={v_bxor}(({b_t4}[{b_i}]-{b_i}*{probe_step})%256,{probe_xor});"
        f"if {b_r}==0 then {b_t1}[#{b_t1}+1]={v_char}({v_unpack}({b_t2},1,{b_t3}));{b_t2},{b_t3}={{}},0 "
        f"else {b_t3}={b_t3}+1;{b_t2}[{b_t3}]={b_r} end end;"
        f"local {b_t5}=0;"
        f"local {b_t6}={v_smt}({{}},{{"
        f"__metatable=211,"
        f"__index=function(_,{b_j})local {b_r}={v_type}({b_j})=={v_type}(1)and {b_j} or 19;{b_t5}={b_t5}+{b_r};return {b_r}*3+1 end,"
        f"__newindex=function(){b_t5}={b_t5}+97 end"
        f"}});"
        f"{b_t2}={b_t6}[5];{v_rset}({b_t6},5,42);{b_t3}={b_t6}[5];"
        f"{b_t4}=({b_t2}*131+{b_t3}*17+({v_rget}({b_t6},9,nil)==nil and 91 or 0)+({v_type}({v_gmt}({b_t6}))=={v_type}(1)and {v_gmt}({b_t6})or 0)+{b_t5}*29)*({v_pcall}({v_smt},{b_t6},{{}})and 3 or 1);"
        f"{isyield_check_lua}"
        f"local {b_r}=({v_type}({v_getfenv})=={v_type}({v_pcall})and {v_getfenv}())or _ENV or _G;"
        f"{b_t5}={v_type}({v_str_lib})=={v_type}({v_ctx})and {v_str_lib}[{b_t1}[1]];"
        f"{b_t6}={v_type}({b_r}[{b_t1}[2]])=={v_type}({v_ctx})and {b_r}[{b_t1}[2]];"
        f"{b_t2}={v_dbginfo} or({b_t6} and {v_type}({b_t6}[{b_t1}[3]])=={v_type}({v_pcall})and {b_t6}[{b_t1}[3]]);"
        f"{b_t3}={b_t6} and {v_type}({b_t6}[{b_t1}[4]])=={v_type}({v_pcall})and {b_t6}[{b_t1}[4]];"
        f"local {b_i}=function({b_j},{b_t6})return {b_j} end;"
        f"local {b_j}=function({b_t6})"
        f"if {v_type}({b_t2})=={v_type}({v_pcall})then "
        f"local s1,s2,s3,s4,s5={v_pcall}({b_t2},{b_t6},{v_char}(115,108,97));"
        f"if s1 and {v_type}(s2)=={v_type}({v_char}(65))and #s2>=2 and {v_type}(s3)=={v_type}(1)and {v_type}(s4)=={v_type}(1)then "
        f"return {v_byte}(s2,1)*256+{v_byte}(s2,2)*4+(#s2-s3)+s4*31+(s5 and 7 or 0)+(s3<0 and 0 or 513)end;"
        f"return 0 "
        f"elseif {b_t3} then "
        f"local s1,s2={v_pcall}({b_t3},{b_t6},{v_char}(83));"
        f"if s1 and {v_type}(s2)=={v_type}({v_ctx})then "
        f"local p1,p2,p3=s2[{b_t1}[11]],s2[{b_t1}[12]],s2[{b_t1}[13]];"
        f"if {v_type}(p1)=={v_type}({v_char}(65))and #p1>=2 and {v_type}(p2)=={v_type}({v_char}(65))and #p2>=1 and {v_type}(p3)=={v_type}(1)then "
        f"return {v_byte}(p1,1)*256+{v_byte}(p2,1)*4+(#p1-p3)+#p2*7+(p3<0 and 0 or 513)end end;"
        f"return 0 "
        f"elseif {v_type}({b_t5})=={v_type}({v_pcall})then "
        f"local s1,s2={v_pcall}({b_t5},{b_i});"
        f"if s1 and {v_type}(s2)=={v_type}({v_char}(65))and #s2>=1 then "
        f"return(not {v_pcall}({b_t5},{b_t6}))and({v_byte}(s2,1)*873+4)or 0 end;"
        f"return 0 else return 0 end end;"
        f"{b_t6}=0;"
        f"if {v_type}({b_t2})=={v_type}({v_pcall})then "
        f"local s1,_,s3,s4,s5={v_pcall}({b_t2},{b_i},{v_char}(115,108,97));"
        f"if s1 and {v_type}(s3)=={v_type}(1)and {v_type}(s4)=={v_type}(1)then {b_t6}=(s3>0 and 11 or 0)+s4*13+(s5 and 99 or 5)end "
        f"elseif {b_t3} then "
        f"local s1,s2={v_pcall}({b_t3},{b_i},{v_char}(83));"
        f"if s1 and {v_type}(s2)=={v_type}({v_ctx})then local p2,p3=s2[{b_t1}[12]],s2[{b_t1}[13]];"
        f"if {v_type}(p2)=={v_type}({v_char}(65))and #p2>=1 and {v_type}(p3)=={v_type}(1)then {b_t6}={v_byte}(p2,1)-#p2*15+(p3>0 and 11 or 0)end end "
        f"elseif {v_type}({b_t5})=={v_type}({v_pcall})then "
        f"local s1,s2={v_pcall}({b_t5},{b_i});if s1 and {v_type}(s2)=={v_type}({v_char}(65))and #s2>=1 then {b_t6}={v_byte}(s2,1)+15 end end;"
        f"do "
        f"local yip,seen={yip_list_str},{{}};"
        f"local eb={v_type}({b_r}[{b_t1}[5]])=={v_type}({v_pcall})and {b_r}[{b_t1}[5]];"
        f"local w1={v_type}({b_r}[{b_t1}[6]])=={v_type}({v_pcall})and {b_r}[{b_t1}[6]];"
        f"local r0=({v_type}({b_r}[{b_t1}[7]])=={v_type}({v_pcall})and {b_r}[{b_t1}[7]])or({v_type}({b_r}[{b_t1}[8]])=={v_type}({v_pcall})and {b_r}[{b_t1}[8]]);"
        f"local raw_ls={b_r}[{b_t1}[9]]~=nil and {b_r}[{b_t1}[9]]or {b_r}[{b_t1}[10]];"
        f"local raw_tc={v_type}({v_tbl_lib})=={v_type}({v_ctx})and {v_rget}({v_tbl_lib},{b_t1}[14])or nil;"
        f"local acc={v_band}({v_bxor}({build_salt},{b_t4})*1664525+{b_t6}*257+{b_k}+1013904223,4294967295);"
        f"for idx=1,#yip do "
        f"local fn=yip[idx];local tn={v_type}(fn);"
        f"local tsig=(#tn>0 and {v_byte}(tn,1)or 0)*#tn;"
        f"local dup=seen[fn]and 911 or 0;"
        f"if fn~=nil then seen[fn]=idx end;"
        f"local wp=(tn=={v_type}({v_pcall}))and {b_j}(fn)or 0;"
        f"local ex=0;"
        f"if eb then ex=ex+{v_bxor}((eb(fn)and 173 or 41)+(eb({b_i})and 88 or 24),197)+{v_bxor}({b_j}(eb),wp)end;"
        f"if w1 then ex=ex+{v_bxor}((w1(fn)and 91 or 130)+(w1({b_i})and 67 or 19),197)+{v_bxor}({b_j}(w1),wp)end;"
        f"if r0 then ex=ex+{v_bxor}((r0(fn)and 53 or 144)+(r0({b_i})and 112 or 53),197)+{v_bxor}({b_j}(r0),wp)end;"
        f"local mix={v_band}({v_bxor}(wp+tsig+idx*73,ex+dup),16777215);"
        f"acc={v_bxor}(acc,{v_lshift}(acc,13));acc={v_bxor}(acc,{v_rshift}(acc,17));acc={v_bxor}(acc,{v_lshift}(acc,5));"
        f"acc={v_band}({v_bxor}(acc,mix)*1664525+idx*8191+1013904223,4294967295)end;"
        f"local wref={b_j}({v_pcall});local xpen=0;"
        f"if raw_ls~=nil then if {v_type}(raw_ls)~={v_type}({v_pcall})then xpen=xpen+541 else xpen=xpen+(seen[raw_ls]and 911 or 0)+{v_bxor}({b_j}(raw_ls),wref);seen[raw_ls]=98 end end;"
        f"if raw_tc~=nil then if {v_type}(raw_tc)~={v_type}({v_pcall})then xpen=xpen+677 else xpen=xpen+(seen[raw_tc]and 911 or 0)+{v_bxor}({b_j}(raw_tc),wref);seen[raw_tc]=99 end end;"
        f"acc={v_band}(acc+xpen,4294967295);"
        f"if acc==0 then acc=1831565813 end;"
        f"{v_ctx}[{k_seed}]=acc;"
        f"local scur=acc%16777216;"
        f"for idx=1,16 do scur=(scur*{boot_lcg_a}+{boot_lcg_c}+idx*4099)%16777216;{v_anchor}[idx]=scur end;"
        f"{v_ctx}[{k_argc}]={v_sel}({v_char}(35),{v_unpack}({v_args}));"
        f"end;"
        f"{v_st}=0x{cff_b85_cfb:X}"
    )

    # Branch 2 (`cff_b85_cfb`): Reconstruct shuffled 85-char Base85 lookup map and stream-decode
    # random-length slices directly through 32-bit Xorshift32 + CFB (`1664525`, `1013904223`)!
    branch_b85_cfb = (
        f"local {b_t1},{b_t2},{b_t3},{b_t4}={{}},{alpha_nums_str},{slices_tbl_str},{slice_ord_str};"
        f"for {b_i}=1,85 do {b_t1}[({b_t2}[{b_i}]-{b_i}*{alpha_mul}-{alpha_add})%256]={b_i}-1 end;"
        f"local {b_t5},{b_t6},{b_t7},{b_t8}={{}},0,{v_ctx}[{k_seed}],0;"
        f"local {b_k},{b_r}=0,0;"
        f"for {b_i}=1,#{b_t4} do "
        f"local sl={b_t3}[{b_t4}[{b_i}]];"
        f"for {b_j}=1,#sl do "
        f"local dv=(({b_t1}[{v_byte}(sl,{b_j})]or 0)-({b_r}%85))%85;"
        f"{b_k}={b_k}*85+dv;{b_t8}={b_t8}+1;"
        f"if {b_t8}==5 then "
        f"local c0,c1,c2,c3={v_band}({v_rshift}({b_k},24),255),{v_band}({v_rshift}({b_k},16),255),{v_band}({v_rshift}({b_k},8),255),{v_band}({b_k},255);"
        f"{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},13));{b_t7}={v_bxor}({b_t7},{v_rshift}({b_t7},17));{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},5));"
        f"{b_t6}={b_t6}+1;{b_t5}[{b_t6}]={v_band}({v_bxor}(c0,{b_t7}),255);{b_t7}={v_band}({b_t7}*1664525+c0+1013904223,4294967295);"
        f"{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},13));{b_t7}={v_bxor}({b_t7},{v_rshift}({b_t7},17));{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},5));"
        f"{b_t6}={b_t6}+1;{b_t5}[{b_t6}]={v_band}({v_bxor}(c1,{b_t7}),255);{b_t7}={v_band}({b_t7}*1664525+c1+1013904223,4294967295);"
        f"{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},13));{b_t7}={v_bxor}({b_t7},{v_rshift}({b_t7},17));{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},5));"
        f"{b_t6}={b_t6}+1;{b_t5}[{b_t6}]={v_band}({v_bxor}(c2,{b_t7}),255);{b_t7}={v_band}({b_t7}*1664525+c2+1013904223,4294967295);"
        f"{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},13));{b_t7}={v_bxor}({b_t7},{v_rshift}({b_t7},17));{b_t7}={v_bxor}({b_t7},{v_lshift}({b_t7},5));"
        f"{b_t6}={b_t6}+1;{b_t5}[{b_t6}]={v_band}({v_bxor}(c3,{b_t7}),255);{b_t7}={v_band}({b_t7}*1664525+c3+1013904223,4294967295);"
        f"{b_k},{b_t8},{b_r}=0,0,{b_r}+1 "
        f"end end end;"
        f"{v_ctx}[{k_plain}],{v_ctx}[{k_plen}]={b_t5},{b_t6};"
        f"{v_st}=0x{cff_unpack_s1:X}"
    )

    # Branch 3 (`cff_unpack_s1`): Validate 4-byte original byte-length header inside decrypted stream
    # and unpack Stage-1 VM bytecode instructions + Stage-2 VM runner closure!
    # If `seed` was poisoned by anti-hook, header consistency fails organically -> `s1code = {}` -> exits returning `nil`!
    branch_unpack_s1 = (
        f"local {b_t1},{b_t2},{b_t3}={v_ctx}[{k_plain}],{v_ctx}[{k_plen}],{{}};"
        f"if {b_t2}>=16 then "
        f"local {b_t4}={b_t1}[1]+{b_t1}[2]*256+{b_t1}[3]*65536+{b_t1}[4]*16777216;"
        f"if {b_t4}>=12 and {b_t4}+4<={b_t2} and {b_t4}+7>={b_t2} then "
        f"local {b_t5}={b_t1}[5]+{b_t1}[6]*256;"
        f"local {b_t6}=2+{b_t5}*24;"
        f"if {b_t6}+6<={b_t4} then "
        f"local {b_t7}={b_t1}[4+{b_t6}+1]+{b_t1}[4+{b_t6}+2]*256+{b_t1}[4+{b_t6}+3]*65536+{b_t1}[4+{b_t6}+4]*16777216;"
        f"local {b_t8}=4+{b_t6}+4+{b_t7};"
        f"if {b_t8}+2<=4+{b_t4} then "
        f"local dlen={b_t1}[{b_t8}+1]+{b_t1}[{b_t8}+2]*256;"
        f"if {b_t6}+4+{b_t7}+2+dlen=={b_t4} then "
        f"local pos=7;"
        f"for {b_i}=1,{b_t5} do "
        f"local ins={{}};"
        f"for {b_j}=1,6 do "
        f"ins[{b_j}]={b_t1}[pos]+{b_t1}[pos+1]*256+{b_t1}[pos+2]*65536+{b_t1}[pos+3]*16777216;"
        f"pos=pos+4 end;"
        f"{b_t3}[{b_i}]=ins end "
        f"end end end end end;"
        f"{v_ctx}[{k_s1code}],{v_ctx}[{k_reg}],{v_ctx}[{k_pc}],{v_ctx}[{k_vmfn}]={b_t3},{{}},1,{minified_rt};"
        f"{v_st}=0x{cff_s1_fetch:X}"
    )

    # Branch 4 (`cff_s1_fetch`): Stage-1 Fetch
    branch_s1_fetch = (
        f"local {b_t1}={v_ctx}[{k_s1code}][{v_ctx}[{k_pc}]];"
        f"if not {b_t1} then {v_st}=0 else {v_ctx}[{k_insn}]={b_t1};{v_st}=0x{cff_s1_disp:X} end"
    )

    # Stage-1 Polymorphic Handlers (inside Branch 5 `cff_s1_disp`)
    # `b_t1` = `R` (`v_ctx[k_reg]`), `b_t2` = `op`, `b_t3..b_t6` = `A, B, C, D` (unpacked from permuted slots!)
    s1_handlers: Dict[int, str] = {
        s1_op_ids["OP_INIT"]: (
            f"{b_t1}[{b_t3}]={b_t4};{b_t1}[{b_t5}]={b_t6}"
        ),
        s1_op_ids["OP_MBA"]: (
            f"local m=({b_t4}+{b_t5})-2*{v_band}({b_t4},{b_t5});"
            f"{b_t1}[{b_t3}]={v_bxor}({v_bxor}(m,{b_t6}),{b_t1}[{rint(reg_chain_crc)}])"
        ),
        s1_op_ids["OP_MIX"]: (
            f"{b_t1}[{b_t3}]=({b_t4}*37+{b_t5}+{b_t6})%65536"
        ),
        s1_op_ids["OP_SLICE_CRC"]: (
            f"local pb,crc={v_ctx}[{k_plain}],{rint(2166136261 % 16777216)};"
            f"for {b_i}={b_t3},{b_t4} do crc=({v_bxor}(crc,pb[{b_i}]or 0)*16777619)%16777216 end;"
            f"{b_t1}[{rint(reg_chain_crc)}]={v_bxor}(({b_t1}[{rint(reg_chain_crc)}]*65599+{b_t1}[{b_t6}])%16777216,(crc+{b_t5})%16777216)"
        ),
        s1_op_ids["OP_EXTRACT"]: (
            f"local pb,s2,k={v_ctx}[{k_plain}],{{}},0;"
            f"for {b_i}={b_t4},{b_t4}+{b_t5}-1 do k=k+1;s2[k]=pb[{b_i}]or 0 end;"
            f"{v_ctx}[{k_plain}]=nil;{b_t1}[{b_t3}]=s2"
        ),
        s1_op_ids["OP_EXEC"]: (
            f"local s2={b_t1}[{b_t4}];{b_t1}[{b_t4}]=nil;"
            f"local ck=({b_t1}[{rint(reg_chain_crc)}]%256+{b_t5})%256;"
            f"local ks=({b_t1}[{rint(reg_chain_crc)}]%256+{b_t6})%256;"
            f"local pk=function(...)return{{[{rint(cnt_key)}]={v_sel}({v_char}(35),...),...}}end;"
            f"{b_t1}[{b_t3}]=pk({v_ctx}[{k_vmfn}](s2,ck,ks,{v_bxor},{v_band},{v_lshift},{v_rshift},{v_unpack}({v_args},1,{v_ctx}[{k_argc}])))"
        ),
        s1_op_ids["OP_RET"]: (
            f"local rv={b_t1}[{b_t3}];return {v_unpack}(rv,1,rv[{rint(cnt_key)}])"
        ),
    }

    sorted_s1_ops = sorted(s1_handlers.items(), key=lambda kv: kv[0])

    def emit_s1_tree(items: List[Tuple[int, str]]) -> str:
        if len(items) == 1:
            op_code, body = items[0]
            return f"if {b_t2}=={rint(op_code)} then {body} end"
        mid = len(items) // 2
        split_val = items[mid - 1][0]
        return (
            f"if {b_t2}<={rint(split_val)} then "
            f"{emit_s1_tree(items[:mid])} else {emit_s1_tree(items[mid:])} end"
        )

    branch_s1_disp = (
        f"local {b_t1},{b_t7}={v_ctx}[{k_reg}],{v_ctx}[{k_insn}];"
        f"local {b_t8}={b_t1}[{rint(reg_chain_crc)}]or 0;"
        f"local {b_t2}={v_bxor}({b_t7}[{slot_op}],({b_t7}[{slot_guard}]+{b_t8}%256)%256);"
        f"local {b_t3},{b_t4},{b_t5},{b_t6}={b_t7}[{slot_a}],{b_t7}[{slot_b}],{b_t7}[{slot_c}],{b_t7}[{slot_d}];"
        f"{emit_s1_tree(sorted_s1_ops)};"
        f"{v_ctx}[{k_pc}]={v_ctx}[{k_pc}]+1;{v_st}=0x{cff_s1_fetch:X}"
    )

    # Branch 6 (`cff_decoy`): Realistic decoy CFF state (never entered, varies AST structure)
    branch_decoy = (
        f"local {b_t1}={v_bxor}({v_ctx}[{k_seed}]or 1,{rng.randint(1025, 65535)});"
        f"{v_ctx}[{k_seed}]={v_band}({b_t1}*1664525+1013904223,4294967295);{v_st}=0"
    )

    cff_branches = [
        (cff_probe, branch_probe),
        (cff_b85_cfb, branch_b85_cfb),
        (cff_unpack_s1, branch_unpack_s1),
        (cff_s1_fetch, branch_s1_fetch),
        (cff_s1_disp, branch_s1_disp),
        (cff_decoy, branch_decoy),
    ]
    rng.shuffle(cff_branches)

    if_parts: List[str] = []
    for idx, (st_val, st_body) in enumerate(cff_branches):
        kw = "if" if idx == 0 else "elseif"
        if_parts.append(f"{kw} {v_st}==0x{st_val:X} then {st_body} ")
    if_parts.append(f"else {v_st}=0 end")
    cff_if_chain = "".join(if_parts)

    vm_body = (
        f"return(function({iife_params_str})"
        f"local {v_st},{v_ctx},{v_anchor}=0x{cff_probe:X},{{}},{{}};"
        f"while {v_st}~=0 do {cff_if_chain} end "
        f"end)({iife_args_str})"
    )

    output = f"{vm_body}\n"

    if FORBIDDEN_ANCHOR_RE.search(output):
        raise RuntimeError(f"Forbidden AnchorPoint=UDim2 pattern found in obfuscated output for {rel_path}")

    for magic in FORBIDDEN_MAGIC_NUMS:
        if re.search(rf"(?<![0-9]){magic}(?![0-9])", output):
            return compile_polymorphic_vm(clean_source, rel_path, bridge, file_seed=file_seed + 13, target=target)

    if STATIC_CONST_ARITH_RE.search(output):
        return compile_polymorphic_vm(clean_source, rel_path, bridge, file_seed=file_seed + 17, target=target)

    return output


def count_top_level_locals(source: str) -> int:
    return len(re.findall(r"\blocal\b", source))


def verify_obfuscated_file(
    rel_path: str,
    clean_source: str,
    obf_source: str,
    bridge: PrometheusBridge,
    target: str = "luau",
) -> Dict[str, object]:
    """
    Verifies an obfuscated v6.0 file against all architectural & security requirements:
    1. Zero Header Comments (`-- STEPH_COMPONENT` and `--[[STEPH_PROMETHEUS_VM]]` absent)
    2. Zero diagnostic error strings (`"Detected"`, `"VM integrity check failed"`, `"unknown VM opcode"`)
    3. Zero static constant-foldable arithmetic & zero magic probe constants
    4. Zero Lua 5.1 16x16 XOR fallback in `--target=luau` & valid Luau AST with max_scope_locals < 55
    5. Live Dual-VM Execution & Silent Seed Poisoning in Luau-mocked `lupa` environment:
       - Clean unhooked environment executes Stage-1 + Stage-2 (`Vmify` custom bytecode VM)
       - `table.concat = nil` still executes cleanly (zero reliance on `table.concat`)
       - Lua wrapper hooks on `string.char`, `bit32.bxor`, `table.concat`, and `loadstring` are
         caught by `debug.info` (`"[C]", -1` check) and silently poison `seed` returning `nil` with zero leaks!
    """
    first_line = obf_source.splitlines()[0].strip()
    if first_line.startswith("--") or "STEPH_COMPONENT" in obf_source or "STEPH_PROMETHEUS_VM" in obf_source:
        raise AssertionError(f"[{rel_path}] Header signature or comment found in obfuscated output!")

    if FORBIDDEN_ANCHOR_RE.search(obf_source):
        raise AssertionError(f"[{rel_path}] Contains forbidden AnchorPoint=UDim2 pattern!")

    if rel_path in obf_source:
        raise AssertionError(f"[{rel_path}] Filename leaked inside obfuscated output!")

    if target == "luau" and re.search(r"for\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*0\s*,\s*15\s+do", obf_source):
        raise AssertionError(f"[{rel_path}] Lua 5.1 bitwise fallback found in --target=luau output!")

    forbidden_strings = (
        "Detected",
        "VM integrity check failed",
        "unknown VM opcode",
        "loadstring",
        "getinfo",
        "short_src",
        "linedefined",
        "iscclosure",
        "islclosure",
        "ishooked",
        "isfunctionhooked",
        "__UPV_",
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

    for magic in FORBIDDEN_MAGIC_NUMS:
        if re.search(rf"(?<![0-9]){magic}(?![0-9])", obf_source):
            raise AssertionError(f"[{rel_path}] Magic probe constant {magic} found in generated source!")

    static_arith_matches = STATIC_CONST_ARITH_RE.findall(obf_source)
    if static_arith_matches:
        raise AssertionError(
            f"[{rel_path}] Found static constant-foldable arithmetic expressions: {static_arith_matches[:5]}"
        )

    stmts, max_scope_locals = bridge.verify_luau_syntax(obf_source, rel_path)
    if max_scope_locals >= 55:
        raise AssertionError(
            f"[{rel_path}] Max function scope local count too high: {max_scope_locals} >= 55 (limit 200)"
        )

    test_rt = lua51.LuaRuntime()
    verify_fn = test_rt.eval(
        f"""
        (function()
            {TEST_LUAU_ENV_LUA}
            return function(vm_code, label)
                _install_luau_test_env()
                local orig_char = string.char
                local orig_bxor = bit32.bxor
                local orig_concat = table.concat
                local orig_loadstring = loadstring
                local orig_pcall = pcall

                local fn, err = orig_loadstring(vm_code, "=" .. label)
                if not fn then
                    error("Outer VM compile error: " .. tostring(err), 0)
                end

                local game_clean = false
                _G.game = setmetatable({{}}, {{
                    __index = function(_, k)
                        game_clean = true
                        error("STAGE2_GAME_" .. tostring(k), 0)
                    end
                }})

                -- 1. Execute in clean unhooked Luau environment
                local ok_clean, res_clean = orig_pcall(fn)

                -- 2. Execute with table.concat = nil (zero table.concat reliance)
                local game_nil_tc = false
                _G.game = setmetatable({{}}, {{
                    __index = function(_, k)
                        game_nil_tc = true
                        error("STAGE2_GAME_" .. tostring(k), 0)
                    end
                }})
                table.concat = nil
                local ok_nil_tc, res_nil_tc = orig_pcall(fn)
                table.concat = orig_concat

                -- 3. Execute with Lua hook on string.char
                local game_hook = false
                _G.game = setmetatable({{}}, {{
                    __index = function(_, k)
                        game_hook = true
                        error("STAGE2_GAME_" .. tostring(k), 0)
                    end
                }})
                string.char = function(...) return orig_char(...) end
                local ok_sc, res_sc = orig_pcall(fn)
                string.char = orig_char

                -- 4. Execute with Lua hook on bit32.bxor
                bit32.bxor = function(a, b, ...) return orig_bxor(a, b, ...) end
                local ok_bx, res_bx = orig_pcall(fn)
                bit32.bxor = orig_bxor

                -- 5. Execute with Lua hook on loadstring
                local dumped_ls = nil
                loadstring = function(s, ...)
                    dumped_ls = s
                    return orig_loadstring(s, ...)
                end
                local ok_ls, res_ls = orig_pcall(fn)
                loadstring = orig_loadstring

                -- 6. Execute with Lua hook on table.concat
                local dumped_tc = nil
                table.concat = function(t, ...)
                    local r = orig_concat(t, ...)
                    if type(r) == "string" and #r > 64 then
                        dumped_tc = r
                    end
                    return r
                end
                local ok_tc, res_tc = orig_pcall(fn)
                table.concat = orig_concat
                _G.game = nil

                return ok_clean, type(res_clean), tostring(res_clean), game_clean,
                       ok_nil_tc, type(res_nil_tc), game_nil_tc,
                       (not game_hook) and ok_sc and res_sc == nil,
                       (not game_hook) and ok_bx and res_bx == nil,
                       dumped_ls == nil and (not game_hook) and ok_ls and res_ls == nil,
                       dumped_tc == nil and (not game_hook) and ok_tc and res_tc == nil
            end
        end)()
        """
    )
    (
        ok_clean,
        res_type,
        res_str,
        game_clean,
        ok_nil_tc,
        res_nil_tc_type,
        game_nil_tc,
        sc_poisoned,
        bx_poisoned,
        ls_poisoned,
        tc_poisoned,
    ) = verify_fn(obf_source, rel_path)

    if not sc_poisoned:
        raise AssertionError(f"[{rel_path}] Failed string.char anti-hook silent seed-poisoning test!")
    if not bx_poisoned:
        raise AssertionError(f"[{rel_path}] Failed bit32.bxor anti-hook silent seed-poisoning test!")
    if not ls_poisoned:
        raise AssertionError(f"[{rel_path}] Failed loadstring anti-hook silent seed-poisoning test!")
    if not tc_poisoned:
        raise AssertionError(f"[{rel_path}] Failed table.concat anti-hook silent seed-poisoning test!")

    if rel_path == "manifest.lua":
        if not ok_clean or res_type != "table" or not ok_nil_tc or res_nil_tc_type != "table":
            raise AssertionError(
                f"[manifest.lua] Expected VM to return table, got ok={ok_clean} type={res_type} ({res_str})"
            )
    elif rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if not ok_clean or res_type != "function" or not ok_nil_tc or res_nil_tc_type != "function":
            raise AssertionError(
                f"[{rel_path}] Expected VM to return builder function, got ok={ok_clean} type={res_type} ({res_str})"
            )
    else:
        if game_clean or (not ok_clean and ("attempt to index" in res_str or "STAGE2_GAME_" in res_str)):
            if not game_nil_tc and ok_nil_tc and res_nil_tc_type == "nil":
                raise AssertionError(f"[{rel_path}] Failed Stage-2 execution when table.concat = nil!")
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
    try:
        for rel in get_target_files(repo_dir):
            src = os.path.join(repo_dir, rel)
            dst = os.path.join(WORKSPACE_DIR, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            synced.append(rel)
    except PermissionError:
        print(f"      [WARN] Skipped workspace sync to {WORKSPACE_DIR} (sandbox write restriction).", flush=True)
    return synced


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Steph HUB Prometheus Vmify Polymorphic Luau Dual-VM Obfuscator v6.0"
    )
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
    parser.add_argument(
        "--target",
        choices=["luau", "lua51"],
        default="luau",
        help="Target VM runtime dialect (default: luau, omits Lua 5.1 bitwise fallbacks)",
    )
    parser.add_argument("--backup-only", action="store_true", help="Only back up unobfuscated source files")
    parser.add_argument("--restore", action="store_true", help="Restore unobfuscated source files into repo")
    parser.add_argument("--verify-only", action="store_true", help="Verify existing obfuscated files in repo")
    parser.add_argument("--no-workspace-sync", action="store_true", help="Skip copying obfuscated files to workspace")
    parser.add_argument("--seed", type=int, default=None, help="Optional deterministic base seed")
    parser.add_argument(
        "--bundle",
        action="store_true",
        help="Bundle all unobf/ modules via tools/bundler.py and obfuscate into a standalone single-file output",
    )
    parser.add_argument(
        "--bundle-out",
        default=None,
        help="Output path for single-file bundled+obfuscated Luau script (implies --bundle)",
    )
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

    if args.bundle or args.bundle_out:
        tools_dir = os.path.join(args.repo, "tools")
        if tools_dir not in sys.path:
            sys.path.insert(0, tools_dir)
        from bundler import bundle_from_dir

        unobf_dir = os.path.join(args.repo, "unobf")
        bundled_src = bundle_from_dir(unobf_dir, entry="main")
        bundle_out_path = args.bundle_out or os.path.join(args.repo, "tools", "dist_bundled_check.lua")
        bundle_seed = (args.seed + 99991) if args.seed is not None else None
        print(f"[BUNDLE] Compiling unified 23-module bundle (--target={args.target}) -> {bundle_out_path}...", flush=True)
        obf_bundle = compile_polymorphic_vm(
            bundled_src,
            "bundled_stephhub.lua",
            bridge,
            file_seed=bundle_seed,
            target=args.target,
        )
        os.makedirs(os.path.dirname(os.path.abspath(bundle_out_path)), exist_ok=True)
        with open(bundle_out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(obf_bundle)
        rep_b = verify_obfuscated_file("bundled_stephhub.lua", bundled_src, obf_bundle, bridge, target=args.target)
        print(
            f"      PASS bundled_stephhub.lua | max_loc={rep_b['max_scope_locals']:2d} (<55) | "
            f"clean={rep_b['clean_bytes']:7d}B -> vm_v6={rep_b['obf_bytes']:7d}B | ret={rep_b['return_type']}",
            flush=True,
        )
        if args.bundle and not args.bundle_out and args.verify_only:
            return 0

    if not args.verify_only:
        print(
            f"[2/4] Compiling Luau files with Dual-VM v6.0 (--target={args.target}: "
            f"Unified Base85 + Xorshift32-CFB + Polymorphic IIFE CFF + Lazy Ring-Buffer Vmify)...",
            flush=True,
        )
        for idx, (rel, clean_src) in enumerate(clean_sources.items()):
            file_seed = (args.seed + idx * 7919) if args.seed is not None else None
            obf_src = compile_polymorphic_vm(
                clean_src,
                rel,
                bridge,
                file_seed=file_seed,
                target=args.target,
            )
            out_path = os.path.join(args.repo, rel)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(obf_src)

    print(
        f"[3/4] Verifying all obfuscated files in Luau ({args.target}) + Anti-Pre-Hook + Prometheus LuaU AST harness...",
        flush=True,
    )
    reports: List[Dict[str, object]] = []
    for rel, clean_src in clean_sources.items():
        obf_path = os.path.join(args.repo, rel)
        with open(obf_path, "r", encoding="utf-8") as f:
            obf_src = f.read()
        rep = verify_obfuscated_file(rel, clean_src, obf_src, bridge, target=args.target)
        reports.append(rep)
        print(
            f"      PASS {rel:24s} | max_loc={rep['max_scope_locals']:2d} (<55) | "
            f"clean={rep['clean_bytes']:7d}B -> vm_v6={rep['obf_bytes']:7d}B | "
            f"cfb=B85_XORSHIFT32 | ret={rep['return_type']}",
            flush=True,
        )

    if not args.no_workspace_sync:
        print(f"[4/4] Syncing {len(reports)} verified obfuscated files to {WORKSPACE_DIR}...", flush=True)
        sync_to_workspace(args.repo)

    print(f"[DONE] Verified {len(reports)}/{len(reports)} v6.0 VM-obfuscated files in {time.time() - t_start:.2f}s.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
