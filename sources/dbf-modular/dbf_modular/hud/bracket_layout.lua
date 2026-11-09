-- Retained flat Quiet Bracket. Coordinates are physical pixels/Y up.
-- update(...,nil,measure) computes LOCAL measured .bounds; resolve Anchor, then
-- update(...,anchor,measure) translates the SAME .primitives and .bounds records.
-- measure(font,text,size)->{left,bottom,right,top,width,height} or nil,reason.
-- An anchor bundle translates weapon/vitals/central independently. group_bounds
-- always remain LOCAL measured extents, including shadows, for whole-group clamps.
-- Primitive schema also carries group='weapon'|'vitals'|'central'.
local Layout = {}
Layout.__index = Layout
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function get(settings, key, default)
    local value = settings and settings:get(key)
    if value == nil then
        return default
    end
    return value
end
function Layout.new()
    return setmetatable({
        primitives = {},
        slots = {},
        bounds = {},
        revision = 0,
        group_bounds = { weapon = {}, vitals = {}, central = {} },
        strip_bounds = {},
        supplies = {},
        supply_slots = {},
    }, Layout)
end
function Layout:add(key, kind, x, y, w, h, text, size, tone, align, decoration, layer)
    local slot = self.slots[key]
    if not slot then
        slot = { key = key, kind = kind }
        self.slots[key] = slot
    end
    local scale = self.scale
    local l, b, r, t = 0, 0, w * scale, h * scale
    if kind == "text" then
        local metrics, why = self.measure(self.view.font, text, size * scale)
        if
            not metrics
            or not finite(metrics.left)
            or not finite(metrics.bottom)
            or not finite(metrics.right)
            or not finite(metrics.top)
            or metrics.right < metrics.left
            or metrics.top < metrics.bottom
        then
            self.reason = why or "text measurement unavailable"
            return false
        end
        l, b, r, t = metrics.left, metrics.bottom, metrics.right, metrics.top
        if align == "center" then
            x = x - (r + l) / (2 * scale)
        elseif align == "right" then
            x = x - r / scale
        end
    end
    local px, py = x * scale, y * scale
    if kind == "text" and not decoration then
        -- A screen pixel is resolution-scaled, independent of HUD user scale.
        local pixel = self.pixel / scale
        if
            not self:add(key .. "_shadow", "text", x + pixel, y - pixel, 0, 0, text, size, "hud_shadow", nil, true, 950)
        then
            return false
        end
    end
    local group = self.group_bounds[self.group]
    group.left, group.bottom = math.min(group.left, px + l), math.min(group.bottom, py + b)
    group.right, group.top = math.max(group.right, px + r), math.max(group.top, py + t)
    group.count = group.count + 1
    local anchor = self.anchors and (self.anchors[self.group] or self.anchors)
    local ax, ay = anchor and anchor.x or 0, anchor and anchor.y or 0
    self.left, self.bottom = math.min(self.left, ax + px + l), math.min(self.bottom, ay + py + b)
    self.right, self.top = math.max(self.right, ax + px + r), math.max(self.top, ay + py + t)
    slot.x, slot.y, slot.z = ax + px, ay + py, layer or (kind == "text" and 951 or 949)
    slot.local_x, slot.local_y = px, py
    slot.ink_left, slot.ink_bottom, slot.ink_right, slot.ink_top = l, b, r, t
    slot.group = self.group
    slot.width, slot.height, slot.text, slot.size = w * scale, h * scale, text, size * scale
    slot.tone, slot.alpha = tone or "text", self.view.opacity or 1
    self.used = self.used + 1
    self.primitives[self.used] = slot
    return true
end
function Layout:text(key, value, x, y, size, tone, align)
    return value == nil or self:add(key, "text", x, y, 0, 0, value, size, tone, align)
end
function Layout:rect(key, x, y, w, h, tone, layer)
    return self:add(key, "rect", x, y, w, h, nil, 0, tone, nil, true, layer)
