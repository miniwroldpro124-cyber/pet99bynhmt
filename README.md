# ZapHub / PS99 — keyless

Two pieces, no key check anywhere in the chain.

| file | what |
|---|---|
| `main.lua` | entry point. wires the engine into the interface and opens it. |
| `zaphub_ps99.lua` | same file, canonical name. |
| `zap_deploy.lua` | same file, kept so old links work. |
| `ps99_engine.lua` | the farm engine — PS99 CLEAN, 35 workers, full remote map. |
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
| Farm | Auto Farm, Auto Tap, Click Aura, Orb Vacuum, Pet Speed, Auto Hatch, Jitter, Aura Visual |
| World | Auto Advance, Auto Teleport World, World 1–4 buttons, Auto Teleport Zones, Auto Buy Zones |
| Progress | Auto Quests, Auto Claim Ranks, Auto Rebirth, Auto Buy Pet Slots |
| Auto | Keys, Gift Bags, Fruits, Potions, Free Gifts, Ultimates, Dice |
| Machines | Daycare, Flexible Flags, Secret Rooms, Treehouse, Fuse, Cards, Relics, Mail Claim |
| Optimise | Reduce Breakable Effects, Reduce Pet Effects, Anti AFK |
| Server | Auto Server Hop, engine picker panel, All Features Off, Unload |
| Status | live world / profile / active feature count |

## Why there are two windows

The engine ships its own panel. It is hidden by default because the ZapLib
window covers every toggle. But the auto-consume workers — keys, bags, fruits,
potions, flags, dice, cards, free gifts — only touch the ids ticked in that
panel. Press `Insert` or use **Server → Open Engine Panel**, tick what you own,
then turn the worker on. Close it again with **Close Engine Panel**.

## How the two halves talk

`ps99_engine.lua` publishes a controller on `getgenv().__PS99CLEAN`:

    SetEnabled(key, bool)   SetWorld(n)   SetPick(category, id, value)
    GetStatus()             AllOff()      Stop()

Every ZapLib toggle is one `SetEnabled` call. Nothing is patched or rewritten;
the engine runs exactly as it was written.

## Provenance

The interface is the recovered Luarmor V4 payload:

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 decrypts to ZapLib alone — the feature tabs are a separate key-gated
script that never reached disk here. `ps99_engine.lua` is the engine that was
already present in the executor workspace, unmodified apart from being uploaded.
