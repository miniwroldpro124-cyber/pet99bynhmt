--!nolint
-- STEPH_COMPONENT: sae_hub 1.3.0
-- Stehp-Hub | Luau / Roblox executor | standalone two-game hub

local VERSION = "1.3.0"
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
local LocalPlayer = Players.LocalPlayer
local hubEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(hubEnv.StehpHubCleanup) == "function" then
    pcall(hubEnv.StehpHubCleanup)
end
local cleanupConnections = {}

local C = {
    bg = Color3.fromRGB(13, 15, 20),
    sidebar = Color3.fromRGB(17, 20, 27),
    card = Color3.fromRGB(22, 26, 35),
    cardAlt = Color3.fromRGB(29, 34, 46),
    accent = Color3.fromRGB(125, 212, 236),
    accentDark = Color3.fromRGB(42, 84, 102),
    text = Color3.fromRGB(232, 237, 244),
    muted = Color3.fromRGB(146, 156, 173),
    line = Color3.fromRGB(44, 51, 68),
    green = Color3.fromRGB(74, 212, 134),
    red = Color3.fromRGB(238, 112, 112),
    amber = Color3.fromRGB(250, 224, 120),
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
    teleports = {
        selected = "Spawn",
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
        antiAfk = false,
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

local function new(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        if key ~= "Parent" then
            object[key] = value
        end
    end
    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function stroke(parent, color, thickness)
    return new("UIStroke", {
        Color = color or C.line,
        Thickness = thickness or 1,
        Transparency = 0.15,
    }, parent)
end

local function tween(object, goal, duration)
    local info = TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(object, info, goal):Play()
end

local Backends = {}
local controlMap = {}
local pages = {}
local navButtons = {}
local currentTab = "Farm"
local searchBox
local statusLabel
local toastLabel
local toastConnection
local gui
local main
local uiScale
local pagesHost
local pageTitle
local pageSubtitle
local refreshPlayers
local buildPages
local economyStartButton
local shuttingDown = false
local syncAntiAfk
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
}

local function notify(message, color)
    if not state.settings.notifications or not toastLabel then
        return
    end
    if toastConnection then
        pcall(task.cancel, toastConnection)
        toastConnection = nil
    end
    toastLabel.Text = tostring(message)
    toastLabel.TextColor3 = color or C.text
    toastLabel.TextTransparency = 0
    toastLabel.Visible = true
    toastConnection = task.delay(2.4, function()
        toastConnection = nil
        if toastLabel then
            tween(toastLabel, { TextTransparency = 1 }, 0.18)
            task.delay(0.2, function()
                if toastLabel and toastLabel.TextTransparency >= 0.95 then
                    toastLabel.Visible = false
                    toastLabel.TextTransparency = 0
                end
            end)
        end
    end)
end

local function registerSearch(tab, row, label)
    if pages[tab] then
        pages[tab].rows[#pages[tab].rows + 1] = { frame = row, label = string.lower(label) }
    end
end

local function addSection(tab, title)
    local page = pages[tab]
    local card = new("Frame", {
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #page.sections + 1,
    }, page.frame)
    corner(card, 10)
    stroke(card)
    local layout = new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 0),
    }, card)
    local heading = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 38),
        Position = UDim2.new(0, 0, 0, 0),
        Text = title,
        TextColor3 = C.text,
        TextSize = 15,
        Font = Enum.Font.GothamSemibold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    }, heading)
    page.sections[#page.sections + 1] = card
    return card
end

local function addRow(parent, height)
    local row = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, height or 46),
        BorderSizePixel = 0,
    }, parent)
    return row
end

local function addToggle(tab, parent, label, path, callback)
    local row = addRow(parent, 48)
    registerSearch(tab, row, label)
    local text = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -74, 1, 0),
        Text = label,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    new("UIPadding", { PaddingLeft = UDim.new(0, 14) }, text)
    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = C.line,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 46, 0, 25),
        Position = UDim2.new(1, -60, 0.5, -12.5),
        Text = "",
    }, row)
    corner(button, 13)
    local knob = new("Frame", {
        BackgroundColor3 = C.text,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 19, 0, 19),
        Position = UDim2.new(0, 3, 0.5, -9.5),
    }, button)
    corner(knob, 10)
    local function apply(value)
        value = value == true
        tween(button, { BackgroundColor3 = value and C.accent or C.line }, 0.14)
        tween(knob, { Position = value and UDim2.new(1, -22, 0.5, -9.5) or UDim2.new(0, 3, 0.5, -9.5) }, 0.14)
    end
    apply(getPath(state, path) == true)
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
    button.MouseButton1Click:Connect(function()
        setValue(getPath(state, path) ~= true)
    end)
    controlMap[path] = { set = setValue, get = function() return getPath(state, path) end }
    return row, setValue
end

