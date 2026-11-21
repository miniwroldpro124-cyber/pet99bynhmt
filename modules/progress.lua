-- modules/progress.lua
-- Quests, ranks, rebirth, pet slots.
return function(ctx)
    local tab = ctx.win:CreateTab("Progress", "rbxassetid://15642579187")
    local ui = ctx.ui

    ui.section(tab, "Quests")
    ui.toggle(tab, {
        name = "Auto Quests", key = "autoQuest", default = false,
        note = "Ensures, tracks and redeems NPC quests.",
    })

    ui.section(tab, "Rank")
    ui.toggle(tab, {
        name = "Auto Claim Ranks", key = "autoRank", default = false,
        note = "Claims every unclaimed rank reward.",
    })
    ui.toggle(tab, {
        name = "Auto Rebirth", key = "autoRebirth", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Buy Pet Slots", key = "autoBuyPetSlots", default = false,
        note = "Stops at 80 slots.",
    })
end
