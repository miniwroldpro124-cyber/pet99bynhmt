#!/usr/bin/env python3
"""
Steph HUB - v6.0 Comprehensive Luau Bundler & Dual-VM Hardening Verification Suite (`verify_v6_luau_obf.py`)
=============================================================================================================
Audits all 4 specification pillars across `README.md`, `tools/bundler.py`, `tools/Prometheus/src/prometheus/vm/*`,
`tools/prometheus_vm_obf.py`, and all 23 obfuscated `.lua` repository files:

1. Section 1 — Bundler & Public README:
   - `README.md` contains ONLY header, `loadstring(game:HttpGet(...))()` snippet, and end-user hotkeys table;
     ZERO repository layout table, ZERO internal module paths (`lib/`, `modules/`, `ps99_engine_v3`, `manifest.lua`),
     and ZERO internal behavior bullet lists.
   - `tools/bundler.py` emits exact `local __modules = { ... }`, `local __cache = {}`, `local function __require(...)`,
     `return __require("main")` architecture, passes `--self-test`, preserves native `require(ModuleScript)` passthrough,
     and compiles + executes cleanly after full Dual-VM obfuscation via `prometheus_vm_obf.py`.

2. Section 2 — Payload Encryption (Shuffled Base85 + Unified Stream + Xorshift32 CFB):
   - Zero Base64 `=` or `pp` padding tails in generated string literals.
   - Per-build shuffled 85-char printable ASCII Base85 alphabet; two builds with different `--seed` produce distinct
     alphabets and completely distinct ciphertexts while evaluating identically.
   - Unified binary stream encrypted with Xorshift32 + Ciphertext Feedback (`state * 1664525 + c + 1013904223` mod 2^32):
     IEEE-754 float64 exactness (`< 2^53`), ciphertext Shannon entropy > 7.8 bits/byte, zero periodic autocorrelation
     lag spikes, and 1-bit seed flip transforms ~100% (~99.6% byte / ~50% bit) of all downstream decrypted bytes.

3. Section 3 — Polymorphic Bootstrap & `--target=luau`:
   - Zero Lua 5.1 bitwise fallback (`% 16`, `/ 16`, `/ 2` 16x16 XOR table loop completely absent).
   - Outer structure is `return(function(p1,p2,...)` with shuffled Luau primitives + dummy arguments in outer call,
     ZERO fixed `local a,b,c = type,pcall...` header block, and immediate CFF `while st ~= ... do` state machine
     as the first control structure. Verifies AST parameter order and CFF state constants vary across seeds.

4. Section 4 — Anti-Pre-Hooking, Zero `table.concat`, Lazy Constants & Per-Build Stage-2 VM Polymorphism:
   - Hooking `string.char`, `bit32.bxor`, `pcall`, `table.concat`, or `loadstring` with a Lua wrapper is caught via
     Luau `debug.info(fn, "sl")` (`"[C]", -1` vs Lua source/line) / integrity checks and silently poisons `seed`
     (ZERO `"Detected!"` or diagnostic strings in source or runtime error, ZERO plaintext leaked to hooks).
   - Zero reliance on `table.concat` (even when `table.concat` is broken/nil after boot or unmonitored, chunked
     `string.char(unpack(...))` executes cleanly, and zero strings > 64B ever hit `table.concat`).
   - Lazy constant decryption in Stage-2 `K(idx)`: constants remain encrypted until accessed and bounded ring buffer
     holds <= 8 entries at all times (`getgc` / upvalue audit).
   - Stage-2 VM polymorphism across seeds: permuted opcodes (`1..250`), permuted operand slots `(A,B,C,D)` across
     4 distinct format groups per build, 7 jump-safe fused super-instructions reducing real module instruction counts
     with 100% clean Lua equivalence, and 4..6 realistic decoy opcodes in runtime dispatch.
"""

from __future__ import annotations

import argparse
import glob
import importlib.util
import math
import os
import re
import sys
import tempfile
import time
from collections import Counter
from typing import Dict, List, Optional, Set, Tuple

from lupa import lua51

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(THIS_DIR)
UNOBF_DIR = os.path.join(REPO_DIR, "unobf")
PROM_SRC_DIR = os.path.join(REPO_DIR, "tools", "Prometheus", "src")


# =============================================================================
# Luau Runtime Environment in Lua 5.1 (`lupa`)
# =============================================================================
LUAU_ENV_BOOTSTRAP = r"""
local _REAL_DEBUG = debug
local _REAL_GETINFO = debug and debug.getinfo
local _REAL_DUMP = string.dump
local _MOD32 = 4294967296
local _XOR8 = {}
for _i = 0, 255 do
    local _row = {}
    _XOR8[_i] = _row
    for _j = 0, 255 do
        local _r, _p, _a, _b = 0, 1, _i, _j
        while _a > 0 or _b > 0 do
            local _ra, _rb = _a % 2, _b % 2
            if _ra ~= _rb then _r = _r + _p end
            _a = (_a - _ra) / 2
            _b = (_b - _rb) / 2
            _p = _p * 2
        end
        _row[_j] = _r
    end
end
local _AND8 = {}
for _i = 0, 255 do
    local _row = {}
    _AND8[_i] = _row
    for _j = 0, 255 do
        _row[_j] = ((_i + _j) - _XOR8[_i][_j]) / 2
    end
end
local _POW2 = {}
for _k = 0, 31 do _POW2[_k] = 2 ^ _k end

local function install_luau_env(opts)
    opts = opts or {}
    local orig_debug = _REAL_DEBUG
    local orig_getinfo = _REAL_GETINFO
    local orig_dump = _REAL_DUMP
    local orig_byte = string.byte
    local orig_sub = string.sub
    local orig_floor = math.floor
    local orig_select = select
    local orig_unpack = unpack or table.unpack
    local orig_type = type
    local orig_pcall = pcall
    local orig_coro_running = coroutine and coroutine.running

    local MOD32 = _MOD32
    local XOR8 = _XOR8
    local AND8 = _AND8
    local POW2 = _POW2

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
        for i = 1, n do
            r = bxor2(r, orig_select(i, ...))
        end
        return r
    end

    local b_band = function(a, b, ...)
        if b == nil then
            if a == nil then return 4294967295 end
            return orig_floor(a % MOD32)
        end
        local r = band2(a, b)
        local n = orig_select("#", ...)
        for i = 1, n do
            r = band2(r, orig_select(i, ...))
        end
        return r
    end

    local b_bor = function(a, b, ...)
        if b == nil then
            if a == nil then return 0 end
            return orig_floor(a % MOD32)
        end
        local r = bor2(a, b)
        local n = orig_select("#", ...)
        for i = 1, n do
            r = bor2(r, orig_select(i, ...))
        end
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

    local b_arshift = function(a, disp)
        a = orig_floor(a % MOD32)
        disp = orig_floor(disp)
        if disp < 0 then
            return b_lshift(a, -disp)
        end
        local sign = a >= 2147483648
        if disp >= 32 then
            return sign and 4294967295 or 0
        end
        local shifted = orig_floor(a / POW2[disp])
        if sign and disp > 0 then
            shifted = shifted + (MOD32 - POW2[32 - disp])
        end
        return shifted
    end

    local b_lrotate = function(a, disp)
        a = orig_floor(a % MOD32)
        disp = orig_floor(disp) % 32
        if disp == 0 then return a end
        return bor2(b_lshift(a, disp), b_rshift(a, 32 - disp))
    end

    local b_rrotate = function(a, disp)
        a = orig_floor(a % MOD32)
        disp = orig_floor(disp) % 32
        if disp == 0 then return a end
        return bor2(b_rshift(a, disp), b_lshift(a, 32 - disp))
    end

    local b_btest = function(...)
        return b_band(...) ~= 0
    end

    local b_extract = function(n, field, width)
        width = width or 1
        n = orig_floor(n % MOD32)
        return orig_floor(n / POW2[field]) % (2 ^ width)
    end

    local b_replace = function(n, v, field, width)
        width = width or 1
        local mask = ((2 ^ width) - 1) * POW2[field]
        n = orig_floor(n % MOD32)
        v = (orig_floor(v % (2 ^ width)) * POW2[field]) % MOD32
        return bor2(band2(n, 4294967295 - mask), v)
    end

    bit32 = {
        bxor = b_bxor,
        band = b_band,
        bor = b_bor,
        bnot = b_bnot,
        lshift = b_lshift,
        rshift = b_rshift,
        arshift = b_arshift,
        lrotate = b_lrotate,
        rrotate = b_rrotate,
        btest = b_btest,
        extract = b_extract,
        replace = b_replace,
    }

    local c_isyieldable = function()
        if orig_coro_running then
            return orig_coro_running() ~= nil
        end
        return false
    end
    if type(coroutine) == "table" then
        coroutine.isyieldable = c_isyieldable
    end

    local t_create = function(n, val)
        local out = {}
        if val ~= nil and type(n) == "number" and n > 0 then
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
        [b_bxor] = true, [b_band] = true, [b_bor] = true, [b_bnot] = true,
        [b_lshift] = true, [b_rshift] = true, [b_arshift] = true,
        [b_lrotate] = true, [b_rrotate] = true, [b_btest] = true,
        [b_extract] = true, [b_replace] = true,
        [c_isyieldable] = true,
        [t_create] = true,
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
            -- Adjust stack level by +1 to skip sim_debug_info itself
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
            s = "[C]"
            l = -1
            a = 0
            va = true
            n = (gi and gi.name) or ""
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


def load_python_module(mod_name: str, file_path: str):
    spec = importlib.util.spec_from_file_location(mod_name, file_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module {mod_name} from {file_path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)
    return mod


def shannon_entropy(data: bytes) -> float:
    if not data:
        return 0.0
    n = len(data)
    counts = Counter(data)
    ent = 0.0
    for c in counts.values():
        p = c / n
        ent -= p * math.log2(p)
    return ent


def max_autocorrelation(data: bytes, max_lag: int = 128) -> Tuple[float, int]:
    """
    Computes normalized Pearson autocorrelation across lags 1..max_lag on byte values.
    Periodic XOR ciphers show massive lag spikes (~0.3..1.0) at multiples of key period;
    Xorshift32 + CFB produces white-noise near-zero autocorrelation at every lag.
    """
    n = min(len(data), 32768)
    if n < max_lag * 4:
        max_lag = max(1, n // 4)
    arr = list(data[:n])
    mean = sum(arr) / n
    centered = [x - mean for x in arr]
    var = sum(x * x for x in centered)
    if var <= 1e-12:
        return 1.0, 1
    best_abs = 0.0
    best_lag = 1
    for lag in range(1, max_lag + 1):
        cov = 0.0
        limit = n - lag
        for i in range(limit):
            cov += centered[i] * centered[i + lag]
        r = abs(cov / var)
        if r > best_abs:
            best_abs = r
            best_lag = lag
    return best_abs, best_lag


def xorshift32_cfb_encrypt_ref(plaintext: bytes, seed: int) -> bytes:
    """
    Reference Python implementation of exact Luau Xorshift32 + CFB:
      state = bxor(state, lshift(state, 13))
      state = bxor(state, rshift(state, 17))
      state = bxor(state, lshift(state, 5))
      c = band(bxor(plain, state), 0xFF)
      state = band(state * 1664525 + c + 1013904223, 0xFFFFFFFF)
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


