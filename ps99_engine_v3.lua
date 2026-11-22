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
local function hostPut(target, key, value) target[key] = value end
local function hostGet(target, key) return target[key] end
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
    -- Effectively infinite: the pet render clamps lerp alpha to [n1,1], so this
    -- saturates to an instant snap. Finite (not math.huge) avoids 0*inf=NaN when
    -- a frame's delta time is zero, which would permanently corrupt the pet CFrame.
    PetSpeedMult = 1e9,
    PetInterval = 0.1,
    TapRate = 26,
    FarmTapRate = 64,
    TapRange = 220,
    MaxTapRate = 48,
    AuraRate = 32,
    AntiAfkCooldown = 60,
    TargetRescan = 0.12,
    BreakableScanCap = 1500,
    VacuumRate = 0.1,
    TeleInterval = 0.4,
    TeleBackoff = 3,
    BuyInterval = 4,
    BuyBackoff = 12,
    QuestInterval = 2,
    QuestBackoff = 25,
    EnsureBackoff = 45,
    QuestMaxRequests = 2,
    RankInterval = 4,
    RebirthInterval = 20,
    EggInterval = 1.2,
    EggRange = 250,
    EggMaxHatch = 50,
    WorldInterval = 1,
    WorldBackoff = 3,
    WorldAdvanceInterval = 2,
    -- Directory.Worlds only defines World 1-4 (and WorldsUtil.GetEggsModelName
    -- returns nil past 4), so anything higher can never be reached.
    WorldCount = 4,
    WorldAdvanceLimit = 3,
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
    PotionInterval = 4,
    MailInterval = 15,
    FreeGiftInterval = 20,
    FreeGiftMax = 12,
    UltimateInterval = 3,
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
    -- v2
    FarmBurst = 6,
    PetRouteRate = 0.15,
    TeleCenterWait = 2,
    ChestFirst = true,
    TeleCenter = true,
    PetAll = true,
    HideEggFx = false,
}

local enabled = {
    petSpeed = false, tap = false, vacuum = false, farm = false,
    zoneTele = false, zoneBuy = false, autoQuest = false,
    autoRank = false, autoRebirth = false, antiAfk = false, clickAura = false,
    autoEgg = false, auraVisual = false, optBreakables = false, optPets = false, worldTele = false,
    worldAdvance = false,
    hideEggFx = false, chestFirst = true, teleCenter = true, petAll = true,
    petBulkJoin = true,
    serverHop = false, autoBuyPetSlots = false, jitter = false,
    autoKeys = false, autoGiftBags = false, autoFruits = false, autoPotions = false,
    autoFreeGifts = false, autoUltimate = false, autoDaycare = false, autoFlags = false,
    autoSecretRooms = false, autoTreehouse = false, autoFuse = false, autoCards = false,
    autoRelics = false, autoMailClaim = false, autoDice = false,
}

-- Per-item selections. Every "auto X" worker above only touches the ids the
-- player ticked, matching how the game's own action menus gate consumption.
-- Picks are stored as id -> true; the workers rebuild lists from live Save
-- inventory each tick, so a pick that is not owned simply does nothing.
local picked = {
    zones = {},          -- zone id -> true (auto click / aura / teleport targeting)
    fruits = {},         -- Directory.Fruits id
    potions = {},        -- Directory.Potions id
    bags = {},           -- GiftBag_Open name
    flags = {},          -- FlexibleFlags_Consume name
    freeGifts = {},      -- numeric free gift Id
    dice = {},           -- Lucky Dice item id
    cards = {},          -- CardItem id
    keys = {},           -- KEY_PAIRS name
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
    heap = 0, save = 0, quest = {}, ensure = {},
    egg = 0, worldTele = 0, petSlot = 0,
    key = 0, bag = 0, mail = 0,
    freeGift = 0, ultimate = 0, daycare = 0, flag = 0,
    secret = 0, relic = 0, treehouse = 0, fuse = 0, card = 0, dice = 0,
    freeGiftCursor = 1, tree = 0, tap = 0, tele = 0, buy = 0, rank = 0, rebirth = 0,
}
local notes = {pet = "off", tap = "off", vacuum = "off", tele = "off", buy = "off", quest = "off", rank = "off", rebirth = "off", antiAfk = "off", egg = "off", world = "off", advance = "off", optimize = "off", hop = "off", petSlot = "off", keys = "off", bags = "off", fruits = "off", potions = "off", freeGift = "off", ultimate = "off", daycare = "off", flags = "off", secret = "off", relics = "off", treehouse = "off", fuse = "off", cards = "off", dice = "off", mailClaim = "off", heap = "idle; no startup scan", profile = "waiting for discovery"}

local petState = {previous = setmetatable({}, {__mode = "k"}), records = setmetatable({}, {__mode = "k"})}
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
    ["Orbs: Collect"] = "RemoteEvent",
    ["Teleports_RequestTeleport"] = "RemoteFunction",
    ["Zones_RequestPurchase"] = "RemoteFunction",
    ["NPC Quests: Ensure"] = "RemoteFunction",
    ["NPC Quests: Redeem"] = "RemoteFunction",
    ["Ranks_ClaimAll"] = "RemoteEvent",
    ["Ranks_ClaimReward"] = "RemoteEvent",
    ["Rebirth_Request"] = "RemoteFunction",
    ["Eggs_RequestPurchase"] = "RemoteFunction",
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
    ["Redeem Free Gift"] = "RemoteFunction",
    ["Ultimates: Activate"] = "RemoteFunction",
    ["Daycare: Enroll"] = "RemoteFunction",
    ["Daycare: Claim"] = "RemoteFunction",
    ["FlexibleFlags_Consume"] = "RemoteFunction",
    ["SecretRoom_Unlock"] = "RemoteFunction",
    ["TreehouseMerchant_Purchase"] = "RemoteFunction",
    ["FuseMachine_Activate"] = "RemoteFunction",
    ["CardCombinationMachine_ActivateBulk"] = "RemoteFunction",
    ["Relics_Request"] = "RemoteFunction",
    ["Relic_Found"] = "RemoteFunction",
    ["YS_Load"] = "RemoteFunction",
    ["RD_Ingest"] = "RemoteFunction",
    ["Lootables_Open"] = "RemoteFunction",
    ["Spinny Wheel: Request Spin"] = "RemoteFunction",
}

