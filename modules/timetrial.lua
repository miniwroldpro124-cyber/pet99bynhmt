-- modules/timetrial.lua
-- Auto Time Trial (World 4 / Zone 279 Hollow Veil Castle minigame).
return function(ctx)
    local tab = ctx.win:CreateTab("Time Trial", "rbxassetid://16259403210")
    local ui = ctx.ui
    local engine = ctx.engine

    ui.section(tab, "Time Trial Status (World 4 / Zone 279)")
    local statusParagraph = tab:CreateParagraph({
        Title = "Time Trial",
        Content = "collecting...",
    })

    ui.section(tab, "Automation")
    ui.toggle(tab, {
        name = "Auto Time Trial",
        key = "autoTimeTrial",
        default = false,
        note = "Auto enters TimeTrial in World 4 (Zone 279), clears breakables with fast tap + pet routing, handles summary screen and re-enters.",
    })
    ui.toggle(tab, {
        name = "Stop At Daily Run Limit (10/day)",
        key = "ttStopAtDailyLimit",
        default = false,
        note = "Only applies after completing the 5 initial goals (when daily points runs unlock).",
    })

    ui.section(tab, "Time Trial Chests (Points)")
    ui.dropdown(tab, {
        name = "Chest Tier",
        key = "TimeTrialChestTier",
        options = { "Best Affordable", "Chest 3 (Best)", "Chest 2 (Mid)", "Chest 1 (Basic)" },
        current = "Best Affordable",
        callback = function(option)
            ui.notify("Time Trial Chest", "Tier: " .. tostring(option))
        end,
    })
    ui.toggle(tab, {
        name = "Auto Open Time Trial Chests",
        key = "autoTimeTrialChests",
        default = false,
        note = "Spends Time Trial Points between runs once all 5 goals are completed.",
    })

    ui.section(tab, "Quick Actions")
    ui.button(tab, "Tele To Zone 279 (Hollow Veil Castle)", function()
        local ok, res, msg = pcall(engine.TeleportTimeTrialZone)
        ui.notify("Time Trial", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Enter Time Trial Now", function()
        local ok, res, msg = pcall(engine.EnterTimeTrial)
        ui.notify("Time Trial", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Leave Time Trial", function()
        local ok, res, msg = pcall(engine.LeaveTimeTrial)
        ui.notify("Time Trial", tostring(ok and (msg or res) or res))
    end)
    ui.button(tab, "Open Selected Chest Now", function()
        local ok, res, msg = pcall(engine.OpenTimeTrialChest)
        ui.notify("Time Trial Chest", tostring(ok and (msg or res) or res))
    end)

    task.spawn(function()
        while type(engine.IsRunning) == "function" and engine.IsRunning() do
            local ok, st = pcall(engine.GetTimeTrialStatus)
            if ok and type(st) == "table" then
                local goalStr = st.pvpUnlocked
                    and ("Goals: Done (PVP Unlocked)")
                    or ("Goal: %d/%d"):format(st.goalIndex or 1, st.totalGoals or 5)
                local line = ("World %s | %s | %s\nPoints: %s | Runs Left: %d/%d | Total: %d | Streak: %d\nState: %s")
                    :format(
                        tostring(st.world or "?"),
                        st.inInstance and "Inside TimeTrial" or "Outside",
                        goalStr,
                        tostring(st.points or 0),
                        tonumber(st.runsLeft) or 0,
                        tonumber(st.dailyLimit) or 10,
                        tonumber(st.totalRuns) or 0,
                        tonumber(st.streak) or 0,
                        tostring(st.note or "off")
                    )
                pcall(function()
                    if type(statusParagraph.Set) == "function" then
                        statusParagraph.Set({ Title = "Time Trial", Content = line })
                    end
                end)
            end
            task.wait(2)
        end
    end)
end
