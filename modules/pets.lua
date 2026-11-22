-- modules/pets.lua
-- Pet speed/teleport tuning, all-egg selector, and 0ms hidden egg hatch animation.
return function(ctx)
    local tab = ctx.win:CreateTab("Pets", "rbxassetid://87867412432006")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Pet Teleport & Speed")
    ui.toggle(tab, {
        name = "Pet Speed Boost", key = "petSpeed", default = false,
        note = "Boosts pet movement speed toward attacked breakables without over-tele thrashing.",
    })
    ui.toggle(tab, {
        name = "Tele After Attack Only", key = "petTeleAfterAttack", default = true,
        note = "Only teleports pets after Breakables_PlayerDealDamage fires on a target; never teleports idle pets.",
    })
    ui.slider(tab, {
        name = "Pet Attack Speed", key = "PetSpeedMult",
        range = { 100, 50000 }, increment = 500, value = 10000,
    })
    ui.slider(tab, {
        name = "Pet Re-route Interval", key = "PetRouteRate",
        range = { 0.2, 1.0 }, increment = 0.05, suffix = "s", value = 0.4,
    })

    ui.section(tab, "Targeting")
    ui.toggle(tab, {
        name = "Route All Pets", key = "petAll", default = true,
        note = "Every owned pet is routed to the attacked breakable instead of the nearest half.",
    })
    ui.toggle(tab, {
        name = "Pet Bulk Join", key = "petBulkJoin", default = true,
        note = "Sends Breakables_JoinPetBulk ({ [euid] = uid }) once per target so pets deal damage immediately.",
    })

    ui.section(tab, "Hatching & Egg Effects")
    ui.toggle(tab, {
        name = "Auto Hatch Eggs", key = "autoEgg", default = false,
        note = "Continuously hatches the selected egg (or nearest/best egg if none is locked).",
    })
    ui.toggle(tab, {
        name = "Hide Egg Effects (Instant Hatch)", key = "hideEggFx", default = false,
        note = "Skips the 3D Egg Opening Frontend cutscene in 0ms, hides EggOpenAnimation UI, and strips egg particles.",
    })

    local okCat, cat = pcall(engine.GetCatalog)
    local eggs = (okCat and type(cat) == "table" and type(cat.eggs) == "table" and #cat.eggs > 0)
        and cat.eggs or { "Cracked Egg", "Spotted Egg", "Paw Egg" }
    local selectedEgg = eggs[1]
    local lockSelectedEgg = false

    ui.dropdown(tab, {
        name = "Select Egg (" .. tostring(#eggs) .. " Eggs)",
        options = eggs,
        current = selectedEgg,
        callback = function(option)
            selectedEgg = tostring(option)
            if lockSelectedEgg then
                pcall(engine.ClearPicks, "eggs")
                pcall(engine.SetPick, "eggs", selectedEgg, true)
                ui.notify("Eggs", "Locked egg: " .. selectedEgg)
            end
        end,
    })

    ui.toggle(tab, {
        name = "Lock Selected Egg For Auto Hatch",
        default = false,
        onChange = function(value)
            lockSelectedEgg = value == true
            pcall(engine.ClearPicks, "eggs")
            if lockSelectedEgg and selectedEgg then
                pcall(engine.SetPick, "eggs", selectedEgg, true)
                ui.notify("Eggs", "Auto Hatch locked to " .. selectedEgg)
            else
                ui.notify("Eggs", "Auto Hatch using nearest / best egg")
            end
        end,
    })

    ui.button(tab, "Hatch Selected Egg Now", function()
        if not selectedEgg then return end
        local ok, result, msg = pcall(engine.HatchEgg, selectedEgg)
        if ok then
            ui.notify("Egg Hatch", tostring(msg or result))
        else
            ui.notify("Egg Hatch", tostring(result))
        end
    end)
end