local function stage(message)
    if not alive then return end
    print("[PS99 CLEAN] " .. tostring(message))
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

local function getSave()
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
    if (enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele or enabled.autoBuyPetSlots or enabled.worldAdvance) and not save then return true end
    if not save and (enabled.autoKeys or enabled.autoGiftBags or enabled.autoFruits or enabled.autoPotions
        or enabled.autoFreeGifts or enabled.autoUltimate or enabled.autoDaycare or enabled.autoFlags
        or enabled.autoSecretRooms or enabled.autoRelics or enabled.autoTreehouse or enabled.autoFuse
        or enabled.autoCards or enabled.autoMailClaim) then return true end
    if enabled.autoRebirth and save and not rebirths[save.Rebirths + 1] then return true end
    if enabled.autoQuest and save and type(save.NPCQuests) == "table" then
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
        if not record.destroyed and record.speedMult == CFG.PetSpeedMult then
            local ok, err = pcall(function()
                record.speedMult = previous
                local cpet = record.cpet
                if type(cpet) == "table" then
                    cpet:Broadcast("petSpeedMult", previous)
                    cpet.parallelIn.petSpeedMult = previous
                end
            end)
            if not ok then warn("[PS99 CLEAN] pet reset: " .. tostring(err)) end
        end
    end
    table.clear(petState.previous)
    petState.module, petState.original, petState.hook = nil, nil, nil
    notes.pet = "off"
end

local function petTick()
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
                -- Only the game's own caller computes the native multiplier.
                local ok, result = pcall(original, pet, ...)
                if not ok then return pet and pet.speedMult or 1 end
                if alive and (enabled.petSpeed or enabled.farm) and pet and pet.owner == LocalPlayer then
                    petState.previous[pet] = result
                    return CFG.PetSpeedMult
                end
                return result
            end
            -- A frozen module cannot be patched; the per-tick write below still
            -- drives the pets, so carry on instead of failing the worker.
            local ok, err = pcall(function() mod.CalculateSpeedMultiplier = hook end)
            if ok then
                petState.module, petState.original, petState.hook = mod, original, hook
            else
                notes.pet = "module read-only: " .. tostring(err)
            end
        end
    end
    local count = 0
    local seen = {}
    local function apply(record)
        if seen[record] or record.destroyed
            or (record.owner ~= nil and record.owner ~= LocalPlayer) then return end
        seen[record] = true
        if petState.previous[record] == nil then petState.previous[record] = tonumber(record.speedMult) end
        -- The record is the game's live object; a write can throw if the pet
        -- died mid-tick, so each mutation is isolated.
        local ok = pcall(function() record.speedMult = CFG.PetSpeedMult end)
        if not ok then return end
        -- PetRendering multiplies input.petSpeedMult, and input IS cpet.parallelIn.
        -- Broadcast records the value and flushes it to the actor next frame;
        -- writing parallelIn covers the frames before that flush runs.
        local cpet = record.cpet
        if type(cpet) == "table" then
            pcall(function() cpet:Broadcast("petSpeedMult", CFG.PetSpeedMult) end)
            pcall(function() cpet.parallelIn.petSpeedMult = CFG.PetSpeedMult end)
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
    notes.pet = count > 0 and ("Inf | %d local pets"):format(count) or "Inf | no pets equipped"
end

