# ZapHub / PS99 — keyless

Two pieces, no key check anywhere in the chain.

| file | what |
|---|---|
| `main.lua` | entry point. wires the engine into the interface and opens it. |
| `zaphub_ps99.lua` | same file, canonical name. |
| `zap_deploy.lua` | same file, kept so old links work. |
| `ps99_engine_v2.lua` | the farm engine — PS99 CLEAN, 38 wired workers, full remote map. |
| `ps99_engine.lua` | engine v1, superseded. |
| `zaphub.lua` | ZapLib 2.0.0, the interface. |
| `features.lua` | older generic layer. superseded by `main.lua`. |

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/main.lua"))()
```

`RightControl` window · `Insert` engine pickers · `X` unload.

## Tabs

| tab | contents |
|---|---|
| Farm | Auto Farm, Auto Tap, Click Aura, Orb Vacuum, Hit Rate, Burst Targets, Reach, Target Rescan, Chests First, Route All Pets, Pet Bulk Join, Pet Re-route, Pet Speed, Auto Hatch, Hide Egg Effects, Jitter, Aura Visual |
| World | Auto Teleport Best Zone, Snap To Zone Centre, Auto Buy Next Zone, Teleport Retry |
| Progress | Auto Quests, Auto Claim Ranks, Auto Rebirth, Auto Buy Pet Slots |
| Auto | Keys, Gift Bags, Fruits, Potions, Free Gifts, Ultimates, Dice |
| Machines | Daycare, Flexible Flags, Secret Rooms, Treehouse, Fuse, Cards, Relics, Mail Claim |
| Optimise | Reduce Breakable Effects, Reduce Pet Effects, Anti AFK |
| Server | Auto Server Hop, engine picker panel, All Features Off, Unload |
| Status | live world / profile / active feature count |

## v2 changes

- **Farm speed** — hit rate 18 → 64/s ceiling (slider 1–48), reach 150 → 220,
  target rescan 0.35 → 0.12 s, pet interval 0.25 → 0.1 s, pet re-route 0.5 → 0.15 s,
  plus a burst that sends damage on every extra in-range breakable per tick.
- **No world teleport** — the world hop toggle, the four Go To World buttons and
  the advance worker default are gone. `worldAdvance` starts off and nothing in
  the interface can turn it on. You stay in the world you are in.
- **Zone teleport is instant** — after the remote is accepted the character is
  snapped to the zone centre read off `__FAKE_GROUND`, with one 0.15 s re-snap,
  instead of walking in from the spawn edge.
- **Hide egg effects** — new toggle. Egg folder names are read off the live things
  root each pass, so `Eggs`, `ZoneEggs` or any other egg-named folder works.
- **Smarter pet targeting** — every owned pet is routed, not the nearest half.
  `Pet Bulk Join` sends `Breakables_JoinPetBulk` once per target so pets count
  from the first hit instead of after travel.
- **Chests first** — chests get their own track and win the target tiebreak.

## v3 changes

- **Old menu fixed** - the grey PS99 CLEAN v21 panel is the engine's own window
  and it came up enabled on some loads. It is now hidden on creation, on
  PlayerGui.ChildAdded, and on a 12 s watchdog. Only **Server -> Open Engine
  Panel** or Insert brings it back.
- **Cache buster** - zaphub.lua and ps99_engine_v2.lua are fetched with
  ?v=3. Append it to main.lua too if your executor caches: main.lua?v=3.
- **Pets attack** - pet records were filtered on an owner field that some
  builds leave nil, so auto click fired and every pet stayed put. Records from
  GetByPlayer are trusted now; SetTarget has a field-write fallback; heap
  rediscovery interval 120 s -> 25 s.
- **Island centre** - the teleport target is the centroid of the zone's own
  breakables (up to 400), not the ground plate. Re-snaps at 0.2 s and 0.6 s.

## Why there are two windows

The engine ships its own panel. It is hidden by default because the ZapLib
window covers every toggle. But the auto-consume workers — keys, bags, fruits,
potions, flags, dice, cards, free gifts — only touch the ids ticked in that
panel. Press `Insert` or use **Server → Open Engine Panel**, tick what you own,
then turn the worker on. Close it again with **Close Engine Panel**.

## How the two halves talk

`ps99_engine_v2.lua` publishes a controller on `getgenv().__PS99CLEAN`:

    SetEnabled(key, bool)   SetWorld(n)   SetPick(category, id, value)
    SetConfig(key, number)  GetConfig(key)
    GetStatus()             AllOff()      Stop()

Every ZapLib toggle is one `SetEnabled` call. Numeric sliders go through
`SetConfig`, which rejects any key that is not an existing numeric CFG field.
Nothing is patched or rewritten; the engine runs as it was written.

## Provenance

The interface is the recovered Luarmor V4 payload:

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 decrypts to ZapLib alone — the feature tabs are a separate key-gated
script that never reached disk here. `ps99_engine_v2.lua` is the engine that was
already present in the executor workspace, patched by `patch_engine.py`
with a hard assert on every replacement.
