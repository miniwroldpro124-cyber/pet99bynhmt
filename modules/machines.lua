-- modules/machines.lua
-- Station and room workers.
return function(ctx)
    local tab = ctx.win:CreateTab("Machines", "rbxassetid://126141499544212")
    local ui = ctx.ui

    ui.section(tab, "Station")
    ui.toggle(tab, { name = "Auto Daycare", key = "autoDaycare", default = false })
    ui.toggle(tab, { name = "Auto Flexible Flags", key = "autoFlags", default = false })
    ui.toggle(tab, { name = "Auto Secret Rooms", key = "autoSecretRooms", default = false })
    ui.toggle(tab, { name = "Auto Treehouse", key = "autoTreehouse", default = false })
    ui.toggle(tab, { name = "Auto Fuse", key = "autoFuse", default = false })
    ui.toggle(tab, { name = "Auto Cards", key = "autoCards", default = false })
    ui.toggle(tab, { name = "Auto Relics", key = "autoRelics", default = false })
    ui.toggle(tab, { name = "Auto Mail Claim", key = "autoMailClaim", default = false })
end
