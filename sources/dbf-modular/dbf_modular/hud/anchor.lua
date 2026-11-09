-- Pure physical-pixel placement. bounds are LOCAL measured layout extents.
-- Returns {x,y,profile,source}; nil on unknown ownership/reticle or oversized HUD.
-- Settings offsets are 1080p pixels, positive Y DOWN. No memory/input/drawing.
local Anchor = {}
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function point(value)
    return type(value) == "table"
        and value.known == true
        and value.clipped ~= true
        and finite(value.x)
        and finite(value.y)
end
local function integer(value, low, high)
    return finite(value) and value >= low and value <= high and value % 1 == 0
end
local function owned_point(value, model)
    if not point(value) then
        return false
    end
    local metadata = value.token ~= nil
        or value.generation ~= nil
        or value.identity ~= nil
        or value.context ~= nil
        or value.camera ~= nil
        or value.unit ~= nil
        or value.unit_domain ~= nil
        or value.node ~= nil
        or value.actor_id ~= nil
    if not metadata then
        -- Old pure callers supplied just known/x/y; no retained model history is
        -- consulted. Production attachment DTOs always carry the complete owner.
        return true
    end
    return value.identity == model.identity
        and value.generation == model.generation
        and type(value.token) == "string"
        and value.token ~= ""
        and integer(value.context, 65536, 2 ^ 47 - 1)
        and integer(value.camera, 65536, 2 ^ 47 - 1)
        and integer(value.unit, 1, 4294967294)
        and integer(value.actor_id, 0, 4294967294)
        and integer(value.node, 0, 4095)
end
local function current_point(value, model, peer)
    if not owned_point(value, model) then
        return false
    end
    -- Gun swaps must not invalidate the actor's independent body. Only common
    -- actor/camera disagreement between two otherwise current points fails closed.
    if peer and owned_point(peer, model) then
        if value.actor_id ~= nil and peer.actor_id ~= nil and value.actor_id ~= peer.actor_id then
            return false
        end
        if value.camera ~= nil and peer.camera ~= nil and value.camera ~= peer.camera then
            return false
        end
        if value.context ~= nil and peer.context ~= nil and value.context ~= peer.context then
            return false
        end
    end
    return true
end
-- The provider annotation is published only after fresh camera/FPS checks.
function Anchor.true_first_person(model)
    return model ~= nil
        and model.known == true
        and model.aim ~= nil
        and model.aim.true_first_person == true
        and model.aim.viewmodel_active == true
        and integer(model.anchor_context, 65536, 2 ^ 47 - 1)
        and integer(model.anchor_camera, 65536, 2 ^ 47 - 1)
        and integer(model.aim.viewmodel_unit, 1, 4294967294)
        and type(model.aim.true_first_person_token) == "string"
        and model.aim.true_first_person_token ~= ""
end
local function tfp_unit_current(value, model)
    local domain = value and value.unit_domain
    local expected = domain == "fps" and model.aim.viewmodel_unit or domain == "weapon" and model.aim.weapon_unit
    -- The expected handle comes from a separately validated sampler stamp,
    -- never another field on the projected point authorizing itself.
    return integer(expected, 1, 4294967294) and value.unit == expected
end
function Anchor.vitals_point(model)
    local value = model and model.anchors and model.anchors.tfp_vitals
    if
        Anchor.true_first_person(model)
        and current_point(value, model, model.anchors and model.anchors.viewmodel)
        and type(value.token) == "string"
        and value.token ~= ""
        and value.context == model.anchor_context
        and value.camera == model.anchor_camera
        and tfp_unit_current(value, model)
    then
        return value
    end
end
function Anchor.weapon_sight_point(model)
    local value = model and model.anchors and model.anchors.viewmodel
    if
        Anchor.true_first_person(model)
        and current_point(value, model, model.anchors and model.anchors.tfp_vitals)
        and type(value.token) == "string"
        and value.token ~= ""
        and value.context == model.anchor_context
        and value.camera == model.anchor_camera
        and tfp_unit_current(value, model)
    then
        return value
    end
end
local function get(settings, key, default)
    local value = settings and settings:get(key)
    if value == nil then
        return default
    end
    return value
