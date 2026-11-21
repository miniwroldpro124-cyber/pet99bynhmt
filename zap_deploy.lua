--[[
    ZapHub / PS99 — interface + engine

    Two pieces, both recovered and both keyless:

      zaphub.lua       ZapLib 2.0.0, the interface. window, tabs, elements,
                       notifications, config store.
      ps99_engine.lua  PS99 CLEAN, the farm engine. 35 workers, full remote map
                       for Pet Simulator 99: breakables, tap, orbs, eggs, quests,
                       ranks, rebirth, keys, dice, fuse, daycare, world advance.

    The engine ships its own panel (ScreenGui "PS99CLEAN"). It is left intact and
    hidden — the Pickers tab opens it, because the auto-consume workers only touch
    the ids ticked in that panel. Everything the panel calls is a plain controller:
    __PS99CLEAN.SetEnabled / SetWorld / SetPick / GetStatus / AllOff / Stop.

    RightControl  ZapLib window
    Insert        engine panel (pickers)
    X             unload engine and clear the interface
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local BASE = "https://raw.githubusercontent.com/miniwroldpro124-cyber/pet99bynhmt/main/"
local LIB_URL = BASE .. "zaphub.lua"
local ENGINE_URL = BASE .. "ps99_engine_v2.lua"

-- game:HttpGet is not a DataModel member on every executor; the request family is.
local function httpGet(url)
    for _, fn in ipairs({
        function() return syn.request({ Url = url, Method = "GET" }).Body end,
        function() return request({ Url = url, Method = "GET" }).Body end,
        function() return http_request({ Url = url, Method = "GET" }).Body end,
        function() return game:HttpGet(url) end,
    }) do
        local ok, body = pcall(fn)
        if ok and type(body) == "string" and #body > 500 then
            return body
        end
    end
    return nil
end

local function loadSource(src, label)
    if type(src) ~= "string" or #src < 500 then
        error("[ZapHub] " .. label .. ": fetch failed", 0)
    end
    local chunk, err = loadstring(src)
    if not chunk then
        error("[ZapHub] " .. label .. ": " .. tostring(err), 0)
    end
    return chunk
end

if not player then
    return warn("[ZapHub] no LocalPlayer")
end

-- ===========================================================================
-- engine
-- ===========================================================================

local engine = _G["__PS99CLEAN"]
if type(engine) ~= "table" or type(engine.SetEnabled) ~= "function" then
    local ok, err = pcall(loadSource(httpGet(ENGINE_URL), "engine"))
    if not ok then
        return warn(tostring(err))
    end
    engine = _G["__PS99CLEAN"]
end
if type(engine) ~= "table" then
    return warn("[ZapHub] engine loaded but published no controller")
end

local function enginePanel()
    local pg = player:FindFirstChild("PlayerGui")
    return pg and pg:FindFirstChild("PS99CLEAN") or nil
end

local function showEnginePanel(on)
    local panel = enginePanel()
    if panel then
        panel.Enabled = on
        return true
    end
    return false
end

showEnginePanel(false)

-- ===========================================================================
-- interface
-- ===========================================================================

local lib = _G["ZapLib"]
if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    local ok, err = pcall(loadSource(httpGet(LIB_URL), "library"))
    if not ok then
        return warn(tostring(err))
    end
    lib = _G["ZapLib"]
end
if type(lib) ~= "table" or type(lib.Window) ~= "table" then
    return warn("[ZapHub] library loaded but no window")
end

local win = lib.Window

-- label, engine key, default. The engine reads these through SetEnabled, so the
-- default here must match enabled{} in ps99_engine.lua or the first click is a
-- no-op that looks like a dead toggle.
local function toggle(tab, label, key, default, note)
    tab:CreateToggle({
        Name = label,
        CurrentValue = default == true,
        Callback = function(v)
            local ok, err = engine.SetEnabled(key, v)
            if not ok then
                lib:CreateNotification({ Title = "Engine", Content = tostring(err) })
            end
        end,
    })
    if note then
        tab:CreateParagraph({ Title = label, Content = note })
    end
end

local farmTab = win:CreateTab("Farm", "rbxassetid://82329173638641")

farmTab:CreateSection("Breakables")
toggle(farmTab, "Auto Farm", "farm", false,
    "Walks the target and sends Breakables_PlayerDealDamage on the engine's own tick.")
toggle(farmTab, "Auto Tap", "tap", false,
    "Taps every breakable in range without moving.")
toggle(farmTab, "Click Aura", "clickAura", false,
    "Aura ring that taps anything that enters it.")
toggle(farmTab, "Orb Vacuum", "vacuum", false,
    "Forces the super-magnet flag on nearby orbs and collects them.")
farmTab:CreateSection("Speed")
farmTab:CreateSlider({
    Name = "Hit Rate",
    Range = { 1, 48 },
    Increment = 1,
    Suffix = "/s",
    CurrentValue = 48,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("MaxTapRate", v)
        lib:CreateNotification({ Title = "Farm", Content = "Hit rate " .. math.floor(v) .. "/s" })
    end,
})
farmTab:CreateSlider({
    Name = "Burst Targets",
    Range = { 0, 12 },
    Increment = 1,
    CurrentValue = 6,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("FarmBurst", v)
        lib:CreateNotification({ Title = "Farm", Content = "Burst " .. math.floor(v) .. " extra per hit" })
    end,
})
farmTab:CreateSlider({
    Name = "Reach",
    Range = { 50, 400 },
    Increment = 10,
    Suffix = "studs",
    CurrentValue = 220,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("TapRange", v)
    end,
})
farmTab:CreateSlider({
    Name = "Target Rescan",
    Range = { 0.05, 0.6 },
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.12,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("TargetRescan", v)
    end,
})
farmTab:CreateSection("Priority")
toggle(farmTab, "Chests First", "chestFirst", true,
    "Chests win the tiebreak over normal breakables in the same scan.")
toggle(farmTab, "Route All Pets", "petAll", true,
    "Sends every owned pet at the target. OFF matches the game's own click, which only routes the nearest half.")
toggle(farmTab, "Pet Bulk Join", "petBulkJoin", true,
    "Registers every routed pet on the server the moment the target changes, so pets count from the first hit instead of after they travel.")
farmTab:CreateSlider({
    Name = "Pet Re-route",
    Range = { 0.05, 0.5 },
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.15,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("PetRouteRate", v)
    end,
})
farmTab:CreateSection("Pets")
toggle(farmTab, "Pet Speed", "petSpeed", false,
    "Snaps pet positions to their target each frame. Render-side only.")
toggle(farmTab, "Auto Hatch", "autoEgg", false,
    "Buys and hatches the nearest egg, up to 50 per pass.")
toggle(farmTab, "Hide Egg Effects", "hideEggFx", false,
    "Kills hatch particles, beams and lights under the egg folders.")
farmTab:CreateSection("Movement")
toggle(farmTab, "Jitter", "jitter", false,
    "Micro-movement so an idle kick cannot land.")
toggle(farmTab, "Aura Visual", "auraVisual", false,
    "Draws the aura ring. Cosmetic.")

local worldTab = win:CreateTab("World", "rbxassetid://16259403210")

worldTab:CreateSection("Zones")
toggle(worldTab, "Auto Teleport Best Zone", "zoneTele", false,
    "Teleports to the highest zone you own the moment it is available.")
toggle(worldTab, "Snap To Zone Centre", "teleCenter", true,
    "Lands you on the middle of the zone instead of the spawn edge. This is what makes the teleport instant.")
toggle(worldTab, "Auto Buy Next Zone", "zoneBuy", false,
    "Purchases with the game's own currency checks. Nothing is spent that the game would refuse.")
worldTab:CreateSlider({
    Name = "Teleport Retry",
    Range = { 0.2, 5 },
    Increment = 0.2,
    Suffix = "s",
    CurrentValue = 0.4,
    CallbackOnRelease = true,
    Callback = function(v)
        engine.SetConfig("TeleInterval", v)
    end,
})
worldTab:CreateParagraph({
    Title = "World hopping",
    Content = "Removed. The engine no longer teleports you between worlds and the advance worker starts off. You stay in the world you are in.",
})

local progTab = win:CreateTab("Progress", "rbxassetid://15642579187")

progTab:CreateSection("Quests")
toggle(progTab, "Auto Quests", "autoQuest", false,
    "Ensures, tracks and redeems NPC quests.")
progTab:CreateSection("Rank")
toggle(progTab, "Auto Claim Ranks", "autoRank", false)
toggle(progTab, "Auto Rebirth", "autoRebirth", false)
toggle(progTab, "Auto Buy Pet Slots", "autoBuyPetSlots", false,
    "Stops at 80 slots.")

local autoTab = win:CreateTab("Auto", "rbxassetid://16089599792")

autoTab:CreateSection("Consumables")
toggle(autoTab, "Auto Keys", "autoKeys", false,
    "Combines and unlocks the key set. Only the keys ticked in the Pickers panel are touched.")
toggle(autoTab, "Auto Gift Bags", "autoGiftBags", false)
toggle(autoTab, "Auto Fruits", "autoFruits", false)
toggle(autoTab, "Auto Potions", "autoPotions", false)
toggle(autoTab, "Auto Free Gifts", "autoFreeGifts", false)
toggle(autoTab, "Auto Ultimates", "autoUltimate", false)
toggle(autoTab, "Auto Dice", "autoDice", false)

local machTab = win:CreateTab("Machines", "rbxassetid://126141499544212")

machTab:CreateSection("Station")
toggle(machTab, "Auto Daycare", "autoDaycare", false)
toggle(machTab, "Auto Flexible Flags", "autoFlags", false)
toggle(machTab, "Auto Secret Rooms", "autoSecretRooms", false)
toggle(machTab, "Auto Treehouse", "autoTreehouse", false)
toggle(machTab, "Auto Fuse", "autoFuse", false)
toggle(machTab, "Auto Cards", "autoCards", false)
toggle(machTab, "Auto Relics", "autoRelics", false)
toggle(machTab, "Auto Mail Claim", "autoMailClaim", false)

local optTab = win:CreateTab("Optimise", "rbxassetid://87867412432006")

optTab:CreateSection("Rendering")
toggle(optTab, "Reduce Breakable Effects", "optBreakables", false,
    "Strips particle emitters and trails from breakables. Restored on OFF.")
toggle(optTab, "Reduce Pet Effects", "optPets", false)
toggle(optTab, "Anti AFK", "antiAfk", false)

local servTab = win:CreateTab("Server", "rbxassetid://16093555964")

servTab:CreateSection("Hop")
toggle(servTab, "Auto Server Hop", "serverHop", false,
    "Hops when the server drops below the engine's player threshold.")
servTab:CreateSection("Pickers")
servTab:CreateParagraph({
    Title = "Pickers",
    Content = "The auto-consume workers only touch the items ticked in the engine's own panel. "
        .. "Open it here, tick what you own, then turn the worker on. Engine panel = Insert.",
})
servTab:CreateButton({
    Name = "Open Engine Panel",
    Callback = function()
        if not showEnginePanel(true) then
            lib:CreateNotification({ Title = "Pickers", Content = "Panel not built yet - give it a second." })
        end
    end,
})
servTab:CreateButton({
    Name = "Close Engine Panel",
    Callback = function()
        showEnginePanel(false)
    end,
})
servTab:CreateSection("Danger")
servTab:CreateButton({
    Name = "All Features Off",
    Callback = function()
        engine.AllOff()
        lib:CreateNotification({ Title = "Engine", Content = "All features off." })
    end,
})
servTab:CreateButton({
    Name = "Unload Everything",
    Callback = function()
        pcall(engine.Stop)
        pcall(lib.Destroy, lib)
    end,
})
servTab:CreateParagraph({
    Title = "Keys",
    Content = "RightControl toggles this window. Insert toggles the engine panel. X unloads.",
})

local status = lib:CreateQuest({
    Title = "Engine",
    Quest = "starting",
    Amount = 1,
    Progress = 0,
})

local statusTab = win:CreateTab("Status", "rbxassetid://12130070198")
local statusParagraph = statusTab:CreateParagraph({
    Title = "Engine",
    Content = "collecting...",
})

local function onCount(t)
    local n = 0
    for _, v in pairs(t) do
        if v then
            n = n + 1
        end
    end
    return n
end

task.spawn(function()
    while true do
        local ok, st = pcall(engine.GetStatus)
        if ok and type(st) == "table" then
            local on = onCount(st.enabled)
            local line = string.format("world %s | profile %s | %d feature(s) on",
                tostring(st.world), tostring(st.profile), on)
            if statusParagraph.Set then
                pcall(statusParagraph.Set, statusParagraph, { Title = "Engine", Content = line })
            end
            if status.Update then
                pcall(status.Update, status, { Quest = line, Amount = math.max(1, on), Progress = on })
            end
        end
        task.wait(3)
    end
end)

lib:CreateNotification({
    Title = "ZapHub | PS99",
    Content = "Loaded. RightControl window, Insert pickers, X unload.",
    Duration = 5,
})

return engine