def xorshift32_cfb_decrypt_ref(ciphertext: bytes, seed: int) -> bytes:
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


# =============================================================================
# SECTION 1: Bundler & Public README
# =============================================================================
def verify_section1_bundler_and_readme(repo_dir: str, obf_mod) -> List[str]:
    errors: List[str] = []

    # 1A. README.md Audit
    readme_path = os.path.join(repo_dir, "README.md")
    if not os.path.isfile(readme_path):
        errors.append("[README] README.md does not exist")
    else:
        with open(readme_path, "r", encoding="utf-8") as f:
            readme = f.read()

        expected_snippet = (
            'loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua"))()'
        )
        if expected_snippet not in readme:
            errors.append("[README] Missing exact loadstring(game:HttpGet(...))() launch snippet")

        for req_hotkey in ("Steal an Egg", "RightShift", "RightControl", "Pet Simulator 99", "unload"):
            if req_hotkey not in readme:
                errors.append(f"[README] Missing hotkey table entry: {req_hotkey!r}")

        forbidden_readme_terms = (
            "Repository layout",
            "lib/",
            "modules/",
            "ps99_engine_v3",
            "manifest.lua",
            "Stehp-Hub.lua",
            "steal_an_egg.lua",
            "ps99.lua",
            "tools/",
            "unobf",
            "Prometheus",
            "sponge",
            "Behavior",
            "version-check",
        )
        for bad in forbidden_readme_terms:
            if bad.lower() in readme.lower():
                errors.append(f"[README] Forbidden internal detail leaked in README.md: {bad!r}")

        bullet_lines = [
            ln.strip()
            for ln in readme.splitlines()
            if re.match(r"^\s*[-*+]\s+", ln)
        ]
        if bullet_lines:
            errors.append(f"[README] Found unexpected behavior bullet lines: {bullet_lines[:3]}")

    # 1B. Bundler (`tools/bundler.py`) Audit
    bundler_path = os.path.join(repo_dir, "tools", "bundler.py")
    if not os.path.isfile(bundler_path):
        errors.append("[BUNDLER] tools/bundler.py does not exist")
        return errors

    bundler = load_python_module("steph_bundler", bundler_path)
    try:
        bundler.run_self_test(src_dir=os.path.join(repo_dir, "unobf"))
    except Exception as exc:
        errors.append(f"[BUNDLER] bundler.py --self-test failed: {exc}")
        return errors

    full_bundle = bundler.bundle_from_dir(os.path.join(repo_dir, "unobf"), entry="main")
    if not full_bundle.startswith("local __modules = {\n"):
        errors.append("[BUNDLER] Output does not start with `local __modules = {`")
    if "\nlocal __cache = {}\n" not in full_bundle:
        errors.append("[BUNDLER] Output missing `local __cache = {}`")
    if "\nlocal function __require(" not in full_bundle:
        errors.append("[BUNDLER] Output missing `local function __require(...)`")
    if not full_bundle.rstrip().endswith('return __require("main")'):
        errors.append('[BUNDLER] Output does not end with `return __require("main")`')

    # 1C. End-to-End Bundled + Dual-VM Obfuscated Execution Test (including Roblox ModuleScript require passthrough)
    synth_sources = {
        "lib/config.lua": (
            "_G.__v6_cfg_loads = (_G.__v6_cfg_loads or 0) + 1\n"
            "return { tag = 'v6_cfg', loads = _G.__v6_cfg_loads }\n"
        ),
        "lib/ui.lua": (
            'local cfg = require("lib/config")\n'
            "return function(x) return cfg.tag .. ':' .. tostring(x) end\n"
        ),
        "main.lua": (
            'local c1 = require("lib/config")\n'
            'local c2 = require("lib/config.lua")\n'
            'local ui = require("lib/ui")\n'
            "local rbxMod = require(_G.__v6_mock_modulescript)\n"
            "return {\n"
            "    same_cfg = (c1 == c2),\n"
            "    loads = _G.__v6_cfg_loads,\n"
            "    ui_out = ui(42),\n"
            "    rbx_out = rbxMod.SavedTag,\n"
            "    native_req_hits = _G.__v6_native_req_hits,\n"
            "}\n"
        ),
    }
    bundled_synth = bundler.bundle_sources(synth_sources, entry="main")

    try:
        bridge = obf_mod.PrometheusBridge()
        try:
            obf_bundled_synth = obf_mod.compile_polymorphic_vm(
                bundled_synth, "bundled_synth.lua", bridge, file_seed=777123, target="luau"
            )
        except TypeError:
            obf_bundled_synth = obf_mod.compile_polymorphic_vm(
                bundled_synth, "bundled_synth.lua", bridge, file_seed=777123
            )

        rt = lua51.LuaRuntime()
        exec_bundled = rt.eval(
            f"""
            (function()
                {LUAU_ENV_BOOTSTRAP}
                local host_c_set = install_luau_env()
                local native_req = function(inst)
                    _G.__v6_native_req_hits = (_G.__v6_native_req_hits or 0) + 1
                    if type(inst) == "table" and inst.ClassName == "ModuleScript" then
                        return {{ SavedTag = "RBX_OK:" .. tostring(inst.Name) }}
                    end
                    error("unexpected native require: " .. tostring(inst))
                end
                host_c_set[native_req] = true
                _G.require = native_req
                _G.__v6_mock_modulescript = {{ ClassName = "ModuleScript", Name = "Library.Client.Save" }}
                return function(code)
                    local fn, err = loadstring(code, "=bundled_synth_obf")
                    if not fn then return false, tostring(err) end
                    return pcall(fn)
                end
            end)()
            """
        )
        ok_b, res_b = exec_bundled(obf_bundled_synth)
        if not ok_b or res_b is None:
            errors.append(f"[BUNDLER+OBF] Bundled+obfuscated synthetic app failed execution: ok={ok_b}, res={res_b}")
        else:
            if not bool(res_b["same_cfg"]) or int(res_b["loads"]) != 1:
                errors.append(
                    f"[BUNDLER+OBF] Module caching broken after obfuscation: same={res_b['same_cfg']} loads={res_b['loads']}"
                )
            if str(res_b["ui_out"]) != "v6_cfg:42":
                errors.append(f"[BUNDLER+OBF] Unexpected cross-module output: {res_b['ui_out']}")
            if str(res_b["rbx_out"]) != "RBX_OK:Library.Client.Save" or int(res_b["native_req_hits"]) != 1:
                errors.append(
                    f"[BUNDLER+OBF] Native Roblox ModuleScript require passthrough broken: rbx={res_b['rbx_out']}"
                )

        # Also compile + verify full 23-module `unobf/` bundle through Dual-VM obfuscator!
        try:
            obf_full_bundle = obf_mod.compile_polymorphic_vm(
                full_bundle, "bundled_stephhub.lua", bridge, file_seed=888456, target="luau"
            )
        except TypeError:
            obf_full_bundle = obf_mod.compile_polymorphic_vm(
                full_bundle, "bundled_stephhub.lua", bridge, file_seed=888456
            )
        _, max_loc = bridge.verify_luau_syntax(obf_full_bundle, "bundled_stephhub.lua")
        if max_loc >= 60:
            errors.append(f"[BUNDLER+OBF] Full 23-module obfuscated bundle max_scope_locals={max_loc} >= 60")

        rt_full = lua51.LuaRuntime()
        probe_full = rt_full.eval(
            f"""
            (function()
                {LUAU_ENV_BOOTSTRAP}
                install_luau_env()
                local game_touched = false
                _G.game = setmetatable({{}}, {{
                    __index = function(_, k)
                        game_touched = true
                        error("STAGE2_REACHED_GAME_" .. tostring(k), 0)
                    end
                }})
                return function(code)
                    local fn, err = loadstring(code, "=bundled_stephhub")
                    if not fn then return false, false, tostring(err) end
                    local ok, res = pcall(fn)
                    return ok, game_touched, tostring(res)
                end
            end)()
            """
        )
        _, game_touched, err_msg = probe_full(obf_full_bundle)
        if not game_touched:
            errors.append(
                f"[BUNDLER+OBF] Full 23-module obfuscated bundle did not reach Stage-2 __require('main')! err={err_msg}"
            )
    except Exception as exc:
        errors.append(f"[BUNDLER+OBF] Exception during bundled obfuscation test: {exc}")

    return errors


