local Projectile = require("game.projectile")
local Launch = require("game.throw_launch")
local Flight = require("game.flight")
local Feature = {}
Feature.__index = Feature
local HOLD = 0.2
local WHITE, YELLOW, BLACK = 16777215, 255 * 65536 + 255 * 256, 0
local FOE = require("game.resources").decal.foe_colour % 16777216
function Feature.new(weapon, equipment, panel)
    local n, judge, read = weapon.n, weapon.judge, weapon.read
    local calls = {}
    for role, name in pairs({
        boost = "throw_boost_apply",
        muzzle = "muzzle_node_of",
        position = "unit_world_position",
        velocity = "shooter_velocity_of",
        step = "projectile_flight_step",
        ray = "world_raycast",
        tree_valid = "speedtree_valid",
        tree_type = "speedtree_type",
        shield = "shield_blocks",
        entity_of = "entity_of_unit",
        hostile = "hostile_of",
        dead = "dead_of",
    }) do
        calls[role] = assert(judge:routine(name))
    end
    local constants = {}
    for role, name in pairs({
        one = "fire_speed_unit",
        caliber_scale = "projectile_caliber_scale",
        drag_area = "projectile_drag_area",
        drag_air = "projectile_drag_air",
        mass_scale = "projectile_mass_scale",
        limit = "projectile_distance_limit",
        floor = "projectile_speed_floor",
        lift = "impact_lift_at",
    }) do
        constants[role] = read:value(weapon.game + n[name], "f32")
    end
    constants.no_entity = read:value(weapon.game + n.entity_none_at, "u32")
    local numbers = {
        inherit_mask = n.projectile_inherit_mask,
        motion_stride = n.physics_motion_stride,
        motion_gravity = n.physics_motion_gravity,
        motion_speed = n.physics_motion_speed,
        motion_damping = n.physics_motion_damping,
        path_bit = n.projectile_path_filter_bit,
        filter_default = n.projectile_filter_default,
        filter_base = n.projectile_filter_base,
        velocity = n.projectile_record_velocity,
        hits = n.projectile_path_hits,
        hit_stride = n.raycast_hit_stride,
        record_at = n.hit_record_at,
        flags_at = n.hit_record_flags_at,
        unit_at = n.hit_record_unit_at,
        normal_at = n.hit_record_normal_at,
        material_at = n.hit_record_material_at,
        tree_flag = n.speedtree_hit_flag,
        near_miss = n.near_miss_material,
        skip_material = n.skip_hit_material,
        shield = n.shield_material,
        tree_stride = n.speedtree_pass_stride,
        tree_count = n.speedtree_pass_count,
        tree_value = n.speedtree_pass_value,
        tree_keep = n.speedtree_pass_keep,
        tree_low = n.speedtree_pass_low,
        tree_high = n.speedtree_pass_high,
        release_delay = n.throw_release_delay_bits,
        water = n.water_material,
    }
    return setmetatable({
        weapon = weapon,
        equipment = equipment,
        panel = panel,
        read = read,
        judge = judge,
        n = n,
        projectile = Projectile.new(weapon),
        launch = Launch.new(weapon),
        calls = calls,
        constants = constants,
        numbers = numbers,
        state = {},
        request = {},
        modifier = assert(judge:routine("explosion_modifier_of")),
        blast_numbers = {
            kind_count = n.explosion_kind_count,
            explosion_stride = n.explosion_info_stride,
            radius_inner = n.explosion_radius_inner,
            radius_outer = n.explosion_radius_outer,
        },
    }, Feature)
end
function Feature:draws(values)
    return values["hud.trajectory"] ~= 0 or values["hud.impact_marker"] ~= 0
end
function Feature:wanted(values)
    return self:draws(values) or values["hud.throw_distance"] == 1
end
function Feature:awake(inputs)
    return inputs.aiming == true or inputs.holding == true