local function addSlider(tab, parent, label, path, minimum, maximum, step, formatter, onChange)
    local row = addRow(parent, 62)
    registerSearch(tab, row, label)
    local text = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 0, 24),
        Position = UDim2.new(0, 14, 0, 7),
        Text = label,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local valueLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 62, 0, 24),
        Position = UDim2.new(1, -76, 0, 7),
        Text = "",
        TextColor3 = C.muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
    local track = new("Frame", {
        BackgroundColor3 = C.line,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -28, 0, 6),
        Position = UDim2.new(0, 14, 0, 43),
    }, row)
    corner(track, 3)
    local fill = new("Frame", {
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
    }, track)
    corner(fill, 3)
    local knob = new("Frame", {
        BackgroundColor3 = C.text,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 15, 0, 15),
        Position = UDim2.new(0, 0, 0.5, -7.5),
        ZIndex = 2,
    }, track)
    corner(knob, 8)
    local dragConnection
    local function normalize(value)
        value = tonumber(value) or minimum
        value = math.clamp(value, minimum, maximum)
        local snapped = math.floor((value - minimum) / step + 0.5) * step + minimum
        return math.clamp(snapped, minimum, maximum)
    end
    local function apply(value)
        value = normalize(value)
        local alpha = (value - minimum) / math.max(maximum - minimum, 0.0001)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, -7.5, 0.5, -7.5)
        valueLabel.Text = formatter and formatter(value) or tostring(value)
    end
    local function setValue(value, persist)
        value = normalize(value)
        setPath(state, path, value)
        apply(value)
        if onChange then
            pcall(onChange, value)
        end
        if persist ~= false then
            saveConfig()
        end
    end
    local function updateFromInput(input)
        local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        setValue(minimum + alpha * (maximum - minimum))
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            updateFromInput(input)
            if dragConnection then
                dragConnection:Disconnect()
            end
            dragConnection = UserInputService.InputChanged:Connect(function(changed)
                if changed == input then
                    updateFromInput(changed)
                end
            end)
        end
    end)
    local sliderEnded = UserInputService.InputEnded:Connect(function(input)
        if dragConnection and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragConnection:Disconnect()
            dragConnection = nil
        end
    end)
    cleanupConnections[#cleanupConnections + 1] = sliderEnded
    apply(getPath(state, path))
    controlMap[path] = { set = setValue, get = function() return getPath(state, path) end, apply = apply }
    return row, setValue
end

local function addDropdown(tab, parent, label, path, options, onChange)
    local row = addRow(parent, 52)
    registerSearch(tab, row, label)
    local text = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -190, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Text = label,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 168, 0, 32),
        Position = UDim2.new(1, -182, 0.5, -16),
        Text = tostring(getPath(state, path) or options[1] or "None"),
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, row)
    corner(button, 7)
    stroke(button)
    local popup = new("Frame", {
        BackgroundColor3 = C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 168, 0, math.min(#options * 32 + 8, 220)),
        Position = UDim2.new(1, -182, 1, -4),
        Visible = false,
        ZIndex = 20,
    }, row)
    corner(popup, 7)
    stroke(popup)
    local list = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, #options * 32),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.accent,
        ZIndex = 21,
    }, popup)
    local layout = new("UIListLayout", { Padding = UDim.new(0, 2) }, list)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
    }, list)
    local optionButtons = {}
    local function setValue(value, persist)
        value = tostring(value)
        setPath(state, path, value)
        button.Text = value
        popup.Visible = false
        if onChange then
            pcall(onChange, value)
        end
        if persist ~= false then
            saveConfig()
        end
    end
    local function rebuild(nextOptions)
        for _, child in ipairs(optionButtons) do
            child:Destroy()
        end
        optionButtons = {}
        list.CanvasSize = UDim2.new(0, 0, 0, #nextOptions * 32)
        popup.Size = UDim2.new(0, 168, 0, math.min(#nextOptions * 32 + 8, 220))
        for _, option in ipairs(nextOptions) do
            local optionButton = new("TextButton", {
                AutoButtonColor = false,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 30),
                Text = tostring(option),
                TextColor3 = C.text,
                TextSize = 12,
                Font = Enum.Font.Gotham,
                ZIndex = 22,
            }, list)
            corner(optionButton, 5)
            optionButtons[#optionButtons + 1] = optionButton
            optionButton.MouseButton1Click:Connect(function()
                setValue(option)
            end)
            optionButton.MouseEnter:Connect(function()
                tween(optionButton, { BackgroundTransparency = 0, BackgroundColor3 = C.accentDark }, 0.12)
            end)
            optionButton.MouseLeave:Connect(function()
                tween(optionButton, { BackgroundTransparency = 1 }, 0.12)
            end)
        end
    end
    rebuild(options)
    button.MouseButton1Click:Connect(function()
        popup.Visible = not popup.Visible
    end)
    controlMap[path] = {
        set = setValue,
        get = function() return getPath(state, path) end,
        setOptions = rebuild,
    }
    return row, setValue, controlMap[path]
end

local function addTextbox(tab, parent, label, path, placeholder, numeric)
    local row = addRow(parent, 58)
    registerSearch(tab, row, label)
    local text = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -210, 0, 20),
        Position = UDim2.new(0, 14, 0, 5),
        Text = label,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local box = new("TextBox", {
        BackgroundColor3 = C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 168, 0, 34),
        Position = UDim2.new(1, -182, 0, 19),
        Text = tostring(getPath(state, path) or ""),
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = C.muted,
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        ClearTextOnFocus = false,
    }, row)
    corner(box, 7)
    stroke(box)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
    local function setValue(value, persist)
        if numeric then
            value = tonumber(value) or 0
            if value < 0 then
                value = 0
            end
        else
            value = tostring(value or "")
        end
        setPath(state, path, value)
        box.Text = tostring(value)
        if persist ~= false then
            saveConfig()
        end
    end
    box.FocusLost:Connect(function()
        setValue(box.Text)
    end)
    controlMap[path] = { set = setValue, get = function() return getPath(state, path) end }
    return row, setValue
end

local function addButton(tab, parent, label, callback, accent)
    local row = addRow(parent, 54)
    registerSearch(tab, row, label)
    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = accent and C.accent or C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -28, 0, 36),
        Position = UDim2.new(0, 14, 0.5, -18),
        Text = label,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.GothamSemibold,
    }, row)
    corner(button, 7)
    if not accent then
        stroke(button)
    end
    button.MouseButton1Click:Connect(function()
        pcall(callback)
    end)
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundColor3 = accent and C.accentDark or C.line }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundColor3 = accent and C.accent or C.cardAlt }, 0.12)
    end)
    return row, button
