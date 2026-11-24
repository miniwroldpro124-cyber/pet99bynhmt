--[[
    Steph HUB v10.3 - Dual-Game Loader (Pet Sim 99 + Steal an Egg)
    Smooth boot: keeps the menu hidden until every component and config is ready.
    Protected source: no repository links are displayed in the UI or logs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[Steph HUB] run this on the client")

local VERSION = "10.3"
local COMPONENT_VERSIONS = {
    ["games/steal_an_egg.lua"] = "1.4.0",
    ["ps99_engine_v3.lua"] = "3.3.0",
    ["lib/menu.lua"] = "2.0.0",
    ["lib/ui.lua"] = "1.1.0",
    ["lib/config.lua"] = "1.1.0",
    ["manifest.lua"] = "1.1.0",
}

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

local STEAL_AN_EGG_PLACE_ID = 107778070777162
local STEAL_AN_EGG_GAME_ID = 10563114921
local PS99_GAME_ID = 3317771874
local PS99_PLACE_IDS = {
    [8737899170] = true,
    [16498369169] = true,
    [17503543197] = true,
    [140403681187145] = true,
    [7709344486] = true,
    [15502339080] = true,
    [15588442388] = true,
}

local function detectGame()
    local placeId = tonumber(game.PlaceId) or game.PlaceId
    local gameId = tonumber(game.GameId) or game.GameId
    local name = string.lower(tostring(game.Name))

    if placeId == STEAL_AN_EGG_PLACE_ID or gameId == STEAL_AN_EGG_GAME_ID or name:find("steal an egg", 1, true) then
        return "sae", "Steal an Egg"
    end
    local clientFolder = ReplicatedStorage:FindFirstChild("Client")
    if clientFolder and clientFolder:FindFirstChild("EggState") then
        return "sae", "Steal an Egg"
    end

    if PS99_PLACE_IDS[placeId] or gameId == PS99_GAME_ID or name:find("pet sim 99", 1, true) or name:find("pet simulator 99", 1, true) then
        return "ps99", "Pet Sim 99"
    end
    local libraryFolder = ReplicatedStorage:FindFirstChild("Library")
    if libraryFolder and libraryFolder:FindFirstChild("Client") then
        return "ps99", "Pet Sim 99"
    end

    return nil, "Select Game"
end

local gameKey, gameTitle = detectGame()

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

local function destroyOldMenus()
    local prevCleanup = hostGlobal("StehpHubCleanup")
    if type(prevCleanup) == "function" then
        pcall(prevCleanup)
    end

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

    local oldNames = {
        "StephHUB_UI", "STEPHHUB_LOADING", "StephHUB_AutoRankHUD",
        "StephHUB_Router", "Steph HUB", "Stehp-Hub", "ZapLib", "KaitunZapLib", "ZapLibKey",
    }
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
        local gVal = hostGlobal(globalName)
        if type(gVal) == "table" and type(gVal.Destroy) == "function" then
            pcall(gVal.Destroy, gVal)
        end
        publishGlobal(globalName, nil)
    end
end

destroyOldMenus()

----------------------------------------------------------------- smooth loader UI

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
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, loading)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, shell)
local shellStroke = make("UIStroke", {
    Color = Color3.fromRGB(48, 56, 74),
    Thickness = 1,
    Transparency = 1,
}, shell)
local shellScale = make("UIScale", { Scale = 0.94 }, shell)

local titleLabel = make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 24),
    Position = UDim2.fromOffset(16, 14),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = ("Steph HUB  -  %s  v%s"):format(gameTitle, VERSION),
    TextColor3 = Color3.fromRGB(232, 238, 248),
    TextTransparency = 1,
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
    TextTransparency = 1,
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
    TextTransparency = 1,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
}, shell)

local track = make("Frame", {
    Size = UDim2.new(1, -32, 0, 6),
    Position = UDim2.fromOffset(16, 74),
    BackgroundColor3 = Color3.fromRGB(30, 35, 46),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, shell)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, track)

