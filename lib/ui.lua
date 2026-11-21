-- lib/ui.lua
-- Element factories bound to one library + engine pair. Every module talks to
-- ZapLib through this table, so a module never repeats the SetEnabled plumbing
-- and every toggle behaves the same way when the engine refuses a call.
return function(lib, engine)
    local ui = {}

    function ui.notify(title, content, duration)
        pcall(lib.CreateNotification, lib, {
            Title = tostring(title),
            Content = tostring(content),
            Duration = duration or 4,
        })
    end

    function ui.section(tab, name)
        tab:CreateSection(name)
    end

    function ui.paragraph(tab, title, content)
        return tab:CreateParagraph({ Title = title, Content = content })
    end

    -- spec = { name, key, default, note }
    function ui.toggle(tab, spec)
        local element = tab:CreateToggle({
            Name = spec.name,
            CurrentValue = spec.default == true,
            Callback = function(value)
                local ok, err = engine.SetEnabled(spec.key, value)
                if not ok then
                    ui.notify("Engine", err or "toggle refused")
                end
            end,
        })
        if spec.note then
            tab:CreateParagraph({ Title = spec.name, Content = spec.note })
        end
        return element
    end

    -- spec = { name, key, range = {lo, hi}, increment, suffix, value, onChange }
    function ui.slider(tab, spec)
        return tab:CreateSlider({
            Name = spec.name,
            Range = spec.range,
            Increment = spec.increment or 1,
            Suffix = spec.suffix,
            CurrentValue = spec.value,
            CallbackOnRelease = true,
            Callback = function(value)
                local ok, err = engine.SetConfig(spec.key, value)
                if not ok then
                    ui.notify("Engine", err or "knob refused")
                end
                if spec.onChange then
                    spec.onChange(value)
                end
            end,
        })
    end

    function ui.button(tab, name, callback)
        return tab:CreateButton({ Name = name, Callback = callback })
    end

    return ui
end