end

local function addInfo(tab, parent, label)
    local row = addRow(parent, 42)
    registerSearch(tab, row, label)
    local text = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Text = label,
        TextColor3 = C.muted,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, row)
    return row, text
end

local function createPage(tab, title, subtitle)
    local frame = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = tab == currentTab,
    }, pagesHost)
    local layout = new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, frame)
    pages[tab] = { frame = frame, rows = {}, sections = {}, title = title, subtitle = subtitle }
    return pages[tab]
end

local function selectTab(tab)
    if not pages[tab] then
        return
    end
    currentTab = tab
    for key, page in pairs(pages) do
        page.frame.Visible = key == tab
    end
    for key, button in pairs(navButtons) do
        tween(button, { BackgroundColor3 = key == tab and C.accentDark or C.sidebar }, 0.12)
        button.TextColor3 = key == tab and C.text or C.muted
    end
    if pageTitle then
        pageTitle.Text = pages[tab].title
    end
    if pageSubtitle then
        pageSubtitle.Text = pages[tab].subtitle
    end
end

local function hasVisibleRow(page, query)
    if not page then
        return false
    end
    for _, row in ipairs(page.rows) do
        if row.frame.Visible and (query == "" or string.find(row.label, query, 1, true)) then
            return true
        end
    end
    return false
end

local function applySearch(query)
    query = string.lower(query or "")
    local firstMatch
    for tab, page in pairs(pages) do
        for _, row in ipairs(page.rows) do
            local visible = query == "" or string.find(row.label, query, 1, true) ~= nil
            row.frame.Visible = visible
            if visible and query ~= "" and not firstMatch then
                firstMatch = tab
            end
        end
        for _, section in ipairs(page.sections) do
            local anyVisible = false
            for _, child in ipairs(section:GetChildren()) do
                if child:IsA("Frame") and child.Visible then
                    anyVisible = true
                    break
                end
            end
            section.Visible = anyVisible
        end
    end
    if query ~= "" and firstMatch and not hasVisibleRow(pages[currentTab], query) then
        selectTab(firstMatch)
    end
end