end
function Anchor.resolve(model, settings, viewport, bounds)
    if
        not model
        or model.known ~= true
        or not model.aim
        or model.aim.known ~= true
        or type(model.aim.first_person) ~= "boolean"
        or type(model.aim.aiming) ~= "boolean"
    then
        return nil, "aim unavailable"
    end
    local width, height = viewport and viewport.width, viewport and viewport.height
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
        return nil, "viewport unavailable"
    end
    if
        not bounds
        or not finite(bounds.left)
        or not finite(bounds.right)
        or not finite(bounds.bottom)
        or not finite(bounds.top)
        or bounds.right < bounds.left
        or bounds.top < bounds.bottom
    then
        return nil, "measured bounds unavailable"
    end
    local profile = model.aim.first_person and "first_person" or model.aim.aiming and "aim" or "hip"
    local selected, source, choice = model.reticle, "reticle", get(settings, "hud.anchor", 2)
    if profile ~= "first_person" and choice == 1 then
        local anchors = model.anchors or {}
        local follow = model.aim.switching == false and model.weapon and model.weapon.reloading == false
        if profile == "aim" then
            if follow and point(anchors.weapon) then
                selected, source = anchors.weapon, "weapon"
            end
        elseif follow and point(anchors.body) then
            selected, source = anchors.body, "body"
        end
    elseif choice == 3 then
        source = "beside"
    end
    if not point(selected) then
        return nil, "reticle unavailable"
    end
    local scale = height / 1080
    local x, y = selected.x, selected.y
    if source == "beside" then
        x = x + 120 * scale
    end
    local ox, oy = get(settings, "hud.offset_x", 0), get(settings, "hud.offset_y", 0)
    if profile ~= "hip" then
        local ads_x, ads_y = get(settings, "hud.ads_offset_x", 0), get(settings, "hud.ads_offset_y", 0)
        if not finite(ox) or not finite(oy) or not finite(ads_x) or not finite(ads_y) then
            return nil, "offset unavailable"
        end
        ox, oy = ox + ads_x, oy + ads_y
    end
    if not finite(ox) or not finite(oy) then
        return nil, "offset unavailable"
    end
    x, y = x + ox * scale, y - oy * scale
    local margin = math.max(2, 5 * scale)
    local low_x, high_x = margin - bounds.left, width - margin - bounds.right
    local low_y, high_y = margin - bounds.bottom, height - margin - bounds.top
    if low_x > high_x or low_y > high_y then
        return nil, "layout exceeds viewport"
    end
    local out = bounds.anchor
    if not out then
        out = {}
        bounds.anchor = out
    end
    out.x, out.y = math.max(low_x, math.min(high_x, x)), math.max(low_y, math.min(high_y, y))
    out.source, out.profile = source, profile
    return out
end

