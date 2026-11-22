-- modules/consume.lua
-- Potion selection, Drink Highest Tier First, and auto-consumption workers.
return function(ctx)
    local tab = ctx.win:CreateTab("Consume", "rbxassetid://16089599792")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Potions (Select & Drink Highest Tier)")
    ui.toggle(tab, {
        name = "Auto Drink Potions", key = "autoPotions", default = false,
        note = "Automatically consumes allowed potions from your inventory.",
    })
    ui.toggle(tab, {
        name = "Drink Highest Tier First", key = "drinkHighestTier", default = true,
        note = "Sorts owned potion stacks by tier (tn) descending and drinks the highest usable tier first.",
    })
    ui.slider(tab, {
        name = "Minimum Potion Tier", key = "PotionMinTier",
        range = { 1, 11 }, increment = 1, value = 1,
    })

    local okCat, cat = pcall(engine.GetCatalog)
    local potions = (okCat and type(cat) == "table" and type(cat.potions) == "table" and #cat.potions > 0)
        and cat.potions or { "Coins", "Damage", "Diamonds", "Huge", "Lucky", "The Cocktail", "Treasure Hunter", "Walkspeed" }
    local chosenPotion = potions[1]
    local filterSelectedOnly = false

    ui.dropdown(tab, {
        name = "Select Potion To Drink (" .. tostring(#potions) .. " Potions)",
        options = potions,
        current = chosenPotion,
        callback = function(option)
            chosenPotion = tostring(option)
            if filterSelectedOnly then
                pcall(engine.SetPick, "potions", chosenPotion, true)
                ui.notify("Potions", "Added " .. chosenPotion .. " to drink list")
            end
        end,
    })
    ui.toggle(tab, {
        name = "Drink Selected Potion(s) Only",
        default = false,
        onChange = function(value)
            filterSelectedOnly = value == true
            if filterSelectedOnly and chosenPotion then
                pcall(engine.SetPick, "potions", chosenPotion, true)
                ui.notify("Potions", "Drinking selected potion: " .. chosenPotion)
            else
                pcall(engine.ClearPicks, "potions")
                ui.notify("Potions", "Filter cleared: drinking all potion types (highest tier first)")
            end
        end,
    })
    ui.button(tab, "Add Selected Potion To Filter", function()
        if not chosenPotion then return end
        pcall(engine.SetPick, "potions", chosenPotion, true)
        ui.notify("Potions", "Added " .. chosenPotion)
    end)
    ui.button(tab, "Clear Potion Filter (Drink All Types)", function()
        pcall(engine.ClearPicks, "potions")
        ui.notify("Potions", "Cleared potion filter; all potions allowed")
    end)

    ui.section(tab, "Other Consumables")
    ui.toggle(tab, {
        name = "Auto Keys (Combine & Unlock)", key = "autoKeys", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Gift Bags & Lootboxes", key = "autoGiftBags", default = false,
    })
    ui.toggle(tab, {
        name = "Auto Fruits", key = "autoFruits", default = false,
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
end
