# Steph HUB — PS99 (v8.0)

Modular Pet Simulator 99 script: one loader (`main.lua`), one headless engine (`ps99_engine_v3.lua`), the Steph HUB UI (`zaphub.lua`), and one file per tab under `modules/*.lua`.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua?v=8.0"))()
```

`RightControl` toggles the Steph HUB window · `X` unloads everything.

## Load order

`main.lua` → loading screen → `ps99_engine_v3.lua` → `zaphub.lua` (Steph HUB UI) → `lib/ui.lua` → `manifest.lua` → `modules/*.lua` → Status tab.

## Repository layout

| file | role |
|---|---|
| `main.lua` | loader — progress bar, engine bootstrap, Steph HUB UI, module loader, Status tab, unload (`X`) |
| `ps99_engine_v3.lua` | headless farm, teleport (World 1–4 / Zones 1–279), enchant mastery, flag/ultimate/TNT, perf & Pumpkin Tycoon engine on `_G.__PS99CLEAN` |
| `zaphub.lua` | Steph HUB UI runtime (`_G.ZapLib`) |
| `lib/ui.lua` | UI element helpers bound to `lib` + `engine` |
| `manifest.lua` | ordered tab manifest (`Pumpkin Tycoon` → `Server`) |
| `modules/event.lua` | Current Event tab (**Pumpkin Tycoon** Part 1 & Part 2, Movement Mode, Optimizer, Turkey, Wild Pets, Nets, Cocoa, Boosts, Gifts) |
| `modules/farm.lua` | Fast Auto Farm, Fast Farm v2_Beta, Auto Tap (Real Game Speed), Flag selector + active check, Ultimate, Sprinkler, TNT / TNT Crate, Auto Equip Enchants (Mastery-aware) |
| `modules/pets.lua` | Pet Speed, Re-route rate, Auto Hatch, Hide Egg FX, Route All Pets, Bulk Join |
| `modules/world.lua` | World 1–4 & Zone 1–279 teleport (Best Zone, Snap To Centre, Buy Next Zone, Spawn / Void 200 / Fantasy 240 quick teleports) |
| `modules/player.lua` | Walk Speed, Jump Power, Infinite Jump, Keep Movement |
| `modules/progress.lua` | Quests, Ranks, Rebirth, Player Upgrades, Pet Equip Slots, Egg Bundle Slots, Forever Free Pack, Auto Equip Enchants |
| `modules/consume.lua` | Keys, Gift Bags, Fruits, Potions, Free Gifts, Forever Free Pack, Dice |
| `modules/picks.lua` | Per-item filter selections for keys / bags / fruits / potions / gifts / dice / cards |
| `modules/cheat.lua` | Chest / Balloon / Lucky Block / Coin Jar / Comet / Meteoric / Pinata / Digsite / Fishing / Claw targets |
| `modules/machines.lua` | Daycare, Secret Rooms, Treehouse, Fuse, Cards, Shiny Relics, Mailbox |
| `modules/render.lua` | White Screen (3D render off), Reduce CPU & RAM mode, FPS Cap, Breakable/Pet FX toggles, Anti-AFK |
| `modules/server.lua` | Auto Server Hop, World 1–4 teleport, All Features Off, Unload, Copy Source URL |

## Engine controller (`_G.__PS99CLEAN`)

| call | use |
|---|---|
| `SetEnabled(key, bool)` | toggle any feature; returns `ok, err` |
| `SetConfig(key, value)` | set numeric or string option (e.g. `SelectedFlag`, `EventMoveMode`) |
| `AllOff()` | disable every feature |
| `SetWorld(n)` | switch/teleport World `1`–`4` |
| `EnterPumpkinTycoon()` | enter Pumpkin Tycoon event |
| `SetEventOpt(key, val)` / `GetEventOpts()` | configure selected Pumpkin Tycoon merchant items, boosts, and upgrades |
| `SetPick(category, id, bool)` | filter specific consumable IDs |
| `GetStatus()` | returns `running, enabled, world, profile, notes, info` |
| `Stop()` | clean teardown (restores rendering, FPS cap, White Screen, clears loops) |
