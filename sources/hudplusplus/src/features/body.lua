local Gauge = require("game.gauge")
local Wake = require("game.wake")
local Body = {}
Body.__index = Body
local WHITE = { 1, 1, 1 }
function Body.new(ui, panel)
    local one = ui.read:value(ui.read:module("game") + ui.n.fire_speed_unit, "f32")
    return setmetatable({
        ui = ui,
        panel = panel,
        health = Gauge.new(ui, false, -1),
        stamina = Gauge.new(ui, true, -1),
        one = one,
        health_wake = Wake.new(1),
        stamina_wake = Wake.new(0),
        events = {},
    }, Body)
end
function Body:observe(values, ready, clock, sample, map)
    self.health_on, self.stamina_on = values["hud.weapon3d.health"] == 1, values["hud.weapon3d.stamina"] == 1
    if not self.health_on then
        self.health:close()
    end
    if not self.stamina_on then
        self.stamina:close()
    end
    self.enabled = self.health_on or self.stamina_on
    local health, danger, stamina
    if self.enabled and ready then
        if self.health_on then
            health, danger = sample.health, sample.danger
        end
        if self.stamina_on then
            stamina = sample.stamina
        end
    else
        clock = nil
    end
    local v, hold = self.events, values["hud.world3d.fire_time"]
    v[1] = health
    self.health_awake = self.health_wake:step(clock, v, health ~= nil and (danger == true or map == true), hold)
    self.stamina_awake =
        self.stamina_wake:step(clock, v, stamina ~= nil and self.one ~= nil and stamina < self.one, hold)
    self.level, self.energy = health, stamina
    return self.enabled
end
local function prepare(gauge, ui, parent, layout, angle)
    local alive = ui:alive(gauge.root)
    if alive == nil then
        return false
    end
    if gauge.parent ~= parent or not alive then
        gauge:close()
        gauge:create(parent)
    end
    gauge:shape(layout, angle)
    return true
end
function Body:put(parent, values, fixed, spot, size, keep, pixel)
    local ui, panel, health, stamina = self.ui, self.panel, self.health, self.stamina
    local layout, angle = values["hud.weapon3d.layout"], values["hud.weapon3d.gauge_angle"]
    local idle, full, gap = values["hud.world3d.idle"], values["hud.weapon3d.opacity"], values["hud.weapon3d.gauge_gap"]
    local seconds, lit = ui.n.widget_fade_seconds[1], false
    if self.health_on and prepare(health, ui, parent, layout, angle) then
        if self.health_awake or not health.filled then
            health:put(self.level, panel:health_colour())
        end
        health:place(fixed, spot, size, gap, keep, pixel)
        lit = health:display(self.health_awake, idle, full, seconds) or lit
    end
    if self.stamina_on and prepare(stamina, ui, parent, layout, angle) then
        if self.stamina_awake or not stamina.filled then
            stamina:put(self.energy, WHITE)
        end
        stamina:place(fixed, spot, size, gap, keep, pixel)
        lit = stamina:display(self.stamina_awake, idle, full, seconds) or lit
    end
    return lit
end
function Body:hide()
    self.health:hide()
    self.stamina:hide()
end
function Body:close()
    self.health:close()
    self.stamina:close()
    self.health_wake:clear()
    self.stamina_wake:clear()
end
return Body