local function buildUI(backend)
    local parent = nil
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then
            parent = result
        end
    end
    if not parent then
        parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    gui = new("ScreenGui", {
        Name = HUB_NAME,
        Enabled = false,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 1000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, parent)
    main = new("Frame", {
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 720, 0, 440),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
    }, gui)
    corner(main, 10)
    stroke(main, C.line, 1)
    uiScale = new("UIScale", { Scale = state.settings.uiScale }, main)
    local shadow = new("ImageLabel", {
        BackgroundTransparency = 1,
        Image = "rbxassetid://6014261993",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.45,
        Size = UDim2.new(1, 50, 1, 50),
        Position = UDim2.new(0, -25, 0, -25),
        ZIndex = -1,
    }, main)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 0),
    }, shadow)

    local topbar = new("Frame", {
        BackgroundColor3 = C.sidebar,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Active = true,
    }, main)
    local topTitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -210, 1, 0),
        Position = UDim2.fromOffset(16, 0),
        Text = HUB_NAME .. "  |  " .. (gameKey == "sae" and "Steal an Egg" or "Pet Sim 99"),
        TextColor3 = C.text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, topbar)
    local topHint = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 190, 1, 0),
        Position = UDim2.new(1, -228, 0, 0),
        Text = gameKey == "sae" and "RightShift / RightControl" or "RightControl",
        TextColor3 = C.muted,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, topbar)
    local topMinimize = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(28, 26),
        Position = UDim2.new(1, -36, 0.5, -13),
        Text = "−",
        TextColor3 = C.muted,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
    }, topbar)
    corner(topMinimize, 6)
    topMinimize.MouseButton1Click:Connect(function()
        gui.Enabled = false
    end)

    local sidebar = new("Frame", {
        BackgroundColor3 = C.sidebar,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 168, 1, -42),
        Position = UDim2.fromOffset(0, 42),
    }, main)
    local navFrame = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 1, -16),
        Position = UDim2.fromOffset(8, 8),
    }, sidebar)
    local navLayout = new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }, navFrame)
    local tabs = {
        { key = "Farm", label = "Farm" },
        { key = "Training", label = "Training" },
        { key = "Teleports", label = "Teleports" },
        { key = "Economy", label = "Economy" },
        { key = "Selling", label = "Selling" },
        { key = "Players", label = "Players" },
        { key = "Settings", label = "Settings" },
        { key = "Credits", label = "Credits" },
    }
    for index, item in ipairs(tabs) do
        local button = new("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = C.sidebar,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 34),
            Text = "  " .. item.label,
            TextColor3 = C.muted,
            TextSize = 12,
            Font = Enum.Font.GothamMedium,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = index,
        }, navFrame)
        corner(button, 6)
        navButtons[item.key] = button
        button.MouseButton1Click:Connect(function()
            selectTab(item.key)
        end)
    end

    local content = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -168, 1, -42),
        Position = UDim2.fromOffset(168, 42),
    }, main)
    local header = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 72),
        Position = UDim2.new(0, 0, 0, 0),
    }, content)
    pageTitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -270, 0, 26),
        Position = UDim2.fromOffset(20, 12),
        Text = "Farm",
        TextColor3 = C.text,
        TextSize = 20,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    pageSubtitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -270, 0, 18),
        Position = UDim2.fromOffset(20, 40),
        Text = "",
        TextColor3 = C.muted,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    searchBox = new("TextBox", {
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 190, 0, 30),
        Position = UDim2.new(1, -214, 0, 18),
        Text = "",
        PlaceholderText = "Search anything",
        PlaceholderColor3 = C.muted,
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
    }, header)
    corner(searchBox, 8)
    stroke(searchBox)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, searchBox)
    pagesHost = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -32, 1, -84),
        Position = UDim2.fromOffset(16, 76),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.accent,
    }, content)

    toastLabel = new("TextLabel", {
        BackgroundColor3 = C.cardAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 300, 0, 36),
        Position = UDim2.new(1, -316, 1, -50),
        Text = "",
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Visible = false,
        ZIndex = 50,
    }, main)
    corner(toastLabel, 8)
    stroke(toastLabel, C.accent)

    local dragBar = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -250, 1, 0),
        Active = true,
    }, topbar)
    local dragging = false
    local dragStart
    local startPosition
    dragBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
        end
    end)
    local dragChanged = UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    local dragEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    cleanupConnections[#cleanupConnections + 1] = dragChanged
    cleanupConnections[#cleanupConnections + 1] = dragEnded

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        applySearch(searchBox.Text)
    end)
    local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == TOGGLE_KEY or input.KeyCode == TOGGLE_KEY_ALT) then
            gui.Enabled = not gui.Enabled
        end
    end)
    cleanupConnections[#cleanupConnections + 1] = keyConnection

    buildPages(backend)
    selectTab("Farm")
    saveConfig()
end

local function refreshControl(path)
    local control = controlMap[path]
    if control then
        control.set(getPath(state, path), false)
    end
end

local function resetConfig()
    state = deepCopy(DEFAULTS)
    config.games[placeKey] = state
    for path in pairs(controlMap) do
        local control = controlMap[path]
        if control then
            control.set(getPath(state, path), false)
        end
    end
    uiScale.Scale = state.settings.uiScale
    if economyStartButton then
        economyStartButton.Text = "Start selected auto actions"
    end
    saveConfig()
    notify("Config reset", C.amber)
end

local playerListHost
local playerRefreshButton

buildPages = function(backend)
    createPage("Farm", "Farm", "Automate egg runs, hatching, and cash upgrades")
    local farm = addSection("Farm", "Automation")
    addToggle("Farm", farm, "Enable Smart Farm", "farm.smart", function(value)
        if value then
            runtime.mode = "farm"
            runtime.runsSinceTraining = 0
            notify("Smart Farm enabled", C.green)
        end
    end)
    addToggle("Farm", farm, "Auto-hatch ready eggs", "farm.hatch")
    addToggle("Farm", farm, backend.key == "ps99" and "Auto-upgrade pet slots (cash)" or "Auto-upgrade treadmill (cash)", "farm.treadmill")
    local farmStatus = addSection("Farm", "Status")
    statusLabel = select(2, addInfo("Farm", farmStatus, "Idle"))

    createPage("Training", "Training", backend.key == "ps99" and "Alternate farm runs with tap-training sessions" or "Alternate farm runs with treadmill speed sessions")
    local training = addSection("Training", "Speed progression")
    addToggle("Training", training, "Train between runs", "training.between")
    addToggle("Training", training, "Training only", "training.only", function(value)
        if value then
            runtime.mode = "training"
            runtime.trainingUntil = os.clock() + state.training.seconds
        else
            runtime.mode = state.farm.smart and "farm" or "idle"
        end
    end)
    addSlider("Training", training, "Seconds per training session", "training.seconds", 1, 60, 1, function(value)
        return string.format("%.2f", value)
    end)
    addSlider("Training", training, "Farm runs between training", "training.farmRuns", 1, 20, 1, function(value)
        return string.format("%.0f", value)
    end)
    addButton("Training", training, "Stop farm and training", function()
        state.farm.smart = false
        state.training.only = false
        state.training.between = false
        runtime.mode = "idle"
        runtime.runsSinceTraining = 0
        refreshControl("farm.smart")
        refreshControl("training.only")
        refreshControl("training.between")
        saveConfig()
        notify("Farm and training stopped", C.amber)
    end, false)

    createPage("Teleports", "Teleports", "Jump to areas, NPCs, and world markers")
    local teleportSection = addSection("Teleports", "Locations")
    local teleportControl
    local teleportOptions = backend.teleports and backend.teleports() or { "Spawn" }
    local _, _, control = addDropdown("Teleports", teleportSection, "Location", "teleports.selected", teleportOptions)
    teleportControl = control
    addButton("Teleports", teleportSection, "Teleport", function()
        local destination = state.teleports.selected
        local ok, err = pcall(backend.teleport, destination)
        if ok then
            notify("Teleported to " .. tostring(destination), C.green)
        else
            notify("Teleport failed: " .. tostring(err), C.red)
        end
    end, true)
    addButton("Teleports", teleportSection, "Refresh locations", function()
        local options = backend.teleports and backend.teleports() or { "Spawn" }
        if teleportControl then
            teleportControl.setOptions(options)
        end
        notify("Locations refreshed", C.green)
    end, false)

    createPage("Economy", "Economy", "Cash upgrades, best gear, trails, and rewards")
    local economy = addSection("Economy", "Cash-only actions")
    addToggle("Economy", economy, backend.key == "ps99" and "Auto-upgrade pet and egg slots (cash)" or "Auto-upgrade equipment slots (cash)", "economy.upgradeSlots")
    addToggle("Economy", economy, "Auto Equip Best", "economy.autoEquip")
    addButton("Economy", economy, "Equip Best now", function()
        local ok, err = pcall(backend.equipBest)
        if ok then
            notify("Best gear equipped", C.green)
        else
            notify("Equip failed: " .. tostring(err), C.red)
        end
    end, false)
    if backend.supportsTrails == false then
        addInfo("Economy", economy, "Cash trails are available in Steal an Egg only.")
    else
        addDropdown("Economy", economy, "Cash trail to buy", "economy.trail", backend.trails and backend.trails() or { "None" })
        addToggle("Economy", economy, "Auto-buy selected trail (cash)", "economy.autoBuyTrail")
    end
    addTextbox("Economy", economy, "Keep this much cash", "economy.reserve", "0", true)
    local startControl
    local _, startButton = addButton("Economy", economy, "Start selected auto actions", function()
        state.economy.running = not state.economy.running
        startControl.Text = state.economy.running and "Stop selected auto actions" or "Start selected auto actions"
        saveConfig()
        if state.economy.running then
            pcall(backend.economyStep, true)
            notify("Economy actions started", C.green)
        else
            notify("Economy actions stopped", C.amber)
        end
    end, true)
    startControl = startButton
    economyStartButton = startButton
    startControl.Text = state.economy.running and "Stop selected auto actions" or "Start selected auto actions"
    local rewards = addSection("Economy", "Rewards")
    addToggle("Economy", rewards, "Auto-collect earnings", "economy.autoCollect")
    addToggle("Economy", rewards, backend.key == "ps99" and "Claim rank rewards" or "Claim index rewards", "economy.indexRewards")
    addButton("Economy", rewards, "Collect / claim now", function()
        pcall(backend.collectEarnings)
        pcall(backend.claimIndex)
        notify("Collection actions sent", C.green)
    end, false)

    createPage("Selling", "Selling", "Explicit pet and satchel sale controls")
    local selling = addSection("Selling", "Sale permission")
    if backend.supportsSelling == false then
        addInfo("Selling", selling, "Pet Sim 99 exposes no verified sale endpoint for roster pets.")
        addInfo("Selling", selling, "Farming World worker sales remain in the game's own merchant UI.")
    else
        addToggle("Selling", selling, "Explicit opt-in only", "selling.explicit")
        addToggle("Selling", selling, "Confirm manual bulk satchel sale", "selling.confirmBulk")
        addTextbox("Selling", selling, "Bulk sale confirmation", "selling.bulkPhrase", "SELL ALL SATCHEL", false)
        addButton("Selling", selling, "Request manual satchel sale", function()
            if not state.selling.explicit or not state.selling.confirmBulk then
                notify("Enable both sale confirmations first", C.amber)
                return
            end
            if string.upper(state.selling.bulkPhrase or "") ~= "SELL ALL SATCHEL" then
                notify("Type SELL ALL SATCHEL to confirm", C.amber)
                return
            end
            local ok, result = pcall(backend.sellEveryPet)
            if ok and result ~= false then
                notify("Bulk sale requested", C.green)
            else
                notify("Sale request failed", C.red)
            end
        end, true)
        local autoSell = addSection("Selling", "Automatic selling")
        addToggle("Selling", autoSell, "Auto-sell new pets", "selling.autoSell")
        local rarities = {
            { label = "Sell future Common", path = "selling.common" },
            { label = "Sell future Uncommon", path = "selling.uncommon" },
            { label = "Sell future Rare", path = "selling.rare" },
            { label = "Sell future Epic", path = "selling.epic" },
            { label = "Sell future Legendary", path = "selling.legendary" },
            { label = "Sell future Mythic", path = "selling.mythic" },
        }
        for _, rarity in ipairs(rarities) do
            addToggle("Selling", autoSell, rarity.label, rarity.path)
        end
    end

    createPage("Players", "Players", "Inspect and teleport to players in the server")
    local playersSection = addSection("Players", "Server players")
    playerListHost = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0, 14, 0, 40),
    }, playersSection)
    local playerLayout = new("UIListLayout", { Padding = UDim.new(0, 5) }, playerListHost)
    playerRefreshButton = addButton("Players", playersSection, "Refresh players", function()
        refreshPlayers()
    end, true)
    refreshPlayers()

    createPage("Settings", "Settings", "Interface, persistence, and runtime preferences")
    local settings = addSection("Settings", "Interface")
    addSlider("Settings", settings, "UI scale", "settings.uiScale", 0.75, 1.25, 0.05, function(value)
        return string.format("%.2f", value)
    end, function(value)
        if uiScale then
            uiScale.Scale = value
        end
    end)
    addToggle("Settings", settings, "Notifications", "settings.notifications")
    addToggle("Settings", settings, "Anti-AFK", "settings.antiAfk")
    local persistence = addSection("Settings", "Config")
    addInfo("Settings", persistence, "Config auto-saves after every change and reloads per game on rerun.")
    addInfo("Settings", persistence, "File: " .. CONFIG_FILE)
    addButton("Settings", persistence, "Save config now", function()
        if flushConfig() then
            notify("Config saved", C.green)
        else
            notify("Config save failed", C.red)
        end
    end, false)
    addButton("Settings", persistence, "Reset config", resetConfig, false)

    createPage("Credits", "Credits", HUB_NAME .. " v" .. VERSION)
    local credits = addSection("Credits", "Build")
    addInfo("Credits", credits, HUB_NAME .. " v" .. VERSION)
    addInfo("Credits", credits, "Games: Steal an Egg + Pet Sim 99")
    addInfo("Credits", credits, "Toggle UI: RightShift")
