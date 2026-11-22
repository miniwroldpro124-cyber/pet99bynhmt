# ZAPX — PS99 loader

One file boots the menu (ZapHub / ZapLib 2.0.0), one file is the farm engine
(`ps99_engine_v3`, headless — no second window), one file per tab.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/d684186/main.lua?v=7.4"))()
```

`RightControl` window · `X` unload.

## Load order

`main.lua` → loading screen → `ps99_engine_v3.lua` → `zaphub.lua` (ZapLib) →
`lib/ui.lua` → `manifest.lua` → one fetch per `modules/*.lua` → Status tab.

Every fetch carries `?v=<VERSION>` so the executor URL cache never serves a stale
file. A tab that fails to download or compile is listed on the Status tab and
the rest still boot.

## Files

| file | role |
|---|---|
| `main.lua` | loader — progress screen, engine, ZapLib, module loop, Status tab, unload |
| `ps99_engine_v3.lua` | farm engine, headless: controller on `_G.__PS99CLEAN`, no ScreenGui, no Insert bind |
| `zaphub.lua` | ZapLib 2.0.0, publishes `_G.ZapLib.Window` |
| `lib/ui.lua` | element factories bound to `lib` + `engine` |
| `manifest.lua` | ordered tab list; add a row, nothing else changes |
| `modules/*.lua` | one builder per tab, receives `ctx` |
| `features.lua` | standalone ZapLib-only feature layer, kept for reference |
| `ps99_engine_v2.lua` | previous engine, builds its own GUI, kept for reference |
| `zapx.lua`, `zap_deploy.lua`, `zaphub_ps99.lua` | old single-file loaders, kept for reference |

## Engine controller (`_G.__PS99CLEAN`)

| call | use |
|---|---|
| `SetEnabled(key, bool)` | feature toggle, returns `ok, err` |
| `SetConfig(key, number)` | numeric knob, rejects anything not already in `CFG` |
| `AllOff()` | every feature off |
| `SetWorld(n)` | teleport target world, 1–4 |
| `SetPick(category, id, bool)` | narrow a consume worker to one id |
| `GetStatus()` | `running, enabled, world, profile, notes, info` |
| `GetPicks()` / `PickList()` | current ticks / available ids per category |
| `ClaimRankRewards()`, `Stop()` | one-shot claim, full teardown |

## Tabs

| tab | controls |
|---|---|
| Farm | Auto Farm, Tap, Click Aura, Orb Vacuum, Hit Rate, Burst, Reach, Rescan, Chests First, Jitter, Aura Visual |
| Pets | Pet Speed, Re-route rate, Auto Hatch, Hide Egg FX, Route All Pets, Pet Bulk Join |
| World | Teleport Best Zone, Snap To Centre, Buy Next Zone, Teleport Retry |
| Player | Walk Speed, Jump Power, Infinite Jump, Keep Movement, Reset, Refresh Status |
| Progress | Quests, Ranks, Rebirth, Pet Slots |
| Consume | Keys, Gift Bags, Fruits, Potions, Free Gifts, Ultimates, Dice |
| Picks | per-id narrowing for keys / bags / fruits / potions / free gifts / dice / cards |
| Machines | Daycare, Flags, Secret Rooms, Treehouse, Fuse, Cards, Relics, Mail |
| Render | Breakable FX, Pet FX, Anti AFK |
| Server | Auto Hop, Teleport World, All Features Off, Unload, Copy Source |
| Status | world / profile / zone / rank, active count, failed tabs, build, source |

## Element behaviour

- Toggle without `key` is local: only `onChange` runs.
- Slider primes its `key` with the build value and never fires `onChange` on
  build, so nothing moves on load.
- Dropdown callbacks fire once on build in ZapLib; `modules/picks.lua` arms on
  its toggle before writing a pick.

## Rebuild

`build_zaphub.py` rebuilds `zaphub.lua` from `zaphub_deobf_raw.lua` and refuses
to write on a token mismatch or compile failure. `luau-compile --binary` is the
gate for every other file.