end
function Layout:bracket_stroke(key, x, y, width, height)
    self:rect(key, x, y, width, height, "text", 948)
    self.slots[key].alpha = (self.view.opacity or 1) * 0.7
end
function Layout:vitals_brackets()
    local bounds = self.group_bounds.vitals
    if bounds.count == 0 then
        return
    end
    -- Measure the visible bars, native icons and counts before adding trim.
    -- The strokes join the same group, so model following and clamps include
    -- the complete outline while cooldowns stay outside it.
    local scale = self.scale
    local left, right = bounds.left / scale - 7, bounds.right / scale + 7
    local bottom, top = bounds.bottom / scale - 6, bounds.top / scale + 6
    local thickness, cap = 1.5, 6
    self:bracket_stroke("vitals_bracket_left", left, bottom, thickness, top - bottom)
    self:bracket_stroke("vitals_bracket_left_top", left, top - thickness, cap, thickness)
    self:bracket_stroke("vitals_bracket_left_bottom", left, bottom, cap, thickness)
    self:bracket_stroke("vitals_bracket_right", right - thickness, bottom, thickness, top - bottom)
    self:bracket_stroke("vitals_bracket_right_top", right - cap, top - thickness, cap, thickness)
    self:bracket_stroke("vitals_bracket_right_bottom", right - cap, bottom, cap, thickness)
end
function Layout:icon(key, x, y, width, height, rotation)
    local spec = self.supply_slots[key]
    if not spec then
        spec = { key = key }
        self.supply_slots[key] = spec
    end
    local scale, group = self.scale, self.group_bounds[self.group]
    local px, py, w, h = x * scale, y * scale, width * scale, height * scale
    local anchor = self.anchors and (self.anchors[self.group] or self.anchors)
    local ax, ay = anchor and anchor.x or 0, anchor and anchor.y or 0
    -- x/y/width/height describe the rotated image's complete visual AABB.
    spec.x, spec.y, spec.width, spec.height, spec.rotation = ax + px, ay + py, w, h, rotation
    self.supply_used = self.supply_used + 1
    self.supplies[self.supply_used] = spec
    group.left, group.right = math.min(group.left, px), math.max(group.right, px + w)
    group.bottom, group.top = math.min(group.bottom, py), math.max(group.top, py + h)
    group.count = group.count + 1
    self.left, self.right = math.min(self.left, spec.x), math.max(self.right, spec.x + w)
    self.bottom, self.top = math.min(self.bottom, spec.y), math.max(self.top, spec.y + h)
    return true