end
function Feature:predict(inputs, fuse, mode, mark)
    local weapon, read, judge, n, equipment = self.weapon, self.read, self.judge, self.n, self.equipment
    local projectile, launch = self.projectile, self.launch
    if inputs.switching == true then
        projectile:clear()
        launch:clear()
        return
    end
    projectile:observe(inputs.aiming, equipment.fire, equipment.fire_record, equipment.charge)
    local c4 = inputs.aiming == true and projectile.blob == nil and launch:c4(equipment.options)
    local shooter_record = weapon:record(inputs.avatar)
    local shooter
    if shooter_record ~= nil then
        shooter = read:value(shooter_record + n.record_engine_unit, "u32")
    end
    local v = launch:observe(inputs, equipment.cell, projectile, c4, shooter, fuse)
    if projectile.flies then
        v = v or {}
        local info = projectile:details()
        v.mass, v.drag, v.gravity, v.substeps, v.life = info.mass, info.drag, info.gravity, info.substeps, info.life
        v.caliber, v.arming, v.flags, v.filter = info.caliber, info.arming, info.flags, info.filter
        v.explode_angle, v.ricochets, v.ricochet_angle, v.ricochet_speed =
            info.explode_angle, info.ricochets, info.ricochet_angle, info.ricochet_speed
        v.entity, v.unit = projectile.id, read:value(projectile.record + n.record_engine_unit, "u32")
        v.info, v.speed, v.scale, v.aim = projectile.info, projectile.speed, projectile.scale, projectile.aim
        v.impact = projectile.projectile.impact
    end
    if v == nil then
        return
    end
    self.from_hand = v.from_hand
    local system = weapon:manager(n.projectile_system)
    if system ~= nil then
        v.filters = read:ptr(system + n.projectile_filter_table)
    end
    v.world, v.eye, v.shooter, v.shooter_id = self.world, inputs.eye, shooter, inputs.avatar
    v.dt, v.trees, v.mark = self.panel.dt, weapon.game + n.speedtree_pass_table, mark
    if mark then
        v.factions, v.health = weapon:manager(n.faction_manager), weapon:manager(n.health_manager)
        if v.factions ~= nil then
            v.faction = weapon:find(v.factions + n.faction_map, inputs.avatar, weapon.invalid_player)
        end
    end
    local k = self.constants
    v.one, v.caliber_scale, v.drag_area, v.drag_air = k.one, k.caliber_scale, k.drag_area, k.drag_air
    v.mass_scale, v.limit, v.floor, v.lift, v.no_entity = k.mass_scale, k.limit, k.floor, k.lift, k.no_entity
    if
        v.entity == nil
        or v.unit == nil
        or v.shooter == nil
        or v.dt == nil
        or v.filters == nil
        or v.world == nil
        or (mark and (v.factions == nil or v.health == nil))
        or k.one == nil
        or k.caliber_scale == nil
        or k.drag_area == nil
        or k.drag_air == nil
        or k.mass_scale == nil
        or k.limit == nil
        or k.floor == nil
        or k.no_entity == nil
    then
        return
    end
    local path
    if mode == 1 or mode == 2 then
        path = self.state.path or {}
        self.state.path = path
    end
    local flight = Flight.predict(read, judge, self.calls, self.state, v, self.numbers, path)
    if flight == nil or flight.finish == nil then
        return flight
    end
    local blast
    if mode == 1 or mode == 3 then
        local book = weapon:manager(n.explosion_modifier_table)
        local cause = v.entity
        if c4 then
            cause = weapon.invalid_entity
        end
        if book ~= nil then
            local outer = judge:call(self.modifier, book, cause, n.explosion_scale_key)
            local inner = judge:call(self.modifier, book, cause, n.explosion_inner_scale_key)
            local impact, expire = launch.kind, launch.kind
            if projectile.flies then
                impact, expire = projectile.projectile.impact, projectile.projectile.expire
            end
            if outer ~= nil and inner ~= nil then
                blast = Flight.blast(read, {
                    at = flight,
                    explosions = weapon.game + n.explosion_info_table,
                    impact = impact,
                    expire = expire,
                    scale_outer = outer,
                    scale_inner = inner,
                }, self.blast_numbers)
            end
        end
    end
    return flight, blast, shooter
end
function Feature:locate(inputs)
    if self.observer ~= nil then
        return
    end
    local shooter = self.shooter
    if shooter == nil then
        local record = self.weapon:record(inputs.avatar)
        if record ~= nil then
            shooter = self.read:value(record + self.n.record_engine_unit, "u32")
        end
    end
    if shooter ~= nil and shooter > 0 then
        local at = self.judge:call(self.calls.position, shooter, 0)
        if at ~= nil and at ~= 0 then
            self.observer = self.read:vector(at, 3)
        end
    end
end
function Feature:step(values, inputs, fuse, guide, clock)
    local mode, marker = values["hud.trajectory"], values["hud.impact_marker"]
    self.from_hand, self.observer, self.shooter = nil, nil, nil
    if (not self:wanted(values) and not guide) or not self.panel.ready then
        self:close()
        return
    end
    local world = inputs.world
    if self.world ~= world then
        self.state, self.bounced = {}, nil
        self.projectile:clear()
        self.launch:clear()
    end
    self.world = world
    local flight, blast, shooter
    if world ~= nil and self:awake(inputs) then
        flight, blast, shooter = self:predict(inputs, fuse, mode, marker ~= 0)
    else
        self.projectile:clear()
        self.launch:clear()
        self.state = {}
    end
    self.flight = flight
    self.shooter = shooter
    if shooter ~= nil and (mode == 1 or mode == 3) then
        self:locate(inputs)
    end
    self.row, self.shot = nil, nil
    if not self:draws(values) then
        self.bounced = nil
        return
    end
    if flight == nil or flight.finish == nil then
        return
    end
    local now = flight.bounce == true
    if
        self.bounced == nil
        or now == self.bounced
        or (clock ~= nil and self.agreed ~= nil and clock - self.agreed >= HOLD)
    then
        self.bounced, self.agreed = now, clock
    end
    if mode == 1 or mode == 3 then
        local row = not self.bounced and blast or {}
        row.key, row.at = "shot", flight.finish
        self.row = row
    end
    local shot, alpha = self.request, math.floor(values["hud.trajectory.line_alpha"]) * 16777216
    shot.at, shot.normal, shot.style = flight.finish, flight.normal, marker - 1
    shot.colour, shot.edge = alpha + WHITE, alpha + BLACK
    shot.path = flight.path
    shot.mark = marker ~= 0
            and flight.seen == true
            and alpha + (self.bounced and YELLOW or flight.foe == true and FOE or WHITE)
        or nil
    self.shot = shot
end
function Feature:close()
    self.projectile:clear()
    self.launch:clear()
    self.world, self.flight, self.from_hand, self.observer, self.row, self.shot, self.state =
        nil, nil, nil, nil, nil, nil, {}
    self.shooter, self.bounced, self.agreed = nil, nil, nil
end
return Feature
