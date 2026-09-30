--[[
    PS99 Delta Auto v5 — self-discovering
    scans game structure on load, adapts to whatever it finds
    author: outcome for He
]]

-- ═══════════════════════════════════════════
-- GUI PARENT
-- ═══════════════════════════════════════════

local parent = (gethui and gethui()) or game:GetService("CoreGui")

-- remove old builds
for _, name in ipairs({"PS99DeltaFull", "PS99Loading", "PS99Debug", "RefTest", "Ptest"}) do
    local old = parent:FindFirstChild(name)
    if old then old:Destroy() end
end

-- ═══════════════════════════════════════════
-- STATUS PANEL (always visible during dev)
-- ═══════════════════════════════════════════

local StatusGui = Instance.new("ScreenGui")
StatusGui.Name = "PS99Status"
StatusGui.ResetOnSpawn = false
StatusGui.Parent = parent

local statusFrame = Instance.new("Frame")
statusFrame.Size = UDim2.new(0, 300, 0, 180)
statusFrame.Position = UDim2.new(0, 10, 0, 10)
statusFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
statusFrame.BackgroundTransparency = 0.25
statusFrame.BorderSizePixel = 0
statusFrame.Parent = StatusGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -10, 1, -10)
statusLabel.Position = UDim2.new(0, 5, 0, 5)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.Text = "loading..."
statusLabel.Parent = statusFrame

local statusLines = {}
local function log(msg)
    table.insert(statusLines, tostring(msg))
    if #statusLines > 20 then table.remove(statusLines, 1) end
    statusLabel.Text = table.concat(statusLines, "\n")
end

-- ═══════════════════════════════════════════
-- SCAN
-- ═══════════════════════════════════════════

log("[scan] start")

local function findFirst(parent, names)
    for _, n in ipairs(names) do
        local c = parent:FindFirstChild(n)
        if c then return c end
    end
    return nil
end

local function findDeep(parent, names, depth)
    depth = depth or 3
    if depth <= 0 then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        for _, n in ipairs(names) do
            if c.Name == n then return c end
        end
        local d = findDeep(c, names, depth - 1)
        if d then return d end
    end
    return nil
end

local Things = workspace:FindFirstChild("__THINGS")
log("[scan] __THINGS: " .. tostring(Things ~= nil))

local Breakables = Things and findFirst(Things, {"Breakables", "Breakable"})
local Pets       = Things and findFirst(Things, {"Pets", "Pet"})
local Orbs       = Things and findFirst(Things, {"Orbs", "Orb", "Coins"})
local Lootbags   = Things and findFirst(Things, {"Lootbags", "Lootbag", "Bags"})

log("[scan] Breakables: " .. tostring(Breakables ~= nil))
log("[scan] Pets: " .. tostring(Pets ~= nil))
log("[scan] Orbs: " .. tostring(Orbs ~= nil))
log("[scan] Lootbags: " .. tostring(Lootbags ~= nil))

local Network = game.ReplicatedStorage:FindFirstChild("Network")
log("[scan] Network: " .. tostring(Network ~= nil))