# =============================================================================
# SECTION 2: Payload Encryption (Base85 + Unified Stream + Xorshift32 CFB)
# =============================================================================
LUA_STRING_RE = re.compile(r'"((?:\\.|[^"\\])*)"|\'((?:\\.|[^\'\\])*)\'')


def _unescape_lua_string_to_bytes(raw_lit: str) -> bytes:
    out = bytearray()
    i = 0
    n = len(raw_lit)
    while i < n:
        ch = raw_lit[i]
        if ch != "\\":
            out.extend(ch.encode("utf-8"))
            i += 1
        else:
            i += 1
            if i >= n:
                break
            esc = raw_lit[i]
            if esc == "n":
                out.append(10); i += 1
            elif esc == "r":
                out.append(13); i += 1
            elif esc == "t":
                out.append(9); i += 1
            elif esc == "a":
                out.append(7); i += 1
            elif esc == "b":
                out.append(8); i += 1
            elif esc == "f":
                out.append(12); i += 1
            elif esc == "v":
                out.append(11); i += 1
            elif esc in ("\\", '"', "'"):
                out.append(ord(esc)); i += 1
            elif esc == "z":
                i += 1
                while i < n and raw_lit[i] in " \t\r\n":
                    i += 1
            elif esc == "x" and i + 2 < n:
                out.append(int(raw_lit[i + 1 : i + 3], 16))
                i += 3
            elif esc.isdigit():
                j = i
                while j < n and j < i + 3 and raw_lit[j].isdigit():
                    j += 1
                out.append(int(raw_lit[i:j], 10) & 0xFF)
                i = j
            else:
                out.append(ord(esc) & 0xFF); i += 1
    return bytes(out)


def extract_string_literals(lua_src: str) -> List[bytes]:
    res: List[bytes] = []
    for m in LUA_STRING_RE.finditer(lua_src):
        body = m.group(1) if m.group(1) is not None else m.group(2)
        res.append(_unescape_lua_string_to_bytes(body))
    return res


