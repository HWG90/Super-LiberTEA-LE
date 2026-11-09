-- Pure assembly for the EXISTING DBF presenters plus Bracket. Physical pixels/Y up.
-- Every group clamps as one measured envelope. Unknown/oversized native content
-- retains its original viewport home; intentionally hidden content never rejoins.
local Anchor = mod.require("hud/anchor.lua")
local Composition = {}
Composition.__index = Composition
local ROLES = { "weapon", "vitals", "central" }
local STACK_ROLES = { "vitals", "weapon", "central" }
local SIDE_ROLES = { "vitals", "weapon" }
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function bounds(b)
    return type(b) == "table"
        and finite(b.left)
        and finite(b.right)
        and finite(b.bottom)
        and finite(b.top)
        and b.left <= b.right
        and b.bottom <= b.top
end
local function copy(out, b)
    out.left, out.right, out.bottom, out.top = b.left, b.right, b.bottom, b.top
end
local function union(out, b)
    out.left, out.right = math.min(out.left, b.left), math.max(out.right, b.right)
    out.bottom, out.top = math.min(out.bottom, b.bottom), math.max(out.top, b.top)
end
local function offset(out, b, a)
    out.left, out.right, out.bottom, out.top = b.left + a.x, b.right + a.x, b.bottom + a.y, b.top + a.y
end
local function copy_anchor(out, a)
    out.x, out.y, out.source, out.profile = a.x, a.y, a.source, a.profile
end
local function overlaps(a, b)
    return a.left < b.right and a.right > b.left and a.bottom < b.top and a.top > b.bottom
end
local function shifted_overlaps(a, b, dx, dy)
    return a.left + dx < b.right and a.right + dx > b.left and a.bottom + dy < b.top and a.top + dy > b.bottom
end
local function address(v)
    return finite(v) and v >= 65536 and v < 2 ^ 47 and v % 1 == 0
