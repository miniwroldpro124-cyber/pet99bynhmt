local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "PS99 CLEAN must run on the client")

local env = type(getgenv) == "function" and getgenv() or _G
if type(env.__PS99CLEAN_CLEANUP) == "function" then
    local ok, err = pcall(env.__PS99CLEAN_CLEANUP)
    if not ok then warn("[PS99 CLEAN] previous cleanup: " .. tostring(err)) end
end

local CFG = {
    -- Effectively infinite: the pet render clamps lerp alpha to [n1,1], so this
    -- saturates to an instant snap. Finite (not math.huge) avoids 0*inf=NaN when
    -- a frame's delta time is zero, which would permanently corrupt the pet CFrame.
    PetSpeedMult = 1e9,
    PetInterval = 0.25,
    TapRate = 18,
    FarmTapRate = 30,
    TapRange = 150,
    MaxTapRate = 16,
    AuraRate = 16,
    AntiAfkCooldown = 60,
    TargetRescan = 0.35,
    BreakableScanCap = 1500,
    VacuumRadius = 180,
    VacuumRate = 0.2,
    VacuumMaxIds = 80,
    VacuumRetry = 2,
    TeleInterval = 4,
    TeleBackoff = 15,
    BuyInterval = 4,
    BuyBackoff = 12,
    QuestInterval = 2,
    QuestBackoff = 25,
    EnsureBackoff = 45,
    QuestMaxRequests = 2,
    RankInterval = 4,
    RebirthInterval = 20,
    EggInterval = 2.6,
    EggRange = 250,
    EggMaxHatch = 50,
    WorldInterval = 4,
    WorldBackoff = 12,
    WorldCount = 6,
    OptimizeInterval = 2,
    OptimizeCap = 400,
    HopMaxPlayers = 4,
    HopInterval = 30,
    PetSlotInterval = 6,
    PetSlotBackoff = 12,
    PetSlotMax = 80,
    ProfileInterval = 2,
    SaveRefresh = 30,
    SnapshotTTL = 60,
    RemoteTimeout = 10,
    DiscoveryInterval = 1,
    TreeInterval = 60,
    HeapInterval = 120,
    HeapRetryInterval = 5,
    HeapCap = 2000,
    TreeCap = 1000,
}

local enabled = {
    petSpeed = false, tap = false, vacuum = false, farm = false,
    zoneTele = false, zoneBuy = false, autoQuest = false,
    autoRank = false, autoRebirth = false, antiAfk = false, clickAura = false,
    autoEgg = false, auraVisual = false, optBreakables = false, optPets = false, worldTele = false,
    serverHop = false, autoBuyPetSlots = false, jitter = false,
}
local alive = true
local workers, requests, connections = {}, {}, {}
local remotes, modules = {}, {}
local zones, zoneNumbers, rebirths, ranks, questDirs, eggByNumber = {}, {}, {}, {}, {}, {}
local worldTarget = 1
local snapshot, snapshotAt, saveSource = nil, -math.huge, "waiting"
local saveCache = nil
local pendingStats, statsRemote, statsConnection = nil, nil, nil
local heapNext, saveNext = 0, 0
local screenGui, stageLabel, footerLabel
local infoLabels, toggleButtons = {}, {}
local notes = {pet = "off", tap = "off", vacuum = "off", tele = "off", buy = "off", quest = "off", rank = "off", rebirth = "off", antiAfk = "off", egg = "off", world = "off", optimize = "off", hop = "off", petSlot = "off", heap = "idle; no startup scan"}
local petHook, petOriginal, petModule
local petPrevious = setmetatable({}, {__mode = "k"})
local targetModel, targetUid, targetAt
local orbSentAt = {}
local orbRecords = setmetatable({}, {__mode = "kv"})
local orbOffsets = setmetatable({}, {__mode = "k"})
local orbModule, orbOriginal, orbHook
local orbCursor = 1
local questNext, ensureNext, assignedQuests = {}, {}, {}
local eggNext, worldTeleNext = 0, 0
local petSlotNext = 0
local auraPart
local optBreakableEffects = setmetatable({}, {__mode = "k"})
local optPetEffects = setmetatable({}, {__mode = "k"})
local syncWorkers, setEnabled, cleanup, updateToggles, updateWorldButtons

local REMOTE_TYPES = {
    ["Get Stats"] = "RemoteFunction",
    ["New Stats"] = "RemoteEvent",
    ["Breakables_PlayerDealDamage"] = "UnreliableRemoteEvent",
    ["Orbs: Collect"] = "RemoteEvent",
    ["Teleports_RequestTeleport"] = "RemoteFunction",
    ["Zones_RequestPurchase"] = "RemoteFunction",
    ["NPC Quests: Ensure"] = "RemoteFunction",
    ["NPC Quests: Redeem"] = "RemoteFunction",
    ["Ranks_ClaimAll"] = "RemoteEvent",
    ["Rebirth_Request"] = "RemoteFunction",
    ["Eggs_RequestPurchase"] = "RemoteFunction",
    ["EquipSlotsMachine_RequestPurchase"] = "RemoteFunction",
}

