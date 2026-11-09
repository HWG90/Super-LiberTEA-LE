-- Read-only HeatComponent sample. Native driver type selects heat; the native
-- current-heat value is divided by its entity override/resource definition limit.
-- This is physical accumulated heat, not remaining ammo, trigger charge or the
-- generic HUD gauge. No native function calls, second reader or input ownership.
local Build = mod.require("sampling/build.lua")
local Layout = mod.require("src/weapon_status_layouts.lua")
local Heat = {}
Heat.__index = Heat
-- Original reader's one mixed-bookkeeping exception: Talon also exposes round
-- state. Its identity-checked HeatComponent must exist before selecting heat.
Heat.TALON = "416d053372c4e433"
local function bytes(hex)
    return (hex:gsub("..", function(value)
        return string.char(tonumber(value, 16))
    end))
end
local witnesses = {}
for i, row in ipairs(Build.heat_witnesses) do
    witnesses[i] = { at = row.at, bytes = bytes(row.hex) }
end
function Heat.new(backend, memory)
    return setmetatable({ b = backend, r = memory, result = {} }, Heat)
end
function Heat:collect(info, current)
    local result, b, r = self.result, self.b, self.r
    for key in pairs(result) do
        result[key] = nil
    end
    if
        (info.ammo_kind ~= "heat" and info.resource_hex ~= Heat.TALON)
        or info.alternate_fire == true
        or not current()
    then
        return
    end
    for _, witness in ipairs(witnesses) do
        if r.read(b.base + witness.at, #witness.bytes) ~= witness.bytes then
            return
        end
    end
    local record = r.read(info.binding.record, 24)
    local manager = r.p(b.base + Layout.heat)
    local index = r.map(manager + 0x28, info.id, 65536)
    local live = r.u(r.read(manager + 0x14, 4), 0)
    if index == nil or index >= 4096 or live > 4096 or index >= live then
        return
    end
    if r.read(r.p(r.p(manager + 0x40) + index * 8), 24) ~= record then
        return
    end
    result.heat_weapon = true
    -- Classification and quantity have separate proofs. A known Talon heat
    -- component with missing calibration stays heat with an unknown quantity.
    pcall(self._calibrate, self, result, info, current, record, manager, index)
    return result
end
function Heat:_calibrate(result, info, current, record, manager, index)
    local b, r = self.b, self.r
    local config
    local override = r.map(manager + 0x68, info.id, 65536)
    if override ~= nil then
        if override >= 4096 then
            return
        end
        config = r.p(manager + 0xa8) + override * 0x250
    else
        -- Original typed resource-definition lookup: 60 slots,16-byte hash rows,
        -- 0x250-byte records. Hash the complete native resource key exactly.
        local owner = r.p(b.base + Layout.owner)
        local table_at = r.p(owner + Layout.static.heat[1])
        local capacity = Layout.static.heat[2]
        local home = ((r.u(record, 4) % capacity) * (2 ^ 32 % capacity) + r.u(record, 0) % capacity) % capacity
        for probe = 0, capacity - 1 do
            local row = r.read(table_at + ((home + probe) % capacity) * 16, 16)
            if row:sub(1, 8) == string.rep("\0", 8) then
                return
            end
            if row:sub(1, 8) == record:sub(1, 8) then
                local slot = r.u(row, 8)
                if slot >= capacity or r.u(row, 12) ~= 0 then
                    return
                end
                config = table_at + capacity * 16 + slot * Layout.static.heat[3]
                break
            end
        end
    end
    if not config then
        return
    end
    local runtime = r.read(r.p(manager + 0x58) + index * 12, 12)
    local value, limit = r.f(runtime, 4), r.f(r.read(config + 0x60, 4), 0)
    local locked = runtime:byte(9)
    if limit <= 0 or limit >= 1e7 or value < -1 or value >= 1e7 or (locked ~= 0 and locked ~= 1) then
        return
    end
    if r.p(b.base + Layout.heat) ~= manager or not current() then
        return
    end
    result.heat = math.max(0, math.min(1, value / limit))
    result.heat_current, result.heat_limit, result.heat_locked = value, limit, locked == 1
end
return Heat
