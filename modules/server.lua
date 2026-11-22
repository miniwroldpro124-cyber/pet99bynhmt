-- modules/server.lua
-- Hop, kill switches, source link. No engine panel: the engine is headless.
return function(ctx)
    local tab = ctx.win:CreateTab("Server", "rbxassetid://16093555964")
    local ui = ctx.ui
    local engine = ctx.engine

    local function engineParagraph(title, content)
        return tab:CreateParagraph({ Title = title, Content = content })
    end

    local hopParagraph = engineParagraph("Hop", "reading...")
    local worldParagraph = engineParagraph("World", "reading...")

    local function count(tableValue)
        local n = 0
        for _, value in pairs(tableValue or {}) do
            if value then n += 1 end
        end
        return n
    end

    local function refresh()
        local ok, state = pcall(engine.GetStatus)
        if not ok or type(state) ~= "table" then
            hopParagraph.Set({ Title = "Hop", Content = "engine not reporting" })
            worldParagraph.Set({ Title = "World", Content = "engine not reporting" })
            return
        end
        local notes = state.notes or {}
        hopParagraph.Set({
            Title = "Hop",
            Content = ("server hop %s  -  %d feature(s) on  -  profile %s")
                :format(tostring(notes.hop or "off"), count(state.enabled), tostring(state.profile)),
        })
        local info = state.info or {}
        worldParagraph.Set({
            Title = "World",
            Content = ("world %s  -  here %s  -  best %s  -  %s zone(s) seen")
                :format(tostring(state.world), tostring(info.here or "?"),
                    tostring(info.best or "?"), tostring(info.zones or "?")),
        })
    end

    ui.section(tab, "Hop")
    ui.toggle(tab, {
        name = "Auto Server Hop", key = "serverHop", default = false,
        note = "Hops when the server drops below the engine's player threshold.",
    })

    ui.section(tab, "Kill switches")
    ui.button(tab, "All Features Off", function()
        local ok, err = pcall(engine.AllOff)
        ui.notify("Engine", ok and "all features off" or tostring(err))
        refresh()
    end)
    ui.button(tab, "Unload Everything", function()
        ui.notify("ZAPX", "unloading")
        ctx.unload()
    end)

    ui.section(tab, "Source")
    ui.paragraph(tab, "GitHub", tostring(ctx.repo or ctx.base or ""))
    ui.button(tab, "Copy Source URL", function()
        local env = getfenv and getfenv() or {}
        local text = tostring(ctx.repo or ctx.base or "")
        for _, name in ipairs({ "setclipboard", "toclipboard" }) do
            local fn = env[name] or rawget(_G, name)
            if type(fn) == "function" and pcall(fn, text) then
                ui.notify("Source", "URL copied.")
                return
            end
        end
        ui.notify("Source", text)
    end)

    ui.paragraph(tab, "Keys", "X unload. The window key is ZapLib's own bind.")

    refresh()
    task.spawn(function()
        while true do
            task.wait(3)
            refresh()
        end
    end)
end
