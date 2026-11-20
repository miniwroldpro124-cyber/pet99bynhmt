# ZapHub / ZapLib 2.0.0

Full UI library, recovered from the Luarmor V4 chain and deobfuscated.

## Run

- `main.lua` — the script. Execute it in your executor.
- `zaphub.lua` — identical copy, same sha256.
- `zap_deploy.lua` — identical copy, kept so existing links keep working.

sha256 `93F530093E1D32DE56EEC793C8C903BB0E473E107EBA8B20A53061AE6C897E1C`

Default toggle is **RightControl**. Settings persist to `ZapLib/Settings.zaplib`
in the executor workspace.

## Surface

    CreateWindow, Reset, Destroy, CreateKeySystem, CreateNotification,
    CreateQuest, SetTheme, RegisterTheme, SetLanguage, AddLanguage,
    AddTranslations, SetAnimationMode, SetNotificationsEnabled,
    SetQuestsEnabled, SetInterfaceScale

Tab builders: `CreateSection`, `CreateParagraph`, `CreateLabel`, `CreateButton`,
`CreateToggle`, `CreateSlider`, `CreateDropdown`, `CreateInput`, `CreateKeybind`.

Themes: Dark, Light, Discord, Dracula, GitHub Dark, and the rest of the set.

## Provenance

| stage | artifact | bytes |
|---|---|---|
| 1 | Luarmor v4 loader stub `a20cb97f94d0d6aafcb766dae08a47c4.lua` | 1275 |
| 2 | `cdn.luarmor.net/v4_init_novemide.lua` — Luraph V4 superflow | 738759 |
| 3 | decrypted payload, captured in-executor | 149424 |

Stage 3 is assembled inside the VM and passed straight to `loadstring`, so it
never exists as a file. The capture ran in the executor; the body was then
devirtualised, every string resolved through the payload's own decoder, and the
dead VM prologue cut. Function-local names remain as the VM emitted them —
renaming those would be guesswork.