local function stage(message)
    if not alive then return end
    print("[PS99 CLEAN] " .. tostring(message))
    if stageLabel then stageLabel.Text = tostring(message) end
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
    if saveCache then
        local ok, value = pcall(function() return rawget(saveCache, LocalPlayer) end)
        if ok and looksLikeSave(value) then
            saveSource = "live"
            return value
        end
        if saveSource == "live" then snapshot = nil end
    end
    if modules.save then
        local ok, value = pcall(modules.save.Get, LocalPlayer)
        if ok and looksLikeSave(value) then
            saveSource = "live"
            return value
        end
        if saveSource == "live" then snapshot = nil end
    end
    if snapshot and os.clock() - snapshotAt <= CFG.SnapshotTTL then
        saveSource = "snapshot"
        return snapshot
    end
    saveSource = "waiting"
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
    if signal == statsRemote then return end
    if statsConnection then statsConnection:Disconnect() end
    statsConnection, statsRemote = nil, signal
    if not signal then return end
    statsConnection = signal:Connect(function(changes, who)
        if not alive or (who ~= nil and who ~= LocalPlayer) or type(changes) ~= "table" then return end
        for _, pair in ipairs(changes) do
            if type(pair) == "table" and type(pair[1]) == "string" then
                if snapshot then snapshot[pair[1]] = pair[2] end
                if pendingStats then pendingStats[pair[1]] = {pair[1], pair[2]} end
            end
        end
    end)
end

local function profileTick()
    bindStats()
    if getSave() and saveSource == "live" then return end
    local now = os.clock()
    if now < saveNext or requests["Get Stats"] then return end
    local network = modules.network
    local remote = getRemote("Get Stats")
    if not network and not remote then
        -- No profile source yet; discovery may still find one, so retry soon
        -- instead of locking out for the full refresh interval.
        saveNext = now + CFG.ProfileInterval
        return
    end
    saveNext = now + CFG.SaveRefresh
    local changes = {}
    pendingStats = changes
    local function adopt(ok, value)
        if pendingStats == changes then pendingStats = nil end
        if ok and looksLikeSave(value) then
            snapshot = table.clone(value)
            for _, pair in pairs(changes) do snapshot[pair[1]] = pair[2] end
            snapshotAt = os.clock()
        elseif not snapshot then
            stage("profile: " .. tostring(ok and "unexpected profile shape" or value))
        end
    end
    local _, err = invokeWithCompletion("Get Stats", function(result) adopt(result[1], result[2]) end, LocalPlayer)
    if not alive then return end
    if not requests["Get Stats"] and pendingStats == changes then pendingStats = nil end
    if err and not snapshot then stage("profile: " .. tostring(err)) end
end

local function registerZone(number, id, definition)
    if type(number) ~= "number" or type(id) ~= "string" or number < 1 then return end
    local existing = zones[number]
    if existing and existing.id ~= id then return end
    zones[number] = {id = id, definition = definition or (existing and existing.definition)}
    zoneNumbers[id] = number
end

local heapObjects, heapCursor
local heapStarted = -math.huge
local orbBackfillNeeded, heapBackfillsOrbs = false, false
local function releaseHeap()
    if heapObjects then heapNext = math.min(heapNext, heapStarted + CFG.HeapRetryInterval) end
    heapObjects, heapCursor, heapBackfillsOrbs = nil, nil, false
end

local function scanHeap()
    if not heapObjects then
        if os.clock() < heapNext then return end
        heapStarted = os.clock()
        heapNext = heapStarted + CFG.HeapInterval
        local gc = getgc or env.getgc
        if type(gc) ~= "function" then notes.heap = "getgc unavailable"; orbBackfillNeeded = false; return end
        -- The boolean requests tables; getgc(false) commonly returns functions only.
        local ok, objects = pcall(gc, true)
        if not ok or type(objects) ~= "table" then notes.heap = "table scan unavailable"; orbBackfillNeeded = false; return end
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
            notes.heap = "scanned"
            return
        end
        if type(object) == "table" then
            if type(rawget(object, "Get")) == "function"
                and type(rawget(object, "GetSaves")) == "function"
                and (type(rawget(object, "GetStatChangedSignal")) == "function"
                    or type(rawget(object, "ProcessManualChange")) == "function"
                    or type(rawget(object, "FetchPlayer")) == "function"
                    or rawget(object, "LoadedStats") ~= nil
                    or rawget(object, "StatsChanged") ~= nil) then
                modules.save = object
            end
            if type(rawget(object, "Invoke")) == "function" and type(rawget(object, "Fired")) == "function"
                and type(rawget(object, "Fire")) == "function" and type(rawget(object, "Invoked")) == "function" then
                modules.network = object
            end
            -- The Save module's live cache is a table keyed by Player -> save. Reading
            -- it directly needs no function signature and is always current.
            if looksLikeSave(rawget(object, LocalPlayer)) then saveCache = object end
            if type(rawget(object, "CalculateSpeedMultiplier")) == "function"
                and type(rawget(object, "GetByPlayer")) == "function"
                and type(rawget(object, "GetByItemUID")) == "function" then
                modules.pet = object
            end
            if type(rawget(object, "new")) == "function" and type(rawget(object, "Combine")) == "function"
                and type(rawget(object, "Collect")) == "function" and type(rawget(object, "ParkSpent")) == "function" then
                modules.orb = object
            end
            local part = rawget(object, "_part")
            if typeof(part) == "Instance" and type(rawget(object, "_combinedIds")) == "table"
                and type(rawget(object, "_destroyed")) == "boolean" then orbRecords[part] = object end
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
        scan[key] = nil
        if count % 500 == 0 then task.wait() end
    end
    if heapObjects == scan then notes.heap = "scan continuing" end
