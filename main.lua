--[[
    PS99 Delta Full Auto v3
    target: Pet Simulator 99
    executor: Delta
    author: outcome for He
    
    v3: loading stages, on-screen progress, prints at every step
]]

-- ═══════════════════════════════════════════
-- LOADING UI (appears first, before anything else)
-- ═══════════════════════════════════════════

local parent = (gethui and gethui()) or game:GetService("CoreGui")

local LoadGui = Instance.new("ScreenGui")
LoadGui.Name = "PS99Loading"
LoadGui.ResetOnSpawn = false
LoadGui.Parent = parent

local loadFrame = Instance.new("Frame")
loadFrame.Size = UDim2.new(0, 260, 0, 90)
loadFrame.Position = UDim2.new(0.5, -130, 0.5, -45)
loadFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
loadFrame.BorderSizePixel = 0
loadFrame.Parent = LoadGui

local loadTitle = Instance.new("TextLabel")
loadTitle.Size = UDim2.new(1, -20, 0, 28)
loadTitle.Position = UDim2.new(0, 10, 0, 8)
loadTitle.BackgroundTransparency = 1
loadTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
loadTitle.Text = "PS99 Delta Full — loading"
loadTitle.Font = Enum.Font.GothamBold
loadTitle.TextSize = 14
loadTitle.TextXAlignment = Enum.TextXAlignment.Left
loadTitle.Parent = loadFrame

local loadStatus = Instance.new("TextLabel")
loadStatus.Size = UDim2.new(1, -20, 0, 44)
loadStatus.Position = UDim2.new(0, 10, 0, 38)
loadStatus.BackgroundTransparency = 1
loadStatus.TextColor3 = Color3.fromRGB(180, 220, 180)
loadStatus.Text = "starting..."
loadStatus.Font = Enum.Font.Code
loadStatus.TextSize = 12
loadStatus.TextXAlignment = Enum.TextXAlignment.Left
loadStatus.TextYAlignment = Enum.TextYAlignment.Top
loadStatus.TextWrapped = true
loadStatus.Parent = loadFrame

local function stage(msg)
    print("[PS99] " .. msg)
    if loadStatus then
        loadStatus.Text = msg
    end
    task.wait(0.05)
end

stage("1. script start")

-- ═══════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════

local config = {
    petSpeed        = false,
    autoTap         = false,
    fastFarm        = false,
    hopEnabled      = false,
    autoBuyPetSlot  = false,
    autoBuyEggSlot  = false,
    autoBuyMap      = false,
    autoTeleBest    = false,
    autoBestWorld   = false,

    maxPlayers      = 4,
    hopInterval     = 30,
    farmDelay       = 0.05,
    tapDelay        = 0.01,
    useRemote       = true,
    useClick        = true,
    antiban         = true,
    debug           = true,
}

stage("2. config loaded")

-- ═══════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local VirtualInputManager  = game:GetService("VirtualInputManager")
local RunService           = game:GetService("RunService")
local TeleportService      = game:GetService("TeleportService")
local HttpService          = game:GetService("HttpService")
local StarterGui           = game:GetService("StarterGui")

stage("3. services loaded")

local LocalPlayer = Players.LocalPlayer
stage("4. LocalPlayer: " .. tostring(LocalPlayer))

local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
stage("5. Character: " .. tostring(Character))

local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 5)
stage("6. HRP: " .. tostring(HumanoidRootPart))

local Camera = workspace.CurrentCamera
stage("7. Camera: " .. tostring(Camera))

-- ═══════════════════════════════════════════
-- DEFENSIVE REFS
-- ═══════════════════════════════════════════

local Things      = workspace:FindFirstChild("__THINGS")
stage("8. __THINGS: " .. tostring(Things))

local Breakables  = Things and Things:FindFirstChild("Breakables")
stage("9. Breakables: " .. tostring(Breakables))

local Orbs        = Things and Things:FindFirstChild("Orbs")
local Lootbags    = Things and Things:FindFirstChild("Lootbags")
local Pets        = Things and Things:FindFirstChild("Pets")
stage("10. Pets: " .. tostring(Pets))