end
function Layout:heat_bar(weapon, y, vertical, data)
    local metrics, why = self.measure(self.view.font, "HEAT", 10 * self.scale)
    if
        not metrics
        or not finite(metrics.left)
        or not finite(metrics.right)
        or not finite(metrics.bottom)
        or not finite(metrics.top)
        or metrics.right < metrics.left
        or metrics.top < metrics.bottom
    then
        self.reason = why or "heat label measurement unavailable"
        return false
    end
    local icon = data and data.heat
    local icon_known = type(icon) == "table"
        and icon.known == true
        and type(icon.texture) == "string"
        and #icon.texture == 16
        and icon.texture:match("^%x+$")
        and finite(icon.width)
        and finite(icon.height)
        and icon.width > 0
        and icon.height > 0
    local icon_width, icon_height
    if icon_known then
        local factor = math.min(14 / icon.width, 28 / icon.height)
        icon_width, icon_height = icon.width * factor, icon.height * factor
    end
    local x, width, height, label_x, align = 105, 80, 8, 65, nil
    if icon_known and not vertical and weapon.text ~= nil then
        local ammo = self.slots.ammo
        local bottom = (ammo.local_y + ammo.ink_bottom - self.pixel) / self.scale
        -- Rotate the complete coil beside the meter without letting its taller
        -- ink touch the current percentage or its one-pixel shadow.
        y = math.min(y, bottom - 4 - icon_width / 2 - height / 2)
    end
    local label_y = y + 4 - (metrics.bottom + metrics.top) / (2 * self.scale)
    if vertical then
        local column_right
        width, height, y = 8, 80, -91
        x = math.max(105, 65 + metrics.right / self.scale + 12)
        label_y = y + 40 - (metrics.bottom + metrics.top) / (2 * self.scale)
        if weapon.text ~= nil then
            local current, current_why = self.measure(self.view.font, weapon.text, 30 * self.scale)
            local maximum, maximum_why = self.measure(self.view.font, "100%", 30 * self.scale)
            if
                not current
                or not finite(current.right)
                or not finite(current.bottom)
                or not finite(current.top)
                or current.top < current.bottom
                or not maximum
                or not finite(maximum.right)
            then
                self.reason = current_why or maximum_why or "vertical heat measurement unavailable"
                return false
            end
            -- Reserve the complete maximum-percentage cell so normal digit
            -- changes do not walk the bar into the current percentage.
            column_right = math.max(145, 65 + current.right / self.scale, 65 + maximum.right / self.scale)
            x = column_right + 12
            if self.option_metrics then
                x = math.max(x, 65 + self.option_metrics.width / self.scale + 8)
            end
            y = -60 + (current.bottom + current.top) / (2 * self.scale) - 40
            label_x, label_y, align =
                x + 4, math.max(y + height, -60 + current.top / self.scale) + 6 - metrics.bottom / self.scale, "center"
        end
        if icon_known then
            if self.option_metrics then
                column_right = math.max(column_right or -math.huge, 65 + self.option_metrics.width / self.scale)
            end
            if column_right then
                -- The coil sits left of the meter. Reserve both its complete
                -- width and the eight-pixel gap from ammo/native controls.
                x = math.max(x, column_right + 8 + icon_width + 6)
            end
        end
    end
    local labeled
    if icon_known then
        local iw, ih = icon_width, icon_height
        local ix, iy, rotation
        if vertical then
            rotation = 0
            ix, iy = x - iw - 6, y
        else
            iw, ih, rotation = ih, iw, 90
            ix, iy = label_x, y + height / 2 - ih / 2
        end
        labeled = self:icon("heat", ix, iy, iw, ih, rotation)
    else
        labeled = self:text("heat_label", "HEAT", label_x, label_y, 10, "text_dim", align)
    end
    if
        not (
            labeled
            and self:rect("heat_shadow", x + 1, y - 1, width, height, "hud_shadow", 948)
            and self:rect("heat_track", x, y, width, height, "line_strong", 949)
            and self:rect(
                "heat_fill",
                x,
                y,
                vertical and width or width * weapon.fill,
                vertical and height * weapon.fill or height,
                weapon.tone,
                950
            )
        )
    then
        return false
    end
    local fill = self.slots.heat_fill
    fill.danger_mix = finite(weapon.heat_warning_mix) and math.max(0, math.min(1, weapon.heat_warning_mix)) or 0
    local pulse = finite(weapon.heat_pulse) and math.max(0.25, math.min(1, weapon.heat_pulse)) or 1
    fill.alpha = (self.view.opacity or 1) * pulse
    return true
end
local function option_metrics(view, metrics)
    return view.native_options ~= false
            and type(metrics) == "table"
            and metrics.ready == true
            and finite(metrics.count)
            and metrics.count % 1 == 0
            and metrics.count > 0
            and metrics.count <= 4
            and finite(metrics.width)
            and metrics.width > 0
            and finite(metrics.height)
            and metrics.height > 0
            and metrics
        or nil
end
function Layout:below_support(key, text, y, size, top)
    if text == nil or top == nil then
        return y
    end
    local metrics, why = self.measure(self.view.font, text, size * self.scale)
    if not metrics or not finite(metrics.top) or not finite(metrics.bottom) or metrics.bottom > metrics.top then
        self.reason = why or (key .. " measurement unavailable")
        return nil
    end
    return math.min(y, (top - metrics.top) / self.scale)
