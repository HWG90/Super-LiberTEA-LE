local Gauge = require("game.gauge")
local Layout = require("game.layout")
local OptionCell = require("game.option_cell")
local Resources = require("game.resources")
local Panel = {}
Panel.__index = Panel
local WHITE = { 1, 1, 1 }
local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function Panel.new(ui)
    local cyan = ui.n.hud_cyan_argb
    return setmetatable({
        ui = ui,
        gauge = Gauge.new(ui, false, 1),
        nodes = {},
        layouts = {},
        stim_size = { ui.n.self_stim_icon_width, ui.n.self_stim_icon_height },
        cyan = { cyan[2], cyan[3], cyan[4] },
        size = { 0, 0 },
        function_cell = OptionCell.new(ui),
        fire_cell = OptionCell.new(ui),
        zero_cell = OptionCell.new(ui),
    }, Panel)
end
function Panel:layout(name, node, kind, parent, gap, parent_kind, padding)
    local layout = self.layouts[name]
    if layout == nil then
        layout = Layout.new(self.ui)
        self.layouts[name] = layout
    end
    layout:create(node, kind, gap, parent_kind, padding)
    if parent ~= nil then
        self.layouts[parent]:add(layout)
    end
    return layout
end
function Panel:frame(name, parent)
    local node = self.ui:frame(self.nodes[name])
    self.nodes[name] = node
    self.ui:size(node, 0, 0)
    self.ui:attach(parent, node)
    return node
end
function Panel:text(name, parent, height)
    local ui, n = self.ui, self.ui.n
    local node = ui:text_node(n.world_text_font, n.world_text_flat, n.world_text_style, height, self.nodes[name], true)
    self.nodes[name] = node
    ui:material_scalar(node, n.outer_outline_distance_key, 2)
    ui:layer(node, n.hud_text_layer)
    ui:colour(node, 1, 1, 1)
    ui:attach(parent, node)
    return node
end
function Panel:image(name, parent, centred)
    local ui, node = self.ui, self.ui:image_node(self.nodes[name])
    self.nodes[name] = node
    ui:layer(node, ui.n.hud_text_layer)
    ui:colour(node, 1, 1, 1)
    if centred then
        ui:anchor(node, 0.5, 0.5)
        ui:pivot(node, 0.5, 0.5)
    end
    ui:attach(parent, node)
    return node
