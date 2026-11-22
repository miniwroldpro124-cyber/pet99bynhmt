-- modules/picks.lua
-- Per-item selections across all game categories (Islands, Potions, Eggs, Huges, Items, Bags, Fruits, Flags, Keys, Dice, Gifts, Cards).
return function(ctx)
    local tab = ctx.win:CreateTab("Picks", "rbxassetid://6031090990")
    local ui = ctx.ui
    local engine = ctx.engine

    local listParagraph = tab:CreateParagraph({
        Title = "Picks",
        Content = "reading engine catalog...",
    })

    local function tickedSummary()
        local ok, picks = pcall(engine.GetPicks)
        if not ok or type(picks) ~= "table" then
            return "engine not reporting"
        end
        local order = { "zones", "potions", "eggs", "huges", "items", "bags", "fruits", "flags", "keys", "dice", "freeGifts", "cards" }
        local parts = {}
        for _, category in ipairs(order) do
            local store = picks[category] or {}
            local n = 0
            for _, value in pairs(store) do
                if value then n += 1 end
            end
            parts[#parts + 1] = ("%s %d"):format(category, n)
        end
        return "ticked  -  " .. table.concat(parts, "  -  ")
    end

    local function idsOf(category)
        local ok, lists = pcall(engine.PickList)
        if not ok or type(lists) ~= "table" then return {}, "unknown" end
        local entry = lists[category]
        if type(entry) ~= "table" then return {}, category end
        local ids = {}
        for _, id in ipairs(entry.items or {}) do
            ids[#ids + 1] = tostring(id)
        end
        return ids, tostring(entry.title or category)
    end

    local function refreshSummary()
        pcall(function()
            listParagraph.Set({ Title = "Picks", Content = tickedSummary() })
        end)
    end

    local function build(category, label)
        ui.section(tab, label)
        local ids = idsOf(category)
        if #ids == 0 then
            ui.paragraph(tab, label, "no entries in the engine list yet - the game save may still be loading.")
            return
        end
        local chosen = ids[1]
        local armed = false
        ui.dropdown(tab, {
            name = ("%s (%d)"):format(label, #ids),
            options = ids,
            current = chosen,
            callback = function(option)
                chosen = tostring(option)
                if not armed then return end
                pcall(engine.SetPick, category, chosen, true)
                ui.notify(label, chosen .. " ticked")
                refreshSummary()
            end,
        })
        ui.toggle(tab, {
            name = label .. " - Tick Selected",
            default = false,
            onChange = function(value)
                armed = value == true
                local ok, err = pcall(engine.SetPick, category, chosen, armed)
                if not ok then
                    ui.notify("Picks", tostring(err))
                    return
                end
                ui.notify(label, ("%s %s"):format(tostring(chosen), armed and "ticked" or "cleared"))
                refreshSummary()
            end,
        })
        ui.button(tab, "Clear All " .. label .. " Picks (Allow All)", function()
            pcall(engine.ClearPicks, category)
            ui.notify(label, "cleared all picks in " .. label)
            refreshSummary()
        end)
    end

    local groups = {
        { "zones", "Islands / Zones" },
        { "potions", "Potions & XP Potions" },
        { "eggs", "Eggs" },
        { "huges", "Huge / Titanic / Gargantuan Pets" },
        { "items", "All Items" },
        { "bags", "Gift Bags & Lootboxes" },
        { "fruits", "Fruits" },
        { "flags", "Zone Flags" },
        { "keys", "Keys" },
        { "dice", "Lucky Dice" },
        { "freeGifts", "Free Gifts" },
        { "cards", "Cards" },
    }

    for _, group in ipairs(groups) do
        build(group[1], group[2])
    end

    refreshSummary()
    task.spawn(function()
        while true do
            task.wait(5)
            refreshSummary()
        end
    end)
end
