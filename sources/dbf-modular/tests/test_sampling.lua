local Fixture = assert(loadfile("tests/sampling_fixture.lua"))()
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local f = Fixture.new()
local m = f:sample()
eq(m.known, true, f.sampler.reason)
eq(m.alive, true)
eq(m.hud_visible, true)
eq(m.menu_open, false)
eq(m.blocked, false)
eq(m.health, 0.75)
eq(m.stamina, 0.5)
eq(m.stims, 2)
eq(m.throwables, 4)
eq(m.weapon.count, 31)
eq(m.weapon.reserve, 3)
eq(m.weapon.fire_mode, "AUTO")
eq(m.weapon.rpm, 750)
eq(m.weapon.capacity, nil)
eq(m.weapon.remaining, nil, "unproven gauge/heat is never fabricated")
eq(m.weapon.reloading, false, "explicit original nonreloadable fact is known false")
eq(m.reticle.x, 1920)
eq(m.reticle.y, 1080)
eq(m.reticle.source, "native")
eq(m.cooldowns, f.services.cooldowns, "actual Core cooldown snapshot contract")
local combined = 0
for _, row in ipairs(f.reads) do
    if row.at == f.panel + f.n.hud_weapon_reserve_shown and row.size == 136 then
        combined = combined + 1
    end
end
eq(combined, 1, "native counter block is collected in one read")
eq(m.aim.first_person, false)
eq(m.aim.aiming, false)
f.action(f.n.first_person_action_bit, true)
m = f:sample()
eq(m.aim.first_person, true)
eq(m.aim.aiming, false)
f.action(f.n.aim_action_bit, true)
m = f:sample()
eq(m.aim.first_person, true)
eq(m.aim.aiming, true)
f.action(f.n.first_person_action_bit, false)
m = f:sample(1)
eq(m.aim.first_person, false)
eq(m.aim.aiming, true)
eq(m.anchors.body.known, true)
eq(m.anchors.body.x, 800)
eq(m.anchors.weapon.known, true)
eq(m.anchors.weapon.x, 1000)
f.action(f.n.switch_action_word * 8 + f.n.switch_action_bit, true)
m = f:sample(1)
eq(m.weapon.fire_mode, nil, "switching clears optional old weapon facts")
eq(m.anchors.weapon.known, true, "switch flag does not retire a still-verified current gun")
eq(m.anchors.body.known, true, "switch flag never blocks the player's bone")
f.action(f.n.switch_action_word * 8 + f.n.switch_action_bit, false)
f.uint(f.inventory_row, 91)
f.uint(f.selector_row, 91)
m = f:sample(1)
eq(m.weapon.rpm, nil, "old still-live weapon is not current wielded weapon")
eq(m.anchors.weapon.known, false)
eq(m.weapon.count, 31, "native UI count is its own fresh fact")
f.uint(f.inventory_row, 90)
f.uint(f.selector_row, 90)
f.info.binding.avatar_id = 43
m = f:sample(1)
eq(m.weapon.fire_mode, nil)
eq(m.anchors.weapon.known, false)
f.info.binding.avatar_id = 42
f.uint(f.weapon_record + 16, 99)
m = f:sample(1)
eq(m.weapon.fire_mode, nil)
eq(m.anchors.weapon.known, false)
f.uint(f.weapon_record + 16, 88)
f.uint(f.crosshair, 0)
m = f:sample()
eq(m.reticle.source, "screen_center")
eq(m.reticle.x, 1920)
eq(m.reticle.y, 1080)
f.uint(f.panel + f.n.hud_weapon_ammo_state, f.n.hud_ammo_none_state)
m = f:sample()
eq(m.weapon.count, nil)
f.uint(f.panel + f.n.hud_weapon_ammo_state, 0)
f.uint(f.panel + f.n.hud_self_last_slot, f.n.throwable_slot)
m = f:sample()
eq(m.weapon.count, 4, "actual native throwing count contract")
eq(m.weapon.throwing, true)
eq(m.weapon.reserve, nil, "gun reserve is not throwable reserve")
eq(m.weapon.fire_mode, nil, "held throwable cannot carry the previous gun option DTO")
eq(m.weapon.reloading, nil)
f.uint(f.panel + f.n.hud_weapon_ammo_state, f.n.hud_ammo_none_state)
f.uint(f.panel + f.n.hud_self_throwables, 0)
m = f:sample()
eq(m.weapon.count, 0, "held throwable count exists even in native none state")
local Policy = f.context.require("hud/policy.lua")
local policy = Policy.new()
local settings = {
    get = function(_, id)
        if id == "hud.density" then
            return 2
        end
    end,
}
local view = policy:update(m, settings, 0.016)
eq(view.weapon.text, "0")
eq(view.weapon.tone, "yellow")
eq(view.reload.visible, false, "actual throwing producer never suggests reloading a grenade")
eq(view.weapon.reserve, nil)
eq(view.weapon.options, nil)
eq(view.weapon_options, false)
eq(view.weapon.options_complete, false)
f.uint(f.panel + f.n.hud_weapon_ammo_state, 0)
f.uint(f.panel + f.n.hud_self_last_slot, 1)
f.uint(f.controller + f.n.avatar_controller_dive_identity_offset, 43)
m = f:sample()
eq(m.known, false, "foreign action-controller row is never consumed")
eq(m.aim.known, false)
f.uint(f.controller + f.n.avatar_controller_dive_identity_offset, 42)
f.globals.DBFMCM.is_open = function()
    return nil
