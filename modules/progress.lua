-- modules/progress.lua
-- Auto Quests, Auto Do Quest Tasks, ranks, rebirth, pet slots.
return function(ctx)
    local tab = ctx.win:CreateTab("Progress", "rbxassetid://15642579187")
    local ui = ctx.ui

    ui.section(tab, "Quests")
    ui.toggle(tab, {
        name = "Auto Quests (Ensure & Claim)", key = "autoQuest", default = false,
        note = "Ensures, tracks and redeems NPC and Daily quests.",
    })
    ui.toggle(tab, {
        name = "Auto Do Quest Tasks", key = "autoDoQuest", default = false,
        note = "Automatically executes active Rank, Zone Gate, Zone, and NPC quest tasks (hatching eggs, drinking/upgrading potions, crafting gold/rainbow pets, deploying flags, spawning jars/comets/pinatas/lucky blocks, and farming breakables).",
    })

    ui.section(tab, "Rank & Progression")
    ui.toggle(tab, {
        name = "Auto Claim Ranks", key = "autoRank", default = false,
        note = "Claims every earned rank reward automatically.",
    })
    ui.toggle(tab, {
        name = "Auto Rebirth", key = "autoRebirth", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Buy Pet Slots", key = "autoBuyPetSlots", default = false,
        note = "Purchases pet equip slots up to 80.",
    })
end
