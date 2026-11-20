# ZapHub / ZapLib 2.0.0

ZapLib is the interface — window, tabs, elements, config store, notifications,
Kaitun overlay. It ships **no game features**. The tabs are built by the script
that sits on top of it.

## Run

One line, everything:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/features.lua"))()
```

That fetches the library if it is not already loaded, then attaches:

| tab | contents |
|---|---|
| Farm | Auto Farm, target name, ProximityPrompt / ClickDetector, radius, reach, walk-to, find-now |
| Player | Walk Speed, Jump Power, Infinite Jump, reset character |
| Teleport | save position, return, origin, go to player, refresh list |
| Visual | Fullbright |
| Misc | rejoin, copy job id, server hop, rescan, stop everything |

Default toggle is **RightControl**. Settings persist to `ZapLib/Settings.zaplib`
in the executor workspace.

## Files

- `features.lua` — the feature layer. run this.
- `zaphub.lua` / `main.lua` / `zap_deploy.lua` — the library, identical copies.
  sha256 `93F530093E1D32DE56EEC793C8C903BB0E473E107EBA8B20A53061AE6C897E1C`

## ZapLib surface

    CreateWindow, Reset, Destroy, CreateKeySystem, CreateNotification,
    CreateQuest, SetTheme, RegisterTheme, SetLanguage, AddLanguage,
    AddTranslations, SetAnimationMode, SetNotificationsEnabled,
    SetQuestsEnabled, SetInterfaceScale

Tab builders: `CreateSection`, `CreateParagraph`, `CreateLabel`, `CreateButton`,
`CreateToggle`, `CreateSlider`, `CreateDropdown`, `CreateMultiDropdown`,
`CreateInput`, `CreateKeybind`.

Because `CreateWindow` stores the window on the library (`ZapLib.Window`), any
later script can attach tabs to the live window without rebuilding it.

## Provenance

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 is assembled inside the VM and passed straight to `loadstring`, so it
never exists as a file. The capture ran in the executor; the body was then
devirtualised, every string resolved through the payload's own decoder, and the
dead VM prologue cut. Function-local names remain as the VM emitted them.

The key-gated feature payload was never in this chain — stage 3 decrypts to
ZapLib alone. `features.lua` is a feature layer written against the recovered
API, not recovered code.
