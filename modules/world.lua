-- modules/world.lua
-- Direct CFrame Island Teleport (Zones 1-279 incl. World 3 200+ & World 4 240+), Best World, and All Islands.
return function(ctx)
    local tab = ctx.win:CreateTab("World", "rbxassetid://16259403210")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Auto Island Teleport")
    ui.toggle(tab, { name = "Auto Tele Best Island (Middle)", key = "zoneTele", default = false })
    ui.toggle(tab, { name = "Stand In Island Middle", key = "teleCenter", default = true })
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

    local okCat, cat = pcall(engine.GetCatalog)
    local islands = (okCat and type(cat) == "table" and type(cat.islands) == "table" and #cat.islands > 0)
        and cat.islands or { "Spawn" }
    local selectedIsland = islands[1]

    ui.dropdown(tab, {
        name = "Select Island (" .. tostring(#islands) .. ")",
        options = islands,
        current = selectedIsland,
        callback = function(option) selectedIsland = tostring(option) end,
    })
    ui.button(tab, "Tele To Selected Island (Middle)", function()
        if not selectedIsland then return end
        local ok, res, msg = pcall(engine.TeleportIsland, selectedIsland)
        ui.notify("Island", tostring(ok and (msg or res) or res))
    end)
end