end

local treeScan, treeNext = nil, 0
local function scanTree()
    if not treeScan and os.clock() < treeNext then return end
    treeScan = treeScan or {queue = {RS}, cursor = 1, childIndex = 1, candidates = {}, priorities = {}, ambiguous = {}}
    local scan = treeScan
    local visited = 0
    while scan.cursor <= #scan.queue and visited < CFG.TreeCap and alive do
        local parent = scan.queue[scan.cursor]
        scan.children = scan.children or parent:GetChildren()
        local child = scan.children[scan.childIndex]
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
        treeNext = os.clock() + CFG.TreeInterval
        bindStats()
    end
end

local function needsNative()
    if (enabled.petSpeed or enabled.farm) and not modules.pet then return true end
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
    if (enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele or enabled.autoBuyPetSlots) and not save then return true end
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
    local hit = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -200, 0), rayParams)
    if not hit then return nil end
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
    if petModule and petModule.CalculateSpeedMultiplier == petHook then
        local ok, err = pcall(function() petModule.CalculateSpeedMultiplier = petOriginal end)
        if not ok then warn("[PS99 CLEAN] pet restore: " .. tostring(err)) end
    end
    for pet, previous in pairs(petPrevious) do
        if not pet.destroyed and pet.speedMult == CFG.PetSpeedMult then
            local ok, err = pcall(function()
                pet.speedMult = previous
                if pet.cpet then pet.cpet:Broadcast("petSpeedMult", previous) end
            end)
            if not ok then warn("[PS99 CLEAN] pet reset: " .. tostring(err)) end
        end
    end
    table.clear(petPrevious)
    petModule, petOriginal, petHook = nil, nil, nil
    notes.pet = "off"
end

local function petTick()
    local mod = modules.pet
    if not mod then notes.pet = "waiting for PlayerPet; " .. notes.heap; return end
    if petModule and (mod ~= petModule or petModule.CalculateSpeedMultiplier ~= petHook) then
        restorePetSpeed()
        enabled.petSpeed, enabled.farm = false, false
        syncWorkers()
        updateToggles()
        stage("Pet speed disabled: another script changed the pet module")
        return
    end
    if not petHook then
        local original = mod.CalculateSpeedMultiplier
        local hook = function(pet, ...)
            -- Only the game's own caller computes the native multiplier.
            local result = original(pet, ...)
            if alive and (enabled.petSpeed or enabled.farm) and pet.owner == LocalPlayer then
                petPrevious[pet] = result
                return CFG.PetSpeedMult
            end
            return result
        end
        local ok, err = pcall(function() mod.CalculateSpeedMultiplier = hook end)
        if not ok then error("pet module is read-only: " .. tostring(err)) end
        petModule, petOriginal, petHook = mod, original, hook
    end
    local count = 0
    for _, pet in pairs(mod.GetByPlayer(LocalPlayer)) do
        if pet.owner == LocalPlayer and not pet.destroyed and type(pet.speedMult) == "number" then
            if petPrevious[pet] == nil then petPrevious[pet] = pet.speedMult end
            pet.speedMult = CFG.PetSpeedMult
            if pet.cpet then pet.cpet:Broadcast("petSpeedMult", CFG.PetSpeedMult) end
            count += 1
        end
    end
    notes.pet = ("Inf | %d local pets"):format(count)
end

local function validTarget(model, point, zone)
    if not model or not model:IsDescendantOf(workspace) then return false end
    if model:GetAttribute("ManualDamage") or model:GetAttribute("DisableDamage") then return false end
    if model:GetAttribute("BreakableUID") == nil then return false end
    local owner = model:GetAttribute("OwnerUsername")
    if owner and owner ~= LocalPlayer.Name then return false end
    if model:GetAttribute("ParentType") == 1 and model:GetAttribute("ParentID") ~= zone then return false end
    local at = modelPosition(model)
    return at ~= nil and (at - point).Magnitude <= CFG.TapRange
end