end
m = f:sample()
eq(m.blocked, true, "unknown menu ownership is blocked")
f.globals.DBFMCM.is_open = function()
    return false
end
f.uint(f.pm + 0x3a8, 78)
m = f:sample()
eq(m.known, false, "stale avatar record cannot survive local actor replacement")
f.uint(f.pm + 0x3a8, 77)
m = f:sample()
eq(m.known, true)
local stable_generation = m.generation
m = f:sample()
eq(m.generation, stable_generation, "steady actor keeps temporal context")
local root_identity = m.identity
f:replace_actor(43, 78)
m = f:sample()
eq(m.known, true)
eq(m.identity, root_identity, "actor replacement can reuse HUD root")
eq(m.generation, stable_generation + 1, "known actor replacement advances temporal generation")
m = f:sample()
eq(m.generation, stable_generation + 1, "same replacement increments once")

-- Actual producer -> Policy must discard health recovery history on actor change.
local fresh = Fixture.new()
local quiet = { get = function() end }
local temporal = Policy.new()
local before = temporal:update(fresh:sample(), quiet, 0.016)
eq(before.health.visible, true)
fresh.float(fresh.panel + fresh.n.self_panel_health_bar + fresh.n.health_bar_drawn, 1)
fresh:replace_actor(43, 78)
local after = temporal:update(fresh:sample(), quiet, 0.016)
eq(after.health.visible, false, "old actor recovery hold does not leak to healthy replacement")

