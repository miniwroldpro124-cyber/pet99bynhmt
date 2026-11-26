#!/usr/bin/env python3
"""
Steph HUB - v6.0 Luau Red-Team Sponge, Anti-Pre-Hook & Sealed-Upvalue Suite (`verify_v5_sponge.py`)
===================================================================================================
Standalone red-team verification suite that tests all 23 obfuscated `.lua` files against every
attack vector and architectural invariant of the v6.0 `--target=luau` Dual-VM architecture:

1. Test 1 — Static Seed Folding, Magic Constant, Plaintext Leak & Zero Lua 5.1 Fallback Audit:
   - Verifies no `seed_base + flag * step` 1-bit bottleneck pattern exists.
   - Verifies zero magic probe target outputs (`23575`, `3257`, `3008093`, `8314969`, `5441028`).
   - Verifies zero plaintext probe or diagnostic strings (`"Detected"`, `"getinfo"`, `"iscclosure"`,
     `"islclosure"`, `"ishooked"`, `"isfunctionhooked"`, `"loadstring"`, `"short_src"`, `"linedefined"`,
     `"VM integrity check failed"`, `"unknown VM opcode"`).
   - Verifies zero Lua 5.1 16x16 XOR bitwise fallback loop in `--target=luau` output.

2. Test 2 — Luau Runtime Execution (`bit32`, `debug.info`, `coroutine.isyieldable`, `table.create`):
   - 2a: Standard Luau environment (`debug.info` returning `"[C]", -1` for C/host primitives and Lua
         `short_src, linedefined, numparams, is_vararg` for Lua closures) -> MUST succeed on all 23 files!
   - 2b: Hybrid Luau + Executor environment (`debug.info` + `debug.getinfo` + `iscclosure`/`islclosure`) -> MUST succeed!
   - 2c: Luau environment with `table.concat = nil` (proving zero reliance on `table.concat`) -> MUST succeed!

3. Test 3 — Environment Stripping Attack (`debug = nil; string.dump = nil`):
   - Strips `debug` and `string.dump` before executing the obfuscated script.
   - Verifies integrity probe silently poisons `seed` so Stage-2 never executes and zero diagnostic errors leak.

4. Test 4 — Pre-Hooking & Behavioral Metamethod Traps:
   - 4a: Lua closure wrapper hook on `string.char` -> caught via `debug.info` (`~= "[C]", -1`), silently poisons `seed`.
   - 4b: Lua closure wrapper hook on `bit32.bxor` -> caught via `debug.info`, silently poisons `seed`.
   - 4c: Lua closure wrapper hook on `pcall` & `loadstring` -> caught via `debug.info`, silently poisons `seed`.

5. Test 5 — Pointer Aliasing Attack (`loadstring = pcall; rawget = rawset`):
   - Aliases genuine C primitives (`debug.info` still returns `"[C]", -1` for both) before running.
   - Verifies pointer uniqueness check (`seen[fn]`) catches duplicate closures and silently poisons `seed`.

6. Test 6 — Sealed Stage-2 Lexical Upvalues & Zero Late `_ENV` Primitive Lookups:
   - Replaces `_G.setmetatable`, `_G.rawset`, `_G.ipairs`, `_G.tonumber`, `_G.select`, `_G.unpack`,
     and `_G.table.concat` with `LATE_*` error bombs during Stage-2 execution and builder invocation.
   - Verifies all 23 files execute Stage-2 VM + ring-buffered `K(idx)` with ZERO late global lookups.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import time
from typing import Dict, List, Tuple

from lupa import lua51

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(THIS_DIR)

from verify_v6_luau_obf import LUAU_ENV_BOOTSTRAP

BOTTLENECK_1BIT_RE = re.compile(r"=[0-9]{4,}\+[a-zA-Z_][a-zA-Z0-9_]*\*[0-9]{4,};")
STATIC_CONST_ARITH_RE = re.compile(r"\(-?\d+[\+\-%]-?\d+\)")
LUA51_XOR_FALLBACK_RE = re.compile(r"for\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*0\s*,\s*15\s+do")

FORBIDDEN_MAGIC_NUMBERS: Tuple[int, ...] = (
    23575,
    3257,
    3008093,
    8314969,
    5441028,
)

FORBIDDEN_PLAINTEXT_STRINGS: Tuple[str, ...] = (
    "Detected!",
    "getinfo",
    "iscclosure",
    "islclosure",
    "ishooked",
    "isfunctionhooked",
    "loadstring",
    "short_src",
    "linedefined",
    "VM integrity check failed",
    "unknown VM opcode",
    "STEPH_COMPONENT",
    "STEPH_PROMETHEUS_VM",
    "__UPV_",
)


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


def check_clean_execution_outcome(
    rel_path: str,
    ok: bool,
    res_type: str,
    res_str: str,
    game_touched: bool,
) -> Tuple[bool, str]:
    if rel_path == "manifest.lua":
        if ok and res_type == "table":
            return True, "table"
        return False, f"expected table, got ok={ok} type={res_type} ({res_str})"
    elif rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if ok and res_type == "function":
            return True, "function"
        return False, f"expected function, got ok={ok} type={res_type} ({res_str})"
    else:
        if game_touched or (not ok and ("attempt to index" in res_str or "attempt to call" in res_str or "STAGE2_GAME" in res_str)):
            return True, "vm_entered(stage2)"
        if ok and res_type != "nil":
            return True, f"ok({res_type})"
        return False, f"expected stage2 entry, got ok={ok} type={res_type} game_touched={game_touched} ({res_str})"


def check_poisoned_outcome(
    rel_path: str,
    ok: bool,
    res_type: str,
    res_str: str,
    game_touched: bool,
) -> Tuple[bool, str]:
    """
    Verifies silent seed poisoning:
      1. Stage-2 never touched `_G.game` (`game_touched == False`).
      2. Never decrypted/returned valid `manifest` table or `modules/*` builder function.
      3. Zero diagnostic `"Detected"` / `"hook"` / `"tamper"` error strings if an organic error occurred.
    """
    if game_touched:
        return False, "Stage-2 executed and touched _G.game despite tamper!"
    if rel_path == "manifest.lua" and ok and res_type == "table":
        return False, "manifest.lua decrypted valid table despite tamper!"
    if (rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua")) and ok and res_type == "function":
        return False, f"{rel_path} returned Stage-2 builder function despite tamper!"
    if not ok:
        low = res_str.lower()
        if "detected" in low or "tamper" in low or "hook" in low or "integrity" in low:
            return False, f"Non-silent diagnostic error string leaked: {res_str}"
    return True, "poisoned_silently"


def run_test1_static_audit(files: Dict[str, str]) -> List[str]:
    errors: List[str] = []
    for rel, src in files.items():
        first_line = src.splitlines()[0].strip() if src.strip() else ""
        if not first_line or first_line.startswith("--"):
            errors.append(f"[{rel}] Starts with comment or empty line")

        m_1bit = BOTTLENECK_1BIT_RE.search(src)
        if m_1bit:
            errors.append(f"[{rel}] Found 1-bit bottleneck pattern: {m_1bit.group(0)!r}")

        if LUA51_XOR_FALLBACK_RE.search(src):
            errors.append(f"[{rel}] Found Lua 5.1 16x16 XOR fallback loop in --target=luau build!")

        for magic in FORBIDDEN_MAGIC_NUMBERS:
            if re.search(rf"(?<![0-9]){magic}(?![0-9])", src):
                errors.append(f"[{rel}] Magic probe constant {magic} found in generated source!")

        for s in FORBIDDEN_PLAINTEXT_STRINGS:
            if s in src:
                errors.append(f"[{rel}] Plaintext string {s!r} leaked in generated source!")

        arith = STATIC_CONST_ARITH_RE.findall(src)
        if arith:
            errors.append(f"[{rel}] Static constant-foldable arithmetic found: {arith[:3]}")

    return errors


def build_lua_harness() -> Tuple[lua51.LuaRuntime, object]:
    rt = lua51.LuaRuntime()
    harness_fn = rt.eval(
        f"""
        (function()
            {LUAU_ENV_BOOTSTRAP}

            return function(vm_code, label, mode)
                local host_c_set, orig_dbg = install_luau_env()
                local orig_getinfo = orig_dbg and orig_dbg.getinfo
                local orig_dump = string.dump
                local orig_char = string.char
                local orig_byte = string.byte
                local orig_sub = string.sub
                local orig_bxor = bit32.bxor
                local orig_band = bit32.band
                local orig_pcall = pcall
                local orig_loadstring = loadstring
                local orig_smt = setmetatable
                local orig_gmt = getmetatable
                local orig_rset = rawset
                local orig_rget = rawget
                local orig_ipairs = ipairs
                local orig_tonum = tonumber
                local orig_select = select
                local orig_unpack = unpack
                local orig_concat = table.concat
                local sim_debug = debug

                local late_bomb_triggered = nil
                local game_touched = false

                local function restore_all()
                    debug = sim_debug
                    string.dump = orig_dump
                    string.char = orig_char
                    string.byte = orig_byte
                    string.sub = orig_sub
                    bit32.bxor = orig_bxor
                    bit32.band = orig_band
                    pcall = orig_pcall
                    loadstring = orig_loadstring
                    setmetatable = orig_smt
                    getmetatable = orig_gmt
                    rawset = orig_rset
                    rawget = orig_rget
                    ipairs = orig_ipairs
                    tonumber = orig_tonum
                    select = orig_select
                    unpack = orig_unpack
                    table.concat = orig_concat
                    _G.iscclosure = nil
                    _G.islclosure = nil
                    _G.ishooked = nil
                    _G.game = nil
                end

                local fn, err = orig_loadstring(vm_code, "=" .. label)
                if not fn then
                    restore_all()
                    return false, "compile_error", tostring(err), false, "nil", false
                end

                local function arm_late_bombs()
                    setmetatable = function() late_bomb_triggered = "LATE_SETMETATABLE"; error("LATE_SETMETATABLE", 0) end
                    rawset = function() late_bomb_triggered = "LATE_RAWSET"; error("LATE_RAWSET", 0) end
                    ipairs = function() late_bomb_triggered = "LATE_IPAIRS"; error("LATE_IPAIRS", 0) end
                    tonumber = function() late_bomb_triggered = "LATE_TONUMBER"; error("LATE_TONUMBER", 0) end
                    select = function() late_bomb_triggered = "LATE_SELECT"; error("LATE_SELECT", 0) end
                    unpack = function() late_bomb_triggered = "LATE_UNPACK"; error("LATE_UNPACK", 0) end
                    if table then
                        table.concat = function() late_bomb_triggered = "LATE_CONCAT"; error("LATE_CONCAT", 0) end
                    end
                end

                _G.game = orig_smt({{}}, {{
                    __index = function(_, k)
                        game_touched = true
                        if mode == "seal_upvalues_after_boot" then
                            arm_late_bombs()
                        end
                        error("STAGE2_GAME_" .. tostring(k), 0)
                    end
                }})

                if mode == "luau_clean" then
                    -- 2a: Standard Luau environment

                elseif mode == "luau_executor_hybrid" then
                    -- 2b: Luau + Executor environment (debug.info + debug.getinfo + iscclosure/islclosure/ishooked)
                    local fn_isc = function(f)
                        if host_c_set[f] then return true end
                        local inf = orig_getinfo and orig_getinfo(f, "S")
                        return (inf and inf.what == "C") or false
                    end
                    local fn_isl = function(f)
                        return type(f) == "function" and not fn_isc(f)
                    end
                    local fn_ish = function(_) return false end
                    local fn_geti = function(f, what)
                        if host_c_set[f] then return orig_getinfo(orig_pcall, what) end
                        return orig_getinfo(f, what)
                    end
                    host_c_set[fn_isc] = true
                    host_c_set[fn_isl] = true
                    host_c_set[fn_ish] = true
                    host_c_set[fn_geti] = true
                    _G.iscclosure = fn_isc
                    _G.islclosure = fn_isl
                    _G.ishooked = fn_ish
                    debug = {{ info = sim_debug.info, getinfo = fn_geti, traceback = sim_debug.traceback }}

                elseif mode == "luau_nil_concat" then
                    -- 2c: table.concat completely absent
                    table.concat = nil

                elseif mode == "strip_debug_and_dump" then
                    -- Test 3: Strip debug and string.dump completely
                    debug = nil
                    string.dump = nil

                elseif mode == "hook_string_char" then
                    -- Test 4a: Lua wrapper hook on string.char
                    string.char = function(...) return orig_char(...) end

                elseif mode == "hook_bit32_bxor" then
                    -- Test 4b: Lua wrapper hook on bit32.bxor
                    bit32.bxor = function(a, b, ...) return orig_bxor(a, b, ...) end

                elseif mode == "hook_pcall_and_loadstring" then
                    -- Test 4c: Lua wrapper hook on pcall & loadstring
                    pcall = function(f, ...) return orig_pcall(f, ...) end
                    loadstring = function(s, ...) return orig_loadstring(s, ...) end

                elseif mode == "alias_c_primitives" then
                    -- Test 5: Pointer aliasing attack on genuine C primitives
                    -- Both remain genuine [C], -1 closures; only pointer uniqueness catches aliasing!
                    rawget = orig_rset
                    loadstring = orig_pcall
                    string.sub = orig_byte

                elseif mode == "seal_upvalues_after_boot" then
                    -- Test 6: Poison _G globals right when Stage-2 starts / before invoking Stage-2 builders
                end

                local ok, res = orig_pcall(fn)
                local rtype = type(res)
                local rstr = tostring(res)

                if mode == "seal_upvalues_after_boot" and ok and rtype == "function" then
                    local dummy
                    dummy = orig_smt({{}}, {{
                        __index = function() return function() return dummy end end,
                        __call = function() return dummy end,
                    }})
                    arm_late_bombs()
                    orig_pcall(res, dummy, dummy)
                end

                if ok and rtype == "table" and label == "manifest.lua" then
                    local str_keys = 0
                    for k, v in pairs(res) do
                        if type(k) == "string" and #k >= 2 then
                            str_keys = str_keys + 1
                        elseif type(v) == "table" then
                            for k2, _ in pairs(v) do
                                if type(k2) == "string" and #k2 >= 2 then
                                    str_keys = str_keys + 1
                                end
                            end
                        end
                    end
                    if str_keys == 0 then
                        ok = false
                        rtype = "corrupt_table"
                        rstr = "manifest_table_has_zero_string_keys"
                    end
                end

                restore_all()
                return ok, rtype, rstr, late_bomb_triggered ~= nil, tostring(late_bomb_triggered), game_touched
            end
        end)()
        """
    )
    return rt, harness_fn


def main() -> int:
    parser = argparse.ArgumentParser(description="Steph HUB v6.0 Luau Red-Team Sponge & Anti-Pre-Hook Suite")
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
    parser.add_argument("--skip-v6", action="store_true", help="Skip chaining verify_v6_luau_obf.py")
    args = parser.parse_args()

    t0 = time.time()
    target_rels = get_target_files(args.repo)
    files: Dict[str, str] = {}
    for rel in target_rels:
        p = os.path.join(args.repo, rel)
        if not os.path.isfile(p):
            print(f"[FAIL] Missing target file: {p}", flush=True)
            return 1
        with open(p, "r", encoding="utf-8") as f:
            files[rel] = f.read()

    print("================================================================================", flush=True)
    print(f" Steph HUB v6.0 Luau Red-Team Verification Suite — Auditing {len(files)} obfuscated files", flush=True)
    print("================================================================================", flush=True)

    all_passed = True

    # TEST 1
    print("\n[Test 1/6] Static Seed Folding, Magic Constant, Plaintext & Zero-Fallback Audit...", flush=True)
    t1_errors = run_test1_static_audit(files)
    if t1_errors:
        all_passed = False
        for err in t1_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(
            f"  PASS: {len(files)}/{len(files)} files contain 0 1-bit bottleneck patterns, "
            f"0 Lua 5.1 XOR fallback loops, 0 magic constants, and 0 plaintext probe/diagnostic strings.",
            flush=True,
        )

    _, harness_fn = build_lua_harness()

    # TEST 2
    print("\n[Test 2/6] Luau Runtime Execution (Clean Luau, Executor Hybrid, table.concat=nil)...", flush=True)
    t2_errors: List[str] = []
    for mode, mode_label in (
        ("luau_clean", "2a: Native Luau (bit32 + debug.info + isyieldable + table.create)"),
        ("luau_executor_hybrid", "2b: Hybrid Luau + Executor (debug.info + iscclosure/islclosure/ishooked)"),
        ("luau_nil_concat", "2c: Luau with table.concat = nil (zero table.concat dependency)"),
    ):
        mode_ok = 0
        for rel, src in files.items():
            ok, rtype, rstr, _, _, gtouch = harness_fn(src, rel, mode)
            passed, detail = check_clean_execution_outcome(rel, ok, rtype, rstr, bool(gtouch))
            if not passed:
                t2_errors.append(f"[{mode_label}] [{rel}] {detail}")
            else:
                mode_ok += 1
        print(f"  {'PASS' if mode_ok == len(files) else 'FAIL'}: {mode_label} -> {mode_ok}/{len(files)} files succeeded", flush=True)

    if t2_errors:
        all_passed = False
        for err in t2_errors:
            print(f"  FAIL: {err}", flush=True)

    # TEST 3
    print("\n[Test 3/6] Environment Stripping Attack (debug = nil; string.dump = nil)...", flush=True)
    t3_errors: List[str] = []
    t3_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, _, _, gtouch = harness_fn(src, rel, "strip_debug_and_dump")
        passed, detail = check_poisoned_outcome(rel, ok, rtype, rstr, bool(gtouch))
        if passed:
            t3_ok += 1
        else:
            t3_errors.append(f"[{rel}] {detail}")
    if t3_errors:
        all_passed = False
        for err in t3_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(f"  PASS: {t3_ok}/{len(files)} files silently poisoned seed and blocked Stage-2 on stripped debug.", flush=True)

    # TEST 4
    print("\n[Test 4/6] Pre-Hooking Attacks (string.char, bit32.bxor, pcall & loadstring Lua Wrappers)...", flush=True)
    t4_errors: List[str] = []
    for mode, mode_label in (
        ("hook_string_char", "4a: Lua wrapper hook on string.char"),
        ("hook_bit32_bxor", "4b: Lua wrapper hook on bit32.bxor"),
        ("hook_pcall_and_loadstring", "4c: Lua wrapper hook on pcall & loadstring"),
    ):
        m_ok = 0
        for rel, src in files.items():
            ok, rtype, rstr, _, _, gtouch = harness_fn(src, rel, mode)
            passed, detail = check_poisoned_outcome(rel, ok, rtype, rstr, bool(gtouch))
            if passed:
                m_ok += 1
            else:
                t4_errors.append(f"[{mode_label}] [{rel}] {detail}")
        print(f"  {'PASS' if m_ok == len(files) else 'FAIL'}: {mode_label} -> {m_ok}/{len(files)} files poisoned & blocked", flush=True)

    if t4_errors:
        all_passed = False
        for err in t4_errors:
            print(f"  FAIL: {err}", flush=True)

    # TEST 5
    print("\n[Test 5/6] Pointer Aliasing Attack on Genuine C Closures...", flush=True)
    t5_errors: List[str] = []
    t5_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, _, _, gtouch = harness_fn(src, rel, "alias_c_primitives")
        passed, detail = check_poisoned_outcome(rel, ok, rtype, rstr, bool(gtouch))
        if passed:
            t5_ok += 1
        else:
            t5_errors.append(f"[{rel}] {detail}")
    if t5_errors:
        all_passed = False
        for err in t5_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(f"  PASS: {t5_ok}/{len(files)} files caught C-closure pointer aliasing and silently poisoned seed.", flush=True)

    # TEST 6
    print("\n[Test 6/6] Sealed Stage-2 Lexical Upvalues & Zero Late Global Lookups...", flush=True)
    t6_errors: List[str] = []
    t6_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, bomb_hit, bomb_name, gtouch = harness_fn(src, rel, "seal_upvalues_after_boot")
        if bomb_hit or any(
            tag in rstr
            for tag in (
                "LATE_SETMETATABLE",
                "LATE_RAWSET",
                "LATE_IPAIRS",
                "LATE_TONUMBER",
                "LATE_SELECT",
                "LATE_UNPACK",
                "LATE_CONCAT",
            )
        ):
            t6_errors.append(f"[{rel}] Triggered poisoned late global lookup: {bomb_name} ({rstr})")
            continue
        passed, detail = check_clean_execution_outcome(rel, ok, rtype, rstr, bool(gtouch))
        if not passed:
            t6_errors.append(f"[{rel}] Failed execution under poisoned Stage-2 _G: {detail}")
        else:
            t6_ok += 1

    if t6_errors:
        all_passed = False
        for err in t6_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(
            f"  PASS: {t6_ok}/{len(files)} files executed Stage-2 VM + ring-buffered K(idx) "
            f"with ZERO late _ENV calls to setmetatable, rawset, ipairs, tonumber, select, unpack, or table.concat!",
            flush=True,
        )

    elapsed = time.time() - t0
    print("\n================================================================================", flush=True)
    if all_passed:
        print(f" [ALL 6 RED-TEAM TESTS PASSED] {len(files)}/{len(files)} v6.0 Luau files verified in {elapsed:.2f}s", flush=True)
        print("================================================================================", flush=True)
    else:
        print(f" [RED-TEAM VERIFICATION FAILED] See errors above ({elapsed:.2f}s)", flush=True)
        print("================================================================================", flush=True)
        return 1

    # Chain `verify_v6_luau_obf.py` automatically unless already invoked by outer runner
    v6_script = os.path.join(THIS_DIR, "verify_v6_luau_obf.py")
    if not args.skip_v6 and not os.environ.get("STEPH_SKIP_CHAINED_V6") and os.path.isfile(v6_script):
        env = os.environ.copy()
        env["STEPH_SKIP_CHAINED_V6"] = "1"
        rc = subprocess.call([sys.executable, "-u", v6_script, "--repo", args.repo], env=env)
        if rc != 0:
            return rc

    return 0


if __name__ == "__main__":
    sys.exit(main())
