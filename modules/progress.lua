-- modules/progress.lua
-- Compact Auto Rank / Quest tasks (Easy Coin Jar first, Gem Gift Bags only when needed), Ranks, Rebirth, Pet Slots.
return function(ctx)
    local tab = ctx.win:CreateTab("Progress", "rbxassetid://15642579187")
    local ui = ctx.ui

    ui.section(tab, "Auto Rank & Quests")
    ui.toggle(tab, {
        name = "Auto Do Rank / Quest Tasks", key = "autoDoQuest", default = false,
        note = "Basic Coin Jar first; opens Large/Small Gift Bags only for Gem quests; never wastes bags when not needed.",
    })
    ui.toggle(tab, { name = "Auto Claim Quests (NPC & Daily)", key = "autoQuest", default = false })
    ui.toggle(tab, { name = "Auto Claim Rank Rewards", key = "autoRank", default = false })

    ui.section(tab, "Progression")
    ui.toggle(tab, { name = "Auto Rebirth", key = "autoRebirth", default = false })
    ui.toggle(tab, { name = "Auto Buy Pet Slots", key = "autoBuyPetSlots", default = false })
end
