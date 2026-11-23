-- modules/pets.lua
-- Pet Speed, Routing, World-Filtered Egg Selector, and 0ms Hidden Egg Effects.
return function(ctx)
    local tab = ctx.win:CreateTab("Pets", "rbxassetid://87867412432006")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Pet Speed & Routing")
    ui.toggle(tab, { name = "Pet Speed Boost", key = "petSpeed", default = false })
    ui.toggle(tab, { name = "Route All Pets", key = "petAll", default = false })
    ui.toggle(tab, { name = "Pet Bulk Join", key = "petBulkJoin", default = false })
    ui.slider(tab, { name = "Pet Attack Speed", key = "PetSpeedMult", range = { 100, 50000 }, increment = 500, value = 10000 })
    ui.slider(tab, { name = "Pet Re-route Interval", key = "PetRouteRate", range = { 0.2, 1.0 }, increment = 0.05, suffix = "s", value = 0.4 })

    local okW, wCat = pcall(engine.GetWorldCatalog)
    local curWorld = (okW and type(wCat) == "table" and wCat.world) or 1
    local eggs = (okW and type(wCat) == "table" and type(wCat.eggs) == "table" and #wCat.eggs > 0)
        and wCat.eggs or nil
    if not eggs then
        local okCat, cat = pcall(engine.GetCatalog)
        eggs = (okCat and type(cat) == "table" and type(cat.eggs) == "table" and #cat.eggs > 0)
            and cat.eggs or { "Cracked Egg", "Spotted Egg", "Paw Egg" }
    end
    local selectedEgg = eggs[1]
    local lockSelectedEgg = false

    ui.section(tab, ("World %d Eggs & Hatching"):format(curWorld))
    ui.toggle(tab, { name = "Auto Hatch Eggs", key = "autoEgg", default = false })
    ui.toggle(tab, { name = "Hide Egg Effects (0ms Instant)", key = "hideEggFx", default = false })

    ui.dropdown(tab, {
        name = ("Select World %d Egg (%d)"):format(curWorld, #eggs),
        options = eggs,
        current = selectedEgg,
        callback = function(option)
            selectedEgg = tostring(option)
            if lockSelectedEgg then
                pcall(engine.ClearPicks, "eggs")
                pcall(engine.SetPick, "eggs", selectedEgg, true)
                ui.notify("Eggs", "Locked: " .. selectedEgg)
            end
        end,
    })
    ui.toggle(tab, {
        name = "Lock Selected Egg",
        default = false,
        onChange = function(value)
            lockSelectedEgg = value == true
            pcall(engine.ClearPicks, "eggs")
            if lockSelectedEgg and selectedEgg then
                pcall(engine.SetPick, "eggs", selectedEgg, true)
                ui.notify("Eggs", "Locked: " .. selectedEgg)
            else
                ui.notify("Eggs", "Using nearest / best egg")
            end
        end,
    })
    ui.button(tab, "Hatch Selected Egg Now", function()
        if not selectedEgg then return end
        local ok, result, msg = pcall(engine.HatchEgg, selectedEgg)
        ui.notify("Egg Hatch", tostring(ok and (msg or result) or result))
    end)
end
