-- modules/world.lua
-- Direct CFrame island teleport (stands in the middle, never uses game cannon teleport)
-- plus Best World teleport across Worlds 1-4 and all 279 islands.
return function(ctx)
    local tab = ctx.win:CreateTab("World", "rbxassetid://16259403210")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Auto Farm Island Teleport")
    ui.toggle(tab, {
        name = "Auto Teleport Best Island (Middle)", key = "zoneTele", default = false,
        note = "Directly snaps CFrame to the middle of your best owned island without calling Teleports_RequestTeleport.",
    })
    ui.toggle(tab, {
        name = "Keep Standing In Island Middle", key = "teleCenter", default = true,
        note = "Anchors your farm position to the centroid of INTERACT.BREAK_ZONES in the middle of the island.",
    })
    ui.toggle(tab, {
        name = "Auto Buy Next Island", key = "zoneBuy", default = false,
        note = "Automatically purchases the next locked zone as soon as you can afford it.",
    })
    ui.slider(tab, {
        name = "Teleport Check Interval", key = "TeleInterval",
        range = { 0.2, 5 }, increment = 0.2, suffix = "s", value = 0.4,
    })

    ui.section(tab, "Best World Teleport (Worlds 1 - 4)")
    ui.button(tab, "Teleport To Best World Now", function()
        local ok, res, msg = pcall(engine.TeleportBestWorld)
        if ok then
            ui.notify("Best World", tostring(msg or res))
        else
            ui.notify("Best World", tostring(res))
        end
    end)
    ui.toggle(tab, {
        name = "Auto Advance To Highest Unlocked World", key = "worldAdvance", default = false,
        note = "Automatically advances forward to the highest unlocked world (never teleports back to World 1).",
    })

    ui.section(tab, "All Islands Teleport (279 Islands)")
    local okCat, cat = pcall(engine.GetCatalog)
    local islands = (okCat and type(cat) == "table" and type(cat.islands) == "table" and #cat.islands > 0)
        and cat.islands or { "Spawn" }
    local selectedIsland = islands[1]

    ui.dropdown(tab, {
        name = "Select Island (" .. tostring(#islands) .. " Islands)",
        options = islands,
        current = selectedIsland,
        callback = function(option)
            selectedIsland = tostring(option)
        end,
    })

    ui.button(tab, "Teleport To Selected Island (Stand In Middle)", function()
        if not selectedIsland then return end
        local ok, res, msg = pcall(engine.TeleportIsland, selectedIsland)
        if ok then
            ui.notify("Island Teleport", tostring(msg or res))
        else
            ui.notify("Island Teleport", tostring(res))
        end
    end)
end
