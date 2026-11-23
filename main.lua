--[[
    Steph HUB / PS99 - loader v8.0
    ------------------------------
    One file boots everything:

        1. loading screen with real per-stage progress
        2. headless farm engine (ps99_engine_v3) - no second window ever exists
        3. Steph HUB interface (Steph HUB UI) - the menu you see
        4. one module per tab, fetched from the repo
        5. Status tab driven live from the engine controller

    RightControl  window toggle
    X             unload
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[Steph HUB] run this on the client")

local REPO = "https://github.com/miniwroldpro124-cyber/pet99bynhmt"
local COMMIT = "main"
local VERSION = "8.5"
local PINNED = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/" .. COMMIT .. "/"
local MIRROR_PINNED = "https://cdn.jsdelivr.net/gh/miniwroldpro124-cyber/pet99bynhmt@" .. COMMIT .. "/"
local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/"
local MIRROR = "https://cdn.jsdelivr.net/gh/miniwroldpro124-cyber/pet99bynhmt@main/"

local playerGui = player:WaitForChild("PlayerGui", 30)
assert(playerGui, "[Steph HUB] PlayerGui never appeared")

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
    Text = "Steph HUB  -  PS99  " .. VERSION,
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

-- Branch pointers are the shipping channel and are tried first, so a push
-- lands without a loader rewrite. raw.githubusercontent caches a branch ref
-- for a few minutes and jsDelivr's @main pointer misses recent pushes, which
-- is what the pinned commit fallback is for: it is immutable and can serve a
-- stale-but-working copy rather than nothing.
local function stamp(body)
    return body:match("^%-%-%[%[%s*Steph HUB v([%w%.]+)")
        or body:match("^%-%-%[%[%s*Steph HUB / PS99 %- loader v([%w%.]+)")
        or body:match("^%-%-%[%[%s*ZAPX v([%w%.]+)")
        or body:match("VERSION%s*=%s*\"([%w%.]+)\"")
        or VERSION
end

local function httpGet(relative)
    if type(readfile) == "function" then
        for _, candidate in ipairs({ relative, "stephhub-src/" .. relative, "zaphub-src/" .. relative, "pet99/" .. relative }) do
            local ok, content = pcall(readfile, candidate)
            if ok and type(content) == "string" and #content > 32 then
                return content
            end
        end
    end
    local query = relative:find("?", 1, true) and "&" or "?"
    local bust = query .. "v=" .. VERSION
    local best, bestVersion = nil, nil
    for _, root in ipairs({ BASE, MIRROR, PINNED, MIRROR_PINNED }) do
        local body = getOnce(root .. relative .. bust)
        if body then
            local served = stamp(body)
            if not best or served > bestVersion then
                best, bestVersion = body, served
            end
            if served >= VERSION then
                return body
            end
        end
    end
    return best
end

local function fetch(relative, label)
    local body = httpGet(relative)
    if not body then
        error("[Steph HUB] download failed: " .. tostring(label or relative), 0)
    end
    return body
end

local function compile(source, label)
    local chunk, err = loadstring(source, "=" .. label)
    if not chunk then
        error("[Steph HUB] " .. label .. ": " .. tostring(err), 0)
    end
    return chunk
end

-- Both engine and interface end in `return <object>`. Executors disagree on
-- whether a chunk's writes reach the sandbox _G, but the return value is
-- always the chunk's own. Run it, keep what it returned, and only fall back
-- to globals when the return is not a table.
local function runBell(source, label)
    local chunk = compile(source, label)
    local ok, result = pcall(chunk)
    if not ok then
        error("[Steph HUB] " .. label .. " boot: " .. tostring(result), 0)
    end
    return result
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
    for _, key in ipairs({ "_G", "shared" }) do
        local ok, host = pcall(function() return _ENV[key] end)
        if ok and type(host) == "table" and host[name] ~= nil then
            return host[name]
        end
    end
    return nil
end

-- Some executors hand back a readonly _G. Every publish is best-effort: the
-- return value is what the boot actually uses, the global is a convenience for
-- a re-run in the same session.
local function publishGlobal(name, value)
    pcall(rawset, _G, name, value)
    if type(getgenv) == "function" then
        pcall(function() getgenv()[name] = value end)
    end
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

    -- A controller already in memory is reused only when it is fully formed;
    -- a half-initialised one is torn down and the engine is fetched again.
    local engine = hostGlobal("__PS99CLEAN")
    if type(engine) ~= "table" or type(engine.SetEnabled) ~= "function"
        or type(engine.GetStatus) ~= "function"
        or (type(engine.IsRunning) == "function" and not engine.IsRunning()) then
        if type(engine) == "table" and type(engine.Stop) == "function" then
            pcall(engine.Stop)
            engine = nil
        end
        setStage("downloading farm engine", 0.08)
        local source = fetch("ps99_engine_v3.lua", "engine")

        setStage("booting farm engine", 0.20)
        local returned = runBell(source, "ps99_engine")
        engine = type(returned) == "table" and returned or hostGlobal("__PS99CLEAN")
        if type(engine) == "table" then
            publishGlobal("__PS99CLEAN", engine)
        end
    end
    if type(engine) ~= "table" or type(engine.GetStatus) ~= "function" then
        error("[Steph HUB] engine loaded but published no controller - see [PS99 CLEAN] lines above", 0)
    end

    ------------------------------------------------------------- interface

    setStage("downloading Steph HUB interface", 0.30)
    local lib = hostGlobal("StephLib")
    if type(lib) ~= "table" or type(lib.Window) ~= "table" then
        local source = fetch("lib/menu.lua", "steph_ui")
        setStage("booting Steph HUB interface", 0.40)
        local returned = runBell(source, "steph_ui")
        lib = type(returned) == "table" and returned or hostGlobal("StephLib")
        if type(lib) == "table" then
            publishGlobal("StephLib", lib)
        end
    end
    local win = type(lib) == "table" and lib.Window or nil
    if type(win) ~= "table" then
        error("[Steph HUB] UI loaded but published no window", 0)
    end

    -------------------------------------------------------------- ui helper

    setStage("loading element factories", 0.46)
    local builder = compile(fetch("lib/ui.lua", "ui"), "lib/ui")()
    if type(builder) ~= "function" then
        error("[Steph HUB] lib/ui did not return a builder", 0)
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

    --------------------------------------------------------------- manifest

    setStage("loading tab manifest", 0.50)
    local manifest = compile(fetch("manifest.lua", "manifest"), "manifest")()
    if type(manifest) ~= "table" then
        error("[Steph HUB] manifest is not a table", 0)
    end

    local loaded, failed = 0, {}
    local span = 0.42 / math.max(#manifest, 1)

    -- Declared before the modules so a module can hold ctx.unload.
    local unloaded = false
    local unload

    for index, entry in ipairs(manifest) do
        setStage("loading tab  " .. tostring(entry.name), 0.52 + span * (index - 1))
        local source = httpGet(entry.file)
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
                        config = config,
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
        Content = ("Steph HUB %s - %d/%d tabs loaded"):format(VERSION, loaded, #manifest),
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
    if config and type(config.load) == "function" then
        pcall(config.load)
    end
    task.wait(0.3)
    if loading and loading.Parent then
        loading:Destroy()
    end

    pcall(lib.CreateNotification, lib, {
        Title = "Steph HUB | PS99 " .. VERSION,
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
    warn("[Steph HUB] " .. message)
    task.delay(10, function()
        if loading and loading.Parent then
            loading:Destroy()
        end
    end)
    return nil
end

return result
