-- modules/farm.lua
-- Breakables: fast click loop, fast farm, pet teleport after attack only, aura, orbs and rate knobs.
return function(ctx)
    local tab = ctx.win:CreateTab("Farm", "rbxassetid://82329173638641")
    local ui = ctx.ui

    ui.section(tab, "Breakables")
    ui.toggle(tab, {
        name = "Fast Auto Farm", key = "farm", default = false,
        note = "High-speed breakable damage + multi-target burst + routes pets to the attacked target.",
    })
    ui.toggle(tab, {
        name = "Fast Click (Auto Tap)", key = "tap", default = false,
        note = "Rapidly taps breakables in range without double-throttling.",
    })
    ui.toggle(tab, {
        name = "Click Aura", key = "clickAura", default = false,
        note = "Cycles the aura ring and taps every breakable inside it while keeping pets locked on their target.",
    })
    ui.toggle(tab, {
        name = "Orb Vacuum", key = "vacuum", default = false,
        note = "Forces the super-magnet flag on all orb records.",
    })

    ui.section(tab, "Pet Attack Behaviour")
    ui.toggle(tab, {
        name = "Pet Tele After Attack Only", key = "petTeleAfterAttack", default = true,
        note = "Pets ONLY teleport and boost speed after attacking a breakable. When not attacking, pets walk normally.",
    })
    ui.slider(tab, {
        name = "Pet Target Dwell", key = "PetAttackDwell",
        range = { 0.2, 1.2 }, increment = 0.05, suffix = "s", value = 0.45,
    })

    ui.section(tab, "Rates")
    ui.slider(tab, {
        name = "Hit Rate", key = "MaxTapRate",
        range = { 1, 120 }, increment = 1, suffix = "/s", value = 90,
    })
    ui.slider(tab, {
        name = "Burst Targets", key = "FarmBurst",
        range = { 0, 20 }, increment = 1, value = 10,
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

    ui.section(tab, "Movement")
    ui.toggle(tab, {
        name = "Jitter", key = "jitter", default = false,
        note = "Micro-delay variation on tap intervals.",
    })
    ui.toggle(tab, {
        name = "Aura Visual", key = "auraVisual", default = false,
        note = "Draws the aura ring around your character.",
    })
end
