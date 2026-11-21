-- modules/world.lua
-- Zone teleporting. World hopping is deliberately not wired.
return function(ctx)
    local tab = ctx.win:CreateTab("World", "rbxassetid://16259403210")
    local ui = ctx.ui

    ui.section(tab, "Zones")
    ui.toggle(tab, {
        name = "Auto Teleport Best Zone", key = "zoneTele", default = false,
        note = "Teleports to the highest zone you own the moment it is available.",
    })
    ui.toggle(tab, {
        name = "Snap To Island Centre", key = "teleCenter", default = true,
        note = "Lands on the centroid of the zone's own breakables, not the spawn edge.",
    })
    ui.toggle(tab, {
        name = "Auto Buy Next Zone", key = "zoneBuy", default = false,
        note = "Purchases with the game's own currency checks. Nothing is spent that the game would refuse.",
    })
    ui.slider(tab, {
        name = "Teleport Retry", key = "TeleInterval",
        range = { 0.2, 5 }, increment = 0.2, suffix = "s", value = 0.4,
    })
    ui.paragraph(tab, "World hopping",
        "Not wired. The engine never teleports you between worlds and the advance worker starts off.")
end
