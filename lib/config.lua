-- lib/config.lua
-- JSON config persistence for Steph HUB (toggles, numeric/string knobs, event options, picks).
return function(engine, ui)
    local HttpService = game:GetService("HttpService")
    local FOLDER = "StephHUB"
    local DEFAULT_FILE = FOLDER .. "/config.json"

    local config = {
        autoSave = true,
        _loading = false,
        elements = {}, -- key -> { { kind = "toggle"|"slider"|"dropdown", handle = element }, ... }
    }

    local function ensureFolder()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local ok, exists = pcall(isfolder, FOLDER)
            if ok and not exists then
                pcall(makefolder, FOLDER)
            end
        end
    end

    function config.register(kind, key, handle)
        if type(key) ~= "string" or type(handle) ~= "table" then return end
        local bucket = config.elements[key]
        if type(bucket) ~= "table" then
            bucket = {}
            config.elements[key] = bucket
        end
        bucket[#bucket + 1] = { kind = kind, handle = handle }
    end

    local function applyUiElements(key, kind, value)
        local bucket = config.elements[key]
        if type(bucket) ~= "table" then return end
        for _, reg in ipairs(bucket) do
            if reg.kind == kind and type(reg.handle) == "table" and type(reg.handle.Set) == "function" then
                pcall(reg.handle.Set, value)
            end
        end
    end

    function config.collect()
        local data = {
            autoSave = config.autoSave,
            enabled = {},
            knobs = {},
            eventOpts = {},
            picks = {},
        }
        if type(engine.GetEnabled) == "function" then
            local ok, en = pcall(engine.GetEnabled)
            if ok and type(en) == "table" then data.enabled = en end
        end
        if type(engine.GetKnobs) == "function" then
            local ok, kn = pcall(engine.GetKnobs)
            if ok and type(kn) == "table" then
                for k, v in pairs(kn) do
                    if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
                        data.knobs[k] = v
                    end
                end
            end
        end
        if type(engine.GetEventOpts) == "function" then
            local ok, ev = pcall(engine.GetEventOpts)
            if ok and type(ev) == "table" then data.eventOpts = ev end
        end
        if type(engine.GetPicks) == "function" then
            local ok, pk = pcall(engine.GetPicks)
            if ok and type(pk) == "table" then data.picks = pk end
        end
        return data
    end

    function config.save(path)
        if type(writefile) ~= "function" then
            return false, "executor has no writefile"
        end
        ensureFolder()
        local okEnc, json = pcall(HttpService.JSONEncode, HttpService, config.collect())
        if not okEnc or type(json) ~= "string" then
            return false, "JSON encode failed"
        end
        local target = path or DEFAULT_FILE
        local okW, errW = pcall(writefile, target, json)
        if not okW then
            return false, tostring(errW)
        end
        return true, "saved to " .. target
    end

    function config.load(path)
        if type(readfile) ~= "function" or type(isfile) ~= "function" then
            return false, "executor has no readfile"
        end
        local target = path or DEFAULT_FILE
        local okEx, exists = pcall(isfile, target)
        if not okEx or not exists then
            return false, "no saved config found"
        end
        local okR, raw = pcall(readfile, target)
        if not okR or type(raw) ~= "string" or #raw == 0 then
            return false, "failed to read config"
        end
        local okDec, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not okDec or type(data) ~= "table" then
            return false, "invalid config JSON"
        end

        config._loading = true
        local okApply, errApply = pcall(function()
            if type(data.knobs) == "table" then
                for k, v in pairs(data.knobs) do
                    pcall(engine.SetConfig, k, v)
                    if type(v) == "number" then
                        applyUiElements(k, "slider", v)
                    elseif type(v) == "string" then
                        applyUiElements(k, "dropdown", v)
                    end
                end
            end

            if type(data.eventOpts) == "table" and type(engine.SetEventOpt) == "function" then
                for k, v in pairs(data.eventOpts) do
                    if type(v) == "table" then
                        for subK, subV in pairs(v) do
                            pcall(engine.SetEventOpt, k, subV, subK)
                        end
                    else
                        pcall(engine.SetEventOpt, k, v)
                    end
                end
            end

            if type(data.picks) == "table" and type(engine.ClearPicks) == "function" and type(engine.SetPick) == "function" then
                for category, store in pairs(data.picks) do
                    if type(store) == "table" then
                        pcall(engine.ClearPicks, category)
                        for id, flag in pairs(store) do
                            if flag == true then
                                pcall(engine.SetPick, category, id, true)
                            end
                        end
                    end
                end
            end

            if type(data.enabled) == "table" then
                for k, v in pairs(data.enabled) do
                    if type(v) == "boolean" then
                        pcall(engine.SetEnabled, k, v)
                        applyUiElements(k, "toggle", v)
                    end
                end
            end
        end)
        if type(data.autoSave) == "boolean" then
            config.autoSave = data.autoSave
        end
        config._loading = false
        if not okApply then
            return false, "load error: " .. tostring(errApply)
        end

        return true, "loaded " .. target
    end

    function config.reset()
        config._loading = true
        if type(engine.AllOff) == "function" then
            pcall(engine.AllOff)
        end
        for _, bucket in pairs(config.elements) do
            if type(bucket) == "table" then
                for _, reg in ipairs(bucket) do
                    if reg.kind == "toggle" and type(reg.handle.Set) == "function" then
                        pcall(reg.handle.Set, false)
                    end
                end
            end
        end
        config._loading = false
        return true, "reset all toggles"
    end

    local savePending = false
    function config.onChanged()
        if config._loading or not config.autoSave or savePending then return end
        savePending = true
        task.delay(0.4, function()
            savePending = false
            if not config._loading and config.autoSave then
                pcall(config.save)
            end
        end)
    end

    return config
end