end

refreshPlayers = function()
    if not playerListHost then
        return
    end
    for _, child in ipairs(playerListHost:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local row = new("Frame", {
            BackgroundColor3 = C.cardAlt,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 38),
        }, playerListHost)
        corner(row, 7)
        local nameLabel = new("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -110, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            Text = player.DisplayName .. " (@" .. player.Name .. ")",
            TextColor3 = C.text,
            TextSize = 12,
            Font = Enum.Font.GothamMedium,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
        local teleport = new("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = C.accentDark,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 92, 0, 28),
            Position = UDim2.new(1, -102, 0.5, -14),
            Text = "Teleport",
            TextColor3 = C.text,
            TextSize = 11,
            Font = Enum.Font.GothamSemibold,
        }, row)
        corner(teleport, 6)
        teleport.MouseButton1Click:Connect(function()
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local targetCharacter = player.Character
            local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
            if root and targetRoot then
                root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
                notify("Teleported to " .. player.DisplayName, C.green)
            else
                notify("Player character is not ready", C.amber)
            end
        end)
    end
end

local jobBusy = {}
local function runJob(name, interval, callback)
    local now = os.clock()
    if jobBusy[name] or now < (runtime["next" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)] or 0) then
        return
    end
    runtime["next" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)] = now + interval
    jobBusy[name] = true
    task.spawn(function()
        local ok, result = pcall(callback)
        jobBusy[name] = false
        if not ok then
            notify(name .. " failed: " .. tostring(result), C.red)
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

        if statusLabel and now - runtime.lastStatus >= 0.2 then
            runtime.lastStatus = now
            if runtime.mode == "training" then
                statusLabel.Text = string.format("Training • %.1fs", math.max(0, runtime.trainingUntil - now))
                statusLabel.TextColor3 = C.accent
            elseif runtime.mode == "farm" then
                statusLabel.Text = string.format("Farming • %.0f/%.0f runs", runtime.runsSinceTraining, state.training.farmRuns)
                statusLabel.TextColor3 = C.green
            else
                statusLabel.Text = "Idle"
                statusLabel.TextColor3 = C.muted
            end
        end
    end)
    cleanupConnections[#cleanupConnections + 1] = heartbeat
end

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
    if not root then
        return false
    end
    local ok = pcall(function()
        root.CFrame = cframe
    end)
    return ok
end

local function walkToCFrame(cframe, timeout)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or not cframe then
        return false
    end
    local hipHeight = math.max(tonumber(humanoid.HipHeight) or 2, 1)
    local destination = cframe.Position + Vector3.new(0, hipHeight + 0.5, 0)
    local deadline = os.clock() + (tonumber(timeout) or 20)
    local function horizontalDistance(target)
        local offset = root.Position - target
        return Vector3.new(offset.X, 0, offset.Z).Magnitude
    end
    local function atDestination()
        return root.Parent ~= nil and horizontalDistance(destination) <= 3.0
            and math.abs(root.Position.Y - destination.Y) <= 6.0
    end
    if atDestination() then
        return true
    end

    local waypoints
    pcall(function()
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            CanJump = true,
        })
        path:ComputeAsync(root.Position, destination)
        if path.Status == Enum.PathStatus.Success then
            waypoints = path:GetWaypoints()
        end
    end)

    local function follow(target)
        local lastMove = -math.huge
        while os.clock() < deadline do
            if shuttingDown or not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
                return false
            end
            if (root.Position - target).Magnitude <= 2.5 then
                return true
            end
            local now = os.clock()
            if now - lastMove >= 0.5 then
                humanoid:MoveTo(target)
                lastMove = now
            end
            task.wait(0.1)
        end
        return false
    end

    if waypoints and #waypoints > 0 then
        for _, waypoint in ipairs(waypoints) do
            if os.clock() >= deadline or not follow(waypoint.Position) then
                break
            end
        end
    end
    if atDestination() then
        return true
    end
    return follow(destination)
