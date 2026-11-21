--[[
    ZAPX - PS99 loader
    ------------------
    Own menu, own rendering, no ZapLib. The farm engine is fetched and patched
    headless before it loads, so the grey PS99 CLEAN panel never exists and the
    only window on screen is this one.

    RightControl  show / hide
    Insert        unused (engine panel is removed)
    X             unload
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "ZAPX must run on the client")

local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/"
local VERSION = "5.0"

--------------------------------------------------------------------- theme

local T = {
    bg = Color3.fromRGB(14, 16, 21),
    panel = Color3.fromRGB(20, 23, 30),
    raised = Color3.fromRGB(29, 33, 43),
    raised2 = Color3.fromRGB(38, 43, 55),
    accent = Color3.fromRGB(125, 212, 236),
    text = Color3.fromRGB(226, 232, 240),
    muted = Color3.fromRGB(138, 148, 163),
    good = Color3.fromRGB(122, 216, 152),
    bad = Color3.fromRGB(238, 128, 128),
}

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

local function make(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function corner(parent, radius)
    make("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function stroke(parent, colour, transparency)
    make("UIStroke", {
        Color = colour or T.raised2,
        Transparency = transparency or 0.5,
        Thickness = 1,
    }, parent)
end

local function pad(parent, all)
    make("UIPadding", {
        PaddingTop = UDim.new(0, all),
        PaddingBottom = UDim.new(0, all),
        PaddingLeft = UDim.new(0, all),
        PaddingRight = UDim.new(0, all),
    }, parent)
end

----------------------------------------------------------------- utilities

local notes = {}
local alive = true

local function notify(title, content)
    notes[#notes + 1] = { title = tostring(title), content = tostring(content), at = os.clock() }
    if #notes > 40 then table.remove(notes, 1) end
    print(("[ZAPX] %s: %s"):format(title, content))
end

local function httpGet(url)
    for _, call in ipairs({
        function() return syn.request({ Url = url, Method = "GET" }).Body end,
        function() return request({ Url = url, Method = "GET" }).Body end,
        function() return http_request({ Url = url, Method = "GET" }).Body end,
        function() return game:HttpGet(url) end,
    }) do
        local ok, body = pcall(call)
        if ok and type(body) == "string" and #body > 100 then
            return body
        end
    end
    return nil
end

local function replaceOnce(source, needle, replacement)
    local index = source:find(needle, 1, true)
    if not index then
        return source, false
    end
    return source:sub(1, index - 1) .. replacement .. source:sub(index + #needle), true
end

--------------------------------------------------------------- engine load

local engine = rawget(_G, "__PS99CLEAN")
if type(engine) ~= "table" or type(engine.SetEnabled) ~= "function" then
    local source = httpGet(BASE .. "ps99_engine_v2.lua?zapx=" .. VERSION)
    if not source then
        return warn("[ZAPX] engine download failed")
    end

    -- Headless: buildGUI returns before creating anything, and the Insert
    -- handler that would index it is guarded. Both replacements are asserted so
    -- a changed engine can never leave the grey panel half built.
    local ok
    source, ok = replaceOnce(source,
        "local function buildGUI()\n    local playerGui",
        "local function buildGUI()\n    if true then return end\n    local playerGui")
    if not ok then
        return warn("[ZAPX] engine patch 1 failed - buildGUI signature changed")
    end

    source, ok = replaceOnce(source,
        "if not processed and input.KeyCode == Enum.KeyCode.Insert then gui.root.Enabled = not gui.root.Enabled end",
        "if not processed and input.KeyCode == Enum.KeyCode.Insert and gui.root then gui.root.Enabled = not gui.root.Enabled end")
    if not ok then
        return warn("[ZAPX] engine patch 2 failed - Insert handler changed")
    end

    local chunk, err = loadstring(source, "=ps99_engine")
    if not chunk then
        return warn("[ZAPX] engine compile: " .. tostring(err))
    end
    local ran, runErr = pcall(chunk)
    if not ran then
        return warn("[ZAPX] engine boot: " .. tostring(runErr))
    end
    engine = rawget(_G, "__PS99CLEAN")
end
if type(engine) ~= "table" then
    return warn("[ZAPX] engine loaded but published no controller")
end

-- Belt and braces: if any engine build slipped through, kill the panel.
do
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        local stale = pg:FindFirstChild("PS99CLEAN")
        if stale then stale:Destroy() end
        pg.ChildAdded:Connect(function(child)
            if child.Name == "PS99CLEAN" then
                child:Destroy()
            end
        end)
    end
end

----------------------------------------------------------------- interface

local root = make("ScreenGui", {
    Name = "ZAPX",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 200,
}, player:WaitForChild("PlayerGui"))

local main = make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(580, 400),
    Position = UDim2.new(0.5, -290, 0.5, -200),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
    Active = true,
}, root)
corner(main, 10)
stroke(main, T.raised2, 0.35)

local bar = make("Frame", {
    Name = "Bar",
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
}, main)
corner(bar, 10)

make("TextLabel", {
    Size = UDim2.new(0, 120, 0, 20),
    Position = UDim2.fromOffset(14, 11),
    BackgroundTransparency = 1,
    Font = FONT_BOLD,
    Text = "ZAPX",
    TextColor3 = T.accent,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

make("TextLabel", {
    Size = UDim2.new(0, 160, 0, 18),
    Position = UDim2.fromOffset(64, 13),
    BackgroundTransparency = 1,
    Font = FONT,
    Text = "PS99  ·  " .. VERSION,
    TextColor3 = T.muted,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

local closeButton = make("TextButton", {
    Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -36, 0, 10),
    BackgroundColor3 = T.raised,
    AutoButtonColor = false,
    Font = FONT_BOLD,
    Text = "x",
    TextColor3 = T.muted,
    TextSize = 13,
    BorderSizePixel = 0,
}, bar)
corner(closeButton, 6)

local nav = make("Frame", {
    Name = "Nav",
    Size = UDim2.new(0, 132, 1, -66),
    Position = UDim2.fromOffset(12, 54),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
}, main)
corner(nav, 8)
pad(nav, 6)

local navLayout = make("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, nav)

local content = make("Frame", {
    Name = "Content",
    Size = UDim2.new(1, -156, 1, -66),
    Position = UDim2.fromOffset(150, 54),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, main)
corner(content, 8)

local pages = {}
local activeTab

local function page(name)
    local scroll = make("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.raised2,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
    }, content)
    pad(scroll, 10)
    make("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)
    local wrapper = { frame = scroll, order = 0 }

    function wrapper.next()
        wrapper.order = wrapper.order + 1
        return wrapper.order
    end

    function wrapper.setCanvas()
        local layout = scroll:FindFirstChildOfClass("UIListLayout")
        scroll.CanvasSize = UDim2.new(0, 0, 0, (layout and layout.AbsoluteContentSize.Y or 0) + 20)
    end

    pages[name] = wrapper
    return wrapper
end

local function selectTab(name)
    for key, wrapper in pairs(pages) do
        wrapper.frame.Visible = key == name
    end
    activeTab = name
    for _, button in ipairs(nav:GetChildren()) do
        if button:IsA("TextButton") then
            button.BackgroundColor3 = button:GetAttribute("Tab") == name and T.raised2 or T.raised
            button.TextColor3 = button:GetAttribute("Tab") == name and T.text or T.muted
        end
    end
    local wrapper = pages[name]
    if wrapper then
        wrapper.setCanvas()
    end
end

local function addTabButton(name, order)
    local button = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = T.raised,
        AutoButtonColor = false,
        Font = FONT,
        Text = "  " .. name,
        TextColor3 = T.muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, nav)
    button:SetAttribute("Tab", name)
    corner(button, 5)
    button.MouseButton1Click:Connect(function()
        selectTab(name)
    end)
    return button
end

------------------------------------------------------------- element kinds

local function section(wrapper, title)
    local holder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        LayoutOrder = wrapper.next(),
    }, wrapper.frame)
    make("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font = FONT_BOLD,
        Text = title:upper(),
        TextColor3 = T.accent,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, holder)
    return holder
end

local function label(wrapper, text, colour)
    local holder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = wrapper.next(),
    }, wrapper.frame)
    local body = make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT,
        Text = text,
        TextColor3 = colour or T.muted,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, holder)
    return body
end

local function toggle(wrapper, text, key, default, hint)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = T.raised,
        BorderSizePixel = 0,
        LayoutOrder = wrapper.next(),
    }, wrapper.frame)
    corner(row, 6)

    make("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Font = FONT,
        Text = text,
        TextColor3 = T.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local track = make("Frame", {
        Size = UDim2.fromOffset(34, 18),
        Position = UDim2.new(1, -44, 0.5, -9),
        BackgroundColor3 = T.raised2,
        BorderSizePixel = 0,
    }, row)
    corner(track, 9)

    local knob = make("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = T.muted,
        BorderSizePixel = 0,
    }, track)
    corner(knob, 7)

    local value = default == true
    local function paint()
        track.BackgroundColor3 = value and T.accent or T.raised2
        knob.BackgroundColor3 = value and T.bg or T.muted
        TweenService:Create(knob, TweenInfo.new(0.12), {
            Position = UDim2.fromOffset(value and 18 or 2, 2),
        }):Play()
        row.BackgroundColor3 = value and T.raised2 or T.raised
    end

    local button = make("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    button.MouseButton1Click:Connect(function()
        value = not value
        paint()
        local ok, err = engine.SetEnabled(key, value)
        if not ok then
            notify("Engine", err or ("refused " .. key))
        end
    end)

    local function apply()
        local ok = engine.SetEnabled(key, value)
        if not ok then
            value = not value
            paint()
        end
    end

    paint()
    apply()

    if hint then
        label(wrapper, hint)
    end
    return row