end
local function cross(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end
function Composition.new()
    local anchors = { weapon = {}, vitals = {}, central = {} }
    return setmetatable({
        base = {},
        combat_bounds = {},
        bounds = {},
        candidate = {},
        strip_bounds = {},
        anchors = anchors,
        anchor = anchors.central,
        cooldown_anchor = anchors.vitals,
        cooldown_role = "vitals",
        group_bounds = { weapon = {}, vitals = {}, central = {} },
        weapon = {},
        cooldown_options = {},
        render_view = {},
        geometry = { primitives = {}, bounds = {} },
        slots = {},
        source_anchor = {},
        clearance = {},
        candidate_anchor = {},
        stack_local_vitals = {},
        stack_local_weapon = {},
        stack_world_vitals = {},
        stack_world_weapon = {},
        stack_bounds = {},
        stack_vitals_anchor = {},
        stack_weapon_anchor = {},
        stack_visual_vitals = {},
        stack_visual_weapon = {},
        sight_target_bounds = {},
        motion = Anchor.Tracker.new(),
        primary_centers = { weapon = 0, vitals = 0 },
        inward_edges = { weapon = 0, vitals = 0 },
        rail_widths = { weapon = 0, vitals = 0 },
        filtered = {},
        sight_sorted = {},
        sight_hull = {},
        held_sight = { valid = false },
        sight_clearance = {
            active = false,
            known = false,
            source = "inactive",
            status = "inactive",
            bounds = {},
            raw_bounds = {},
        },
    }, Composition)
end
function Composition:reset_motion()
    self.motion:reset()
    self.stacked = false
    local sight = self.sight_clearance
    sight.active, sight.known, sight.source, sight.status = false, false, "inactive", "inactive"
    sight.fits = false
    self.held_sight.valid = false
    self.filtered.weapon, self.filtered.vitals, self.filtered.central = nil, nil, nil
end
-- Projected box corners are not perimeter ordered. Build each unit's convex
-- silhouette into retained scratch references, then intersect its edges with
-- the configured horizontal slab. Extreme stock corners below the slab cannot
-- widen a sight-line aperture. No producer point or native geometry is changed.
function Composition:clip_sight_polygons(data, low_y, high_y)
    local polygons = data.polygons
    if
        type(polygons) ~= "table"
        or #polygons < 1
        or #polygons > 8
        or (data.unit_count ~= nil and data.unit_count ~= #polygons)
    then
        return nil, nil, 0, "fallback: projected hull unavailable"
    end
    local sorted, hull, width, height = self.sight_sorted, self.sight_hull, self.viewport.width, self.viewport.height
    local left, right, hits = math.huge, -math.huge, 0
    for unit = 1, #polygons do
        local polygon = polygons[unit]
        if type(polygon) ~= "table" or #polygon ~= 8 then
            return nil, nil, 0, "fallback: malformed projected hull"
        end
        for index = 1, 8 do
            local p = polygon[index]
            if type(p) ~= "table" or not finite(p.x) or not finite(p.y) or p.clipped == true then
                return nil, nil, 0, "fallback: malformed projected hull"
            end
            if math.abs(p.x) > 8 * width or math.abs(p.y) > 8 * height then
                return nil, nil, 0, "fallback: projected hull out of range"
            end
            local at = index
            while at > 1 and (p.x < sorted[at - 1].x or (p.x == sorted[at - 1].x and p.y < sorted[at - 1].y)) do
                sorted[at], at = sorted[at - 1], at - 1
            end
            sorted[at] = p
        end
        local count = 0
        for index = 1, 8 do
            local p = sorted[index]
            if count == 0 or p.x ~= sorted[count].x or p.y ~= sorted[count].y then
                count = count + 1
                sorted[count] = p
            end
        end
        if count < 3 then
            return nil, nil, 0, "fallback: degenerate projected hull"
        end
        local used = 0
        for index = 1, count do
            local p = sorted[index]
            while used >= 2 and cross(hull[used - 1], hull[used], p) <= 0 do
                used = used - 1
            end
            used = used + 1
            hull[used] = p
        end
        local lower = used
        for index = count - 1, 1, -1 do
            local p = sorted[index]
            while used > lower and cross(hull[used - 1], hull[used], p) <= 0 do
                used = used - 1
            end
            used = used + 1
            hull[used] = p
        end
        used = used - 1
        if used < 3 then
            return nil, nil, 0, "fallback: degenerate projected hull"
        end
        local unit_left, unit_right = math.huge, -math.huge
        for index = 1, used do
            local a, b = hull[index], hull[index == used and 1 or index + 1]
            if a.y >= low_y and a.y <= high_y then
                unit_left, unit_right = math.min(unit_left, a.x), math.max(unit_right, a.x)
            end
            if a.y ~= b.y then
                local bottom, top = math.min(a.y, b.y), math.max(a.y, b.y)
                if low_y >= bottom and low_y <= top then
                    local x = a.x + (b.x - a.x) * (low_y - a.y) / (b.y - a.y)
                    unit_left, unit_right = math.min(unit_left, x), math.max(unit_right, x)
                end
                if high_y >= bottom and high_y <= top then
                    local x = a.x + (b.x - a.x) * (high_y - a.y) / (b.y - a.y)
                    unit_left, unit_right = math.min(unit_left, x), math.max(unit_right, x)
                end
            end
        end
        if unit_left <= unit_right and unit_right >= 0 and unit_left <= width then
            left, right, hits =
                math.min(left, math.max(0, unit_left)), math.max(right, math.min(width, unit_right)), hits + 1
        end
    end
    if hits == 0 then
        return nil, nil, 0, "fallback: projected hull misses sight band"
    end
    return left, right, hits
end
function Composition:prepare_sight(geometry, root)
    for _, role in ipairs(SIDE_ROLES) do
        local source = geometry.group_bounds and geometry.group_bounds[role]
        local left, right =
            (role == "vitals" and -157 or 60) * self.scale, (role == "vitals" and -53 or 173) * self.scale
        if source and bounds(source) and (source.count or 0) > 0 then
            left, right = math.min(left, source.left), math.max(right, source.right)
        end
        self.inward_edges[role] = role == "vitals" and right or left
        self.rail_widths[role] = right - left
    end
    local sight, b = self.sight_clearance, self.sight_clearance.bounds
    sight.active, sight.known, sight.source, sight.status = root.source == "sights", false, "inactive", "inactive"
    sight.fits = false
    sight.held = false
    sight.band_left, sight.band_right, sight.units_in_band = nil, nil, 0
    sight.raw_bounds.left, sight.raw_bounds.right, sight.raw_bounds.bottom, sight.raw_bounds.top = nil, nil, nil, nil
    if not sight.active then
        self.held_sight.valid = false
        return
    end
    local minimum, padding = 96 * self.scale, 18 * self.scale
    b.left, b.right, b.bottom, b.top =
        root.x - minimum, root.x + minimum, root.y - 22 * self.pixel, root.y + 22 * self.pixel
    sight.source, sight.status = "fallback", "fallback: geometry unavailable"
    local data, model, viewport = self.model.sight_clearance, self.model, self.viewport
    local held, rig = self.held_sight, self.model.aim.viewmodel_unit
    local ox, oy = self.settings:get("hud.offset_x") or 0, self.settings:get("hud.offset_y") or 0
    local ax, ay = self.settings:get("hud.ads_offset_x") or 0, self.settings:get("hud.ads_offset_y") or 0
    local tfp = Anchor.true_first_person(model)
    local rx = tfp and (self.settings:get("hud.tfp_ammo_offset_x") or 0) or 0
    local ry = tfp and (self.settings:get("hud.tfp_ammo_offset_y") or 0) or 0
    local same_owner = held.valid
        and finite(rig)
        and rig > 0
        and rig < 4294967295
        and rig % 1 == 0
        and address(model.anchor_context)
        and address(model.anchor_camera)
        and type(model.follow_token) == "string"
        and model.follow_token ~= ""
        and held.identity == model.identity
        and held.generation == model.generation
        and held.context == model.anchor_context
        and held.camera == model.anchor_camera
        and held.follow_token == model.follow_token
        and held.rig == rig
        and held.width == viewport.width
        and held.height == viewport.height
        and held.scale == self.scale
        and held.ox == ox
        and held.oy == oy
        and held.ax == ax
        and held.ay == ay
        and held.rx == rx
        and held.ry == ry
    if not same_owner then
        held.valid = false
    end
    if type(data) == "table" and data.known == true then
        -- A rejected current payload cannot preserve a prior different shape.
        held.valid = false
        local raw = data.bounds
        local vm = model.anchors and model.anchors.viewmodel
        if
            data.identity ~= model.identity
            or data.generation ~= model.generation
            or type(model.follow_token) ~= "string"
            or model.follow_token == ""
            or data.follow_token ~= model.follow_token
            or not address(model.anchor_context)
            or not address(model.anchor_camera)
            or data.context ~= model.anchor_context
            or data.camera ~= model.anchor_camera
            or (
                vm
                and vm.known == true
                and (
                    (vm.context ~= nil and vm.context ~= data.context)
                    or (vm.camera ~= nil and vm.camera ~= data.camera)
                )
            )
        then
            sight.status = "fallback: geometry owner changed"
        elseif data.source ~= "weapon_bounds" then
            sight.status = "fallback: unsupported geometry source"
        elseif not bounds(raw) or raw.right <= raw.left or raw.top <= raw.bottom then
            sight.status = "fallback: malformed geometry"
        elseif
            raw.right - raw.left > 8 * viewport.width
            or raw.top - raw.bottom > 8 * viewport.height
            or math.abs(raw.left) > 8 * viewport.width
            or math.abs(raw.right) > 8 * viewport.width
            or math.abs(raw.bottom) > 8 * viewport.height
            or math.abs(raw.top) > 8 * viewport.height
        then
            sight.status = "fallback: geometry out of range"
        elseif b.bottom >= viewport.height or b.top <= 0 then
            sight.status = "fallback: sight band outside viewport"
        elseif
            raw.right <= 0
            or raw.left >= viewport.width
            or raw.top <= math.max(0, b.bottom)
            or raw.bottom >= math.min(viewport.height, b.top)
        then
            sight.status = "fallback: geometry misses sight band"
        else
            copy(sight.raw_bounds, raw)
            local left, right, hits, why =
                self:clip_sight_polygons(data, math.max(0, b.bottom), math.min(viewport.height, b.top))
            sight.band_left, sight.band_right, sight.units_in_band = left, right, hits
            if left ~= nil then
                b.left, b.right = math.min(b.left, left - padding), math.max(b.right, right + padding)
                sight.known, sight.source, sight.status = true, "weapon_bounds", "weapon_bounds"
            else
                sight.status = why
            end
        end
    elseif held.valid then
        -- Keep screen INSETS only, never geometry or an absolute projected point.
        -- Include the last displayed edges so unknown geometry cannot continue
        -- shrinking a still-in-progress inward animation.
        held.left = math.max(held.left, held.display_left or held.left)
        held.right = math.max(held.right, held.display_right or held.right)
        b.left = math.min(b.left, model.reticle.x - held.left)
        b.right = math.max(b.right, model.reticle.x + held.right)
        sight.held, sight.status = true, "fallback: held measured spacing"
    end
    local margin = math.max(2, 5 * self.pixel)
    -- TrueFP puts vitals on the arm, so only its weapon column needs sight room.
    local left_required = not Anchor.true_first_person(model)
    sight.fits = (not left_required or b.left - self.rail_widths.vitals >= margin)
        and b.right + self.rail_widths.weapon <= viewport.width - margin
    if (sight.known or sight.held) and not sight.fits then
        sight.known, sight.source, sight.status = false, "fallback", "fallback: geometry leaves no column room"
        sight.held, held.valid = false, false
        b.left, b.right = root.x - minimum, root.x + minimum
        sight.fits = (not left_required or b.left - self.rail_widths.vitals >= margin)
            and b.right + self.rail_widths.weapon <= viewport.width - margin
    end
    if not sight.fits then
        sight.status = "fallback: aperture cannot fit viewport"
    end
    if sight.known and sight.fits and finite(rig) and rig > 0 and rig < 4294967295 and rig % 1 == 0 then
        held.valid, held.left, held.right = true, model.reticle.x - b.left, b.right - model.reticle.x
        held.identity, held.generation, held.context, held.camera =
            model.identity, model.generation, model.anchor_context, model.anchor_camera
        held.follow_token, held.rig, held.width, held.height, held.scale =
            model.follow_token, rig, viewport.width, viewport.height, self.scale
        held.ox, held.oy, held.ax, held.ay = ox, oy, ax, ay
        held.rx, held.ry = rx, ry
        held.display_left, held.display_right = nil, nil
    end
end
function Composition:apply_sight(role, anchor)
    local sight = self.sight_clearance
    if anchor.source ~= "sights" or not sight.active or not sight.fits then
        return
    end
    local inward = self.inward_edges[role]
    local limit = role == "vitals" and sight.bounds.left or sight.bounds.right
    local current = anchor.x + inward
    if (role == "vitals" and current > limit) or (role == "weapon" and current < limit) then
        anchor.x, anchor.clearance = limit - inward, true
    end
end
function Composition:commit_sight(role, anchor)
    local filtered = self.filtered[role]
    if anchor.source == "sights" and filtered then
        -- The retained state is a screen reference, not a pose. Remember the
        -- actually displayed safe edge so a smaller optic moves inward smoothly.
        filtered.x = anchor.x + self.inward_edges[role]
        local held = self.held_sight
        if held.valid then
            if role == "vitals" then
                held.display_left = self.model.reticle.x - filtered.x
            else
                held.display_right = filtered.x - self.model.reticle.x
            end
        end
    end
end
function Composition:measure_primary(geometry, measure)
    local ammo, health, heat
    -- Layout.slots retains hidden records. Only this frame's primitive list may
    -- supply a current alignment reference; support cells never recenter it.
    for _, p in ipairs(geometry.primitives) do
        if p.key == "ammo" and p.kind == "text" then
            ammo = p
        elseif p.key == "health_track" and p.kind == "rect" then
            health = p
        elseif p.key == "heat_track" and p.kind == "rect" then
            heat = p
        end
    end
    self.primary_centers.vitals = health and health.y + health.height / 2 or -54.5 * self.scale
    self.health_center_x = health and health.x + health.width / 2 or -105 * self.scale
    self.health_top = health and health.y + health.height or -52 * self.scale
    if not ammo and heat then
        self.primary_centers.weapon = heat.y + heat.height / 2
        self.weapon_center_x = heat.x + heat.width / 2
        return true
    end
    local text, size, y =
        ammo and ammo.text or "0", ammo and ammo.size or 30 * self.scale, ammo and ammo.y or -60 * self.scale
    local metrics, why = measure(self.view.font, text, size)
    if not metrics or not finite(metrics.bottom) or not finite(metrics.top) or metrics.top < metrics.bottom then
        return false, why or "primary text reference unavailable"
    end
    self.primary_centers.weapon = y + (metrics.bottom + metrics.top) / 2
    local x = ammo and ammo.x or 65 * self.scale
    -- All actual Gui measurements supply horizontal ink bounds. Keep older
    -- screen-only fixtures compatible; a model-bound primary needs real ones.
    self.weapon_center_x = finite(metrics.left)
            and finite(metrics.right)
            and metrics.right >= metrics.left
            and x + (metrics.left + metrics.right) / 2
        or nil
    return true
end
function Composition:reticle_clearance()
    local reticle = self.model.reticle
    if not reticle or reticle.known ~= true or not finite(reticle.x) or not finite(reticle.y) then
        return
    end
    local exclusion = self.clearance
    exclusion.left, exclusion.right = reticle.x - 46 * self.pixel, reticle.x + 46 * self.pixel
    exclusion.bottom, exclusion.top = reticle.y - 22 * self.pixel, reticle.y + 22 * self.pixel
    return exclusion
end
function Composition:clear_role(role)
    local group, anchor = self.group_bounds[role], self.anchors[role]
    if role == "central" or group.count == 0 then
        return true
    end
    local exclusion = self:reticle_clearance()
    if not exclusion then
        return true
    end
    offset(self.source_anchor, group, anchor)
    if not overlaps(self.source_anchor, exclusion) then
        return true
    end
    -- Keep the flat group intact and move only this group to the nearest safe
    -- edge. A weapon animation must not move vitals or the shared central shelf.
    local margin = math.max(2, 5 * self.pixel)
    local low_x, high_x = margin - group.left, self.viewport.width - margin - group.right
    local low_y, high_y = margin - group.bottom, self.viewport.height - margin - group.top
    local left, right = exclusion.left - group.right, exclusion.right - group.left
    local bottom, top = exclusion.bottom - group.top, exclusion.top - group.bottom
    if anchor.source == "sights" then
        local outward = role == "vitals" and left or right
        if outward >= low_x and outward <= high_x then
            -- Keep FP primary rows on their configured sight line. A horizontal
            -- offset may need correcting outward, never by dipping the row.
            anchor.x, anchor.clearance = outward, true
            return true
        end
    end
    local distance, x, y = math.huge, anchor.x, anchor.y
    if left >= low_x and left <= high_x then
        distance, x = math.abs(left - anchor.x), left
    end
    if right >= low_x and right <= high_x and math.abs(right - anchor.x) < distance then
        distance, x = math.abs(right - anchor.x), right
    end
    if bottom >= low_y and bottom <= high_y and math.abs(bottom - anchor.y) < distance then
        distance, x, y = math.abs(bottom - anchor.y), anchor.x, bottom
    end
    if top >= low_y and top <= high_y and math.abs(top - anchor.y) < distance then
        distance, x, y = math.abs(top - anchor.y), anchor.x, top
    end
    if distance == math.huge then
        return false, "combat group cannot clear reticle"
    end
    anchor.x, anchor.y, anchor.clearance = x, y, true
    return true
end
-- A stacked presentation has one filtered owner (health), never two smoothing
-- passes. Stable logical shelves keep Quiet/reveal changes from moving the pair;
-- actual measured text, icons, options and cooldowns can only enlarge them.
function Composition:place_stack(replacement, replacement_role)
    local vital, weapon = self.stack_local_vitals, self.stack_local_weapon
    local vg = replacement_role == "vitals" and replacement or self.group_bounds.vitals
    local wg = replacement_role == "weapon" and replacement or self.group_bounds.weapon
    vital.left, vital.right, vital.bottom, vital.top =
        -157 * self.scale, -53 * self.scale, -100 * self.scale, self.health_top + 6 * self.scale
    weapon.left, weapon.right, weapon.bottom, weapon.top =
        60 * self.scale, 173 * self.scale, -142 * self.scale, -30 * self.scale
    if vg.count == nil or vg.count > 0 then
        union(vital, vg)
    end
    if wg.count == nil or wg.count > 0 then
        union(weapon, wg)
    end
    if not finite(self.weapon_center_x) then
        return false, "weapon primary horizontal reference unavailable"
    end
    local va, wa = self.stack_vitals_anchor, self.stack_weapon_anchor
    copy_anchor(va, self.anchors.vitals)
    copy_anchor(wa, self.anchors.weapon)
    local ox, oy = self.settings:get("hud.tfp_ammo_offset_x") or 0, self.settings:get("hud.tfp_ammo_offset_y") or 0
    if not finite(ox) or not finite(oy) or math.abs(ox) > 600 or math.abs(oy) > 600 then
        return false, "TFP offset unavailable"
    end
    wa.x = va.x + self.stack_vitals_center_x - self.stack_weapon_center_x + ox * self.pixel
    local base_y = va.y + vital.top + 12 * self.scale - weapon.bottom
    local shown_top = (vg.count == nil or vg.count > 0) and vg.top or vital.top
    local shown_bottom = (wg.count == nil or wg.count > 0) and wg.bottom or weapon.bottom
    local safe_y = va.y + shown_top + 12 * self.scale - shown_bottom
    -- Positive Y may use the virtual shelf's extra spacing, but never cross
    -- the complete currently displayed health/ammo/options/cooldown envelopes.
    wa.y = math.max(safe_y, base_y - oy * self.pixel)
    local vb, wb, box = self.stack_world_vitals, self.stack_world_weapon, self.stack_bounds
    offset(vb, vital, va)
    offset(wb, weapon, wa)
    copy(box, vb)
    union(box, wb)
    local margin = math.max(2, 5 * self.pixel)
    local low_x, high_x = margin - box.left, self.viewport.width - margin - box.right
    local low_y, high_y = margin - box.bottom, self.viewport.height - margin - box.top
    if low_x > high_x or low_y > high_y then
        return false, "stacked layout exceeds viewport"
    end
    local dx, dy = math.max(low_x, math.min(high_x, 0)), math.max(low_y, math.min(high_y, 0))
    local exclusion = self:reticle_clearance()
    if exclusion then
        if shifted_overlaps(vb, exclusion, dx, dy) or shifted_overlaps(wb, exclusion, dx, dy) then
            local distance, x, y = math.huge, dx, dy
            local left, right = exclusion.left - box.right, exclusion.right - box.left
            local bottom, top = exclusion.bottom - box.top, exclusion.top - box.bottom
            if left >= low_x and left <= high_x then
                distance, x = math.abs(left - dx), left
            end
            if right >= low_x and right <= high_x and math.abs(right - dx) < distance then
                distance, x = math.abs(right - dx), right
            end
            if bottom >= low_y and bottom <= high_y and math.abs(bottom - dy) < distance then
                distance, x, y = math.abs(bottom - dy), dx, bottom
            end
            if top >= low_y and top <= high_y and math.abs(top - dy) < distance then
                distance, x, y = math.abs(top - dy), dx, top
            end
            if distance == math.huge then
                return false, "stacked layout cannot clear reticle"
            end
            dx, dy = x, y
        end
    end
    va.x, va.y, wa.x, wa.y = va.x + dx, va.y + dy, wa.x + dx, wa.y + dy
    copy_anchor(self.anchors.vitals, va)
    copy_anchor(self.anchors.weapon, wa)
    return true
end
function Composition:try_component(component, role)
    local group, anchor = self.group_bounds[role], self.anchors[role]
    copy(self.candidate, component)
    if group.count > 0 then
        union(self.candidate, group)
    end
    if self.stacked and (role == "weapon" or role == "vitals") then
        local placed, why = self:place_stack(self.candidate, role)
        if not placed then
            return nil, why
        end
        copy(group, self.candidate)
        group.count = group.count + 1
        return true
    end
    local margin, b = math.max(2, 5 * self.pixel), self.candidate
    local low_x, high_x = margin - b.left, self.viewport.width - margin - b.right
    local low_y, high_y = margin - b.bottom, self.viewport.height - margin - b.top
    if low_x > high_x or low_y > high_y then
        return nil, "layout exceeds viewport"
    end
    local a = self.candidate_anchor
    copy_anchor(a, anchor)
    a.x, a.y = math.max(low_x, math.min(high_x, anchor.x)), math.max(low_y, math.min(high_y, anchor.y))
    -- A native overview must not drag the tracked combat group to make room.
    if math.abs(a.x - anchor.x) > 8 * self.pixel or math.abs(a.y - anchor.y) > 8 * self.pixel then
        return nil, "presenter requires moving combat HUD"
    end
    local exclusion = self:reticle_clearance()
    if exclusion then
        -- Test each measured component, not the empty rectangle between a side
        -- column and its wider row below. Also recheck the existing column at
        -- the candidate origin so an allowed clamp cannot move it into aim.
        offset(self.source_anchor, component, a)
        if overlaps(self.source_anchor, exclusion) then
            return nil, "presenter overlaps reticle clearance"
        end
        if group.count > 0 then
            offset(self.source_anchor, group, a)
            if overlaps(self.source_anchor, exclusion) then
                return nil, "presenter overlaps reticle clearance"
            end
        end
    end
    local sight = self.sight_clearance
    if a.source == "sights" and sight.active then
        offset(self.source_anchor, component, a)
        if overlaps(self.source_anchor, sight.bounds) then
            return nil, "presenter overlaps sight aperture"
        end
        if group.count > 0 then
            offset(self.source_anchor, group, a)
            if overlaps(self.source_anchor, sight.bounds) then
                return nil, "presenter overlaps sight aperture"
            end
        end
    end
    copy(group, self.candidate)
    group.count = group.count + 1
    copy_anchor(anchor, a)
    self:commit_sight(role, anchor)
    return true
end
function Composition:prepare_strip(geometry, metrics)
    local view, model = self.view, self.model
    self.strip_ready = view.native_options ~= false
        and metrics
        and metrics.ready == true
        and finite(metrics.count)
        and metrics.count % 1 == 0
        and metrics.count > 0
        and metrics.count <= 4
        and metrics.root == model.identity
        and (metrics.generation == nil or metrics.generation == model.generation)
        and finite(metrics.width)
        and finite(metrics.height)
        and metrics.width > 0
        and metrics.height > 0
    if not self.strip_ready then
        return
    end
    local b, group, placed = self.strip_bounds, self.group_bounds.weapon, geometry.strip_bounds
    if placed and placed.valid == true and bounds(placed) then
        copy(b, placed)
    else
        -- Legacy pure callers provide just a measured row and local envelope.
        b.left, b.bottom = 65 * self.scale, math.min(group.bottom, -120 * self.scale) - metrics.height
        b.right, b.top = b.left + metrics.width, b.bottom + metrics.height
    end
end
function Composition:stack_centers()
    local vital, weapon = self.stack_visual_vitals, self.stack_visual_weapon
    local vg, wg = self.group_bounds.vitals, self.group_bounds.weapon
    if vg.count > 0 then
        copy(vital, vg)
    else
        vital.left, vital.right = -157 * self.scale, -53 * self.scale
    end
    self.stack_weapon_visible = wg.count > 0
    if self.stack_weapon_visible then
        copy(weapon, wg)
    else
        weapon.left, weapon.right = 60 * self.scale, 173 * self.scale
    end
    -- Frozen before any cooldown packet expands either measured group. Only
    -- current visible glyphs, heat/coil and the original options row center the
    -- stack; hidden health uses its stable logical bracket reference.
    self.stack_vitals_center_x = (vital.left + vital.right) / 2
    self.stack_weapon_center_x = (weapon.left + weapon.right) / 2
end
function Composition:begin(geometry, model, view, settings, viewport, metrics, measure, dt)
    self.valid, self.has_strip, self.has_cooldowns = false, false, false
    self.cooldown_packet, self.strip_reason, self.cooldown_reason = nil, nil, nil
    if not geometry or not geometry.valid or not bounds(geometry.bounds) then
        self:reset_motion()
        return false, "combat bounds unavailable"
    end
    local height = viewport and viewport.height
    if not finite(height) or height <= 0 then
        self:reset_motion()
        return false, "viewport unavailable"
    end
    self.model, self.view, self.settings, self.viewport = model, view, settings, viewport
    self.pixel = height / 1080
    self.scale = self.pixel * (settings:get("hud.scale") or 100) / 100
    if not finite(self.scale) or self.scale <= 0 then
        self:reset_motion()
        return false, "composition scale unavailable"
    end
    copy(self.base, geometry.bounds)
    local measured, measurement_reason = self:measure_primary(geometry, measure)
    if not measured then
        self:reset_motion()
        return false, measurement_reason
    end
    local root, root_reason = Anchor.target_role(model, settings, viewport, self.base, "central")
    if not root then
        self:reset_motion()
        return false, root_reason
    end
    -- The weapon role chooses sight rails independently of the raw camera
    -- profile. TrueFP hip still needs a right-hand rail; central stays reticle.
    copy(self.sight_target_bounds, self.base)
    local sight_root = Anchor.target_role(model, settings, viewport, self.sight_target_bounds, "weapon") or root
    if Anchor.true_first_person(model) and sight_root.source == "sights" then
        -- Role tuning moves the readout, never the optic's physical screen band.
        sight_root.x = sight_root.x - (settings:get("hud.tfp_ammo_offset_x") or 0) * self.pixel
        sight_root.y = sight_root.y + (settings:get("hud.tfp_ammo_offset_y") or 0) * self.pixel
    end
    self:prepare_sight(geometry, sight_root)
    self.motion:begin(model, settings, viewport, dt)
    self.stacked = Anchor.true_first_person(model) and settings:get("hud.tfp_ammo_placement") == 2
    for _, role in ipairs(ROLES) do
        local group = self.group_bounds[role]
        local source = geometry.group_bounds and geometry.group_bounds[role]
        if source then
            if not bounds(source) then
                self:reset_motion()
                return false, "combat group bounds unavailable"
            end
            copy(group, source)
            group.count = source.count or 1
        elseif not geometry.group_bounds and role == "central" then
            -- Compatibility for callers with a single measured local envelope.
            copy(group, geometry.bounds)
            group.count = #geometry.primitives > 0 and #geometry.primitives or 0
        else
            group.left, group.right, group.bottom, group.top, group.count = 0, 0, 0, 0, 0
        end
    end
    self:prepare_strip(geometry, metrics)
    if self.stacked then
        self:stack_centers()
    end
    for _, role in ipairs(self.stacked and STACK_ROLES or ROLES) do
        local group = self.group_bounds[role]
        local target, why = Anchor.target_role(model, settings, viewport, group, role)
        if not target then
            self:reset_motion()
            return false, why
        end
        local center = self.primary_centers[role] or 0
        local inward = self.inward_edges[role] or 0
        local reference_x = inward
        -- Track the displayed primary reference across profiles. Hip/TP retain
        -- their existing bone-relative origin; FP targets the sight line itself.
        -- The inverse transform after filtering keeps glyph changes aligned and
        -- avoids a profile-entry jump from adding a post-filter vertical lift.
        if target.source == "tfp_vitals" then
            target.x = target.x - 96 * self.scale
            reference_x = self.health_center_x
        elseif target.source == "weapon_sight" then
            if not finite(self.weapon_center_x) then
                self:reset_motion()
                return false, "weapon primary horizontal reference unavailable"
            end
            -- The primary center sits beside the current model attachment,
            -- independently of the reticle and adaptive screen sight aperture.
            -- Filter the physical primary center itself. Current text bearings
            -- and meter orientation affect only the post-filter local origin.
            target.x = target.x + 96 * self.scale
            reference_x = self.weapon_center_x
        elseif target.source ~= "sights" or role == "central" then
            target.y = target.y + center
            target.x = target.x + inward
        elseif role ~= "central" then
            target.x = role == "vitals" and math.min(target.x - 96 * self.scale, self.sight_clearance.bounds.left)
                or math.max(target.x + 96 * self.scale, self.sight_clearance.bounds.right)
        end
        if target.source == "above_health" then
            -- A separately selected ammo point is ignored in this mode. Retire
            -- independent weapon history so switching back cannot resume it.
            self.motion:filter(role, nil)
            self.filtered[role] = nil
            copy_anchor(self.anchors[role], target)
        else
            local filtered = self.motion:filter(role, target)
            self.filtered[role] = filtered
            local a = self.anchors[role]
            copy_anchor(a, filtered)
            a.clearance = false
            a.x = a.x - reference_x
            a.y = a.y - center
            local clamped, problem = Anchor.clamp(viewport, group, a, a)
            if not clamped then
                self:reset_motion()
                return false, problem
            end
            self:apply_sight(role, a)
            local clear, reason = self:clear_role(role)
            if not clear then
                self:reset_motion()
                return false, reason
            end
            self:commit_sight(role, a)
        end
    end
    if self.stacked then
        local placed, why = self:place_stack()
        if not placed then
            self:reset_motion()
            return false, why
        end
    end
    if self.strip_ready then
        local old_center = self.stack_weapon_center_x
        if self.stacked then
            local visual = self.stack_visual_weapon
            local left = self.stack_weapon_visible and math.min(visual.left, self.strip_bounds.left)
                or self.strip_bounds.left
            local right = self.stack_weapon_visible and math.max(visual.right, self.strip_bounds.right)
                or self.strip_bounds.right
            self.stack_weapon_center_x = (left + right) / 2
        end
        local placed, problem = self:try_component(self.strip_bounds, "weapon")
        if placed then
            if self.stacked then
                if self.stack_weapon_visible then
                    union(self.stack_visual_weapon, self.strip_bounds)
                else
                    copy(self.stack_visual_weapon, self.strip_bounds)
                end
            end
            self.has_strip = true
            local spec = self.weapon
            spec.edge, spec.gap = metrics.edge, metrics.gap
            spec.root, spec.generation, spec.source_revision = model.identity, model.generation, metrics.source_revision
        else
            self.stack_weapon_center_x = old_center
            self.strip_reason = problem
        end
    end
    self.cooldown_role = settings:get("hud.cooldown_anchor") == 2 and "weapon" or "vitals"
    self.cooldown_anchor = self.anchors[self.cooldown_role]
    local group = self.group_bounds[self.cooldown_role]
    local weapon_side = self.cooldown_role == "weapon"
    local center = (weapon_side and 116.5 or -105) * self.scale
    local half = (weapon_side and 56.5 or 52) * self.scale
    local bottom = (weapon_side and -142 or -100) * self.scale
    -- Reserve the whole logical health/supplies or ammo/options shelf even when
    -- Quiet hides its cells. Outliers expand symmetrically around its fixed
    -- center, so digit/icon counts and shadow bearings cannot recenter the dock.
    if group.count > 0 then
        half = math.max(half, center - group.left, group.right - center)
        bottom = math.min(bottom, group.bottom)
    end
    self.combat_bounds.left, self.combat_bounds.right = center - half, center + half
    self.combat_bounds.bottom, self.combat_bounds.top = bottom, group.count > 0 and group.top or 0
    local request = self.cooldown_options
    request.identity, request.generation, request.scale, request.pixel =
        model.identity, model.generation, self.scale * 0.75, self.pixel
    request.font, request.measure, request.combat_bounds = view.font, measure, self.combat_bounds
    request.enabled = view.native_cooldowns ~= false
    request.ready = view.ready
    self.valid = true
    return true
end
function Composition:include_cooldowns(packet)
    self.has_cooldowns, self.cooldown_packet = false, nil
    if self.view.native_cooldowns == false then
        return true
    end
    if not self.valid then
        return false, "composition unavailable"
    end
    if not packet then
        return false, "cooldown layout unavailable"
    end
    if
        packet.valid ~= true
        or packet.identity ~= self.model.identity
        or packet.generation ~= self.model.generation
        or not bounds(packet.bounds)
    then
        self.cooldown_reason = packet.reason or "cooldown packet identity/bounds unavailable"
        return false, self.cooldown_reason
    end
    if packet.has_content ~= true then
        return true
    end
    local okay, why = self:try_component(packet.bounds, self.cooldown_role)
    if not okay then
        self.cooldown_reason = why
        return false, why
    end
    self.cooldown_packet, self.has_cooldowns = packet, true
    return true
end
function Composition:weapon_placement()
    if not self.valid or not self.has_strip then
        return
    end
    local spec, a = self.weapon, self.anchors.weapon
    spec.x, spec.y, spec.opacity = a.x + self.strip_bounds.left, a.y + self.strip_bounds.bottom, self.view.opacity
    return spec
end
function Composition:assemble(base_geometry)
    local out = self.geometry
    out.valid, out.visible = self.valid, self.view.visible == true or self.has_strip or self.has_cooldowns
    out.supplies = base_geometry.supplies
    local used = 0
    for _, p in ipairs(base_geometry.primitives) do
        used = used + 1
        out.primitives[used] = p
    end
    if self.has_cooldowns then
        for _, p in ipairs(self.cooldown_packet.primitives or {}) do
            local key = "cooldown/" .. p.key
            local q = self.slots[key]
            if not q then
                q = {}
                self.slots[key] = q
            end
            for name, value in pairs(p) do
                q[name] = value
            end
            local a = self.cooldown_anchor
            q.key, q.x, q.y, q.group = key, p.x + a.x, p.y + a.y, self.cooldown_role
            q.alpha = (p.alpha or 1) * (self.view.opacity or 1)
            used = used + 1
            out.primitives[used] = q
        end
    end
    for i = #out.primitives, used + 1, -1 do
        out.primitives[i] = nil
    end
    local occupied = false
    for _, role in ipairs(ROLES) do
        local group = self.group_bounds[role]
        if group.count > 0 then
            offset(self.source_anchor, group, self.anchors[role])
            if occupied then
                union(out.bounds, self.source_anchor)
            else
                copy(out.bounds, self.source_anchor)
                occupied = true
            end
        end
    end
    if not occupied then
        out.bounds.left, out.bounds.right, out.bounds.bottom, out.bounds.top =
            self.anchor.x, self.anchor.x, self.anchor.y, self.anchor.y
    end
    copy(self.bounds, out.bounds)
    out.group_bounds = self.group_bounds
    local v = self.render_view
    v.visible, v.opacity, v.font, v.weapon_options = out.visible, self.view.opacity, self.view.font, false
    return out, v
end
return Composition
