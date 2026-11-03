local Feature = {}
Feature.__index = Feature
function Feature.new(ui, panel)
    return setmetatable({ ui = ui, panel = panel }, Feature)
end
function Feature:step(enabled)
    local panel, ui = self.panel, self.ui
    if not enabled or not panel.ready then
        self.last = nil
        return
    end
    local n, read = ui.n, ui.read
    local base = panel.mission + n.hud_widgets_panels_crosshair_at
    if read:value(base + n.crosshair_hit_kind, "i32") ~= n.crosshair_hit_kill_kind then
        self.last = nil
        return
    end
    local clock = read:value(base + n.crosshair_hit_clock, "f32")
    if clock == nil then
        self.last = nil
        return
    end
    local last = self.last
    self.last = clock
    if last ~= nil and clock <= last then
        return
    end
    local at = base + n.crosshair_fixed_at
    ui:slide_scale(at, 1, 1.6, 0)
    ui:slide_scale(at, 1.6, 1, clock)
end
function Feature:close()
    self.last = nil
end
return Feature