end

local function slider(wrapper, text, key, minimum, maximum, step, value, suffix)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = T.raised,
        BorderSizePixel = 0,
        LayoutOrder = wrapper.next(),
    }, wrapper.frame)
    corner(row, 6)

    make("TextLabel", {
        Size = UDim2.new(1, -70, 0, 16),
        Position = UDim2.fromOffset(10, 5),
        BackgroundTransparency = 1,
        Font = FONT,
        Text = text,
        TextColor3 = T.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local readout = make("TextLabel", {
        Size = UDim2.new(0, 60, 0, 16),
        Position = UDim2.new(1, -70, 0, 5),
        BackgroundTransparency = 1,
        Font = FONT_BOLD,
        Text = "",
        TextColor3 = T.accent,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local barFrame = make("Frame", {
        Size = UDim2.new(1, -20, 0, 8),
        Position = UDim2.fromOffset(10, 26),
        BackgroundColor3 = T.raised2,
        BorderSizePixel = 0,
    }, row)
    corner(barFrame, 4)

    local fill = make("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
    }, barFrame)
    corner(fill, 4)

    local current = value

    local function paint()
        local alpha = (current - minimum) / math.max(maximum - minimum, 0.0001)
        fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
        readout.Text = string.format("%.2f%s", current, suffix or "")
    end

    local function commit()
        local ok = engine.SetConfig(key, current)
        if not ok then
            notify("Engine", "knob refused: " .. key)
        end
    end

    local function fromX(x)
        local width = math.max(barFrame.AbsoluteSize.X, 1)
        local alpha = math.clamp((x - barFrame.AbsolutePosition.X) / width, 0, 1)
        local raw = minimum + (maximum - minimum) * alpha
        if step and step > 0 then
            raw = math.floor(raw / step + 0.5) * step
        end
        current = math.clamp(raw, minimum, maximum)
        paint()
    end

    local dragging = false

    local grab = make("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, barFrame)

    grab.MouseButton1Down:Connect(function()
        dragging = true
        fromX(UIS:GetMouseLocation().X)
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            commit()
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            fromX(input.Position.X)
        end
    end)

    paint()
    commit()
    return row
end

local function button(wrapper, text, callback, colour)
    local row = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = colour or T.raised,
        AutoButtonColor = false,
        Font = FONT,
        Text = text,
        TextColor3 = T.text,
        TextSize = 12,
        BorderSizePixel = 0,
        LayoutOrder = wrapper.next(),
    }, wrapper.frame)
    corner(row, 6)
    row.MouseEnter:Connect(function() row.BackgroundColor3 = T.raised2 end)
    row.MouseLeave:Connect(function() row.BackgroundColor3 = colour or T.raised end)
    row.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        if not ok then
            notify("Error", tostring(err))
        end
    end)
    return row
end

local statusBar = make("TextLabel", {
    Size = UDim2.new(1, -24, 0, 18),
    Position = UDim2.new(0, 12, 1, -24),
    BackgroundTransparency = 1,
    Font = FONT,
    Text = "starting",
    TextColor3 = T.muted,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

---------------------------------------------------------------------- drag

do
    local dragging, startMouse, startPos = false, nil, nil

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startMouse = UIS:GetMouseLocation()
            startPos = main.Position
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = UIS:GetMouseLocation() - startMouse
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

---------------------------------------------------------------------- tabs

local farmPage = page("Farm")
section(farmPage, "Breakables")
toggle(farmPage, "Auto Farm", "farm", false,
    "Fires the damage remote on the engine tick and routes every owned pet at the same target.")
toggle(farmPage, "Auto Tap", "tap", false)
toggle(farmPage, "Click Aura", "clickAura", false)
toggle(farmPage, "Orb Vacuum", "vacuum", false)

section(farmPage, "Rates")
slider(farmPage, "Hit Rate", "MaxTapRate", 1, 60, 1, 48, "/s")
slider(farmPage, "Burst Targets", "FarmBurst", 0, 12, 1, 6, "")
slider(farmPage, "Reach", "TapRange", 50, 400, 10, 220, " studs")
slider(farmPage, "Target Rescan", "TargetRescan", 0.05, 0.6, 0.05, 0.12, "s")

section(farmPage, "Priority")
toggle(farmPage, "Chests First", "chestFirst", true)
toggle(farmPage, "Jitter", "jitter", false)
toggle(farmPage, "Aura Visual", "auraVisual", false)

local petsPage = page("Pets")
section(petsPage, "Speed")
toggle(petsPage, "Pet Speed", "petSpeed", false,
    "Hooks CalculateSpeedMultiplier so pets render on top of the target.")
slider(petsPage, "Pet Re-route", "PetRouteRate", 0.05, 0.5, 0.05, 0.15, "s")
section(petsPage, "Targeting")
toggle(petsPage, "Route All Pets", "petAll", true)
toggle(petsPage, "Pet Bulk Join", "petBulkJoin", true,
    "Sends Breakables_JoinPetBulk once per target so pets count before they travel.")
section(petsPage, "Hatching")
toggle(petsPage, "Auto Hatch", "autoEgg", false)
toggle(petsPage, "Hide Egg Effects", "hideEggFx", false)

local worldPage = page("World")
section(worldPage, "Zones")
toggle(worldPage, "Auto Teleport Best Zone", "zoneTele", false)
toggle(worldPage, "Snap To Island Centre", "teleCenter", true,
    "Lands on the centroid of the zone's own breakables instead of the spawn edge.")
toggle(worldPage, "Auto Buy Next Zone", "zoneBuy", false)
slider(worldPage, "Teleport Retry", "TeleInterval", 0.2, 5, 0.2, 0.4, "s")
label(worldPage, "World hopping is not wired. You stay in the world you are in.")

local progressPage = page("Progress")
section(progressPage, "Quests")
toggle(progressPage, "Auto Quests", "autoQuest", false)
section(progressPage, "Rank")
toggle(progressPage, "Auto Claim Ranks", "autoRank", false)
toggle(progressPage, "Auto Rebirth", "autoRebirth", false)
toggle(progressPage, "Auto Buy Pet Slots", "autoBuyPetSlots", false)

local consumePage = page("Consume")
section(consumePage, "Items")
toggle(consumePage, "Auto Keys", "autoKeys", false)
toggle(consumePage, "Auto Gift Bags", "autoGiftBags", false)
toggle(consumePage, "Auto Fruits", "autoFruits", false)
toggle(consumePage, "Auto Potions", "autoPotions", false)
toggle(consumePage, "Auto Free Gifts", "autoFreeGifts", false)
toggle(consumePage, "Auto Ultimates", "autoUltimate", false)
toggle(consumePage, "Auto Dice", "autoDice", false)
label(consumePage, "With no picker list set, every worker consumes everything it finds.")

local machinesPage = page("Machines")
section(machinesPage, "Station")
toggle(machinesPage, "Auto Daycare", "autoDaycare", false)
toggle(machinesPage, "Auto Flexible Flags", "autoFlags", false)
toggle(machinesPage, "Auto Secret Rooms", "autoSecretRooms", false)
toggle(machinesPage, "Auto Treehouse", "autoTreehouse", false)
toggle(machinesPage, "Auto Fuse", "autoFuse", false)
toggle(machinesPage, "Auto Cards", "autoCards", false)
toggle(machinesPage, "Auto Relics", "autoRelics", false)
toggle(machinesPage, "Auto Mail Claim", "autoMailClaim", false)

local renderPage = page("Render")
section(renderPage, "Effects")
toggle(renderPage, "Reduce Breakable Effects", "optBreakables", false)
toggle(renderPage, "Reduce Pet Effects", "optPets", false)
section(renderPage, "Session")
toggle(renderPage, "Anti AFK", "antiAfk", false)

local serverPage = page("Server")
section(serverPage, "Hop")
toggle(serverPage, "Auto Server Hop", "serverHop", false)
section(serverPage, "Controls")
button(serverPage, "All Features Off", function()
    engine.AllOff()
    notify("Engine", "All features off")
end)
button(serverPage, "Unload Everything", function()
    alive = false
    pcall(engine.Stop)
    root:Destroy()
end, Color3.fromRGB(60, 34, 38))

local statusPage = page("Status")
section(statusPage, "Live")
local statusLabel = label(statusPage, "collecting...", T.text)
local notesLabel = label(statusPage, "-")
section(statusPage, "Log")
local logLabel = label(statusPage, "-")
section(statusPage, "Build")
label(statusPage, ("ZAPX %s - engine headless - %d features")
    :format(VERSION, 38))

local function addTabNames()
    local order = 1
    local fixed = { "Farm", "Pets", "World", "Progress", "Consume", "Machines", "Render", "Server", "Status" }
    for _, name in ipairs(fixed) do
        addTabButton(name, order)
        order = order + 1
    end
end

addTabNames()
selectTab("Farm")

----------------------------------------------------------------- status loop

local function countActive(tableValue)
    local n = 0
    for _, value in pairs(tableValue or {}) do
        if value then n = n + 1 end
    end
    return n
end

local function noteLine(noteTable)
    local parts = {}
    for _, key in ipairs({ "tap", "pet", "tele", "buy", "quest", "rank", "rebirth", "egg", "heap", "profile" }) do
        local value = noteTable[key]
        if value then
            parts[#parts + 1] = key .. ": " .. tostring(value)
        end
    end
    if #parts == 0 then
        return "-"
    end
    return table.concat(parts, "  |  ")
end

task.spawn(function()
    while alive do
        local ok, status = pcall(engine.GetStatus)
        if ok and type(status) == "table" then
            local active = countActive(status.enabled)
            local line = ("world %s  ·  profile %s  ·  %d on")
                :format(tostring(status.world), tostring(status.profile), active)
            statusLabel.Text = line
            statusBar.Text = line
            notesLabel.Text = noteLine(status.notes)
            if #notes > 0 then
                local recent = {}
                for index = math.max(1, #notes - 6), #notes do
                    recent[#recent + 1] = notes[index].title .. ": " .. notes[index].content
                end
                logLabel.Text = table.concat(recent, "\n")
            end
            statusPage.setCanvas()
        end
        task.wait(1.5)
    end
end)

------------------------------------------------------------------- hotkeys

local visible = true

closeButton.MouseButton1Click:Connect(function()
    visible = false
    main.Visible = false
end)

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        visible = not visible
        main.Visible = visible
    elseif input.KeyCode == Enum.KeyCode.X then
        alive = false
        pcall(engine.Stop)
        root:Destroy()
    end
end)

notify("Loader", "ZAPX " .. VERSION .. " up - RightControl toggles the window")

return engine