-- Known visibility/menu ownership gates optional native getters, not panel facts.
local gated = Fixture.new()
gated:sample(1)
local called = #gated.calls
gated.float(gated.panel + gated.n.widget_inherited_opacity, 0)
local hidden = gated:sample(1)
eq(hidden.hud_visible, false)
eq(hidden.weapon.count, 31)
eq(#gated.calls, called, "hidden HUD does not project")
gated.float(gated.panel + gated.n.widget_inherited_opacity, 1)
gated.services.snapshot = nil
local build = gated.context.require("sampling/build.lua")
gated.uint(gated.root + build.menu_panel + build.menu_open_at, 2)
local unknown = gated:sample(1)
eq(unknown.menu_open, nil)
eq(#gated.calls, called, "unknown menu does not project")
gated.uint(gated.root + build.menu_panel + build.menu_open_at, 0)
local visible = gated:sample(1)
eq(visible.menu_open, false)
eq(visible.anchors.body.known, true)
eq(#gated.calls > called, true)

local reload = Fixture.new()
reload.info.reloadable = true
reload.before_read = function(at)
    if at == reload.backend.base + reload.n.reload_manager then
        reload.uint(reload.inventory_row, 91)
        reload.uint(reload.selector_row, 91)
    end
end
local switched = reload:sample(2)
eq(switched.known, true)
eq(switched.weapon.count, 31)
eq(switched.weapon.reloading, nil, "fresh held-weapon switch retires optional reload fact")
eq(#reload.calls, 0, "reload getter cannot use an old live weapon after switching")
do
    local motion = Fixture.new()
    local attachments = motion.context.require("sampling/attachments.lua")
    local state = motion:sample(1)
    local body, gun = state.anchors.body, state.anchors.weapon
    eq(state.aim.aiming, false)
    eq(body.known, true, "hip follows current player bone")
    eq(gun.known, true, "hip follows current gun too")
    eq(body.unit, motion.body_engine)
    eq(body.unit_ref, 77)
    eq(body.node, 6)
    eq(body.actor_id, 42)
    eq(body.entity, nil)
    eq(gun.unit, motion.weapon_engine)
    eq(gun.unit_ref, 88)
    eq(gun.node, 3)
    eq(gun.actor_id, 42)
    eq(gun.entity, 90)
    eq(body.camera, motion.camera)
    eq(gun.camera, motion.camera)
    eq(body.generation, state.generation)
    eq(gun.generation, state.generation)
    eq(body.identity, state.identity)
    eq(gun.identity, state.identity)
    eq(body.context, motion.ui_context)
    eq(gun.context, motion.ui_context)
    eq(body.local_offset, attachments.body.offset)
    eq(gun.local_offset, attachments.weapon.offset)
    eq(motion.projections[1].offset, attachments.body.offset, "model-local player calibration forwarded")
    eq(motion.projections[2].offset, attachments.weapon.offset, "model-local gun calibration forwarded")
    eq(attachments.body.offset.x, -0.04)
    eq(attachments.body.offset.z, -0.12)
    eq(attachments.weapon.offset.x, 0.04)
    eq(attachments.weapon.offset.y, -0.08)
    local body_token, gun_token, follow_token = body.token, gun.token, state.follow_token
    motion.body_point.x, motion.body_point.y = 810, 470
    state = motion:sample(1)
    eq(state.anchors.body, body, "body DTO reused")
    eq(body.x, 810)
    eq(body.y, 470)
    eq(gun.x, 1000)
    eq(gun.y, 450, "player bone motion does not move gun anchor")
    eq(body.token, body_token, "animation does not replace semantic identity")
    motion.weapon_point.x, motion.weapon_point.y = 1100, 460
    motion.info.reloadable, motion.reloading = true, true
    state = motion:sample(1)
    eq(state.weapon.reloading, true)
    eq(body.known, true, "reload never blocks player bone")
    eq(gun.known, true, "verified gun follows reload animation")
    eq(gun.x, 1100)
    eq(body.x, 810)
    eq(body.token, body_token)
    eq(gun.token, gun_token)
    motion.action(motion.n.aim_action_bit, true)
    state = motion:sample(1)
    eq(gun.known, true, "ADS keeps verified bone attachment")
    eq(body.token, body_token)
    eq(gun.token, gun_token)
    local projected = #motion.projections
    motion.action(motion.n.first_person_action_bit, true)
    state = motion:sample(1)
    eq(body.known, false)
    eq(gun.known, false)
    eq(state.anchors.viewmodel.known, false)
    eq(#motion.projections, projected, "unproven first-person camera keeps reticle fallback without bone calls")
    motion.action(motion.n.first_person_action_bit, false)
    motion.action(motion.n.aim_action_bit, false)
    motion.services.weapon = nil
    state = motion:sample(1)
    eq(body.known, true, "missing gun data cannot suppress player attachment")
    eq(body.token, body_token)
    eq(gun.known, false)
    eq(state.weapon.count, 31)
    motion.services.weapon = motion.info
    motion.uint(motion.inventory_row, 91)
    motion.uint(motion.selector_row, 91)
    state = motion:sample(1)
    eq(body.known, true)
    eq(body.token, body_token)
    eq(gun.known, false, "replaced wield does not use old live gun")
    motion.uint(motion.inventory_row, 90)
    motion.uint(motion.selector_row, 90)
    motion.info.unit_ref = 99
    motion.uint(motion.weapon_record + 16, 99)
    state = motion:sample(1)
    eq(gun.known, true)
    eq(gun.unit, motion.weapon_engine)
    eq(gun.unit_ref, 99)
    eq(gun.token ~= gun_token, true, "replacement gun unit has its own attachment token")
    eq(state.follow_token ~= follow_token, true, "replacement equipped weapon resets blending owner")
    eq(body.token, body_token, "gun replacement leaves player token alone")
    gun_token = gun.token
    motion.uint(motion.fire_row + motion.n.weapon_data_fire_node, 4)
    state = motion:sample(1)
    eq(gun.node, 4)
    eq(gun.token ~= gun_token, true, "live fire-node change invalidates gun history")
    motion.body_point.node = 9
    state = motion:sample(1)
    eq(body.node, 9)
    eq(body.token ~= body_token, true, "resolved player bone is not cached")
end
do
    local heat = Fixture.new()
    local state = heat:sample(1)
    local body_token = state.anchors.body.token
    heat:heat_sample(12, 100, false)
    state = heat:sample(1)
    eq(state.weapon.heat_weapon, true)
    eq(state.weapon.reloading, nil)
    eq(state.anchors.body.known, true, "unknown heat reload state does not block player bone")
    eq(state.anchors.weapon.known, true, "verified heat gun still has animated attachment")
    eq(state.anchors.body.token, body_token)
end
do
    local failed = Fixture.new()
    failed.project_failure = failed.body_engine
    local state = failed:sample(1)
    eq(state.known, true)
    eq(state.weapon.count, 31)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, true, "one failed role does not disable the other")
    failed.project_failure = failed.weapon_engine
    state = failed:sample(1)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, false)
    eq(state.weapon.count, 31)
    local attachments = failed.context.require("sampling/attachments.lua")
    failed.project_failure, attachments.body.offset = nil, nil
    state = failed:sample(1)
    eq(state.known, true)
    eq(state.weapon.count, 31)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, true, "bad player calibration stays role-local")
end
do
    local changed = Fixture.new()
    changed.before_project = function(_, unit)
        if unit ~= changed.body_engine then
            changed.uint(changed.fire_row + changed.n.weapon_data_fire_node, 4)
        end
    end
    local state = changed:sample(1)
    eq(state.known, true)
    eq(state.weapon.count, 31)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, false, "fire-node replacement between lookup/getter retires only gun")
    changed.before_project = nil
    changed.after_project = function(_, unit)
        if unit ~= changed.body_engine then
            changed.uint(changed.selector_row, 91)
        end
    end
    state = changed:sample(1)
    eq(state.known, true)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, false, "post-projection wield replacement is rejected")