-- build remote map
local remotes = {}
if Network then
    for _, r in ipairs(Network:GetChildren()) do
        remotes[r.Name] = r
    end
    log("[scan] remotes found: " .. tostring(#Network:GetChildren()))
end

-- remote matcher — find first remote containing any keyword
local function findRemote(...)
    local keys = {...}
    for name, remote in pairs(remotes) do
        local lower = name:lower()
        local allMatch = true
        for _, k in ipairs(keys) do
            if not lower:find(k:lower(), 1, true) then
                allMatch = false
                break
            end
        end
        if allMatch then return remote, name end
    end
    return nil
end

local hitRemote       = findRemote("hit")
local collectOrbR     = findRemote("collect", "orb") or findRemote("orb")
local collectBagR     = findRemote("collect", "bag") or findRemote("lootbag")
local buyPetSlotR     = findRemote("buy", "pet") or findRemote("purchase", "pet")
local buyEggSlotR     = findRemote("buy", "egg") or findRemote("purchase", "egg")
local buyAreaR        = findRemote("buy", "area") or findRemote("unlock")
local teleBestAreaR   = findRemote("teleport") or findRemote("best", "area")

log("[remote] hit: " .. tostring(hitRemote and hitRemote.Name or "nil"))
log("[remote] collectOrb: " .. tostring(collectOrbR and collectOrbR.Name or "nil"))
log("[remote] collectBag: " .. tostring(collectBagR and collectBagR.Name or "nil"))
log("[remote] buyPetSlot: " .. tostring(buyPetSlotR and buyPetSlotR.Name or "nil"))
log("[remote] buyEggSlot: " .. tostring(buyEggSlotR and buyEggSlotR.Name or "nil"))
log("[remote] buyArea: " .. tostring(buyAreaR and buyAreaR.Name or "nil"))

-- ═══════════════════════════════════════════
-- SERVICES / LOCAL
-- ═══════════════════════════════════════════

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")
local LocalPlayer         = Players.LocalPlayer
local Camera              = workspace.CurrentCamera

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 5)

LocalPlayer.CharacterAdded:Connect(function(c)
    Character = c
    HumanoidRootPart = c:WaitForChild("HumanoidRootPart", 5)
end)

log("[ok] player ready")

-- ═══════════════════════════════════════════
-- CONFIG + ANTIBAN
-- ═══════════════════════════════════════════

local config = {
    petSpeed = false,
    autoTap = false,
    fastFarm = false,
    hopEnabled = false,
    autoBuyPetSlot = false,
    autoBuyEggSlot = false,
    autoBuyMap = false,
    autoTeleBest = false,
    maxPlayers = 4,
    hopInterval = 30,
    farmDelay = 0.06,
    tapDelay = 0.02,
    antiban = true,
}

local antiban = {
    enabled = true,
    lastFire = {},
    cooldowns = {},
    jitterMin = 0.7,
    jitterMax = 1.7,
    clickSpread = 6,
    pauseMin = 1.0,
    pauseMax = 3.0,
    pauseChance = 0.015,
}

local function canFire(key)
    if not antiban.enabled then return true end
    local last = antiban.lastFire[key]
    if not last then return true end
    return (tick() - last) >= (antiban.cooldowns[key] or 0.1)
end

local function markFired(key)
    antiban.lastFire[key] = tick()
end

local function jitter(base)
    if not antiban.enabled then return base end
    return base * (antiban.jitterMin + math.random() * (antiban.jitterMax - antiban.jitterMin))
end

local function humanPause()
    if not antiban.enabled then return end
    if math.random() < antiban.pauseChance then
        task.wait(antiban.pauseMin + math.random() * (antiban.pauseMax - antiban.pauseMin))
    end
end

-- safe fire wrapper
local function fire(remote, key, ...)
    if not remote then return false end
    if not canFire(key or remote.Name) then return false end
    local ok = pcall(function() remote:FireServer(...) end)
    if ok then markFired(key or remote.Name) end
    return ok
end

-- ═══════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════

local function xzDist(a, b)
    if not a or not b then return math.huge end
    local dx = a.Position.X - b.Position.X
    local dz = a.Position.Z - b.Position.Z
    return math.sqrt(dx * dx + dz * dz)
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
    local best, bd = nil, math.huge
    for _, obj in ipairs(Breakables:GetChildren()) do
        local hb = getHitbox(obj)
        if hb then
            local d = xzDist(hb, HumanoidRootPart)
            if d < bd then best, bd = hb, d end
        end
    end
    return best
end

local function clickAt(x, y)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
end

local function clickPart(part)
    local pos, onScreen = Camera:WorldToScreenPoint(part.Position)
    if onScreen then
        local ox = (math.random() * 2 - 1) * antiban.clickSpread
        local oy = (math.random() * 2 - 1) * antiban.clickSpread
        clickAt(pos.X + ox, pos.Y + oy)
        return true
    end
    return false
end

local function smoothMove(cf)
    if not HumanoidRootPart or not HumanoidRootPart.Parent then return end
    if not antiban.enabled then
        HumanoidRootPart.CFrame = cf
        return
    end
    local start = HumanoidRootPart.CFrame
    for i = 1, 4 do
        HumanoidRootPart.CFrame = start:Lerp(cf, i / 4)
        task.wait(0.02)
    end
end

-- cooldowns
antiban.cooldowns.hit = 0.12
antiban.cooldowns.collectOrb = 0.4
antiban.cooldowns.collectBag = 0.4
antiban.cooldowns.buyPetSlot = 6
antiban.cooldowns.buyEggSlot = 6
antiban.cooldowns.buyArea = 10

-- ═══════════════════════════════════════════
-- FEATURE LOOPS
-- ═══════════════════════════════════════════

local threads = {}

local function spawnLoop(name, fn)
    if threads[name] then return end
    threads[name] = task.spawn(function()
        local ok, err = pcall(fn)
        threads[name] = nil
        if not ok then log("[err] " .. name .. ": " .. tostring(err)) end
    end)
end

-- pet speed
spawnLoop("petSpeed", function()
    while config.petSpeed do
        if Pets and HumanoidRootPart and HumanoidRootPart.Parent then
            local rootCF = HumanoidRootPart.CFrame
            for _, pet in ipairs(Pets:GetChildren()) do
                local hrp = pet:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = rootCF * CFrame.new(0, 0, -3) end
            end
        end
        task.wait(jitter(0.03))
    end
end)

-- auto tap
spawnLoop("autoTap", function()
    while config.autoTap do
        local t = nearestBreakable()
        if t then clickPart(t) end
        humanPause()
        task.wait(jitter(config.tapDelay))
    end
end)

-- fast farm
spawnLoop("fastFarm", function()
    while config.fastFarm do
        local t = nearestBreakable()
        if t and HumanoidRootPart then
            smoothMove(t.CFrame * CFrame.new(0, 3, 0))
            fire(hitRemote, "hit", t.Parent)
            clickPart(t)
            fire(collectOrbR, "collectOrb")
            fire(collectBagR, "collectBag")
        end
        humanPause()
        task.wait(jitter(config.farmDelay))
    end
end)

-- server hop
spawnLoop("serverHop", function()
    while config.hopEnabled do
        if #Players:GetPlayers() > config.maxPlayers then
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok and res then
                local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
                if ok2 and data and data.data then
                    for _, s in ipairs(data.data) do
                        if s.playing < config.maxPlayers and s.id ~= game.JobId then
                            pcall(function()
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                            end)
                            task.wait(10)
                            break
                        end
                    end
                end
            end
        end
        task.wait(config.hopInterval)
    end
end)

-- buy loops
spawnLoop("buyPetSlot", function()
    while config.autoBuyPetSlot do
        fire(buyPetSlotR, "buyPetSlot")
        task.wait(jitter(5))
    end
end)

spawnLoop("buyEggSlot", function()
    while config.autoBuyEggSlot do
        fire(buyEggSlotR, "buyEggSlot")
        task.wait(jitter(5))
    end
end)

spawnLoop("buyMap", function()
    while config.autoBuyMap do
        fire(buyAreaR, "buyArea")
        task.wait(jitter(10))
    end
end)

-- anti-afk
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end)

