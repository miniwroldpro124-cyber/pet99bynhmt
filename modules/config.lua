-- modules/config.lua
-- Config Save / Load / Auto-Save tab for Steph HUB.
return function(ctx)
    local tab = ctx.win:CreateTab("Config", "rbxassetid://6031090990")
    local ui = ctx.ui
    local config = ctx.config

    ui.section(tab, "Config Persistence")
    ui.paragraph(tab, "Storage", "Saved locally as JSON in StephHUB/config.json (toggles, sliders, event options, picks).")

    if not config then
        ui.paragraph(tab, "Unavailable", "Config module was not loaded by main.lua.")
        return
    end

    ui.button(tab, "Save Config", function()
        local ok, msg = config.save()
        ui.notify("Config", tostring(msg))
    end)

    ui.button(tab, "Load Config", function()
        local ok, msg = config.load()
        ui.notify("Config", tostring(msg))
    end)

    ui.toggle(tab, {
        name = "Auto-Save On Change",
        default = config.autoSave == true,
        onChange = function(value)
            config.autoSave = value == true
            if config.autoSave then
                config.save()
            end
            ui.notify("Config", config.autoSave and "Auto-save enabled" or "Auto-save disabled")
        end,
    })

    ui.button(tab, "Reset All Toggles", function()
        local ok, msg = config.reset()
        ui.notify("Config", tostring(msg))
    end)
end