end

local function parseNumber(value)
    if type(value) == "number" then
        return value
    end
    local text = tostring(value or ""):gsub(",", "")
    local number = string.match(text, "[-%d%.]+")
    return tonumber(number) or 0
end

local function readStat(names)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if not leaderstats then
        return nil
    end
    for _, name in ipairs(names) do
        local stat = leaderstats:FindFirstChild(name)
        if stat then
            local ok, value = pcall(function()
                return stat.Value
            end)
            if ok and type(value) == "number" then
                return value
            end
        end
    end
    return nil
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

local function triggerPrompt(prompt)
    if not prompt then
        return false
    end
    if type(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then
            return true
        end
    end
    if type(firesignal) == "function" and prompt.Triggered then
        local ok = pcall(firesignal, prompt.Triggered)
        if ok then
            return true
        end
    end
    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.35)
        prompt:InputHoldEnd()
    end)
    return ok
end

local function promptNamed(names, maxDistance)
    local namesSet = {}
    for _, name in ipairs(names) do
        namesSet[name] = true
    end
    for _, instance in ipairs(descendantsBounded(workspace, 7000)) do
        if namesSet[instance.Name] then
            local ok, isPrompt = pcall(function()
                return instance:IsA("ProximityPrompt")
            end)
            if ok and isPrompt then
                local parent = instance.Parent
                local part
                local root = characterRoot()
                if parent and root then
                    local ok, candidate = pcall(function()
                        if parent:IsA("BasePart") then
                            return parent
                        end
                        return parent:FindFirstChildWhichIsA("BasePart")
                    end)
                    if ok then
                        part = candidate
                    end
                end
                if part and root then
                    local ok, distance = pcall(function()
                        return (part.Position - root.Position).Magnitude
                    end)
                    if ok and distance <= (maxDistance or 80) then
                        return instance
                    end
                end
            end
        end
    end
    return nil
