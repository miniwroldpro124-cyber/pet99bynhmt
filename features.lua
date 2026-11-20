--[[
    ZapHub / ZapLib 2.0.0 - feature layer

    ZapLib is the interface. It draws the window, the tabs, the elements, the
    config store and the Kaitun overlay - and nothing else. Every feature lives
    in a script that sits on top of it. This is that script.

    Run this alone. It loads the library if it is not already in memory, then
    attaches Farm / Player / Teleport / Visual / Misc tabs to the window it
    finds at _G.ZapLib.Window.

    Recovered constants and the element API come from the deobf in this repo.
    The feature code below is written against that API: CreateTab returns a tab
    whose methods are CreateSection, CreateParagraph, CreateButton, CreateToggle,
    CreateSlider, CreateDropdown, CreateInput, CreateKeybind.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LIB_URL = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/zaphub.lua"

local player = Players.LocalPlayer
if not player then
    return warn("[ZapHub] no LocalPlayer")
end

-- transport: game:HttpGet is a DataModel member in some executors and absent in
-- others (Xeno). request/http_request are the fallbacks that always carry UA.
local function httpGet(url)
    if syn and syn.request then
        local ok, res = pcall(syn.request, { Url = url, Method = "GET" })
        if ok and res and res.Body then
            return res.Body
        end
    end
    if request then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok and res and res.Body then
            return res.Body
        end
    end
    if http_request then
        local ok, res = pcall(http_request, { Url = url, Method = "GET" })
        if ok and res and res.Body then
            return res.Body
        end
    end
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if ok then
        return body
    end
    return nil
end

local lib = _G["ZapLib"]
if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    local src = httpGet(LIB_URL)
    if not src or #src < 1000 then
        return warn("[ZapHub] library fetch failed - run zaphub.lua first, then this")
    end
    local chunk = loadstring(src)
    if not chunk then
        return warn("[ZapHub] library did not compile")
    end
    local ok, err = pcall(chunk)
    if not ok then
        return warn("[ZapHub] library threw: " .. tostring(err))
    end
    lib = _G["ZapLib"]
end

if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    return warn("[ZapHub] library loaded but no window is attached")
end

local win = lib.Window
local ICON = "rbxassetid://16259403210"

local function humanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function root()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function alive()
    local hum = humanoid()
    return hum and hum.Health > 0 and root() ~= nil
end

-- ===========================================================================
-- Farm
-- ===========================================================================

local farm = {
    running = false,
    keyword = "Chest",
    radius = 60,
    reach = 12,
    walk = true,
    click = true,
    mode = "ProximityPrompt",
}

-- one bounded scan; a corrupted or enormous workspace must never hang the loop.
-- explicit stack, not GetDescendants - that materialises the whole tree every
-- tick, and on a big map this loop runs four times a second.
local function collectTargets(keyword, radius)
    local rp = root()
    if not rp then
        return {}
    end
    local origin = rp.Position
    local needle = string.lower(keyword)
    local out = {}
    local seen = 0
    local stack = { Workspace }
    while #stack > 0 do
        local node = table.remove(stack)
        for _, child in ipairs(node:GetChildren()) do
            seen = seen + 1
            if seen > 8000 then
                return out
            end
            if child:IsA("BasePart") then
                if string.find(string.lower(child.Name), needle, 1, true) then
                    local dist = (child.Position - origin).Magnitude
                    if dist <= radius then
                        out[#out + 1] = { part = child, dist = dist }
                    end
                end
            end
            if child:IsA("Model") or child:IsA("Folder") or child:IsA("Workspace") then
                stack[#stack + 1] = child
            end
        end
    end
    table.sort(out, function(a, b)
        return a.dist < b.dist
    end)
    return out
end

local function promptOf(part)
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("ProximityPrompt") then
            return c
        end
    end
    local model = part.Parent
    if model then
        for _, c in ipairs(model:GetDescendants()) do
            if c:IsA("ProximityPrompt") then
                return c
            end
        end
    end
    return nil
end

local function detectorOf(part)
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("ClickDetector") then
            return c
        end
    end
    local model = part.Parent
    if model then
        for _, c in ipairs(model:GetDescendants()) do
            if c:IsA("ClickDetector") then
                return c
            end
        end
    end
    return nil
end

local function walkTo(pos)
    local hum = humanoid()
    if not hum then
        return false
    end
    hum:MoveTo(pos)
    local deadline = os.clock() + 5
    while os.clock() < deadline do
        local rp = root()
        if not rp then
            return false
        end
        if (rp.Position - pos).Magnitude <= farm.reach then
            return true
        end
        task.wait(0.1)
    end
    return false
end

local function actOn(part)
    if farm.mode == "ClickDetector" or not promptOf(part) then
        local det = detectorOf(part)
        if det and fireclickdetector then
            pcall(fireclickdetector, det)
            return true
        end
        return false
    end
    local prompt = promptOf(part)
    if not prompt then
        return false
    end
    pcall(function()
        prompt:InputHoldBegin()
    end)
    task.wait(math.max(tonumber(prompt.HoldDuration) or 0, 0.05) + 0.05)
    pcall(function()
        prompt:InputHoldEnd()
    end)
    return true
end

local function farmLoop()
    while farm.running do
        if not alive() then
            task.wait(0.5)
        else
            local targets = collectTargets(farm.keyword, farm.radius)
            local hit = false
            for _, t in ipairs(targets) do
                if not farm.running then
                    break
                end
                if t.part.Parent then
                    local rp = root()
                    local near = rp and (rp.Position - t.part.Position).Magnitude <= farm.reach
                    if not near and farm.walk then
                        near = walkTo(t.part.Position)
                    end
                    if near and farm.click then
                        hit = actOn(t.part) or hit
                    end
                    if hit then
                        break
                    end
                end
            end
            if not hit then
                task.wait(0.4)
            else
                task.wait(0.15)
            end
        end
    end
end

local function setFarm(on)
    if on and not farm.running then
        farm.running = true
        task.spawn(farmLoop)
    elseif not on then
        farm.running = false
    end
end

-- ===========================================================================
-- Player
-- ===========================================================================

local baseSpeed = 16
local baseJump = 50
local jumpConn

local function applySpeed(v)
    local hum = humanoid()
    if hum then
        pcall(function()
            hum.WalkSpeed = v
        end)
    end
end

local function applyJump(v)
    local hum = humanoid()
    if hum then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = v
        end)
    end
end

local function setInfiniteJump(on)
    if jumpConn then
        jumpConn:Disconnect()
        jumpConn = nil
    end
    if not on then
        return
    end
    jumpConn = UserInputService.JumpRequest:Connect(function()
        local hum = humanoid()
        if hum then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end)
end

-- respawns reset the humanoid, so the values are re-applied on every new body
player.CharacterAdded:Connect(function()
    task.wait(0.5)
    applySpeed(baseSpeed)
    applyJump(baseJump)
end)

-- ===========================================================================
-- Teleport
-- ===========================================================================

local savedPos

local function tp(pos)
    local rp = root()
    if not rp then
        return false
    end
    pcall(function()
        rp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end)
    return true
end

local function playerList()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            out[#out + 1] = p.Name
        end
    end
    table.sort(out)
    if #out == 0 then
        out = { "nobody else here" }
    end
    return out
end

-- ===========================================================================
-- Visual
-- ===========================================================================

local lightBackup

local function setFullbright(on)
    if on then
        if lightBackup then
            return
        end
        lightBackup = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
        }
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
    elseif lightBackup then
        Lighting.Brightness = lightBackup.Brightness
        Lighting.ClockTime = lightBackup.ClockTime
        Lighting.FogEnd = lightBackup.FogEnd
        Lighting.Ambient = lightBackup.Ambient
        Lighting.OutdoorAmbient = lightBackup.OutdoorAmbient
        lightBackup = nil
    end
end

-- ===========================================================================
-- Tabs
-- ===========================================================================

local farmTab = win:CreateTab("Farm", "rbxassetid://82329173638641")

farmTab:CreateSection("Auto Farm")
farmTab:CreateToggle({
    Name = "Auto Farm",
    CurrentValue = false,
    Callback = function(v)
        setFarm(v)
    end,
})
farmTab:CreateInput({
    Name = "Target Name",
    PlaceholderText = "Chest",
    CurrentValue = farm.keyword,
    RemoveTextAfterFocusLost = false,
    Callback = function(v)
        if v ~= "" then
            farm.keyword = v
        end
    end,
})
farmTab:CreateDropdown({
    Name = "Interact With",
    Options = { "ProximityPrompt", "ClickDetector" },
    CurrentOption = farm.mode,
    Callback = function(v)
        farm.mode = v
    end,
})
farmTab:CreateSlider({
    Name = "Search Radius",
    Range = { 10, 400 },
    Increment = 5,
    Suffix = "studs",
    CurrentValue = farm.radius,
    CallbackOnRelease = true,
    Callback = function(v)
        farm.radius = v
    end,
})
farmTab:CreateSlider({
    Name = "Reach",
    Range = { 4, 60 },
    Increment = 1,
    Suffix = "studs",
    CurrentValue = farm.reach,
    CallbackOnRelease = true,
    Callback = function(v)
        farm.reach = v
    end,
})
farmTab:CreateToggle({
    Name = "Walk To Target",
    CurrentValue = true,
    Callback = function(v)
        farm.walk = v
    end,
})
farmTab:CreateToggle({
    Name = "Interact",
    CurrentValue = true,
    Callback = function(v)
        farm.click = v
    end,
})
farmTab:CreateButton({
    Name = "Find Targets Now",
    Callback = function()
        local list = collectTargets(farm.keyword, farm.radius)
        lib:CreateNotification({
            Title = "Auto Farm",
            Content = string.format("%d match(es) for \"%s\" within %d studs", #list, farm.keyword, math.floor(farm.radius)),
        })
    end,
})

local playerTab = win:CreateTab("Player", "rbxassetid://120561115194230")

playerTab:CreateSection("Movement")
playerTab:CreateSlider({
    Name = "Walk Speed",
    Range = { 8, 200 },
    Increment = 1,
    CurrentValue = 16,
    Callback = function(v)
        baseSpeed = v
        applySpeed(v)
    end,
})
playerTab:CreateSlider({
    Name = "Jump Power",
    Range = { 30, 300 },
    Increment = 5,
    CurrentValue = 50,
    Callback = function(v)
        baseJump = v
        applyJump(v)
    end,
})
playerTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Callback = function(v)
        setInfiniteJump(v)
    end,
})
playerTab:CreateButton({
    Name = "Reset Character",
    Callback = function()
        local hum = humanoid()
        if hum then
            hum.Health = 0
        end
    end,
})

local tpTab = win:CreateTab("Teleport", "rbxassetid://16089599792")

tpTab:CreateSection("Position")
tpTab:CreateButton({
    Name = "Save Current Position",
    Callback = function()
        local rp = root()
        if rp then
            savedPos = rp.Position
            lib:CreateNotification({ Title = "Teleport", Content = "Position saved." })
        end
    end,
})
tpTab:CreateButton({
    Name = "Return To Saved Position",
    Callback = function()
        if not savedPos then
            lib:CreateNotification({ Title = "Teleport", Content = "No position saved yet." })
            return
        end
        tp(savedPos)
    end,
})
tpTab:CreateButton({
    Name = "Teleport To Origin",
    Callback = function()
        tp(Vector3.new(0, 0, 0))
    end,
})
tpTab:CreateSection("Players")
local tpSelect
tpSelect = tpTab:CreateDropdown({
    Name = "Player",
    Options = playerList(),
    CurrentOption = playerList()[1],
    Callback = function() end,
})
tpTab:CreateButton({
    Name = "Go To Player",
    Callback = function()
        local name = tpSelect:Get()
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name == name and p.Character then
                local target = p.Character:FindFirstChild("HumanoidRootPart")
                if target then
                    tp(target.Position)
                    return
                end
            end
        end
        lib:CreateNotification({ Title = "Teleport", Content = "That player has no character." })
    end,
})
tpTab:CreateButton({
    Name = "Refresh Player List",
    Callback = function()
        tpSelect:SetOptions(playerList())
    end,
})

local visualTab = win:CreateTab("Visual", "rbxassetid://87867412432006")

visualTab:CreateSection("Lighting")
visualTab:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false,
    Callback = function(v)
        setFullbright(v)
    end,
})

