local Stage = require("game.world_stage")
local Body = require("features.body")
local Stratagem = require("features.stratagem")
local Pack = require("features.pack")
local Weapon3d = require("features.weapon_3d")
local Cooldown = require("features.stratagem_cooldown")
local Pose = require("game.world_pose")
local Hud = {}
Hud.__index = Hud
local CENTRE = { 0, 0 }
local NONE = { 0, 0 }
function Hud.new(ui, port, panel, weapon, equipment, inputs, extension, pick)
    local stage = Stage.new(ui, port, { 140, 90 })
    local stratagem, pack = Stratagem.new(ui, panel, weapon, pick), Pack.new(ui, weapon)
    return setmetatable({
        stage = stage,
        panel = panel,
        weapon = weapon,
        inputs = inputs,
        body = Body.new(ui, panel),
        pack = pack,
        extension = extension,
        cooldown = Cooldown.new(ui, panel, stratagem.inputs),
        equipment = equipment,
        weapon_view = Weapon3d.new(ui, panel, weapon, equipment, pack.values),
        stratagem = stratagem,
        stratagem_rack = stage:rack({ 140, 90 }),
        sequence = 0,
        hand = stage:rack({ 140, 90 }),
        frame = {},
        placement = {},
        spread = {},
        stratagem_spread = {},
        listing = { offset = {} },
        icon = { offset = {} },
        aim = { offset = {} },
        aim_body = { offset = {} },
        rest = { offset = {} },
    }, Hud)
end
local function scene_config(scene, values, name)
    local prefix = "hud.world3d." .. name
    scene.offset[1], scene.offset[2] = values[prefix .. "_x"], values[prefix .. "_y"]
    scene.radius, scene.tau, scene.ceiling =
        values[prefix .. "_radius"], values[prefix .. "_tau"], values[prefix .. "_ceiling"]
end
function Hud:configure(values)
    if self.values == values then
        return
    end
    self.values = values
    self.panel:configure(values)
    scene_config(self.aim, values, "aim")
    scene_config(self.aim_body, values, "aim_body")
    scene_config(self.rest, values, "weapon")
    scene_config(self.listing, values, "stratagem")
    scene_config(self.icon, values, "stratagem_icon")
    self.spread[1], self.spread[2] = values["hud.world3d.screen_x"], values["hud.world3d.screen_y"]
    self.stratagem_spread[1], self.stratagem_spread[2] =
        values["hud.world3d.stratagem_screen_x"], values["hud.world3d.stratagem_screen_y"]
    self.frame.share = 0.14 * values["hud.world3d.size"]
    self.frame.mix, self.frame.cap = values["hud.world3d.tilt_mix"], values["hud.world3d.tilt_cap"]
end
function Hud:wanted(values)
    return values["hud.weapon3d.health"] == 1
        or values["hud.weapon3d.stamina"] == 1
        or values["hud.weapon3d.pack"] == 1
        or values["hud.weapon3d.cooldown"] == 1
        or self.weapon_view:wanted(values)
        or values["hud.stratagem3d"] == 1
        or self.extension.wanted
end
function Hud:hide_hand()
    self.body:hide()
    self.pack:hide()
    self.weapon_view:hide()
    self.cooldown:hide()
end
function Hud:hide()
    self:hide_hand()
    self.stratagem:hide()
    self.extension.hide()
end
function Hud:begin(values)
    self.sequence = self.sequence + 1
    self:configure(values)
    self.ready, self.clock, self.hand_ready, self.content_due = nil, nil, false, false
    if self:wanted(values) then
        self.ready = self.inputs.ready
    end
    if self.ready then
        self.clock = self.panel:clock()
    end
    self.ball_needed = self.stratagem:prepare(
        values["hud.stratagem3d"] == 1,
        self.inputs,
        self.extension.wanted,
        values["hud.weapon3d.cooldown"] == 1
    )
    local weapon = self.ready and self.weapon_view:wanted(values)
    local centre = self.ready
        and values["hud.world3d.lock"] == 1
        and (
            values["hud.weapon3d.health"] == 1
            or values["hud.weapon3d.stamina"] == 1
            or values["hud.weapon3d.pack"] == 1
        )
    return weapon, weapon or centre
