local Flight = require("game.flight")
local Delivery = {}
Delivery.__index = Delivery
function Delivery.new(weapon)
    local n, judge = weapon.n, weapon.judge
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = judge,
        n = n,
        state = {},
        eagle_of = assert(judge:routine("eagle_default_of")),
        bomb_of = assert(judge:routine("bombardment_default_of")),
        weapon_of = assert(judge:routine("projectile_weapon_default_of")),
        scale_calls = {
            tag_of = assert(judge:routine("stratagem_tag_of")),
            upgrade = assert(judge:routine("upgrade_value_of")),
        },
        scale_numbers = {
            tag_stride = n.tag_row_stride,
            tag_count = n.tag_count_at,
            tag_hashes = n.tag_hashes_at,
            outer = n.explosion_outer_upgrade,
            inner = n.explosion_inner_upgrade,
        },
        heading_numbers = {
            block = n.eagle_heading_block,
            read = n.eagle_heading_read,
            copy = n.eagle_heading_copy,
        },
    }, Delivery)
end
function Delivery:clear()
    self.kind, self.entry, self.eagle, self.bombardment, self.weapon_blob, self.degrees, self.scale =
        nil, nil, nil, nil, nil, nil, nil
    self.world = nil
end
function Delivery:select(kind)
    if kind == self.kind then
        return
    end
    self.kind, self.eagle, self.bombardment, self.weapon_blob, self.degrees, self.scale = kind, nil, nil, nil, nil, nil
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    if kind == nil or kind <= 0 or kind >= n.stratagem_kind_end then
        return
    end
    local tags, upgrades = weapon:manager(n.stratagem_tag_db), weapon:manager(n.upgrade_manager)
    if tags ~= nil and upgrades ~= nil then
        self.scale = Flight.scale(
            read,
            judge,
            self.scale_calls,
            self.state,
            { tags = tags, upgrades = upgrades, kind = kind },
            self.scale_numbers
        )
    end
    local info = read:ptr(weapon.game + n.stratagem_info_table + kind * n.stratagem_info_stride)
    if info == nil then
        return
    end
    local count = read:value(info + n.stratagem_delivery_count, "u32")
    if count == nil or count <= 0 then
        return
    end
    local array = read:ptr(info + n.stratagem_delivery_array)
    local hash
    if array ~= nil then
        hash = read:value(array, "key64")
    end
    if not hash then
        return
    end
    local entities = weapon:manager(n.roots_entity_owner_rva)
    if entities == nil then
        return
    end
    local key = judge:uint64_of(hash)
    if read:ptr(entities + n.eagle_default_table) ~= nil then
        local value = judge:call(self.eagle_of, key)
        if value ~= 0 then
            self.eagle = value
        end
    end
    if self.eagle ~= nil then
        self.degrees = Flight.heading(read, self.eagle, self.heading_numbers)
        local mode = read:value(self.eagle + n.eagle_mode_at, "u32")
        if mode == n.eagle_strafing_mode and read:ptr(entities + n.projectile_registry_table) ~= nil then
            local value = judge:call(self.weapon_of, key)
            if value ~= 0 then
                self.weapon_blob = value
            end
        end
    elseif read:ptr(entities + n.bombardment_default_table) ~= nil then
        local value = judge:call(self.bomb_of, key)
        if value ~= 0 then
            self.bombardment = value
        end
    end
end
function Delivery:observe(cell, world)
    if world ~= self.world then
        self:clear()
        self.world = world
    end
    local weapon, read, n = self.weapon, self.read, self.n
    self.entry = nil
    if cell == nil then
        self:select(nil)
        return
    end
    local manager = weapon:manager(n.beacon_manager)
    if manager == nil then
        self:select(nil)
        return
    end
    local index = weapon:find(manager + n.beacon_map, cell, weapon.invalid_entity)
    local entries
    if index ~= nil then
        entries = read:ptr(manager + n.beacon_entries)
    end
    if entries ~= nil then
        self.entry = entries + index * n.beacon_entry_size
    end
    local kind
    if self.entry ~= nil then
        kind = read:value(self.entry + n.beacon_kind_at, "u32")
    end
    self:select(kind)
end
return Delivery
