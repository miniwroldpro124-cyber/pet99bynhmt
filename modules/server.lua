-- modules/server.lua
-- Server hop, the picker panel, and the two kill switches.
return function(ctx)
    local tab = ctx.win:CreateTab("Server", "rbxassetid://16093555964")
    local ui = ctx.ui

    ui.section(tab, "Hop")
    ui.toggle(tab, {
        name = "Auto Server Hop", key = "serverHop", default = false,
        note = "Hops when the server drops below the engine's player threshold.",
    })

    ui.section(tab, "Pickers")
    ui.paragraph(tab, "Engine panel",
        "Keys, bags, fruits, potions, flags, dice, cards and free gifts only fire on ids "
        .. "ticked in the engine's own panel. Open it here, tick what you own, close it again.")
    ui.button(tab, "Open Engine Panel", function()
        if not ctx.setPanel(true) then
            ui.notify("Pickers", "Panel not built yet - give it a second.")
        end
    end)
    ui.button(tab, "Close Engine Panel", function()
        ctx.setPanel(false)
    end)

    ui.section(tab, "Kill switches")
    ui.button(tab, "All Features Off", function()
        pcall(ctx.engine.AllOff)
        ui.notify("Engine", "All features off.")
    end)
    ui.button(tab, "Unload Everything", function()
        ctx.unload()
    end)
    ui.paragraph(tab, "Keys", "RightControl window - Insert engine panel - X unload.")
end
