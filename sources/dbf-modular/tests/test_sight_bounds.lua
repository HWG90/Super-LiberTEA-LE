-- Real sparse bytes/production decoder and real Session; no game or native writes.
local Fixture = assert(loadfile("tests/sampling_fixture.lua"))()
local checks = 0
local common_reads, adaptive_reads
local function eq(actual, expected, reason)
    checks = checks + 1
    assert(actual == expected, (reason or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function fresh(total, chain)
    local f = Fixture.new()
    f:first_person()
    f:sample(1)
    local native, r = f.sampler.native, f.sampler.r
    local exe, registry, slots, generations, world, vt =
        0x60000000, 0x61000000, 0x62000000, 0x63000000, 0x64000000, 0x65000000
    f.exe, f.registry, f.slots, f.generations, f.world, f.vtable = exe, registry, slots, generations, world, vt
    f.objects, f.units, f.boxes, f.box_calls, f.projected, f.owner_calls = {}, {}, {}, {}, {}, 0
    f.box_native_calls = {}
    f.pointer(exe + 0x1ab76f8, registry)
    f.put(registry + 0x88, string.rep("\0", 32))
    f.pointer(registry + 0x88, slots)
    f.uint(registry + 0x98, 0x400000)
    f.pointer(registry + 0xa0, generations)
    f.put(vt + 0xc8, string.rep("\0", 0x128))
    f.pointer(vt + 0xc8, exe + 0x293550)
    f.pointer(vt + 0xf8, exe + 0x28d330)
    f.pointer(vt + 0x1e8, exe + 0x28e650)
    for i = 1, total or 2 do
        local unit, object = f.weapon_engine + i - 1, 0x66000000 + i * 0x400
        f.units[i], f.objects[i] = unit, object
        f.put(generations + unit % 0x400000, string.char(math.floor(unit / 0x400000)))
        f.pointer(slots + unit % 0x400000 * 8, object)
        f.put(object, string.rep("\0", 0x1e8))
        f.pointer(object, vt)
        f.uint(object + 8, unit)
        f.pointer(object + 0x18, world)
        local matrix = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, (i - 1) * 1.5, 0, 2, 1 }
        f.boxes[unit] = { matrix = matrix, half = { 0.4, 0.2, 0.1 } }
    end
    for i = 2, #f.units do
        local parent = chain and i - 1 or 1
        f.pointer(f.objects[i] + 0x1d0, f.objects[parent])
        if chain or i == 2 then
            f.pointer(f.objects[parent] + 0x1d8, f.objects[i])
        else
            f.pointer(f.objects[i - 1] + 0x1e0, f.objects[i])
        end
    end
    local reused = { matrix = {}, half = {} }
    function native:geometry_ready()
        return not f.unready and exe or nil, "geometry witness changed"
    end
    function native:unit_box(unit, validate)
        f.box_calls[#f.box_calls + 1] = unit
        if f.before_box then
            f.before_box(unit)
        end
        -- Actual Native fences before alive, before box and after box. The
        -- geometry witness phase performs no Unit access of its own.
        for index = 1, 2 do
            if not validate(unit) then
                return nil, "box owner changed"
            end
            if index == 1 and f.after_alive then
                f.after_alive(unit)
            end
        end
        f.box_native_calls[#f.box_native_calls + 1] = unit
        local box = f.boxes[unit]
        if not box then
            return nil, "box unavailable"
        end
        for i = 1, 16 do
            reused.matrix[i] = box.matrix[i]
        end
        for i = 1, 3 do
            reused.half[i] = box.half[i]
        end
        if f.after_box then
            f.after_box(unit)
        end
        if not validate(unit) then
            return nil, "box owner changed after getter"
        end
        return reused
    end
    function native:project_points(camera, points, validate)
        for i, p in ipairs(points) do
            if not validate() then
                return nil, "camera changed"
            end
            if f.before_corner then
                f.before_corner(i, p)
            end
            local out = f.projected[i] or {}
            f.projected[i] = out
            out.x, out.y, out.clip = 1920 + p.x * (f.zoom or 100), 1080 + p.y * (f.zoom or 100), f.clip or 0.5
        end
        for i = #points + 1, #f.projected do
            f.projected[i] = nil
        end
        if not validate() then
            return nil, "camera changed after projection"
        end
        return f.projected
    end
    local Sight = f.context.require("sampling/sight_bounds.lua")
    f.collector = Sight.new(native, r)
    f.request = {
        unit = f.weapon_engine,
        identity = f.root,
        context = f.ui_context,
        generation = 1,
        camera = f.camera,
        follow_token = "current-actor-current-weapon",
        owner_current = function()
            f.owner_calls = f.owner_calls + 1
            if f.before_owner then
                f.before_owner(f.owner_calls)
            end
            return f.owner_live ~= false
        end,
        camera_current = function()
            return f.camera_live ~= false
        end,
    }
    function f:collect()
        r.reset()
        return self.collector:collect(self.request)
    end
    return f
end
do
    local f = fresh(1)
    f.boxes[f.weapon_engine].matrix = { 0, 2, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 1 }
    local value = f:collect()
    eq(value.known, true)
    eq(value.bounds.left, 1900, "actual affine rotation and scale transform box corners")
    eq(value.bounds.right, 1940)
    eq(value.bounds.bottom, 1000)
    eq(value.bounds.top, 1160)
end
do
    local f = fresh(2)
    local value = f:collect()
    eq(value.known, true)
    eq(value.source, "weapon_bounds")
    eq(value.unit_count, 2)
    eq(#value.polygons, 2, "one complete projected corner set per current Unit")
    for unit = 1, 2 do
        eq(#value.polygons[unit], 8, "OBB corners are never dropped before hull clipping")
        for corner = 1, 8 do
            local point = value.polygons[unit][corner]
            local projected = f.projected[(unit - 1) * 8 + corner]
            eq(point.x, projected.x)
            eq(point.y, projected.y)
            eq(point ~= projected, true, "projected native scratch is copied into owned scalar records")
        end
    end
    eq(f.box_calls[1], f.weapon_engine, "first box belongs to current gun, never FPS rig")
    eq(f.box_calls[2], f.units[2], "second box belongs to real attached optic unit")
    eq(#f.projected, 16)
    eq(value.bounds.left, 1880)
    eq(value.bounds.right, 2110)
    eq(value.bounds.bottom, 1060)
    eq(value.bounds.top, 1100)
    eq(value.identity, f.root)
    eq(value.context, f.ui_context)
    eq(value.camera, f.camera)
    eq(value.generation, 1)
    eq(value.follow_token, f.request.follow_token)
    eq(f.owner_calls, 2, "standalone collector brackets batch with full owner proof")
    local bounds, first = value.bounds, f.collector.points[1]
    local polygons, polygon, vertex = value.polygons, value.polygons[1], value.polygons[1][1]
    local saved_x = vertex.x
    f.projected[1].x = -999999
    eq(vertex.x, saved_x, "native projection result reuse cannot alter published polygons")
    f.boxes[f.units[2]].matrix[13] = 3
    f.zoom = 200
    value = f:collect()
    eq(value.known, true)
    eq(value.bounds, bounds, "bounds record reused")
    eq(f.collector.points[1], first, "corner records reused")
    eq(value.polygons, polygons, "active polygon array reused")
    eq(value.polygons[1], polygon, "per-Unit polygon reused")
    eq(value.polygons[1][1], vertex, "projected scalar records reused")
    eq(value.bounds.right, 2600, "poses and camera projection sampled again, no XY cache")
    f.boxes[f.weapon_engine].matrix[14] = -20
    value = f:collect()
    eq(value.known, true, "offviewport weapon extent is retained for consumer band intersection")
    eq(value.bounds.bottom < 0, true)
    f.pointer(f.objects[1] + 0x1d8, 0)
    f.pointer(f.objects[2] + 0x1d0, 0)
    value = f:collect()
    eq(value.known, true)
    eq(value.unit_count, 1)
    eq(#value.polygons, 1, "detached optic cannot retain a stale active polygon")
    eq(value.polygons[2], nil)
end
do
    for _, invalid in ipairs({ "clip", "nonfinite" }) do
        local f = fresh(2)
        f.before_corner = function(index, point)
            if index == 16 then
                if invalid == "clip" then
                    f.clip = 1.1
                else
                    point.x = 0 / 0
                end
            end
        end
        local value = f:collect()
        eq(value.known, false, "one invalid corner refuses the complete geometry")
        eq(value.polygons, nil, "no partial 15-corner geometry reaches the hull consumer")
    end
end
do
    for _, size in ipairs({ 1, 3, 8 }) do
        local f = fresh(size)
        local value = f:collect()
        eq(value.known, true)
        eq(value.unit_count, size)
        eq(#f.projected, size * 8)
    end
    for _, options in ipairs({ { 9, false }, { 6, true } }) do
        local f = fresh(options[1], options[2])
        eq(f:collect().known, false, "oversized/deep tree is unknown, never truncated")
        eq(#f.box_calls, 0)
    end
end
do
    for _, bad in ipairs({ "cycle", "parent", "generation", "registry", "type", "world" }) do
        local f = fresh(2)
        if bad == "cycle" then
            f.pointer(f.objects[2] + 0x1e0, f.objects[2])
        elseif bad == "parent" then
            f.pointer(f.objects[2] + 0x1d0, f.objects[1] + 8)
        elseif bad == "generation" then
            f.put(f.generations + f.units[2], "\1")
        elseif bad == "registry" then
            f.pointer(f.slots + f.units[2] * 8, f.objects[2] + 8)
        elseif bad == "type" then
            f.pointer(f.vtable + 0xc8, f.exe + 1)
        else
            f.pointer(f.objects[2] + 0x18, f.world + 8)
        end
        local value = f:collect()
        eq(value.known, false, bad .. " cannot grant geometry")
        eq(#f.box_calls, 0, bad .. " refuses before native getter")
    end
end
do
    -- A replacement registry can leave the old arrays/objects readable. They
    -- cannot authorize a getter that will resolve through the NEW registry.
    for _, mutation in ipairs({ "registry", "header" }) do
        for _, phase in ipairs({ "after_alive", "between_boxes" }) do
            local f = fresh(2)
            local function replace()
                if mutation == "registry" then
                    f.pointer(f.exe + 0x1ab76f8, f.registry + 0x1000)
                else
                    f.pointer(f.registry + 0x88, f.slots + 0x1000)
                end
            end
            if phase == "after_alive" then
                f.after_alive = replace
            else
                f.before_box = function(unit)
                    if unit == f.units[2] then
                        replace()
                    end
                end
            end
            eq(f:collect().known, false, mutation .. " replacement " .. phase .. " cannot publish")
            eq(
                #f.box_native_calls,
                phase == "after_alive" and 0 or 1,
                "stale registry proof never reaches next box getter"
            )
        end
    end
end
do
    for _, phase in ipairs({ "before_box", "after_box", "before_corner" }) do
        local f = fresh(2)
        f[phase] = function()
            f.pointer(f.objects[2] + 0x1d0, f.objects[1] + 8)
        end
        eq(f:collect().known, false, phase .. " topology mutation is refused")
    end
    local f = fresh(2)
    f.before_owner = function(index)
        if index == 2 then
            f.owner_live = false
        end
    end
    eq(f:collect().known, false, "owner replacement after projection cannot publish")
    f = fresh(2)
    f.before_corner = function()
        f.camera_live = false
    end
    eq(f:collect().known, false, "camera replacement during batch cannot publish")
    for _, bad in ipairs({ "clip", "nan", "empty", "matrix", "missing" }) do
        f = fresh(2)
        if bad == "clip" then
            f.clip = 1.1
        elseif bad == "nan" then
            f.boxes[f.weapon_engine].half[1] = 0 / 0
        elseif bad == "empty" then
            f.boxes[f.weapon_engine].half = { 0, 0, 0 }
        elseif bad == "matrix" then
            f.boxes[f.weapon_engine].matrix[16] = 0
        else
            f.boxes[f.units[2]] = nil
        end
        eq(f:collect().known, false, bad .. " must not omit a family member")
    end
end
do
    local f = fresh(2)
    f.request.defer_owner_after = true
    local value = f:collect()
    eq(value.known, false, "deferred packet is never public before final Session owner check")
    eq(f.owner_calls, 1)
    eq(f.collector:finish(true, f.request.follow_token).known, true)
    value = f:collect()
    f.pointer(f.objects[2] + 0x1d0, 0)
    eq(f.collector:finish(true, f.request.follow_token).known, false, "final topology replacement refused")
    f = fresh(2)
    f.request.defer_owner_after = true
    f:collect()
    eq(f.collector:finish(false, f.request.follow_token).known, false)
    f:collect()
    eq(f.collector:finish(true, "next-weapon").known, false)
end
do
    local f = fresh(2)
    local r = f.sampler.r
    local original = r.read
    r.reads = 440
    local value = f.collector:collect(f.request)
    eq(value.known, false, "optional geometry yields before exhausting base sampler")
    eq(r.reads <= 448, true)
    eq(r.read, original, "shared reader restored after budget refusal")
    f = fresh(2)
    f.project_validations = 4
    f.info.reloadable = true
    local state = f:sample(1)
    eq(state.known, true)
    eq(state.anchors.viewmodel.known, true)
    eq(state.sight_clearance.known, true, state.sight_clearance.reason)
    eq(state.sight_clearance.unit_count, 2)
    eq(state.sight_clearance.follow_token, state.follow_token)
    eq(state.anchor_context, f.ui_context)
    eq(state.anchor_camera, f.camera)
    eq(
        f.sampler.r.reads <= 512,
        true,
        "ordinary reloadable weapon + three Unit/two camera gates + two OBBs stay bounded"
    )
    common_reads = f.sampler.r.reads
    f = fresh(2)
    f.project_validations = 4
    f:heat_sample(12, 100, false)
    state = f:sample(1)
    eq(state.known, true)
    eq(state.weapon.heat_weapon, true)
    eq(state.sight_clearance.known, true, "actual heat collector + two-unit geometry fits the existing budget")
    eq(f.sampler.r.reads <= 512, true)
    f = fresh(3)
    f.project_validations = 4
    state = f:sample(1)
    eq(state.known, true)
    eq(state.anchors.viewmodel.known, true)
    eq(state.sight_clearance.known, true, "newly reachable three-unit family completes final tree fence")
    eq(state.sight_clearance.unit_count, 3)
    eq(f.sampler.r.reads <= 512, true)
    f = fresh(4)
    f.project_validations = 4
    state = f:sample(1)
    eq(state.known, true, "intermediate expensive family preserves base HUD")
    eq(state.anchors.viewmodel.known, true)
    eq(state.sight_clearance.known, false)
    eq(f.sampler.r.reads <= 512, true)
    f = fresh(8)
    f.project_validations = 4
    state = f:sample(1)
    eq(state.known, true, "expensive geometry never blanks base HUD")
    eq(state.anchors.viewmodel.known, true)
    eq(state.weapon.count, 31)
    eq(state.sight_clearance.known, false, "oversized read workload falls back without partial clearance")
    eq(f.sampler.r.reads <= 512, true)
end
do
    for _, phase in ipairs({ "after_pose", "after_project" }) do
        local f = fresh(2)
        f.project_validations = 4
        f[phase] = function(_, unit)
            if unit == f.viewmodel_engine then
                f.uint(f.selector_row, 91)
            end
        end
        local state = f:sample(1)
        eq(state.known, true, "wield-only drift retains native panel facts")
        eq(state.anchors.viewmodel.known, false, phase .. " full final owner fence retires copied FPS point")
        eq(state.anchors.viewmodel.token, nil)
        eq(state.sight_clearance.known, false)
        eq(#f.box_native_calls, 0, "changed wield never starts geometry getters")
        eq(state.follow_token, nil)
        eq(state.weapon.count, 31)
    end
end
do
    local f = fresh(2)
    f.project_validations = 4
    f.after_box = function()
        f.pointer(f.objects[2] + 0x1d0, 0)
    end
    local state = f:sample(1)
    eq(state.sight_clearance.known, false)
    eq(state.known, true, "attachment-only failure leaves base facts live")
    eq(state.anchors.viewmodel.known, true)
    eq(state.weapon.count, 31)
    f = fresh(2)
    f.project_validations = 4
    f.before_corner = function()
        f.pointer(f.camera_manager, f.camera + 0x100)
    end
    state = f:sample(1)
    eq(state.known, false, "global camera mutation during corner batch invalidates old anchor points")
    eq(state.sight_clearance.known, false)
    eq(state.anchor_context, nil)
    eq(state.anchor_camera, nil)
    for _, anchor in pairs(state.anchors) do
        eq(anchor.known, false)
        eq(anchor.token, nil)
    end
    eq(state.weapon.count, 31, "global guard keeps already-collected counter unchanged")
    f = fresh(2)
    f.unready = true
    state = f:sample(1)
    eq(state.known, true)
    eq(state.sight_clearance.known, false)
    eq(#f.box_calls, 0, "unknown geometry witness never invokes a box getter")
end
do
    for _, kind in ipairs({ "reloadable", "heat" }) do
        local f = fresh(2)
        f.project_validations = 4
        f.info.reloadable = true
        if kind == "heat" then
            f:heat_sample(12, 100, false)
        end
        local projected = #f.projections
        local state = f:sample(1, true)
        eq(state.known, true)
        eq(state.sight_clearance.known, true, kind .. " adaptive geometry completes with headroom")
        eq(state.sight_clearance.unit_count, 2)
        eq(state.anchors.viewmodel.known, false, "adaptive HUD does not invent an unused FPS point")
        eq(state.aim.viewmodel_active, true)
        eq(state.aim.viewmodel_unit, f.viewmodel_engine)
        eq(#f.projections, projected, "adaptive mode performs no FPS Unit/pose/project getter")
        for _, unit in ipairs(f.box_native_calls) do
            eq(unit ~= f.viewmodel_engine, true, "bounds use actual weapon/optic units only")
        end
        eq(f.sampler.r.reads < 400, true, "live-map collisions retain existing-budget headroom")
        if kind == "reloadable" then
            adaptive_reads = f.sampler.r.reads
        end
        local Anchor = f.context.require("hud/anchor.lua")
        local bounds = { left = -100, right = 100, bottom = -80, top = 30 }
        local target = assert(Anchor.target_role(state, {
            get = function(_, key)
                if key == "hud.anchor" then
                    return 1
                end
            end,
        }, state.viewport, bounds, "weapon"))
        eq(target.source, "sights")
        eq(target.x, state.reticle.x, "owner-only FPS metadata never supplies invented coordinates")
        eq(target.y, state.reticle.y)
        eq(target.context, f.ui_context)
        eq(target.camera, f.camera)
        eq(type(target.token), "string")
        eq(target.follow_token, state.follow_token)
    end
    for _, choice in ipairs({ 2, 3 }) do
        local f = fresh(2)
        f.project_validations = 4
        local projected = #f.projections
        local state = f:sample(choice, true)
        eq(state.sight_clearance.known, true, "all first-person anchor choices collect current optic clearance")
        eq(state.aim.viewmodel_unit, f.viewmodel_engine)
        eq(state.anchors.viewmodel.known, false)
        eq(#f.projections, projected, "screen anchor choices need no Unit pose getter")
        f.action(f.n.first_person_action_bit, false)
        f.action(f.n.aim_action_bit, true)
        f.set_camera_request(4)
        local boxes = #f.box_native_calls
        state = f:sample(choice, true)
        eq(state.known, true)
        eq(state.aim.viewmodel_active, false)
        eq(state.sight_clearance.known, false)
        eq(#f.projections, projected, "third-person screen choice never samples body/gun poses")
        eq(#f.box_native_calls, boxes)
        f.action(f.n.aim_action_bit, false)
        state = f:sample(choice, true)
        eq(state.known, true)
        eq(#f.projections, projected, "hip screen choice never samples body/gun poses")
        eq(#f.box_native_calls, boxes)
    end
end
do
    local f = fresh(2)
    f.after_box = function()
        f.uint(f.selector_row, 91)
    end
    local state = f:sample(1, true)
    eq(state.known, true)
    eq(state.aim.viewmodel_unit, nil, "final full wield proof rejects owner-only FPS metadata")
    eq(state.aim.viewmodel_active, nil)
    eq(state.sight_clearance.known, false)
    eq(state.follow_token, nil)
    eq(state.weapon.count, 31)
    f = fresh(2)
    f.before_corner = function()
        f.pointer(f.camera_manager, f.camera + 0x100)
    end
    state = f:sample(1, true)
    eq(state.known, false)
    eq(state.aim.viewmodel_unit, nil)
    eq(state.sight_clearance.known, false)
    eq(state.anchor_context, nil)
    eq(state.anchor_camera, nil)
end
print(
    "weapon sight bounds: "
        .. checks
        .. " checks passed; real Session two-unit family "
        .. common_reads
        .. "/512 reads; adaptive reloadable family "
        .. adaptive_reads
        .. "/512"
)
