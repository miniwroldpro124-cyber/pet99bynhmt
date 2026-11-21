--[[
    ZapHub / PS99 - main

    Bootstrap only. Every tab is a separate file fetched from the repo:

        main.lua            this file - menu, engine, unload
        manifest.lua        ordered tab list
        lib/ui.lua          element factories
        modules/*.lua       one tab each
        zaphub.lua          ZapLib 2.0.0, the interface
        ps99_engine_v2.lua  PS99 CLEAN, the farm engine

    Nothing is hard-coded here except the base URL and the version. Add a tab by
    adding a row to manifest.lua and a file under modules/.

    RightControl  window
    Insert        engine picker panel
    X             unload
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/"
local VERSION = "v4"
local PANEL = "PS99CLEAN"

assert(player, "[ZapHub] no LocalPlayer")

local function httpGet(url)
    -- game:HttpGet is not a member on every executor but the request family is.
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
        if ok and type(body) == "string" and #body > 16 then
            return body
        end
    end
    return nil
end

local function fetch(relative)
    local body = httpGet(BASE .. relative)
    if not body then
        error("[ZapHub] fetch failed: " .. relative, 0)
    end
    return body
end

local function compile(source, label)
    local chunk, err = loadstring(source, "=" .. label)
    if not chunk then
        error("[ZapHub] " .. label .. ": " .. tostring(err), 0)
    end
    return chunk
end

--------------------------------------------------------------------- engine

local engine = rawget(_G, "__PS99CLEAN")
if type(engine) ~= "table" or type(engine.SetEnabled) ~= "function" then
    local ok, err = pcall(function()
        compile(fetch("ps99_engine_v2.lua"), "engine")()
    end)
    if not ok then
        return warn(tostring(err))
    end
    engine = rawget(_G, "__PS99CLEAN")
end
if type(engine) ~= "table" then
    return warn("[ZapHub] engine loaded but published no controller")
end

-- The engine builds its own grey "PS99 CLEAN" window and leaves it enabled.
-- panelAllowed is the only path back to it.
local panelAllowed = false

local function panel()
    local gui = player:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild(PANEL) or nil
end

local function setPanel(on)
    panelAllowed = on == true
    local gui = panel()
    if gui then
        gui.Enabled = panelAllowed
        return true
    end
    return false
end

setPanel(false)

do
    local gui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 10)
    if gui then
        gui.ChildAdded:Connect(function(child)
            if child.Name == PANEL and not panelAllowed then
                child.Enabled = false
            end
        end)
    end
    task.spawn(function()
        for _ = 1, 60 do
            if not panelAllowed then
                local instance = panel()
                if instance and instance.Enabled then
                    instance.Enabled = false
                end
            end
            task.wait(0.2)
        end
    end)
end

---------------------------------------------------------------- interface

local lib = rawget(_G, "ZapLib")
if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    local ok, err = pcall(function()
        compile(fetch("zaphub.lua"), "library")()
    end)
    if not ok then
        return warn(tostring(err))
    end
    lib = rawget(_G, "ZapLib")
end
if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    return warn("[ZapHub] library loaded but no window")
end

local win = lib.Window

local uiOk, uiOrErr = pcall(function()
    local builder = compile(fetch("lib/ui.lua"), "lib/ui")()
    if type(builder) ~= "function" then
        error("lib/ui did not return a builder", 0)
    end
    return builder(lib, engine)
end)
if not uiOk or type(uiOrErr) ~= "table" then
    return warn("[ZapHub] ui helper: " .. tostring(uiOrErr))
end
local ui = uiOrErr

local unloaded = false

local function unload()
    if unloaded then return end
    unloaded = true
    pcall(engine.Stop)
    pcall(lib.Destroy, lib)
end

local ctx = {
    player = player,
    engine = engine,
    lib = lib,
    win = win,
    ui = ui,
    version = VERSION,
    base = BASE,
    setPanel = setPanel,
    unload = unload,
    fetch = fetch,
    compile = compile,
}

------------------------------------------------------------------ modules

local manifestOk, manifest = pcall(function()
    return compile(fetch("manifest.lua"), "manifest")()
end)
if not manifestOk or type(manifest) ~= "table" then
    return warn("[ZapHub] manifest: " .. tostring(manifest))
end

local loaded, failed = 0, {}

for _, entry in ipairs(manifest) do
    local source = httpGet(BASE .. entry.file)
    if not source then
        failed[#failed + 1] = entry.name .. " (fetch)"
    else
        local chunk, err = loadstring(source, "=" .. entry.file)
        if not chunk then
            failed[#failed + 1] = entry.name .. " (" .. tostring(err) .. ")"
        else
            local ran, builder = pcall(chunk)
            if not ran then
                failed[#failed + 1] = entry.name .. " (" .. tostring(builder) .. ")"
            elseif type(builder) ~= "function" then
                failed[#failed + 1] = entry.name .. " (no builder returned)"
            else
                local ok, runErr = pcall(builder, ctx)
                if ok then
                    loaded += 1
                else
                    failed[#failed + 1] = entry.name .. " (" .. tostring(runErr) .. ")"
                end
            end
        end
    end
    task.wait()
end

------------------------------------------------------------- status + keys

local statusTab = win:CreateTab("Status", "rbxassetid://12130070198")

local statusParagraph = statusTab:CreateParagraph({
    Title = "Engine",
    Content = "collecting...",
})

statusTab:CreateParagraph({
    Title = "Build",
    Content = ("ZapHub PS99 %s - %d/%d modules"):format(VERSION, loaded, #manifest),
})

if #failed > 0 then
    statusTab:CreateParagraph({
        Title = "Failed modules",
        Content = table.concat(failed, "\n"),
    })
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
            local on = count(state.enabled)
            local line = ("world %s | profile %s | %d feature(s) on")
                :format(tostring(state.world), tostring(state.profile), on)
            if statusParagraph.Set then
                pcall(statusParagraph.Set, statusParagraph, { Title = "Engine", Content = line })
            end
        end
        task.wait(3)
    end
end)

local UIS = game:GetService("UserInputService")

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.X then
        unload()
    end
end)

pcall(lib.CreateNotification, lib, {
    Title = "ZapHub | PS99 " .. VERSION,
    Content = ("%d/%d modules. RightControl window, Insert pickers, X unload."):format(loaded, #manifest),
    Duration = 6,
})

return ctx