local fill = make("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(125, 212, 236),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, track)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)

local subtitleLabel = make("TextLabel", {
    Size = UDim2.new(1, -32, 0, 14),
    Position = UDim2.fromOffset(16, 94),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "preparing modules - menu opens when ready",
    TextColor3 = Color3.fromRGB(104, 114, 132),
    TextTransparency = 1,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local hintLabel = make("TextLabel", {
    Size = UDim2.new(1, -32, 0, 14),
    Position = UDim2.fromOffset(16, 114),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = gameKey == "sae" and "RightShift / RightControl toggle menu" or "RightControl toggle menu  -  X unload",
    TextColor3 = Color3.fromRGB(92, 102, 120),
    TextTransparency = 1,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local function fadeLoader(show)
    local dur = show and 0.22 or 0.20
    local style = show and Enum.EasingStyle.Quint or Enum.EasingStyle.Quad
    local info = TweenInfo.new(dur, style, Enum.EasingDirection.Out)
    local alpha = show and 0 or 1
    Tween:Create(shell, info, { BackgroundTransparency = alpha }):Play()
    Tween:Create(shellStroke, info, { Transparency = alpha }):Play()
    Tween:Create(shellScale, info, { Scale = show and 1 or 0.95 }):Play()
    Tween:Create(titleLabel, info, { TextTransparency = alpha }):Play()
    Tween:Create(stageLabel, info, { TextTransparency = alpha }):Play()
    Tween:Create(percentLabel, info, { TextTransparency = alpha }):Play()
    Tween:Create(track, info, { BackgroundTransparency = alpha }):Play()
    Tween:Create(fill, info, { BackgroundTransparency = alpha }):Play()
    Tween:Create(subtitleLabel, info, { TextTransparency = alpha }):Play()
    Tween:Create(hintLabel, info, { TextTransparency = alpha }):Play()
    task.wait(dur + 0.02)
end

local progress = 0
local fillTween = nil

local function setStage(text, value)
    if value then
        progress = math.clamp(value, progress, 1)
    end
    stageLabel.Text = tostring(text)
    percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
    if fillTween then
        pcall(function() fillTween:Cancel() end)
    end
    fillTween = Tween:Create(
        fill,
        TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Size = UDim2.new(progress, 0, 1, 0) }
    )
    fillTween:Play()
end

fadeLoader(true)
setStage("detecting game", 0.05)

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

local function componentVersion(source)
    return source:match("%-%- STEPH_COMPONENT: [^%s]+ ([%d%.]+)")
        or source:match('local%s+VERSION%s*=%s*"([%d%.]+)"')
end

local function validComponent(source, relative)
    local expected = COMPONENT_VERSIONS[relative]
    if not expected then
        return true
    end
    if source:find("AnchorPoint%s*=%s*UDim2") then
        return false
    end
    return componentVersion(source) == expected
end

local function httpGet(relative)
    local query = relative:find("?", 1, true) and "&" or "?"
    local bust = query .. "v=" .. VERSION .. "&t=" .. SESSION_BUST
    for _, root in ipairs({ BASE, MIRROR }) do
        local body = getOnce(root .. relative .. bust)
        if body and validComponent(body, relative) then
            return body
        end
    end
    if type(readfile) == "function" then
        for _, candidate in ipairs({ relative, "stephhub-src/" .. relative, "pet99/" .. relative }) do
            local ok, content = pcall(readfile, candidate)
            if ok and type(content) == "string" and #content > 32 and validComponent(content, relative) then
                return content
            end
        end
    end
    return nil
end

local function fetch(relative, label)
    local body = httpGet(relative)
    if not body then
        local expected = COMPONENT_VERSIONS[relative]
        local suffix = expected and (" (required v" .. expected .. ")") or ""
        error("[Steph HUB] failed to load component: " .. tostring(label or relative) .. suffix, 0)
    end
    return body
end

local function compile(source, label)
    local chunk, err = loadstring(source, "=" .. tostring(label))
    if not chunk then
        error("[Steph HUB] compile error in " .. tostring(label) .. ": " .. tostring(err), 0)
    end
    return chunk
end

local function runChunk(source, label)
    local chunk = compile(source, label)
    local ok, result = pcall(chunk)
    if not ok then
        error("[Steph HUB] boot error in " .. tostring(label) .. ": " .. tostring(result), 0)
    end
    return result
end

------------------------------------------------------------------ Steal an Egg boot

local function cleanupStealAnEgg()
    local cleanup = hostGlobal("StehpHubCleanup")
    if type(cleanup) == "function" then
        pcall(cleanup)
    end
    publishGlobal("StehpHubCleanup", nil)
end

local function bootStealAnEgg()
    titleLabel.Text = ("Steph HUB  -  Steal an Egg  v%s"):format(VERSION)
    hintLabel.Text = "RightShift / RightControl toggle menu"
    setStage("loading Steal an Egg hub", 0.24)
    local source = fetch("games/steal_an_egg.lua", "Steal an Egg hub")

    setStage("compiling Steal an Egg hub", 0.55)
    local chunk = compile(source, "sae_hub")

    setStage("initializing modules & config", 0.78)
    publishGlobal("__STEPH_DEFER_SHOW", true)
    local ok, hub = pcall(chunk)
    publishGlobal("__STEPH_DEFER_SHOW", nil)
    if not ok then
        cleanupStealAnEgg()
        error("[Steph HUB] Steal an Egg init failed: " .. tostring(hub), 0)
    end
    if type(hub) ~= "table" or type(hub.Show) ~= "function" then
        cleanupStealAnEgg()
        error("[Steph HUB] Steal an Egg hub published no menu controller", 0)
    end

    setStage("ready", 1.0)
    task.wait(0.26)
    fadeLoader(false)
    if loading and loading.Parent then
        loading:Destroy()
    end

    local shown, showErr = pcall(hub.Show)
    if not shown then
        cleanupStealAnEgg()
        error("[Steph HUB] Steal an Egg menu show failed: " .. tostring(showErr), 0)
    end

    return hub
end

------------------------------------------------------------------ Pet Sim 99 boot

local function bootPS99()
    titleLabel.Text = ("Steph HUB  -  Pet Sim 99  v%s"):format(VERSION)
    hintLabel.Text = "RightControl toggle menu  -  X unload"
    local engine = hostGlobal("__PS99CLEAN")
    if type(engine) == "table" and type(engine.Stop) == "function" then
        pcall(engine.Stop)
    end
    engine = nil

    setStage("loading farm engine", 0.12)
    local source = fetch("ps99_engine_v3.lua", "engine")

    setStage("starting farm engine", 0.24)
    local returned = runChunk(source, "ps99_engine")
    engine = type(returned) == "table" and returned or hostGlobal("__PS99CLEAN")
    if type(engine) == "table" then
        publishGlobal("__PS99CLEAN", engine)
    end
    if type(engine) ~= "table" or type(engine.GetStatus) ~= "function" then
        error("[Steph HUB] engine loaded but published no controller", 0)
    end

    setStage("loading interface", 0.34)
    local prevLib = hostGlobal("StephLib")
    if type(prevLib) == "table" and type(prevLib.Destroy) == "function" then
        pcall(prevLib.Destroy, prevLib)
    end
    local uiSource = fetch("lib/menu.lua", "steph_ui")

    setStage("preparing interface", 0.42)
    local returnedUi = runChunk(uiSource, "steph_ui")
    local lib = type(returnedUi) == "table" and returnedUi or hostGlobal("StephLib")
    if type(lib) == "table" then
        publishGlobal("StephLib", lib)
        if type(lib.Hide) == "function" then
            pcall(lib.Hide, lib)
        end
    end
    local win = type(lib) == "table" and lib.Window or nil
    if type(win) ~= "table" or type(lib.Show) ~= "function" or type(lib.Destroy) ~= "function" then
        error("[Steph HUB] UI loaded but published an incomplete controller", 0)
    end

    setStage("loading UI helpers", 0.48)
    local builder = compile(fetch("lib/ui.lua", "ui"), "lib/ui")()
    if type(builder) ~= "function" then
        error("[Steph HUB] UI helper did not return a builder", 0)
    end
    local ui = builder(lib, engine)

    setStage("loading config manager", 0.52)
    local configModule = compile(fetch("lib/config.lua", "config"), "lib/config")()
    if type(configModule) ~= "function" then
        error("[Steph HUB] config manager did not return a builder", 0)
    end
    local config = configModule(engine, ui)
    if type(config) ~= "table" or type(config.load) ~= "function" then
        error("[Steph HUB] config manager published an incomplete controller", 0)
    end
    if type(ui.setConfig) == "function" then
        ui.setConfig(config)
    end

    setStage("loading tab manifest", 0.56)
    local manifest = compile(fetch("manifest.lua", "manifest"), "manifest")()
    if type(manifest) ~= "table" then
        error("[Steph HUB] manifest is not a table", 0)
    end

    local loaded, failed = 0, {}
    local span = 0.36 / math.max(#manifest, 1)

    local unloaded = false
    local unloadConnection
    local unload

    for index, entry in ipairs(manifest) do
        setStage("loading " .. tostring(entry.name), 0.56 + span * index)
        local modSource = httpGet(entry.file)
        if not modSource then
            failed[#failed + 1] = tostring(entry.name) .. " (download)"
        else
            local chunk = loadstring(modSource, "=" .. entry.file)
            if not chunk then
                failed[#failed + 1] = tostring(entry.name) .. " (compile)"
            else
                local ran, moduleORerr = pcall(chunk)
                if not ran then
                    failed[#failed + 1] = tostring(entry.name) .. " (runtime)"
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

    if #failed > 0 then
        pcall(engine.Stop)
        pcall(lib.Destroy, lib)
        error("[Steph HUB] PS99 tabs failed: " .. table.concat(failed, ", "), 0)
    end

    setStage("building status tab", 0.94)
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

    statusTab:CreateButton({
        Name = "Unload Menu",
        Callback = function()
            unload()
        end,
    })

    unload = function()
        if unloaded then return end
        unloaded = true
        if unloadConnection then
            pcall(function() unloadConnection:Disconnect() end)
            unloadConnection = nil
        end
        pcall(engine.Stop)
        pcall(lib.Destroy, lib)
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

    local function refreshStatus()
        local ok, state = pcall(engine.GetStatus)
        if not ok or type(state) ~= "table" then
            pcall(function()
                if type(engineParagraph.Set) == "function" then
                    engineParagraph.Set({ Title = "Engine", Content = "status error: " .. tostring(state) })
                end
            end)
            return
        end
        local notes = state.notes or {}
        local detail = tostring(notes.profile or notes.heap or "no profile yet")
        local line = ("world %s  -  profile %s  -  %d feature(s) on  -  %s")
            :format(tostring(state.world), tostring(state.profile), count(state.enabled), detail)
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

    refreshStatus()
    task.spawn(function()
        while not unloaded do
            task.wait(3)
            if not unloaded then refreshStatus() end
        end
    end)

    setStage("applying saved config", 0.98)
    local configNote = ""
    local okLoad, loadedConfig, loadReason = pcall(config.load)
    if not okLoad then
        pcall(engine.Stop)
        pcall(lib.Destroy, lib)
        error("[Steph HUB] config load failed: " .. tostring(loadedConfig), 0)
    end
    if loadedConfig ~= true then
        local reason = tostring(loadReason or "unknown")
        if reason ~= "no saved config found" and reason ~= "executor has no readfile" then
            local okReset, resetResult = pcall(config.reset)
            if not okReset or resetResult ~= true then
                pcall(engine.Stop)
                pcall(lib.Destroy, lib)
                error("[Steph HUB] config reset failed: " .. tostring(resetResult), 0)
            end
            configNote = " Saved config reset: " .. reason .. "."
        end
    end

    setStage("ready", 1.0)
    task.wait(0.26)
    fadeLoader(false)
    if loading and loading.Parent then
        loading:Destroy()
    end

    local shown, showErr = pcall(lib.Show, lib)
    if not shown then
        unload()
        error("[Steph HUB] menu show failed: " .. tostring(showErr), 0)
    end

    if type(lib.CreateNotification) == "function" then
        pcall(lib.CreateNotification, lib, {
            Title = "Steph HUB | PS99 " .. VERSION,
            Content = ("%d/%d tabs ready. RightControl toggle, X unload.%s"):format(loaded, #manifest, configNote),
            Duration = 5,
        })
    end

    unloadConnection = UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.X then
            unload()
        end
    end)

    return { engine = engine, lib = lib, window = win, version = VERSION }
end

---------------------------------------------------------------------- dispatch

local function cleanupPS99()
    local engine = hostGlobal("__PS99CLEAN")
    if type(engine) == "table" and type(engine.Stop) == "function" then
        pcall(engine.Stop, engine)
    end
    local lib = hostGlobal("StephLib")
    if type(lib) == "table" and type(lib.Destroy) == "function" then
        pcall(lib.Destroy, lib)
    end
    publishGlobal("__PS99CLEAN", nil)
    publishGlobal("StephLib", nil)
end

local function handleBootError(err)
    if gameKey == "sae" then
        cleanupStealAnEgg()
    elseif gameKey == "ps99" then
        cleanupPS99()
    end
    local message = tostring(err)
    stageLabel.Text = "failed"
    stageLabel.TextColor3 = Color3.fromRGB(238, 128, 128)
    subtitleLabel.Text = message
    subtitleLabel.TextColor3 = Color3.fromRGB(238, 128, 128)
    percentLabel.Text = "--"
    warn("[Steph HUB] " .. message)
    task.delay(8, function()
        if loading and loading.Parent then
            fadeLoader(false)
            loading:Destroy()
        end
    end)
end

local function promptGameChoice()
    setStage("choose script to run", 0.10)
    subtitleLabel.Visible = false
    hintLabel.Visible = false
    shell.Size = UDim2.fromOffset(390, 174)

    local btnHost = make("Frame", {
        Size = UDim2.new(1, -32, 0, 74),
        Position = UDim2.fromOffset(16, 88),
        BackgroundTransparency = 1,
    }, shell)

    local saeBtn = make("TextButton", {
        Size = UDim2.new(0.48, 0, 0, 34),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(139, 92, 246),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "Steal an Egg",
        TextColor3 = Color3.fromRGB(241, 237, 250),
        TextSize = 13,
        AutoButtonColor = true,
    }, btnHost)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, saeBtn)

    local ps99Btn = make("TextButton", {
        Size = UDim2.new(0.48, 0, 0, 34),
        Position = UDim2.new(0.52, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(42, 84, 102),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "Pet Sim 99",
        TextColor3 = Color3.fromRGB(232, 238, 248),
        TextSize = 13,
        AutoButtonColor = true,
    }, btnHost)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, ps99Btn)

    local closeBtn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 28),
        Position = UDim2.new(0, 0, 0, 42),
        BackgroundColor3 = Color3.fromRGB(30, 35, 46),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        Text = "Cancel",
        TextColor3 = Color3.fromRGB(148, 158, 176),
        TextSize = 12,
        AutoButtonColor = true,
    }, btnHost)
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, closeBtn)

    local chosen = false
    local function launchChoice(fn)
        if chosen then return end
        chosen = true
        btnHost:Destroy()
        shell.Size = UDim2.fromOffset(390, 146)
        subtitleLabel.Visible = true
        hintLabel.Visible = true
        task.spawn(function()
            local ok, res = pcall(fn)
            if not ok then
                handleBootError(res)
            end
        end)
    end

    saeBtn.MouseButton1Click:Connect(function()
        gameKey = "sae"
        launchChoice(bootStealAnEgg)
    end)
    ps99Btn.MouseButton1Click:Connect(function()
        gameKey = "ps99"
        launchChoice(bootPS99)
    end)
    closeBtn.MouseButton1Click:Connect(function()
        if chosen then return end
        chosen = true
        fadeLoader(false)
        if loading and loading.Parent then
            loading:Destroy()
        end
    end)
end

if gameKey == "sae" then
    local ok, result = pcall(bootStealAnEgg)
    if not ok then
        handleBootError(result)
        return nil
    end
    return result
elseif gameKey == "ps99" then
    local ok, result = pcall(bootPS99)
    if not ok then
        handleBootError(result)
        return nil
    end
    return result
else
    promptGameChoice()
    return nil
end
