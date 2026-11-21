# ZAPX — PS99 loader

One file draws the menu, one file is the farm engine. No ZapLib, no key, no grey
panel.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua?v=5"))()
```

`RightControl` window · `X` unload.

## Why the menu changed

The old build loaded ZapLib and then the farm engine, and the engine built its
own `PS99 CLEAN v21` window on top. That grey box is what read as "old script
menu". The engine is now patched **headless** before it loads:

```lua
source = replace(source, "local function buildGUI()\n    local playerGui",
                         "local function buildGUI()\n    if true then return end\n    local playerGui")
source = replace(source, "…Insert then gui.root.Enabled…",
                         "…Insert and gui.root then …")
```

Both replacements are asserted on exact text, and the patched source is compiled
before publish (`test_headless.py`). The engine never creates a ScreenGui.

## Files

| file | what |
|---|---|
| `main.lua` | ZAPX loader — own UI, engine fetch, headless patch, all tabs |
| `zapx.lua` | same file, canonical name |
| `zap_deploy.lua` / `zaphub_ps99.lua` | same file, old links still boot |
| `ps99_engine_v2.lua` | farm engine — fetched and patched at runtime |
| `zaphub.lua` | ZapLib 2.0.0 — unused by the loader, kept for reference |
| `manifest.lua`, `modules/`, `lib/` | previous modular split — superseded, unused |

## Tabs

| tab | controls |
|---|---|
| Farm | Auto Farm, Auto Tap, Click Aura, Orb Vacuum, Hit Rate 1–60/s, Burst, Reach, Rescan, Chests First, Jitter, Aura Visual |
| Pets | Pet Speed, Pet Re-route, Route All Pets, Pet Bulk Join, Auto Hatch, Hide Egg Effects |
| World | Auto Teleport Best Zone, Snap To Island Centre, Auto Buy Next Zone, Teleport Retry |
| Progress | Auto Quests, Claim Ranks, Rebirth, Pet Slots |
| Consume | Keys, Bags, Fruits, Potions, Free Gifts, Ultimates, Dice |
| Machines | Daycare, Flags, Secret Rooms, Treehouse, Fuse, Cards, Relics, Mail |
| Render | Breakable FX, Pet FX, Anti AFK |
| Server | Auto Hop, All Features Off, Unload |
| Status | world / profile / active count, engine notes, log |

## Interface

Self-contained: dark frame, drag bar, left tab rail, animated toggles, sliders
with drag-track, notifications to the console log, live status bar. No external
UI library, so nothing to fail to load.

## Engine contract used

    SetEnabled(key, bool)   SetConfig(key, number)   GetStatus()
    AllOff()                Stop()

Everything else in the engine is untouched. With no picker list set, the consume
workers take everything they find (`allowAll`), which is why the old grey panel
is not needed.

## Provenance

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 decrypts to ZapLib alone. The real feature tabs are a separate key-gated
script that never reached disk here. `ps99_engine_v2.lua` is the engine already
present in the executor workspace, patched by `patch_engine.py` with a hard
assert on every replacement.
