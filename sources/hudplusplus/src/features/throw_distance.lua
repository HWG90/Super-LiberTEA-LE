local Point = require("game.screen_point")
local Feature = {}
Feature.__index = Feature
function Feature.new(ui, judge, panel, trajectory, view)
    return setmetatable(
        { ui = ui, panel = panel, trajectory = trajectory, view = view, point = Point.new(judge, ui.n) },
        Feature
    )
end
function Feature:close()
    self.ui:destroy(self.root)
    if self.label ~= nil then
        self.label.live, self.label.text, self.label.shown = false, nil, nil
    end
    self.parent = nil
end
function Feature:step(values)
    local ui, panel, source, n = self.ui, self.panel, self.trajectory, self.ui.n
    if values["hud.throw_distance"] ~= 1 or not panel.ready then
        self:close()
        return
    end
    local flight = source.flight
    local x, y, count
    if source.from_hand == true and flight ~= nil and flight.distance ~= nil then
        x, y = self.point:project(self.view.camera, flight.finish)
        count = math.floor(flight.distance)
    end
    if x == nil then
        if ui:alive(self.root) then
            ui:show(self.root, false)
        end
        return
    end
    local parent = panel.mission - n.hud_widgets_mission_hud + n.hud_marker_layer
    if self.parent ~= parent or ui:alive(self.root) ~= true then
        self:close()
        ui:context(parent, function()
            self.root = ui:frame(self.root)
            ui:size(self.root, 0, 0)
            ui:attach(parent, self.root)
            self.label = ui:label_node(
                n.ping_distance_font,
                n.world_text_flat,
                n.world_text_style,
                n.ping_distance_template,
                self.label
            )
            ui:attach(self.root.at, self.label)
            ui:anchor(self.label, 0.5, 0.5)
            ui:pivot(self.label, 0.5, 0.5)
            ui:position(self.label, 0, -30)
            ui:layer(self.label, n.ping_distance_layer)
            ui:colour(self.label, 1, 1, 1)
        end)
        self.parent = parent
    end
    ui:position(self.root, x, y)
    ui:number(self.label, n.ping_distance_count_arg, count)
    ui:show(self.root, true)
end
return Feature