end

local function equipTool(tool)
    if not tool then
        return false
    end
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    return ok
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

local function teleportNamed(name, aliases, maxDistance)
    local target = nearestNamed(name, aliases, maxDistance)
    local cframe = instanceCFrame(target)
    if not cframe then
        return false
    end
    return teleportToCFrame(cframe * CFrame.new(0, 0, 4))
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

local function numberField(object, names, default)
    for _, name in ipairs(names) do
        local ok, value = pcall(function()
            return object[name]
        end)
        if ok and type(value) == "number" then
            return value
        end
        local attributeOk, attribute = pcall(function()
            return object:GetAttribute(name)
        end)
        if attributeOk and type(attribute) == "number" then
            return attribute
        end
    end
    return default or 0
end

local function stringField(object, names, default)
    for _, name in ipairs(names) do
        local ok, value = pcall(function()
            return object[name]
        end)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
        local attributeOk, attribute = pcall(function()
            return object:GetAttribute(name)
        end)
        if attributeOk and type(attribute) == "string" and attribute ~= "" then
            return attribute
        end
    end
    return default or ""
end

local function boolField(object, names)
    for _, name in ipairs(names) do
        local ok, value = pcall(function()
            return object[name]
        end)
        if ok and type(value) == "boolean" then
            return value
        end
        local attributeOk, attribute = pcall(function()
            return object:GetAttribute(name)
        end)
        if attributeOk and type(attribute) == "boolean" then
            return attribute
        end
    end
    return false
