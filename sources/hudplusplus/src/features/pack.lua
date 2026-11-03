local Pack = require("game.pack")
local Gauge = require("game.gauge")
local Wake = require("game.wake")
local Feature = {}
Feature.__index = Feature
local WHITE = { 1, 1, 1 }
function Feature.new(ui, weapon)
    return setmetatable(
        { ui = ui, values = Pack.new(weapon), gauge = Gauge.new(ui, true, 1), wake = Wake.new(1), events = {} },
        Feature
    )
end
function Feature:observe(enabled, clock, worn, gauge, hold, keep, wield)
    self.enabled, self.worn, self.wield = enabled, worn, wield
    if not enabled or clock == nil then
        self.wake:clear()
        self.awake = nil
        if not enabled then
            self.gauge:close()
        end
        return
    end
    self.events[1] = gauge
    self.awake = self.wake:step(clock, self.events, self.values.busy == true or keep == true, hold)
end
function Feature:put(parent, values, fixed, spot, size, keep, pixel)
    if not self.enabled then
        return false
    end
    local ui, gauge = self.ui, self.gauge
    if not self.worn or self.values:hides(self.wield) then
        gauge:hide()
        return false
    end
    local alive = ui:alive(gauge.root)
    if alive == nil then
        return false
    end
    if gauge.parent ~= parent or not alive then
        gauge:close()
        gauge:create(parent)
    end
    gauge:shape(values["hud.weapon3d.layout"], values["hud.weapon3d.gauge_angle"])
    if self.awake or not gauge.filled then
        local share = self.values.share
        if share == nil and self.values.left ~= nil then
            share = 1 - self.values.left
        end
        gauge:put(share, WHITE)
        self.has_value = share ~= nil
    end
    if not self.has_value then
        gauge:hide()
        return false
    end
    gauge:place(fixed, spot, size, values["hud.weapon3d.gauge_gap"], keep, pixel)
    return gauge:display(
        self.awake,
        values["hud.world3d.idle"],
        values["hud.weapon3d.opacity"],
        ui.n.widget_fade_seconds[1]
    )
end
function Feature:hide()
    self.gauge:hide()
end
function Feature:close()
    self.gauge:close()
    self.wake:clear()
    self.awake = nil
end
return Feature
