local Layout = require("game.layout")
local OptionCell = require("game.option_cell")
local Line = {}
Line.__index = Line
function Line.new(ui)
    return setmetatable({
        ui = ui,
        layout = Layout.new(ui),
        text_layout = Layout.new(ui),
        function_cell = OptionCell.new(ui),
        fire_cell = OptionCell.new(ui),
        zero_cell = OptionCell.new(ui),
        function_layout = Layout.new(ui),
        icons_layout = Layout.new(ui),
        fire_layout = Layout.new(ui),
        zero_layout = Layout.new(ui),
    }, Line)
end
function Line:create(parent, row, frame, ammo, functions, fire_mode, zeroing)
    local ui, n = self.ui, self.ui.n
    ui:context(parent, function()
        if ammo or functions then
            self.root = ui:frame(self.root)
            ui:size(self.root, 0, 0)
            ui:anchor(self.root, 1, 0.5)
            ui:position(self.root, 6, 0)
            self.line = ui:frame(self.line)
            ui:size(self.line, 0, 0)
            ui:anchor(self.line, 0, 0)
            ui:pivot(self.line, 0, 0.5)
            ui:attach(self.root.at, self.line)
            self.layout:create(self.line, n.layout_right)
            if ammo then
                self.text = ui:text_node(n.hud_text_font, n.hud_text_variant, n.hud_text_variant, nil, self.text)
                ui:layer(self.text, n.hud_text_layer)
                ui:attach(self.line.at, self.text)
                self.text_layout:create(self.text, 0, 8, n.layout_right)
                self.layout:add(self.text_layout)
                ui:call("measure_widget", self.text.at)
            end
            if functions then
                local node = self.function_cell:create(self.line.at, frame, n.option_cell_picture_curved)
                self.function_layout:create(node, 0, 8, n.layout_right)
                self.layout:add(self.function_layout)
            end
            ui:attach(parent, self.root)
        end
        if fire_mode or zeroing then
            self.icons = ui:frame(self.icons)
            ui:size(self.icons, 0, 0)
            ui:anchor(self.icons, 1, 0.5)
            ui:pivot(self.icons, 0, 0.5)
            self.icons_layout:create(self.icons, n.layout_right, nil, nil, 6)
            if fire_mode then
                local node = self.fire_cell:create(self.icons.at, frame, n.option_cell_picture_curved)
                self.fire_layout:create(node, 0, 8, n.layout_right)
                self.icons_layout:add(self.fire_layout)
            end
            if zeroing then
                local node = self.zero_cell:create(self.icons.at, frame, n.option_cell_picture_curved)
                self.zero_layout:create(node, 0, 8, n.layout_right)
                self.icons_layout:add(self.zero_layout)
            end
            ui:attach(row, self.icons)
        end
    end)
    self.parent, self.row = parent, row
end
function Line:alive()
    if self.parent == nil then
        return false
    end
    if self.root ~= nil and self.root.live then
        local alive = self.ui:alive(self.root)
        if alive ~= true then
            return alive
        end
    end
    if self.icons ~= nil and self.icons.live then
        return self.ui:alive(self.icons)
    end
    return true
end
function Line:put(value)
    self.ui:text(self.text, value)
end
function Line:show(shown)
    if self.root ~= nil and self.root.live then
        self.ui:show(self.root, shown)
    end
    if self.icons ~= nil and self.icons.live then
        self.ui:show(self.icons, shown)
    end
    if not shown then
        self.function_cell:update(0)
        self.fire_cell:update(0)
        self.zero_cell:update(0)
    end
end
function Line:update(frame, values)
    self.function_cell:update(frame, unpack(values[1], 1, 3))
    self.fire_cell:update(frame, unpack(values[2], 1, 3))
    self.zero_cell:update(frame, unpack(values[3], 1, 3))
    if self.icons ~= nil and self.icons.live then
        self.icons_layout:place()
    end
end
function Line:extend(row, block)
    local ui, read, n = self.ui, self.ui.read, self.ui.n
    if self.line == nil or not self.line.live then
        return false
    end
    self.layout:place()
    if read:ptr(block + n.widget_parent) ~= row or read:ptr(self.root.at + n.widget_parent) ~= block then
        error("weapon-line-parent", 0)
    end
    local position = read:vector(block + n.widget_local_position, 2)
    local tail = read:vector(block + n.widget_local_size, 2)
    local factor = read:vector(block + n.widget_size_factor, 2)
    local content = read:vector(self.line.at + n.widget_local_size, 2)
    local parent = read:vector(row + n.widget_local_size, 2)
    local line_offset = read:vector(self.line.at + n.widget_local_position, 2)
    local root_offset = read:vector(self.root.at + n.widget_local_position, 2)
    if
        position == nil
        or tail == nil
        or factor == nil
        or content == nil
        or parent == nil
        or line_offset == nil
        or root_offset == nil
    then
        return false
    end
    if content[1] <= 0 then
        return false
    end
    local right = content[1] + line_offset[1] + root_offset[1] + tail[1]
    local width = math.ceil(position[1] + right * factor[1]) + 10
    if parent[1] ~= width then
        ui:call("widget_size_set", row, ui:pair(width, parent[2]))
    end
    return true
end
function Line:reset(panel, requested)
    if panel == nil then
        return nil
    end
    local ui, n = self.ui, self.ui.n
    local before = ui.read:value(panel + n.self_weapon_layout_request, "u8")
    if before == nil then
        return nil
    end
    if requested then
        return before == 0 and "cleared" or "requested"
    end
    if before ~= n.self_layout_request_on then
        ui:put(panel + n.self_weapon_layout_request, n.self_layout_request_on, 1)
    end
    return "requested"
end
function Line:close()
    self.ui:destroy(self.root)
    self.ui:destroy(self.icons)
    self.ui:destroy(self.line)
    self.ui:destroy(self.text)
    self.function_cell:close()
    self.fire_cell:close()
    self.zero_cell:close()
    self.parent, self.row = nil, nil
end
return Line
