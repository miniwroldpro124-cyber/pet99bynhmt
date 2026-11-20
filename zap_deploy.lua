-- ZapHub / ZapLib 2.0.0 - standalone deploy build
-- Decrypted from ZHARVEST chunk 04 (Luraph VM, chunk 02 chain). UI only: no key
-- check, no server calls, no HWID. Everything the original gated is reachable.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer
local GuiInsetY = GuiService:GetGuiInset().Y

local l = {["DefaultIcon"]="rbxassetid://16259403210",["NotificationIcon"]="rbxassetid://15642579187",["LogoIcon"]="rbxassetid://120561115194230",["StatIcon"]="rbxassetid://82329173638641",["ClickIcon"]="rbxassetid://16089599792",["ChevronIcon"]="rbxassetid://16093555964",["LockIcon"]="rbxassetid://126141499544212",["MinimizeIcon"]="rbxassetid://71627683074088",["CloseIcon"]="rbxassetid://91413233063028",["SettingsIcon"]="rbxassetid://87867412432006",["Fast"]=0.15,["Normal"]=0.3,["Slow"]=0.45,["DragTime"]=0.2,["DragThreshold"]=4,["CloseDelay"]=3,["MaxNotifications"]=5,["WindowWidth"]=700,["WindowHeight"]=400,["ToggleKey"]="RightControl",["ReservedKey"]="__ZapLibSettings",["FolderName"]="ZapLib",["FileName"]="Settings.zaplib",["Version"]="2.0.0"}
l.ToggleKey = Enum.KeyCode.RightControl

local m = {}
for _, wgt in ipairs({"Regular", "Medium", "SemiBold", "Bold", "Heavy"}) do
    m[wgt] = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight[wgt])
end
m.BoldItalic = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
m.Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local TOKENS = {"Background","Surface","SurfaceHover","SurfaceActive","Raised","Stroke","StrokeAccent",
    "StrokeStrong","Accent","AccentHover","AccentText","AccentInk","Text","TextMuted","TextDim",
    "Knob","Danger","Success","Overlay","Glass","GlassStroke"}

local RAW = {
    ["Dark"] = {10,10,10,20,18,16,29,26,21,38,33,26,35,31,25,44,38,30,74,52,18,161,109,30,255,160,0,255,194,77,255,160,0,26,18,6,242,239,233,170,164,155,138,132,124,242,239,233,255,105,107,46,204,113,0,0,0,24,21,17,255,255,255},
    ["Light"] = {247,244,238,255,255,255,250,245,236,243,235,222,238,231,218,228,221,208,240,214,166,214,138,0,255,160,0,230,140,0,176,98,0,26,18,6,26,22,15,96,88,76,132,124,112,255,255,255,214,60,62,30,150,80,0,0,0,255,255,255,120,90,30},
    ["Discord"] = {49,51,56,43,45,49,53,55,60,64,66,73,30,31,34,63,65,71,60,66,112,88,101,242,88,101,242,109,120,244,148,156,247,255,255,255,242,243,245,181,186,193,128,132,142,255,255,255,242,63,67,35,165,90,0,0,0,43,45,49,255,255,255},
    ["Dracula"] = {40,42,54,47,48,59,56,58,71,68,71,90,33,34,44,67,68,78,75,69,102,108,95,158,189,147,249,207,176,251,189,147,249,34,34,43,248,248,242,166,167,185,98,114,164,34,34,43,255,85,85,80,250,123,0,0,0,47,48,59,255,255,255},
    ["GitHub Dark"] = {13,17,23,20,23,28,27,31,38,33,38,45,1,4,9,48,54,61,31,58,102,61,95,158,87,129,241,121,160,245,88,166,255,255,255,255,230,237,243,141,150,160,110,118,129,255,255,255,248,81,73,63,185,80,0,0,0,22,27,34,255,255,255},
    ["Gruvbox Dark"] = {40,40,40,50,48,47,60,56,54,80,73,69,29,32,33,69,64,61,102,92,84,124,111,100,250,189,47,252,208,98,250,189,47,40,40,40,235,219,178,189,174,147,146,131,116,40,40,40,251,73,52,184,187,38,0,0,0,50,48,47,255,255,255},
    ["Halloween"] = {19,16,25,26,23,30,34,30,39,41,37,44,11,8,16,52,41,38,74,50,32,138,84,38,233,144,62,240,169,94,235,160,77,24,15,7,236,230,217,182,173,157,133,124,112,24,15,7,229,83,75,127,176,105,0,0,0,26,23,30,255,255,255},
    ["Rosé Pine"] = {25,23,36,31,29,46,38,35,58,46,43,66,22,20,31,42,40,55,64,61,82,110,106,134,235,188,186,242,208,206,235,188,186,25,23,36,224,222,244,144,140,170,110,106,134,25,23,36,235,111,146,156,207,216,0,0,0,31,29,46,255,255,255},
    ["Solarized Light"] = {251,246,228,246,242,225,239,233,212,228,223,202,238,232,213,218,218,206,197,211,224,147,161,161,84,138,206,63,120,191,47,111,181,253,246,227,71,91,98,101,123,131,147,161,161,253,246,227,220,50,47,133,153,0,0,0,253,246,227,88,110,117},
    ["Windows Vista"] = {243,246,251,255,255,255,238,244,253,225,234,249,228,233,241,205,214,229,169,194,232,122,159,216,82,124,212,107,146,224,47,95,184,255,255,255,27,27,27,79,90,109,125,135,152,255,255,255,214,69,69,46,158,79,0,0,0,255,255,255,97,114,131},
    ["Windows XP"] = {236,233,216,251,251,248,238,242,251,193,210,238,227,224,208,207,203,182,127,157,185,49,106,197,36,94,219,61,119,232,11,63,168,255,255,255,26,26,26,77,77,77,128,128,128,255,255,255,214,64,42,60,141,47,0,0,0,255,255,255,36,94,219},
}

local themes = {}
for name, flat in pairs(RAW) do
    local cols = {}
    for i, token in ipairs(TOKENS) do
        local r, g, b = flat[(i - 1) * 3 + 1], flat[(i - 1) * 3 + 2], flat[(i - 1) * 3 + 3]
        cols[token] = Color3.fromRGB(r, g, b)
    end
    themes[name] = cols
end

local q = {Name = "Dark", Colors = themes.Dark}

local t = {
    Flags = {}, Elements = {}, Tabs = {}, SelectedTab = nil, Window = nil,
    Kaitun = nil, KaitunActive = false, Destroyed = false, Generation = 0,
    Settings = {Theme = "Dark", Language = "English", AnimationMode = "Smooth",
                Notifications = true, Quests = true, Scale = 1},
}

local u = {}

local trackers = {}

local function applyTheme()
    for obj, set in pairs(trackers) do
        if obj.Parent then
            for _, rec in pairs(set) do
                local col = q.Colors[rec.Token]
                if col then obj[rec.Property] = col end
            end
        else
            trackers[obj] = nil
        end
    end
end

local function gethui_safe()
    local fn = gethui or get_hidden_gui
    if fn then
        local ok, h = pcall(fn)
        if ok and h then return h end
    end
    return LP:WaitForChild("PlayerGui")
end

local function M(a)
    local s = (a and a.AbsoluteSize) or Vector2.new(0, 0)
    if s.X < 2 or s.Y < 2 then
        local cam = workspace.CurrentCamera
        s = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    end
    return s
