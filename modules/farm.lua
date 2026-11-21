-- modules/farm.lua
-- Breakables: the click loop, aura, orbs and the rate knobs.
return function(ctx)
    local tab = ctx.win:CreateTab("Farm", "rbxassetid://82329173638641")
    local ui = ctx.ui

    ui.section(tab, "Breakables")
    ui.toggle(tab, {
        name = "Auto Farm", key = "farm", default = false,
        note = "Sends Breakables_PlayerDealDamage on the engine's own tick and routes pets at the same target.",
    })
    ui.toggle(tab, {
        name = "Auto Tap", key = "tap", default = false,
        note = "Taps every breakable in range without moving the character.",
    })
    ui.toggle(tab, {
        name = "Click Aura", key = "clickAura", default = false,
        note = "Cycles the aura ring and taps anything inside it.",
    })
    ui.toggle(tab, {
        name = "Orb Vacuum", key = "vacuum", default = false,
        note = "Forces the super-magnet flag on nearby orb records.",
    })

    ui.section(tab, "Rates")
    ui.slider(tab, {
        name = "Hit Rate", key = "MaxTapRate",
        range = { 1, 48 }, increment = 1, suffix = "/s", value = 48,
    })
    ui.slider(tab, {
        name = "Burst Targets", key = "FarmBurst",
        range = { 0, 12 }, increment = 1, value = 6,
    })
    ui.slider(tab, {
        name = "Reach", key = "TapRange",
        range = { 50, 400 }, increment = 10, suffix = " studs", value = 220,
    })
    ui.slider(tab, {
        name = "Target Rescan", key = "TargetRescan",
        range = { 0.05, 0.6 }, increment = 0.05, suffix = "s", value = 0.12,
    })

    ui.section(tab, "Priority")
    ui.toggle(tab, {
        name = "Chests First", key = "chestFirst", default = true,
        note = "Chests win the tiebreak over normal breakables in the same scan.",
    })
    ui.paragraph(tab, "Pets",
        "Route All Pets and Pet Bulk Join live on the Pets tab.")

    ui.section(tab, "Movement")
    ui.toggle(tab, {
        name = "Jitter", key = "jitter", default = false,
        note = "Micro-movement so an idle kick cannot land.",
    })
    ui.toggle(tab, {
        name = "Aura Visual", key = "auraVisual", default = false,
        note = "Draws the aura ring. Cosmetic.",
    })
end
