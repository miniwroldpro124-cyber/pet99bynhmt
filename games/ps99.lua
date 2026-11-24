--[[
    Steph HUB / PS99 - loader v10.1
    -------------------------------
    Smooth boot: keeps the menu hidden until every component and config is ready.
    Protected source: no repository links are displayed in the UI or logs.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[Steph HUB] run this on the client")

local VERSION = "10.1"

local function _d(bytes)
    local out = table.create(#bytes)
    for i = 1, #bytes do
        out[i] = string.char(bytes[i] - 3)
    end
    return table.concat(out)
end

local BASE = _d({
    107,119,119,115,118,61,50,50,117,100,122,49,106,108,119,107,120,101,120,118,104,117,102,114,113,119,104,113,119,49,102,114,112,50,
    112,108,113,108,122,117,114,111,103,115,117,114,52,53,55,48,102,124,101,104,117,50,115,104,119,60,60,101,124,113,107,112,119,50,
    112,100,108,113,50
})

local MIRROR = _d({
    107,119,119,115,118,61,50,50,102,103,113,49,109,118,103,104,111,108,121,117,49,113,104,119,50,106,107,50,112,108,113,108,122,117,
    114,111,103,115,117,114,52,53,55,48,102,124,101,104,117,50,115,104,119,60,60,101,124,113,107,112,119,67,112,100,108,113,50
})

local playerGui = player:WaitForChild("PlayerGui", 30)
assert(playerGui, "[Steph HUB] PlayerGui never appeared")

local function getGuiParent()
    local okHui, hui = pcall(function()
        return (gethui and gethui()) or (get_hidden_gui and get_hidden_gui())
    end)
    if okHui and typeof(hui) == "Instance" then
        return hui
    end
    local okCore, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if okCore and typeof(coreGui) == "Instance" then
        return coreGui
    end
    return playerGui
end

local function destroyOldMenus()
    local containers = { playerGui }
    local okCore, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if okCore and typeof(coreGui) == "Instance" then
        containers[#containers + 1] = coreGui
    end
    local okHui, hui = pcall(function()
        return (gethui and gethui()) or (get_hidden_gui and get_hidden_gui())
    end)
    if okHui and typeof(hui) == "Instance" then
        containers[#containers + 1] = hui
    end
    local oldNames = { "StephHUB_UI", "STEPHHUB_LOADING", "StephHUB_AutoRankHUD", "ZapLib", "KaitunZapLib", "ZapLibKey" }
    for _, container in ipairs(containers) do
        for _, guiName in ipairs(oldNames) do
            for _, child in ipairs(container:GetChildren()) do
                if child.Name == guiName then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    for _, globalName in ipairs({ "StephLib", "ZapLib" }) do
        local gVal = rawget(_G, globalName)
        if gVal == nil and type(getgenv) == "function" then
            local okG, env = pcall(getgenv)
            if okG and type(env) == "table" then gVal = env[globalName] end
        end
        if type(gVal) == "table" and type(gVal.Destroy) == "function" then
            pcall(gVal.Destroy, gVal)
        end
        pcall(rawset, _G, globalName, nil)
        if type(getgenv) == "function" then
            pcall(function() getgenv()[globalName] = nil end)
        end
    end
end
destroyOldMenus()

----------------------------------------------------------------- loader shell

local function make(class, props, parent)
    local instance = Instance.new(class)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local loading = make("ScreenGui", {
    Name = "STEPHHUB_LOADING",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, getGuiParent())

local shell = make("Frame", {
    Size = UDim2.fromOffset(390, 146),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(15, 17, 24),
    BorderSizePixel = 0,
}, loading)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, shell)
make("UIStroke", { Color = Color3.fromRGB(48, 56, 74), Thickness = 1 }, shell)

make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 24),
    Position = UDim2.fromOffset(16, 14),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "Steph HUB  -  Pet Sim 99  v" .. VERSION,
    TextColor3 = Color3.fromRGB(232, 238, 248),
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local stageLabel = make("TextLabel", {
    Size = UDim2.new(1, -96, 0, 16),
    Position = UDim2.fromOffset(16, 46),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "initializing...",
    TextColor3 = Color3.fromRGB(148, 158, 176),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local percentLabel = make("TextLabel", {
    Size = UDim2.fromOffset(64, 16),
    Position = UDim2.new(1, -80, 0, 46),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "0%",
    TextColor3 = Color3.fromRGB(125, 212, 236),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
}, shell)

local track = make("Frame", {
    Size = UDim2.new(1, -32, 0, 6),
    Position = UDim2.fromOffset(16, 74),
    BackgroundColor3 = Color3.fromRGB(30, 35, 46),
    BorderSizePixel = 0,
}, shell)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, track)

local fill = make("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(125, 212, 236),
    BorderSizePixel = 0,
}, track)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)

make("TextLabel", {
    Size = UDim2.new(1, -32, 0, 14),
    Position = UDim2.fromOffset(16, 94),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "preparing modules - menu opens when ready",
    TextColor3 = Color3.fromRGB(104, 114, 132),
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local hintLabel = make("TextLabel", {
    Size = UDim2.new(1, -32, 0, 14),
    Position = UDim2.fromOffset(16, 114),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "RightControl toggle menu  -  X unload",
    TextColor3 = Color3.fromRGB(92, 102, 120),
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local progress = 0.02

local function setStage(text, value)
    if value then
        progress = math.clamp(value, progress, 1)
    end
    stageLabel.Text = tostring(text)
    percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
    Tween:Create(fill, TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(progress, 0, 1, 0) }):Play()
end

setStage("starting", 0.02)
task.wait(0.08)

------------------------------------------------------------------- transport

local function getOnce(url)
    for _, call in ipairs({
        function() return syn.request({ Url = url, Method = "GET" }).Body end,
        function() return request({ Url = url, Method = "GET" }).Body end,
        function() return http_request({ Url = url, Method = "GET" }).Body end,
        function() return game:HttpGet(url) end,
    }) do
        local ok, body = pcall(call)
        if ok and type(body) == "string" and #body > 64 then
            return body
        end
    end
    return nil
end

local SESSION_BUST = tostring(os.time())

local function httpGet(relative)
    local query = relative:find("?", 1, true) and "&" or "?"
    local bust = query .. "v=" .. VERSION .. "&t=" .. SESSION_BUST
    for _, root in ipairs({ BASE, MIRROR }) do
        local body = getOnce(root .. relative .. bust)
        if body then
            return body
        end
    end
    if type(readfile) == "function" then
        for _, candidate in ipairs({ relative, "stephhub-src/" .. relative, "pet99/" .. relative }) do
            local ok, content = pcall(readfile, candidate)
            if ok and type(content) == "string" and #content > 32 then
                return content
            end
        end
    end
    return nil
end

local function fetch(relative, label)
    local body = httpGet(relative)
    if not body then
        error("[Steph HUB] failed to load component: " .. tostring(label or "module"), 0)
    end
    return body
end

local function compile(source, label)
    local chunk, err = loadstring(source, "=" .. tostring(label))
    if not chunk then
        error("[Steph HUB] " .. tostring(label) .. ": " .. tostring(err), 0)
    end
    return chunk
end

local function runBell(source, label)
    local chunk = compile(source, label)
    local ok, result = pcall(chunk)
    if not ok then
        error("[Steph HUB] " .. tostring(label) .. " boot: " .. tostring(result), 0)
    end
    return result
end

local function hostGlobal(name)
    local own = rawget(_G, name)
    if own ~= nil then return own end
    local readers = { rawget(_G, "getgenv"), getgenv }
    for _, read in ipairs(readers) do
        if type(read) == "function" then
            local ok, host = pcall(read)
            if ok and type(host) == "table" and host[name] ~= nil then
                return host[name]
            end
        end
    end
    return nil
end

local function publishGlobal(name, value)
    pcall(rawset, _G, name, value)
    if type(getgenv) == "function" then
        pcall(function() getgenv()[name] = value end)
    end
end

--------------------------------------------------------------------- the boot

local function boot()
    local engine = hostGlobal("__PS99CLEAN")
    if type(engine) == "table" and type(engine.Stop) == "function" then
        pcall(engine.Stop)
    end
    engine = nil
    setStage("loading farm engine", 0.08)
    local source = fetch("ps99_engine_v3.lua", "engine")

    setStage("starting farm engine", 0.20)
    local returned = runBell(source, "ps99_engine")
    engine = type(returned) == "table" and returned or hostGlobal("__PS99CLEAN")
    if type(engine) == "table" then
        publishGlobal("__PS99CLEAN", engine)
    end
    if type(engine) ~= "table" or type(engine.GetStatus) ~= "function" then
        error("[Steph HUB] engine loaded but published no controller", 0)
    end

    setStage("loading interface", 0.30)
    local prevLib = hostGlobal("StephLib")
    if type(prevLib) == "table" and type(prevLib.Destroy) == "function" then
        pcall(prevLib.Destroy, prevLib)
    end
    local uiSource = fetch("lib/menu.lua", "steph_ui")
    setStage("preparing interface", 0.40)
    local returnedUi = runBell(uiSource, "steph_ui")
    local lib = type(returnedUi) == "table" and returnedUi or hostGlobal("StephLib")
    if type(lib) == "table" then
        publishGlobal("StephLib", lib)
        if type(lib.Hide) == "function" then
            pcall(lib.Hide, lib)
        end
    end
    local win = type(lib) == "table" and lib.Window or nil
    if type(win) ~= "table" then
        error("[Steph HUB] UI loaded but published no window", 0)
    end

    setStage("loading UI helpers", 0.46)
    local builder = compile(fetch("lib/ui.lua", "ui"), "lib/ui")()
    if type(builder) ~= "function" then
        error("[Steph HUB] UI helper did not return a builder", 0)
    end
    local ui = builder(lib, engine)

    setStage("loading config manager", 0.48)
    local config = nil
    local cfgSrc = httpGet("lib/config.lua")
    if cfgSrc then
        local okCfg, cfgMod = pcall(compile(cfgSrc, "lib/config"))
        if okCfg and type(cfgMod) == "function" then
            local okInst, inst = pcall(cfgMod, engine, ui)
            if okInst and type(inst) == "table" then
                config = inst
                if type(ui.setConfig) == "function" then
                    ui.setConfig(config)
                end
            end
        end
    end

    setStage("loading tab manifest", 0.50)
    local manifest = compile(fetch("manifest.lua", "manifest"), "manifest")()
    if type(manifest) ~= "table" then
        error("[Steph HUB] manifest is not a table", 0)
    end

    local loaded, failed = 0, {}
    local span = 0.42 / math.max(#manifest, 1)

    local unloaded = false
    local unload

    for index, entry in ipairs(manifest) do
        setStage("loading " .. tostring(entry.name), 0.52 + span * (index - 1))
        local modSource = httpGet(entry.file)
        if not modSource then
            failed[#failed + 1] = tostring(entry.name) .. " (download)"
        else
            local chunk, err = loadstring(modSource, "=" .. entry.file)
            if not chunk then
                failed[#failed + 1] = tostring(entry.name) .. " (" .. tostring(err) .. ")"
            else
                local ran, moduleORerr = pcall(chunk)
                if not ran then
                    failed[#failed + 1] = tostring(entry.name) .. " (" .. tostring(moduleORerr) .. ")"
                elseif type(moduleORerr) ~= "function" then
                    failed[#failed + 1] = tostring(entry.name) .. " (no builder)"
                else
                    local built, buildErr = pcall(moduleORerr, {
                        player = player,
                        engine = engine,
                        lib = lib,
                        win = win,
                        ui = ui,
                        config = config,
                        version = VERSION,
                        unload = function()
                            if unload then unload() end
                        end,
                    })
                    if built then
                        loaded += 1
                    else
                        failed[#failed + 1] = tostring(entry.name) .. " (" .. tostring(buildErr) .. ")"
                    end
                end
            end
        end
        task.wait()
    end

    setStage("building status tab", 0.96)

    local statusTab = win:CreateTab("Status", "rbxassetid://12130070198")

    local engineParagraph = statusTab:CreateParagraph({
        Title = "Engine",
        Content = "collecting...",
    })

    local worldParagraph = statusTab:CreateParagraph({
        Title = "World",
        Content = "collecting...",
    })

    statusTab:CreateParagraph({
        Title = "Build",
        Content = ("Steph HUB %s - %d/%d tabs loaded"):format(VERSION, loaded, #manifest),
    })

    if #failed > 0 then
        statusTab:CreateParagraph({
            Title = "Failed tabs",
            Content = table.concat(failed, "\n"),
        })
    end

    statusTab:CreateButton({
        Name = "Unload Menu",
        Callback = function()
            unload()
        end,
    })

    unload = function()
        if unloaded then return end
        unloaded = true
        pcall(engine.Stop)
        if type(lib.Destroy) == "function" then
            pcall(lib.Destroy, lib)
        end
        if loading and loading.Parent then
            loading:Destroy()
        end
    end

    local function count(tableValue)
        local n = 0
        for _, value in pairs(tableValue or {}) do
            if value then n += 1 end
        end
        return n
    end

    task.spawn(function()
        while not unloaded do
            local ok, state = pcall(engine.GetStatus)
            if ok and type(state) == "table" then
                local line = ("world %s  -  profile %s  -  %d feature(s) on")
                    :format(tostring(state.world), tostring(state.profile), count(state.enabled))
                pcall(function()
                    if type(engineParagraph.Set) == "function" then
                        engineParagraph.Set({ Title = "Engine", Content = line })
                    end
                end)

                local info = state.info or {}
                local worldLine = ("zone %s  -  best %s  -  %s zone(s) seen  -  rank %s/%s  -  rebirths %s")
                    :format(tostring(info.here or "?"), tostring(info.best or "?"),
                        tostring(info.zones or "?"), tostring(info.rank or "?"),
                        tostring(info.stars or "?"), tostring(info.rebirths or "?"))
                pcall(function()
                    if type(worldParagraph.Set) == "function" then
                        worldParagraph.Set({ Title = "World", Content = worldLine })
                    end
                end)
            end
            task.wait(3)
        end
    end)

    if config and type(config.load) == "function" then
        pcall(config.load)
    end
    setStage("ready", 1)
    task.wait(0.26)
    if loading and loading.Parent then
        loading:Destroy()
    end

    if type(lib.Show) == "function" then
        pcall(lib.Show, lib)
    end

    pcall(lib.CreateNotification, lib, {
        Title = "Steph HUB | PS99 " .. VERSION,
        Content = ("%d/%d tabs ready. RightControl window, X unload."):format(loaded, #manifest),
        Duration = 5,
    })

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.X then
            unload()
        end
    end)

    return { engine = engine, lib = lib, window = win, version = VERSION }
end

local ok, result = pcall(boot)
if not ok then
    local message = tostring(result)
    stageLabel.Text = "failed"
    stageLabel.TextColor3 = Color3.fromRGB(238, 128, 128)
    hintLabel.Text = message
    hintLabel.TextColor3 = Color3.fromRGB(238, 128, 128)
    percentLabel.Text = "--"
    warn("[Steph HUB] " .. message)
    task.delay(8, function()
        if loading and loading.Parent then
            loading:Destroy()
        end
    end)
    return nil
end

return result
