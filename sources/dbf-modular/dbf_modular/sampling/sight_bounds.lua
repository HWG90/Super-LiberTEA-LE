-- Current weapon + real Unit descendants, never the FPS animation rig or a
-- world inventory. The caller supplies the current actor/wield/camera guards.
-- Layout contract: each Unit contributes all eight projected OBB corners in
-- physical pixels. The consumer clips their convex hulls to its configured
-- sight band; the full XY union is retained only as diagnostic bounds.
local Sight = {}
Sight.__index = Sight
-- WJ freecam/subject_backend.lua33..54,414..433, build26251122. Native's
-- geometry_ready independently pins the registry/children getter witnesses.
local L = {
    registry = 0x1ab76f8,
    slots = 0x88,
    capacity = 0x98,
    generations = 0xa0,
    world = 0x18,
    parent = 0x1d0,
    child = 0x1d8,
    sibling = 0x1e0,
    type_c8 = 0x293600,
    type_f8 = 0x28d3e0,
    type_1e8 = 0x28e700,
}
local MAX_UNITS, MAX_DEPTH, FINISH_RESERVE = 8, 4, 64
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function address(v)
    return finite(v) and v >= 65536 and v < 2 ^ 47 and v % 1 == 0
end
local function handle(v)
    return finite(v) and v > 0 and v < 0x40000000 and v % 1 == 0
end
local function link(r, raw, at)
    local p = r.u(raw, at) + r.u(raw, at + 4) * 4294967296
    assert(p == 0 or address(p), "weapon attachment link unavailable")
    return p
end
local function clear(t)
    for key in pairs(t) do
        t[key] = nil
    end
end
function Sight.new(native, reader, target)
    target = target or {}
    local self =
        setmetatable({ native = native, r = reader, result = target, records = {}, seen = {}, points = {} }, Sight)
    for i = 1, MAX_UNITS do
        self.records[i] = {}
    end
    self.polygons, self.active_polygons = {}, {}
    for unit = 1, MAX_UNITS do
        local polygon = {}
        self.polygons[unit] = polygon
        for corner = 1, 8 do
            polygon[corner] = {}
        end
    end
    for i = 1, MAX_UNITS * 8 do
        self.points[i] = {}
    end
    self.bounds = {}
    self:reset()
    return self
end
function Sight:reset()
    clear(self.result)
    self.result.known, self.result.reason = false, "not sampled"
    self.pending, self.request, self.count = false, nil, 0
end
-- Bound all reader users in this synchronous optional operation, including
-- the caller's owner guard. Restore the shared reader even on refusal/error.
-- Keep enough of its ORIGINAL512-read budget for Session's final owner fence.
function Sight:_bounded(reserve, fn)
    local r, original = self.r, self.r.read
    local limit = 512 - reserve
    r.read = function(at, size)
        assert(r.reads < limit, "optional weapon bounds read budget exhausted")
        return original(at, size)
    end
    local okay, value, reason = pcall(fn)
    r.read = original
    if not okay then
        return nil, tostring(value)
    end
    return value, reason
end
function Sight:_registry_current()
    local r = self.r
    return r.p(self.exe + L.registry) == self.registry and r.read(self.registry + L.slots, 32) == self.registry_bytes
end
function Sight:_current(row)
    local r = self.r
    if
        r.read(self.generations + row.index, 1):byte() ~= row.generation
        or r.p(self.slots + row.index * 8) ~= row.object
    then
        return false
    end
    local raw = r.read(row.object, L.sibling + 8)
    return r.pointer(raw, 0) == row.vtable
        and r.u(raw, 8) == row.unit
        and r.pointer(raw, L.world) == self.world
        and link(r, raw, L.parent) == row.parent
        and link(r, raw, L.child) == row.child
        and link(r, raw, L.sibling) == row.sibling
end
function Sight:_tree_current()
    if not self:_registry_current() then
        return false
    end
    for i = 1, self.count do
        if not self:_current(self.records[i]) then
            return false
        end
    end
    return true
