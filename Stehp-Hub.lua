-- Steph HUB compatibility entry for the universal loader.
local VERSION = "10.4"

local function _d(bytes)
    local out = table.create(#bytes)
    for i = 1, #bytes do
        out[i] = string.char(bytes[i] - 3)
    end
    return table.concat(out)
end

local BASE = _d({
    107,119,119,115,118,61,50,50,117,100,122,49,106,108,119,107,120,101,120,118,104,117,102,114,113,119,104,113,119,49,102,114,112,50,
    112,108,113,108,122,117,114,111,103,115,117,114,52,53,55,48,102,124,101,104,117,50,115,104,119,60,60,101,124,113,107,112,119,50,
    112,100,108,113,50
})

local source
if type(readfile) == "function" then
    local ok, localSource = pcall(readfile, "main.lua")
    if ok and type(localSource) == "string" and #localSource > 64 then
        source = localSource
    end
end
if not source then
    source = game:HttpGet(BASE .. "main.lua?v=" .. VERSION .. "&t=" .. tostring(os.time()))
end
assert(type(source) == "string" and #source > 64, "[Steph HUB] main loader is missing")
local chunk, err = loadstring(source, "=main.lua")
assert(chunk, err)
return chunk()