end
do
    -- Shared camera/HUD/actor mutations DURING THE SECOND role invalidate the
    -- first role too; node/entity-only mutations above leave player vitals live.
    for _, mutation in ipairs({ "camera", "hud", "context", "actor" }) do
        local changed = Fixture.new()
        changed.after_project = function(_, unit)
            if unit == changed.body_engine then
                return
            end
            if mutation == "camera" then
                changed.pointer(changed.camera_manager, changed.camera + 0x100)
            elseif mutation == "hud" then
                changed.uint(changed.root + changed.context.require("sampling/build.lua").numbers.hud_built, 0)
                changed.pointer(changed.backend.base + changed.n.roots_hud_manager_rva, changed.root + 0x100)
            elseif mutation == "context" then
                changed.pointer(changed.panel + changed.n.widget_gui_context, changed.ui_context + 0x100)
            else
                changed.uint(changed.pm + 0x3a8, 78)
            end
        end
        local state = changed:sample(1)
        eq(state.known, false, mutation .. " changed after player's successful projection")
        eq(state.anchors.body.known, false)
        eq(state.anchors.weapon.known, false)
        eq(state.anchors.body.token, nil)
        eq(state.anchors.body.camera, nil)
        eq(state.weapon.count, 31, "attachment refusal does not fabricate/erase collected native counter")
    end
end
do
    local calibrated = Fixture.new()
    local open = io.open
    io.open = function()
        error("per-frame file IO forbidden")
    end
    local okay, state = pcall(calibrated.sample, calibrated, 1)
    io.open = open
    eq(okay, true)
    eq(state.known, true)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, true)
    eq(calibrated.sampler.r.reads <= 512, true, "two attachments stay inside bounded sampler budget")
