# Steph HUB — Multi-Game Loader (v10.2)

One loader detects the current game and boots the matching hub:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua"))()
```

The hub menu stays hidden until the selected game's components, tabs, and saved configuration are ready. Downloaded components are version-checked so stale files cannot recreate the old `AnchorPoint` datatype crash.

## Supported Games

| Game | Detection | Controls |
|---|---|---|
| **Steal an Egg** | PlaceId `107778070777162`, GameId `10563114921`, game name, or `ReplicatedStorage.Client.EggState` | `RightShift` / `RightControl` toggle |
| **Pet Simulator 99** | GameId `3317771874`, known PlaceIds, game name, or `ReplicatedStorage.Library.Client` | `RightControl` toggle · `X` unload |

In an unrecognized place, the loader shows manual game-selection buttons.

## Repository layout

| File | Role |
|---|---|
| `main.lua` | Universal two-game loader, deferred menu display, component validation, PS99 tab/config bootstrap |
| `games/steal_an_egg.lua` | Steal an Egg hub: Smart Farm, auto-hatch, walking movement, treadmill training, teleports, economy, selling, players, settings |
| `ps99_engine_v3.lua` | PS99 automation engine and retrying profile/discovery bootstrap |
| `lib/menu.lua` | Shared Steph HUB window runtime |
| `lib/ui.lua` | UI element helpers |
| `lib/config.lua` | PS99 JSON configuration auto-save/auto-load/reset |
| `manifest.lua` | Ordered PS99 tab manifest |
| `modules/*.lua` | PS99 tab modules |
| `Stehp-Hub.lua` | Compatibility entry that launches `main.lua` |
| `games/ps99.lua` | Legacy compatibility entry that launches `main.lua` |

## Behavior

- Steal an Egg farm and training movement uses humanoid pathfinding/walking; manual teleports remain available.
- Steal an Egg configuration is saved and restored on rerun.
- PS99 opens only after every manifest tab and the saved configuration load successfully.
- The PS99 status tab and Auto Rank HUD retry missing `Library/Client/Save` modules instead of staying on `loading...`.
- Anti-AFK uses Roblox `VirtualUser` input and optional idle-connection handling. It does not bypass server-side anti-cheat or remote validation.
