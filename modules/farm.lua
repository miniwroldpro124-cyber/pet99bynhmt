-- modules/farm.lua
-- Steph HUB Farm tab: Main Fast Farm, Fast Farm v2_Beta (Auto Efficient Farm), Auto Tap, Flags, Ultimate, Sprinkler, TNT, Enchants, Slots/Upgrades.
return function(ctx)
    local tab = ctx.win:CreateTab("Farm", "rbxassetid://82329173638641")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Auto Farm")
    ui.toggle(tab, { name = "Fast Auto Farm (Main)", key = "farm", default = false })
    ui.toggle(tab, {
        name = "Auto Efficient Farm (Fast Farm v2_Beta)", key = "fastFarmBeta", default = false,
        note = "Heartbeat bypass: chests/nearest sort, 1-pet-1-ore CQ_Route + JoinPetBulk + cpet.Arrived + 1e6 speed + 20-target burst.",
    })
    ui.toggle(tab, { name = "Auto Tap (Fast Click)", key = "tap", default = false })
    ui.toggle(tab, {
        name = "Auto Tap Real Game Speed (Legit)", key = "legitTap", default = false,
        note = "Matches real game auto-tap speed (~8/s single target) when Auto Tap is enabled.",
    })
    ui.toggle(tab, { name = "Click Aura", key = "clickAura", default = false })
    ui.toggle(tab, { name = "Orb Vacuum", key = "vacuum", default = false })

    ui.section(tab, "Zone Utilities (Flag, Ultimate, Sprinkler, TNT)")
    local okCat, cat = pcall(engine.GetCatalog)
    local flags = { "Any Flag" }
    if okCat and type(cat) == "table" and type(cat.flags) == "table" then
        for _, f in ipairs(cat.flags) do flags[#flags + 1] = tostring(f) end
    else
        for _, f in ipairs({ "Coins Flag", "Diamonds Flag", "Fortune Flag", "Hasty Flag", "Magnet Flag", "Rainbow Flag", "Shiny Flag", "Strength Flag", "Exotic Treasure Flag" }) do
            flags[#flags + 1] = f
        end
    end
    ui.dropdown(tab, {
        name = "Choose Flag",
        options = flags,
        current = flags[1],
        callback = function(opt)
            pcall(engine.SetConfig, "SelectedFlag", tostring(opt))
            ui.notify("Flag", "Selected: " .. tostring(opt))
        end,
    })
    ui.toggle(tab, {
        name = "Auto Use Flag", key = "autoFlags", default = false,
        note = "Smart active-flag detection; only places inside an active zone.",
    })
    ui.toggle(tab, { name = "Auto Use Ultimate", key = "autoUltimate", default = false })
    ui.toggle(tab, {
        name = "Auto Use Breakable Sprinkler", key = "autoSprinkler", default = false,
        note = "Detects active sprinklers in current zone via SprinklerCmds + world check.",
    })
    ui.toggle(tab, {
        name = "Auto Use TNT", key = "autoTNT", default = false,
        note = "Only consumes TNT when inside a breakable zone.",
    })
    ui.toggle(tab, {
        name = "Auto Use TNT Crate", key = "autoTNTCrate", default = false,
        note = "Only consumes TNT Crate when inside a breakable zone.",
    })

    ui.section(tab, "Enchants & Progression")
    ui.toggle(tab, {
        name = "Auto Equip Enchants (Mastery Best Tier)", key = "autoEquipEnchant", default = false,
        note = "Priority: 1. Coins, 2. Strong Pets, 3. Tap Power, 4. Lightning, then other highest usable tier per Enchant Mastery.",
    })
    ui.toggle(tab, { name = "Auto Buy Player Upgrades", key = "autoBuyUpgrades", default = false })
    ui.toggle(tab, { name = "Auto Buy Pet Equip Slots", key = "autoBuyPetSlots", default = false })
    ui.toggle(tab, { name = "Auto Buy Egg Bundle Slots", key = "autoBuyEggSlots", default = false })
    ui.toggle(tab, { name = "Auto Claim Forever Free Pack", key = "autoForeverPack", default = false })

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
