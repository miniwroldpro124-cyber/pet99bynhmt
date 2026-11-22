-- modules/farm.lua
-- Sorted & compact Farm controls: Fast Farm, Fast Farm [BETA] bypass, Fast Click, Sprinkler, and tuning knobs.
return function(ctx)
    local tab = ctx.win:CreateTab("Farm", "rbxassetid://82329173638641")
    local ui = ctx.ui

    ui.section(tab, "Auto Farm")
    ui.toggle(tab, {
        name = "Fast Farm [BETA] (Speed/Attack Bypass)", key = "fastFarmBeta", default = false,
        note = "Heartbeat bypass: 1-pet-1-ore CQ_Route + same-frame JoinPetBulk + cpet.Arrived + 1e6 speed + 16-target burst.",
    })
    ui.toggle(tab, { name = "Fast Auto Farm", key = "farm", default = false })
    ui.toggle(tab, { name = "Fast Click (Auto Tap)", key = "tap", default = false })
    ui.toggle(tab, { name = "Click Aura", key = "clickAura", default = false })
    ui.toggle(tab, { name = "Orb Vacuum", key = "vacuum", default = false })
    ui.toggle(tab, { name = "Auto Use Sprinkler", key = "autoSprinkler", default = false })

    ui.section(tab, "Targeting & Tuning")
    ui.toggle(tab, { name = "Chests First", key = "chestFirst", default = true })
    ui.toggle(tab, { name = "Pet Tele After Attack Only", key = "petTeleAfterAttack", default = true })
    ui.toggle(tab, { name = "Jitter", key = "jitter", default = false })
    ui.toggle(tab, { name = "Aura Visual", key = "auraVisual", default = false })
    ui.slider(tab, { name = "Hit Rate", key = "MaxTapRate", range = { 1, 120 }, increment = 1, suffix = "/s", value = 90 })
    ui.slider(tab, { name = "Burst Targets", key = "FarmBurst", range = { 0, 20 }, increment = 1, value = 10 })
    ui.slider(tab, { name = "Reach", key = "TapRange", range = { 50, 400 }, increment = 10, suffix = " studs", value = 220 })
    ui.slider(tab, { name = "Target Rescan", key = "TargetRescan", range = { 0.05, 0.6 }, increment = 0.05, suffix = "s", value = 0.12 })
    ui.slider(tab, { name = "Pet Target Dwell", key = "PetAttackDwell", range = { 0.2, 1.2 }, increment = 0.05, suffix = "s", value = 0.45 })
end
