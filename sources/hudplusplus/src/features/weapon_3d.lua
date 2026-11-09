local Display = require("game.weapon_panel")
local Wake = require("game.wake")
local Reload = require("game.reload")
local Cycle = require("game.weapon_cycle")
local Feature = {}
Feature.__index = Feature
local NONE = { 0, 0 }
function Feature.new(ui, panel, weapon, equipment, pack)
    return setmetatable({
        ui = ui,
        panel = panel,
        weapon = weapon,
        equipment = equipment,
        pack = pack,
        display = Display.new(ui),
        wake = Wake.new(11),
        reload = Reload.new(weapon),
        cycle = Cycle.new(weapon),
        events = {},
        sample = { slots = { {}, {}, {} } },
    }, Feature)
end
local function shown_reserve(ammo, pack)
    if ammo.throwing then
        return nil
    end
    if ammo.reserve ~= nil then
        return ammo.reserve
    end
    return pack.remaining
end
function Feature:wanted(values)
    return values["hud.weapon3d.ammo"] == 1
        or values["hud.weapon3d.reserve"] == 1
        or values["hud.weapon3d.throwables"] == 1
        or values["hud.weapon3d.stims"] == 1
        or values["hud.weapon3d.functions"] == 1
        or values["hud.weapon3d.fire_mode"] == 1
        or values["hud.weapon3d.zeroing"] == 1
        or values["hud.weapon3d.arc"] == 1
end
function Feature:observe(values, ready, clock, inputs, sample, slots, reloading, map)
    self.enabled, self.ammo, self.awake = self:wanted(values), nil, nil
    if not self.enabled or not ready then
        self.wake:clear()
        self.reload:clear()
        if not self.enabled then
            self.display:close()
        end
        return
    end
    local panel, read, n = self.panel, self.weapon.read, self.weapon.n
    local equipment = self.equipment
    local ammo = sample.ammo
    self.ammo = ammo
    local count_on, reserve_on, arc_on =
        values["hud.weapon3d.ammo"] == 1, values["hud.weapon3d.reserve"] == 1, values["hud.weapon3d.arc"] == 1
    local throwables_on, stims_on, functions_on =
        values["hud.weapon3d.throwables"] == 1, values["hud.weapon3d.stims"] == 1, values["hud.weapon3d.functions"] == 1
    local mode_on, zero_on = values["hud.weapon3d.fire_mode"] == 1, values["hud.weapon3d.zeroing"] == 1
    local v = self.events
    for index = 1, 11 do
        v[index] = nil
    end
    if count_on or reserve_on or arc_on then
        v[1] = read:value(panel.base + n.self_panel_weapon_picture, "hex64")
    end
    if reserve_on then
        v[2] = shown_reserve(ammo, self.pack)
    end
    if count_on then
        v[3] = ammo.text
    end
    if functions_on then
        v[4], v[9] = slots[1][2], equipment.throwable.fuse_choice
    end
    if mode_on then
        v[5] = slots[2][2]
    end
    if zero_on then
        v[6] = slots[3][2]
    end
    if count_on or reserve_on or arc_on or throwables_on or functions_on or mode_on or zero_on then
        v[7] = equipment.wield
    end
    if stims_on then
        v[8] = ammo.stims
    end
    if arc_on then
        v[10] = ammo.drawn
    end
    if throwables_on then
        v[11] = ammo.throwables_unheld
    end
    local held = inputs.engaged == true
        or equipment.charge.charging == true
        or reloading == true
        or map == true
        or (ammo.magazine_low == true and (count_on or arc_on))
        or (ammo.reserve_low == true and reserve_on)
    self.awake = self.wake:step(clock, v, held, values["hud.world3d.fire_time"])