local Network     = ReplicatedStorage:FindFirstChild("Network")
stage("11. Network: " .. tostring(Network))

-- re-scan loop
task.spawn(function()
    while task.wait(3) do
        if not Things then Things = workspace:FindFirstChild("__THINGS") end
        if Things then
            if not Breakables then Breakables = Things:FindFirstChild("Breakables") end
            if not Orbs then Orbs = Things:FindFirstChild("Orbs") end
            if not Lootbags then Lootbags = Things:FindFirstChild("Lootbags") end
            if not Pets then Pets = Things:FindFirstChild("Pets") end
        end
        if not Network then Network = ReplicatedStorage:FindFirstChild("Network") end
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5)
end)

stage("12. refs + rescan ready")

-- ═══════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════

local function xzDist(a, b)
    if not a or not b then return math.huge end
    local ap, bp = a.Position, b.Position
    local dx, dz = ap.X - bp.X, ap.Z - bp.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function jitterWait(base)
    if config.antiban then
        task.wait(base + math.random() * base * 0.5)
    else
        task.wait(base)
    end
end

local function fireRemote(name, ...)
    if not Network then return false end
    local remote = Network:FindFirstChild(name)
    if not remote then return false end
    pcall(function()
        remote:FireServer(...)
    end)
    return true
end

local function getHitbox(obj)
    if not obj or not obj.Parent then return nil end
    local h = obj:FindFirstChild("Hitbox", true)
    if h then return h end
    local m = obj:FindFirstChildWhichIsA("MeshPart")
    if m then return m end
    return obj:FindFirstChildWhichIsA("BasePart")
end

local function nearestBreakable()
    if not Breakables or not HumanoidRootPart or not HumanoidRootPart.Parent then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(Breakables:GetChildren()) do
        local hb = getHitbox(obj)
        if hb then
            local d = xzDist(hb, HumanoidRootPart)
            if d < bestDist then
                best, bestDist = hb, d
            end
        end
    end
    return best
end

local function clickAt(x, y)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.01)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

local function clickPart(part)
    local pos, onScreen = Camera:WorldToScreenPoint(part.Position)
    if onScreen then
        clickAt(pos.X, pos.Y)
        return true
    end
    return false
end

stage("13. utility ready")

-- ═══════════════════════════════════════════
-- FEATURES
-- ═══════════════════════════════════════════

local petSpeedThread = nil
local function startPetSpeed()
    if petSpeedThread then return end
    petSpeedThread = task.spawn(function()
        while config.petSpeed do
            if Pets and HumanoidRootPart and HumanoidRootPart.Parent then
                local rootCF = HumanoidRootPart.CFrame
                for _, pet in ipairs(Pets:GetChildren()) do
                    local hrp = pet:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hrp.CFrame = rootCF * CFrame.new(0, 0, -3)
                    end
                end
            end
            task.wait(0.03)
        end
        petSpeedThread = nil
    end)
end

local tapThread = nil
local function startTap()
    if tapThread then return end
    tapThread = task.spawn(function()
        while config.autoTap do
            local target = nearestBreakable()
            if target then clickPart(target) end
            task.wait(config.tapDelay)
        end
        tapThread = nil
    end)
end

local farmThread = nil
local function startFarm()
    if farmThread then return end
    farmThread = task.spawn(function()
        while config.fastFarm do
            if not HumanoidRootPart or not HumanoidRootPart.Parent then
                Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 5)
            end
            local target = nearestBreakable()
            if target and HumanoidRootPart then
                HumanoidRootPart.CFrame = target.CFrame * CFrame.new(0, 3, 0)
                if config.useRemote then fireRemote("HitBreakable", target.Parent) end
                if config.useClick then clickPart(target) end
                fireRemote("CollectOrb")
                fireRemote("CollectLootbag")
            end
            task.wait(config.farmDelay)
        end
        farmThread = nil
    end)
end

local hopThread = nil
local function getLowServers(placeId, maxCount)
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?limit=100"
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if not ok or not res then return {} end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 or not data or not data.data then return {} end
    local out = {}
    for _, s in ipairs(data.data) do
        if s.playing < maxCount and s.id ~= game.JobId then
            table.insert(out, s)
        end
    end
    return out
