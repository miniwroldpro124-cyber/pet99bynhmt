#!/usr/bin/env python3
"""
Pre-Obfuscator Luau Module Bundler for Steph HUB.

Combines multiple Lua/Luau source files into a single standalone Luau script
using an in-memory `__modules` / `__cache` / `__require` architecture before
feeding into Prometheus Stage-2 Vmify + Stage-1 VM obfuscation.

Public Python API:
  - bundle_sources(sources: dict[str, str], entry: str = "main") -> str
  - bundle_from_dir(src_dir: str, entry: str = "main") -> str

CLI:
  - python tools/bundler.py --src unobf --entry main --out <path>
  - python tools/bundler.py --self-test
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Dict, List, Set, Tuple

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(THIS_DIR)
DEFAULT_SRC_DIR = os.path.join(REPO_DIR, "unobf")

PROMETHEUS_DIRS = [
    os.path.join(REPO_DIR, "tools", "Prometheus", "src"),
    r"C:\Users\LaptopAT\.gemini\antigravity\scratch\Prometheus\src",
]


def normalize_module_key(path: str) -> str:
    """
    Normalize a module file path or identifier to an extensionless forward-slash key.
    Examples:
      'lib\\config.lua' -> 'lib/config'
      './modules/farm.lua' -> 'modules/farm'
      'main.lua' -> 'main'
      'lib/ui' -> 'lib/ui'
    """
    key = path.strip().replace("\\", "/")
    while key.startswith("./"):
        key = key[2:]
    key = key.lstrip("/")
    if key.endswith(".luau"):
        key = key[:-5]
    elif key.endswith(".lua"):
        key = key[:-4]
    return key


def sanitize_lua_source(source: str) -> str:
    """
    Strip leading UTF-8 BOM and Unix shebang lines if present, and normalize
    line endings to LF without altering internal multiline string literals.
    """
    if source.startswith("\ufeff"):
        source = source[1:]
    source = source.replace("\r\n", "\n").replace("\r", "\n")
    if source.startswith("#!"):
        nl = source.find("\n")
        source = source[nl + 1 :] if nl != -1 else ""
    if source.startswith("\ufeff"):
        source = source[1:]
    return source


def _lua_quote(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\0", "\\0")
    )
    return f'"{escaped}"'


def _build_bundled_lookup_lua(bundled_keys: Set[str]) -> str:
    entries = ", ".join(f"[{_lua_quote(k)}] = true" for k in sorted(bundled_keys))
    return "{" + entries + "}"


def _transform_module_for_bundle(
    key: str,
    code: str,
    all_sources: Dict[str, str],
    bundled_keys: Set[str],
    entry_key: str,
) -> str:
    """
    In-memory bundle adaptation (never mutates files on disk):
      1. If both 'main' and compatibility wrapper ('Stehp-Hub' / 'games/ps99')
         are bundled together and not serving as an isolated entry without 'main',
         route compatibility wrappers cleanly through `require("main", ...)`.
      2. For loader modules defining `local function httpGet(relative)` and
         `local function compile(source, label)` (such as `unobf/main.lua`),
         resolve any bundled component directly in-memory via `require(...)`
         without `game:HttpGet` network fetches or `loadstring` compilation.
      3. For `games/steal_an_egg` (`ensurePs99Engine`), resolve `ps99_engine_v3`
         in-memory via `require("ps99_engine_v3")` when bundled.
    """
    if key == "games/ps99" and "main" in bundled_keys and key != entry_key:
        if "game:HttpGet" in code and "main.lua" in code:
            return 'return require("main", ...)\n'

    if key == "Stehp-Hub" and "main" in bundled_keys and key != entry_key:
        if all_sources.get("Stehp-Hub") == all_sources.get("main"):
            return 'return require("main", ...)\n'

    if (
        "local function httpGet(relative)" in code
        and "local function compile(source, label)" in code
    ):
        lookup_literal = _build_bundled_lookup_lua(bundled_keys)
        http_get_injection = (
            f"local __BUNDLED_SET = {lookup_literal}\n"
            "local function __resolveBundled(relative)\n"
            '    if type(relative) ~= "string" then\n'
            "        return nil\n"
            "    end\n"
            '    local k = relative:gsub("\\\\", "/"):gsub("^%./", ""):gsub("^/+", ""):gsub("%?.*$", "")\n'
            "    if __BUNDLED_SET[k] then\n"
            "        return k\n"
            "    end\n"
            '    if k:sub(-4) == ".lua" then\n'
            "        k = k:sub(1, -5)\n"
            '    elseif k:sub(-5) == ".luau" then\n'
            "        k = k:sub(1, -6)\n"
            "    end\n"
            "    if __BUNDLED_SET[k] then\n"
            "        return k\n"
            "    end\n"
            '    local slashKey = k:gsub("%.", "/")\n'
            "    if __BUNDLED_SET[slashKey] then\n"
            "        return slashKey\n"
            "    end\n"
            "    return nil\n"
            "end\n\n"
            "local function httpGet(relative)\n"
            "    local __bkey = __resolveBundled(relative)\n"
            "    if __bkey ~= nil then\n"
            "        return function(...)\n"
            "            return require(__bkey, ...)\n"
            "        end\n"
            "    end"
        )
        code = re.sub(
            r"local\s+function\s+httpGet\s*\(\s*relative\s*\)",
            lambda _m: http_get_injection,
            code,
            count=1,
        )

        compile_injection = (
            "local function compile(source, label)\n"
            '    if type(source) == "function" then\n'
            "        return source\n"
            "    end"
        )
        code = re.sub(
            r"local\s+function\s+compile\s*\(\s*source\s*,\s*label\s*\)",
            lambda _m: compile_injection,
            code,
            count=1,
        )

        code = re.sub(
            r'local\s+chunk\s*=\s*loadstring\s*\(\s*modSource\s*,\s*"="\s*\.\.\s*entry\.file\s*\)',
            lambda _m: 'local chunk = type(modSource) == "function" and modSource or loadstring(modSource, "=" .. entry.file)',
            code,
        )

    if key == "games/steal_an_egg" and "ps99_engine_v3" in bundled_keys:
        sae_pattern = (
            r"(ensurePs99Engine\s*=\s*function\s*\(\s*\)\s*\n"
            r"\s*if\s+stopped\s+then\s+return\s+nil\s+end\s*\n"
            r"\s*if\s+engine\s+then\s+return\s+engine\s+end\s*\n"
            r"\s*if\s+engineLoading\s+then\s+return\s+nil\s+end)"
        )
        sae_replacement = (
            "\\1\n"
            "        do\n"
            "            engineLoading = true\n"
            '            local okBundled, loadedBundled = pcall(require, "ps99_engine_v3")\n'
            "            engineLoading = false\n"
            '            if okBundled and type(loadedBundled) == "table" then\n'
            "                engine = loadedBundled\n"
            '                engineCall(engine, "SetConfig", "TapRate", 60)\n'
            '                engineCall(engine, "SetConfig", "FarmTapRate", 90)\n'
            '                engineCall(engine, "SetConfig", "EggMaxHatch", 100)\n'
            "                return engine\n"
            "            end\n"
            "        end"
        )
        code = re.sub(sae_pattern, sae_replacement, code, count=1)

    return code


def bundle_sources(sources: dict[str, str], entry: str = "main") -> str:
    """
    Bundle a mapping of `{module_path_or_name: luau_source}` into a single
    standalone Luau chunk using the `__modules` / `__cache` / `__require`
    module-table architecture.
    """
    if not sources:
        raise ValueError("sources dictionary must not be empty")

    normalized: Dict[str, str] = {}
    for raw_name, raw_source in sources.items():
        if not isinstance(raw_name, str) or not raw_name.strip():
            raise ValueError(f"Invalid module name: {raw_name!r}")
        if not isinstance(raw_source, str):
            raise TypeError(f"Source for module {raw_name!r} must be str")
        norm_key = normalize_module_key(raw_name)
        if not norm_key:
            raise ValueError(f"Module name normalized to empty string: {raw_name!r}")
        normalized[norm_key] = sanitize_lua_source(raw_source)

    entry_key = normalize_module_key(entry)
    if entry_key not in normalized:
        raise KeyError(
            f"Entry module {entry_key!r} (from {entry!r}) not found in sources: "
            f"{sorted(normalized.keys())}"
        )

    bundled_keys: Set[str] = set(normalized.keys())
    ordered_keys: List[str] = sorted(normalized.keys())

    parts: List[str] = ["local __modules = {"]
    for mod_key in ordered_keys:
        transformed = _transform_module_for_bundle(
            key=mod_key,
            code=normalized[mod_key],
            all_sources=normalized,
            bundled_keys=bundled_keys,
            entry_key=entry_key,
        )
        body = transformed.rstrip("\r\n")
        parts.append(f"    [{_lua_quote(mod_key)}] = function(require, ...)")
        if body:
            parts.append(body)
        parts.append("    end,")
    parts.append("}")
    parts.append("")
    parts.append("local __cache = {}")
    parts.append("local __nil_sentinel = {}")
    parts.append("local function __require(name, ...)")
    parts.append('    if type(name) ~= "string" then')
    parts.append('        if type(require) == "function" then')
    parts.append("            return require(name, ...)")
    parts.append("        end")
    parts.append('        error("native require is unavailable", 2)')
    parts.append("    end")
    parts.append('    local key = name:gsub("\\\\", "/"):gsub("^%./", ""):gsub("^/+", ""):gsub("%?.*$", "")')
    parts.append("    if __modules[key] == nil then")
    parts.append('        if key:sub(-4) == ".lua" then')
    parts.append("            key = key:sub(1, -5)")
    parts.append('        elseif key:sub(-5) == ".luau" then')
    parts.append("            key = key:sub(1, -6)")
    parts.append("        end")
    parts.append("        if __modules[key] == nil then")
    parts.append('            local dotted = key:gsub("%.", "/")')
    parts.append("            if __modules[dotted] ~= nil then")
    parts.append("                key = dotted")
    parts.append('            elseif __modules[key .. "/init"] ~= nil then')
    parts.append('                key = key .. "/init"')
    parts.append('            elseif __modules[dotted .. "/init"] ~= nil then')
    parts.append('                key = dotted .. "/init"')
    parts.append("            end")
    parts.append("        end")
    parts.append("    end")
    parts.append("    local loader = __modules[key]")
    parts.append("    if loader == nil then")
    parts.append('        if type(require) == "function" then')
    parts.append("            return require(name, ...)")
    parts.append("        end")
    parts.append("        error(\"module '\" .. tostring(name) .. \"' not found\", 2)")
    parts.append("    end")
    parts.append("    if __cache[key] == nil then")
    parts.append("        local res = loader(__require, ...)")
    parts.append("        if res == nil then")
    parts.append("            __cache[key] = __nil_sentinel")
    parts.append("        else")
    parts.append("            __cache[key] = res")
    parts.append("        end")
    parts.append("    end")
    parts.append("    if __cache[key] == __nil_sentinel then")
    parts.append("        return nil")
    parts.append("    end")
    parts.append("    return __cache[key]")
    parts.append("end")
    parts.append("")
    parts.append(f"return __require({_lua_quote(entry_key)})")
    parts.append("")

    return "\n".join(parts)


def collect_sources_from_dir(src_dir: str) -> dict[str, str]:
    """
    Recursively collect all `.lua` and `.luau` files under `src_dir` into a
    dict mapping relative slash path -> raw UTF-8 text.
    """
    resolved_dir = src_dir
    if not os.path.isdir(resolved_dir):
        repo_candidate = os.path.join(REPO_DIR, src_dir)
        if os.path.isdir(repo_candidate):
            resolved_dir = repo_candidate
        else:
            raise FileNotFoundError(f"Source directory not found: {src_dir}")

    resolved_dir = os.path.abspath(resolved_dir)
    collected: dict[str, str] = {}
    for root, dirs, files in os.walk(resolved_dir):
        dirs.sort()
        for fname in sorted(files):
            if not (fname.endswith(".lua") or fname.endswith(".luau")):
                continue
            if fname.endswith(".unobf.lua"):
                continue
            full_path = os.path.join(root, fname)
            rel_path = os.path.relpath(full_path, resolved_dir).replace("\\", "/")
            with open(full_path, "r", encoding="utf-8-sig") as f:
                collected[rel_path] = f.read()

    if not collected:
        raise ValueError(f"No .lua or .luau files found in {resolved_dir}")
    return collected


def bundle_from_dir(src_dir: str, entry: str = "main") -> str:
    """
    Load all `.lua`/`.luau` sources from `src_dir` and bundle them with `entry`
    as the entrypoint module.
    """
    sources = collect_sources_from_dir(src_dir)
    return bundle_sources(sources, entry=entry)


def verify_luau_syntax(code: str, filename: str = "bundle.lua") -> Tuple[int, int]:
    """
    Verify valid Luau AST syntax (and Stage-2 VM compilability) using
    `tools/Prometheus/src` via `lupa`.
    Returns `(statement_count, proto_child_count)`.
    """
    from lupa import lua51

    prom_src = None
    for candidate in PROMETHEUS_DIRS:
        if os.path.isfile(os.path.join(candidate, "prometheus.lua")):
            prom_src = candidate
            break
    if not prom_src:
        raise RuntimeError("Prometheus src directory not found under tools/Prometheus/src")

    rt = lua51.LuaRuntime()
    escaped_path = prom_src.replace("\\", "\\\\")
    parse_fn = rt.execute(
        f"""
        arg = {{}}
        package.path = "{escaped_path}\\\\?.lua;" .. package.path
        local Prometheus = require("prometheus")
        local Parser = require("prometheus.parser")
        local Compiler = require("prometheus.vm.compiler")
        Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error

        return function(src, name)
            local parser = Parser:new({{ LuaVersion = "LuaU" }})
            local ast = parser:parse(src, name)
            local stmts = (ast and ast.body and ast.body.statements) and #ast.body.statements or 0
            local proto = Compiler:compile(ast)
            local children = (proto and proto.children) and #proto.children or 0
            return stmts, children
        end
        """
    )
    stmts, children = parse_fn(code, filename)
    return int(stmts), int(children)


def run_self_test(src_dir: str = DEFAULT_SRC_DIR) -> None:
    """
    Execute comprehensive bundler self-tests:
      (a) Exact `require("lib/config")` caching, path normalization
          (`"lib/config"`, `"lib/config.lua"`, `"lib.config"`, `"./lib/config"`),
          UTF-8 BOM / shebang stripping, varargs forwarding, `false`/`nil`
          return caching, and cross-module `require`.
      (b) Passthrough of non-string / Roblox `ModuleScript` `require(obj)` and
          unbundled external modules to native global `require`, plus in-memory
          `main` loader resolution without `game:HttpGet`.
      (c) Full bundle generation of `unobf/` with Prometheus Luau AST parse &
          VM compiler verification.
    """
    from lupa import lua51

    # --- Test (a): Caching, normalization, BOM/shebang stripping, cross-module require ---
    sources_a = {
        "lib/config.lua": (
            "\ufeff#!/usr/bin/env luau\n"
            "_G.__cfg_loads = (_G.__cfg_loads or 0) + 1\n"
            "return { version = '1.2.0', loads = _G.__cfg_loads }\n"
        ),
        "lib/false_mod.lua": (
            "_G.__false_loads = (_G.__false_loads or 0) + 1\n"
            "return false\n"
        ),
        "lib/nil_mod.lua": (
            "_G.__nil_loads = (_G.__nil_loads or 0) + 1\n"
        ),
        "lib/ui.lua": (
            'local cfg1 = require("lib/config")\n'
            'local cfg2 = require("lib/config.lua")\n'
            "return { same = (cfg1 == cfg2), cfg = cfg1 }\n"
        ),
        "main.lua": (
            'local c1 = require("lib/config")\n'
            'local c2 = require("lib/config.lua")\n'
            'local c3 = require("lib.config")\n'
            'local c4 = require("./lib/config.lua")\n'
            'local ui = require("lib/ui")\n'
            'local f1 = require("lib/false_mod")\n'
            'local f2 = require("lib/false_mod.lua")\n'
            'local n1 = require("lib/nil_mod")\n'
            'local n2 = require("lib/nil_mod.lua")\n'
            "return {\n"
            "    same_all = (c1 == c2) and (c2 == c3) and (c3 == c4) and (c1 == ui.cfg) and ui.same,\n"
            "    cfg_loads = _G.__cfg_loads,\n"
            "    false_ok = (f1 == false) and (f2 == false) and (_G.__false_loads == 1),\n"
            "    nil_ok = (n1 == nil) and (n2 == nil) and (_G.__nil_loads == 1),\n"
            "    version = c1.version,\n"
            "}\n"
        ),
    }
    bundled_a = bundle_sources(sources_a, entry="main")
    assert bundled_a.startswith("local __modules = {\n"), "Bundle must start with `local __modules = {`"
    assert '["lib/config"] = function(require' in bundled_a, "Normalized key `lib/config` missing"
    assert 'return __require("main")' in bundled_a, "Entrypoint `return __require(\"main\")` missing"
    verify_luau_syntax(bundled_a, "self_test_a.lua")

    rt_a = lua51.LuaRuntime()
    res_a = rt_a.execute(bundled_a)
    assert bool(res_a["same_all"]) is True, "Cross-module & normalized require must return identical cached table"
    assert int(res_a["cfg_loads"]) == 1, f"Expected lib/config to execute once, got {res_a['cfg_loads']}"
    assert bool(res_a["false_ok"]) is True, "Module returning `false` must cache properly"
    assert bool(res_a["nil_ok"]) is True, "Module returning `nil` must cache properly"
    assert str(res_a["version"]) == "1.2.0", f"Unexpected version: {res_a['version']}"
    print("[SELF-TEST a] PASS: require('lib/config') caching, path normalization & cross-module require")

    # --- Test (b): Roblox Instance/ModuleScript passthrough + in-memory main loader ---
    sources_b = {
        "lib/config.lua": "return function(tag) return 'bundled:' .. tostring(tag) end\n",
        "modules/farm.lua": "return function(ctx) return 'farm_ok:' .. tostring(ctx.cfg('ps99')) end\n",
        "manifest.lua": "return { { name = 'Farm', file = 'modules/farm.lua' } }\n",
        "main.lua": (
            "local function httpGet(relative)\n"
            "    error('game:HttpGet network fetch should never run for bundled module: ' .. tostring(relative))\n"
            "end\n"
            "local function fetch(relative, label)\n"
            "    local body = httpGet(relative)\n"
            "    assert(body, label)\n"
            "    return body\n"
            "end\n"
            "local function compile(source, label)\n"
            "    return loadstring(source, '=' .. tostring(label))\n"
            "end\n"
            "local cfgBuilder = compile(fetch('lib/config.lua', 'config'), 'lib/config')()\n"
            "local manifest = compile(fetch('manifest.lua', 'manifest'), 'manifest')()\n"
            "local entry = manifest[1]\n"
            "local modSource = httpGet(entry.file)\n"
            'local chunk = loadstring(modSource, "=" .. entry.file)\n'
            "local farmBuilder = chunk()\n"
            "local farmResult = farmBuilder({ cfg = cfgBuilder })\n"
            "local rbxSave = require(_G.__mock_roblox_module_script)\n"
            "return {\n"
            "    farm = farmResult,\n"
            "    rbx_name = rbxSave.Name,\n"
            "    native_calls = _G.__native_require_calls,\n"
            "}\n"
        ),
    }
    bundled_b = bundle_sources(sources_b, entry="main")
    verify_luau_syntax(bundled_b, "self_test_b.lua")

    rt_b = lua51.LuaRuntime()
    rt_b.execute(
        """
        _G.__native_require_calls = 0
        _G.__mock_roblox_module_script = setmetatable(
            { ClassName = "ModuleScript", Name = "ReplicatedStorage.Library.Client.Save" },
            { __tostring = function() return "Instance(Save)" end }
        )
        _G.require = function(target)
            _G.__native_require_calls = _G.__native_require_calls + 1
            if type(target) == "table" and target.ClassName == "ModuleScript" then
                return { Name = target.Name, LoadedByNative = true }
            end
            error("Unexpected native require target: " .. tostring(target))
        end
        """
    )
    res_b = rt_b.execute(bundled_b)
    assert str(res_b["farm"]) == "farm_ok:bundled:ps99", f"Unexpected bundled main result: {res_b['farm']}"
    assert (
        str(res_b["rbx_name"]) == "ReplicatedStorage.Library.Client.Save"
    ), "Roblox ModuleScript require passthrough failed"
    assert int(res_b["native_calls"]) == 1, f"Expected exactly 1 native require call, got {res_b['native_calls']}"
    print("[SELF-TEST b] PASS: Roblox ModuleScript require(obj) passthrough & zero-HTTP main component resolution")

    # --- Test (c): Full `unobf/` directory bundle + Luau AST & VM compile verification ---
    raw_unobf = collect_sources_from_dir(src_dir)
    expected_keys = {normalize_module_key(k) for k in raw_unobf.keys()}
    full_bundle = bundle_from_dir(src_dir, entry="main")
    for required_key in (
        "main",
        "manifest",
        "ps99_engine_v3",
        "lib/config",
        "lib/ui",
        "lib/menu",
        "games/steal_an_egg",
        "modules/farm",
    ):
        assert required_key in expected_keys, f"Expected {required_key!r} in {src_dir}"
        assert f"[{_lua_quote(required_key)}] = function(require" in full_bundle, (
            f"Bundled output missing module entry {required_key!r}"
        )

    stmts, children = verify_luau_syntax(full_bundle, "stephhub_bundled.lua")
    assert children >= len(expected_keys), (
        f"Expected at least {len(expected_keys)} compiled module prototypes, got {children}"
    )
    print(
        f"[SELF-TEST c] PASS: Bundled {len(expected_keys)} modules from {src_dir!r} "
        f"({len(full_bundle):,} bytes, {stmts} top-level AST stmts, {children} top child protos)"
    )
    print("[SELF-TEST] ALL CHECKS PASSED.")


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bundle Steph HUB Luau modules into a single standalone file."
    )
    parser.add_argument(
        "--src",
        default=DEFAULT_SRC_DIR,
        help="Source directory containing clean Luau modules (default: unobf).",
    )
    parser.add_argument(
        "--entry",
        default="main",
        help="Entry module name (default: main).",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Output path for the bundled Luau file.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run built-in unit, passthrough, and full unobf/ Luau AST self-tests.",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        run_self_test(src_dir=args.src)
        if not args.out:
            return 0

    bundled = bundle_from_dir(args.src, entry=args.entry)
    verify_luau_syntax(bundled, filename=args.out or "bundle.lua")

    if args.out:
        out_path = os.path.abspath(args.out)
        out_dir = os.path.dirname(out_path)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(bundled)
        print(f"[BUNDLER] Wrote {len(bundled):,} bytes to {out_path}")
    else:
        sys.stdout.write(bundled)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