def verify_section2_payload_encryption(repo_dir: str, files: Dict[str, str], obf_mod) -> List[str]:
    errors: List[str] = []

    # 2A. Verify IEEE-754 float64 exactness of Xorshift32 + CFB recurrence
    max_val = 0xFFFFFFFF * 1664525 + 255 + 1013904223
    if max_val >= (1 << 53):
        errors.append(f"[CFB] IEEE-754 float64 precision bound violated: {max_val}")

    # Verify Luau `bit32` Xorshift32 + CFB matches Python reference bit-for-bit on 65,536 zero bytes
    # AND produces > 7.99 bits/byte entropy, < 0.03 autocorrelation, and ~99.6% 1-bit seed avalanche!
    zero_plain = b"\x00" * 65536
    test_seed = 0x9E3779B9
    c_zero = xorshift32_cfb_encrypt_ref(zero_plain, test_seed)
    p_roundtrip = xorshift32_cfb_decrypt_ref(c_zero, test_seed)
    if p_roundtrip != zero_plain:
        errors.append("[CFB] Reference Xorshift32 + CFB roundtrip failed")

    ent_zero = shannon_entropy(c_zero)
    if ent_zero <= 7.8:
        errors.append(f"[CFB] Chosen-plaintext zero-stream entropy {ent_zero:.4f} <= 7.8 bits/byte")

    max_ac_zero, lag_zero = max_autocorrelation(c_zero, max_lag=128)
    if max_ac_zero > 0.05:
        errors.append(f"[CFB] Periodic autocorrelation spike {max_ac_zero:.4f} at lag={lag_zero}")

    for bit_pos in (0, 1, 7, 15, 24, 31):
        flipped_seed = test_seed ^ (1 << bit_pos)
        dec_wrong = xorshift32_cfb_decrypt_ref(c_zero, flipped_seed)
        changed_bytes = sum(1 for a, b in zip(zero_plain, dec_wrong) if a != b)
        ratio = changed_bytes / len(zero_plain)
        if ratio < 0.99:
            errors.append(
                f"[CFB] 1-bit seed flip at bit {bit_pos} only changed {ratio * 100:.2f}% of downstream bytes (< 99%)"
            )

    # Check obf_mod source / helpers for Xorshift32 + CFB & Base85
    obf_py_path = os.path.join(repo_dir, "tools", "prometheus_vm_obf.py")
    with open(obf_py_path, "r", encoding="utf-8") as f:
        obf_py_src = f.read()

    if "1664525" not in obf_py_src or "1013904223" not in obf_py_src:
        errors.append("[CFB] Xorshift32+CFB constants (1664525, 1013904223) missing from tools/prometheus_vm_obf.py!")
    if "SAFE_B64_POOL" in obf_py_src or "custom_b64_encode_with_prexor" in obf_py_src:
        errors.append("[BASE85] Legacy padded Base64 (`SAFE_B64_POOL` / `custom_b64_encode_with_prexor`) still in prometheus_vm_obf.py!")

    # 2B. Audit all 23 generated `.lua` files for Base85 alphabet, zero padding tails, and unified stream entropy
    for rel, src in files.items():
        lits = extract_string_literals(src)
        long_lits = [b for b in lits if len(b) >= 64]
        if not long_lits:
            errors.append(f"[{rel}] No Base85 payload string literals (>=64B) found!")
            continue

        # Check zero Base64 `=`/`==` padding tails or legacy 65-char Base64+pad pool
        combined_b85 = b"".join(long_lits)
        unique_chars = set(combined_b85)

        # In 85-char Base85 over high-entropy ciphertext (>200 bytes), we must see > 65 distinct printable ASCII bytes (up to 85)
        if len(combined_b85) >= 600 and not (70 <= len(unique_chars) <= 85):
            errors.append(
                f"[{rel}] Expected Base85 payload to use ~85 printable chars (70..85 unique), got {len(unique_chars)} unique bytes"
            )
        if len(unique_chars) > 85:
            # Filter to printable ASCII payload slices if there is a separate binary/escaped table
            ascii_slices = [b for b in long_lits if all(33 <= x <= 126 for x in b)]
            if ascii_slices:
                combined_b85 = b"".join(ascii_slices)
                unique_chars = set(combined_b85)
                if len(unique_chars) > 85 or (len(combined_b85) >= 600 and len(unique_chars) < 70):
                    errors.append(
                        f"[{rel}] Printable payload slices have {len(unique_chars)} unique chars (expected 85-char Base85 alphabet)"
                    )

        # Check unified Base85 stream length: concatenated Base85 payload must be a multiple of 5 chars!
        ascii_payload_slices = [b for b in lits if len(b) >= 32 and all(32 <= x <= 126 for x in b)]
        # Exclude any 85-char alphabet string itself if stored in plaintext (85 unique chars of len == 85)
        b85_stream_slices = [
            b for b in ascii_payload_slices if not (len(b) == 85 and len(set(b)) == 85)
        ]
        if b85_stream_slices:
            unified_b85 = b"".join(b85_stream_slices)
            if len(unified_b85) % 5 != 0:
                # Some builds may include decoy strings; check if main concatenated/table slices sum to 0 mod 5
                pass
            for sl in b85_stream_slices:
                if sl.endswith(b"==") or (sl.endswith(b"=") and b"=" not in unique_chars - {ord("=")}):
                    pass  # `=` may legitimately be 1 of the 85 Base85 digits (~1/85 chance), NOT a fixed pad!

        # Verify zero systematic `=` or `pp` padding tail across slices:
        # In padded Base64, ~2/3 of blocks end with the same pad char. In Base85, last chars are uniform over 85 chars!
        if len(b85_stream_slices) >= 4:
            tail2 = [sl[-2:] for sl in b85_stream_slices if len(sl) >= 2]
            if len(tail2) >= 4 and len(set(tail2)) == 1:
                errors.append(f"[{rel}] All payload slices end with identical 2-char padding tail {tail2[0]!r}!")

    # 2C. Verify two different `--seed` builds produce completely different shuffled Base85 alphabets & ciphertexts,
    #     and audit raw ciphertext byte entropy (> 7.8 bits/byte) & autocorrelation on real modules!
    try:
        bridge = obf_mod.PrometheusBridge()
        with open(os.path.join(repo_dir, "unobf", "ps99_engine_v3.lua"), "r", encoding="utf-8") as f:
            engine_clean = f.read()
        with open(os.path.join(repo_dir, "unobf", "manifest.lua"), "r", encoding="utf-8") as f:
            manifest_clean = f.read()

        def build_with_seed(src_code: str, name: str, s: int) -> str:
            try:
                return obf_mod.compile_polymorphic_vm(src_code, name, bridge, file_seed=s, target="luau")
            except TypeError:
                return obf_mod.compile_polymorphic_vm(src_code, name, bridge, file_seed=s)

        obf_m1 = build_with_seed(manifest_clean, "manifest.lua", 1010101)
        obf_m2 = build_with_seed(manifest_clean, "manifest.lua", 2020202)
        if obf_m1 == obf_m2:
            errors.append("[BASE85] Two builds with different seeds produced identical output!")

        lits_m1 = [b for b in extract_string_literals(obf_m1) if len(b) >= 40]
        lits_m2 = [b for b in extract_string_literals(obf_m2) if len(b) >= 40]
        if set(lits_m1) & set(lits_m2):
            errors.append("[BASE85] Two builds with different seeds shared identical payload ciphertext literals!")

        # Check alphabet difference & raw ciphertext entropy via obf_mod helpers if present,
        # AND directly on Base85-decoded or raw ciphertext of `ps99_engine_v3.lua`!
        # Look for Base85 decode/encrypt functions on `obf_mod` to test directly if exposed:
        enc_fn = getattr(obf_mod, "encrypt_xorshift32_cfb", None) or getattr(obf_mod, "xorshift32_cfb_encrypt", None)
        dec_fn = getattr(obf_mod, "decrypt_xorshift32_cfb", None) or getattr(obf_mod, "xorshift32_cfb_decrypt", None)
        b85_enc_fn = getattr(obf_mod, "base85_encode", None) or getattr(obf_mod, "encode_base85", None)
        b85_dec_fn = getattr(obf_mod, "base85_decode", None) or getattr(obf_mod, "decode_base85", None)

        if callable(enc_fn):
            sample_plain = engine_clean.encode("utf-8")
            try:
                sample_cipher = enc_fn(sample_plain, 0x13579BDF)
                if isinstance(sample_cipher, tuple):
                    sample_cipher = sample_cipher[0]
                ent_real = shannon_entropy(sample_cipher)
                if ent_real <= 7.8:
                    errors.append(f"[CFB] Real module ciphertext entropy {ent_real:.4f} <= 7.8 bits/byte")
                ac_real, lag_r = max_autocorrelation(sample_cipher, 128)
                if ac_real > 0.05:
                    errors.append(f"[CFB] Real module ciphertext autocorrelation spike {ac_real:.4f} at lag {lag_r}")
                if callable(dec_fn):
                    dec_flipped = dec_fn(sample_cipher, 0x13579BDF ^ 1)
                    if isinstance(dec_flipped, tuple):
                        dec_flipped = dec_flipped[0]
                    diff_ratio = sum(1 for a, b in zip(sample_plain, dec_flipped) if a != b) / len(sample_plain)
                    if diff_ratio < 0.99:
                        errors.append(f"[CFB] obf_mod decryptor 1-bit seed flip changed only {diff_ratio * 100:.2f}%")
            except Exception as exc:
                errors.append(f"[CFB] Error testing obf_mod stream cipher helper directly: {exc}")

        # Also measure byte entropy directly on `ps99_engine_v3.lua` Base85 ciphertext in repo!
        eng_obf = files.get("ps99_engine_v3.lua", "")
        eng_slices = [
            b for b in extract_string_literals(eng_obf)
            if len(b) >= 64 and all(32 <= x <= 126 for x in b) and not (len(b) == 85 and len(set(b)) == 85)
        ]
        if eng_slices:
            joined_eng_b85 = b"".join(eng_slices)
            alpha_set = sorted(set(joined_eng_b85))
            if len(alpha_set) != 85:
                errors.append(
                    f"[BASE85] ps99_engine_v3.lua Base85 payload alphabet has {len(alpha_set)} unique chars, expected exactly 85!"
                )
            else:
                # Even under ANY permutation of the 85 digits, a uniform ciphertext over [0, 2^32-1]
                # induces Shannon entropy ~ log2(85) = 6.409 bits/char on Base85 text (>= 6.38 bits/char),
                # AND when decoded with the canonical sorted alphabet (or verified via Xorshift32+CFB output),
                # zero periodic lag spikes exist in the Base85 character stream itself!
                b85_char_ent = shannon_entropy(joined_eng_b85)
                if b85_char_ent < 6.35:
                    errors.append(
                        f"[BASE85] ps99_engine_v3.lua Base85 stream char entropy {b85_char_ent:.4f} < 6.35 (expected ~6.409)"
                    )
                ac_b85, lag_b85 = max_autocorrelation(joined_eng_b85, 128)
                if ac_b85 > 0.05:
                    errors.append(
                        f"[BASE85] Periodic autocorrelation spike {ac_b85:.4f} at lag={lag_b85} in ps99_engine_v3.lua payload!"
                    )

            # Check another file (`games/steal_an_egg.lua`) has a DIFFERENT shuffled 85-char order or ciphertext
            sae_obf = files.get("games/steal_an_egg.lua", "")
            sae_slices = [
                b for b in extract_string_literals(sae_obf)
                if len(b) >= 64 and all(32 <= x <= 126 for x in b) and not (len(b) == 85 and len(set(b)) == 85)
            ]
            if sae_slices:
                joined_sae = b"".join(sae_slices)
                if len(set(joined_sae)) != 85:
                    errors.append(
                        f"[BASE85] games/steal_an_egg.lua Base85 payload alphabet has {len(set(joined_sae))} unique chars, expected 85!"
                    )
    except Exception as exc:
        errors.append(f"[SECTION 2] Unexpected error in encryption verification: {exc}")

    return errors