end
function Layout:supply(key, view, x, right_aligned, data)
    if not view.visible then
        return true
    end
    local text = view.text
    local count = type(text) == "string" and text:match(key == "stims" and "^STIM (%d+)$" or "^G (%d+)$")
    local icon = data and data[key]
    local known = count
        and type(icon) == "table"
        and icon.known == true
        and type(icon.texture) == "string"
        and #icon.texture == 16
        and icon.texture:match("^%x+$")
        and finite(icon.width)
        and finite(icon.height)
        and icon.width > 0
        and icon.height > 0
    if not known then
        return self:text(key, text, x, -86, 12, view.tone, right_aligned and "right" or nil)
    end
    local metrics, why = self.measure(self.view.font, count, 12 * self.scale)
    if
        not metrics
        or not finite(metrics.left)
        or not finite(metrics.right)
        or not finite(metrics.bottom)
        or not finite(metrics.top)
        or metrics.right < metrics.left
        or metrics.top < metrics.bottom
    then
        self.reason = why or "supply count measurement unavailable"
        return false
    end
    -- Uniform fitting preserves the current native sprite's actual aspect.
    local factor = math.min(24 / icon.width, 14 / icon.height)
    local w, h = icon.width * factor * self.scale, icon.height * factor * self.scale
    local gap = 4 * self.scale
    local right = x * self.scale
    local icon_x, text_x
    if right_aligned then
        text_x = right - metrics.right
        icon_x = text_x + metrics.left - gap - w
    else
        icon_x = right
        text_x = icon_x + w + gap - metrics.left
    end
    if not self:text(key, count, text_x / self.scale, -86, 12, view.tone) then
        return false
    end
    local y = -86 * self.scale + (metrics.bottom + metrics.top - h) / 2
    local spec = self.supply_slots[key]
    if not spec then
        spec = { key = key }
        self.supply_slots[key] = spec
    end
    local a = self.anchors and (self.anchors.vitals or self.anchors)
    local ax, ay = a and a.x or 0, a and a.y or 0
    spec.x, spec.y, spec.width, spec.height = ax + icon_x, ay + y, w, h
    self.supply_used = self.supply_used + 1
    self.supplies[self.supply_used] = spec
    local group = self.group_bounds.vitals
    group.left, group.right = math.min(group.left, icon_x), math.max(group.right, icon_x + w)
    group.bottom, group.top = math.min(group.bottom, y), math.max(group.top, y + h)
    group.count = group.count + 1
    self.left, self.right = math.min(self.left, spec.x), math.max(self.right, spec.x + w)
    self.bottom, self.top = math.min(self.bottom, spec.y), math.max(self.top, spec.y + h)
    return true
