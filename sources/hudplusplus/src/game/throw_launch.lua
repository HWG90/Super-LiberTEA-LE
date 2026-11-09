local Flight = require("game.flight")
local Launch = {}
Launch.__index = Launch
local function value(read, at, offset, form)
    if at ~= nil and at ~= 0 then
        return read:value(at + offset, form)
    end
end
local function argument(judge, key)
    if key == false then
        key = "0000000000000000"
    end
    if key ~= nil then
        return judge:uint64_of(key)
    end
end
function Launch.new(weapon)
    local n, judge, read = weapon.n, weapon.judge, weapon.read
    local calls = {}
    for _, name in ipairs({
        "throwable_find",
        "unit_component_by_key",
        "physics_world_index",
        "avatar_flag_of",
        "avatar_settings_open",
        "unit_node",
        "explosive_data_of",
        "explosive_data_by_key",
        "weapon_data_open",
        "axis_value",
    }) do
        calls[name] = assert(judge:routine(name))
    end
    return setmetatable({
        weapon = weapon,
        n = n,
        read = read,
        judge = judge,
        calls = calls,
        exe = assert(read:module("exe")),
        reach = read:value(weapon.game + n.throw_reach_at, "f32"),
        spawn_reach = read:value(weapon.game + n.spawn_throw_reach_at, "f32"),
        nudge = read:value(weapon.game + n.throw_nudge_scale_at, "f32"),
        degree = read:value(weapon.game + n.throw_degree_at, "f32"),
        energy_scale = read:value(weapon.game + n.throw_energy_scale_at, "f32"),
        motion_calls = {
            resource = assert(judge:routine("physics_resource_by_name")),
            template = assert(judge:routine("physics_template_of")),
        },
        motion_numbers = {
            resource_kind = n.physics_resource_kind,
            actor_block = n.physics_actor_block,
            actor_count = n.physics_actor_count,
            actor_entries = n.physics_actor_entries,
            actor_name = n.physics_actor_name,
            actor_template = n.physics_actor_template,
            next_actor = n.physics_next_actor,
            actor_time = n.physics_actor_time,
            template_motion = n.physics_template_motion,
        },
    }, Launch)
end
function Launch:clear()
    self.key, self.settings, self.ids, self.values, self.kind, self.record = nil, nil, nil, nil, nil, nil
end
function Launch:c4(options)
    if options.row == nil then
        return false
    end
    local n, read, judge = self.n, self.read, self.judge
    local records = read:ptr(options.manager + n.weapon_data_records)
    local record
    if records ~= nil then
        record = read:ptr(records + options.index * n.weapon_data_record_stride)
    end
    if record == nil then
        return false
    end
    local book = judge:call(self.calls.weapon_data_open, record)
    local slot
    if value(read, book, n.weapon_function_left, "u32") == n.weapon_function_detonator then
        slot = n.option_slot_1
    elseif value(read, book, n.weapon_function_right, "u32") == n.weapon_function_detonator then
        slot = n.option_slot_2
    end
    if slot == nil then
        return false
    end
    local mode = judge:call(self.calls.axis_value, options.manager, options.id, slot)
    if mode == n.candidate_none or mode == n.candidate_none % 4294967296 then
        mode = 0
    end
    return mode ~= nil and mode % 2 == 0
end
function Launch:select(key)
    if key == self.key then
        return self.settings
    end
    self.key, self.settings, self.ids = key, nil, nil
    local arg = argument(self.judge, key)
    if arg == nil then
        return
    end
    local settings = self.judge:call(self.calls.throwable_find, arg)
    if settings == nil or settings == 0 then
        return
    end
    self.settings = settings
    local component = self.judge:call(self.calls.unit_component_by_key, arg)
    local name = value(self.read, component, self.n.unit_component_name, "key64")
    if name ~= nil then
        self.ids = Flight.motion_ids(
            self.read,
            self.judge,
            self.motion_calls,
            { name = name, settings = settings },
            self.motion_numbers
        )
    end
    return settings
