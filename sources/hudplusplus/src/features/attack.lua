local Eagles = require("game.eagles")
local Attackers = require("game.attackers")
local Shells = require("game.shells")
local Flight = require("game.flight")
local Feature = {}
Feature.__index = Feature
function Feature.new(weapon, panel, trajectory, delivery)
    local n, numbers = weapon.n, {}
    for role, name in pairs({
        kind_count = "explosion_kind_count",
        explosion_stride = "explosion_info_stride",
        radius_inner = "explosion_radius_inner",
        radius_outer = "explosion_radius_outer",
        children = "area_children",
        info_stride = "projectile_info_stride",
        info_impact = "projectile_explosion_impact",
        info_expire = "projectile_explosion_expire",
        weapon_type = "projectile_type",
        mode_at = "eagle_mode_at",
        pattern_at = "eagle_pattern_at",
        projectile_at = "eagle_projectile",
        guide_length = "guide_length",
        pattern_mode = "eagle_pattern_bomb_mode",
        strafing_mode = "eagle_strafing_mode",
        degrees = "eagle_degrees",
        pattern_count = "eagle_pattern_count",
        pattern_points = "eagle_pattern_points",
        point_stride = "eagle_pattern_point_stride",
        pattern_stride = "eagle_pattern_stride",
        bomb_projectile = "bombardment_preview_projectile",
        scatter = "bombardment_preview_spread",
        drift = "area_drift",
        shots = "guide_shots",
        salvos = "guide_salvos",
        shot_interval = "guide_shot_interval",
        salvo_interval = "guide_salvo_interval",
        turn = "guide_heading",
        centered = "guide_centered",
    }) do
        numbers[role] = n[name]
    end
    return setmetatable({
        weapon = weapon,
        panel = panel,
        trajectory = trajectory,
        delivery = delivery,
        eagles = Eagles.new(weapon, numbers),
        attackers = Attackers.new(weapon),
        shells = Shells.new(weapon, trajectory),
        numbers = numbers,
        rows = {},
    }, Feature)
end
function Feature:prepare(enabled, inputs)
    if not enabled or not self.panel.ready or inputs.world == nil then
        if self.world ~= nil then
            self:close()
        end
        return false
    end
    if self.world ~= inputs.world then
        self.eagles:clear()
        self.attackers:clear()
        self.shells:clear()
        self.next_at = nil
    end
    self.world = inputs.world
    return self.delivery.entry ~= nil
end
function Feature:observe(mode, dt)
    if self.world == nil then
        return
    end
    self.time = (self.time or 0) + (dt or 0)
    if dt == nil or self.next_at == nil or self.time >= self.next_at or self.mode ~= mode then
        self.eagles:observe(mode)
        self.attackers:observe(self.eagles.keys)
        self.shells:observe(self.attackers.keys, mode, self.world)
        self.next_at = (self.next_at or self.time) + 1 / 30
        if self.next_at <= self.time then
            self.next_at = self.time + 1 / 30
        end
    end
    self.mode = mode
end
function Feature:step(inputs, heading)
    if self.world == nil then
        return
    end
    local weapon, delivery, trajectory = self.weapon, self.delivery, self.trajectory
    local flight, scale, row = trajectory.flight, delivery.scale, nil
    if delivery.entry ~= nil and flight ~= nil and flight.finish ~= nil and scale ~= nil then
        local n = weapon.n
        row = Flight.blast(weapon.read, {
            at = flight,
            explosions = weapon.game + n.explosion_info_table,
            scale_outer = scale.outer,
            scale_inner = scale.inner,
            infos = weapon.game + n.projectile_info_table,
            eagle = delivery.eagle,
            entry_degrees = delivery.degrees,
            bombardment = delivery.bombardment,
            weapon = delivery.weapon_blob,
            patterns = weapon.game + n.eagle_pattern_table,
            heading_degrees = heading,
        }, self.numbers)
        if row ~= nil then
            row.key, row.at = "guide", flight.finish
        end
    end
    local rows = self.rows
    for index = #rows, 1, -1 do
        rows[index] = nil
    end
    if row ~= nil then
        rows[1] = row
    end
    for _, eagle in ipairs(self.eagles.rows) do
        rows[#rows + 1] = eagle
    end
    for _, shell in ipairs(self.shells.rows) do
        rows[#rows + 1] = shell
    end
    if #rows > 0 then
        trajectory:locate(inputs)
    end
end
function Feature:close()
    self.eagles:clear()
    self.attackers:clear()
    self.shells:clear()
    self.world, self.rows, self.time, self.next_at, self.mode = nil, {}, nil, nil, nil
end
return Feature
