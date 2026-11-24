--[[
    Steph HUB - Universal Multi-Game Loader v9.7
    --------------------------------------------
    One loadstring runs both games automatically:
      1. Pet Simulator 99  -> games/ps99.lua  (full modular Steph HUB + engine)
      2. Steal an Egg      -> games/steal_an_egg.lua (verified remotes + UI)

    If launched in an unrecognized place, shows manual game buttons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tween = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[Steph HUB] run this on the client")

local REPO = "https://github.com/miniwroldpro124-cyber/pet99bynhmt"
local COMMIT = "main"
local VERSION = "9.7"
local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/" .. COMMIT .. "/"
local MIRROR = "https://cdn.jsdelivr.net/gh/miniwroldpro124-cyber/pet99bynhmt@" .. COMMIT .. "/"

local GAMES = {
    sae = {
        id = "sae",
        name = "Steal an Egg",
        file = "games/steal_an_egg.lua",
        gameIds = { [10563114921] = true },
        placeIds = { [107778070777162] = true },
    },
    ps99 = {
        id = "ps99",
        name = "Pet Simulator 99",
        file = "games/ps99.lua",
        gameIds = { [3317771874] = true },
        placeIds = {
            [8737899170] = true,   -- World 1
            [16498369169] = true,  -- World 2 (Tech)
            [17503543197] = true,  -- World 3 (Void)
            [15502339080] = true,  -- Trading Plaza
            [15588442388] = true,  -- Pro Trading Plaza
        },
    },
}

local playerGui = player:WaitForChild("PlayerGui", 30)
assert(playerGui, "[Steph HUB] PlayerGui never appeared")

-- Tear down any previous Steph HUB / Steal an Egg UI or cleanup hook before routing
local function cleanupPrevious()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env.StehpHubCleanup) == "function" then
        pcall(env.StehpHubCleanup)
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
    local oldNames = { "STEPHHUB_ROUTER", "STEPHHUB_LOADING", "Steph HUB", "Stehp-Hub" }
    for _, container in ipairs(containers) do
        for _, guiName in ipairs(oldNames) do
            for _, child in ipairs(container:GetChildren()) do
                if child.Name == guiName then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end
cleanupPrevious()

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

------------------------------------------------------------------- detection

local function detectGame()
    local placeId = tonumber(game.PlaceId) or 0
    local gameId = tonumber(game.GameId) or 0

    for _, key in ipairs({ "sae", "ps99" }) do
        local spec = GAMES[key]
        if spec.placeIds[placeId] or spec.gameIds[gameId] then
            return spec
        end
    end

    -- Structural fallback if Roblox adds a new sub-place ID
    local clientFolder = ReplicatedStorage:FindFirstChild("Client")
    if clientFolder and clientFolder:FindFirstChild("EggState") then
        return GAMES.sae
    end
    local libraryFolder = ReplicatedStorage:FindFirstChild("Library")
    if libraryFolder and libraryFolder:FindFirstChild("Client") then
        return GAMES.ps99
    end
    return nil
end

----------------------------------------------------------------- router UI

local function make(class, props, parent)
    local instance = Instance.new(class)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local routerGui = make("ScreenGui", {
    Name = "STEPHHUB_ROUTER",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 610,
}, playerGui)

local card = make("Frame", {
    Size = UDim2.fromOffset(390, 146),
    Position = UDim2.new(0.5, -195, 0.5, -73),
    BackgroundColor3 = Color3.fromRGB(18, 15, 27),
    BorderSizePixel = 0,
}, routerGui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
make("UIStroke", { Color = Color3.fromRGB(55, 45, 76), Thickness = 1 }, card)

make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 24),
    Position = UDim2.fromOffset(14, 12),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "Steph HUB  -  Loader  " .. VERSION,
    TextColor3 = Color3.fromRGB(241, 237, 250),
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, card)

local statusLabel = make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 18),
    Position = UDim2.fromOffset(14, 42),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "detecting game...",
    TextColor3 = Color3.fromRGB(157, 148, 178),
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, card)

