-- Real sampler/native ownership seam: custom TFP hip is not native ADS.
local Fixture = assert(loadfile("tests/sampling_fixture.lua"))()
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function fixture()
    local f = Fixture.new()
    f.sample_options = { tfp_vitals_bone = 2, tfp_ammo_bone = 1, tfp_ammo_placement = 1 }
    f.set_camera_request(6)
    f.mode = { mode = "pose_offset", phase = "running", enabled = true, cleanup_pending = false }
    f.polls = 0
    f.globals.NativeADSCameraTest = {
        status = function()
            f.polls = f.polls + 1
            return "True FP active", f.mode
        end,
    }
    local m = f:sample(2, true)
    -- Adaptive sight support normally skips the unused point. TFP needs it.
    f.sampler.native.geometry_ready = function()
        error("TFP must not collect optic bounds")
    end
    f.sampler.native.unit_box = function()
        error("TFP must not collect optic bounds")
    end
    f.sampler.native.project_points = function()
        error("TFP must not collect optic bounds")
    end
    return f, m
end
for _, aim in ipairs({ false, true }) do
    local f = fixture()
    f.action(f.n.aim_action_bit, aim)
    local before = f.polls
    local m = f:sample(2, true)
    eq(f.polls, before + 1, "one public mode poll")
    eq(m.known, true)
    eq(m.aim.first_person, false, "raw native ADS bit remains separate")
    eq(m.aim.aiming, aim)
    eq(m.aim.true_first_person, true)
    eq(m.aim.viewmodel_active, true)
    eq(m.anchors.tfp_vitals.known, true)
    eq(m.anchors.tfp_vitals.unit, f.viewmodel_engine)
    eq(m.anchors.tfp_vitals.x, f.left_arm_point.x)
    eq(m.anchors.tfp_vitals.y, f.left_arm_point.y)
    eq(m.anchors.viewmodel.known, true, "ammo follows an actual FPS weapon attachment")
    eq(m.anchors.viewmodel.unit, f.viewmodel_engine)
    eq(m.anchors.viewmodel.x, f.viewmodel_point.x)
    eq(m.anchors.viewmodel.y, f.viewmodel_point.y)
    eq(m.anchors.viewmodel.local_offset.y, 0.5, "weapon point preserves the proven model-local calibration")
    eq(type(m.aim.true_first_person_token), "string")
    eq(m.sight_clearance.known, false)
    eq(m.weapon.count, 31)
end
for _, mutation in ipairs({ "mode_off", "native_ads", "provider", "weapon", "camera", "unit", "projection" }) do
    local f = fixture()
    if mutation == "mode_off" then
        f.mode.phase = "waiting"
    elseif mutation == "native_ads" then
        f.mode.mode = "native_ads"
    elseif mutation == "projection" then
        f.project_failure = f.viewmodel_engine
    else
        f.after_project = function()
            if mutation == "provider" then
                f.globals.NativeADSCameraTest = {}
            elseif mutation == "weapon" then
                f.uint(f.inventory_row, 91)
                f.uint(f.selector_row, 91)
            elseif mutation == "camera" then
                f.pointer(f.camera_manager, f.camera + 4096)
            else
                f.uint(f.controller + f.n.avatar_viewmodel_offset, f.viewmodel_engine + 1)
            end
        end
    end
    local m = f:sample(2, true)
    eq(m.aim.true_first_person, mutation == "projection", mutation .. " retains only a proven FPS owner")
    eq(m.aim.true_first_person_token ~= nil, mutation == "projection")
    eq(m.anchors.tfp_vitals.known, false)
    eq(m.anchors.viewmodel.known, false, "failed ownership never publishes a partially valid batch")
    eq(m.weapon.count, 31, "readout remains available on attachment fallback")
