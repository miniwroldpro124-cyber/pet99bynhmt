"""
build_zaphub.py - assemble the finished ZapHub / ZapLib script.

Source of truth: 04_clean.lua - the deobfuscated Luraph payload recovered in
the executor (chunk 04 of the ZHARVEST run). 04_fmt.lua from the same run is
NOT used: its formatter glued `c and(` into `cand(`, which silently turns a
local into a global read. Verified fixes stay in the pipeline, not in memory.

Pipeline:
  1. cut the dead VM prologue (bit32 polyfill + string decoder, unused after
     string resolution - confirmed: zero remaining calls, one `bit32` mention)
  2. splice header + boot around the body's `return t`
  3. format with zap_format.format_lua (whitespace only, tokens untouched)
  4. assert token stream identity, then compile

Outputs into OJBS-Q/zaphub-src:
  zaphub.lua             runnable script
  zaphub_deobf_raw.lua   untouched minified deobf (source of truth)
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))

from zap_format import format_lua, tokens  # noqa: E402

SRC_CAPTURE = pathlib.Path(r"C:\Users\LaptopAT\AppData\Local\Xeno\workspace\ZHARVEST\04_clean.lua")
OUT = pathlib.Path(r"C:\Users\LaptopAT\Downloads\OJBS-Q\zaphub-src")
SRC = SRC_CAPTURE if SRC_CAPTURE.exists() else OUT / "zaphub_deobf_raw.lua"
LUAU = pathlib.Path(r"C:\Users\LaptopAT\Downloads\OJBS-OPENCODE\zaphub_dump\tools\luau-compile.exe")
if not LUAU.exists():
    LUAU = pathlib.Path(r"C:\Users\LaptopAT\AppData\Local\Temp\luau_bin\luau-compile.exe")

BODY_MARKER = 'local a=game:GetService("Players")'
RETURN_TAIL = "return t"

HEADER = """--[[
    ZapHub / ZapLib 2.0.0
    by zap_xyz and 1dnt

    Recovered from the Luarmor V4 loader chain:
      stage 1  api.luarmor.net/files/v4/loaders/a20cb97f94d0d6aafcb766dae08a47c4.lua
      stage 2  cdn.luarmor.net/v4_init_novemide.lua      738759 b, Luraph V4 superflow
      stage 3  decrypted payload, captured in-executor as ZHARVEST chunk 04

    The Luraph VM was devirtualised, every string resolved through the
    payload's own decoder, and the recovered constants renamed back to their
    API names. Function-local names stay as the VM emitted them: renaming
    those would be guesswork, and guesswork is not a build.

    Public surface
      CreateWindow, Reset, Destroy, CreateKeySystem, CreateNotification,
      CreateQuest, SetTheme, RegisterTheme, SetLanguage, AddLanguage,
      AddTranslations, SetAnimationMode, SetNotificationsEnabled,
      SetQuestsEnabled, SetInterfaceScale

    Executor calls used: gethui, writefile, readfile, isfile, isfolder,
    makefolder, delfile, setclipboard. Each is probed before use.
]]

"""

BOOT = """
-- ===========================================================================
-- boot
-- ===========================================================================

local win = t:CreateWindow({
    Name = "ZapHub | by zap_xyz and 1dnt",
    Theme = "Dark",
    AnimationMode = "Smooth",
})

local home = win:CreateTab("Home", "rbxassetid://16259403210")

home:CreateSection("ZapLib 2.0.0")
home:CreateParagraph({
    Title = "Loaded",
    Content = "RightControl toggles the window. The settings tab carries theme, language, "
        .. "animation mode and interface scale; configuration is written to the executor "
        .. "workspace under ZapLib/Settings.zaplib.",
})

home:CreateSection("Session")
home:CreateButton({
    Name = "Copy Discord Invite",
    Callback = function()
        if setclipboard then
            pcall(setclipboard, "https://discord.gg/zaphub")
            t:CreateNotification({ Title = "ZapHub", Content = "Invite copied to the clipboard." })
        else
            t:CreateNotification({ Title = "ZapHub", Content = "discord.gg/zaphub" })
        end
    end,
})

home:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        local players = game:GetService("Players")
        local teleport = game:GetService("TeleportService")
        if not players.LocalPlayer then
            return
        end
        pcall(function()
            teleport:Teleport(game.PlaceId, players.LocalPlayer)
        end)
    end,
})

t:CreateNotification({
    Title = "ZapHub",
    Content = "Loaded. RightControl toggles the window.",
    Duration = 4,
})

return t
"""


def compile_ok(path: pathlib.Path) -> bool:
    res = subprocess.run([str(LUAU), "--binary", str(path)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0


def main() -> int:
    raw = SRC.read_text(encoding="utf-8", errors="strict")

    body = raw[raw.index(BODY_MARKER):]
    if "cand(" in body or "dor(" in body:
        raise SystemExit("mangled operator in source - wrong input file")

    tail_at = body.rindex(RETURN_TAIL)
    stub = body[:tail_at].rstrip()

    # Format only the recovered body. The boot section is authored text and is
    # spliced verbatim: the token formatter is proven on VM output, not on prose.
    formatted_body = format_lua(HEADER + stub)
    if tokens(formatted_body) != tokens(HEADER + stub):
        raise SystemExit("formatter changed the token stream - refusing to ship")

    text = formatted_body.rstrip() + "\n" + BOOT

    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "zaphub.lua"
    target.write_text(text, encoding="utf-8", newline="\n")
    (OUT / "zaphub_deobf_raw.lua").write_text(raw, encoding="utf-8", newline="\n")

    ok = compile_ok(target)
    print("zaphub.lua   %7d b  %5d lines  compile=%s" % (len(text), text.count("\n"), "ok" if ok else "FAIL"))
    print("raw deobf    %7d b  %5d lines" % (len(raw), raw.count("\n")))
    if not ok:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
