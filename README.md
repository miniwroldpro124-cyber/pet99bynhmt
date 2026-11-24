# Steph HUB — Multi-Game Loader (v9.7)

One universal loader (`main.lua`) automatically detects the current game and boots the matching script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua"))()
```

## Supported Games

| Game | Detection | Entry File | Controls |
|---|---|---|---|
| **Pet Simulator 99** | `GameId 3317771874` / World 1–4 & Trading Plaza PlaceIds | `games/ps99.lua` | `RightControl` toggle · `X` unload |
| **Steal an Egg** | `PlaceId 107778070777162` / `GameId 10563114921` | `games/steal_an_egg.lua` | `RightShift` or `RightControl` toggle |

If launched in an unrecognized place, `main.lua` displays manual buttons to boot either **Pet Simulator 99** or **Steal an Egg**.

## Repository layout

| file | role |
|---|---|
| `main.lua` | universal 2-game loader — detects game, downloads & launches `games/ps99.lua` or `games/steal_an_egg.lua` |
| `games/steal_an_egg.lua` | Steal an Egg hub — Smart Farm, Auto-hatch, Treadmill training & upgrades, Teleports, Economy (slots, Equip Best, trails, earnings, index), Explicit/Auto Selling, Players, Settings (verified against `ReplicatedStorage` client dump) |
| `games/ps99.lua` | Pet Simulator 99 bootstrap — progress bar, engine, Steph HUB UI, module loader, Status tab, unload (`X`) |
| `ps99_engine_v3.lua` | PS99 headless farm, teleport (World 1–4 / Zones 1–279), Time Trial (World 4 / Zone 279), enchant mastery, flag/ultimate/TNT, perf & Pumpkin Tycoon engine on `_G.__PS99CLEAN` |
| `lib/menu.lua` | PS99 Steph HUB UI runtime (`_G.StephLib`) |
| `lib/ui.lua` | PS99 UI element helpers bound to `lib` + `engine` |
| `lib/config.lua` | PS99 JSON config auto-save / auto-load / reset (`StephHUB/config.json`) |
| `manifest.lua` | PS99 ordered tab manifest (`Pumpkin Tycoon` → `Config`) |
| `modules/*.lua` | PS99 modular tab files (`timetrial`, `event`, `farm`, `pets`, `world`, `player`, `progress`, `consume`, `picks`, `cheat`, `machines`, `render`, `server`) |