-- Raw role points precede the primary-reference adapter and measured clamp.
-- These records contain projected pixels and identity scalars, never native poses.
function Anchor.target_role(model, settings, viewport, bounds, role)
    if role ~= "weapon" and role ~= "vitals" and role ~= "central" then
        return nil, "anchor role unavailable"
    end
    if
        not model
        or model.known ~= true
        or not model.aim
        or model.aim.known ~= true
        or type(model.aim.first_person) ~= "boolean"
        or type(model.aim.aiming) ~= "boolean"
    then
        return nil, "aim unavailable"
    end
    local width, height = viewport and viewport.width, viewport and viewport.height
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
        return nil, "viewport unavailable"
    end
    if
        not bounds
        or not finite(bounds.left)
        or not finite(bounds.right)
        or not finite(bounds.bottom)
        or not finite(bounds.top)
        or bounds.right < bounds.left
        or bounds.top < bounds.bottom
    then
        return nil, "measured bounds unavailable"
    end
    local first_person = model.aim.first_person or (model.aim.aiming and model.aim.viewmodel_active == true)
    local profile = first_person and "first_person" or model.aim.aiming and "aim" or "hip"
    local selected, source, fallback = model.reticle, "reticle", false
    local choice = get(settings, "hud.anchor", 1)
    local tfp = Anchor.true_first_person(model)
    if tfp and role == "weapon" and get(settings, "hud.tfp_ammo_placement", 1) == 2 then
        -- Composition derives the displayed stack from the filtered vitals
        -- group; the separately selected ammo bone cannot steer this mode.
        local vital = Anchor.vitals_point(model)
        if vital then
            selected = vital
        else
            fallback = true
        end
        source = "above_health"
    elseif tfp and role == "weapon" then
        local sight = Anchor.weapon_sight_point(model)
        if sight then
            selected, source = sight, "weapon_sight"
        else
            source, fallback = "sights", true
        end
    elseif tfp and role == "vitals" then
        local vital = Anchor.vitals_point(model)
        if vital then
            selected, source = vital, "tfp_vitals"
        else
            local anchors = model.anchors or {}
            if current_point(anchors.body, model, anchors.weapon) then
                selected, source = anchors.body, "body"
            end
            fallback = true
        end
    elseif role ~= "central" then
        if profile == "first_person" then
            -- The sight line is already sampled, including the known viewport
            -- center when the native crosshair is hidden. FP rig projection is
            -- mode/owner evidence, never a coordinate dependency for these rails.
            source = "sights"
        elseif choice == 1 then
            local anchors = model.anchors or {}
            if role == "weapon" and profile == "aim" and current_point(anchors.weapon, model, anchors.body) then
                selected, source = anchors.weapon, "weapon"
            elseif current_point(anchors.body, model, anchors.weapon) then
                selected, source = anchors.body, "body"
                fallback = role == "weapon" and profile == "aim"
            else
                fallback = true
            end
        elseif choice == 3 then
            source = "beside"
        end
    end
    if not current_point(selected, model) then
        return nil, "reticle unavailable"
    end
    local scale = height / 1080
    local x, y = selected.x + (source == "beside" and 120 * scale or 0), selected.y
    local ox, oy = get(settings, "hud.offset_x", 0), get(settings, "hud.offset_y", 0)
    if not finite(ox) or not finite(oy) then
        return nil, "offset unavailable"
    end
    if profile ~= "hip" then
        local ax, ay = get(settings, "hud.ads_offset_x", 0), get(settings, "hud.ads_offset_y", 0)
        if not finite(ax) or not finite(ay) then
            return nil, "offset unavailable"
        end
        ox, oy = ox + ax, oy + ay
    end
    if tfp and role ~= "central" then
        local rx = role == "vitals" and get(settings, "hud.tfp_vitals_offset_x", 0)
            or get(settings, "hud.tfp_ammo_offset_x", 0)
        local ry = role == "vitals" and get(settings, "hud.tfp_vitals_offset_y", 0)
            or get(settings, "hud.tfp_ammo_offset_y", 0)
        if not finite(rx) or not finite(ry) or math.abs(rx) > 600 or math.abs(ry) > 600 then
            return nil, "TFP offset unavailable"
        end
        -- The stacked presenter applies ammo offsets relative to displayed
        -- health. All other owned/fallback role points receive them here once.
        if source ~= "above_health" then
            ox, oy = ox + rx, oy + ry
        end
    end
    x, y = x + ox * scale, y - oy * scale
    local out = bounds.target
    if not out then
        out = {}
        bounds.target = out
    end
    out.x, out.y, out.source, out.profile = x, y, source, profile
    local owner = selected
    if source == "sights" then
        local viewmodel = model.anchors and model.anchors.viewmodel
        if
            integer(model.anchor_camera, 65536, 2 ^ 47 - 1)
            and integer(model.anchor_context, 65536, 2 ^ 47 - 1)
            and integer(model.aim.viewmodel_unit, 1, 4294967294)
        then
            -- Adaptive rails have no dependency on an unused FPS point. Their
            -- explicit fresh mode/owner stamps still reset smoothing correctly.
            out.camera, out.context = model.anchor_camera, model.anchor_context
            out.token = string.format("viewmodel:%.0f:%.0f:%.0f", out.camera, out.context, model.aim.viewmodel_unit)
            owner = nil
        elseif owned_point(viewmodel, model) then
            owner = viewmodel
        end
    end
    if owner then
        out.camera, out.context, out.token = owner.camera, owner.context, owner.token
    end
    if tfp then
        out.token = model.aim.true_first_person_token .. ":" .. (out.token or "reticle")
    end
    out.follow_token = model.follow_token
    out.tracking = (tfp or choice == 1) and role ~= "central" and source ~= "reticle" and not fallback
    out.fallback = fallback
    return out
end

function Anchor.clamp(viewport, bounds, target, output)
    local width, height = viewport and viewport.width, viewport and viewport.height
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
        return nil, "viewport unavailable"
    end
    if not target or not finite(target.x) or not finite(target.y) then
        return nil, "anchor target unavailable"
    end
    if
        not bounds
        or not finite(bounds.left)
        or not finite(bounds.right)
        or not finite(bounds.bottom)
        or not finite(bounds.top)
        or bounds.right < bounds.left
        or bounds.top < bounds.bottom
    then
        return nil, "measured bounds unavailable"
    end
    local margin = math.max(2, 5 * height / 1080)
    local low_x, high_x = margin - bounds.left, width - margin - bounds.right
    local low_y, high_y = margin - bounds.bottom, height - margin - bounds.top
    if low_x > high_x or low_y > high_y then
        return nil, "layout exceeds viewport"
    end
    local out = output or bounds.anchor
    if not out then
        out = {}
        bounds.anchor = out
    end
    out.x, out.y = math.max(low_x, math.min(high_x, target.x)), math.max(low_y, math.min(high_y, target.y))
    out.source, out.profile = target.source, target.profile
    return out
end