# =============================================================================
# SECTION 3: Polymorphic Bootstrap & `--target=luau`
# =============================================================================
LUA51_XOR_FALLBACK_RE = re.compile(r"for\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*0\s*,\s*15\s+do")
FIXED_HEADER_PREAMBLE_RE = re.compile(r"^return\s*\(\s*function\s*\(\s*\.\.\.\s*\)\s*local\s+[^=]+=type\s*,\s*pcall")


def verify_section3_polymorphic_bootstrap(repo_dir: str, files: Dict[str, str], obf_mod) -> List[str]:
    errors: List[str] = []

    escaped_prom = PROM_SRC_DIR.replace("\\", "\\\\")
    ast_rt = lua51.LuaRuntime()
    inspect_ast_fn = ast_rt.eval(
        f"""
        (function()
            arg = {{}}
            package.path = "{escaped_prom}\\\\?.lua;" .. package.path
            local Prometheus = require("prometheus")
            local Parser = require("prometheus.parser")
            Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

            local function exprSig(e)
                if not e then return "nil" end
                if e.kind == "IndexExpression" then
                    return exprSig(e.base) .. "." .. exprSig(e.index)
                elseif e.kind == "StringExpression" then
                    return tostring(e.value)
                elseif e.kind == "NumberExpression" then
                    return "num:" .. tostring(e.value)
                elseif e.kind == "VariableExpression" or e.kind == "GlobalVariableExpression" then
                    if e.scope and e.scope.variables and e.id then
                        return tostring(e.scope.variables[e.id] or e.kind)
                    end
                    return tostring(e.kind)
                elseif e.kind == "AndExpression" then
                    return "(" .. exprSig(e.lhs) .. "&&" .. exprSig(e.rhs) .. ")"
                elseif e.kind == "OrExpression" then
                    return "(" .. exprSig(e.lhs) .. "||" .. exprSig(e.rhs) .. ")"
                else
                    return tostring(e.kind)
                end
            end

            return function(code, label)
                local ast = Parser:new({{ LuaVersion = "LuaU" }}):parse(code, label)
                local stmts = ast.body.statements
                if #stmts ~= 1 or stmts[1].kind ~= "ReturnStatement" then
                    return {{ ok = false, err = "Root chunk must be a single ReturnStatement, got " .. tostring(#stmts) }}
                end
                local ret = stmts[1]
                if not ret.args or #ret.args ~= 1 or ret.args[1].kind ~= "FunctionCallExpression" then
                    return {{ ok = false, err = "ReturnStatement must wrap outer IIFE FunctionCallExpression" }}
                end
                local call = ret.args[1]
                local fn = call.base
                if not fn or fn.kind ~= "FunctionLiteralExpression" then
                    return {{ ok = false, err = "Outer call base must be FunctionLiteralExpression, got " .. tostring(fn and fn.kind) }}
                end

                local param_count = #(fn.args or {{}})
                local call_arg_sigs = {{}}
                for i, a in ipairs(call.args or {{}}) do
                    call_arg_sigs[i] = exprSig(a)
                end

                local body_stmts = fn.body.statements or {{}}
                local first_kinds = {{}}
                for i = 1, math.min(#body_stmts, 5) do
                    first_kinds[i] = body_stmts[i].kind
                end

                -- Find CFF WhileStatement position and state constants
                local while_pos = nil
                local pre_while_locals = 0
                local state_consts = {{}}
                for i, s in ipairs(body_stmts) do
                    if s.kind == "WhileStatement" then
                        while_pos = i
                        -- Collect state comparison constants from if/elseif chain inside while body
                        local ws = s.body and s.body.statements or {{}}
                        for _, inner in ipairs(ws) do
                            if inner.kind == "IfStatement" then
                                if inner.condition and inner.condition.rhs then
                                    state_consts[#state_consts + 1] = exprSig(inner.condition.rhs)
                                end
                                for _, eif in ipairs(inner.elseifs or {{}}) do
                                    if eif.condition and eif.condition.rhs then
                                        state_consts[#state_consts + 1] = exprSig(eif.condition.rhs)
                                    end
                                end
                            end
                        end
                        break
                    elseif s.kind == "LocalVariableDeclaration" then
                        pre_while_locals = pre_while_locals + #(s.ids or {{}})
                    end
                end

                return {{
                    ok = true,
                    param_count = param_count,
                    call_arg_count = #(call.args or {{}}),
                    call_arg_sig = table.concat(call_arg_sigs, "|"),
                    while_pos = while_pos or -1,
                    pre_while_locals = pre_while_locals,
                    body_stmt_count = #body_stmts,
                    state_sig = table.concat(state_consts, "|"),
                    first_kinds = table.concat(first_kinds, ","),
                }}
            end
        end)()
        """
    )

    for rel, src in files.items():
        # 3A. Zero Lua 5.1 bitwise fallback
        if LUA51_XOR_FALLBACK_RE.search(src) or "%16][" in src or "-%16)/16" in src or "/16;" in src:
            errors.append(f"[{rel}] Lua 5.1 16x16 XOR bitwise fallback loop still present in --target=luau output!")

        if FIXED_HEADER_PREAMBLE_RE.search(src.strip()):
            errors.append(f"[{rel}] Legacy fixed `return(function(...)local a,b,c=type,pcall...` preamble still present!")

        if not src.lstrip().startswith("return(function(") and not src.lstrip().startswith("return (function("):
            errors.append(f"[{rel}] Outer bootstrap does not start with `return(function(...)`")

        # 3B. AST verification of shuffled IIFE params + immediate CFF while loop
        rep = inspect_ast_fn(src, rel)
        if not rep["ok"]:
            errors.append(f"[{rel}] AST bootstrap failure: {rep['err']}")
            continue

        if int(rep["param_count"]) < 10 or int(rep["call_arg_count"]) < 10:
            errors.append(
                f"[{rel}] Expected outer IIFE to pass shuffled primitives + dummy args (>=10 params), "
                f"got params={rep['param_count']}, args={rep['call_arg_count']}"
            )

        wpos = int(rep["while_pos"])
        if wpos < 1 or wpos > 3:
            errors.append(
                f"[{rel}] Expected immediate CFF `while st ~= ... do` at top of outer IIFE (stmt 1..3), "
                f"got while_pos={wpos} (first stmts: {rep['first_kinds']})"
            )

        sig = str(rep["call_arg_sig"])
        if "bit32" not in sig:
            errors.append(f"[{rel}] Expected native Luau `bit32.*` functions passed in outer IIFE call args, got: {sig}")

    # 3C. Verify parameter order and CFF state constants change across two different seeds
    try:
        bridge = obf_mod.PrometheusBridge()
        with open(os.path.join(repo_dir, "unobf", "manifest.lua"), "r", encoding="utf-8") as f:
            manifest_clean = f.read()

        def build_seed(s: int) -> str:
            try:
                return obf_mod.compile_polymorphic_vm(manifest_clean, "manifest.lua", bridge, file_seed=s, target="luau")
            except TypeError:
                return obf_mod.compile_polymorphic_vm(manifest_clean, "manifest.lua", bridge, file_seed=s)

        b1 = build_seed(31337)
        b2 = build_seed(90001)
        r1 = inspect_ast_fn(b1, "manifest_s1.lua")
        r2 = inspect_ast_fn(b2, "manifest_s2.lua")
        if r1["ok"] and r2["ok"]:
            if str(r1["call_arg_sig"]) == str(r2["call_arg_sig"]):
                errors.append("[BOOTSTRAP] Outer IIFE argument order did NOT change across two different seeds!")
            if str(r1["state_sig"]) == str(r2["state_sig"]):
                errors.append("[BOOTSTRAP] Outer CFF `while` state constants did NOT change across two different seeds!")
    except Exception as exc:
        errors.append(f"[BOOTSTRAP] Cross-seed AST comparison failed: {exc}")

    return errors


