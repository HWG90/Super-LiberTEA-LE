-- Read-only combat facts after the ORIGINAL DBF update. Shares its backend and
-- option sample; never creates a picker, input handler, camera or native GUI.
local Build = mod.require("sampling/build.lua")
local Memory = mod.require("src/weapon_status_memory.lua")
local Layout = mod.require("src/weapon_status_layouts.lua")
local Native = mod.require("sampling/native.lua")
local Heat = mod.require("sampling/heat.lua")
local Attachments = mod.require("sampling/attachments.lua")
local SightBounds = mod.require("sampling/sight_bounds.lua")
local FirstPersonMode = mod.require("sampling/first_person_mode.lua")
local FirstPersonBones = mod.require("sampling/first_person_bones.lua")
local Session = {}
Session.__index = Session
local INVENTORY_SLOTS = { [1] = 0, [2] = 4, [3] = 8, [4] = 16, [5] = 16, [6] = 12 }
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function ratio(v)
    return finite(v) and v >= 0 and v <= 1 and v or nil
end
local function count(v)
    return finite(v) and v >= 0 and v <= 1000000 and v % 1 == 0 and v or nil
end
local function u32(v)
    return finite(v) and v >= 0 and v < 4294967295 and v % 1 == 0 and v or nil
end
local function address(v)
    return finite(v) and v >= 65536 and v < 2 ^ 47 and v % 1 == 0
end
local function clear(t)
    for k in pairs(t) do
        t[k] = nil
    end
end
local function bit_value(raw, index)
    local value = raw:byte(math.floor(index / 8) + 1)
    if value == nil then
        return nil
    end
    return math.floor(value / 2 ^ (index % 8)) % 2 == 1
