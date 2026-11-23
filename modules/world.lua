-- modules/world.lua
-- Direct CFrame & Legit Island Teleport (filtered to current World 1-4), Best World, and Zone Filter.
return function(ctx)
    local tab = ctx.win:CreateTab("World", "rbxassetid://16259403210")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Auto Island Teleport")
    ui.dropdown(tab, {
        name = "Teleport Mode",
        key = "TeleMode",
        options = { "Instant", "Legit" },
        current = "Instant",
        callback = function(option)
            ui.notify("Teleport Mode", tostring(option) .. " (Middle)")
        end,
    })
    ui.button(tab, "Tele To Farm (Middle + Egg)", function()
        local fn = engine.TeleportToFarm or engine.TeleportBestWorld
        local ok, res, msg = pcall(fn)
        ui.notify("Tele To Farm", tostring(ok and (msg or res) or res))
    end)
    ui.toggle(tab, { name = "Auto Tele Best Island (Middle)", key = "zoneTele", default = false })
    ui.toggle(tab, { name = "Stand In Island Middle", key = "teleCenter", default = false })
    ui.toggle(tab, {
        name = "Middle + Near Egg Priority", key = "teleNearEgg", default = false,
        note = "Stands inside the farm breakables as close to the middle as possible while staying in range of the island egg.",
    })
    ui.toggle(tab, { name = "Auto Buy Next Island", key = "zoneBuy", default = false })
    ui.slider(tab, { name = "Tele Check Interval", key = "TeleInterval", range = { 0.2, 5 }, increment = 0.2, suffix = "s", value = 0.4 })

    ui.section(tab, "World Teleports (1-4 / Zones 200+)")
    ui.button(tab, "Teleport To Best World", function()
        local ok, res, msg = pcall(engine.TeleportBestWorld)
        ui.notify("Best World", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Teleport World 3 (Void Spawn 200)", function()
        local ok, res, msg = pcall(engine.TeleportIsland, "Void Spawn")
        ui.notify("World 3", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Teleport World 4 (Fantasy Spawn 240)", function()
        local ok, res, msg = pcall(engine.TeleportIsland, "Fantasy Spawn")
        ui.notify("World 4", tostring(ok and (msg or res) or res))
    end)
    ui.toggle(tab, { name = "Auto Advance Highest World", key = "worldAdvance", default = false })

    local okW, wCat = pcall(engine.GetWorldCatalog)
    local curWorld = (okW and type(wCat) == "table" and wCat.world) or 1
    local islands = (okW and type(wCat) == "table" and type(wCat.islands) == "table" and #wCat.islands > 0)
        and wCat.islands or nil
    if not islands then
        local okCat, cat = pcall(engine.GetCatalog)
        islands = (okCat and type(cat) == "table" and type(cat.islands) == "table" and #cat.islands > 0)
            and cat.islands or { "Spawn" }
    end
    local selectedIsland = islands[1]

    ui.section(tab, ("World %d Islands (%d)"):format(curWorld, #islands))
    ui.dropdown(tab, {
        name = ("Select World %d Island (%d)"):format(curWorld, #islands),
        options = islands,
        current = selectedIsland,
        callback = function(option) selectedIsland = tostring(option) end,
    })
    ui.button(tab, "Tele To Selected Island (Middle)", function()
        if not selectedIsland then return end
        local ok, res, msg = pcall(engine.TeleportIsland, selectedIsland)
        ui.notify("Island", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Lock Farm To Selected Island", function()
        if not selectedIsland then return end
        pcall(engine.ClearPicks, "zones")
        pcall(engine.SetPick, "zones", selectedIsland, true)
        ui.notify("Zone Filter", "Locked farm to " .. selectedIsland)
    end)
    ui.button(tab, "Clear Island Filter (Allow All)", function()
        pcall(engine.ClearPicks, "zones")
        ui.notify("Zone Filter", "All islands allowed")
    end)
end
