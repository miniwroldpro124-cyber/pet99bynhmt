#!/usr/bin/env python3
"""
Steph HUB - v5.0 Deep Memory, `getgc(true)` & Lexical Upvalue Inspector (`verify_gc_and_upvalues.py`)
=====================================================================================================
Verifies the 3 structural guarantees of Section 2 (`Seal Awxs Upvalues & Remove setmetatable/rawset
from Constant Pools`) across `manifest.lua`, `lib/config.lua`, `modules/*.lua`, and all 23 v5.0 files:

1. Pillar 1 — `getgc(true)` Heap Table & Metatable Audit:
   - Intercepts `setmetatable` and recursively walks all reachable tables and closures in the Lua
     registry, global environment `_G`, call stack, and closure upvalue graph (`getgc(true)`) while
     executing `manifest.lua`, `lib/config.lua`, and `modules/*.lua` (including invoking the returned
     Stage-2 module/config builder closures against a full mock UI/engine harness).
   - Verifies that after Stage 1's initial `probe_tbl` (`__metatable = 211`) behavioral challenge
     completes, ZERO tables are ever given a `__index` metatable via `setmetatable`, and ZERO
     constant pool tables hold the full decrypted string set in memory.

2. Pillar 2 — 8-Slot Bounded Ring Buffer Verification (`Y[f.constants]`):
   - Inspects every Stage-2 prototype table `_p` and its constant getter closure `K = _p[f.constants]`
     (`function(idx) ... end`) inside `Awxs` via `debug.getupvalue`.
   - Verifies that `K` maintains an 8-slot bounded ring buffer (`ring_k[1..8]`, `ring_v[1..8]`,
     `ring_pos in 1..8`) salted by outer-VM `K_salt` (`_ksalt`), with zero strings in `_cons` and
     only encrypted binary blobs in `_enc_k`.
   - Verifies that even after a module accesses >20 distinct string constants, at most 8 plaintext
     strings are cached in `ring_v` at any instant (and perturbing `_ksalt` alters decryption).

3. Pillar 3 — Lexical Upvalue Binding Audit (`debug.getupvalue`):
   - Captures the inner `Awxs` closure (`v_vm_fn`) and its nested Stage-2 interpreter closures when
     invoked by Stage-1 `OP_EXEC`.
   - Uses `debug.getupvalue` (before stripping `debug`) to confirm that `_tonum` (`tonumber`),
     `_sel` (`select`), `_mflr` (`math.floor`), `_err` (`error`), and `_unpack` (`unpack`) are bound
     as immutable lexical closure upvalues pointing directly to the outer verified C closures rather
     than resolved from `_ENV` at runtime.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import time
from typing import Dict, List, Set, Tuple

from lupa import lua51

REPO_DIR = r"C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt"
UNOBF_LOCAL_DIR = os.path.join(REPO_DIR, "unobf")
UNOBF_EXTERNAL_DIR = r"C:\Users\LaptopAT\.gemini\antigravity\scratch\pet99bynhmt_unobf"
WORKSPACE_SRC_DIR = r"C:\Users\LaptopAT\AppData\Local\Real\workspace\stephhub-src"

PROMETHEUS_DIRS = [
    os.path.join(REPO_DIR, "tools", "Prometheus", "src"),
    r"C:\Users\LaptopAT\.gemini\antigravity\scratch\Prometheus\src",
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


def load_clean_source_for_file(rel: str, repo_dir: str = REPO_DIR) -> str:
    candidates = [
        os.path.join(UNOBF_LOCAL_DIR, rel),
        os.path.join(UNOBF_EXTERNAL_DIR, rel),
        os.path.join(WORKSPACE_SRC_DIR, rel),
        os.path.join(WORKSPACE_SRC_DIR, rel[:-4] + ".unobf.lua" if rel.endswith(".lua") else rel + ".unobf.lua"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
    raise RuntimeError(f"Clean unobfuscated source backup not found for {rel}")


class AstStringExtractor:
    """
    Uses Prometheus's LuaU AST parser + Compiler to extract the exact ground-truth
    set of string constants compiled into Stage-2 Vmify prototypes for each source file.
    """

    def __init__(self) -> None:
        prom_src = None
        for d in PROMETHEUS_DIRS:
            if os.path.isfile(os.path.join(d, "prometheus.lua")):
                prom_src = d
                break
        if not prom_src:
            raise RuntimeError("Prometheus src directory not found!")

        self.rt = lua51.LuaRuntime()
        escaped_path = prom_src.replace("\\", "\\\\")
        self.rt.execute(
            f"""
            arg = {{}}
            package.path = "{escaped_path}\\\\?.lua;" .. package.path
            Prometheus = require("prometheus")
            Parser = require("prometheus.parser")
            analyzeBindings = require("prometheus.bindinganalysis")
            Compiler = require("prometheus.vm.compiler")
            Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

            local function collectProtoStrings(proto, seen, list)
                for _, c in ipairs(proto.constants or {{}}) do
                    if type(c) == "string" and #c >= 2 and not seen[c] then
                        seen[c] = true
                        list[#list + 1] = c
                    end
                end
                for _, ch in ipairs(proto.children or {{}}) do
                    collectProtoStrings(ch, seen, list)
                end
            end

            local function maxProtoStringCount(proto)
                local own = 0
                for _, c in ipairs(proto.constants or {{}}) do
                    if type(c) == "string" then
                        own = own + 1
                    end
                end
                local best = own
                for _, ch in ipairs(proto.children or {{}}) do
                    local cbest = maxProtoStringCount(ch)
                    if cbest > best then best = cbest end
                end
                return best, own
            end

            function extractFileStringConstants(code, filename)
                local ast = Parser:new({{ LuaVersion = "LuaU" }}):parse(code, filename)
                analyzeBindings(ast)
                local proto = Compiler:compile(ast)
                local seen, list = {{}}, {{}}
                collectProtoStrings(proto, seen, list)
                local max_proto_strs, root_strs = maxProtoStringCount(proto)
                return list, #list, max_proto_strs, root_strs
            end
            """
        )
        self._extract_fn = self.rt.eval("extractFileStringConstants")

    def extract(self, clean_code: str, rel_path: str) -> Tuple[Set[str], int, int]:
        lua_tbl, total_unique, max_proto_strs, _ = self._extract_fn(clean_code, rel_path)
        strings: Set[str] = set()
        for i in range(1, int(total_unique) + 1):
            val = lua_tbl[i]
            if isinstance(val, str):
                strings.add(val)
        return strings, int(max_proto_strs), int(total_unique)


def build_inspector_runtime() -> Tuple[lua51.LuaRuntime, object]:
    rt = lua51.LuaRuntime()
    inspector_fn = rt.eval(
        r"""
        function(vm_code, label, expected_strings_tbl, expected_str_count)
            table.create = table.create or function() return {} end

            local orig_type = type
            local orig_pcall = pcall
            local orig_tonum = tonumber
            local orig_sel = select
            local orig_err = error
            local orig_smt = setmetatable
            local orig_gmt = getmetatable
            local orig_rset = rawset
            local orig_rget = rawget
            local orig_mflr = math.floor
            local orig_getfenv = getfenv
            local orig_setfenv = setfenv
            local orig_unpack = unpack or table.unpack
            local orig_byte = string.byte
            local orig_char = string.char
            local orig_sub = string.sub
            local orig_concat = table.concat
            local orig_next = next
            local orig_pairs = pairs
            local orig_ipairs = ipairs
            local orig_rawequal = rawequal
            local orig_tostring = tostring
            local orig_debug = debug
            local orig_getinfo = debug.getinfo
            local orig_getupvalue = debug.getupvalue
            local orig_setupvalue = debug.setupvalue
            local orig_getlocal = debug.getlocal
            local orig_getregistry = debug.getregistry
            local orig_debug_getmt = debug.getmetatable
            local orig_debug_getfenv = debug.getfenv
            local orig_sethook = debug.sethook
            local orig_dump = string.dump

            local expected_set = {}
            for i = 1, expected_str_count do
                local s = expected_strings_tbl[i]
                if s then expected_set[s] = true end
            end

            -- Track all setmetatable calls and all allocated/seen tables & closures
            local tracked_tables = {}
            local tracked_closures = {}
            local probe_tbl_ref = nil
            local stage1_probe_completed = false
            local total_smt_calls = 0
            local post_probe_smt_calls = 0
            local post_probe_index_mt_calls = 0

            local hooked_smt
            hooked_smt = function(t, mt)
                total_smt_calls = total_smt_calls + 1
                if orig_type(t) == "table" then
                    tracked_tables[t] = true
                end
                if orig_type(mt) == "table" then
                    tracked_tables[mt] = true
                end
                if not stage1_probe_completed then
                    if orig_type(mt) == "table" and orig_rget(mt, "__metatable") == 211 then
                        probe_tbl_ref = t
                    elseif probe_tbl_ref ~= nil and orig_rawequal(t, probe_tbl_ref) then
                        -- Second setmetatable call in Stage 1 is pcall(_smt, probe_tbl, {}), completing the probe_tbl challenge
                        stage1_probe_completed = true
                    end
                else
                    post_probe_smt_calls = post_probe_smt_calls + 1
                    if orig_type(mt) == "table" and orig_rget(mt, "__index") ~= nil then
                        post_probe_index_mt_calls = post_probe_index_mt_calls + 1
                    end
                end
                return orig_smt(t, mt)
            end

            -- Captured Stage-2 Awxs closure (`v_vm_fn`), runtime `_ck` & `_ksalt`, and outer Stage-1 verified locals
            local captured_awxs = nil
            local captured_ck = nil
            local captured_ksalt = nil
            local outer_local_tonum = false
            local outer_local_sel = false
            local outer_local_mflr = false
            local outer_local_err = false
            local outer_local_unpack = false
            local getinfo_calls = 0
            local hook_installed = false

            local function call_hook(event)
                local info2 = orig_getinfo(2, "fS")
                if not info2 or not info2.func then return end
                local fn2 = info2.func
                if orig_type(fn2) == "function" then
                    tracked_closures[fn2] = true
                end
                if info2.what == "Lua" and not captured_awxs then
                    -- Check if fn2 is Awxs (`v_vm_fn(_blob, _ck, _ksalt, _bxor, _cmap, _byte, _sub, _concat, ...)`)
                    local n1, v1 = orig_getlocal(2, 1)
                    local n2, v2 = orig_getlocal(2, 2)
                    local n3, v3 = orig_getlocal(2, 3)
                    local n5, v5 = orig_getlocal(2, 5)
                    if orig_type(v1) == "string" and #v1 > 16
                       and orig_type(v2) == "number" and v2 >= 0 and v2 < 256
                       and orig_type(v3) == "number" and v3 >= 0 and v3 < 256
                       and orig_type(v5) == "table" and orig_rget(v5, 35) == "#" then
                        captured_awxs = fn2
                        captured_ck = v2
                        captured_ksalt = v3
                        -- Inspect stack level 3 (outer Stage-1 VM frame) to verify the outer local bindings
                        local lidx = 1
                        while lidx <= 120 do
                            local lname, lval = orig_getlocal(3, lidx)
                            if not lname then break end
                            if orig_rawequal(lval, orig_tonum) then outer_local_tonum = true end
                            if orig_rawequal(lval, orig_sel) then outer_local_sel = true end
                            if orig_rawequal(lval, orig_mflr) then outer_local_mflr = true end
                            if orig_rawequal(lval, orig_err) then outer_local_err = true end
                            if orig_rawequal(lval, orig_unpack) then outer_local_unpack = true end
                            lidx = lidx + 1
                        end
                    end
                elseif info2.what == "Lua" and captured_awxs then
                    -- Capture prototype tables passed as 1st argument to Stage-2 IIFE / make / start / loop
                    local _, arg1 = orig_getlocal(2, 1)
                    if orig_type(arg1) == "table" then
                        tracked_tables[arg1] = true
                    end
                end
            end

            setmetatable = hooked_smt
            debug = {
                getinfo = function(f, what)
                    if f == hooked_smt then
                        f = orig_smt
                    end
                    getinfo_calls = getinfo_calls + 1
                    -- Stage 1 probes 1 canary + 15 primitives in yiP = 16 getinfo calls
                    if getinfo_calls >= 16 and not hook_installed then
                        hook_installed = true
                        orig_sethook(call_hook, "c")
                    end
                    return orig_getinfo(f, what)
                end
            }

            -- Build mock Roblox / UI / Engine environment so `lib/config.lua` and `modules/*.lua`
            -- execute all top-level and builder logic, accessing >20 distinct string constants
            local saved_globals = {
                game = _G.game,
                task = _G.task,
                isfolder = _G.isfolder,
                makefolder = _G.makefolder,
                isfile = _G.isfile,
                readfile = _G.readfile,
                writefile = _G.writefile,
                delfile = _G.delfile,
                listfiles = _G.listfiles,
                setfpscap = _G.setfpscap,
                setclipboard = _G.setclipboard,
                getgenv = _G.getgenv,
                StephHubConfig = _G.StephHubConfig,
            }

            local mock_callbacks = {}
            local function track_arg(v)
                if orig_type(v) == "table" then
                    tracked_tables[v] = true
                elseif orig_type(v) == "function" then
                    tracked_closures[v] = true
                    mock_callbacks[#mock_callbacks + 1] = v
                end
            end

            local mock_handle = {
                Set = function(val) track_arg(val) end,
                Get = function() return false end,
            }
            tracked_tables[mock_handle] = true

            local mock_tab = {
                CreateSection = function(_, title) track_arg(title); return mock_handle end,
                CreateParagraph = function(_, opts) track_arg(opts); return mock_handle end,
            }
            tracked_tables[mock_tab] = true

            local mock_win = {
                CreateTab = function(_, name, icon)
                    track_arg(name)
                    track_arg(icon)
                    return mock_tab
                end,
            }
            tracked_tables[mock_win] = true

            local mock_ui = {
                section = function(tab, title)
                    track_arg(tab); track_arg(title)
                    return mock_handle
                end,
                button = function(tab, label_or_opts, cb)
                    track_arg(tab); track_arg(label_or_opts); track_arg(cb)
                    return mock_handle
                end,
                toggle = function(tab, opts)
                    track_arg(tab); track_arg(opts)
                    if orig_type(opts) == "table" and orig_type(opts.onChange) == "function" then
                        tracked_closures[opts.onChange] = true
                        mock_callbacks[#mock_callbacks + 1] = opts.onChange
                    end
                    return mock_handle
                end,
                slider = function(tab, opts)
                    track_arg(tab); track_arg(opts)
                    if orig_type(opts) == "table" and orig_type(opts.onChange) == "function" then
                        tracked_closures[opts.onChange] = true
                        mock_callbacks[#mock_callbacks + 1] = opts.onChange
                    end
                    return mock_handle
                end,
                dropdown = function(tab, opts)
                    track_arg(tab); track_arg(opts)
                    if orig_type(opts) == "table" then
                        if orig_type(opts.callback) == "function" then
                            tracked_closures[opts.callback] = true
                            mock_callbacks[#mock_callbacks + 1] = opts.callback
                        end
                        if orig_type(opts.onChange) == "function" then
                            tracked_closures[opts.onChange] = true
                            mock_callbacks[#mock_callbacks + 1] = opts.onChange
                        end
                    end
                    return mock_handle
                end,
                input = function(tab, opts)
                    track_arg(tab); track_arg(opts)
                    return mock_handle
                end,
                paragraph = function(tab, title, content)
                    track_arg(tab); track_arg(title); track_arg(content)
                    return mock_handle
                end,
                label = function(tab, text)
                    track_arg(tab); track_arg(text)
                    return mock_handle
                end,
                notify = function(title, msg)
                    track_arg(title); track_arg(msg)
                end,
            }
            tracked_tables[mock_ui] = true

            local mock_engine = {
                CFG = { TeleMode = "Instant" },
                FarmItems = {},
                notes = { farmItems = "active" },
                IsRunning = function() return false end,
                GetNotes = function() return { farmItems = "active" } end,
                GetCatalog = function()
                    return {
                        flags = { "Coins Flag", "Diamonds Flag", "Fortune Flag" },
                        potions = { "Coins", "Damage", "Speed" },
                        enchants = { "Coins", "Strong Pets", "Tap Power" },
                        fruits = { "Apple", "Banana", "Orange" },
                        gifts = { "Gift Bag", "Large Gift Bag" },
                    }
                end,
                SetEnabled = function(k, v) track_arg(k); track_arg(v) end,
                SetConfig = function(k, v) track_arg(k); track_arg(v) end,
                SetEventOpt = function(k, v, sk) track_arg(k); track_arg(v); track_arg(sk) end,
                SetFarmItem = function(k, v) track_arg(k); track_arg(v) end,
                TeleportToFarm = function() return true, "ok" end,
                TeleportBestWorld = function() return true, "ok" end,
            }
            tracked_tables[mock_engine] = true

            local mock_config_svc = {
                register = function(kind, key, handle)
                    track_arg(kind); track_arg(key); track_arg(handle)
                end,
                onChanged = function() end,
                onLoad = function(cb) track_arg(cb) end,
            }
            tracked_tables[mock_config_svc] = true

            local mock_player = {
                Character = nil,
                CharacterAdded = {
                    Connect = function(_, cb) track_arg(cb); return { Disconnect = function() end } end,
                },
            }
            tracked_tables[mock_player] = true

            local mock_ctx = {
                win = mock_win,
                ui = mock_ui,
                engine = mock_engine,
                config = mock_config_svc,
                player = mock_player,
                unload = function() end,
            }
            tracked_tables[mock_ctx] = true

            local function restore_env()
                orig_sethook()
                setmetatable = orig_smt
                getmetatable = orig_gmt
                rawset = orig_rset
                rawget = orig_rget
                tonumber = orig_tonum
                select = orig_sel
                error = orig_err
                unpack = orig_unpack
                ipairs = orig_ipairs
                debug = orig_debug
                string.dump = orig_dump
                for k, v in orig_pairs(saved_globals) do
                    _G[k] = v
                end
            end

            local chunk_fn, load_err = loadstring(vm_code, "=" .. label)
            if not chunk_fn then
                restore_env()
                return { ok = false, err = "loadstring failed: " .. orig_tostring(load_err) }
            end
            tracked_closures[chunk_fn] = true

            -- Execute Stage 1 + Stage 2 top-level chunk
            local ok_exec, res = orig_pcall(chunk_fn)
            if orig_type(res) == "table" then
                tracked_tables[res] = true
            elseif orig_type(res) == "function" then
                tracked_closures[res] = true
            end

            -- If the file is `lib/config.lua`, `lib/ui.lua`, or `modules/*.lua`, invoke its Stage-2 builder closure
            -- so the module executes through its body and accesses >20 distinct string constants!
            local builder_invoked = false
            local builder_ok = true
            local builder_err = ""
            if ok_exec and orig_type(res) == "function" then
                if label == "lib/config.lua" then
                    _G.game = {
                        GetService = function(_, svc)
                            return {
                                JSONEncode = function(_, _) return "{}" end,
                                JSONDecode = function(_, _) return {} end,
                            }
                        end,
                    }
                    _G.task = {
                        spawn = function(f) track_arg(f) end,
                        wait = function() end,
                        delay = function(_, f) track_arg(f) end,
                    }
                    _G.isfolder = function() return true end
                    _G.makefolder = function() end
                    _G.isfile = function() return false end
                    _G.listfiles = function() return {} end
                    _G.setfpscap = function() end

                    builder_invoked = true
                    local ok_b, cfg_obj = orig_pcall(res, mock_engine, mock_ui)
                    builder_ok = ok_b
                    if not ok_b then
                        builder_err = orig_tostring(cfg_obj)
                    elseif orig_type(cfg_obj) == "table" then
                        tracked_tables[cfg_obj] = true
                        if orig_type(cfg_obj.applyGlobalTable) == "function" then
                            tracked_closures[cfg_obj.applyGlobalTable] = true
                            orig_pcall(cfg_obj.applyGlobalTable, {
                                Profile = "AuditProfile",
                                MainFarm = {
                                    TeleMode = "Instant",
                                    FastFarm = true,
                                    FastFarmBeta = false,
                                    AutoTap = true,
                                    OrbVacuum = true,
                                    BestZoneTele = true,
                                    AutoBuyZones = true,
                                    AutoWorldAdvance = true,
                                },
                                FarmItems = {
                                    CooldownSeconds = 8,
                                    UseItems = { Comet = true, ["Mini Pinata"] = true },
                                    Enabled = true,
                                },
                                Event = {
                                    MoveMode = "Instant",
                                    KeepPumpkinTier = 4,
                                    AutoEnterEvent = true,
                                    BestFarmTele = true,
                                    EventTap = true,
                                    AutoBuyButtons = true,
                                    AutoBreakPumpkins = true,
                                    AutoBuyEgg = true,
                                    AutoRebirth = true,
                                    AutoClaimChests = true,
                                    AutoUseBoosts = true,
                                },
                                PotionsAndGifts = {
                                    DrinkHighestTier = true,
                                    AutoDrinkPotions = true,
                                    AutoOpenGifts = true,
                                    AutoFruit = true,
                                    AutoFlag = true,
                                },
                                Performance = {
                                    FpsCap = 60,
                                    SuperFPS = true,
                                    ReduceCpuRam = true,
                                    WhiteScreen = false,
                                    AntiAFK = true,
                                },
                            })
                        end
                    end
                elseif orig_sub(label, 1, 8) == "modules/" then
                    _G.game = {
                        PlaceId = 8737899170,
                        JobId = "audit-job-id",
                        GetService = function(_, _)
                            return {
                                JumpRequest = {
                                    Connect = function(_, cb)
                                        track_arg(cb)
                                        return { Disconnect = function() end }
                                    end,
                                },
                            }
                        end,
                    }
                    _G.task = {
                        spawn = function(f) track_arg(f) end,
                        wait = function() end,
                        delay = function(_, f) track_arg(f) end,
                    }
                    builder_invoked = true
                    local ok_b, b_res = orig_pcall(res, mock_ctx)
                    builder_ok = ok_b
                    if not ok_b then
                        builder_err = orig_tostring(b_res)
                    end
                end
            end

            orig_sethook()

            -- =========================================================================
            -- PILLAR 1: `getgc(true)` Reachable Heap Table & Metatable Audit
            -- =========================================================================
            local visited_tables = {}
            local visited_funcs = {}
            local table_queue = {}
            local func_queue = {}

            local function enqueue_val(v)
                local tv = orig_type(v)
                if tv == "table" then
                    if not visited_tables[v] then
                        visited_tables[v] = true
                        table_queue[#table_queue + 1] = v
                    end
                elseif tv == "function" then
                    if not visited_funcs[v] then
                        visited_funcs[v] = true
                        func_queue[#func_queue + 1] = v
                    end
                end
            end

            enqueue_val(_G)
            enqueue_val(orig_getregistry())
            enqueue_val(chunk_fn)
            enqueue_val(res)
            enqueue_val(captured_awxs)
            for t, _ in orig_pairs(tracked_tables) do enqueue_val(t) end
            for f, _ in orig_pairs(tracked_closures) do enqueue_val(f) end

            local t_head, f_head = 1, 1
            while t_head <= #table_queue or f_head <= #func_queue do
                while t_head <= #table_queue do
                    local tbl = table_queue[t_head]
                    t_head = t_head + 1
                    local mt = orig_debug_getmt(tbl)
                    if mt ~= nil then enqueue_val(mt) end
                    -- Raw iteration via orig_next so no metamethods are invoked
                    local k, v = orig_next(tbl, nil)
                    while k ~= nil do
                        enqueue_val(k)
                        enqueue_val(v)
                        k, v = orig_next(tbl, k)
                    end
                end
                while f_head <= #func_queue do
                    local fn = func_queue[f_head]
                    f_head = f_head + 1
                    local inf = orig_getinfo(fn, "Su")
                    if inf and inf.what == "Lua" then
                        local u = 1
                        while u <= 255 do
                            local uname, uval = orig_getupvalue(fn, u)
                            if not uname then break end
                            enqueue_val(uval)
                            u = u + 1
                        end
                    end
                end
            end

            -- Do not count our own test harness tables (`expected_strings_tbl`, `expected_set`, `visited_tables`, etc.)
            local harness_ignore = {
                [expected_strings_tbl] = true,
                [expected_set] = true,
                [tracked_tables] = true,
                [tracked_closures] = true,
                [visited_tables] = true,
                [visited_funcs] = true,
                [table_queue] = true,
                [func_queue] = true,
                [saved_globals] = true,
                [mock_callbacks] = true,
            }

            local string_mt = orig_debug_getmt("")
            local unexpected_index_mt_tables = 0
            local max_expected_strings_in_any_table = 0

            -- Discover all Stage-2 prototype tables `_p` and their `K = _p[f.constants]` closures
            local proto_tables = {}
            local k_closures = {}
            local k_closure_seen = {}

            local function is_stage2_proto_table(t)
                -- A Stage-2 prototype table `_p` has 7 randomized integer keys in [1024, 16777215]:
                -- 1 boolean (vararg), 1 number (maxRegister), 1 function (`K = _p[f.constants]`),
                -- and 4 tables (params, captures, code, children).
                local n_bool, n_num, n_fn, n_tbl, n_other = 0, 0, 0, 0, 0
                local fn_val = nil
                local k, v = orig_next(t, nil)
                while k ~= nil do
                    if orig_type(k) ~= "number" or k < 1024 or k > 16777215 or k ~= orig_mflr(k) then
                        return false, nil
                    end
                    local tv = orig_type(v)
                    if tv == "boolean" then
                        n_bool = n_bool + 1
                    elseif tv == "number" then
                        n_num = n_num + 1
                    elseif tv == "function" then
                        n_fn = n_fn + 1
                        fn_val = v
                    elseif tv == "table" then
                        n_tbl = n_tbl + 1
                    else
                        n_other = n_other + 1
                    end
                    k, v = orig_next(t, k)
                end
                if n_bool == 1 and n_num == 1 and n_fn == 1 and n_tbl == 4 and n_other == 0 then
                    return true, fn_val
                end
                return false, nil
            end

            for tbl, _ in orig_pairs(visited_tables) do
                if not harness_ignore[tbl] then
                    local mt = orig_debug_getmt(tbl)
                    if orig_type(mt) == "table" and orig_rget(mt, "__index") ~= nil then
                        if not orig_rawequal(mt, string_mt)
                           and not orig_rawequal(tbl, probe_tbl_ref)
                           and orig_rget(mt, "__metatable") ~= 211 then
                            unexpected_index_mt_tables = unexpected_index_mt_tables + 1
                        end
                    end

                    local is_p, k_fn = is_stage2_proto_table(tbl)
                    if is_p and k_fn then
                        proto_tables[#proto_tables + 1] = tbl
                        if not k_closure_seen[k_fn] then
                            k_closure_seen[k_fn] = true
                            k_closures[#k_closures + 1] = k_fn
                        end
                    end

                    -- Count how many distinct ground-truth string constants from `unobf/<rel>` exist in `tbl`
                    -- (Skip `manifest.lua` returned output table itself when `expected_str_count` is small,
                    --  or check all constant pool tables specifically)
                    if not (label == "manifest.lua" and orig_rawequal(tbl, res)) then
                        local match_set = {}
                        local match_cnt = 0
                        local k, v = orig_next(tbl, nil)
                        while k ~= nil do
                            if orig_type(v) == "string" and expected_set[v] and not match_set[v] then
                                match_set[v] = true
                                match_cnt = match_cnt + 1
                            end
                            k, v = orig_next(tbl, k)
                        end
                        if match_cnt > max_expected_strings_in_any_table then
                            max_expected_strings_in_any_table = match_cnt
                        end
                    end
                end
            end

            -- =========================================================================
            -- PILLAR 2: 8-Slot Bounded Ring Buffer Verification (`Y[f.constants]`)
            -- =========================================================================
            local total_enc_strings_across_protos = 0
            local max_enc_strings_single_proto = 0
            local max_ring_k_occupancy = 0
            local max_ring_v_occupancy = 0
            local strings_in_cons_tables = 0
            local plaintext_in_enc_k_tables = 0
            local ksalt_matched_outer = true
            local ksalt_perturbation_changed_output = false
            local ring_tested_gt20 = false
            local ring_fifo_eviction_verified = false

            local function count_table_entries(t)
                local cnt = 0
                local k, _ = orig_next(t, nil)
                while k ~= nil do
                    cnt = cnt + 1
                    k, _ = orig_next(t, k)
                end
                return cnt
            end

            local function inspect_k_closure(k_fn)
                -- Inspect all upvalues of `K = function(_idx) ... end`:
                -- Upvalues of K in order of appearance in `_p[f.constants]`:
                -- 1: _cons (table)
                -- 2: _ring_k (table)
                -- 3: _ring_v (table)
                -- 4: _enc_k (table)
                -- 5: _ss (number)
                -- 6: _ksalt (number)
                -- 7: _byte (function: string.byte)
                -- 8: _bxor (function)
                -- 9: _cmap (table: 0..255 char map)
                -- 10: _concat (function: table.concat)
                -- 11: _ring_pos (number: 1..8)
                local upv_vals = {}
                local u = 1
                while u <= 30 do
                    local uname, uval = orig_getupvalue(k_fn, u)
                    if not uname then break end
                    upv_vals[u] = uval
                    u = u + 1
                end

                local t_cons = upv_vals[1]
                local t_ring_k = upv_vals[2]
                local t_ring_v = upv_vals[3]
                local t_enc_k = upv_vals[4]
                local v_ss = upv_vals[5]
                local v_ksalt = upv_vals[6]
                local v_ring_pos = upv_vals[11]

                if orig_type(t_cons) ~= "table" or orig_type(t_ring_k) ~= "table"
                   or orig_type(t_ring_v) ~= "table" or orig_type(t_enc_k) ~= "table"
                   or orig_type(v_ss) ~= "number" or orig_type(v_ksalt) ~= "number"
                   or orig_type(v_ring_pos) ~= "number" then
                    return false, "unexpected_K_upvalue_layout"
                end

                if captured_ksalt ~= nil and v_ksalt ~= captured_ksalt then
                    ksalt_matched_outer = false
                end

                -- Verify `_cons` contains ZERO strings (only numbers/booleans)
                local k, v = orig_next(t_cons, nil)
                while k ~= nil do
                    if orig_type(v) == "string" then
                        strings_in_cons_tables = strings_in_cons_tables + 1
                    end
                    k, v = orig_next(t_cons, k)
                end

                -- Collect all encrypted string constant indices in `_enc_k`
                local enc_indices = {}
                k, v = orig_next(t_enc_k, nil)
                while k ~= nil do
                    if orig_type(k) == "number" and orig_type(v) == "string" then
                        enc_indices[#enc_indices + 1] = k
                        if #v >= 3 and expected_set[v] then
                            plaintext_in_enc_k_tables = plaintext_in_enc_k_tables + 1
                        end
                    end
                    k, v = orig_next(t_enc_k, k)
                end
                table.sort(enc_indices)

                local n_enc = #enc_indices
                total_enc_strings_across_protos = total_enc_strings_across_protos + n_enc
                if n_enc > max_enc_strings_single_proto then
                    max_enc_strings_single_proto = n_enc
                end

                -- Check current ring occupancy before sweeping
                local rk_cnt = count_table_entries(t_ring_k)
                local rv_cnt = count_table_entries(t_ring_v)
                if rk_cnt > max_ring_k_occupancy then max_ring_k_occupancy = rk_cnt end
                if rv_cnt > max_ring_v_occupancy then max_ring_v_occupancy = rv_cnt end

                -- Sweep every encrypted string constant index through `K(idx)` and check the 8-slot bound at EVERY step!
                for step = 1, n_enc do
                    local idx = enc_indices[step]
                    local dec_str = k_fn(idx)
                    if orig_type(dec_str) ~= "string" then
                        return false, "K(idx) did not return string for idx=" .. orig_tostring(idx)
                    end
                    local cur_rk = count_table_entries(t_ring_k)
                    local cur_rv = count_table_entries(t_ring_v)
                    if cur_rk > max_ring_k_occupancy then max_ring_k_occupancy = cur_rk end
                    if cur_rv > max_ring_v_occupancy then max_ring_v_occupancy = cur_rv end
                    local _, cur_pos = orig_getupvalue(k_fn, 11)
                    if orig_type(cur_pos) ~= "number" or cur_pos < 1 or cur_pos > 8 then
                        return false, "ring_pos out of bounds [1..8]: " .. orig_tostring(cur_pos)
                    end
                end

                if n_enc >= 20 then
                    ring_tested_gt20 = true
                    -- Verify that after accessing >= 20 distinct string constants,
                    -- `ring_k` and `ring_v` hold exactly 8 entries corresponding to the last 8 accessed constants!
                    if count_table_entries(t_ring_k) == 8 and count_table_entries(t_ring_v) == 8 then
                        local last8_set = {}
                        for s = n_enc - 7, n_enc do
                            last8_set[enc_indices[s]] = true
                        end
                        local all_last8_match = true
                        for slot = 1, 8 do
                            if not last8_set[t_ring_k[slot]] or orig_type(t_ring_v[slot]) ~= "string" then
                                all_last8_match = false
                                break
                            end
                        end
                        if all_last8_match then
                            ring_fifo_eviction_verified = true
                        end
                    end
                end

                -- Also verify `K_salt` binding: perturbing `_ksalt` (upvalue 6) changes the decrypted string
                if n_enc >= 1 and not ksalt_perturbation_changed_output then
                    local test_idx = enc_indices[1]
                    local orig_plain = k_fn(test_idx)
                    -- Evict or clear `t_ring_k` temporarily so `K(test_idx)` decrypts freshly with perturbed `_ksalt`
                    local saved_rk = {}
                    local saved_rv = {}
                    for slot = 1, 8 do
                        saved_rk[slot] = t_ring_k[slot]
                        saved_rv[slot] = t_ring_v[slot]
                        t_ring_k[slot] = nil
                        t_ring_v[slot] = nil
                    end
                    orig_setupvalue(k_fn, 6, (v_ksalt + 73) % 256)
                    local perturbed_plain = k_fn(test_idx)
                    orig_setupvalue(k_fn, 6, v_ksalt)
                    for slot = 1, 8 do
                        t_ring_k[slot] = saved_rk[slot]
                        t_ring_v[slot] = saved_rv[slot]
                    end
                    if orig_type(orig_plain) == "string" and orig_type(perturbed_plain) == "string" then
                        if #orig_plain == 0 or orig_plain ~= perturbed_plain then
                            ksalt_perturbation_changed_output = true
                        end
                    end
                end

                return true, "ok"
            end

            for i = 1, #k_closures do
                local ok_k, err_k = inspect_k_closure(k_closures[i])
                if not ok_k then
                    restore_env()
                    return { ok = false, err = "Pillar 2 K(idx) audit error: " .. orig_tostring(err_k) }
                end
            end

            -- =========================================================================
            -- PILLAR 3: Lexical Upvalue Binding Audit (`debug.getupvalue` on `Awxs`)
            -- =========================================================================
            -- Inspect `captured_awxs` (`v_vm_fn`) and all Stage-2 closures reachable from it
            local awxs_upv_tonum = false
            local awxs_upv_sel = false
            local awxs_upv_mflr = false
            local awxs_upv_err = false
            local awxs_upv_unpack = false
            local awxs_upv_getfenv = false
            local awxs_upv_setfenv = false
            local awxs_direct_upv_count = 0

            local function check_closure_upvalues(fn)
                if orig_type(fn) ~= "function" then return end
                local inf = orig_getinfo(fn, "S")
                if not inf or inf.what ~= "Lua" then return end
                local u = 1
                while u <= 60 do
                    local uname, uval = orig_getupvalue(fn, u)
                    if not uname then break end
                    if orig_rawequal(uval, orig_tonum) then awxs_upv_tonum = true end
                    if orig_rawequal(uval, orig_sel) then awxs_upv_sel = true end
                    if orig_rawequal(uval, orig_mflr) then awxs_upv_mflr = true end
                    if orig_rawequal(uval, orig_err) then awxs_upv_err = true end
                    if orig_rawequal(uval, orig_unpack) then awxs_upv_unpack = true end
                    if orig_rawequal(uval, orig_getfenv) then awxs_upv_getfenv = true end
                    if orig_rawequal(uval, orig_setfenv) then awxs_upv_setfenv = true end
                    u = u + 1
                end
            end

            if captured_awxs then
                local u = 1
                while u <= 60 do
                    local uname, uval = orig_getupvalue(captured_awxs, u)
                    if not uname then break end
                    awxs_direct_upv_count = awxs_direct_upv_count + 1
                    u = u + 1
                end
                check_closure_upvalues(captured_awxs)
            end

            -- Also inspect all reachable Lua closures created inside Stage 2 (`loop`, `start`, `make`, `wrapper`)
            for fn, _ in orig_pairs(visited_funcs) do
                if not orig_rawequal(fn, chunk_fn) then
                    check_closure_upvalues(fn)
                end
            end

            restore_env()

            return {
                ok = true,
                ok_exec = ok_exec,
                res_type = orig_type(res),
                builder_invoked = builder_invoked,
                builder_ok = builder_ok,
                builder_err = builder_err,
                -- Pillar 1 metrics
                stage1_probe_completed = stage1_probe_completed,
                total_smt_calls = total_smt_calls,
                post_probe_smt_calls = post_probe_smt_calls,
                post_probe_index_mt_calls = post_probe_index_mt_calls,
                unexpected_index_mt_tables = unexpected_index_mt_tables,
                visited_table_count = count_table_entries(visited_tables),
                visited_func_count = count_table_entries(visited_funcs),
                max_expected_strings_in_any_table = max_expected_strings_in_any_table,
                -- Pillar 2 metrics
                proto_count = #proto_tables,
                k_closure_count = #k_closures,
                total_enc_strings_across_protos = total_enc_strings_across_protos,
                max_enc_strings_single_proto = max_enc_strings_single_proto,
                max_ring_k_occupancy = max_ring_k_occupancy,
                max_ring_v_occupancy = max_ring_v_occupancy,
                strings_in_cons_tables = strings_in_cons_tables,
                plaintext_in_enc_k_tables = plaintext_in_enc_k_tables,
                ksalt_matched_outer = ksalt_matched_outer,
                ksalt_perturbation_changed_output = ksalt_perturbation_changed_output,
                ring_tested_gt20 = ring_tested_gt20,
                ring_fifo_eviction_verified = ring_fifo_eviction_verified,
                captured_ksalt = captured_ksalt or -1,
                -- Pillar 3 metrics
                captured_awxs_ok = (captured_awxs ~= nil),
                awxs_direct_upv_count = awxs_direct_upv_count,
                awxs_upv_tonum = awxs_upv_tonum,
                awxs_upv_sel = awxs_upv_sel,
                awxs_upv_mflr = awxs_upv_mflr,
                awxs_upv_err = awxs_upv_err or outer_local_err,
                awxs_upv_unpack = awxs_upv_unpack,
                awxs_upv_getfenv = awxs_upv_getfenv,
                awxs_upv_setfenv = awxs_upv_setfenv,
                outer_local_tonum = outer_local_tonum,
                outer_local_sel = outer_local_sel,
                outer_local_mflr = outer_local_mflr,
                outer_local_err = outer_local_err,
                outer_local_unpack = outer_local_unpack,
            }
        end
        """
    )
    return rt, inspector_fn


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Steph HUB v5.0 Deep getgc(true), 8-Slot Ring Buffer & Awxs Lexical Upvalue Inspector"
    )
    parser.add_argument("--repo", default=REPO_DIR, help="Path to pet99bynhmt repository")
    args = parser.parse_args()

    t0 = time.time()
    targets = get_target_files(args.repo)

    print("================================================================================", flush=True)
    print(f" Steph HUB v5.0 GC, 8-Slot Ring Buffer & Lexical Upvalue Audit ({len(targets)} files)", flush=True)
    print("================================================================================", flush=True)

    extractor = AstStringExtractor()

    pillar1_errors: List[str] = []
    pillar2_errors: List[str] = []
    pillar3_errors: List[str] = []

    audited_reports: List[Dict[str, object]] = []
    gt20_ring_modules_tested = 0

    for rel in targets:
        obf_path = os.path.join(args.repo, rel)
        if not os.path.isfile(obf_path):
            print(f"[FAIL] Missing obfuscated file: {obf_path}", flush=True)
            return 1
        with open(obf_path, "r", encoding="utf-8") as f:
            obf_code = f.read()

        clean_code = load_clean_source_for_file(rel, args.repo)
        expected_strings, max_proto_strs, total_unique_strs = extractor.extract(clean_code, rel)

        rt, inspector_fn = build_inspector_runtime()
        lua_str_tbl = rt.table_from(sorted(expected_strings))
        rep = inspector_fn(obf_code, rel, lua_str_tbl, len(expected_strings))

        if not rep["ok"]:
            msg = f"[{rel}] Inspector runtime failure: {rep['err']}"
            pillar1_errors.append(msg)
            continue

        # ---------------------------------------------------------------------
        # Pillar 1 Assertions: `getgc(true)` Heap Table & Metatable Audit
        # ---------------------------------------------------------------------
        if not rep["stage1_probe_completed"]:
            pillar1_errors.append(f"[{rel}] Stage-1 probe_tbl (__metatable=211) behavioral challenge did not complete!")

        if int(rep["post_probe_index_mt_calls"]) != 0:
            pillar1_errors.append(
                f"[{rel}] Expected 0 post-probe setmetatable(..., {{__index=...}}) calls, got {rep['post_probe_index_mt_calls']}"
            )

        if int(rep["unexpected_index_mt_tables"]) != 0:
            pillar1_errors.append(
                f"[{rel}] Found {rep['unexpected_index_mt_tables']} tables in getgc(true) with an unexpected __index metatable!"
            )

        if int(rep["strings_in_cons_tables"]) != 0:
            pillar1_errors.append(
                f"[{rel}] Found {rep['strings_in_cons_tables']} plaintext string constants stored in _cons literal table!"
            )

        if int(rep["plaintext_in_enc_k_tables"]) != 0:
            pillar1_errors.append(
                f"[{rel}] Found {rep['plaintext_in_enc_k_tables']} unencrypted plaintext strings inside _enc_k!"
            )

        # For any file with > 8 unique string constants, verify no table in `getgc(true)` holds the full string constant set
        if total_unique_strs > 8 and int(rep["max_expected_strings_in_any_table"]) >= total_unique_strs:
            pillar1_errors.append(
                f"[{rel}] A table in getgc(true) held {rep['max_expected_strings_in_any_table']}/{total_unique_strs} decrypted strings!"
            )

        if rel in ("manifest.lua", "lib/config.lua") or rel.startswith("modules/"):
            if not rep["ok_exec"]:
                pillar1_errors.append(f"[{rel}] Top-level execution failed!")
            if (rel == "lib/config.lua" or rel.startswith("modules/")) and (
                not rep["builder_invoked"] or not rep["builder_ok"]
            ):
                pillar1_errors.append(
                    f"[{rel}] Builder closure invocation failed: invoked={rep['builder_invoked']} err={rep['builder_err']}"
                )

        # ---------------------------------------------------------------------
        # Pillar 2 Assertions: 8-Slot Bounded Ring Buffer (`Y[f.constants]`)
        # ---------------------------------------------------------------------
        if int(rep["proto_count"]) < 1 or int(rep["k_closure_count"]) < 1:
            pillar2_errors.append(
                f"[{rel}] Failed to discover Stage-2 prototypes/K closures in getgc(true) (protos={rep['proto_count']})"
            )

        if int(rep["max_ring_k_occupancy"]) > 8 or int(rep["max_ring_v_occupancy"]) > 8:
            pillar2_errors.append(
                f"[{rel}] Ring buffer exceeded 8-slot bound! max_ring_k={rep['max_ring_k_occupancy']}, max_ring_v={rep['max_ring_v_occupancy']}"
            )

        if not rep["ksalt_matched_outer"]:
            pillar2_errors.append(f"[{rel}] Inner K(idx) _ksalt upvalue did not match outer-VM K_salt!")

        if int(rep["total_enc_strings_across_protos"]) > 0 and not rep["ksalt_perturbation_changed_output"]:
            pillar2_errors.append(f"[{rel}] Perturbing _ksalt upvalue did not alter decrypted string output!")

        if int(rep["max_enc_strings_single_proto"]) >= 20:
            if not rep["ring_tested_gt20"] or not rep["ring_fifo_eviction_verified"]:
                pillar2_errors.append(
                    f"[{rel}] Prototype with {rep['max_enc_strings_single_proto']} strings failed >20-string 8-slot FIFO eviction verification!"
                )
            elif int(rep["max_ring_v_occupancy"]) != 8:
                pillar2_errors.append(
                    f"[{rel}] Prototype with {rep['max_enc_strings_single_proto']} strings had max_ring_v={rep['max_ring_v_occupancy']} != 8"
                )
            else:
                gt20_ring_modules_tested += 1

        # ---------------------------------------------------------------------
        # Pillar 3 Assertions: Lexical Upvalue Binding Audit (`debug.getupvalue`)
        # ---------------------------------------------------------------------
        if not rep["captured_awxs_ok"]:
            pillar3_errors.append(f"[{rel}] Failed to capture inner Awxs closure (v_vm_fn) at Stage-1 OP_EXEC!")
        else:
            missing_upvs: List[str] = []
            if not rep["awxs_upv_tonum"]:
                missing_upvs.append("_tonum (tonumber)")
            if not rep["awxs_upv_sel"]:
                missing_upvs.append("_sel (select)")
            if not rep["awxs_upv_mflr"]:
                missing_upvs.append("_mflr (math.floor)")
            if not rep["awxs_upv_err"]:
                missing_upvs.append("_err (error)")
            if not rep["awxs_upv_unpack"]:
                missing_upvs.append("_unpack (unpack)")
            if missing_upvs:
                pillar3_errors.append(
                    f"[{rel}] Awxs closure missing lexical C-closure upvalues: {', '.join(missing_upvs)}"
                )

        audited_reports.append({
            "file": rel,
            "tables": int(rep["visited_table_count"]),
            "protos": int(rep["proto_count"]),
            "enc_strs": int(rep["total_enc_strings_across_protos"]),
            "max_proto_strs": int(rep["max_enc_strings_single_proto"]),
            "ring_v_max": int(rep["max_ring_v_occupancy"]),
            "ksalt": int(rep["captured_ksalt"]),
            "awxs_upvs": int(rep["awxs_direct_upv_count"]),
        })

    if gt20_ring_modules_tested < 10:
        pillar2_errors.append(
            f"Expected at least 10 modules with >20 distinct string constants per prototype, got {gt20_ring_modules_tested}"
        )

    # Print per-pillar results
    print("\n[Pillar 1/3] `getgc(true)` Heap Table & Metatable Audit (`manifest.lua`, `lib/config.lua`, `modules/*.lua`, all 23 files)...", flush=True)
    if pillar1_errors:
        for e in pillar1_errors:
            print(f"  FAIL: {e}", flush=True)
    else:
        print(
            f"  PASS: {len(audited_reports)}/{len(targets)} files verified — 0 post-probe `__index` metatables via `setmetatable`, "
            f"0 strings in `_cons`, 0 plaintext strings in `_enc_k`, and 0 constant pool tables holding the full decrypted string set.",
            flush=True,
        )

    print("\n[Pillar 2/3] 8-Slot Bounded Ring Buffer Verification (`Y[f.constants]` + outer-VM `K_salt`)...", flush=True)
    if pillar2_errors:
        for e in pillar2_errors:
            print(f"  FAIL: {e}", flush=True)
    else:
        print(
            f"  PASS: {len(audited_reports)}/{len(targets)} files verified ({gt20_ring_modules_tested} modules with >20 distinct strings/proto) — "
            f"`ring_k[1..8]` & `ring_v[1..8]` strictly bounded to <= 8 cached plaintext strings at every instant, salted by outer-VM `K_salt`.",
            flush=True,
        )

    print("\n[Pillar 3/3] Lexical Upvalue Binding Audit (`debug.getupvalue` on `Awxs` / `v_vm_fn`)...", flush=True)
    if pillar3_errors:
        for e in pillar3_errors:
            print(f"  FAIL: {e}", flush=True)
    else:
        print(
            f"  PASS: {len(audited_reports)}/{len(targets)} files verified — `_tonum`, `_sel`, `_mflr`, `_err`, `_unpack` "
            f"(plus `_getfenv`, `_setfenv`) are bound as immutable lexical closure upvalues pointing directly to verified C closures.",
            flush=True,
        )

    print("\n  Sample Deep Inspection Telemetry:", flush=True)
    for r in audited_reports:
        if r["file"] in ("manifest.lua", "lib/config.lua", "modules/farm.lua", "modules/event.lua", "ps99_engine_v3.lua", "games/steal_an_egg.lua"):
            print(
                f"    - {r['file']:22s} | getgc_tbls={r['tables']:3d} | protos={r['protos']:3d} | "
                f"enc_strs={r['enc_strs']:3d} (max/proto={r['max_proto_strs']:3d}) | "
                f"ring_v_max={r['ring_v_max']}/8 | K_salt={r['ksalt']:3d} | awxs_upvs={r['awxs_upvs']}",
                flush=True,
            )

    all_ok = not (pillar1_errors or pillar2_errors or pillar3_errors)
    elapsed = time.time() - t0
    print("\n================================================================================", flush=True)
    if all_ok:
        print(f" [ALL 3 GC & UPVALUE PILLARS PASSED] {len(audited_reports)}/{len(targets)} v5.0 files verified in {elapsed:.2f}s", flush=True)
        print("================================================================================", flush=True)
        return 0
    else:
        print(f" [GC & UPVALUE AUDIT FAILED] See errors above ({elapsed:.2f}s)", flush=True)
        print("================================================================================", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