end

local function H(v)
    if type(v) ~= "number" then return tostring(v) end
    local abs = math.abs(v)
    for _, unit in ipairs({{999999995904, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}) do
        if abs >= unit[1] then
            return (string.gsub(string.format("%.1f", v / unit[1]), "%.0$", "")) .. unit[2]
        end
    end
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.2f", v)
end

local function I(v)
    if type(v) == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.1f", v)
    end
    return tostring(v)
end

local function J(a)
    a = math.max(0, math.floor(a))
    return string.format("%d:%02d:%02d:%02d", math.floor(a / 86400), math.floor((a % 86400) / 3600), math.floor((a % 3600) / 60), a % 60)
end

local LOCALE = {
    ["Welcome, %s"] = {
        ["Bahasa Indonesia"] = "Selamat datang, %s",
        ["Deutsch"] = "Willkommen, %s",
        ["Español"] = "Bienvenido, %s",
        ["Filipino"] = "Maligayang pagdating, %s",
        ["Français"] = "Bienvenue, %s",
        ["Polski"] = "Witaj, %s",
        ["Português"] = "Bem-vindo, %s",
        ["Română"] = "Bine ai venit, %s",
        ["Tiếng Việt"] = "Chào mừng, %s",
        ["Türkçe"] = "Hoş geldin, %s",
        ["Русский"] = "Добро пожаловать, %s",
        ["Українська"] = "Вітаємо, %s",
        ["ไทย"] = "ยินดีต้อนรับ, %s",
    },
    ["Close ZapHub?"] = {
        ["Bahasa Indonesia"] = "Tutup ZapHub?",
        ["Deutsch"] = "ZapHub schließen?",
        ["Español"] = "¿Cerrar ZapHub?",
        ["Filipino"] = "Isara ang ZapHub?",
        ["Français"] = "Fermer ZapHub ?",
        ["Polski"] = "Zamknąć ZapHub?",
        ["Português"] = "Fechar o ZapHub?",
        ["Română"] = "Închizi ZapHub?",
        ["Tiếng Việt"] = "Đóng ZapHub?",
        ["Türkçe"] = "ZapHub kapatılsın mı?",
        ["Русский"] = "Закрыть ZapHub?",
        ["Українська"] = "Закрити ZapHub?",
        ["ไทย"] = "ปิด ZapHub?",
    },
    ["All running functions and loops will be stopped immediately. To reopen it, re-execute your script."] = {
        ["Bahasa Indonesia"] = "Semua fungsi dan loop yang berjalan akan langsung dihentikan. Untuk membukanya lagi, jalankan ulang script-mu.",
        ["Deutsch"] = "Alle laufenden Funktionen und Schleifen werden sofort beendet. Um es wieder zu öffnen, führe dein Skript erneut aus.",
        ["Español"] = "Todas las funciones y bucles en ejecución se detendrán de inmediato. Para volver a abrirlo, vuelve a ejecutar tu script.",
        ["Filipino"] = "Agad na ititigil ang lahat ng tumatakbong function at loop. Para muling buksan, i-execute muli ang iyong script.",
        ["Français"] = "Toutes les fonctions et boucles en cours seront arrêtées immédiatement. Pour le rouvrir, relancez votre script.",
        ["Polski"] = "Wszystkie uruchomione funkcje i pętle zostaną natychmiast zatrzymane. Aby otworzyć ponownie, uruchom skrypt jeszcze raz.",
        ["Português"] = "Todas as funções e loops em execução serão interrompidos imediatamente. Para reabrir, execute seu script novamente.",
        ["Română"] = "Toate funcțiile și buclele active vor fi oprite imediat. Pentru a-l redeschide, rulează din nou scriptul.",
        ["Tiếng Việt"] = "Mọi hàm và vòng lặp đang chạy sẽ dừng ngay lập tức. Để mở lại, hãy chạy lại script.",
        ["Türkçe"] = "Çalışan tüm fonksiyonlar ve döngüler hemen durdurulacak. Yeniden açmak için scriptini tekrar çalıştır.",
        ["Русский"] = "Все работающие функции и циклы будут остановлены немедленно. Чтобы открыть снова, запустите скрипт повторно.",
        ["Українська"] = "Усі запущені функції та цикли буде негайно зупинено. Щоб відкрити знову, запустіть скрипт повторно.",
        ["ไทย"] = "ฟังก์ชันและลูปที่กำลังทำงานทั้งหมดจะหยุดทันที หากต้องการเปิดใหม่ ให้รันสคริปต์อีกครั้ง",
    },
    ["Cancel"] = {["Deutsch"] = "Abbrechen", ["Español"] = "Cancelar", ["Français"] = "Annuler",
        ["Português"] = "Cancelar", ["Русский"] = "Отмена", ["Українська"] = "Скасувати"},
    ["Close"] = {["Deutsch"] = "Schließen", ["Español"] = "Cerrar", ["Français"] = "Fermer",
        ["Português"] = "Fechar", ["Русский"] = "Закрыть", ["Українська"] = "Закрити"},
}

local function C(s)
    if (type(s) ~= "string") then return s end
    local table_ = LOCALE[s]
    if (table_) then
        local hit = table_[t.Settings.Language]
        if (hit) then return hit end
    end
    return s
end
local function D(s, ...)
    s = C(s)
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        return (ok and out) or s
    end
    return s
end
local function F(v)
    if not v then return nil end
    return (tonumber(v) and ("rbxassetid://" .. v)) or v
end

local function Y(rad)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, rad)
    return corner
end

local function fb(a, b, cc, d)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, a)
    p.PaddingTop = UDim.new(0, b or a)
    p.PaddingRight = UDim.new(0, cc or a)
    p.PaddingBottom = UDim.new(0, d or b or a)
    return p
end

local function gb(a, b, cc, d)
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, a or 0)
    lay.FillDirection = b or Enum.FillDirection.Vertical
    lay.HorizontalAlignment = cc or Enum.HorizontalAlignment.Left
    lay.VerticalAlignment = d or Enum.VerticalAlignment.Top
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    return lay
end

local function db(token, thickness)
    local s = Instance.new("UIStroke")
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local col = q.Colors[token or "Stroke"]
    if col then s.Color = col end
    return s
end

local defaults = {
    Frame = {BorderSizePixel = 0},
    CanvasGroup = {BorderSizePixel = 0},
    TextLabel = {BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = m.Medium, TextSize = 13, Text = ""},
    TextButton = {AutoButtonColor = false, BorderSizePixel = 0, FontFace = m.Medium, TextSize = 13, Text = ""},
    TextBox = {BorderSizePixel = 0, FontFace = m.Medium, TextSize = 13, Text = "", ClearTextOnFocus = false},
    ImageLabel = {BackgroundTransparency = 1, BorderSizePixel = 0},
    ImageButton = {AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0},
    ScrollingFrame = {BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
                      ScrollBarImageTransparency = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
                      AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y},
}

local function track(obj, prop, token)
    local set = trackers[obj]
    if not set then
        set = {}
        trackers[obj] = set
    end
    local rec = set[prop]
    if rec then
        rec.Token = token
    else
        rec = {Object = obj, Property = prop, Token = token}
        set[prop] = rec
    end
    local col = q.Colors[token]
    if col then obj[prop] = col end
    return rec
end

