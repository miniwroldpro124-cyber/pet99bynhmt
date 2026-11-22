-- modules/event.lua
-- Current Event Tab: Pumpkin Tycoon (Part 1 + Part 2 zones 1..8, Wild Pets, Turkey).
return function(ctx)
    local tab = ctx.win:CreateTab("Pumpkin Tycoon", "rbxassetid://118952082110870")
    local ui = ctx.ui
    local engine = ctx.engine

    local function setOpt(k, v, sub)
        if type(engine.SetEventOpt) == "function" then
            pcall(engine.SetEventOpt, k, v, sub)
        end
    end

    ui.section(tab, "Pumpkin Tycoon — Movement & Performance")
    ui.button(tab, "Teleport To Pumpkin Tycoon Event", function()
        if type(engine.EnterPumpkinTycoon) == "function" then
            local ok, res, msg = pcall(engine.EnterPumpkinTycoon)
            ui.notify("Pumpkin Tycoon", tostring(ok and (msg or res) or res))
        end
    end)
    ui.dropdown(tab, {
        name = "Select Movement Mode",
        options = { "Teleport", "Legit Walk" },
        current = "Teleport",
        callback = function(opt)
            setOpt("moveMode", tostring(opt))
            ui.notify("Movement Mode", tostring(opt))
        end,
    })
    ui.toggle(tab, {
        name = "Optimize Pumpkin Tycoon", key = "optPumpkinTycoon", default = false,
        note = "Cleans island + Turkey island and removes Turkey/pumpkin flashes & particle lag.",
    })

    ui.section(tab, "Tycoon Progression, Eggs & Rebirth")
    ui.toggle(tab, {
        name = "Auto Teleport to Best Pumpkin Egg/Area", key = "ptAutoTeleBestEgg", default = false,
        note = "Supports all 8 zones including Part 2 (Pine Woods, Maple Creek, Golden Ridge).",
    })
    ui.toggle(tab, {
        name = "Auto Buy Pumpkin Tycoon Buttons", key = "ptAutoBuyButtons", default = false,
        note = "Builds all zones (including 3 new Part 2 zones) & claims island rewards.",
    })
    ui.toggle(tab, { name = "Auto Rebirth Pumpkin Tycoon", key = "ptAutoRebirth", default = false })
    ui.toggle(tab, {
        name = "Auto Buy Nearest Pumpkin Egg", key = "ptAutoBuyEgg", default = false,
        note = "Intelligent coin-saving system (pauses hatching when next zone button is prioritized).",
    })

    ui.section(tab, "Pumpkins — Keep & Break")
    local keepMap = {
        ["Off (Break All)"] = 0, ["Basic+"] = 1, ["Rare+"] = 2, ["Epic+"] = 3,
        ["Legendary+"] = 4, ["Mythical+"] = 5, ["Exotic+"] = 6, ["Divine+"] = 7, ["Secret+"] = 8,
    }
    ui.dropdown(tab, {
        name = "Keep Pumpkin Tier",
        options = { "Off (Break All)", "Basic+", "Rare+", "Epic+", "Legendary+", "Mythical+", "Exotic+", "Divine+", "Secret+" },
        current = "Legendary+",
        callback = function(opt)
            local rung = keepMap[tostring(opt)] or 4
            setOpt("keepRung", rung)
            ui.notify("Auto Keep", tostring(opt))
        end,
    })
    ui.toggle(tab, { name = "Auto Keep Pumpkins", key = "ptAutoKeepPumpkins", default = false })
    ui.toggle(tab, {
        name = "Auto Break Pumpkins", key = "ptAutoBreakPumpkins", default = false,
        note = "Pets break every non-kept pumpkin on your island without you moving around.",
    })

    ui.section(tab, "Merchant & Planting")
    ui.toggle(tab, {
        name = "Auto Buy Selected Merchant Pumpkins", key = "ptAutoBuyMerchant", default = false,
        note = "Enables the game's own Auto Merchant + buys selected rarities below.",
    })
    ui.toggle(tab, {
        name = "Auto Plant Merchant Pumpkins", key = "ptAutoPlantPumpkins", default = false,
        note = "Enables auto-place and plants stocked pumpkins onto empty pedestals.",
    })
    for _, b in ipairs({
        { "RarePlus", "Merchant Band: Rare+" },
        { "EpicPlus", "Merchant Band: Epic+" },
        { "LegendaryPlus", "Merchant Band: Legendary+" },
        { "MythicalPlus", "Merchant Band: Mythical+" },
        { "ExoticPlus", "Merchant Band: Exotic+" },
    }) do
        ui.toggle(tab, { name = b[2], default = true, onChange = function(v) setOpt("merchantBands", v == true, b[1]) end })
    end

    ui.section(tab, "Upgrades, Hot Cocoa, Boosts & Gifts")
    ui.toggle(tab, { name = "Auto Buy Selected Pumpkin Upgrades", key = "ptAutoBuyUpgrades", default = false })
    for _, tr in ipairs({
        { "SpawnLuck", "Upgrade: Spawn Luck" },
        { "PumpkinCoins", "Upgrade: Patch Coin Payout" },
        { "PumpkinDamage", "Upgrade: Pumpkin Damage" },
        { "RespawnSpeed", "Upgrade: Faster Spawns" },
        { "StockSlots", "Upgrade: Merchant Stock" },
        { "AutoBreakRules", "Upgrade: Auto Break Rules" },
        { "ChaseOdds", "Upgrade: Chase Odds" },
        { "EggLuck", "Upgrade: Island Luck" },
        { "MerchantLuck", "Upgrade: Merchant Luck" },
    }) do
        ui.toggle(tab, { name = tr[2], default = true, onChange = function(v) setOpt("upgradeTracks", v == true, tr[1]) end })
    end

    ui.toggle(tab, { name = "Auto Buy Selected Hot Cocoa Boosts", key = "ptAutoBuyCocoa", default = false })
    ui.toggle(tab, { name = "Hot Cocoa: Patch Coin Boost", default = true, onChange = function(v) setOpt("cocoaBoosts", v == true, "PumpkinTycoonCoins1") end })
    ui.toggle(tab, { name = "Hot Cocoa: Pumpkin Damage Boost", default = true, onChange = function(v) setOpt("cocoaBoosts", v == true, "PumpkinTycoonDamage1") end })
    ui.toggle(tab, { name = "Hot Cocoa: Island Luck Boost", default = true, onChange = function(v) setOpt("cocoaBoosts", v == true, "PumpkinTycoonIslandLuck1") end })

    ui.toggle(tab, {
        name = "Auto Use Selected Pumpkin Boosts", key = "ptAutoUseBoosts", default = false,
        note = "Uses Tier III boosts first (Tier III -> Tier II -> Tier I).",
    })
    ui.toggle(tab, { name = "Use Boost: Patch Coin Boost", default = true, onChange = function(v) setOpt("pumpkinBoosts", v == true, "Patch Coin Boost") end })
    ui.toggle(tab, { name = "Use Boost: Pumpkin Damage Boost", default = true, onChange = function(v) setOpt("pumpkinBoosts", v == true, "Pumpkin Damage Boost") end })
    ui.toggle(tab, { name = "Use Boost: Island Luck Boost", default = true, onChange = function(v) setOpt("pumpkinBoosts", v == true, "Island Luck Boost") end })

    ui.toggle(tab, { name = "Auto Open Flannel Gifts", key = "ptAutoFlannelGifts", default = false })

    ui.section(tab, "Wild Pets & Pet Nets")
    ui.toggle(tab, { name = "Auto Hunt Wild Pets", key = "ptAutoHuntWild", default = false })
    local tierMap = { ["Any"] = 0, ["Uncommon"] = 1, ["Rare"] = 2, ["Epic"] = 3, ["Huge"] = 4 }
    ui.dropdown(tab, {
        name = "Hunt Minimum Tier",
        options = { "Any", "Uncommon", "Rare", "Epic", "Huge" },
        current = "Any",
        callback = function(opt) setOpt("huntMinTier", tierMap[tostring(opt)] or 0) end,
    })
    ui.toggle(tab, { name = "Hunt Variants Only (Gold/RB/Shiny)", default = false, onChange = function(v) setOpt("huntVariant", v == true) end })
    ui.toggle(tab, { name = "Save Ultra Net For Huge Pets", default = true, onChange = function(v) setOpt("huntUltraHuge", v == true) end })
    ui.toggle(tab, { name = "Auto Catch Wild Pets", key = "ptAutoCatchWild", default = false })
    ui.dropdown(tab, {
        name = "Net Selection Mode",
        options = { "Auto", "Pet Net", "Ultra Pet Net" },
        current = "Auto",
        callback = function(opt) setOpt("catchMinNet", tostring(opt)) end,
    })
    ui.toggle(tab, { name = "Auto Buy Pet Nets", key = "ptAutoBuyNets", default = false })

    ui.section(tab, "Turkey Boss & Rare Pet Spawns")
    ui.toggle(tab, { name = "Auto Fight Turkey", key = "ptAutoFightTurkey", default = false })
    ui.toggle(tab, {
        name = "Auto Catch Rare Pet Spawns", key = "ptAutoCatchRare", default = false,
        note = "Throws your best net at the Huge, Titanic or Gargantuan spawned after each Turkey.",
    })
end