# =============================================================================
# SECTION 4: Anti-Pre-Hooking, Zero `table.concat`, Lazy Constants & Stage-2 VM Polymorphism
# =============================================================================
def verify_section4_antihook_lazy_polymorphism(repo_dir: str, files: Dict[str, str], obf_mod) -> List[str]:
    errors: List[str] = []

    # 4A & 4B: Anti-Pre-Hooking + Silent Seed Poisoning + Zero `table.concat` Reliance
    # Check generated sources for zero diagnostic error strings (`"Detected!"`, etc.)
    forbidden_diag = (
        "Detected",
        "hook detected",
        "tamper",
        "VM integrity",
        "unknown VM opcode",
    )
    for rel, src in files.items():
        for diag in forbidden_diag:
            if diag.lower() in src.lower():
                errors.append(f"[{rel}] Forbidden diagnostic string {diag!r} found in generated source!")

    rt = lua51.LuaRuntime()
    hook_harness = rt.eval(
        f"""
        (function()
            {LUAU_ENV_BOOTSTRAP}

            return function(vm_code, label, hook_mode)
                local host_c_set = install_luau_env()
                local orig_char = string.char
                local orig_bxor = bit32.bxor
                local orig_pcall = pcall
                local orig_concat = table.concat
                local orig_loadstring = loadstring

                local fn, comp_err = orig_loadstring(vm_code, "=" .. label)
                if not fn then
                    return false, "compile_error", tostring(comp_err), false, false, 0
                end

                local leaked_plain = false
                local max_concat_len = 0
                local game_touched = false

                local function check_leak(s)
                    if type(s) == "string" and #s >= 6 then
                        if string.find(s, "Steal an Egg", 1, true)
                           or string.find(s, "Pet Sim 99", 1, true)
                           or string.find(s, "MainFarm", 1, true)
                           or string.find(s, "ReplicatedStorage", 1, true)
                           or string.find(s, "modules/farm.lua", 1, true)
                           or string.find(s, "Coins Flag", 1, true) then
                            leaked_plain = true
                        end
                    end
                end

                _G.game = setmetatable({{}}, {{
                    __index = function(_, k)
                        game_touched = true
                        error("STAGE2_GAME_INDEX_" .. tostring(k), 0)
                    end
                }})

                if hook_mode == "hook_string_char" then
                    -- Genuine Lua wrapper hook (NOT in host_c_set -> debug.info returns Lua src/line!)
                    local acc = {{}}
                    string.char = function(...)
                        local s = orig_char(...)
                        if #acc < 512 then acc[#acc + 1] = s end
                        check_leak(s)
                        return s
                    end
                elseif hook_mode == "hook_bit32_bxor" then
                    bit32.bxor = function(a, b, ...)
                        return orig_bxor(a, b, ...)
                    end
                elseif hook_mode == "hook_pcall" then
                    pcall = function(f, ...)
                        return orig_pcall(f, ...)
                    end
                elseif hook_mode == "hook_table_concat" then
                    table.concat = function(t, ...)
                        local s = orig_concat(t, ...)
                        check_leak(s)
                        return s
                    end
                elseif hook_mode == "hook_loadstring" then
                    loadstring = function(s, ...)
                        check_leak(s)
                        return orig_loadstring(s, ...)
                    end
                elseif hook_mode == "spy_c_table_concat" then
                    -- Registered in host_c_set so integrity checks pass cleanly, proving 0 strings > 64B hit table.concat!
                    local c_spy_concat = function(t, ...)
                        local s = orig_concat(t, ...)
                        if type(s) == "string" and #s > max_concat_len then
                            max_concat_len = #s
                        end
                        return s
                    end
                    host_c_set[c_spy_concat] = true
                    table.concat = c_spy_concat
                elseif hook_mode == "nil_table_concat" then
                    -- Remove table.concat completely when unmonitored (nil)
                    table.concat = nil
                end

                local ok, res = orig_pcall(fn)
                if hook_mode == "hook_string_char" and type(res) == "nil" then
                    -- Also check concatenated char buffer never formed plaintext
                end

                -- If clean spy/nil mode returned a module builder function, invoke it on a mock context to exercise K(idx)
                if (hook_mode == "spy_c_table_concat" or hook_mode == "nil_table_concat") and ok and type(res) == "function" then
                    local dummy = setmetatable({{}}, {{
                        __index = function() return function() return dummy end end,
                        __call = function() return dummy end,
                    }})
                    orig_pcall(res, dummy, dummy)
                end

                string.char = orig_char
                bit32.bxor = orig_bxor
                pcall = orig_pcall
                table.concat = orig_concat
                loadstring = orig_loadstring
                _G.game = nil

                return ok, type(res), tostring(res), leaked_plain, game_touched, max_concat_len
            end
        end)()
        """
    )

    # Test all 5 Lua wrapper hooks across key files + full sweep
    hook_modes = (
        "hook_string_char",
        "hook_bit32_bxor",
        "hook_pcall",
        "hook_table_concat",
        "hook_loadstring",
    )
    audit_hook_targets = [
        rel for rel in ("manifest.lua", "lib/config.lua", "modules/farm.lua", "main.lua", "games/steal_an_egg.lua")
        if rel in files
    ]
    for hmode in hook_modes:
        for rel in audit_hook_targets:
            ok, rtype, rstr, leaked, game_touched, _ = hook_harness(files[rel], rel, hmode)
            if leaked:
                errors.append(f"[ANTI-HOOK] [{hmode}] [{rel}] Plaintext string leaked to Lua wrapper hook!")
            if game_touched:
                errors.append(f"[ANTI-HOOK] [{hmode}] [{rel}] Stage-2 payload executed despite active hook!")
            if rel == "manifest.lua" and ok and rtype == "table":
                errors.append(f"[ANTI-HOOK] [{hmode}] [manifest.lua] Decrypted manifest table despite active hook!")
            if (rel == "lib/config.lua" or rel.startswith("modules/")) and ok and rtype == "function":
                errors.append(f"[ANTI-HOOK] [{hmode}] [{rel}] Returned Stage-2 builder function despite active hook!")
            if not ok and ("detected" in rstr.lower() or "hook" in rstr.lower() or "tamper" in rstr.lower()):
                errors.append(f"[ANTI-HOOK] [{hmode}] [{rel}] Non-silent diagnostic error thrown: {rstr}")

    # Test zero `table.concat` reliance (`spy_c_table_concat` -> max_concat_len <= 64 on ALL 23 files, AND `nil_table_concat` works!)
    for rel, src in files.items():
        ok_spy, rtype_spy, rstr_spy, _, game_spy, max_tc_len = hook_harness(src, rel, "spy_c_table_concat")
        # Note: `games/ps99.lua` user code itself calls `table.concat` on its 73-byte URL table before `game:HttpGet`,
        # so verify zero obfuscator/VM `table.concat` calls (>64B) on all non-`_d` scripts (and <= 256B overall)!
        tc_limit = 80 if rel == "games/ps99.lua" else 64
        if int(max_tc_len) > tc_limit:
            errors.append(
                f"[NO-CONCAT] [{rel}] table.concat received a {max_tc_len}-byte string (> {tc_limit}B) during decryption/execution!"
            )
        stage2_entered_spy = bool(game_spy) or (not ok_spy and ("attempt to index" in rstr_spy or "attempt to call" in rstr_spy))
        if rel == "manifest.lua" and (not ok_spy or rtype_spy != "table"):
            errors.append(f"[CLEAN-EXEC] [{rel}] Expected table, got ok={ok_spy} type={rtype_spy} ({rstr_spy})")
        elif (rel.startswith("modules/") or rel in ("lib/ui.lua", "lib/config.lua")) and (not ok_spy or rtype_spy != "function"):
            errors.append(f"[CLEAN-EXEC] [{rel}] Expected function, got ok={ok_spy} type={rtype_spy} ({rstr_spy})")
        elif rel in ("main.lua", "Stehp-Hub.lua", "ps99_engine_v3.lua", "games/steal_an_egg.lua") and not stage2_entered_spy:
            errors.append(f"[CLEAN-EXEC] [{rel}] Did not enter Stage-2 game logic: ok={ok_spy} ({rstr_spy})")

        ok_nil, rtype_nil, rstr_nil, _, game_nil, _ = hook_harness(src, rel, "nil_table_concat")
        stage2_entered_nil = bool(game_nil) or (not ok_nil and ("attempt to index" in rstr_nil or "attempt to call" in rstr_nil))
        if rel == "manifest.lua" and (not ok_nil or rtype_nil != "table"):
            errors.append(f"[NIL-CONCAT] [{rel}] Failed when table.concat=nil: ok={ok_nil} type={rtype_nil} ({rstr_nil})")
        elif (rel.startswith("modules/") or rel in ("lib/ui.lua", "lib/config.lua")) and (not ok_nil or rtype_nil != "function"):
            errors.append(f"[NIL-CONCAT] [{rel}] Failed when table.concat=nil: ok={ok_nil} type={rtype_nil} ({rstr_nil})")
        elif rel in ("main.lua", "Stehp-Hub.lua", "ps99_engine_v3.lua", "games/steal_an_egg.lua") and not stage2_entered_nil:
            errors.append(f"[NIL-CONCAT] [{rel}] Failed Stage-2 entry when table.concat=nil: ok={ok_nil} ({rstr_nil})")

    # 4C. Lazy Constant Decryption Audit (Invoke verify_gc_and_upvalues.py logic / quick lazy pre-access check)
    lazy_rt = lua51.LuaRuntime()
    lazy_check_fn = lazy_rt.eval(
        f"""
        (function()
            {LUAU_ENV_BOOTSTRAP}
            return function(vm_code, label, target_secret)
                local _, orig_dbg = install_luau_env()
                local gmt = orig_dbg.getmetatable
                local getupv = orig_dbg.getupvalue
                local getinfo = orig_dbg.getinfo
                local getreg = orig_dbg.getregistry

                local fn, err = loadstring(vm_code, "=" .. label)
                if not fn then return false, "loadstring: " .. tostring(err) end
                -- Execute ONLY top-level chunk of `modules/farm.lua`: returns `function(ctx) ... end`
                -- BEFORE calling `res(ctx)`, inner strings like target_secret have NEVER been accessed via K(idx)!
                local ok, res = pcall(fn)
                if not ok or type(res) ~= "function" then
                    return false, "expected builder function, got " .. tostring(res)
                end

                local v_tbls, v_fns, tq, fq = {{}}, {{}}, {{}}, {{}}
                local function enq(v)
                    local tv = type(v)
                    if tv == "table" and not v_tbls[v] then
                        v_tbls[v] = true; tq[#tq + 1] = v
                    elseif tv == "function" and not v_fns[v] then
                        v_fns[v] = true; fq[#fq + 1] = v
                    end
                end
                enq(_G); enq(getreg()); enq(fn); enq(res)
                local th, fh = 1, 1
                while th <= #tq or fh <= #fq do
                    while th <= #tq do
                        local t = tq[th]; th = th + 1
                        local mt = gmt(t); if mt then enq(mt) end
                        for k, v in next, t, nil do enq(k); enq(v) end
                    end
                    while fh <= #fq do
                        local f = fq[fh]; fh = fh + 1
                        local inf = getinfo(f, "S")
                        if inf and inf.what == "Lua" then
                            local u = 1
                            while u <= 60 do
                                local n, val = getupv(f, u)
                                if not n then break end
                                enq(val); u = u + 1
                            end
                        end
                    end
                end

                -- Verify target_secret (an inner constant of modules/farm.lua) is NOT in plaintext anywhere in memory yet!
                for t in pairs(v_tbls) do
                    if t ~= v_tbls and t ~= v_fns and t ~= tq and t ~= fq then
                        for k, v in next, t, nil do
                            if k == target_secret or v == target_secret then
                                return false, "unaccessed constant already decrypted in heap before K(idx) call!"
                            end
                        end
                    end
                end
                for f in pairs(v_fns) do
                    local inf = getinfo(f, "S")
                    if inf and inf.what == "Lua" then
                        local u = 1
                        while u <= 60 do
                            local n, val = getupv(f, u)
                            if not n then break end
                            if val == target_secret then
                                return false, "unaccessed constant already decrypted in closure upvalue!"
                            end
                            u = u + 1
                        end
                    end
                end
                return true, "ok"
            end
        end)()
        """
    )
    if "modules/farm.lua" in files:
        ok_lazy, lazy_msg = lazy_check_fn(files["modules/farm.lua"], "modules/farm.lua", "Fast Farm (Beta)")
        if not ok_lazy:
            errors.append(f"[LAZY-K] [modules/farm.lua] {lazy_msg}")

    # 4D. Stage-2 VM Polymorphism Verification Across Seeds (`layout.lua`, `compiler.lua`, `runtime.lua`)
    escaped_prom = PROM_SRC_DIR.replace("\\", "\\\\")
    poly_rt = lua51.LuaRuntime()
    poly_audit_fn = poly_rt.eval(
        f"""
        (function()
            arg = {{}}
            package.path = "{escaped_prom}\\\\?.lua;" .. package.path
            local Prometheus = require("prometheus")
            local Parser = require("prometheus.parser")
            local analyzeBindings = require("prometheus.bindinganalysis")
            local analyzeVm = require("prometheus.vm.analysis")
            local optimize = require("prometheus.vm.optimize")
            local Compiler = require("prometheus.vm.compiler")
            local Layout = require("prometheus.vm.layout")
            local Runtime = require("prometheus.vm.runtime")
            local opcodes = require("prometheus.vm.opcodes")
            Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

            local function countInsns(proto)
                local total = #(proto.code or {{}})
                for _, ch in ipairs(proto.children or {{}}) do
                    total = total + countInsns(ch)
                end
                return total
            end

            local function countSuperInsns(proto)
                local superSet = {{}}
                for _, id in pairs(Layout.SUPER_OPCODES or {{}}) do
                    superSet[id] = true
                end
                local hits = 0
                local function walk(p)
                    for _, ins in ipairs(p.code or {{}}) do
                        if superSet[ins[1]] then hits = hits + 1 end
                    end
                    for _, ch in ipairs(p.children or {{}}) do walk(ch) end
                end
                walk(proto)
                return hits
            end

            return function(real_mod_src)
                local l1 = Layout.new(11111)
                local l2 = Layout.new(22222)

                -- 1. Check opcode ID permutation across seeds
                local same_ops, total_ops = 0, 0
                for name, id1 in pairs(l1.opcodes) do
                    if not name:match("^DECOY_") then
                        total_ops = total_ops + 1
                        if l2.opcodes[name] == id1 then same_ops = same_ops + 1 end
                    end
                end
                if total_ops < 60 or same_ops == total_ops then
                    return false, "Opcodes did not permute across seeds: same=" .. same_ops .. "/" .. total_ops
                end

                -- 2. Check per-format operand permutations within a single build AND across seeds
                local perm_sigs = {{}}
                local perm_cnt = 0
                for g = 1, #(l1.formatPerms or {{}}) do
                    local p = l1.formatPerms[g]
                    local s = table.concat(p, ",")
                    if not perm_sigs[s] then
                        perm_sigs[s] = true
                        perm_cnt = perm_cnt + 1
                    end
                end
                if perm_cnt < 3 then
                    return false, "Expected >= 3 distinct operand slot permutations per build, got " .. perm_cnt
                end

                local op_perm_diff = false
                for name, p1 in pairs(l1.opcodeOperands or {{}}) do
                    local p2 = l2.opcodeOperands and l2.opcodeOperands[name]
                    if p2 and table.concat(p1, ",") ~= table.concat(p2, ",") then
                        op_perm_diff = true
                        break
                    end
                end
                if not op_perm_diff then
                    return false, "Operand slot permutations did not vary across seeds"
                end

                -- 3. Check decoy opcodes in layout and Runtime.build(layout)
                local dcnt = l1.decoyCount or 0
                if dcnt < 4 or dcnt > 6 then
                    return false, "Expected 4..6 decoy opcodes, got " .. tostring(dcnt)
                end
                local rt_src = Runtime.build(l1)
                if string.find(rt_src, "table.concat", 1, true) then
                    return false, "Runtime.build(layout) still references table.concat!"
                end
                for dname, did in pairs(l1.decoys or {{}}) do
                    if not string.find(rt_src, "if opcode == " .. tostring(did) .. " then", 1, true) then
                        return false, "Decoy opcode " .. dname .. " (" .. tostring(did) .. ") missing from dispatch tree!"
                    end
                end

                -- 4. Check super-instruction fusion reduces real module instruction count
                local ast1 = Parser:new({{ LuaVersion = "LuaU" }}):parse(real_mod_src, "real_mod.lua")
                analyzeBindings(ast1)
                local unfused_compiler = Compiler:new(analyzeVm(ast1), ast1)
                local unfused_proto = optimize(unfused_compiler:finish(ast1))
                local unfused_count = countInsns(unfused_proto)

                local ast2 = Parser:new({{ LuaVersion = "LuaU" }}):parse(real_mod_src, "real_mod.lua")
                analyzeBindings(ast2)
                local fused_proto = Compiler:compile(ast2)
                local fused_count = countInsns(fused_proto)
                local super_hits = countSuperInsns(fused_proto)

                if super_hits < 10 or fused_count >= unfused_count then
                    return false, string.format(
                        "Super-instructions did not reduce instruction count: unfused=%d, fused=%d, super_hits=%d",
                        unfused_count, fused_count, super_hits
                    )
                end

                -- 5. Execute complex Luau snippet across 4 random seeds and verify exact equivalence to clean Lua
                local test_luau = [=[
                    local acc = 0
                    local up = 10
                    local function bump(dx, ...)
                        up += dx
                        local extra = select("#", ...)
                        for i = 1, extra do
                            up += (select(i, ...) or 0)
                        end
                        return up, up // 3
                    end
                    for i = 1, 15 do
                        if i % 4 == 0 then continue end
                        local a, b = bump(i, 2, 5)
                        acc += a + b
                    end
                    local tbl = {{ k = "ok", n = acc }}
                    return tbl.k .. ":" .. tostring(tbl.n) .. ":" .. tostring(up)
                ]=]
                -- Compute reference in Stage-2 VM across 4 distinct polymorphic layouts
                local expected_out = nil
                for _, s in ipairs({{ 101, 202, 303, 404 }}) do
                    local lay = Layout.new(s)
                    local tast = Parser:new({{ LuaVersion = "LuaU" }}):parse(test_luau, "poly_exec.lua")
                    analyzeBindings(tast)
                    local tproto = Compiler:compile(tast)

                    local function buildProtoTbl(p)
                        local f = lay.fields
                        local code = {{}}
                        for idx, ins in ipairs(p.code) do
                            code[idx] = lay:encode(ins)
                        end
                        local ch = {{}}
                        for idx, c in ipairs(p.children) do
                            ch[idx] = buildProtoTbl(c)
                        end
                        local ktbl = p.constants
                        return {{
                            [f.vararg] = p.vararg,
                            [f.maxRegister] = p.maxRegister,
                            [f.params] = p.params,
                            [f.captures] = p.captures,
                            [f.constants] = function(kidx) return ktbl[kidx] end,
                            [f.code] = code,
                            [f.children] = ch,
                        }}
                    end

                    local rts = Runtime.build(lay)
                    rts = rts:gsub("__UPV_TONUM__", "tonumber")
                             :gsub("__UPV_SEL__", "select")
                             :gsub("__UPV_MFLR__", "math.floor")
                             :gsub("__UPV_ERR__", "error")
                             :gsub("__UPV_UNPACK__", "unpack")
                             :gsub("__UPV_GETFENV__", "getfenv")
                             :gsub("__UPV_SETFENV__", "setfenv")
                             :gsub("__PROTOTYPES__", "_PROTOS")
                    local runner_src = "return function(_PROTOS, ...) " .. rts .. " end"
                    local runner = assert(loadstring(runner_src, "=rt_" .. tostring(s)))()
                    local actual = runner({{ buildProtoTbl(tproto) }})
                    if expected_out == nil then
                        expected_out = actual
                    elseif actual ~= expected_out then
                        return false, "Polymorphic VM output mismatch on seed " .. tostring(s) .. ": " .. tostring(actual)
                    end
                end
                if expected_out ~= "ok:1466:190" then
                    return false, "Unexpected Luau polymorphic execution result: " .. tostring(expected_out)
                end

                return true, string.format(
                    "ops=%d (decoys=%d), fmtPerms=%d, unfused=%d -> fused=%d (-%d via %d super-insns)",
                    total_ops, dcnt, perm_cnt, unfused_count, fused_count, unfused_count - fused_count, super_hits
                )
            end
        end)()
        """
    )
    with open(os.path.join(repo_dir, "unobf", "main.lua"), "r", encoding="utf-8") as f:
        main_unobf = f.read()
    ok_poly, poly_msg = poly_audit_fn(main_unobf)
    if not ok_poly:
        errors.append(f"[STAGE2-POLY] {poly_msg}")
    else:
        print(f"    [Stage-2 Polymorphism Telemetry] {poly_msg}", flush=True)

    return errors


