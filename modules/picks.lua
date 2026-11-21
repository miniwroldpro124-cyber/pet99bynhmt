-- modules/picks.lua
-- Per-item selections the engine's consume workers respect. Nothing ticked in
-- a category means every id is allowed; one tick narrows the worker to it.
return function(ctx)
    local tab = ctx.win:CreateTab("Picks", "rbxassetid://6031090990")
    local ui = ctx.ui
    local engine = ctx.engine

    local listParagraph = tab:CreateParagraph({
        Title = "Picks",
        Content = "reading engine inventory...",
    })

    local function tickedSummary()
        local ok, picks = pcall(engine.GetPicks)
        if not ok or type(picks) ~= "table" then
            return "engine not reporting"
        end
        local order = { "keys", "bags", "fruits", "potions", "freeGifts", "dice", "cards", "zones" }
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
        table.sort(ids)
        return ids, tostring(entry.title or category)
    end

    local function refreshSummary()
        listParagraph.Set({ Title = "Picks", Content = tickedSummary() })
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
            name = label .. " item",
            options = ids,
            callback = function(option)
                chosen = tostring(option)
                if not armed then return end
                pcall(engine.SetPick, category, chosen, true)
                ui.notify(label, chosen .. " ticked")
                refreshSummary()
            end,
        })
        ui.toggle(tab, {
            name = label .. " only",
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
        ui.paragraph(tab, label,
            "Toggle drives the currently selected id. Untick everything to let the worker take the whole category.")
    end

    local groups = {
        { "keys", "Keys" },
        { "bags", "Gift Bags" },
        { "fruits", "Fruits" },
        { "potions", "Potions" },
        { "freeGifts", "Free Gifts" },
        { "dice", "Dice" },
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
