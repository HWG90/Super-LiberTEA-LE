local Panel = {}
Panel.__index = Panel
local function flag(value)
    return value ~= nil and value ~= 0
end
local STYLE_WIDGETS = { "magazine", "throwable", "reserve", "stims" }
function Panel.new(read, n)
    local style = {}
    for _, widget in ipairs({ n.self_magazine_fill, n.self_throwable_text, n.self_reserve_text, n.self_stims_text }) do
        for index = 0, 2 do
            style[#style + 1] = { widget + n.widget_local_colour + index * 4, "f32" }
        end
    end
    style[#style + 1] = { n.self_throwable_text + n.widget_local_opacity, "f32" }
    style[#style + 1] = { n.self_weapon_block + n.widget_local_opacity, "f32" }
    local health_at = n.self_panel_health_bar + n.health_bar_drawn
    return setmetatable({
        read = read,
        n = n,
        ammunition = {},
        sample = {},
        health_at = health_at,
        health_cells = read.layout({ { health_at, "f32" }, { n.self_panel_health_danger, "u8" } }),
        supply_cells = read.layout({}),
        style_cells = read.layout(style),
        colours = { magazine = {}, throwable = {}, reserve = {}, stims = {} },
        health_values = {},
        supply_values = {},
        style_values = {},
    }, Panel)
end
function Panel:configure(values)
    local n, fields, indices = self.n, {}, {}
    local function add(name, at, form)
        fields[#fields + 1] = { at, form }
        indices[name] = #fields
    end
    if values["hud.weapon3d.stims"] == 1 then
        add("stims", n.self_panel_stims, "i32")
    end
    if values["hud.weapon3d.ammo"] == 1 or values["hud.weapon3d.arc"] == 1 then
        add("magazine_low", n.self_panel_magazine_low, "u8")
    end
    if values["hud.weapon3d.reserve"] == 1 then
        add("reserve_low", n.self_panel_reserve_low, "u8")
    end
    if values["hud.weapon3d.pack"] == 1 then
        add("pack_low", n.self_panel_pack_low, "u8")
    end
    local cells = self.read.layout(fields)
    for name, index in pairs(indices) do
        cells[name] = index
    end
    self.supply_cells = cells
end
function Panel:observe(wanted, hud_wanted)
    local read, n = self.read, self.n
    self.base, self.mission, self.ready, self.editable, self.opacity, self.dt = nil, nil, false, false, nil, nil
    self.in_mission = nil
    if wanted == false then
        return false
    end
    local game = read:module("game")
    if game == nil then
        return false
    end
    local scene = read:ptr(game + n.hud_scene_manager)
    if scene == nil then
        return false
    end
    local kind = read:value(scene + n.hud_scene, "u32")
    if kind ~= nil then
        self.in_mission = kind == n.hud_scene_mission
    end
    if not self.in_mission then
        return false
    end
    local manager = read:ptr(game + n.roots_hud_manager_rva)
    if manager == nil then
        return false
    end
    local mission = manager + n.hud_widgets_mission_hud
    self.mission, self.base = mission, mission + n.hud_widgets_panels_self_panel_at
    if hud_wanted == false then
        return false
    end
    local language = read:ptr(game + n.ui_language_manager)
    if language == nil or read:value(language + n.ui_language_switch, "bool") ~= false then
        return false
    end
    local first = read:value(self.base, "u32")
    self.editable = read:value(manager + n.hud_built, "bool") == true and first ~= nil and first ~= 0
    if not self.editable then
        return false
    end
    self.ready = read:value(mission + n.hud_gate_ready, "bool") == true
    self.opacity = read:value(self.base + n.widget_inherited_opacity, "f32")
    local clock = read:ptr(game + n.stratagem_slots_clock_global)
    if clock ~= nil then
        self.dt = read:value(clock + n.hud_dt_at, "f32")
    end
    return true
end
function Panel:health_colour()
    if not self.ready then
        return nil
    end
    local n = self.n
    return self.read:vector(self.base + n.self_panel_health_bar + n.health_bar_fill + n.widget_local_colour, 3)
end
function Panel:style(throwing, reserve_shown)
    if not self.ready then
        return nil
    end
    local got, style = self.read:value(self.base, self.style_cells, self.style_values), self.colours
    for slot, name in ipairs(STYLE_WIDGETS) do
        local colour, at = style[name], (slot - 1) * 3
        colour[1], colour[2], colour[3] = got[at + 1], got[at + 2], got[at + 3]
    end
    if not reserve_shown then
        style.reserve[1], style.reserve[2], style.reserve[3] = nil, nil, nil
    end
    style.number, style.opacity = style.magazine, got[14]
    if throwing then
        if got[4] ~= nil then
            style.number = style.throwable
        end
        if got[13] ~= nil then
            style.opacity = got[13]
        end
    end
    return style
end
function Panel:magazine_size()
    if self.ready then
        return self.read:vector(self.base + self.n.panel_magazine_outline + self.n.hud_widgets_size_x, 2)
    end
end
function Panel:throwable_icon()
    if not self.ready then
        return nil
    end
    local read, n, base = self.read, self.n, self.base
    return read:value(base + n.self_panel_throwable_picture, "hex64"),
        read:vector(base + n.self_panel_throwable_icon + n.hud_widgets_size_x, 2)
end
function Panel:health()
    if self.ready then
        return self.read:value(self.base + self.health_at, "f32")
    end
end
function Panel:stamina()
    if not self.ready then
        return nil
    end
    return self.read:value(self.mission + self.n.hud_widgets_stamina_panel_at + self.n.stamina_panel_share, "f32")
end
function Panel:events(values, world_ready, count_2d)
    if not self.ready then
        return nil
    end
    local read, n, base, sample, ammo = self.read, self.n, self.base, self.sample, self.ammunition
    local number = world_ready and values["hud.weapon3d.ammo"] == 1
    local arc = world_ready and values["hud.weapon3d.arc"] == 1
    local reserve = world_ready and values["hud.weapon3d.reserve"] == 1
    local throwables = world_ready and values["hud.weapon3d.throwables"] == 1
    local pack = world_ready and values["hud.weapon3d.pack"] == 1
    sample.health, sample.danger, sample.stamina, sample.worn = nil, nil, nil, nil
    sample.gauge, sample.spare, sample.pack_low, sample.ammo = nil, nil, nil, ammo
    ammo.throwing, ammo.hidden, ammo.drawn, ammo.count, ammo.text = nil, nil, nil, nil, nil
    ammo.empty, ammo.reserve, ammo.throwables, ammo.throwables_unheld = nil, nil, nil, nil
    ammo.stims, ammo.magazine_low, ammo.reserve_low = nil, nil, nil
    if number or arc or reserve or throwables then
        ammo.throwing = read:value(base + n.hud_self_last_slot, "u32") == n.throwable_slot
    end
    local shown
    if number or arc or count_2d then
        local state = read:value(base + n.hud_weapon_ammo_state, "i32")
        shown = state ~= nil and state ~= n.hud_ammo_none_state
        ammo.hidden = state ~= nil and not shown
        if arc or (shown and (count_2d or (number and not ammo.throwing))) then
            ammo.drawn = read:value(base + n.hud_weapon_count_shown, "i32")
        end
        if shown and arc then
            ammo.empty = read:value(base + n.ammo_gauge, "f32")
        end
    end
    if (ammo.throwing and (number or arc)) or (throwables and not ammo.throwing) then
        local count = read:value(base + n.hud_self_throwables, "i32")
        if ammo.throwing then
            ammo.throwables = count
        else
            ammo.throwables_unheld = count
        end
    end
    if number then
        if shown and ammo.throwing and ammo.throwables == nil and not arc and not count_2d then
            ammo.drawn = read:value(base + n.hud_weapon_count_shown, "i32")
        end
        ammo.text = ammo.throwables
        if shown and ammo.text == nil then
            ammo.text = ammo.drawn
        end
    end
    if shown and (number or count_2d) then
        ammo.count = ammo.drawn
    end
    if reserve or pack then
        local spare = read:value(base + n.spare_widget, "bit", n.widget_shown_bit)
        sample.spare = spare ~= nil and spare ~= 0
        if reserve and sample.spare and not ammo.throwing then
            ammo.reserve = read:value(base + n.hud_weapon_reserve_shown, "u32")
        end
    end
    if world_ready and self.supply_cells.n > 0 then
        local cells = self.supply_cells
        local got = read:value(base, cells, self.supply_values)
        ammo.stims = got[cells.stims]
        if cells.magazine_low ~= nil and shown then
            ammo.magazine_low = flag(got[cells.magazine_low])
        end
        if cells.reserve_low ~= nil and sample.spare then
            ammo.reserve_low = flag(got[cells.reserve_low])
        end
        if cells.pack_low ~= nil then
            sample.pack_low = flag(got[cells.pack_low])
        end
    end
    if world_ready and values["hud.weapon3d.health"] == 1 then
        local got = read:value(base, self.health_cells, self.health_values)
        sample.health, sample.danger = got[1], flag(got[2])
    end
    if world_ready and values["hud.weapon3d.stamina"] == 1 then
        sample.stamina = self:stamina()
    end
    if pack or reserve then
        sample.gauge = read:value(base + n.self_panel_gauge_shown, "f32")
        local worn = read:value(base + n.self_panel_pack_cell, "bit", n.widget_shown_bit)
        sample.worn = worn ~= nil and worn ~= 0
    end
    return sample
end
function Panel:clock()
    if self.ready then
        return self.read:value(self.mission + self.n.hud_clock, "f32")
    end
end
function Panel:weapon_mount()
    if not self.editable then
        return nil
    end
    local row = self.base + self.n.self_weapon_widget
    local opacity = self.read:value(row + self.n.hud_widgets_shown, "f32")
    return self.base + self.n.self_weapon_block, row, opacity ~= nil and opacity > 0
end
return Panel