-- The game's own click routes your pets at the breakable (BreakableFrontend
-- tryToSendPetToBreakable -> PlayerPet.SetTarget -> CQ_Route -> the pet's own
-- Breakables_JoinPetBulk on arrival), and the server only credits pet damage
-- for pets it has been told are on that target. Firing the click remote alone
-- leaves every pet idle, so farm ended up doing click damage only. Only
-- BelongsToLocalPlayer pets may be routed, and the game sends the nearest half.
function petState.route(target, point)
    if not alive or not target or not target.Parent then return 0 end
    local mod = modules.pet
    local local_pets, seen = {}, {}
    local group = mod and type(mod.GetByPlayer) == "function" and mod.GetByPlayer(LocalPlayer) or nil
    if type(group) == "table" then
        for _, record in pairs(group) do if not seen[record] then seen[record] = true; local_pets[#local_pets + 1] = record end end
    end
    for record in pairs(petState.records) do
        if not seen[record] then seen[record] = true; local_pets[#local_pets + 1] = record end
    end
    -- Nearest first, matching the game's table.sort by distance to the target.
    local ranked = {}
    -- v3: GetByPlayer is already scoped to the local player, and some builds
    -- leave owner nil on those records. A missing owner is not a reason to
    -- leave a pet standing still while the click lands.
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
    -- v2: every owned pet is routed, not the nearest half. The half cut was
    -- the game's own click behaviour; for a farm the spare pets are wasted
    -- damage on whatever they were still standing next to.
    local limit = enabled.petAll and #ranked or math.max(1, math.ceil(#ranked / 2))
    local routed = 0
    for index = 1, math.min(limit, #ranked) do
        local record = ranked[index].record
        -- A pet already on this breakable returns false and sends nothing, so
        -- calling every tap costs one table compare rather than a remote.
        local ok = pcall(function() record:SetTarget(target) end)
        if not ok then
            -- v3: a record that lost SetTarget still routes if the field the
            -- game itself reads is written directly.
            pcall(function() record.target = target end)
            pcall(function() record.Target = target end)
        end
        if ok then routed += 1 end
    end
    -- v2: register the pets on the server side too. Breakables_JoinPetBulk is
    -- the same remote a pet's own arrival fires, so one send per target makes
    -- every routed pet count from the first tick instead of after travel. The
    -- stamp stops a 0.15 s re-route from resending for the same breakable.
    if enabled.petBulkJoin and petState.bulkTarget ~= target then
        local uid = target:GetAttribute("BreakableUID")
        if uid ~= nil then
            petState.bulkTarget = target
            pcall(fire, "Breakables_JoinPetBulk", uid)
        end
    end
    return routed
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


-- The game taps from its own registry, not from the workspace tree: the record
-- behind each uid carries dir.NoTapping / disableDamage / modifier.Owner, which
-- no attribute on the model exposes. Falls through to the tree walk when the
-- registry module was never discovered.
local function pickTarget(point, zone)
    local registry = modules.breakables
    local byZone, getRecord = registry and registry.AllByZoneAndClass, registry and registry.Get
    if type(byZone) == "function" and type(getRecord) == "function" and zone then
        local merged = {}
        for _, class in ipairs({"Normal", "Chest"}) do
            local list = byZone(zone, class)
            if type(list) == "table" then
                for uid, value in pairs(list) do merged[uid] = value end
            end
        end
        local targets, best, bestUid, bestDistance = {}, nil, nil, math.huge
        -- v2: chests are the money, so they get their own track and win the
        -- tiebreak when the switch is on.
        local chestBest, chestUid, chestDistance = nil, nil, math.huge
        for uid, value in pairs(merged) do
            -- AllByZoneAndClass hands back the breakable record; the legacy
            -- variant hands back the model. Accept either.
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
                    local at = record.position
                    if at then
                        local measured, result = pcall(function() return (at - point).Magnitude end)
                        if measured then distance = result end
                    end
                    if distance <= CFG.TapRange then
                        targets[#targets + 1] = model
                        if distance <= bestDistance then best, bestUid, bestDistance = model, uid, distance end
                        if class == "Chest" and distance <= chestDistance then
                            chestBest, chestUid, chestDistance = model, uid, distance
                        end
                    end
                end
            end
        end
        -- An empty registry is a real answer: everything in this zone is
        -- NoTapping, owned by someone else, or out of range. Walking the folder
        -- would put exactly those models back.
        if next(merged) ~= nil then
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
                if validTarget(child, point, zone) then
                    local childPos = modelPosition(child)
                    if childPos then
                        scan.targets[#scan.targets + 1] = child
                        local length = (childPos - point).Magnitude
                        local bestPos = validTarget(scan.best, point, zone) and modelPosition(scan.best) or nil
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
    if validTarget(scan.best, point, zone) then return scan.best, scan.uid end
    return nil, nil
end

local function tapTick()
    local now = os.clock()
    if now < nextAt.tap then return end
    local point = position()
    if not point then notes.tap = "waiting for character"; return end
    local zone = currentZone()
    -- Zone picker: once the player ticks zones, click/aura stay inside that set.
    if pickCount(picked.zones) > 0 and not picked.zones[zone] then
        notes.tap = "zone not selected: " .. tostring(zone or "unknown")
        target.model, target.uid = nil, nil
        return
    end
    if not validTarget(target.model, point, zone) or now - (target.at or 0) >= CFG.TargetRescan then
        target.model, target.uid = pickTarget(point, zone)
        target.at = now
    end
    -- Last resort: the game's own click target. GetAutoTapTarget applies the
    -- live AutoTap policy (range, NoTapping, zone) from the registry, so it
    -- still refuses what the folder walk cannot see.
    if not target.model and now >= (CFG.TapProbeAt or 0) then
        CFG.TapProbeAt = now + 0.5
        local registry = modules.breakables
        if registry then
            local ok, model = pcall(registry.GetAutoTapTarget)
            if ok and model and validTarget(model, point, zone) then
                target.model, target.uid = model, model:GetAttribute("BreakableUID")
                target.at = now
            end
        end
    end
    if enabled.clickAura then
        target.model, target.uid = nil, nil
        for _ = 1, #auraTargets do
            auraCursor = auraCursor % #auraTargets + 1
            local candidate = auraTargets[auraCursor]
            if validTarget(candidate, point, zone) then
                target.model, target.uid = candidate, candidate:GetAttribute("BreakableUID")
                break
            end
        end
    end
    if not target.uid then notes.tap = "no eligible breakable in range"; return end
    local interval = 1 / CFG.MaxTapRate
    if enabled.jitter then
        interval = interval * (1 + math.random() * 0.8)
        if math.random() < 0.02 then interval = interval + 0.3 + math.random() * 0.5 end
    end
    nextAt.tap = now + interval
    local ok, message = fire("Breakables_PlayerDealDamage", target.uid)
    -- v2 burst: the server credits damage per uid, so every extra in-range
    -- breakable goes out on this same tick instead of waiting a turn.
    if enabled.farm and (CFG.FarmBurst or 0) > 0 then
        local extras = 0
        for index = 1, #auraTargets do
            if extras >= CFG.FarmBurst then break end
            local candidate = auraTargets[index]
            if candidate ~= target.model and validTarget(candidate, point, zone) then
                local uid = candidate:GetAttribute("BreakableUID")
                if uid then
                    fire("Breakables_PlayerDealDamage", uid)
                    extras += 1
                end
            end
        end
    end
    -- Same order as the game's own click: damage first, then pets. Re-route on a
    -- target change or twice a second, which catches pets equipped mid-farm
    -- without re-ranking every pet on all 16 taps a second.
    if target.model ~= petState.routeTarget or now - (petState.routeAt or 0) >= CFG.PetRouteRate then
        petState.routeTarget, petState.routeAt = target.model, now
        petState.route(target.model, point)
    end
    notes.tap = ok and (enabled.clickAura and "aura: " or "tapping ") .. tostring(target.uid) or message
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

-- The game collects an orb itself when its record carries _superMagnet: the
-- RenderStepped branch in OrbCmds/Orb returns false (which queues the real
-- Network.Fire("Orbs: Collect", id)) as soon as the orb is past 150 studs. Firing
-- the remote from outside skips the record's own _collected bookkeeping, so the
-- server rejects it. Setting the flag lets Orbs: Collect come from the game.
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
            -- Infinite range: every known orb gets the magnet flag. The game's
            -- own collect branch (queued when the orb crosses its threshold)
            -- fires Orbs: Collect itself, so no distance cap here.
            if orbOffsets[record] == nil then orbOffsets[record] = record._superMagnet end
            if record._superMagnet ~= true then record._superMagnet = true end
            flagged += 1
        end
    end
    if total == 0 then notes.vacuum = "waiting for orb records; " .. notes.heap; return end
    notes.vacuum = ("%d/%d orbs magnetized"):format(flagged, total)
end


-- v3: the middle of the island is where the breakables are, not where the
-- zone's ground plate happens to sit. Centroid of the zone's own breakable
-- positions first, ground plate second, model bounding box last.
local function zoneCenter(id)
    if type(id) ~= "string" then return nil end
    local registry = modules.breakables
    if registry and type(registry.AllByZoneAndClass) == "function" then
        local sum, count = Vector3.zero, 0
        for _, class in ipairs({"Normal", "Chest"}) do
            local ok, list = pcall(registry.AllByZoneAndClass, id, class)
            if ok and type(list) == "table" then
                for _, value in pairs(list) do
                    local record = type(value) == "table" and value.model ~= nil and value or nil
                    local at = record and record.position or (typeof(value) == "Instance" and modelPosition(value))
                    if typeof(at) == "Vector3" then
                        sum += at
                        count += 1
                    end
                    if count >= 400 then break end
                end
            end
            if count >= 400 then break end
        end
        if count > 0 then return sum / count end
    end
    local ground = thingsFolder("__FAKE_GROUND")
    if not ground then return nil end
    local target = ground:FindFirstChild(id, true)
    if not target then return nil end
    local ok, box = pcall(function() return target:GetBoundingBox() end)
    if ok and box then return box.Position end
    if target:IsA("BasePart") then return target.Position end
    local ok2, pivot = pcall(function() return target:GetPivot().Position end)
    return ok2 and pivot or nil
end

local function snapTo(point)
    if not point then return false end
    local character = LocalPlayer.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if not root then return false end
    local ok = pcall(function() root.CFrame = CFrame.new(point + Vector3.new(0, 4, 0)) end)
    return ok
end

local function teleTick()
    local now = os.clock()
    if now < nextAt.tele then return end
    local save = getSave()
    if not save then notes.tele = "waiting for profile"; return end
    local best = maxOwned(save)
    if not best then notes.tele = "waiting for zone map"; return end
    local id = zones[best].id
    if currentZone() == id then notes.tele = "already in " .. id; return end
    nextAt.tele = now + CFG.TeleBackoff
    local ok, message = invoke("Teleports_RequestTeleport", id)
    if not alive or not enabled.zoneTele then return end
    notes.tele = ok == true and "accepted: " .. id or tostring(message or "rejected")
    if ok == true then
        nextAt.tele = os.clock() + CFG.TeleInterval
        -- v2: snap to the zone centre the moment the remote is accepted. The
        -- remote only switches the zone; the character would otherwise walk in
        -- from the spawn edge, which is the wait the user felt. The centre is
        -- read off __FAKE_GROUND, one part per zone id.
        if enabled.teleCenter and id then
            local centre = zoneCenter(id)
            if centre then
                snapTo(centre)
                -- the zone switch can land a frame or two after the remote
                -- returns and would overwrite the CFrame, so re-snap twice.
                task.delay(0.2, function()
                    if alive and enabled.teleCenter then snapTo(zoneCenter(id)) end
                end)
                task.delay(0.6, function()
                    if alive and enabled.teleCenter then snapTo(zoneCenter(id)) end
                end)
            end
        end
    end
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
    if not save or type(save.NPCQuests) ~= "table" then notes.quest = "waiting for quests"; return end
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
    -- ClaimAll is the batch path; the per-index remote is the fallback when
    -- the batch remote is missing or refused for one specific reward.
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
        -- Rank directory not on the heap yet. ClaimAll is server-validated
        -- (it only pays earned, unredeemed rewards) and costs one remote, so
        -- it doubles as the probe while discovery catches up.
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
        -- The game keys redemption state by tostring(index) and treats false
        -- as redeemed, so only a missing key counts as claimable.
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

local function closestEgg(point)
    local best, bestNumber, bestDistance
    for _, folderName in ipairs({"ZoneEggs", "Eggs"}) do
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
                            if number and at then
                                local distance = (at - point).Magnitude
                                if distance <= CFG.EggRange and (not bestDistance or distance < bestDistance) then
                                    best, bestNumber, bestDistance = child, number, distance
                                end
                            end
                            if child:IsA("Folder") or child:IsA("Model") then queue[#queue + 1] = child end
                        end
                    end
                end
                if visited % 500 == 0 then task.wait() end
            end
        end
    end
    return best, bestNumber
end

local function eggTick()
    local now = os.clock()
    if now < nextAt.egg then return end
    local save = getSave()
    if not save then notes.egg = "waiting for profile"; return end
    local point = position()
    if not point then notes.egg = "waiting for character"; return end
    if next(eggByNumber) == nil then notes.egg = "waiting for egg directory; " .. notes.heap; return end
    local _, number = closestEgg(point)
    if not number then notes.egg = "no egg in range"; return end
    local eggId = eggByNumber[number]
    if not eggId then notes.egg = "egg " .. number .. " not in directory"; return end
    local count = math.clamp(type(save.EggHatchCount) == "number" and save.EggHatchCount or 1, 1, CFG.EggMaxHatch)
    nextAt.egg = now + CFG.EggInterval
    local ok, message = invoke("Eggs_RequestPurchase", eggId, count)
    if not alive or not enabled.autoEgg then return end
    notes.egg = ok == true and ("opened %s x%d"):format(eggId, count) or tostring(message or "rejected")
end

local function worldTeleTick()
    local now = os.clock()
    if now < nextAt.worldTele then return end
    local save = getSave()
    if not save then notes.world = "waiting for profile"; return end
    local number = bestInWorld(save, worldTarget)
    if not number then notes.world = "world " .. worldTarget .. " zone map unavailable"; return end
    local id = zones[number].id
    if currentZone() == id then notes.world = "already in world " .. worldTarget .. " (" .. id .. ")"; return end
    nextAt.worldTele = now + CFG.WorldBackoff
    local ok, message = invoke("Teleports_RequestTeleport", id)
    if not alive or not enabled.worldTele then return end
    notes.world = ok == true and ("world %d -> %s"):format(worldTarget, id) or tostring(message or "rejected")
    if ok == true then nextAt.worldTele = os.clock() + CFG.WorldInterval end
end

-- Progression: world 1 first, then 2, then 3. A world counts as reached once a
-- zone at or past its first number is unlocked (owning zone 100 means world 2),
-- which matches how the server gates teleports. World 4 stays opt-in because
-- the default cap is 3.
CFG.AdvanceTick = function()
    local now = os.clock()
    if now < (CFG.AdvanceNext or 0) then return end
    local save = getSave()
    if not save then notes.advance = "waiting for profile"; return end
    local limit = math.min(CFG.WorldAdvanceLimit, CFG.WorldCount)
    if worldTarget >= limit then notes.advance = "holding world " .. worldTarget .. " (cap " .. limit .. ")"; return end
    local best = maxOwned(save)
    if not best then notes.advance = "no unlocked zones yet"; return end
    local nextWorld = worldTarget
    for world = worldTarget + 1, limit do
        if best >= (CFG.WorldFirst[world] or math.huge) then nextWorld = world end
    end
    if nextWorld == worldTarget then
        notes.advance = ("world %d until zone %d (owned %d)"):format(worldTarget, CFG.WorldLast[worldTarget] or 0, best)
        return
    end
    CFG.AdvanceNext = now + CFG.WorldAdvanceInterval
    worldTarget = nextWorld
    if enabled.worldTele then nextAt.worldTele = 0 end
    notes.advance = "advanced -> world " .. nextWorld
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

-- v2: egg folders are not named the same in every zone build, so the names
-- are read off the live things root instead of hard-coded.
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

local function optimizeTick()
    local changed = 0
    if enabled.optBreakables then changed += suppressEffects("Breakables", optBreakableEffects) end
    if enabled.optPets then changed += suppressEffects("Pets", optPetEffects) end
    -- v2: hatch effects live under the egg folders, not under Pets, so the
    -- pet switch never touched them. Names come off the live root each pass,
    -- which survives the folder being called Eggs, ZoneEggs or EggHatchFx.
    if enabled.hideEggFx then
        for _, name in ipairs(eggFolderNames()) do
            changed += suppressEffects(name, optPetEffects)
        end
        changed += suppressEffects("Eggs", optPetEffects)
        changed += suppressEffects("ZoneEggs", optPetEffects)
    end
    notes.optimize = ("breakables %s | pets %s | +%d"):format(
        enabled.optBreakables and "on" or "off", enabled.optPets and "on" or "off", changed)
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
    nextAt.petSlot = now + CFG.PetSlotBackoff
    local ok, message = invoke("EquipSlotsMachine_RequestPurchase", slot)
    if not alive or not enabled.autoBuyPetSlots then return end
    notes.petSlot = ok == true and ("bought slot " .. slot) or tostring(message or "rejected")
    if ok == true then nextAt.petSlot = os.clock() + CFG.PetSlotInterval; nextAt.save = 0 end
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

-- Stack items in a save bucket: {uid = id, amount = n, data = raw}, sorted by id.
local function stackList(bucket)
    local out = {}
    if not bucket then return out end
    for uid, data in pairs(bucket) do
        if type(data) == "table" and type(data.id) == "string" then
            out[#out + 1] = {uid = uid, id = data.id, amount = tonumber(data._am) or 1, data = data}
        end
    end
    table.sort(out, function(a, b)
        if a.id == b.id then return tostring(a.uid) < tostring(b.uid) end
        return a.id < b.id
    end)
    return out
end

-- Verified against the game's own action menus. Fiesta keys combine through
-- TN_Bind / MW_Reduce (KeyCombine.Build), not a *_Combine endpoint; the prison
-- combiner consumes plain "Prison Key" stacks and takes a count only.
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

-- Names passed as arg 1 to GiftBag_Open by the game's own action menus.
local BAG_KINDS = {
    "Gift Bag", "Large Gift Bag", "Seed Bag", "Diamond Gift Bag",
    "Fruit Bundle", "Potion Bundle", "Large Potion Bundle",
    "Enchant Bundle", "Large Enchant Bundle", "Flag Bundle",
    "Toy Bundle", "Mini Chest", "Rainbow Mini Chest", "Charm Stone",
}

local FLAG_NAMES = {
    "Coins Flag", "Diamonds Flag", "Fortune Flag", "Hasty Flag",
    "Magnet Flag", "Rainbow Flag", "Shiny Flag", "Strength Flag",
    "Exotic Treasure Flag",
}

-- Directory.Fruits / Directory.Potions ids (module-name suffix after the "| ").
local FRUIT_IDS = {"Apple", "Banana", "Candycane", "Orange", "Pineapple", "Rainbow", "Watermelon"}
local POTION_IDS = {
    "Coins", "Damage", "Diamonds", "Huge", "Lucky",
    "The Cocktail", "Treasure Hunter", "Walkspeed",
}
local DICE_IDS = {
    "Lucky Dice V2", "Lucky Dice II V2", "Lucky Dice III V2",
    "Mega Lucky Dice V2", "Mega Lucky Dice II V2", "Fire Dice V2",
}
local MEGA_DICE = {["Mega Lucky Dice V2"] = true, ["Mega Lucky Dice II V2"] = true}
local FREE_GIFT_MAX = 12

-- Category catalogue surfaced by the Picks tab. Each entry maps a picked.* store
-- to the ids the game itself uses in its action menus.
local PICK_CATEGORIES = {
    {"zones", "Zones"}, {"keys", "Keys"}, {"bags", "Bags"}, {"fruits", "Fruits"},
    {"potions", "Potions"}, {"flags", "Flags"}, {"dice", "Dice"},
    {"cards", "Cards"}, {"freeGifts", "Gifts"},
}

local function pickItems(category)
    local out = {}
    if category == "zones" then
        for id in pairs(zones) do out[#out + 1] = id end
        table.sort(out)
    elseif category == "keys" then
        for _, pair in ipairs(KEY_PAIRS) do out[#out + 1] = pair.name end
    elseif category == "bags" then
        for _, name in ipairs(BAG_KINDS) do out[#out + 1] = name end
    elseif category == "fruits" then
        for _, id in ipairs(FRUIT_IDS) do out[#out + 1] = id end
    elseif category == "potions" then
        for _, id in ipairs(POTION_IDS) do out[#out + 1] = id end
    elseif category == "flags" then
        for _, name in ipairs(FLAG_NAMES) do out[#out + 1] = name end
    elseif category == "dice" then
        for _, id in ipairs(DICE_IDS) do out[#out + 1] = id end
    elseif category == "freeGifts" then
        for id = 1, FREE_GIFT_MAX do out[#out + 1] = id end
    elseif category == "cards" then
        local seen = {}
        for _, card in ipairs(stackList(inventory(getSave(), "Card"))) do
            if not seen[card.id] then seen[card.id] = true; out[#out + 1] = card.id end
        end
    end
    return out
end

-- Selection defaults: when the player has not ticked anything in a category the
-- worker behaves like the older "consume everything" mode, so toggling an
-- "Auto X" row still does something useful on a fresh install.
local function allowAll(store, id)
    return pickCount(store) == 0 or store[id] == true
end

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
    notes.keys = "no selected key halves to combine"
end

local function bagTick()
    local now = os.clock()
    if now < nextAt.bag then return end
    local save = getSave()
    if not save then notes.bags = "waiting for profile"; return end
    local buckets = {"Misc", "Lootbox"}
    for _, kind in ipairs(BAG_KINDS) do
        if allowAll(picked.bags, kind) then
            for _, bucketName in ipairs(buckets) do
                for _, item in ipairs(stackList(inventory(save, bucketName))) do
                    if not alive or not enabled.autoGiftBags then return end
                    if item.id == kind then
                        nextAt.bag = now + CFG.BagInterval
                        local amount = math.max(1, math.min(item.amount, CFG.BagMaxOpen))
                        local ok, message = invoke("GiftBag_Open", kind, amount)
                        if not alive or not enabled.autoGiftBags then return end
                        notes.bags = ok == true and ("opened " .. kind .. " x" .. amount) or tostring(message or "rejected")
                        if ok == true then nextAt.save = 0 end
                        return
                    end
                end
            end
        end
    end
    notes.bags = "no selected bags in inventory"
end

local consumeNext = {Fruit = 0, Potion = 0}
local function consumeTick(kind, remote, noteKey)
    local now = os.clock()
    if now < consumeNext[kind] then return end
    local save = getSave()
    if not save then notes[noteKey] = "waiting for profile"; return end
    local store = picked[kind == "Fruit" and "fruits" or "potions"]
    local cap = kind == "Fruit" and CFG.FruitQueueLimit or CFG.PotionMaxConsume
    local interval = kind == "Fruit" and CFG.FruitInterval or CFG.PotionInterval
    for _, item in ipairs(stackList(inventory(save, kind))) do
        if not alive then return end
        if allowAll(store, item.id) then
            consumeNext[kind] = now + interval
            local count = math.max(1, math.min(item.amount, cap))
            local ok, message = fire(remote, item.uid, count)
            if not alive then return end
            notes[noteKey] = ok and ("consumed " .. item.id .. " x" .. count) or tostring(message or "rejected")
            if ok then nextAt.save = 0 end
            return
        end
    end
    notes[noteKey] = "no selected stacks in inventory"
end

local function fruitTick() consumeTick("Fruit", "Fruits: Consume", "fruits") end
local function potionTick() consumeTick("Potion", "Potions: Consume", "potions") end

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

local function ultimateTick()
    local now = os.clock()
    if now < nextAt.ultimate then return end
    local save = getSave()
    if not save then notes.ultimate = "waiting for profile"; return end
    -- UltimateCmds.UltimatesUnlocked() gates the whole system on 4 rebirths.
    if (tonumber(save.Rebirths) or 0) < 4 then notes.ultimate = "unlocks at 4 rebirths"; return end
    local id = save.EquippedUltimate
    if type(id) ~= "string" then
        -- Nothing equipped: equip the highest-XP ultimate the player owns.
        local best, bestXP = nil, -1
        for candidate, xp in pairs(type(save.Ultimates) == "table" and save.Ultimates or {}) do
            local value = tonumber(xp) or 0
            if type(candidate) == "string" and value > bestXP then best, bestXP = candidate, value end
        end
        if not best then notes.ultimate = "no ultimate owned"; return end
        nextAt.ultimate = now + CFG.UltimateInterval
        local ok, message = invoke("Ultimates: Equip", best)
        if not alive or not enabled.autoUltimate then return end
        notes.ultimate = ok == true and ("equipped " .. best) or tostring(message or "rejected")
        if ok == true then nextAt.save = 0 end
        return
    end
    local cooldowns = type(save.UltimateCooldowns) == "table" and save.UltimateCooldowns or {}
    local charge = tonumber(cooldowns[id]) or 0
    if charge < 1 then notes.ultimate = ("charging %s (%d%%)"):format(id, math.floor(charge * 100)); return end
    nextAt.ultimate = now + CFG.UltimateInterval
    local ok, message = invoke("Ultimates: Activate", id)
    if not alive or not enabled.autoUltimate then return end
    notes.ultimate = ok == true and ("activated " .. id) or tostring(message or "rejected")
    if ok == true then nextAt.save = 0 end
end

-- Mirrors DaycareCmds.ComputeRemainingTime: offline time counts 1x, online 3x.
-- ComputeSaveAge = (save.Age or 0) + max(0, serverNow - save.LoginTime).
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
    -- DaycareCmds.GetMaxSlots: 10 free + 25 gamepass + DaycareVouchers.
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
    for _, item in ipairs(stackList(inventory(save, "Misc"))) do
        if not alive or not enabled.autoFlags then return end
        if item.id:match(" Flag$") and allowAll(picked.flags, item.id) then
            nextAt.flag = now + CFG.FlagInterval
            local ok, message = invoke("FlexibleFlags_Consume", item.id, item.uid, 1)
            if not alive or not enabled.autoFlags then return end
            notes.flags = ok == true and ("deployed " .. item.id) or tostring(message or "rejected")
            if ok == true then nextAt.save = 0 end
            return
        end
    end
    notes.flags = "no selected flags in inventory"
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
            -- CardItem:GetCombinationRequirement() defaults to Balancing.RequiredPerPetCardConversion (3).
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
            -- ActionMenu_Misc_Lucky_Dice_V2 / Mega: Invoke(remote, Id, count).
            -- Fire Dice V2's menu sends the count alone.
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

local function hopTick()
    local count = #Players:GetPlayers()
    if count <= CFG.HopMaxPlayers then notes.hop = ("server has %d players (limit %d)"):format(count, CFG.HopMaxPlayers); return end
    local body = httpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?limit=100")
    if not body then notes.hop = "no HTTP function available"; return end
    local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
    if not ok or type(data) ~= "table" or type(data.data) ~= "table" then notes.hop = "server list unavailable"; return end
    for _, server in ipairs(data.data) do
        if type(server) == "table" and type(server.id) == "string"
            and type(server.playing) == "number" and server.playing < CFG.HopMaxPlayers
            and server.id ~= game.JobId then
            notes.hop = "hopping to a " .. server.playing .. "-player server"
            pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer) end)
            return
        end
    end
    notes.hop = "no low-player server found"
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

local antiAfkConnection
local antiAfkLast, antiAfkCount = -math.huge, 0
local function syncAntiAfk()
    if not alive or not enabled.antiAfk then
        if antiAfkConnection then antiAfkConnection:Disconnect(); antiAfkConnection = nil end
        notes.antiAfk = "off"
        return
    end
    if antiAfkConnection then return end
    notes.antiAfk = "armed; waiting for idle event"
    antiAfkConnection = LocalPlayer.Idled:Connect(function()
        if not alive or not enabled.antiAfk or os.clock() - antiAfkLast < CFG.AntiAfkCooldown then return end
        local camera = workspace.CurrentCamera
        if not camera then notes.antiAfk = "waiting for camera"; return end
        antiAfkLast = os.clock()
        local ok, err = pcall(function()
            local virtualUser = game:GetService("VirtualUser")
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0), camera.CFrame)
        end)
        if not ok then
            setEnabled("antiAfk", false)
            notes.antiAfk = "input unavailable: " .. tostring(err)
            stage("Anti-AFK disabled: " .. tostring(err))
            return
        end
        antiAfkCount += 1
        notes.antiAfk = ("idle pulse sent (%d)"):format(antiAfkCount)
    end)
end

syncWorkers = function()
    if not alive then return end
    syncAntiAfk()
    local profileWanted = enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele or enabled.autoBuyPetSlots or enabled.worldAdvance
    local discoveryWanted = profileWanted or enabled.petSpeed or enabled.farm or enabled.vacuum
    ensureWorker("profile", profileWanted, CFG.ProfileInterval, profileTick)
    ensureWorker("discovery", discoveryWanted, CFG.DiscoveryInterval, discoveryTick)
    if not discoveryWanted then heapObjects, heapCursor, treeScan = nil, nil, nil end
    local petWanted = enabled.petSpeed or enabled.farm
    if not petWanted and petState.hook then restorePetSpeed() end
    ensureWorker("pet", petWanted, CFG.PetInterval, petTick, function() enabled.petSpeed = false; enabled.farm = false; restorePetSpeed() end)
    local tapRate = enabled.clickAura and CFG.AuraRate or (enabled.farm and CFG.FarmTapRate or CFG.TapRate)
    ensureWorker("tap", enabled.tap or enabled.farm or enabled.clickAura, 1 / math.min(tapRate, CFG.MaxTapRate), tapTick, function() enabled.tap = false; enabled.farm = false; enabled.clickAura = false end)
    if (enabled.vacuum or enabled.farm) and not orbState.hook then
        if not orbBackfillNeeded then nextAt.heap = math.min(nextAt.heap, os.clock() + CFG.HeapRetryInterval) end
        orbBackfillNeeded = true
    end
    ensureWorker("vacuum", enabled.vacuum or enabled.farm, CFG.VacuumRate, vacuumTick, function() enabled.vacuum = false; enabled.farm = false end)
    ensureWorker("tele", enabled.zoneTele, 0.5, teleTick, function() enabled.zoneTele = false end)
    ensureWorker("buy", enabled.zoneBuy, 0.5, buyTick, function() enabled.zoneBuy = false end)
    ensureWorker("quest", enabled.autoQuest, CFG.QuestInterval, questTick, function() enabled.autoQuest = false end)
    ensureWorker("rank", enabled.autoRank, 1, rankTick, function() enabled.autoRank = false end)
    ensureWorker("rebirth", enabled.autoRebirth, 1, rebirthTick, function() enabled.autoRebirth = false end)
    ensureWorker("egg", enabled.autoEgg, 0.5, eggTick, function() enabled.autoEgg = false end)
    ensureWorker("world", enabled.worldTele, 0.5, worldTeleTick, function() enabled.worldTele = false end)
    ensureWorker("advance", enabled.worldAdvance, 1, CFG.AdvanceTick, function() enabled.worldAdvance = false end)
    ensureWorker("petSlot", enabled.autoBuyPetSlots, 1, petSlotTick, function() enabled.autoBuyPetSlots = false end)
    ensureWorker("keys", enabled.autoKeys, 1, keyTick, function() enabled.autoKeys = false end)
    ensureWorker("bags", enabled.autoGiftBags, 1, bagTick, function() enabled.autoGiftBags = false end)
    ensureWorker("fruits", enabled.autoFruits, 1, fruitTick, function() enabled.autoFruits = false end)
    ensureWorker("potions", enabled.autoPotions, 1, potionTick, function() enabled.autoPotions = false end)
    ensureWorker("freeGift", enabled.autoFreeGifts, 1, freeGiftTick, function() enabled.autoFreeGifts = false end)
    ensureWorker("ultimate", enabled.autoUltimate, 1, ultimateTick, function() enabled.autoUltimate = false end)
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
    if not enabled.optBreakables then restoreEffects(optBreakableEffects) end
    if not enabled.optPets then restoreEffects(optPetEffects) end
    if enabled.optBreakables or enabled.optPets then
        ensureWorker("optimize", true, CFG.OptimizeInterval, optimizeTick, function() enabled.optBreakables = false; enabled.optPets = false end)
    else
        stopWorker("optimize")
        notes.optimize = "off"
    end
    if enabled.auraVisual then ensureAuraPart() else destroyAuraPart() end
    if not enabled.tap and not enabled.farm and not enabled.clickAura then
        target.model, target.uid, target.at, targetScan = nil, nil, nil, nil
        auraTargets, auraCursor = {}, 0
        petState.routeTarget, petState.routeAt = nil, nil
        notes.tap = "off"
    end
    if not enabled.vacuum and not enabled.farm then restoreOrbCapture(); notes.vacuum = "off" end
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
        world = worldTarget,
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
    unpublish()
    print("[PS99 CLEAN] unloaded")
end

local controller = {
    SetEnabled = setEnabled,
    ClaimRankRewards = claimRankRewards,
    AllOff = allOff,
    Stop = cleanup,
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
    -- v2: numeric knobs the UI drives. Anything not in CFG is rejected, so a
    -- typo in the interface cannot inject a new field into the engine.
    SetConfig = function(key, value)
        if CFG[key] == nil or type(CFG[key]) ~= "number" then return false, "unknown knob" end
        local number = tonumber(value)
        if not number then return false, "not a number" end
        CFG[key] = number
        return true, number
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
-- Headless: no ScreenGui, no Insert bind, no drawn stage. The interface lives
-- in main.lua; this module publishes the controller and nothing else on screen.
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
publish()
if not alive then return controller end
connect(LocalPlayer.CharacterAdded, function()
    target.model, target.uid, target.at = nil, nil, nil
    petState.routeTarget, petState.routeAt = nil, nil
end)
ensureWorker("status", true, 1, updateStatus)
stage("Ready; headless; no startup scans")
return controller
