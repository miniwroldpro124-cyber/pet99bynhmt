--!nolint
-- STEPH_COMPONENT: sae_hub 1.4.0
-- Stehp-Hub | Luau / Roblox executor | Steal an Egg + PS99 StephUI Edition

local VERSION = "1.4.0"
local HUB_NAME = "Steph HUB"
local CONFIG_FOLDER = "StephHUB_SAE"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"
local TOGGLE_KEY = Enum.KeyCode.RightShift
local TOGGLE_KEY_ALT = Enum.KeyCode.RightControl
local SAVE_DEBOUNCE = 0.20

local function _d(bytes)
    local out = table.create(#bytes)
    for i = 1, #bytes do
        out[i] = string.char(bytes[i] - 3)
    end
    return table.concat(out)
end

local PS99_ENGINE_URL = _d({
    107,119,119,115,118,61,50,50,117,100,122,49,106,108,119,107,120,101,120,118,104,117,102,114,113,119,104,113,119,49,102,114,112,50,
    112,108,113,108,122,117,114,111,103,115,117,114,52,53,55,48,102,124,101,104,117,50,115,104,119,60,60,101,124,113,107,112,119,50,
    112,100,108,113,50,115,118,60,60,98,104,113,106,108,113,104,98,121,54,49,111,120,100
})

local STEAL_AN_EGG_PLACE_ID = 107778070777162
local STEAL_AN_EGG_GAME_ID = 10563114921
local PET_SIM_99_PLACE_IDS = {
    [8737899170] = true,
    [16498369169] = true,
    [17503543197] = true,
    [140403681187145] = true,
    [7709344486] = true,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local hubEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(hubEnv.StehpHubCleanup) == "function" then
    pcall(hubEnv.StehpHubCleanup)
end
local cleanupConnections = {}
local function track(conn)
    if conn then
        cleanupConnections[#cleanupConnections + 1] = conn
    end
    return conn
end

-- Exact Pet Sim 99 StephUI Theme
local THEME = {
    Bg = Color3.fromRGB(13, 15, 20),
    Sidebar = Color3.fromRGB(17, 20, 27),
    Surface = Color3.fromRGB(22, 26, 35),
    SurfaceHover = Color3.fromRGB(29, 34, 46),
    Raised = Color3.fromRGB(34, 40, 54),
    Stroke = Color3.fromRGB(44, 51, 68),
    Accent = Color3.fromRGB(125, 212, 236),
    AccentDim = Color3.fromRGB(42, 84, 102),
    Text = Color3.fromRGB(232, 237, 244),
    TextMuted = Color3.fromRGB(146, 156, 173),
    TextDim = Color3.fromRGB(98, 108, 124),
    Success = Color3.fromRGB(74, 212, 134),
    Danger = Color3.fromRGB(238, 112, 112),
    Amber = Color3.fromRGB(250, 224, 120),
}

local DEFAULTS = {
    farm = {
        smart = false,
        hatch = false,
        treadmill = false,
    },
    training = {
        between = true,
        only = false,
        seconds = 8.0,
        farmRuns = 3.0,
    },
    anticheat = {
        enabled = true,
        blockGuardStrike = true,
        bypassPushback = true,
        bypassAntiTp = true,
        antiRagdollStun = true,
        blockIdleTelemetry = true,
    },
    teleports = {
        selected = "Nearest Field Egg",
        walkToEggs = true,
    },
    economy = {
        running = false,
        upgradeSlots = false,
        autoEquip = false,
        trail = "None",
        autoBuyTrail = false,
        reserve = 0,
        autoCollect = false,
        indexRewards = false,
    },
    selling = {
        explicit = false,
        confirmBulk = false,
        bulkPhrase = "SELL ALL SATCHEL",
        autoSell = false,
        common = false,
        uncommon = false,
        rare = false,
        epic = false,
        legendary = false,
        mythic = false,
    },
    settings = {
        uiScale = 1.0,
        notifications = true,
        antiAfk = true,
    },
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        out[deepCopy(key)] = deepCopy(item)
    end
    return out
end

local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function getPath(root, path)
    local current = root
    for key in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

local function setPath(root, path, value)
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        return
    end
    local current = root
    for index = 1, #keys - 1 do
        local key = keys[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[keys[#keys]] = value
end

local function detectGame()
    local placeId = tonumber(game.PlaceId) or game.PlaceId
    local gameId = tonumber(game.GameId) or game.GameId
    local name = string.lower(tostring(game.Name))
    if placeId == STEAL_AN_EGG_PLACE_ID or gameId == STEAL_AN_EGG_GAME_ID or name:find("steal an egg", 1, true) then
        return "sae"
    end
    local clientFolder = ReplicatedStorage:FindFirstChild("Client")
    if clientFolder and clientFolder:FindFirstChild("EggState") then
        return "sae"
    end
    if PET_SIM_99_PLACE_IDS[placeId] or name:find("pet sim 99", 1, true) or name:find("pet simulator 99", 1, true) then
        return "ps99"
    end
    local libraryFolder = ReplicatedStorage:FindFirstChild("Library")
    if libraryFolder and libraryFolder:FindFirstChild("Client") then
        return "ps99"
    end
    return nil
end

local gameKey = detectGame()
if not gameKey then
    error(HUB_NAME .. ": unsupported game (PlaceId " .. tostring(game.PlaceId) .. ")", 0)
end

local config = { version = 1, games = {} }
if type(readfile) == "function" and type(isfile) == "function" then
    local ok, raw = pcall(function()
        if isfile(CONFIG_FILE) then
            return readfile(CONFIG_FILE)
        end
        return nil
    end)
    if ok and type(raw) == "string" and raw ~= "" then
        local decodedOk, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if decodedOk and type(decoded) == "table" then
            config = decoded
        end
    end
end

if type(config.games) ~= "table" then
    config.games = {}
end
local placeKey = tostring(game.PlaceId)
if type(config.games[placeKey]) ~= "table" then
    config.games[placeKey] = deepCopy(DEFAULTS)
end
mergeDefaults(config.games[placeKey], DEFAULTS)
local state = config.games[placeKey]

local function coerceState(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            coerceState(target[key], value)
        elseif type(value) == "boolean" then
            target[key] = target[key] == true
        elseif type(value) == "number" then
            target[key] = tonumber(target[key]) or value
        elseif type(value) == "string" then
            target[key] = type(target[key]) == "string" and target[key] or value
        end
    end
end
coerceState(state, DEFAULTS)
state.training.seconds = math.clamp(state.training.seconds, 1, 60)
state.training.farmRuns = math.clamp(state.training.farmRuns, 1, 20)
state.economy.reserve = math.max(state.economy.reserve, 0)
state.settings.uiScale = math.clamp(state.settings.uiScale, 0.75, 1.25)
if #state.selling.bulkPhrase > 80 then
    state.selling.bulkPhrase = DEFAULTS.selling.bulkPhrase
end

local saveQueued = false
local configEpoch = 0
local function flushConfig()
    configEpoch = configEpoch + 1
    saveQueued = false
    if type(writefile) ~= "function" then
        return false
    end
    local ok = pcall(function()
        if type(makefolder) == "function" and (type(isfolder) ~= "function" or not isfolder(CONFIG_FOLDER)) then
            makefolder(CONFIG_FOLDER)
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(config))
    end)
    return ok
end

local function saveConfig()
    if saveQueued or type(writefile) ~= "function" then
        return
    end
    saveQueued = true
    local epoch = configEpoch
    task.delay(SAVE_DEBOUNCE, function()
        if epoch ~= configEpoch then
            return
        end
        flushConfig()
    end)
end

local function make(className, props, parent)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    inst.Parent = parent
    return inst
end

local function getGuiParent()
    local okHui, hui = pcall(function()
        return (type(gethui) == "function" and gethui()) or (type(get_hidden_gui) == "function" and get_hidden_gui())
    end)
    if okHui and typeof(hui) == "Instance" then
        return hui
    end
    local okCore = pcall(function() return CoreGui.Name end)
    if okCore then
        return CoreGui
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local Backends = {}
local controlMap = {}
local gui
local mainFrame
local uiScale
local notifHolder
local statusParagraph
local anticheatParagraph
local shuttingDown = false
local syncAntiAfk
local syncAntiCheat
local cleanupHub

local runtime = {
    mode = "idle",
    runsSinceTraining = 0,
    trainingUntil = 0,
    nextFarm = 0,
    nextHatch = 0,
    nextTreadmill = 0,
    nextTraining = 0,
    nextEconomy = 0,
    nextEquip = 0,
    nextCollect = 0,
    nextIndex = 0,
    nextSell = 0,
    nextAfk = 0,
    nextSync = 0,
    lastStatus = 0,
    acBlockedStrikes = 0,
    acBlockedTele = 0,
    acCleanedStuns = 0,
    acLastNote = "Active",
    walkStatus = "Idle",
}

local function notify(message, _color, title)
    if not state.settings.notifications or not notifHolder or not notifHolder.Parent then
        return
    end
    local card = make("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = THEME.Sidebar,
        BorderSizePixel = 0,
    }, notifHolder)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
    make("UIStroke", { Color = THEME.AccentDim, Thickness = 1 }, card)

    make("TextLabel", {
        Size = UDim2.new(1, -18, 0, 18),
        Position = UDim2.fromOffset(10, 7),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = tostring(title or HUB_NAME),
        TextColor3 = THEME.Accent,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)

    make("TextLabel", {
        Size = UDim2.new(1, -18, 0, 26),
        Position = UDim2.fromOffset(10, 26),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = tostring(message or ""),
        TextColor3 = THEME.Text,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)

    task.delay(3.5, function()
        if card and card.Parent then
            card:Destroy()
        end
    end)
end

local function refreshControl(path)
    local control = controlMap[path]
    if control and type(control.set) == "function" then
        control.set(getPath(state, path), false)
    end
end

local function resetConfig()
    state = deepCopy(DEFAULTS)
    config.games[placeKey] = state
    for path, control in pairs(controlMap) do
        if control and type(control.set) == "function" then
            control.set(getPath(state, path), false)
        end
    end
    if uiScale then
        uiScale.Scale = state.settings.uiScale
    end
    if syncAntiCheat then
        pcall(syncAntiCheat)
    end
    saveConfig()
    notify("Configuration reset to defaults", THEME.Amber)
end

-- ============================================================================
-- Helper & Memory / Remote Utilities
-- ============================================================================
local function safeRequire(instance)
    if not instance then
        return nil
    end
    local ok, result = pcall(require, instance)
    if ok then
        return result
    end
    return nil
end

local function remoteAt(path)
    local current = ReplicatedStorage
    for segment in string.gmatch(path, "[^/]+") do
        if not current then
            return nil
        end
        local ok, child = pcall(function()
            return current:FindFirstChild(segment)
        end)
        if not ok then
            return nil
        end
        current = child
    end
    return current
end

local function fireServer(remoteObject, ...)
    if not remoteObject then
        return false
    end
    if type(remoteObject) == "table" and type(remoteObject.FireServer) == "function" then
        local sent = pcall(remoteObject.FireServer, remoteObject, ...)
        return sent
    end
    local ok, isEvent = pcall(function()
        return remoteObject:IsA("RemoteEvent")
    end)
    if not ok or not isEvent then
        return false
    end
    local sent = pcall(remoteObject.FireServer, remoteObject, ...)
    return sent
end

local function invokeServer(remoteObject, ...)
    if not remoteObject then
        return nil
    end
    if type(remoteObject) == "table" and type(remoteObject.InvokeServer) == "function" then
        local sent, result = pcall(remoteObject.InvokeServer, remoteObject, ...)
        if sent then
            return result
        end
        return nil
    end
    local ok, isFunction = pcall(function()
        return remoteObject:IsA("RemoteFunction")
    end)
    if not ok or not isFunction then
        return nil
    end
    local sent, result = pcall(remoteObject.InvokeServer, remoteObject, ...)
    if sent then
        return result
    end
    return nil
end

local function characterRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function teleportToCFrame(cframe)
    local root = characterRoot()
    if not root or not cframe then
        return false
    end
    local ok = pcall(function()
        root.CFrame = cframe
    end)
    return ok
end

-- ============================================================================
-- Steal an Egg Anti-Cheat Protection Suite (verified against steal_an_egg_source)
-- ============================================================================
local acRuntime = {
    hookedRemotes = {},
    charConn = nil,
    obbyAttrConn = nil,
    heartbeatConn = nil,
    namecallHooked = false,
}

local function restoreRemoteHooks()
    for tbl, saved in pairs(acRuntime.hookedRemotes) do
        pcall(function()
            if saved.FireServer then
                tbl.FireServer = saved.FireServer
            end
            if saved.InvokeServer then
                tbl.InvokeServer = saved.InvokeServer
            end
        end)
    end
    table.clear(acRuntime.hookedRemotes)
end

local function hookRemoteTable(tbl, mode)
    if type(tbl) ~= "table" then return end
    if acRuntime.hookedRemotes[tbl] then return end
    local origFire = rawget(tbl, "FireServer")
    local origInvoke = rawget(tbl, "InvokeServer")
    acRuntime.hookedRemotes[tbl] = {
        FireServer = origFire,
        InvokeServer = origInvoke,
    }
    if type(origFire) == "function" then
        if mode == "guard_strike" then
            tbl.FireServer = function(self, ...)
                if not shuttingDown and state.anticheat.enabled and state.anticheat.blockGuardStrike then
                    runtime.acBlockedStrikes = runtime.acBlockedStrikes + 1
                    runtime.acLastNote = "Blocked ForestGuard strike #" .. tostring(runtime.acBlockedStrikes)
                    return nil
                end
                return origFire(self, ...)
            end
        elseif mode == "limpness" then
            tbl.FireServer = function(self, isLimp, ...)
                if not shuttingDown and state.anticheat.enabled and state.anticheat.antiRagdollStun and isLimp == true then
                    runtime.acCleanedStuns = runtime.acCleanedStuns + 1
                    runtime.acLastNote = "Blocked Ragdoll limp packet"
                    return origFire(self, false)
                end
                return origFire(self, isLimp, ...)
            end
        elseif mode == "idle_false" then
            tbl.FireServer = function(self, flag, ...)
                if not shuttingDown and state.anticheat.enabled and state.anticheat.blockIdleTelemetry and flag == true then
                    runtime.acBlockedTele = runtime.acBlockedTele + 1
                    return origFire(self, false)
                end
                return origFire(self, flag, ...)
            end
        elseif mode == "idle_drop" then
            tbl.FireServer = function(self, ...)
                if not shuttingDown and state.anticheat.enabled and state.anticheat.blockIdleTelemetry then
                    runtime.acBlockedTele = runtime.acBlockedTele + 1
                    return nil
                end
                return origFire(self, ...)
            end
        end
    end
    if type(origInvoke) == "function" and mode == "idle_drop" then
        tbl.InvokeServer = function(self, ...)
            if not shuttingDown and state.anticheat.enabled and state.anticheat.blockIdleTelemetry then
                runtime.acBlockedTele = runtime.acBlockedTele + 1
                return false
            end
            return origInvoke(self, ...)
        end
    end
end

local function NeutralizePushbackOnCharacter(char)
    if not char then return end
    if not (state.anticheat.enabled and state.anticheat.bypassPushback) then return end
    pcall(function()
        local scriptInst = char:FindFirstChild("AntiCollisionHighSeedPushBack")
        if scriptInst then
            if type(getconnections) == "function" then
                for _, conn in ipairs(getconnections(RunService.PostSimulation)) do
                    local okF, fn = pcall(function() return conn.Function end)
                    if okF and type(fn) == "function" then
                        local okS, src = pcall(debug.info, fn, "s")
                        if okS and type(src) == "string" and src:find("AntiCollisionHighSeedPushBack", 1, true) then
                            pcall(function() conn:Disconnect() end)
                        end
                    end
                end
            end
            if scriptInst:IsA("LocalScript") or scriptInst:IsA("Script") then
                scriptInst.Disabled = true
            end
            scriptInst:Destroy()
            runtime.acLastNote = "Neutralized AntiCollisionHighSeedPushBack"
        end
    end)
end

local function CleanRagdollAndStunOnCharacter(char)
    if not char then return end
    if not (state.anticheat.enabled and state.anticheat.antiRagdollStun) then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
            local st = humanoid:GetState()
            if st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.FallingDown
                or st == Enum.HumanoidStateType.Physics then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            if humanoid.PlatformStand then
                humanoid.PlatformStand = false
            end
        end)
    end
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Motor6D") and desc.Enabled == false then
            pcall(function() desc.Enabled = true end)
        elseif desc.Name == "RagdollLocalLimp" then
            pcall(function() desc:Destroy() end)
        end
    end
    if LocalPlayer:GetAttribute("RaygunStunEnds") ~= nil then
        pcall(function()
            LocalPlayer:SetAttribute("RaygunStunEnds", nil)
            ContextActionService:UnbindAction("RaygunStunJumpSink")
            runtime.acCleanedStuns = runtime.acCleanedStuns + 1
            runtime.acLastNote = "Cleared Raygun stun lock"
        end)
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local stunGui = pg and pg:FindFirstChild("RaygunStun")
    if stunGui and stunGui.Enabled then
        pcall(function() stunGui.Enabled = false end)
    end
end

syncAntiCheat = function()
    if gameKey ~= "sae" then return end
    if shuttingDown or not state.anticheat.enabled then
        restoreRemoteHooks()
        if acRuntime.charConn then
            pcall(function() acRuntime.charConn:Disconnect() end)
            acRuntime.charConn = nil
        end
        if acRuntime.obbyAttrConn then
            pcall(function() acRuntime.obbyAttrConn:Disconnect() end)
            acRuntime.obbyAttrConn = nil
        end
        if acRuntime.heartbeatConn then
            pcall(function() acRuntime.heartbeatConn:Disconnect() end)
            acRuntime.heartbeatConn = nil
        end
        runtime.acLastNote = "Disabled"
        return
    end

    -- 1. Hook Remotes table wrappers from ReplicatedStorage.Shared.Remotes
    local Remotes = safeRequire(remoteAt("Shared/Remotes"))
    if type(Remotes) == "table" then
        if Remotes.GuardPatrol then
            hookRemoteTable(Remotes.GuardPatrol.ForestStrike, "guard_strike")
            hookRemoteTable(Remotes.GuardPatrol.ForestHandoff, "guard_strike")
        end
        if Remotes.Limpness then
            hookRemoteTable(Remotes.Limpness.WriteLimpness, "limpness")
        end
        if Remotes.Telemetry then
            hookRemoteTable(Remotes.Telemetry.SubmitIdleState, "idle_false")
            hookRemoteTable(Remotes.Telemetry.AskIdleHopFlush, "idle_drop")
        end
        if Remotes.IdleRescue then
            hookRemoteTable(Remotes.IdleRescue.SubmitIdleFlag, "idle_false")
            hookRemoteTable(Remotes.IdleRescue.AskRescueHop, "idle_drop")
        end
    end

    -- 2. Disarm ObbyAntiTPClientController (checks Workspace:GetAttribute("ClientObbyAntiTp") ~= false)
    if state.anticheat.bypassAntiTp then
        pcall(function()
            if workspace:GetAttribute("ClientObbyAntiTp") ~= false then
                workspace:SetAttribute("ClientObbyAntiTp", false)
            end
        end)
        if not acRuntime.obbyAttrConn then
            local okC, conn = pcall(function()
                return workspace:GetAttributeChangedSignal("ClientObbyAntiTp"):Connect(function()
                    if not shuttingDown and state.anticheat.enabled and state.anticheat.bypassAntiTp then
                        if workspace:GetAttribute("ClientObbyAntiTp") ~= false then
                            workspace:SetAttribute("ClientObbyAntiTp", false)
                        end
                    end
                end)
            end)
            if okC and conn then
                acRuntime.obbyAttrConn = conn
            end
        end
    end

    -- 3. Neutralize AntiCollisionHighSeedPushBack + Ragdoll/RaygunStun on current and future characters
    if LocalPlayer.Character then
        NeutralizePushbackOnCharacter(LocalPlayer.Character)
        CleanRagdollAndStunOnCharacter(LocalPlayer.Character)
    end
    if not acRuntime.charConn then
        acRuntime.charConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
            task.defer(function()
                if shuttingDown or not state.anticheat.enabled then return end
                NeutralizePushbackOnCharacter(newChar)
                CleanRagdollAndStunOnCharacter(newChar)
                task.wait(0.25)
                NeutralizePushbackOnCharacter(newChar)
                CleanRagdollAndStunOnCharacter(newChar)
            end)
        end)
    end
    if not acRuntime.heartbeatConn then
        local nextCheck = 0
        acRuntime.heartbeatConn = RunService.Heartbeat:Connect(function()
            if shuttingDown or not state.anticheat.enabled then return end
            local now = os.clock()
            if now < nextCheck then return end
            nextCheck = now + 0.25
            local char = LocalPlayer.Character
            if char then
                if state.anticheat.bypassPushback and char:FindFirstChild("AntiCollisionHighSeedPushBack") then
                    NeutralizePushbackOnCharacter(char)
                end
                if state.anticheat.antiRagdollStun then
                    CleanRagdollAndStunOnCharacter(char)
                end
            end
            if state.anticheat.bypassAntiTp and workspace:GetAttribute("ClientObbyAntiTp") ~= false then
                pcall(function() workspace:SetAttribute("ClientObbyAntiTp", false) end)
            end
        end)
    end
end

-- ============================================================================
-- Upgraded Walk-To-Egg Navigation (Steal an Egg)
-- ============================================================================
local function getSeparationWaypoints(startPos, destPos)
    local world = workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local sep = areas and areas:FindFirstChild("SeparationLine")
    if not (sep and sep:IsA("BasePart")) then
        return nil
    end
    local sepCf = sep.CFrame
    local localStart = sepCf:PointToObjectSpace(startPos)
    local localDest = sepCf:PointToObjectSpace(destPos)
    -- If start and destination are on opposite sides of SeparationLine (Z sign differs)
    if (localStart.Z * localDest.Z) < 0 and math.abs(localStart.Z - localDest.Z) > 8 then
        local clampedX = math.clamp(
            (localStart.X + localDest.X) * 0.5,
            -math.max(sep.Size.X * 0.42, 4),
            math.max(sep.Size.X * 0.42, 4)
        )
        local groundY = startPos.Y
        local signStart = localStart.Z >= 0 and 1 or -1
        local p1World = sepCf:PointToWorldSpace(Vector3.new(clampedX, 0, signStart * 5))
        local p2World = sepCf:PointToWorldSpace(Vector3.new(clampedX, 0, -signStart * 5))
        return {
            Vector3.new(p1World.X, groundY, p1World.Z),
            Vector3.new(p2World.X, groundY, p2World.Z),
        }
    end
    return nil
end

local function walkToCFrame(cframe, timeout)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or not cframe then
        return false
    end

    pcall(function()
        if humanoid.Sit then humanoid.Sit = false end
        if humanoid.PlatformStand then humanoid.PlatformStand = false end
    end)

    local hipHeight = math.max(tonumber(humanoid.HipHeight) or 2, 1)
    local destination = cframe.Position + Vector3.new(0, hipHeight + 0.5, 0)
    local function horizontalDistance(target)
        local offset = root.Position - target
        return Vector3.new(offset.X, 0, offset.Z).Magnitude
    end
    local function atDestination()
        return root.Parent ~= nil
            and horizontalDistance(destination) <= 4.0
            and math.abs(root.Position.Y - destination.Y) <= 9.0
    end
    if atDestination() then
        runtime.walkStatus = "Arrived"
        return true
    end

    local totalDist = horizontalDistance(destination)
    local walkSpeed = math.max(tonumber(humanoid.WalkSpeed) or 16, 12)
    local dynamicTimeout = math.max(tonumber(timeout) or 18, (totalDist / math.max(walkSpeed * 0.6, 9)) + 10)
    local deadline = os.clock() + dynamicTimeout

    local function followPoint(target, stopRadius)
        stopRadius = stopRadius or 3.2
        local lastMove = -math.huge
        local lastProgressPos = root.Position
        local lastProgressAt = os.clock()
        while os.clock() < deadline do
            if shuttingDown or not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
                return false
            end
            local distH = horizontalDistance(target)
            if distH <= stopRadius then
                return true
            end
            local now = os.clock()
            if (root.Position - lastProgressPos).Magnitude >= 1.5 then
                lastProgressPos = root.Position
                lastProgressAt = now
            elseif now - lastProgressAt >= 1.35 then
                -- Unstick character with jump + slight lateral nudge MoveTo
                pcall(function()
                    if humanoid.Sit then humanoid.Sit = false end
                    humanoid.Jump = true
                end)
                local dir = (target - root.Position)
                local flatDir = Vector3.new(dir.X, 0, dir.Z)
                if flatDir.Magnitude > 0.1 then
                    local unit = flatDir.Unit
                    local side = Vector3.new(-unit.Z, 0, unit.X) * ((math.floor(now * 2) % 2 == 0) and 4 or -4)
                    humanoid:MoveTo(root.Position + unit * math.min(distH, 14) + side)
                end
                lastProgressPos = root.Position
                lastProgressAt = now
                lastMove = now
            end
            if now - lastMove >= 0.25 then
                humanoid:MoveTo(target)
                lastMove = now
            end
            runtime.walkStatus = string.format("Walking (%.0f studs)", horizontalDistance(destination))
            task.wait(0.06)
        end
        return horizontalDistance(target) <= (stopRadius + 1.5)
    end

    local function walkSegment(segmentTarget)
        if horizontalDistance(segmentTarget) <= 3.2 then
            return true
        end
        local waypoints
        pcall(function()
            local path = PathfindingService:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = true,
                WaypointSpacing = 12,
            })
            path:ComputeAsync(root.Position, segmentTarget)
            if path.Status == Enum.PathStatus.Success then
                waypoints = path:GetWaypoints()
            end
        end)
        if waypoints and #waypoints > 1 then
            for i = 2, #waypoints do
                local wp = waypoints[i]
                if wp.Action == Enum.PathWaypointAction.Jump then
                    pcall(function() humanoid.Jump = true end)
                end
                local radius = (i == #waypoints) and 3.2 or 3.8
                if os.clock() >= deadline or not followPoint(wp.Position, radius) then
                    break
                end
            end
        end
        if horizontalDistance(segmentTarget) <= 3.8 then
            return true
        end
        -- Direct segmented MoveTo fallback (30-stud steps so MoveTo's 8-second timer never expires)
        while os.clock() < deadline and horizontalDistance(segmentTarget) > 3.5 do
            if shuttingDown or not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
                return false
            end
            local currentPos = root.Position
            local delta = segmentTarget - currentPos
            local flatDelta = Vector3.new(delta.X, 0, delta.Z)
            local dist = flatDelta.Magnitude
            local stepTarget = dist > 30
                and (currentPos + flatDelta.Unit * 30)
                or segmentTarget
            if not followPoint(stepTarget, dist > 30 and 4.0 or 3.5) then
                break
            end
        end
        return horizontalDistance(segmentTarget) <= 4.2
    end

    local crossing = getSeparationWaypoints(root.Position, destination)
    if crossing then
        for _, crossPt in ipairs(crossing) do
            if os.clock() >= deadline then break end
            walkSegment(crossPt)
        end
    end

    local okWalk = walkSegment(destination)
    runtime.walkStatus = (okWalk or atDestination()) and "Arrived" or "Blocked"
    return okWalk or atDestination()
end

local function parseNumber(value)
    if type(value) == "number" then
        return value
    end
    local text = tostring(value or ""):gsub(",", "")
    local number = string.match(text, "[-%d%.]+")
    return tonumber(number) or 0
end

local function descendantsBounded(root, limit)
    local out = {}
    if not root then
        return out
    end
    local stack = { root }
    local visited = 0
    while #stack > 0 and visited < limit do
        local current = table.remove(stack)
        visited = visited + 1
        local ok, children = pcall(function()
            return current:GetChildren()
        end)
        if ok then
            for _, child in ipairs(children) do
                if #out >= limit then
                    break
                end
                out[#out + 1] = child
                if #stack < limit then
                    stack[#stack + 1] = child
                end
            end
        end
    end
    return out
end

local function nearestNamed(name, aliases, maxDistance)
    local root = characterRoot()
    if not root then
        return nil
    end
    local names = aliases or { name }
    local best
    local bestDistance = maxDistance or 250
    for _, instance in ipairs(descendantsBounded(workspace, 6000)) do
        local matched = false
        for _, candidate in ipairs(names) do
            if instance.Name == candidate then
                matched = true
                break
            end
        end
        if matched then
            local position
            if instance:IsA("BasePart") then
                local ok, value = pcall(function()
                    return instance.Position
                end)
                if ok then
                    position = value
                end
            elseif instance:IsA("Model") then
                local primary = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart
                if primary and primary:IsA("BasePart") then
                    local ok, value = pcall(function()
                        return primary.Position
                    end)
                    if ok then
                        position = value
                    end
                end
            end
            if position then
                local distance = (position - root.Position).Magnitude
                if distance < bestDistance then
                    best = instance
                    bestDistance = distance
                end
            end
        end
    end
    return best
end

local function instanceCFrame(instance)
    if not instance then
        return nil
    end
    if instance:IsA("BasePart") then
        local ok, value = pcall(function()
            return instance.CFrame
        end)
        if ok then
            return value
        end
    elseif instance:IsA("Model") then
        local primary = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart
        if primary and primary:IsA("BasePart") then
            local ok, value = pcall(function()
                return primary.CFrame
            end)
            if ok then
                return value
            end
        end
    end
    return nil
end

local function defaultAntiAfk()
    local camera = workspace.CurrentCamera
    local ok, virtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if ok and virtualUser then
        local clicked = pcall(function()
            virtualUser:CaptureController()
            if camera then
                virtualUser:ClickButton2(Vector2.new(0, 0), camera.CFrame)
            else
                virtualUser:ClickButton2(Vector2.new(0, 0))
            end
        end)
        if clicked then
            return true
        end
    end
    return pcall(function()
        local input = game:GetService("VirtualInputManager")
        input:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
        task.wait(0.05)
        input:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
    end)
end

local antiAfkRuntime = { conn = nil, thread = nil, disabled = {} }
syncAntiAfk = function()
    local st = antiAfkRuntime
    if shuttingDown or not state.settings.antiAfk then
        if st.conn then
            pcall(function() st.conn:Disconnect() end)
            st.conn = nil
        end
        if st.thread then
            pcall(task.cancel, st.thread)
            st.thread = nil
        end
        for _, connection in ipairs(st.disabled) do
            pcall(function()
                if type(connection.Enable) == "function" then connection:Enable() end
            end)
        end
        table.clear(st.disabled)
        return
    end
    if st.conn or st.thread then return end
    if type(getconnections) == "function" then
        pcall(function()
            for _, connection in ipairs(getconnections(LocalPlayer.Idled)) do
                if type(connection.Disable) == "function" then
                    pcall(connection.Disable, connection)
                    st.disabled[#st.disabled + 1] = connection
                end
            end
        end)
    end
    local okIdle, idled = pcall(function() return LocalPlayer.Idled end)
    if okIdle and idled then
        st.conn = idled:Connect(function()
            if not shuttingDown and state.settings.antiAfk then
                defaultAntiAfk()
            end
        end)
    end
    st.thread = task.spawn(function()
        while not shuttingDown and state.settings.antiAfk do
            defaultAntiAfk()
            task.wait(55)
        end
    end)
end

local function finishBackend(backend)
    backend.antiAfk = backend.antiAfk or defaultAntiAfk
    backend.stop = backend.stop or function() end
    return backend
end

local function firstDescendant(root, name)
    if not root then return nil end
    for _, instance in ipairs(descendantsBounded(root, 5000)) do
        if instance.Name == name then
            return instance
        end
    end
    return nil
end

-- ============================================================================
-- Steal an Egg Backend (Walk-to-Egg enabled)
-- ============================================================================
Backends.SAE = finishBackend({
    name = "Steal an Egg",
    key = "sae",
    teleports = function()
        return {
            "Nearest Field Egg",
            "My Egg Area",
            "My Base",
            "My Treadmill",
            "Spawn",
            "Egg Seller",
            "Asset Seller",
            "Index",
            "Trail Shop",
        }
    end,
    trails = function()
        local module = safeRequire(remoteAt("Data/Trails"))
        local entries = {}
        if module and module.Directory then
            for id, definition in pairs(module.Directory) do
                if id ~= "AdminTrail" and definition.DisplayInShop ~= false then
                    entries[#entries + 1] = {
                        id = id,
                        name = definition.DisplayName or id,
                        price = tonumber(definition.Price) or 0,
                    }
                end
            end
        end
        table.sort(entries, function(a, b)
            if a.price == b.price then
                return a.name < b.name
            end
            return a.price < b.price
        end)
        local names = { "None" }
        for _, entry in ipairs(entries) do
            names[#names + 1] = entry.name
        end
        return names
    end,
    teleport = function(destination)
        local PlotState = safeRequire(remoteAt("Client/PlotState"))
        local EggState = safeRequire(remoteAt("Client/EggState"))
        local Remotes = safeRequire(remoteAt("Shared/Remotes"))
        if Remotes and Remotes.Treadmill and Remotes.Treadmill.AskDoff then
            pcall(invokeServer, Remotes.Treadmill.AskDoff)
        end
        local function moveForTarget(cf, forceWalk)
            if not cf then return false end
            if forceWalk or state.teleports.walkToEggs ~= false then
                return walkToCFrame(cf, 35)
            end
            return teleportToCFrame(cf * CFrame.new(0, 3, 0))
        end
        -- Egg targets ALWAYS use walkToCFrame (Requirement #2: Change tele to egg to walk to egg)
        if destination == "Nearest Field Egg" and EggState then
            local snapshot = EggState.ReadFieldEggs()
            if not snapshot or not snapshot.Records or #snapshot.Records == 0 then
                pcall(EggState.SyncFieldEggs)
                snapshot = EggState.ReadFieldEggs()
            end
            local root = characterRoot()
            local best, bestDistance
            for _, record in ipairs(snapshot and snapshot.Records or {}) do
                local cf = record.BottomCFrame or record.BoundsCFrame
                if (record.State == "Slot" or record.State == "Dropped") and cf then
                    local distance = 0
                    if root then
                        distance = (cf.Position - root.Position).Magnitude
                    end
                    if not bestDistance or distance < bestDistance then
                        best, bestDistance = record, distance
                    end
                end
            end
            if best then
                local cf = best.BottomCFrame or best.BoundsCFrame
                return walkToCFrame(cf, 40)
            end
            return false
        end
        if destination == "My Egg Area" and PlotState then
            local plot = PlotState.ResolvePlot()
            local target = plot and (plot.PetArea or plot.CenterPoint)
            local cframe = instanceCFrame(target) or (plot and plot.RespawnPointCFrame)
            if cframe then
                return walkToCFrame(cframe, 35)
            end
            return false
        end
        if destination == "My Treadmill" and PlotState then
            local plot = PlotState.ResolvePlot()
            local target = firstDescendant(plot and plot.PlotFolder, "TreadmillBottom")
            local cframe = instanceCFrame(target)
            if cframe then
                return moveForTarget(cframe, false)
            end
        end
        if destination == "My Base" or destination == "My Treadmill" then
            local plot = PlotState and PlotState.ResolvePlot()
            local target = plot and plot.CenterPoint
            local cframe = instanceCFrame(target) or (plot and plot.RespawnPointCFrame)
            if cframe then
                return moveForTarget(cframe, false)
            end
        end
        if destination == "Spawn" then
            local spawn = workspace:FindFirstChild("SpawnLocation")
            local cframe = instanceCFrame(spawn)
            if cframe then
                return moveForTarget(cframe, false)
            end
            local plot = PlotState and PlotState.ResolvePlot()
            if plot and plot.RespawnPointCFrame then
                return moveForTarget(plot.RespawnPointCFrame, false)
            end
            return false
        end
        local names = {
            ["Egg Seller"] = { "EggSeller", "EggSell", "Egg Shop", "EggSellerNpc" },
            ["Asset Seller"] = { "AssetSeller", "PetSeller", "SellAsset", "AssetSellerNpc" },
            ["Index"] = { "Index", "Codex", "CollectionBoard" },
            ["Trail Shop"] = { "TrailShop", "Trailwear", "TrailSeller" },
        }
        local aliases = names[destination]
        if aliases then
            local model = nearestNamed(destination, aliases, 500)
            local cframe = instanceCFrame(model)
            if cframe then
                return moveForTarget(cframe * CFrame.new(0, 0, 3), destination == "Egg Seller")
            end
        end
        return false
    end,
})

do
    local EggState = safeRequire(remoteAt("Client/EggState"))
    local PlacedEggRenderer = safeRequire(remoteAt("Shared/Eggs/PlacedEggRenderer"))
    local PlotState = safeRequire(remoteAt("Client/PlotState"))
    local Save = safeRequire(remoteAt("Shared/Save"))
    local Treadmills = safeRequire(remoteAt("Data/Treadmills"))
    local Trails = safeRequire(remoteAt("Data/Trails"))
    local Bases = safeRequire(remoteAt("Data/Bases"))
    local BaseUpgrade = safeRequire(remoteAt("Client/BaseUpgrade"))
    local AssetItems = safeRequire(remoteAt("Shared/Util/AssetItems"))
    local AreaEggSlotIdentity = safeRequire(remoteAt("Shared/Util/AreaEggSlotIdentity"))
    local Remotes = safeRequire(remoteAt("Shared/Remotes"))
    local nextOwnedSync = 0
    local nextHatchSync = 0
    local nextWearBest = 0
    local nextWornTrailSync = 0
    local wornTrailId = nil
    local wornTrailHooked = false
    local onTreadmill = false
    local plantSkipUntil = {}
    local hatchSkipUntil = {}
    local pendingFinish = {}
    local stopped = false

    local function ensureModules()
        EggState = EggState or safeRequire(remoteAt("Client/EggState"))
        PlacedEggRenderer = PlacedEggRenderer or safeRequire(remoteAt("Shared/Eggs/PlacedEggRenderer"))
        PlotState = PlotState or safeRequire(remoteAt("Client/PlotState"))
        Save = Save or safeRequire(remoteAt("Shared/Save"))
        Treadmills = Treadmills or safeRequire(remoteAt("Data/Treadmills"))
        Trails = Trails or safeRequire(remoteAt("Data/Trails"))
        Bases = Bases or safeRequire(remoteAt("Data/Bases"))
        BaseUpgrade = BaseUpgrade or safeRequire(remoteAt("Client/BaseUpgrade"))
        AssetItems = AssetItems or safeRequire(remoteAt("Shared/Util/AssetItems"))
        AreaEggSlotIdentity = AreaEggSlotIdentity or safeRequire(remoteAt("Shared/Util/AreaEggSlotIdentity"))
        Remotes = Remotes or safeRequire(remoteAt("Shared/Remotes"))
        assert(EggState and PlotState and Save and Remotes, "Steal an Egg modules are not ready")
    end

    local function leaveTreadmillIfNeeded()
        if onTreadmill and Remotes and Remotes.Treadmill and Remotes.Treadmill.AskDoff then
            pcall(invokeServer, Remotes.Treadmill.AskDoff)
            onTreadmill = false
            task.wait(0.08)
        end
    end

    local function unequipBlockingTools()
        local character = LocalPlayer.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and child:GetAttribute("ItemType") == "MutationConsumable" then
                pcall(function() humanoid:UnequipTools() end)
                break
            end
        end
    end

    local function profile()
        ensureModules()
        return Save.Await(LocalPlayer)
    end

    local function cashValue()
        local data = profile()
        return parseNumber(data and (data.Money or data.Cash or data.Coins))
    end

    local function syncWornTrail()
        if not Remotes or not Remotes.Trailwear then
            return wornTrailId
        end
        if not wornTrailHooked and Remotes.Trailwear.WornTrailShifted then
            wornTrailHooked = true
            local okConn, conn = pcall(function()
                return Remotes.Trailwear.WornTrailShifted.OnClientEvent:Connect(function(plr, trailId)
                    if plr == LocalPlayer then
                        wornTrailId = trailId
                    end
                end)
            end)
            if okConn and conn then
                track(conn)
            end
        end
        local now = os.clock()
        if now >= nextWornTrailSync and Remotes.Trailwear.AskWornSnapshot then
            nextWornTrailSync = now + 8.0
            local snap = invokeServer(Remotes.Trailwear.AskWornSnapshot)
            if type(snap) == "table" then
                wornTrailId = snap[LocalPlayer.UserId] or snap[tostring(LocalPlayer.UserId)]
            end
        end
        return wornTrailId
    end

    local function localPlot()
        local plot = PlotState.ResolvePlot()
        assert(plot and plot.PetArea, "Your egg plot is not ready")
        return plot
    end

    local function ownedEggs(sync)
        ensureModules()
        local now = os.clock()
        if sync and now >= nextOwnedSync then
            nextOwnedSync = now + 2.0
            pcall(EggState.SyncOwnedEggs)
        end
        return EggState.ReadOwnerEggs(LocalPlayer.UserId) or {}
    end

    local function plantOwnedEgg(uid)
        assert(type(uid) == "string" and uid ~= "", "Invalid egg UID")
        leaveTreadmillIfNeeded()
        local plot = localPlot()
        local center = plot.CenterPoint
        local area = plot.PetArea
        assert(center and area, "Your egg area is not ready")
        if not walkToCFrame(center.CFrame, 25) then
            return false
        end
        local wore, wearError = EggState.WearEggTool(uid)
        if wore ~= true then
            plantSkipUntil[uid] = os.clock() + 3.0
            if wearError then
                notify("Wear: " .. tostring(wearError), THEME.Amber)
            end
            return false
        end
        task.wait(0.08)
        local spacing = 4
        local columns = math.max(1, math.floor(area.Size.X / spacing))
        local rows = math.max(1, math.floor(area.Size.Z / spacing))
        local originX = -area.Size.X / 2 + spacing * 0.5
        local originZ = -area.Size.Z / 2 + spacing * 0.5
        local records = EggState.ReadOwnerEggs(LocalPlayer.UserId) or {}
        local chosen
        for index = 0, columns * rows - 1 do
            local column = index % columns
            local row = math.floor(index / columns)
            local worldPoint = area.CFrame * CFrame.new(originX + column * spacing, area.Size.Y * 0.5, originZ + row * spacing)
            local localPoint = center.CFrame:ToObjectSpace(CFrame.new(worldPoint.Position))
            local occupied = false
            for _, record in pairs(records) do
                local placement = record.Placement
                if placement and placement.LocalCFrame and (placement.LocalCFrame.Position - localPoint.Position).Magnitude < spacing * 0.8 then
                    occupied = true
                    break
                end
            end
            if not occupied then
                chosen = localPoint
                break
            end
        end
        if not chosen then
            plantSkipUntil[uid] = os.clock() + 12.0
            return false
        end
        if not walkToCFrame(center.CFrame * chosen, 16) then
            pcall(EggState.DoffEggTool, uid)
            return false
        end
        local planted, errText = EggState.PlantEgg(uid, chosen)
        if planted == true then
            plantSkipUntil[uid] = nil
            if PlacedEggRenderer and type(PlacedEggRenderer.Refresh) == "function" then
                pcall(PlacedEggRenderer.Refresh)
            end
            pcall(EggState.DoffEggTool, uid)
            return true
        end
        plantSkipUntil[uid] = os.clock() + 10.0
        if errText then
            notify("Plant: " .. tostring(errText), THEME.Amber)
        end
        return false
    end

    local function separationExitCFrame()
        local world = workspace:FindFirstChild("World")
        local areas = world and world:FindFirstChild("Areas")
        local sep = areas and areas:FindFirstChild("SeparationLine")
        if sep and sep:IsA("BasePart") then
            local root = characterRoot()
            local groundY = root and root.Position.Y or sep.Position.Y
            local exitPos = sep.Position - sep.CFrame.LookVector * 6
            exitPos = Vector3.new(exitPos.X, groundY, exitPos.Z)
            return CFrame.new(exitPos)
        end
        return nil
    end

    local function deliverCarriedEgg()
        leaveTreadmillIfNeeded()
        local plot = localPlot()
        local exitCf = separationExitCFrame()
        if exitCf and not walkToCFrame(exitCf, 25) then
            return false
        end
        local targetCFrame = (plot.CenterPoint and plot.CenterPoint.CFrame) or plot.RespawnPointCFrame
        if not targetCFrame then
            return false
        end
        if not walkToCFrame(targetCFrame, 30) then
            return false
        end
        for _ = 1, 12 do
            task.wait(0.12)
            local carry = EggState.ReadCarryState() or {}
            if not carry.IsCarrying then
                nextOwnedSync = 0
                pcall(EggState.SyncOwnedEggs)
                return true
            end
        end
        return false
    end

    local function nearestFieldEgg()
        local snapshot = EggState.ReadFieldEggs()
        local root = characterRoot()
        local best, bestDistance
        for _, record in ipairs(snapshot and snapshot.Records or {}) do
            local cf = record.BottomCFrame or record.BoundsCFrame
            if (record.State == "Slot" or record.State == "Dropped") and cf then
                local distance = 0
                if root then
                    distance = (cf.Position - root.Position).Magnitude
                end
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = record, distance
                end
            end
        end
        return best
    end

    Backends.SAE.warmup = function()
        pcall(ensureModules)
        pcall(syncAntiCheat)
        if EggState then
            pcall(EggState.SyncOwnedEggs)
            pcall(EggState.SyncFieldEggs)
        end
    end

    Backends.SAE.farmStep = function()
        if stopped then return false end
        ensureModules()
        leaveTreadmillIfNeeded()
        unequipBlockingTools()
        local carry = EggState.ReadCarryState() or {}
        if carry.IsCarrying then
            return deliverCarriedEgg()
        end
        local now = os.clock()
        local records = ownedEggs(true)
        for uid, record in pairs(records) do
            if record.Placement == nil and now >= (plantSkipUntil[uid] or 0) then
                if plantOwnedEgg(uid) then
                    return true
                end
            end
        end
        if now >= runtime.nextSync then
            runtime.nextSync = now + 3.0
            pcall(EggState.SyncFieldEggs)
        end
        local field = nearestFieldEgg()
        if not field then
            pcall(EggState.SyncFieldEggs)
            field = nearestFieldEgg()
            if not field then
                return false
            end
        end
        local fieldCf = field.BottomCFrame or field.BoundsCFrame
        if not fieldCf then
            return false
        end
        if not walkToCFrame(fieldCf, 35) then
            return false
        end
        task.wait(0.15)
        local firstAreaKey
        if AreaEggSlotIdentity and field.Uid and AreaEggSlotIdentity.LooksLikeFirstAreaUid(field.Uid) then
            firstAreaKey = AreaEggSlotIdentity.SlotKey(field.AreaId, field.NestId)
        end
        local carried, carryError = EggState.CarryFieldEgg(field.Uid, firstAreaKey)
        if carried or (EggState.ReadCarryState() or {}).IsCarrying then
            return deliverCarriedEgg()
        end
        if carryError then
            notify("Carry: " .. tostring(carryError), THEME.Amber)
        end
        return false
    end

    Backends.SAE.hatchStep = function()
        if stopped then return false end
        ensureModules()
        local now = os.clock()
        if now >= nextHatchSync then
            nextHatchSync = now + 1.5
            pcall(EggState.SyncOwnedEggs)
        end
        local records = ownedEggs(false)
        for uid in pairs(records) do
            if not pendingFinish[uid] and now >= (hatchSkipUntil[uid] or 0) and EggState.IsReadyToHatch(uid) then
                if PlacedEggRenderer and type(PlacedEggRenderer.ActivateLocalEgg) == "function" then
                    local okAct, activated, activateError = pcall(PlacedEggRenderer.ActivateLocalEgg, uid)
                    if okAct and activated == true then
                        pendingFinish[uid] = true
                        task.delay(6.0, function()
                            pendingFinish[uid] = nil
                        end)
                        return true
                    end
                    hatchSkipUntil[uid] = now + 1.0
                    if not okAct or activateError then
                        notify("Hatch: " .. tostring(activateError or activated), THEME.Danger)
                    end
                    if type(PlacedEggRenderer.Refresh) == "function" then
                        pcall(PlacedEggRenderer.Refresh)
                    end
                else
                    local began, errorText, result = EggState.BeginHatch(uid)
                    if began then
                        pendingFinish[uid] = true
                        local delay = result == "MechaUpgraded" and 5.0 or 1.1
                        task.delay(delay, function()
                            if not stopped then
                                pcall(EggState.FinishHatch, uid)
                                if PlacedEggRenderer and type(PlacedEggRenderer.Refresh) == "function" then
                                    pcall(PlacedEggRenderer.Refresh)
                                end
                            end
                            pendingFinish[uid] = nil
                        end)
                        return true
                    end
                    hatchSkipUntil[uid] = now + 2.0
                    if errorText then
                        notify(errorText, THEME.Danger)
                    end
                end
            end
        end
        return false
    end

    Backends.SAE.trainingStep = function()
        if stopped then return false end
        ensureModules()
        local plot = localPlot()
        local target = firstDescendant(plot.PlotFolder, "TreadmillBottom")
        local cframe = instanceCFrame(target)
        assert(cframe, "TreadmillBottom is missing")
        if not walkToCFrame(cframe, 25) then
            return false
        end
        local treadmill = Remotes.Treadmill
        assert(treadmill and treadmill.AskWearStill, "Treadmill remote is missing")
        local ok = invokeServer(treadmill.AskWearStill) == true
        if ok then
            onTreadmill = true
        end
        return ok
    end

    Backends.SAE.treadmillStep = function()
        if stopped then return false end
        ensureModules()
        local data = profile()
        if not data then return false end
        local level = tonumber(data.TreadmillUpgradeLevel) or 1
        local nextConfig = Treadmills.GetByUpgradeLevel(level + 1)
        if not nextConfig then return false end
        local cash = cashValue()
        local cost = tonumber(nextConfig.Price) or tonumber(nextConfig.Cost) or math.huge
        if cash - cost < state.economy.reserve then return false end
        local remote = Remotes.Treadmill and Remotes.Treadmill.AskTierRaise
        return invokeServer(remote, nextConfig._id) == true
    end

    local function selectedTrail()
        local selected = state.economy.trail
        if selected == "None" then return nil end
        for id, definition in pairs(Trails and Trails.Directory or {}) do
            if id == selected or definition.DisplayName == selected then
                return id, definition
            end
        end
        return nil
    end

    Backends.SAE.economyStep = function(force)
        if stopped or (not force and not state.economy.running) then return false end
        ensureModules()
        local data = profile()
        if not data then return false end
        if state.economy.upgradeSlots and Bases and Bases.BASES and Bases.GetCost then
            local level = tonumber(data.BaseUpgradeLevel) or 0
            if Bases.BASES[level + 1] then
                local ok, cost = pcall(Bases.GetCost, LocalPlayer, level + 1)
                if ok and cashValue() - (tonumber(cost) or math.huge) >= state.economy.reserve then
                    if BaseUpgrade and type(BaseUpgrade.PurchaseNextTier) == "function" then
                        local okUp, queued = pcall(BaseUpgrade.PurchaseNextTier)
                        return okUp and queued == true
                    end
                end
            end
        end
        if state.economy.autoBuyTrail and Trails then
            local id, definition = selectedTrail()
            if id and definition then
                local inventory = data.TrailInventory or {}
                local equipped = data.EquippedTrail or syncWornTrail()
                local trailwear = Remotes.Trailwear
                if not inventory[id] and equipped ~= id then
                    local price = tonumber(definition.Price) or math.huge
                    if cashValue() - price >= state.economy.reserve and trailwear and trailwear.AskPurchase then
                        local bought = invokeServer(trailwear.AskPurchase, id)
                        if bought == true then
                            wornTrailId = id
                            return true
                        end
                    end
                elseif inventory[id] and equipped ~= id and trailwear and trailwear.AskChoose then
                    local chosen = invokeServer(trailwear.AskChoose, id)
                    if chosen == true then
                        wornTrailId = id
                        return true
                    end
                end
            end
        end
        return false
    end

    Backends.SAE.equipBest = function()
        if stopped or os.clock() < nextWearBest then return false end
        nextWearBest = os.clock() + 5.5
        ensureModules()
        local haul = Remotes.Haul
        if not haul or not haul.WearBest then return false end
        return invokeServer(haul.WearBest) == true
    end

    Backends.SAE.collectEarnings = function()
        if stopped then return false end
        ensureModules()
        local away = Remotes.AwayEarnings
        if not away or not away.FetchSummary or not away.AskCollect then return false end
        local summary = invokeServer(away.FetchSummary)
        if type(summary) ~= "table" then
            return false
        end
        local claimable = math.max(tonumber(summary.TotalAmount) or 0, 0)
        if claimable < 5 then
            return false
        end
        return invokeServer(away.AskCollect, { Kind = "Claim" }) == true
    end

    Backends.SAE.claimIndex = function()
        if stopped then return false end
        ensureModules()
        local codex = Remotes.Codex
        if not codex or not codex.AskRedeemAll then return false end
        return invokeServer(codex.AskRedeemAll) == true
    end

    Backends.SAE.sellEveryPet = function()
        if stopped or not state.selling.explicit or not state.selling.confirmBulk then return false end
        if string.upper(state.selling.bulkPhrase or "") ~= "SELL ALL SATCHEL" then return false end
        ensureModules()
        local petSatchel = Remotes.PetSatchel
        if not petSatchel then return false end
        local data = profile()
        local inventory = data and data.Inventory
        if type(inventory) ~= "table" then return false end
        local equippedSet = {}
        for _, eqUid in ipairs(data.EquippedAssets or {}) do
            equippedSet[eqUid] = true
        end
        local sellUids = {}
        for uid, rawItem in pairs(inventory) do
            if not equippedSet[uid] then
                local itemData = rawItem
                if AssetItems and type(AssetItems.Decode) == "function" then
                    local okDec, decoded = pcall(AssetItems.Decode, rawItem)
                    if okDec and type(decoded) == "table" then
                        itemData = decoded
                    end
                end
                if type(itemData) ~= "table" or (itemData.IsFavorite ~= true and itemData.InFuse ~= true) then
                    sellUids[#sellUids + 1] = uid
                end
            end
        end
        if #sellUids == 0 then
            return false
        end
        if petSatchel.SellEveryPet then
            return fireServer(petSatchel.SellEveryPet, sellUids)
        end
        if petSatchel.SellSelection then
            local sent = false
            for i = 1, #sellUids, 512 do
                local batch = {}
                local last = math.min(i + 511, #sellUids)
                table.move(sellUids, i, last, 1, batch)
                sent = fireServer(petSatchel.SellSelection, { Assets = batch, Eggs = {} }) or sent
            end
            return sent
        end
        return false
    end

    Backends.SAE.sellStep = function(rarityEnabled)
        if stopped or not state.selling.explicit or not state.selling.autoSell then return false end
        ensureModules()
        local haul = Remotes.Haul
        if not haul or not haul.WriteAutoSell or not haul.FetchAutoSell then return false end
        local wanted = {}
        for _, id in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
            if rarityEnabled(id) then
                wanted[id] = true
            end
        end
        local current = invokeServer(haul.FetchAutoSell) or {}
        local changed = false
        for id in pairs(wanted) do
            if current[id] ~= true then changed = true end
        end
        for id, value in pairs(current) do
            if value == true and not wanted[id] then changed = true end
        end
        if not changed then return false end
        return invokeServer(haul.WriteAutoSell, wanted) == true
    end

    Backends.SAE.stop = function()
        stopped = true
        pendingFinish = {}
        leaveTreadmillIfNeeded()
    end
end

-- ============================================================================
-- PS99 Fallback Backend (for standalone Stehp-Hub usage)
-- ============================================================================
local ensurePs99Engine
local engineCall

Backends.PS99 = finishBackend({
    name = "Pet Sim 99",
    key = "ps99",
    supportsSelling = false,
    supportsTrails = false,
    teleports = function()
        return {
            "Spawn",
            "Best Farm",
            "Best World",
            "Farm Island",
            "Rank Rewards",
        }
    end,
    trails = function()
        return { "None" }
    end,
    teleport = function(destination)
        local engine = ensurePs99Engine()
        if not engine then return false end
        if destination == "Best Farm" then
            return engineCall(engine, "TeleportToFarm") ~= nil
        elseif destination == "Best World" then
            return engineCall(engine, "TeleportBestWorld") ~= nil
        elseif destination == "Farm Island" then
            return engineCall(engine, "TeleportIsland") ~= nil
        elseif destination == "Rank Rewards" then
            return engineCall(engine, "ClaimRankRewards") ~= nil
        elseif destination == "Spawn" then
            local spawn = workspace:FindFirstChild("SpawnLocation")
            local cframe = instanceCFrame(spawn)
            return cframe ~= nil and teleportToCFrame(cframe * CFrame.new(0, 4, 0)) or false
        end
        return false
    end,
})

do
    local engine
    local engineLoading = false
    local lastEnabled = {}
    local farmTicks = 0
    local stopped = false

    engineCall = function(target, method, ...)
        if not target or type(target[method]) ~= "function" then return nil end
        local ok, result = pcall(target[method], target, ...)
        if ok then return result end
        return nil
    end

    ensurePs99Engine = function()
        if stopped then return nil end
        if engine then return engine end
        if engineLoading then return nil end
        if type(loadstring) ~= "function" or type(game.HttpGet) ~= "function" then
            notify("PS99 engine loader is unavailable", THEME.Danger)
            return nil
        end
        engineLoading = true
        local ok, loaded = pcall(function()
            local source = game:HttpGet(PS99_ENGINE_URL)
            local chunk, compileError = loadstring(source, "Stehp-Hub/PS99")
            if not chunk then error(compileError, 0) end
            return chunk()
        end)
        engineLoading = false
        if not ok or type(loaded) ~= "table" then
            notify("PS99 engine failed to load", THEME.Danger)
            return nil
        end
        engine = loaded
        engineCall(engine, "SetConfig", "TapRate", 60)
        engineCall(engine, "SetConfig", "FarmTapRate", 90)
        engineCall(engine, "SetConfig", "EggMaxHatch", 100)
        return engine
    end

    local function setEngine(key, value)
        local target = ensurePs99Engine()
        if not target or lastEnabled[key] == value then return false end
        local result = engineCall(target, "SetEnabled", key, value)
        if result == true then
            lastEnabled[key] = value
            return true
        end
        return false
    end

    local function ps99Profile()
        local save = safeRequire(remoteAt("Library/Client/Save"))
        if not save or type(save.Get) ~= "function" then return nil end
        local ok, data = pcall(save.Get, save, LocalPlayer)
        if ok then return data end
        return nil
    end

    local function ps99Cash()
        local data = ps99Profile()
        if not data then return nil end
        local direct = tonumber(data.Coins) or tonumber(data.Cash)
        if direct then return direct end
        local inventory = data.Inventory and data.Inventory.Currency
        if type(inventory) == "table" then
            for _, entry in pairs(inventory) do
                if type(entry) == "table" and entry.id == "Coins" then
                    return tonumber(entry._am) or tonumber(entry.amount) or 0
                end
            end
        end
        return nil
    end

    local function cashAboveReserve()
        local cash = ps99Cash()
        return cash == nil or cash > state.economy.reserve
    end

    Backends.PS99.farmStep = function()
        if stopped then return false end
        local target = ensurePs99Engine()
        if not target then return false end
        setEngine("farm", true)
        setEngine("petSpeed", true)
        setEngine("vacuum", true)
        setEngine("tap", false)
        setEngine("legitTap", false)
        farmTicks = farmTicks + 1
        if farmTicks >= 8 then
            farmTicks = 0
            return true
        end
        return false
    end

    Backends.PS99.hatchStep = function()
        return setEngine("autoEgg", state.farm.hatch)
    end

    Backends.PS99.trainingStep = function()
        if stopped then return false end
        setEngine("farm", false)
        setEngine("petSpeed", false)
        setEngine("vacuum", false)
        setEngine("tap", true)
        setEngine("legitTap", true)
        return true
    end

    Backends.PS99.treadmillStep = function()
        if not cashAboveReserve() then
            setEngine("autoBuyPetSlots", false)
            return false
        end
        return setEngine("autoBuyPetSlots", true)
    end

    Backends.PS99.economyStep = function(force)
        if stopped or (not force and not state.economy.running) then return false end
        local allowed = cashAboveReserve()
        local changed = false
        changed = setEngine("autoBuyEggSlots", allowed and state.economy.upgradeSlots) or changed
        changed = setEngine("autoBuyUpgrades", allowed and state.economy.upgradeSlots) or changed
        return changed
    end

    Backends.PS99.equipBest = function()
        return setEngine("autoEquipEnchant", true)
    end

    Backends.PS99.collectEarnings = function()
        local changed = false
        changed = setEngine("autoMailClaim", true) or changed
        changed = setEngine("autoFreeGifts", true) or changed
        changed = setEngine("autoOpenChests", true) or changed
        changed = setEngine("autoKeys", true) or changed
        changed = setEngine("autoGiftBags", true) or changed
        return changed
    end

    Backends.PS99.claimIndex = function()
        local target = ensurePs99Engine()
        return target ~= nil and engineCall(target, "ClaimRankRewards") ~= nil or false
    end

    Backends.PS99.sellEveryPet = function()
        return false
    end

    Backends.PS99.sellStep = function()
        return false
    end

    Backends.PS99.sync = function()
        if stopped then return false end
        local farming = runtime.mode == "farm" and state.farm.smart
        local training = runtime.mode == "training"
        local buying = cashAboveReserve()
        local desired = {
            farm = farming,
            petSpeed = farming,
            vacuum = farming,
            tap = training,
            legitTap = training,
            autoEgg = state.farm.hatch,
            autoBuyPetSlots = state.farm.treadmill and buying,
            autoBuyEggSlots = state.economy.running and state.economy.upgradeSlots and buying,
            autoBuyUpgrades = state.economy.running and state.economy.upgradeSlots and buying,
            autoEquipEnchant = state.economy.autoEquip,
            autoMailClaim = state.economy.autoCollect,
            autoFreeGifts = state.economy.autoCollect,
            autoOpenChests = state.economy.autoCollect,
            autoKeys = state.economy.autoCollect,
            autoGiftBags = state.economy.autoCollect,
        }
        local active = false
        for _, value in pairs(desired) do
            active = active or value == true
        end
        if not active then
            if engine then
                engineCall(engine, "AllOff")
                lastEnabled = {}
            end
            return false
        end
        local changed = false
        for key, value in pairs(desired) do
            changed = setEngine(key, value) or changed
        end
        return changed
    end

    Backends.PS99.stop = function()
        stopped = true
        if engine then
            engineCall(engine, "Stop")
        end
        engine = nil
        lastEnabled = {}
    end
end

-- ============================================================================
-- Pet Sim 99 StephUI 2.0 Interface Builder for Steal an Egg
-- ============================================================================
local function buildUI(backend)
    local guiParent = getGuiParent()
    do
        local containers = { guiParent }
        local okCore = pcall(function() return CoreGui.Name end)
        if okCore and CoreGui ~= guiParent then containers[#containers + 1] = CoreGui end
        local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if pg and pg ~= guiParent then containers[#containers + 1] = pg end
        for _, container in ipairs(containers) do
            for _, name in ipairs({ "StephHUB_UI", HUB_NAME }) do
                for _, child in ipairs(container:GetChildren()) do
                    if child.Name == name then
                        pcall(function() child:Destroy() end)
                    end
                end
            end
        end
    end

    gui = make("ScreenGui", {
        Name = "StephHUB_UI",
        Enabled = false,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 500,
    }, guiParent)

    mainFrame = make("Frame", {
        Name = "MainWindow",
        Size = UDim2.fromOffset(720, 440),
        Position = UDim2.new(0.5, -360, 0.5, -220),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, gui)
    make("UICorner", { CornerRadius = UDim.new(0, 10) }, mainFrame)
    make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, mainFrame)
    uiScale = make("UIScale", { Scale = state.settings.uiScale }, mainFrame)

    -- Topbar (Exact Pet Sim 99 layout)
    local topbar = make("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = THEME.Sidebar,
        BorderSizePixel = 0,
        Active = true,
    }, mainFrame)
    make("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
    }, topbar)

    make("TextLabel", {
        Size = UDim2.new(1, -120, 1, 0),
        Position = UDim2.fromOffset(16, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "Steph HUB  -  " .. (gameKey == "sae" and "Steal an Egg" or "PS99"),
        TextColor3 = THEME.Text,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, topbar)

    make("TextLabel", {
        Size = UDim2.fromOffset(180, 42),
        Position = UDim2.new(1, -240, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = "RightControl: Hide",
        TextColor3 = THEME.TextDim,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, topbar)

    local minBtn = make("TextButton", {
        Size = UDim2.fromOffset(28, 24),
        Position = UDim2.new(1, -50, 0.5, -12),
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "-",
        TextColor3 = THEME.TextMuted,
        TextSize = 14,
        AutoButtonColor = true,
    }, topbar)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, minBtn)

    do
        local dragging, dragStart, startPos = false, nil, nil
        track(topbar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end))
        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))
    end

    local minimized = false
    track(minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        local targetSize = minimized and UDim2.fromOffset(720, 42) or UDim2.fromOffset(720, 440)
        minBtn.Text = minimized and "+" or "-"
        TweenService:Create(mainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = targetSize,
        }):Play()
    end))

    track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == TOGGLE_KEY or input.KeyCode == TOGGLE_KEY_ALT then
            if gui and gui.Enabled then
                mainFrame.Visible = not mainFrame.Visible
            elseif gui then
                gui.Enabled = true
                mainFrame.Visible = true
            end
        end
    end))

    -- Body & Sidebar (Exact Pet Sim 99 StephUI layout)
    local body = make("Frame", {
        Size = UDim2.new(1, 0, 1, -42),
        Position = UDim2.fromOffset(0, 42),
        BackgroundTransparency = 1,
    }, mainFrame)

    local sidebar = make("ScrollingFrame", {
        Size = UDim2.new(0, 168, 1, 0),
        BackgroundColor3 = THEME.Sidebar,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, body)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, sidebar)
    make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }, sidebar)
    make("Frame", {
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.fromOffset(168, 0),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
    }, body)

    local contentHolder = make("Frame", {
        Size = UDim2.new(1, -169, 1, 0),
        Position = UDim2.fromOffset(169, 0),
        BackgroundTransparency = 1,
    }, body)

    notifHolder = make("Frame", {
        Size = UDim2.fromOffset(290, 320),
        Position = UDim2.new(1, -304, 1, -334),
        BackgroundTransparency = 1,
        ZIndex = 20,
    }, gui)
    make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 8),
    }, notifHolder)

    local tabs = {}
    local activeTab = nil
    local function selectTab(tabEntry)
        if activeTab == tabEntry then return end
        for _, entry in ipairs(tabs) do
            local isThis = entry == tabEntry
            entry.page.Visible = isThis
            TweenService:Create(entry.button, TweenInfo.new(0.14), {
                BackgroundColor3 = isThis and THEME.Raised or THEME.Sidebar,
            }):Play()
            entry.label.TextColor3 = isThis and THEME.Accent or THEME.TextMuted
            entry.indicator.Visible = isThis
        end
        activeTab = tabEntry
    end

    local function CreateTab(name)
        local order = #tabs + 1
        local btn = make("TextButton", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = THEME.Sidebar,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
        }, sidebar)
        make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)

        local indicator = make("Frame", {
            Size = UDim2.new(0, 3, 0, 18),
            Position = UDim2.new(0, 2, 0.5, -9),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Visible = false,
        }, btn)
        make("UICorner", { CornerRadius = UDim.new(0, 2) }, indicator)

        local lbl = make("TextLabel", {
            Size = UDim2.new(1, -16, 1, 0),
            Position = UDim2.fromOffset(12, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            Text = tostring(name or "Tab"),
            TextColor3 = THEME.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, btn)

        local page = make("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = THEME.Stroke,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, contentHolder)
        make("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 14),
            PaddingLeft = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 14),
        }, page)
        make("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, page)

        local entry = { button = btn, label = lbl, indicator = indicator, page = page }
        tabs[order] = entry
        track(btn.MouseButton1Click:Connect(function()
            selectTab(entry)
        end))
        if order == 1 then
            selectTab(entry)
        end

        local tabObj = { page = page }
        local elemOrder = 0
        local function nextOrder()
            elemOrder = elemOrder + 1
            return elemOrder
        end

        function tabObj:CreateSection(sectionName)
            return make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = tostring(sectionName or ""):upper(),
                TextColor3 = THEME.Accent,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = nextOrder(),
            }, page)
        end

        function tabObj:CreateParagraph(titleText, contentText)
            local card = make("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, card)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, card)
            make("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 10),
            }, card)
            make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, card)

            local titleLbl = make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = tostring(titleText or ""),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = 1,
            }, card)

            local bodyLbl = make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                Text = tostring(contentText or ""),
                TextColor3 = THEME.TextMuted,
                TextSize = 11,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = 2,
            }, card)

            return {
                Set = function(newTitle, newContent)
                    if type(newTitle) == "table" then
                        if newTitle.Title ~= nil then titleLbl.Text = tostring(newTitle.Title) end
                        if newTitle.Content ~= nil then bodyLbl.Text = tostring(newTitle.Content) end
                    else
                        if newTitle ~= nil then titleLbl.Text = tostring(newTitle) end
                        if newContent ~= nil then bodyLbl.Text = tostring(newContent) end
                    end
                end,
            }
        end

        function tabObj:CreateButton(label, callback)
            local btnRow = make("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, btnRow)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, btnRow)

            local titleLbl = make("TextLabel", {
                Size = UDim2.new(1, -60, 1, 0),
                Position = UDim2.fromOffset(12, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                Text = tostring(label or "Button"),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, btnRow)

            local badge = make("TextLabel", {
                Size = UDim2.fromOffset(44, 20),
                Position = UDim2.new(1, -54, 0.5, -10),
                BackgroundColor3 = THEME.Raised,
                Font = Enum.Font.GothamBold,
                Text = "RUN",
                TextColor3 = THEME.Accent,
                TextSize = 10,
            }, btnRow)
            make("UICorner", { CornerRadius = UDim.new(0, 4) }, badge)

            track(btnRow.MouseEnter:Connect(function()
                TweenService:Create(btnRow, TweenInfo.new(0.1), { BackgroundColor3 = THEME.SurfaceHover }):Play()
            end))
            track(btnRow.MouseLeave:Connect(function()
                TweenService:Create(btnRow, TweenInfo.new(0.1), { BackgroundColor3 = THEME.Surface }):Play()
            end))
            track(btnRow.MouseButton1Click:Connect(function()
                if type(callback) == "function" then
                    task.spawn(callback)
                end
            end))
            return {
                Button = btnRow,
                SetText = function(newText)
                    titleLbl.Text = tostring(newText or "")
                end,
            }
        end

        function tabObj:CreateToggle(label, path, callback)
            local cur = getPath(state, path) == true
            local row = make("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, row)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, row)

            make("TextLabel", {
                Size = UDim2.new(1, -64, 1, 0),
                Position = UDim2.fromOffset(12, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                Text = tostring(label or "Toggle"),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, row)

            local pill = make("Frame", {
                Size = UDim2.fromOffset(38, 20),
                Position = UDim2.new(1, -50, 0.5, -10),
                BackgroundColor3 = cur and THEME.Accent or THEME.Raised,
                BorderSizePixel = 0,
            }, row)
            make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)

            local knob = make("Frame", {
                Size = UDim2.fromOffset(14, 14),
                Position = cur and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
                BackgroundColor3 = cur and THEME.Bg or THEME.TextMuted,
                BorderSizePixel = 0,
            }, pill)
            make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

            local function apply(val)
                val = val == true
                TweenService:Create(pill, TweenInfo.new(0.14), {
                    BackgroundColor3 = val and THEME.Accent or THEME.Raised,
                }):Play()
                TweenService:Create(knob, TweenInfo.new(0.14), {
                    Position = val and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
                    BackgroundColor3 = val and THEME.Bg or THEME.TextMuted,
                }):Play()
            end

            local function setValue(value, persist)
                value = value == true
                setPath(state, path, value)
                apply(value)
                if callback then
                    pcall(callback, value)
                end
                if persist ~= false then
                    saveConfig()
                end
            end

            track(row.MouseButton1Click:Connect(function()
                setValue(getPath(state, path) ~= true)
            end))

            controlMap[path] = { set = setValue, get = function() return getPath(state, path) end }
            return controlMap[path]
        end

        function tabObj:CreateSlider(label, path, minimum, maximum, step, suffix, onChange)
            suffix = tostring(suffix or "")
            local val = math.clamp(tonumber(getPath(state, path)) or minimum, minimum, maximum)

            local card = make("Frame", {
                Size = UDim2.new(1, 0, 0, 48),
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, card)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, card)

            make("TextLabel", {
                Size = UDim2.new(1, -90, 0, 20),
                Position = UDim2.fromOffset(12, 5),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                Text = tostring(label or "Slider"),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, card)

            local valLbl = make("TextLabel", {
                Size = UDim2.fromOffset(72, 20),
                Position = UDim2.new(1, -84, 0, 5),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = tostring(val) .. suffix,
                TextColor3 = THEME.Accent,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Right,
            }, card)

            local trackBar = make("Frame", {
                Size = UDim2.new(1, -24, 0, 6),
                Position = UDim2.fromOffset(12, 32),
                BackgroundColor3 = THEME.Raised,
                BorderSizePixel = 0,
            }, card)
            make("UICorner", { CornerRadius = UDim.new(1, 0) }, trackBar)

            local pct = (maximum > minimum) and ((val - minimum) / (maximum - minimum)) or 0
            local fillBar = make("Frame", {
                Size = UDim2.new(pct, 0, 1, 0),
                BackgroundColor3 = THEME.Accent,
                BorderSizePixel = 0,
            }, trackBar)
            make("UICorner", { CornerRadius = UDim.new(1, 0) }, fillBar)

            local function normalize(n)
                n = tonumber(n) or minimum
                local stepped = minimum + math.floor(((n - minimum) / step) + 0.5) * step
                stepped = math.clamp(stepped, minimum, maximum)
                if step < 1 then
                    local decimals = math.max(1, math.ceil(-math.log10(step)))
                    local mul = 10 ^ decimals
                    stepped = math.floor(stepped * mul + 0.5) / mul
                end
                return stepped
            end

            local function apply(v)
                v = normalize(v)
                local p = (maximum > minimum) and ((v - minimum) / (maximum - minimum)) or 0
                fillBar.Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0)
                valLbl.Text = tostring(v) .. suffix
            end

            local function setValue(v, persist)
                v = normalize(v)
                setPath(state, path, v)
                apply(v)
                if onChange then
                    pcall(onChange, v)
                end
                if persist ~= false then
                    saveConfig()
                end
            end

            local sliding = false
            local function updateFromInput(input)
                local x = input.Position.X - trackBar.AbsolutePosition.X
                local w = math.max(trackBar.AbsoluteSize.X, 1)
                local alpha = math.clamp(x / w, 0, 1)
                setValue(minimum + (maximum - minimum) * alpha)
            end

            track(trackBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    updateFromInput(input)
                end
            end))
            track(UserInputService.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    updateFromInput(input)
                end
            end))
            track(UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end))

            apply(val)
            controlMap[path] = { set = setValue, get = function() return getPath(state, path) end }
            return controlMap[path]
        end

        function tabObj:CreateDropdown(label, path, options, onChange)
            options = type(options) == "table" and options or { "None" }
            local current = tostring(getPath(state, path) or options[1] or "None")

            local container = make("Frame", {
                Size = UDim2.new(1, 0, 0, 34),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, container)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, container)
            make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, container)

            local header = make("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundTransparency = 1,
                Text = "",
                LayoutOrder = 1,
            }, container)

            make("TextLabel", {
                Size = UDim2.new(0.55, -12, 1, 0),
                Position = UDim2.fromOffset(12, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                Text = tostring(label or "Dropdown"),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, header)

            local curLbl = make("TextLabel", {
                Size = UDim2.new(0.45, -24, 1, 0),
                Position = UDim2.new(0.55, 0, 0, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = tostring(current) .. "  v",
                TextColor3 = THEME.Accent,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, header)

            local listFrame = make("ScrollingFrame", {
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = THEME.Sidebar,
                BorderSizePixel = 0,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = THEME.Stroke,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                Visible = false,
                LayoutOrder = 2,
            }, container)
            make("UIPadding", {
                PaddingTop = UDim.new(0, 4),
                PaddingBottom = UDim.new(0, 4),
                PaddingLeft = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 6),
            }, listFrame)
            make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, listFrame)

            local open = false
            local rebuildList

            local function setValue(value, persist)
                current = tostring(value or options[1] or "None")
                setPath(state, path, current)
                curLbl.Text = current .. (open and "  ^" or "  v")
                if rebuildList then rebuildList() end
                if onChange then
                    pcall(onChange, current)
                end
                if persist ~= false then
                    saveConfig()
                end
            end

            rebuildList = function(newOptions)
                if type(newOptions) == "table" then
                    options = newOptions
                end
                for _, child in ipairs(listFrame:GetChildren()) do
                    if child:IsA("TextButton") then child:Destroy() end
                end
                for i, opt in ipairs(options) do
                    local optStr = tostring(opt)
                    local itemBtn = make("TextButton", {
                        Size = UDim2.new(1, 0, 0, 26),
                        BackgroundColor3 = optStr == tostring(current) and THEME.Raised or THEME.Surface,
                        BorderSizePixel = 0,
                        Font = Enum.Font.Gotham,
                        Text = "  " .. optStr,
                        TextColor3 = optStr == tostring(current) and THEME.Accent or THEME.Text,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        LayoutOrder = i,
                    }, listFrame)
                    make("UICorner", { CornerRadius = UDim.new(0, 5) }, itemBtn)
                    track(itemBtn.MouseButton1Click:Connect(function()
                        open = false
                        listFrame.Visible = false
                        listFrame.Size = UDim2.new(1, 0, 0, 0)
                        setValue(optStr)
                    end))
                end
            end

            rebuildList()

            track(header.MouseButton1Click:Connect(function()
                open = not open
                listFrame.Visible = open
                local h = math.min(#options * 29 + 8, 160)
                listFrame.Size = open and UDim2.new(1, 0, 0, h) or UDim2.new(1, 0, 0, 0)
                curLbl.Text = tostring(current) .. (open and "  ^" or "  v")
            end))

            controlMap[path] = {
                set = setValue,
                get = function() return getPath(state, path) end,
                setOptions = rebuildList,
            }
            return controlMap[path]
        end

        function tabObj:CreateInput(label, path, placeholder, numeric)
            local row = make("Frame", {
                Size = UDim2.new(1, 0, 0, 38),
                BackgroundColor3 = THEME.Surface,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(),
            }, page)
            make("UICorner", { CornerRadius = UDim.new(0, 7) }, row)
            make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, row)

            make("TextLabel", {
                Size = UDim2.new(0.55, -12, 1, 0),
                Position = UDim2.fromOffset(12, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                Text = tostring(label or "Input"),
                TextColor3 = THEME.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, row)

            local box = make("TextBox", {
                Size = UDim2.new(0.42, -14, 0, 26),
                Position = UDim2.new(0.58, 0, 0.5, -13),
                BackgroundColor3 = THEME.Raised,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamMedium,
                Text = tostring(getPath(state, path) or ""),
                PlaceholderText = tostring(placeholder or ""),
                PlaceholderColor3 = THEME.TextDim,
                TextColor3 = THEME.Accent,
                TextSize = 11,
                ClearTextOnFocus = false,
            }, row)
            make("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
            make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

            local function setValue(value, persist)
                if numeric then
                    value = math.max(tonumber(value) or 0, 0)
                else
                    value = tostring(value or "")
                end
                setPath(state, path, value)
                box.Text = tostring(value)
                if persist ~= false then
                    saveConfig()
                end
            end

            track(box.FocusLost:Connect(function()
                setValue(box.Text)
            end))

            controlMap[path] = { set = setValue, get = function() return getPath(state, path) end }
            return controlMap[path]
        end

        return tabObj
    end

    -- ========================================================================
    -- Build Tabs (Exact Pet Sim 99 StephUI style)
    -- ========================================================================
    local farmTab = CreateTab("Farm")
    farmTab:CreateSection("Egg Stealing & Hatching (Walk-to-Egg)")
    farmTab:CreateParagraph(
        "Walk-to-Egg Engine",
        "All egg movement uses pathfind + SeparationLine crossing waypoints + stuck jump recovery instead of instant teleport."
    )
    farmTab:CreateToggle("Enable Smart Egg Farm (Walk to Egg)", "farm.smart", function(value)
        if value then
            runtime.mode = "farm"
            runtime.runsSinceTraining = 0
            notify("Smart Egg Farm started (Walk-to-Egg active)", THEME.Success)
        else
            runtime.mode = state.training.only and "training" or "idle"
        end
    end)
    farmTab:CreateToggle("Auto-Hatch Ready Eggs", "farm.hatch")
    farmTab:CreateToggle(
        backend.key == "ps99" and "Auto-Upgrade Pet Slots (Cash)" or "Auto-Upgrade Treadmill (Cash)",
        "farm.treadmill"
    )
    farmTab:CreateSection("Quick Egg Walk Actions")
    farmTab:CreateButton("Walk to Nearest Field Egg", function()
        task.spawn(function()
            notify("Walking to nearest field egg...", THEME.Accent)
            local ok = backend.teleport("Nearest Field Egg")
            if ok then
                notify("Arrived at nearest field egg", THEME.Success)
            else
                notify("Could not reach field egg", THEME.Amber)
            end
        end)
    end)
    farmTab:CreateButton("Walk to My Egg Area", function()
        task.spawn(function()
            notify("Walking to your egg area...", THEME.Accent)
            local ok = backend.teleport("My Egg Area")
            if ok then
                notify("Arrived at your egg area", THEME.Success)
            else
                notify("Could not reach egg area", THEME.Amber)
            end
        end)
    end)

    -- Training Tab
    local trainTab = CreateTab("Training")
    trainTab:CreateSection("Treadmill Speed Progression")
    trainTab:CreateToggle("Train Between Egg Runs", "training.between")
    trainTab:CreateToggle("Training Only Mode", "training.only", function(value)
        if value then
            runtime.mode = "training"
            runtime.trainingUntil = os.clock() + state.training.seconds
        else
            runtime.mode = state.farm.smart and "farm" or "idle"
        end
    end)
    trainTab:CreateSlider("Seconds Per Training Session", "training.seconds", 1, 60, 1, "s")
    trainTab:CreateSlider("Farm Runs Between Training", "training.farmRuns", 1, 20, 1, " runs")
    trainTab:CreateButton("Stop Farm & Training", function()
        state.farm.smart = false
        state.training.only = false
        state.training.between = false
        runtime.mode = "idle"
        runtime.runsSinceTraining = 0
        refreshControl("farm.smart")
        refreshControl("training.only")
        refreshControl("training.between")
        saveConfig()
        notify("Farm and training stopped", THEME.Amber)
    end)

    -- Anti-Cheat Tab
    local acTab = CreateTab("Anti-Cheat")
    acTab:CreateSection("Steal an Egg Anti-Cheat Bypass")
    anticheatParagraph = acTab:CreateParagraph(
        "Protection Status",
        "Guard Strike Block: ON | Speed Pushback Bypass: ON | Obby Anti-TP Disarm: ON | Anti-Ragdoll & Raygun Stun: ON"
    )
    acTab:CreateToggle("Master Anti-Cheat Protection", "anticheat.enabled", function()
        pcall(syncAntiCheat)
    end)
    acTab:CreateToggle("Block Forest Guard Strike & Egg Confiscation", "anticheat.blockGuardStrike", function()
        pcall(syncAntiCheat)
    end)
    acTab:CreateToggle("Bypass High-Speed Downward Pushback", "anticheat.bypassPushback", function()
        pcall(syncAntiCheat)
    end)
    acTab:CreateToggle("Disarm Obby Anti-Teleport Lagback / Kill", "anticheat.bypassAntiTp", function()
        pcall(syncAntiCheat)
    end)
    acTab:CreateToggle("Anti-Ragdoll Limp & Raygun Stun Lock", "anticheat.antiRagdollStun", function()
        pcall(syncAntiCheat)
    end)
    acTab:CreateToggle("Spoof Idle Telemetry & Block AFK Server Hop", "anticheat.blockIdleTelemetry", function()
        pcall(syncAntiCheat)
    end)

    -- Economy Tab
    local ecoTab = CreateTab("Economy")
    ecoTab:CreateSection("Cash Upgrades & Gear")
    ecoTab:CreateToggle(
        backend.key == "ps99" and "Auto-Upgrade Pet & Egg Slots (Cash)" or "Auto-Upgrade Base Slots (Cash)",
        "economy.upgradeSlots"
    )
    ecoTab:CreateToggle("Auto Equip Best Pets", "economy.autoEquip")
    ecoTab:CreateButton("Equip Best Pets Now", function()
        local ok, err = pcall(backend.equipBest)
        if ok then
            notify("Best pets equipped", THEME.Success)
        else
            notify("Equip failed: " .. tostring(err), THEME.Danger)
        end
    end)
    if backend.supportsTrails ~= false then
        ecoTab:CreateDropdown("Cash Trail To Buy", "economy.trail", backend.trails and backend.trails() or { "None" })
        ecoTab:CreateToggle("Auto-Buy Selected Trail (Cash)", "economy.autoBuyTrail")
    end
    ecoTab:CreateInput("Keep Minimum Cash Reserve", "economy.reserve", "0", true)
    ecoTab:CreateToggle("Run Selected Auto Economy Actions", "economy.running", function(val)
        if val then
            pcall(backend.economyStep, true)
            notify("Economy automation enabled", THEME.Success)
        else
            notify("Economy automation paused", THEME.Amber)
        end
    end)
    ecoTab:CreateSection("Earnings & Codex Rewards")
    ecoTab:CreateToggle("Auto-Collect Offline/Away Earnings", "economy.autoCollect")
    ecoTab:CreateToggle(
        backend.key == "ps99" and "Auto-Claim Rank Rewards" or "Auto-Claim Codex Index Rewards",
        "economy.indexRewards"
    )
    ecoTab:CreateButton("Collect & Claim All Now", function()
        pcall(backend.collectEarnings)
        pcall(backend.claimIndex)
        notify("Collection & index claim sent", THEME.Success)
    end)

    -- Selling Tab
    local sellTab = CreateTab("Selling")
    sellTab:CreateSection("Satchel & Auto-Sell Controls")
    if backend.supportsSelling == false then
        sellTab:CreateParagraph("Not Available", "Pet Sim 99 does not expose a satchel pet sale remote.")
    else
        sellTab:CreateToggle("Explicit Selling Opt-In", "selling.explicit")
        sellTab:CreateToggle("Confirm Manual Bulk Satchel Sale", "selling.confirmBulk")
        sellTab:CreateInput("Bulk Sale Phrase", "selling.bulkPhrase", "SELL ALL SATCHEL", false)
        sellTab:CreateButton("Execute Manual Satchel Sale", function()
            if not state.selling.explicit or not state.selling.confirmBulk then
                notify("Enable both sale confirmations first", THEME.Amber)
                return
            end
            if string.upper(state.selling.bulkPhrase or "") ~= "SELL ALL SATCHEL" then
                notify("Type SELL ALL SATCHEL to confirm", THEME.Amber)
                return
            end
            local ok, result = pcall(backend.sellEveryPet)
            if ok and result ~= false then
                notify("Bulk satchel sale sent", THEME.Success)
            else
                notify("Bulk sale request failed", THEME.Danger)
            end
        end)
        sellTab:CreateSection("Auto-Sell Rarities")
        sellTab:CreateToggle("Auto-Sell New Pets By Rarity", "selling.autoSell")
        sellTab:CreateToggle("Sell Future Common", "selling.common")
        sellTab:CreateToggle("Sell Future Uncommon", "selling.uncommon")
        sellTab:CreateToggle("Sell Future Rare", "selling.rare")
        sellTab:CreateToggle("Sell Future Epic", "selling.epic")
        sellTab:CreateToggle("Sell Future Legendary", "selling.legendary")
        sellTab:CreateToggle("Sell Future Mythic", "selling.mythic")
    end

    -- Teleports / Movement Tab
    local teleTab = CreateTab("Teleports")
    teleTab:CreateSection("Locations & Walk-to-Egg Navigation")
    teleTab:CreateToggle("Use Walk-to-Target For Non-Egg Locations", "teleports.walkToEggs")
    local teleportOptions = backend.teleports and backend.teleports() or { "Nearest Field Egg" }
    local teleportDropdown = teleTab:CreateDropdown("Destination", "teleports.selected", teleportOptions)
    teleTab:CreateButton("Go To Selected Location", function()
        local destination = state.teleports.selected
        notify("Moving to " .. tostring(destination) .. "...", THEME.Accent)
        local ok, err = pcall(backend.teleport, destination)
        if ok and err ~= false then
            notify("Reached " .. tostring(destination), THEME.Success)
        else
            notify("Movement failed: " .. tostring(err or "unreachable"), THEME.Danger)
        end
    end)
    teleTab:CreateButton("Refresh Locations", function()
        local opts = backend.teleports and backend.teleports() or { "Nearest Field Egg" }
        if teleportDropdown and teleportDropdown.setOptions then
            teleportDropdown.setOptions(opts)
        end
        notify("Locations refreshed", THEME.Success)
    end)

    -- Settings Tab
    local setTab = CreateTab("Settings")
    setTab:CreateSection("Interface & Runtime")
    setTab:CreateSlider("UI Scale", "settings.uiScale", 0.75, 1.25, 0.05, "x", function(value)
        if uiScale then
            uiScale.Scale = value
        end
    end)
    setTab:CreateToggle("Show Notifications", "settings.notifications")
    setTab:CreateToggle("Anti-AFK Virtual Input", "settings.antiAfk")
    setTab:CreateSection("Configuration File")
    setTab:CreateParagraph("Auto-Save", "Settings auto-save to " .. CONFIG_FILE)
    setTab:CreateButton("Save Config Now", function()
        if flushConfig() then
            notify("Config saved", THEME.Success)
        else
            notify("Config save failed", THEME.Danger)
        end
    end)
    setTab:CreateButton("Reset Config To Defaults", resetConfig)

    -- Status Tab (Same as Pet Sim 99 Status tab)
    local statusTab = CreateTab("Status")
    statusTab:CreateSection("Live Engine Status")
    statusParagraph = statusTab:CreateParagraph(
        "Steph HUB v" .. VERSION .. "  |  " .. (gameKey == "sae" and "Steal an Egg" or "Pet Sim 99"),
        "Mode: Idle\nWalk Engine: Ready\nAnti-Cheat: Active"
    )
    statusTab:CreateSection("Session Controls")
    statusTab:CreateButton("All Features Off", function()
        state.farm.smart = false
        state.farm.hatch = false
        state.farm.treadmill = false
        state.training.only = false
        state.economy.running = false
        runtime.mode = "idle"
        for _, k in ipairs({ "farm.smart", "farm.hatch", "farm.treadmill", "training.only", "economy.running" }) do
            refreshControl(k)
        end
        saveConfig()
        notify("All automation toggles turned off", THEME.Amber)
    end)
    statusTab:CreateButton("Unload Menu", function()
        if cleanupHub then
            cleanupHub()
        end
    end)

    saveConfig()
end

-- ============================================================================
-- Scheduler & Status Loop
-- ============================================================================
local jobBusy = {}
local function runJob(name, interval, callback)
    local now = os.clock()
    local key = "next" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    if jobBusy[name] or now < (runtime[key] or 0) then
        return
    end
    runtime[key] = now + interval
    jobBusy[name] = true
    task.spawn(function()
        local ok, result = pcall(callback)
        jobBusy[name] = false
        if not ok then
            notify(name .. " error: " .. tostring(result), THEME.Danger)
        end
        return result
    end)
end

local function rarityEnabled(rarity)
    rarity = string.lower(tostring(rarity or ""))
    if rarity:find("common", 1, true) then
        return state.selling.common
    elseif rarity:find("uncommon", 1, true) then
        return state.selling.uncommon
    elseif rarity:find("rare", 1, true) then
        return state.selling.rare
    elseif rarity:find("epic", 1, true) then
        return state.selling.epic
    elseif rarity:find("legendary", 1, true) then
        return state.selling.legendary
    elseif rarity:find("mythic", 1, true) then
        return state.selling.mythic
    end
    return false
end

local function startScheduler(backend)
    local heartbeat = RunService.Heartbeat:Connect(function()
        if shuttingDown then return end
        local now = os.clock()
        syncAntiAfk()
        if uiScale then
            uiScale.Scale = state.settings.uiScale
        end

        if state.farm.hatch then
            runJob("hatch", 0.55, function()
                return backend.hatchStep()
            end)
        end
        if state.farm.treadmill then
            runJob("treadmill", 0.8, function()
                return backend.treadmillStep()
            end)
        end

        if state.training.only then
            runtime.mode = "training"
            if runtime.trainingUntil <= now then
                runtime.trainingUntil = now + state.training.seconds
            end
        elseif state.training.between and state.farm.smart then
            if runtime.runsSinceTraining >= state.training.farmRuns and runtime.mode ~= "training" then
                runtime.mode = "training"
                runtime.trainingUntil = now + state.training.seconds
            elseif runtime.mode == "training" and now >= runtime.trainingUntil then
                runtime.mode = "farm"
                runtime.runsSinceTraining = 0
            end
        else
            runtime.mode = state.farm.smart and "farm" or "idle"
        end

        if runtime.mode == "farm" and state.farm.smart then
            runJob("farm", 0.65, function()
                local success = backend.farmStep()
                if success then
                    runtime.runsSinceTraining = runtime.runsSinceTraining + 1
                end
                return success
            end)
        elseif runtime.mode == "training" then
            runJob("training", 0.35, function()
                return backend.trainingStep()
            end)
        end

        if state.economy.running or state.economy.autoCollect then
            runJob("economy", 0.9, function()
                return backend.economyStep(false)
            end)
        end
        if state.economy.autoEquip then
            runJob("equip", 2.5, function()
                return backend.equipBest()
            end)
        end
        if state.economy.autoCollect then
            runJob("collect", 4.0, function()
                return backend.collectEarnings()
            end)
        end
        if state.economy.indexRewards then
            runJob("index", 5.0, function()
                return backend.claimIndex()
            end)
        end
        if state.selling.explicit and state.selling.autoSell then
            runJob("sell", 0.75, function()
                return backend.sellStep(rarityEnabled)
            end)
        end
        if backend.sync then
            runJob("sync", 1.0, function()
                return backend.sync()
            end)
        end

        if now - runtime.lastStatus >= 0.4 then
            runtime.lastStatus = now
            local modeText = "Idle"
            if runtime.mode == "training" then
                modeText = string.format("Training (%.1fs remaining)", math.max(0, runtime.trainingUntil - now))
            elseif runtime.mode == "farm" then
                modeText = string.format("Farming Eggs (%d/%d runs)", runtime.runsSinceTraining, state.training.farmRuns)
            end
            local acSummary = string.format(
                "Master: %s | Guard Strikes Blocked: %d | Stuns Cleared: %d | Idle Spoofed: %d\nLast Event: %s",
                state.anticheat.enabled and "ON" or "OFF",
                runtime.acBlockedStrikes,
                runtime.acCleanedStuns,
                runtime.acBlockedTele,
                tostring(runtime.acLastNote or "Active")
            )
            if anticheatParagraph then
                anticheatParagraph.Set("Protection Status", acSummary)
            end
            if statusParagraph then
                statusParagraph.Set(
                    "Steph HUB v" .. VERSION .. "  |  " .. (gameKey == "sae" and "Steal an Egg" or "Pet Sim 99"),
                    string.format(
                        "Mode: %s\nMovement: %s (Walk-to-Egg)\nAnti-Cheat: %s (Strikes Blocked: %d)",
                        modeText,
                        tostring(runtime.walkStatus or "Idle"),
                        state.anticheat.enabled and "ACTIVE" or "OFF",
                        runtime.acBlockedStrikes
                    )
                )
            end
        end
    end)
    track(heartbeat)
end

local backendKey = gameKey == "sae" and "SAE" or "PS99"
local backend = Backends[backendKey]
assert(backend, HUB_NAME .. ": backend failed to initialize")
finishBackend(backend)
if type(backend.warmup) == "function" then
    pcall(backend.warmup)
end
buildUI(backend)
pcall(syncAntiCheat)
startScheduler(backend)

local function showHub()
    if gui and gui.Parent then
        gui.Enabled = true
        if mainFrame then
            mainFrame.Visible = true
        end
    end
end

local function hideHub()
    if gui and gui.Parent then
        gui.Enabled = false
    end
end

cleanupHub = function()
    shuttingDown = true
    syncAntiAfk()
    pcall(syncAntiCheat)
    flushConfig()
    for _, connection in ipairs(cleanupConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(cleanupConnections)
    if gui then
        pcall(function()
            gui:Destroy()
        end)
        gui = nil
    end
    if backend.stop then
        pcall(backend.stop)
    end
    hubEnv.StehpHubCleanup = nil
end

hubEnv.StehpHubCleanup = cleanupHub

if not hubEnv.__STEPH_DEFER_SHOW then
    showHub()
end

return {
    Show = showHub,
    Hide = hideHub,
    Destroy = cleanupHub,
    Cleanup = cleanupHub,
    Version = VERSION,
    Game = gameKey,
}
