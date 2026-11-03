-- Run HUD Plus's own signature resolver over captured module images.
-- usage: luajit resolve_offline.lua <bundle.lua> <exe image> <game image> <out.tsv> [out.json]
-- The JSON holds the found values exactly (name -> number, hex string or list of numbers).
local bundle_path, exe_path, game_path, out_path, json_path = arg[1], arg[2], arg[3], arg[4], arg[5]

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local source = slurp(bundle_path)
local tail = "return import('entry')"
local at = source:find(tail, #source - 200, true)
assert(at, "bundle tail not found")
source = source:sub(1, at - 1) .. "return import"
local import = assert(loadstring(source, "@hud_plus_bundle"))()

local Signatures = import("native.signatures")
local data = import("game.data")

local images = { exe = slurp(exe_path), game = slurp(game_path) }
local bases = { exe = 0x140000000, game = 0x180000000 }

local channel = {}
function channel:module(which) return bases[which] end
function channel:text(address, size)
    for name, base in pairs(bases) do
        local image = images[name]
        if address >= base and address + size <= base + #image then
            return image:sub(address - base + 1, address - base + size)
        end
    end
    return nil
end

-- Copy the baked numbers: resolve() overwrites nothing, but close() reads them.
local baked = {}
for k, v in pairs(data) do baked[k] = v end
local old = {}
for k, v in pairs(data.numbers) do old[k] = v end

local clock = os.clock()
local found, missing = Signatures.resolve(channel, baked)
io.stderr:write(string.format("resolve took %.1fs\n", os.clock() - clock))
assert(found, missing)

local function show(v)
    if type(v) == "table" then
        local parts = {}
        for i = 1, #v do parts[i] = string.format("%.9g", v[i]) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "number" then
        if v == math.floor(v) and v >= 0 and v < 2^53 then return string.format("0x%x", v) end
        return string.format("%.9g", v)
    end
    return tostring(v)
end

local names = {}
for name in pairs(old) do names[#names + 1] = name end
table.sort(names)
local out = assert(io.open(out_path, "w"))
local counts = { same = 0, changed = 0, missing = 0 }
for _, name in ipairs(names) do
    local new = found[name]
    local state
    if new == nil then state = "missing:" .. tostring(missing[name])
    elseif show(new) == show(old[name]) then state = "same"
    else state = "changed" end
    counts[state:match("^%a+")] = counts[state:match("^%a+")] + 1
    out:write(name, "\t", state, "\t", show(old[name]), "\t", show(new), "\n")
end
out:close()
if json_path then
    local function exact(v)
        if type(v) == "table" then
            local parts = {}
            for i = 1, #v do parts[i] = string.format("%.17g", v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        elseif type(v) == "number" then
            if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
            return string.format("%.17g", v)
        end
        return '"' .. tostring(v) .. '"'
    end
    local rows = {}
    for _, name in ipairs(names) do
        if found[name] ~= nil then rows[#rows + 1] = string.format("%q:%s", name, exact(found[name])) end
    end
    local j = assert(io.open(json_path, "w"))
    j:write("{", table.concat(rows, ","), "}")
    j:close()
end
io.stderr:write(string.format("same=%d changed=%d missing=%d\n", counts.same, counts.changed, counts.missing))