end
function Layout:update(view, settings, viewport, anchor, measure, supplies, options)
    local height = viewport and viewport.height
    self.valid, self.reason = false, nil
    if not finite(height) or height <= 0 or type(measure) ~= "function" then
        self.reason = "layout inputs unavailable"
        return self
    end
    local percent = get(settings, "hud.scale", 100)
    if not finite(percent) or percent <= 0 then
        self.reason = "scale unavailable"
        return self
    end
    self.scale, self.used, self.supply_used = height / 1080 * percent / 100, 0, 0
    self.pixel = height / 1080
    self.left, self.bottom, self.right, self.top = math.huge, math.huge, -math.huge, -math.huge
    self.anchors = anchor
    for _, group in pairs(self.group_bounds) do
        group.left, group.bottom, group.right, group.top, group.count = math.huge, math.huge, -math.huge, -math.huge, 0
    end
    self.view, self.measure = view, measure
    self.option_metrics = option_metrics(view, options)
    self.strip_bounds.valid = false
    local weapon = view.weapon
    self.group = "weapon"
    if weapon.visible then
        -- Saved top+30 and 30px line box -> engine baseline Y=-60.
        if not self:text("ammo", weapon.text, 65, -60, 30, weapon.tone) then
            return self
        end
        local vertical_heat = get(settings, "hud.heat_bar_vertical", false) == true
        if
            weapon.heat_bar and not self:heat_bar(weapon, weapon.text ~= nil and -76 or -55, vertical_heat, supplies)
        then
            return self
        end
        if view.details and not self:text("capacity", weapon.capacity, 145, -60, 13, "text_dim") then
            return self
        end
    end
    local support_top
    if self.option_metrics then
        local bottom
        if weapon.visible and weapon.text ~= nil then
            local p = self.slots.ammo
            bottom = p.local_y + p.ink_bottom
        elseif weapon.visible and weapon.heat_bar then
            bottom = self.slots.heat_track.local_y - self.pixel
        else
            local metrics, why = measure(view.font, "0", 30 * self.scale)
            if not metrics or not finite(metrics.bottom) then
                self.reason = why or "option row reference unavailable"
                return self
            end
            bottom = -60 * self.scale + metrics.bottom
        end
        -- A horizontal meter lies below the percentage. A vertical Hybrid
        -- meter sits beside this complete options row, so it cannot push the
        -- original controls away from the ammo value.
        if weapon.visible and weapon.heat_bar and get(settings, "hud.heat_bar_vertical", false) ~= true then
            bottom = math.min(bottom, self.slots.heat_track.local_y - self.pixel)
        end
        local b = self.strip_bounds
        b.left, b.top = 65 * self.scale, bottom - 8 * self.scale
        b.right, b.bottom = b.left + self.option_metrics.width, b.top - self.option_metrics.height
        b.valid = true
        support_top = b.bottom - 6 * self.scale
    end
    local reload_y = self:below_support("reload", view.reload.visible and view.reload.text or nil, -80, 11, support_top)
    if
        reload_y == nil
        or view.reload.visible and not self:text("reload", view.reload.text, 65, reload_y, 11, view.reload.tone)
    then
        return self
    end
    if view.reload.visible and support_top then
        support_top = self.slots.reload.local_y + self.slots.reload.ink_bottom - 6 * self.scale
    end
    if weapon.visible and view.details then
        local vertical_heat = get(settings, "hud.heat_bar_vertical", false) == true
        local reserve_y = weapon.heat_bar and (vertical_heat and -110 or weapon.text ~= nil and -94 or -80) or -98
        local reserve_top = weapon.heat_bar
                and math.min(support_top or math.huge, self.group_bounds.weapon.bottom - 6 * self.scale)
            or support_top
        reserve_y = self:below_support("reserve", weapon.reserve, reserve_y, 11, reserve_top)
        if reserve_y == nil or not self:text("reserve", weapon.reserve, 65, reserve_y, 11, "text_dim") then
            return self
        end
    end
    self.group = "vitals"
    if view.health.visible then
        self:rect("health_track", -145, -57, 80, 5, "line")
        self:rect("health", -145, -57, 80 * view.health.fill, 5, view.health.tone)
    end
    if view.stamina.visible then
        self:rect("stamina_track", -145, -64, 80, 2, "line")
        self:rect("stamina", -145, -64, 80 * view.stamina.fill, 2, view.stamina.tone)
    end
    -- Fixed independent slots: one supply never moves the other.
    if not self:supply("stims", view.stims, -145, false, supplies) then
        return self
    end
    if not self:supply("throwables", view.throwables, -65, true, supplies) then
        return self
    end
    self:vitals_brackets()
    for index = #self.primitives, self.used + 1, -1 do
        self.primitives[index] = nil
    end
    for index = #self.supplies, self.supply_used + 1, -1 do
        self.supplies[index] = nil
    end
    if self.used == 0 then
        local a = anchor and (anchor.central or anchor)
        self.left, self.bottom = a and a.x or 0, a and a.y or 0
        self.right, self.top = self.left, self.bottom
    end
    for _, group in pairs(self.group_bounds) do
        if group.count == 0 then
            group.left, group.bottom, group.right, group.top = 0, 0, 0, 0
        end
    end
    local bounds = self.bounds
    bounds.left, bounds.bottom = self.left, self.bottom
    bounds.right, bounds.top = self.right, self.top
    self.visible, self.valid, self.profile = view.visible == true, true, view.profile
    self.revision = self.revision + 1
    return self
end
return Layout
