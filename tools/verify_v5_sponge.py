#!/usr/bin/env python3
"""
Steph HUB - v5.0 Red-Team Security Verification Suite (`verify_v5_sponge.py`)
=============================================================================
Standalone red-team verification suite that tests all 23 obfuscated `.lua` files
against every attack vector and architectural invariant of the v5.0 upgrade:

1. Test 1 — Static Seed Folding & Magic Constant Audit:
   - Verifies no `seed_base + flag * step` 1-bit bottleneck pattern exists.
   - Verifies none of the C-closure probe target outputs (`23575`, `3257`, `3008093`,
     `8314969`, `5441028`) appear anywhere in the generated `.lua` source.
   - Verifies zero plaintext probe strings (`"getinfo"`, `"iscclosure"`, `"islclosure"`,
     `"ishooked"`, `"isfunctionhooked"`, `"loadstring"`, `"short_src"`, `"linedefined"`,
     `"VM integrity check failed"`, `"unknown VM opcode"`) appear in the generated `.lua` source.

2. Test 2 — Cross-Runtime Execution (Lua 5.1 `debug.getinfo`, Luau `debug.info`, `string.dump`-only):
   - Executes `manifest.lua`, `ps99_engine_v3.lua`, and all 23 obfuscated files across:
     a) Standard Lua 5.1 (`debug.getinfo` present, `debug.info = nil`) -> MUST succeed!
     b) Simulated Luau (`debug.info` returning `"[C]", -1, 0, true` for C closures and
        `"chunk", 10, 2, false` for the 2-param Lua canary; `debug.getinfo = nil`) -> MUST succeed!
     c) `string.dump`-only (`debug = nil`, `string.dump` intact) -> MUST succeed!

3. Test 3 — Environment Stripping Attack (`debug = nil; string.dump = nil`):
   - Strips both `debug` and `string.dump` before executing the obfuscated script.
   - Verifies `w_probe` fails closed (`0`), corrupting the 24-bit sponge `acc` so every file
     fails to decrypt and returns `nil` (never executing the Stage-2 payload).

4. Test 4 — Behavioral Metamethod & C-Dumper `setmetatable` Trap:
   - Simulates a dynamic constant dumper wrapping `setmetatable` that touches `tbl[1]`
     whenever a table with `__index` is registered (4a), and an unlocked metatable hook
     that allows rebinding a locked `__metatable = 211` table (4b).
   - Verifies `behav` diverges from `3257`, corrupting the 24-bit sponge `acc` and
     preventing decryption across all 23 files.

5. Test 5 — Pointer Aliasing Attack (`rawget = rawset`):
   - Aliases two globals to the same C closure (`rawget = rawset`) before running.
   - Verifies `seen[fn]` injects `dup = 911` into the sponge, corrupting `acc` and
     preventing decryption across all 23 files.

6. Test 6 — Sealed `Awxs` Upvalues & Metatable-Free Ring Buffer:
   - Hooks `getmetatable` (called once during Stage-1's `behav` challenge at boot) so that
     immediately after `getmetatable` runs in Stage 1, `_G.setmetatable`, `_G.rawset`,
     `_G.ipairs`, `_G.tonumber`, `_G.select`, and `_G.unpack` are replaced with `error(...)` bombs.
   - Verifies that Stage-1 `OP_EXEC` and Stage-2 `Awxs` (with lexical upvalues, numeric `for`,
     and the 8-slot metatable-free ring buffer constant getter `K(idx)`) execute cleanly
     across all 23 files without ever triggering a single late global lookup.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import time
from typing import Dict, List, Tuple

from lupa import lua51

REPO_DIR = r"C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"

# 1-bit bottleneck pattern from v4.0: `v_t1 = boot_seed_base + v_t2 * boot_trust_step;`
BOTTLENECK_1BIT_RE = re.compile(r"=[0-9]{4,}\+[a-zA-Z_][a-zA-Z0-9_]*\*[0-9]{4,};")
STATIC_CONST_ARITH_RE = re.compile(r"\(-?\d+[\+\-%]-?\d+\)")

FORBIDDEN_MAGIC_NUMBERS: Tuple[int, ...] = (
    23575,
    3257,
    3008093,
    8314969,
    5441028,
)

FORBIDDEN_PLAINTEXT_STRINGS: Tuple[str, ...] = (
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


def check_clean_execution_outcome(rel_path: str, ok: bool, res_type: str, res_str: str) -> Tuple[bool, str]:
    """
    Validates that an untampered execution of `rel_path` succeeded through Stage-1
    and Stage-2 Vmify decryption:
      - `manifest.lua` -> returns decrypted manifest table (`ok=True, res_type='table'`)
      - `modules/*.lua`, `lib/ui.lua`, `lib/config.lua` -> returns decrypted builder function (`ok=True, res_type='function'`)
      - Top-level game scripts (`main.lua`, `Stehp-Hub.lua`, `ps99_engine_v3.lua`, `games/*.lua`) ->
        decrypts and enters Stage-2 Vmify bytecode interpreter until hitting a Roblox global (`attempt to index` / `attempt to call`),
        never returning `nil` (which is the fail-closed sponge poison outcome).
    """
    if rel_path == "manifest.lua":
        if ok and res_type == "table":
            return True, "table"
        return False, f"expected table, got ok={ok} type={res_type} ({res_str})"
    elif rel_path.startswith("modules/") or rel_path in ("lib/ui.lua", "lib/config.lua"):
        if ok and res_type == "function":
            return True, "function"
        return False, f"expected function, got ok={ok} type={res_type} ({res_str})"
    else:
        if not ok and ("attempt to index" in res_str or "attempt to call" in res_str):
            return True, "vm_entered(stage2)"
        if ok and res_type != "nil":
            return True, f"ok({res_type})"
        return False, f"expected stage2 entry, got ok={ok} type={res_type} ({res_str})"


def run_test1_static_audit(files: Dict[str, str]) -> List[str]:
    errors: List[str] = []
    for rel, src in files.items():
        first_line = src.splitlines()[0].strip() if src.strip() else ""
        if not first_line or first_line.startswith("--"):
            errors.append(f"[{rel}] Starts with comment or empty line")

        m_1bit = BOTTLENECK_1BIT_RE.search(src)
        if m_1bit:
            errors.append(f"[{rel}] Found 1-bit bottleneck pattern: {m_1bit.group(0)!r}")

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
        r"""
        function(vm_code, label, mode)
            table.create = table.create or function() return {} end

            local orig_debug = debug
            local orig_getinfo = debug and debug.getinfo
            local orig_info = debug and debug.info
            local orig_dump = string.dump
            local orig_smt = setmetatable
            local orig_gmt = getmetatable
            local orig_rset = rawset
            local orig_rget = rawget
            local orig_ipairs = ipairs
            local orig_tonum = tonumber
            local orig_select = select
            local orig_unpack = unpack

            local late_bomb_triggered = nil

            local function restore_all()
                debug = orig_debug
                if orig_debug then
                    orig_debug.getinfo = orig_getinfo
                    orig_debug.info = orig_info
                end
                string.dump = orig_dump
                setmetatable = orig_smt
                getmetatable = orig_gmt
                rawset = orig_rset
                rawget = orig_rget
                ipairs = orig_ipairs
                tonumber = orig_tonum
                select = orig_select
                unpack = orig_unpack
            end

            local fn, err = loadstring(vm_code, "=" .. label)
            if not fn then
                return false, "compile_error", tostring(err), false, "nil"
            end

            if mode == "lua51_getinfo" then
                -- 2a: Standard Lua 5.1 environment (debug.getinfo present, debug.info = nil)
                debug = { getinfo = orig_getinfo }
                string.dump = orig_dump

            elseif mode == "luau_debug_info" then
                -- 2b: Simulated Luau environment (debug.info present, debug.getinfo = nil)
                local sim_info
                sim_info = function(f, what)
                    local is_c = false
                    if f == sim_info then
                        is_c = true
                    elseif type(f) == "function" and orig_getinfo then
                        local inf = orig_getinfo(f, "S")
                        is_c = (inf and inf.what == "C") or false
                    end
                    local s = is_c and "[C]" or "chunk"
                    local l = is_c and -1 or 10
                    local a = is_c and 0 or 2
                    local va = is_c and true or false
                    if what == "sla" then
                        return s, l, a, va
                    end
                    local out = {}
                    for i = 1, #what do
                        local c = string.sub(what, i, i)
                        if c == "s" then
                            out[#out + 1] = s
                        elseif c == "l" then
                            out[#out + 1] = l
                        elseif c == "a" then
                            out[#out + 1] = a
                            out[#out + 1] = va
                        end
                    end
                    return orig_unpack(out)
                end
                debug = { info = sim_info, getinfo = nil }
                string.dump = orig_dump

            elseif mode == "string_dump_only" then
                -- 2c: string.dump-only environment (debug = nil, string.dump intact)
                debug = nil
                string.dump = orig_dump

            elseif mode == "strip_debug_and_dump" then
                -- Test 3: Environment Stripping Attack (debug = nil; string.dump = nil)
                debug = nil
                string.dump = nil

            elseif mode == "behav_dumper_touch" then
                -- Test 4a: C-Dumper setmetatable trap touching tbl[1] when __index is registered
                -- Even if the attacker disguises their setmetatable hook to pass debug.getinfo as a C function,
                -- touching tbl[1] increments probe_hits and corrupts behav (3286 ~= 3257).
                local hooked_smt
                hooked_smt = function(t, mt)
                    local res = orig_smt(t, mt)
                    if type(mt) == "table" and mt.__index then
                        local _ = t[1]
                    end
                    return res
                end
                setmetatable = hooked_smt
                debug = {
                    getinfo = function(f, what)
                        if f == hooked_smt then
                            return orig_getinfo(orig_smt, what)
                        end
                        return orig_getinfo(f, what)
                    end
                }

            elseif mode == "behav_rebind_unlocked" then
                -- Test 4b: Metamethod tampering where locked __metatable = 211 is allowed to rebind
                local hooked_smt
                hooked_smt = function(t, mt)
                    if orig_gmt(t) == 211 then
                        return t
                    end
                    return orig_smt(t, mt)
                end
                setmetatable = hooked_smt
                debug = {
                    getinfo = function(f, what)
                        if f == hooked_smt then
                            return orig_getinfo(orig_smt, what)
                        end
                        return orig_getinfo(f, what)
                    end
                }

            elseif mode == "alias_rawget_rawset" then
                -- Test 5: Pointer Aliasing Attack (rawget = rawset)
                -- rawset is a genuine C closure, so all C-closure checks pass; only seen[fn] (dup = 911) catches it!
                rawget = orig_rset

            elseif mode == "seal_upvalues_after_boot" then
                -- Test 6: Hook getmetatable (called once during Stage-1 behav challenge at boot)
                -- Right after getmetatable is called in Stage 1, poison _G.setmetatable, _G.rawset,
                -- _G.ipairs, _G.tonumber, _G.select, and _G.unpack with error bombs!
                local hooked_gmt
                hooked_gmt = function(t)
                    local res = orig_gmt(t)
                    setmetatable = function()
                        late_bomb_triggered = "LATE_SETMETATABLE"
                        error("LATE_SETMETATABLE", 0)
                    end
                    rawset = function()
                        late_bomb_triggered = "LATE_RAWSET"
                        error("LATE_RAWSET", 0)
                    end
                    ipairs = function()
                        late_bomb_triggered = "LATE_IPAIRS"
                        error("LATE_IPAIRS", 0)
                    end
                    tonumber = function()
                        late_bomb_triggered = "LATE_TONUMBER"
                        error("LATE_TONUMBER", 0)
                    end
                    select = function()
                        late_bomb_triggered = "LATE_SELECT"
                        error("LATE_SELECT", 0)
                    end
                    unpack = function()
                        late_bomb_triggered = "LATE_UNPACK"
                        error("LATE_UNPACK", 0)
                    end
                    return res
                end
                getmetatable = hooked_gmt
                debug = {
                    getinfo = function(f, what)
                        if f == hooked_gmt then
                            return orig_getinfo(orig_gmt, what)
                        end
                        return orig_getinfo(f, what)
                    end
                }
            end

            local ok, res = pcall(fn)
            local rtype = type(res)
            local rstr = tostring(res)
            if mode == "seal_upvalues_after_boot" and ok and rtype == "function" then
                -- Also invoke the returned Stage-2 builder closure under the poisoned _G
                -- to exercise inner closure ARGS loops and ring-buffered K(idx) lookups!
                pcall(res, {})
            end
            if ok and rtype == "table" and label == "manifest.lua" then
                -- Verify manifest table actually decrypted string keys properly (on res or res[1])
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
                    rstr = "manifest_table_has_zero_string_keys"
                end
            end
            restore_all()
            return ok, rtype, rstr, late_bomb_triggered ~= nil, tostring(late_bomb_triggered)
        end
        """
    )
    return rt, harness_fn


def main() -> int:
    parser = argparse.ArgumentParser(description="Steph HUB v5.0 Red-Team Sponge & Sealed-Upvalue Verification Suite")
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
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

    print(f"================================================================================", flush=True)
    print(f" Steph HUB v5.0 Red-Team Verification Suite — Auditing {len(files)} obfuscated files", flush=True)
    print(f"================================================================================", flush=True)

    all_passed = True

    # -------------------------------------------------------------------------
    # TEST 1: Static Seed Folding & Magic Constant Audit
    # -------------------------------------------------------------------------
    print("\n[Test 1/6] Static Seed Folding & Magic Constant Audit...", flush=True)
    t1_errors = run_test1_static_audit(files)
    if t1_errors:
        all_passed = False
        for err in t1_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(
            f"  PASS: {len(files)}/{len(files)} files contain 0 1-bit bottleneck patterns, "
            f"0 magic probe constants {FORBIDDEN_MAGIC_NUMBERS}, and 0 plaintext probe strings.",
            flush=True,
        )

    _, harness_fn = build_lua_harness()

    # -------------------------------------------------------------------------
    # TEST 2: Cross-Runtime Execution (Lua 5.1 getinfo, Luau debug.info, string.dump-only)
    # -------------------------------------------------------------------------
    print("\n[Test 2/6] Cross-Runtime Execution (Lua 5.1 debug.getinfo, Luau debug.info, string.dump-only)...", flush=True)
    t2_errors: List[str] = []
    for mode, mode_label in (
        ("lua51_getinfo", "2a: Lua 5.1 debug.getinfo (debug.info=nil)"),
        ("luau_debug_info", "2b: Simulated Luau debug.info (debug.getinfo=nil)"),
        ("string_dump_only", "2c: string.dump-only (debug=nil)"),
    ):
        mode_ok = 0
        for rel, src in files.items():
            ok, rtype, rstr, _, _ = harness_fn(src, rel, mode)
            passed, detail = check_clean_execution_outcome(rel, ok, rtype, rstr)
            if not passed:
                t2_errors.append(f"[{mode_label}] [{rel}] {detail}")
            else:
                mode_ok += 1
        print(f"  {'PASS' if mode_ok == len(files) else 'FAIL'}: {mode_label} -> {mode_ok}/{len(files)} files succeeded", flush=True)

    if t2_errors:
        all_passed = False
        for err in t2_errors:
            print(f"  FAIL: {err}", flush=True)

    # -------------------------------------------------------------------------
    # TEST 3: Environment Stripping Attack (debug = nil; string.dump = nil)
    # -------------------------------------------------------------------------
    print("\n[Test 3/6] Environment Stripping Attack (debug = nil; string.dump = nil)...", flush=True)
    t3_errors: List[str] = []
    t3_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, _, _ = harness_fn(src, rel, "strip_debug_and_dump")
        if ok and rtype == "nil":
            t3_ok += 1
        else:
            t3_errors.append(f"[{rel}] Expected fail-closed (ok=True, type='nil'), got ok={ok} type={rtype} ({rstr})")
    if t3_errors:
        all_passed = False
        for err in t3_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(f"  PASS: {t3_ok}/{len(files)} files failed closed (w_probe=0 -> poisoned sponge -> returned nil).", flush=True)

    # -------------------------------------------------------------------------
    # TEST 4: Behavioral Metamethod & C-Dumper setmetatable Trap
    # -------------------------------------------------------------------------
    print("\n[Test 4/6] Behavioral Metamethod & C-Dumper setmetatable Trap...", flush=True)
    t4_errors: List[str] = []
    for mode, mode_label in (
        ("behav_dumper_touch", "4a: C-Dumper setmetatable hook touching tbl[1] on __index"),
        ("behav_rebind_unlocked", "4b: Metamethod tamper allowing rebind of locked __metatable=211"),
    ):
        m_ok = 0
        for rel, src in files.items():
            ok, rtype, rstr, _, _ = harness_fn(src, rel, mode)
            if ok and rtype == "nil":
                m_ok += 1
            else:
                t4_errors.append(f"[{mode_label}] [{rel}] Expected fail-closed nil, got ok={ok} type={rtype} ({rstr})")
        print(f"  {'PASS' if m_ok == len(files) else 'FAIL'}: {mode_label} -> {m_ok}/{len(files)} files poisoned & blocked", flush=True)

    if t4_errors:
        all_passed = False
        for err in t4_errors:
            print(f"  FAIL: {err}", flush=True)

    # -------------------------------------------------------------------------
    # TEST 5: Pointer Aliasing Attack (rawget = rawset)
    # -------------------------------------------------------------------------
    print("\n[Test 5/6] Pointer Aliasing Attack (rawget = rawset)...", flush=True)
    t5_errors: List[str] = []
    t5_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, _, _ = harness_fn(src, rel, "alias_rawget_rawset")
        if ok and rtype == "nil":
            t5_ok += 1
        else:
            t5_errors.append(f"[{rel}] Expected fail-closed nil on rawget=rawset, got ok={ok} type={rtype} ({rstr})")
    if t5_errors:
        all_passed = False
        for err in t5_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(f"  PASS: {t5_ok}/{len(files)} files detected duplicate C-closure pointer (dup=911) and returned nil.", flush=True)

    # -------------------------------------------------------------------------
    # TEST 6: Sealed Awxs Upvalues & Metatable-Free Ring Buffer
    # -------------------------------------------------------------------------
    print("\n[Test 6/6] Sealed Awxs Upvalues & Metatable-Free Ring Buffer (Poisoning _G right after Stage-1 getmetatable)...", flush=True)
    t6_errors: List[str] = []
    t6_ok = 0
    for rel, src in files.items():
        ok, rtype, rstr, bomb_hit, bomb_name = harness_fn(src, rel, "seal_upvalues_after_boot")
        if bomb_hit or any(
            tag in rstr
            for tag in (
                "LATE_SETMETATABLE",
                "LATE_RAWSET",
                "LATE_IPAIRS",
                "LATE_TONUMBER",
                "LATE_SELECT",
                "LATE_UNPACK",
            )
        ):
            t6_errors.append(f"[{rel}] Triggered poisoned late global lookup: {bomb_name} ({rstr})")
            continue
        passed, detail = check_clean_execution_outcome(rel, ok, rtype, rstr)
        if not passed:
            t6_errors.append(f"[{rel}] Failed execution under poisoned post-boot _G: {detail}")
        else:
            t6_ok += 1

    if t6_errors:
        all_passed = False
        for err in t6_errors:
            print(f"  FAIL: {err}", flush=True)
    else:
        print(
            f"  PASS: {t6_ok}/{len(files)} files executed Stage-1 OP_EXEC + Stage-2 Awxs + 8-slot ring buffer "
            f"with ZERO late _ENV calls to setmetatable, rawset, ipairs, tonumber, select, or unpack!",
            flush=True,
        )

    elapsed = time.time() - t0
    print(f"\n================================================================================", flush=True)
    if all_passed:
        print(f" [ALL 6 RED-TEAM TESTS PASSED] {len(files)}/{len(files)} v5.0 files verified in {elapsed:.2f}s", flush=True)
        print(f"================================================================================", flush=True)
        return 0
    else:
        print(f" [RED-TEAM VERIFICATION FAILED] See errors above ({elapsed:.2f}s)", flush=True)
        print(f"================================================================================", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