end
local function safe(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    local ok, v, a = pcall(fn, ...)
    if ok then
        return v, a
    end
end
function Session.new(deps)
    assert(deps.core, "Original DBF Core required")
    return setmetatable({
        core = deps.core,
        globals = deps.globals or _G,
        first_person_mode = FirstPersonMode.new(deps.globals or _G),
        native_factory = deps.native_factory or Native.new,
        report = deps.report or function() end,
        time = 0,
        generation = 0,
        model = {
            aim = {},
            viewport = {},
            reticle = {},
            anchors = { body = {}, weapon = {}, viewmodel = {}, tfp_vitals = {} },
            weapon = {},
            supply_icons = { stims = {}, throwables = {}, heat = {} },
            sight_clearance = {},
        },
        bounds_request = {},
        actor = {},
    }, Session)
end
function Session:reset()
    self.true_first_person_candidate = false
    local m = self.model
    m.known, m.in_mission, m.alive, m.hud_visible, m.menu_open, m.blocked = false, false, false, false, nil, false
    m.identity, m.font, m.world, m.health, m.stamina, m.stims, m.throwables, m.cooldowns =
        nil, nil, nil, nil, nil, nil, nil, nil
    m.follow_token = nil
    m.anchor_context, m.anchor_camera = nil, nil
    for _, icon in pairs(m.supply_icons) do
        clear(icon)
        icon.known = false
    end
    if self.sight_bounds then
        self.sight_bounds:reset()
    else
        clear(m.sight_clearance)
        m.sight_clearance.known = false
    end
    clear(m.aim)
    m.aim.known = false
    clear(m.weapon)
    m.weapon.known = false
    clear(m.reticle)
    m.reticle.known = false
    for _, anchor in pairs(m.anchors) do
        clear(anchor)
        anchor.known = false
        anchor.reason = "not sampled"
    end
end
function Session:_actor(services)
    local r, b = self.r, self.backend
    local pm = r.p(b.base + Layout.player)
    local roster = r.read(pm + 0x84, 8)
    if r.u(roster, 0) == 0 or r.u(roster, 4) == 0 then
        return
    end
    local player = r.read(r.p(pm + 0xe8), 24)
    if not bit_value(player, 160) or r.map(pm + 0xd0, r.u(player, 8), 64) ~= 0 then
        return
    end
    local unit = r.u(r.read(pm + 0x3a8, 4), 0)
    if unit == 0x7fff or unit == 0 or unit == 4294967295 then
        return
    end
    local actor = self.actor
    local source = services.weapon
    if actor.unit ~= unit then
        clear(actor)
        local bind = source and source.binding
        if
            source
            and source.avatar_unit_ref == unit
            and bind
            and self:_actor_current({ unit = unit, id = bind.avatar_id, record = bind.avatar_record })
        then
            actor.unit, actor.id, actor.record = unit, bind.avatar_id, bind.avatar_record
        else
            local owner = r.p(b.base + Layout.owner)
            local index = r.map(owner + Layout.unit_map, unit, 1048576)
            if not index or index >= 1048576 then
                return
            end
            actor.record = owner + Layout.records + index * 24
            local record = r.read(actor.record, 24)
            actor.id, actor.unit = r.u(record, 8), unit
        end
    end
    if not self:_actor_current(actor) then
        clear(actor)
        return
    end
    return actor
end
function Session:_actor_current(actor)
    if not actor or not address(actor.record) or not u32(actor.id) or not u32(actor.unit) then
        return false
    end
    local record = self.backend.read(actor.record, 24)
    local player = self.r.p(self.backend.base + Layout.player)
    if self.r.u(self.r.read(player + 0x3a8, 4), 0) ~= actor.unit then
        return false
    end
    return type(record) == "string"
        and #record == 24
        and self.r.u(record, 8) == actor.id
        and self.r.u(record, 16) == actor.unit
        and bit_value(record, 160) == true
end
-- Recheck only the original reader's current inventory/selector identity. This
-- does not collect options/ammunition or create a second reader/backend.
function Session:_weapon_current(info, actor)
    local r, b = self.r, self.backend
    local bind = info and info.binding
    if
        not bind
        or bind.module_base ~= b.base
        or bind.avatar_id ~= actor.id
        or bind.avatar_record ~= actor.record
        or info.avatar_unit_ref ~= actor.unit
        or not u32(info.id)
        or info.id == 0
        or not u32(info.unit_ref)
        or not address(bind.record)
        or not self:_actor_current(actor)
    then
        return false
    end
    local raw = b.read(bind.record, 24)
    if
        type(raw) ~= "string"
        or #raw ~= 24
        or r.u(raw, 8) ~= info.id
        or r.u(raw, 16) ~= info.unit_ref
        or bit_value(raw, 160) ~= true
    then
        return false
    end
    local avatar = r.read(actor.record, 24)
    local inventory = r.p(b.base + Layout.inventory)
    local index = r.map(inventory + 0x28, actor.id, 65536)
    if index == nil or index >= 4096 or index >= r.u(r.read(inventory + 0x14, 4), 0) then
        return false
    end
    if r.read(r.p(r.p(inventory + 0x40) + index * 8), 24) ~= avatar then
        return false
    end
    local slots = r.read(r.p(inventory + 0x50) + index * 48, 48)
    local slot = r.u(slots, 28)
    local offset = INVENTORY_SLOTS[slot]
    local selected = offset and r.u(slots, offset)
    local selector = r.p(b.base + Layout.selector)
    local si = r.map(selector + 0x30, actor.id, 1048576)
    if si ~= nil then
        local live, capacity = r.u(r.read(selector + 0x18, 4), 0), r.u(r.read(selector + 0x10, 4), 0)
        if live > capacity or live > 262144 or si >= live then
            return false
        end
        if r.read(r.p(r.p(selector + 0x48) + si * 8), 24) ~= avatar then
            return false
        end
        local current = r.u(r.read(r.p(selector + 0x60) + si * 0x1d0, 4), 0)
        if current ~= 0 and current ~= 4294967295 and current ~= actor.id then
            selected = current
        end
    end
    return selected == info.id
end
function Session:_reticle(at)
    local r, n = self.r, Build.numbers
    local flags = r.u(r.read(at, 4), 0)
    if not bit_value(r.read(at, 1), n.widget_shown_bit) or flags == 0 then
        return
    end
    local context = r.p(at + n.widget_gui_context)
    if r.u(r.read(context, 4), 0) % 256 ~= n.ui_context_live then
        return
    end
    if not (r.f(r.read(at + n.widget_inherited_opacity, 4), 0) > 0) then
        return
    end
    local size = r.read(at + n.hud_widgets_size_x, 8)
    local w, h = r.f(size, 0), r.f(size, 4)
    if w < 0 or h < 0 or w > 100000 or h > 100000 then
        return
    end
    local raw = r.read(at + 0x64, 64)
    local a, b, c, d, tx, ty = r.f(raw, 0), r.f(raw, 8), r.f(raw, 32), r.f(raw, 40), r.f(raw, 48), r.f(raw, 56)
    if math.abs(a * d - b * c) < 1e-8 then
        return
    end
    return a * w / 2 + c * h / 2 + tx, b * w / 2 + d * h / 2 + ty
end
function Session:_native()
    if not self.native then
        self.native = self.native_factory(self.backend)
    end
    return self.native
end
local function node_index(value)
    return finite(value) and value >= 0 and value < 4096 and value % 1 == 0
end
local function attachment_offset(role)
    local settings = type(Attachments) == "table" and Attachments[role]
    local offset = type(settings) == "table" and settings.offset
    if type(offset) == "table" and finite(offset.x) and finite(offset.y) and finite(offset.z) then
        return offset
    end
end
local function tfp_bone(options, key)
    local choice = options and options[key]
    if choice == nil then
        choice = 1
    end
    local hash, name, domain = FirstPersonBones.resolve(choice)
    if not hash then
        return choice
    end
    local offset = attachment_offset(name)
    if offset and (math.abs(offset.x) > 2 or math.abs(offset.y) > 2 or math.abs(offset.z) > 2) then
        offset = nil
    end
    return choice, hash, offset, domain
end
local function stamp_bone(target, role, choice, hash, domain)
    target.role, target.bone_choice, target.bone_hash, target.unit_domain = role, choice, hash, domain
    if target.token then
        target.token = target.token
            .. ":bone="
            .. tostring(choice)
            .. ":hash="
            .. string.format("%08x", hash)
            .. ":domain="
            .. domain
    end
end
local function anchor_result(
    target,
    role,
    actor,
    info,
    engine,
    camera,
    offset,
    generation,
    root,
    context,
    called,
    x,
    y,
    clip,
    node
)
    if not called or not finite(x) or not finite(y) or not finite(clip) or clip > 1 or not node_index(node) then
        target.reason = not called and tostring(x) or type(y) == "string" and y or "model attachment unavailable"
        return
    end
    target.x, target.y, target.unit, target.node = x, y, engine, node
    target.unit_ref = info and info.unit_ref or actor.unit
    target.actor_id, target.entity = actor.id, info and info.id or nil
    target.identity, target.context = root, context
    target.camera, target.generation, target.local_offset = camera, generation, offset
    -- Token equality identifies a semantic attachment, not an animation frame.
    -- Body deliberately excludes weapon/reload state so vitals never reset on
    -- a gun change. Every identity field remains explicit in the DTO as well.
    target.token = table.concat({
        role,
        string.format(
            "%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f",
            root,
            context,
            generation,
            actor.id,
            actor.unit,
            actor.record,
            camera,
            node
        ),
        info and string.format("%.0f:%.0f:%.0f", info.id, info.unit_ref, info.binding.record) or "body",
        info and tostring(info.resource_hex) or "body",
        string.format("engine=%.0f", engine),
        string.format("%.17g:%.17g:%.17g", offset.x, offset.y, offset.z),
    }, ":")
    target.known, target.reason = true, nil
end
function Session:_anchors(native, actor, info, root, panel, context, options)
    local m, r, b, n = self.model, self.r, self.backend, Build.numbers
    local true_first_person = self.true_first_person_candidate == true
    local body, weapon, viewmodel = m.anchors.body, m.anchors.weapon, m.anchors.viewmodel
    local tfp_vitals = m.anchors.tfp_vitals
    local okay, camera_manager, camera = pcall(function()
        local manager = r.p(b.base + n.camera_manager)
        return manager, r.p(manager)
    end)
    if not okay then
        body.reason, weapon.reason, viewmodel.reason = "camera unavailable", "camera unavailable", "camera unavailable"
        return
    end
    local generation, actor_unit, actor_id, actor_record = m.generation, actor.unit, actor.id, actor.record
    m.anchor_context, m.anchor_camera = context, camera
    local function engine_handle(record)
        local handle = r.u(r.read(record + n.record_engine_unit, 4), 0)
        return u32(handle) and handle > 0 and handle or nil
    end
    local function context_current()
        return self.generation == generation
            and r.p(b.base + n.roots_hud_manager_rva) == root
            and r.p(panel + n.widget_gui_context) == context
            and r.u(r.read(context, 4), 0) % 256 == n.ui_context_live
            and r.p(b.base + n.camera_manager) == camera_manager
            and r.p(camera_manager) == camera
    end
    local function actor_identity_current()
        return actor.unit == actor_unit and actor.id == actor_id and actor.record == actor_record
    end
    -- Corner projection has no Unit getter. Prove the camera and borrowed GUI
    -- context per point; full root/actor/wield checks bracket the whole batch.
    local function bounds_camera_current()
        return self.generation == generation
            and r.p(b.base + n.camera_manager) == camera_manager
            and r.p(camera_manager) == camera
            and r.p(panel + n.widget_gui_context) == context
    end
    local function shared_current()
        return actor_identity_current() and context_current() and self:_actor_current(actor)
    end
    -- DBF's record+16 reference remains the identity/lookup key above. Native
    -- Unit getters consume the distinct, source-proven record+12 engine handle.
    -- Never expose/use the original reader's cached diagnostic candidates.
    local read_engine, body_engine = pcall(function()
        if shared_current() then
            return engine_handle(actor_record)
        end
    end)
    if not read_engine then
        body_engine = nil
    end
    local function body_current(engine)
        return body_engine ~= nil
            and engine == body_engine
            and shared_current()
            and engine_handle(actor_record) == body_engine
    end
    local gun_current, gun_engine, gun_owner_current, fp_current, fp_engine, fp_rig_current
    local captured, capture_reason = pcall(function()
        if not info or not shared_current() or not self:_weapon_current(info, actor) then
            return
        end
        local entity, unit_ref, record, resource = info.id, info.unit_ref, info.binding.record, info.resource_hex
        gun_engine = engine_handle(record)
        if gun_engine == nil then
            return
        end
        gun_owner_current = function(engine)
            return engine == gun_engine
                and info.id == entity
                and info.unit_ref == unit_ref
                and info.binding.record == record
                and info.resource_hex == resource
                and actor_identity_current()
                and context_current()
                -- _weapon_current already proves the current local actor;
                -- do not repeat that complete lookup in this same guard.
                and self:_weapon_current(info, actor)
                and engine_handle(record) == gun_engine
        end
        if body_engine ~= nil then
            -- Stable across hip/head, gun aim and FPS rig changes. Pose, node,
            -- presentation state and FPS rig are deliberately excluded.
            m.follow_token = string.format(
                "%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f",
                root,
                context,
                generation,
                actor_id,
                actor_unit,
                actor_record,
                body_engine,
                camera_manager,
                camera,
                entity,
                unit_ref,
                record,
                gun_engine
            ) .. ":" .. tostring(resource)
        end
    end)
    if not captured then
        gun_owner_current, m.follow_token = nil, nil
    end
    local function finish()
        -- The second role can expose a camera/HUD/actor replacement after the
        -- first role succeeded. Never publish mixed-frame attachment owners.
        -- A model-handle replacement alone is role-local; the original
        -- actor/reference contract can remain valid across a new model.
        if body.known then
            local okay, live = pcall(body_current, body_engine)
            if not okay or live ~= true then
                clear(body)
                body.known, body.reason = false, "player engine model attachment changed"
            end
        end
        if weapon.known then
            local okay, live = pcall(gun_current, gun_engine)
            if not okay or live ~= true then
                clear(weapon)
                weapon.known, weapon.reason = false, "weapon engine model attachment changed"
            end
        end
        local viewmodel_owner_live = false
        if fp_current then
            local okay, live = pcall(fp_current, fp_engine)
            viewmodel_owner_live = okay and live == true
            m.aim.viewmodel_active = viewmodel_owner_live and true or nil
            m.aim.viewmodel_unit = viewmodel_owner_live and fp_engine or nil
            -- The current wield and the FPS rig are independent Unit domains.
            m.aim.weapon_unit = viewmodel_owner_live and gun_engine or nil
            if viewmodel.known and not viewmodel_owner_live then
                clear(viewmodel)
                viewmodel.known, viewmodel.reason = false, "first-person model attachment changed"
            end
            if tfp_vitals.known and not viewmodel_owner_live then
                clear(tfp_vitals)
                tfp_vitals.known, tfp_vitals.reason = false, "TFP vitals attachment changed"
            end
        end
        if m.follow_token and not viewmodel_owner_live then
            local okay, live = pcall(function()
                return gun_owner_current(gun_engine) and engine_handle(actor_record) == body_engine
            end)
            if not okay or live ~= true then
                m.follow_token = nil
            end
        end
        local checked, current = pcall(shared_current)
        if checked and current == true then
            if self.sight_bounds then
                self.sight_bounds:finish(viewmodel_owner_live and m.follow_token ~= nil, m.follow_token)
            end
            return true
        end
        for _, target in pairs(m.anchors) do
            clear(target)
            target.known, target.reason = false, "shared model attachment context changed"
        end
        m.aim.viewmodel_active = nil
        m.aim.viewmodel_unit = nil
        m.aim.weapon_unit = nil
        m.follow_token = nil
        m.anchor_context, m.anchor_camera = nil, nil
        if self.sight_bounds then
            self.sight_bounds:finish(false)
        end
        return false
    end
    if m.aim.first_person == true or m.aim.aiming == true or true_first_person then
        local tp_camera = false
        local vitals_choice, vitals_hash, offset, vitals_domain
        local ammo_choice, ammo_hash, ammo_offset, ammo_domain
        local vitals_engine, ammo_engine, ammo_current
        if true_first_person then
            vitals_choice, vitals_hash, offset, vitals_domain = tfp_bone(options, "tfp_vitals_bone")
            ammo_choice, ammo_hash, ammo_offset, ammo_domain = tfp_bone(options, "tfp_ammo_bone")
        else
            offset = attachment_offset("viewmodel")
        end
        local projection_attempted = false
        local called, x, y, clip, node = pcall(function()
            local queue = r.read(camera_manager + n.camera_queue_head, 8)
            local head, tail = r.u(queue, 0), r.u(queue, n.camera_queue_tail - n.camera_queue_head)
            if head >= 32 or tail >= 32 then
                return nil, "first-person camera queue unavailable"
            end
            local request = head ~= tail
                    and camera_manager + n.camera_queue_rows + ((tail + 31) % 32) * n.camera_queue_stride
                or camera_manager + n.camera_queue_fallback
            local bytes = r.read(request, 16)
            local kind = bytes:byte(1) + bytes:byte(2) * 256
            if kind == 4 and m.aim.first_person ~= true and not true_first_person then
                tp_camera = true
                return nil, "third-person aiming camera"
            end
            if kind ~= 6 then
                return nil, "first-person camera owner unavailable"
            end
            if not offset and not true_first_person then
                return nil, "first-person model calibration unavailable"
            end
            if not gun_owner_current or body_engine == nil then
                return nil, captured and "current weapon unavailable" or tostring(capture_reason)
            end
            local manager, index = self.controller_manager, self.controller_index
            if not address(manager) or not finite(index) or index < 0 or index >= 65536 or index % 1 ~= 0 then
                return nil, "first-person controller unavailable"
            end
            local controller = manager
                + n.roots_avatar_manager_controller_base
                + index * n.roots_avatar_manager_controller_stride
            local function controller_current()
                return r.p(b.base + n.roots_avatar_manager_rva) == manager
                    and r.map(manager + n.roots_avatar_manager_map, actor_id, 1048576) == index
                    and r.u(r.read(controller + n.avatar_controller_dive_identity_offset, 4), 0) == actor_id
            end
            if not controller_current() then
                return nil, "first-person controller changed"
            end
            fp_engine = r.u(r.read(controller + n.avatar_viewmodel_offset, 4), 0)
            if not u32(fp_engine) or fp_engine == 0 then
                return nil, "first-person model unavailable"
            end
            if r.u(bytes, 4) ~= actor_id or r.u(bytes, 8) ~= info.id or r.u(bytes, 12) ~= body_engine then
                return nil, "first-person camera owner unavailable"
            end
            fp_current = function(engine)
                return engine == fp_engine
                    and (not true_first_person or self.first_person_mode:current())
                    and gun_owner_current(gun_engine)
                    and engine_handle(actor_record) == body_engine
                    and controller_current()
                    and r.u(r.read(controller + n.avatar_viewmodel_offset, 4), 0) == fp_engine
                    and r.read(camera_manager + n.camera_queue_head, 8) == queue
                    and r.read(request, 16) == bytes
            end
            -- Both attachments belong to this actor's same FPS rig. The
            -- second point does not need to rediscover the selected weapon
            -- before every rig getter: prove the complete weapon before the
            -- batch above and again in finish(), while every rig getter still
            -- rechecks its live actor/controller/rig/camera/context ownership.
            fp_rig_current = function(engine)
                return engine == fp_engine
                    and self.first_person_mode:current()
                    and shared_current()
                    and engine_handle(actor_record) == body_engine
                    and controller_current()
                    and r.u(r.read(controller + n.avatar_viewmodel_offset, 4), 0) == fp_engine
                    and r.read(camera_manager + n.camera_queue_head, 8) == queue
                    and r.read(request, 16) == bytes
            end
            local batch_started = false
            local function role_current(domain, secondary)
                return function(engine)
                    if domain == "weapon" then
                        if engine ~= gun_engine then
                            return false
                        end
                        if not batch_started then
                            local live = fp_current(fp_engine)
                            batch_started = live == true
                            return live
                        end
                        -- Every gun Unit getter proves current wield, record,
                        -- resource and engine; an FPS-only guard cannot do so.
                        return self.first_person_mode:current() and gun_owner_current(engine)
                    elseif domain == "fps" then
                        if secondary and batch_started then
                            return fp_rig_current(engine)
                        end
                        local live = fp_current(engine)
                        batch_started = batch_started or live == true
                        return live
                    end
                    return false
                end
            end
            vitals_engine = vitals_domain == "weapon" and gun_engine or fp_engine
            ammo_engine = ammo_domain == "weapon" and gun_engine or fp_engine
            ammo_current = true_first_person and role_current(ammo_domain, true) or nil
            if true_first_person and (not vitals_hash or not offset) then
                return nil, "TFP vitals bone unavailable"
            end
            if
                options
                and options.sight_clearance == true
                and not true_first_person
                and type(native.geometry_ready) == "function"
                and type(native.unit_box) == "function"
                and type(native.project_points) == "function"
            then
                -- Actual FP rails use the sight line and current weapon OBBs.
                -- Their unused FPS point consumes no Unit getters/projection;
                -- diagnostics keep the original point path when not requested.
                return nil, "adaptive sight clearance uses the sight line"
            end
            -- Native.project proves this callback before its first getter,
            -- between getters and after final projection; no duplicate probe.
            projection_attempted = true
            return native:project(
                camera,
                true_first_person and vitals_engine or fp_engine,
                nil,
                true_first_person and role_current(vitals_domain, false) or fp_current,
                offset,
                true_first_person and vitals_hash or n.viewmodel_weapon_node,
                bounds_camera_current
            )
        end)
        if tp_camera then
            m.aim.viewmodel_active = false
            if options and options.anchor ~= 1 then
                viewmodel.reason = "screen anchor selected"
                return finish()
            end
        else
            body.reason, weapon.reason = "first person uses viewmodel", "first person uses viewmodel"
            local target = true_first_person and tfp_vitals or viewmodel
            anchor_result(
                target,
                true_first_person and "tfp_vitals" or "viewmodel",
                actor,
                info,
                true_first_person and vitals_engine or fp_engine,
                camera,
                offset,
                generation,
                root,
                context,
                called,
                x,
                y,
                clip,
                node
            )
            if target.known then
                -- The FPS rig is not the DBF weapon record's +16 reference.
                if not true_first_person or vitals_domain == "fps" then
                    target.unit_ref = nil
                end
                target.weapon_unit_ref, target.weapon_unit = info.unit_ref, gun_engine
            end
            if true_first_person then
                stamp_bone(target, "tfp_vitals", vitals_choice, vitals_hash, vitals_domain)
            end
            if true_first_person then
                local placement = options.tfp_ammo_placement
                if placement == nil then
                    placement = 1
                end
                local function put_ammo(accepted, wx, wy, wc, wn)
                    anchor_result(
                        viewmodel,
                        "tfp_ammo",
                        actor,
                        info,
                        ammo_engine,
                        camera,
                        ammo_offset,
                        generation,
                        root,
                        context,
                        accepted,
                        wx,
                        wy,
                        wc,
                        wn
                    )
                    if viewmodel.known then
                        if ammo_domain == "fps" then
                            viewmodel.unit_ref = nil
                        end
                        viewmodel.weapon_unit_ref, viewmodel.weapon_unit = info.unit_ref, gun_engine
                    end
                end
                if placement == 2 then
                    -- Pure layout uses the selected vitals point in this mode.
                    -- Retain the saved ammo preference without sampling it.
                    viewmodel.reason = "ammo follows selected vitals anchor"
                elseif placement ~= 1 then
                    viewmodel.reason = "TFP ammo placement unavailable"
                elseif not ammo_hash or not ammo_offset then
                    viewmodel.reason = "TFP ammo bone unavailable"
                elseif not ammo_current then
                    viewmodel.reason = "first-person owner unavailable"
                elseif
                    ammo_hash == vitals_hash
                    and ammo_domain == vitals_domain
                    and ammo_engine == vitals_engine
                    and offset
                    and ammo_offset.x == offset.x
                    and ammo_offset.y == offset.y
                    and ammo_offset.z == offset.z
                then
                    -- Same current-frame hash AND complete local calibration:
                    -- copy returned scalars into a distinct role DTO. No pose,
                    -- projection buffer or prior-frame sample is cached.
                    put_ammo(called, x, y, clip, node)
                else
                    -- If the first role was intentionally unavailable, still
                    -- prove the full selected weapon before a rig-only batch.
                    local owned = projection_attempted
                    if not owned then
                        local okay, current = pcall(fp_current, fp_engine)
                        owned = okay and current == true
                    end
                    if owned then
                        -- Keep the ORIGINAL512-read limit and room for final
                        -- full-owner/resource fences. The common current-map
                        -- path takes75 reads after this projection (full FPS
                        -- owner, shared context and heat-art publication);
                        -- reserve80, without changing the global512 cap.
                        -- Collision/identity failures still fail closed in the
                        -- final guards, never authorize a cached native row.
                        local read, exhausted = r.read, false
                        r.read = function(at, size)
                            if r.reads >= 512 - 80 then
                                exhausted = true
                                error("optional FPS weapon projection read budget exhausted", 0)
                            end
                            return read(at, size)
                        end
                        local accepted, wx, wy, wc, wn = pcall(
                            native.project,
                            native,
                            camera,
                            ammo_engine,
                            nil,
                            ammo_current,
                            ammo_offset,
                            ammo_hash,
                            bounds_camera_current
                        )
                        r.read = read
                        put_ammo(accepted, wx, wy, wc, wn)
                        if not viewmodel.known and exhausted then
                            viewmodel.reason = "optional FPS weapon projection read budget exhausted"
                        end
                    else
                        viewmodel.reason = "first-person owner unavailable"
                    end
                end
                stamp_bone(viewmodel, "tfp_ammo", ammo_choice, ammo_hash, ammo_domain)
            end
            if
                not true_first_person
                and fp_current
                and type(native.unit_box) == "function"
                and type(native.project_points) == "function"
            then
                self.sight_bounds = self.sight_bounds or SightBounds.new(native, r, m.sight_clearance)
                local request = self.bounds_request
                request.unit, request.camera = gun_engine, camera
                request.identity, request.context, request.generation = root, context, generation
                request.follow_token, request.defer_owner_after = m.follow_token, true
                request.owner_current = function()
                    return fp_current(fp_engine)
                end
                request.camera_current = bounds_camera_current
                self.sight_bounds:collect(request)
            end
            return finish()
        end
    end
    viewmodel.reason = "not first person"
    local body_offset, weapon_offset = attachment_offset("body"), attachment_offset("weapon")
    local called, x, y, clip, node
    if body_offset and body_engine then
        called, x, y, clip, node = pcall(
            native.project,
            native,
            camera,
            body_engine,
            nil,
            body_current,
            body_offset,
            nil,
            options.heat_icon == true and bounds_camera_current or nil
        )
        anchor_result(
            body,
            "body",
            actor,
            nil,
            body_engine,
            camera,
            body_offset,
            generation,
            root,
            context,
            called,
            x,
            y,
            clip,
            node
        )
    else
        body.reason = body_offset and "player engine handle unavailable" or "body model calibration unavailable"
    end
    -- A missing/replaced gun affects only the gun attachment. Player vitals
    -- keep following their own current bone during reload, switching and heat.
    if not info then
        weapon.reason = "current weapon unavailable"
        return finish()
    end
    if not weapon_offset then
        weapon.reason = "weapon model calibration unavailable"
        return finish()
    end
    called, x, y, clip, node = pcall(function()
        local entity = info.id
        if not gun_owner_current or not gun_owner_current(gun_engine) then
            return nil, "current weapon changed"
        end
        local data = r.p(b.base + n.weapon_data_manager)
        local index = r.map(data + n.weapon_data_map, entity, 65536)
        if index == nil or index >= 4096 then
            return nil, "weapon firing component unavailable"
        end
        local rows = r.p(data + n.weapon_data_r1_at)
        local row = rows + index * n.weapon_data_r1_stride
        if r.u(r.read(row + n.weapon_data_fire_count, 4), 0) == 0 then
            return nil, "weapon firing node unavailable"
        end
        local fire_node = r.i(r.read(row + n.weapon_data_fire_node, 4), 0)
        if not node_index(fire_node) then
            return nil, "weapon firing node unavailable"
        end
        local function attachment_current(engine)
            return gun_owner_current(engine)
                and r.p(b.base + n.weapon_data_manager) == data
                and r.map(data + n.weapon_data_map, entity, 65536) == index
                and r.p(data + n.weapon_data_r1_at) == rows
                and r.u(r.read(row + n.weapon_data_fire_count, 4), 0) > 0
                and r.i(r.read(row + n.weapon_data_fire_node, 4), 0) == fire_node
        end
        gun_current = attachment_current
        local px, py, clipped, resolved = native:project(
            camera,
            gun_engine,
            fire_node,
            attachment_current,
            weapon_offset,
            nil,
            options.heat_icon == true and bounds_camera_current or nil
        )
        if px ~= nil and resolved ~= fire_node then
            return nil, "weapon firing node changed"
        end
        return px, py, clipped, resolved
    end)
    anchor_result(
        weapon,
        "weapon",
        actor,
        info,
        gun_engine,
        camera,
        weapon_offset,
        generation,
        root,
        context,
        called,
        x,
        y,
        clip,
        node
    )
    return finish()
end
-- HUD+ Weapon:ammo_icons returns the resource definition's filled ammo art.
-- Reuse Original DBF's bounded typed-resource table rather than another native
-- weapon getter or a hand-picked coil texture. This is optional artwork only.
function Session:_heat_picture(info, actor, panel)
    local r, n, b = self.r, Build.numbers, self.backend
    local record = r.read(info.binding.record, 24)
    local key = record:sub(1, 8)
    local low, high = r.u(record, 0), r.u(record, 4)
    if string.format("%08x%08x", high, low) ~= info.resource_hex then
        return
    end
    local spec = Layout.static.weapon_data
    local owner = r.p(b.base + Layout.owner)
    local table_at = r.p(owner + spec[1])
    local cached = self.heat_picture_cache
    local row_at, row, index
    if cached and cached.key == key and cached.table_at == table_at and r.read(cached.row_at, 16) == cached.row then
        row_at, row, index = cached.row_at, cached.row, cached.index
    else
        local capacity = spec[2]
        local home = ((high % capacity) * (2 ^ 32 % capacity) + low % capacity) % capacity
        for probe = 0, math.min(capacity, 128) - 1 do
            row_at = table_at + ((home + probe) % capacity) * 16
            row = r.read(row_at, 16)
            if row:sub(1, 8) == string.rep("\0", 8) then
                return
            end
            if row:sub(1, 8) == key then
                index = r.u(row, 8)
                if index >= capacity or r.u(row, 12) ~= 0 then
                    return
                end
                break
            end
        end
        if index == nil then
            return
        end
        cached = { key = key, table_at = table_at, row_at = row_at, row = row, index = index }
        self.heat_picture_cache = cached
    end
    local source = table_at + spec[2] * 16 + index * spec[3] + n.weapon_data_instance_ammo_icon
    local picture = r.read(source, 8)
    low, high = r.u(picture, 0), r.u(picture, 4)
    local size = r.read(panel + n.self_magazine_fill + n.hud_widgets_size_x, 8)
    local width, height = r.f(size, 0), r.f(size, 4)
    if
        (low == 0 and high == 0)
        or not finite(width)
        or not finite(height)
        or width <= 0
        or height <= 0
        or width > 4096
        or height > 4096
    then
        return
    end
    if
        not self:_weapon_current(info, actor)
        or r.read(info.binding.record, 24) ~= record
        or r.p(b.base + Layout.owner) ~= owner
        or r.p(owner + spec[1]) ~= table_at
        or r.read(row_at, 16) ~= row
    then
        return
    end
    local icon = self.model.supply_icons.heat
    icon.known, icon.texture = true, string.format("%08x%08x", high, low)
    icon.width, icon.height, icon.source = width, height, source
    icon.weapon_record, icon.weapon_record_bytes = info.binding.record, record
    icon.weapon_entity, icon.weapon_unit_ref = info.id, info.unit_ref
    icon.kind = "native_ammo_fill"
    local receipt = self.heat_picture_receipt or {}
    self.heat_picture_receipt = receipt
    receipt.info, receipt.record, receipt.owner = info, record, owner
    receipt.table_at, receipt.row_at, receipt.row = table_at, row_at, row
    receipt.source, receipt.picture = source, picture
end
-- Decorative art is collected before optional projection. Publish it only
-- after the current selected weapon and its native definition remain proven.
function Session:_heat_picture_current(info, actor)
    local receipt, r, b = self.heat_picture_receipt, self.r, self.backend
    return receipt
        and receipt.info == info
        and self:_weapon_current(info, actor)
        and r.read(info.binding.record, 24) == receipt.record
        and r.p(b.base + Layout.owner) == receipt.owner
        and r.p(receipt.owner + Layout.static.weapon_data[1]) == receipt.table_at
        and r.read(receipt.row_at, 16) == receipt.row
        and r.read(receipt.source, 8) == receipt.picture
end
function Session:_sample(options)
    local m, r, b, n = self.model, self.r, self.backend, Build.numbers
    r.reset()
    local scene = r.p(b.base + n.hud_scene_manager)
    local kind = r.u(r.read(scene + n.hud_scene, 4), 0)
    m.in_mission = kind == n.hud_scene_mission
    if not m.in_mission then
        return
    end
    local root = r.p(b.base + n.roots_hud_manager_rva)
    local mission = root + n.hud_widgets_mission_hud
    local panel = mission + n.hud_widgets_panels_self_panel_at
    local flags = r.u(r.read(panel, 4), 0)
    local context = r.p(panel + n.widget_gui_context)
    if flags == 0 or r.u(r.read(context, 4), 0) % 256 ~= n.ui_context_live then
        return
    end
    if r.u(r.read(root + n.hud_built, 4), 0) % 256 ~= 1 or r.u(r.read(mission + n.hud_gate_ready, 4), 0) % 256 ~= 1 then
        return
    end
    if r.u(r.read(mission + n.hud_local_pause, 4), 0) % 256 ~= 0 then
        return
    end
    if root ~= self.identity or context ~= self.context then
        self.identity, self.context = root, context
        self.generation = self.generation + 1
        clear(self.actor)
        self.controller_index, self.controller_manager = nil, nil
        self.font, self.font_next = nil, nil
    end
    m.identity, m.generation = root, self.generation
    local services = self.services
    local sampled = services.snapshot
    if sampled and sampled.identity == root and type(sampled.open) == "boolean" then
        m.menu_open = sampled.open
    else
        local value = r.u(r.read(root + Build.menu_panel + Build.menu_open_at, 4), 0) % 256
        if value == 0 or value == 1 then
            m.menu_open = value == 1
        end
    end
    local opacity = r.f(r.read(panel + n.widget_inherited_opacity, 4), 0)
    m.hud_visible = opacity > 0 and bit_value(r.read(panel, 1), n.widget_shown_bit) == true
    m.health = ratio(r.f(r.read(panel + n.self_panel_health_bar + n.health_bar_drawn, 4), 0))
    m.stamina = ratio(r.f(r.read(mission + n.hud_widgets_stamina_panel_at + n.stamina_panel_share, 4), 0))
    local counters = r.read(panel + n.hud_weapon_reserve_shown, n.hud_self_last_slot - n.hud_weapon_reserve_shown + 4)
    m.stims = count(r.i(counters, n.self_panel_stims - n.hud_weapon_reserve_shown))
    m.throwables = count(r.i(counters, n.hud_self_throwables - n.hud_weapon_reserve_shown))
    local actor = self:_actor(services)
    if not actor then
        return
    end
    if self.actor_id ~= actor.id or self.actor_unit ~= actor.unit or self.actor_record ~= actor.record then
        self.actor_id, self.actor_unit, self.actor_record = actor.id, actor.unit, actor.record
        self.generation = self.generation + 1
        m.generation = self.generation
        self.controller_index, self.controller_manager, self.controller_avatar = nil, nil, nil
    end
    m.alive = m.health ~= nil and m.health > 0
    local manager = r.p(b.base + n.roots_avatar_manager_rva)
    local index = self.controller_index
    if self.controller_manager ~= manager or self.controller_avatar ~= actor.id or index == nil then
        index = r.map(manager + n.roots_avatar_manager_map, actor.id, 1048576)
        if index == nil or index >= 65536 then
            return
        end
        self.controller_index, self.controller_manager, self.controller_avatar = index, manager, actor.id
    end
    local controller = manager
        + n.roots_avatar_manager_controller_base
        + index * n.roots_avatar_manager_controller_stride
    if r.u(r.read(controller + n.avatar_controller_dive_identity_offset, 4), 0) ~= actor.id then
        self.controller_index = nil
        return
    end
    local actions = r.read(controller + n.avatar_action_words, 16)
    m.aim.first_person = bit_value(actions, n.first_person_action_bit)
    m.aim.aiming = bit_value(actions, n.aim_action_bit)
    m.aim.switching = bit_value(actions, n.switch_action_word * 8 + n.switch_action_bit)
    m.aim.known = type(m.aim.first_person) == "boolean" and type(m.aim.aiming) == "boolean"
    local camera_mode = self.first_person_mode:update()
    self.true_first_person_candidate = camera_mode.active == true
    local okay, x, y = pcall(self._reticle, self, mission + n.hud_widgets_panels_crosshair_at)
    -- A hidden native crosshair (notably ADS) is not an unknown viewport.
    -- Fall back to an explicitly screen-pinned center, never a guessed affine.
    m.reticle.known = true
    if okay and finite(x) and finite(y) then
        m.reticle.x, m.reticle.y, m.reticle.source = x, y, "native"
    else
        m.reticle.x, m.reticle.y, m.reticle.source = m.viewport.width / 2, m.viewport.height / 2, "screen_center"
    end
    local weapon = m.weapon
    local ammo_state = r.i(counters, n.hud_weapon_ammo_state - n.hud_weapon_reserve_shown)
    local held = r.u(counters, n.hud_self_last_slot - n.hud_weapon_reserve_shown) == n.throwable_slot
    weapon.throwing = held
    if held then
        weapon.count = m.throwables
        weapon.count_kind = "throwable"
    elseif ammo_state ~= n.hud_ammo_none_state then
        weapon.count = count(r.i(counters, n.hud_weapon_count_shown - n.hud_weapon_reserve_shown))
    end
    local spare = r.read(panel + n.spare_widget, 1)
    if not held and bit_value(spare, n.widget_shown_bit) then
        weapon.reserve = count(r.u(counters, 0))
    end
    weapon.known = weapon.count ~= nil
    local info = services.weapon
    local anchor_info
    if info then
        local valid, current = pcall(self._weapon_current, self, info, actor)
        if not held and valid and current == true then
            anchor_info = info
        end
        if held or m.aim.switching ~= false or not valid or current ~= true then
            info = nil
        end
    end
    if info then
        for _, key in ipairs({
            "fire_mode",
            "rpm",
            "rpm_index",
            "rpm_selectable",
            "ammo_mode",
            "zoom",
            "zoom_index",
            "changeable",
        }) do
            weapon[key] = info[key]
        end
        weapon.known = true
        weapon.identity = info.resource_hex
        weapon.entity = info.id
        weapon.ammo_kind = info.ammo_kind
        weapon.count_kind = (info.ammo_kind == "magazine" or info.ammo_kind == "rounds") and "ammo" or nil
        if info.reloadable == false then
            weapon.reloading = false
        end
        if info.ammo_kind == "heat" or info.resource_hex == Heat.TALON then
            local okay, heat = pcall(self.heat.collect, self.heat, info, function()
                return self:_weapon_current(info, actor)
            end)
            if info.ammo_kind == "heat" or (okay and heat and heat.heat_weapon == true) then
                weapon.ammo_kind, weapon.heat_weapon, weapon.count_kind = "heat", true, "heat"
                weapon.count, weapon.reserve, weapon.reloading = nil, nil, nil
                if okay and heat then
                    weapon.heat, weapon.heat_current, weapon.heat_limit, weapon.heat_locked =
                        heat.heat, heat.heat_current, heat.heat_limit, heat.heat_locked
                end
            end
        end
    end
    -- The existing counter block includes the stock HUD's currently equipped
    -- grenade picture. Only dimensions need an optional extra read. Failure
    -- hides that icon without discarding otherwise valid combat facts.
    if m.aim.known then
        local icons, supply = m.supply_icons, Build.supply
        local stims = icons.stims
        stims.known, stims.texture = true, supply.stim_texture
        stims.width, stims.height = supply.stim_width, supply.stim_height
        local okay, width, height = pcall(function()
            local size = r.read(panel + n.self_panel_throwable_icon + n.hud_widgets_size_x, 8)
            return r.f(size, 0), r.f(size, 4)
        end)
        local picture = n.self_panel_throwable_picture - n.hud_weapon_reserve_shown
        local low, high = r.u(counters, picture), r.u(counters, picture + 4)
        local grenade = icons.throwables
        if
            okay
            and finite(width)
            and finite(height)
            and width > 0
            and height > 0
            and width <= 4096
            and height <= 4096
            and (low ~= 0 or high ~= 0)
        then
            grenade.known = true
            grenade.texture = string.format("%08x%08x", high, low)
            grenade.width, grenade.height = width, height
            grenade.source = panel + n.self_panel_throwable_picture
        end
        if options.heat_icon == true and info and weapon.heat_weapon == true and not weapon.throwing then
            pcall(self._heat_picture, self, info, actor, panel)
        end
    end
    local want_anchor = self.true_first_person_candidate
        or options.anchor == 1
        or options.sight_clearance == true and (m.aim.first_person == true or m.aim.aiming == true)
    local attachment_context_current = true
    if not want_anchor then
        for _, anchor in pairs(m.anchors) do
            anchor.reason = "screen anchor selected"
        end
    end
    local want_reload = info and not weapon.heat_weapon and info.reloadable and not info.alternate_fire
    if
        (want_anchor or want_reload)
        and m.alive
        and m.hud_visible == true
        and m.menu_open == false
        and m.blocked == false
    then
        local native_ok, native = pcall(self._native, self)
        if native_ok then
            if want_reload then
                pcall(function()
                    local reload = r.p(b.base + n.reload_manager)
                    if self:_weapon_current(info, actor) then
                        local value = native:call("reloading", reload, info.id)
                        if type(value) == "boolean" then
                            weapon.reloading = value
                        end
                    end
                end)
            end
            if want_anchor and type(native) == "table" and type(native.project) == "function" then
                local okay, why = pcall(self._anchors, self, native, actor, anchor_info, root, panel, context, options)
                if okay and why == false then
                    attachment_context_current = false
                end
                if not okay then
                    for _, anchor in pairs(m.anchors) do
                        if not anchor.known then
                            anchor.reason = tostring(why)
                        end
                    end
                end
            end
        end
    end
    m.cooldowns = services.cooldowns or sampled
    if not self.font_next or self.time >= self.font_next then
        self.font = safe(b.dock_font, rawget(self.globals, "stingray"))
        self.font_next = self.time + 1
    end
    m.font = self.font
    m.known = m.aim.known and attachment_context_current or false
    m.aim.true_first_person = self.true_first_person_candidate
            and m.known
            and m.aim.viewmodel_active == true
            and self.first_person_mode:current()
        or false
    m.aim.true_first_person_token = m.aim.true_first_person and camera_mode.token or nil
    local icons = m.supply_icons
    if icons.heat.known then
        local okay, current = pcall(self._heat_picture_current, self, info, actor)
        if not m.known or not okay or current ~= true then
            clear(icons.heat)
            icons.heat.known = false
        end
    end
    for _, icon in pairs(icons) do
        if m.known and icon.known then
            icon.identity, icon.generation, icon.context = root, m.generation, context
        else
            clear(icon)
            icon.known = false
        end
    end
end
function Session:sample(dt, options)
    options = options or {}
    self:reset()
    self.time = self.time + (finite(dt) and math.max(0, math.min(dt, 1)) or 0)
    local m = self.model
    m.time, m.generation = self.time, self.generation
    self.services = self.core:services() or {}
    local b = self.services.backend
    if not b then
        return m
    end
    if self.backend ~= b then
        if self.native then
            self.native:close()
            self.native = nil
        end
        self.backend, self.r, self.sight_bounds = b, Memory.new(b), nil
        self.heat_picture_cache = nil
        self.heat = Heat.new(b, self.r)
        clear(self.actor)
        self.identity, self.context, self.controller_index, self.controller_manager, self.font, self.font_next =
            nil, nil, nil, nil, nil, nil
    end
    local sr = rawget(self.globals, "stingray")
    local viewport = options.viewport
    if
        not viewport
        or not finite(viewport.width)
        or not finite(viewport.height)
        or viewport.width <= 0
        or viewport.height <= 0
    then
        return m
    end
    m.viewport.width, m.viewport.height = viewport.width, viewport.height
    local input = rawget(self.globals, "LiveLuaLoader")
    local status = input and input.input_service and safe(input.input_service.status)
    local mcm = rawget(self.globals, "DBFMCM")
    m.blocked = mcm and type(mcm.is_open) == "function" and safe(mcm.is_open) ~= false or false
    if input and input.input_service and type(input.input_service.status) == "function" then
        if type(status) ~= "table" then
            m.blocked = true
        else
            m.blocked = m.blocked or status.owner ~= nil and status.owner ~= false or status.pending_restore == true
        end
    end
    if b.focused and safe(b.focused) ~= true then
        m.blocked = true
    end
    local worlds = sr and sr.Application and safe(sr.Application.worlds)
    local main = sr and sr.Application and safe(sr.Application.main_world)
    if type(worlds) ~= "table" then
        return m
    end
    for _, world in pairs(worlds) do
        if world ~= main then
            m.world = world
            break
        end
    end
    m.world = m.world or main
    if not m.world then
        return m
    end
    local okay, why = pcall(self._sample, self, options)
    if not okay then
        self:reset()
        m.time, m.generation = self.time, self.generation
        self.reason = tostring(why)
    else
        self.reason = nil
    end
    return m
end
function Session:close()
    if self.native then
        self.native:close()
        self.native = nil
    end
    self:reset()
    self.first_person_mode:close()
    self.backend, self.r, self.heat, self.sight_bounds = nil, nil, nil, nil
    return true
end
return Session
