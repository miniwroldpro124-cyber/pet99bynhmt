--[[
    PS99 Delta Full Auto — custom build
    target: Pet Simulator 99
    executor: Delta (Android/PC)
    author: outcome for He
    
    features:
      - infinite pet speed
      - auto tap FAST
      - fast farm
      - auto low-player server
      - auto buy pet slot
      - auto buy egg slot
      - auto buy new map
      - auto tele best map
      - auto best world
      - antiban (jitter + cooldown respect)
]]

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
}

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

local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Camera      = workspace.CurrentCamera

local Network     = ReplicatedStorage:WaitForChild("Network")
local Things      = workspace:WaitForChild("__THINGS")
local Breakables  = Things:WaitForChild("Breakables")
local Orbs        = Things:WaitForChild("Orbs")
local Lootbags    = Things:WaitForChild("Lootbags")
local Pets        = Things:WaitForChild("Pets")

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
end)

-- ═══════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════

local function xzDist(a, b)
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
    local remote = Network:FindFirstChild(name)
    if remote then
        pcall(function()
            remote:FireServer(...)
        end)
        return true
    end
    return false
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
    if not HumanoidRootPart or not HumanoidRootPart.Parent then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(Breakables:GetChildren()) do
        if obj.Name ~= "Highlight" then
            local hb = getHitbox(obj)
            if hb then
                local d = xzDist(hb, HumanoidRootPart)
                if d < bestDist then
                    best, bestDist = hb, d
                end
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

-- ═══════════════════════════════════════════
-- 1. INFINITE PET SPEED
-- ═══════════════════════════════════════════

local petSpeedThread = nil

local function startPetSpeed()
    if petSpeedThread then return end
    petSpeedThread = task.spawn(function()
        while config.petSpeed do
            if HumanoidRootPart and HumanoidRootPart.Parent then
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

-- ═══════════════════════════════════════════
-- 2. AUTO TAP FAST
-- ═══════════════════════════════════════════

local tapThread = nil

local function startTap()
    if tapThread then return end
    tapThread = task.spawn(function()
        while config.autoTap do
            local target = nearestBreakable()
            if target then
                clickPart(target)
            end
            task.wait(config.tapDelay)
        end
        tapThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 3. FAST FARM
-- ═══════════════════════════════════════════

local farmThread = nil

local function startFarm()
    if farmThread then return end
    farmThread = task.spawn(function()
        while config.fastFarm do
            if not HumanoidRootPart or not HumanoidRootPart.Parent then
                Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
            end

            local target = nearestBreakable()
            if target then
                HumanoidRootPart.CFrame = target.CFrame * CFrame.new(0, 3, 0)

                if config.useRemote then
                    fireRemote("HitBreakable", target.Parent)
                end

                if config.useClick then
                    clickPart(target)
                end

                fireRemote("CollectOrb")
                fireRemote("CollectLootbag")
            end

            task.wait(config.farmDelay)
        end
        farmThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 4. AUTO LOW-PLAYER SERVER
-- ═══════════════════════════════════════════

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

local function hopToLowServer()
    local servers = getLowServers(game.PlaceId, config.maxPlayers)
    if #servers > 0 then
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
        end)
    end
end

local function startHop()
    if hopThread then return end
    hopThread = task.spawn(function()
        while config.hopEnabled do
            if #Players:GetPlayers() > config.maxPlayers then
                hopToLowServer()
                task.wait(10)
            end
            task.wait(config.hopInterval)
        end
        hopThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 5. AUTO BUY PET SLOT
-- ═══════════════════════════════════════════

local petSlotThread = nil

local function startBuyPetSlot()
    if petSlotThread then return end
    petSlotThread = task.spawn(function()
        while config.autoBuyPetSlot do
            pcall(function()
                fireRemote("BuyPetSlot")
                fireRemote("PurchasePetSlot")
                fireRemote("BuyPetEquipSlot")
            end)
            jitterWait(5)
        end
        petSlotThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 6. AUTO BUY EGG SLOT
-- ═══════════════════════════════════════════

local eggSlotThread = nil

local function startBuyEggSlot()
    if eggSlotThread then return end
    eggSlotThread = task.spawn(function()
        while config.autoBuyEggSlot do
            pcall(function()
                fireRemote("BuyEggSlot")
                fireRemote("PurchaseEggSlot")
                fireRemote("BuyEggBundleSlot")
            end)
            jitterWait(5)
        end
        eggSlotThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 7. AUTO BUY NEW MAP
-- ═══════════════════════════════════════════

local buyMapThread = nil

local function startBuyMap()
    if buyMapThread then return end
    buyMapThread = task.spawn(function()
        while config.autoBuyMap do
            pcall(function()
                fireRemote("BuyArea")
                fireRemote("UnlockArea")
                fireRemote("PurchaseArea")
                fireRemote("BuyNextArea")
            end)
            jitterWait(10)
        end
        buyMapThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 8. AUTO TELE BEST MAP
-- ═══════════════════════════════════════════

local teleBestThread = nil

local function startTeleBest()
    if teleBestThread then return end
    teleBestThread = task.spawn(function()
        while config.autoTeleBest do
            pcall(function()
                fireRemote("TeleportToBestArea")
                fireRemote("TeleportBestArea")
                fireRemote("BestArea")
            end)
            jitterWait(15)
        end
        teleBestThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- 9. AUTO BEST WORLD
-- ═══════════════════════════════════════════

local bestWorldThread = nil

local function startBestWorld()
    if bestWorldThread then return end
    bestWorldThread = task.spawn(function()
        while config.autoBestWorld do
            pcall(function()
                fireRemote("TeleportToBestWorld")
                fireRemote("BestWorld")
                fireRemote("AutoBestWorld")
            end)
            jitterWait(20)
        end
        bestWorldThread = nil
    end)
end

-- ═══════════════════════════════════════════
-- ANTI-AFK
-- ═══════════════════════════════════════════

LocalPlayer.Idled:Connect(function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end)

-- ═══════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PS99DeltaFull"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 56, 0, 56)
toggleBtn.Position = UDim2.new(0, 16, 0, 100)
toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
toggleBtn.TextColor3 = Color3.fromRGB(0, 200, 255)
toggleBtn.Text = "P"
toggleBtn.TextSize = 26
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = ScreenGui

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

-- drag main frame by title
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

-- TOGGLES
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

-- ═══════════════════════════════════════════
-- STARTUP
-- ═══════════════════════════════════════════

StarterGui:SetCore("SendNotification", {
    Title = "PS99 Delta Full",
    Text = "Loaded. Tap P to open.",
    Duration = 3,
})
