-- lib/ui.lua
-- Element factories bound to one library + engine pair. Every module talks to
-- Steph HUB's UI wrapper through this table, so a module never repeats the SetEnabled plumbing
-- and every toggle behaves the same way when the engine refuses a call.
--
-- spec.key is optional. With a key the element drives the engine; without one
-- it is a local control and only spec.onChange runs (player movement, etc).
return function(lib, engine)
    local ui = {}

    function ui.notify(title, content, duration)
        pcall(lib.CreateNotification, lib, {
            Title = tostring(title),
            Content = tostring(content),
            Duration = duration or 4,
        })
        print(("[Steph HUB] %s: %s"):format(tostring(title), tostring(content)))
    end

    function ui.section(tab, name)
        tab:CreateSection(name)
    end

    function ui.paragraph(tab, title, content)
        return tab:CreateParagraph({ Title = title, Content = content })
    end

    function ui.label(tab, text)
        return tab:CreateLabel(text)
    end

    -- spec = { name, key, default, note, onChange }
    function ui.toggle(tab, spec)
        local element = tab:CreateToggle({
            Name = spec.name,
            CurrentValue = spec.default == true,
            Callback = function(value)
                if spec.key then
                    local ok, err = engine.SetEnabled(spec.key, value)
                    if not ok then
                        ui.notify("Engine", err or ("refused " .. tostring(spec.key)))
                    end
                end
                if spec.onChange then
                    local ran, err = pcall(spec.onChange, value)
                    if not ran then
                        ui.notify("UI", tostring(err))
                    end
                end
            end,
        })
        if spec.note then
            tab:CreateParagraph({ Title = spec.name, Content = spec.note })
        end
        return element
    end

    -- spec = { name, key, range = {lo, hi}, increment, suffix, value, onChange }
    -- ZapLib fires the callback once on build with the current value. Push that
    -- first value to the engine silently so the knob is bound without waiting
    -- for a drag, and never run onChange before the user has touched it.
    function ui.slider(tab, spec)
        local priming = true
        local slider = tab:CreateSlider({
            Name = spec.name,
            Range = spec.range,
            Increment = spec.increment or 1,
            Suffix = spec.suffix,
            CurrentValue = spec.value,
            CallbackOnRelease = false,
            Callback = function(value)
                if priming then
                    priming = false
                    if spec.key then
                        pcall(engine.SetConfig, spec.key, value)
                    end
                    return
                end
                if spec.key then
                    local ok, err = engine.SetConfig(spec.key, value)
                    if not ok then
                        ui.notify("Engine", err or ("knob refused: " .. tostring(spec.key)))
                    end
                end
                if spec.onChange then
                    local ran, err = pcall(spec.onChange, value)
                    if not ran then
                        ui.notify("UI", tostring(err))
                    end
                end
            end,
        })
    end

    function ui.button(tab, name, callback)
        return tab:CreateButton({
            Name = name,
            Callback = function()
                local ok, err = pcall(callback)
                if not ok then
                    ui.notify("Error", tostring(err))
                end
            end,
        })
    end

    function ui.dropdown(tab, spec)
        local priming = true
        local dropdown = tab:CreateDropdown({
            Name = spec.name,
            Options = spec.options,
            CurrentOption = spec.current or spec.options[1],
            Callback = function(option)
                if priming then
                    priming = false
                    return
                end
                if spec.callback then
                    local ran, err = pcall(spec.callback, option)
                    if not ran then
                        ui.notify("UI", tostring(err))
                    end
                end
            end,
        })
        priming = false
        return dropdown
    end

    return ui
end