local track = make("Frame", {
    Size = UDim2.new(1, -28, 0, 6),
    Position = UDim2.fromOffset(14, 70),
    BackgroundColor3 = Color3.fromRGB(37, 30, 54),
    BorderSizePixel = 0,
}, card)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, track)

local fill = make("Frame", {
    Size = UDim2.new(0.15, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(139, 92, 246),
    BorderSizePixel = 0,
}, track)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)

local infoLabel = make("TextLabel", {
    Size = UDim2.new(1, -28, 0, 16),
    Position = UDim2.fromOffset(14, 88),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "games: Pet Simulator 99  |  Steal an Egg",
    TextColor3 = Color3.fromRGB(115, 108, 138),
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, card)

local function setStatus(text, pct, color)
    statusLabel.Text = tostring(text)
    if color then
        statusLabel.TextColor3 = color
    end
    if pct then
        Tween:Create(fill, TweenInfo.new(0.18), { Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0) }):Play()
    end
end

local function launchSpec(spec)
    setStatus("downloading " .. spec.name .. "...", 0.45, Color3.fromRGB(157, 148, 178))
    local source = httpGet(spec.file)
    if not source then
        setStatus("download failed: " .. spec.file, 0.45, Color3.fromRGB(248, 113, 113))
        warn("[Steph HUB] download failed: " .. spec.file)
        return nil
    end

    setStatus("compiling " .. spec.name .. "...", 0.80)
    local chunk, err = loadstring(source, "=" .. spec.file)
    if not chunk then
        setStatus("compile error: " .. tostring(err), 0.80, Color3.fromRGB(248, 113, 113))
        warn("[Steph HUB] compile error in " .. spec.file .. ": " .. tostring(err))
        return nil
    end

    setStatus("launching " .. spec.name .. "...", 1.0, Color3.fromRGB(74, 222, 128))
    task.wait(0.15)
    if routerGui and routerGui.Parent then
        routerGui:Destroy()
    end

    local ok, result = pcall(chunk)
    if not ok then
        warn("[Steph HUB] " .. spec.name .. " boot error: " .. tostring(result))
        return nil
    end
    return result
end

local detected = detectGame()
if detected then
    return launchSpec(detected)
end

-- Unrecognized PlaceId: expand card to let the user pick either script manually
card.Size = UDim2.fromOffset(390, 206)
card.Position = UDim2.new(0.5, -195, 0.5, -103)
setStatus("unknown place (" .. tostring(game.PlaceId) .. ") - pick a script:", 1.0, Color3.fromRGB(251, 191, 36))
infoLabel.Text = "source: " .. REPO:gsub("^https://", "")

local function addPickButton(label, xOffset, width, bg, onClick)
    local btn = make("TextButton", {
        Size = UDim2.fromOffset(width, 34),
        Position = UDim2.fromOffset(xOffset, 122),
        BackgroundColor3 = bg,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        Text = label,
        TextColor3 = Color3.fromRGB(241, 237, 250),
        TextSize = 12,
        AutoButtonColor = false,
    }, card)
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, btn)
    btn.MouseButton1Click:Connect(function()
        task.spawn(onClick)
    end)
    return btn
end

addPickButton("Pet Simulator 99", 14, 174, Color3.fromRGB(104, 65, 196), function()
    launchSpec(GAMES.ps99)
end)
addPickButton("Steal an Egg", 202, 174, Color3.fromRGB(139, 92, 246), function()
    launchSpec(GAMES.sae)
end)

local closeBtn = make("TextButton", {
    Size = UDim2.new(1, -28, 0, 28),
    Position = UDim2.fromOffset(14, 166),
    BackgroundColor3 = Color3.fromRGB(37, 30, 54),
    BorderSizePixel = 0,
    Font = Enum.Font.Gotham,
    Text = "Close",
    TextColor3 = Color3.fromRGB(157, 148, 178),
    TextSize = 12,
    AutoButtonColor = false,
}, card)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
closeBtn.MouseButton1Click:Connect(function()
    if routerGui and routerGui.Parent then
        routerGui:Destroy()
    end
end)

return nil