end
function Feature:prepare(parent, frame, values)
    if not self.enabled then
        return false
    end
    local display = self.display
    local alive = self.ui:alive(display.gauge.root)
    if alive == nil then
        return nil
    end
    if not alive or display.parent ~= parent or display.values ~= values then
        display:close()
        display:create(parent, frame, values)
    end
    return self.awake == true or not display.filled
end
function Feature:content(values, inputs, picked, record, ammo, slots, fuse, reloading)
    local sample, panel, weapon = self.sample, self.panel, self.weapon
    local equipment = self.equipment
    local charge, throwable = equipment.charge, equipment.throwable
    sample.ammo, sample.reserve = ammo.text, shown_reserve(ammo, self.pack)
    sample.throwables, sample.stims = ammo.throwables_unheld, ammo.stims
    sample.wielded = equipment.wield ~= nil and equipment.wield == picked
    for index = 1, 3 do
        sample.slots[index][1], sample.slots[index][2], sample.slots[index][3] = unpack(slots[index], 1, 3)
    end
    sample.fuse = throwable
    sample.style = nil
    if
        values["hud.weapon3d.ammo"] == 1
        or values["hud.weapon3d.arc"] == 1
        or values["hud.weapon3d.reserve"] == 1
        or values["hud.weapon3d.throwables"] == 1
        or values["hud.weapon3d.stims"] == 1
    then
        sample.style = panel:style(ammo.throwing, ammo.reserve ~= nil)
    end
    sample.outline, sample.fill, sample.magazine_size = nil, nil, nil
    if values["hud.weapon3d.reserve"] == 1 and sample.reserve ~= nil then
        sample.outline, sample.fill = weapon:ammo_icons(record)
        sample.magazine_size = panel:magazine_size()
    end
    sample.throwable_icon, sample.throwable_size = nil, nil
    if values["hud.weapon3d.throwables"] == 1 and sample.throwables ~= nil then
        sample.throwable_icon, sample.throwable_size = panel:throwable_icon()
    end
    if values["hud.weapon3d.functions"] == 1 then
        throwable:wheel(equipment.wield)
    end
    sample.empty, sample.progress, sample.cycle, sample.charge, sample.ready = nil, nil, nil, nil, nil
    if values["hud.weapon3d.arc"] == 1 then
        self.reload:observe(inputs.avatar, equipment.fire, equipment.fire_record, self.pack.remaining, reloading)
        self.cycle:shot(equipment.fire, ammo.hidden, equipment.fire_count, charge.index)
        sample.progress = self.reload.share
        if sample.progress == nil then
            throwable:progress(inputs.avatar, equipment.cell, equipment.inventory, ammo.throwing, ammo.throwables, fuse)
            sample.progress = throwable.share
        end
        if sample.progress == nil then
            self.cycle:melee(inputs.avatar, equipment.avatar_row, inputs.melee, ammo.hidden, equipment.fire_count)
            sample.progress = self.cycle.progress
        end
        sample.cycle, sample.charge, sample.ready = self.cycle.left, charge.share, charge.ready_share
        if
            self.reload.share == nil
            and charge.share == nil
            and charge.charging ~= true
            and not ammo.throwing
            and picked ~= nil
        then
            sample.empty = ammo.empty
        end
    else
        self.reload:clear()
    end
end
function Feature:put(frame, values, fixed, spot, keep, pixel, changed)
    if not self.enabled or self.display.parent == nil then
        return false, NONE
    end
    local display = self.display
    if changed then
        display:put(frame, self.sample)
    else
        display:update(frame)
    end
    display.gauge:place(fixed, spot, display.size, values["hud.weapon3d.gauge_gap"], keep, pixel)
    return display.gauge:display(
        self.awake,
        values["hud.world3d.idle"],
        values["hud.weapon3d.opacity"],
        self.ui.n.widget_fade_seconds[1]
    ),
        display.size
end
function Feature:hide()
    self.display:hide()
end
function Feature:close()
    self.display:close()
    self.wake:clear()
    self.reload:clear()
end
return Feature