end

local function toolScore(tool)
    return numberField(tool, { "Power", "Damage", "DPS", "Value", "Price", "Earnings", "Level", "Tier" }, 0)
        + numberField(tool, { "Rarity" }, 0) * 1000
end

local function petRarity(pet)
    local rarity = string.lower(stringField(pet, { "Rarity", "PetRarity", "Tier" }, ""))
    if rarity == "" then
        rarity = string.lower(tostring(pet.Name or ""))
    end
    for _, candidate in ipairs({ "mythic", "legendary", "epic", "rare", "uncommon", "common" }) do
        if string.find(rarity, candidate, 1, true) then
            return candidate
        end
    end
    return "unknown"
end

local function petUid(pet)
    return stringField(pet, { "UID", "UUID", "PetId", "Id" }, "")
end

local function petLocked(pet)
    return boolField(pet, { "Favorite", "Favourite", "Locked", "IsFavorite", "IsFavourite" })
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

Backends.SAE = finishBackend({
    name = "Steal an Egg",
    key = "sae",
    teleports = function()
        return {
            "Spawn",
            "My Base",
            "My Egg Area",
            "My Treadmill",
            "Nearest Field Egg",
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
                return teleportToCFrame(cf * CFrame.new(0, 3, 0))
            end
            return false
        end
        if destination == "My Treadmill" and PlotState then
            local plot = PlotState.ResolvePlot()
            local target = firstDescendant(plot and plot.PlotFolder, "TreadmillBottom")
            local cframe = instanceCFrame(target)
            if cframe then
                return teleportToCFrame(cframe * CFrame.new(0, 4, 0))
            end
        end
        if destination == "My Base" or destination == "My Egg Area" or destination == "My Treadmill" then
            local plot = PlotState and PlotState.ResolvePlot()
            local target = destination == "My Egg Area" and plot and plot.PetArea or plot and plot.CenterPoint
            local cframe = instanceCFrame(target) or plot and plot.RespawnPointCFrame
            if cframe then
                return teleportToCFrame(cframe * CFrame.new(0, 4, 0))
            end
        end
        if destination == "Spawn" then
            local spawn = workspace:FindFirstChild("SpawnLocation")
            local cframe = instanceCFrame(spawn)
            if cframe then
                return teleportToCFrame(cframe * CFrame.new(0, 4, 0))
            end
            local plot = PlotState and PlotState.ResolvePlot()
            if plot and plot.RespawnPointCFrame then
                return teleportToCFrame(plot.RespawnPointCFrame * CFrame.new(0, 4, 0))
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
                return teleportToCFrame(cframe * CFrame.new(0, 3, 0))
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
                cleanupConnections[#cleanupConnections + 1] = conn
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
        if not walkToCFrame(center.CFrame, 12) then
            return false
        end
        local wore, wearError = EggState.WearEggTool(uid)
        if wore ~= true then
            plantSkipUntil[uid] = os.clock() + 3.0
            if wearError then
                notify("Wear: " .. tostring(wearError), C.amber)
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
        if not walkToCFrame(center.CFrame * chosen, 8) then
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
            notify("Plant: " .. tostring(errText), C.amber)
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
        if exitCf and not walkToCFrame(exitCf, 12) then
            return false
        end
        local targetCFrame = (plot.CenterPoint and plot.CenterPoint.CFrame) or plot.RespawnPointCFrame
        if not targetCFrame then
            return false
        end
        if not walkToCFrame(targetCFrame, 16) then
            return false
        end
        for _ = 1, 10 do
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
        if not walkToCFrame(fieldCf, 16) then
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
            notify("Carry: " .. tostring(carryError), C.amber)
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
                        notify("Hatch: " .. tostring(activateError or activated), C.red)
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
                        notify(errorText, C.red)
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
        if not walkToCFrame(cframe, 16) then
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
            notify("PS99 engine loader is unavailable", C.red)
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
            notify("PS99 engine failed to load", C.red)
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

local backendKey = gameKey == "sae" and "SAE" or "PS99"
local backend = Backends[backendKey]
assert(backend, HUB_NAME .. ": backend failed to initialize")
finishBackend(backend)
if type(backend.warmup) == "function" then
    pcall(backend.warmup)
end
buildUI(backend)
startScheduler(backend)

local function showHub()
    if gui and gui.Parent then
        gui.Enabled = true
    end
end

local function hideHub()
    if gui and gui.Parent then
        gui.Enabled = false
    end
end

local function cleanupHub()
    shuttingDown = true
    syncAntiAfk()
    flushConfig()
    if toastConnection then
        pcall(task.cancel, toastConnection)
        toastConnection = nil
    end
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
