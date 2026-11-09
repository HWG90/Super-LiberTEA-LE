local Resources = require("game.resources")
local Pose = require("game.world_pose")
local Gauge = {}
Gauge.__index = Gauge
local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function Gauge.new(ui, inner, side)
    return setmetatable({ ui = ui, inner = inner, side = side, root_place = {}, arc_place = {} }, Gauge)
end
function Gauge:create(parent)
    local ui, n = self.ui, self.ui.n
    ui:context(parent, function()
        self.root = ui:frame(self.root)
        ui:size(self.root, 140, 90)
        ui:opacity(self.root, 0)
        self.arc = ui:frame(self.arc)
        ui:size(self.arc, 0, 0)
        ui:anchor(self.arc, 0.5, 0.5)
        ui:pivot(self.arc, 0.5, 0.5)
        ui:attach(self.root.at, self.arc)
        self.track = ui:image_node(self.track)
        self.fill = ui:image_node(self.fill)
        self.fill.gauge_value = nil
        local prefix = self.inner and "inner_" or "outer_"
        for _, node in ipairs({ self.track, self.fill }) do
            ui:size(node, 96, 96)
            ui:anchor(node, 0.5, 0.5)
            ui:pivot(node, 0.5, 0.5)
            ui:attach(self.arc.at, node)
        end
        ui:material(self.track, Resources[prefix .. "track"])
        ui:material(self.fill, Resources[prefix .. "fill"])
        ui:layer(self.track, n.crosshair_track_layer)
        ui:layer(self.fill, n.crosshair_fill_layer)
        ui:colour(self.track, 0, 0, 0)
        ui:colour(self.fill, 1, 1, 1)
        ui:opacity(self.track, self.inner and 0.4 or 0.5)
        ui:opacity(self.fill, self.inner and 0.8 or 1)
        ui:show(self.track, true)
        ui:attach(parent, self.root)
    end)
    self.parent, self.part, self.start, self.angle = parent, nil, nil, nil
    self.root_place[1], self.root_place[2], self.arc_place[1], self.arc_place[2] = nil, nil, nil, nil
    self.filled, self.lit = false, false
end
function Gauge.toward(layout)
    return DIRECTIONS[layout + 1]
end
function Gauge:shape(layout, span)
    local toward = DIRECTIONS[layout + 1]
    local x, y = self.side * toward[1], self.side * toward[2]
    local centre = x > 0 and 90 or x < 0 and 270 or y > 0 and 0 or 180
    local start, part = (centre - span / 2) % 360, span / 360
    local changed = self.part ~= part or self.start ~= start
    self.part, self.start, self.angle, self.forward, self.toward = part, start, span, y - x > 0, toward
    if changed then
        self.ui:material_scalar(self.track, self.ui.n.gauge_percent_key, part + 2 * 2.864775 / 360)
        self.ui:material_scalar(self.track, self.ui.n.gauge_angle_key, start - 2.864775)
        if self.fill.gauge_value ~= nil then
            self:cut(self.fill, self.fill.gauge_value)
        end
    end
end
function Gauge:cut(node, value)
    local ui = self.ui
    local angle = self.start
    if not self.forward then
        angle = self.start + self.angle - self.angle * value
    end
    ui:material_scalar(node, ui.n.gauge_percent_key, self.part * value)
    ui:material_scalar(node, ui.n.gauge_angle_key, angle)
    node.gauge_value = value
end
function Gauge:paint(node, value, colour)
    local ui = self.ui
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or colour == nil then
        ui:show(node, false)
        node.gauge_value = nil
        return
    end
    self:cut(node, value)
    ui:colour(node, colour[3], colour[2], colour[1])
    ui:show(node, true)
end
function Gauge:put(value, colour)
    self:paint(self.fill, value, colour)
    if self.fill.gauge_value ~= nil then
        self.filled = true
    end
end
local function approach(ui, node, at, x, y, keep, pixel)
    local target_x, target_y = x, y
    if at[1] == nil then
        at[1], at[2] = x, y
    else
        x, y = x + (at[1] - x) * keep, y + (at[2] - y) * keep
        if Pose.near(x - target_x, y - target_y, pixel) then
            x, y = target_x, target_y
        end
    end
    ui:position(node, x, y)
    at[1], at[2] = x, y
end
Gauge.approach = approach
function Gauge.centre(side, toward, fixed, spot)
    if not fixed then
        return 0, 0
    end
    return (side * toward[1] * math.abs(spot[1]) - spot[1]) * 90, side * toward[2] * math.abs(spot[1]) * 90
end
function Gauge:place(fixed, spot, size, gap, keep, pixel)
    local toward = self.toward
    local extent = toward[1] ~= 0 and size[1] or size[2]
    local x, y = Gauge.centre(self.side, toward, fixed, spot)
    approach(self.ui, self.root, self.root_place, x, y, keep, pixel)
    local spread = 0
    if extent > 0 then
        spread = math.max(0, extent / 2 + gap - 30)
    end
    approach(
        self.ui,
        self.arc,
        self.arc_place,
        self.side * toward[1] * spread,
        self.side * toward[2] * spread,
        keep,
        pixel
    )
end
function Gauge:display(awake, idle, full, seconds, dim)
    local shown = awake == true or (awake ~= nil and idle > 0)
    if shown and not self.lit then
        self.ui:opacity(self.root, 0)
    end
    if awake == false and idle == 1 then
        full = full * (dim or 0.3)
    end
    self.ui:fade(self.root, shown, full, seconds)
    self.lit = shown
    if not shown then
        local alpha = self.ui.read:value(self.root.at + self.ui.n.widget_local_opacity, "f32")
        self.lit = alpha ~= nil and alpha > 0
    end
    return self.lit
end
function Gauge:hide()
    if self.root ~= nil and self.root.live then
        self.ui:opacity(self.root, 0)
    end
    self.lit, self.filled = false, false
    self.root_place[1], self.arc_place[1] = nil, nil
end
function Gauge:close()
    self.ui:destroy(self.root)
    self.ui:destroy(self.arc)
    self.ui:destroy(self.track)
    self.ui:destroy(self.fill)
    self.parent, self.lit, self.filled = nil, false, false
end
return Gauge