log("[ok] features ready")

-- ═══════════════════════════════════════════
-- MAIN GUI
-- ═══════════════════════════════════════════

local sg = Instance.new("ScreenGui")
sg.Name = "PS99DeltaFull"
sg.ResetOnSpawn = false
sg.Parent = parent

local pbtn = Instance.new("TextButton")
pbtn.Size = UDim2.new(0, 56, 0, 56)
pbtn.Position = UDim2.new(0, 16, 0, 220)
pbtn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
pbtn.TextColor3 = Color3.fromRGB(0, 200, 255)
pbtn.Text = "P"
pbtn.TextSize = 26
pbtn.Font = Enum.Font.GothamBold
pbtn.Parent = sg

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 280, 0, 420)
main.Position = UDim2.new(0.5, -140, 0.5, -210)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
main.BorderSizePixel = 0
main.Visible = false
main.Parent = sg

local ttl = Instance.new("TextLabel")
ttl.Size = UDim2.new(1, -40, 0, 34)
ttl.Position = UDim2.new(0, 10, 0, 0)
ttl.BackgroundTransparency = 1
ttl.TextColor3 = Color3.fromRGB(0, 200, 255)
ttl.Text = "PS99 v5"
ttl.Font = Enum.Font.GothamBold
ttl.TextSize = 14
ttl.TextXAlignment = Enum.TextXAlignment.Left
ttl.Parent = main

local xbtn = Instance.new("TextButton")
xbtn.Size = UDim2.new(0, 24, 0, 24)
xbtn.Position = UDim2.new(1, -30, 0, 6)
xbtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
xbtn.TextColor3 = Color3.fromRGB(255, 200, 200)
xbtn.Text = "X"
xbtn.Font = Enum.Font.GothamBold
xbtn.TextSize = 14
xbtn.Parent = main
xbtn.MouseButton1Click:Connect(function() main.Visible = false end)

local sc = Instance.new("ScrollingFrame")
sc.Size = UDim2.new(1, -12, 1, -42)
sc.Position = UDim2.new(0, 6, 0, 38)
sc.BackgroundTransparency = 1
sc.BorderSizePixel = 0
sc.ScrollBarThickness = 4
sc.ScrollBarImageColor3 = Color3.fromRGB(0, 150, 200)
sc.CanvasSize = UDim2.new(0, 0, 0, 500)
sc.Parent = main