end
do
    local handles = Fixture.new()
    -- Old candidate diagnostics can be stale/absent. Only freshly validated
    -- record+12 supplies a native handle; record+16 remains DBF's lookup ref.
    handles.info.binding.candidate, handles.info.binding.avatar_candidate = 1169, 1166
    local state = handles:sample(1)
    eq(state.anchors.body.unit, handles.body_engine)
    eq(state.anchors.body.unit_ref, 77)
    eq(state.anchors.weapon.unit, handles.weapon_engine)
    eq(state.anchors.weapon.unit_ref, 88)
    eq(handles.projections[1].unit, handles.body_engine, "DBF ref77 never reaches Native Unit getter")
    eq(handles.projections[2].unit, handles.weapon_engine, "DBF ref88 never reaches Native Unit getter")
    local body_token, gun_token = state.anchors.body.token, state.anchors.weapon.token
    local follow_token = state.follow_token
    handles.body_engine = handles.body_engine + 1
    handles.uint(handles.actor_record + handles.n.record_engine_unit, handles.body_engine)
    state = handles:sample(1)
    eq(state.anchors.body.known, true)
    eq(state.anchors.body.unit, handles.body_engine)
    eq(state.anchors.body.unit_ref, 77, "model handle does not rewrite original actor ref")
    eq(state.anchors.body.token ~= body_token, true, "same-ref new engine model has a fresh token")
    eq(state.follow_token ~= follow_token, true, "same-ref new body model replaces blending owner")
    follow_token = state.follow_token
    eq(state.anchors.weapon.token, gun_token, "player model replacement leaves gun identity independent")
    handles.weapon_engine = handles.weapon_engine + 1
    handles.uint(handles.weapon_record + handles.n.record_engine_unit, handles.weapon_engine)
    state = handles:sample(1)
    eq(state.anchors.weapon.known, true)
    eq(state.anchors.weapon.unit, handles.weapon_engine)
    eq(state.anchors.weapon.unit_ref, 88)
    eq(state.anchors.weapon.token ~= gun_token, true, "same-ref new gun model has a fresh token")
    eq(state.follow_token ~= follow_token, true, "same-ref new gun model replaces blending owner")
end
do
    local changed = Fixture.new()
    changed.before_project = function(_, engine)
        if engine == changed.body_engine then
            changed.uint(changed.actor_record + changed.n.record_engine_unit, engine + 1)
        end
    end
    local state = changed:sample(1)
    eq(state.known, true)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, true, "player engine change before getter stays role-local")
    eq(state.weapon.count, 31)
    changed = Fixture.new()
    changed.after_project = function(_, engine)
        if engine == changed.weapon_engine then
            changed.uint(changed.weapon_record + changed.n.record_engine_unit, engine + 1)
        end
    end
    state = changed:sample(1)
    eq(state.known, true)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, false, "gun engine change after getter cannot publish old model")
    eq(state.anchors.weapon.unit, nil)
    changed = Fixture.new()
    changed.after_project = function(_, engine)
        if engine == changed.weapon_engine then
            changed.uint(changed.actor_record + changed.n.record_engine_unit, changed.body_engine + 1)
        end
    end
    state = changed:sample(1)
    eq(state.known, true)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, true, "second projection cannot leave old body engine handle published")
    eq(state.anchors.body.unit, nil)
