--[[
    ZAPX / PS99 - loader v7
    -----------------------
    One file boots everything:

        1. loading screen with real per-stage progress
        2. headless farm engine (ps99_engine_v3) - no second window ever exists
        3. ZapHub interface (ZapLib) - the menu you see
        4. one module per tab, fetched from the repo
        5. Status tab driven live from the engine controller

    RightControl  window (ZapLib's own bind)
    X             unload
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[ZAPX] run this on the client")

local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/"
local REPO = "https://github.com/miniwroldpro124-cyber/pet99bynhmt"
local VERSION = "7.1"

local playerGui = player:WaitForChild("PlayerGui", 30)
assert(playerGui, "[ZAPX] PlayerGui never appeared")

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
    Name = "ZAPX_LOADING",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 600,
}, playerGui)

local shell = make("Frame", {
    Size = UDim2.fromOffset(380, 152),
    Position = UDim2.new(0.5, -190, 0.5, -76),
    BackgroundColor3 = Color3.fromRGB(14, 16, 21),
    BorderSizePixel = 0,
}, loading)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, shell)
make("UIStroke", { Color = Color3.fromRGB(44, 50, 64), Thickness = 1 }, shell)

make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 24),
    Position = UDim2.fromOffset(14, 12),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "ZAPX  -  PS99  " .. VERSION,
    TextColor3 = Color3.fromRGB(226, 232, 240),
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local stageLabel = make("TextLabel", {
    Size = UDim2.new(1, -90, 0, 16),
    Position = UDim2.fromOffset(14, 42),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "starting",
    TextColor3 = Color3.fromRGB(138, 148, 163),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local percentLabel = make("TextLabel", {
    Size = UDim2.fromOffset(60, 16),
    Position = UDim2.new(1, -74, 0, 42),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "0%",
    TextColor3 = Color3.fromRGB(125, 212, 236),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
}, shell)

local track = make("Frame", {
    Size = UDim2.new(1, -28, 0, 6),
    Position = UDim2.fromOffset(14, 68),
    BackgroundColor3 = Color3.fromRGB(30, 34, 43),
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
    Size = UDim2.new(1, -28, 0, 14),
    Position = UDim2.fromOffset(14, 88),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "source  " .. REPO:gsub("^https://", ""),
    TextColor3 = Color3.fromRGB(96, 106, 122),
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local hintLabel = make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 14),
    Position = UDim2.fromOffset(14, 112),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "downloading from github - rightcontrol window - x unload",
    TextColor3 = Color3.fromRGB(96, 106, 122),
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, shell)

local progress = 0.02

local function setStage(text, value)
    if value then
        progress = math.clamp(value, 0, 1)
    end
    stageLabel.Text = tostring(text)
    percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
    Tween:Create(fill, TweenInfo.new(0.18), { Size = UDim2.new(progress, 0, 1, 0) }):Play()
end

setStage("starting", 0.02)
task.wait(0.1)

------------------------------------------------------------------- transport

local function httpGet(url)
    -- The version query defeats the executor's own URL cache.
    local stamped = url .. (url:find("?", 1, true) and "&" or "?") .. "v=" .. VERSION
    for _, call in ipairs({
        function() return syn.request({ Url = stamped, Method = "GET" }).Body end,
        function() return request({ Url = stamped, Method = "GET" }).Body end,
        function() return http_request({ Url = stamped, Method = "GET" }).Body end,
        function() return game:HttpGet(stamped) end,
        function() return game:HttpGet(url) end,
    }) do
        local ok, body = pcall(call)
        if ok and type(body) == "string" and #body > 64 then
            return body
        end
    end
    return nil
end

local function fetch(relative, label)
    local body = httpGet(BASE .. relative)
    if not body then
        error("[ZAPX] download failed: " .. tostring(label or relative), 0)
    end
    return body
end

local function compile(source, label)
    local chunk, err = loadstring(source, "=" .. label)
    if not chunk then
        error("[ZAPX] " .. label .. ": " .. tostring(err), 0)
    end
    return chunk
end

-- main.lua runs in the executor sandbox; engine and modules are compiled with
-- loadstring and write to the host globals. Read the host view first.
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

local function copyToClipboard(text)
    local env = getfenv and getfenv() or {}
    for _, name in ipairs({ "setclipboard", "toclipboard" }) do
        local fn = env[name] or rawget(_G, name)
        if type(fn) == "function" and pcall(fn, text) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------- the boot

local function boot()
    ---------------------------------------------------------------- engine

    local engine = hostGlobal("__PS99CLEAN")
    if type(engine) ~= "table" or type(engine.SetEnabled) ~= "function" then
        setStage("downloading farm engine", 0.08)
        local source = fetch("ps99_engine_v3.lua", "engine")

        setStage("booting farm engine", 0.20)
        local booted, bootErr = pcall(compile(source, "ps99_engine"))
        if not booted then
            error("[ZAPX] engine boot: " .. tostring(bootErr), 0)
        end
        engine = hostGlobal("__PS99CLEAN")
    end
    if type(engine) ~= "table" or type(engine.GetStatus) ~= "function" then
        error("[ZAPX] engine loaded but published no controller", 0)
    end

    ------------------------------------------------------------- interface

    setStage("downloading ZapHub interface", 0.30)
    local lib = hostGlobal("ZapLib")
    if type(lib) ~= "table" or type(lib.Window) ~= "table" then
        local source = fetch("zaphub.lua", "zaphub")
        setStage("booting ZapHub interface", 0.40)
        local ran, err = pcall(compile(source, "zaphub"))
        if not ran then
            error("[ZAPX] interface boot: " .. tostring(err), 0)
        end
        lib = hostGlobal("ZapLib")
    end
    local win = type(lib) == "table" and lib.Window or nil
    if type(win) ~= "table" then
        error("[ZAPX] ZapHub loaded but published no window", 0)
    end

    -------------------------------------------------------------- ui helper

    setStage("loading element factories", 0.46)
    local builder = compile(fetch("lib/ui.lua", "ui"), "lib/ui")()
    if type(builder) ~= "function" then
        error("[ZAPX] lib/ui did not return a builder", 0)
    end
    local ui = builder(lib, engine)

    --------------------------------------------------------------- manifest

    setStage("loading tab manifest", 0.50)
    local manifest = compile(fetch("manifest.lua", "manifest"), "manifest")()
    if type(manifest) ~= "table" then
        error("[ZAPX] manifest is not a table", 0)
    end

    local loaded, failed = 0, {}
    local span = 0.42 / math.max(#manifest, 1)

    -- Declared before the modules so a module can hold ctx.unload.
    local unloaded = false
    local unload

    for index, entry in ipairs(manifest) do
        setStage("loading tab  " .. tostring(entry.name), 0.52 + span * (index - 1))
        local source = httpGet(BASE .. entry.file)
        if not source then
            failed[#failed + 1] = tostring(entry.name) .. " (download)"
        else
            local chunk, err = loadstring(source, "=" .. entry.file)
            if not chunk then
                failed[#failed + 1] = tostring(entry.name) .. " (" .. tostring(err) .. ")"
            else
                local ran, moduleORerr = pcall(chunk)
                if not ran then
                    failed[#failed + 1] = tostring(entry.name) .. " (" .. tostring(moduleORerr) .. ")"
                elseif type(moduleORerr) ~= "function" then
                    failed[#failed + 1] = tostring(entry.name) .. " (no builder returned)"
                else
                    local built, buildErr = pcall(moduleORerr, {
                        player = player,
                        engine = engine,
                        lib = lib,
                        win = win,
                        ui = ui,
                        version = VERSION,
                        base = BASE,
                        repo = REPO,
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

    ---------------------------------------------------------------- status

    setStage("building status tab", 0.97)

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
        Content = ("ZAPX %s - %d/%d tabs loaded"):format(VERSION, loaded, #manifest),
    })

    if #failed > 0 then
        statusTab:CreateParagraph({
            Title = "Failed tabs",
            Content = table.concat(failed, "\n"),
        })
    end

    statusTab:CreateParagraph({
        Title = "Source",
        Content = REPO,
    })

    statusTab:CreateButton({
        Name = "Copy Source URL",
        Callback = function()
            if copyToClipboard(REPO) then
                ui.notify("Source", "GitHub URL copied.")
            else
                ui.notify("Source", REPO)
            end
        end,
    })

    statusTab:CreateButton({
        Name = "Unload Menu",
        Callback = function()
            unload()
        end,
    })

    ---------------------------------------------------------------- unload

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

    setStage("ready", 1)
    task.wait(0.3)
    if loading and loading.Parent then
        loading:Destroy()
    end

    pcall(lib.CreateNotification, lib, {
        Title = "ZAPX | PS99 " .. VERSION,
        Content = ("%d/%d tabs. RightControl window, X unload."):format(loaded, #manifest),
        Duration = 6,
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
    warn("[ZAPX] " .. message)
    task.delay(10, function()
        if loading and loading.Parent then
            loading:Destroy()
        end
    end)
    return nil
end

return result