end
function Sight:_walk(unit, expected_object, expected_parent, depth)
    assert(depth <= MAX_DEPTH and self.count < MAX_UNITS, "weapon attachment tree exceeds bound")
    assert(handle(unit), "weapon attachment handle unavailable")
    local r = self.r
    local index, generation = unit % 0x400000, math.floor(unit / 0x400000)
    assert(
        index < self.capacity and r.read(self.generations + index, 1):byte() == generation,
        "weapon attachment generation retired"
    )
    local object = r.p(self.slots + index * 8)
    assert(not expected_object or object == expected_object, "weapon attachment registry changed")
    assert(not self.seen[object], "weapon attachment cycle or duplicate")
    local raw = r.read(object, L.sibling + 8)
    local vtable, world = r.pointer(raw, 0), r.pointer(raw, L.world)
    assert(r.u(raw, 8) == unit and (not self.world or self.world == world), "weapon attachment identity/world changed")
    assert(address(world), "weapon attachment world unavailable")
    local typed = r.read(vtable + 0xc8, 0x128)
    assert(
        r.pointer(typed, 0) == self.exe + L.type_c8
            and r.pointer(typed, 0x30) == self.exe + L.type_f8
            and r.pointer(typed, 0x120) == self.exe + L.type_1e8,
        "weapon attachment renderer type changed"
    )
    local parent, child, sibling = link(r, raw, L.parent), link(r, raw, L.child), link(r, raw, L.sibling)
    assert(not expected_parent or parent == expected_parent, "weapon attachment parent changed")
    self.world, self.count, self.seen[object] = world, self.count + 1, true
    local row = self.records[self.count]
    row.unit, row.object, row.index, row.generation = unit, object, index, generation
    row.vtable, row.parent, row.child, row.sibling = vtable, parent, child, sibling
    while child ~= 0 do
        assert(address(child), "weapon child pointer unavailable")
        local ref = r.u(r.read(child + 8, 4), 0)
        local direct_index = self.count + 1
        self:_walk(ref, child, object, depth + 1)
        -- Recursion may append grandchildren: use this direct child's captured
        -- sibling instead of the final descendant's sibling.
        child = self.records[direct_index].sibling
    end
end
local function corners(box, points, count)
    assert(type(box) == "table" and type(box.matrix) == "table" and type(box.half) == "table", "weapon box unavailable")
    local m, h = box.matrix, box.half
    for i = 1, 16 do
        assert(finite(m[i]) and math.abs(m[i]) < 1e7, "weapon box matrix invalid")
    end
    for i = 1, 3 do
        assert(finite(h[i]) and h[i] >= 0 and h[i] < 1000, "weapon box half extent invalid")
    end
    assert(h[1] + h[2] + h[3] > 0, "weapon box empty")
    assert(
        math.abs(m[4]) < 1e-5 and math.abs(m[8]) < 1e-5 and math.abs(m[12]) < 1e-5 and math.abs(m[16] - 1) < 1e-5,
        "weapon box is not affine"
    )
    for ix = -1, 1, 2 do
        for iy = -1, 1, 2 do
            for iz = -1, 1, 2 do
                count = count + 1
                local p = points[count]
                local x, y, z = ix * h[1], iy * h[2], iz * h[3]
                p.x, p.y, p.z =
                    m[13] + m[1] * x + m[5] * y + m[9] * z,
                    m[14] + m[2] * x + m[6] * y + m[10] * z,
                    m[15] + m[3] * x + m[7] * y + m[11] * z
            end
        end
    end
    return count
