-- LAS-44 Nova presentation terms, game.dll 6AF322C1 (HD2 26568081).
--
-- When the player aims, the game places the weapon at distance D in front of the camera
-- (game+0x110ADE0, written to the kind-6 camera request +0x90):
--   D = N + G / (tan(F/Z/2) * C),   N = (1-u)*row[+148] + u*row[+14C],   u = (F-45)/45
-- Z is the selected zoom (row +74/+78/+7C), C its coefficient (+13C/+140/+144), F the FOV
-- setting and G the weapon's box extent. Each spawned weapon has its own row in the weapon
-- manager [game+0x2CE1EA0] (map +70, rows +B0, stride 4D8), and the optic writes Z and C there.
-- The Nova's optic gives Z 3.5/2.5/1 and C 0.6 at every zoom, which only looks right at 3.5x:
-- the lower zooms show the gun too far away. PATCH holds the row terms that make the game place
-- the gun at D 0.3477/0.217/-0.018, the distances at which the scope matched its 3.5x look on
-- screen at FOV 90 (measured 2026-11-07). 3.5x keeps its own D.
--
-- Only rows mapped to the Nova's resource key and still holding exactly VANILLA are written;
-- restore() writes VANILLA back over rows that still hold exactly PATCH.
local M = {}
M.STAMP = 0x6AF322C1
M.MANAGER = 0x2CE1EA0
local STRIDE, TERMS, ZOOMS = 0x4D8, 0x13C, 0x74
local KEY = '\66\83\199\232\170\78\216\115'        -- 73d84eaae8c75342, little-endian
local function unhex(s) return (s:gsub('%x%x', function(p) return string.char(tonumber(p, 16)) end)) end
M.VANILLA = unhex('9a99193f9a99193f9a99193f00000000cdcccc3d')  -- C 0.6/0.6/0.6, N 0/0.1
M.PATCH = unhex('edf3a93ec897a83ea8c4d33ecdccccbdcdccccbd')    -- C .33194/.32928/.41361, N -0.1/-0.1
local NOVA_ZOOMS = unhex('00006040000020400000803f')              -- Z 3.5/2.5/1
local MAX_CAPACITY = 4096

local function u32(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function pointer(bytes, offset)
    local value = u32(bytes, offset or 0) + u32(bytes, (offset or 0) + 4) * 4294967296
    return value >= 65536 and value < 2^47 and value or nil
end

-- io: read(address, size) -> bytes|nil, why; write(address, bytes) -> true|false, why;
--     module(name) -> base, size, stamp | nil, why.
function M.new(io)
    return setmetatable({io = io}, {__index = M})
end

function M:_read(address, size)
    local bytes, why = self.io:read(address, size)
    assert(type(bytes) == 'string' and #bytes == size, why or 'Memory is unreadable')
    return bytes
end

-- A manager map: entries pointer +0, capacity +8, empty key +C; entries are (key, value) u32 pairs.
function M:_map(manager, at)
    local header = self:_read(manager + at, 16)
    local array, capacity = pointer(header), u32(header, 8)
    if not array or capacity == 0 then return nil, 0 end
    assert(capacity <= MAX_CAPACITY, 'Weapon manager capacity differs')
    return self:_read(array, capacity * 8), capacity, u32(header, 12)
end

-- Rows of every spawned Nova, as addresses.
function M:rows()
    local game, _, stamp = self.io:module('game.dll')
    assert(game, stamp)
    assert(stamp == M.STAMP, ('Unsupported game build (game.dll %08X)'):format(stamp))
    local manager = assert(pointer(self:_read(game + M.MANAGER, 8)), 'Weapon manager is unavailable')
    local novas = {}
    local descriptors, count, unused = self:_map(manager, 0x30)
    if descriptors then
        local slots = assert(pointer(self:_read(manager + 0x48, 8)), 'Weapon descriptors are unavailable')
        for b = 0, count - 1 do
            local slot = u32(descriptors, b * 8 + 4)
            if u32(descriptors, b * 8) ~= unused and slot ~= 0xFFFFFFFF and slot < MAX_CAPACITY then
                local descriptor = pointer(self:_read(slots + slot * 8, 8))
                if descriptor then
                    local d = self:_read(descriptor, 12)
                    if d:sub(1, 8) == KEY then novas[u32(d, 8)] = true end
                end
            end
        end
    end
    local found = {}
    local entities, capacity, empty = self:_map(manager, 0x70)
    if not entities or not next(novas) then return found end
    local rows = assert(pointer(self:_read(manager + 0xB0, 8)), 'Weapon rows are unavailable')
    for b = 0, capacity - 1 do
        local entity, index = u32(entities, b * 8), u32(entities, b * 8 + 4)
        if entity ~= empty and index ~= 0xFFFFFFFF and index < MAX_CAPACITY and novas[entity] then
            local row = rows + index * STRIDE
            if self:_read(row + ZOOMS, 12) == NOVA_ZOOMS then found[#found + 1] = row end
        end
    end
    return found
end

-- Replace from with to on every Nova row that holds exactly from. Returns rows written.
function M:_swap(from, to)
    local written = 0
    for _, row in ipairs(self:rows()) do
        if self:_read(row + TERMS, #from) == from then
            local ok, why = self.io:write(row + TERMS, to)
            assert(ok, why or 'Memory write failed')
            written = written + 1
        end
    end
    return written
end

function M:apply() return self:_swap(M.VANILLA, M.PATCH) end
function M:restore() return self:_swap(M.PATCH, M.VANILLA) end

return M