local function ab(obj, prop, token)
    local set = trackers[obj]
    local rec = set and set[prop]
    if not rec then return end
    rec.Token = token
    local col = q.Colors[token]
    if col then obj[prop] = col end
end

local function eb(cls, props, children)
    local inst = Instance.new(cls)
    local base = defaults[cls]
    if base then
        for k, v in pairs(base) do inst[k] = v end
    end
    for k, v in pairs(props or {}) do
        if k ~= "Theme" and k ~= "Loc" and k ~= "LocPlaceholder" and k ~= "Parent" then
            inst[k] = v
        end
    end
    if props and props.Theme then
        for prop, token in pairs(props.Theme) do track(inst, prop, token) end
    end
    if props and props.Loc then inst.Text = C(props.Loc) end
    for _, ch in ipairs(children or {}) do ch.Parent = inst end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end


local function T(sig, fn) return sig:Connect(fn) end
local function U(sig, fn) return sig:Connect(fn) end
local function N(obj, fn) obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(fn) end
local function O(fn, ...) return task.spawn(fn, ...) end
local function P(delay, fn, ...) return task.spawn(function(...) task.wait(delay) fn(...) end, ...) end
local function V(a) if a ~= nil then return end end
local function bb() end
local function X() end
local function B() end
local function cb() end
local function A() end

local function W(label, fn)
    task.spawn(function()
        while label.Parent do
            local ok, v = pcall(fn)
            if ok then label.Text = v end
            task.wait(0.2)
        end
    end)
    return label
end