end
do
    local missing = Fixture.new()
    missing.uint(missing.actor_record + missing.n.record_engine_unit, 0)
    local state = missing:sample(1)
    eq(state.known, true)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, true)
    eq(#missing.projections, 1, "missing player engine handle causes no native player call")
    missing.uint(missing.weapon_record + missing.n.record_engine_unit, 0xffffffff)
    state = missing:sample(1)
    eq(state.known, true)
    eq(state.anchors.weapon.known, false)
    eq(state.weapon.count, 31)
    eq(#missing.projections, 1, "invalid engine handles never substitute DBF refs")
end
do
    local fp = Fixture.new()
    local attachments = fp.context.require("sampling/attachments.lua")
    local state = fp:sample(1)
    local follow = state.follow_token
    eq(type(follow), "string")
    fp.action(fp.n.aim_action_bit, true)
    state = fp:sample(1)
    eq(state.follow_token, follow, "head-to-gun aim transition retains current actor/wield owner")
    fp:first_person()
    state = fp:sample(1)
    local point = state.anchors.viewmodel
    eq(state.known, true)
    eq(point.known, true, "native kind6 owns a distinct FPS attachment")
    eq(state.aim.viewmodel_active, true)
    eq(state.anchors.body.known, false, "FP does not project a hidden TP body")
    eq(state.anchors.weapon.known, false, "FP does not substitute its TP gun")
    eq(point.unit, fp.viewmodel_engine)
    eq(point.unit_ref, nil, "FPS engine handle has no ECS reference counterpart")
    eq(point.weapon_unit, fp.weapon_engine)
    eq(point.weapon_unit_ref, 88)
    eq(point.entity, 90)
    eq(point.actor_id, 42)
    eq(point.node, 8)
    eq(point.camera, fp.camera)
    eq(point.identity, state.identity)
    eq(point.context, fp.ui_context)
    eq(point.generation, state.generation)
    eq(state.anchor_context, fp.ui_context)
    eq(state.anchor_camera, fp.camera)
    eq(point.local_offset, attachments.viewmodel.offset)
    eq(point.x, 1920)
    eq(point.y, 850)
    eq(attachments.viewmodel.offset.x, 0)
    eq(attachments.viewmodel.offset.y, 0.5, "explicit forward calibration projects the weapon beyond its raw pivot")
    eq(attachments.viewmodel.offset.z, 0)
    local projection = fp.projections[#fp.projections]
    eq(projection.unit, fp.viewmodel_engine)
    eq(projection.node, nil)
    eq(projection.node_hash, fp.n.viewmodel_weapon_node, "semantic FPS attachment hash reaches Native")
    eq(state.follow_token, follow, "FPS source change retains actor/wield owner")
    local token = point.token
    fp.viewmodel_point.x, fp.viewmodel_point.y, fp.viewmodel_point.node = 1990, 830, 9
    state = fp:sample(1)
    eq(state.anchors.viewmodel, point, "FPS DTO reused")
    eq(point.x, 1990)
    eq(point.y, 830)
    eq(point.node, 9, "semantic node is freshly resolved")
    eq(point.token ~= token, true, "node remap replaces attachment identity")
    eq(state.follow_token, follow, "node remap does not replace stable actor/wield owner")
    token = point.token
    fp.viewmodel_engine = fp.viewmodel_engine + 1
    fp.uint(fp.controller + fp.n.avatar_viewmodel_offset, fp.viewmodel_engine)
    state = fp:sample(1)
    eq(point.known, true)
    eq(point.unit, fp.viewmodel_engine)
    eq(point.token ~= token, true)
    eq(state.follow_token, follow, "new FPS rig keeps valid current actor/wield blend owner")
    fp.info.reloadable, fp.reloading = true, true
    state = fp:sample(1)
    eq(state.weapon.reloading, true)
    eq(point.known, true, "verified FPS follows reload animation without neutral-pose assumptions")
    eq(state.follow_token, follow)
    fp:heat_sample(12, 100, false)
    state = fp:sample(1)
    eq(state.weapon.heat_weapon, true)
    eq(state.weapon.reloading, nil)
    eq(point.known, true, "heat unknown reload cannot suppress FPS attachment")
    fp.action(fp.n.first_person_action_bit, false)
    fp.action(fp.n.aim_action_bit, false)
    state = fp:sample(1)
    eq(point.known, false)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, true)
end
do
    -- Custom True FPV camera ownership is independent of native bit48. Hip
    -- still follows the head; aiming uses the positively owned FPS viewmodel.
    local fp = Fixture.new()
    fp.set_camera_request(6)
    local state = fp:sample(1)
    local follow = state.follow_token
    eq(state.aim.first_person, false)
    eq(state.aim.aiming, false)
    eq(state.aim.viewmodel_active, nil)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, true)
    eq(state.anchors.viewmodel.known, false, "custom FP hip retains requested player/head source")
    fp.action(fp.n.aim_action_bit, true)
    state = fp:sample(1)
    eq(state.aim.first_person, false, "raw native first-person bit is never rewritten")
    eq(state.aim.aiming, true)
    eq(state.aim.viewmodel_active, true, "owned native kind6 annotates custom first-person aiming")
    eq(state.anchors.viewmodel.known, true)
    eq(state.anchors.body.known, false)
    eq(state.anchors.weapon.known, false)
    eq(state.follow_token, follow)
    fp.project_failure = fp.viewmodel_engine
    state = fp:sample(1)
    eq(state.aim.viewmodel_active, true, "optional point failure does not invent a third-person camera")
    eq(state.anchors.viewmodel.known, false)
    eq(state.weapon.count, 31)
    eq(state.health, 0.75)
    fp.project_failure = nil
    fp.uint(fp.camera_request + 8, 91)
    local projected = #fp.projections
    state = fp:sample(1)
    eq(state.aim.first_person, false)
    eq(state.aim.viewmodel_active, nil, "foreign camera owner cannot annotate FPS")
    eq(state.anchors.viewmodel.known, false)
    eq(state.anchors.weapon.known, false, "unproven kind6 never substitutes the world weapon")
    eq(#fp.projections, projected)
    eq(state.weapon.count, 31)
end
do
    local tp = Fixture.new()
    tp.action(tp.n.aim_action_bit, true)
    tp.uint(tp.controller + tp.n.avatar_viewmodel_offset, 0)
    local state = tp:sample(1)
    eq(state.aim.first_person, false)
    eq(state.aim.aiming, true)
    eq(state.aim.viewmodel_active, false)
    eq(state.anchors.body.known, true)
    eq(state.anchors.weapon.known, true, "ordinary kind4 aiming keeps verified TP weapon")
    eq(state.anchors.viewmodel.known, false)
    eq(#tp.projections, 2, "no FPS getter for ordinary third-person aiming")
    tp.services.weapon = nil
    state = tp:sample(1)
    eq(state.anchors.body.known, true, "TP aiming without weapon options retains player facts")
    eq(state.aim.viewmodel_active, false)
end
do
    -- Use the actual newest-ring-entry rule, including tail wrap. Equal queue
    -- indices select the constructor's fallback request instead.
    for _, queue in ipairs({ { 0, 0 }, { 2, 0 }, { 1, 7 } }) do
        local fp = Fixture.new()
        local at = fp:first_person(queue[1], queue[2])
        local state = fp:sample(1)
        eq(state.anchors.viewmodel.known, true)
        local expected = queue[1] ~= queue[2]
                and fp.camera_manager + fp.n.camera_queue_rows + ((queue[2] + 31) % 32) * fp.n.camera_queue_stride
            or fp.camera_manager + fp.n.camera_queue_fallback
        eq(at, expected)
    end
end
do
    for _, invalid in ipairs({ "kind", "avatar", "weapon", "body", "fps", "head", "tail", "missing_weapon" }) do
        local fp = Fixture.new()
        local at = fp:first_person()
        if invalid == "kind" then
            fp.uint(at, 4)
        elseif invalid == "avatar" then
            fp.uint(at + 4, 43)
        elseif invalid == "weapon" then
            fp.uint(at + 8, 91)
        elseif invalid == "body" then
            fp.uint(at + 12, fp.body_unit)
        elseif invalid == "fps" then
            fp.uint(fp.controller + fp.n.avatar_viewmodel_offset, 0xffffffff)
        elseif invalid == "head" then
            fp.uint(fp.camera_manager + fp.n.camera_queue_head, 32)
        elseif invalid == "tail" then
            fp.uint(fp.camera_manager + fp.n.camera_queue_tail, 32)
        else
            fp.services.weapon = nil
        end
        local state = fp:sample(1)
        eq(state.known, true, invalid .. " remains optional")
        eq(state.anchors.viewmodel.known, false, invalid .. " cannot publish an FPS point")
        eq(#fp.projections, 0, invalid .. " is refused before Native")
        eq(state.weapon.count, 31)
        eq(state.health, 0.75)
    end
end
do
    for _, phase in ipairs({ "before_project", "after_project" }) do
        for _, mutation in ipairs({ "fps", "request", "queue", "controller", "wield", "body_engine", "gun_engine" }) do
            local fp = Fixture.new()
            local at = fp:first_person()
            fp[phase] = function()
                if mutation == "fps" then
                    fp.uint(fp.controller + fp.n.avatar_viewmodel_offset, fp.viewmodel_engine + 1)
                elseif mutation == "request" then
                    fp.uint(at + 8, 91)
                elseif mutation == "queue" then
                    fp.uint(fp.camera_manager + fp.n.camera_queue_tail, 1)
                elseif mutation == "controller" then
                    fp.uint(fp.controller + fp.n.avatar_controller_dive_identity_offset, 43)
                elseif mutation == "wield" then
                    fp.uint(fp.selector_row, 91)
                elseif mutation == "body_engine" then
                    fp.uint(fp.actor_record + fp.n.record_engine_unit, fp.body_engine + 1)
                else
                    fp.uint(fp.weapon_record + fp.n.record_engine_unit, fp.weapon_engine + 1)
                end
            end
            local state = fp:sample(1)
            eq(state.known, true, mutation .. " attachment refusal keeps collected facts")
            eq(state.anchors.viewmodel.known, false, phase .. " rechecks " .. mutation)
            eq(state.anchors.viewmodel.token, nil)
            eq(state.aim.viewmodel_active, nil, "changed FPS ownership clears its camera annotation")
            eq(state.weapon.count, 31)
            eq(state.health, 0.75)
            if mutation == "wield" or mutation == "body_engine" or mutation == "gun_engine" then
                eq(state.follow_token, nil, "changed blend owner is never retained")
            end
        end
    end
end
do
    for _, mutation in ipairs({ "camera", "camera_manager", "hud", "context", "actor" }) do
        local fp = Fixture.new()
        fp:first_person()
        fp.after_project = function()
            if mutation == "camera" then
                fp.pointer(fp.camera_manager, fp.camera + 0x100)
            elseif mutation == "camera_manager" then
                fp.pointer(fp.backend.base + fp.n.camera_manager, fp.camera_manager + 0x100)
            elseif mutation == "hud" then
                fp.pointer(fp.backend.base + fp.n.roots_hud_manager_rva, fp.root + 0x100)
            elseif mutation == "context" then
                fp.pointer(fp.panel + fp.n.widget_gui_context, fp.ui_context + 0x100)
            else
                fp.uint(fp.pm + 0x3a8, 78)
            end
        end
        local state = fp:sample(1)
        eq(state.known, false, mutation .. " globally invalidates the frame")
        eq(state.follow_token, nil)
        eq(state.aim.viewmodel_active, nil)
        eq(state.anchor_context, nil)
        eq(state.anchor_camera, nil)
        for _, point in pairs(state.anchors) do
            eq(point.known, false)
            eq(point.token, nil)
            eq(point.camera, nil)
        end
        eq(state.weapon.count, 31, "global attachment refusal leaves collected count unmodified")
    end
end
do
    local fp = Fixture.new()
    fp:first_person()
    -- Actual Native's nil-node path fences alive, semantic-node, position and
    -- projection getters, then checks once after projection (five in total).
    fp.project_validations = 4
    local open = io.open
    io.open = function()
        error("per-frame file IO forbidden")
    end
    local okay, state = pcall(fp.sample, fp, 1)
    io.open = open
    eq(okay, true)
    eq(state.anchors.viewmodel.known, true)
    eq(fp.sampler.r.reads <= 512, true, "all five Native freshness fences stay within sampler budget")
    local calls = #fp.projections
    state = fp:sample(2)
    eq(state.anchors.viewmodel.known, false)
    eq(state.follow_token, nil)
    eq(#fp.projections, calls, "screen-pinned selection does not resolve an FPS attachment")
    fp.float(fp.panel + fp.n.widget_inherited_opacity, 0)
    state = fp:sample(1)
    eq(state.anchors.viewmodel.known, false)
    eq(#fp.projections, calls, "hidden HUD does not resolve an FPS attachment")
end
eq(f.sampler:close(), true)
print("actual-byte sampling: " .. checks .. " checks passed")
