local Flight = require("game.flight")
local Shells = {}
Shells.__index = Shells
function Shells.new(weapon, trajectory)
    local n, numbers = weapon.n, {}
    for key, value in pairs(trajectory.numbers) do
        numbers[key] = value
    end
    for role, name in pairs({
        pool_states = "projectile_pool_states",
        state_stride = "projectile_pool_state_stride",
        pool_shooter = "projectile_pool_shooter",
        shooter_bit = "projectile_pool_shooter_bit",
        shooter_stride = "projectile_pool_source_stride",
        pool_type = "projectile_pool_type",
        type_stride = "projectile_pool_type_stride",
        info_stride = "projectile_info_stride",
        info_filter = "projectile_info_filter",
        gravity_at = "projectile_live_gravity",
        drag_at = "projectile_live_drag",
        mass_at = "projectile_live_mass",
        substeps_at = "projectile_live_substeps",
        follow_at = "projectile_live_unit",
    }) do
        numbers[role] = n[name]
    end
    return setmetatable({
        weapon = weapon,
        trajectory = trajectory,
        numbers = numbers,
        cache = {},
        rows = {},
        state = {},
        flags = weapon.read.strided(n.projectile_pool_capacity, n.projectile_pool_state_stride, "u16"),
        modifier = assert(weapon.judge:routine("explosion_modifier_of")),
        blast_numbers = {
            kind_count = n.explosion_kind_count,
            explosion_stride = n.explosion_info_stride,
            radius_inner = n.explosion_radius_inner,
            radius_outer = n.explosion_radius_outer,
            children = n.area_children,
        },
    }, Shells)
end
function Shells:slots(system)
    local read, n = self.weapon.read, self.weapon.n
    local count = read:value(system + n.projectile_pool_count, "u32")
    local cursor = read:value(system + n.projectile_pool_cursor, "u32")
    if count == nil or cursor == nil or count > n.projectile_pool_capacity then
        return nil
    end
    local out, scanned, size, flags = {}, 0, count, self.flags
    while #out < count and scanned < n.projectile_pool_capacity do
        local last = (cursor - scanned - 1) % n.projectile_pool_capacity
        size = math.min(size, last + 1, n.projectile_pool_capacity - scanned)
        flags.n = size
        local got = read:value(
            system + n.projectile_pool_states + (last - size + 1) * n.projectile_pool_state_stride,
            flags,
            flags
        )
        for index = size, 1, -1 do
            if math.floor(got[index] / n.projectile_pool_active) % 2 == 1 then
                out[#out + 1] = last - size + index
                if #out == count then
                    break
                end
            end
        end
        scanned, size = scanned + size, size * 2
    end
    return out
end
function Shells:landing(system, slot, keys, own, mode, world)
    local weapon, trajectory = self.weapon, self.trajectory
    local read, judge, n = weapon.read, weapon.judge, weapon.n
    local meta = system + n.projectile_pool_meta + slot * n.projectile_pool_meta_stride
    if mode == 1 then
        local owner = read:value(meta, "key64")
        if not owner or owner ~= own then
            return {}
        end
    end
    local source = read:value(system + n.projectile_pool_source + slot * n.projectile_pool_source_stride, "u32")
    if source == nil then
        return {}
    end
    local origin = read:value(meta + n.projectile_pool_origin, "u32")
    local attacker = keys[source] or (origin ~= nil and keys[origin])
    if not attacker then
        return {}
    end
    local filters = read:ptr(system + n.projectile_filter_table)
    local k = trajectory.constants
    if filters == nil or k.limit == nil or k.floor == nil then
        return {}
    end
    local flight = Flight.predict(read, judge, trajectory.calls, self.state, {
        live = system + n.projectile_pool_motion + slot * n.projectile_pool_motion_stride,
        aircraft = attacker.aircraft,
        filters = filters,
        limit = k.limit,
        floor = k.floor,
        world = world,
        trees = weapon.game + n.speedtree_pass_table,
        pool = system,
        slot = slot,
        infos = weapon.game + n.projectile_info_table,
    }, self.numbers)
    if flight == nil or flight.finish == nil then
        return {}
    end
    local expire, impact =
        read:value(meta + n.projectile_pool_expire, "u32"), read:value(meta + n.projectile_pool_impact, "u32")
    local kind
    if expire ~= nil and expire > 0 then
        kind = expire
    elseif impact ~= nil and impact > 0 then
        kind = impact
    end
    local modifiers = weapon:manager(n.explosion_modifier_table)
    if modifiers == nil then
        return {}
    end
    local outer = judge:call(self.modifier, modifiers, source, n.explosion_scale_key)
    local inner = judge:call(self.modifier, modifiers, source, n.explosion_inner_scale_key)
    if outer == nil or inner == nil then
        return {}
    end
    local row = Flight.blast(read, {
        at = flight,
        impact = kind,
        expire = kind,
        scale_outer = outer,
        scale_inner = inner,
        explosions = weapon.game + n.explosion_info_table,
    }, self.blast_numbers) or {}
    row.key, row.at = "shell:" .. slot, flight.finish
    return row
end
function Shells:observe(keys, mode, world)
    if next(keys) == nil or world == nil then
        self:clear()
        return
    end
    local weapon = self.weapon
    local read, n = weapon.read, weapon.n
    local system = weapon:manager(n.projectile_system)
    if system == nil then
        self:clear()
        return
    end
    if system ~= self.system or world ~= self.world or mode ~= self.mode then
        self:clear()
    end
    self.system, self.world, self.mode = system, world, mode
    local own
    if mode == 1 then
        own = weapon:local_key()
    end
    if own ~= self.owner then
        self.cache = {}
        self.owner = own
    end
    local slots = self:slots(system)
    if slots == nil then
        self.rows = {}
        return
    end
    local cache, rows = {}, {}
    for _, slot in ipairs(slots) do
        local row = self.cache[slot] or self:landing(system, slot, keys, own, mode, world)
        cache[slot] = row
        if row.at ~= nil then
            rows[#rows + 1] = row
        end
    end
    self.cache, self.rows = cache, rows
end
function Shells:clear()
    self.cache, self.rows, self.state, self.system, self.world, self.mode, self.owner = {}, {}, {}, nil, nil, nil, nil
end
return Shells
