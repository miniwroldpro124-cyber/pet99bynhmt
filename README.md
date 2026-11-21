# ZapHub / PS99 — keyless, modular

`main.lua` is a bootstrap. It downloads the engine, the interface, a manifest and
one file per tab, then wires them together. Every function lives in the project,
and the menu is the recovered ZapHub library.

```
main.lua                bootstrap: fetch, load, wire, unload
manifest.lua            ordered tab list — add a row, get a tab
lib/ui.lua              element factories bound to ZapLib + engine
modules/farm.lua        Auto Farm, Auto Tap, Click Aura, Orb Vacuum, rates, chests
modules/pets.lua        Pet Speed, Auto Hatch, Hide Egg Effects, routing
modules/world.lua       Auto Teleport Best Zone, Snap To Island Centre, Auto Buy
modules/progress.lua    Quests, Ranks, Rebirth, Pet Slots
modules/consume.lua     Keys, Bags, Fruits, Potions, Gifts, Ultimates, Dice
modules/machines.lua    Daycare, Flags, Secret Rooms, Treehouse, Fuse, Cards, Relics, Mail
modules/render.lua      Breakable FX, Pet FX, Anti AFK
modules/server.lua      Hop, picker panel, All Off, Unload
zaphub.lua              ZapLib 2.0.0 — the interface
ps99_engine_v2.lua      PS99 CLEAN — the farm engine
```

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua"))()
```

Append `?v=4` to the URL if your executor caches: `main.lua?v=4`.

`RightControl` window · `Insert` engine pickers · `X` unload.

## Module contract

Each file under `modules/` returns one function:

```lua
return function(ctx)
    local tab = ctx.win:CreateTab("Name", "rbxassetid://...")
    ctx.ui.toggle(tab, { name = "Auto Farm", key = "farm", default = false, note = "..." })
end
```

`ctx` carries `win`, `lib`, `ui`, `engine`, `player`, `version`, `base`,
`setPanel`, `unload`, `fetch`, `compile`. A module that throws is caught, named
on the Status tab, and the rest of the menu still builds.

## Element helpers

| call | engine |
|---|---|
| `ui.toggle(tab, spec)` | `SetEnabled(spec.key, bool)` |
| `ui.slider(tab, spec)` | `SetConfig(spec.key, number)` |
| `ui.button(tab, name, fn)` | plain callback |
| `ui.section` / `ui.paragraph` | layout only |

`SetConfig` rejects any key that is not an existing numeric `CFG` field, so a
typo in a module cannot inject state into the engine.

## Surface

38 toggles and 6 sliders across 8 tabs — every engine key except `worldTele` and
`worldAdvance`, which stay unwired on purpose. `test_modules.py` builds the whole
menu against a stub ZapLib and asserts the counts.

## Pickers

The auto-consume workers only touch ids ticked in the engine's own panel.
**Server → Open Engine Panel**, tick what you own, close it, then turn the worker
on. The panel is hidden at boot and only that button or `Insert` brings it back.

## Provenance

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 decrypts to ZapLib alone. The feature tabs are a separate key-gated
script that never reached disk here. `ps99_engine_v2.lua` is the engine that was
already in the executor workspace, patched by `patch_engine.py` with a hard
assert on every replacement.