end
local function startHop()
    if hopThread then return end
    hopThread = task.spawn(function()
        while config.hopEnabled do
            if #Players:GetPlayers() > config.maxPlayers then
                local servers = getLowServers(game.PlaceId, config.maxPlayers)
                if #servers > 0 then
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
                    end)
                    task.wait(10)
                end
            end
            task.wait(config.hopInterval)
        end
        hopThread = nil
    end)
end

local petSlotThread = nil
local function startBuyPetSlot()
    if petSlotThread then return end
    petSlotThread = task.spawn(function()
        while config.autoBuyPetSlot do
            fireRemote("BuyPetSlot")
            fireRemote("PurchasePetSlot")
            fireRemote("BuyPetEquipSlot")
            jitterWait(5)
        end
        petSlotThread = nil
    end)
end

local eggSlotThread = nil
local function startBuyEggSlot()
    if eggSlotThread then return end
    eggSlotThread = task.spawn(function()
        while config.autoBuyEggSlot do
            fireRemote("BuyEggSlot")
            fireRemote("PurchaseEggSlot")
            fireRemote("BuyEggBundleSlot")
            jitterWait(5)
        end
        eggSlotThread = nil
    end)
end

local buyMapThread = nil
local function startBuyMap()
    if buyMapThread then return end
    buyMapThread = task.spawn(function()
        while config.autoBuyMap do
            fireRemote("BuyArea")
            fireRemote("UnlockArea")
            fireRemote("PurchaseArea")
            fireRemote("BuyNextArea")
            jitterWait(10)
        end
        buyMapThread = nil
    end)
end

local teleBestThread = nil
local function startTeleBest()
    if teleBestThread then return end
    teleBestThread = task.spawn(function()
        while config.autoTeleBest do
            fireRemote("TeleportToBestArea")
            fireRemote("TeleportBestArea")
            fireRemote("BestArea")
            jitterWait(15)
        end
        teleBestThread = nil
    end)
end

local bestWorldThread = nil
local function startBestWorld()
    if bestWorldThread then return end
    bestWorldThread = task.spawn(function()
        while config.autoBestWorld do
            fireRemote("TeleportToBestWorld")
            fireRemote("BestWorld")
            fireRemote("AutoBestWorld")
            jitterWait(20)
        end
        bestWorldThread = nil
    end)
end

LocalPlayer.Idled:Connect(function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end)

stage("14. features ready")

-- ═══════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PS99DeltaFull"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = parent

stage("15. main ScreenGui created")

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 56, 0, 56)
toggleBtn.Position = UDim2.new(0, 16, 0, 100)
toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
toggleBtn.TextColor3 = Color3.fromRGB(0, 200, 255)
toggleBtn.Text = "P"
toggleBtn.TextSize = 26
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = ScreenGui

stage("16. toggle button created")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 420)
mainFrame.Position = UDim2.new(0.5, -140, 0.5, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = ScreenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 34)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(0, 200, 255)
title.Text = "PS99 Delta Full"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = mainFrame
closeBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -42)
scroll.Position = UDim2.new(0, 6, 0, 38)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 150, 200)
scroll.CanvasSize = UDim2.new(0, 0, 0, 520)
scroll.Parent = mainFrame

stage("17. main frame + scroll built")

local yPos = 0
local function makeToggle(label, toggler)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -8, 0, 34)
    btn.Position = UDim2.new(0, 4, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
    btn.TextColor3 = Color3.fromRGB(200, 200, 200)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Text = label .. "  ·  OFF"
    btn.Parent = scroll

    local active = false
    btn.MouseButton1Click:Connect(function()
        active = not active
        btn.Text = label .. (active and "  ·  ON" or "  ·  OFF")
        btn.BackgroundColor3 = active and Color3.fromRGB(0, 80, 100) or Color3.fromRGB(36, 36, 48)
        toggler(active)
    end)

    yPos = yPos + 38
    scroll.CanvasSize = UDim2.new(0, 0, 0, yPos + 8)
end

-- drag toggle button
local dragging, dragStart, startPos
toggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = toggleBtn.Position
    end
end)
toggleBtn.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        toggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
toggleBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        local moved = math.abs(input.Position.X - dragStart.X) + math.abs(input.Position.Y - dragStart.Y)
        if moved < 10 then
            mainFrame.Visible = not mainFrame.Visible
        end
    end
