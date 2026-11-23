-- modules/machines.lua
-- Sorted station, room workers, and multi-ticket Auto Spin selector.
return function(ctx)
    local tab = ctx.win:CreateTab("Machines", "rbxassetid://126141499544212")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Auto Spin Tickets (Choose Menu)")
    ui.toggle(tab, {
        name = "Auto Spin Selected Tickets", key = "autoSpinTickets", default = false,
        note = "Spins chosen (or all if none chosen) Spinny Wheel & Raffle tickets with close/reopen animation bypass + auto-click Claim.",
    })

    local allTickets = {
        "Spinny Wheel Ticket",
        "Tech Spinny Wheel Ticket",
        "Void Spinny Wheel Ticket",
        "Fantasy Spinny Wheel Ticket",
        "Exclusive Raffle Ticket",
        "Tower Raffle Ticket",
        "Arcade Ticket",
        "Golden Paw Ticket",
        "Millionaire Ticket",
        "Mystery Ticket",
    }
    local chosenTicket = allTickets[1]
    ui.dropdown(tab, {
        name = ("Select Ticket (%d)"):format(#allTickets),
        options = allTickets,
        current = chosenTicket,
        callback = function(opt) chosenTicket = tostring(opt) end,
    })
    ui.button(tab, "Add Selected Ticket", function()
        if not chosenTicket then return end
        pcall(engine.SetPick, "tickets", chosenTicket, true)
        ui.notify("Tickets", "Added: " .. chosenTicket)
    end)
    ui.button(tab, "Choose All Tickets", function()
        for _, t in ipairs(allTickets) do
            pcall(engine.SetPick, "tickets", t, true)
        end
        ui.notify("Tickets", "Selected all " .. #allTickets .. " ticket types")
    end)
    ui.button(tab, "Clear Ticket Filter (Allow All)", function()
        pcall(engine.ClearPicks, "tickets")
        ui.notify("Tickets", "Cleared filter (all unlocked tickets allowed)")
    end)

    ui.section(tab, "Auto Machines & Rooms")
    ui.toggle(tab, { name = "Auto Cards", key = "autoCards", default = false })
    ui.toggle(tab, { name = "Auto Daycare", key = "autoDaycare", default = false })
    ui.toggle(tab, { name = "Auto Flags", key = "autoFlags", default = false })
    ui.toggle(tab, { name = "Auto Fuse", key = "autoFuse", default = false })
    ui.toggle(tab, { name = "Auto Mail Claim", key = "autoMailClaim", default = false })
    ui.toggle(tab, { name = "Auto Relics", key = "autoRelics", default = false })
    ui.toggle(tab, { name = "Auto Secret Rooms", key = "autoSecretRooms", default = false })
    ui.toggle(tab, { name = "Auto Open All Chests", key = "autoOpenChests", default = false })
    ui.toggle(tab, { name = "Auto Treehouse", key = "autoTreehouse", default = false })
end
