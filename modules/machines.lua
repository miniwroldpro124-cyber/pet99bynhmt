-- modules/machines.lua
-- Sorted station & room workers.
return function(ctx)
    local tab = ctx.win:CreateTab("Machines", "rbxassetid://126141499544212")
    local ui = ctx.ui

    ui.section(tab, "Auto Machines & Rooms")
    ui.toggle(tab, { name = "Auto Cards", key = "autoCards", default = false })
    ui.toggle(tab, { name = "Auto Daycare", key = "autoDaycare", default = false })
    ui.toggle(tab, { name = "Auto Flags", key = "autoFlags", default = false })
    ui.toggle(tab, { name = "Auto Fuse", key = "autoFuse", default = false })
    ui.toggle(tab, { name = "Auto Mail Claim", key = "autoMailClaim", default = false })
    ui.toggle(tab, { name = "Auto Relics", key = "autoRelics", default = false })
    ui.toggle(tab, { name = "Auto Secret Rooms", key = "autoSecretRooms", default = false })
    ui.toggle(tab, {
        name = "Auto Spin All Tickets", key = "autoSpinTickets", default = false,
        note = "Spins all unlocked Spinny Wheel tickets, closes/reopens the wheel to skip animation delay, and auto-clicks Claim.",
    })
    ui.toggle(tab, { name = "Auto Open All Chests", key = "autoOpenChests", default = false })
    ui.toggle(tab, { name = "Auto Treehouse", key = "autoTreehouse", default = false })
end
