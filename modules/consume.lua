-- modules/consume.lua
-- Items the engine consumes from the picker panel.
return function(ctx)
    local tab = ctx.win:CreateTab("Consume", "rbxassetid://16089599792")
    local ui = ctx.ui

    ui.section(tab, "Items")
    ui.toggle(tab, {
        name = "Auto Keys", key = "autoKeys", default = false,
        note = "Combines and unlocks the key set. Only keys ticked in the engine panel are touched.",
    })
    ui.toggle(tab, {
        name = "Auto Gift Bags", key = "autoGiftBags", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Fruits", key = "autoFruits", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Potions", key = "autoPotions", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Free Gifts", key = "autoFreeGifts", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Ultimates", key = "autoUltimate", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Dice", key = "autoDice", default = false,
    })

    ui.paragraph(tab, "Pickers",
        "No separate picker panel. With nothing ticked the engine treats every "
        .. "item as allowed, so these workers take everything they find.")
end
