local Projectile = {}
Projectile.__index = Projectile
local function value(read, base, offset, form)
    if base ~= nil and base ~= 0 then
        return read:value(base + offset, form)
    end
end
local function key_argument(judge, key)
    if key == false then
        key = "0000000000000000"
    end
    if key ~= nil then
        return judge:uint64_of(key)
    end
end
function Projectile.new(weapon)
    local judge = weapon.judge
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = judge,
        n = weapon.n,
        can_call = assert(judge:routine("can_fire")),
        open_call = assert(judge:routine("projectile_weapon_open")),
        function_call = assert(judge:routine("weapon_function_of")),
        aim_call = assert(judge:routine("weapon_aim_record_find")),
    }, Projectile)
end
function Projectile:clear()
    self.id, self.record, self.blob, self.data_index, self.can_fire, self.entity_key, self.flies =
        nil, nil, nil, nil, nil, nil, nil
    self.info, self.kind, self.speed, self.scale, self.aim = nil, nil, nil, nil, nil, nil
    self.projectile, self.aim_key, self.corrected = nil, nil, nil
end
function Projectile:information(kind)
    local read, n = self.read, self.n
    local held = self.projectile
    if held == nil or kind ~= held.kind then
        held = { kind = kind }
        self.projectile = held
        if kind ~= nil and kind > 0 then
            held.info = read:ptr(self.weapon.game + n.projectile_info_table + kind * n.projectile_info_stride)
        end
        held.impact = value(read, held.info, n.projectile_explosion_impact, "u32")
        held.expire = value(read, held.info, n.projectile_explosion_expire, "u32")
    end
    return held
end
function Projectile:details()
    local held, read, n = self.projectile, self.read, self.n
    if held.detail == nil then
        local at, v = held.info, {}
        v.mass = value(read, at, n.projectile_mass, "f32")
        v.drag = value(read, at, n.projectile_drag, "f32")
        v.gravity = value(read, at, n.projectile_gravity_scale, "f32")
        v.substeps = value(read, at, n.projectile_substeps, "u32")
        v.life = value(read, at, n.projectile_lifetime, "f32")
        v.caliber = value(read, at, n.projectile_caliber, "f32")
        v.arming = value(read, at, n.projectile_arming, "f32")
        v.flags = value(read, at, n.projectile_info_flags, "u32")
        v.filter = value(read, at, n.projectile_info_filter, "u32")
        v.explode_angle = value(read, at, n.projectile_explode_angle, "f32")
        v.ricochets = value(read, at, n.projectile_ricochets, "u32")
        v.ricochet_angle = value(read, at, n.projectile_ricochet_angle, "f32")
        v.ricochet_speed = value(read, at, n.projectile_ricochet_speed, "f32")
        v.speed = value(read, at, n.projectile_speed, "f32")
        held.detail = v
    end
    return held.detail
end
function Projectile:target()
    if self.record == nil or self.data_index == nil then
        return nil
    end
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    local key = weapon:key(self.record)
    if key ~= self.aim_key then
        self.aim_key, self.corrected = key, nil
        local arg = key_argument(judge, key)
        local at
        if arg ~= nil then
            at = judge:call(self.aim_call, arg)
        end
        self.corrected = value(read, at, n.weapon_aim_record_corrected, "bool")
    end
    local rows = read:ptr(self.data + n.weapon_data_r1_at)
    if rows == nil then
        return nil
    end
    local at = rows + self.data_index * n.weapon_data_r1_stride
    local offset = n.weapon_aim_point
    if self.corrected == true then
        offset = n.weapon_aim_corrected_point
    end
    return read:vector(at + offset, 3)
end
function Projectile:observe(aiming, id, record, charge)
    self.id, self.record, self.blob, self.data_index, self.can_fire, self.entity_key, self.flies =
        nil, nil, nil, nil, nil, nil, nil
    self.info, self.kind, self.speed, self.scale, self.aim = nil, nil, nil, nil, nil, nil
    if aiming ~= true or id == nil then
        self:clear()
        return
    end
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    self.data = weapon:manager(n.weapon_data_manager)
    if self.data == nil then
        return
    end
    self.data_index = weapon:find(self.data + n.weapon_data_map, id, weapon.invalid_entity)
    if self.data_index == nil then
        return
    end
    self.id, self.record = id, record
    local components = weapon:manager(n.weapon_manager)
    if components ~= nil then
        self.can_fire = judge:call(self.can_call, components, id)
    end
    local manager, owner = weapon:manager(n.projectile_weapon_manager), weapon:manager(n.roots_entity_owner_rva)
    if manager == nil or owner == nil or read:ptr(owner + n.projectile_registry_table) == nil or record == nil then
        return
    end
    local blob = judge:call(self.open_call, record)
    if blob == nil or blob == 0 then
        return
    end
    self.blob = blob
    local programmable = judge:call(self.function_call, id, n.weapon_function_programmable) == n.weapon_function_on
    local kind, entity
    if programmable then
        kind = read:value(blob + n.projectile_blob_programmed_type, "u32")
        entity = read:value(blob + n.projectile_blob_programmed_entity, "key64")
    end
    if entity == nil or entity == false then
        entity = read:value(blob + n.projectile_blob_entity, "key64")
    end
    if entity ~= nil and entity ~= false then
        self.entity_key = entity
    end
    if self.can_fire ~= true then
        return
    end
    local charged, short = charge:projectile()
    if kind == nil or kind <= 0 then
        kind = charged
    end
    if kind == nil or kind <= 0 then
        kind = read:value(blob + n.projectile_type, "u32")
    end
    local held = self:information(kind)
    self.kind, self.info = kind, held.info
    if
        self.info == nil
        or not ((held.impact ~= nil and held.impact > 0) or (held.expire ~= nil and held.expire > 0))
        or short == true
        or self.entity_key ~= nil
    then
        return
    end
    local heat = weapon:manager(n.weapon_heat_manager)
    if heat ~= nil and weapon:find(heat + n.weapon_heat_map, id, weapon.invalid_entity) ~= nil then
        return
    end
    local index = weapon:find(manager + n.projectile_weapon_map, id, weapon.invalid_entity)
    local row
    if index ~= nil then
        local rows = read:ptr(manager + n.projectile_weapon_rows)
        if rows ~= nil then
            row = rows + index * n.projectile_weapon_row_stride
        end
    end
    if
        value(read, row, n.projectile_slot_fixed_direction, "bool") == true
        or read:value(blob + n.projectile_blob_fixed_direction, "bool") == true
    then
        return
    end
    self.flies = true
    local v = self:details()
    self.scale = value(read, row, n.projectile_weapon_speed_scale, "f32")
    local speed
    if index ~= nil and judge:call(self.function_call, id, n.weapon_function_muzzle_speed) == n.weapon_function_on then
        speed = read:value(blob + n.projectile_blob_muzzle_speed, "f32")
    end
    if speed == nil or speed <= 0 then
        speed = v.speed
    end
    self.speed, self.aim = speed, self:target()
end
return Projectile