end
function Panel:create(parent, frame, values)
    local ui, n, gauge = self.ui, self.ui.n, self.gauge
    gauge:create(parent)
    ui:context(parent, function()
        local column = self:frame("column", gauge.root.at)
        ui:anchor(column, 0.5, 0.5)
        ui:pivot(column, 0.5, 0.5)
        self:layout("column", column, n.layout_down, nil, nil, nil, 3)
        local ammo = self:frame("ammo_row", column.at)
        ui:show(ammo, values["hud.weapon3d.functions"] == 1 or values["hud.weapon3d.ammo"] == 1)
        self:layout("ammo_row", ammo, n.layout_right, "column", 6, n.layout_down)
        if values["hud.weapon3d.functions"] == 1 then
            local cell = self.function_cell:create(ammo.at, frame)
            local scale = values["hud.weapon3d.icon_size"]
            ui:scale(cell, scale, scale)
            self:layout("function", cell, 0, "ammo_row", 3, n.layout_right)
        end
        if values["hud.weapon3d.ammo"] == 1 then
            self:layout(
                "ammo",
                self:text("ammo", ammo.at, values["hud.weapon3d.ammo_text_size"]),
                0,
                "ammo_row",
                3,
                n.layout_right
            )
        end
        local row = self:frame("reserve_row", column.at)
        self:layout("reserve_row", row, n.layout_right, "column", 6, n.layout_down)
        local scale, count = values["hud.weapon3d.reserve_icon_size"], values["hud.weapon3d.count_text_size"]
        if values["hud.weapon3d.reserve"] == 1 then
            local magazine = self:frame("magazine", row.at)
            ui:scale(magazine, scale, scale)
            self:layout("magazine", magazine, 0, "reserve_row", 3, n.layout_right)
            self:image("outline", magazine.at, true)
            self:image("fill", magazine.at, true)
            self:layout("reserve", self:text("reserve", row.at, count), 0, "reserve_row", 3, n.layout_right)
        end
        if values["hud.weapon3d.throwables"] == 1 then
            local cell = self:frame("throwables", row.at)
            self:layout("throwables", cell, n.layout_right, "reserve_row", 3, n.layout_right)
            local icon = self:image("throwable_icon", cell.at)
            ui:scale(icon, scale, scale)
            self:layout("throwable_icon", icon, 0, "throwables", 2, n.layout_right)
            self:layout(
                "throwable_count",
                self:text("throwable_count", cell.at, count),
                0,
                "throwables",
                2,
                n.layout_right
            )
        end
        if values["hud.weapon3d.stims"] == 1 then
            local cell = self:frame("stims", row.at)
            self:layout("stims", cell, n.layout_right, "reserve_row", 3, n.layout_right)
            local icon = self:frame("stim_icon", cell.at)
            ui:size(icon, n.self_stim_icon_height, n.self_stim_icon_width)
            scale = values["hud.weapon3d.stim_icon_size"]
            ui:scale(icon, scale, scale)
            self:layout("stim_icon", icon, 0, "stims", 2, n.layout_right)
            local picture = self:image("stim_picture", icon.at, true)
            ui:size(picture, n.self_stim_icon_width, n.self_stim_icon_height)
            ui:rotation(picture, 90)
            self:layout("stim_count", self:text("stim_count", cell.at, count), 0, "stims", 2, n.layout_right)
        end
        local side = self:frame("options", gauge.arc.at)
        local toward = DIRECTIONS[values["hud.weapon3d.layout"] + 1]
        local kind = toward[1] ~= 0 and n.layout_down or n.layout_right
        ui:anchor(side, 0.5, 0.5)
        ui:pivot(side, 0.5 - toward[1] / 2, 0.5 - toward[2] / 2)
        ui:position(side, toward[1] * 48, toward[2] * 48)
        self:layout("options", side, kind)
        scale = values["hud.weapon3d.mode_icon_size"]
        if values["hud.weapon3d.fire_mode"] == 1 then
            local cell = self.fire_cell:create(side.at, frame)
            ui:scale(cell, scale, scale)
            self:layout("fire", cell, 0, "options", 8, kind)
        end
        if values["hud.weapon3d.zeroing"] == 1 then
            local cell = self.zero_cell:create(side.at, frame)
            ui:scale(cell, scale, scale)
            self:layout("zero", cell, 0, "options", 8, kind)
        end
        if values["hud.weapon3d.arc"] == 1 then
            for _, name in ipairs({ "progress", "cycle", "charge", "ready" }) do
                local node = ui:image_node(self.nodes[name])
                self.nodes[name] = node
                node.gauge_value = nil
                ui:size(node, 96, 96)
                ui:anchor(node, 0.5, 0.5)
                ui:pivot(node, 0.5, 0.5)
                ui:material(node, Resources.outer_fill)
                ui:layer(node, name == "ready" and n.hud_text_layer or n.crosshair_fill_layer)
                ui:attach(gauge.arc.at, node)
            end
        end
    end)
    self.parent, self.values, self.filled, self.sample = parent, values, false, nil
    self.size[1], self.size[2] = 0, 0
    gauge:shape(values["hud.weapon3d.layout"], values["hud.weapon3d.gauge_angle"])
end
function Panel:picture(name, hash, size)
    local ui, node, n = self.ui, self.nodes[name], self.ui.n
    if node == nil or not node.live then
        return
    end
    if size == nil then
        hash = nil
    end
    ui:image(node, hash, n.flat_ammo_icon_material)
    if hash == nil then
        return
    end
    ui:size(node, size[1], size[2])
    ui:material_four(node, n.shadow_color_key, 0.6, 0, 0, 0)
    ui:material_pair(node, n.shadow_offset_key, n.shadow_offset[1], n.shadow_offset[2])
end
local function tint(ui, node, colour)
    if colour ~= nil and colour[1] ~= nil then
        ui:colour(node, colour[1], colour[2], colour[3])
        return
    end
    local normal = ui.n.self_panel_normal_colour
    ui:colour(node, normal[2], normal[3], normal[4])
