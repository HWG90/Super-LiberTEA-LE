-- Offline checks for goose_nova_weapon_fov against a fake weapon manager.
-- Run from this folder: luajit harness.lua
package.path = '../stage/goose_nova_weapon_fov/?.lua;' .. package.path
local Nova = require('src.nova')

local function le(n, size)
    local out = {}
    for i = 1, size do out[i] = string.char(n % 256); n = math.floor(n / 256) end
    return table.concat(out)
end
local function unhex(s) return (s:gsub('%x%x', function(p) return string.char(tonumber(p, 16)) end)) end

-- Sparse memory made of regions; reads must fall inside one region.
local function memory(stamp)
    local regions, writes = {}, {}
    local m = {writes = writes}
    function m.put(base, bytes) regions[#regions + 1] = {base = base, bytes = bytes} end
    local function find(address, size)
        for _, r in ipairs(regions) do
            if address >= r.base and address + size <= r.base + #r.bytes then return r end
        end
    end
    function m:read(address, size)
        local r = find(address, size)
        if not r then return nil, ('unmapped read 0x%X+%d'):format(address, size) end
        local at = address - r.base
        return r.bytes:sub(at + 1, at + size)
    end
    function m:write(address, bytes)
        local r = find(address, #bytes)
        if not r then return false, 'unmapped write' end
        local at = address - r.base
        r.bytes = r.bytes:sub(1, at) .. bytes .. r.bytes:sub(at + #bytes + 1)
        writes[#writes + 1] = address
        return true
    end
    function m:module(name)
        assert(name == 'game.dll')
        return 0x140000000, 0x3382000, stamp
    end
    return m
end

local NOVA_KEY = unhex('4253c7e8aa4ed873')
local OTHER_KEY = unhex('33e4c47233056d41')
local Z_NOVA = unhex('00006040000020400000803f')
local Z_OTHER = unhex('000000400000404000008040')
local EMPTY = 0xFFFFFFFF

-- weapons: {entity, key, zooms, terms}; row index = position - 1
local function world(stamp, weapons)
    local m = memory(stamp)
    local GAME, MANAGER, DESC_ARRAY, SLOTS, DESCS, ENT_ARRAY, ROWS = 0x140000000, 0x10000000,
        0x10100000, 0x10200000, 0x10300000, 0x10400000, 0x10500000
    local cap = 8
    m.put(GAME + Nova.MANAGER, le(MANAGER, 8))
    local manager = string.rep('\0', 0x30) .. le(DESC_ARRAY, 8) .. le(cap, 4) .. le(EMPTY, 4)
        .. string.rep('\0', 8) .. le(SLOTS, 8) .. string.rep('\0', 0x70 - 0x50) .. le(ENT_ARRAY, 8) .. le(cap, 4) .. le(EMPTY, 4)
        .. string.rep('\0', 0xB0 - 0x80) .. le(ROWS, 8)
    m.put(MANAGER, manager)
    local desc_array, ent_array, slots, rows = {}, {}, {}, {}
    for i = 1, cap do
        local w = weapons[i]
        if w then
            desc_array[i] = le(w[1], 4) .. le(i - 1, 4)
            ent_array[i] = le(w[1], 4) .. le(i - 1, 4)
            slots[i] = le(DESCS + (i - 1) * 16, 8)
            m.put(DESCS + (i - 1) * 16, w[2] .. le(w[1], 4) .. le(0, 4))
            rows[i] = string.rep('\0', 0x74) .. w[3] .. string.rep('\0', 0x13C - 0x80) .. w[4]
                .. string.rep('\0', 0x4D8 - 0x150)
        else
            desc_array[i] = le(EMPTY, 4) .. le(EMPTY, 4)
            ent_array[i] = le(EMPTY, 4) .. le(EMPTY, 4)
            slots[i] = le(0, 8)
            rows[i] = string.rep('\0', 0x4D8)
        end
    end
    m.put(DESC_ARRAY, table.concat(desc_array))
    m.put(ENT_ARRAY, table.concat(ent_array))
    m.put(SLOTS, table.concat(slots))
    m.put(ROWS, table.concat(rows))
    function m.terms(i) return (m:read(ROWS + (i - 1) * 0x4D8 + 0x13C, 20)) end
    return m
end

local passed = 0
local function check(name, ok)
    if not ok then error('FAIL ' .. name, 2) end
    passed = passed + 1
    print('ok  ' .. name)
end

local MODIFIED = unhex('000000400000004000000040cdcccc3dcdcccc3d')
local m = world(Nova.STAMP, {
    {100, NOVA_KEY, Z_NOVA, Nova.VANILLA},
    {200, OTHER_KEY, Z_NOVA, Nova.VANILLA},
    {300, NOVA_KEY, Z_NOVA, MODIFIED},
    {400, NOVA_KEY, Z_OTHER, Nova.VANILLA},
    nil,
    {600, NOVA_KEY, Z_NOVA, Nova.VANILLA},
})
local n = Nova.new(m)
check('finds the three Nova rows with the Nova optic', #n:rows() == 3)
check('apply writes the two vanilla Nova rows', n:apply() == 2)
check('Nova row 1 holds the patch', m.terms(1) == Nova.PATCH)
check('Nova row 6 holds the patch', m.terms(6) == Nova.PATCH)
check('a non-Nova weapon is left alone', m.terms(2) == Nova.VANILLA)
check('a Nova row with other terms is left alone', m.terms(3) == MODIFIED)
check('a Nova with another optic is left alone', m.terms(4) == Nova.VANILLA)
check('apply again writes nothing', n:apply() == 0)
check('restore writes the two patched rows back', n:restore() == 2)
check('Nova row 1 is vanilla again', m.terms(1) == Nova.VANILLA)
check('restore again writes nothing', n:restore() == 0)
check('only four writes were made', #m.writes == 4)

local wrong = Nova.new(world(0x6AB3B43F, {{100, NOVA_KEY, Z_NOVA, Nova.VANILLA}}))
local ok, why = pcall(wrong.apply, wrong)
check('another build is refused', not ok and tostring(why):find('Unsupported game build', 1, true) ~= nil)

-- main.lua lifecycle with a stub LLL mod table and the fake memory.
local live = world(Nova.STAMP, {{100, NOVA_KEY, Z_NOVA, Nova.VANILLA}})
local logs = {}
mod = {
    log = function(s) logs[#logs + 1] = s end,
    require = function(path)
        if path == 'src/memory.lua' then return {new = function() return live end} end
        return require(path:gsub('%.lua$', ''):gsub('/', '.'))
    end,
}
local main = dofile('../stage/goose_nova_weapon_fov/main.lua')
main.on_enable()
main.on_update(0.6)
check('on_update patches the spawned Nova', live.terms(1) == Nova.PATCH)
check('on_disable restores it', main.on_disable() == true and live.terms(1) == Nova.VANILLA)
check('the log says what happened', table.concat(logs, '|'):find('Set the Nova terms on 1', 1, true) ~= nil
    and table.concat(logs, '|'):find('Restored the game terms on 1', 1, true) ~= nil)
print(passed .. ' checks passed')
