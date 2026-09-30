--[[
    PS99 Delta Full Auto v4
    error capture build — shows any failure on screen
]]

local parent = (gethui and gethui()) or game:GetService("CoreGui")

local LoadGui = Instance.new("ScreenGui")
LoadGui.Name = "PS99Loading"
LoadGui.ResetOnSpawn = false
LoadGui.Parent = parent

local loadFrame = Instance.new("Frame")
loadFrame.Size = UDim2.new(0, 280, 0, 110)
loadFrame.Position = UDim2.new(0.5, -140, 0.5, -55)
loadFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
loadFrame.BorderSizePixel = 0
loadFrame.Parent = LoadGui

local loadTitle = Instance.new("TextLabel")
loadTitle.Size = UDim2.new(1, -20, 0, 26)
loadTitle.Position = UDim2.new(0, 10, 0, 6)
loadTitle.BackgroundTransparency = 1
loadTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
loadTitle.Text = "PS99 — loading"
loadTitle.Font = Enum.Font.GothamBold
loadTitle.TextSize = 14
loadTitle.TextXAlignment = Enum.TextXAlignment.Left
loadTitle.Parent = loadFrame

local loadStatus = Instance.new("TextLabel")
loadStatus.Size = UDim2.new(1, -20, 0, 70)
loadStatus.Position = UDim2.new(0, 10, 0, 34)
loadStatus.BackgroundTransparency = 1
loadStatus.TextColor3 = Color3.fromRGB(200, 220, 200)
loadStatus.Text = "starting..."
loadStatus.Font = Enum.Font.Code
loadStatus.TextSize = 12
loadStatus.TextXAlignment = Enum.TextXAlignment.Left
loadStatus.TextYAlignment = Enum.TextYAlignment.Top
loadStatus.TextWrapped = true
loadStatus.Parent = loadFrame

local function setStatus(msg)
    pcall(function()
        loadStatus.Text = tostring(msg)
    end)
end

local ok, err = pcall(function()

setStatus("1. start")

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

setStatus("2. config ok")

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
setStatus("3. services ok")

local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 5)
local Camera = workspace.CurrentCamera
setStatus("4. char + camera ok")

-- ═══════════════════════════════════════════
-- REFS
-- ═══════════════════════════════════════════

local Things      = workspace:FindFirstChild("__THINGS")
local Breakables  = Things and Things:FindFirstChild("Breakables")
local Orbs        = Things and Things:FindFirstChild("Orbs")
local Lootbags    = Things and Things:FindFirstChild("Lootbags")
local Pets        = Things and Things:FindFirstChild("Pets")
local Network     = ReplicatedStorage:FindFirstChild("Network")
setStatus("5. refs: Things=" .. tostring(Things ~= nil) .. " Network=" .. tostring(Network ~= nil))

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

setStatus("6. rescan started")

-- ═══════════════════════════════════════════
-- ANTIBAN
-- ═══════════════════════════════════════════

local antiban = {
    enabled     = true,
    lastFire    = {},
    cooldowns   = {},
    pauseMin    = 1.5,
    pauseMax    = 4.0,
    pauseChance = 0.02,
    jitterMin   = 0.7,
    jitterMax   = 1.6,
    clickSpread = 8,
    interpolate = true,
}

local function setCooldown(n, s) antiban.cooldowns[n] = s end
local function canFire(n)
    if not antiban.enabled then return true end
    local last = antiban.lastFire[n]
    if not last then return true end
    return (tick() - last) >= (antiban.cooldowns[n] or 0.1)
end
local function markFired(n) antiban.lastFire[n] = tick() end
local function jitterDelay(base)
    if not antiban.enabled then return base end
    return base * (antiban.jitterMin + math.random() * (antiban.jitterMax - antiban.jitterMin))
end
local function humanPauseCheck()
    if not antiban.enabled then return end
    if math.random() < antiban.pauseChance then
        task.wait(antiban.pauseMin + math.random() * (antiban.pauseMax - antiban.pauseMin))
    end
end
local function randomClickOffset()
    if not antiban.enabled then return 0, 0 end
    local r = antiban.clickSpread
    return (math.random() * 2 - 1) * r, (math.random() * 2 - 1) * r
end
local function smoothMove(targetCFrame)
    if not HumanoidRootPart or not HumanoidRootPart.Parent then return end
    if not antiban.enabled or not antiban.interpolate then
        HumanoidRootPart.CFrame = targetCFrame
        return
    end
    local start = HumanoidRootPart.CFrame
    for i = 1, 4 do
        HumanoidRootPart.CFrame = start:Lerp(targetCFrame, i / 4)
        task.wait(0.02)
    end
