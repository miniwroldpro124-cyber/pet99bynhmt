local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "PS99 CLEAN must run on the client")

-- Engine modules are compiled with loadstring, so their _G is the real global
-- table while main.lua's own _G is the executor's sandboxed view. Publish to
-- both; main.lua only ever reads back what it published.
local _G = _G
local function hostEnv()
    if type(getgenv) == "function" then
        local ok, value = pcall(getgenv)
        if ok and type(value) == "table" then return value end
    end
    return nil
end
local env = hostEnv() or _G
-- Some executors hand back a readonly _G. A failed write must not take the
-- engine down: the chunk's return value is the real delivery path.
local function hostPut(target, key, value)
    pcall(function() target[key] = value end)
end
local function hostGet(target, key)
    local ok, value = pcall(function() return target[key] end)
    if ok then return value end
    return nil
end
local function publish()
    hostPut(env, "__PS99CLEAN", controller)
    hostPut(env, "__PS99CLEAN_CLEANUP", cleanup)
    if env ~= _G then
        hostPut(_G, "__PS99CLEAN", controller)
        hostPut(_G, "__PS99CLEAN_CLEANUP", cleanup)
    end
end
local function unpublish()
    if hostGet(env, "__PS99CLEAN_CLEANUP") == cleanup then
        hostPut(env, "__PS99CLEAN", nil)
        hostPut(env, "__PS99CLEAN_CLEANUP", nil)
    end
    if hostGet(_G, "__PS99CLEAN_CLEANUP") == cleanup then
        hostPut(_G, "__PS99CLEAN", nil)
        hostPut(_G, "__PS99CLEAN_CLEANUP", nil)
    end
end
if type(hostGet(env, "__PS99CLEAN_CLEANUP")) == "function" then
    local ok, err = pcall(hostGet(env, "__PS99CLEAN_CLEANUP"))
    if not ok then warn("[PS99 CLEAN] previous cleanup: " .. tostring(err)) end
end
if env ~= _G and type(hostGet(_G, "__PS99CLEAN_CLEANUP")) == "function" then
    local ok, err = pcall(hostGet(_G, "__PS99CLEAN_CLEANUP"))
    if not ok then warn("[PS99 CLEAN] previous cleanup: " .. tostring(err)) end
end

local CFG = {
    -- Finite high speed multiplier for instant 1-frame snap when attacking a
    -- breakable; idle/following pets stay at their normal speed multiplier.
    PetSpeedMult = 10000,
    PetAttackDwell = 0.45,
    PetInterval = 0.05,
    TapRate = 60,
    FarmTapRate = 90,
    TapRange = 220,
    MaxTapRate = 90,
    AuraRate = 60,
    AntiAfkCooldown = 60,
    TargetRescan = 0.12,
    BreakableScanCap = 1500,
    VacuumRate = 0.1,
    TeleInterval = 0.4,
    TeleBackoff = 1.2,
    BuyInterval = 4,
    BuyBackoff = 12,
    QuestInterval = 2,
    QuestBackoff = 25,
    EnsureBackoff = 45,
    QuestMaxRequests = 2,
    DoQuestInterval = 0.6,
    RankInterval = 4,
    RebirthInterval = 20,
    EggInterval = 0.6,
    EggRange = 250,
    EggMaxHatch = 100,
    WorldInterval = 1,
    WorldBackoff = 3,
    WorldAdvanceInterval = 2,
    -- Directory.Worlds defines World 1-4.
    WorldCount = 4,
    WorldAdvanceLimit = 4,
    OptimizeInterval = 2,
    OptimizeCap = 400,
    HopMaxPlayers = 4,
    HopInterval = 30,
    PetSlotInterval = 6,
    PetSlotBackoff = 12,
    PetSlotMax = 80,
    KeyInterval = 4,
    BagInterval = 3,
    FruitInterval = 4,
    PotionInterval = 2.5,
    PotionMinTier = 1,
    PotionMaxTier = 99,
    MailInterval = 15,
    FreeGiftInterval = 20,
    FreeGiftMax = 12,
    UltimateInterval = 1,
    SprinklerInterval = 10,
    DaycareInterval = 8,
    DaycareDuration = 21600,
    DaycareOnlineSpeedup = 3,
    DaycareSlotsFree = 10,
    FlagInterval = 60,
    SecretInterval = 10,
    TreehouseInterval = 30,
    DiceInterval = 20,
    CardInterval = 20,
    FruitQueueLimit = 20,
    PotionMaxConsume = 100,
    BagMaxOpen = 50,
    DiceMaxConsume = 25,
    FuseInterval = 60,
    FuseMinStacks = 6,
    FuseMinPets = 3,
    FuseMaxPets = 100,
    ProfileInterval = 2,
    SaveRefresh = 30,
    SnapshotTTL = 60,
    RemoteTimeout = 10,
    DiscoveryInterval = 1,
    TreeInterval = 60,
    HeapInterval = 25,
    HeapRetryInterval = 5,
    HeapCap = 2000,
    TreeCap = 1000,
    -- v2 / v3 / v8 Steph HUB
    FarmBurst = 10,
    PetRouteRate = 0.4,
    TeleCenterWait = 2,
    ChestFirst = true,
    TeleCenter = true,
    PetAll = true,
    HideEggFx = false,
    FlySpeed = 120,
    EggSlotInterval = 6,
    EggSlotBackoff = 12,
    UpgradeInterval = 8,
    ForeverPackInterval = 30,
    EnchantInterval = 5,
    TNTInterval = 10,
    TNTCrateInterval = 15,
    LowCpuFpsCap = 15,
    SelectedFlag = "Any Flag",
    SelectedMoveMode = "Teleport",
    TeleMode = "Instant", -- "Instant" | "Legit"
    SelectedKeepRung = 4,
    HuntMinTier = 0,
    TimeTrialChestTier = "Best Affordable",
    TimeTrialInterval = 0.12,
}

local enabled = {
    petSpeed = false, tap = false, legitTap = false, vacuum = false, farm = false, fastFarmBeta = false,
    zoneTele = false, zoneBuy = false, autoQuest = false, autoDoQuest = false,
    autoRank = false, autoRebirth = false, antiAfk = false, clickAura = false,
    autoEgg = false, auraVisual = false, optBreakables = false, optPets = false, worldTele = false,
    worldAdvance = false,
    hideEggFx = false, chestFirst = false, teleCenter = false, teleNearEgg = false, petAll = false,
    petBulkJoin = false, petTeleAfterAttack = false, drinkHighestTier = false,
    serverHop = false, autoBuyPetSlots = false, autoBuyEggSlots = false,
    autoForeverPack = false, autoBuyUpgrades = false, autoEquipEnchant = false,
    autoTNT = false, autoTNTCrate = false, whiteScreen = false, reduceCpuRam = false,
    jitter = false,
    autoKeys = false, autoGiftBags = false, autoFruits = false, autoPotions = false,
    autoFreeGifts = false, autoUltimate = false, autoSprinkler = false, autoDaycare = false, autoFlags = false,
    autoSecretRooms = false, autoTreehouse = false, autoFuse = false, autoCards = false,
    autoRelics = false, autoMailClaim = false, autoDice = false,
    autoSpinTickets = false, autoOpenChests = false,
    autoSeasonPass = false, autoZoneGifts = false,
    autoTimeTrial = false, autoTimeTrialChests = false, ttStopAtDailyLimit = false,
    noclip = false, fly = false, unlockGamepasses = false, removeGates = false,
    -- Pumpkin Tycoon Event
    optPumpkinTycoon = false,
    ptAutoTeleBestEgg = false,
    ptAutoTeleNearestFarm = false,
    ptAutoBuyEgg = false,
    ptAutoBuyButtons = false,
    ptAutoRebirth = false,
    ptAutoKeepPumpkins = false,
    ptAutoBreakPumpkins = false,
    ptAutoBuyMerchant = false,
    ptAutoPlantPumpkins = false,
    ptAutoBuyUpgrades = false,
    ptAutoBuyCocoa = false,
    ptAutoUseBoosts = false,
    ptAutoFlannelGifts = false,
    ptAutoHuntWild = false,
    ptAutoCatchWild = false,
    ptAutoBuyNets = false,
    ptAutoFightTurkey = false,
    ptAutoCatchRare = false,
}

-- Per-item selections. Every "auto X" worker above only touches the ids the
-- player ticked, matching how the game's own action menus gate consumption.
-- Picks are stored as id -> true; the workers rebuild lists from live Save
-- inventory each tick, so a pick that is not owned simply does nothing.
local picked = {
    zones = {},          -- zone id -> true (auto click / aura / teleport targeting)
    fruits = {},         -- Directory.Fruits id
    potions = {},        -- Directory.Potions / XPPotions id
    bags = {},           -- GiftBag_Open / Lootbox name
    flags = {},          -- FlexibleFlags_Consume name
    freeGifts = {},      -- numeric free gift Id
    dice = {},           -- Lucky Dice item id
    cards = {},          -- CardItem id
    keys = {},           -- KEY_PAIRS name
    eggs = {},           -- Egg id
    huges = {},          -- Huge / Titanic / Gargantuan pet id
    items = {},          -- Misc / All items id
    tickets = {},        -- Spinny Wheel / Raffle Ticket id
}
local function pickCount(store)
    local count = 0
    for _ in pairs(store) do count += 1 end
    return count
end
local function togglePick(store, id)
    if type(id) ~= "string" and type(id) ~= "number" then return false end
    if store[id] then store[id] = nil else store[id] = true end
    return true
end
local alive = true
local workers, requests, connections = {}, {}, {}
local remotes, modules = {}, {}
local zones, zoneNumbers, rebirths, ranks, questDirs, eggByNumber = {}, {}, {}, {}, {}, {}
local worldTarget = 1
-- State folded into tables: the main chunk must stay well under Luau's
-- 200-register limit or the chunk fails to compile at all.
local snap = {raw = nil, at = -math.huge, source = "waiting", cache = nil}
local stats = {pending = nil, remote = nil, connection = nil}
local nextAt = {
    heap = 0, save = 0, quest = {}, ensure = {}, doQuest = 0, coinJar = 0,
    egg = 0, worldTele = 0, petSlot = 0, eggSlot = 0, foreverPack = 0, upgrade = 0,
    enchant = 0, tnt = 0, tntCrate = 0, pt = 0,
    key = 0, bag = 0, mail = 0,
    freeGift = 0, ultimate = 0, sprinkler = 0, daycare = 0, flag = 0,
    secret = 0, relic = 0, treehouse = 0, fuse = 0, card = 0, dice = 0,
    freeGiftCursor = 1, tree = 0, tap = 0, tele = 0, buy = 0, rank = 0, rebirth = 0,
}
local notes = {
    pet = "off", tap = "off", betaFarm = "off", vacuum = "off", tele = "off", buy = "off",
    quest = "off", doQuest = "off", rank = "off", rebirth = "off", antiAfk = "off", egg = "off",
    world = "off", advance = "off", optimize = "off", hop = "off", petSlot = "off", eggSlot = "off",
    foreverPack = "off", upgrade = "off", enchant = "off", tnt = "off", tntCrate = "off",
    whiteScreen = "off", reduceCpu = "off", event = "off", timeTrial = "off",
    keys = "off", bags = "off", fruits = "off", potions = "off", freeGift = "off", ultimate = "off",
    sprinkler = "off", daycare = "off", flags = "off", secret = "off", relics = "off", treehouse = "off",
    fuse = "off", cards = "off", dice = "off", mailClaim = "off", cheat = "ready",
    heap = "idle; no startup scan", profile = "waiting for discovery",
}

local petState = {
    previous = setmetatable({}, {__mode = "k"}),
    records = setmetatable({}, {__mode = "k"}),
    teleportedTarget = setmetatable({}, {__mode = "k"}),
    assignedModel = setmetatable({}, {__mode = "k"}),
    assignedUid = setmetatable({}, {__mode = "k"}),
    joinedTarget = setmetatable({}, {__mode = "k"}),
    lastAttackAt = -math.huge,
    attackModel = nil,
    attackUid = nil,
    switchAt = 0,
}
local target = {}
local orbRecords = setmetatable({}, {__mode = "kv"})
-- record -> the _superMagnet it had before we forced it on (restore on OFF).
local orbOffsets = setmetatable({}, {__mode = "k"})
local orbState = {cursor = 1}
-- false marks "the record had no magnet flag before we set it" so the weak key
-- survives; a nil value would drop the entry and lose the restore.
local function magnetize(record)
    if orbOffsets[record] == nil then orbOffsets[record] = record._superMagnet or false end
    record._superMagnet = true
end
local assignedQuests = {}
local secretTried = {}
local pendingMail = nil
local auraPart
local optBreakableEffects = setmetatable({}, {__mode = "k"})
local optPetEffects = setmetatable({}, {__mode = "k"})
local syncWorkers, setEnabled, cleanup, updateToggles
local info = {}

local REMOTE_TYPES = {
    ["Get Stats"] = "RemoteFunction",
    ["New Stats"] = "RemoteEvent",
    ["Breakables_PlayerDealDamage"] = "UnreliableRemoteEvent",
    ["Breakables_JoinPetBulk"] = "RemoteEvent",
    ["Breakables_RenderWorld"] = "RemoteEvent",
    ["CQ_Route"] = "RemoteEvent",
    ["CQ_Pin"] = "RemoteEvent",
    ["Sprinklers: Consume"] = "RemoteFunction",
    ["Orbs: Collect"] = "RemoteEvent",
    ["Teleports_RequestTeleport"] = "RemoteFunction",
    ["Teleports_RequestInstanceTeleport"] = "RemoteFunction",
    ["Instancing_PlayerEnterInstance"] = "RemoteFunction",
    ["Instancing_PlayerLeaveInstance"] = "RemoteEvent",
    ["TimeTrials_OpenChest"] = "RemoteFunction",
    ["TimeTrial_Multipliers_Request"] = "RemoteFunction",
    ["RequestStreaming"] = "RemoteEvent",
    ["World1Teleport"] = "RemoteFunction",
    ["World2Teleport"] = "RemoteFunction",
    ["World3Teleport"] = "RemoteFunction",
    ["World4Teleport"] = "RemoteFunction",
    ["Zones_RequestPurchase"] = "RemoteFunction",
    ["NPC Quests: Ensure"] = "RemoteFunction",
    ["NPC Quests: Redeem"] = "RemoteFunction",
    ["Daily Quests: Select Card"] = "RemoteFunction",
    ["Daily Quests: Reroll"] = "RemoteFunction",
    ["Ranks_ClaimAll"] = "RemoteEvent",
    ["Ranks_ClaimReward"] = "RemoteEvent",
    ["Rebirth_Request"] = "RemoteFunction",
    ["Eggs_RequestPurchase"] = "RemoteFunction",
    ["CustomEggs_Hatch"] = "RemoteFunction",
    ["EquipSlotsMachine_RequestPurchase"] = "RemoteFunction",
    ["CrystalKey_Combine"] = "RemoteFunction",
    ["TechKey_Combine"] = "RemoteFunction",
    ["VoidKey_Combine"] = "RemoteFunction",
    ["FantasyKey_Combine"] = "RemoteFunction",
    ["MVPKey_Combine"] = "RemoteFunction",
    ["SecretKey_Combine"] = "RemoteFunction",
    ["TreasureHideout_Combine"] = "RemoteFunction",
    ["TN_Bind"] = "RemoteFunction",
    ["MW_Reduce"] = "RemoteFunction",
    ["CrystalKey_Unlock"] = "RemoteFunction",
    ["TechKey_Unlock"] = "RemoteFunction",
    ["VoidKey_Unlock"] = "RemoteFunction",
    ["FantasyKey_Unlock"] = "RemoteFunction",
    ["SecretKey_Unlock"] = "RemoteFunction",
    ["PrisonKey_Combine"] = "RemoteFunction",
    ["PrisonKey_Use"] = "RemoteFunction",
    ["Eggs_RequestUnlock"] = "RemoteFunction",
    ["LuckyDice_Consume_V2"] = "RemoteFunction",
    ["LuckyDice_ConsumeMega_V2"] = "RemoteFunction",
    ["FireDice_Consume_V2"] = "RemoteFunction",
    ["LuckyDice_Craft_V2"] = "RemoteFunction",
    ["LuckyDice_Get_V2"] = "RemoteFunction",
    ["Ultimates: Equip"] = "RemoteFunction",
    ["Ultimates: Unequip"] = "RemoteEvent",
    ["GiftBag_Open"] = "RemoteFunction",
    ["Fruits: Consume"] = "RemoteEvent",
    ["Potions: Consume"] = "RemoteEvent",
    ["XPPotions: Consume"] = "RemoteEvent",
    ["Redeem Free Gift"] = "RemoteFunction",
    ["Ultimates: Activate"] = "RemoteFunction",
    ["Daycare: Enroll"] = "RemoteFunction",
    ["Daycare: Claim"] = "RemoteFunction",
    ["FlexibleFlags_Consume"] = "RemoteFunction",
    ["SecretRoom_Unlock"] = "RemoteFunction",
    ["TreehouseMerchant_Purchase"] = "RemoteFunction",
    ["FuseMachine_Activate"] = "RemoteFunction",
    ["GoldMachine_Activate"] = "RemoteFunction",
    ["RainbowMachine_Activate"] = "RemoteFunction",
    ["UpgradePotionsMachine_Activate"] = "RemoteFunction",
    ["UpgradeEnchantsMachine_Activate"] = "RemoteFunction",
    ["UpgradeFruitsMachine_Activate"] = "RemoteFunction",
    ["VendingMachines_Purchase"] = "RemoteFunction",
    ["Merchant_RequestPurchase"] = "RemoteFunction",
    ["Upgrades_Purchase"] = "RemoteFunction",
    ["CoinJar_Spawn"] = "RemoteFunction",
    ["Comet_Spawn"] = "RemoteFunction",
    ["Pinata_Spawn"] = "RemoteFunction",
    ["LuckyBlock_Spawn"] = "RemoteFunction",
    ["CardCombinationMachine_ActivateBulk"] = "RemoteFunction",
    ["Relics_Request"] = "RemoteFunction",
    ["Relic_Found"] = "RemoteFunction",
    ["YS_Load"] = "RemoteFunction",
    ["RD_Ingest"] = "RemoteFunction",
    ["KX_Release"] = "RemoteFunction",
    ["Lootables_Open"] = "RemoteFunction",
    ["Spinny Wheel: Request Spin"] = "RemoteFunction",
    ["Enchants_Equip"] = "RemoteEvent",
    ["Enchants_ClearSlot"] = "RemoteEvent",
    ["EggHatchSlotsMachine_RequestPurchase"] = "RemoteFunction",
    ["ForeverPacks: Claim Free"] = "RemoteFunction",
    ["TNT_Consume"] = "RemoteFunction",
    ["TNT_Crate_Consume"] = "RemoteFunction",
    ["Consumables_Consume"] = "RemoteFunction",
    ["Plots_Invoke"] = "RemoteFunction",
    ["Instancing_Enter"] = "RemoteFunction",
    ["Instancing_Leave"] = "RemoteFunction",
}

local function stage(message)
    if not alive then return end
    print("[Steph HUB] " .. tostring(message))
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function getRemote(name)
    local expected = REMOTE_TYPES[name]
    local cached = remotes[name]
    if cached and cached.Name == name and cached:IsDescendantOf(RS) and cached:IsA(expected) then return cached end
    local network = RS:FindFirstChild("Network")
    if network then
        for _, child in ipairs(network:GetChildren()) do
            if child.Name == name and child:IsA(expected) then remotes[name] = child; return child end
        end
    end
    local found = remotes[name]
    if found and found:IsDescendantOf(RS) and found:IsA(expected) then return found end
    return nil
end

-- The current game hashes its Network remote names, so a raw "Get Stats"/etc.
-- lookup by name can hit a decoy that returns nil. The game's own Network module
-- resolves the real (hashed) remote internally, so prefer it whenever discovered.
local function fire(name, ...)
    if not alive then return false, "stopped" end
    local net = modules.network
    if net then
        local kind = REMOTE_TYPES[name] == "UnreliableRemoteEvent" and "UnreliableFire" or "Fire"
        local fn = net[kind]
        if type(fn) == "function" then
            local ok, err = pcall(fn, name, ...)
            return ok, ok and "sent" or tostring(err)
        end
    end
    local remote = getRemote(name)
    if not remote then return false, "missing " .. name end
    local ok, err = pcall(remote.FireServer, remote, ...)
    return ok, ok and "sent" or tostring(err)
end

local workerContext = {}
local function invokeWithCompletion(name, completion, ...)
    if not alive then return nil, "stopped" end
    if requests[name] then return nil, "previous request still pending" end
    local remote = getRemote(name)
    local net = modules.network
    local hasNet = net and type(net.Invoke) == "function"
    if not remote and not hasNet then return nil, "missing " .. name end
    local args = table.pack(...)
    local request = {started = os.clock(), done = false, sent = false, owner = workerContext[coroutine.running()]}
    requests[name] = request
    request.thread = task.defer(function()
        if not alive or (request.owner and not request.owner.running) then
            if requests[name] == request then requests[name] = nil end
            request.result, request.done = {false, "cancelled"}, true
            return
        end
        request.sent = true
        local result
        local liveNet = modules.network
        if liveNet and type(liveNet.Invoke) == "function" then
            result = table.pack(pcall(liveNet.Invoke, name, table.unpack(args, 1, args.n)))
        else
            local liveRemote = getRemote(name)
            if not liveRemote then
                result = {false, "missing " .. name}
            else
                result = table.pack(pcall(liveRemote.InvokeServer, liveRemote, table.unpack(args, 1, args.n)))
            end
        end
        if not alive then return end
        request.result, request.done = result, true
        if requests[name] == request then requests[name] = nil end
        if completion and (not request.owner or request.owner.running) then completion(result) end
    end)
    while alive and not request.done and os.clock() - request.started < CFG.RemoteTimeout do
        task.wait(0.05)
    end
    if not alive then return nil, "stopped" end
    -- A timed-out request stays single-flight until its actual response arrives.
    if not request.done then return nil, "timeout; request still pending" end
    local result = request.result
    if not result[1] then return nil, tostring(result[2]) end
    if result.n < 2 or result[2] == nil then return nil, tostring(result[3] or "empty response") end
    return table.unpack(result, 2, result.n)
end

local function invoke(name, ...)
    return invokeWithCompletion(name, nil, ...)
end

local function looksLikeSave(value)
    return type(value) == "table"
        and type(rawget(value, "UnlockedZones")) == "table"
        and type(rawget(value, "Rank")) == "number"
        and type(rawget(value, "Rebirths")) == "number"
end

CFG.BootstrapDone = false
function CFG.BootstrapModules()
    if CFG.BootstrapDone then return end
    CFG.BootstrapDone = true
    local lib = RS:FindFirstChild("Library")
    local cli = lib and lib:FindFirstChild("Client")
    if not cli then return end
    local function tryReq(slot, name)
        if modules[slot] then return end
        local child = cli:FindFirstChild(name)
        if not child then return end
        local ok, mod = pcall(require, child)
        if ok and type(mod) == "table" then
            modules[slot] = mod
        end
    end
    tryReq("save", "Save")
    tryReq("network", "Network")
    tryReq("pet", "PlayerPet")
    tryReq("breakables", "BreakableCmds")
    tryReq("breakableFrontend", "BreakableFrontend")
    tryReq("customEggs", "CustomEggsCmds")
    tryReq("gamepasses", "Gamepasses")
    tryReq("ultimates", "UltimateCmds")
    tryReq("sprinklers", "SprinklerCmds")
    tryReq("flags", "FlexibleFlagCmds")
    tryReq("enchants", "EnchantCmds")
    tryReq("mastery", "MasteryCmds")
    tryReq("foreverPack", "ForeverPackCmds")
    tryReq("upgrades", "UpgradeCmds")
    tryReq("zoneCmds", "ZoneCmds")
    tryReq("instancing", "InstancingCmds")
    tryReq("mapCmds", "MapCmds")
    tryReq("pumpkinTycoon", "PumpkinTycoonCmds")
end

local function getSave()
    if not modules.save and not CFG.BootstrapDone then
        CFG.BootstrapModules()
    end
    if snap.cache then
        local ok, value = pcall(function() return rawget(snap.cache, LocalPlayer) end)
        if ok and looksLikeSave(value) then
            snap.source = "live"
            return value
        end
        if snap.source == "live" then snap.raw = nil end
    end
    if modules.save then
        local ok, value = pcall(modules.save.Get, LocalPlayer)
        if ok and looksLikeSave(value) then
            snap.source = "live"
            return value
        end
        if snap.source == "live" then snap.raw = nil end
    end
    if snap.raw and os.clock() - snap.at <= CFG.SnapshotTTL then
        snap.source = "snapshot"
        return snap.raw
    end
    snap.source = "waiting"
    return nil
end

local function bindStats()
    local signal
    local net = modules.network
    if net and type(net.Fired) == "function" then
        local ok, fired = pcall(net.Fired, "New Stats")
        if ok and fired then signal = fired end
    end
    if not signal then
        local remote = getRemote("New Stats")
        signal = remote and remote.OnClientEvent or nil
    end
    if signal == stats.remote then return end
    if stats.connection then stats.connection:Disconnect() end
    stats.connection, stats.remote = nil, signal
    if not signal then return end
    stats.connection = signal:Connect(function(changes, who)
        if not alive or (who ~= nil and who ~= LocalPlayer) or type(changes) ~= "table" then return end
        for _, pair in ipairs(changes) do
            if type(pair) == "table" and type(pair[1]) == "string" then
                if snap.raw then snap.raw[pair[1]] = pair[2] end
                if stats.pending then stats.pending[pair[1]] = {pair[1], pair[2]} end
            end
        end
    end)
end

local function profileTick()
    bindStats()
    if getSave() and snap.source == "live" then return end
    local now = os.clock()
    if now < nextAt.save or requests["Get Stats"] then return end
    local network = modules.network
    local remote = getRemote("Get Stats")
    if not network and not remote then
        -- No profile source yet; discovery may still find one, so retry soon
        -- instead of locking out for the full refresh interval.
        nextAt.save = now + CFG.ProfileInterval
        notes.profile = modules.save and "waiting for live save" or ("waiting for Save module; " .. notes.heap)
        return
    end
    nextAt.save = now + CFG.SaveRefresh
    local changes = {}
    stats.pending = changes
    local function adopt(ok, value)
        if stats.pending == changes then stats.pending = nil end
        if ok and looksLikeSave(value) then
            snap.raw = table.clone(value)
            for _, pair in pairs(changes) do snap.raw[pair[1]] = pair[2] end
            snap.at = os.clock()
            notes.profile = "remote snapshot"
        elseif not snap.raw then
            -- This build's hashed "Get Stats" RemoteFunction answers nil; the
            -- Save module cache is the real source, so stay quiet and keep
            -- discovery running instead of printing every poll.
            notes.profile = "Get Stats returned nothing; waiting for Save module"
        end
    end
    local _, err = invokeWithCompletion("Get Stats", function(result) adopt(result[1], result[2]) end, LocalPlayer)
    if not alive then return end
    if not requests["Get Stats"] and stats.pending == changes then stats.pending = nil end
    if err and not snap.raw then notes.profile = "Get Stats: " .. tostring(err) end
end

local function registerZone(number, id, definition)
    if type(number) ~= "number" or type(id) ~= "string" or number < 1 then return end
    local existing = zones[number]
    if existing and existing.id ~= id then return end
    zones[number] = {id = id, definition = definition or (existing and existing.definition)}
    zoneNumbers[id] = number
end

-- Full zone index, read from the live directory (279 zones, no gaps, no
-- duplicate names). Registered at load so teleport, best-zone and world logic
-- work before the heap ever returns a zone module; the heap scan later swaps
-- each entry's definition for the live module (gates, costs, attributes).
CFG.ZoneIndex = {
    [1] = {
        "Spawn", "Colorful Forest", "Castle", "Green Forest", "Autumn", "Cherry Blossom",
        "Farm", "Backyard", "Misty Falls", "Mine", "Crystal Caverns", "Dead Forest",
        "Dark Forest", "Mushroom Field", "Enchanted Forest", "Crimson Forest", "Jungle", "Jungle Temple",
        "Oasis", "Beach", "Coral Reef", "Shipwreck", "Atlantis", "Palm Beach",
        "Tiki", "Pirate Cove", "Pirate Tavern", "Shanty Town", "Desert Village", "Fossil Digsite",
        "Desert Pyramids", "Red Desert", "Wild West", "Grand Canyons", "Safari", "Mountains",
        "Snow Village", "Icy Peaks", "Ice Rink", "Ski Town", "Hot Springs", "Fire and Ice",
        "Volcano", "Obsidian Cave", "Lava Forest", "Underworld", "Underworld Bridge", "Underworld Castle",
        "Metal Dojo", "Fire Dojo", "Samurai Village", "Bamboo Forest", "Zen Garden", "Flower Field",
        "Fairytale Meadows", "Fairytale Castle", "Royal Kingdom", "Fairy Castle", "Cozy Village", "Rainbow River",
        "Colorful Mines", "Colorful Mountains", "Frost Mountains", "Ice Sculptures", "Snowman Town", "Ice Castle",
        "Polar Express", "Firefly Cold Forest", "Golden Road", "No Path Forest", "Ancient Ruins", "Runic Altar",
        "Wizard Tower", "Witch Marsh", "Haunted Forest", "Haunted Graveyard", "Haunted Mansion", "Dungeon Entrance",
        "Dungeon", "Treasure Dungeon", "Empyrean Dungeon", "Mythic Dungeon", "Cotton Candy Forest", "Gummy Forest",
        "Chocolate Waterfall", "Sweets", "Toys and Blocks", "Carnival", "Theme Park", "Clouds",
        "Cloud Garden", "Cloud Forest", "Cloud Houses", "Cloud Palace", "Heaven Gates", "Heaven",
        "Heaven Golden Castle", "Colorful Clouds", "Rainbow Road",
    },
    [2] = {
        "Tech Spawn", "Futuristic City", "Hologram Forest", "Robot Farm", "Bit Stream", "Neon Mine",
        "Mushroom Lab", "Virtual Garden", "Data Tree Farm", "Tech Jungle", "Lava Jungle", "Oasis Ruins",
        "Future Beach", "Tech Reef", "Robo Pirates", "Cyber Cove", "Runic Desert", "Charged Pyramids",
        "Fallout Desert", "Tech Wild West", "Cuboid Canyon", "Frozen Mountains", "Frostbyte Forest", "Forcefield Mine",
        "Cyber Base Camp", "Frosted City", "Cracked Iceberg", "Melted River", "Nexus", "Secure Coast",
        "Nuclear Forest", "Radiation Mine", "Exploded Reactor", "Spaceship Dock", "Rocky Planet", "Lunar Planet",
        "Mars Planet", "Saturn Planet", "Comet Planet", "Galaxy Port", "Electric Garden", "Mutated Forest",
        "Neon City", "Arcade Town", "Robot Factory", "Egg Incubator", "Hi-Tech Hive", "Spore Garden",
        "UFO Forest", "Alien Lab", "Alien Mothership", "Space Forge", "Space Factory", "Space Junkyard",
        "Steampunk Alley", "Steampunk Town", "Steampunk Clockwork", "Steampunk Airship", "Circuit Board", "Mothership Circuit Board",
        "Wizard Ruins", "Wizard Forest", "Wizard Tech Forest", "Wizard Tech Tower", "Wizard Dungeon", "Cyberpunk Undercity",
        "Cyberpunk Industrial", "Cyberpunk City", "Cyberpunk Road", "Tech Ninja Kyoto", "Tech Samurai", "Tech Ninja Village",
        "Tech Ninja City", "Dominus Dungeon", "Dominus Vault", "Dominus Lair", "Holographic Powerplant", "Holographic City",
        "Holographic Forest", "Holographic Mine", "Dark Tech Cove", "Dark Tech Ruins", "Dark Tech Castle", "Dark Tech Dungeon",
        "Dark Tech Forest", "Hacker Powerplant", "Hacker Compound", "Hacker Base", "Hacker Error", "Glitch Forest",
        "Glitch City", "Glitch Skyscrapers", "Glitch Town", "Glitch Quantum", "Quantum Forest", "Quantum Space Base",
        "Quantum Galaxy", "Void Atomic", "Void Fracture", "Void Spiral",
    },
    [3] = {
        "Void Spawn", "Prison Block", "Prison Cafeteria", "Prison Yard", "Prison HQ", "Beach Island",
        "Ocean Island", "Tiki Island", "Jungle Island", "Volcano Island", "Hacker Matrix", "Hacker Fortress",
        "Hacker Cave", "Hacker Lab", "Hacker Mainframe", "Dirt Village", "Stone Forts", "Silver City",
        "Golden Metropolis", "Diamond Mega City", "Kawaii Tokyo", "Kawaii Village", "Kawaii Grove", "Kawaii Dreamland",
        "Kawaii Temple", "Grassy Plains", "Rocky Ridge", "Crystal Lake", "Electro Forge", "Elemental Realm",
        "Elysium Fields", "Ocean Paradise", "Lost Library", "Nebula Forest", "Aether Colosseum", "Doodle Meadow",
        "Doodle Safari", "Doodle Fairyland", "Doodle Cave", "Doodle Oasis",
    },
    [4] = {
        "Fantasy Spawn", "Flora Falls", "Lantern Forest", "Honeycomb Hollow", "Fairy Glade", "Windmill Point",
        "Radiant Runestones", "Fogbound Forest", "Rune Graveyard", "Halo Spires", "Twilight Grove", "Moonlight Ridge",
        "Starroot Highlands", "Aether Archways", "Celestial Watchtower", "Whispering Hills", "Runestone Bluff", "Totem Trail",
        "Wyrmwatch Ridge", "Highcliff Sanctuary", "Ember Cliffs", "Charred Canyon", "Ember Chasm", "Molten Nest",
        "Obsidian Spire", "Crystalfall Hollow", "Glimmer Grottos", "Mirror Tome Path", "Scribes Terrace", "Archivists Tower",
        "Mystmire Bloom", "Lotus Fenlight", "Faerie Hex Glade", "Bloomcourt Terrace", "Toadstool Throne", "Bloomfade Crossing",
        "Duskwillow Path", "Wraithcap Grove", "Veilroot Depths", "Hollow Veil Castle",
    },
}
CFG.WorldFirst, CFG.WorldLast = {}, {}
for world, names in ipairs(CFG.ZoneIndex) do
    CFG.WorldFirst[world] = (CFG.WorldLast[world - 1] or 0) + 1
    CFG.WorldLast[world] = CFG.WorldFirst[world] + #names - 1
end
for world, names in ipairs(CFG.ZoneIndex) do
    local first = CFG.WorldFirst[world]
    for index, name in ipairs(names) do
        local number = first + index - 1
        registerZone(number, name, {WorldNumber = world, ZoneNumber = number, ZoneName = name})
    end
end

CFG.EggIndex = {
    "Cracked Egg", "Spotted Egg", "Paw Egg", "Grass Egg", "Wood Egg", "Pumpkin Egg", "Hive Egg", "Acorn Egg", "Blossom Egg", "Corgi Egg",
    "Cat Egg", "Dog Egg", "Dragon Egg", "Rock Egg", "Geode Egg", "Hut Egg", "Grave Egg", "Spike Egg", "Sprout Egg", "Mushroom Egg",
    "Spirit Egg", "Crimson Egg", "Overgrown Egg", "Mossy Egg", "Jungle Egg", "Sandcastle Egg", "Palm Tree Egg", "Beach Ball Egg", "Coral Egg", "Anchor Egg",
    "Atlantis Egg", "Tropical Egg", "Beach Egg", "Coconut Egg", "Tiki Egg", "Sand Bucket Egg", "Sunny Egg", "Pirate Egg", "Ship Egg", "Zebra Egg",
    "Cheetah Egg", "Cactus Egg", "Fossil Egg", "Egyptian Egg", "Sandstone Egg", "Cowboy Egg", "Canyon Egg", "Hyena Egg", "Melted Egg", "Snow Egg",
    "Icicle Egg", "Snowman Egg", "Yeti Egg", "Ice Egg", "Thawed Egg", "Magma Egg", "Obsidian Egg", "Volcano Egg", "Bone Egg", "Tentacle Egg",
    "Hell Egg", "Metal Egg", "Sakura Egg", "Ninja Egg", "Lantern Egg", "Bonsai Egg", "Garden Egg", "Pixie Egg", "Pedal Egg", "Crowned Egg",
    "Royal Egg", "Dandelion Egg", "Colorful Egg", "Colorful Geode Egg", "Colorful Mosaic Egg", "Frosted Geode Egg", "Ice Sculpture Egg", "Hot Cocoa Egg", "Ice Castle Egg Egg", "Teddy Egg",
    "Firefly Egg", "Golden Brick Egg", "Cobblestone Egg", "Ruins Egg", "Runic Egg", "Wizard Egg", "Witch Egg", "Eerie Egg", "Abyssal Egg", "Cursed Egg",
    "Dungeon Egg", "Shadow Egg", "Treasure Egg", "Empyrean Egg", "Mythic Egg", "Cotton Candy Egg", "Gummy Egg", "Ice Cream Egg", "Sweets Egg", "Toy Egg",
    "Carnival Egg", "Hot Air Balloon Egg", "Cloud Egg", "Cloud Garden Egg", "Cloud Forest Egg", "Cloud House Egg", "Cloud Castle Egg", "Angel Egg", "Heaven Egg", "Heaven Castle Egg",
    "Colorful Cloud Egg", "Rainbow Egg", "Tech Ciruit Egg", "Tech City Egg", "Tech Forest Egg", "Tech Silo Egg", "Tech Data Egg", "Tech Cuboid Egg", "Tech Sprout Egg", "Tech Tree Egg",
    "Tech Incubator Egg", "Tech Overgrown Egg", "Tech Magma Egg", "Tech Oasis Egg", "Tech Palm Egg", "Tech Coral Egg", "Tech Ship Egg", "Tech Ruins Egg", "Tech Dusty Egg", "Tech Luminati Egg",
    "Tech Cactus Egg", "Tech Cowboy Egg", "Tech Canyon Egg", "Tech Snow Egg", "Tech Mossy Egg", "Tech Ice Crystal Egg", "Tech Flurry Egg", "Tech Ice Circuit Egg", "Tech Glacier Egg", "Tech Melted Egg Egg",
    "Tech Nexus Egg", "Nuclear Crack Egg", "Nuclear Forest Egg", "Nuclear Mine Egg", "Nuclear Egg", "Tech Rocket Egg", "Tech Planets Egg", "Tech Moon Egg", "Tech Mars Egg", "Tech Saturn Egg",
    "Tech Comet Egg", "Tech Galaxy Egg", "Electric Garden Egg", "Electric City Egg", "Electric Forest Egg", "Electric Egg", "Tech Factory Egg", "Tech Robot Egg", "Tech Hive Egg", "Alien Garden Egg",
    "Alien Forest Egg", "Alien Lab Egg", "Alien UFO Egg", "Space Forge Egg", "Space Factory Egg", "Space Junkyard Egg", "Steampunk Gears Egg", "Steampunk Lantern Egg", "Steampunk Clockwork Egg", "Steampunk Airship Egg",
    "Motherboard Egg", "Aura Egg", "Wizard Ruins Egg", "Wizard Temple Egg", "Wizard Forest Egg", "Wizard Tower Egg", "Wizard Dungeon Egg", "Cyberpunk Undercity Egg", "Cyberpunk Industrial Egg", "Cyberpunk City Egg",
    "Cyberpunk Road Egg", "Tech Kyoto Egg", "Tech Samurai Egg", "Tech Dojo Egg", "Tech Sakura Egg", "Dominus Rex Egg", "Dominus Frigidus Egg", "Dominus Infernus Egg", "Holographic Pipes Egg", "Holographic Egg",
    "Holographic Tree Egg", "Holographic Crystal Egg", "Dark Tech Stone Egg", "Dark Tech Relic Egg", "Dark Tech Castle Egg", "Dark Tech Brick Egg", "Dark Tech Spike Egg", "Hacker Metal Egg", "Hacker Gear Egg", "Hacker Matrix Egg",
    "Hacker Error Egg", "Glitch Tree Egg", "Glitch Green Egg", "Glitch Aqua Egg", "Glitch Cyan Egg", "Quantum Egg", "Quantum Leafy Egg", "Quantum Space Egg", "Quantum Galaxy Egg", "Void Crystal Egg",
    "Void Fracture Egg", "Void Spiral Egg", "Rusty Egg", "Striped Egg", "Cinderblocks Egg", "Lootbag Egg", "Summer Beach Egg", "Summer Floatie Egg", "Summer Melon Egg", "Summer Beachball Egg",
    "Summer Sun Egg", "Hacker Circuit Egg", "Hacker Wireframe Egg", "Hacker Crystal Egg", "Hacker Electric Egg", "Hacker Secure Egg", "Growing Egg", "Sturdy Egg", "Established Egg", "Elegant Egg",
    "Luxe Egg", "Sakura Blossom Egg", "Dream Egg", "Moonlight Egg", "Strawberry Egg", "Kawaii Egg", "Grass Type Egg", "Rock Type Egg", "Water Type Egg", "Electric Type Egg",
    "Fire Type Egg", "Elysium Egg", "Paradise Egg", "Lost Library Egg", "Nebula Egg", "Colosseum Egg", "Doodle Flower Egg", "Doodle Safari Egg", "Doodle Fairy Egg", "Doodle Gem Egg",
    "Doodle Tropical Egg", "Fantasy Egg", "Flora Egg", "Firefly Forest Egg", "Honeycomb Egg", "Fairy Mushroom Egg", "Fantasy Meadow Egg", "Radiant Runestones Egg", "Fogbound Forest Egg", "Rune Graveyard Egg",
    "Halo Spires Egg", "Twilight Grove Egg", "Moonlight Ridge Egg", "Starroot Oak Egg", "Aether Egg", "Crescent Moon Egg", "Whispering Hills Egg", "Runestone Bluff Egg", "Totem Trail Egg", "Wyrmwatch Ridge Egg",
    "Highcliff Sanctuary Egg", "Ember Cliffs Egg", "Charred Canyon Egg", "Ember Chasm Egg", "Molten Nest Egg", "Obsidian Spire Egg", "Crystalfall Hollow Egg", "Glimmer Grottos Egg", "Mirror Tome Path Egg", "Scribes Terrace Egg",
    "Archivists Tower Egg", "Mystmire Bloom Egg", "Lotus Fenlight Egg", "Faerie Hex Glade Egg", "Bloomcourt Terrace Egg", "Toadstool Throne Egg", "Bloomfade Egg", "Duskwillow Egg", "Wraithcap Egg", "Veilroot Egg",
    "Hollow Egg",
}
for index, name in ipairs(CFG.EggIndex) do
    eggByNumber[index] = name
end

local heapObjects, heapCursor
local heapStarted = -math.huge
local orbBackfillNeeded, heapBackfillsOrbs = false, false
-- getgc's snap.raw table is usually writable, but a read-only one would abort
-- the whole scan, so clearing entries is probed once and dropped if refused.
local heapState = {clear = true, sources = nil, tried = 0}
local function releaseHeap()
    if heapObjects then nextAt.heap = math.min(nextAt.heap, heapStarted + CFG.HeapRetryInterval) end
    heapObjects, heapCursor, heapBackfillsOrbs, heapState.sources = nil, nil, false, nil
end

-- Candidate tables come from whichever executor scan APIs exist, in order of
-- cost. Module return values are only reachable through a GC walk; the module
-- cache APIs are kept as a fallback for executors without getgc.
local function nextSource()
    heapState.sources = heapState.sources or {
        function() local gc = getgc or env.getgc; return type(gc) == "function" and gc(true) or nil end,
        function() local gc = getgc or env.getgc; return type(gc) == "function" and gc(false) or nil end,
        function() local reg = getreg or env.getreg; return type(reg) == "function" and reg() or nil end,
    }
    local known = type(getgc or env.getgc) == "function" or type(getreg or env.getreg) == "function"
    -- The working maker stays first so later scans do not re-probe the others.
    for index = 1, #heapState.sources do
        local ok, objects = pcall(heapState.sources[index])
        if ok and type(objects) == "table" and next(objects) ~= nil then
            if index > 1 then
                local maker = table.remove(heapState.sources, index)
                table.insert(heapState.sources, 1, maker)
            end
            return objects
        end
    end
    return nil, known
end

local function inspectObject(object)
    if type(rawget(object, "Get")) == "function"
        and type(rawget(object, "GetSaves")) == "function"
        and (type(rawget(object, "GetStatChangedSignal")) == "function"
            or type(rawget(object, "ProcessManualChange")) == "function"
            or type(rawget(object, "FetchPlayer")) == "function"
            or rawget(object, "LoadedStats") ~= nil
            or rawget(object, "StatsChanged") ~= nil) then
        modules.save = object
    end
    -- The real Network module also exposes the unreliable pair and the
    -- observer setter; requiring them keeps a decoy table out.
    if type(rawget(object, "Invoke")) == "function" and type(rawget(object, "Fired")) == "function"
        and type(rawget(object, "Fire")) == "function" and type(rawget(object, "Invoked")) == "function"
        and type(rawget(object, "UnreliableFire")) == "function"
        and type(rawget(object, "UnreliableFired")) == "function"
        and type(rawget(object, "_SetSendObserver")) == "function" then
        modules.network = object
    end
    -- The Save module's live cache is a table keyed by Player -> save. Reading
    -- it directly needs no function signature and is always current.
    if looksLikeSave(rawget(object, LocalPlayer)) then snap.cache = object end
    if type(rawget(object, "CalculateSpeedMultiplier")) == "function"
        and type(rawget(object, "GetByPlayer")) == "function"
        and type(rawget(object, "GetByItemUID")) == "function" then
        modules.pet = object
    end
    -- PlayerPet instances also carry the module through their metatable index,
    -- so a pet found on the heap is enough to reach CalculateSpeedMultiplier
    -- even when the module table itself was never in the returned snap.raw.
    if rawget(object, "euid") ~= nil and rawget(object, "owner") ~= nil
        and rawget(object, "cpet") ~= nil and rawget(object, "destroyed") ~= nil then
        petState.records[object] = true
        local class = getmetatable(object)
        class = type(class) == "table" and rawget(class, "__index")
        if type(class) == "table" and type(rawget(class, "CalculateSpeedMultiplier")) == "function" then
            modules.pet = class
        end
    end
    if type(rawget(object, "new")) == "function" and type(rawget(object, "Combine")) == "function"
        and type(rawget(object, "Collect")) == "function" and type(rawget(object, "ParkSpent")) == "function" then
        modules.orb = object
    end
    if type(rawget(object, "Owns")) == "function" and type(rawget(object, "Active")) == "function" then
        modules.gamepasses = object
    end
    if type(rawget(object, "GetEquippedItem")) == "function"
        and type(rawget(object, "GetChargePercentage")) == "function"
        and type(rawget(object, "IsCharged")) == "function"
        and type(rawget(object, "Activate")) == "function" then
        modules.ultimates = object
    end
    -- BreakableCmds is a frozen table of forwarded BreakableFrontend calls. Its
    -- zone index knows each breakable's dir (NoTapping, ManualDamage), which no
    -- attribute on the model carries, so it beats walking the workspace tree.
    if type(rawget(object, "AllByZoneAndClass")) == "function"
        and type(rawget(object, "AllByInstanceAndClass")) == "function"
        and type(rawget(object, "GetAutoTapTarget")) == "function"
        and type(rawget(object, "DamageDealt")) == "function"
        and type(rawget(object, "Get")) == "function" then
        modules.breakables = object
    end
    local part = rawget(object, "_part")
    if typeof(part) == "Instance" and type(rawget(object, "_combinedIds")) == "table"
        and type(rawget(object, "_destroyed")) == "boolean" then
        orbRecords[part] = object
        if enabled.vacuum or enabled.farm then magnetize(object) end
    end
    local id = rawget(object, "_id")
    if type(id) == "string" then
        if type(rawget(object, "ZoneNumber")) == "number"
            and type(rawget(object, "WorldNumber")) == "number"
            and type(rawget(object, "ZoneName")) == "string" then
            registerZone(rawget(object, "ZoneNumber"), id, object)
        elseif type(rawget(object, "RebirthNumber")) == "number"
            and type(rawget(object, "ZoneNumberRequired")) == "number" then
            rebirths[rawget(object, "RebirthNumber")] = object
        elseif type(rawget(object, "RankNumber")) == "number"
            and type(rawget(object, "Rewards")) == "table" then
            ranks[rawget(object, "RankNumber")] = object
        elseif type(rawget(object, "DisplayName")) == "string"
            and type(rawget(object, "Sets")) == "table" then
            questDirs[id] = object
        elseif type(rawget(object, "eggNumber")) == "number" then
            eggByNumber[rawget(object, "eggNumber")] = id
        end
    end
end

local function scanHeap()
    if not heapObjects then
        if os.clock() < nextAt.heap then return end
        heapStarted = os.clock()
        nextAt.heap = heapStarted + CFG.HeapInterval
        local objects, known = nextSource()
        if not objects then
            notes.heap = known and "scan returned no tables" or "getgc unavailable"
            orbBackfillNeeded = false
            return
        end
        heapObjects, heapCursor, heapBackfillsOrbs = objects, nil, orbBackfillNeeded
    end
    local scan = heapObjects
    for count = 1, CFG.HeapCap do
        if not alive or heapObjects ~= scan then return end
        local key, object = next(scan, heapCursor)
        heapCursor = key
        if key == nil then
            if heapBackfillsOrbs then orbBackfillNeeded = false end
            heapObjects, heapCursor, heapBackfillsOrbs = nil, nil, false
            notes.heap = "scanned " .. tostring(heapState.tried)
            return
        end
        heapState.tried += 1
        local kind = type(object)
        if kind == "table" then
            inspectObject(object)
            -- An instance's class table carries the module (PlayerPet, Orb, item
            -- classes), so a metatable is a second route to the same functions.
            local meta = getmetatable(object)
            local class = type(meta) == "table" and rawget(meta, "__index")
            if type(class) == "table" then inspectObject(class) end
        elseif kind == "function" then
            -- Executors that return functions only still expose the module
            -- through its upvalues: Save's cache, the Orb class, zone dirs and
            -- every other module-local table live there. Roblox's debug table
            -- has no getupvalue, so the executor extensions are probed too.
            local readUpvalue = (debug and debug.getupvalue) or getupvalue or env.getupvalue
            if type(readUpvalue) == "function" then
                for index = 1, 24 do
                    local ok, upname, value = pcall(readUpvalue, object, index)
                    if not ok or upname == nil then break end
                    if type(value) == "table" then inspectObject(value) end
                end
            else
                local dumpUpvalues = getupvalues or env.getupvalues
                if type(dumpUpvalues) == "function" then
                    local ok, values = pcall(dumpUpvalues, object)
                    if ok and type(values) == "table" then
                        for _, value in pairs(values) do
                            if type(value) == "table" then inspectObject(value) end
                        end
                    end
                end
            end
        end
        if heapState.clear and type(key) == "number" then
            local ok = pcall(function() scan[key] = nil end)
            if not ok then heapState.clear = false end
        end
        if count % 500 == 0 then task.wait() end
    end
    if heapObjects == scan then notes.heap = ("scanning; %d tables"):format(heapState.tried) end
end

local treeScan
local function scanTree()
    if not treeScan and os.clock() < nextAt.tree then return end
    treeScan = treeScan or {queue = {RS}, cursor = 1, childIndex = 1, candidates = {}, priorities = {}, ambiguous = {}}
    local scan = treeScan
    local visited = 0
    while scan.cursor <= #scan.queue and visited < CFG.TreeCap and alive do
        local parent = scan.queue[scan.cursor]
        local okChildren, fetched = pcall(function() return parent:GetChildren() end)
        if not okChildren then
            scan.cursor += 1
            scan.children, scan.childIndex = nil, 1
        else
            scan.children = fetched
        end
        local child = scan.children and scan.children[scan.childIndex]
        if not child then
            scan.cursor += 1
            scan.children, scan.childIndex = nil, 1
            visited += 1
        else
            scan.childIndex += 1
            visited += 1
            local expected = REMOTE_TYPES[child.Name]
            if expected and child:IsA(expected) then
                local priority = parent.Name == "Network" and 3 or
                    ((parent.Name == "Remotes" or parent.Name == "Net" or parent.Name == "__Network") and 2 or 1)
                local oldPriority = scan.priorities[child.Name] or 0
                if priority > oldPriority then
                    scan.candidates[child.Name], scan.priorities[child.Name], scan.ambiguous[child.Name] = child, priority, nil
                elseif priority == oldPriority then scan.ambiguous[child.Name] = true end
            end
            if child:IsA("ModuleScript") then
                local number, id = child.Name:match("^(%d+)%s*|%s*(.-)%s*$")
                if number then
                    local ancestor = child.Parent
                    while ancestor and ancestor ~= RS do
                        if ancestor.Name == "Zones" then registerZone(tonumber(number), id); break end
                        if ancestor.Name == "Zone Eggs" then eggByNumber[tonumber(number)] = id; break end
                        ancestor = ancestor.Parent
                    end
                end
            end
            scan.queue[#scan.queue + 1] = child
        end
        if visited % 500 == 0 then task.wait() end
    end
    if scan.cursor > #scan.queue then
        for name in pairs(scan.ambiguous) do scan.candidates[name] = nil end
        remotes, treeScan = scan.candidates, nil
        nextAt.tree = os.clock() + CFG.TreeInterval
        bindStats()
    end
end

local function needsNative()
    if (enabled.petSpeed or enabled.farm) and not modules.pet and next(petState.records) == nil then return true end
    -- Only Fast Farm insists on the registry: it is the mode that must not
    -- waste taps on NoTapping breakables. Plain tap and Aura keep using the
    -- folder walk so they still cost no heap scan.
    if enabled.farm and not modules.breakables then return true end
    if (enabled.vacuum or enabled.farm) and (not modules.orb or orbBackfillNeeded) then return true end
    if enabled.autoEgg and next(eggByNumber) == nil then return true end
    if enabled.worldTele then
        local ready = false
        for _, zone in pairs(zones) do
            if zone.definition and zone.definition.WorldNumber == worldTarget then ready = true; break end
        end
        if not ready then return true end
    end
    local save = getSave()
    -- The live Save cache is authoritative: the current game's "Get Stats" remote
    -- can exist yet return nil, so always discover the Save module when a profile
    -- is needed, regardless of whether a stats remote was found by name.
    if (enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoDoQuest or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele or enabled.autoBuyPetSlots or enabled.autoBuyEggSlots or enabled.autoForeverPack or enabled.autoBuyUpgrades or enabled.autoEquipEnchant or enabled.worldAdvance) and not save then return true end
    if not save and (enabled.autoKeys or enabled.autoGiftBags or enabled.autoFruits or enabled.autoPotions
        or enabled.autoFreeGifts or enabled.autoUltimate or enabled.autoDaycare or enabled.autoFlags
        or enabled.autoSecretRooms or enabled.autoRelics or enabled.autoTreehouse or enabled.autoFuse
        or enabled.autoCards or enabled.autoMailClaim or enabled.autoTNT or enabled.autoTNTCrate
        or enabled.optPumpkinTycoon or enabled.ptAutoTeleBestEgg or enabled.ptAutoBuyEgg
        or enabled.ptAutoBuyButtons or enabled.ptAutoRebirth or enabled.ptAutoKeepPumpkins
        or enabled.ptAutoBreakPumpkins or enabled.ptAutoBuyMerchant or enabled.ptAutoPlantPumpkins
        or enabled.ptAutoBuyUpgrades or enabled.ptAutoBuyCocoa or enabled.ptAutoUseBoosts
        or enabled.ptAutoFlannelGifts or enabled.ptAutoHuntWild or enabled.ptAutoCatchWild
        or enabled.ptAutoBuyNets or enabled.ptAutoFightTurkey or enabled.ptAutoCatchRare) then return true end
    if enabled.autoRebirth and save and not rebirths[save.Rebirths + 1] then return true end
    if (enabled.autoQuest or enabled.autoDoQuest) and save and type(save.NPCQuests) == "table" then
        for id, data in pairs(save.NPCQuests) do
            if type(data) == "table" and data.Completed ~= true and not questDirs[id] then return true end
        end
    end
    return false
end

local function discoveryTick()
    scanTree()
    if not alive or not needsNative() then releaseHeap(); return end
    scanHeap()
    while alive and heapObjects and needsNative() do
        task.wait()
        scanHeap()
    end
    if not needsNative() then releaseHeap() end
end

local function thingsFolder(name)
    for _, rootName in ipairs({"__THINGS", "_THINGS", "THINGS"}) do
        local root = workspace:FindFirstChild(rootName)
        local found = root and root:FindFirstChild(name)
        if found then return found end
    end
    return workspace:FindFirstChild(name)
end

local function position()
    local character = LocalPlayer.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    return root and root.Position or nil
end

local function modelPosition(model)
    if model:IsA("BasePart") then return model.Position end
    if model:IsA("Model") then return model:GetPivot().Position end
    return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true
local function currentZone()
    local ground, point = thingsFolder("__FAKE_GROUND"), position()
    if not ground or not point then return nil end
    rayParams.FilterDescendantsInstances = {ground}
    -- The ground model can be destroyed mid-call by the game's own teardown;
    -- a filter holding a destroyed instance makes Raycast throw.
    local ok, hit = pcall(workspace.Raycast, workspace, point + Vector3.new(0, 8, 0), Vector3.new(0, -200, 0), rayParams)
    if not ok or not hit then return nil end
    local id = hit.Instance.Name
    return id
end

local function maxOwned(save)
    if not save then return nil end
    local best
    for id, owned in pairs(save.UnlockedZones) do
        local number = owned == true and zoneNumbers[id] or nil
        if number and (not best or number > best) then best = number end
    end
    return best
end

local function bestInWorld(save, world)
    local best, entry
    for number, zone in pairs(zones) do
        if zone.definition and zone.definition.WorldNumber == world then
            if not entry or number < entry then entry = number end
            if save and save.UnlockedZones[zone.id] == true and (not best or number > best) then best = number end
        end
    end
    return best or entry
end

local function restorePetSpeed()
    if petState.module and petState.module.CalculateSpeedMultiplier == petState.hook then
        local ok, err = pcall(function() petState.module.CalculateSpeedMultiplier = petState.original end)
        if not ok then warn("[PS99 CLEAN] pet restore: " .. tostring(err)) end
    end
    for record, previous in pairs(petState.previous) do
        if not record.destroyed and type(previous) == "number" then
            local ok, err = pcall(function()
                record.speedMult = previous
                local cpet = record.cpet
                if type(cpet) == "table" then
                    cpet:Broadcast("petSpeedMult", previous)
                    cpet:Broadcast("petSpeed", 0.45)
                    if cpet.parallelIn then
                        cpet.parallelIn.petSpeedMult = previous
                        cpet.parallelIn.petSpeed = 0.45
                    end
                    if cpet.actor and type(cpet.actor.SendMessage) == "function" then
                        cpet.actor:SendMessage("Update", cpet.uid, cpet.bucketId, { petSpeedMult = previous, petSpeed = 0.45 })
                    end
                end
            end)
            if not ok then warn("[PS99 CLEAN] pet reset: " .. tostring(err)) end
        end
    end
    table.clear(petState.previous)
    table.clear(petState.teleportedTarget)
    table.clear(petState.assignedModel)
    table.clear(petState.assignedUid)
    table.clear(petState.joinedTarget)
    petState.attackModel, petState.attackUid, petState.bulkTarget = nil, nil, nil
    petState.module, petState.original, petState.hook = nil, nil, nil
    notes.pet = "off"
end

function petState.isAttacking(record)
    if not enabled.petTeleAfterAttack then return true end
    if record then
        local cpet = rawget(record, "cpet")
        if type(cpet) == "table" and cpet.targetType == "Breakable" then
            return true
        end
        local assigned = petState.assignedModel[record]
        if assigned and assigned.Parent then
            return true
        end
        local tgt = rawget(record, "target")
        if typeof(tgt) == "Instance" and tgt.Parent and tgt:GetAttribute("BreakableUID") ~= nil then
            return true
        end
        return false
    end
    local now = os.clock()
    return (petState.attackModel ~= nil and petState.attackModel.Parent ~= nil)
        or (now - (petState.lastAttackAt or -math.huge) <= 0.9)
end

local function petTick()
    if not modules.pet and not CFG.BootstrapDone then
        CFG.BootstrapModules()
    end
    local mod = modules.pet
    if not mod and next(petState.records) == nil then notes.pet = "waiting for PlayerPet; " .. notes.heap; return end
    if mod then
        if petState.module and (mod ~= petState.module or petState.module.CalculateSpeedMultiplier ~= petState.hook) then
            restorePetSpeed()
            enabled.petSpeed, enabled.farm = false, false
            syncWorkers()
            updateToggles()
            stage("Pet speed disabled: another script changed the pet module")
            return
        end
        if not petState.hook then
            local original = mod.CalculateSpeedMultiplier
            local hook = function(pet, ...)
                local ok, result = pcall(original, pet, ...)
                if not ok then return pet and pet.speedMult or 1 end
                if alive and (enabled.petSpeed or enabled.farm) and pet and pet.owner == LocalPlayer then
                    petState.previous[pet] = result
                    if petState.isAttacking(pet) then
                        return CFG.PetSpeedMult
                    end
                end
                return result
            end
            local ok, err = pcall(function() mod.CalculateSpeedMultiplier = hook end)
            if ok then
                petState.module, petState.original, petState.hook = mod, original, hook
            else
                notes.pet = "module read-only: " .. tostring(err)
            end
        end
    end
    local count, activeCount = 0, 0
    local seen = {}
    local boostBaseSpeed = (CFG.PetSpeedMult >= 1000) and 50 or math.max(0.45, CFG.PetSpeedMult * 0.05)
    local function apply(record)
        if seen[record] or record.destroyed
            or (record.owner ~= nil and record.owner ~= LocalPlayer) then return end
        seen[record] = true
        if petState.previous[record] == nil then
            local prev = tonumber(record.speedMult)
            petState.previous[record] = (prev and prev < 50 and prev) or 1
        end
        local petAttacking = petState.isAttacking(record)
        local desiredSpeed = petAttacking and CFG.PetSpeedMult or (petState.previous[record] or 1)
        local desiredBase = petAttacking and boostBaseSpeed or 0.45
        if petAttacking then
            activeCount += 1
        else
            petState.teleportedTarget[record] = nil
            petState.assignedModel[record] = nil
            petState.assignedUid[record] = nil
            petState.joinedTarget[record] = nil
        end
        local ok = pcall(function() record.speedMult = desiredSpeed end)
        if not ok then return end
        local cpet = record.cpet
        if type(cpet) == "table" then
            pcall(function()
                cpet:Broadcast("petSpeedMult", desiredSpeed)
                cpet:Broadcast("petSpeed", desiredBase)
                if cpet.parallelIn then
                    cpet.parallelIn.petSpeedMult = desiredSpeed
                    cpet.parallelIn.petSpeed = desiredBase
                end
                if cpet.actor and type(cpet.actor.SendMessage) == "function" then
                    cpet.actor:SendMessage("Update", cpet.uid, cpet.bucketId, { petSpeedMult = desiredSpeed, petSpeed = desiredBase })
                end
            end)
        end
        count += 1
    end
    local group = nil
    if mod and type(mod.GetByPlayer) == "function" then
        local ok, value = pcall(mod.GetByPlayer, LocalPlayer)
        if ok and type(value) == "table" then group = value end
    end
    if group then
        for _, record in pairs(group) do apply(record) end
    end
    for record in pairs(petState.records) do apply(record) end
    if count == 0 then
        notes.pet = "no pets equipped"
    elseif activeCount > 0 then
        notes.pet = ("fast x%d | %d/%d pets attacking"):format(math.floor(CFG.PetSpeedMult), activeCount, count)
    else
        notes.pet = ("idle | %d pets waiting for attack"):format(count)
    end
end

-- 1 Pet = 1 Breakable (strictly distributes pets so each pet locks onto its own
-- distinct breakable without stacking all pets onto 1 ore, attacks that
-- breakable first via Breakables_PlayerDealDamage, then teleports the pet and
-- registers all pet->breakable pairs in Breakables_JoinPetBulk).
function petState.routeSpread(candidates, point)
    if not alive or type(candidates) ~= "table" or #candidates == 0 then return 0 end
    local mod = modules.pet
    local local_pets, seen = {}, {}
    local group = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
    if type(group) == "table" then
        for _, record in pairs(group) do if not seen[record] then seen[record] = true; local_pets[#local_pets + 1] = record end end
    end
    for record in pairs(petState.records) do
        if not seen[record] then seen[record] = true; local_pets[#local_pets + 1] = record end
    end
    local ranked = {}
    for _, record in ipairs(local_pets) do
        local foreign = rawget(record, "owner") ~= nil and rawget(record, "owner") ~= LocalPlayer
        if not record.destroyed and not foreign and type(record.GetPosition) == "function" then
            local distance = math.huge
            local ok, at = pcall(record.GetPosition, record)
            if ok and at then
                local measured, value = pcall(function() return (at - point).Magnitude end)
                if measured then distance = value end
            end
            ranked[#ranked + 1] = {record = record, distance = distance}
        end
    end
    table.sort(ranked, function(a, b) return a.distance < b.distance end)
    local total = math.min(enabled.petAll and #ranked or math.max(1, math.ceil(#ranked / 2)), #ranked)
    if total == 0 then return 0 end

    local validByModel = {}
    local ordered = {}
    for _, model in ipairs(candidates) do
        if model and model.Parent then
            local uid = model:GetAttribute("BreakableUID")
            if uid ~= nil and not validByModel[model] then
                validByModel[model] = uid
                ordered[#ordered + 1] = {model = model, uid = uid}
            end
        end
    end
    if #ordered == 0 then return 0 end

    -- Pass 1: preserve existing living 1-to-1 assignments so a pet stays on its
    -- own breakable until that breakable is destroyed (no duplicate overlap).
    local usedByModel = {}
    for index = 1, total do
        local record = ranked[index].record
        local curModel = petState.assignedModel[record]
        local curUid = curModel and validByModel[curModel] or nil
        if curModel and curUid and not usedByModel[curModel] then
            usedByModel[curModel] = record
            petState.assignedUid[record] = curUid
        else
            petState.assignedModel[record] = nil
            petState.assignedUid[record] = nil
        end
    end

    -- Pass 2: assign every remaining pet to an unused breakable (1 pet = 1 ore).
    local cursor = 1
    for index = 1, total do
        local record = ranked[index].record
        if not petState.assignedModel[record] then
            local pickedEntry = nil
            for scan = 1, #ordered do
                local idx = ((cursor + scan - 2) % #ordered) + 1
                local entry = ordered[idx]
                if not usedByModel[entry.model] then
                    pickedEntry = entry
                    cursor = (idx % #ordered) + 1
                    break
                end
            end
            if pickedEntry then
                usedByModel[pickedEntry.model] = record
                petState.assignedModel[record] = pickedEntry.model
                petState.assignedUid[record] = pickedEntry.uid
            else
                -- More pets than breakables on the entire island: leave extra
                -- pet unassigned or on its own without stacking onto occupied ores.
                petState.assignedModel[record] = nil
                petState.assignedUid[record] = nil
            end
        end
    end

    -- Pass 3: attack each assigned breakable first, then route & snap each pet
    -- once to its own breakable and batch Breakables_JoinPetBulk.
    local routed = 0
    local bulkJoin = {}
    local attackedThisTick = {}
    for index = 1, total do
        local record = ranked[index].record
        local tModel = petState.assignedModel[record]
        local tUid = petState.assignedUid[record]
        if tModel and tUid and tModel.Parent then
            if not attackedThisTick[tUid] then
                attackedThisTick[tUid] = true
                fire("Breakables_PlayerDealDamage", tUid)
            end
            petState.attackModel, petState.attackUid = tModel, tUid
            petState.lastAttackAt = os.clock()
            local ok = pcall(function() record:SetTarget(tModel) end)
            if not ok then
                pcall(function() record.target = tModel end)
                pcall(function() record.Target = tModel end)
            end
            routed += 1
            local euid = rawget(record, "euid")
            if euid ~= nil and petState.joinedTarget[record] ~= tModel then
                petState.joinedTarget[record] = tModel
                bulkJoin[euid] = tUid
            end
            if petState.teleportedTarget[record] ~= tModel then
                local targetPos = modelPosition(tModel)
                if targetPos then
                    petState.teleportedTarget[record] = tModel
                    local angle = ((index - 1) / math.max(total, 1)) * math.pi * 2
                    local ringPos = targetPos + Vector3.new(math.cos(angle) * 3.5, 0, math.sin(angle) * 3.5)
                    local ringCF = CFrame.lookAt(ringPos, Vector3.new(targetPos.X, ringPos.Y, targetPos.Z))
                    pcall(function()
                        local boostBase = (CFG.PetSpeedMult >= 1000) and 50 or math.max(0.45, CFG.PetSpeedMult * 0.05)
                        record.speedMult = CFG.PetSpeedMult
                        local cpet = rawget(record, "cpet")
                        if type(cpet) == "table" then
                            if cpet.parallelIn then
                                cpet.parallelIn.petSpeedMult = CFG.PetSpeedMult
                                cpet.parallelIn.petSpeed = boostBase
                            end
                            cpet:Broadcast("petSpeedMult", CFG.PetSpeedMult)
                            cpet:Broadcast("petSpeed", boostBase)
                            if cpet.physical and cpet.physical.Parent then
                                cpet.physical:PivotTo(ringCF)
                            end
                            if type(cpet.parallelOut) == "table" then
                                cpet.parallelOut.cf = ringCF
                                cpet.parallelOut.arrived = true
                                cpet.parallelOut.farming = true
                            end
                            if cpet.actor and type(cpet.actor.SendMessage) == "function" then
                                cpet.actor:SendMessage("Update", cpet.uid, cpet.bucketId, { petSpeedMult = CFG.PetSpeedMult, petSpeed = boostBase })
                                cpet.actor:SendMessage("Reposition", cpet.uid, cpet.bucketId)
                            end
                        end
                    end)
                end
            end
        end
    end
    if enabled.petBulkJoin and next(bulkJoin) ~= nil then
        pcall(fire, "Breakables_JoinPetBulk", bulkJoin)
    end
    return routed
end

function petState.route(targetModel, point, explicitUid)
    local list = {}
    if targetModel and targetModel.Parent then list[#list + 1] = targetModel end
    if type(auraTargets) == "table" then
        for _, cand in ipairs(auraTargets) do
            if cand ~= targetModel and cand and cand.Parent then
                list[#list + 1] = cand
            end
        end
    end
    return petState.routeSpread(list, point)
end

local function validTarget(model, point, zone)
    if not model or not model:IsDescendantOf(workspace) then return false end
    if model:GetAttribute("ManualDamage") or model:GetAttribute("DisableDamage") then return false end
    if model:GetAttribute("BreakableUID") == nil then return false end
    local owner = model:GetAttribute("OwnerUsername")
    if owner and owner ~= LocalPlayer.Name then return false end
    local parentType = model:GetAttribute("ParentType")
    if zone and parentType == 1 and model:GetAttribute("ParentID") ~= zone then return false end
    local at = modelPosition(model)
    return at ~= nil and (at - point).Magnitude <= CFG.TapRange
end

local targetScan
local auraTargets, auraCursor = {}, 0

-- Queries the live BreakableFrontend registry first (fixing the chest class
-- tracking bug and including special breakable classes), then falls through to
-- the workspace.Breakables scan if the registry has no eligible hits.
local function pickTarget(point, zone)
    local registry = modules.breakables
    local byZone, getRecord = registry and registry.AllByZoneAndClass, registry and registry.Get
    if type(byZone) == "function" and type(getRecord) == "function" and zone then
        local merged, chestSet = {}, {}
        for _, class in ipairs({"Chest", "Normal", "Economy", "Event", "Pinata", "LuckyBlock", "Comet", "CoinJar"}) do
            local okList, list = pcall(byZone, zone, class)
            if okList and type(list) == "table" then
                for uid, value in pairs(list) do
                    merged[uid] = value
                    if class == "Chest" then chestSet[uid] = true end
                end
            end
        end
        local targets, best, bestUid, bestDistance = {}, nil, nil, math.huge
        local chestBest, chestUid, chestDistance = nil, nil, math.huge
        for uid, value in pairs(merged) do
            local record = type(value) == "table" and value.model ~= nil and value or nil
            local model = record and record.model or value
            if not record then
                local ok, found = pcall(getRecord, uid)
                record = ok and type(found) == "table" and found or nil
            end
            if record and model and model.Parent then
                local dir = record.dir
                local blocked = record.disableDamage == true or (type(dir) == "table" and dir.NoTapping == true)
                    or not not (record.modifier and record.modifier.Owner and record.modifier.Owner ~= LocalPlayer.Name)
                if not blocked then
                    local distance = math.huge
                    local at = record.position or modelPosition(model)
                    if at then
                        local measured, result = pcall(function() return (at - point).Magnitude end)
                        if measured then distance = result end
                    end
                    if distance <= CFG.TapRange then
                        targets[#targets + 1] = model
                        if distance <= bestDistance then best, bestUid, bestDistance = model, uid, distance end
                        local isChest = chestSet[uid] or (type(dir) == "table" and dir.isChest == true)
                            or tostring(record.id or ""):lower():find("chest", 1, true) ~= nil
                        if isChest and distance <= chestDistance then
                            chestBest, chestUid, chestDistance = model, uid, distance
                        end
                    end
                end
            end
        end
        if #targets > 0 then
            auraTargets, targetScan = targets, nil
            if enabled.chestFirst and chestBest then return chestBest, chestUid end
            return best, bestUid
        end
    end
    local root = thingsFolder("Breakables")
    if not root then targetScan = nil; return nil, nil end
    if not targetScan or targetScan.root ~= root or targetScan.zone ~= zone then
        targetScan = {root = root, zone = zone, queue = {root}, cursor = 1, childIndex = 1, targets = {}}
    end
    local scan, visited = targetScan, 0
    while scan.cursor <= #scan.queue and visited < CFG.BreakableScanCap do
        local parent = scan.queue[scan.cursor]
        local okChildren, fetched = pcall(function() return parent:GetChildren() end)
        if not okChildren then
            scan.cursor += 1
            scan.children, scan.childIndex = nil, 1
        else
            scan.children = fetched
        end
        local child = scan.children and scan.children[scan.childIndex]
        visited += 1
        if not child then
            scan.cursor += 1
            scan.children, scan.childIndex = nil, 1
        else
            scan.childIndex += 1
            local uid = child:GetAttribute("BreakableUID")
            if uid ~= nil then
                if validTarget(child, point, zone) or (zone and validTarget(child, point, nil)) then
                    local childPos = modelPosition(child)
                    if childPos then
                        scan.targets[#scan.targets + 1] = child
                        local length = (childPos - point).Magnitude
                        local isChest = enabled.chestFirst and tostring(child:GetAttribute("BreakableID") or child.Name):lower():find("chest", 1, true) ~= nil
                        if isChest then length = length * 0.25 end
                        local bestPos = validTarget(scan.best, point, nil) and modelPosition(scan.best) or nil
                        local oldDistance = bestPos and (bestPos - point).Magnitude or math.huge
                        if length <= oldDistance then scan.best, scan.uid = child, uid end
                    end
                end
            elseif child:IsA("Folder") or child:IsA("Model") then scan.queue[#scan.queue + 1] = child end
        end
        if visited % 500 == 0 then task.wait() end
    end
    if scan.cursor > #scan.queue then
        auraTargets, targetScan = scan.targets, nil
    elseif #auraTargets == 0 and #scan.targets > 0 then
        auraTargets = scan.targets
    end
    if validTarget(scan.best, point, nil) then return scan.best, scan.uid end
    return nil, nil
end

local function tapTick()
    local now = os.clock()
    local isLegitOnly = enabled.legitTap and not enabled.farm and not enabled.clickAura
    if (enabled.jitter or isLegitOnly) and now < nextAt.tap then return end
    local point = position()
    if not point then notes.tap = "waiting for character"; return end
    local zone = currentZone()
    if pickCount(picked.zones) > 0 and zone and not picked.zones[zone] then
        notes.tap = "zone not selected: " .. tostring(zone or "unknown")
        target.model, target.uid = nil, nil
        petState.attackModel, petState.attackUid = nil, nil
        return
    end
    if not validTarget(target.model, point, zone) or now - (target.at or 0) >= CFG.TargetRescan then
        target.model, target.uid = pickTarget(point, zone)
        target.at = now
    end
    if not target.model and now >= (CFG.TapProbeAt or 0) then
        CFG.TapProbeAt = now + 0.35
        local registry = modules.breakables
        if registry and type(registry.GetAutoTapTarget) == "function" then
            local ok, model = pcall(registry.GetAutoTapTarget)
            if ok and model and validTarget(model, point, nil) then
                target.model, target.uid = model, model:GetAttribute("BreakableUID")
                target.at = now
            end
        end
    end
    -- Sticky pet attack target: keep pets locked onto their current attacked
    -- breakable while it is alive (or for at least PetAttackDwell seconds) so
    -- Click Aura rotation does not thrash pet teleports 60 times per second.
    local petTargetModel, petTargetUid = petState.attackModel, petState.attackUid
    local dwell = math.max(CFG.PetAttackDwell or 0.45, CFG.PetRouteRate or 0.35)
    if not validTarget(petTargetModel, point, nil) or (now - (petState.switchAt or 0) >= dwell and target.model and target.model ~= petTargetModel and not enabled.clickAura) then
        petTargetModel, petTargetUid = target.model, target.uid
        petState.attackModel, petState.attackUid, petState.switchAt = petTargetModel, petTargetUid, now
    end
    if enabled.clickAura and #auraTargets > 0 then
        target.model, target.uid = nil, nil
        for _ = 1, #auraTargets do
            auraCursor = auraCursor % #auraTargets + 1
            local candidate = auraTargets[auraCursor]
            if validTarget(candidate, point, nil) then
                target.model, target.uid = candidate, candidate:GetAttribute("BreakableUID")
                break
            end
        end
        if not validTarget(petTargetModel, point, nil) and target.model then
            petTargetModel, petTargetUid = target.model, target.uid
            petState.attackModel, petState.attackUid, petState.switchAt = petTargetModel, petTargetUid, now
        end
    end
    if not target.uid and not petTargetUid then
        petState.attackModel, petState.attackUid = nil, nil
        notes.tap = "no eligible breakable in range"
        return
    end
    if isLegitOnly then
        nextAt.tap = now + 0.125 + math.random() * 0.035
    elseif enabled.jitter then
        local interval = (1 / math.max(CFG.MaxTapRate, 1)) * (1 + math.random() * 0.5)
        if math.random() < 0.02 then interval += 0.25 end
        nextAt.tap = now + interval
    end
    local primaryUid = petTargetUid or target.uid
    local primaryModel = petTargetModel or target.model
    local ok, message = fire("Breakables_PlayerDealDamage", primaryUid)
    if target.uid and target.uid ~= primaryUid and not isLegitOnly then
        fire("Breakables_PlayerDealDamage", target.uid)
    end
    if not isLegitOnly and (enabled.farm or enabled.tap or enabled.clickAura) and (CFG.FarmBurst or 0) > 0 and #auraTargets > 1 then
        local extras = 0
        for _ = 1, math.min(#auraTargets, (CFG.FarmBurst or 6) * 2) do
            if extras >= CFG.FarmBurst then break end
            auraCursor = auraCursor % #auraTargets + 1
            local candidate = auraTargets[auraCursor]
            if candidate ~= primaryModel and candidate ~= target.model and validTarget(candidate, point, nil) then
                local uid = candidate:GetAttribute("BreakableUID")
                if uid then
                    fire("Breakables_PlayerDealDamage", uid)
                    extras += 1
                end
            end
        end
    end
    -- Route & teleport pets (1 pet = 1 distinct breakable) ONLY AFTER our attack
    -- (Breakables_PlayerDealDamage) has fired.
    if ok and primaryModel and primaryUid then
        petState.lastAttackAt = now
        local routeInterval = math.clamp(tonumber(CFG.PetRouteRate) or 0.35, 0.1, 1.0)
        if primaryModel ~= petState.routeTarget or now - (petState.routeAt or 0) >= routeInterval then
            petState.routeTarget, petState.routeAt = primaryModel, now
            petState.route(primaryModel, point, primaryUid)
        end
    end
    notes.tap = ok and ((enabled.clickAura and "aura: " or "tapping ") .. tostring(primaryUid)) or tostring(message)
end

local function restoreOrbCapture()
    if orbState.module and orbState.module.new == orbState.hook then
        local ok, err = pcall(function() orbState.module.new = orbState.original end)
        if not ok then warn("[PS99 CLEAN] orb restore: " .. tostring(err)) end
    end
    for record, previous in pairs(orbOffsets) do
        pcall(function() record._superMagnet = previous or nil end)
    end
    table.clear(orbOffsets)
    orbState.module, orbState.original, orbState.hook = nil, nil, nil
end

local function vacuumTick()
    if not orbState.hook and modules.orb then
        local mod, original = modules.orb, modules.orb.new
        local hook = function(...)
            local orb = original(...)
            if alive and type(orb) == "table" and orb._part then
                orbRecords[orb._part] = orb
                if enabled.vacuum or enabled.farm then magnetize(orb) end
            end
            return orb
        end
        local ok = pcall(function() mod.new = hook end)
        if ok then orbState.module, orbState.original, orbState.hook = mod, original, hook end
    end
    local root, point = thingsFolder("Orbs"), position()
    if not root or not point then notes.vacuum = "waiting for orbs/character"; return end
    local children = root:GetChildren()
    local flagged, total = 0, 0
    for _ = 1, math.min(#children, CFG.BreakableScanCap) do
        if orbState.cursor > #children then orbState.cursor = 1 end
        local child = children[orbState.cursor]
        orbState.cursor += 1
        local record = orbRecords[child]
        if type(record) == "table" and not record._destroyed and record._part == child then
            total += 1
            if orbOffsets[record] == nil then orbOffsets[record] = record._superMagnet end
            if record._superMagnet ~= true then record._superMagnet = true end
            flagged += 1
        end
    end
    if total == 0 then notes.vacuum = "waiting for orb records; " .. notes.heap; return end
    notes.vacuum = ("%d/%d orbs magnetized"):format(flagged, total)
end

-- Finds the zone folder in Directory cache or workspace.Map / Map2 / Map3 / Map4 (Zones 1-279+).
local function findZoneFolder(id)
    local num = zoneNumbers[id]
    local zoneEntry = num and zones[num]
    local def = zoneEntry and zoneEntry.definition
    if type(def) == "table" and typeof(def.ZoneFolder) == "Instance" and def.ZoneFolder.Parent then
        return def.ZoneFolder
    end
    local exactName = num and (tostring(num) .. " | " .. id) or nil
    local altName = (num and type(def) == "table" and type(def.ZoneName) == "string")
        and (tostring(num) .. " | " .. def.ZoneName) or nil
    local suffix = " | " .. id
    for w = 1, CFG.WorldCount do
        local map = workspace:FindFirstChild(w == 1 and "Map" or ("Map" .. w))
        if map then
            if exactName then
                local exact = map:FindFirstChild(exactName)
                if exact then return exact end
            end
            if altName and altName ~= exactName then
                local alt = map:FindFirstChild(altName)
                if alt then return alt end
            end
            local ok, children = pcall(map.GetChildren, map)
            if ok then
                for _, child in ipairs(children) do
                    if child.Name == id or child.Name:sub(-#suffix) == suffix
                        or (num and tonumber(child.Name:match("^(%d+)%s*|")) == num) then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

local function zoneWorldNumber(id)
    local num = zoneNumbers[id]
    local def = num and zones[num] and zones[num].definition
    if type(def) == "table" and type(def.WorldNumber) == "number" then
        return def.WorldNumber
    end
    if num then
        if num >= (CFG.WorldFirst[4] or 240) then return 4 end
        if num >= (CFG.WorldFirst[3] or 200) then return 3 end
        if num >= (CFG.WorldFirst[2] or 100) then return 2 end
    end
    return 1
end

local function detectActiveWorld()
    for w = CFG.WorldCount, 2, -1 do
        if workspace:FindFirstChild("Map" .. w) then return w end
    end
    if workspace:FindFirstChild("Map") then return 1 end
    local pid = game.PlaceId
    if pid == 140403681187145 then return 4 end
    if pid == 17503543197 then return 3 end
    if pid == 16498369169 then return 2 end
    return 1
end

-- Finds the closest egg model belonging to or bordering a farm zone.
function CFG.FindZoneEggPos(id, breakCenter, folder)
    local bestPos, bestDist = nil, 95
    local function consider(inst)
        if not inst then return end
        local p = inst:IsA("BasePart") and inst.Position or (inst:IsA("Model") and modelPosition(inst))
        if p and breakCenter then
            local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(breakCenter.X, 0, breakCenter.Z)).Magnitude
            if d < bestDist then
                bestDist = d
                bestPos = p
            end
        end
    end
    if folder then
        for _, desc in ipairs(folder:GetDescendants()) do
            local nm = desc.Name:lower()
            if (desc:IsA("Model") or desc:IsA("BasePart")) and (nm:find("egg", 1, true) or nm:find("capsule", 1, true)) then
                consider(desc)
            end
        end
    end
    local eggsRoot = thingsFolder("Eggs")
    if eggsRoot and breakCenter then
        for _, child in ipairs(eggsRoot:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                for _, egg in ipairs(child:GetChildren()) do
                    if egg:IsA("Model") or egg:IsA("BasePart") then
                        consider(egg)
                    end
                end
            end
        end
    end
    return bestPos, bestDist
end

-- Resolves the optimal standing spot for a farm island focused on MAIN FARM / BREAKABLE items:
-- Priority 1: Live breakable items / INTERACT.BREAK_ZONES middle (strictly inside breakable bounds; shifts slightly toward an egg ONLY if still inside the breakables).
-- Priority 2: Live breakables centroid (exact = true).
-- Priority 3: __FAKE_GROUND / PERSISTENT.Teleport fallback (exact = false, triggers streaming).
local function zoneCenter(id, preferEgg)
    if type(id) ~= "string" then return nil, false end
    local folder = findZoneFolder(id)
    local liveSum, liveCount, liveMaxY = Vector3.zero, 0, -math.huge
    local registry = modules.breakables
    if registry and type(registry.AllByZoneAndClass) == "function" then
        for _, class in ipairs({"Normal", "Chest", "Economy", "Event", "Pinata", "LuckyBlock", "Comet", "CoinJar"}) do
            local ok, list = pcall(registry.AllByZoneAndClass, id, class)
            if ok and type(list) == "table" then
                for _, value in pairs(list) do
                    local record = type(value) == "table" and value.model ~= nil and value or nil
                    local at = record and record.position or (typeof(value) == "Instance" and modelPosition(value))
                    if typeof(at) == "Vector3" then
                        liveSum += at
                        liveCount += 1
                        if at.Y > liveMaxY then liveMaxY = at.Y end
                    end
                    if liveCount >= 400 then break end
                end
            end
            if liveCount >= 400 then break end
        end
    end
    if folder then
        local interact = folder:FindFirstChild("INTERACT")
        local breakZones = interact and (interact:FindFirstChild("BREAK_ZONES") or interact:FindFirstChild("BREAKABLE_SPAWNS"))
        if breakZones then
            local sum, count = Vector3.zero, 0
            local minX, maxX = math.huge, -math.huge
            local minZ, maxZ = math.huge, -math.huge
            local maxY = -math.huge
            for _, part in ipairs(breakZones:GetDescendants()) do
                if part:IsA("BasePart") then
                    sum += part.Position
                    count += 1
                    local hx, hz = part.Size.X * 0.5, part.Size.Z * 0.5
                    minX = math.min(minX, part.Position.X - hx)
                    maxX = math.max(maxX, part.Position.X + hx)
                    minZ = math.min(minZ, part.Position.Z - hz)
                    maxZ = math.max(maxZ, part.Position.Z + hz)
                    maxY = math.max(maxY, part.Position.Y + part.Size.Y * 0.5)
                end
            end
            if count > 0 then
                local topY = math.max(maxY, liveCount > 0 and liveMaxY or maxY)
                local mid = liveCount >= 3
                    and Vector3.new(math.clamp(liveSum.X / liveCount, minX + 2, maxX - 2), topY, math.clamp(liveSum.Z / liveCount, minZ + 2, maxZ - 2))
                    or Vector3.new(sum.X / count, topY, sum.Z / count)
                if preferEgg ~= false and enabled.teleNearEgg then
                    local eggPos, eggDist = CFG.FindZoneEggPos(id, mid, folder)
                    if eggPos and eggDist <= 70 then
                        if eggDist <= 24 then
                            return mid, true
                        end
                        -- Shift toward egg ONLY if the resulting spot stays strictly inside the breakable zone
                        local dir = Vector3.new(mid.X - eggPos.X, 0, mid.Z - eggPos.Z)
                        if dir.Magnitude > 0.01 then
                            dir = dir.Unit
                            local nearEgg = Vector3.new(eggPos.X + dir.X * 18, topY, eggPos.Z + dir.Z * 18)
                            local clampedX = math.clamp(nearEgg.X, minX + 2, maxX - 2)
                            local clampedZ = math.clamp(nearEgg.Z, minZ + 2, maxZ - 2)
                            if (Vector3.new(clampedX, 0, clampedZ) - Vector3.new(eggPos.X, 0, eggPos.Z)).Magnitude <= 26 then
                                return Vector3.new(clampedX, topY, clampedZ), true
                            end
                        end
                    end
                end
                return mid, true
            end
        end
    end
    if liveCount > 0 then
        return Vector3.new(liveSum.X / liveCount, liveMaxY, liveSum.Z / liveCount), true
    end
    local ground = thingsFolder("__FAKE_GROUND")
    if ground then
        local targetPart = ground:FindFirstChild(id, true)
        if targetPart then
            if targetPart:IsA("BasePart") then return targetPart.Position + Vector3.new(0, targetPart.Size.Y * 0.5, 0), false end
            local ok, box, sz = pcall(function() return targetPart:GetBoundingBox() end)
            if ok and box then return box.Position + Vector3.new(0, sz and sz.Y * 0.5 or 0, 0), false end
            local ok2, pivot = pcall(function() return targetPart:GetPivot().Position end)
            if ok2 and pivot then return pivot, false end
        end
    end
    if folder then
        local persistent = folder:FindFirstChild("PERSISTENT")
        local tele = persistent and persistent:FindFirstChild("Teleport")
        if tele then
            if tele:IsA("BasePart") then return tele.Position + Vector3.new(0, tele.Size.Y * 0.5, 0), false end
            if tele:IsA("CFrameValue") then return tele.Value.Position, false end
            local ok, pos = pcall(function() return modelPosition(tele) end)
            if ok and pos then return pos, false end
        end
    end
    return nil, false
end

local function snapTo(point)
    if not point then return false end
    local character = LocalPlayer.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if not root then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Sit then
        pcall(function() hum.Sit = false end)
    end
    -- Teleport higher (+12 studs) to avoid clipping under floors or falling into the void
    local highPos = point + Vector3.new(0, 12, 0)
    pcall(fire, "RequestStreaming", point)
    local ok = pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        character:PivotTo(CFrame.new(highPos))
    end)
    if not ok then
        ok = pcall(function() root.CFrame = CFrame.new(highPos) end)
    end
    if ok then
        -- Anti-void guard: if solid ground below hasn't streamed in yet, briefly anchor until ground loads
        task.spawn(function()
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { character }
            local hit = workspace:Raycast(highPos, Vector3.new(0, -65, 0), rp)
            if not hit and root and root.Parent then
                pcall(function() root.Anchored = true end)
                local deadline = os.clock() + 1.2
                while alive and root and root.Parent and os.clock() < deadline do
                    hit = workspace:Raycast(highPos, Vector3.new(0, -65, 0), rp)
                    if hit then break end
                    task.wait(0.1)
                end
                if root and root.Parent then
                    if hit then
                        pcall(function()
                            root.AssemblyLinearVelocity = Vector3.zero
                            character:PivotTo(CFrame.new(hit.Position + Vector3.new(0, 6, 0)))
                        end)
                    end
                    pcall(function() root.Anchored = false end)
                end
            end
        end)
    end
    return ok
end

local WORLD_FALLBACK_SPAWN = {
    [3] = Vector3.new(-10221.390625, -2.1, -7376.2900390625),
    [4] = Vector3.new(-15916.173828125, 50.972, -387.6759948730469),
}

local function leaveActiveInstance()
    local inst = modules.instancing
    local inInst = false
    if inst then
        if type(inst.IsInInstance) == "function" then
            local okI, resI = pcall(inst.IsInInstance)
            if okI and resI == true then inInst = true end
        elseif type(inst.Get) == "function" then
            local okI, cur = pcall(inst.Get)
            if okI and type(cur) == "table" and cur.instanceID ~= nil then inInst = true end
        end
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local stuckPg = pg and pg:FindFirstChild("PumpkinTycoon") ~= nil
    local ptPos = position()
    local onPlotSky = CFG.Event and CFG.Event.Plot and CFG.Event.Plot() ~= nil and ptPos and ptPos.Y > 400
    if inInst and inst and type(inst.Leave) == "function" then
        pcall(inst.Leave)
        task.wait(0.6)
        return true
    end
    if inInst or stuckPg or onPlotSky then
        pcall(fire, "Instancing_PlayerLeaveInstance")
        task.wait(0.8)
        return true
    end
    return false
end

local legitTeleDone = {}

-- Island teleport (supports Zones 1-279 / World 1-4) with 2 modes:
--   "Instant" : direct CFrame snap to INTERACT.BREAK_ZONES middle (falls back to server tp if streamed out)
--   "Legit"   : uses Teleports_RequestTeleport first, waits for zone stream, then moves/snaps to middle
-- Both modes always finish in the exact middle of the farm area.
local function teleportToIslandMiddle(id, modeOverride)
    if type(id) ~= "string" or #id == 0 then return false, "invalid zone id" end
    leaveActiveInstance()
    local hereW = detectActiveWorld()
    local targetW = zoneWorldNumber(id)
    if targetW ~= hereW and targetW >= 1 and targetW <= CFG.WorldCount then
        local remoteName = "World" .. tostring(targetW) .. "Teleport"
        local ok, message = invoke(remoteName)
        return ok == true, ok == true and ("switching to World " .. targetW .. " for " .. id)
            or tostring(message or ("invoke " .. remoteName .. " failed"))
    end
    local mode = tostring(modeOverride or CFG.TeleMode or "Instant")
    local isLegit = mode:lower():find("legit", 1, true) ~= nil
    local zoneNum = zoneNumbers[id]
    local isFirstLegit200 = zoneNum and zoneNum >= 200 and not legitTeleDone[id]

    local function requestServerTele()
        local inst = modules.instancing
        local inInst = false
        if inst and type(inst.IsInInstance) == "function" then
            local okI, resI = pcall(inst.IsInInstance)
            inInst = okI and resI == true
        end
        local tpRemote = inInst and "Teleports_RequestInstanceTeleport" or "Teleports_RequestTeleport"
        local okTp = invoke(tpRemote, id)
        return okTp ~= nil and okTp ~= false
    end

    local function moveMiddleLegit(targetPos)
        local ch = LocalPlayer.Character
        local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart)
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not root then return false end
        local dist2D = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
        if dist2D <= 10 then return true end
        if hum and dist2D <= 120 then
            pcall(function() hum:MoveTo(targetPos) end)
            local walkDeadline = os.clock() + math.clamp(dist2D / math.max(hum.WalkSpeed, 16) + 0.6, 0.8, 3.0)
            while alive and os.clock() < walkDeadline do
                local cur = position()
                if cur and (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude <= 10 then
                    return true
                end
                task.wait(0.1)
            end
        end
        return snapTo(targetPos)
    end

    if isLegit then
        local alreadyInZone = currentZone() == id
        if not alreadyInZone then
            local okTp = requestServerTele()
            if okTp then
                if zoneNum and zoneNum >= 200 then legitTeleDone[id] = true end
                local deadline = os.clock() + 2.5
                local centre, exact = zoneCenter(id)
                while not exact and os.clock() < deadline and alive do
                    task.wait(0.2)
                    centre, exact = zoneCenter(id)
                end
                if centre then
                    if isLegit then
                        moveMiddleLegit(centre)
                    else
                        snapTo(centre)
                    end
                    task.delay(0.4, function()
                        if not alive then return end
                        local refined, isExact = zoneCenter(id)
                        if refined and (isExact or enabled.teleCenter or enabled.zoneTele) then
                            local cur = position()
                            if not cur or (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(refined.X, 0, refined.Z)).Magnitude > 10 then
                                if isLegit then moveMiddleLegit(refined) else snapTo(refined) end
                            end
                        end
                    end)
                    return true, (isLegit and "legit teleported to middle of " or "legit teleported (first visit) to ") .. id
                end
                return true, "legit teleported to " .. id .. " (via server)"
            end
        else
            local centre = zoneCenter(id)
            if centre then
                local okM = isLegit and moveMiddleLegit(centre) or snapTo(centre)
                return okM, okM and ("centered in middle of " .. id .. (isLegit and " (legit)" or "")) or "character unavailable"
            end
        end
    end

    local centre, exact = zoneCenter(id)
    local myPosNow = position()
    local tooFarOrBig = (zoneNum and zoneNum >= 200)
        and (not centre or not exact or (myPosNow and centre and (myPosNow - centre).Magnitude > 900))
    if not centre or tooFarOrBig then
        -- Big/streamed-out island (e.g. Zone 200+): force server teleport + streaming, then wait for exact farm area center
        if requestServerTele() then
            if zoneNum and zoneNum >= 200 then legitTeleDone[id] = true end
            local deadline = os.clock() + 3.0
            while alive and os.clock() < deadline do
                centre, exact = zoneCenter(id)
                if centre and exact then break end
                task.wait(0.2)
            end
            if not centre then
                return true, "teleported to " .. id .. " (via server)"
            end
        end
    end
    if not centre then
        local fallback = WORLD_FALLBACK_SPAWN[targetW]
        if fallback and (id == "Void Spawn" or id == "Fantasy Spawn") then
            pcall(fire, "RequestStreaming", fallback)
            local okSnap = snapTo(fallback)
            if okSnap then
                task.delay(0.45, function()
                    if not alive then return end
                    local refined = zoneCenter(id)
                    if refined then snapTo(refined) end
                end)
                return true, "teleported to " .. id .. " (fallback spawn)"
            end
        end
        return false, "island center not loaded: " .. tostring(id)
    end
    local ok = isLegit and moveMiddleLegit(centre) or snapTo(centre)
    if ok then
        local delays = exact and { 0.25 } or { 0.25, 0.65, 1.25 }
        for _, waitSec in ipairs(delays) do
            task.delay(waitSec, function()
                if not alive then return end
                local refined, isExact = zoneCenter(id)
                if refined and (isExact or enabled.teleCenter or enabled.zoneTele) then
                    local cur = position()
                    if not cur or (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(refined.X, 0, refined.Z)).Magnitude > 10 then
                        if isLegit then moveMiddleLegit(refined) else snapTo(refined) end
                    end
                end
            end)
        end
    end
    return ok, ok and ("teleported to middle of " .. id .. " (" .. (isLegit and "legit" or "instant") .. ")") or "character unavailable"
end

local function teleTick()
    local now = os.clock()
    if now < nextAt.tele then return end
    local save = getSave()
    if not save then notes.tele = "waiting for profile"; return end
    local best = maxOwned(save)
    if not best then notes.tele = "waiting for zone map"; return end
    local id = zones[best].id
    local hereW = detectActiveWorld()
    local targetW = zoneWorldNumber(id)
    if targetW ~= hereW then
        nextAt.tele = now + CFG.WorldBackoff
        if enabled.worldAdvance or enabled.worldTele then
            local ok, msg = teleportToIslandMiddle(id)
            notes.tele = tostring(msg)
            return
        end
        notes.tele = ("best zone %s is in World %d (you are in World %d)"):format(id, targetW, hereW)
        return
    end
    local centre = zoneCenter(id)
    local pos = position()
    local inZone = currentZone() == id
    if centre then
        local dist2D = pos and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(centre.X, 0, centre.Z)).Magnitude or math.huge
        if inZone and (not enabled.teleCenter or dist2D <= 10) then
            notes.tele = ("standing in middle of %s (%s)"):format(id, tostring(CFG.TeleMode or "Instant"))
            return
        end
    elseif inZone then
        notes.tele = "in " .. id .. " (waiting for center)"
        return
    end
    nextAt.tele = now + CFG.TeleInterval
    local ok, msg = teleportToIslandMiddle(id)
    notes.tele = ok and ("middle: " .. id .. " (" .. tostring(CFG.TeleMode or "Instant") .. ")") or tostring(msg)
end

local function buyTick()
    local now = os.clock()
    if now < nextAt.buy then return end
    local save = getSave()
    if not save then notes.buy = "waiting for profile"; return end
    local best = maxOwned(save)
    local nextZone = best and zones[best + 1]
    if not nextZone then notes.buy = "next zone unavailable"; return end
    nextAt.buy = now + CFG.BuyBackoff
    local ok, message = invoke("Zones_RequestPurchase", nextZone.id)
    if not alive or not enabled.zoneBuy then return end
    notes.buy = ok == true and "accepted: " .. nextZone.id or tostring(message or "rejected")
    if ok == true then nextAt.buy = os.clock() + CFG.BuyInterval; nextAt.save = 0 end
end

local function goalFull(goal)
    return type(goal) == "table" and type(goal.Progress) == "number"
        and type(goal.Amount) == "number" and goal.Progress >= goal.Amount
end

local function goalLocked(definition, goals, index)
    local function requiresPrevious(at)
        return at > 1 and (definition.SequentialGoals == true or
            (type(goals[at]) == "table" and goals[at].RequiresPrevious == true))
    end
    if not requiresPrevious(index) then return false end
    for previous = index - 1, 1, -1 do
        if not goalFull(goals[previous]) or goals[previous].Claimed ~= true then return true end
        if not requiresPrevious(previous) then return false end
    end
    return false
end

local function claimTarget(definition, goals)
    if type(goals) ~= "table" then return nil end
    local allFull = #goals == 3
    for index = 1, 3 do
        local goal = goals[index]
        if not goalFull(goal) then allFull = false end
        if definition.PerGoalClaim == true then
            if goalFull(goal) and goal.Claimed ~= true and not goalLocked(definition, goals, index) then return index end
            if not goal or goal.Claimed ~= true then allFull = false end
        end
    end
    return allFull and 0 or nil
end

local function questTick()
    local save = getSave()
    if not save then notes.quest = "waiting for profile"; return end
    if type(save.DailyQuests) == "table" and save.DailyQuests.ActiveCard == nil then
        pcall(invoke, "Daily Quests: Select Card", 1)
    end
    if type(save.NPCQuests) ~= "table" then notes.quest = "waiting for quests"; return end
    local ids = {}
    for id in pairs(save.NPCQuests) do if type(id) == "string" then ids[#ids + 1] = id end end
    table.sort(ids)
    local sent, now = 0, os.clock()
    notes.quest = "no completed claimable quests"
    for _, id in ipairs(ids) do
        if not alive or not enabled.autoQuest or sent >= CFG.QuestMaxRequests then return end
        local data, definition = save.NPCQuests[id], questDirs[id]
        if type(data) == "table" and data.Completed ~= true then
            local goals = data.Quests
            if type(goals) == "table" and next(goals) ~= nil then assignedQuests[id] = nil
            elseif assignedQuests[id] and assignedQuests[id].save == save then goals = assignedQuests[id].goals end
            if not definition then
                notes.quest = "waiting for NPC directory: " .. id
            elseif type(goals) ~= "table" or next(goals) == nil then
                if now >= (nextAt.ensure[id] or 0) then
                    nextAt.ensure[id] = now + CFG.EnsureBackoff
                    sent += 1
                    local ok, message = invokeWithCompletion("NPC Quests: Ensure", function(result)
                        if result[1] and result[2] == true and type(result[3]) == "table" then
                            assignedQuests[id] = {save = save, goals = result[3], reward = result[4]}
                        end
                    end, id)
                    if not alive or not enabled.autoQuest then return end
                    notes.quest = ok == true and "assignment received: " .. id or tostring(message or "assignment rejected")
                    nextAt.save = 0
                end
            elseif now >= (nextAt.quest[id] or 0) then
                local index = claimTarget(definition, goals)
                if index ~= nil then
                    nextAt.quest[id] = now + CFG.QuestBackoff
                    sent += 1
                    local ok, message
                    if index == 0 then ok, message = invoke("NPC Quests: Redeem", id)
                    else ok, message = invoke("NPC Quests: Redeem", id, index) end
                    if not alive or not enabled.autoQuest then return end
                    notes.quest = ok == true and "claimed: " .. id or tostring(message or "claim rejected")
                    if ok == true then nextAt.save = 0 end
                end
            end
        end
    end
end

local function claimRankRewards(onlyIndex)
    if not alive then return false, "stopped" end
    if os.clock() < nextAt.rank then return false, "rank claim cooldown" end
    nextAt.rank = os.clock() + CFG.RankInterval
    local ok, message = fire("Ranks_ClaimAll")
    if not ok and onlyIndex ~= nil then
        local index = onlyIndex
        local single, singleMessage = fire("Ranks_ClaimReward", index)
        if single then ok, message = single, singleMessage end
    end
    notes.rank = ok and "claim request sent" or message
    if ok then nextAt.save = 0 end
    return ok, message
end

local function rankTick()
    if os.clock() < nextAt.rank then return end
    local save = getSave()
    if not save then claimRankRewards(); return end
    local redeemed = save.RedeemedRankRewards
    if type(redeemed) ~= "table" then notes.rank = "waiting for reward state"; return end
    local stars = tonumber(save.RankStars) or 0
    local definition = ranks[save.Rank]
    if not definition then
        claimRankRewards()
        return
    end
    local order = {}
    for index, reward in pairs(definition.Rewards or {}) do
        local numeric = tonumber(index)
        if numeric and type(reward) == "table" then
            order[#order + 1] = {index = index, numeric = numeric, need = tonumber(reward.StarsRequired)}
        end
    end
    table.sort(order, function(a, b) return a.numeric < b.numeric end)
    local total, claimable = 0, nil
    for _, entry in ipairs(order) do
        if not entry.need then notes.rank = "invalid reward definition"; return end
        total += entry.need
        if stars >= total and redeemed[tostring(entry.index)] == nil then claimable = entry.index; break end
    end
    if claimable == nil then
        notes.rank = ("nothing earned (rank %s, %d stars)"):format(tostring(save.Rank), stars)
        return
    end
    claimRankRewards(claimable)
end

local function rebirthTick()
    local now = os.clock()
    if now < nextAt.rebirth then return end
    local save = getSave()
    if not save then notes.rebirth = "waiting for profile"; return end
    local definition = rebirths[save.Rebirths + 1]
    if not definition then notes.rebirth = "next rebirth unavailable"; return end
    local best = maxOwned(save)
    if not best or best < definition.ZoneNumberRequired then
        notes.rebirth = "requires zone " .. tostring(definition.ZoneNumberRequired)
        return
    end
    nextAt.rebirth = now + CFG.RebirthInterval
    local id = tostring(definition.RebirthNumber)
    local ok, message = invoke("Rebirth_Request", id)
    if not alive or not enabled.autoRebirth then return end
    notes.rebirth = ok == true and "accepted: " .. id or tostring(message or "rejected")
    if ok == true then nextAt.save = 0 end
end

local function findEggModel(targetEggId, point)
    local targetNum
    for num, id in pairs(eggByNumber) do
        if id == targetEggId then targetNum = num; break end
    end
    local best, bestNumber, bestDistance
    for _, folderName in ipairs({"ZoneEggs", "Eggs", "CustomEggs"}) do
        local root = thingsFolder(folderName)
        if root then
            local queue, cursor, visited = {root}, 1, 0
            while cursor <= #queue and visited < CFG.BreakableScanCap do
                local parent = queue[cursor]
                local ok, children = pcall(function() return parent:GetChildren() end)
                cursor += 1
                visited += 1
                if ok then
                    for _, child in ipairs(children) do
                        visited += 1
                        if child:IsA("Model") or child:IsA("Folder") then
                            local number = tonumber(child.Name:match("^(%d+)"))
                            local at = modelPosition(child)
                            if at then
                                if targetEggId and (child.Name == targetEggId or (targetNum and number == targetNum) or child.Name:find(targetEggId, 1, true)) then
                                    return child, number or targetNum, at
                                end
                                if number and point then
                                    local distance = (at - point).Magnitude
                                    if distance <= CFG.EggRange and (not bestDistance or distance < bestDistance) then
                                        best, bestNumber, bestDistance = child, number, distance
                                    end
                                end
                            end
                            queue[#queue + 1] = child
                        end
                    end
                end
                if visited % 500 == 0 then task.wait() end
            end
        end
    end
    return best, bestNumber, best and modelPosition(best) or nil
end

local function hatchEggById(eggId, count, snapNear)
    if type(eggId) ~= "string" or #eggId == 0 then return false, "invalid egg id" end
    local save = getSave()
    local hatchCount = math.clamp(tonumber(count) or (save and tonumber(save.EggHatchCount)) or 1, 1, CFG.EggMaxHatch)
    local point = position()
    local _, _, eggPos = findEggModel(eggId, point)
    if snapNear and eggPos and point and (eggPos - point).Magnitude > 30 then
        snapTo(eggPos + Vector3.new(0, 0, 6))
        task.wait(0.1)
    end
    local ok, message = invoke("Eggs_RequestPurchase", eggId, hatchCount)
    return ok == true, ok == true and ("opened %s x%d"):format(eggId, hatchCount) or tostring(message or "rejected")
end

local function eggTick()
    local now = os.clock()
    if now < nextAt.egg then return end
    local save = getSave()
    if not save then notes.egg = "waiting for profile"; return end
    local point = position()
    if not point then notes.egg = "waiting for character"; return end
    local chosenEgg
    for id, active in pairs(picked.eggs) do
        if active then chosenEgg = id; break end
    end
    if not chosenEgg then
        local _, number = findEggModel(nil, point)
        if number then
            chosenEgg = eggByNumber[number]
        end
    end
    if not chosenEgg and type(save.MaximumAvailableEgg) == "number" then
        chosenEgg = eggByNumber[save.MaximumAvailableEgg]
    end
    if not chosenEgg then notes.egg = "no egg in range or selected"; return end
    nextAt.egg = now + CFG.EggInterval
    local ok, msg = hatchEggById(chosenEgg, save.EggHatchCount, pickCount(picked.eggs) > 0)
    if not alive or not enabled.autoEgg then return end
    notes.egg = msg
end

-- Detects which World (1-4) the current server Place holds.
local function currentWorldNumber()
    for w = CFG.WorldCount, 2, -1 do
        if workspace:FindFirstChild("Map" .. w) then return w end
    end
    if workspace:FindFirstChild("Map") then return 1 end
    local pid = game.PlaceId
    if pid == 140403681187145 then return 4 end
    if pid == 17503543197 then return 3 end
    if pid == 16498369169 then return 2 end
    return 1
end

local function bestUnlockedWorld(save)
    local here = currentWorldNumber()
    local best = maxOwned(save) or 1
    local reb = save and tonumber(save.Rebirths) or 0
    local calc = 1
    if best >= (CFG.WorldFirst[4] or 240) or (best >= 239 and reb >= 8) then calc = 4
    elseif best >= (CFG.WorldFirst[3] or 200) or (best >= 199 and reb >= 8) then calc = 3
    elseif best >= (CFG.WorldFirst[2] or 100) or (best >= 99 and reb >= 4) then calc = 2 end
    return math.max(here, calc)
end

local function teleportToWorldOrBestIsland(targetW)
    local save = getSave()
    local hereWorld = currentWorldNumber()
    local desiredWorld = tonumber(targetW) or (save and bestUnlockedWorld(save)) or math.max(worldTarget, hereWorld)
    desiredWorld = math.clamp(math.floor(desiredWorld), 1, CFG.WorldCount)
    -- Never auto-downgrade or auto-tele back to World 1 when already in a higher world.
    if desiredWorld < hereWorld then
        desiredWorld = hereWorld
    end
    worldTarget = desiredWorld
    if hereWorld ~= desiredWorld and desiredWorld >= 1 and desiredWorld <= CFG.WorldCount then
        local remoteName = "World" .. tostring(desiredWorld) .. "Teleport"
        local ok, message = invoke(remoteName)
        return ok == true, ok == true and ("switching to World " .. desiredWorld) or tostring(message or ("invoke " .. remoteName .. " failed"))
    end
    local number = bestInWorld(save, desiredWorld)
    if not number or not zones[number] then
        return false, "world " .. desiredWorld .. " zone map unavailable"
    end
    local id = zones[number].id
    return teleportToIslandMiddle(id)
end

local function worldTeleTick()
    local now = os.clock()
    if now < nextAt.worldTele then return end
    local save = getSave()
    if not save then notes.world = "waiting for profile"; return end
    local hereWorld = currentWorldNumber()
    if worldTarget < hereWorld then
        worldTarget = hereWorld
    end
    if enabled.worldAdvance then
        worldTarget = math.max(hereWorld, bestUnlockedWorld(save))
    end
    if hereWorld ~= worldTarget and worldTarget > hereWorld then
        nextAt.worldTele = now + CFG.WorldBackoff
        local remoteName = "World" .. tostring(worldTarget) .. "Teleport"
        local ok, message = invoke(remoteName)
        if not alive or not enabled.worldTele then return end
        notes.world = ok == true and ("teleporting -> World " .. worldTarget) or tostring(message or "world teleport rejected")
        return
    end
    local number = bestInWorld(save, hereWorld)
    if not number then notes.world = "world " .. hereWorld .. " zone map unavailable"; return end
    local id = zones[number].id
    local centre = zoneCenter(id)
    local pos = position()
    local dist2D = (pos and centre) and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(centre.X, 0, centre.Z)).Magnitude or math.huge
    if currentZone() == id and dist2D <= 18 then
        notes.world = ("in world %d middle (%s)"):format(hereWorld, id)
        return
    end
    nextAt.worldTele = now + CFG.WorldInterval
    local ok, message = teleportToIslandMiddle(id)
    notes.world = ok and ("world %d -> middle of %s"):format(hereWorld, id) or tostring(message)
end

CFG.AdvanceTick = function()
    local now = os.clock()
    if now < (CFG.AdvanceNext or 0) then return end
    local save = getSave()
    if not save then notes.advance = "waiting for profile"; return end
    local hereWorld = currentWorldNumber()
    local limit = math.min(CFG.WorldAdvanceLimit, CFG.WorldCount)
    local bestW = math.max(hereWorld, math.min(bestUnlockedWorld(save), limit))
    if bestW <= hereWorld then
        worldTarget = hereWorld
        notes.advance = ("at world %d (owned zone %d)"):format(hereWorld, maxOwned(save) or 1)
        return
    end
    CFG.AdvanceNext = now + CFG.WorldAdvanceInterval
    worldTarget = bestW
    local ok, msg = teleportToWorldOrBestIsland(bestW)
    notes.advance = ok and ("hopping -> world " .. bestW) or tostring(msg)
end

local EFFECT_CLASSES = {
    ParticleEmitter = true, Trail = true, Beam = true, Smoke = true,
    Fire = true, Sparkles = true, PointLight = true, SpotLight = true, SurfaceLight = true,
}
local function suppressEffects(folderName, store)
    local root = thingsFolder(folderName)
    if not root then return 0 end
    local queue, cursor, visited, changed = {root}, 1, 0, 0
    while cursor <= #queue and visited < CFG.OptimizeCap do
        local parent = queue[cursor]
        local ok, children = pcall(function() return parent:GetChildren() end)
        cursor += 1
        visited += 1
        if ok then
            for _, child in ipairs(children) do
                visited += 1
                if EFFECT_CLASSES[child.ClassName] then
                    if store[child] == nil then
                        store[child] = child.Enabled
                        local disabled = pcall(function() child.Enabled = false end)
                        if disabled then changed += 1 end
                    end
                elseif child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart") then
                    queue[#queue + 1] = child
                end
            end
        end
        if visited % 500 == 0 then task.wait() end
    end
    return changed
end

local function restoreEffects(store)
    for effect, original in pairs(store) do
        pcall(function() effect.Enabled = original end)
    end
    table.clear(store)
end

local function eggFolderNames()
    local names, seen = {}, {}
    for _, rootName in ipairs({"__THINGS", "_THINGS", "THINGS"}) do
        local root = workspace:FindFirstChild(rootName)
        if root then
            local ok, children = pcall(function() return root:GetChildren() end)
            if ok then
                for _, child in ipairs(children) do
                    local name = tostring(child.Name)
                    if not seen[name] and string.find(string.lower(name), "egg", 1, true) then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end
            end
        end
    end
    return names
end

-- Item 4: True Hidden Egg Effect. Hooks PlayEggAnimation / PlayNormalEggAnimation
-- in Egg Opening Frontend so the 3D camera cutscene is bypassed in 0ms while
-- Eggs_PlayOpenAnimation still runs SM_Unmask and CompletedHatching cleanly.
CFG.EggFxState = {senv = nil, originals = {}}
local function syncEggFx()
    local state = CFG.EggFxState
    local active = alive and enabled.hideEggFx
    pcall(function() workspace:SetAttribute("GlobalInstantHatch", active and true or nil) end)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local eggGui = pg and pg:FindFirstChild("EggOpenAnimation")
    if eggGui and eggGui:IsA("LayerCollector") then
        pcall(function() eggGui.Enabled = not active end)
    end
    local lighting = game:GetService("Lighting")
    for _, fxName in ipairs({"EggOpeningDepthOfField", "EggOpenBloom"}) do
        local fx = lighting:FindFirstChild(fxName)
        if fx and fx:IsA("PostEffect") then
            pcall(function() fx.Enabled = not active end)
        end
    end
    if active then
        local cam = workspace.CurrentCamera
        if cam then
            for _, modelName in ipairs({"Eggs", "Pets"}) do
                local leftover = cam:FindFirstChild(modelName)
                if leftover then pcall(function() leftover:Destroy() end) end
            end
        end
        local senvReader = getsenv or env.getsenv
        if type(senvReader) == "function" and not state.senv then
            local ps = LocalPlayer:FindFirstChild("PlayerScripts")
            local frontend = ps and ps:FindFirstChild("Egg Opening Frontend", true)
            if frontend then
                local ok, senv = pcall(senvReader, frontend)
                if ok and type(senv) == "table" then
                    state.senv = senv
                    for _, fnName in ipairs({"PlayEggAnimation", "PlayNormalEggAnimation", "PlayTowerDefenseAnimations"}) do
                        local orig = rawget(senv, fnName)
                        if type(orig) == "function" then
                            state.originals[fnName] = orig
                            senv[fnName] = function(...)
                                if alive and enabled.hideEggFx then
                                    if type(rawget(senv, "ToggleCoreUI")) == "function" then
                                        pcall(senv.ToggleCoreUI, true)
                                    end
                                    return
                                end
                                return orig(...)
                            end
                        end
                    end
                end
            end
        end
    elseif state.senv then
        for fnName, orig in pairs(state.originals) do
            pcall(function() state.senv[fnName] = orig end)
        end
        table.clear(state.originals)
        state.senv = nil
    end
end

local function optimizeTick()
    local changed = 0
    if enabled.optBreakables then changed += suppressEffects("Breakables", optBreakableEffects) end
    if enabled.optPets then changed += suppressEffects("Pets", optPetEffects) end
    syncEggFx()
    if enabled.hideEggFx then
        for _, name in ipairs(eggFolderNames()) do
            changed += suppressEffects(name, optPetEffects)
        end
        changed += suppressEffects("Eggs", optPetEffects)
        changed += suppressEffects("ZoneEggs", optPetEffects)
    end
    notes.optimize = ("breakables %s | pets %s | eggFx %s | +%d"):format(
        enabled.optBreakables and "on" or "off",
        enabled.optPets and "on" or "off",
        enabled.hideEggFx and "hidden" or "normal",
        changed)
end

local function destroyAuraPart()
    if auraPart then pcall(function() auraPart:Destroy() end); auraPart = nil end
end

local function ensureAuraPart()
    if auraPart then return end
    local ok, part = pcall(function()
        local p = Instance.new("Part")
        p.Name = "PS99CLEAN_Aura"
        p.Anchored, p.CanCollide, p.CastShadow = true, false, false
        p.Shape = Enum.PartType.Cylinder
        p.Size = Vector3.new(0.3, CFG.TapRange * 2, CFG.TapRange * 2)
        p.Color = Color3.fromRGB(120, 220, 170)
        p.Transparency = 0.75
        p.Orientation = Vector3.new(0, 0, 90)
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Parent = workspace
        return p
    end)
    if ok then auraPart = part else warn("[PS99 CLEAN] aura visualizer: " .. tostring(part)) end
end

local function setWorldTarget(n)
    if type(n) ~= "number" or n < 1 or n > CFG.WorldCount then return false end
    worldTarget = math.floor(n)
    if enabled.worldTele then nextAt.worldTele = 0 end
    return true
end

local function petSlotTick()
    local now = os.clock()
    if now < nextAt.petSlot then return end
    local save = getSave()
    if not save then notes.petSlot = "waiting for profile"; return end
    local purchased = type(save.PetSlotsPurchased) == "number" and save.PetSlotsPurchased or 0
    local slot = purchased + 1
    if slot > CFG.PetSlotMax then notes.petSlot = "slot cap reached (" .. CFG.PetSlotMax .. ")"; return end
    local rankDef = ranks[save.Rank]
    if type(rankDef) == "table" and type(rankDef.UnlockablePetSlots) == "number" and purchased >= rankDef.UnlockablePetSlots then
        notes.petSlot = ("rank %s pet slot cap (%d)"):format(tostring(save.Rank), purchased)
        nextAt.petSlot = now + CFG.PetSlotBackoff
        return
    end
    nextAt.petSlot = now + CFG.PetSlotBackoff
    local ok, message = invoke("EquipSlotsMachine_RequestPurchase", slot)
    if not alive or not enabled.autoBuyPetSlots then return end
    notes.petSlot = ok == true and ("bought pet slot " .. slot) or tostring(message or "rejected")
    if ok == true then nextAt.petSlot = os.clock() + CFG.PetSlotInterval; nextAt.save = 0 end
end

CFG.EggSlotBundles = nil
local function nextEggSlotEnd(purchased)
    if not CFG.EggSlotBundles then
        local bundles, cur, total = {}, 1, 83
        while cur <= total do
            local size = (cur <= 10 and 1) or (cur <= 30 and 2) or 3
            local endSlot = math.min(cur + size - 1, total)
            bundles[#bundles + 1] = { Start = cur, End = endSlot }
            cur = endSlot + 1
        end
        CFG.EggSlotBundles = bundles
    end
    for _, b in ipairs(CFG.EggSlotBundles) do
        if purchased < b.End then
            return b.End
        end
    end
    return nil
end

function CFG.EggSlotTick()
    local now = os.clock()
    if now < nextAt.eggSlot then return end
    local save = getSave()
    if not save then notes.eggSlot = "waiting for profile"; return end
    local purchased = type(save.EggSlotsPurchased) == "number" and save.EggSlotsPurchased or 0
    local targetEnd = nextEggSlotEnd(purchased)
    if not targetEnd then notes.eggSlot = "max egg slots purchased"; nextAt.eggSlot = now + 30; return end
    nextAt.eggSlot = now + CFG.EggSlotBackoff
    local ok, message = invoke("EggHatchSlotsMachine_RequestPurchase", targetEnd)
    if not alive or not enabled.autoBuyEggSlots then return end
    notes.eggSlot = ok == true and ("bought egg bundle -> " .. targetEnd) or tostring(message or "rejected")
    if ok == true then nextAt.eggSlot = os.clock() + CFG.EggSlotInterval; nextAt.save = 0 end
end

function CFG.ForeverPackTick()
    local now = os.clock()
    if now < nextAt.foreverPack then return end
    local save = getSave()
    if not save then notes.foreverPack = "waiting for profile"; return end
    local fpCmds = modules.foreverPack
    local state = nil
    if fpCmds and type(fpCmds.GetState) == "function" then
        local okSt, st = pcall(fpCmds.GetState, "Default")
        if okSt and type(st) == "table" then state = st end
    end
    if not state and type(save.ForeverPacks) == "table" then
        state = save.ForeverPacks.Default or save.ForeverPacks
    end
    if type(state) == "table" and type(state.Slots) == "table" then
        local idx = (tonumber(state.Slot) or 0) + 1
        local slot = state.Slots[idx]
        if type(slot) == "table" and slot.Price and not slot.Free and not slot.Credit then
            notes.foreverPack = "next slot costs Robux (paused)"
            nextAt.foreverPack = now + CFG.ForeverPackInterval
            return
        end
    end
    nextAt.foreverPack = now + CFG.ForeverPackInterval
    local ok, message = invoke("ForeverPacks: Claim Free", "Default")
    if not alive or not enabled.autoForeverPack then return end
    notes.foreverPack = ok == true and "claimed forever free pack" or tostring(message or "none available")
    if ok == true then nextAt.foreverPack = os.clock() + 3; nextAt.save = 0 end
end

function CFG.UpgradeTick()
    local now = os.clock()
    if now < nextAt.upgrade then return end
    local save = getSave()
    if not save then notes.upgrade = "waiting for profile"; return end
    local upCmds = modules.upgrades
    if not upCmds or type(upCmds.All) ~= "function" then
        if not CFG.BootstrapDone then CFG.BootstrapModules() end
        upCmds = modules.upgrades
    end
    if not upCmds or type(upCmds.All) ~= "function" then
        notes.upgrade = "waiting for UpgradeCmds"
        nextAt.upgrade = now + CFG.UpgradeInterval
        return
    end
    local okList, list = pcall(upCmds.All)
    if not okList or type(list) ~= "table" then
        notes.upgrade = "upgrade list unavailable"
        nextAt.upgrade = now + CFG.UpgradeInterval
        return
    end
    for _, up in ipairs(list) do
        if not alive or not enabled.autoBuyUpgrades then return end
        local uid, zid = up.UpgradeID, up.ZoneID
        if uid and zid and save.UnlockedZones[zid] == true then
            local already = type(upCmds.Owns) == "function" and upCmds.Owns(uid, zid) == true
            if not already then
                nextAt.upgrade = now + 1.5
                local ok, message = invoke("Upgrades_Purchase", uid, zid)
                if not alive or not enabled.autoBuyUpgrades then return end
                if ok == true then
                    notes.upgrade = ("bought %s (%s)"):format(uid, zid)
                    nextAt.save = 0
                    return
                else
                    notes.upgrade = ("%s (%s): %s"):format(uid, zid, tostring(message or "cannot afford"))
                end
            end
        end
    end
    nextAt.upgrade = now + CFG.UpgradeInterval
    notes.upgrade = "all unlocked player upgrades owned"
end

local function serverClock()
    local ok, value = pcall(function() return workspace:GetServerTimeNow() end)
    if ok and type(value) == "number" then return value end
    if type(os.time) == "function" then return os.time() end
    return 0
end

local function inventory(save, kind)
    local inv = save and rawget(save, "Inventory")
    local bucket = type(inv) == "table" and rawget(inv, kind)
    return type(bucket) == "table" and bucket or nil
end

-- Stack items in a save bucket: {uid = id, amount = n, tier = tn, data = raw}.
local function stackList(bucket)
    local out = {}
    if not bucket then return out end
    for uid, data in pairs(bucket) do
        if type(data) == "table" and type(data.id) == "string" then
            out[#out + 1] = {
                uid = uid,
                id = data.id,
                amount = tonumber(data._am) or 1,
                tier = tonumber(data.tn) or 1,
                data = data,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.id == b.id then
            if a.tier ~= b.tier then return a.tier > b.tier end
            return tostring(a.uid) < tostring(b.uid)
        end
        return a.id < b.id
    end)
    return out
end

local KEY_PAIRS = {
    {name = "CrystalKey_Combine", lower = "Crystal Key Lower Half", upper = "Crystal Key Upper Half"},
    {name = "TechKey_Combine", lower = "Tech Key Lower Half", upper = "Tech Key Upper Half"},
    {name = "VoidKey_Combine", lower = "Void Key Lower Half", upper = "Void Key Upper Half"},
    {name = "FantasyKey_Combine", lower = "Fantasy Key Lower Half", upper = "Fantasy Key Upper Half"},
    {name = "MVPKey_Combine", lower = "MVP Key Lower Half", upper = "MVP Key Upper Half"},
    {name = "SecretKey_Combine", lower = "Secret Key Lower Half", upper = "Secret Key Upper Half"},
    {name = "TreasureHideout_Combine", lower = "Treasure Hideout Key Lower Half", upper = "Treasure Hideout Key Upper Half"},
    {name = "TN_Bind", lower = "Fiesta Key Lower Half", upper = "Fiesta Key Upper Half"},
    {name = "MW_Reduce", lower = "Fiesta Boss Key Lower Half", upper = "Fiesta Boss Key Upper Half"},
    {name = "PrisonKey_Combine", lower = "Prison Key"},
}

local BAG_KINDS = {
    "Gift Bag", "Large Gift Bag", "Seed Bag", "Diamond Gift Bag",
    "Fruit Bundle", "Potion Bundle", "Large Potion Bundle",
    "Enchant Bundle", "Large Enchant Bundle", "Flag Bundle",
    "Toy Bundle", "Mini Chest", "Rainbow Mini Chest", "Charm Stone",
    "2024 Anniversary Gift", "2024 Gargantuan Christmas Present", "2024 Large Christmas Present",
    "2024 Medium Christmas Present", "2024 Small Christmas Present", "2024 New Years Gift",
    "2025 New Years Gift", "2026 New Years Gift", "Adoption Gift", "Adventurer Lootbox",
    "Anime Pack", "Arcade Gift", "Autumn Gift", "Axolotl Pack", "Basketball Gift", "BIG Pack",
    "Blood Moon Gift", "Blossom Gift", "Buff Gym Gift", "Candy Corn Gift", "Candycane Gift",
    "Clan Gift", "Clan Gift 2", "Color Gift", "Cosmic Basketball Gift", "Deep Sea Treasure Chest",
    "Dino Gift", "Doodle Gift", "Elemental Gift", "Evil Gift", "Fantasy Pack", "Fiesta Gift",
    "Flannel Gift", "Ghostface Gift", "Ghostly Pack", "Glitched Gift", "Global Event Gift",
    "Good Gift", "Good vs Evil Gift", "Graffiti Gift", "Gym Gift", "Halloween Lucky Block Gift",
    "Hellfire Gift", "Horseshoe Gift", "Huge Easter Gift", "Hype Egg", "Hype Egg 2", "Hype Egg 3",
    "Jolly Gift", "Large Christmas Present", "Large Fantasy Present", "Love Gift", "Lucky Admin Gift",
    "Lucky Block Gift", "Lucky Gift", "Marble Gift", "Medium Christmas Present", "Medium Fantasy Present",
    "Mega Boost Chest", "Mega Charm Chest", "Mega Enchant Chest", "Mega Potion Chest", "Mega Ultimate Chest",
    "Meme Pack", "Meteor Gift", "Midnight Gift", "Nightmare Pack", "Ninja Pack", "Obsidian Gift",
    "Pet Games Gift", "Pog Pack", "Pumpkin Gift", "Rave Gift", "Retro Pack", "Santa Gift",
    "School Gift", "Slime Gift", "Small Christmas Present", "Small Fantasy Present", "Snowflake Gift",
    "Soccer Gift", "Space Mine Gift", "Spider Gift", "Summer Gift", "Sun Angelus Gift", "Sunflower Gift",
    "Super Hero Pack", "Time Trial Gift", "Time Trial Gift 2", "Titanic Christmas Present",
    "Titanic Easter Gift", "Titanic Fantasy Present", "Tower Defense Gift", "Tower Defense Gift 2",
    "Tower Defense Gift 3", "Tropical Gift", "Turkey Gift", "Wooden Gift", "World Cup Gift",
}

local FLAG_NAMES = {
    "Coins Flag", "Diamonds Flag", "Exotic Treasure Flag", "Fortune Flag",
    "Golden Flag", "Hasty Flag", "Magnet Flag", "Rainbow Flag",
    "Shiny Flag", "Strength Flag",
}

local FRUIT_IDS = {"Apple", "Banana", "Candycane", "Orange", "Pineapple", "Rainbow", "Watermelon"}
local POTION_IDS = {
    "Coins", "Damage", "Diamonds", "Huge", "Lucky",
    "The Cocktail", "Treasure Hunter", "Walkspeed",
    "Garden XP Token", "Mastery", "Pet XP Token", "Recipe",
    "Titanic", "Tower Defense I", "Tower Defense II", "Tower Defense III",
    "Ultimate", "Ultra Huge", "Ultra Mastery", "Ultra Titanic",
}
local XP_POTION_SET = {
    ["Garden XP Token"] = true, ["Mastery"] = true, ["Pet XP Token"] = true,
    ["Recipe"] = true, ["Titanic"] = true, ["Tower Defense I"] = true,
    ["Tower Defense II"] = true, ["Tower Defense III"] = true, ["Ultimate"] = true,
    ["Ultra Huge"] = true, ["Ultra Mastery"] = true, ["Ultra Titanic"] = true,
}
local DICE_IDS = {
    "Lucky Dice V2", "Lucky Dice II V2", "Lucky Dice III V2",
    "Mega Lucky Dice V2", "Mega Lucky Dice II V2", "Fire Dice V2",
}
local MEGA_DICE = {["Mega Lucky Dice V2"] = true, ["Mega Lucky Dice II V2"] = true}
local FREE_GIFT_MAX = 12

-- Dynamic & static full-game catalog (Item 8: All Items, Potions, Huges, Eggs, Islands).
CFG.Catalog = {
    scanned = false,
    islands = {},
    potions = table.clone(POTION_IDS),
    fruits = table.clone(FRUIT_IDS),
    flags = table.clone(FLAG_NAMES),
    bags = table.clone(BAG_KINDS),
    eggs = table.clone(CFG.EggIndex),
    huges = {
        "Huge Cat", "Huge Dog", "Huge Dragon", "Huge Corgi", "Huge Pegasus", "Huge Festive Cat",
        "Huge Pumpkin Cat", "Huge Santa Paws", "Huge Gargoyle Dragon", "Huge Forest Wyvern",
        "Huge Hacked Cat", "Huge Pixel Cat", "Huge Cupcake", "Huge Lucky Cat", "Huge Hell Rock",
        "Huge Peacock", "Huge Nightmare Spirit", "Huge Rainbow Unicorn", "Huge Abyssal Jellyfish",
        "Huge Happy Rock", "HugeHappyComputer", "Huge Red Wolf", "Huge Golden Dragon", "Huge Kitsune Fox",
        "Titanic Cat", "Titanic Hubert", "Titanic Balloon Monkey", "Titanic Neon Agony",
        "Titanic Dominus Astra", "Titanic Red Dragon", "Titanic Kitsune Fox", "Titanic Sun Angelus",
        "Titanic Yin-Yang Grim Reaper", "Gargantuan Cat", "Gargantuan Angelus", "Gargantuan Dark Dragon",
        "Gargantuan Doge", "Gargantuan Grim Reaper", "Gargantuan Hypnotic Kitsune", "Gargantuan Nyan Cat",
        "Gargantuan Santa Paws", "Gargantuan Super Cat",
    },
    items = {
        "Basic Coin Jar", "Giant Coin Jar", "Basic Item Jar", "Comet", "Pinata", "Lucky Block",
        "Crystal Key", "Crystal Key Lower Half", "Crystal Key Upper Half",
        "Tech Key", "Tech Key Lower Half", "Tech Key Upper Half",
        "Void Key", "Void Key Lower Half", "Void Key Upper Half",
        "Fantasy Key", "Fantasy Key Lower Half", "Fantasy Key Upper Half",
        "Secret Key", "Secret Key Lower Half", "Secret Key Upper Half",
        "Treasure Hideout Key", "MVP Key", "Prison Key", "Golden Prison Key",
        "Spinny Wheel Ticket", "Tech Spinny Wheel Ticket", "Void Spinny Wheel Ticket", "Fantasy Spinny Wheel Ticket",
        "Daycare Slot Voucher", "Exclusive Daycare Slot Voucher", "Clan Voucher", "Booth Slot Voucher",
        "Charm Stone", "Charm Chisel", "Charm Hammer", "Bucket O' Magic", "Super Magnet",
        "Breakable Sprinkler", "Glitch Drive", "overload", "Royalty", "Diamond Gift Bag",
        "Gift Bag", "Large Gift Bag", "Mini Chest", "Rainbow Mini Chest", "Seed Bag",
        "Fruit Bundle", "Potion Bundle", "Large Potion Bundle", "Enchant Bundle", "Large Enchant Bundle",
        "Flag Bundle", "Toy Bundle",
    },
}

local function scanLiveDirectory()
    local cat = CFG.Catalog
    if #cat.islands == 0 then
        for num = 1, 279 do
            if zones[num] then cat.islands[#cat.islands + 1] = zones[num].id end
        end
    end
    local dirRoot = RS:FindFirstChild("__DIRECTORY") or workspace:FindFirstChild("__DIRECTORY")
    if not dirRoot or cat.scanned then return cat end
    cat.scanned = true
    local function collectNames(folder, dest, alsoSet)
        if not folder then return end
        local seen = {}
        for _, v in ipairs(dest) do seen[v] = true end
        local ok, desc = pcall(folder.GetDescendants, folder)
        if not ok then return end
        for _, child in ipairs(desc) do
            if child:IsA("ModuleScript") then
                local id = child.Name:gsub("^(.-)%s*|%s*", ""):match("^%s*(.-)%s*$")
                if id and #id > 0 and not seen[id] then
                    seen[id] = true
                    dest[#dest + 1] = id
                    if alsoSet then alsoSet[id] = true end
                end
            end
        end
        table.sort(dest)
    end
    collectNames(dirRoot:FindFirstChild("Potions"), cat.potions)
    collectNames(dirRoot:FindFirstChild("XPPotions"), cat.potions, XP_POTION_SET)
    collectNames(dirRoot:FindFirstChild("Fruits"), cat.fruits)
    collectNames(dirRoot:FindFirstChild("ZoneFlags"), cat.flags)
    collectNames(dirRoot:FindFirstChild("Lootboxes"), cat.bags)
    collectNames(dirRoot:FindFirstChild("Eggs"), cat.eggs)
    collectNames(dirRoot:FindFirstChild("MiscItems"), cat.items)
    collectNames(dirRoot:FindFirstChild("Lootboxes"), cat.items)
    collectNames(dirRoot:FindFirstChild("Consumables"), cat.items)
    local petsDir = dirRoot:FindFirstChild("Pets")
    if petsDir then
        collectNames(petsDir:FindFirstChild("Huge"), cat.huges)
        collectNames(petsDir:FindFirstChild("Titanic"), cat.huges)
        collectNames(petsDir:FindFirstChild("Gargantuan"), cat.huges)
    end
    POTION_IDS = cat.potions
    FRUIT_IDS = cat.fruits
    FLAG_NAMES = cat.flags
    BAG_KINDS = cat.bags
    return cat
end

local PICK_CATEGORIES = {
    {"zones", "Zones"}, {"keys", "Keys"}, {"bags", "Bags"}, {"fruits", "Fruits"},
    {"potions", "Potions"}, {"flags", "Flags"}, {"dice", "Dice"},
    {"cards", "Cards"}, {"freeGifts", "Gifts"}, {"eggs", "Eggs"},
    {"huges", "Huges"}, {"items", "Items"}, {"tickets", "Tickets"},
}

local function pickItems(category)
    local cat = scanLiveDirectory()
    local out = {}
    if category == "zones" then
        for num = 1, 279 do
            if zones[num] then out[#out + 1] = zones[num].id end
        end
    elseif category == "keys" then
        for _, pair in ipairs(KEY_PAIRS) do out[#out + 1] = pair.name end
    elseif category == "bags" then
        for _, name in ipairs(cat.bags) do out[#out + 1] = name end
    elseif category == "fruits" then
        for _, id in ipairs(cat.fruits) do out[#out + 1] = id end
    elseif category == "potions" then
        for _, id in ipairs(cat.potions) do out[#out + 1] = id end
    elseif category == "flags" then
        for _, name in ipairs(cat.flags) do out[#out + 1] = name end
    elseif category == "dice" then
        for _, id in ipairs(DICE_IDS) do out[#out + 1] = id end
    elseif category == "freeGifts" then
        for id = 1, FREE_GIFT_MAX do out[#out + 1] = id end
    elseif category == "eggs" then
        for _, id in ipairs(cat.eggs) do out[#out + 1] = id end
    elseif category == "huges" then
        for _, id in ipairs(cat.huges) do out[#out + 1] = id end
    elseif category == "items" then
        for _, id in ipairs(cat.items) do out[#out + 1] = id end
    elseif category == "tickets" then
        for _, name in ipairs({
            "Spinny Wheel Ticket", "Tech Spinny Wheel Ticket", "Void Spinny Wheel Ticket",
            "Fantasy Spinny Wheel Ticket", "Exclusive Raffle Ticket", "Tower Raffle Ticket",
            "Arcade Ticket", "Golden Paw Ticket", "Millionaire Ticket", "Mystery Ticket",
        }) do
            out[#out + 1] = name
        end
    elseif category == "cards" then
        local seen = {}
        for _, card in ipairs(stackList(inventory(getSave(), "Card"))) do
            if not seen[card.id] then seen[card.id] = true; out[#out + 1] = card.id end
        end
    end
    return out
end

local function allowAll(store, id)
    return pickCount(store) == 0 or store[id] == true
end

local KEY_UNLOCKS = {
    {item = "Crystal Key", remote = "CrystalKey_Unlock", pick = "CrystalKey_Combine"},
    {item = "Tech Key", remote = "TechKey_Unlock", pick = "TechKey_Combine"},
    {item = "Void Key", remote = "VoidKey_Unlock", pick = "VoidKey_Combine"},
    {item = "Fantasy Key", remote = "FantasyKey_Unlock", pick = "FantasyKey_Combine"},
    {item = "Secret Key", remote = "SecretKey_Unlock", pick = "SecretKey_Combine"},
    {item = "Prison Key", remote = "PrisonKey_Use", pick = "PrisonKey_Combine"},
}

local function keyTick()
    local now = os.clock()
    if now < nextAt.key then return end
    local save = getSave()
    if not save then notes.keys = "waiting for profile"; return end
    local misc = stackList(inventory(save, "Misc"))
    local halves = {}
    for _, item in ipairs(misc) do halves[item.id] = (halves[item.id] or 0) + item.amount end
    for _, pair in ipairs(KEY_PAIRS) do
        if not alive or not enabled.autoKeys then return end
        local count = halves[pair.lower] or 0
        if pair.upper then count = math.min(count, halves[pair.upper] or 0) end
        if count > 0 and allowAll(picked.keys, pair.name) then
            nextAt.key = now + CFG.KeyInterval
            local ok, message = invoke(pair.name, count)
            if not alive or not enabled.autoKeys then return end
            notes.keys = ok == true and pair.name .. " x" .. count or tostring(message or "rejected")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    for _, unlock in ipairs(KEY_UNLOCKS) do
        if not alive or not enabled.autoKeys then return end
        local have = halves[unlock.item] or 0
        if have > 0 and allowAll(picked.keys, unlock.pick) then
            nextAt.key = now + CFG.KeyInterval
            local ok, message = invoke(unlock.remote)
            if not alive or not enabled.autoKeys then return end
            if ok == true then
                notes.keys = "unlocked " .. unlock.item
                nextAt.save = 0
                return
            end
        end
    end
    notes.keys = "no selected keys to combine or unlock"
end

local MISC_GIFT_BAG_SET = {
    ["Gift Bag"] = true, ["Large Gift Bag"] = true, ["Seed Bag"] = true,
    ["Diamond Gift Bag"] = true, ["Fruit Bundle"] = true, ["Potion Bundle"] = true,
    ["Large Potion Bundle"] = true, ["Enchant Bundle"] = true, ["Large Enchant Bundle"] = true,
    ["Flag Bundle"] = true, ["Toy Bundle"] = true, ["Mini Chest"] = true,
    ["Rainbow Mini Chest"] = true, ["Charm Stone"] = true,
}

local function bagTick()
    local now = os.clock()
    if now < nextAt.bag then return end
    local save = getSave()
    if not save then notes.bags = "waiting for profile"; return end
    scanLiveDirectory()
    -- Lootboxes (Hype Eggs, Anniversary Gifts, Clan Gifts, Packs, etc.) use KX_Release(uid, amount, nil).
    for _, item in ipairs(stackList(inventory(save, "Lootbox"))) do
        if not alive or not enabled.autoGiftBags then return end
        if allowAll(picked.bags, item.id) then
            nextAt.bag = now + CFG.BagInterval
            local amount = math.max(1, math.min(item.amount, CFG.BagMaxOpen))
            local ok, message = invoke("KX_Release", item.uid, amount, nil)
            if not alive or not enabled.autoGiftBags then return end
            if ok == true then
                notes.bags = ("opened lootbox %s x%d"):format(item.id, amount)
                nextAt.save = 0
                return
            end
        end
    end
    -- Misc gift bags & bundles use GiftBag_Open(id, amount).
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if not alive or not enabled.autoGiftBags then return end
        if (MISC_GIFT_BAG_SET[item.id] or picked.bags[item.id]) and allowAll(picked.bags, item.id) then
            nextAt.bag = now + CFG.BagInterval
            local amount = math.max(1, math.min(item.amount, CFG.BagMaxOpen))
            local ok, message = invoke("GiftBag_Open", item.id, amount)
            if not alive or not enabled.autoGiftBags then return end
            if ok == true then
                notes.bags = ("opened %s x%d"):format(item.id, amount)
                nextAt.save = 0
                return
            end
        end
    end
    notes.bags = "no selected bags or lootboxes in inventory"
end

local SPINNY_WHEELS = {
    { id = "StarterWheel", ticket = "Spinny Wheel Ticket",         zone = nil },
    { id = "TechWheel",    ticket = "Tech Spinny Wheel Ticket",    zone = "Tech Spawn",    rebirths = 4 },
    { id = "VoidWheel",    ticket = "Void Spinny Wheel Ticket",    zone = "Void Spawn",    rebirths = 4 },
    { id = "FantasyWheel", ticket = "Fantasy Spinny Wheel Ticket", zone = "Fantasy Spawn", rebirths = 4 },
}

CFG.Spin = { total = 0 }

function CFG.Spin.ClickButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    local fired = false
    if type(firesignal) == "function" then
        for _, sigName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down" }) do
            local ok = pcall(function() firesignal(btn[sigName]) end)
            if ok then fired = true end
        end
    end
    if not fired and type(getconnections) == "function" then
        for _, sigName in ipairs({ "Activated", "MouseButton1Click" }) do
            pcall(function()
                for _, conn in ipairs(getconnections(btn[sigName])) do
                    if type(conn.Fire) == "function" then
                        pcall(conn.Fire, conn)
                        fired = true
                    elseif type(conn.Function) == "function" then
                        pcall(conn.Function)
                        fired = true
                    end
                end
            end)
        end
    end
    return fired
end

function CFG.Spin.ClaimPopup()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local msg = pg and pg:FindFirstChild("Message")
    if not msg or not msg.Enabled then return false end
    local frame = msg:FindFirstChild("Frame")
    local contents = frame and frame:FindFirstChild("Contents")
    local okBtn = contents and contents:FindFirstChild("Ok")
    local closeBtn = frame and frame:FindFirstChild("Close")
    local clicked = false
    if okBtn and okBtn.Visible then
        clicked = CFG.Spin.ClickButton(okBtn) or clicked
    end
    if not clicked and closeBtn and closeBtn.Visible then
        clicked = CFG.Spin.ClickButton(closeBtn) or clicked
    end
    return clicked
end

function CFG.Spin.BypassAndReopen(wheelId)
    local tabCtrl, swCmds = nil, nil
    pcall(function() tabCtrl = require(RS.Library.Client.TabController) end)
    pcall(function() swCmds = require(RS.Library.Client.SpinnyWheelCmds) end)
    -- Trick: closing the SpinnyWheel tab triggers SpinnyWheelCmds's CloseListener
    -- (u120 = true; u119:Disconnect()), immediately skipping the 5s animation + 1s wait.
    if tabCtrl and type(tabCtrl.CloseTab) == "function" then
        for _ = 1, 8 do
            local cur = type(tabCtrl.Get) == "function" and tabCtrl.Get() or nil
            if cur == "SpinnyWheel" then
                pcall(tabCtrl.CloseTab)
                break
            end
            task.wait(0.03)
        end
    end
    -- Auto-click the "You win!" / "Congratulations!" Claim (Ok) popup
    for _ = 1, 10 do
        if CFG.Spin.ClaimPopup() then break end
        task.wait(0.03)
    end
    -- Reopen wheel menu cleanly so the game's client state resets for the next spin
    if swCmds and type(swCmds.Get) == "function" and type(swCmds.Show) == "function" then
        local okW, wheelObj = pcall(swCmds.Get, wheelId)
        if okW and wheelObj then
            pcall(swCmds.Show, wheelObj)
        end
    elseif tabCtrl and type(tabCtrl.OpenTab) == "function" then
        pcall(tabCtrl.OpenTab, "SpinnyWheel")
    end
end

function CFG.Spin.CollectWheels()
    local list = {}
    local seen = {}
    for _, w in ipairs(SPINNY_WHEELS) do
        list[#list + 1] = w
        seen[w.id] = true
    end
    pcall(function()
        local dir = require(RS.Library.Directory.SpinnyWheels)
        if type(dir) == "table" then
            for id, entry in pairs(dir) do
                if not seen[id] and type(entry) == "table" and type(entry.RequiredItem) == "table" then
                    local req = entry.RequiredItem
                    local isMisc = (req._class == "Misc") or (type(req.Class) == "table" and req.Class.Name == "Misc")
                    local ticketId = (type(req.GetId) == "function" and select(2, pcall(req.GetId, req)))
                        or (req._data and req._data.id) or req._id or req.id
                    if isMisc and type(ticketId) == "string" and #ticketId > 0 then
                        list[#list + 1] = {
                            id = tostring(id),
                            ticket = ticketId,
                            zone = entry.ParentType == 1 and entry.ParentId or nil,
                            rebirths = 0,
                        }
                        seen[id] = true
                    end
                end
            end
        end
    end)
    return list
end

local function spinTick()
    local now = os.clock()
    if now < (nextAt.spin or 0) then return end
    CFG.Spin.ClaimPopup()
    local save = getSave()
    if not save then notes.spin = "waiting for profile"; return end
    local misc = stackList(inventory(save, "Misc"))
    local counts = {}
    for _, item in ipairs(misc) do
        counts[item.id] = (counts[item.id] or 0) + item.amount
    end
    local serverNow = workspace:GetServerTimeNow()
    local cooldowns = type(save.SpinnyWheelCooldowns) == "table" and save.SpinnyWheelCooldowns or {}
    local rebirths = tonumber(save.Rebirths) or 0
    local wheels = CFG.Spin.CollectWheels()
    for _, w in ipairs(wheels) do
        if not alive or not enabled.autoSpinTickets then return end
        local unlocked = true
        if w.id == "StarterWheel" then
            unlocked = save.CastleUnlocked == true
        else
            unlocked = rebirths >= (w.rebirths or 0) and (not w.zone or ownsZone(save, w.zone))
        end
        if unlocked then
            local cd = cooldowns[w.id]
            if not cd or cd <= serverNow then
                pcall(fire, "Spinny Wheel: Request Ticket", w.id)
            end
            local have = counts[w.ticket] or 0
            if have > 0 and allowAll(picked.tickets, w.ticket) then
                nextAt.spin = now + 0.15
                local ok = invoke("Spinny Wheel: Request Spin", w.id)
                if not alive or not enabled.autoSpinTickets then return end
                if ok then
                    CFG.Spin.total += 1
                    notes.spin = ("spun %s (#%d, %d left)"):format(w.id, CFG.Spin.total, math.max(0, have - 1))
                    CFG.Spin.BypassAndReopen(w.id)
                    nextAt.save = 0
                    return
                end
            end
        end
    end
    -- Support Raffle tickets when owned & allowed by ticket picker
    for _, raffleTicket in ipairs({ "Exclusive Raffle Ticket", "Tower Raffle Ticket" }) do
        local have = counts[raffleTicket] or 0
        if have > 0 and allowAll(picked.tickets, raffleTicket) then
            nextAt.spin = now + 0.35
            local ok = invoke("Raffle_Submit", math.min(have, 10))
            if ok then
                CFG.Spin.total += 1
                notes.spin = ("submitted %s"):format(raffleTicket)
                nextAt.save = 0
                return
            end
        end
    end
    pcall(function()
        local tabCtrl = require(RS.Library.Client.TabController)
        if tabCtrl and type(tabCtrl.Get) == "function" and tabCtrl.Get() == "SpinnyWheel" then
            tabCtrl.CloseTab()
        end
    end)
    notes.spin = CFG.Spin.total > 0 and ("all tickets spun (" .. CFG.Spin.total .. ")") or "no spinny wheel tickets"
end

local ALL_KEY_CHESTS = {
    { item = "Crystal Key", remote = "CrystalKey_Unlock", batch = true },
    { item = "Tech Key",    remote = "TechKey_Unlock",    batch = true },
    { item = "Void Key",    remote = "VoidKey_Unlock",    batch = true },
    { item = "Fantasy Key", remote = "FantasyKey_Unlock", batch = true },
    { item = "Hacker Key",  remote = "HackerKey_Unlock",  batch = true },
    { item = "Secret Key",  remote = "SecretKey_Unlock",  batch = false },
    { item = "MVP Key",     remote = "MVPKey_Unlock",     batch = true, mvp = true },
}

local function chestTick()
    local now = os.clock()
    if now < (nextAt.chest or 0) then return end
    local save = getSave()
    if not save then notes.chests = "waiting for profile"; return end
    local misc = stackList(inventory(save, "Misc"))
    local counts = {}
    for _, item in ipairs(misc) do
        counts[item.id] = (counts[item.id] or 0) + item.amount
    end
    for _, kc in ipairs(ALL_KEY_CHESTS) do
        if not alive or not enabled.autoOpenChests then return end
        local have = counts[kc.item] or 0
        if have > 0 then
            local canRun = true
            if kc.mvp then
                local subOk, subMod = pcall(function() return require(RS.Library.Client.SubscriptionCmds) end)
                if subOk and type(subMod) == "table" and type(subMod.HasMainSubscription) == "function" then
                    local okH, has = pcall(subMod.HasMainSubscription)
                    canRun = okH and has == true
                end
            end
            if canRun then
                nextAt.chest = now + CFG.KeyInterval
                local amount = kc.batch and math.min(have, 100) or 1
                local ok = kc.batch and invoke(kc.remote, amount) or invoke(kc.remote)
                if not alive or not enabled.autoOpenChests then return end
                if ok == true then
                    notes.chests = ("unlocked %s x%d"):format(kc.item, amount)
                    nextAt.save = 0
                    return
                end
            end
        end
    end
    for _, item in ipairs(stackList(inventory(save, "Lootbox"))) do
        if not alive or not enabled.autoOpenChests then return end
        if tostring(item.id):lower():find("chest", 1, true) then
            nextAt.chest = now + CFG.BagInterval
            local amount = math.max(1, math.min(item.amount, CFG.BagMaxOpen))
            local ok = invoke("KX_Release", item.uid, amount, nil)
            if not alive or not enabled.autoOpenChests then return end
            if ok == true then
                notes.chests = ("opened %s x%d"):format(item.id, amount)
                nextAt.save = 0
                return
            end
        end
    end
    for _, item in ipairs(misc) do
        if not alive or not enabled.autoOpenChests then return end
        if tostring(item.id):lower():find("chest", 1, true) then
            nextAt.chest = now + CFG.BagInterval
            local amount = math.max(1, math.min(item.amount, CFG.BagMaxOpen))
            local ok = invoke("GiftBag_Open", item.id, amount)
            if not alive or not enabled.autoOpenChests then return end
            if ok == true then
                notes.chests = ("opened %s x%d"):format(item.id, amount)
                nextAt.save = 0
                return
            end
        end
    end
    notes.chests = "no chests or keys in inventory"
end

local consumeNext = {Fruit = 0, Potion = 0, potionCooldown = {}}
local function fruitTick()
    local now = os.clock()
    if now < consumeNext.Fruit then return end
    local save = getSave()
    if not save then notes.fruits = "waiting for profile"; return end
    for _, item in ipairs(stackList(inventory(save, "Fruit"))) do
        if not alive or not enabled.autoFruits then return end
        if allowAll(picked.fruits, item.id) then
            consumeNext.Fruit = now + CFG.FruitInterval
            local count = math.max(1, math.min(item.amount, CFG.FruitQueueLimit))
            local ok, message = fire("Fruits: Consume", item.uid, count)
            if not alive then return end
            notes.fruits = ok and ("consumed " .. item.id .. " x" .. count) or tostring(message or "rejected")
            if ok then nextAt.save = 0 end
            return
        end
    end
    notes.fruits = "no selected fruits in inventory"
end

-- Item 5: Select what potion to drink & Drink Highest Tier First (with tier
-- fallback if a high-tier stack is on cooldown or Mastery-gated).
local function potionTick()
    local now = os.clock()
    if now < consumeNext.Potion then return end
    local save = getSave()
    if not save then notes.potions = "waiting for profile"; return end
    local minTier = tonumber(CFG.PotionMinTier) or 1
    local maxTier = tonumber(CFG.PotionMaxTier) or 99
    local candidates = {}
    for _, bucketKind in ipairs({"Potion", "XPPotion"}) do
        local isXP = bucketKind == "XPPotion"
        for _, item in ipairs(stackList(inventory(save, bucketKind))) do
            if allowAll(picked.potions, item.id) and item.tier >= minTier and item.tier <= maxTier then
                local cd = consumeNext.potionCooldown[item.uid] or 0
                if now >= cd then
                    item.isXP = isXP
                    candidates[#candidates + 1] = item
                end
            end
        end
    end
    if #candidates == 0 then
        table.clear(consumeNext.potionCooldown)
        notes.potions = "no selected potions in inventory"
        return
    end
    table.sort(candidates, function(a, b)
        if a.tier ~= b.tier then
            if enabled.drinkHighestTier then
                return a.tier > b.tier
            else
                return a.tier < b.tier
            end
        end
        if a.id ~= b.id then return a.id < b.id end
        return tostring(a.uid) < tostring(b.uid)
    end)
    local chosen = candidates[1]
    consumeNext.Potion = now + CFG.PotionInterval
    consumeNext.potionCooldown[chosen.uid] = now + 8
    local count = math.max(1, math.min(chosen.amount, CFG.PotionMaxConsume))
    local remoteName = (chosen.isXP or XP_POTION_SET[chosen.id]) and "XPPotions: Consume" or "Potions: Consume"
    local ok, message = fire(remoteName, chosen.uid, count)
    if not alive then return end
    notes.potions = ok and ("drank %s (Tier %d) x%d"):format(chosen.id, chosen.tier, count) or tostring(message or "rejected")
    if ok then nextAt.save = 0 end
end

local function freeGiftTick()
    local now = os.clock()
    if now < nextAt.freeGift then return end
    local save = getSave()
    if not save then notes.freeGift = "waiting for profile"; return end
    local redeemed = type(save.FreeGiftsRedeemed) == "table" and save.FreeGiftsRedeemed or {}
    local claimed = {}
    for _, id in ipairs(redeemed) do claimed[tostring(id)] = true end
    for _ = 1, CFG.FreeGiftMax do
        if not alive or not enabled.autoFreeGifts then return end
        local id = nextAt.freeGiftCursor
        nextAt.freeGiftCursor = nextAt.freeGiftCursor % CFG.FreeGiftMax + 1
        if not claimed[tostring(id)] and allowAll(picked.freeGifts, id) then
            nextAt.freeGift = now + CFG.FreeGiftInterval
            local ok, message = invoke("Redeem Free Gift", id)
            if not alive or not enabled.autoFreeGifts then return end
            notes.freeGift = ok == true and ("redeemed gift " .. id) or tostring(message or "not ready")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    notes.freeGift = "all free gifts redeemed"
end

local function getUltimateCmds()
    if modules.ultimates then return modules.ultimates end
    local ok, mod = pcall(function()
        local lib = RS:FindFirstChild("Library")
        local cli = lib and lib:FindFirstChild("Client")
        local u = cli and cli:FindFirstChild("UltimateCmds")
        return u and require(u) or nil
    end)
    if ok and type(mod) == "table" then
        modules.ultimates = mod
        return mod
    end
    return nil
end

local function isUltimateHudReady()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = pg and pg:FindFirstChild("Main")
    if not mainGui then return false end
    local ready = mainGui:FindFirstChild("UltimateReady", true)
    return ready ~= nil and ready:IsA("GuiObject") and ready.Visible == true
end

local function ultimateTick()
    local now = os.clock()
    if now < nextAt.ultimate then return end
    local save = getSave()
    if not save then notes.ultimate = "waiting for profile"; return end
    if (tonumber(save.Rebirths) or 0) < 4 then notes.ultimate = "unlocks at 4 rebirths"; return end

    local ultCmds = getUltimateCmds()
    local ultId = nil

    if ultCmds and type(ultCmds.GetEquippedItem) == "function" then
        local okEq, item = pcall(ultCmds.GetEquippedItem)
        if okEq and type(item) == "table" and type(item.GetId) == "function" then
            local okId, resolved = pcall(item.GetId, item)
            if okId and type(resolved) == "string" then
                ultId = resolved
            end
        end
    end

    if not ultId then
        local rawEq = save.EquippedUltimate
        local ultBucket = inventory(save, "Ultimate")
        if type(rawEq) == "string" and #rawEq > 0 then
            if ultBucket and type(ultBucket[rawEq]) == "table" and type(ultBucket[rawEq].id) == "string" then
                ultId = ultBucket[rawEq].id
            else
                ultId = rawEq
            end
        end
    end

    if type(ultId) ~= "string" or #ultId == 0 then
        local best = nil
        local ultStacks = stackList(inventory(save, "Ultimate"))
        if #ultStacks > 0 then
            best = ultStacks[1].id
        else
            local bestXP = -1
            for candidate, xp in pairs(type(save.Ultimates) == "table" and save.Ultimates or {}) do
                local value = tonumber(xp) or 0
                if type(candidate) == "string" and value > bestXP then best, bestXP = candidate, value end
            end
        end
        if not best then notes.ultimate = "no ultimate owned"; return end
        nextAt.ultimate = now + 1.5
        local ok, message = invoke("Ultimates: Equip", best)
        if not alive or not enabled.autoUltimate then return end
        notes.ultimate = ok == true and ("equipped " .. best) or tostring(message or "rejected")
        if ok == true then nextAt.save = 0 end
        return
    end

    -- Check charge via UltimateCmds.GetChargePercentage / IsCharged (since
    -- save.UltimateCooldowns[id] stores raw points 0..Cooldown(level), NOT 0..1).
    local pct = 0
    local charged = false
    local activeNow = false
    if ultCmds then
        if type(ultCmds.IsActive) == "function" then
            local okAct, act = pcall(ultCmds.IsActive)
            if okAct and act == true then activeNow = true end
        end
        if type(ultCmds.GetChargePercentage) == "function" then
            local okPct, val = pcall(ultCmds.GetChargePercentage, ultId)
            if okPct and type(val) == "number" then pct = val end
        end
        if type(ultCmds.IsCharged) == "function" then
            local okChg, val = pcall(ultCmds.IsCharged, ultId)
            if okChg and val == true then charged = true end
        end
    end
    if pct >= 1 or isUltimateHudReady() then
        charged = true
        if pct < 1 then pct = 1 end
    end
    if activeNow then
        notes.ultimate = "active: " .. ultId
        return
    end
    if not charged then
        notes.ultimate = ("charging %s (%d%%)"):format(ultId, math.floor(pct * 100))
        return
    end

    nextAt.ultimate = now + 1.0
    local ok, message = false, nil
    if ultCmds and type(ultCmds.Activate) == "function" then
        local okCall, res = pcall(ultCmds.Activate, ultId)
        if okCall and res == true then
            ok = true
        end
    end
    if not ok then
        local invOk, invMsg = invoke("Ultimates: Activate", ultId)
        ok, message = invOk == true, invMsg
    end
    if not alive or not enabled.autoUltimate then return end
    notes.ultimate = ok and ("activated " .. ultId) or tostring(message or "rejected")
    if ok then nextAt.save = 0 end
end

local function daycareRemaining(save, record, serverNow)
    if type(record) ~= "table" then return 0 end
    local age = (tonumber(save.Age) or 0) + math.max(0, serverNow - (tonumber(save.LoginTime) or serverNow))
    local online = math.max(0, age - (tonumber(record.CreationAge) or 0))
    local offline = math.max(0, serverNow - (tonumber(record.CreationTime) or serverNow) - online)
    local elapsed = online * CFG.DaycareOnlineSpeedup + offline
    return math.max(0, CFG.DaycareDuration - elapsed)
end

local function daycareTick()
    local now = os.clock()
    if now < nextAt.daycare then return end
    local save = getSave()
    if not save then notes.daycare = "waiting for profile"; return end
    local active = type(save.DaycareActive) == "table" and save.DaycareActive or {}
    local serverNow = serverClock()
    local used = 0
    for uid, record in pairs(active) do
        if not alive or not enabled.autoDaycare then return end
        if type(record) == "table" then used += tonumber(record.Pet and record.Pet._am) or 0 end
        if type(record) == "table" and record.Pet ~= nil and daycareRemaining(save, record, serverNow) <= 0 then
            nextAt.daycare = now + CFG.DaycareInterval
            local ok, message = invoke("Daycare: Claim", tostring(uid))
            if not alive or not enabled.autoDaycare then return end
            notes.daycare = ok == true and ("claimed " .. tostring(uid)) or tostring(message or "rejected")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    local slots = CFG.DaycareSlotsFree + (tonumber(save.DaycareVouchers) or 0)
    if used >= slots then notes.daycare = ("all %d slots filled"):format(slots); return end
    local selected, total = {}, 0
    for _, pet in ipairs(stackList(inventory(save, "Pet"))) do
        if not alive or not enabled.autoDaycare then return end
        if used + total >= slots then break end
        if pet.data._lk ~= true then
            local take = math.min(pet.amount, slots - used - total)
            selected[pet.uid] = take
            total += take
        end
    end
    if total <= 0 then notes.daycare = "no unlocked pets to enroll"; return end
    nextAt.daycare = now + CFG.DaycareInterval
    local ok, message = invoke("Daycare: Enroll", selected)
    if not alive or not enabled.autoDaycare then return end
    notes.daycare = ok == true and ("enrolled " .. total .. " pets") or tostring(message or "rejected")
    if ok == true then nextAt.save = 0 end
end

local function flagTick()
    local now = os.clock()
    if now < nextAt.flag then return end
    local save = getSave()
    if not save then notes.flags = "waiting for profile"; return end
    local zone = currentZone()
    if not zone then
        local mapCmds = modules.mapCmds
        local instInfo = mapCmds and type(mapCmds.GetCurrentInstanceInfo) == "function" and mapCmds.GetCurrentInstanceInfo()
        if not instInfo then
            notes.flags = "stand inside a zone"
            nextAt.flag = now + 2
            return
        end
    end
    local chosenFlag = type(CFG.SelectedFlag) == "string" and CFG.SelectedFlag or "Any Flag"
    local fCmds = modules.flags
    if fCmds then
        if type(fCmds.PlayerHasActiveFlag) == "function" and chosenFlag ~= "Any Flag" then
            local okAct, act = pcall(fCmds.PlayerHasActiveFlag, chosenFlag)
            if okAct and act == true then
                notes.flags = ("active %s in zone"):format(chosenFlag)
                nextAt.flag = now + 10
                return
            end
        end
        if type(fCmds.GetActiveFlag) == "function" and zone then
            local okAct, active = pcall(fCmds.GetActiveFlag, 1, zone)
            if okAct and type(active) == "table" and tonumber(active.EndTime) then
                local left = active.EndTime - serverClock()
                if left > 12 then
                    notes.flags = ("active %s (%ds)"):format(tostring(active.FlagId or "flag"), math.floor(left))
                    nextAt.flag = now + math.min(left - 8, CFG.FlagInterval)
                    return
                end
            end
        end
    end
    local flagsFolder = thingsFolder("Flags")
    local pt = position()
    if flagsFolder and pt then
        for _, child in ipairs(flagsFolder:GetChildren()) do
            local pos = modelPosition(child)
            if pos and (pos - pt).Magnitude <= 140 then
                notes.flags = "flag already nearby"
                nextAt.flag = now + 12
                return
            end
        end
    end
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if not alive or not enabled.autoFlags then return end
        local matchChosen = (chosenFlag == "Any Flag" and allowAll(picked.flags, item.id)) or (item.id == chosenFlag)
        if item.id:match(" Flag$") and matchChosen and item.amount > 0 then
            nextAt.flag = now + CFG.FlagInterval
            local ok, message = invoke("FlexibleFlags_Consume", item.id, item.uid, 1)
            if not alive or not enabled.autoFlags then return end
            notes.flags = ok == true and ("deployed " .. item.id) or tostring(message or "rejected")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    notes.flags = "no " .. (chosenFlag == "Any Flag" and "selected flags" or chosenFlag) .. " in inventory"
end

local function secretRoomTick()
    local now = os.clock()
    if now < nextAt.secret then return end
    local save = getSave()
    if not save then notes.secret = "waiting for profile"; return end
    local owned = type(save.SecretRooms) == "table" and save.SecretRooms or {}
    local ok, tagged = pcall(function() return game:GetService("CollectionService"):GetTagged("Secret Room") end)
    if not ok or type(tagged) ~= "table" then notes.secret = "no tagged secret rooms"; return end
    for _, model in ipairs(tagged) do
        if not alive or not enabled.autoSecretRooms then return end
        local name = model.Name
        if type(name) == "string" and not owned[name] and not secretTried[name] then
            secretTried[name] = true
            nextAt.secret = now + CFG.SecretInterval
            local result, message = invoke("SecretRoom_Unlock", name)
            if not alive or not enabled.autoSecretRooms then return end
            notes.secret = result == true and ("unlocked " .. name) or tostring(message or "no secret key")
            if result == true then nextAt.save = 0 end
            return
        end
    end
    notes.secret = "all nearby secret rooms unlocked"
end

local function treehouseTick()
    local now = os.clock()
    if now < nextAt.treehouse then return end
    nextAt.treehouse = now + CFG.TreehouseInterval
    for slot = 1, 3 do
        if not alive or not enabled.autoTreehouse then return end
        local ok, message = invoke("TreehouseMerchant_Purchase", slot)
        if not alive or not enabled.autoTreehouse then return end
        notes.treehouse = ok == true and ("bought slot " .. slot) or tostring(message or "sold out")
        if ok == true then nextAt.save = 0; return end
    end
end

local function fuseTick()
    local now = os.clock()
    if now < nextAt.fuse then return end
    local save = getSave()
    if not save then notes.fuse = "waiting for profile"; return end
    local pets = stackList(inventory(save, "Pet"))
    local groups, order = {}, {}
    for _, pet in ipairs(pets) do
        if pet.data._lk ~= true then
            local key = pet.id .. (pet.data.sh and "|s" or "") .. (pet.data.pt and ("|" .. pet.data.pt) or "")
            if not groups[key] then groups[key] = {}; order[#order + 1] = key end
            table.insert(groups[key], pet)
        end
    end
    if #order < CFG.FuseMinStacks then notes.fuse = ("needs %d distinct pets (have %d)"):format(CFG.FuseMinStacks, #order); return end
    table.sort(order)
    local payload, total = {}, 0
    for _, key in ipairs(order) do
        if total >= CFG.FuseMaxPets then break end
        local stack = groups[key][1]
        local take = math.min(stack.amount, CFG.FuseMaxPets - total)
        payload[stack.uid] = take
        total += take
    end
    if total < CFG.FuseMinPets then notes.fuse = "not enough pets to fuse (" .. total .. ")"; return end
    nextAt.fuse = now + CFG.FuseInterval
    local ok, message = invoke("FuseMachine_Activate", payload)
    if not alive or not enabled.autoFuse then return end
    notes.fuse = ok == true and ("fused " .. total .. " pets") or tostring(message or "rejected")
    if ok == true then nextAt.save = 0 end
end

local function cardTick()
    local now = os.clock()
    if now < nextAt.card then return end
    local save = getSave()
    if not save then notes.cards = "waiting for profile"; return end
    local payload, total = {}, 0
    for _, card in ipairs(stackList(inventory(save, "Card"))) do
        if allowAll(picked.cards, card.id) then
            local count = card.amount // 3
            if count > 0 then payload[card.uid] = count; total += count end
        end
    end
    if total <= 0 then notes.cards = "no complete card sets"; return end
    nextAt.card = now + CFG.CardInterval
    local ok, message = invoke("CardCombinationMachine_ActivateBulk", payload)
    if not alive or not enabled.autoCards then return end
    notes.cards = ok == true and ("combined " .. total .. " card sets") or tostring(message or "rejected")
    if ok == true then nextAt.save = 0 end
end

local function diceTick()
    local now = os.clock()
    if now < nextAt.dice then return end
    local save = getSave()
    if not save then notes.dice = "waiting for profile"; return end
    local halves = {}
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        halves[item.id] = (halves[item.id] or 0) + item.amount
    end
    for _, id in ipairs(DICE_IDS) do
        if not alive or not enabled.autoDice then return end
        local amount = halves[id] or 0
        if amount > 0 and allowAll(picked.dice, id) then
            nextAt.dice = now + CFG.DiceInterval
            local count = math.max(1, math.min(amount, CFG.DiceMaxConsume))
            local ok, message
            if id == "Fire Dice V2" then
                ok, message = invoke("FireDice_Consume_V2", count)
            elseif MEGA_DICE[id] then
                ok, message = invoke("LuckyDice_ConsumeMega_V2", id, count)
            else
                ok, message = invoke("LuckyDice_Consume_V2", id, count)
            end
            if not alive or not enabled.autoDice then return end
            notes.dice = ok == true and ("rolled " .. id .. " x" .. count) or tostring(message or "rejected")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    notes.dice = "no selected dice in inventory"
end

local function relicTick()
    local now = os.clock()
    if now < nextAt.relic then return end
    local save = getSave()
    if not save then notes.relics = "waiting for profile"; return end
    local owned = type(save.ShinyRelics) == "table" and save.ShinyRelics or {}
    local relics, message = invoke("Relics_Request")
    if not alive or not enabled.autoRelics then return end
    if type(relics) ~= "table" then notes.relics = tostring(message or relics or "relic list unavailable"); return end
    local has = {}
    for _, id in ipairs(owned) do has[tostring(id)] = true end
    for _, record in pairs(relics) do
        if not alive or not enabled.autoRelics then return end
        local id = type(record) == "table" and (record.Id or record._id) or nil
        if type(id) == "string" and not has[id] then
            nextAt.relic = now + CFG.SecretInterval
            local found, message = invoke("Relic_Found", id)
            if not alive or not enabled.autoRelics then return end
            notes.relics = found == true and ("relic found: " .. id) or tostring(message or "not reachable")
            if found == true then nextAt.save = 0 end
            return
        end
    end
    notes.relics = "no uncollected relics listed"
end

local function mailClaimTick()
    local now = os.clock()
    if now < nextAt.mail then return end
    local save = getSave()
    if not save then notes.mailClaim = "waiting for profile"; return end
    if not pendingMail then
        local inbox, loadError = invoke("YS_Load")
        if not alive or not enabled.autoMailClaim then return end
        if type(inbox) ~= "table" then notes.mailClaim = tostring(loadError or inbox or "mailbox unavailable"); return end
        local uuids = {}
        for _, mail in ipairs(type(inbox.Inbox) == "table" and inbox.Inbox or {}) do
            if type(mail) == "table" and type(mail.uuid) == "string" then table.insert(uuids, mail.uuid) end
        end
        if #uuids == 0 then notes.mailClaim = "mailbox empty"; return end
        pendingMail = uuids
    end
    nextAt.mail = now + CFG.MailInterval
    local ok, message = invoke("RD_Ingest", pendingMail)
    if not alive or not enabled.autoMailClaim then return end
    if ok == true then
        notes.mailClaim = "claimed " .. #pendingMail .. " mail"
        nextAt.save = 0
    else
        notes.mailClaim = tostring(message or "claim rejected")
    end
    pendingMail = nil
end

CFG.Quest = {
    WORLD_SPAWN = {
        [1] = "Spawn",
        [2] = "Tech Spawn",
        [3] = "Void Spawn",
        [4] = "Fantasy Spawn",
    },
    PRIORITY = {
        [6] = 1, [81] = 1,
        [34] = 2, [74] = 2, [35] = 2, [33] = 2,
        [12] = 2, [13] = 2, [57] = 2,
        [10] = 2, [14] = 2, [11] = 2, [15] = 2, [65] = 2,
        [18] = 2, [55] = 2, [56] = 2, [61] = 2, [80] = 2,
        [4] = 3, [5] = 3, [40] = 3, [41] = 3, [19] = 3,
        [31] = 4, [37] = 4, [68] = 4,
        [32] = 4, [38] = 4, [69] = 4, [43] = 4, [66] = 4, [70] = 4, [44] = 4, [67] = 4, [71] = 4,
        [2] = 5, [3] = 5, [20] = 5, [42] = 5, [83] = 5,
        [7] = 6, [99] = 6, [100] = 6,
    },
}

function CFG.Quest.BestEggInfo(save)
    local maxEggNum = nil
    local maxHatch = nil
    pcall(function()
        local eggCmds = require(RS.Library.Client.EggCmds)
        if type(eggCmds) == "table" then
            if type(eggCmds.GetHighestEggNumberAvailable) == "function" then
                local ok, num = pcall(eggCmds.GetHighestEggNumberAvailable)
                if ok and type(num) == "number" and num > 0 then maxEggNum = num end
            end
            if type(eggCmds.GetMaxHatch) == "function" then
                local ok, cnt = pcall(eggCmds.GetMaxHatch)
                if ok and type(cnt) == "number" and cnt > 0 then maxHatch = cnt end
            end
        end
    end)
    if not maxEggNum then
        maxEggNum = tonumber(save and save.MaximumAvailableEgg) or 1
    end
    if not maxHatch then
        maxHatch = tonumber(save and save.EggHatchCount) or 1
    end
    local bestEggId = eggByNumber[maxEggNum]
    local bestEggPets = {}
    local petCount = 0
    pcall(function()
        local dir = require(RS.Library.Directory)
        local eggs = dir and dir.Eggs
        if type(eggs) == "table" then
            local entry = bestEggId and eggs[bestEggId] or nil
            if type(entry) ~= "table" then
                for id, data in pairs(eggs) do
                    if type(data) == "table" and data.eggNumber == maxEggNum then
                        bestEggId = tostring(id)
                        entry = data
                        break
                    end
                end
            end
            if type(entry) == "table" and type(entry.pets) == "table" then
                for _, p in ipairs(entry.pets) do
                    local pid = type(p) == "table" and p[1] or (type(p) == "string" and p or nil)
                    if type(pid) == "string" and #pid > 0 then
                        bestEggPets[pid] = true
                        petCount += 1
                    end
                end
            end
        end
    end)
    if not bestEggId then bestEggId = eggByNumber[1] end
    return bestEggId, bestEggPets, petCount, maxEggNum, math.clamp(maxHatch, 1, CFG.EggMaxHatch)
end

function CFG.Quest.HatchBestEgg(save, desiredCount)
    local bestEggId, _, _, _, maxHatch = CFG.Quest.BestEggInfo(save)
    if not bestEggId then return false, "best egg unknown" end
    local count = math.clamp(tonumber(desiredCount) or maxHatch, 1, maxHatch)
    local _, _, eggPos = findEggModel(bestEggId, position())
    if not eggPos then
        local spawnZone = CFG.Quest.WORLD_SPAWN[detectActiveWorld()] or "Spawn"
        if currentZone() ~= spawnZone then
            teleportToIslandMiddle(spawnZone)
            task.wait(0.35)
        end
        _, _, eggPos = findEggModel(bestEggId, position())
    end
    local ok, msg = hatchEggById(bestEggId, count, true)
    if not ok then
        local unlocked = invoke("Eggs_RequestUnlock", bestEggId)
        if unlocked == true then
            task.wait(0.15)
            ok, msg = hatchEggById(bestEggId, count, true)
        end
    end
    if ok then nextAt.save = 0 end
    return ok, msg
end

function CFG.Quest.FindBestPetStacks(save, petFilter, wantPt)
    local matches = {}
    for _, pet in ipairs(stackList(inventory(save, "Pet"))) do
        if pet.data._lk ~= true and pet.amount >= 10 then
            local ptOk = (wantPt == nil and not pet.data.pt) or (wantPt ~= nil and pet.data.pt == wantPt)
            if ptOk and (not petFilter or petFilter[pet.id] == true) then
                matches[#matches + 1] = pet
            end
        end
    end
    table.sort(matches, function(a, b) return a.amount > b.amount end)
    return matches
end

-- Item 6: Auto Do Quest Tasks. Inspects Rank Goals (save.Goals), ZoneGateQuest,
-- ZoneQuests, and NPCQuests, and automatically performs the required action.
local function collectActiveGoals(save)
    local list = {}
    local function push(goal, source)
        if type(goal) == "table" and type(goal.Type) == "number" and not goalFull(goal) and goal.Claimed ~= true then
            list[#list + 1] = {
                goal = goal,
                source = source,
                prio = CFG.Quest.PRIORITY[goal.Type] or 9,
                stars = tonumber(goal.Stars) or 0,
            }
        end
    end
    if type(save.ZoneGateQuest) == "table" then push(save.ZoneGateQuest, "gate") end
    if type(save.Goals) == "table" then
        for k, g in pairs(save.Goals) do push(g, "rank:" .. tostring(k)) end
    end
    if type(save.NPCQuests) == "table" then
        for id, data in pairs(save.NPCQuests) do
            if type(data) == "table" and data.Completed ~= true then
                local qs = data.Quests or (assignedQuests[id] and assignedQuests[id].goals)
                if type(qs) == "table" then
                    for _, g in pairs(qs) do push(g, "npc:" .. tostring(id)) end
                end
            end
        end
    end
    if type(save.ZoneQuests) == "table" then
        local here = currentZone()
        local zq = here and save.ZoneQuests[here]
        if type(zq) == "table" and type(zq.Quests) == "table" then
            for _, g in pairs(zq.Quests) do push(g, "zone:" .. tostring(here)) end
        end
    end
    table.sort(list, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.stars ~= b.stars then return a.stars > b.stars end
        return tostring(a.source) < tostring(b.source)
    end)
    return list
end

local function doQuestTick()
    local now = os.clock()
    if now < nextAt.doQuest then return end
    local save = getSave()
    if not save then notes.doQuest = "waiting for profile"; return end
    if enabled.autoQuest then pcall(questTick) end
    if enabled.autoRank then pcall(rankTick) end
    local activeGoals = collectActiveGoals(save)
    if #activeGoals == 0 then
        notes.doQuest = "no active incomplete quest goals"
        nextAt.doQuest = now + CFG.DoQuestInterval
        return
    end
    nextAt.doQuest = now + CFG.DoQuestInterval
    for _, entry in ipairs(activeGoals) do
        if not alive or not enabled.autoDoQuest then return end
        local goal = entry.goal
        local gtype = tonumber(goal.Type)
        local rem = math.max(1, (tonumber(goal.Amount) or 1) - (tonumber(goal.Progress) or 0))
        -- 6 = ZONE, 81 = SPECIFIC_ZONE
        if gtype == 6 or gtype == 81 then
            local targetZoneId = goal.ZoneID
            if not targetZoneId then
                local best = maxOwned(save)
                local nxt = best and zones[best + 1]
                targetZoneId = nxt and nxt.id
            end
            if targetZoneId then
                local ok = invoke("Zones_RequestPurchase", targetZoneId)
                if ok == true then
                    notes.doQuest = "bought quest zone " .. targetZoneId
                    nextAt.save = 0
                    nextAt.doQuest = now + 0.35
                    return
                end
            end
        -- 2 = PET, 3 = EGG, 20 = BEST_EGG, 42 = HATCH_RARE_PET, 83 = HATCH_CUSTOM_EGG
        elseif gtype == 2 or gtype == 3 or gtype == 20 or gtype == 42 or gtype == 83 then
            local ok, msg
            if goal.EggID then
                local _, _, _, _, maxHatch = CFG.Quest.BestEggInfo(save)
                local count = math.clamp(math.min(rem, maxHatch), 1, maxHatch)
                ok, msg = hatchEggById(goal.EggID, count, true)
                if ok then nextAt.save = 0 end
            else
                local _, _, _, _, maxHatch = CFG.Quest.BestEggInfo(save)
                ok, msg = CFG.Quest.HatchBestEgg(save, math.min(rem, maxHatch))
            end
            if ok then
                notes.doQuest = "quest hatch: " .. tostring(msg)
                nextAt.doQuest = now + 0.45
                return
            end
        -- 34 = USE_POTION, 74 = XP_POTION
        elseif gtype == 34 or gtype == 74 then
            local bucketName = gtype == 74 and "XPPotion" or "Potion"
            local reqId = goal.PotionID
            local reqTier = tonumber(goal.PotionTier)
            for _, item in ipairs(stackList(inventory(save, bucketName))) do
                if (not reqId or item.id == reqId) and (not reqTier or item.tier >= reqTier) then
                    local take = math.max(1, math.min(rem, item.amount, CFG.PotionMaxConsume))
                    local rName = gtype == 74 and "XPPotions: Consume" or "Potions: Consume"
                    local ok = fire(rName, item.uid, take)
                    if ok then
                        notes.doQuest = ("quest potion: %s (T%d) x%d"):format(item.id, item.tier, take)
                        nextAt.save = 0
                        nextAt.doQuest = now + 0.35
                        return
                    end
                end
            end
        -- 35 = USE_FRUIT
        elseif gtype == 35 then
            local reqId = goal.FruitID
            for _, item in ipairs(stackList(inventory(save, "Fruit"))) do
                if not reqId or item.id == reqId then
                    local take = math.max(1, math.min(rem, item.amount, CFG.FruitQueueLimit))
                    if fire("Fruits: Consume", item.uid, take) then
                        notes.doQuest = ("quest fruit: %s x%d"):format(item.id, take)
                        nextAt.save = 0
                        nextAt.doQuest = now + 0.35
                        return
                    end
                end
            end
        -- 33 = USE_FLAG
        elseif gtype == 33 then
            local best = maxOwned(save)
            if best and zones[best] and currentZone() ~= zones[best].id then
                teleportToIslandMiddle(zones[best].id)
            end
            for _, item in ipairs(stackList(inventory(save, "Misc"))) do
                if item.id:match(" Flag$") then
                    if invoke("FlexibleFlags_Consume", item.id, item.uid, 1) == true then
                        notes.doQuest = "quest flag: " .. item.id
                        nextAt.save = 0
                        nextAt.doQuest = now + 0.4
                        return
                    end
                end
            end
        -- 4 = GOLD_PET, 40 = BEST_GOLD_PET (auto crafts best-egg pets into Golden; auto hatches best egg when short)
        elseif gtype == 4 or gtype == 40 then
            local bestEggId, bestEggPets, bestPetCount, _, maxHatch = CFG.Quest.BestEggInfo(save)
            local filter = (gtype == 40 and bestPetCount > 0) and bestEggPets or nil
            local stacks = CFG.Quest.FindBestPetStacks(save, filter, nil)
            if #stacks == 0 and gtype == 4 then
                stacks = CFG.Quest.FindBestPetStacks(save, nil, nil)
            end
            for _, pet in ipairs(stacks) do
                local craftCount = math.max(1, math.min(rem, pet.amount // 10, 100))
                local ok = invoke("GoldMachine_Activate", pet.uid, craftCount)
                if ok then
                    notes.doQuest = ("quest best gold: %s x%d"):format(pet.id, craftCount)
                    nextAt.save = 0
                    nextAt.doQuest = now + 0.35
                    return
                end
            end
            local okH, msgH = CFG.Quest.HatchBestEgg(save, maxHatch)
            if okH then
                notes.doQuest = ("quest best gold: hatching %s (%s)"):format(tostring(bestEggId), tostring(msgH))
                nextAt.doQuest = now + 0.55
                return
            end
        -- 5 = RAINBOW_PET, 41 = BEST_RAINBOW_PET (crafts Golden -> Rainbow; crafts Normal -> Golden first; hatches best egg when short)
        elseif gtype == 5 or gtype == 41 then
            local bestEggId, bestEggPets, bestPetCount, _, maxHatch = CFG.Quest.BestEggInfo(save)
            local filter = (gtype == 41 and bestPetCount > 0) and bestEggPets or nil
            local goldStacks = CFG.Quest.FindBestPetStacks(save, filter, 1)
            if #goldStacks == 0 and gtype == 5 then
                goldStacks = CFG.Quest.FindBestPetStacks(save, nil, 1)
            end
            for _, pet in ipairs(goldStacks) do
                local craftCount = math.max(1, math.min(rem, pet.amount // 10, 100))
                local ok = invoke("RainbowMachine_Activate", pet.uid, craftCount)
                if ok then
                    notes.doQuest = ("quest best rainbow: %s x%d"):format(pet.id, craftCount)
                    nextAt.save = 0
                    nextAt.doQuest = now + 0.35
                    return
                end
            end
            local normalStacks = CFG.Quest.FindBestPetStacks(save, filter, nil)
            if #normalStacks == 0 and gtype == 5 then
                normalStacks = CFG.Quest.FindBestPetStacks(save, nil, nil)
            end
            for _, pet in ipairs(normalStacks) do
                local craftCount = math.max(1, math.min(rem * 10, pet.amount // 10, 100))
                local ok = invoke("GoldMachine_Activate", pet.uid, craftCount)
                if ok then
                    notes.doQuest = ("quest best rainbow (prep gold): %s x%d"):format(pet.id, craftCount)
                    nextAt.save = 0
                    nextAt.doQuest = now + 0.35
                    return
                end
            end
            local okH, msgH = CFG.Quest.HatchBestEgg(save, maxHatch)
            if okH then
                notes.doQuest = ("quest best rainbow: hatching %s (%s)"):format(tostring(bestEggId), tostring(msgH))
                nextAt.doQuest = now + 0.55
                return
            end
        -- 19 = FUSE_PETS
        elseif gtype == 19 then
            pcall(fuseTick)
            notes.doQuest = "quest fuse triggered"
        -- 12 = UPGRADE_POTION
        elseif gtype == 12 then
            local reqTier = tonumber(goal.PotionTier)
            for _, item in ipairs(stackList(inventory(save, "Potion"))) do
                if item.amount >= 5 and (not reqTier or item.tier == reqTier - 1) then
                    local craftCount = math.max(1, math.min(rem, item.amount // 5))
                    if invoke("UpgradePotionsMachine_Activate", item.uid, craftCount) == true then
                        notes.doQuest = ("quest upgrade potion: %s T%d x%d"):format(item.id, item.tier, craftCount)
                        return
                    end
                end
            end
        -- 13 = UPGRADE_ENCHANT
        elseif gtype == 13 then
            local reqTier = tonumber(goal.EnchantTier)
            for _, item in ipairs(stackList(inventory(save, "Enchant"))) do
                if item.amount >= 5 and (not reqTier or item.tier == reqTier - 1) then
                    local craftCount = math.max(1, math.min(rem, item.amount // 5))
                    if invoke("UpgradeEnchantsMachine_Activate", item.uid, craftCount) == true then
                        notes.doQuest = ("quest upgrade enchant: %s T%d x%d"):format(item.id, item.tier, craftCount)
                        return
                    end
                end
            end
        -- 57 = UPGRADE_FRUIT
        elseif gtype == 57 then
            for _, item in ipairs(stackList(inventory(save, "Fruit"))) do
                if item.amount >= 20 then
                    local take = math.min(item.amount, rem * 20)
                    if invoke("UpgradeFruitsMachine_Activate", {[item.uid] = take}) == true then
                        notes.doQuest = "quest upgrade fruit: " .. item.id
                        return
                    end
                end
            end
        -- 7 = CURRENCY, 99 = OBTAIN_CURRENCY, 100 = CLAIM_FREE_DIAMONDS
        -- Collect Gem / Diamonds: open Large Gift Bag, Small Gift Bag ("Gift Bag"), or Diamond Gift Bag.
        elseif gtype == 7 or gtype == 99 or gtype == 100 then
            local curr = tostring(goal.CurrencyID or goal.Currency or ""):lower()
            if gtype == 100 or curr:find("diamond", 1, true) or curr:find("gem", 1, true) then
                local miscList = stackList(inventory(save, "Misc"))
                local gemBags = {"Large Gift Bag", "Gift Bag", "Diamond Gift Bag"}
                for _, bagName in ipairs(gemBags) do
                    for _, item in ipairs(miscList) do
                        if item.id == bagName and item.amount > 0 then
                            local openAmt = math.max(1, math.min(item.amount, 5))
                            if invoke("GiftBag_Open", item.id, openAmt) == true then
                                notes.doQuest = ("quest gems: opened %s x%d"):format(item.id, openAmt)
                                nextAt.save = 0
                                return
                            end
                        end
                    end
                end
            end
        -- 31/37/68 = COIN_JAR (easiest/cheapest coin jar first: Basic -> Normal -> Magic -> Giant)
        elseif gtype == 31 or gtype == 37 or gtype == 68 then
            if now >= (nextAt.coinJar or 0) then
                local best = maxOwned(save)
                if best and zones[best] and currentZone() ~= zones[best].id then
                    teleportToIslandMiddle(zones[best].id)
                end
                local miscList = stackList(inventory(save, "Misc"))
                local jarOrder = {"Basic Coin Jar"}
                for _, jarName in ipairs(jarOrder) do
                    for _, item in ipairs(miscList) do
                        if item.id == jarName and item.amount > 0 then
                            if invoke("CoinJar_Spawn", item.uid) == true then
                                nextAt.coinJar = now + 12
                                notes.doQuest = "quest coin jar (easy first): " .. item.id
                                nextAt.save = 0
                                return
                            end
                        end
                    end
                end
            end
        -- 32/38/69 = COMET, 43/66/70 = PINATA, 44/67/71 = LUCKYBLOCK
        elseif gtype == 32 or gtype == 38 or gtype == 69
            or gtype == 43 or gtype == 66 or gtype == 70 or gtype == 44 or gtype == 67 or gtype == 71 then
            local best = maxOwned(save)
            if best and zones[best] and currentZone() ~= zones[best].id then
                teleportToIslandMiddle(zones[best].id)
            end
            local wantName, remoteName
            if gtype == 32 or gtype == 38 or gtype == 69 then wantName, remoteName = "Comet", "Comet_Spawn"
            elseif gtype == 43 or gtype == 66 or gtype == 70 then wantName, remoteName = "Pinata", "Pinata_Spawn"
            else wantName, remoteName = "Lucky Block", "LuckyBlock_Spawn" end
            for _, item in ipairs(stackList(inventory(save, "Misc"))) do
                if item.id:find(wantName, 1, true) then
                    if invoke(remoteName, item.uid) == true then
                        notes.doQuest = "quest spawned " .. item.id
                        return
                    end
                end
            end
        -- 10/14 = BUY/COLLECT POTION, 11/15 = BUY/COLLECT ENCHANT, 65 = COLLECT FRUIT
        -- Only open matching category bundles; NEVER waste Gift Bags when not needed.
        elseif gtype == 10 or gtype == 14 or gtype == 11 or gtype == 15 or gtype == 65 then
            local bundleMatch = (gtype == 10 or gtype == 14) and "Potion Bundle"
                or ((gtype == 11 or gtype == 15) and "Enchant Bundle" or "Fruit Bundle")
            for _, item in ipairs(stackList(inventory(save, "Misc"))) do
                if item.id:find(bundleMatch, 1, true) then
                    if invoke("GiftBag_Open", item.id, math.min(item.amount, 5)) == true then
                        notes.doQuest = "quest opened " .. item.id
                        return
                    end
                end
            end
        -- 18 = FREE_GIFT, 80 = EQUIP_PET, 55 = SECRET_KEY, 56 = CRYSTAL_KEY, 61 = DIAMOND_WHEEL
        elseif gtype == 18 then
            pcall(freeGiftTick)
        elseif gtype == 80 then
            pcall(petSlotTick)
        elseif gtype == 56 then
            if invoke("CrystalKey_Unlock") == true then notes.doQuest = "quest crystal chest unlocked"; return end
        elseif gtype == 55 then
            if invoke("SecretKey_Unlock") == true then notes.doQuest = "quest secret chest unlocked"; return end
        elseif gtype == 61 then
            if invoke("Spinny Wheel: Request Spin", "DiamondWheel") == true then notes.doQuest = "quest spun diamond wheel"; return end
        end
    end
    -- Fallback for breakable/currency/crit/lootbag/mini-chest goals (Types 1, 7, 8, 9, 21, 39, 63, 64, 75, 99):
    -- make sure the player is standing in the middle of the best unlocked island and tapping + vacuuming.
    local best = maxOwned(save)
    if best and zones[best] then
        local id = zones[best].id
        if currentZone() ~= id then
            teleportToIslandMiddle(id)
        end
    end
    pcall(tapTick)
    pcall(vacuumTick)
    notes.doQuest = ("working on %d quest goal(s) (type %s)"):format(#activeGoals, tostring(activeGoals[1].goal.Type))
end

-- Auto Use Sprinkler: keeps a Breakable Sprinkler running in the current zone
-- using SprinklerCmds.PlayerHasActiveSprinkler + GetActiveSprinkler + world check.
function CFG.SprinklerTick()
    local now = os.clock()
    if now < nextAt.sprinkler then return end
    local save = getSave()
    if not save then notes.sprinkler = "waiting for profile"; return end
    local zone = currentZone()
    if not zone then notes.sprinkler = "stand inside a zone"; nextAt.sprinkler = now + 2; return end
    local spCmds = modules.sprinklers
    if spCmds then
        if type(spCmds.GetActiveSprinkler) == "function" then
            local ok, active = pcall(spCmds.GetActiveSprinkler, zone)
            if ok and type(active) == "table" and tonumber(active.EndTime) then
                local left = active.EndTime - serverClock()
                if left > 15 then
                    notes.sprinkler = ("active in %s (%ds left)"):format(zone, math.floor(left))
                    nextAt.sprinkler = now + math.min(left - 10, CFG.SprinklerInterval)
                    return
                end
            end
        end
        if type(spCmds.PlayerHasActiveSprinkler) == "function" then
            local okHas, has = pcall(spCmds.PlayerHasActiveSprinkler, "Breakable Sprinkler")
            if okHas and has == true then
                notes.sprinkler = "active in " .. zone
                nextAt.sprinkler = now + CFG.SprinklerInterval
                return
            end
        end
    end
    local spFolder = thingsFolder("Sprinklers")
    local pt = position()
    if spFolder and pt then
        for _, child in ipairs(spFolder:GetChildren()) do
            local pos = modelPosition(child)
            if pos and (pos - pt).Magnitude <= 140 then
                notes.sprinkler = "sprinkler already nearby"
                nextAt.sprinkler = now + CFG.SprinklerInterval
                return
            end
        end
    end
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if not alive or not enabled.autoSprinkler then return end
        if item.id == "Breakable Sprinkler" and item.amount > 0 then
            nextAt.sprinkler = now + CFG.SprinklerInterval
            local ok, message = invoke("Sprinklers: Consume", "Breakable Sprinkler", item.uid, 1)
            if not alive or not enabled.autoSprinkler then return end
            notes.sprinkler = ok == true and ("placed Breakable Sprinkler in " .. zone) or tostring(message or "cannot place here")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    notes.sprinkler = "no Breakable Sprinkler in inventory"
end

-- Auto Use TNT / TNT Crate: only consumes when standing inside an active zone.
function CFG.TNTTick()
    local now = os.clock()
    if now < nextAt.tnt then return end
    local save = getSave()
    if not save then notes.tnt = "waiting for profile"; return end
    local zone = currentZone()
    if not zone then notes.tnt = "stand inside a zone"; nextAt.tnt = now + 2; return end
    local hasTNT = false
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if item.id == "TNT" and item.amount > 0 then hasTNT = true; break end
    end
    if not hasTNT then notes.tnt = "no TNT in inventory"; nextAt.tnt = now + 5; return end
    nextAt.tnt = now + CFG.TNTInterval
    local ok, msg = invoke("TNT_Consume")
    if not alive or not enabled.autoTNT then return end
    notes.tnt = ok == true and ("used TNT in " .. zone) or tostring(msg or "cannot use here")
    if ok == true then nextAt.save = 0 end
end

function CFG.TNTCrateTick()
    local now = os.clock()
    if now < nextAt.tntCrate then return end
    local save = getSave()
    if not save then notes.tntCrate = "waiting for profile"; return end
    local zone = currentZone()
    if not zone then notes.tntCrate = "stand inside a zone"; nextAt.tntCrate = now + 2; return end
    local hasCrate = false
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if item.id == "TNT Crate" and item.amount > 0 then hasCrate = true; break end
    end
    if not hasCrate then notes.tntCrate = "no TNT Crate in inventory"; nextAt.tntCrate = now + 5; return end
    nextAt.tntCrate = now + CFG.TNTCrateInterval
    local ok, msg = invoke("TNT_Crate_Consume")
    if not alive or not enabled.autoTNTCrate then return end
    notes.tntCrate = ok == true and ("used TNT Crate in " .. zone) or tostring(msg or "cannot use here")
    if ok == true then nextAt.save = 0 end
end

-- Auto Equip Enchant: Priority Coins -> Strong Pets -> Tap Power -> Lightning -> Other,
-- strictly selecting the highest tier allowed by the player's Enchant Mastery.
CFG.EnchantPriority = {
    "Coins", "Strong Pets", "Tap Power", "Lightning",
    "Super Lightning", "Criticals", "Diamonds", "Treasure Hunter",
    "Lucky Eggs", "Chest Breaker", "Mega Chest Breaker", "Fortune",
    "Explosive", "Tap Teamwork", "Fireworks", "Blast",
    "Super Magnet", "Magnet", "Fruity", "Happy Pets", "Large Taps", "Swift Taps",
}
function CFG.CanUseEnchantTier(tier, save)
    if tier <= 7 then return true end
    local mCmds = modules.mastery
    if mCmds and type(mCmds.CanUseEnchant) == "function" then
        local ok, can = pcall(mCmds.CanUseEnchant, tier)
        if ok and type(can) == "boolean" then return can end
    end
    local xp = save and type(save.Mastery) == "table" and tonumber(save.Mastery.Enchants) or 0
    -- PS99 Enchant Mastery perk levels: Tier 8 = 60, Tier 9 = 80, Tier 10 = 90
    if tier == 8 then return xp >= 195000 end
    if tier == 9 then return xp >= 1100000 end
    if tier >= 10 then return xp >= 2700000 end
    return false
end

function CFG.AutoEquipEnchantTick()
    local now = os.clock()
    if now < nextAt.enchant then return end
    local save = getSave()
    if not save then notes.enchant = "waiting for profile"; return end
    nextAt.enchant = now + CFG.EnchantInterval

    local maxSlots = 1
    local encCmds = modules.enchants
    if encCmds and type(encCmds.GetMaxEquippedEnchants) == "function" then
        local okMax, val = pcall(encCmds.GetMaxEquippedEnchants)
        if okMax and type(val) == "number" and val > 0 then maxSlots = val end
    elseif type(save.MaxEnchantsEquipped) == "number" then
        maxSlots = save.MaxEnchantsEquipped
    elseif ranks[save.Rank] and type(ranks[save.Rank].MaxEnchantsEquipped) == "number" then
        maxSlots = ranks[save.Rank].MaxEnchantsEquipped
    end

    local owned = stackList(inventory(save, "Enchant"))
    local usable = {}
    for _, item in ipairs(owned) do
        if CFG.CanUseEnchantTier(item.tier, save) then
            usable[#usable + 1] = item
        end
    end
    if #usable == 0 then notes.enchant = "no usable enchants"; return end

    local prioMap = {}
    for idx, name in ipairs(CFG.EnchantPriority) do
        prioMap[name] = idx
    end
    table.sort(usable, function(a, b)
        local pa = prioMap[a.id] or 999
        local pb = prioMap[b.id] or 999
        if pa ~= pb then return pa < pb end
        if a.tier ~= b.tier then return a.tier > b.tier end
        return tostring(a.uid) < tostring(b.uid)
    end)

    -- Pick highest usable tier per unique enchant first following priority order,
    -- then fill remaining slots with best available enchants if needed.
    local desired = {}
    local usedUid = {}
    local seenType = {}
    for _, item in ipairs(usable) do
        if #desired >= maxSlots then break end
        if not seenType[item.id] then
            seenType[item.id] = true
            usedUid[item.uid] = true
            desired[#desired + 1] = item
        end
    end
    if #desired < maxSlots then
        for _, item in ipairs(usable) do
            if #desired >= maxSlots then break end
            if not usedUid[item.uid] then
                usedUid[item.uid] = true
                desired[#desired + 1] = item
            end
        end
    end

    local equipped = type(save.EquippedEnchants) == "table" and save.EquippedEnchants or {}
    local equippedSet = {}
    for _, uid in pairs(equipped) do
        if type(uid) == "string" then equippedSet[uid] = true end
    end
    local desiredSet = {}
    for _, item in ipairs(desired) do
        desiredSet[item.uid] = true
    end

    local changed = false
    for slotIdx, uid in pairs(equipped) do
        if type(uid) == "string" and not desiredSet[uid] then
            pcall(fire, "Enchants_ClearSlot", tonumber(slotIdx) or slotIdx)
            changed = true
            task.wait(0.05)
        end
    end
    for _, item in ipairs(desired) do
        if not equippedSet[item.uid] then
            pcall(fire, "Enchants_Equip", item.uid)
            changed = true
            task.wait(0.05)
        end
    end
    if changed then nextAt.save = 0 end
    local names = {}
    for _, item in ipairs(desired) do names[#names + 1] = ("%s T%d"):format(item.id, item.tier) end
    notes.enchant = ("equipped (%d/%d): %s"):format(#desired, maxSlots, table.concat(names, ", "))
end

-- White Screen + Reduce CPU / RAM
CFG.PerfState = {
    whiteGui = nil,
    lightingSaved = {},
    qualitySaved = nil,
    fpsRestored = false,
}

function CFG.SyncWhiteScreen()
    local st = CFG.PerfState
    local active = alive and enabled.whiteScreen
    local RunService = game:GetService("RunService")
    pcall(function() RunService:Set3dRenderingEnabled(not active) end)
    local function findMenuGui()
        local roots = {}
        pcall(function() if type(gethui) == "function" then roots[#roots + 1] = gethui() end end)
        pcall(function() roots[#roots + 1] = game:GetService("CoreGui") end)
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then roots[#roots + 1] = pg end
        for _, r in ipairs(roots) do
            local m = r and r:FindFirstChild("StephHUB_UI")
            if m then return m end
        end
        return nil
    end
    if active then
        local menuGui = findMenuGui()
        if menuGui then
            -- Keep Steph HUB menu visible above White Screen so the user can toggle everything on/off
            pcall(function()
                menuGui.Enabled = true
                if menuGui.DisplayOrder < 500 then menuGui.DisplayOrder = 500 end
                local win = menuGui:FindFirstChild("MainWindow")
                if win then win.Visible = true end
            end)
        end
        if not st.whiteGui or not st.whiteGui.Parent then
            local parent = (menuGui and menuGui.Parent) or nil
            if not parent then
                pcall(function() if type(gethui) == "function" then parent = gethui() end end)
            end
            if not parent then
                pcall(function() parent = game:GetService("CoreGui") end)
            end
            if not parent then
                parent = LocalPlayer:FindFirstChild("PlayerGui")
            end
            if parent then
                local gui = Instance.new("ScreenGui")
                gui.Name = "StephHUB_WhiteScreen"
                gui.ResetOnSpawn = false
                gui.IgnoreGuiInset = true
                -- Always below StephHUB_UI (DisplayOrder 500) in the same container
                gui.DisplayOrder = 400
                local bg = Instance.new("Frame")
                bg.Size = UDim2.fromScale(1, 1)
                bg.BackgroundColor3 = Color3.new(1, 1, 1)
                bg.BorderSizePixel = 0
                bg.Parent = gui
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 0, 32)
                lbl.Position = UDim2.new(0, 0, 0, 14)
                lbl.BackgroundTransparency = 1
                lbl.Font = Enum.Font.GothamBold
                lbl.Text = "Steph HUB  -  White Screen Active (3D Render Paused)"
                lbl.TextColor3 = Color3.fromRGB(60, 65, 80)
                lbl.TextSize = 16
                lbl.Parent = bg
                local bar = Instance.new("Frame")
                bar.Size = UDim2.fromOffset(420, 38)
                bar.Position = UDim2.new(0.5, -210, 0, 50)
                bar.BackgroundTransparency = 1
                bar.Parent = bg
                local menuBtn = Instance.new("TextButton")
                menuBtn.Size = UDim2.fromOffset(200, 36)
                menuBtn.Position = UDim2.fromOffset(0, 0)
                menuBtn.BackgroundColor3 = Color3.fromRGB(38, 92, 168)
                menuBtn.BorderSizePixel = 0
                menuBtn.Font = Enum.Font.GothamBold
                menuBtn.Text = "Show / Hide Menu"
                menuBtn.TextColor3 = Color3.new(1, 1, 1)
                menuBtn.TextSize = 14
                menuBtn.Parent = bar
                Instance.new("UICorner", menuBtn).CornerRadius = UDim.new(0, 8)
                menuBtn.MouseButton1Click:Connect(function()
                    local m = findMenuGui()
                    if m then
                        local win = m:FindFirstChild("MainWindow")
                        if win then
                            win.Visible = not win.Visible
                            m.Enabled = true
                        else
                            m.Enabled = not m.Enabled
                        end
                    end
                end)
                local offBtn = Instance.new("TextButton")
                offBtn.Size = UDim2.fromOffset(200, 36)
                offBtn.Position = UDim2.fromOffset(220, 0)
                offBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
                offBtn.BorderSizePixel = 0
                offBtn.Font = Enum.Font.GothamBold
                offBtn.Text = "White Screen: OFF"
                offBtn.TextColor3 = Color3.new(1, 1, 1)
                offBtn.TextSize = 14
                offBtn.Parent = bar
                Instance.new("UICorner", offBtn).CornerRadius = UDim.new(0, 8)
                offBtn.MouseButton1Click:Connect(function()
                    if type(setEnabled) == "function" then
                        pcall(setEnabled, "whiteScreen", false)
                    else
                        enabled.whiteScreen = false
                        CFG.SyncWhiteScreen()
                    end
                end)
                gui.Parent = parent
                st.whiteGui = gui
            end
        end
        notes.whiteScreen = "on (3D render disabled)"
    else
        if st.whiteGui then
            pcall(function() st.whiteGui:Destroy() end)
            st.whiteGui = nil
        end
        notes.whiteScreen = "off"
    end
end

function CFG.SyncReduceCpuRam()
    local st = CFG.PerfState
    local active = alive and enabled.reduceCpuRam
    local Lighting = game:GetService("Lighting")
    local setfps = setfpscap or env.setfpscap
    if active then
        if st.qualitySaved == nil then
            pcall(function() st.qualitySaved = settings().Rendering.QualityLevel end)
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        end
        if type(setfps) == "function" then
            pcall(setfps, math.clamp(tonumber(CFG.LowCpuFpsCap) or 15, 5, 60))
            st.fpsRestored = false
        end
        if st.lightingSaved.GlobalShadows == nil then
            st.lightingSaved.GlobalShadows = Lighting.GlobalShadows
            pcall(function() Lighting.GlobalShadows = false end)
        end
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("PostEffect") and child.Enabled then
                if st.lightingSaved[child] == nil then st.lightingSaved[child] = true end
                pcall(function() child.Enabled = false end)
            end
        end
        suppressEffects("Breakables", optBreakableEffects)
        suppressEffects("Pets", optPetEffects)
        local debris = workspace:FindFirstChild("__DEBRIS")
        if debris then
            for _, child in ipairs(debris:GetChildren()) do
                pcall(function() child:Destroy() end)
            end
        end
        pcall(collectgarbage, "step", 200)
        notes.reduceCpu = ("on (%d fps cap)"):format(math.floor(tonumber(CFG.LowCpuFpsCap) or 15))
    else
        if st.qualitySaved ~= nil then
            local savedQ = st.qualitySaved
            st.qualitySaved = nil
            pcall(function() settings().Rendering.QualityLevel = savedQ end)
        end
        if not st.fpsRestored and type(setfps) == "function" then
            st.fpsRestored = true
            pcall(setfps, 0)
        end
        if st.lightingSaved.GlobalShadows ~= nil then
            local gs = st.lightingSaved.GlobalShadows
            st.lightingSaved.GlobalShadows = nil
            pcall(function() Lighting.GlobalShadows = gs end)
        end
        for fx, _ in pairs(st.lightingSaved) do
            if typeof(fx) == "Instance" and fx.Parent then
                pcall(function() fx.Enabled = true end)
            end
            st.lightingSaved[fx] = nil
        end
        notes.reduceCpu = "off"
    end
end

-- Fast Farm [BETA]: Heartbeat-driven bypass that skips client tap throttle,
-- skips pet walk travel delay by sending CQ_Route + Breakables_JoinPetBulk in
-- the same frame (1 pet = 1 distinct breakable), fires cpet.Arrived, and
-- pushes petSpeedMult = 1e6 / petSpeed = 100 directly to parallel pet actors.
CFG.BetaState = { conn = nil, lastStep = 0 }
function CFG.SyncFastFarmBeta()
    local st = CFG.BetaState
    if not alive or not enabled.fastFarmBeta then
        if st.conn then st.conn:Disconnect(); st.conn = nil end
        notes.betaFarm = "off"
        return
    end
    if st.conn then return end
    if not CFG.BootstrapDone then CFG.BootstrapModules() end
    notes.betaFarm = "running [BETA no-limit bypass]"
    st.conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not alive or not enabled.fastFarmBeta then return end
        local now = os.clock()
        st.lastStep = now
        local point = position()
        if not point then return end
        local zone = currentZone()
        if pickCount(picked.zones) > 0 and zone and not picked.zones[zone] then return end
        if #auraTargets == 0 or now - (target.at or 0) >= 0.04 then
            target.model, target.uid = pickTarget(point, zone)
            target.at = now
        end
        local validList = {}
        local seenM = {}
        if target.model and validTarget(target.model, point, nil) then
            seenM[target.model] = true
            validList[#validList + 1] = { model = target.model, uid = target.model:GetAttribute("BreakableUID") }
        end
        if type(auraTargets) == "table" then
            for _, m in ipairs(auraTargets) do
                if not seenM[m] and validTarget(m, point, nil) then
                    local u = m:GetAttribute("BreakableUID")
                    if u ~= nil then
                        seenM[m] = true
                        validList[#validList + 1] = { model = m, uid = u }
                    end
                end
            end
        end
        if #validList == 0 then
            petState.attackModel, petState.attackUid = nil, nil
            notes.betaFarm = "waiting for breakables"
            return
        end
        if #validList > 1 then
            table.sort(validList, function(a, b)
                local aChest = enabled.chestFirst and tostring(a.model:GetAttribute("BreakableID") or a.model.Name):lower():find("chest", 1, true) ~= nil
                local bChest = enabled.chestFirst and tostring(b.model:GetAttribute("BreakableID") or b.model.Name):lower():find("chest", 1, true) ~= nil
                if aChest ~= bChest then return aChest end
                local ap, bp = modelPosition(a.model), modelPosition(b.model)
                local ad = ap and (ap - point).Magnitude or math.huge
                local bd = bp and (bp - point).Magnitude or math.huge
                return ad < bd
            end)
        end
        -- 1. No-limit multi-target tap damage burst (hits EVERY valid breakable in zone every Heartbeat)
        for i = 1, #validList do
            fire("Breakables_PlayerDealDamage", validList[i].uid)
        end
        petState.lastAttackAt = now
        -- 2. Direct 1-pet-1-breakable CQ_Route + same-frame Breakables_JoinPetBulk bypass
        local mod = modules.pet
        local pets, seenP = {}, {}
        local group = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
        if type(group) == "table" then
            for _, rec in pairs(group) do if not seenP[rec] then seenP[rec] = true; pets[#pets + 1] = rec end end
        end
        for rec in pairs(petState.records) do
            if not seenP[rec] then seenP[rec] = true; pets[#pets + 1] = rec end
        end
        local validByModel = {}
        for _, e in ipairs(validList) do validByModel[e.model] = e.uid end
        local usedByModel = {}
        local cqRoute, joinBulk = {}, {}
        local assignedCount = 0
        for _, rec in ipairs(pets) do
            if not rec.destroyed and (rawget(rec, "owner") == nil or rawget(rec, "owner") == LocalPlayer) then
                local cur = petState.assignedModel[rec]
                if cur and validByModel[cur] and not usedByModel[cur] then
                    usedByModel[cur] = rec
                    petState.assignedUid[rec] = validByModel[cur]
                else
                    petState.assignedModel[rec] = nil
                    petState.assignedUid[rec] = nil
                end
            end
        end
        local idxCursor = 1
        for pIdx, rec in ipairs(pets) do
            if not rec.destroyed and (rawget(rec, "owner") == nil or rawget(rec, "owner") == LocalPlayer) then
                if not petState.assignedModel[rec] then
                    for scan = 1, #validList do
                        local pickIdx = ((idxCursor + scan - 2) % #validList) + 1
                        local entry = validList[pickIdx]
                        if not usedByModel[entry.model] then
                            usedByModel[entry.model] = rec
                            petState.assignedModel[rec] = entry.model
                            petState.assignedUid[rec] = entry.uid
                            idxCursor = (pickIdx % #validList) + 1
                            break
                        end
                    end
                end
                local tModel = petState.assignedModel[rec]
                local tUid = petState.assignedUid[rec]
                if tModel and tUid and tModel.Parent then
                    assignedCount += 1
                    petState.attackModel, petState.attackUid = tModel, tUid
                    local euid = rawget(rec, "euid")
                    if petState.joinedTarget[rec] ~= tModel then
                        petState.joinedTarget[rec] = tModel
                        pcall(function() rec:SetTarget(tModel) end)
                        if euid ~= nil then
                            cqRoute[euid] = { t = 2, v = tUid }
                            joinBulk[euid] = tUid
                        end
                        local tPos = modelPosition(tModel)
                        if tPos then
                            local angle = (pIdx / math.max(#pets, 1)) * math.pi * 2
                            local ringPos = tPos + Vector3.new(math.cos(angle) * 3.0, 0, math.sin(angle) * 3.0)
                            local ringCF = CFrame.lookAt(ringPos, Vector3.new(tPos.X, ringPos.Y, tPos.Z))
                            pcall(function()
                                rec.speedMult = 1e6
                                local cpet = rawget(rec, "cpet")
                                if type(cpet) == "table" then
                                    if cpet.parallelIn then
                                        cpet.parallelIn.petSpeedMult = 1e6
                                        cpet.parallelIn.petSpeed = 100
                                    end
                                    cpet:Broadcast("petSpeedMult", 1e6)
                                    cpet:Broadcast("petSpeed", 100)
                                    if cpet.physical and cpet.physical.Parent then cpet.physical:PivotTo(ringCF) end
                                    if type(cpet.parallelOut) == "table" then
                                        cpet.parallelOut.cf = ringCF
                                        cpet.parallelOut.arrived = true
                                        cpet.parallelOut.farming = true
                                    end
                                    if cpet.actor and type(cpet.actor.SendMessage) == "function" then
                                        cpet.actor:SendMessage("Update", cpet.uid, cpet.bucketId, { petSpeedMult = 1e6, petSpeed = 100 })
                                        cpet.actor:SendMessage("Reposition", cpet.uid, cpet.bucketId)
                                    end
                                    if type(cpet.Arrived) == "table" and type(cpet.Arrived.Fire) == "function" then
                                        cpet.Arrived:Fire()
                                    end
                                end
                            end)
                        end
                    end
                end
            end
        end
        if next(cqRoute) ~= nil then pcall(fire, "CQ_Route", cqRoute) end
        if next(joinBulk) ~= nil then pcall(fire, "Breakables_JoinPetBulk", joinBulk) end
        notes.betaFarm = ("BETA | %d pets -> %d ores"):format(assignedCount, #validList)
    end)
end

-- Item 7: Edit & Cheat in Game (Stats/Currency editor, Gamepass unlocker,
-- Gate/Barrier remover, Visual Huge/Titanic/Gargantuan pet spawner & morpher,
-- Item/Potion/Egg inventory spoofer, Noclip & 3D Flight).
CFG.CheatState = {
    noclipConn = nil,
    flyConn = nil,
    flyBV = nil,
    flyBG = nil,
    gpHooked = false,
    gpOrigOwns = nil,
    gpOrigActive = nil,
    removedParts = setmetatable({}, {__mode = "k"}),
    uidCounter = 1,
}

local function syncNoclip()
    local st = CFG.CheatState
    if not alive or not enabled.noclip then
        if st.noclipConn then st.noclipConn:Disconnect(); st.noclipConn = nil end
        return
    end
    if st.noclipConn then return end
    st.noclipConn = game:GetService("RunService").Stepped:Connect(function()
        if not alive or not enabled.noclip then return end
        local ch = LocalPlayer.Character
        if not ch then return end
        for _, part in ipairs(ch:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

local function syncFly()
    local st = CFG.CheatState
    if not alive or not enabled.fly then
        if st.flyConn then st.flyConn:Disconnect(); st.flyConn = nil end
        if st.flyBV then pcall(function() st.flyBV:Destroy() end); st.flyBV = nil end
        if st.flyBG then pcall(function() st.flyBG:Destroy() end); st.flyBG = nil end
        return
    end
    if st.flyConn then return end
    st.flyConn = game:GetService("RunService").RenderStepped:Connect(function()
        if not alive or not enabled.fly then return end
        local ch = LocalPlayer.Character
        local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart)
        local cam = workspace.CurrentCamera
        if not root or not cam then return end
        if not st.flyBV or st.flyBV.Parent ~= root then
            if st.flyBV then pcall(function() st.flyBV:Destroy() end) end
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            bv.Velocity = Vector3.zero
            bv.Parent = root
            st.flyBV = bv
        end
        if not st.flyBG or st.flyBG.Parent ~= root then
            if st.flyBG then pcall(function() st.flyBG:Destroy() end) end
            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
            bg.P = 9e4
            bg.CFrame = cam.CFrame
            bg.Parent = root
            st.flyBG = bg
        end
        local dir = Vector3.zero
        local cf = cam.CFrame
        if not UIS:GetFocusedTextBox() then
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0, 1, 0) end
        end
        if dir.Magnitude > 0 then dir = dir.Unit * (tonumber(CFG.FlySpeed) or 120) end
        st.flyBV.Velocity = dir
        st.flyBG.CFrame = cf
    end)
end

local function syncGamepasses()
    local st = CFG.CheatState
    local active = alive and enabled.unlockGamepasses
    local save = getSave()
    if save and active then
        save.BypassTeleportRequirement = true
        save.AutoTapper = true
        pcall(function() workspace:SetAttribute("GlobalInstantHatch", true) end)
        pcall(function() workspace:SetAttribute("GlobalPetFly", true) end)
    end
    local gp = modules.gamepasses
    if not gp then
        local ok, req = pcall(function()
            local lib = RS:FindFirstChild("Library")
            local cli = lib and lib:FindFirstChild("Client")
            local mod = cli and cli:FindFirstChild("Gamepasses")
            return mod and require(mod) or nil
        end)
        if ok and type(req) == "table" then
            gp = req
            modules.gamepasses = gp
        end
    end
    if gp and active and not st.gpHooked then
        st.gpOrigOwns = gp.Owns
        st.gpOrigActive = gp.Active
        pcall(function()
            gp.Owns = function() return true end
            gp.Active = function() return true end
            st.gpHooked = true
        end)
    elseif gp and not active and st.gpHooked then
        pcall(function()
            if st.gpOrigOwns then gp.Owns = st.gpOrigOwns end
            if st.gpOrigActive then gp.Active = st.gpOrigActive end
        end)
        st.gpHooked = false
    end
end

local function syncGates()
    local st = CFG.CheatState
    if alive and enabled.removeGates then
        for _, borderName in ipairs({"Border", "Border2", "Border3", "Border4"}) do
            local b = workspace:FindFirstChild(borderName)
            if b then
                for _, part in ipairs(b:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        st.removedParts[part] = {canCollide = part.CanCollide, transparency = part.Transparency}
                        part.CanCollide = false
                    end
                end
            end
        end
        for w = 1, CFG.WorldCount do
            local map = workspace:FindFirstChild(w == 1 and "Map" or ("Map" .. w))
            if map then
                for _, part in ipairs(map:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        local n = part.Name:lower()
                        local pName = part.Parent and part.Parent.Name:lower() or ""
                        if n:find("gate", 1, true) or n:find("barrier", 1, true) or n:find("forcefield", 1, true)
                            or pName:find("gate", 1, true) or pName:find("barrier", 1, true) then
                            st.removedParts[part] = {canCollide = part.CanCollide, transparency = part.Transparency}
                            part.CanCollide = false
                            part.Transparency = 1
                        end
                    end
                end
            end
        end
    else
        for part, prev in pairs(st.removedParts) do
            if part and part.Parent then
                pcall(function()
                    part.CanCollide = prev.canCollide
                    part.Transparency = prev.transparency
                end)
            end
        end
        table.clear(st.removedParts)
    end
end

local function runCheatAction(action, params)
    params = type(params) == "table" and params or {}
    local save = getSave()
    local function fireStatChange(key)
        if modules.save and type(modules.save.FireStatChangedForManuallyChangedSave) == "function" then
            pcall(modules.save.FireStatChangedForManuallyChangedSave, key, LocalPlayer)
        end
    end
    if action == "setStat" then
        if not save then return false, "save profile not loaded yet" end
        local key = tostring(params.key or "")
        local val = tonumber(params.value)
        if not val then return false, "invalid numeric value" end
        save[key] = val
        if key == "Diamonds" or key == "Coins" then
            local curr = inventory(save, "Currency")
            if curr then
                local matched = false
                for _, entry in pairs(curr) do
                    if type(entry) == "table" and entry.id == key then
                        entry._am = val
                        matched = true
                    end
                end
                if not matched then
                    curr["cheat_" .. key:lower()] = {id = key, _am = val}
                end
            end
            fireStatChange("Inventory")
        end
        fireStatChange(key)
        notes.cheat = ("edited %s = %s"):format(key, tostring(val))
        return true, notes.cheat
    elseif action == "unlockAllZones" then
        if not save then return false, "save profile not loaded yet" end
        save.UnlockedZones = type(save.UnlockedZones) == "table" and save.UnlockedZones or {}
        for _, z in pairs(zones) do
            save.UnlockedZones[z.id] = true
        end
        save.BypassTeleportRequirement = true
        fireStatChange("UnlockedZones")
        notes.cheat = "unlocked all 279 zones locally"
        return true, notes.cheat
    elseif action == "spawnItem" then
        if not save then return false, "save profile not loaded yet" end
        local bucket = tostring(params.bucket or "Misc")
        local id = tostring(params.id or "")
        if #id == 0 then return false, "missing item id" end
        local amount = math.max(1, math.floor(tonumber(params.amount) or 1))
        local tier = tonumber(params.tier)
        save.Inventory = type(save.Inventory) == "table" and save.Inventory or {}
        save.Inventory[bucket] = type(save.Inventory[bucket]) == "table" and save.Inventory[bucket] or {}
        local uid = ("zapx_%s_%d"):format(bucket:lower(), CFG.CheatState.uidCounter)
        CFG.CheatState.uidCounter += 1
        local record = {id = id, _am = amount}
        if tier and (bucket == "Potion" or bucket == "Enchant" or bucket == "XPPotion") then
            record.tn = math.clamp(math.floor(tier), 1, 11)
        end
        if params.pt and tonumber(params.pt) and tonumber(params.pt) > 0 then
            record.pt = tonumber(params.pt)
        end
        if params.sh == true then
            record.sh = true
        end
        save.Inventory[bucket][uid] = record
        fireStatChange("Inventory")
        notes.cheat = ("spawned %s x%d in %s"):format(id, amount, bucket)
        return true, notes.cheat
    elseif action == "morphPets" then
        if not save then return false, "save profile not loaded yet" end
        local newId = tostring(params.id or "Huge Cat")
        local pt = tonumber(params.pt)
        local sh = params.sh == true
        local morphed = 0
        local petBucket = inventory(save, "Pet")
        if petBucket then
            for _, data in pairs(petBucket) do
                if type(data) == "table" then
                    data.id = newId
                    data.pt = (pt and pt > 0) and pt or nil
                    data.sh = sh or nil
                    morphed += 1
                end
            end
        end
        local mod = modules.pet
        local group = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
        if type(group) == "table" then
            for _, record in pairs(group) do
                pcall(function()
                    if type(record.item) == "table" then
                        record.item._data.id = newId
                        record.item._data.pt = (pt and pt > 0) and pt or nil
                        record.item._data.sh = sh or nil
                    end
                end)
            end
        end
        fireStatChange("Inventory")
        notes.cheat = ("morphed %d pets -> %s"):format(morphed, newId)
        return true, notes.cheat
    end
    return false, "unknown cheat action: " .. tostring(action)
end

local function httpGet(url)
    if type(game.HttpGet) == "function" then
        local ok, body = pcall(game.HttpGet, game, url)
        if ok then return body end
    end
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if type(req) == "function" then
        local ok, response = pcall(req, {Url = url, Method = "GET"})
        if ok and type(response) == "table" then return response.Body or response.body end
    end
    return nil
end

CFG.Hop = {
    inProgress = false,
    startedAt = 0,
    targetJobId = nil,
    blacklist = {}, -- [jobId] = expireClock
    failCount = 0,
    forceRetry = false,
    conn = nil,
}

function CFG.Hop.FetchCandidates(force)
    local now = os.clock()
    for jobId, exp in pairs(CFG.Hop.blacklist) do
        if exp <= now then CFG.Hop.blacklist[jobId] = nil end
    end
    local httpSvc = game:GetService("HttpService")
    local candidates = {}
    local cursor = nil
    for _ = 1, 3 do
        local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true")
            :format(tostring(game.PlaceId))
        if cursor and #cursor > 0 then
            url = url .. "&cursor=" .. httpSvc:UrlEncode(cursor)
        end
        local body = httpGet(url)
        if not body then break end
        local ok, data = pcall(function() return httpSvc:JSONDecode(body) end)
        if not ok or type(data) ~= "table" or type(data.data) ~= "table" then break end
        for _, server in ipairs(data.data) do
            if type(server) == "table" and type(server.id) == "string" and #server.id > 0
                and server.id ~= game.JobId and not CFG.Hop.blacklist[server.id]
                and type(server.playing) == "number" and server.playing >= 1
                and type(server.maxPlayers) == "number" and server.playing < server.maxPlayers then
                if force or server.playing < CFG.HopMaxPlayers then
                    candidates[#candidates + 1] = server
                end
            end
        end
        if #candidates >= 10 then break end
        cursor = type(data.nextPageCursor) == "string" and data.nextPageCursor or nil
        if not cursor or #cursor == 0 then break end
    end
    table.sort(candidates, function(a, b)
        if a.playing ~= b.playing then return a.playing < b.playing end
        return (tonumber(a.ping) or 9999) < (tonumber(b.ping) or 9999)
    end)
    return candidates
end

local hopTick
function CFG.Hop.EnsureListener()
    if CFG.Hop.conn then return end
    local tpSvc = game:GetService("TeleportService")
    CFG.Hop.conn = connect(tpSvc.TeleportInitFailed, function(plr, tpResult, errMsg)
        if plr ~= LocalPlayer then return end
        CFG.Hop.inProgress = false
        CFG.Hop.failCount += 1
        if CFG.Hop.targetJobId then
            CFG.Hop.blacklist[CFG.Hop.targetJobId] = os.clock() + 180
        end
        local code = tostring(tpResult and tpResult.Name or "Failed")
        notes.hop = ("teleport failed (%s): %s; retrying"):format(code, tostring(errMsg or "err"))
        if alive and (enabled.serverHop or CFG.Hop.forceRetry) then
            task.delay(1.5, function()
                if not alive then return end
                if enabled.serverHop or CFG.Hop.forceRetry then
                    hopTick(CFG.Hop.forceRetry)
                end
            end)
        end
    end)
end

hopTick = function(force)
    CFG.Hop.EnsureListener()
    local now = os.clock()
    if CFG.Hop.inProgress and (now - CFG.Hop.startedAt) < 12 then
        notes.hop = "teleport already in progress..."
        return
    end
    local count = #Players:GetPlayers()
    if not force and count <= CFG.HopMaxPlayers then
        notes.hop = ("server has %d players (limit %d)"):format(count, CFG.HopMaxPlayers)
        return
    end
    CFG.Hop.forceRetry = force == true
    local tpSvc = game:GetService("TeleportService")

    if CFG.Hop.failCount >= 3 then
        CFG.Hop.failCount = 0
        CFG.Hop.inProgress = true
        CFG.Hop.startedAt = now
        CFG.Hop.targetJobId = nil
        notes.hop = "fallback random server hop (PlaceId " .. tostring(game.PlaceId) .. ")"
        local ok, err = pcall(function() tpSvc:Teleport(game.PlaceId, LocalPlayer) end)
        if not ok then
            CFG.Hop.inProgress = false
            notes.hop = "fallback hop error: " .. tostring(err)
        end
        return
    end

    local candidates = CFG.Hop.FetchCandidates(force)
    if #candidates == 0 then
        if force then
            CFG.Hop.inProgress = true
            CFG.Hop.startedAt = now
            CFG.Hop.targetJobId = nil
            notes.hop = "no listed server; hopping to fresh server"
            local ok, err = pcall(function() tpSvc:Teleport(game.PlaceId, LocalPlayer) end)
            if not ok then
                CFG.Hop.inProgress = false
                notes.hop = "hop error: " .. tostring(err)
            end
        else
            notes.hop = "no low-player server found"
        end
        return
    end

    for _, server in ipairs(candidates) do
        CFG.Hop.inProgress = true
        CFG.Hop.startedAt = os.clock()
        CFG.Hop.targetJobId = server.id
        notes.hop = ("hopping to %d/%d player server"):format(server.playing, server.maxPlayers)
        local ok, err = pcall(function()
            tpSvc:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
        end)
        if ok then
            return
        end
        CFG.Hop.inProgress = false
        CFG.Hop.blacklist[server.id] = os.clock() + 180
        CFG.Hop.failCount += 1
        notes.hop = "server rejected (" .. tostring(err) .. "); trying next"
    end
    notes.hop = "all candidate servers failed; retrying next tick"
end

-- =========================================================================
-- Current Event: Pumpkin Tycoon (Part 1 + Part 2 Zones 1..8, Wild Pets, Turkey)
-- =========================================================================
CFG.EventOpts = {
    moveMode = "Teleport", -- "Teleport" | "Legit Walk"
    keepRung = 4,          -- 0=Off, 1=Basic..8=Secret
    huntMinTier = 0,       -- 0=Any, 1=Uncommon, 2=Rare, 3=Epic, 4=Huge
    huntVariant = false,
    huntUltraHuge = true,
    catchMinNet = "Auto",  -- "Auto" | "Pet Net" | "Ultra Pet Net"
    merchantBands = { RarePlus = true, EpicPlus = true, LegendaryPlus = true, MythicalPlus = true, ExoticPlus = true },
    upgradeTracks = { SpawnLuck = true, PumpkinCoins = true, PumpkinDamage = true, RespawnSpeed = true, StockSlots = true, ChaseOdds = true, EggLuck = true, MerchantLuck = true },
    cocoaBoosts = { PumpkinTycoonCoins1 = true, PumpkinTycoonDamage1 = true, PumpkinTycoonIslandLuck1 = true },
    pumpkinBoosts = { ["Patch Coin Boost"] = true, ["Pumpkin Damage Boost"] = true, ["Island Luck Boost"] = true },
}

CFG.Event = {
    ZONES = {
        { Section = "CocoaCabin",  Name = "Cocoa Cabin",   Egg = "Cocoa Cabin Egg",   Part = 1 },
        { Section = "AppleOrchard",Name = "Apple Orchard", Egg = "Apple Orchard Egg", Part = 1 },
        { Section = "HayrideHill", Name = "Hayride Hill",  Egg = "Hayride Hill Egg",  Part = 1 },
        { Section = "CiderMill",   Name = "Cider Mill",    Egg = "Cider Mill Egg",    Part = 1 },
        { Section = "GoldenGrove", Name = "Golden Grove",  Egg = "Golden Grove Egg",  Part = 1 },
        { Section = "Zone6",       Name = "Pine Woods",    Egg = "Pine Woods Egg",    Part = 2 },
        { Section = "Zone7",       Name = "Maple Creek",   Egg = "Maple Creek Egg",   Part = 2 },
        { Section = "Zone8",       Name = "Golden Ridge",  Egg = "Golden Ridge Egg",  Part = 2 },
    },
    LADDER = { "Basic", "Rare", "Epic", "Legendary", "Mythical", "Exotic", "Divine", "Secret" },
    NET = {
        Buy = "NZ_Commit", BuyBand = "FZ_Reserve", CocoaBuyTime = "VB_Extend",
        SetAutoBreak = "QW_Policy", SetLock = "KT_Shelter", PlaceStock = "XC_Allocate",
        SetAutoPlace = "JD_Prefer", SetAutoMerchant = "HM_Sustain", UpgradeBuy = "OQ_Advance",
        GiftOpen = "YR_Hydrate", Complete = "BT_Settle", Complete2 = "MH_Conclude",
        Rebirth = "EW_Renew", CatchWild = "RU_Ensnare", CatchSighting = "PV_Glimpse",
        SetHunt = "LF_Pursue", Cannon = "TC_Launch", BuyNet = "ZK_Barter",
        NetShelf = "QS_Survey", SetAutoNets = "GN_Restock",
    },
    next = {
        opt = 0, tele = 0, egg = 0, btn = 0, rebirth = 0, keep = 0, breakP = 0,
        merch = 0, plant = 0, upg = 0, cocoa = 0, boost = 0, gift = 0,
        hunt = 0, wild = 0, net = 0, turkey = 0, rare = 0,
    },
    walkTarget = nil,
}

function CFG.Event.Cmds()
    if modules.pumpkinTycoon then return modules.pumpkinTycoon end
    local lib = RS:FindFirstChild("Library")
    local cli = lib and lib:FindFirstChild("Client")
    local pt = cli and cli:FindFirstChild("PumpkinTycoonCmds")
    if pt then
        local ok, mod = pcall(require, pt)
        if ok and type(mod) == "table" then modules.pumpkinTycoon = mod; return mod end
    end
    return nil
end

function CFG.Event.Feature(name)
    local cmds = CFG.Event.Cmds()
    if cmds and type(cmds.Feature) == "function" then
        local ok, f = pcall(cmds.Feature, name)
        if ok and type(f) == "table" then return f end
    end
    return nil
end

function CFG.Event.Plot()
    local island = CFG.Event.Feature("Island")
    if island and type(island.Plot) == "function" then
        local ok, p = pcall(island.Plot)
        if ok and p then return p end
    end
    return nil
end

function CFG.Event.PlotInvoke(plot, verb, ...)
    if not plot then return false, "no plot" end
    if type(plot.Invoke) == "function" then
        local ok, r1, r2, r3 = pcall(plot.Invoke, plot, verb, ...)
        if ok then return r1, r2, r3 end
    end
    local pid = type(plot.GetId) == "function" and plot:GetId() or plot.Id
    if pid then
        return invoke("Plots_Invoke", pid, verb, ...)
    end
    return false, "plot id missing"
end

function CFG.Event.Currency(save, currId)
    local c = inventory(save, "Currency")
    if c then
        for _, entry in pairs(c) do
            if type(entry) == "table" and entry.id == currId then
                return tonumber(entry._am) or 0
            end
        end
    end
    local lib = RS:FindFirstChild("Library")
    local itemsMod = lib and lib:FindFirstChild("Items")
    if itemsMod then
        local ok, items = pcall(require, itemsMod)
        if ok and type(items) == "table" and type(items.Currency) == "function" then
            local ok2, obj = pcall(items.Currency, currId)
            if ok2 and type(obj) == "table" and type(obj.CountAny) == "function" then
                local ok3, val = pcall(obj.CountAny, obj)
                if ok3 and type(val) == "number" then return val end
            end
        end
    end
    return 0
end

function CFG.Event.MoveTo(targetPos)
    if typeof(targetPos) ~= "Vector3" then return false end
    local ch = LocalPlayer.Character
    local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart)
    if not root then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if hum and hum.Sit then
        pcall(function() hum.Sit = false end)
    end
    local dist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
    if dist <= 6 then return true end
    if CFG.EventOpts.moveMode == "Legit Walk" and dist < 250 and hum then
        pcall(function() hum:MoveTo(targetPos) end)
        return true
    end
    return snapTo(targetPos)
end

function CFG.Event.TeleToFarm()
    if not CFG.Event.InInstance() then
        local okE, msgE = CFG.Event.Enter()
        if not okE then return false, tostring(msgE or "failed to enter event") end
        task.wait(0.6)
    end
    local plot = nil
    for _ = 1, 15 do
        plot = CFG.Event.Plot()
        if plot then break end
        task.wait(0.2)
    end
    if not plot then return false, "event plot not loaded yet" end
    local bestZ = CFG.Event.OwnedZones(plot)
    local targetPos = CFG.Event.FarmCenter(plot, bestZ)
    if not targetPos then return false, "event farm center unavailable" end
    local okM = CFG.Event.MoveTo(targetPos)
    local zName = (CFG.Event.ZONES[bestZ] and CFG.Event.ZONES[bestZ].Name) or ("Zone " .. tostring(bestZ))
    return okM, okM and ("teleported to middle of event farm: " .. zName) or "character unavailable"
end

function CFG.Event.InInstance()
    local inst = modules.instancing
    if inst then
        if type(inst.IsInInstance) == "function" then
            local okI, resI = pcall(inst.IsInInstance, "PumpkinTycoon")
            if okI and resI == true then return true end
        end
        if type(inst.Get) == "function" then
            local ok, cur = pcall(inst.Get)
            if ok and type(cur) == "table" and cur.instanceID == "PumpkinTycoon" then
                return true
            end
        end
    end
    local ic = thingsFolder("__INSTANCE_CONTAINER")
    local active = ic and ic:FindFirstChild("Active")
    if active and active:FindFirstChild("PumpkinTycoon") then
        return true
    end
    return false
end

function CFG.Event.Enter()
    local function ensureOnPlot()
        local plot = nil
        for _ = 1, 20 do
            plot = CFG.Event.Plot()
            if plot and (type(plot.GetModel) ~= "function" or plot:GetModel()) then break end
            task.wait(0.2)
        end
        if plot then
            local island = CFG.Event.Feature("Island")
            if island and type(island.Show) == "function" then
                pcall(island.Show, plot, 8)
            end
            if type(plot.LocalTeleport) == "function" then
                local okLT, resLT = pcall(plot.LocalTeleport, plot)
                if okLT and resLT == true then return end
            end
            if type(plot.GetModel) == "function" then
                local model = plot:GetModel()
                if model then
                    local sp = model:FindFirstChild("SpawnPosition", true)
                    local target = (sp and sp:IsA("BasePart") and sp.Position) or modelPosition(model)
                    local myPos = position()
                    if target and (not myPos or (myPos - target).Magnitude > 250 or myPos.Y < target.Y - 60) then
                        snapTo(target + Vector3.new(0, 3, 0))
                    end
                end
            end
        end
    end
    if CFG.Event.InInstance() then
        ensureOnPlot()
        return true, "already inside Pumpkin Tycoon"
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild("PumpkinTycoon") then
        pcall(fire, "Instancing_PlayerLeaveInstance")
        task.wait(1.0)
    end
    local inst = modules.instancing
    if inst then
        if type(inst.Enter) == "function" then
            local okE, resE = pcall(inst.Enter, "PumpkinTycoon")
            if okE and resE ~= false then
                for _ = 1, 25 do
                    if CFG.Event.InInstance() then break end
                    task.wait(0.2)
                end
                ensureOnPlot()
                return true, "entered Pumpkin Tycoon"
            end
        end
        if type(inst.GetEnterPart) == "function" then
            local okP, part = pcall(inst.GetEnterPart, "PumpkinTycoon")
            if okP and typeof(part) == "Instance" and part:IsA("BasePart") then
                snapTo(part.Position)
                task.wait(0.25)
            end
        end
    end
    local ok, msg = invoke("Instancing_PlayerEnterInstance", "PumpkinTycoon")
    if ok == true then
        ensureOnPlot()
        return true, "entered Pumpkin Tycoon"
    end
    return false, tostring(msg or "failed to enter Pumpkin Tycoon")
end

function CFG.Event.FindCustomEgg(eggId)
    local ce = modules.customEggs
    if not ce then
        local cli = RS:FindFirstChild("Library") and RS.Library:FindFirstChild("Client")
        local mod = cli and cli:FindFirstChild("CustomEggsCmds")
        if mod then
            local ok, loaded = pcall(require, mod)
            if ok and type(loaded) == "table" then ce = loaded; modules.customEggs = loaded end
        end
    end
    if not ce then return nil, nil end
    local obj = nil
    local function resolveObj(res)
        if type(res) == "table" then return res end
        if type(res) == "string" and type(ce.Get) == "function" then
            local okG, got = pcall(ce.Get, res)
            if okG and type(got) == "table" then return got end
        end
        return nil
    end
    if type(ce.GetClosestById) == "function" then
        local ok, res = pcall(ce.GetClosestById, eggId)
        if ok and res then obj = resolveObj(res) end
    end
    if not obj and type(ce.GetById) == "function" then
        local ok, res = pcall(ce.GetById, eggId)
        if ok and res then obj = resolveObj(res) end
    end
    if not obj and type(ce.All) == "function" then
        local ok, all = pcall(ce.All)
        if ok and type(all) == "table" then
            for _, entry in pairs(all) do
                local eid = type(entry) == "table" and (entry._id or entry.id or (entry.dir and entry.dir._id))
                if eid == eggId then obj = entry; break end
            end
        end
    end
    if not obj then return nil, nil end
    local uid = obj._uid or obj.uid
    local pos = nil
    if type(obj.GetPosition) == "function" then
        local okP, p = pcall(obj.GetPosition, obj)
        if okP and typeof(p) == "Vector3" then pos = p end
    end
    if not pos and typeof(obj._model) == "Instance" then
        pos = modelPosition(obj._model)
    end
    return uid, pos
end

function CFG.Event.CollectBreakables()
    local found = {}
    local bf = modules.breakableFrontend
    if not bf then
        local cli = RS:FindFirstChild("Library") and RS.Library:FindFirstChild("Client")
        local mod = cli and cli:FindFirstChild("BreakableFrontend")
        if mod then
            local ok, loaded = pcall(require, mod)
            if ok and type(loaded) == "table" then bf = loaded; modules.breakableFrontend = loaded end
        end
    end
    local reg = bf or modules.breakables
    local getRecord = (bf and bf.Get) or (modules.breakables and modules.breakables.Get)
    if reg then
        local list = nil
        if type(reg.AllByInstanceAndClasses) == "function" then
            local ok, r = pcall(reg.AllByInstanceAndClasses, "Chest", "Normal")
            if ok and type(r) == "table" then list = r end
        end
        if (not list or next(list) == nil) and type(reg.AllByInstanceAndClass) == "function" then
            local ok, r = pcall(reg.AllByInstanceAndClass, "Chest")
            if ok and type(r) == "table" then list = r end
        end
        if list then
            for uid, val in pairs(list) do
                local rec = type(val) == "table" and val.clientAttributes and val or nil
                if not rec and type(getRecord) == "function" then
                    local okG, g = pcall(getRecord, uid)
                    if okG and type(g) == "table" then rec = g end
                end
                if rec then
                    found[rec.uid or uid] = rec
                elseif typeof(val) == "Instance" then
                    found[uid] = { uid = uid, model = val, clientAttributes = val:GetAttributes() }
                end
            end
        end
    end
    if next(found) == nil then
        local root = thingsFolder("Breakables")
        if root then
            for _, child in ipairs(root:GetChildren()) do
                local uid = child:GetAttribute("BreakableUID") or child.Name
                local rec = type(getRecord) == "function" and select(2, pcall(getRecord, uid)) or nil
                if type(rec) == "table" then
                    found[rec.uid or uid] = rec
                else
                    local attrs = child:GetAttributes()
                    if type(attrs.PumpkinPedestal) == "number" or attrs.PumpkinTurkey == true then
                        found[uid] = { uid = uid, model = child, clientAttributes = attrs }
                    end
                end
            end
        end
    end
    return found
end

function CFG.Event.OwnedZones(plot)
    local btns = plot and type(plot.Save) == "function" and plot:Save("Buttons") or {}
    local maxZ = 1
    for i = 1, #CFG.Event.ZONES do
        local z = CFG.Event.ZONES[i]
        if btns and ((btns[z.Section .. "_Zone"] ~= nil and btns[z.Section .. "_Zone"] ~= false)
            or (btns[z.Section .. "_Egg"] ~= nil and btns[z.Section .. "_Egg"] ~= false)) then
            maxZ = i
        end
    end
    return maxZ, btns or {}
end

function CFG.Event.ZonePos(plot, zIdx)
    if not plot then return nil, nil end
    local z = CFG.Event.ZONES[zIdx]
    if z and z.Egg then
        local _, cePos = CFG.Event.FindCustomEgg(z.Egg)
        if cePos then
            return cePos + Vector3.new(0, 2, 6), cePos
        end
    end
    local model = type(plot.GetModel) == "function" and plot:GetModel() or nil
    local island = CFG.Event.Feature("Island")
    local decor = island and type(island.Decor) == "function" and island.Decor(plot) or nil
    for _, container in ipairs({ decor, model }) do
        if container and z then
            local eggModel = container:FindFirstChild(z.Egg, true) or container:FindFirstChild(z.Section .. "_Egg", true)
            if eggModel then
                local p = modelPosition(eggModel)
                if p then return p + Vector3.new(0, 2, 6), p end
            end
            local zonePart = container:FindFirstChild("WildArea_" .. zIdx, true) or container:FindFirstChild(z.Section, true)
            if zonePart then
                local p = modelPosition(zonePart)
                if p then return p, p end
            end
        end
    end
    if model then
        local okU, ptBtns = pcall(require, RS.Library.Util.PumpkinTycoonButtons)
        if okU and ptBtns and type(ptBtns.ZoneSlab) == "function" then
            local okS, slab = pcall(ptBtns.ZoneSlab, model, zIdx)
            if okS and slab then
                local p = modelPosition(slab)
                if p then return p + Vector3.new(0, 3, 0), p end
            end
        end
    end
    return model and modelPosition(model) or nil, nil
end

local EVENT_DEBRIS_FX = {
    TurkeyFlash = true, TurkeyBreakRing = true, TurkeyBeacon = true,
    TurkeyCoin = true, TurkeyOrb = true, TurkeyMeteor = true,
    PumpkinBeacon = true, PumpkinPillar = true, PumpkinBloom = true, PumpkinChunk = true,
}

function CFG.Event.Optimize(now)
    if now < CFG.Event.next.opt then return end
    CFG.Event.next.opt = now + 5.0
    local Lighting = game:GetService("Lighting")
    for _, name in ipairs({ "PumpkinFxFlash", "PumpkinFxDim", "TurkeyFlash" }) do
        local fx = Lighting:FindFirstChild(name)
        if fx then pcall(function() fx:Destroy() end) end
    end
    local ptFX = CFG.Event.Feature("PumpkinFx")
    if ptFX and type(ptFX.ClearAll) == "function" then pcall(ptFX.ClearAll) end
    local debris = workspace:FindFirstChild("__DEBRIS")
    if debris then
        for _, child in ipairs(debris:GetChildren()) do
            if EVENT_DEBRIS_FX[child.Name] then
                pcall(function() child:Destroy() end)
            end
        end
    end
    local instFolder = thingsFolder("Instances")
    local icFolder = thingsFolder("__INSTANCE_CONTAINER")
    for _, ptInst in ipairs({ instFolder and instFolder:FindFirstChild("PumpkinTycoon"), icFolder and icFolder:FindFirstChild("PumpkinTycoon") }) do
        if ptInst then
            local shared = ptInst:FindFirstChild("PumpkinTycoonShared")
            if shared then
                suppressEffects("Instances", optBreakableEffects)
                local arena = shared:FindFirstChild("TurkeyArena", true)
                if arena then
                    for _, child in ipairs(arena:GetDescendants()) do
                        if EFFECT_CLASSES[child.ClassName] then
                            pcall(function() child.Enabled = false end)
                        end
                    end
                end
            end
            for _, child in ipairs(ptInst:GetDescendants()) do
                if EFFECT_CLASSES[child.ClassName] then
                    if optBreakableEffects[child] == nil then optBreakableEffects[child] = child.Enabled end
                    pcall(function() child.Enabled = false end)
                end
            end
        end
    end
    local islandsFolder = workspace:FindFirstChild("PumpkinTycoonIslands")
    if islandsFolder then
        for _, child in ipairs(islandsFolder:GetDescendants()) do
            if EFFECT_CLASSES[child.ClassName] then
                pcall(function() child.Enabled = false end)
            end
        end
    end
end

function CFG.Event.TeleBestEgg(now, plot)
    if now < CFG.Event.next.tele then return end
    CFG.Event.next.tele = now + 2.0
    local bestZ = CFG.Event.OwnedZones(plot)
    local targetPos = CFG.Event.ZonePos(plot, bestZ)
    if targetPos then
        CFG.Event.MoveTo(targetPos)
    end
end

function CFG.Event.FarmCenter(plot, zIdx)
    if not plot then return nil end
    local z = CFG.Event.ZONES[zIdx]
    local model = type(plot.GetModel) == "function" and plot:GetModel() or nil
    local island = CFG.Event.Feature("Island")
    local decor = island and type(island.Decor) == "function" and island.Decor(plot) or nil

    -- 0. First priority: live breakable items on the player's event plot near this zone
    local zoneHint = nil
    for _, container in ipairs({ decor, model }) do
        if container and z then
            local sec = container:FindFirstChild(z.Section, true)
            if sec then
                zoneHint = modelPosition(sec)
                if zoneHint then break end
            end
        end
    end
    local okB, liveBreakables = pcall(CFG.Event.CollectBreakables)
    if okB and type(liveBreakables) == "table" then
        local bSum, bCount, bMaxY = Vector3.zero, 0, -math.huge
        for _, rec in pairs(liveBreakables) do
            local pos = rec and (rec.position or (rec.model and modelPosition(rec.model)))
            if typeof(pos) == "Vector3" then
                if not zoneHint or (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(zoneHint.X, 0, zoneHint.Z)).Magnitude <= 90 then
                    bSum += pos
                    bCount += 1
                    if pos.Y > bMaxY then bMaxY = pos.Y end
                end
            end
        end
        if bCount >= 1 then
            return Vector3.new(bSum.X / bCount, bMaxY + 2, bSum.Z / bCount)
        end
    end

    -- 1. Explicit farm / breakable zone parts inside the zone section
    for _, container in ipairs({ decor, model }) do
        if container and z then
            local section = container:FindFirstChild(z.Section, true)
            if section then
                for _, key in ipairs({ "BREAK_ZONES", "BreakZone", "BreakableZone", "FarmArea", "FarmZone", "Patch", "WildArea_" .. zIdx }) do
                    local hit = section:FindFirstChild(key, true)
                    if hit then
                        if hit:IsA("BasePart") then
                            return Vector3.new(hit.Position.X, hit.Position.Y + hit.Size.Y * 0.5 + 2, hit.Position.Z)
                        elseif hit:IsA("Model") or hit:IsA("Folder") then
                            local sum, n, maxY = Vector3.zero, 0, -math.huge
                            for _, p in ipairs(hit:GetDescendants()) do
                                if p:IsA("BasePart") then
                                    sum += p.Position
                                    n += 1
                                    if p.Position.Y + p.Size.Y * 0.5 > maxY then maxY = p.Position.Y + p.Size.Y * 0.5 end
                                end
                            end
                            if n > 0 then
                                return Vector3.new(sum.X / n, maxY + 2, sum.Z / n)
                            end
                        end
                    end
                end
                -- 2. Average pumpkin pedestals inside the section to get exact middle of the farm patch
                local sum, n, maxY = Vector3.zero, 0, -math.huge
                for _, desc in ipairs(section:GetDescendants()) do
                    local nm = desc.Name:lower()
                    if nm:find("pedestal", 1, true) or nm:find("pumpkin", 1, true) or nm:find("plot", 1, true) then
                        local pos = desc:IsA("BasePart") and desc.Position or (desc:IsA("Model") and modelPosition(desc))
                        if pos then
                            sum += pos
                            n += 1
                            if pos.Y > maxY then maxY = pos.Y end
                        end
                    end
                end
                if n >= 2 then
                    return Vector3.new(sum.X / n, maxY + 2, sum.Z / n)
                end
                -- 3. Section model bounding-box upper center (never below floor)
                if section:IsA("Model") then
                    local okBox, cf, size = pcall(function() return section:GetBoundingBox() end)
                    if okBox and cf and size then
                        return Vector3.new(cf.Position.X, cf.Position.Y + size.Y * 0.15 + 2, cf.Position.Z)
                    end
                end
                local sp = modelPosition(section)
                if sp then return sp + Vector3.new(0, 4, 0) end
            end
            local wildArea = container:FindFirstChild("WildArea_" .. zIdx, true)
            if wildArea then
                local wp = wildArea:IsA("BasePart") and wildArea.Position or modelPosition(wildArea)
                if wp then return wp + Vector3.new(0, 4, 0) end
            end
        end
    end
    local fallback = CFG.Event.ZonePos(plot, zIdx)
    return fallback
end

function CFG.Event.TeleNearestFarm(now, plot)
    if now < (CFG.Event.next.nearFarm or 0) then return end
    CFG.Event.next.nearFarm = now + 1.0
    local myPos = position()
    if not myPos then return end
    -- Force find the nearest breakable zone (preferring live breakable clusters) and snap to its middle
    local bestZ = CFG.Event.OwnedZones(plot)
    local nearestPos, nearestDist = nil, math.huge
    local bestPos = nil
    for zIdx = 1, bestZ do
        local zPos = CFG.Event.FarmCenter(plot, zIdx)
        if zPos then
            if zIdx == bestZ then bestPos = zPos end
            local d = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(zPos.X, 0, zPos.Z)).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearestPos = zPos
            end
        end
    end
    local targetPos = nearestPos or bestPos
    if targetPos then
        local d2 = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
        if d2 > 8 then
            snapTo(targetPos)
        end
    end
end

function CFG.Event.BuyButtons(now, plot, save)
    if now < CFG.Event.next.btn then return end
    CFG.Event.next.btn = now + 0.6
    local _, btnsSave = CFG.Event.OwnedZones(plot)
    local ptButtonsUtil = nil
    pcall(function() ptButtonsUtil = require(RS.Library.Util.PumpkinTycoonButtons) end)
    local p2Built = CFG.Event.Cmds() and type(CFG.Event.Cmds().OwnPlotPart2) == "function" and CFG.Event.Cmds().OwnPlotPart2()
    local coins = CFG.Event.Currency(save, "PumpkinTycoonCoins")

    if ptButtonsUtil then
        local c1 = type(ptButtonsUtil.Complete) == "function" and ptButtonsUtil.Complete(btnsSave, false)
        if c1 and not ptButtonsUtil.Completed(btnsSave) then
            CFG.Event.PlotInvoke(plot, CFG.Event.NET.Complete)
        end
        if p2Built then
            local c2 = type(ptButtonsUtil.Complete) == "function" and ptButtonsUtil.Complete(btnsSave, true)
            if c2 and not ptButtonsUtil.Completed2(btnsSave) then
                CFG.Event.PlotInvoke(plot, CFG.Event.NET.Complete2)
            end
        end
        local maxZones = p2Built and #CFG.Event.ZONES or 5
        local btnCmds = CFG.Event.Feature("Buttons")
        local pMult = btnCmds and type(btnCmds.PriceMult) == "function" and btnCmds.PriceMult() or nil
        local avail = ptButtonsUtil.Available(btnsSave, maxZones, p2Built == true, pMult)
        for _, b in ipairs(avail or {}) do
            local cost = ptButtonsUtil.Price(b, pMult)
            if coins >= cost then
                local spot = nil
                local model = type(plot.GetModel) == "function" and plot:GetModel() or nil
                if model and type(ptButtonsUtil.ResolvedSpot) == "function" then
                    local okS, cf = pcall(ptButtonsUtil.ResolvedSpot, model, b)
                    if okS and typeof(cf) == "CFrame" then spot = cf.Position end
                end
                if spot and CFG.EventOpts.moveMode == "Legit Walk" then
                    CFG.Event.MoveTo(spot)
                end
                local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.Buy, b.Id)
                if ok == true then
                    nextAt.save = 0
                    CFG.Event.next.btn = now + 0.35
                end
                return
            end
        end
    end
end

function CFG.Event.Rebirth(now, plot)
    if now < CFG.Event.next.rebirth then return end
    CFG.Event.next.rebirth = now + 3.0
    local _, btnsSave = CFG.Event.OwnedZones(plot)
    local ptButtonsUtil = nil
    pcall(function() ptButtonsUtil = require(RS.Library.Util.PumpkinTycoonButtons) end)
    if ptButtonsUtil then
        local ready = (type(ptButtonsUtil.RebirthReady) == "function" and ptButtonsUtil.RebirthReady(btnsSave))
            or (type(ptButtonsUtil.Complete) == "function" and ptButtonsUtil.Complete(btnsSave, true))
        if ready then
            local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.Rebirth)
            if ok == true then
                nextAt.save = 0
                CFG.Event.next.rebirth = now + 5.0
            end
        end
    end
end

function CFG.Event.BuyNearestEgg(now, plot, save)
    if now < CFG.Event.next.egg then return end
    -- Intelligent coin saving: if Auto Buy Buttons is active and we have an affordable
    -- (or cheaper than 3 hatches) unbought zone/progression button, let buttons buy first!
    if enabled.ptAutoBuyButtons then
        local okU, ptBtns = pcall(require, RS.Library.Util.PumpkinTycoonButtons)
        if okU and ptBtns then
            local _, btnsSave = CFG.Event.OwnedZones(plot)
            local p2Built = CFG.Event.Cmds() and CFG.Event.Cmds().OwnPlotPart2 and CFG.Event.Cmds().OwnPlotPart2()
            local btnCmds = CFG.Event.Feature("Buttons")
            local pMult = btnCmds and type(btnCmds.PriceMult) == "function" and btnCmds.PriceMult() or nil
            local avail = ptBtns.Available(btnsSave, p2Built and #CFG.Event.ZONES or 5, p2Built == true, pMult)
            if type(avail) == "table" and avail[1] and avail[1].Subclass == nil then
                local nextCost = ptBtns.Price(avail[1], pMult)
                local coins = CFG.Event.Currency(save, "PumpkinTycoonCoins")
                if coins < nextCost * 1.15 then
                    CFG.Event.next.egg = now + 1.5
                    return
                end
            end
        end
    end
    local bestZ = CFG.Event.OwnedZones(plot)
    local ptPos, eggPos = CFG.Event.ZonePos(plot, bestZ)
    local zInfo = CFG.Event.ZONES[bestZ]
    if zInfo and ptPos then
        local myPos = position()
        if myPos and (myPos - (eggPos or ptPos)).Magnitude > 14 then
            CFG.Event.MoveTo(ptPos)
            CFG.Event.next.egg = now + 0.5
            return
        end
        CFG.Event.next.egg = now + CFG.EggInterval
        local count = math.clamp(tonumber(save and save.EggHatchCount) or 1, 1, CFG.EggMaxHatch)
        local eggUid = CFG.Event.FindCustomEgg(zInfo.Egg)
        if eggUid then
            invoke("CustomEggs_Hatch", eggUid, count)
        else
            invoke("Eggs_RequestPurchase", zInfo.Egg, count)
        end
    end
end

function CFG.Event.KeepPumpkins(now, plot)
    if now < CFG.Event.next.keep then return end
    CFG.Event.next.keep = now + 2.5
    local maxKeep = #CFG.Event.LADDER
    local abMod = CFG.Event.Feature("AutoBreak")
    if abMod and type(abMod.MaxBelow) == "function" then
        local okM, m = pcall(abMod.MaxBelow)
        if okM and type(m) == "number" and m >= 0 then maxKeep = m end
    end
    local wantRung = math.clamp(math.floor(tonumber(CFG.EventOpts.keepRung) or 4), 0, maxKeep)
    local abSave = plot:Save("AutoBreak")
    local curBelow = type(abSave) == "table" and tonumber(abSave.Below) or 0
    if curBelow ~= wantRung then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetAutoBreak, wantRung)
    end
    local pedSave = plot:Save("Pedestals")
    if wantRung > 0 and type(pedSave) == "table" then
        for idx = 1, 8 do
            local ped = pedSave[idx]
            if type(ped) == "table" and ped.Unlocked and type(ped.Standing) == "table" then
                local rung = tonumber(ped.Standing.R or ped.Standing.Rung or 0) or 0
                if rung >= wantRung and not ped.Locked then
                    CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetLock, idx, true)
                end
            end
        end
    end
end

function CFG.Event.BreakPumpkins(now, plot)
    if now < CFG.Event.next.breakP then return end
    CFG.Event.next.breakP = now + 0.12
    local list = CFG.Event.CollectBreakables()
    if next(list) == nil then return end

    local pedSave = plot:Save("Pedestals") or {}
    local wantRung = enabled.ptAutoKeepPumpkins and (tonumber(CFG.EventOpts.keepRung) or 0) or 0
    local targets = {}
    for uid, rec in pairs(list) do
        local attrs = type(rec) == "table" and rec.clientAttributes
        local model = type(rec) == "table" and rec.model
        if type(attrs) == "table" and type(attrs.PumpkinPedestal) == "number" and model and model.Parent then
            local owner = model:GetAttribute("OwnerUsername")
            if owner == nil or owner == LocalPlayer.Name then
                local pedIdx = attrs.PumpkinPedestal
                local rung = tonumber(attrs.PumpkinRung or 0) or 0
                local isLocked = type(pedSave[pedIdx]) == "table" and pedSave[pedIdx].Locked == true
                local isKept = wantRung > 0 and rung >= wantRung
                if not isLocked and not isKept then
                    targets[#targets + 1] = { uid = rec.uid or uid, model = model, rung = rung }
                end
            end
        end
    end
    if #targets == 0 then return end
    table.sort(targets, function(a, b) return a.rung > b.rung end)

    for _, t in ipairs(targets) do
        fire("Breakables_PlayerDealDamage", t.uid)
    end
    local mod = modules.pet
    local pets = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
    if type(pets) == "table" then
        local cqRoute, joinBulk, idx = {}, {}, 1
        for _, p in pairs(pets) do
            local t = targets[((idx - 1) % #targets) + 1]
            idx += 1
            if t and not p.destroyed then
                pcall(function() p:SetAnchored(false); p:SetTarget(t.model) end)
                local euid = rawget(p, "euid")
                if euid ~= nil then
                    cqRoute[euid] = { t = 2, v = t.uid }
                    joinBulk[euid] = t.uid
                end
            end
        end
        if next(cqRoute) ~= nil then pcall(fire, "CQ_Route", cqRoute) end
        if next(joinBulk) ~= nil then pcall(fire, "Breakables_JoinPetBulk", joinBulk) end
    end
end

function CFG.Event.Merchant(now, plot, save)
    if now < CFG.Event.next.merch then return end
    CFG.Event.next.merch = now + 2.0
    if plot:Save("MerchantAuto") ~= true then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetAutoMerchant, true)
    end
    local mSave = plot:Save("Merchant")
    if type(mSave) == "table" then
        local items = type(mSave.Items) == "table" and mSave.Items or mSave
        local bands = CFG.EventOpts.merchantBands or {}
        for _, bandId in ipairs({ "ExoticPlus", "MythicalPlus", "LegendaryPlus", "EpicPlus", "RarePlus" }) do
            if bands[bandId] and tonumber(items[bandId]) and tonumber(items[bandId]) > 0 then
                local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.BuyBand, bandId)
                if ok == true then nextAt.save = 0 end
                break
            end
        end
    end
end

function CFG.Event.PlantPumpkins(now, plot)
    if now < CFG.Event.next.plant then return end
    CFG.Event.next.plant = now + 1.5
    if plot:Save("StockAutoPlace") ~= true then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetAutoPlace, true)
    end
    local stock = plot:Save("Stock")
    local peds = plot:Save("Pedestals")
    if type(stock) ~= "table" or type(peds) ~= "table" then return end
    local emptyIdx = nil
    for i = 1, 8 do
        if type(peds[i]) == "table" and peds[i].Unlocked == true and type(peds[i].Standing) ~= "table" then
            emptyIdx = i
            break
        end
    end
    if not emptyIdx then return end
    local band = nil
    if type(stock[1]) == "string" then band = stock[1]
    else
        for k, v in pairs(stock) do
            if type(v) == "number" and v > 0 then band = k; break end
            if type(v) == "string" then band = v; break end
        end
    end
    if band then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.PlaceStock, emptyIdx, band)
    end
end

function CFG.Event.Upgrades(now, plot, save)
    if now < CFG.Event.next.upg then return end
    CFG.Event.next.upg = now + 1.5
    local tokens = CFG.Event.Currency(save, "PumpkinTokens")
    if tokens <= 0 then return end
    local tracks = CFG.EventOpts.upgradeTracks or {}
    local upgCmds = CFG.Event.Feature("Upgrades")
    for _, trackId in ipairs({ "SpawnLuck", "PumpkinCoins", "PumpkinDamage", "RespawnSpeed", "StockSlots", "ChaseOdds", "EggLuck", "MerchantLuck" }) do
        if tracks[trackId] then
            if upgCmds then
                local tier = type(upgCmds.Tier) == "function" and select(2, pcall(upgCmds.Tier, trackId)) or nil
                if type(upgCmds.Capped) == "function" and type(tier) == "number" then
                    local okCap, capped = pcall(upgCmds.Capped, trackId, tier)
                    if okCap and capped == true then continue end
                end
                if type(upgCmds.Cost) == "function" then
                    local okCost, cost = pcall(upgCmds.Cost, trackId)
                    if okCost and type(cost) == "number" and tokens < cost then continue end
                end
            end
            local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.UpgradeBuy, trackId)
            if ok == true then
                nextAt.save = 0
                return
            end
        end
    end
end

function CFG.Event.Cocoa(now, plot, save)
    if now < CFG.Event.next.cocoa then return end
    CFG.Event.next.cocoa = now + 5.0
    local coins = CFG.Event.Currency(save, "PumpkinTycoonCoins")
    if coins <= 0 then return end
    local boostCmds = nil
    pcall(function() boostCmds = require(RS.Library.Client.BoostCmds) end)
    local cocoaOpts = CFG.EventOpts.cocoaBoosts or {}
    for offerKey, want in pairs(cocoaOpts) do
        if want then
            local rem = boostCmds and type(boostCmds.GetTimer) == "function" and (boostCmds.GetTimer(offerKey) or 0) or 0
            if rem < 3600 then
                local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.CocoaBuyTime, offerKey, 10)
                if ok == true then
                    nextAt.save = 0
                    return
                end
            end
        end
    end
end

function CFG.Event.UseBoosts(now, save)
    if now < CFG.Event.next.boost then return end
    CFG.Event.next.boost = now + 4.0
    local ptBoostUtil = nil
    pcall(function() ptBoostUtil = require(RS.Library.Util.PumpkinTycoonBoosts) end)
    local boostsWanted = CFG.EventOpts.pumpkinBoosts or {}
    local list = {}
    for _, item in ipairs(stackList(inventory(save, "Consumable"))) do
        if boostsWanted[item.id] then
            local okAllow = true
            if ptBoostUtil and type(ptBoostUtil.Allowed) == "function" then
                local okA, res = pcall(ptBoostUtil.Allowed, LocalPlayer, item.tier)
                if okA then okAllow = res == true end
            end
            if okAllow then list[#list + 1] = item end
        end
    end
    if #list == 0 then return end
    -- Tier III boosts first (Tier 3 -> Tier 2 -> Tier 1)
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return a.id < b.id
    end)
    local chosen = list[1]
    local ok = invoke("Consumables_Consume", chosen.uid, 1)
    if ok == true then nextAt.save = 0 end
end

function CFG.Event.OpenFlannelGifts(now, save)
    if now < CFG.Event.next.gift then return end
    CFG.Event.next.gift = now + 2.5
    local loot = stackList(inventory(save, "Lootbox"))
    for _, item in ipairs(loot) do
        if item.id == "Flannel Gift" and item.amount > 0 then
            local amt = math.min(item.amount, 8)
            local ch = LocalPlayer.Character
            local ring = {}
            local pos = ch and ch:GetPivot().Position or Vector3.zero
            for i = 1, amt do
                local ang = (i / amt) * math.pi * 2
                ring[i] = pos + Vector3.new(10 * math.cos(ang), -3, 10 * math.sin(ang))
            end
            local ok = invoke(CFG.Event.NET.GiftOpen, item.uid, amt, ring, true)
            if ok ~= true then
                ok = invoke("KX_Release", item.uid, amt, nil)
            end
            if ok == true then nextAt.save = 0 end
            return
        end
    end
end

function CFG.Event.HuntWild(now, plot)
    if now < CFG.Event.next.hunt then return end
    CFG.Event.next.hunt = now + 4.0
    local huntSave = plot:Save("Hunt")
    local wantMin = tonumber(CFG.EventOpts.huntMinTier) or 0
    local wantVar = CFG.EventOpts.huntVariant == true
    local wantUltra = CFG.EventOpts.huntUltraHuge ~= false
    if type(huntSave) ~= "table" or huntSave.On ~= true or huntSave.Min ~= wantMin
        or (huntSave.Variant == true) ~= wantVar or (huntSave.UltraOnHuge == true) ~= wantUltra then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetHunt, {
            On = true, Min = wantMin, Variant = wantVar, UltraOnHuge = wantUltra,
        })
    end
end

function CFG.Event.BestNet(save, isHuge)
    local hasNet, hasUltra = 0, 0
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if item.id == "Pet Net" then hasNet += item.amount
        elseif item.id == "Ultra Pet Net" then hasUltra += item.amount end
    end
    if isHuge and hasUltra > 0 then return "Ultra Pet Net" end
    if CFG.EventOpts.catchMinNet == "Ultra Pet Net" and hasUltra > 0 then return "Ultra Pet Net" end
    if hasUltra > 0 and CFG.EventOpts.catchMinNet == "Auto" and isHuge then return "Ultra Pet Net" end
    if hasNet > 0 then return "Pet Net" end
    if hasUltra > 0 then return "Ultra Pet Net" end
    return nil
end

function CFG.Event.CatchWild(now, plot, save)
    if now < CFG.Event.next.wild then return end
    CFG.Event.next.wild = now + 3.2
    local wildSave = plot:Save("Wild")
    if type(wildSave) ~= "table" then return end
    local wildMod = CFG.Event.Feature("Wild")
    local spawned = wildMod and type(wildMod.All) == "function" and wildMod.All() or nil
    for slotKey, entry in pairs(wildSave) do
        local slot = tonumber(slotKey)
        if slot and type(entry) == "table" and type(entry.P) == "string" then
            local isHuge = entry.P:find("Huge", 1, true) ~= nil or entry.P:find("Titanic", 1, true) ~= nil
            local net = CFG.Event.BestNet(save, isHuge)
            if not net then return end
            if type(spawned) == "table" and spawned[slot] and spawned[slot].CustomPet and spawned[slot].CustomPet.primaryPart then
                local pPos = spawned[slot].CustomPet.primaryPart.Position
                if CFG.EventOpts.moveMode == "Legit Walk" then CFG.Event.MoveTo(pPos) end
            end
            local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.CatchWild, slot, net)
            if ok == true then
                nextAt.save = 0
                return
            end
        end
    end
end

function CFG.Event.BuyNets(now, plot)
    if now < CFG.Event.next.net then return end
    CFG.Event.next.net = now + 4.0
    if plot:Save("NetStoreAuto") ~= true then
        CFG.Event.PlotInvoke(plot, CFG.Event.NET.SetAutoNets, true)
    end
    local store = CFG.Event.Feature("Store")
    if store and type(store.Shelf) == "function" then
        local okS, shelf = pcall(store.Shelf)
        if okS and type(shelf) == "table" and type(shelf.offers) == "table" then
            for _, offer in ipairs(shelf.offers) do
                if (offer.item == "Ultra Pet Net" or offer.item == "Pet Net") and (offer.left or 0) > 0 then
                    local ok = invoke("Merchant_RequestPurchase", "PetNetStore", offer.slot, false, shelf.seed)
                    if ok ~= true then
                        CFG.Event.PlotInvoke(plot, CFG.Event.NET.BuyNet, offer.slot)
                    end
                    return
                end
            end
        end
    end
end

function CFG.Event.FightTurkey(now, plot)
    if now < CFG.Event.next.turkey then return end
    CFG.Event.next.turkey = now + 0.15
    local list = CFG.Event.CollectBreakables()
    local turkeyUid, turkeyModel = nil, nil
    for uid, rec in pairs(list) do
        local attrs = type(rec) == "table" and rec.clientAttributes
        if type(attrs) == "table" and attrs.PumpkinTurkey == true and rec.model and rec.model.Parent then
            turkeyUid, turkeyModel = rec.uid or uid, rec.model
            break
        end
    end
    if not turkeyModel then
        local instFolder = thingsFolder("Instances")
        local icFolder = thingsFolder("__INSTANCE_CONTAINER")
        local ptShared = (icFolder and icFolder:FindFirstChild("PumpkinTycoonShared", true))
            or (instFolder and instFolder:FindFirstChild("PumpkinTycoon") and instFolder.PumpkinTycoon:FindFirstChild("PumpkinTycoonShared"))
        local arena = ptShared and ptShared:FindFirstChild("TurkeyArena", true)
        if arena and arena:GetAttribute("TurkeyAlive") == true then
            local spawnPart = arena:FindFirstChild("TurkeySpawn", true)
            if spawnPart and spawnPart:IsA("BasePart") then
                local pt = position()
                if pt and (pt - spawnPart.Position).Magnitude > 90 then
                    if CFG.EventOpts.moveMode == "Teleport" then
                        CFG.Event.PlotInvoke(plot, CFG.Event.NET.Cannon, "centre")
                        task.wait(0.2)
                    end
                    CFG.Event.MoveTo(spawnPart.Position + Vector3.new(0, 4, 8))
                end
            end
        end
        return
    end
    local tPos = modelPosition(turkeyModel)
    local pt = position()
    if tPos and pt and (pt - tPos).Magnitude > 110 then
        CFG.Event.MoveTo(tPos + Vector3.new(0, 4, 10))
    end
    fire("Breakables_PlayerDealDamage", turkeyUid)
    local mod = modules.pet
    local pets = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
    if type(pets) == "table" then
        local cqRoute, joinBulk = {}, {}
        for _, p in pairs(pets) do
            if not p.destroyed then
                pcall(function() p:SetAnchored(false); p:SetTarget(turkeyModel) end)
                local euid = rawget(p, "euid")
                if euid ~= nil then
                    cqRoute[euid] = { t = 2, v = turkeyUid }
                    joinBulk[euid] = turkeyUid
                end
            end
        end
        if next(cqRoute) ~= nil then pcall(fire, "CQ_Route", cqRoute) end
        if next(joinBulk) ~= nil then pcall(fire, "Breakables_JoinPetBulk", joinBulk) end
    end
end

function CFG.Event.CatchRare(now, plot, save)
    if now < CFG.Event.next.rare then return end
    CFG.Event.next.rare = now + 0.5
    local bestNet = CFG.Event.BestNet(save, true)
    if not bestNet then return end
    local turkeyMod = CFG.Event.Feature("Turkey")
    if turkeyMod and type(turkeyMod.Sighting) == "function" and type(turkeyMod.Throw) == "function" then
        local okS, exp = pcall(turkeyMod.Sighting)
        if okS and exp ~= nil then
            local okT = pcall(turkeyMod.Throw, bestNet)
            if okT then CFG.Event.next.rare = now + 3.2; return end
        end
    end
    for _, container in ipairs({ workspace:FindFirstChild("__DEBRIS"), thingsFolder("Pets") }) do
        if container then
            for _, desc in ipairs(container:GetDescendants()) do
                if desc:IsA("BasePart") then
                    local sid = desc:GetAttribute("PumpkinSighting")
                    if type(sid) == "string" and #sid > 0 then
                        CFG.Event.MoveTo(desc.Position + Vector3.new(0, 2, 8))
                        local ok = CFG.Event.PlotInvoke(plot, CFG.Event.NET.CatchSighting, sid, bestNet)
                        if ok == true then
                            CFG.Event.next.rare = now + 3.2
                            nextAt.save = 0
                        end
                        return
                    end
                end
            end
        end
    end
end

function CFG.Event.Tick()
    local now = os.clock()
    if enabled.optPumpkinTycoon then pcall(CFG.Event.Optimize, now) end
    local save = getSave()
    if not save then notes.event = "waiting for profile"; return end
    if enabled.ptAutoUseBoosts then pcall(CFG.Event.UseBoosts, now, save) end
    if enabled.ptAutoFlannelGifts then pcall(CFG.Event.OpenFlannelGifts, now, save) end
    local plot = CFG.Event.Plot()
    if not plot then notes.event = "enter Pumpkin Tycoon to run"; return end
    if enabled.ptAutoFightTurkey then pcall(CFG.Event.FightTurkey, now, plot) end
    if enabled.ptAutoCatchRare then pcall(CFG.Event.CatchRare, now, plot, save) end
    if enabled.ptAutoBreakPumpkins then pcall(CFG.Event.BreakPumpkins, now, plot) end
    if enabled.ptAutoKeepPumpkins then pcall(CFG.Event.KeepPumpkins, now, plot) end
    if enabled.ptAutoBuyButtons then pcall(CFG.Event.BuyButtons, now, plot, save) end
    if enabled.ptAutoRebirth then pcall(CFG.Event.Rebirth, now, plot) end
    if enabled.ptAutoBuyMerchant then pcall(CFG.Event.Merchant, now, plot, save) end
    if enabled.ptAutoPlantPumpkins then pcall(CFG.Event.PlantPumpkins, now, plot) end
    if enabled.ptAutoBuyUpgrades then pcall(CFG.Event.Upgrades, now, plot, save) end
    if enabled.ptAutoBuyCocoa then pcall(CFG.Event.Cocoa, now, plot, save) end
    if enabled.ptAutoHuntWild then pcall(CFG.Event.HuntWild, now, plot) end
    if enabled.ptAutoCatchWild then pcall(CFG.Event.CatchWild, now, plot, save) end
    if enabled.ptAutoBuyNets then pcall(CFG.Event.BuyNets, now, plot) end
    if enabled.ptAutoTeleBestEgg then pcall(CFG.Event.TeleBestEgg, now, plot) end
    if enabled.ptAutoTeleNearestFarm then pcall(CFG.Event.TeleNearestFarm, now, plot) end
    if enabled.ptAutoBuyEgg then pcall(CFG.Event.BuyNearestEgg, now, plot, save) end
    notes.event = ("Pumpkin Tycoon (%s)"):format(CFG.EventOpts.moveMode)
end

local function stopWorker(name)
    local worker = workers[name]
    if not worker then return end
    workers[name] = nil
    worker.running = false
    if name == "profile" and stats.pending then table.clear(stats.pending); stats.pending = nil end
    if worker.thread then workerContext[worker.thread] = nil end
    for remoteName, request in pairs(requests) do
        if request.owner == worker and not request.sent then
            if request.thread then pcall(task.cancel, request.thread) end
            requests[remoteName] = nil
        end
    end
    if worker.thread and worker.thread ~= coroutine.running() then pcall(task.cancel, worker.thread) end
end

local function ensureWorker(name, wanted, interval, tick, onFailure)
    if not wanted then stopWorker(name); return end
    if workers[name] then workers[name].interval = interval; return end
    local worker = {running = true, interval = interval, errors = 0}
    workers[name] = worker
    worker.thread = task.defer(function()
        workerContext[coroutine.running()] = worker
        while alive and worker.running and workers[name] == worker do
            worker.lastBeat = os.clock()
            local ok, err = pcall(tick)
            if not alive or not worker.running or workers[name] ~= worker then return end
            worker.lastBeat = os.clock()
            if ok then worker.errors = 0 else
                worker.errors += 1
                stage(name .. ": " .. tostring(err))
                if worker.errors >= 3 and onFailure then
                    stopWorker(name)
                    onFailure()
                    updateToggles()
                    syncWorkers()
                    return
                end
            end
            task.wait(worker.errors > 0 and math.max(worker.interval, 2) or worker.interval)
        end
    end)
end

CFG.AntiAfk = {
    conn = nil,
    thread = nil,
    disabledConns = {},
    last = -math.huge,
    count = 0,
}

function CFG.AntiAfk.Pulse()
    local camera = workspace.CurrentCamera
    local ok = pcall(function()
        local virtualUser = game:GetService("VirtualUser")
        virtualUser:CaptureController()
        if camera then
            virtualUser:ClickButton2(Vector2.new(0, 0), camera.CFrame)
        else
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end
    end)
    if not ok then
        ok = pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
        end)
    end
    if ok then
        CFG.AntiAfk.count += 1
        CFG.AntiAfk.last = os.clock()
    end
    return ok
end

local function syncAntiAfk()
    local st = CFG.AntiAfk
    if not alive or not enabled.antiAfk then
        if st.conn then st.conn:Disconnect(); st.conn = nil end
        if st.thread then pcall(task.cancel, st.thread); st.thread = nil end
        for _, c in ipairs(st.disabledConns) do
            pcall(function() if type(c.Enable) == "function" then c:Enable() end end)
        end
        table.clear(st.disabledConns)
        notes.antiAfk = "off"
        return
    end
    if st.conn then return end
    local disabledCount = 0
    if type(getconnections) == "function" then
        pcall(function()
            for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
                if type(c.Disable) == "function" then
                    pcall(c.Disable, c)
                    st.disabledConns[#st.disabledConns + 1] = c
                    disabledCount += 1
                end
            end
        end)
    end
    st.conn = LocalPlayer.Idled:Connect(function()
        if not alive or not enabled.antiAfk then return end
        if CFG.AntiAfk.Pulse() then
            notes.antiAfk = ("active (%d idle blocked, %d pulses)"):format(disabledCount, st.count)
        end
    end)
    st.thread = task.spawn(function()
        while alive and enabled.antiAfk do
            CFG.AntiAfk.Pulse()
            notes.antiAfk = ("active (%d idle blocked, %d pulses)"):format(disabledCount, st.count)
            task.wait(math.max(30, CFG.AntiAfkCooldown or 60))
        end
    end)
    notes.antiAfk = ("active (%d idle blocked)"):format(disabledCount)
end

-- Auto Time Trial (World 4 / Zone 279 Hollow Veil Castle minigame, Instance ID "TimeTrial")
CFG.TimeTrial = {
    INSTANCE_ID = "TimeTrial",
    ZONE_NUMBER = 279,
    ZONE_NAME = "Hollow Veil Castle",
    WORLD_NUMBER = 4,
    nextEnterAt = 0,
    nextChestAt = 0,
    nextMoveAt = 0,
    emptySince = nil,
    visitedPads = {},
}

function CFG.TimeTrial.Types()
    local ok, mod = pcall(function()
        return require(RS.Library.Types.TimeTrials)
    end)
    return ok and type(mod) == "table" and mod or nil
end

function CFG.TimeTrial.InInstance()
    local inst = modules.instancing
    if inst then
        if type(inst.GetInstanceID) == "function" then
            local okId, curId = pcall(inst.GetInstanceID)
            if okId and curId == CFG.TimeTrial.INSTANCE_ID then return true end
        end
        if type(inst.IsInInstance) == "function" then
            local okIn, resIn = pcall(inst.IsInInstance, CFG.TimeTrial.INSTANCE_ID)
            if okIn and resIn == true then return true end
        end
        if type(inst.Get) == "function" then
            local okG, cur = pcall(inst.Get)
            if okG and type(cur) == "table" and cur.instanceID == CFG.TimeTrial.INSTANCE_ID then
                return true
            end
        end
    end
    local ic = thingsFolder("__INSTANCE_CONTAINER")
    local active = ic and ic:FindFirstChild("Active")
    if active and active:FindFirstChild(CFG.TimeTrial.INSTANCE_ID) then
        return true
    end
    return false
end

function CFG.TimeTrial.GetModel()
    local inst = modules.instancing
    if inst and type(inst.GetModel) == "function" and CFG.TimeTrial.InInstance() then
        local okM, model = pcall(inst.GetModel)
        if okM and typeof(model) == "Instance" then return model end
    end
    local ic = thingsFolder("__INSTANCE_CONTAINER")
    local active = ic and ic:FindFirstChild("Active")
    return active and active:FindFirstChild(CFG.TimeTrial.INSTANCE_ID) or nil
end

function CFG.TimeTrial.IsSummaryOpen()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local summaryGui = pg and pg:FindFirstChild("TimeTrialSummary")
    if summaryGui and summaryGui:IsA("ScreenGui") and summaryGui.Enabled then
        return true
    end
    local okTab, open = pcall(function()
        local tc = require(RS.Library.Client.TabController)
        if type(tc) == "table" and type(tc.GetCurrentTab) == "function" then
            return tc.GetCurrentTab() == "TimeTrialSummary"
        end
        return false
    end)
    return okTab and open == true
end

function CFG.TimeTrial.GetStatus()
    local save = getSave()
    local ttTypes = CFG.TimeTrial.Types()
    local totalGoals = (ttTypes and tonumber(ttTypes.TotalGoals)) or 5
    local dailyLimit = (ttTypes and tonumber(ttTypes.DailyRuns)) or 10
    local st = save and type(save.TimeTrialStats) == "table" and save.TimeTrialStats or nil
    local goalIndex = (st and tonumber(st.GoalIndex)) or 1
    local dailyRuns = (st and tonumber(st.DailyRuns)) or 0
    local points = (st and tonumber(st.Points)) or 0
    local totalRuns = (st and tonumber(st.TotalRuns)) or 0
    local streak = (st and tonumber(st.Streak)) or 0
    local pvpUnlocked = goalIndex > totalGoals
    return {
        inInstance = CFG.TimeTrial.InInstance(),
        world = detectActiveWorld(),
        goalIndex = goalIndex,
        totalGoals = totalGoals,
        pvpUnlocked = pvpUnlocked,
        dailyRuns = dailyRuns,
        dailyLimit = dailyLimit,
        runsLeft = math.max(0, dailyLimit - dailyRuns),
        points = points,
        totalRuns = totalRuns,
        streak = streak,
        note = notes.timeTrial or "off",
    }
end

function CFG.TimeTrial.TeleportToZone()
    if CFG.TimeTrial.InInstance() then
        return true, "already inside Time Trial"
    end
    if detectActiveWorld() ~= CFG.TimeTrial.WORLD_NUMBER then
        local okW, msgW = teleportToWorldOrBestIsland(CFG.TimeTrial.WORLD_NUMBER)
        return okW, okW and "teleporting to World 4" or tostring(msgW or "failed World 4 teleport")
    end
    local inst = modules.instancing
    if inst and type(inst.GetEnterPart) == "function" then
        local okP, part = pcall(inst.GetEnterPart, CFG.TimeTrial.INSTANCE_ID)
        if okP and typeof(part) == "Instance" and part:IsA("BasePart") then
            snapTo(part.Position + Vector3.new(0, 4, 0))
            return true, "teleported to Time Trial portal"
        end
    end
    local okZ, msgZ = teleportToIslandMiddle(CFG.TimeTrial.ZONE_NAME)
    return okZ, msgZ or ("teleported to " .. CFG.TimeTrial.ZONE_NAME)
end

function CFG.TimeTrial.Enter()
    if CFG.TimeTrial.InInstance() then
        return true, "already inside Time Trial"
    end
    local inst = modules.instancing
    if inst and type(inst.IsInInstance) == "function" then
        local okOther, inAny = pcall(inst.IsInInstance)
        if okOther and inAny == true then
            leaveActiveInstance()
            task.wait(0.6)
        end
    end
    if detectActiveWorld() ~= CFG.TimeTrial.WORLD_NUMBER then
        notes.timeTrial = "switching to World 4..."
        teleportToWorldOrBestIsland(CFG.TimeTrial.WORLD_NUMBER)
        return false, "switching to World 4 (re-run after load)"
    end
    local portalPart = nil
    if inst and type(inst.GetEnterPart) == "function" then
        local okP, part = pcall(inst.GetEnterPart, CFG.TimeTrial.INSTANCE_ID)
        if okP and typeof(part) == "Instance" and part:IsA("BasePart") then
            portalPart = part
        end
    end
    if portalPart then
        local myPos = position()
        if not myPos or (myPos - portalPart.Position).Magnitude > 45 then
            snapTo(portalPart.Position + Vector3.new(0, 4, 0))
            task.wait(0.25)
        end
    else
        pcall(teleportToIslandMiddle, CFG.TimeTrial.ZONE_NAME)
        task.wait(0.35)
    end
    table.clear(CFG.TimeTrial.visitedPads)
    CFG.TimeTrial.emptySince = nil
    if inst and type(inst.Enter) == "function" then
        local okE, resE = pcall(inst.Enter, CFG.TimeTrial.INSTANCE_ID)
        if okE and resE ~= false then
            for _ = 1, 20 do
                if CFG.TimeTrial.InInstance() then
                    notes.timeTrial = "entered Time Trial"
                    return true, "entered Time Trial"
                end
                task.wait(0.2)
            end
        end
    end
    local okInv, msgInv = invoke("Instancing_PlayerEnterInstance", CFG.TimeTrial.INSTANCE_ID)
    if okInv == true then
        for _ = 1, 15 do
            if CFG.TimeTrial.InInstance() then break end
            task.wait(0.2)
        end
        notes.timeTrial = "entered Time Trial"
        return true, "entered Time Trial"
    end
    notes.timeTrial = "enter failed: " .. tostring(msgInv or "unavailable")
    return false, tostring(msgInv or "failed to enter Time Trial")
end

function CFG.TimeTrial.Leave()
    pcall(function()
        local tc = require(RS.Library.Client.TabController)
        if type(tc) == "table" and type(tc.CloseTab) == "function" then
            tc.CloseTab()
        end
    end)
    local inst = modules.instancing
    if inst and type(inst.Leave) == "function" and CFG.TimeTrial.InInstance() then
        pcall(inst.Leave)
        task.wait(0.6)
    end
    if CFG.TimeTrial.InInstance() then
        pcall(fire, "Instancing_PlayerLeaveInstance")
        task.wait(0.8)
    end
    table.clear(CFG.TimeTrial.visitedPads)
    CFG.TimeTrial.emptySince = nil
    nextAt.save = 0
    return true, "left Time Trial"
end

function CFG.TimeTrial.OpenChest(tierOverride)
    local st = CFG.TimeTrial.GetStatus()
    if not st.pvpUnlocked then
        return false, ("complete all %d goals first (%d/%d)"):format(st.totalGoals, st.goalIndex, st.totalGoals)
    end
    local ttTypes = CFG.TimeTrial.Types()
    local chestDir = ttTypes and type(ttTypes.ChestDirectory) == "table" and ttTypes.ChestDirectory or nil
    local function chestCost(id)
        local entry = chestDir and chestDir[id]
        if type(entry) == "table" and type(entry.PointsRequired) == "function" then
            local okC, cost = pcall(entry.PointsRequired)
            if okC and type(cost) == "number" and cost > 0 then return cost end
        end
        return nil
    end
    local mode = tostring(tierOverride or CFG.TimeTrialChestTier or "Best Affordable")
    local order = { 3, 2, 1 }
    if mode:find("3", 1, true) then
        order = { 3 }
    elseif mode:find("2", 1, true) then
        order = { 2 }
    elseif mode:find("1", 1, true) then
        order = { 1 }
    end
    for _, id in ipairs(order) do
        local cost = chestCost(id)
        if cost == nil or st.points >= cost then
            local okOpen, errOpen = invoke("TimeTrials_OpenChest", id)
            if okOpen == true then
                nextAt.save = 0
                notes.timeTrial = ("opened Time Trial Chest #%d"):format(id)
                return true, ("opened Time Trial Chest #%d"):format(id)
            elseif #order == 1 then
                return false, tostring(errOpen or ("need more points for Chest #" .. id))
            end
        end
    end
    return false, ("not enough points (%d)"):format(st.points)
end

function CFG.TimeTrial.FindBreakables(point)
    local folder = thingsFolder("Breakables")
    if not folder then return {} end
    local list = {}
    for _, m in ipairs(folder:GetChildren()) do
        if m and m.Parent then
            local uid = m:GetAttribute("BreakableUID")
            if uid ~= nil then
                local pos = modelPosition(m)
                if pos then
                    local dist = point and (pos - point).Magnitude or 0
                    if dist <= 1500 then
                        local bid = tostring(m:GetAttribute("BreakableID") or m.Name):lower()
                        local isChest = bid:find("chest", 1, true) ~= nil
                        list[#list + 1] = { model = m, uid = uid, pos = pos, dist = dist, isChest = isChest }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if enabled.chestFirst and a.isChest ~= b.isChest then
            return a.isChest
        end
        return a.dist < b.dist
    end)
    return list
end

function CFG.TimeTrial.AttackBreakables(list)
    local maxTap = math.min(#list, 25)
    for i = 1, maxTap do
        fire("Breakables_PlayerDealDamage", list[i].uid)
    end
    local mod = modules.pet
    local pets, seenP = {}, {}
    local group = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
    if type(group) == "table" then
        for _, rec in pairs(group) do if not seenP[rec] then seenP[rec] = true; pets[#pets + 1] = rec end end
    end
    for rec in pairs(petState.records) do
        if not seenP[rec] then seenP[rec] = true; pets[#pets + 1] = rec end
    end
    local cqRoute, joinBulk = {}, {}
    local assigned = 0
    for pIdx, rec in ipairs(pets) do
        if not rec.destroyed and (rawget(rec, "owner") == nil or rawget(rec, "owner") == LocalPlayer) then
            local entry = list[((pIdx - 1) % #list) + 1]
            if entry and entry.model and entry.model.Parent then
                assigned += 1
                local euid = rawget(rec, "euid")
                if petState.joinedTarget[rec] ~= entry.model then
                    petState.joinedTarget[rec] = entry.model
                    pcall(function() rec:SetTarget(entry.model) end)
                    if euid ~= nil then
                        cqRoute[euid] = { t = 2, v = entry.uid }
                        joinBulk[euid] = entry.uid
                    end
                    local angle = (pIdx / math.max(#pets, 1)) * math.pi * 2
                    local ringPos = entry.pos + Vector3.new(math.cos(angle) * 3.0, 0, math.sin(angle) * 3.0)
                    local ringCF = CFrame.lookAt(ringPos, Vector3.new(entry.pos.X, ringPos.Y, entry.pos.Z))
                    pcall(function()
                        rec.speedMult = 1e6
                        local cpet = rawget(rec, "cpet")
                        if type(cpet) == "table" then
                            if cpet.parallelIn then
                                cpet.parallelIn.petSpeedMult = 1e6
                                cpet.parallelIn.petSpeed = 100
                            end
                            cpet:Broadcast("petSpeedMult", 1e6)
                            cpet:Broadcast("petSpeed", 100)
                            if cpet.physical and cpet.physical.Parent then cpet.physical:PivotTo(ringCF) end
                            if type(cpet.parallelOut) == "table" then
                                cpet.parallelOut.cf = ringCF
                                cpet.parallelOut.arrived = true
                                cpet.parallelOut.farming = true
                            end
                            if type(cpet.Arrived) == "table" and type(cpet.Arrived.Fire) == "function" then
                                cpet.Arrived:Fire()
                            end
                        end
                    end)
                end
            end
        end
    end
    if next(cqRoute) ~= nil then pcall(fire, "CQ_Route", cqRoute) end
    if next(joinBulk) ~= nil then pcall(fire, "Breakables_JoinPetBulk", joinBulk) end
    return assigned
end

function CFG.TimeTrial.FindNextPad(ttModel, myPos)
    if not ttModel then return nil end
    local bestPart, bestDist = nil, math.huge
    for _, desc in ipairs(ttModel:GetDescendants()) do
        if desc:IsA("BasePart") and not CFG.TimeTrial.visitedPads[desc] then
            local lname = desc.Name:lower()
            if lname ~= "safety_net" and lname ~= "enterteleport" and lname ~= "leave" and lname ~= "leaveteleport" then
                if lname:find("finish", 1, true) or lname:find("goal", 1, true)
                    or lname:find("checkpoint", 1, true) or lname:find("pad", 1, true)
                    or lname:find("portal", 1, true) or lname:find("end", 1, true) then
                    local d = myPos and (desc.Position - myPos).Magnitude or 0
                    if d < bestDist then
                        bestPart, bestDist = desc, d
                    end
                end
            end
        end
    end
    return bestPart
end

function CFG.TimeTrial.Tick()
    if not alive then return end
    local now = os.clock()
    local inTT = CFG.TimeTrial.InInstance()
    if enabled.autoTimeTrialChests and not inTT and now >= (CFG.TimeTrial.nextChestAt or 0) then
        CFG.TimeTrial.nextChestAt = now + 2.0
        pcall(CFG.TimeTrial.OpenChest)
    end
    if not enabled.autoTimeTrial then
        if not enabled.autoTimeTrialChests then notes.timeTrial = "off" end
        return
    end
    if inTT then
        if CFG.TimeTrial.IsSummaryOpen() then
            notes.timeTrial = "run complete, restarting..."
            CFG.TimeTrial.Leave()
            CFG.TimeTrial.nextEnterAt = os.clock() + 1.5
            return
        end
        local myPos = position()
        local list = CFG.TimeTrial.FindBreakables(myPos)
        if #list > 0 then
            CFG.TimeTrial.emptySince = nil
            local nearest = list[1]
            if myPos and nearest.dist > 28 and now >= (CFG.TimeTrial.nextMoveAt or 0) then
                CFG.TimeTrial.nextMoveAt = now + 0.35
                snapTo(nearest.pos + Vector3.new(0, 4, 0))
            end
            local assigned = CFG.TimeTrial.AttackBreakables(list)
            notes.timeTrial = ("running | %d targets | %d pets"):format(#list, assigned)
        else
            if not CFG.TimeTrial.emptySince then
                CFG.TimeTrial.emptySince = now
            elseif now - CFG.TimeTrial.emptySince >= 1.5 then
                local pad = CFG.TimeTrial.FindNextPad(CFG.TimeTrial.GetModel(), myPos)
                if pad and now >= (CFG.TimeTrial.nextMoveAt or 0) then
                    CFG.TimeTrial.visitedPads[pad] = true
                    CFG.TimeTrial.nextMoveAt = now + 0.8
                    snapTo(pad.Position + Vector3.new(0, 4, 0))
                    notes.timeTrial = "moving to " .. pad.Name
                    return
                end
            end
            notes.timeTrial = "waiting for breakables..."
        end
        return
    end
    -- Outside Time Trial instance
    local st = CFG.TimeTrial.GetStatus()
    if enabled.ttStopAtDailyLimit and st.pvpUnlocked and st.runsLeft <= 0 then
        notes.timeTrial = ("daily limit reached (%d/%d)"):format(st.dailyRuns, st.dailyLimit)
        return
    end
    if now < (CFG.TimeTrial.nextEnterAt or 0) then return end
    CFG.TimeTrial.nextEnterAt = now + 3.5
    CFG.TimeTrial.Enter()
end

syncWorkers = function()
    if not alive then return end
    syncAntiAfk()
    syncEggFx()
    syncNoclip()
    syncFly()
    syncGamepasses()
    syncGates()
    CFG.SyncFastFarmBeta()
    CFG.SyncWhiteScreen()
    CFG.SyncReduceCpuRam()
    local eventWanted = enabled.optPumpkinTycoon or enabled.ptAutoTeleBestEgg or enabled.ptAutoTeleNearestFarm or enabled.ptAutoBuyEgg
        or enabled.ptAutoBuyButtons or enabled.ptAutoRebirth or enabled.ptAutoKeepPumpkins
        or enabled.ptAutoBreakPumpkins or enabled.ptAutoBuyMerchant or enabled.ptAutoPlantPumpkins
        or enabled.ptAutoBuyUpgrades or enabled.ptAutoBuyCocoa or enabled.ptAutoUseBoosts
        or enabled.ptAutoFlannelGifts or enabled.ptAutoHuntWild or enabled.ptAutoCatchWild
        or enabled.ptAutoBuyNets or enabled.ptAutoFightTurkey or enabled.ptAutoCatchRare
    local ttWanted = enabled.autoTimeTrial or enabled.autoTimeTrialChests
    local profileWanted = enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoDoQuest
        or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele
        or enabled.autoBuyPetSlots or enabled.autoBuyEggSlots or enabled.autoForeverPack
        or enabled.autoBuyUpgrades or enabled.autoEquipEnchant or enabled.worldAdvance or enabled.unlockGamepasses
        or enabled.autoKeys or enabled.autoGiftBags or enabled.autoFruits or enabled.autoPotions
        or enabled.autoFreeGifts or enabled.autoUltimate or enabled.autoSprinkler or enabled.autoDaycare or enabled.autoFlags
        or enabled.autoSecretRooms or enabled.autoTreehouse or enabled.autoFuse or enabled.autoCards
        or enabled.autoRelics or enabled.autoMailClaim or enabled.autoDice or enabled.autoTNT or enabled.autoTNTCrate
        or enabled.autoSpinTickets or enabled.autoOpenChests
        or eventWanted or ttWanted
    local discoveryWanted = profileWanted or enabled.petSpeed or enabled.farm or enabled.fastFarmBeta or enabled.vacuum or enabled.tap or enabled.clickAura
    ensureWorker("profile", profileWanted, CFG.ProfileInterval, profileTick)
    ensureWorker("discovery", discoveryWanted, CFG.DiscoveryInterval, discoveryTick)
    if not discoveryWanted then heapObjects, heapCursor, treeScan = nil, nil, nil end
    local petWanted = enabled.petSpeed or enabled.farm or enabled.fastFarmBeta or enabled.ptAutoBreakPumpkins or enabled.ptAutoFightTurkey or enabled.autoTimeTrial
    if not petWanted and petState.hook then restorePetSpeed() end
    ensureWorker("pet", petWanted, CFG.PetInterval, petTick)
    local tapRate = enabled.clickAura and CFG.AuraRate or (enabled.farm and CFG.FarmTapRate or CFG.TapRate)
    if enabled.legitTap and not enabled.farm and not enabled.clickAura then tapRate = 8 end
    ensureWorker("tap", enabled.tap or enabled.farm or enabled.clickAura, 1 / math.clamp(math.min(tapRate, CFG.MaxTapRate), 1, 120), tapTick)
    if (enabled.vacuum or enabled.farm or enabled.fastFarmBeta or enabled.ptAutoBreakPumpkins or enabled.autoTimeTrial) and not orbState.hook then
        if not orbBackfillNeeded then nextAt.heap = math.min(nextAt.heap, os.clock() + CFG.HeapRetryInterval) end
        orbBackfillNeeded = true
    end
    ensureWorker("vacuum", enabled.vacuum or enabled.farm or enabled.fastFarmBeta or enabled.ptAutoBreakPumpkins or enabled.autoTimeTrial, CFG.VacuumRate, vacuumTick)
    ensureWorker("tele", enabled.zoneTele, 0.5, teleTick, function() enabled.zoneTele = false end)
    ensureWorker("buy", enabled.zoneBuy, 0.5, buyTick, function() enabled.zoneBuy = false end)
    ensureWorker("quest", enabled.autoQuest, CFG.QuestInterval, questTick, function() enabled.autoQuest = false end)
    ensureWorker("doQuest", enabled.autoDoQuest, CFG.DoQuestInterval, doQuestTick, function() enabled.autoDoQuest = false end)
    ensureWorker("rank", enabled.autoRank, 1, rankTick, function() enabled.autoRank = false end)
    ensureWorker("rebirth", enabled.autoRebirth, 1, rebirthTick, function() enabled.autoRebirth = false end)
    ensureWorker("egg", enabled.autoEgg, 0.35, eggTick, function() enabled.autoEgg = false end)
    ensureWorker("world", enabled.worldTele, 0.5, worldTeleTick, function() enabled.worldTele = false end)
    ensureWorker("advance", enabled.worldAdvance, 1, CFG.AdvanceTick, function() enabled.worldAdvance = false end)
    ensureWorker("petSlot", enabled.autoBuyPetSlots, 1, petSlotTick, function() enabled.autoBuyPetSlots = false end)
    ensureWorker("eggSlot", enabled.autoBuyEggSlots, 1, CFG.EggSlotTick, function() enabled.autoBuyEggSlots = false end)
    ensureWorker("foreverPack", enabled.autoForeverPack, 2, CFG.ForeverPackTick, function() enabled.autoForeverPack = false end)
    ensureWorker("upgrade", enabled.autoBuyUpgrades, 1.5, CFG.UpgradeTick, function() enabled.autoBuyUpgrades = false end)
    ensureWorker("enchant", enabled.autoEquipEnchant, 1.5, CFG.AutoEquipEnchantTick, function() enabled.autoEquipEnchant = false end)
    ensureWorker("tnt", enabled.autoTNT, 1, CFG.TNTTick, function() enabled.autoTNT = false end)
    ensureWorker("tntCrate", enabled.autoTNTCrate, 1, CFG.TNTCrateTick, function() enabled.autoTNTCrate = false end)
    ensureWorker("keys", enabled.autoKeys, 1, keyTick, function() enabled.autoKeys = false end)
    ensureWorker("bags", enabled.autoGiftBags, 1, bagTick, function() enabled.autoGiftBags = false end)
-- Auto Season Pass (EventPass_Get + EventPass_Buy) & Auto Claim Free Zone Gifts (DailyRewards, Free Gifts, Free Vending, Forever Pack)
function CFG.SeasonPassTick()
    local now = os.clock()
    if now < (nextAt.seasonPass or 0) then return end
    nextAt.seasonPass = now + 5.0
    local passName = nil
    local epu = nil
    pcall(function()
        epu = require(RS.Library.Util.EventPassUtil)
        if epu and type(epu.Current) == "function" then
            passName = epu.Current()
        end
    end)
    if type(passName) ~= "string" or #passName == 0 then
        notes.seasonPass = "no active season pass"
        return
    end
    local state = invoke("EventPass_Get", passName)
    if type(state) ~= "table" or state.Buying == false then
        notes.seasonPass = "season pass unavailable"
        return
    end
    local stars = tonumber(state.Stars) or 0
    local spent = tonumber(state.Spent) or 0
    local owned = type(state.Owned) == "table" and state.Owned or {}
    local tierUnlock = type(state.TierUnlock) == "table" and state.TierUnlock or {}
    local claimed = 0
    pcall(function()
        local d = epu.Get(passName)
        local ws = d and type(epu.WeekSet) == "function" and epu.WeekSet(d, tonumber(state.Week) or 1) or nil
        local tiers = ws and (ws.Tiers or ws.Rewards) or nil
        if type(tiers) == "table" then
            for ti, tier in ipairs(tiers) do
                local unlockReq = tonumber(tierUnlock[ti]) or 0
                if spent >= unlockReq then
                    local list = type(tier) == "table" and (tier.Rewards or tier) or {}
                    for _, rw in ipairs(list) do
                        if type(rw) == "table" and type(rw.Key) == "string" and not owned[rw.Key] then
                            local cost = tonumber(rw.Cost) or 0
                            local soon = type(epu.ComingSoon) == "function" and epu.ComingSoon(rw)
                            local sold = type(epu.SoldOut) == "function" and epu.SoldOut(rw)
                            if not soon and not sold and stars >= cost then
                                local ok = invoke("EventPass_Buy", passName, rw.Key)
                                if ok then
                                    claimed += 1
                                    stars -= cost
                                    spent += cost
                                    owned[rw.Key] = true
                                    task.wait(0.2)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    notes.seasonPass = claimed > 0
        and ("claimed %d reward(s) (%d tokens left)"):format(claimed, stars)
        or ("%s: %d tokens (ready)"):format(passName, stars)
end

function CFG.ZoneGiftsTick()
    local now = os.clock()
    if now < (nextAt.zoneGifts or 0) then return end
    nextAt.zoneGifts = now + 8.0
    local claimed = 0
    -- 1. Free Playtime Gifts (1..12)
    local save = getSave()
    local redeemed = save and type(save.FreeGiftsRedeemed) == "table" and save.FreeGiftsRedeemed or {}
    for id = 1, 12 do
        if not redeemed[id] and not redeemed[tostring(id)] then
            local ok = invoke("Redeem Free Gift", id)
            if ok == true then claimed += 1 end
        end
    end
    -- 2. Free Forever Pack
    local okFP = invoke("ForeverPacks: Claim Free")
    if okFP == true then claimed += 1 end
    -- 3. Free Zone Daily / Timed Rewards
    local dirRoot = RS:FindFirstChild("__DIRECTORY")
    local timedFolder = dirRoot and dirRoot:FindFirstChild("TimedRewards")
    if timedFolder then
        for _, child in ipairs(timedFolder:GetDescendants()) do
            if child:IsA("ModuleScript") then
                local okM, mod = pcall(require, child)
                local rid = (okM and type(mod) == "table" and mod._id) or child.Name:gsub("^(.-)%s*|%s*", "")
                if type(rid) == "string" and #rid > 0 then
                    local okD = invoke("DailyRewards_Redeem", rid)
                    if okD == true then claimed += 1; task.wait(0.1) end
                end
            end
        end
    end
    -- 4. Free Zone Vending Machines (Price == 0)
    local vmFolder = dirRoot and dirRoot:FindFirstChild("VendingMachines")
    if vmFolder then
        for _, child in ipairs(vmFolder:GetDescendants()) do
            if child:IsA("ModuleScript") then
                local okM, mod = pcall(require, child)
                if okM and type(mod) == "table" and (mod.Price == nil or mod.Price == 0) then
                    local vid = mod._id or child.Name:gsub("^(.-)%s*|%s*", "")
                    if type(vid) == "string" and #vid > 0 then
                        local okV = invoke("VendingMachines_Purchase", vid, 1)
                        if okV == true then claimed += 1; task.wait(0.1) end
                    end
                end
            end
        end
    end
    if claimed > 0 then nextAt.save = 0 end
    notes.zoneGifts = claimed > 0 and ("claimed " .. claimed .. " free zone gift(s)") or "checked free zone gifts"
end

    ensureWorker("spin", enabled.autoSpinTickets, 0.15, spinTick, function() enabled.autoSpinTickets = false end)
    ensureWorker("seasonPass", enabled.autoSeasonPass, 5.0, CFG.SeasonPassTick, function() enabled.autoSeasonPass = false end)
    ensureWorker("zoneGifts", enabled.autoZoneGifts, 8.0, CFG.ZoneGiftsTick, function() enabled.autoZoneGifts = false end)
    ensureWorker("chests", enabled.autoOpenChests, 1, chestTick, function() enabled.autoOpenChests = false end)
    ensureWorker("fruits", enabled.autoFruits, 1, fruitTick, function() enabled.autoFruits = false end)
    ensureWorker("potions", enabled.autoPotions, 1, potionTick, function() enabled.autoPotions = false end)
    ensureWorker("freeGift", enabled.autoFreeGifts, 1, freeGiftTick, function() enabled.autoFreeGifts = false end)
    ensureWorker("ultimate", enabled.autoUltimate, 1, ultimateTick, function() enabled.autoUltimate = false end)
    ensureWorker("sprinkler", enabled.autoSprinkler, 2, CFG.SprinklerTick, function() enabled.autoSprinkler = false end)
    ensureWorker("daycare", enabled.autoDaycare, 1, daycareTick, function() enabled.autoDaycare = false end)
    ensureWorker("flags", enabled.autoFlags, 1, flagTick, function() enabled.autoFlags = false end)
    ensureWorker("secret", enabled.autoSecretRooms, 1, secretRoomTick, function() enabled.autoSecretRooms = false end)
    ensureWorker("treehouse", enabled.autoTreehouse, 1, treehouseTick, function() enabled.autoTreehouse = false end)
    ensureWorker("fuse", enabled.autoFuse, 1, fuseTick, function() enabled.autoFuse = false end)
    ensureWorker("cards", enabled.autoCards, 1, cardTick, function() enabled.autoCards = false end)
    ensureWorker("dice", enabled.autoDice, 1, diceTick, function() enabled.autoDice = false end)
    ensureWorker("relics", enabled.autoRelics, 1, relicTick, function() enabled.autoRelics = false end)
    ensureWorker("mailClaim", enabled.autoMailClaim, 1, mailClaimTick, function() enabled.autoMailClaim = false end)
    ensureWorker("hop", enabled.serverHop, CFG.HopInterval, hopTick, function() enabled.serverHop = false end)
    ensureWorker("pumpkinEvent", eventWanted, (enabled.ptAutoBreakPumpkins or enabled.ptAutoFightTurkey) and 0.12 or 0.4, CFG.Event.Tick)
    if not eventWanted then notes.event = "off" end
    ensureWorker("timeTrial", ttWanted, CFG.TimeTrialInterval or 0.12, CFG.TimeTrial.Tick)
    if not ttWanted then notes.timeTrial = "off" end
    if not enabled.optBreakables and not enabled.reduceCpuRam and not enabled.optPumpkinTycoon then restoreEffects(optBreakableEffects) end
    if not enabled.optPets and not enabled.hideEggFx and not enabled.reduceCpuRam then restoreEffects(optPetEffects) end
    if enabled.optBreakables or enabled.optPets or enabled.hideEggFx or enabled.reduceCpuRam then
        ensureWorker("optimize", true, CFG.OptimizeInterval, function()
            optimizeTick()
            if enabled.reduceCpuRam then CFG.SyncReduceCpuRam() end
        end, function() enabled.optBreakables = false; enabled.optPets = false end)
    else
        stopWorker("optimize")
        notes.optimize = "off"
    end
    if enabled.auraVisual then ensureAuraPart() else destroyAuraPart() end
    if not enabled.tap and not enabled.farm and not enabled.fastFarmBeta and not enabled.clickAura and not enabled.autoDoQuest then
        target.model, target.uid, target.at, targetScan = nil, nil, nil, nil
        auraTargets, auraCursor = {}, 0
        petState.routeTarget, petState.routeAt = nil, nil
        petState.attackModel, petState.attackUid = nil, nil
        table.clear(petState.teleportedTarget)
        table.clear(petState.assignedModel)
        table.clear(petState.assignedUid)
        table.clear(petState.joinedTarget)
        notes.tap = "off"
    end
    if not enabled.vacuum and not enabled.farm and not enabled.fastFarmBeta and not enabled.autoDoQuest and not enabled.ptAutoBreakPumpkins and not enabled.autoTimeTrial then restoreOrbCapture(); notes.vacuum = "off" end
end

updateToggles = function() end

setEnabled = function(key, value)
    if not alive then return false, "stopped" end
    if enabled[key] == nil or type(value) ~= "boolean" then return false, "invalid toggle" end
    enabled[key] = value
    syncWorkers()
    updateToggles()
    return true
end

local function allOff()
    for key in pairs(enabled) do enabled[key] = false end
    syncWorkers()
    updateToggles()
    stage("All features off; already-sent requests cannot be recalled")
end

local function updateStatus()
    local now = os.clock()
    local restarted = false
    for name, worker in pairs(workers) do
        if worker.lastBeat and now - worker.lastBeat > math.max(180, worker.interval * 12) then
            stopWorker(name)
            stage(name .. ": stalled; restarting")
            restarted = true
        end
    end
    if restarted then syncWorkers() end
    local save = getSave()
    local best = maxOwned(save)
    local count = 0
    for _ in pairs(zones) do count += 1 end
    if auraPart then
        local point = position()
        if point then pcall(function() auraPart.Position = point end) end
    end
    info = {
        zones = count,
        best = tostring(best and zones[best].id or "unknown"),
        here = tostring(currentZone() or "unknown"),
        world = currentWorldNumber(),
        targetWorld = worldTarget,
        bestWorld = bestUnlockedWorld(save),
        rank = tostring(save and save.Rank or "?"),
        stars = tostring(save and save.RankStars or "?"),
        rebirths = tostring(save and save.Rebirths or "?"),
    }
end

cleanup = function()
    if not alive then return end
    alive = false
    for key in pairs(enabled) do enabled[key] = false end
    syncAntiAfk()
    syncEggFx()
    syncNoclip()
    syncFly()
    syncGamepasses()
    syncGates()
    CFG.SyncFastFarmBeta()
    CFG.SyncWhiteScreen()
    CFG.SyncReduceCpuRam()
    for name in pairs(workers) do stopWorker(name) end
    heapObjects, heapCursor, treeScan, targetScan, stats.pending = nil, nil, nil, nil, nil
    for _, request in pairs(requests) do
        if request.thread and request.thread ~= coroutine.running() then pcall(task.cancel, request.thread) end
    end
    table.clear(requests)
    if stats.connection then stats.connection:Disconnect(); stats.connection = nil end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    restorePetSpeed()
    restoreOrbCapture()
    restoreEffects(optBreakableEffects)
    restoreEffects(optPetEffects)
    destroyAuraPart()
    table.clear(legitTeleDone)
    unpublish()
    print("[Steph HUB] unloaded")
end

local controller = {
    SetEnabled = setEnabled,
    ClaimRankRewards = claimRankRewards,
    AllOff = allOff,
    Stop = cleanup,
    TeleportIsland = teleportToIslandMiddle,
    EnterPumpkinTycoon = function()
        return CFG.Event.Enter()
    end,
    EnterTimeTrial = function()
        return CFG.TimeTrial.Enter()
    end,
    LeaveTimeTrial = function()
        return CFG.TimeTrial.Leave()
    end,
    TeleportTimeTrialZone = function()
        return CFG.TimeTrial.TeleportToZone()
    end,
    OpenTimeTrialChest = function(tier)
        return CFG.TimeTrial.OpenChest(tier)
    end,
    GetTimeTrialStatus = function()
        return CFG.TimeTrial.GetStatus()
    end,
    SetEventOpt = function(key, value, subKey)
        if subKey ~= nil and type(CFG.EventOpts[key]) == "table" then
            CFG.EventOpts[key][subKey] = value
            return true, CFG.EventOpts[key]
        end
        if CFG.EventOpts[key] == nil then return false, "unknown event opt" end
        CFG.EventOpts[key] = value
        return true, value
    end,
    GetEventOpts = function()
        return CFG.EventOpts
    end,
    TeleportBestWorld = function()
        local save = getSave()
        local bestW = bestUnlockedWorld(save)
        return teleportToWorldOrBestIsland(bestW)
    end,
    TeleportToFarm = function()
        local save = getSave()
        if not save then return false, "waiting for profile" end
        local best = maxOwned(save)
        if not best or not zones[best] then return false, "waiting for zone map" end
        return teleportToIslandMiddle(zones[best].id)
    end,
    TeleportEventFarm = function()
        return CFG.Event.TeleToFarm()
    end,
    HatchEgg = function(eggId, count)
        return hatchEggById(eggId, count, true)
    end,
    Cheat = runCheatAction,
    GetCatalog = function()
        return scanLiveDirectory()
    end,
    GetWorldCatalog = function()
        local w = detectActiveWorld()
        local wMin = (CFG.WorldFirst and CFG.WorldFirst[w]) or (w == 1 and 1 or (w == 2 and 100 or (w == 3 and 200 or 240)))
        local wMax = (CFG.WorldFirst and CFG.WorldFirst[w + 1] and (CFG.WorldFirst[w + 1] - 1)) or (w == 1 and 99 or (w == 2 and 199 or (w == 3 and 239 or 999)))
        local worldIslands = {}
        for num = wMin, math.min(wMax, 350) do
            if zones[num] then
                worldIslands[#worldIslands + 1] = zones[num].id
            end
        end
        local worldEggs = {}
        local seenEgg = {}
        pcall(function()
            local dir = require(RS.Library.Directory)
            local eggsDir = dir and dir.Eggs
            if type(eggsDir) == "table" then
                local ordered = {}
                for id, data in pairs(eggsDir) do
                    if type(data) == "table" and type(data.eggNumber) == "number" then
                        local en = data.eggNumber
                        if en >= wMin and en <= wMax then
                            ordered[#ordered + 1] = { num = en, id = tostring(id) }
                        end
                    end
                end
                table.sort(ordered, function(a, b) return a.num < b.num end)
                for _, e in ipairs(ordered) do
                    if not seenEgg[e.id] then
                        seenEgg[e.id] = true
                        worldEggs[#worldEggs + 1] = e.id
                    end
                end
            end
        end)
        if #worldEggs == 0 then
            for num = wMin, math.min(wMax, 350) do
                if eggByNumber[num] and not seenEgg[eggByNumber[num]] then
                    seenEgg[eggByNumber[num]] = true
                    worldEggs[#worldEggs + 1] = eggByNumber[num]
                end
            end
        end
        return { world = w, islands = worldIslands, eggs = worldEggs }
    end,
    ClearPicks = function(category)
        local store = picked[category]
        if not store then return false, "unknown category" end
        table.clear(store)
        return true, 0
    end,
    SetPick = function(category, id, value)
        local store = picked[category]
        if not store then return false, "unknown category" end
        if type(value) == "boolean" then
            store[id] = value or nil
        else
            togglePick(store, id)
        end
        return true, pickCount(store)
    end,
    SetConfig = function(key, value)
        if CFG[key] == nil then return false, "unknown knob" end
        if type(CFG[key]) == "string" then
            CFG[key] = tostring(value)
            syncWorkers()
            return true, CFG[key]
        end
        if type(CFG[key]) ~= "number" then return false, "unknown knob" end
        local number = tonumber(value)
        if not number then return false, "not a number" end
        CFG[key] = number
        if key == "TapRange" and auraPart and auraPart.Parent then
            pcall(function() auraPart.Size = Vector3.new(0.3, number * 2, number * 2) end)
        end
        syncWorkers()
        return true, number
    end,
    HopNow = function()
        task.spawn(hopTick, true)
        return true, "searching low-player server"
    end,
    GetConfig = function(key)
        if CFG[key] == nil then return nil end
        return CFG[key]
    end,
    GetPicks = function()
        local out = {}
        for category, store in pairs(picked) do out[category] = table.clone(store) end
        return out
    end,
    GetStatus = function()
        getSave()
        return {
            running = alive,
            enabled = table.clone(enabled),
            world = worldTarget,
            profile = snap.source,
            notes = table.clone(notes),
            info = table.clone(info),
        }
    end,
}
controller.Status = stage
controller.GetEnabled = function()
    return table.clone(enabled)
end
controller.IsRunning = function()
    return alive
end
controller.GetKnobs = function()
    return table.clone(CFG)
end
controller.GetNotes = function()
    return table.clone(notes)
end
controller.GetWorld = function()
    return worldTarget, CFG.WorldCount
end
controller.SetWorld = setWorldTarget
controller.PickList = function()
    local out = {}
    for _, category in ipairs(PICK_CATEGORIES) do
        out[category[1]] = { title = category[2], items = pickItems(category[1]) }
    end
    return out
end
worldTarget = currentWorldNumber()
publish()
if not alive then return controller end
task.defer(CFG.BootstrapModules)
task.defer(scanLiveDirectory)
connect(LocalPlayer.CharacterAdded, function()
    target.model, target.uid, target.at = nil, nil, nil
    petState.routeTarget, petState.routeAt = nil, nil
    petState.attackModel, petState.attackUid = nil, nil
    table.clear(petState.teleportedTarget)
    table.clear(petState.assignedModel)
    table.clear(petState.assignedUid)
    table.clear(petState.joinedTarget)
end)
ensureWorker("status", true, 1, updateStatus)
stage("Ready; headless; no startup scans")
return controller
