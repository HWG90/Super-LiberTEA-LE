local Attackers = {}
Attackers.__index = Attackers
function Attackers.new(weapon)
    return setmetatable({
        weapon = weapon,
        lob = {},
        lob_cache = {},
        keys = {},
        faction = assert(weapon.judge:routine("faction_includes")),
    }, Attackers)
end
local function records(read, manager, used, capacity, array)
    if manager == nil then
        return nil
    end
    local limit = read:value(manager + capacity, "u32")
    local base = read:ptr(manager + array)
    if used == nil or limit == nil or used > limit or base == nil then
        return nil
    end
    local out = {}
    for index = 0, used - 1 do
        local at = read:ptr(base + index * 8)
        if at == nil then
            return nil
        end
        out[#out + 1] = at
    end
    return out
end
function Attackers:observe(eagles)
    local weapon = self.weapon
    local read, judge, n = weapon.read, weapon.judge, weapon.n
    local keys = {}
    for id in pairs(eagles) do
        keys[id] = { id = id, aircraft = id }
    end
    local bomb_manager = weapon:manager(n.bombardment_manager)
    local count
    if bomb_manager ~= nil then
        count = read:value(bomb_manager + n.bombardment_count, "u32")
    end
    local bombs = records(read, bomb_manager, count, n.bombardment_capacity, n.bombardment_records)
    for _, at in ipairs(bombs or {}) do
        local id = read:value(at + n.bombardment_entity_id, "u32")
        if id ~= nil and keys[id] == nil then
            keys[id] = { id = id }
        end
    end
    local manager = weapon:manager(n.turret_manager)
    local used
    if manager ~= nil then
        used = read:value(manager + n.turret_used, "u32")
    end
    if manager ~= self.manager or used ~= self.used then
        local lob, cache = {}, {}
        local previous = self.lob_cache
        if manager ~= self.manager then
            previous = {}
        end
        local rows = records(read, manager, used, n.turret_capacity, n.turret_rows)
        local targeting = weapon:manager(n.targeting_manager)
        if targeting ~= nil then
            for _, at in ipairs(rows or {}) do
                local id = read:value(at + n.turret_entity_id, "u32")
                if id ~= nil then
                    local ours = previous[id]
                    if ours == nil then
                        local index = weapon:find(targeting + n.targeting_map, id, weapon.invalid_player)
                        local cells
                        if index ~= nil then
                            cells = read:ptr(targeting + n.targeting_rows)
                        end
                        ours = cells ~= nil
                            and read:value(cells + index * n.targeting_row_stride + n.targeting_arc_aim, "bool") == true
                            and judge:call(self.faction, 0, n.owner_faction_mask, id) == true
                    end
                    cache[id] = ours
                    if ours then
                        lob[id] = self.lob[id] or { id = id }
                    end
                end
            end
        end
        self.manager, self.used, self.lob, self.lob_cache = manager, used, lob, cache
    end
    for id, item in pairs(self.lob) do
        if keys[id] == nil then
            keys[id] = item
        end
    end
    self.keys = keys
end
function Attackers:clear()
    self.manager, self.used, self.lob, self.lob_cache, self.keys = nil, nil, {}, {}, {}
end
return Attackers
