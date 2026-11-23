--[[
    StephUI 1.0 - Clean PS99 Interface (no ZapLib)
    Drop-in replacement for the old menu library with the exact same surface:
      lib.Window, win:CreateTab, tab:CreateSection, tab:CreateParagraph,
      tab:CreateLabel, tab:CreateToggle, tab:CreateSlider, tab:CreateButton,
      tab:CreateDropdown, lib:CreateNotification, lib:Destroy
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

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
}

local function make(className, props, parent)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        inst[k] = v
    end
    inst.Parent = parent
    return inst
end

local function getGuiParent()
    local okHui, hui = pcall(function()
        return (gethui and gethui()) or (get_hidden_gui and get_hidden_gui())
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

local function normalizeSetArgs(first, second)
    if second ~= nil then
        return second
    end
    return first
end

local connections = {}
local function track(conn)
    connections[#connections + 1] = conn
    return conn
end

local guiParent = getGuiParent()
do
    local containers = { guiParent }
    local okCore = pcall(function() return CoreGui.Name end)
    if okCore and CoreGui ~= guiParent then containers[#containers + 1] = CoreGui end
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg ~= guiParent then containers[#containers + 1] = pg end
    local oldNames = { "StephHUB_UI", "StephHUB_AutoRankHUD", "ZapLib", "KaitunZapLib", "ZapLibKey" }
    for _, container in ipairs(containers) do
        for _, name in ipairs(oldNames) do
            for _, child in ipairs(container:GetChildren()) do
                if child.Name == name then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end

local screen = make("ScreenGui", {
    Name = "StephHUB_UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 500,
}, guiParent)

local mainFrame = make("Frame", {
    Name = "MainWindow",
    Size = UDim2.fromOffset(720, 440),
    Position = UDim2.new(0.5, -360, 0.5, -220),
    BackgroundColor3 = THEME.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, screen)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, mainFrame)
make("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, mainFrame)

-- Topbar
local topbar = make("Frame", {
    Name = "Topbar",
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
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
    Text = "Steph HUB  -  PS99",
    TextColor3 = THEME.Text,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, topbar)

local statusHint = make("TextLabel", {
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

-- Dragging
do
    local dragging, dragStart, startPos = false, nil, nil
    track(topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
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

track(UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        mainFrame.Visible = not mainFrame.Visible
    end
end))

-- Body
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

-- Notifications
local notifHolder = make("Frame", {
    Size = UDim2.fromOffset(290, 320),
    Position = UDim2.new(1, -304, 1, -334),
    BackgroundTransparency = 1,
    ZIndex = 20,
}, screen)
make("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 8),
}, notifHolder)

local lib = {}
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

function lib:CreateNotification(opts)
    opts = opts or {}
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
        Text = tostring(opts.Title or "Steph HUB"),
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
        Text = tostring(opts.Content or ""),
        TextColor3 = THEME.Text,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)

    task.delay(tonumber(opts.Duration) or 4, function()
        if card and card.Parent then
            card:Destroy()
        end
    end)
end

function lib:Destroy()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
    if screen and screen.Parent then
        screen:Destroy()
    end
end

local win = {}

function win:CreateTab(name, icon)
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

    local hasIcon = type(icon) == "string" and #icon > 0
    if hasIcon then
        make("ImageLabel", {
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.new(0, 10, 0.5, -8),
            BackgroundTransparency = 1,
            Image = icon,
            ImageColor3 = THEME.TextMuted,
        }, btn)
    end

    local lbl = make("TextLabel", {
        Size = UDim2.new(1, hasIcon and -36 or -16, 1, 0),
        Position = UDim2.fromOffset(hasIcon and 32 or 12, 0),
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

    local tabObj = {}
    local elemOrder = 0
    local function nextOrder()
        elemOrder += 1
        return elemOrder
    end

    function tabObj:CreateSection(sectionName)
        local lblSec = make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            Text = tostring(sectionName or ""):upper(),
            TextColor3 = THEME.Accent,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = nextOrder(),
        }, page)
        return lblSec
    end

    function tabObj:CreateLabel(text)
        local lblItem = make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = tostring(text or ""),
            TextColor3 = THEME.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = nextOrder(),
        }, page)
        local handle = {}
        function handle.Set(a, b)
            lblItem.Text = tostring(normalizeSetArgs(a, b) or "")
        end
        return handle
    end

    function tabObj:CreateParagraph(opts)
        opts = opts or {}
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
            Text = tostring(opts.Title or ""),
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
            Text = tostring(opts.Content or ""),
            TextColor3 = THEME.TextMuted,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 2,
        }, card)

        local handle = {}
        function handle.Set(a, b)
            local p = normalizeSetArgs(a, b)
            if type(p) == "table" then
                if p.Title ~= nil then titleLbl.Text = tostring(p.Title) end
                if p.Content ~= nil then bodyLbl.Text = tostring(p.Content) end
            end
        end
        return handle
    end

    function tabObj:CreateButton(opts)
        opts = opts or {}
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

        make("TextLabel", {
            Size = UDim2.new(1, -60, 1, 0),
            Position = UDim2.fromOffset(12, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            Text = tostring(opts.Name or "Button"),
            TextColor3 = THEME.Text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, btnRow)

        make("TextLabel", {
            Size = UDim2.fromOffset(44, 20),
            Position = UDim2.new(1, -54, 0.5, -10),
            BackgroundColor3 = THEME.Raised,
            Font = Enum.Font.GothamBold,
            Text = "RUN",
            TextColor3 = THEME.Accent,
            TextSize = 10,
        }, btnRow)

        track(btnRow.MouseEnter:Connect(function()
            TweenService:Create(btnRow, TweenInfo.new(0.1), { BackgroundColor3 = THEME.SurfaceHover }):Play()
        end))
        track(btnRow.MouseLeave:Connect(function()
            TweenService:Create(btnRow, TweenInfo.new(0.1), { BackgroundColor3 = THEME.Surface }):Play()
        end))
        track(btnRow.MouseButton1Click:Connect(function()
            if type(opts.Callback) == "function" then
                task.spawn(opts.Callback)
            end
        end))
        return btnRow
    end

    function tabObj:CreateToggle(opts)
        opts = opts or {}
        local state = opts.CurrentValue == true
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
            Text = tostring(opts.Name or "Toggle"),
            TextColor3 = THEME.Text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)

        local pill = make("Frame", {
            Size = UDim2.fromOffset(38, 20),
            Position = UDim2.new(1, -50, 0.5, -10),
            BackgroundColor3 = state and THEME.Accent or THEME.Raised,
            BorderSizePixel = 0,
        }, row)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)

        local knob = make("Frame", {
            Size = UDim2.fromOffset(14, 14),
            Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
            BackgroundColor3 = state and THEME.Bg or THEME.TextMuted,
            BorderSizePixel = 0,
        }, pill)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

        local handle = { CurrentValue = state }
        local function apply(newState, fireCb)
            state = newState == true
            handle.CurrentValue = state
            TweenService:Create(pill, TweenInfo.new(0.14), {
                BackgroundColor3 = state and THEME.Accent or THEME.Raised,
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.14), {
                Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
                BackgroundColor3 = state and THEME.Bg or THEME.TextMuted,
            }):Play()
            if fireCb and type(opts.Callback) == "function" then
                task.spawn(opts.Callback, state)
            end
        end

        function handle.Set(a, b)
            local v = normalizeSetArgs(a, b)
            apply(v == true, true)
        end

        track(row.MouseButton1Click:Connect(function()
            apply(not state, true)
        end))

        return handle
    end

    function tabObj:CreateSlider(opts)
        opts = opts or {}
        local range = opts.Range or { 0, 100 }
        local lo, hi = tonumber(range[1]) or 0, tonumber(range[2]) or 100
        local inc = tonumber(opts.Increment) or 1
        local suffix = tostring(opts.Suffix or "")
        local val = math.clamp(tonumber(opts.CurrentValue) or lo, lo, hi)

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
            Text = tostring(opts.Name or "Slider"),
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

        local pct = (hi > lo) and ((val - lo) / (hi - lo)) or 0
        local fillBar = make("Frame", {
            Size = UDim2.new(pct, 0, 1, 0),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
        }, trackBar)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, fillBar)

        local handle = { CurrentValue = val }
        local function roundStep(n)
            local stepped = lo + math.floor(((n - lo) / inc) + 0.5) * inc
            stepped = math.clamp(stepped, lo, hi)
            if inc < 1 then
                local decimals = math.max(1, math.ceil(-math.log10(inc)))
                local mul = 10 ^ decimals
                stepped = math.floor(stepped * mul + 0.5) / mul
            end
            return stepped
        end

        local function setVal(newVal, fireCb)
            val = roundStep(tonumber(newVal) or lo)
            handle.CurrentValue = val
            local p = (hi > lo) and ((val - lo) / (hi - lo)) or 0
            fillBar.Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0)
            valLbl.Text = tostring(val) .. suffix
            if fireCb and type(opts.Callback) == "function" then
                task.spawn(opts.Callback, val)
            end
        end

        function handle.Set(a, b)
            setVal(normalizeSetArgs(a, b), true)
        end

        local sliding = false
        local function updateFromInput(input)
            local x = input.Position.X - trackBar.AbsolutePosition.X
            local w = math.max(trackBar.AbsoluteSize.X, 1)
            local alpha = math.clamp(x / w, 0, 1)
            setVal(lo + (hi - lo) * alpha, true)
        end

        track(trackBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                sliding = true
                updateFromInput(input)
            end
        end))
        track(UIS.InputChanged:Connect(function(input)
            if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                updateFromInput(input)
            end
        end))
        track(UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end))

        if type(opts.Callback) == "function" then
            task.spawn(opts.Callback, val)
        end

        return handle
    end

    function tabObj:CreateDropdown(opts)
        opts = opts or {}
        local options = type(opts.Options) == "table" and opts.Options or {}
        local current = opts.CurrentOption
        if type(current) == "table" then current = current[1] end
        current = current or options[1] or ""

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
            Text = tostring(opts.Name or "Dropdown"),
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
        local handle = { CurrentOption = current }

        local function rebuildList()
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
                    current = optStr
                    handle.CurrentOption = current
                    curLbl.Text = current .. "  v"
                    open = false
                    listFrame.Visible = false
                    listFrame.Size = UDim2.new(1, 0, 0, 0)
                    rebuildList()
                    if type(opts.Callback) == "function" then
                        task.spawn(opts.Callback, current)
                    end
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

        function handle.Set(a, b)
            local v = normalizeSetArgs(a, b)
            if type(v) == "table" then v = v[1] end
            current = tostring(v or "")
            handle.CurrentOption = current
            curLbl.Text = current .. (open and "  ^" or "  v")
            rebuildList()
            if type(opts.Callback) == "function" then
                task.spawn(opts.Callback, current)
            end
        end

        function handle.Refresh(a, b, c)
            local newOpts = c ~= nil and b or a
            local newCur = c ~= nil and c or b
            if type(newOpts) == "table" then
                options = newOpts
            end
            if newCur ~= nil then
                current = tostring(type(newCur) == "table" and newCur[1] or newCur)
            elseif options[1] then
                current = tostring(options[1])
            end
            handle.CurrentOption = current
            curLbl.Text = current .. (open and "  ^" or "  v")
            rebuildList()
        end

        if type(opts.Callback) == "function" then
            task.spawn(opts.Callback, current)
        end

        return handle
    end

    return tabObj
end

lib.Window = win
return lib
