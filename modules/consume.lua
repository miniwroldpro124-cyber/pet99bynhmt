-- modules/consume.lua
-- Potions (select + highest tier first) and Auto Consumables (Keys, Bags, Fruits, Gifts, Dice, Forever Free Pack).
return function(ctx)
    local tab = ctx.win:CreateTab("Consume", "rbxassetid://16089599792")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Potions")
    ui.toggle(tab, { name = "Auto Drink Potions", key = "autoPotions", default = false })
    ui.toggle(tab, { name = "Drink Highest Tier First", key = "drinkHighestTier", default = true })
    ui.slider(tab, { name = "Min Potion Tier", key = "PotionMinTier", range = { 1, 11 }, increment = 1, value = 1 })

    local okCat, cat = pcall(engine.GetCatalog)
    local potions = (okCat and type(cat) == "table" and type(cat.potions) == "table" and #cat.potions > 0)
        and cat.potions or { "Coins", "Damage", "Diamonds", "Huge", "Lucky", "The Cocktail", "Treasure Hunter", "Walkspeed" }
    local chosenPotion = potions[1]
    local filterSelectedOnly = false

    ui.dropdown(tab, {
        name = "Select Potion (" .. tostring(#potions) .. ")",
        options = potions,
        current = chosenPotion,
        callback = function(option)
            chosenPotion = tostring(option)
            if filterSelectedOnly then
                pcall(engine.SetPick, "potions", chosenPotion, true)
                ui.notify("Potions", "Added " .. chosenPotion)
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
                ui.notify("Potions", "Filter: " .. chosenPotion)
            else
                pcall(engine.ClearPicks, "potions")
                ui.notify("Potions", "All potions allowed (highest tier first)")
            end
        end,
    })
    ui.button(tab, "Add Selected Potion", function()
        if not chosenPotion then return end
        pcall(engine.SetPick, "potions", chosenPotion, true)
        ui.notify("Potions", "Added " .. chosenPotion)
    end)
    ui.button(tab, "Clear Potion Filter", function()
        pcall(engine.ClearPicks, "potions")
        ui.notify("Potions", "Cleared potion filter")
    end)

    ui.section(tab, "Auto Use")
    ui.toggle(tab, { name = "Auto Claim Forever Free Pack", key = "autoForeverPack", default = false })
    ui.toggle(tab, { name = "Auto Free Gifts", key = "autoFreeGifts", default = false })
    ui.toggle(tab, { name = "Auto Dice", key = "autoDice", default = false })
    ui.toggle(tab, { name = "Auto Fruits", key = "autoFruits", default = false })
    ui.toggle(tab, { name = "Auto Gift Bags & Lootboxes", key = "autoGiftBags", default = false })
    ui.toggle(tab, { name = "Auto Keys (Combine & Unlock)", key = "autoKeys", default = false })
end
