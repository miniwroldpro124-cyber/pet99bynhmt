-- modules/cheat.lua
-- In-game Edit & Cheat suite: Stats/Currency editor, Gamepass & Perk unlocker,
-- Gate/Barrier remover, Huge/Titanic/Gargantuan spawner & morpher, All Items/Potions/Eggs spoofer, Noclip & Fly.
return function(ctx)
    local tab = ctx.win:CreateTab("Cheat", "rbxassetid://6031090990")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "In-Game Unlocks & Bypasses")
    ui.toggle(tab, {
        name = "Unlock All Gamepasses & Perks", key = "unlockGamepasses", default = false,
        note = "Hooks Gamepasses.Owns/Active -> true, enables AutoTapper, GlobalInstantHatch, GlobalPetFly, and BypassTeleportRequirement.",
    })
    ui.toggle(tab, {
        name = "Remove All Zone Gates & Barriers", key = "removeGates", default = false,
        note = "Disables collisions on all zone gates, forcefields, and world borders.",
    })
    ui.button(tab, "Unlock All 279 Islands In Save", function()
        local ok, res, msg = pcall(engine.Cheat, "unlockAllZones")
        ui.notify("Cheat", tostring(msg or res))
    end)

    ui.section(tab, "Movement Cheats (Noclip & 3D Fly)")
    ui.toggle(tab, {
        name = "Noclip (Walk Through Walls)", key = "noclip", default = false,
    })
    ui.toggle(tab, {
        name = "Fly (WASD + Space / LeftCtrl)", key = "fly", default = false,
    })
    ui.slider(tab, {
        name = "Fly Speed", key = "FlySpeed",
        range = { 30, 350 }, increment = 10, suffix = " studs/s", value = 120,
    })

    ui.section(tab, "Edit Stats & Currency")
    local statOptions = {
        "Diamonds", "Coins", "Rank", "RankStars", "Rebirths",
        "EggHatchCount", "MaximumAvailableEgg", "PetSlotsPurchased",
    }
    local selectedStat = statOptions[1]
    local statAmount = 999999999

    ui.dropdown(tab, {
        name = "Select Stat To Edit",
        options = statOptions,
        current = selectedStat,
        callback = function(option)
            selectedStat = tostring(option)
        end,
    })
    ui.slider(tab, {
        name = "Small Stat Value (Rank / Rebirth / Eggs / Slots)",
        range = { 1, 291 }, increment = 1, value = 99,
        onChange = function(val)
            statAmount = val
        end,
    })
    ui.button(tab, "Apply Slider Value To Selected Stat", function()
        local ok, res, msg = pcall(engine.Cheat, "setStat", { key = selectedStat, value = statAmount })
        ui.notify("Edit Stat", tostring(msg or res))
    end)
    ui.button(tab, "Set Selected Stat = 1,000,000,000 (1B)", function()
        local ok, res, msg = pcall(engine.Cheat, "setStat", { key = selectedStat, value = 1000000000 })
        ui.notify("Edit Stat", tostring(msg or res))
    end)
    ui.button(tab, "Set Selected Stat = 999,999,999,999 (999B)", function()
        local ok, res, msg = pcall(engine.Cheat, "setStat", { key = selectedStat, value = 999999999999 })
        ui.notify("Edit Stat", tostring(msg or res))
    end)

    local okCat, cat = pcall(engine.GetCatalog)
    cat = (okCat and type(cat) == "table") and cat or {}
    local huges = (type(cat.huges) == "table" and #cat.huges > 0) and cat.huges or { "Huge Cat", "Titanic Cat", "Gargantuan Cat" }
    local potions = (type(cat.potions) == "table" and #cat.potions > 0) and cat.potions or { "Coins", "Damage", "Diamonds", "Huge", "Lucky", "The Cocktail" }
    local eggs = (type(cat.eggs) == "table" and #cat.eggs > 0) and cat.eggs or { "Cracked Egg" }
    local items = (type(cat.items) == "table" and #cat.items > 0) and cat.items or { "Basic Coin Jar", "Comet", "Pinata", "Lucky Block" }

    ui.section(tab, "Huge / Titanic / Gargantuan Pet Spawner & Morpher")
    local chosenHuge = huges[1]
    local chosenVariant = 0
    local chosenShiny = false

    ui.dropdown(tab, {
        name = "Select Huge / Titanic / Gargantuan (" .. tostring(#huges) .. ")",
        options = huges,
        current = chosenHuge,
        callback = function(option)
            chosenHuge = tostring(option)
        end,
    })
    ui.dropdown(tab, {
        name = "Pet Variant",
        options = { "Normal", "Golden", "Rainbow" },
        current = "Normal",
        callback = function(option)
            if option == "Golden" then chosenVariant = 1
            elseif option == "Rainbow" then chosenVariant = 2
            else chosenVariant = 0 end
        end,
    })
    ui.toggle(tab, {
        name = "Shiny Variant",
        default = false,
        onChange = function(value)
            chosenShiny = value == true
        end,
    })
    ui.button(tab, "Spawn Selected Huge In Inventory", function()
        local ok, res, msg = pcall(engine.Cheat, "spawnItem", {
            bucket = "Pet",
            id = chosenHuge,
            amount = 1,
            pt = chosenVariant,
            sh = chosenShiny,
        })
        ui.notify("Pet Spawner", tostring(msg or res))
    end)
    ui.button(tab, "Morph All Equipped Pets To Selected Huge", function()
        local ok, res, msg = pcall(engine.Cheat, "morphPets", {
            id = chosenHuge,
            pt = chosenVariant,
            sh = chosenShiny,
        })
        ui.notify("Pet Morpher", tostring(msg or res))
    end)

    ui.section(tab, "Spawn Any Potion, Egg, Or Game Item")
    local chosenPotion = potions[1]
    local chosenTier = 11
    ui.dropdown(tab, {
        name = "Select Potion (" .. tostring(#potions) .. ")",
        options = potions,
        current = chosenPotion,
        callback = function(option)
            chosenPotion = tostring(option)
        end,
    })
    ui.slider(tab, {
        name = "Potion Tier",
        range = { 1, 11 }, increment = 1, value = 11,
        onChange = function(val)
            chosenTier = val
        end,
    })
    ui.button(tab, "Spawn Selected Potion x100", function()
        local ok, res, msg = pcall(engine.Cheat, "spawnItem", {
            bucket = "Potion",
            id = chosenPotion,
            tier = chosenTier,
            amount = 100,
        })
        ui.notify("Potion Spawner", tostring(msg or res))
    end)

    local chosenEgg = eggs[1]
    ui.dropdown(tab, {
        name = "Select Egg (" .. tostring(#eggs) .. ")",
        options = eggs,
        current = chosenEgg,
        callback = function(option)
            chosenEgg = tostring(option)
        end,
    })
    ui.button(tab, "Spawn Selected Egg / Pack x50 In Inventory", function()
        local ok, res, msg = pcall(engine.Cheat, "spawnItem", {
            bucket = "Lootbox",
            id = chosenEgg,
            amount = 50,
        })
        ui.notify("Egg Spawner", tostring(msg or res))
    end)

    local chosenItem = items[1]
    ui.dropdown(tab, {
        name = "Select Game Item (" .. tostring(#items) .. ")",
        options = items,
        current = chosenItem,
        callback = function(option)
            chosenItem = tostring(option)
        end,
    })
    ui.button(tab, "Spawn Selected Item x100 In Inventory", function()
        local ok, res, msg = pcall(engine.Cheat, "spawnItem", {
            bucket = "Misc",
            id = chosenItem,
            amount = 100,
        })
        ui.notify("Item Spawner", tostring(msg or res))
    end)
end