end

setStatus("7. antiban ready")

-- ═══════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════

local function xzDist(a, b)
    if not a or not b then return math.huge end
    local dx = a.Position.X - b.Position.X
    local dz = a.Position.Z - b.Position.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function fireRemote(name, ...)
    if not Network then return false end
    if not canFire(name) then return false end
    local remote = Network:FindFirstChild(name)
    if not remote then return false end
    pcall(function() remote:FireServer(...) end)
    markFired(name)
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
            if d < bestDist then best, bestDist = hb, d end
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
        local ox, oy = randomClickOffset()
        clickAt(pos.X + ox, pos.Y + oy)
        return true
    end
    return false
end

setStatus("8. utility ready")

setCooldown("HitBreakable", 0.15)
setCooldown("CollectOrb", 0.5)
setCooldown("CollectLootbag", 0.5)
setCooldown("BuyPetSlot", 8)
setCooldown("BuyEggSlot", 8)
setCooldown("BuyArea", 12)
setCooldown("UnlockArea", 12)
setCooldown("TeleportToBestArea", 20)
setCooldown("TeleportToBestWorld", 25)

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
                    if hrp then hrp.CFrame = rootCF * CFrame.new(0, 0, -3) end
                end
            end
            task.wait(jitterDelay(0.03))
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
            humanPauseCheck()
            task.wait(jitterDelay(config.tapDelay))
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
                smoothMove(target.CFrame * CFrame.new(0, 3, 0))
                if config.useRemote then fireRemote("HitBreakable", target.Parent) end
                if config.useClick then clickPart(target) end
                fireRemote("CollectOrb")
                fireRemote("CollectLootbag")
            end
            humanPauseCheck()
            task.wait(jitterDelay(config.farmDelay))
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
        if s.playing < maxCount and s.id ~= game.JobId then table.insert(out, s) end
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
            task.wait(jitterDelay(5))
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
            task.wait(jitterDelay(5))
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
            task.wait(jitterDelay(10))
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
            task.wait(jitterDelay(15))
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
            task.wait(jitterDelay(20))
        end
        bestWorldThread = nil
    end)
end

LocalPlayer.Idled:Connect(function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end)

setStatus("9. features ready")

-- ═══════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PS99DeltaFull"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = parent

setStatus("10. ScreenGui")

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

setStatus("11. main frame")

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
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -42)
scroll.Position = UDim2.new(0, 6, 0, 38)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 150, 200)
scroll.CanvasSize = UDim2.new(0, 0, 0, 520)
scroll.Parent = mainFrame

setStatus("12. scroll ready")

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

-- drag
local dragging, dragStart, startPos
toggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = input.Position; startPos = toggleBtn.Position
    end
end)
toggleBtn.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = input.Position - dragStart
        toggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
toggleBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        local moved = math.abs(input.Position.X - dragStart.X) + math.abs(input.Position.Y - dragStart.Y)
        if moved < 10 then mainFrame.Visible = not mainFrame.Visible end
    end
end)

local fDrag, fStart, fPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag = true; fStart = input.Position; fPos = mainFrame.Position
    end
end)
title.InputChanged:Connect(function(input)
    if fDrag and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = input.Position - fStart
        mainFrame.Position = UDim2.new(fPos.X.Scale, fPos.X.Offset + d.X, fPos.Y.Scale, fPos.Y.Offset + d.Y)
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag = false
    end
end)

setStatus("13. drag handlers")

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
    antiban.enabled = on
end)

setStatus("14. toggles built")

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
        lbl.Parent = box
        task.spawn(function()
            while config.debug do
                local things = workspace:FindFirstChild("__THINGS")
                local net = ReplicatedStorage:FindFirstChild("Network")
                local br = things and things:FindFirstChild("Breakables")
                local pets = things and things:FindFirstChild("Pets")
                lbl.Text = string.format(
                    "Things: %s\nNetwork: %s\nBreakables: %s\nPets: %s\nPlayers: %d",
                    things and "OK" or "nil",
                    net and "OK" or "nil",
                    br and "OK" or "nil",
                    pets and "OK" or "nil",
                    #Players:GetPlayers()
                )
                task.wait(1)
            end
        end)
    elseif existing and not on then
        existing:Destroy()
    end
end)

setStatus("15. done — removing overlay")

end)

if not ok then
    setStatus("ERROR:\n" .. tostring(err))
    task.wait(30)
else
    task.wait(1.5)
end

if LoadGui then LoadGui:Destroy() end
