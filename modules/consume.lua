-- modules/consume.lua
-- Potions, Fruits, Gift Bags, Keys (with built-in pickers moved from Picks tab) and Free Zone Gifts.
return function(ctx)
    local tab = ctx.win:CreateTab("Consume", "rbxassetid://16089599792")
    local ui = ctx.ui
    local engine = ctx.engine

    local okCat, cat = pcall(engine.GetCatalog)
    cat = (okCat and type(cat) == "table") and cat or {}

    local function addPicker(category, label, items)
        if type(items) ~= "table" or #items == 0 then return end
        local chosen = items[1]
        ui.dropdown(tab, {
            name = ("Select %s (%d)"):format(label, #items),
            options = items,
            current = chosen,
            callback = function(opt) chosen = tostring(opt) end,
        })
        ui.button(tab, "Add Selected " .. label, function()
            if not chosen then return end
            pcall(engine.SetPick, category, chosen, true)
            ui.notify(label, "Added " .. chosen)
        end)
        ui.button(tab, "Clear " .. label .. " Filter (Allow All)", function()
            pcall(engine.ClearPicks, category)
            ui.notify(label, "All " .. label .. " allowed")
        end)
    end

    ui.section(tab, "Potions")
    ui.toggle(tab, {
        name = "Auto Drink Potions (No Stack)", key = "autoPotions", default = false,
        note = "Drinks 1 bottle per type; skips lower or same tier while a potion timer is active.",
    })
    ui.toggle(tab, { name = "Drink Highest Tier First", key = "drinkHighestTier", default = false })
    ui.slider(tab, { name = "Min Potion Tier", key = "PotionMinTier", range = { 1, 11 }, increment = 1, value = 1 })
    local potions = (type(cat.potions) == "table" and #cat.potions > 0)
        and cat.potions or { "Coins", "Damage", "Diamonds", "Huge", "Lucky", "The Cocktail", "Treasure Hunter", "Walkspeed" }
    addPicker("potions", "Potion", potions)

    ui.section(tab, "Auto Use & Free Gifts")
    ui.toggle(tab, {
        name = "Auto Claim Free Zone Gifts", key = "autoZoneGifts", default = false,
        note = "Claims Free Playtime Gifts, Forever Free Pack, Daily/Timed Zone Rewards, and Free Zone Vending Machines.",
    })
    ui.toggle(tab, { name = "Auto Claim Forever Free Pack", key = "autoForeverPack", default = false })
    ui.toggle(tab, { name = "Auto Free Gifts", key = "autoFreeGifts", default = false })
    ui.toggle(tab, { name = "Auto Dice", key = "autoDice", default = false })
    ui.toggle(tab, {
        name = "Auto Fruits (Full Queue)", key = "autoFruits", default = false,
        note = "Eats all selected fruits (Shiny first) up to your exact Fruit Queue limit.",
    })
    ui.toggle(tab, { name = "Auto Gift Bags & Lootboxes", key = "autoGiftBags", default = false })
    ui.toggle(tab, {
        name = "Auto Keys (Combine & Unlock 4 Worlds + Secret)", key = "autoKeys", default = false,
        note = "Combines key halves, opens the 4 world chests, and uses Secret Keys only in Crystal Key Castle (spin for Crystal Keys).",
    })
    ui.toggle(tab, {
        name = "Auto Open 4 World Chests + Secret Key Spin", key = "autoOpenChests", default = false,
        note = "Opens Crystal/Tech/Void/Fantasy chests (Worlds 1-4) and uses Secret Keys exclusively for Crystal Key Castle spin.",
    })

    ui.section(tab, "Item Filters (Optional)")
    addPicker("fruits", "Fruit", type(cat.fruits) == "table" and #cat.fruits > 0 and cat.fruits or { "Apple", "Orange", "Banana", "Pineapple", "Watermelon", "Rainbow" })
    addPicker("bags", "Gift Bag / Lootbox", type(cat.bags) == "table" and #cat.bags > 0 and cat.bags or { "Gift Bag", "Large Gift Bag", "Mini Chest", "Hype Egg" })
    addPicker("keys", "Key", { "Crystal Key", "Tech Key", "Void Key", "Fantasy Key", "Secret Key" })
end