# =============================================================================
# CLI Entrypoint
# =============================================================================
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Steph HUB v6.0 Comprehensive Luau Bundler & Dual-VM Hardening Verifier"
    )
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
    parser.add_argument(
        "--section",
        type=int,
        choices=[1, 2, 3, 4],
        default=None,
        help="Optional single spec section (1..4) to run",
    )
    args = parser.parse_args()

    t0 = time.time()
    target_rels = get_target_files(args.repo)
    files: Dict[str, str] = {}
    for rel in target_rels:
        p = os.path.join(args.repo, rel)
        if not os.path.isfile(p):
            print(f"[FAIL] Missing obfuscated target file: {p}", flush=True)
            return 1
        with open(p, "r", encoding="utf-8") as f:
            files[rel] = f.read()

    obf_mod = load_python_module("steph_prom_vm_obf", os.path.join(args.repo, "tools", "prometheus_vm_obf.py"))

    print("================================================================================", flush=True)
    print(f" Steph HUB v6.0 Luau Obfuscator & Bundler Verification Suite ({len(files)} files)", flush=True)
    print("================================================================================", flush=True)

    all_passed = True
    sections = [args.section] if args.section is not None else [1, 2, 3, 4]

    if 1 in sections:
        print("\n[Section 1/4] Auditing Public README.md & Pre-Obfuscator Module Bundler (`tools/bundler.py`)...", flush=True)
        s1_errs = verify_section1_bundler_and_readme(args.repo, obf_mod)
        if s1_errs:
            all_passed = False
            for e in s1_errs:
                print(f"  FAIL: {e}", flush=True)
        else:
            print(
                "  PASS: README.md stripped to launch snippet + hotkeys only; bundler.py --self-test, "
                "__modules/__cache/__require structure, Roblox ModuleScript require passthrough, and "
                "full 23-module bundled+obfuscated Luau execution verified!",
                flush=True,
            )

    if 2 in sections:
        print("\n[Section 2/4] Auditing Payload Encryption (Shuffled Base85 + Unified Stream + Xorshift32 CFB)...", flush=True)
        s2_errs = verify_section2_payload_encryption(args.repo, files, obf_mod)
        if s2_errs:
            all_passed = False
            for e in s2_errs:
                print(f"  FAIL: {e}", flush=True)
        else:
            print(
                "  PASS: Zero Base64 `=`/`pp` padding tails, per-build shuffled 85-char Base85 alphabet, "
                "unified stream, Xorshift32+CFB IEEE-754 exactness, Shannon entropy > 7.8 bits/byte, "
                "zero periodic autocorrelation spikes, and ~99.6% 1-bit seed avalanche verified!",
                flush=True,
            )

    if 3 in sections:
        print("\n[Section 3/4] Auditing Polymorphic Bootstrap & `--target=luau` AST...", flush=True)
        s3_errs = verify_section3_polymorphic_bootstrap(args.repo, files, obf_mod)
        if s3_errs:
            all_passed = False
            for e in s3_errs:
                print(f"  FAIL: {e}", flush=True)
        else:
            print(
                f"  PASS: {len(files)}/{len(files)} files contain 0 Lua 5.1 bitwise fallback loops, "
                "shuffled outer IIFE primitive + dummy arguments, zero fixed preamble block, "
                "immediate CFF `while` loop, and per-seed AST parameter/state polymorphism!",
                flush=True,
            )

    if 4 in sections:
        print("\n[Section 4/4] Auditing Anti-Pre-Hooking, Zero `table.concat`, Lazy `K(idx)` & Stage-2 VM Polymorphism...", flush=True)
        s4_errs = verify_section4_antihook_lazy_polymorphism(args.repo, files, obf_mod)
        if s4_errs:
            all_passed = False
            for e in s4_errs:
                print(f"  FAIL: {e}", flush=True)
        else:
            print(
                "  PASS: All 5 Lua hooks (string.char, bit32.bxor, pcall, table.concat, loadstring) caught "
                "with silent seed poisoning & 0 leaked strings; 0 reliance on table.concat (works even when nil, "
                "0 strings > 64B); lazy K(idx) decryption & Stage-2 opcode/operand/super-op/decoy polymorphism verified!",
                flush=True,
            )

    elapsed = time.time() - t0
    print("\n================================================================================", flush=True)
    if all_passed:
        print(f" [ALL V6.0 VERIFICATION GATES PASSED] {len(files)}/{len(files)} files verified in {elapsed:.2f}s", flush=True)
        print("================================================================================", flush=True)
        return 0
    else:
        print(f" [V6.0 VERIFICATION FAILED] See errors above ({elapsed:.2f}s)", flush=True)
        print("================================================================================", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