local miscTab = win:CreateTab("Misc", "rbxassetid://16093555964")

miscTab:CreateSection("Server")
miscTab:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
        end)
    end,
})
miscTab:CreateButton({
    Name = "Copy Job ID",
    Callback = function()
        if setclipboard then
            pcall(setclipboard, game.JobId)
            lib:CreateNotification({ Title = "Misc", Content = "Job ID copied." })
        else
            lib:CreateNotification({ Title = "Misc", Content = game.JobId })
        end
    end,
})
miscTab:CreateButton({
    Name = "Server Hop",
    Callback = function()
        local body = httpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?limit=100")
        if not body then
            lib:CreateNotification({ Title = "Misc", Content = "Server list fetch failed." })
            return
        end
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if not ok or type(decoded) ~= "table" or not decoded.data then
            lib:CreateNotification({ Title = "Misc", Content = "Server list unreadable." })
            return
        end
        local pool = {}
        for _, s in ipairs(decoded.data) do
            if s.id ~= game.JobId and (tonumber(s.playing) or 0) < (tonumber(s.maxPlayers) or 0) then
                pool[#pool + 1] = s.id
            end
        end
        if #pool == 0 then
            lib:CreateNotification({ Title = "Misc", Content = "No other open server." })
            return
        end
        local target = pool[math.random(1, #pool)]
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target, player)
        end)
    end,
})
miscTab:CreateSection("Session")
miscTab:CreateButton({
    Name = "Rescan Targets",
    Callback = function()
        local list = collectTargets(farm.keyword, farm.radius)
        lib:CreateNotification({ Title = "Misc", Content = string.format("%d target(s) in range", #list) })
    end,
})
miscTab:CreateButton({
    Name = "Stop Everything",
    Callback = function()
        setFarm(false)
        setInfiniteJump(false)
        setFullbright(false)
    end,
})
miscTab:CreateParagraph({
    Title = "Where the features are",
    Content = "ZapLib is the interface only. These tabs are the feature layer that sits on top of it.",
})

lib:CreateNotification({
    Title = "ZapHub",
    Content = "Feature layer attached. RightControl toggles the window.",
    Duration = 4,
})

return true
