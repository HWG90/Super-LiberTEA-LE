local OptionCell = {}
OptionCell.__index = OptionCell
function OptionCell.new(ui)
    return setmetatable({ ui = ui }, OptionCell)
end
function OptionCell:create(parent, frame, material)
    local ui, n = self.ui, self.ui.n
    self.node = ui:node(n.option_cell_size, self.node)
    local at = self.node.at
    ui:call("option_cell_create", at, n.hud_text_layer, 0)
    ui:size(self.node, 32, 32)
    ui:call("widget_opacity_set", at + n.option_cell_marker, 0)
    ui:call("widget_shown_set", at + n.option_cell_text, 0)
    ui:call("widget_layer_set", at + n.option_cell_picture, n.hud_text_layer)
    ui:call("widget_position_set", at + n.option_cell_picture, ui:pair(0, 0))
    local picture = { at = at + n.option_cell_picture }
    if material ~= nil then
        ui:material(picture, material)
    end
    ui:material_four(picture, n.shadow_color_key, 0.6, 0, 0, 0)
    ui:attach(parent, self.node)
    ui:show(self.node, false)
    self.created, self.valid = frame, false
    self.axis, self.value, self.output, self.alpha = nil, nil, nil, nil
    return self.node
end
function OptionCell:update(frame, axis, value, output)
    local ui, node = self.ui, self.node
    if node == nil or not node.live then
        return
    end
    if axis == nil or value == nil or output == nil then
        ui:show(node, false)
        self.valid = false
        return
    end
    if frame == self.created then
        return
    end
    local changed = not self.valid
        or self.mode ~= nil
        or self.axis ~= axis
        or self.value ~= value
        or self.output ~= output
    if changed then
        ui:show(node, true)
        ui:call("option_cell_fill", node.at, axis, value, 1, assert(ui.port:uint64_of(output)))
        ui:call("widget_position_set", node.at + ui.n.option_cell_picture, ui:pair(0, 0))
    end
    local alpha = ui.read:value(node.at + ui.n.widget_inherited_opacity, "f32")
    if changed or alpha ~= self.alpha then
        ui:call("option_cell_shade", node.at)
    end
    self.valid, self.mode, self.axis, self.value, self.output, self.alpha = true, nil, axis, value, output, alpha
end
function OptionCell:update_fuse(frame, mode, pick, throw_id, seconds)
    local ui, node = self.ui, self.node
    if node == nil or not node.live then
        return
    end
    if mode == nil or pick == nil or throw_id == nil or seconds == nil then
        ui:show(node, false)
        self.valid = false
        return
    end
    if frame == self.created then
        return
    end
    local changed = not self.valid
        or self.axis ~= nil
        or self.mode ~= mode
        or self.pick ~= pick
        or self.throw_id ~= throw_id
        or self.seconds ~= seconds
    if changed then
        ui:show(node, true)
        ui:call("option_cell_fill_fuse", node.at, mode, pick, 1, throw_id, seconds)
        ui:call("widget_position_set", node.at + ui.n.option_cell_picture, ui:pair(0, 0))
    end
    local alpha = ui.read:value(node.at + ui.n.widget_inherited_opacity, "f32")
    if changed or alpha ~= self.alpha then
        ui:call("option_cell_shade", node.at)
    end
    self.valid, self.axis, self.mode, self.pick, self.throw_id, self.seconds, self.alpha =
        true, nil, mode, pick, throw_id, seconds, alpha
end
function OptionCell:close()
    self.ui:destroy(self.node)
    self.valid = false
end
return OptionCell