local targetScan
local auraTargets, auraCursor = {}, 0
local nextTapAt = 0
local function pickTarget(point, zone)
    local root = thingsFolder("Breakables")
    if not root then targetScan = nil; return nil, nil end
    if not targetScan or targetScan.root ~= root or targetScan.zone ~= zone then
        targetScan = {root = root, zone = zone, queue = {root}, cursor = 1, childIndex = 1, targets = {}}
    end
    local scan, visited = targetScan, 0
    while scan.cursor <= #scan.queue and visited < CFG.BreakableScanCap do
        local parent = scan.queue[scan.cursor]
        scan.children = scan.children or parent:GetChildren()
        local child = scan.children[scan.childIndex]
        visited += 1
        if not child then
            scan.cursor += 1
            scan.children, scan.childIndex = nil, 1
        else
            scan.childIndex += 1
            local uid = child:GetAttribute("BreakableUID")
            if uid ~= nil then
                if validTarget(child, point, zone) then
                    scan.targets[#scan.targets + 1] = child
                    local length = (modelPosition(child) - point).Magnitude
                    local oldDistance = validTarget(scan.best, point, zone) and (modelPosition(scan.best) - point).Magnitude or math.huge
                    if length <= oldDistance then scan.best, scan.uid = child, uid end
                end
            elseif child:IsA("Folder") or child:IsA("Model") then scan.queue[#scan.queue + 1] = child end
        end
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
    if now < nextTapAt then return end
    local point = position()
    if not point then notes.tap = "waiting for character"; return end
    local zone = currentZone()
    if not validTarget(targetModel, point, zone) or now - (targetAt or 0) >= CFG.TargetRescan then
        targetModel, targetUid = pickTarget(point, zone)
        targetAt = now
    end
    if enabled.clickAura then
        targetModel, targetUid = nil, nil
        for _ = 1, #auraTargets do
            auraCursor = auraCursor % #auraTargets + 1
            local candidate = auraTargets[auraCursor]
            if validTarget(candidate, point, zone) then
                targetModel, targetUid = candidate, candidate:GetAttribute("BreakableUID")
                break
            end
        end
    end
    if not targetUid then notes.tap = "no eligible breakable in range"; return end
    local interval = 1 / CFG.MaxTapRate
    if enabled.jitter then
        interval = interval * (1 + math.random() * 0.8)
        if math.random() < 0.02 then interval = interval + 0.3 + math.random() * 0.5 end
    end
    nextTapAt = now + interval
    local ok, message = fire("Breakables_PlayerDealDamage", targetUid)
    notes.tap = ok and (enabled.clickAura and "aura: " or "tapping ") .. tostring(targetUid) or message
end

local function restoreOrbCapture()
    if orbModule and orbModule.new == orbHook then
        local ok, err = pcall(function() orbModule.new = orbOriginal end)
        if not ok then warn("[PS99 CLEAN] orb restore: " .. tostring(err)) end
    end
    orbModule, orbOriginal, orbHook = nil, nil, nil
end

local function vacuumTick()
    if not orbHook and modules.orb then
        local mod, original = modules.orb, modules.orb.new
        local hook = function(...)
            local orb = original(...)
            if alive and type(orb) == "table" and orb._part then orbRecords[orb._part] = orb end
            return orb
        end
        local ok = pcall(function() mod.new = hook end)
        if ok then orbModule, orbOriginal, orbHook = mod, original, hook end
    end
    local root, point = thingsFolder("Orbs"), position()
    if not root or not point then notes.vacuum = "waiting for orbs/character"; return end
    local ids, seen, now = {}, {}, os.clock()
    for id, sentAt in pairs(orbSentAt) do if now - sentAt >= CFG.VacuumRetry then orbSentAt[id] = nil end end
    local function append(id)
        if #ids < CFG.VacuumMaxIds and (type(id) == "number" or type(id) == "string") and not orbSentAt[id] and not seen[id] then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    local children = root:GetChildren()
    for _ = 1, math.min(#children, CFG.BreakableScanCap) do
        if #ids >= CFG.VacuumMaxIds then break end
        if orbCursor > #children then orbCursor = 1 end
        local child = children[orbCursor]
        orbCursor += 1
        local at, record = modelPosition(child), orbRecords[child]
        if at and (at - point).Magnitude <= CFG.VacuumRadius then
            if record and not record._destroyed then
                append(record._id)
                local combined = record._combinedIds
                local offset = orbOffsets[record] or 1
                for _ = 1, math.min(#combined, CFG.VacuumMaxIds) do
                    if #ids >= CFG.VacuumMaxIds then break end
                    if offset > #combined then offset = 1 end
                    append(combined[offset])
                    offset += 1
                end
                orbOffsets[record] = offset
            elseif not record then append(tonumber(child.Name)) end
        end
    end
    if #ids == 0 then notes.vacuum = "no nearby unrequested orbs"; return end
    local ok, message = fire("Orbs: Collect", ids)
    if ok then for _, id in ipairs(ids) do orbSentAt[id] = now end end
    notes.vacuum = ok and ("requested %d orb IDs"):format(#ids) or message
end

local teleNext, buyNext, rankNext, rebirthNext = 0, 0, 0, 0
local function teleTick()
    local now = os.clock()
    if now < teleNext then return end
    local save = getSave()
    if not save then notes.tele = "waiting for profile"; return end
    local best = maxOwned(save)
    if not best then notes.tele = "waiting for zone map"; return end
    local id = zones[best].id
    if currentZone() == id then notes.tele = "already in " .. id; return end
    teleNext = now + CFG.TeleBackoff
    local ok, message = invoke("Teleports_RequestTeleport", id)
    if not alive or not enabled.zoneTele then return end
    notes.tele = ok == true and "accepted: " .. id or tostring(message or "rejected")
    if ok == true then teleNext = os.clock() + CFG.TeleInterval end
end

local function buyTick()
    local now = os.clock()
    if now < buyNext then return end
    local save = getSave()
    if not save then notes.buy = "waiting for profile"; return end
    local best = maxOwned(save)
    local nextZone = best and zones[best + 1]
    if not nextZone then notes.buy = "next zone unavailable"; return end
    buyNext = now + CFG.BuyBackoff
    local ok, message = invoke("Zones_RequestPurchase", nextZone.id)
    if not alive or not enabled.zoneBuy then return end
    notes.buy = ok == true and "accepted: " .. nextZone.id or tostring(message or "rejected")
    if ok == true then buyNext = os.clock() + CFG.BuyInterval; saveNext = 0 end
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
                if now >= (ensureNext[id] or 0) then
                    ensureNext[id] = now + CFG.EnsureBackoff
                    sent += 1
                    local ok, message = invokeWithCompletion("NPC Quests: Ensure", function(result)
                        if result[1] and result[2] == true and type(result[3]) == "table" then
                            assignedQuests[id] = {save = save, goals = result[3], reward = result[4]}
                        end
                    end, id)
                    if not alive or not enabled.autoQuest then return end
                    notes.quest = ok == true and "assignment received: " .. id or tostring(message or "assignment rejected")
                    saveNext = 0
                end
            elseif now >= (questNext[id] or 0) then
                local index = claimTarget(definition, goals)
                if index ~= nil then
                    questNext[id] = now + CFG.QuestBackoff
                    sent += 1
                    local ok, message
                    if index == 0 then ok, message = invoke("NPC Quests: Redeem", id)
                    else ok, message = invoke("NPC Quests: Redeem", id, index) end
                    if not alive or not enabled.autoQuest then return end
                    notes.quest = ok == true and "claimed: " .. id or tostring(message or "claim rejected")
                    if ok == true then saveNext = 0 end
                end
            end
        end
    end
end

local function claimRankRewards()
    if not alive then return false, "stopped" end
    if os.clock() < rankNext then return false, "rank claim cooldown" end
    rankNext = os.clock() + CFG.RankInterval
    local ok, message = fire("Ranks_ClaimAll")
    notes.rank = ok and "claim request sent" or message
    return ok, message
end

local function rankTick()
    if os.clock() < rankNext then return end
    local save = getSave()
    if not save then claimRankRewards(); return end
    local definition = ranks[save.Rank]
    if not definition then claimRankRewards(); return end
    local redeemed = save.RedeemedRankRewards
    if type(redeemed) ~= "table" then notes.rank = "waiting for reward state"; return end
    local total, claimable = 0, false
    for index, reward in ipairs(definition.Rewards) do
        if type(reward.StarsRequired) ~= "number" then notes.rank = "invalid reward definition"; return end
        total += reward.StarsRequired
        if (save.RankStars or 0) >= total and not redeemed[tostring(index)] then claimable = true; break end
    end
    if not claimable then notes.rank = "no earned rewards to claim"; return end
    claimRankRewards()
end

local function rebirthTick()
    local now = os.clock()
    if now < rebirthNext then return end
    local save = getSave()
    if not save then notes.rebirth = "waiting for profile"; return end
    local definition = rebirths[save.Rebirths + 1]
    if not definition then notes.rebirth = "next rebirth unavailable"; return end
    local best = maxOwned(save)
    if not best or best < definition.ZoneNumberRequired then
        notes.rebirth = "requires zone " .. tostring(definition.ZoneNumberRequired)
        return
    end
    rebirthNext = now + CFG.RebirthInterval
    local id = tostring(definition.RebirthNumber)
    local ok, message = invoke("Rebirth_Request", id)
    if not alive or not enabled.autoRebirth then return end
    notes.rebirth = ok == true and "accepted: " .. id or tostring(message or "rejected")
    if ok == true then saveNext = 0 end
end

local function closestEgg(point)
    local best, bestNumber, bestDistance
    for _, folderName in ipairs({"ZoneEggs", "Eggs"}) do
        local root = thingsFolder(folderName)
        if root then
            local queue, cursor, visited = {root}, 1, 0
            while cursor <= #queue and visited < CFG.BreakableScanCap do
                local parent = queue[cursor]
                local children = parent:GetChildren()
                cursor += 1
                visited += 1
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
        end
    end
    return best, bestNumber
end

local function eggTick()
    local now = os.clock()
    if now < eggNext then return end
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
    eggNext = now + CFG.EggInterval
    local ok, message = invoke("Eggs_RequestPurchase", eggId, count)
    if not alive or not enabled.autoEgg then return end
    notes.egg = ok == true and ("opened %s x%d"):format(eggId, count) or tostring(message or "rejected")
end

local function worldTeleTick()
    local now = os.clock()
    if now < worldTeleNext then return end
    local save = getSave()
    if not save then notes.world = "waiting for profile"; return end
    local number = bestInWorld(save, worldTarget)
    if not number then notes.world = "world " .. worldTarget .. " zone map unavailable"; return end
    local id = zones[number].id
    if currentZone() == id then notes.world = "already in world " .. worldTarget .. " (" .. id .. ")"; return end
    worldTeleNext = now + CFG.WorldBackoff
    local ok, message = invoke("Teleports_RequestTeleport", id)
    if not alive or not enabled.worldTele then return end
    notes.world = ok == true and ("world %d -> %s"):format(worldTarget, id) or tostring(message or "rejected")
    if ok == true then worldTeleNext = os.clock() + CFG.WorldInterval end
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
        local children = parent:GetChildren()
        cursor += 1
        visited += 1
        for _, child in ipairs(children) do
            visited += 1
            if EFFECT_CLASSES[child.ClassName] then
                if store[child] == nil then
                    store[child] = child.Enabled
                    local ok = pcall(function() child.Enabled = false end)
                    if ok then changed += 1 end
                end
            elseif child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart") then
                queue[#queue + 1] = child
            end
        end
    end
    return changed
end

local function restoreEffects(store)
    for effect, original in pairs(store) do
        pcall(function() effect.Enabled = original end)
    end
    table.clear(store)
end

local function optimizeTick()
    local changed = 0
    if enabled.optBreakables then changed += suppressEffects("Breakables", optBreakableEffects) end
    if enabled.optPets then changed += suppressEffects("Pets", optPetEffects) end
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
    if enabled.worldTele then worldTeleNext = 0 end
    if updateWorldButtons then updateWorldButtons() end
    return true
end

local function petSlotTick()
    local now = os.clock()
    if now < petSlotNext then return end
    local save = getSave()
    if not save then notes.petSlot = "waiting for profile"; return end
    local purchased = type(save.PetSlotsPurchased) == "number" and save.PetSlotsPurchased or 0
    local slot = purchased + 1
    if slot > CFG.PetSlotMax then notes.petSlot = "slot cap reached (" .. CFG.PetSlotMax .. ")"; return end
    petSlotNext = now + CFG.PetSlotBackoff
    local ok, message = invoke("EquipSlotsMachine_RequestPurchase", slot)
    if not alive or not enabled.autoBuyPetSlots then return end
    notes.petSlot = ok == true and ("bought slot " .. slot) or tostring(message or "rejected")
    if ok == true then petSlotNext = os.clock() + CFG.PetSlotInterval; saveNext = 0 end
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
    if name == "profile" and pendingStats then table.clear(pendingStats); pendingStats = nil end
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
            local ok, err = pcall(tick)
            if not alive or not worker.running or workers[name] ~= worker then return end
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
    local profileWanted = enabled.zoneTele or enabled.zoneBuy or enabled.autoQuest or enabled.autoRank or enabled.autoRebirth or enabled.autoEgg or enabled.worldTele or enabled.autoBuyPetSlots
    local discoveryWanted = profileWanted or enabled.petSpeed or enabled.farm or enabled.vacuum
    ensureWorker("profile", profileWanted, CFG.ProfileInterval, profileTick)
    ensureWorker("discovery", discoveryWanted, CFG.DiscoveryInterval, discoveryTick)
    if not discoveryWanted then heapObjects, heapCursor, treeScan = nil, nil, nil end
    local petWanted = enabled.petSpeed or enabled.farm
    if not petWanted and petHook then restorePetSpeed() end
    ensureWorker("pet", petWanted, CFG.PetInterval, petTick, function() enabled.petSpeed = false; enabled.farm = false; restorePetSpeed() end)
    local tapRate = enabled.clickAura and CFG.AuraRate or (enabled.farm and CFG.FarmTapRate or CFG.TapRate)
    ensureWorker("tap", enabled.tap or enabled.farm or enabled.clickAura, 1 / math.min(tapRate, CFG.MaxTapRate), tapTick, function() enabled.tap = false; enabled.farm = false; enabled.clickAura = false end)
    if (enabled.vacuum or enabled.farm) and not orbHook then
        if not orbBackfillNeeded then heapNext = math.min(heapNext, os.clock() + CFG.HeapRetryInterval) end
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
    ensureWorker("petSlot", enabled.autoBuyPetSlots, 1, petSlotTick, function() enabled.autoBuyPetSlots = false end)
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
        targetModel, targetUid, targetAt, targetScan = nil, nil, nil, nil
        auraTargets, auraCursor = {}, 0
        notes.tap = "off"
    end
    if not enabled.vacuum and not enabled.farm then restoreOrbCapture(); notes.vacuum = "off" end
end

updateToggles = function()
    for key, button in pairs(toggleButtons) do
        button.Text = enabled[key] and "ON" or "OFF"
        button.BackgroundColor3 = enabled[key] and Color3.fromRGB(34, 153, 98) or Color3.fromRGB(65, 70, 82)
    end
end

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
    local save = getSave()
    local best = maxOwned(save)
    local count = 0
    for _ in pairs(zones) do count += 1 end
    if auraPart then
        local point = position()
        if point then pcall(function() auraPart.Position = point end) end
    end
    if infoLabels.farm then
        infoLabels.farm.Text = "Speed: " .. notes.pet .. "\nTap/Aura: " .. notes.tap .. "\nOrbs: " .. notes.vacuum .. "\nEgg: " .. notes.egg .. "\nFast Farm = speed + tap + orbs. Aura cycles nearby targets; shared 16/s cap."
        infoLabels.tools.Text = "Anti-AFK: " .. notes.antiAfk .. "\nOptimize: " .. notes.optimize .. "\nServer hop: " .. notes.hop .. "\nJitter: " .. (enabled.jitter and "on (randomized tap timing)" or "off") .. "\nOptimize restores effects on OFF."
        infoLabels.zone.Text = "Here: " .. tostring(currentZone() or "unknown") .. "\nBest: " .. tostring(best and zones[best].id or "unknown") .. "\nBuy: " .. notes.buy .. "\nPet slots: " .. notes.petSlot .. "\nTeleport: " .. notes.tele .. "\nWorld " .. worldTarget .. ": " .. notes.world
        infoLabels.quest.Text = notes.quest .. "\nClaims finished NPC goals; does not solve every quest type."
        infoLabels.rank.Text = ("Rank: %s | Stars: %s | Rebirths: %s\nRank: %s\nRebirth: %s"):format(
            tostring(save and save.Rank or "?"), tostring(save and save.RankStars or "?"),
            tostring(save and save.Rebirths or "?"), notes.rank, notes.rebirth)
    end
    if footerLabel then footerLabel.Text = ("Profile: %s | Zones: %d | %s"):format(saveSource, count, notes.heap) end
end

local function create(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties) do instance[key] = value end
    instance.Parent = parent
    return instance
end

local function buildGUI()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    if not alive then return end
    assert(playerGui, "PlayerGui did not load")
    screenGui = create("ScreenGui", {Name = "PS99CLEAN", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, playerGui)
    local main = create("Frame", {Name = "Main", Size = UDim2.fromOffset(390, 420), Position = UDim2.fromOffset(40, 90), BackgroundColor3 = Color3.fromRGB(24, 27, 35), BorderSizePixel = 0}, screenGui)
    create("UICorner", {CornerRadius = UDim.new(0, 8)}, main)
    local title = create("Frame", {Name = "Title", Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.fromRGB(17, 20, 27), BorderSizePixel = 0, Active = true}, main)
    create("TextLabel", {Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = "PS99 CLEAN v13", TextColor3 = Color3.fromRGB(125, 212, 236), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextSize = 17}, title)
    local function titleButton(text, offset, width, color, callback)
        local button = create("TextButton", {Size = UDim2.fromOffset(width, 26), Position = UDim2.new(1, offset, 0, 6), BackgroundColor3 = color, BorderSizePixel = 0, Text = text, TextColor3 = Color3.fromRGB(245, 245, 245), Font = Enum.Font.GothamBold, TextSize = 13}, title)
        connect(button.Activated, callback)
    end
    titleButton("OFF", -116, 44, Color3.fromRGB(121, 83, 40), allOff)
    titleButton("_", -67, 26, Color3.fromRGB(55, 66, 81), function() screenGui.Enabled = false end)
    titleButton("X", -36, 26, Color3.fromRGB(156, 60, 67), function() cleanup() end)
    local tabs = {
        {name = "Farm", rows = {{"petSpeed", "Pet Speed (Inf)"}, {"tap", "Fast Auto Click"}, {"clickAura", "Click Aura"}, {"auraVisual", "Click Aura Visualizer"}, {"vacuum", "Orb Vacuum"}, {"autoEgg", "Auto Open Closest Egg"}, {"farm", "Fast Farm"}, {"optBreakables", "Optimize Breakables"}, {"optPets", "Optimize Pets"}, {"jitter", "Human Jitter"}}, info = "farm"},
        {name = "Zone", rows = {{"zoneTele", "Auto Tele Best Zone"}, {"zoneBuy", "Auto Buy Next Zone"}, {"autoBuyPetSlots", "Auto Buy Pet Slots"}, {"worldTele", "Auto World Teleport"}}, info = "zone", world = true},
        {name = "Quest", rows = {{"autoQuest", "Auto Quest (claim completed)"}}, info = "quest"},
        {name = "Rank", rows = {{"autoRank", "Auto Rank Rewards"}, {"claimRank", "Claim Rank Rewards", true}, {"autoRebirth", "Auto Rebirth (resets progress)"}}, info = "rank"},
        {name = "Tools", rows = {{"antiAfk", "Anti-AFK"}, {"serverHop", "Auto Low-Player Server"}}, info = "tools"},
    }
    local tabBar = create("Frame", {Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 38), BackgroundTransparency = 1}, main)
    local body = create("Frame", {Size = UDim2.new(1, 0, 1, -124), Position = UDim2.fromOffset(0, 70), BackgroundTransparency = 1}, main)
    local pages, buttons, worldButtons = {}, {}, {}
    updateWorldButtons = function()
        for n, button in ipairs(worldButtons) do
            button.BackgroundColor3 = n == worldTarget and Color3.fromRGB(49, 96, 130) or Color3.fromRGB(45, 50, 62)
            button.Text = (n == worldTarget and "> " or "") .. "World " .. n
        end
    end
    local function selectTab(selected)
        for index, page in ipairs(pages) do
            page.Visible = index == selected
            buttons[index].BackgroundColor3 = index == selected and Color3.fromRGB(49, 66, 80) or Color3.fromRGB(30, 35, 45)
        end
    end
    for index, tab in ipairs(tabs) do
        local tabIndex = index
        buttons[index] = create("TextButton", {Size = UDim2.new(1 / #tabs, 0, 1, 0), Position = UDim2.new((index - 1) / #tabs, 0, 0, 0), BorderSizePixel = 0, Text = tab.name, TextColor3 = Color3.fromRGB(220, 227, 237), Font = Enum.Font.GothamBold, TextSize = 14}, tabBar)
        pages[index] = create("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Visible = index == 1}, body)
        local y = 8
        for _, row in ipairs(tab.rows) do
            local key = row[1]
            local frame = create("Frame", {Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, y), BackgroundColor3 = Color3.fromRGB(34, 39, 49), BorderSizePixel = 0}, pages[index])
            create("TextLabel", {Size = UDim2.new(1, -85, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Text = row[2], TextColor3 = Color3.fromRGB(225, 231, 239), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium, TextSize = 14}, frame)
            local button = create("TextButton", {Size = UDim2.fromOffset(62, 26), Position = UDim2.new(1, -70, 0, 5), BorderSizePixel = 0, TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 13}, frame)
            if row[3] then
                button.Text = "CLAIM"
                button.BackgroundColor3 = Color3.fromRGB(49, 96, 130)
                connect(button.Activated, function()
                    local _, message = claimRankRewards()
                    stage("Rank: " .. tostring(message))
                end)
            else
                toggleButtons[key] = button
                connect(button.Activated, function() setEnabled(key, not enabled[key]) end)
            end
            y += 42
        end
        if tab.world then
            for n = 1, CFG.WorldCount do
                local world = n
                local button = create("TextButton", {Size = UDim2.new(1 / CFG.WorldCount, -8, 0, 30), Position = UDim2.new((n - 1) / CFG.WorldCount, 4, 0, y), BorderSizePixel = 0, Text = "World " .. n, TextColor3 = Color3.fromRGB(235, 240, 248), Font = Enum.Font.GothamBold, TextSize = 12}, pages[index])
                worldButtons[n] = button
                connect(button.Activated, function() setWorldTarget(world); setEnabled("worldTele", true) end)
            end
            y += 38
        end
        infoLabels[tab.info] = create("TextLabel", {Size = UDim2.new(1, -24, 0, 112), Position = UDim2.fromOffset(12, y + 4), BackgroundTransparency = 1, Text = "waiting...", TextColor3 = Color3.fromRGB(176, 192, 206), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Font = Enum.Font.Gotham, TextSize = 13}, pages[index])
        pages[index].CanvasSize = UDim2.fromOffset(0, y + 124)
        connect(buttons[index].Activated, function() selectTab(tabIndex) end)
    end
    updateWorldButtons()
    selectTab(1)
    stageLabel = create("TextLabel", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -48), BackgroundTransparency = 1, Text = "Insert: hide/show | X: unload", TextColor3 = Color3.fromRGB(235, 191, 117), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, TextSize = 12}, main)
    footerLabel = create("TextLabel", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -25), BackgroundTransparency = 1, Text = "starting", TextColor3 = Color3.fromRGB(158, 178, 195), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, TextSize = 12}, main)
    local dragging, dragInput, dragStart, startPosition
    connect(title.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragInput, dragStart, startPosition = true, input, input.Position, main.Position
        end
    end)
    connect(UIS.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    connect(UIS.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    connect(UIS.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.Insert then screenGui.Enabled = not screenGui.Enabled end
    end)
    updateToggles()
end

cleanup = function()
    if not alive then return end
    alive = false
    for key in pairs(enabled) do enabled[key] = false end
    syncAntiAfk()
    for name in pairs(workers) do stopWorker(name) end
    heapObjects, heapCursor, treeScan, targetScan, pendingStats = nil, nil, nil, nil, nil
    for _, request in pairs(requests) do
        if request.thread and request.thread ~= coroutine.running() then pcall(task.cancel, request.thread) end
    end
    table.clear(requests)
    if statsConnection then statsConnection:Disconnect(); statsConnection = nil end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    restorePetSpeed()
    restoreOrbCapture()
    restoreEffects(optBreakableEffects)
    restoreEffects(optPetEffects)
    destroyAuraPart()
    if screenGui then screenGui:Destroy(); screenGui = nil end
    if env.__PS99CLEAN_CLEANUP == cleanup then env.__PS99CLEAN_CLEANUP = nil; env.__PS99CLEAN = nil end
    print("[PS99 CLEAN] unloaded")
end

local controller = {
    SetEnabled = setEnabled,
    SetWorld = setWorldTarget,
    ClaimRankRewards = claimRankRewards,
    AllOff = allOff,
    Stop = cleanup,
    GetStatus = function()
        getSave()
        return {running = alive, enabled = table.clone(enabled), world = worldTarget, profile = saveSource, notes = table.clone(notes)}
    end,
}
env.__PS99CLEAN = controller
env.__PS99CLEAN_CLEANUP = cleanup
local ok, err = pcall(buildGUI)
if not ok then cleanup(); error("PS99 CLEAN GUI: " .. tostring(err)) end
if not alive then return controller end
connect(LocalPlayer.CharacterAdded, function() targetModel, targetUid, targetAt = nil, nil, nil end)
ensureWorker("status", true, 1, updateStatus)
stage("Ready; no startup scans | Insert: hide/show | X: unload")
return controller