local w = {}
w.Play = function(obj, dur, props)
    if t.Settings.AnimationMode == "Basic" or not obj.Parent then
        for k, v in pairs(props) do obj[k] = v end
        return
    end
    for k, v in pairs(props) do
        local info = TweenInfo.new(dur or l.Normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tw = TweenService:Create(obj, info, {[k] = v})
        if tw then tw:Play() end
    end
end
w.Set = function(obj, props)
    for k, v in pairs(props) do obj[k] = v end
end
w.Flush = function() end

local input = {Began = {}, Ended = {}}
local function isPointer(inp)
    return inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch
end
UserInputService.InputBegan:Connect(function(inp)
    for _, fn in ipairs(input.Began) do fn(inp) end
end)
UserInputService.InputEnded:Connect(function(inp)
    for _, fn in ipairs(input.Ended) do fn(inp) end
end)

local drag = {Active = nil}
local function finishDrag()
    local a = drag.Active
    if a then
        drag.Active = nil
        if a.OnEnd then a.OnEnd() end
    end
end
UserInputService.InputChanged:Connect(function(inp)
    local a = drag.Active
    if a and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp == a.Input) then
        a.OnMove(inp.Position)
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    local a = drag.Active
    if a and (inp == a.Input or (inp.UserInputType == Enum.UserInputType.MouseButton1 and a.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
        finishDrag()
    end
end)

local function r(frame, handle, _extra, onDrop)
    frame.InputBegan:Connect(function(inp)
        if not isPointer(inp) then return end
        local start = inp.Position
        local base = handle.Position
        drag.Active = {Input = inp, OnMove = function(pos)
            local dx = pos.X - start.X
            local dy = pos.Y - start.Y
            if math.abs(dx) + math.abs(dy) < l.DragThreshold then return end
            handle.Position = UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset + dy)
        end, OnEnd = onDrop}
    end)
end

local function notify(title, text, icon, duration)
    task.spawn(function()
        for _ = 1, 10 do
            local ok = pcall(function()
                StarterGui:SetCore("SendNotification", {Title = title, Text = text, Icon = icon, Duration = duration})
            end)
            if ok then return end
            task.wait(0.5)
        end
    end)
end


local function stateWriter(key)
    return function(self, value)
        t.Settings[key] = value
    end
end
local function makeRealTab()
    local tab = {Widgets = {}}
    function tab:CreateSection(name) return nil end
    function tab:CreateParagraph(o) return {Set = function() end} end
    function tab:CreateLabel(o) return {Set = function() end} end
    function tab:CreateKeybind(o) return {Set = function() end} end
    function tab:CreateToggle(o)
        local w = {Value = o.CurrentValue == true}
        function w:Set(v) self.Value = v == true end
        function w:Get() return self.Value end
        function w:Apply(v) self:Set(v) end
        self.Widgets[#self.Widgets + 1] = w
        return w
    end
    function tab:CreateSlider(o)
        local w = {Value = tonumber(o.CurrentValue) or 0}
        function w:Set(v) self.Value = tonumber(v) or self.Value end
        function w:Get() return self.Value end
        function w:Apply(v) self:Set(v) end
        self.Widgets[#self.Widgets + 1] = w
        return w
    end
    function tab:CreateDropdown(o)
        local w = {Value = o.CurrentOption, Options = o.Options}
        function w:Set(v) self.Value = v end
        function w:SetValue(v) self:Set(v) end
        function w:SetOptions(list) self.Options = list end
        function w:Apply(v) self:Set(v) end
        self.Widgets[#self.Widgets + 1] = w
        return w
    end
    function tab:CreateButton(o)
        local w = {Fired = 0}
        function w:Fire() self.Fired = self.Fired + 1 if o.Callback then o.Callback() end end
        function w:Set() end
        self.Widgets[#self.Widgets + 1] = w
        return w
    end
    function tab:CreateInput(o)
        local w = {Value = ""}
        function w:Set(v) self.Value = tostring(v) end
        function w:Get() return self.Value end
        function w:Apply(v) self:Set(v) end
        self.Widgets[#self.Widgets + 1] = w
        return w
    end
    return tab
end

local function buildWindow(d)cb()
local e=false
local f=gethui_safe();
local g=l["WindowWidth"];
local j=l["WindowHeight"];
local n={}
local o={["Open"]=false,["Position"]=UDim2.new(0.5,0,0.5,0),["Closing"]=false,["PopupOpen"]=false,["Order"]=0,["LastTab"]=nil}
local d=d["Name"] or "ZapLib | By 'zap_xyz' and '1dnt'";
local p=eb("UIScale",{["Name"]="Scale",["Parent"]=T})
local s=eb("UIScale",{["Name"]="Scale"})
local function u(a,b,c,d)
local b=eb("ImageLabel",{["Name"]="Icon",["AnchorPoint"]=Vector2.new(0.5,0.5),["Position"]=UDim2.new(0.5,0,0.5,0),["Size"]=UDim2.new(0,16,0,16),["Image"]=b,["Theme"]={["ImageColor3"]="TextMuted"}})
local a=eb("TextButton",{["Name"]=a,
  ["AnchorPoint"]=Vector2.new(1,0.5),
  ["Position"]=UDim2.new(1,c,0.5,0),
  ["Size"]=UDim2.new(0,32,0,32),
  ["Theme"]={["BackgroundColor3"]="Surface"}},{Y(8),db("Stroke"),b
})U(a.MouseEnter,function ()ab(a,"BackgroundColor3",d)ab(b,"ImageColor3",((d=="Danger") and "Knob") or "Text")
end)
U(a.MouseLeave,
function ()ab(a,"BackgroundColor3","Surface")ab(b,"ImageColor3","TextMuted")
end)
return a
end;
local x=eb("TextLabel",{["Name"]="UITitle",["Position"]=UDim2.new(0,56,0,0),["Size"]=UDim2.new(1,-170,1,0),["FontFace"]=m["Bold"],["TextSize"]=16,["TextXAlignment"]=Enum["TextXAlignment"]["Left"],["TextTruncate"]=Enum["TextTruncate"]["AtEnd"],["Theme"]={["TextColor3"]="Text"}})
local y=W(x,
function ()
return C(d)
end)
local z=u("MinimizeButton",l.MinimizeIcon,-54,"SurfaceActive")
local u=u("CloseButton",l.CloseIcon,-14,"Danger")
local x=eb("Frame",{["Name"]="Top",["Size"]=UDim2.new(1,0,0,52),["BackgroundTransparency"]=1,["Active"]=true},{eb("ImageLabel",{["Name"]="Logo",["AnchorPoint"]=Vector2.new(0,0.5),["Position"]=UDim2.new(0,16,0.5,0),["Size"]=UDim2.new(0,30,0,30),["Image"]=l["LogoIcon"]},{Y(15)}),x,z,u,eb("Frame",{["Name"]="Divider",["AnchorPoint"]=Vector2.new(0,1),["Position"]=UDim2.new(0,0,1,0),["Size"]=UDim2.new(1,0,0,1),["Theme"]={["BackgroundColor3"]="Stroke"}})})
local B=eb("ScrollingFrame",{["Name"]="Tabs",["Position"]=UDim2.new(0,0,0,52),["Size"]=UDim2.new(0,200,1,-108)},{fb(12),gb(6)})
local E=eb("Frame",{["Name"]="Pages",["Position"]=UDim2.new(0,201,0,52),["Size"]=UDim2.new(1,-201,1,-108),["BackgroundTransparency"]=1,["ClipsDescendants"]=true})
local H=eb("ImageLabel",{["Name"]="Avatar",["AnchorPoint"]=Vector2.new(0,0.5),["Position"]=UDim2.new(0,16,0.5,0),["Size"]=UDim2.new(0,34,0,34),["Image"]="rbxasset://textures/ui/GuiImagePlaceholder.png",["BackgroundTransparency"]=0,["Theme"]={["BackgroundColor3"]="Raised"}},{Y(17),db("StrokeStrong")})
local I=eb("TextLabel",{["Name"]="WelcomeText",
  ["Position"]=UDim2.new(0,60,0,0),
  ["Size"]=UDim2.new(1,-130,1,0),
  ["FontFace"]=m["SemiBold"],
  ["TextSize"]=14,
  ["TextXAlignment"]=Enum["TextXAlignment"]["Left"],
  ["TextTruncate"]=Enum["TextTruncate"]["AtEnd"],
  ["Theme"]={["TextColor3"]="Text"}
})W(I,function ()
return D("Welcome, %s",G(i.Name))
end)
local G=eb("ImageLabel",{["Name"]="Icon",["AnchorPoint"]=Vector2.new(0.5,0.5),["Position"]=UDim2.new(0.5,0,0.5,0),["Size"]=UDim2.new(0,18,0,18),["Image"]=l["SettingsIcon"],["Theme"]={["ImageColor3"]="TextMuted"}})
local J=eb("TextButton",{["Name"]="SettingsButton",["AnchorPoint"]=Vector2.new(1,0.5),["Position"]=UDim2.new(1,-14,0.5,0),["Size"]=UDim2.new(0,34,0,34),["Theme"]={["BackgroundColor3"]="Surface"}},{Y(10),db("Stroke"),G})
local I=eb("Frame",{["Name"]="Bottom",["AnchorPoint"]=Vector2.new(0,1),["Position"]=UDim2.new(0,0,1,0),["Size"]=UDim2.new(1,0,0,56),["BackgroundTransparency"]=1,["Active"]=true},{H,I,J,eb("Frame",{["Name"]="Divider",["Size"]=UDim2.new(1,0,0,1),["Theme"]={["BackgroundColor3"]="Stroke"}})})
local K=eb("TextLabel",{["Name"]="Title",["Size"]=UDim2.new(1,0,0,22),["Loc"]="Close ZapHub?",["FontFace"]=m["Bold"],["TextSize"]=17,["TextXAlignment"]=Enum["TextXAlignment"]["Left"],["LayoutOrder"]=1,["Theme"]={["TextColor3"]="Text"}})
local L=eb("TextLabel",{["Name"]="Warning",["Size"]=UDim2.new(1,0,0,0),["AutomaticSize"]=Enum["AutomaticSize"]['Y'],["Loc"]="All running functions and loops will be stopped immediately. To reopen it, re-execute your script.",["TextWrapped"]=true,["TextSize"]=13,["TextXAlignment"]=Enum["TextXAlignment"]["Left"],["TextYAlignment"]=Enum["TextYAlignment"]["Top"],["LayoutOrder"]=2,["Theme"]={["TextColor3"]="TextMuted"}})
local Q=eb("TextButton",{["Name"]="Cancel",["Size"]=UDim2.new(0.5,-6,1,0),["Loc"]="Cancel",["FontFace"]=m["SemiBold"],["TextSize"]=14,["LayoutOrder"]=1,["Theme"]={["BackgroundColor3"]="Raised",["TextColor3"]="Text"}},{Y(10),db("Stroke")})
local S=eb("TextButton",{["Name"]="Button",["Size"]=UDim2.new(0.5,-6,1,0),["Loc"]="Close",["FontFace"]=m["Bold"],["TextSize"]=14,["LayoutOrder"]=2,["Theme"]={["BackgroundColor3"]="Danger",["TextColor3"]="Knob"}},{Y(10)})
local T=eb("Frame",{["Name"]="Handler",["Size"]=UDim2.new(1,0,0,40),["BackgroundTransparency"]=1,["LayoutOrder"]=3},{gb(12,Enum["FillDirection"].Horizontal),Q,S})
local K=eb("CanvasGroup",{["Name"]="Main",["AnchorPoint"]=Vector2.new(0.5,0.5),["Position"]=UDim2.new(0.5,0,0.5,20),["Size"]=UDim2.new(0,340,0,0),["AutomaticSize"]=Enum["AutomaticSize"]['Y'],["GroupTransparency"]=1,["Theme"]={["BackgroundColor3"]="Surface"}},{Y(14),db("StrokeAccent"),fb(20),gb(12),K,L,T})
local L=eb("Frame",{["Name"]="ClosePopUp",["Size"]=UDim2.new(1,0,1,0),["BackgroundTransparency"]=1,["Visible"]=false,["Active"]=true,["ZIndex"]=100,["Theme"]={["BackgroundColor3"]="Overlay"}},{Y(16),K})
local T=eb("Frame",{["Name"]="Window",["AnchorPoint"]=Vector2.new(0.5,0.5),["Position"]=UDim2.new(0.5,0,1.5,0),["Size"]=UDim2.new(0,g,0,j),["Visible"]=false,["Active"]=true,["Theme"]={["BackgroundColor3"]="Background"},["Parent"]=gethui_safe()},{Y(16),db("StrokeAccent"),p,eb("UIAspectRatioConstraint",{["AspectRatio"]=(g/j),["DominantAxis"]=Enum["DominantAxis"]["Width"]}),x,B,eb("Frame",{["Name"]="SidebarDivider",["Position"]=UDim2.new(0,200,0,52),["Size"]=UDim2.new(0,1,1,-108),["Theme"]={["BackgroundColor3"]="Stroke"}}),E,I,L})
local V=eb("TextLabel",{["Name"]="Label",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["FontFace"]=m["Bold"],["TextSize"]=14,["LayoutOrder"]=2,["Theme"]={["TextColor3"]="Text"}})
local D=W(V,
function ()
return D((o["Open"] and "Close") or "Open")
end)
local V=eb("TextButton",{["Name"]="ToggleButton",["Parent"]=f,["AnchorPoint"]=Vector2.new(0.5,0),["Position"]=UDim2.new(0.5,0,0,12),["Size"]=UDim2.new(0,0,0,42),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["Theme"]={["BackgroundColor3"]="Surface"},["Parent"]=gethui_safe()},{Y(21),db("StrokeAccent"),s,fb(7,0,16,0),gb(8,Enum["FillDirection"].Horizontal,Enum["HorizontalAlignment"].Left,Enum["VerticalAlignment"].Center),eb("ImageLabel",{["Name"]="Logo",["Size"]=UDim2.new(0,28,0,28),["Image"]=l["LogoIcon"],["LayoutOrder"]=1},{Y(14)}),V})
local function X(a)
local b=M(f)
local c=t["Settings"]["Scale"];
w.Play(p,a or 0,{["Scale"]=(math.clamp(math.min((b['X']-24)/g,(b['Y']-24)/j),0.5,1.25)*c)},false,Enum["EasingStyle"].Quint)w.Play(s,a or 0,{["Scale"]=(math.clamp(math.min(b['X']/900,b['Y']/650)+0.2,0.8,1.2)*c)},false,Enum["EasingStyle"].Quint)
end;
N(f,
function ()X()
end)
task.spawn(
function ()
local a,b=pcall(Players.GetUserThumbnailAsync,Players,LP.UserId,Enum["ThumbnailType"].HeadShot,Enum["ThumbnailSize"].Size100x100)
if (a and H["Parent"]) then
  H["Image"]=b
end
end)
local function a(a)
if (o["Open"]~=a) then
else
return
end;
o["Open"]=a;
bb(D)
if a then
  T["Visible"]=true;
w.Play(T,l.Slow,{["Position"]=o["Position"]},false,Enum["EasingStyle"].Quint)
else
local a=UDim2.new(o["Position"]['X'].Scale,o["Position"]['X'].Offset,o["Position"]['Y']["Scale"]+1,o["Position"]['Y'].Offset)O(
function ()w.Play(T,l.Slow,{["Position"]=a},true,Enum["EasingStyle"].Quint,Enum["EasingDirection"].In)
if not o["Open"] then
  T["Visible"]=false
end
end)
end
end;
local function g(a)o["PopupOpen"]=a;
if a then
  L["Visible"]=true;
w.Play(L,l.Normal,{["BackgroundTransparency"]=0.45})w.Play(K,l.Slow,{["GroupTransparency"]=0,["Position"]=UDim2.new(0.5,0,0.5,0)},false,Enum["EasingStyle"].Quint)
else w.Play(K,l.Normal,{["GroupTransparency"]=1,
  ["Position"]=UDim2.new(0.5,0,0.5,20)})O(function ()w.Play(L,l.Normal,{["BackgroundTransparency"]=1
},true)
if ( not o["PopupOpen"]) then
  L["Visible"]=false
end
end)
end
end;
local function i()o["Position"]=T["Position"]
end;
r(x,T,nil,i)r(I,T,nil,i)r(V,V,
function ()a( not o["Open"])
end)
table.insert(input.Began,
function(b)
if (((b["KeyCode"]==l["ToggleKey"]) and not c:GetFocusedTextBox())) then
  a( not o["Open"])
end
end)
z["MouseButton1Click"]:Connect(
function ()a(false)
end)
u["MouseButton1Click"]:Connect(
function ()
if ( not o["Closing"]) then
  g(true)
end
end)
Q["MouseButton1Click"]:Connect(
function ()g(false)
end)
S["MouseButton1Click"]:Connect(
function ()
if o["Closing"] then
  return
end;
o["Closing"]=true;
g(false)t:CreateNotification({["Title"]="Closing ZapHub",
  ["Content"]="ZapHub is closing. All running functions and loops will be stopped immediately. To reopen it, re-execute your script."
})P(l.CloseDelay,function ()t:Destroy()
end)
end)
local b;
local function c(a,c,d)o["Order"]=o["Order"]+1;
local e={["Name"]=a,["Internal"]=d,["Functions"]={},["Count"]=0}e["Page"]=eb("Frame",{["Name"]="Page",["Size"]=UDim2.new(1,0,1,0),["BackgroundTransparency"]=1,["Visible"]=false,["Parent"]=E})e["Scroll"]=eb("ScrollingFrame",{["Name"]="Scroll",["Size"]=UDim2.new(1,0,1,0),["Parent"]=e["Page"],["Theme"]={["ScrollBarImageColor3"]="StrokeStrong"}},{fb(14,12,16,12),gb(8)})
if d then
  e.Style =
  function(a)ab(J,"BackgroundColor3",(a and "SurfaceActive") or "Surface")ab(G,"ImageColor3",(a and "AccentText") or "TextMuted")
end
else
local c=eb("ImageLabel",{["Name"]="Icon",["AnchorPoint"]=Vector2.new(0,0.5),["Position"]=UDim2.new(0,14,0.5,0),["Size"]=UDim2.new(0,18,0,18),["Image"]=(F(c) or l["DefaultIcon"]),["Theme"]={["ImageColor3"]="TextMuted"}})
local d=eb("TextLabel",{["Name"]="Label",
  ["Position"]=UDim2.new(0,44,0,0),
  ["Size"]=UDim2.new(1,-54,1,0),
  ["FontFace"]=m["SemiBold"],
  ["TextSize"]=13,
  ["TextXAlignment"]=Enum["TextXAlignment"]["Left"],
  ["TextTruncate"]=Enum["TextTruncate"]["AtEnd"],
  ["Theme"]={["TextColor3"]="TextMuted"}
})W(d,function ()
return C(a)
end)
local a=eb("Frame",{["Name"]="Bar",["AnchorPoint"]=Vector2.new(0,0.5),["Position"]=UDim2.new(0,0,0.5,0),["Size"]=UDim2.new(0,3,0,18),["BackgroundTransparency"]=1,["Theme"]={["BackgroundColor3"]="Accent"}},{Y(2)})
local f=eb("TextButton",{["Name"]="Tab",["Size"]=UDim2.new(1,0,0,40),["LayoutOrder"]=o["Order"],["Parent"]=B,["Theme"]={["BackgroundColor3"]="Background"}},{Y(10),a,c,d})e["Button"]=f;
e.Style =
function(b)ab(f,"BackgroundColor3",(b and "SurfaceActive") or "Background")ab(d,"TextColor3",(b and "AccentText") or "TextMuted")ab(c,"ImageColor3",(b and "AccentText") or "TextMuted")w.Play(a,l.Fast,{["BackgroundTransparency"]=((b and 0) or 1)})
end;
f["MouseButton1Click"]:Connect(
function ()b(e)
end)
U(f.MouseEnter,
function ()
if ((t["SelectedTab"]~=e)) then
  ab(f,"BackgroundColor3","SurfaceHover")
end
end)
U(f.MouseLeave,
function ()
if (t["SelectedTab"]==e) then
else ab(f,"BackgroundColor3","Background")
end
end)
table.insert(t.Tabs,e)
end;
A(e)
return e
end;
local function switchTab(a)
local b=t["SelectedTab"];
if ((b==a)) then
  return
end;
t["SelectedTab"]=a;
if (b) then
  b.Style(false)b["Page"]["Visible"]=false
end;
a.Style(true)a["Page"]["Position"]=UDim2.new(0,0,0,14)a["Page"]["Visible"]=true;
w.Play(a.Page,l.Slow,{["Position"]=UDim2.new(0,0,0,0)},false,Enum["EasingStyle"].Quint)
end;
local g=c("Settings",l.SettingsIcon,true)U(J.MouseEnter,
function ()
if (t["SelectedTab"]==g) then
else ab(J,"BackgroundColor3","SurfaceHover")
end
end)
U(J.MouseLeave,
function ()
if ((t["SelectedTab"]~=g)) then
  ab(J,"BackgroundColor3","Surface")
end
end)
U(V.MouseEnter,
function ()ab(V,"BackgroundColor3","SurfaceHover")
end)
U(V.MouseLeave,
function ()ab(V,"BackgroundColor3","Surface")
end)
J["MouseButton1Click"]:Connect(
function ()
if (t["SelectedTab"]==g) then
  switchTab(o["LastTab"] or t["Tabs"][1] or g)
else o["LastTab"]=t["SelectedTab"];
switchTab(g)
end
end)
n.CreateTab =
function (a,a,d)
local a=c(a or "Tab",d,false)
if ( not o["LastTab"]) then
  o["LastTab"]=a
end;
if ( not t["SelectedTab"]) then
  switchTab(a)
end;
return a["Functions"]
end;
n.SetTitle =
function(a,a)d=a or d;
bb(y)
end;
n.SaveConfig =
function(a)
return nil
end;
n.ExportConfig =
function(a)
return b:JSONEncode(t.Flags)
end;
n.LoadConfig =
function(a,text)
local ok, decoded = pcall(function() return b:JSONDecode(text) end)
if (not ok or type(decoded) ~= "table") then
  t:CreateNotification({["Title"]="Configuration Manager",["Content"]="Invalid configuration."})
  return false
end;
for key, value in pairs(decoded) do
  if (key ~= l["ReservedKey"]) then
    t["Flags"][key] = value
    local el = t["Elements"][key]
    if el then el.Apply(value, true, true) end
  end
end;
t:CreateNotification({["Title"]="Configuration Manager",["Content"]="Configuration loaded and applied."})
return true
end;
n.Load =
function (b,b,c)
if ((type(c)=="string")and(c~="")) then
  n:LoadConfig(c)
end;
if ((b=="NoGUI")) then
  f["Enabled"]=false
elseif ((b=="GUI")) then
  f["Enabled"]=true;
a(true)
end
end;
n.Toggle =
function(b,b)if (type(b)=="boolean") then  a(b)else a(not o["Open"])end
end;
n.Destroy =
function(a)t:Destroy()
end;
t.Toggle =
function(a,a)n:Toggle(a)
end;
local b="";
local themeOrder = {"Dark", "Light", "Discord", "Dracula", "GitHub Dark", "Gruvbox Dark",
    "Halloween", "Rosé Pine", "Solarized Light", "Windows Vista", "Windows XP"}
local languageNames = {"English", "Bahasa Indonesia", "Deutsch", "Español", "Filipino",
    "Français", "Polski", "Português", "Română", "Tiếng Việt", "Türkçe",
    "Русский", "Українська", "ไทย"}
local function themeNames()
    local out = {}
    for _, name in ipairs(themeOrder) do
        if themes[name] then out[#out + 1] = name end
    end
    return out
end
local settingsHooks = {}
t.GetThemes = function() return themeNames() end
t.GetLanguages = function() return {table.unpack(languageNames)} end
t.GetAnimationMode = function() return t.Settings.AnimationMode end
t.SetLanguage = function(_, lang)
    if (not table.find(languageNames, lang)) then return false end
    t.Settings.Language = lang
    if (t.Window and t.Window.SetTitle) then t.Window:SetTitle() end
    for _, hook in ipairs(settingsHooks) do hook("Language", lang) end
    return true
end
t.OnSettingChanged = function(_, hook)
    table.insert(settingsHooks, hook)
    return function()
        local i = table.find(settingsHooks, hook)
        if i then table.remove(settingsHooks, i) end
    end
end
t.CreateNotification = function(_, opts) return {Close = function() end} end
t.CreateQuest = function(_, opts) return {Update = function() end, Destroy = function() end} end
local c=makeRealTab();
c:CreateSection("Appearance")
local d=c:CreateDropdown({["Name"]="Theme",
  ["Options"]=t:GetThemes(),
  ["CurrentOption"]=q["Name"],
  ["Internal"]=true,
  ["Callback"]=function(a
)
if ((a~=q["Name"])) then
  t:SetTheme(a)
end
end})
local f=c:CreateDropdown({["Name"]="Language",
  ["Options"]=t:GetLanguages(),
  ["CurrentOption"]=t["Settings"]["Language"],
  ["Internal"]=true,
  ["Callback"]=function(a
)
if (a==t["Settings"]["Language"]) then
else t:SetLanguage(a)
end
end})c:CreateSection("Performance")
local g=c:CreateDropdown({["Name"]="Animation Mode",
  ["Options"]={"Smooth","Basic"},
  ["CurrentOption"]=t["Settings"]["AnimationMode"],["Internal"]=true,["Callback"]=function(a)
if (a==t["Settings"]["AnimationMode"]) then
else t:SetAnimationMode(a)
end
end})c:CreateParagraph({["Title"]="Animation Mode",
  ["Content"]="Smooth uses animated transitions. Basic makes everything instant to save CPU and memory."
})c:CreateSection("Interface")local i=c:CreateToggle({["Name"]="Show Notifications",
  ["CurrentValue"]=t["Settings"]["Notifications"],
  ["Internal"]=true,
  ["Callback"]=function(a
)
if (a==t["Settings"]["Notifications"]) then
else t:SetNotificationsEnabled(a)
end
end})
local j=c:CreateToggle({["Name"]="Show Quests",
  ["CurrentValue"]=t["Settings"]["Quests"],
  ["Internal"]=true,
  ["Callback"]=function(a
)
if ((a~=t["Settings"]["Quests"])) then
  t:SetQuestsEnabled(a)
end
end})
local m=c:CreateSlider({["Name"]="Interface Scale",["Range"]={0.5,1.5},["Increment"]=0.05,["Suffix"]="x",["CurrentValue"]=t["Settings"]["Scale"],["Internal"]=true,["CallbackOnRelease"]=true,["Callback"] =
function(a)
if ((a~=t["Settings"]["Scale"])) then
  t:SetInterfaceScale(a)
end
end})c:CreateParagraph({["Title"]="Interface Scale",
  ["Content"]="Multiplies the automatic screen scale. It is applied when you release the slider."})c:CreateSection("Configuration")c:CreateButton({["Name"]="Save Configuration",
  ["Callback"]=function ()n:SaveConfig()t:CreateNotification({["Title"]="Configuration Manager",
  ["Content"]="Configuration saved."
})
end})c:CreateButton({["Name"]="Export Configuration",
  ["Callback"]=function ()
if (k["SetClipboard"]) then
  k.SetClipboard(n:ExportConfig())t:CreateNotification({["Title"]="Configuration Manager",["Content"]="Configuration copied to the clipboard."})
else t:CreateNotification({["Title"]="Configuration Manager",["Content"]="Your executor does not support the clipboard."})warn("[ZapLib] Configuration: "..n:ExportConfig())
  end
end})c:CreateInput({["Name"]="Import Configuration",
  ["PlaceholderText"]="Paste a configuration here",
  ["Internal"]=true,
  ["Callback"]=function(a)b=
a
end})c:CreateButton({["Name"]="Load Configuration",
  ["Callback"]=function ()n:LoadConfig(b
)
end})t.OnSettingChanged(
function(a,b)
if (a=="Theme") then
  d:SetValue(b,true)
elseif (a=="Themes") then
  d:SetOptions(t:GetThemes())
elseif ((a=="Language")) then
  f:SetValue(b,true)
elseif (a=="Languages") then
  f:SetOptions(t:GetLanguages())
elseif ((a=="AnimationMode")) then
  g:SetValue(b,true)
elseif (a=="Notifications") then
  i:Set(b)
elseif (a=="Quests") then
  j:Set(b)
elseif ((a=="Scale")) then
  m:Set(b)X(l.Normal)
end
end)
if e then
  t:CreateNotification({["Title"]="Configuration Manager",["Content"]="The saved configuration from a previous session has been loaded correctly."})
else t:CreateNotification({["Title"]="Configuration Manager",["Content"]="Remember that the configuration is saved for future sessions."})
end;
t["Window"]=n;
a(true)
return {Frame = T, Toggle = V, Tabs = B}
end;

local d = {}
local function S(fn, ...) return fn(...) end
local function reg(obj, names)
    for _, name in ipairs(names) do
        local fn = rawget(obj, name)
        if type(fn) == "function" then
            obj[name] = function(...) return fn(...) end
        end
    end
end
local a=t["Generation"];
for b,c in pairs(d) do
  d[b] =
  function (...)
  if (t["Generation"]==a) then
  else
  return nil
end;
local a=S(c,...)
if ((type(a)=="table")) then
  reg(a,{"Set","SetValue","SetOptions"})
end;
return a
end
end


local function buildKaitun(a)B()
local b=gethui_safe()
for a,a in ipairs(b:GetChildren()) do
  if ((a["Name"]=="KaitunZapLib")) then
    a:Destroy()
  end
end;
local c=1100;
local d=620;
local a={["Title"]=(a["Title"] or "Kaitun"),["SubTitle"]=(a["SubTitle"] or "Premium unlocked"),["Footer"]=(a["Footer"] or "discord.gg/zaphub"),["Elapsed"]=0,["Running"]=true,["Order"]=0}
local e={}
local g=eb("ScreenGui",{["Name"]="KaitunZapLib",
  ["ResetOnSpawn"]=false,
  ["ZIndexBehavior"]=Enum["ZIndexBehavior"]["Sibling"],
  ["DisplayOrder"]=999999999,
  ["IgnoreGuiInset"]=true,
  ["Parent"]=gethui_safe()
})pcall(function ()g["ScreenInsets"]=Enum["ScreenInsets"]["None"]
end)
local function i(a,b)
return eb("Frame",{["Name"]=a,["Size"]=UDim2.new(1,0,1,0),["Theme"]={["BackgroundColor3"]="Accent"}},{eb("UIGradient",{["Rotation"]=b,["Transparency"]=NumberSequence.new({NumberSequenceKeypoint.new(0,0.9),NumberSequenceKeypoint.new(0.5,1),NumberSequenceKeypoint.new(1,1)})})})
end;
local i=eb("Frame",{["Name"]="Cover",["Size"]=UDim2.new(1,0,1,0),["Active"]=true,["Theme"]={["BackgroundColor3"]="Background"},["Parent"]=g},{i("GlowTopRight",135),i("GlowBottomLeft",315)})
local i=eb("Frame",{["Name"]="Safe",["Size"]=UDim2.new(1,0,1,0),["BackgroundTransparency"]=1,["Parent"]=i})
local j=eb("UIScale",{["Name"]="Scale"})
local k=eb("Frame",{["Name"]="Canvas",["Size"]=UDim2.new(1,0,1,0),["BackgroundTransparency"]=1,["Parent"]=i},{j})eb("Frame",{["Name"]="Brand",["Position"]=UDim2.new(0,32,0,16),["Size"]=UDim2.new(0,0,0,52),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["BackgroundTransparency"]=1,["Parent"]=k},{gb(12,Enum["FillDirection"].Horizontal,Enum["HorizontalAlignment"].Left,Enum["VerticalAlignment"].Center),eb("ImageLabel",{["Name"]="Logo",["Size"]=UDim2.new(0,52,0,52),["Image"]=l["LogoIcon"],["LayoutOrder"]=1},{Y(26)}),eb("Frame",{["Name"]="Name",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["BackgroundTransparency"]=1,["LayoutOrder"]=2},{gb(0,Enum["FillDirection"].Horizontal,Enum["HorizontalAlignment"].Left,Enum["VerticalAlignment"].Center),eb("TextLabel",{["Name"]="Zap",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["Text"]="Zap",["FontFace"]=m["Heavy"],["TextSize"]=40,["LayoutOrder"]=1,["Theme"]={["TextColor3"]="Text"}}),eb("TextLabel",{["Name"]="Hub",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["Text"]="Hub",["FontFace"]=m["Heavy"],["TextSize"]=40,["LayoutOrder"]=2,["Theme"]={["TextColor3"]="AccentText"}})})})
local n=eb("TextLabel",{["Name"]="Time",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["Text"]=J(0),["FontFace"]=m["Mono"],["TextSize"]=22,["LayoutOrder"]=2,["Theme"]={["TextColor3"]="Text"}})
local hz=eb("Frame",{["Name"]="Timer",["AnchorPoint"]=Vector2.new(1,0),["Position"]=UDim2.new(1,-32,0,19),["Size"]=UDim2.new(0,0,0,46),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["BackgroundTransparency"]=0.3,["Parent"]=k,["Theme"]={["BackgroundColor3"]="Glass"}},{Y(23),fb(18,0,18,0),gb(10,Enum["FillDirection"].Horizontal,Enum["HorizontalAlignment"].Left,Enum["VerticalAlignment"].Center),eb("UIStroke",{["Thickness"]=1,["Transparency"]=0.8,["ApplyStrokeMode"]=Enum["ApplyStrokeMode"]["Border"],["Theme"]={["Color"]="GlassStroke"}}),eb("UIGradient",{["Rotation"]=90,["Transparency"]=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,0.35)})}),eb("Frame",{["Name"]="Dot",["Size"]=UDim2.new(0,9,0,9),["LayoutOrder"]=1,["Theme"]={["BackgroundColor3"]="Accent"}},{Y(5)}),n})
hz["Parent"]=k
local o=eb("TextLabel",{["Name"]="Title",["AnchorPoint"]=Vector2.new(0.5,0),["Position"]=UDim2.new(0.5,0,0,88),["Size"]=UDim2.new(1,-64,0,96),["FontFace"]=m["Heavy"],["TextSize"]=84,["TextTruncate"]=Enum["TextTruncate"]["AtEnd"],["Parent"]=k,["Theme"]={["TextColor3"]="Text"}})
local p=eb("TextLabel",{["Name"]="SubTitle",["AnchorPoint"]=Vector2.new(0.5,0),["Position"]=UDim2.new(0.5,0,0,184),["Size"]=UDim2.new(1,-64,0,28),["FontFace"]=m["BoldItalic"],["TextSize"]=20,["TextTruncate"]=Enum["TextTruncate"]["AtEnd"],["Parent"]=k,["Theme"]={["TextColor3"]="AccentText"}})
local o=W(o,
function ()
return C(a.Title)
end)
local p=W(p,
function ()
return C(a.SubTitle)
end)
local q=eb("ScrollingFrame",{["Name"]="Stats",["AnchorPoint"]=Vector2.new(0.5,0),["Position"]=UDim2.new(0.5,0,0,240),["Size"]=UDim2.new(1,-64,1,-304),["ScrollBarThickness"]=0,["Parent"]=k},{gb(10),fb(4),eb("UISizeConstraint",{["MaxSize"]=Vector2.new(760,math.huge)})})
local r=eb("TextLabel",{["Name"]="Footer",["AnchorPoint"]=Vector2.new(1,1),["Position"]=UDim2.new(1,-32,1,-20),["Size"]=UDim2.new(0,0,0,24),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["FontFace"]=m["Bold"],["TextSize"]=18,["Parent"]=k,["Theme"]={["TextColor3"]="Text"}})
local r=W(r,
function ()
return C(a.Footer)
end)
local function s()
local a=f:GetGuiInset()['Y'];
i["Position"]=UDim2.new(0,0,0,a)i["Size"]=UDim2.new(1,0,1,-a)
local b=M(g)
local e=b['X'];
local a=math.max(b['Y']-a,1)
local a=math.clamp(math.min(e/c,a/d),0.4,1.5)j["Scale"]=a;
k["Size"]=UDim2.new(1/a,0,1/a,0)
end;
N(g,s)pcall(
function ()T(f:GetPropertyChangedSignal("TopbarInset"),s)
end)
local function c()n["Text"]=J(a.Elapsed)
end;
e.SetTitle =
function(b,b)a["Title"]=b or a["Title"];
bb(o)
end;
e.SetSubTitle =
function(b,b)a["SubTitle"]=b or a["SubTitle"];
bb(p)
end;
e.SetFooter =
function(b,b)a["Footer"]=b or a["Footer"];
bb(r)
end;
e.SetTimer =
function(b,b)a["Elapsed"]=tonumber(b)or 0;
c()
end;
e.GetTimer =
function(b)
return a["Elapsed"]
end;
e.StartTimer =
function(b)a["Running"]=true
end;
e.StopTimer =
function(b)a["Running"]=false
end;
e.AddStat =
function(b,b)b=((type(b)=="table")and b)or{["Value"]=b}a["Order"]=a["Order"]+1;
local b=b;
b["Value"]=((b["Value"]==nil) and 0) or b["Value"];
local c=eb("ImageLabel",{["Name"]="Thumbnail",["Size"]=UDim2.new(0,30,0,30),["Image"]=(F(b.Icon) or l["StatIcon"]),["LayoutOrder"]=1,["Theme"]={["ImageColor3"]="Text"}})
local d=eb("TextLabel",{["Name"]="Amount",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["FontFace"]=m["Bold"],["TextSize"]=22,["TextXAlignment"]=Enum["TextXAlignment"]["Left"],["LayoutOrder"]=2,["Theme"]={["TextColor3"]="Text"}})
local e=eb("TextLabel",{["Name"]="StatName",["Size"]=UDim2.new(0,0,1,0),["AutomaticSize"]=Enum["AutomaticSize"]['X'],["FontFace"]=m["Medium"],["TextSize"]=16,["TextXAlignment"]=Enum["TextXAlignment"]["Left"],["LayoutOrder"]=3,["Theme"]={["TextColor3"]="TextMuted"}})
local a=eb("Frame",{["Name"]="StatFrame",["Size"]=UDim2.new(1,0,0,56),["LayoutOrder"]=a["Order"],["Parent"]=q,["Theme"]={["BackgroundColor3"]="Surface"}},{Y(12),db("StrokeStrong",1.5),fb(16,0,16,0),gb(14,Enum["FillDirection"].Horizontal,Enum["HorizontalAlignment"].Left,Enum["VerticalAlignment"].Center),c,d,e})
local f=W(e,
function ()
return (b["Name"] and C(b.Name)) or ""
end)
local function g()d["Text"]=((type(b.Format)=="function") and tostring(b.Format(b.Value))) or H(b.Value)bb(f)e["Visible"]=b["Name"]~=nil
end;
g()b.Set=
function(a,a)b["Value"]=a;
g()
end;
b.Get =
function(a)
return b["Value"]
end;
b.SetName =
function(a,a)b["Name"]=a;
g()
end;
b.SetIcon =
function(a,a)c["Image"]=F(a)or l["StatIcon"]
end;
b.Destroy =
function(b)a:Destroy()
end;
return b
end;
e.Destroy =
function(a)t:Destroy()
end;
O(
function ()
local b=os.clock()
while not t["Destroyed"] do
  task.wait(1)
  local d=os.clock()
  if (a["Running"]) then
    a["Elapsed"]=a["Elapsed"]+(d-b)c()
  end;
b=d
end
end)
e["Gui"]=g;
u["KaitunGui"]=g;
g["Parent"]=b;
T(g.Destroying,
function ()t:Destroy()
end)
return e
end;
local function setTheme(name)
    if (not themes[name]) then return false end
    q.Name = name
    q.Colors = themes[name]
    t.Settings.Theme = name
    applyTheme()
    for _, hook in ipairs(settingsHooks) do hook("Theme", name) end
    return true
end
t.SetTheme = function(_, name) return setTheme(name) end
t.GetTheme = function() return q.Name end
t.SetAnimationMode = function(_, mode)
    if (mode ~= "Smooth" and mode ~= "Basic") then return false end
    t.Settings.AnimationMode = mode
    for _, hook in ipairs(settingsHooks) do hook("AnimationMode", mode) end
    return true
end
t.SetNotificationsEnabled = function(_, on)
    t.Settings.Notifications = on == true
    for _, hook in ipairs(settingsHooks) do hook("Notifications", t.Settings.Notifications) end
end
t.SetQuestsEnabled = function(_, on)
    t.Settings.Quests = on == true
    for _, hook in ipairs(settingsHooks) do hook("Quests", t.Settings.Quests) end
end
t.SetInterfaceScale = function(_, scale)
    scale = math.clamp(tonumber(scale) or 1, 0.5, 1.5)
    t.Settings.Scale = scale
    for _, hook in ipairs(settingsHooks) do hook("Scale", scale) end
end
t.GetSetting = function(_, key) return t.Settings[key] end
t.Destroy = function()
    t.Destroyed = true
    t.Generation = t.Generation + 1
    for obj in pairs(trackers) do
        pcall(function() obj:Destroy() end)
    end
    if t.Kaitun then pcall(function() t.Kaitun.Destroy(t.Kaitun) end) end
    t.Tabs = {}
    t.Elements = {}
    t.Window = nil
    _G.ZapLib = nil
end

if (_G.ZapLib and _G.ZapLib.Destroy) then
    pcall(function() _G.ZapLib:Destroy() end)
end

local win = buildWindow({Name = "ZapHub | by zap_xyz and 1dnt"})
local kat = buildKaitun({Title = "ZapHub", SubTitle = "Premium unlocked", Footer = "discord.gg/zaphub"})
t.Kaitun = kat
t.KaitunActive = true
if win.Toggle then
    win.Toggle.Visible = false
end
_G.ZapLib = t