local yP = 0
local function mkToggle(label, fn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 34)
    b.Position = UDim2.new(0, 4, 0, yP)
    b.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
    b.TextColor3 = Color3.fromRGB(200, 200, 200)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.Text = label .. "  ·  OFF"
    b.Parent = sc
    local active = false
    b.MouseButton1Click:Connect(function()
        active = not active
        b.Text = label .. (active and "  ·  ON" or "  ·  OFF")
        b.BackgroundColor3 = active and Color3.fromRGB(0, 80, 100) or Color3.fromRGB(36, 36, 48)
        fn(active)
    end)
    yP = yP + 38
    sc.CanvasSize = UDim2.new(0, 0, 0, yP + 8)
end

-- drag P
local drag, ds, sp
pbtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag = true; ds = i.Position; sp = pbtn.Position
    end
end)
pbtn.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - ds
        pbtn.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
end)
pbtn.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag = false
        if math.abs(i.Position.X - ds.X) + math.abs(i.Position.Y - ds.Y) < 10 then
            main.Visible = not main.Visible
        end
    end
end)

-- drag main
local fd, fs, fp
ttl.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        fd = true; fs = i.Position; fp = main.Position
    end
end)
ttl.InputChanged:Connect(function(i)
    if fd and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - fs
        main.Position = UDim2.new(fp.X.Scale, fp.X.Offset + d.X, fp.Y.Scale, fp.Y.Offset + d.Y)
    end
end)
ttl.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        fd = false
    end
end)

mkToggle("Infinite Pet Speed", function(on)
    config.petSpeed = on
    if on then spawnLoop("petSpeed", function()
        while config.petSpeed do
            if Pets and HumanoidRootPart and HumanoidRootPart.Parent then
                local rootCF = HumanoidRootPart.CFrame
                for _, pet in ipairs(Pets:GetChildren()) do
                    local hrp = pet:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CFrame = rootCF * CFrame.new(0, 0, -3) end
                end
            end
            task.wait(jitter(0.03))
        end
    end) end
end)

mkToggle("Auto Tap FAST", function(on)
    config.autoTap = on
    if on then spawnLoop("autoTap", function()
        while config.autoTap do
            local t = nearestBreakable()
            if t then clickPart(t) end
            humanPause()
            task.wait(jitter(config.tapDelay))
        end
    end) end
end)

mkToggle("Fast Farm", function(on)
    config.fastFarm = on
    if on then spawnLoop("fastFarm", function()
        while config.fastFarm do
            local t = nearestBreakable()
            if t and HumanoidRootPart then
                smoothMove(t.CFrame * CFrame.new(0, 3, 0))
                fire(hitRemote, "hit", t.Parent)
                clickPart(t)
                fire(collectOrbR, "collectOrb")
                fire(collectBagR, "collectBag")
            end
            humanPause()
            task.wait(jitter(config.farmDelay))
        end
    end) end
end)

mkToggle("Auto Low-Player Server", function(on)
    config.hopEnabled = on
    if on then spawnLoop("serverHop", function()
        while config.hopEnabled do
            if #Players:GetPlayers() > config.maxPlayers then
                local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
                local ok, res = pcall(function() return game:HttpGet(url) end)
                if ok and res then
                    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
                    if ok2 and data and data.data then
                        for _, s in ipairs(data.data) do
                            if s.playing < config.maxPlayers and s.id ~= game.JobId then
                                pcall(function()
                                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                                end)
                                task.wait(10)
                                break
                            end
                        end
                    end
                end
            end
            task.wait(config.hopInterval)
        end
    end) end
end)

mkToggle("Auto Buy Pet Slot", function(on)
    config.autoBuyPetSlot = on
    if on then spawnLoop("buyPetSlot", function()
        while config.autoBuyPetSlot do
            fire(buyPetSlotR, "buyPetSlot")
            task.wait(jitter(5))
        end
    end) end
end)

mkToggle("Auto Buy Egg Slot", function(on)
    config.autoBuyEggSlot = on
    if on then spawnLoop("buyEggSlot", function()
        while config.autoBuyEggSlot do
            fire(buyEggSlotR, "buyEggSlot")
            task.wait(jitter(5))
        end
    end) end
end)

mkToggle("Auto Buy New Map", function(on)
    config.autoBuyMap = on
    if on then spawnLoop("buyMap", function()
        while config.autoBuyMap do
            fire(buyAreaR, "buyArea")
            task.wait(jitter(10))
        end
    end) end
end)

mkToggle("Antiban", function(on)
    config.antiban = on
    antiban.enabled = on
end)

mkToggle("Hide Status Panel", function(on)
    statusFrame.Visible = not on
end)

log("[ok] GUI ready")
