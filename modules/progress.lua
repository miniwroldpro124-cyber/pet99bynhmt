-- modules/progress.lua
-- Auto Rank / Quest tasks, Ranks, Rebirth, Player Upgrades, Pet/Egg Slots, Forever Free Pack, Enchants.
return function(ctx)
    local tab = ctx.win:CreateTab("Progress", "rbxassetid://15642579187")
    local ui = ctx.ui

    ui.section(tab, "Auto Rank & Quests")
    ui.toggle(tab, {
        name = "Auto Do Rank / Quest Tasks", key = "autoDoQuest", default = false,
        note = "Priority-sorted Rank quests: auto hatches best egg & crafts Best Golden/Rainbow pets, Basic Coin Jar first, opens bundles/bags only when needed.",
    })
    ui.toggle(tab, { name = "Auto Claim Quests (NPC & Daily)", key = "autoQuest", default = false })
    ui.toggle(tab, { name = "Auto Claim Rank Rewards", key = "autoRank", default = false })

    ui.section(tab, "Progression & Slots")
    ui.toggle(tab, { name = "Auto Rebirth", key = "autoRebirth", default = false })
    ui.toggle(tab, { name = "Auto Buy Player Upgrades", key = "autoBuyUpgrades", default = false })
    ui.toggle(tab, { name = "Auto Buy Pet Equip Slots", key = "autoBuyPetSlots", default = false })
    ui.toggle(tab, { name = "Auto Buy Egg Bundle Slots", key = "autoBuyEggSlots", default = false })
    ui.toggle(tab, { name = "Auto Claim Forever Free Pack", key = "autoForeverPack", default = false })
    ui.toggle(tab, { name = "Auto Equip Enchants (Mastery)", key = "autoEquipEnchant", default = false })
end