end
function Panel:put(frame, sample)
    local ui, n, nodes, gauge, style = self.ui, self.ui.n, self.nodes, self.gauge, sample.style
    ui:show(nodes.options, sample.wielded == true)
    if nodes.ammo ~= nil and nodes.ammo.live then
        ui:text(nodes.ammo, sample.ammo)
        if style ~= nil then
            tint(ui, nodes.ammo, style.number)
            if style.opacity ~= nil then
                ui:opacity(nodes.ammo, style.opacity)
            end
        end
    end
    if nodes.reserve ~= nil and nodes.reserve.live then
        ui:text(nodes.reserve, sample.reserve)
        if style ~= nil then
            tint(ui, nodes.reserve, style.reserve)
        end
        ui:show(nodes.magazine, sample.reserve ~= nil and sample.outline ~= nil and sample.magazine_size ~= nil)
        if sample.magazine_size ~= nil then
            ui:size(nodes.magazine, sample.magazine_size[1], sample.magazine_size[2])
        end
        local outline, fill
        if sample.reserve ~= nil then
            outline = sample.outline
            if sample.reserve > 0 then
                fill = sample.fill
            end
        end
        self:picture("outline", outline, sample.magazine_size)
        self:picture("fill", fill, sample.magazine_size)
    end
    if nodes.throwables ~= nil and nodes.throwables.live then
        ui:show(nodes.throwables, sample.throwables ~= nil)
        ui:text(nodes.throwable_count, sample.throwables)
        if style ~= nil then
            tint(ui, nodes.throwable_count, style.throwable)
        end
        self:picture("throwable_icon", sample.throwable_icon, sample.throwable_size)
    end
    if nodes.stims ~= nil and nodes.stims.live then
        ui:show(nodes.stims, sample.stims ~= nil)
        ui:text(nodes.stim_count, sample.stims)
        if style ~= nil then
            tint(ui, nodes.stim_count, style.stims)
        end
        self:picture("stim_picture", n.stim_icon_material, self.stim_size)
    end
    local arc = self.values["hud.weapon3d.arc"] == 1
    ui:show(gauge.track, arc)
    local ammo, progress, cycle, charge, ready
    if arc then
        ammo, progress, charge, ready = sample.empty, sample.progress, sample.charge, sample.ready
        if ammo ~= nil then
            ammo = 1 - ammo
        end
        if sample.cycle ~= nil then
            cycle = 1 - sample.cycle
        end
    end
    local arc_colour = style and style.magazine
    gauge:paint(gauge.fill, ammo, arc_colour)
    if arc then
        gauge:paint(nodes.progress, progress, WHITE)
        gauge:paint(nodes.cycle, cycle, WHITE)
        gauge:paint(nodes.charge, charge, arc_colour)
        gauge:paint(nodes.ready, ready, self.cyan)
    end
    self.filled, self.sample = true, sample
    self:update(frame)
end
function Panel:update(frame)
    local sample, nodes, ui = self.sample, self.nodes, self.ui
    if sample == nil then
        return
    end
    local slots, fuse = sample.slots, sample.fuse
    if fuse.seconds ~= nil then
        self.function_cell:update_fuse(frame, fuse.mode, fuse.pick, fuse.id, fuse.seconds)
    else
        self.function_cell:update(frame, unpack(slots[1], 1, sample.wielded == true and 3 or 0))
    end
    self.fire_cell:update(frame, unpack(slots[2], 1, 3))
    self.zero_cell:update(frame, unpack(slots[3], 1, 3))
    ui:shade(nodes.outline)
    ui:shade(nodes.fill)
    ui:shade(nodes.throwable_icon)
    ui:shade(nodes.stim_picture)
    self.layouts.column:place()
    self.layouts.options:place()
    local size = ui.read:vector(nodes.column.at + ui.n.widget_local_size, 2)
    self.size[1], self.size[2] = 0, 0
    if size ~= nil then
        self.size[1], self.size[2] = size[1], size[2]
    end
end
function Panel:hide()
    self.gauge:hide()
    self.filled, self.sample = false, nil
    self.function_cell:update(0)
    self.fire_cell:update(0)
    self.zero_cell:update(0)
end
function Panel:close()
    self.gauge:close()
    for _, node in pairs(self.nodes) do
        self.ui:destroy(node)
    end
    self.function_cell:close()
    self.fire_cell:close()
    self.zero_cell:close()
    self.parent, self.values, self.filled, self.sample = nil, nil, false, nil
    self.size[1], self.size[2] = 0, 0
end
return Panel