end
function Launch:observe(inputs, cell, projectile, c4, shooter, fuse)
    self.values, self.kind, self.record = nil, nil, nil
    local read, judge, n, weapon = self.read, self.judge, self.n, self.weapon
    local hand = inputs.holding == true and (inputs.aiming == true or inputs.throwing == true)
    local from_hand = hand or c4 == true
    local key, record, entity
    if hand then
        entity, record = cell, weapon:record(cell)
        key = weapon:key(record)
    elseif c4 then
        key = n.c4_charge_key
    elseif projectile.can_fire == true then
        key = projectile.entity_key
    end
    if key == nil then
        self:clear()
        return
    end
    local settings = self:select(key)
    if settings == nil then
        return
    end
    self.record = record
    local v = {
        thrown = true,
        from_hand = from_hand,
        body_ids = self.ids,
        nudge = self.nudge,
        fixed_speed = value(read, settings, n.throw_fixed_speed_at, "f32"),
    }
    self.values = v
    if inputs.aiming == true and projectile.id ~= nil then
        entity, record = projectile.id, projectile.record
    end
    v.entity, v.unit = entity, value(read, record, n.record_engine_unit, "u32")
    if from_hand then
        v.booster, v.reach = inputs.avatar, self.reach
    else
        v.booster, v.reach, v.aim = projectile.id, self.spawn_reach, projectile:target()
    end
    local config = weapon:manager(n.throwable_manager)
    if config ~= nil then
        config = read:ptr(config)
    end
    v.launch_filter = value(read, config, n.throw_launch_filter_at, "u32")
    local library = read:ptr(self.exe + n.physics_motion_library)
    if library ~= nil then
        v.motions = read:ptr(library + n.physics_motion_rows)
    end
    local world = weapon:manager(n.physics_query_world)
    local index
    if world ~= nil then
        index = judge:call(self.calls.physics_world_index, world)
    end
    if index ~= nil and index ~= weapon.invalid_player then
        local body = read:ptr(self.exe + n.physics_worlds + index * n.physics_world_stride)
        if body ~= nil then
            v.acceleration = read:vector(body + n.physics_gravity_at, 3)
            v.solver_steps = read:value(body + n.physics_steps_at, "u32")
        end
    end
    local explosive
    if self.record ~= nil then
        explosive = judge:call(self.calls.explosive_data_of, self.record)
    end
    if explosive == nil or explosive == 0 then
        explosive = judge:call(self.calls.explosive_data_by_key, argument(judge, key))
    end
    self.kind = value(read, explosive, n.explosive_kind_at, "u32")
    if not from_hand then
        return v
    end
    local short, states = nil, weapon:manager(n.throw_states_manager)
    if states ~= nil then
        short = judge:call(self.calls.avatar_flag_of, states, inputs.avatar, n.throw_short_bit)
    end
    local book
    if inputs.manager ~= nil and inputs.index ~= nil then
        local ref = read:ptr(inputs.manager + n.avatar_settings_slots_at + inputs.index * n.avatar_settings_slot_stride)
        if ref ~= nil then
            book = judge:call(self.calls.avatar_settings_open, ref)
        end
    end
    local angle, power = n.throw_long_angle_at, n.throw_long_power_at
    if short == true then
        angle, power = n.throw_short_angle_at, n.throw_short_power_at
    end
    v.throw_angle, v.throw_power = value(read, book, angle, "f32"), value(read, book, power, "f32")
    v.short_anim = value(read, settings, n.throw_short_anim_at, "u32")
    v.release_anim = v.short_anim
    if short ~= true then
        v.release_anim = value(read, settings, n.throw_long_anim_at, "u32")
    end
    v.move_floor = value(read, settings, n.throw_move_floor_at, "f32")
    v.move_add = value(read, settings, n.throw_move_add_at, "f32")
    v.move_sub = value(read, settings, n.throw_move_sub_at, "f32")
    v.energy_min = value(read, settings, n.throw_energy_min_at, "f32")
    v.energy_max = value(read, settings, n.throw_energy_max_at, "f32")
    v.degree, v.energy_scale = self.degree, self.energy_scale
    local camera = weapon:manager(n.camera_manager)
    if camera ~= nil then
        v.forward = read:vector(camera + n.camera_forward_at, 3)
    end
    if shooter ~= nil then
        v.shoulder_node = judge:call(self.calls.unit_node, shooter, n.shoulder_node_name)
        if c4 then
            v.hand_node = judge:call(self.calls.unit_node, shooter, n.c4_hand_node_name)
        end
    end
    local mover = weapon:manager(n.throw_mover_manager_at)
    if mover ~= nil then
        local slot = weapon:find(mover + n.throw_mover_map, inputs.avatar, weapon.invalid_player)
        local rows
        if slot ~= nil then
            rows = read:ptr(mover + n.throw_mover_rows)
        end
        if rows ~= nil then
            v.motion = read:vector(rows + slot * n.throw_mover_stride + n.throw_mover_velocity, 3)
        end
    end
    if hand then
        v.fuse = fuse
    end
    return v
end
return Launch