end
local f = fixture()
f.uint(f.camera_request + 8, 91)
local before = #f.projections
local m = f:sample(2, true)
eq(m.aim.true_first_person, false)
eq(#f.projections, before, "foreign camera request must not reach a getter")
eq(f.sampler:close(), true)
eq(f.sampler.first_person_mode:current(), false)
-- Role-local visibility failures do not turn off the actual applied mode or
-- move the other readout onto the failed role's last point.
for _, hash in ipairs({ f.n.viewmodel_left_arm_node, f.n.viewmodel_weapon_node }) do
    local f = fixture()
    f.project_failure_hash = hash
    local m = f:sample(2, true)
    eq(m.aim.true_first_person, true)
    eq(m.anchors.tfp_vitals.known, hash ~= f.n.viewmodel_left_arm_node)
    eq(m.anchors.viewmodel.known, hash ~= f.n.viewmodel_weapon_node)
end
-- Three full guards for the first point and three rig guards for the second
-- match the actual Native getter protocol, including per-getter mutations.
for _, field in ipairs({ "actor", "controller", "fps", "camera", "provider" }) do
    local f = fixture()
    f.project_validations = 5
    local second_getters = 0
    f.after_unit_getter = function(unit, hash, ordinal)
        if hash ~= f.n.viewmodel_weapon_node then
            return
        end
        second_getters = second_getters + 1
        if ordinal ~= 1 then
            return
        end
        if field == "actor" then
            f.uint(f.actor_record + 16, 123)
        elseif field == "controller" then
            f.uint(f.controller + f.n.avatar_controller_dive_identity_offset, 123)
        elseif field == "fps" then
            f.uint(f.controller + f.n.avatar_viewmodel_offset, unit + 1)
        elseif field == "camera" then
            f.pointer(f.camera_manager, f.camera + 4096)
        else
            f.globals.NativeADSCameraTest = {}
        end
    end
    local m = f:sample(2, true)
    eq(second_getters, 1, field .. " replacement blocks the next Unit getter")
    eq(m.anchors.tfp_vitals.known, false)
    eq(m.anchors.viewmodel.known, false)
    eq(m.aim.true_first_person, false)
    eq(f.sampler.r.reads <= 512, true)
end
-- A wield change need not invalidate this actor's live FPS rig during getters,
-- but the full post-batch weapon proof must discard BOTH copied points.
f = fixture()
f.project_validations = 5
f.after_unit_getter = function(_, hash, ordinal)
    if hash == f.n.viewmodel_weapon_node and ordinal == 1 then
        f.uint(f.selector_row, 91)
    end
end
m = f:sample(2, true)
eq(m.anchors.tfp_vitals.known, false)
eq(m.anchors.viewmodel.known, false)
eq(m.aim.true_first_person, false)
eq(f.sampler.r.reads <= 512, true)
-- Default1/1 is the same fresh chassis point for two independent role DTOs.
f = fixture()
f.sample_options = nil
local count = #f.projections
m = f:sample(2, true)
eq(#f.projections - count, 1, "identical whole bone+offset request is sampled once")
eq(m.anchors.left_arm, nil, "retired internal DTO has no compatibility alias")
eq(m.anchors.tfp_vitals.known, true)
eq(m.anchors.viewmodel.known, true)
eq(m.anchors.tfp_vitals ~= m.anchors.viewmodel, true)
eq(m.anchors.tfp_vitals.bone_choice, 1)
eq(m.anchors.viewmodel.bone_choice, 1)
eq(m.anchors.tfp_vitals.bone_hash, f.n.viewmodel_weapon_node)
eq(m.anchors.tfp_vitals.role, "tfp_vitals")
eq(m.anchors.viewmodel.role, "tfp_ammo")
eq(m.anchors.tfp_vitals.x, f.viewmodel_point.x)
eq(m.anchors.viewmodel.x, f.viewmodel_point.x)
eq(m.anchors.tfp_vitals.token ~= m.anchors.viewmodel.token, true, "roles have distinct owner tokens")
local health_token, ammo_token = m.anchors.tfp_vitals.token, m.anchors.viewmodel.token
f.viewmodel_point.x = f.viewmodel_point.x + 13
count = #f.projections
m = f:sample(2, true)
eq(#f.projections - count, 1)
eq(m.anchors.tfp_vitals.x, f.viewmodel_point.x, "no prior-frame projection is cached")
eq(m.anchors.viewmodel.x, f.viewmodel_point.x)
eq(m.anchors.tfp_vitals.token, health_token)
eq(m.anchors.viewmodel.token, ammo_token)
f.sample_options = { tfp_vitals_bone = 2, tfp_ammo_bone = 1 }
m = f:sample(2, true)
eq(m.anchors.tfp_vitals.token ~= health_token, true, "only the changed role resets bone tracking")
eq(m.anchors.viewmodel.token, ammo_token)
eq(m.anchors.tfp_vitals.x, f.left_arm_point.x)
for _, health in ipairs({ 1, 2, 3 }) do
    f.sample_options = { tfp_vitals_bone = health, tfp_ammo_bone = 3, tfp_ammo_placement = 2 }
    count = #f.projections
    m = f:sample(2, true)
    eq(#f.projections - count, 1, "Above Health never samples its unused ammo bone")
    eq(m.anchors.tfp_vitals.known, true)
    eq(m.anchors.tfp_vitals.bone_choice, health)
    eq(m.anchors.viewmodel.known, false)
    eq(m.anchors.viewmodel.reason, "ammo follows selected vitals anchor")
end
local Bones = f.context.require("sampling/first_person_bones.lua")
for _, bad in ipairs({ 0, #Bones.choices + 1, 1.5, "2", false }) do
    for _, role in ipairs({ "tfp_vitals_bone", "tfp_ammo_bone" }) do
        f.sample_options = { tfp_vitals_bone = 1, tfp_ammo_bone = 1, [role] = bad }
        count = #f.projections
        m = f:sample(2, true)
        eq(m.aim.true_first_person, true)
        eq(#f.projections - count, 1, "unverified bone never reaches a native getter")
        eq(m.anchors.tfp_vitals.known, role ~= "tfp_vitals_bone")
        eq(m.anchors.viewmodel.known, role ~= "tfp_ammo_bone")
    end
end
f.sample_options = { tfp_vitals_bone = 3, tfp_ammo_bone = 1 }
f.left_elbow_point = nil
m = f:sample(2, true)
eq(m.anchors.tfp_vitals.known, false, "missing semantic node never replays a former role point")
eq(m.anchors.tfp_vitals.token, nil)
eq(m.anchors.viewmodel.known, true)
f.sample_options.tfp_ammo_bone = 3
count = #f.projections
m = f:sample(2, true)
eq(#f.projections - count, 1, "identical unavailable semantic request is not retried as another bone")
eq(m.anchors.tfp_vitals.known, false)
eq(m.anchors.viewmodel.known, false)
f.sample_options = { tfp_vitals_bone = 1, tfp_ammo_bone = 1, tfp_ammo_placement = 4 }
count = #f.projections
m = f:sample(2, true)
eq(#f.projections - count, 1)
eq(m.anchors.tfp_vitals.known, true)
eq(m.anchors.viewmodel.known, false, "unknown placement cannot authorize a guessed role")
eq(f.sampler:close(), true)
-- Every appended semantic bone can be unavailable on a current rig without
-- borrowing another role's point, replaying an old node or changing the mode.
for choice = 4, #Bones.choices do
    local f = fixture()
    local hash, _, domain = Bones.resolve(choice)
    if domain == "weapon" then
        f.weapon_bone_points[hash] = nil
    else
        f.extra_bone_points[hash] = nil
    end
    for _, role in ipairs({ "tfp_vitals_bone", "tfp_ammo_bone" }) do
        f.sample_options = { tfp_vitals_bone = 1, tfp_ammo_bone = 1, [role] = choice }
        local m = f:sample(2, true)
        eq(m.aim.true_first_person, true)
        eq(m.anchors.tfp_vitals.known, role ~= "tfp_vitals_bone")
        eq(m.anchors.viewmodel.known, role ~= "tfp_ammo_bone")
        local point = role == "tfp_vitals_bone" and m.anchors.tfp_vitals or m.anchors.viewmodel
        eq(point.token, nil)
        eq(point.bone_hash, hash)
    end
    eq(f.sampler:close(), true)
end
-- Typed target units are independently stamped, including legitimate node0.
for choice = 11, #Bones.choices do
    local f = fixture()
    f.project_validations = 5
    for _, role in ipairs({ "tfp_vitals_bone", "tfp_ammo_bone" }) do
        f.sample_options = { tfp_vitals_bone = 1, tfp_ammo_bone = 1, [role] = choice }
        local before = #f.projections
        local m = f:sample(2, true)
        local target = role == "tfp_vitals_bone" and m.anchors.tfp_vitals or m.anchors.viewmodel
        local hash = Bones.resolve(choice)
        eq(m.aim.true_first_person, true)
        eq(m.aim.weapon_unit, f.weapon_engine, "fresh independent selected-gun stamp")
        eq(m.aim.viewmodel_unit, f.viewmodel_engine)
        eq(target.known, true)
        eq(target.unit_domain, "weapon")
        eq(target.unit, f.weapon_engine, "gun bones never use FPS rig handle")
        eq(target.unit_ref, f.info.unit_ref)
        eq(target.bone_hash, hash)
        eq(target.node, f.weapon_bone_points[hash].node)
        eq(target.local_offset.x, 0)
        eq(target.local_offset.y, 0, "gun origin has no FPS-forward calibration")
        eq(target.local_offset.z, 0)
        eq(#f.projections - before, 2)
        eq(f.sampler.r.reads <= 512, true)
    end
    f.sample_options = { tfp_vitals_bone = choice, tfp_ammo_bone = choice }
    local before = #f.projections
    local m = f:sample(2, true)
    eq(#f.projections - before, 1, "same-domain actual gun request dedups only this frame")
    eq(m.anchors.viewmodel ~= m.anchors.tfp_vitals, true)
    eq(m.anchors.viewmodel.token ~= m.anchors.tfp_vitals.token, true)
    eq(m.anchors.viewmodel.unit_domain, "weapon")
    eq(f.sampler:close(), true)
end
-- Every actual gun Unit getter freshly proves Mode, wield, record and engine.
for _, mutation in ipairs({ "engine", "record", "selected", "provider", "camera", "context" }) do
    for ordinal = 1, 2 do
        local f = fixture()
        f.project_validations = 5
        f.sample_options = { tfp_vitals_bone = 11, tfp_ammo_bone = 12 }
        local getters = 0
        f.after_unit_getter = function(unit, hash, at)
            if unit ~= f.weapon_engine or hash ~= Bones.resolve(11) then
                return
            end
            getters = getters + 1
            if at ~= ordinal then
                return
            end
            if mutation == "engine" then
                f.uint(f.weapon_record + f.n.record_engine_unit, unit + 1)
            elseif mutation == "record" then
                f.uint(f.weapon_record + 8, 91)
            elseif mutation == "selected" then
                f.uint(f.selector_row, 91)
            elseif mutation == "provider" then
                f.globals.NativeADSCameraTest = {}
            elseif mutation == "camera" then
                f.pointer(f.camera_manager, f.camera + 4096)
            else
                f.pointer(f.panel + f.n.widget_gui_context, f.ui_context + 4096)
            end
        end
        local m = f:sample(2, true)
        eq(getters, ordinal, mutation .. " stops the next gun getter")
        eq(m.anchors.tfp_vitals.known, false)
        eq(m.anchors.viewmodel.known, false)
        eq(m.aim.weapon_unit, nil)
        eq(m.aim.true_first_person, false)
        eq(f.sampler.r.reads <= 512, true)
    end
end
-- The gun remains a valid Unit during FPS-role replacement, but final full
-- FPS/request/wield proof must reject every point and independent stamp.
for _, mutation in ipairs({ "fps", "request", "wield" }) do
    local f = fixture()
    f.project_validations = 5
    f.sample_options = { tfp_vitals_bone = 11, tfp_ammo_bone = 12 }
    f.after_pose = function(_, unit, _, _, hash)
        if unit ~= f.weapon_engine or hash ~= Bones.resolve(12) then
            return
        end
        if mutation == "fps" then
            f.uint(f.controller + f.n.avatar_viewmodel_offset, f.viewmodel_engine + 1)
        elseif mutation == "request" then
            f.uint(f.camera_request + 8, 91)
        else
            f.uint(f.selector_row, 91)
        end
    end
    local m = f:sample(2, true)
    eq(m.aim.true_first_person, false)
    eq(m.aim.weapon_unit, nil)
    eq(m.anchors.tfp_vitals.known, false)
    eq(m.anchors.viewmodel.known, false)
end
-- An ordinary reloadable weapon adds its real reloading query before anchors.
local peak = 0
for _, pair in ipairs({ { 1, 11 }, { 11, 1 }, { 11, 12 }, { 12, 11 }, { 11, 11 } }) do
    local f = fixture()
    f.project_validations, f.info.reloadable = 5, true
    f.sample_options = { tfp_vitals_bone = pair[1], tfp_ammo_bone = pair[2], heat_icon = true }
    local m = f:sample(2, true)
    eq(m.anchors.tfp_vitals.known, true)
    eq(m.anchors.viewmodel.known, true)
    eq(m.weapon.reloading, false)
    eq(f.sampler.r.reads <= 512, true)
    eq(f.sampler.r.bytes <= 65536, true)
    peak = math.max(peak, f.sampler.r.reads)
end
print("True first person sampling: " .. checks .. " checks passed; reloadable mixed/gun peak " .. peak .. "/512")