end
function Sight:collect(request)
    self:reset()
    self.request = request
    local result = self.result
    local okay, reason = self:_bounded(FINISH_RESERVE, function()
        local native, r = self.native, self.r
        assert(
            type(request) == "table"
                and handle(request.unit)
                and type(request.owner_current) == "function"
                and type(request.camera_current) == "function",
            "weapon bounds owner unavailable"
        )
        assert(request.owner_current() == true, "weapon bounds owner changed")
        assert(
            type(native.geometry_ready) == "function"
                and type(native.unit_box) == "function"
                and type(native.project_points) == "function",
            "weapon bounds services unavailable"
        )
        local exe, ready_reason = native:geometry_ready()
        self.exe = assert(exe, ready_reason or "weapon bounds services unavailable")
        assert(address(self.exe), "weapon bounds executable unavailable")
        self.registry = r.p(self.exe + L.registry)
        self.registry_bytes = r.read(self.registry + L.slots, 32)
        self.slots, self.capacity, self.generations =
            r.pointer(self.registry_bytes, 0), r.u(self.registry_bytes, 16), r.pointer(self.registry_bytes, 24)
        assert(
            address(self.slots) and address(self.generations) and self.capacity > 0 and self.capacity <= 0x400000,
            "weapon registry bounds changed"
        )
        clear(self.seen)
        self.count, self.world = 0, nil
        self:_walk(request.unit, nil, nil, 0)
        local point_count = 0
        for i = 1, self.count do
            local row = self.records[i]
            local box, why = native:unit_box(row.unit, function(unit)
                return unit == row.unit and self:_registry_current() and self:_current(row)
            end)
            assert(box, why or "weapon box unavailable")
            point_count = corners(box, self.points, point_count)
        end
        -- The Native API consumes a dense array, never old trailing corners.
        local active = self.active_points or {}
        self.active_points = active
        for i = 1, math.max(#active, point_count) do
            active[i] = i <= point_count and self.points[i] or nil
        end
        local projected, why = native:project_points(request.camera, active, request.camera_current)
        assert(type(projected) == "table", why or "weapon bounds projection unavailable")
        local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
        for i = 1, point_count do
            local p = projected[i]
            assert(
                type(p) == "table" and finite(p.x) and finite(p.y) and finite(p.clip) and p.clip <= 1,
                "weapon box corner clipped or unavailable"
            )
            local polygon = self.polygons[math.floor((i - 1) / 8) + 1]
            local corner = polygon[(i - 1) % 8 + 1]
            corner.x, corner.y = p.x, p.y
            left, right, bottom, top =
                math.min(left, p.x), math.max(right, p.x), math.min(bottom, p.y), math.max(top, p.y)
        end
        assert(right > left and top > bottom, "weapon projected bounds empty")
        if not request.defer_owner_after then
            assert(request.owner_current() == true, "weapon bounds owner changed after sampling")
        end
        assert(self:_tree_current() and request.camera_current() == true, "weapon bounds topology/camera changed")
        self.bounds.left, self.bounds.right, self.bounds.bottom, self.bounds.top = left, right, bottom, top
        result.identity, result.context, result.generation, result.camera =
            request.identity, request.context, request.generation, request.camera
        result.follow_token, result.source, result.bounds, result.unit_count =
            request.follow_token, "weapon_bounds", self.bounds, self.count
        for i = 1, math.max(#self.active_polygons, self.count) do
            self.active_polygons[i] = i <= self.count and self.polygons[i] or nil
        end
        result.polygons = self.active_polygons
        result.reason = nil
        self.pending = request.defer_owner_after == true
        result.known = not self.pending
        return true
    end)
    if not okay then
        self.pending, result.known, result.reason = false, false, reason or "weapon bounds unavailable"
    end
    return result
end
-- Session's final full actor/wield/FPS guard supplies the deferred after-batch
-- proof. Recheck the small attachment tree after that proof, then publish.
function Sight:finish(owner_live, follow_token)
    if not self.pending then
        return self.result
    end
    self.pending = false
    local okay, reason = self:_bounded(0, function()
        assert(owner_live == true and follow_token == self.result.follow_token, "weapon bounds final owner changed")
        assert(
            self:_tree_current() and self.request.camera_current() == true,
            "weapon bounds final topology/camera changed"
        )
        return true
    end)
    self.result.known = okay == true
    if not okay then
        self.result.reason = reason
    end
    return self.result
end
return Sight