end)

-- drag main frame
local fDrag, fStart, fPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag = true
        fStart = input.Position
        fPos = mainFrame.Position
    end
end)
title.InputChanged:Connect(function(input)
    if fDrag and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - fStart
        mainFrame.Position = UDim2.new(fPos.X.Scale, fPos.X.Offset + delta.X, fPos.Y.Scale, fPos.Y.Offset + delta.Y)
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag = false
    end
end)

stage("18. drag handlers attached")

-- toggles
makeToggle("Infinite Pet Speed", function(on)
    config.petSpeed = on
    if on then startPetSpeed() else petSpeedThread = nil end
end)
makeToggle("Auto Tap FAST", function(on)
    config.autoTap = on
    if on then startTap() else tapThread = nil end
end)
makeToggle("Fast Farm", function(on)
    config.fastFarm = on
    if on then startFarm() else farmThread = nil end
end)
makeToggle("Auto Low-Player Server", function(on)
    config.hopEnabled = on
    if on then startHop() else hopThread = nil end
end)
makeToggle("Auto Buy Pet Slot", function(on)
    config.autoBuyPetSlot = on
    if on then startBuyPetSlot() else petSlotThread = nil end
end)
makeToggle("Auto Buy Egg Slot", function(on)
    config.autoBuyEggSlot = on
    if on then startBuyEggSlot() else eggSlotThread = nil end
end)
makeToggle("Auto Buy New Map", function(on)
    config.autoBuyMap = on
    if on then startBuyMap() else buyMapThread = nil end
end)
makeToggle("Auto Tele Best Map", function(on)
    config.autoTeleBest = on
    if on then startTeleBest() else teleBestThread = nil end
end)
makeToggle("Auto Best World", function(on)
    config.autoBestWorld = on
    if on then startBestWorld() else bestWorldThread = nil end
end)
makeToggle("Antiban (jitter)", function(on)
    config.antiban = on
end)

stage("19. toggles built")

-- debug panel
makeToggle("Debug Info", function(on)
    config.debug = on
    local existing = parent:FindFirstChild("PS99Debug")
    if on and not existing then
        local dbg = Instance.new("ScreenGui")
        dbg.Name = "PS99Debug"
        dbg.ResetOnSpawn = false
        dbg.Parent = parent

        local box = Instance.new("Frame")
        box.Size = UDim2.new(0, 240, 0, 140)
        box.Position = UDim2.new(0, 10, 1, -160)
        box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        box.BackgroundTransparency = 0.3
        box.Parent = dbg

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 1, -10)
        lbl.Position = UDim2.new(0, 5, 0, 5)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(0, 255, 100)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Text = ""
        lbl.Parent = box

        task.spawn(function()
            while config.debug do
                local things = workspace:FindFirstChild("__THINGS")
                local net = ReplicatedStorage:FindFirstChild("Network")
                local br = things and things:FindFirstChild("Breakables")
                local pets = things and things:FindFirstChild("Pets")
                lbl.Text = string.format(
                    "Things: %s\nNetwork: %s\nBreakables: %s\nPets: %s\nPlayers: %d\nHRP: %s",
                    things and "OK" or "nil",
                    net and "OK" or "nil",
                    br and "OK" or "nil",
                    pets and "OK" or "nil",
                    #Players:GetPlayers(),
                    HumanoidRootPart and "OK" or "nil"
                )
                task.wait(1)
            end
        end)
    elseif existing and not on then
        existing:Destroy()
    end
end)

stage("20. done")

-- remove loading overlay after 2s
task.delay(2, function()
    if LoadGui then LoadGui:Destroy() end
end)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "PS99 Delta Full",
        Text = "Loaded. Tap P.",
        Duration = 3,
    })
end)