-- Stateless compatibility entry point. Legacy Anchor.resolve above is unchanged.
function Anchor.resolve_role(model, settings, viewport, bounds, role)
    local target, why = Anchor.target_role(model, settings, viewport, bounds, role)
    if not target then
        return nil, why
    end
    return Anchor.clamp(viewport, bounds, target)
end

local Tracker = {}
Tracker.__index = Tracker
local TFP_MOTION_SETTINGS = {
    "hud.tfp_vitals_bone",
    "hud.tfp_ammo_bone",
    "hud.tfp_ammo_placement",
    "hud.tfp_vitals_offset_x",
    "hud.tfp_vitals_offset_y",
    "hud.tfp_ammo_offset_x",
    "hud.tfp_ammo_offset_y",
}
local function copy_target(out, target)
    out.x, out.y, out.source, out.profile = target.x, target.y, target.source, target.profile
    out.camera, out.context, out.token = target.camera, target.context, target.token
    out.follow_token, out.tracking, out.fallback = target.follow_token, target.tracking, target.fallback
end
function Tracker.new()
    return setmetatable({
        frame = 0,
        tfp_config = {},
        next_tfp_config = {},
        roles = {
            weapon = { output = {} },
            vitals = { output = {} },
            central = { output = {} },
        },
    }, Tracker)
end
function Tracker:reset()
    self.follow_token, self.identity, self.generation, self.width, self.height, self.choice, self.mode_token =
        nil, nil, nil, nil, nil, nil, nil
    for _, state in pairs(self.roles) do
        state.active, state.frame, state.valid = false, nil, false
    end
    for i = 1, #TFP_MOTION_SETTINGS do
        self.tfp_config[i] = nil
    end
end
function Tracker:begin(model, settings, viewport, dt)
    self.frame = self.frame + 1
    local token = model and model.follow_token
    local choice, width, height =
        get(settings, "hud.anchor", 1), viewport and viewport.width, viewport and viewport.height
    local mode_token = Anchor.true_first_person(model) and model.aim.true_first_person_token or nil
    local config_changed = false
    for i, key in ipairs(TFP_MOTION_SETTINGS) do
        local value = mode_token and get(settings, key, i <= 3 and 1 or 0) or nil
        self.next_tfp_config[i] = value
        config_changed = config_changed or value ~= self.tfp_config[i]
    end
    if
        not model
        or model.known ~= true
        or type(token) ~= "string"
        or token == ""
        or token ~= self.follow_token
        or model.identity ~= self.identity
        or model.generation ~= self.generation
        or choice ~= self.choice
        or mode_token ~= self.mode_token
        or config_changed
        or width ~= self.width
        or height ~= self.height
    then
        self:reset()
    end
    self.follow_token = model and model.known == true and type(token) == "string" and token ~= "" and token or nil
    self.identity, self.generation = model and model.identity, model and model.generation
    self.choice, self.width, self.height = choice, width, height
    self.mode_token = mode_token
    for i = 1, #TFP_MOTION_SETTINGS do
        self.tfp_config[i] = self.next_tfp_config[i]
    end
    local ms = get(settings, "hud.anchor_damping_ms", 80)
    if not finite(ms) or ms < 0 or ms > 300 then
        ms = 80
    end
    dt = finite(dt) and math.max(0, math.min(dt, 1)) or 0
    self.alpha = ms == 0 and 1 or 1 - math.exp(-dt / (ms / 1000))
end
function Tracker:filter(role, target, output)
    local state = self.roles[role]
    if not state then
        return nil, "anchor role unavailable"
    end
    local retained = state.output
    if state.frame ~= self.frame then
        state.frame = self.frame
        state.valid = target ~= nil and finite(target.x) and finite(target.y)
        if not state.valid then
            state.active = false
            return nil, "anchor target unavailable"
        end
        local tracking = target.tracking == true
            and self.follow_token ~= nil
            and target.follow_token == self.follow_token
            and role ~= "central"
        local same = state.active
            and tracking
            and retained.camera == target.camera
            and retained.context == target.context
            and (self.mode_token == nil or retained.token == target.token)
            and not (
                retained.source == target.source
                and retained.profile == target.profile
                and retained.token ~= target.token
            )
        local x, y = target.x, target.y
        if same then
            x, y = retained.x + (x - retained.x) * self.alpha, retained.y + (y - retained.y) * self.alpha
        end
        copy_target(retained, target)
        retained.x, retained.y, state.active = x, y, tracking
    end
    if not state.valid then
        return nil, "anchor target unavailable"
    end
    local out = output or retained
    if out ~= retained then
        copy_target(out, retained)
    end
    return out
end
Anchor.Tracker = Tracker
return Anchor