end
function Hud:prepare(values, avatar, seated, seat_row, wield, player, players, reloading, slots, sample)
    local stage, inputs, body, panel = self.stage, self.inputs, self.body, self.panel
    if not panel.editable then
        self:close()
        return
    end
    local alive = stage.ui:alive(stage.root)
    if alive == nil then
        return
    end
    if not alive then
        self:close()
    end
    local ready, clock = self.ready, self.clock
    local pack_on = values["hud.weapon3d.pack"] == 1
    local weapon_on = self.weapon_view:wanted(values)
    local worn, drawn, spare, wield_record, key
    local pack_needed = pack_on or (weapon_on and values["hud.weapon3d.reserve"] == 1)
    local health_on = values["hud.weapon3d.health"] == 1
    local map
    if ready and (health_on or weapon_on or pack_on) then
        map = self.weapon:map_open(panel.mission - panel.n.hud_widgets_mission_hud)
    end
    local body_on = body:observe(values, ready, clock, sample, map)
    if ready and pack_needed then
        worn, drawn, spare = sample.worn, sample.gauge, sample.spare
    end
    if ready and (weapon_on or inputs.aiming == true or (pack_needed and not spare)) then
        wield_record = self.equipment.record
        if wield_record == nil and not weapon_on then
            wield_record = self.weapon:record(wield)
        end
    end
    if pack_needed and not spare then
        key = self.weapon:key(wield_record)
    end
    local ammo_shown = values["hud.weapon3d.ammo"] == 1 or values["hud.weapon3d.arc"] == 1
    if ready and pack_needed then
        self.pack.values:observe(avatar, key, spare, worn, drawn, values["hud.weapon3d.reserve"] == 1)
    end
    self.pack:observe(
        pack_on,
        clock,
        worn,
        drawn,
        values["hud.world3d.fire_time"],
        map == true or (sample ~= nil and sample.pack_low == true),
        ammo_shown and wield or nil
    )
    self.weapon_view:observe(values, ready, clock, inputs, sample, slots, reloading, map)
    local showing = self.stratagem:observe(
        values["hud.stratagem3d"] == 1,
        inputs,
        player,
        players,
        self.extension.wanted,
        self.equipment.cell
    )
    if not showing or not self.extension.wanted or self.stratagem.inputs.listing then
        self.extension.close()
    end
    local cooldown_on =
        self.cooldown:observe(values, ready, clock, avatar, players, self.stratagem.inputs.listing == true)
    if not body_on and not pack_on and not weapon_on and not cooldown_on and not showing then
        if stage.root ~= nil then
            stage:close()
        end
        return
    end
    inputs:place(panel, seated, seat_row, wield, wield_record, reloading)
    if not stage:prepare(panel) then
        self:hide()
        return
    end
    if not ready or inputs.clear ~= true then
        self:hide()
        stage:hide()
        stage:submit(panel.dt)
        return
    end
    local lock = values["hud.world3d.lock"]
    local fixed = lock ~= 0 or inputs.pinned == true
    self.frame.fixed = fixed
    if not stage:place(self.frame, inputs.body, true) then
        self:hide()
        stage:submit(panel.dt)
        return
    end
    if showing then
        local scene = self.stratagem.inputs.listing and self.listing or self.icon
        local placement = self.placement
        placement.fixed, placement.offset, placement.scene, placement.dt =
            fixed, fixed and self.stratagem_spread or scene.offset, scene, panel.dt
        if stage:place_rack(self.stratagem_rack, placement, inputs.anchor, inputs.anchor_node) then
            if values["hud.stratagem3d"] == 1 then
                self.stratagem:put(self.stratagem_rack.node.at, self.sequence, values)
            end
            if self.extension.wanted and not self.stratagem.inputs.listing then
                self.extension.put(self.stratagem_rack.node.at, self.sequence)
            end
        else
            self.stratagem:hide()
            self.extension.hide()
        end
    else
        stage:hide_rack(self.stratagem_rack)
    end
    if showing and values["hud.stratagem3d"] == 1 then
        self:hide_hand()
        stage:hide_rack(self.hand)
        stage:submit(panel.dt)
        return
    end
    local scene = self.rest
    if inputs.fire_found == true then
        scene = self.aim
    elseif inputs.aiming == true then
        scene = self.aim_body
    end
    local spot = scene.offset
    if fixed then
        spot = CENTRE
        if inputs.pinned == true or lock == 2 or inputs.engaged == true then
            spot = self.spread
        end
    end
    local placement = self.placement
    placement.fixed, placement.offset, placement.scene, placement.dt = fixed, spot, scene, panel.dt
    if stage:place_rack(self.hand, placement, inputs.anchor, inputs.anchor_node) then
        self.hand_ready = true
        self.content_due = self.weapon_view:prepare(self.hand.node.at, self.sequence, values)
        return self.content_due
    else
        self:hide_hand()
    end
    stage:submit(panel.dt)
end
function Hud:finish(values)
    if not self.hand_ready then
        return
    end
    local placement, stage, hand = self.placement, self.stage, self.hand.node.at
    local fixed, spot = placement.fixed, placement.offset
    local keep, pixel = Pose.keep(placement.scene.tau, self.panel.dt), stage.pose:pixel()
    local weapon_lit, size = false, NONE
    if self.content_due ~= nil then
        weapon_lit, size = self.weapon_view:put(self.sequence, values, fixed, spot, keep, pixel, self.content_due)
    end
    local body_lit = self.body:put(hand, values, fixed, spot, size, keep, pixel)
    local pack_lit = self.pack:put(hand, values, fixed, spot, size, keep, pixel)
    local cooldown_lit = self.cooldown:put(hand, self.sequence, values, fixed, spot, size, keep, pixel)
    if not weapon_lit and not body_lit and not pack_lit and not cooldown_lit then
        stage:hide_rack(self.hand)
    end
    stage:submit(self.panel.dt)
end
function Hud:close()
    self.extension.close()
    self.stratagem:close()
    self.weapon_view:close()
    self.body:close()
    self.pack:close()
    self.cooldown:close()
    self.stage:close()
end
return Hud
