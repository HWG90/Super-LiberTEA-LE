local resources = require("game.resources").decal
local Core, Instance = {}, {}
Instance.__index = Instance
local ROOT, VISIBILITY_FLAG = 0, 1
local PICTURES = { "plain", "warn", "strip_plain", "strip_warn", "arrows_plain", "arrows_warn" }
function Instance:call(name, ...)
    return self.port:call(assert(self.port:routine(name)), ...)
end
function Core.new(access, numbers)
    local port, judge = access.call.world, access.call.judge
    local spec = { fade = 0.1, reference = { radius = 20, strip = { 50, 20 } }, arrow = 6 }
    for key, value in pairs(resources) do
        spec[key] = value
    end
    spec.lines = {
        dash = 1.5,
        gap = 1,
        flow = 4,
        strands = 2,
        width = 0.12,
        pitch = 0.05,
        edge = 0.06,
        styles = {
            { { ring = 1, width = 0.18 }, { dot = 0.14 } },
            {
                { arc = 1, width = 0.18, from = 20, to = 70 },
                { arc = 1, width = 0.18, from = 110, to = 160 },
                { arc = 1, width = 0.18, from = 200, to = 250 },
                { arc = 1, width = 0.18, from = 290, to = 340 },
                { dot = 0.14 },
            },
        },
    }
    local pose, vector, turn =
        assert(port:buffer("float", 16)), assert(port:buffer("float", 3)), assert(port:buffer("float", 4))
    local from, to = assert(port:buffer("float", 3)), assert(port:buffer("float", 3))
    for index, value in ipairs(spec.pose) do
        pose[index - 1] = value
    end
    local textures = {}
    for _, name in ipairs(PICTURES) do
        textures[name] = judge:uint64_of(spec.look[name])
    end
    return setmetatable({
        port = port,
        judge = judge,
        read = access.read,
        n = numbers,
        spec = spec,
        pose = pose,
        vector = vector,
        turn = turn,
        from = from,
        to = to,
        textures = textures,
        unit = judge:uint64_of(spec.unit),
        material = judge:uint64_of(spec.material),
        lit = false,
        items = {},
        spare = {},
        trail = { alpha = 0, toward = 0 },
        axes = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } },
        strands = {},
        radii = {},
    }, Instance)
end
local function ready(self, world)
    local n, spec, judge = self.n, self.spec, self.judge
    local keeper = self.read:ptr(world + n.world_resource_manager)
    if judge:open(keeper, n.unit_type, spec.unit) ~= true then
        return false
    end
    local app = judge:app()
    if judge:open(app, n.material_type, spec.material) ~= true then
        return false
    end
    for _, name in ipairs(PICTURES) do
        if spec.look[name] ~= nil and judge:open(app, n.texture_type, spec.look[name]) ~= true then
            return false
        end
    end
    return true
end
local function decal_material(self, mesh)
    local n, read, slot = self.n, self.read, self.spec.slot
    local count = read:value(mesh + n.mesh_material_count)
    local slots, materials = read:ptr(mesh + n.mesh_material_slots), read:ptr(mesh + n.mesh_materials)
    if slots == nil or materials == nil then
        return nil
    end
    local found
    for index = 0, count - 1 do
        if read:value(slots + index * 4) == slot then
            if found ~= nil then
                return nil
            end
            found = index
        end
    end
    local material = found and read:ptr(materials + found * 8)
    if material == 0 then
        return nil
    end
    return material
end
local function spawn_hidden(self, world)
    local id = self:call("world_spawn_unit", world, self.unit, self.pose)
    if type(id) ~= "number" then
        return nil
    end
    local unit = { id = id, alpha = 0, toward = 0 }
    self.units[#self.units + 1] = unit
    self:call("unit_visibility_set", id, 0, VISIBILITY_FLAG)
    return unit
end
local function paint(self, unit, picture)
    self:call("material_texture_set", unit.material, self.spec.picture, self.textures[picture])
    self:call("mesh_instance_refresh", unit.mesh)
    unit.picture = picture
end
local function make_one(self, world, picture)
    local spec = self.spec
    local unit = spawn_hidden(self, world)
    if unit == nil then
        return nil, "spawn"
    end
    local id = unit.id
    self:call("unit_material_set", id, spec.slot, self.material)
    if self:call("unit_mesh_count", id) ~= 1 then
        return nil, "mesh"
    end
    local mesh = self:call("unit_mesh", id, 0)
    local material = type(mesh) == "number" and mesh ~= 0 and decal_material(self, mesh) or nil
    if material == nil then
        return nil, "material"
    end
    unit.mesh, unit.material = mesh, material
    paint(self, unit, picture)
    for _, scalar in ipairs(spec.scalars) do
        self:call("material_float_set", material, scalar[1], scalar[2])
    end
    self:call("unit_lod_static", id, 1)
    return unit
end
local function living(self)
    local first = self.units and self.units[1]
    if first == nil then
        return nil
    end
    return self:call("unit_alive", first.id) == true
end
local function blank(self)
    for index, object in ipairs(self.objects) do
        if self.drawn[index] then
            self:call("line_object_reset", object)
            self:call("line_object_dispatch", self.at_world, object)
        end
    end
end
local function clear_lines(self)
    local drawn = self.drawn
    if drawn ~= nil and (drawn[1] or drawn[2]) and living(self) then
        blank(self)
    end
    if drawn ~= nil then
        drawn[1], drawn[2] = false, false
    end
    self.mark = nil
end
local function drop(self)
    if living(self) then
        if self.drawn ~= nil then
            blank(self)
        end
        local units, objects = self.units, self.objects or {}
        for index = #units, 1, -1 do
            self:call("world_destroy_unit", self.at_world, units[index].id)
        end
        for index = #objects, 1, -1 do
            self:call("line_object_destroy", self.at_world, objects[index])
        end
    end
    self.units, self.objects, self.drawn, self.want, self.mark = nil, nil, nil, nil, nil
    self.lit, self.items, self.spare, self.trail = false, {}, {}, { alpha = 0, toward = 0 }
end
local DEPTH, TOP = 0, 1
local TINY = 1e-6
local function length(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end
local OUTLINES = { true, false }
local function line(self, object, colour, ax, ay, az, bx, by, bz)
    local from, to = self.from, self.to
    from[0], from[1], from[2] = ax, ay, az
    to[0], to[1], to[2] = bx, by, bz
    self:call("line_object_add_line", object, colour, from, to)
end
local function band(self, spec, colour, eye, ax, ay, az, bx, by, bz)
    local lx, ly, lz = (ax + bx) / 2 - eye[1], (ay + by) / 2 - eye[2], (az + bz) / 2 - eye[3]
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local far, along = length(lx, ly, lz), length(dx, dy, dz)
    local sx, sy, sz = dy * lz - dz * ly, dz * lx - dx * lz, dx * ly - dy * lx
    local side = length(sx, sy, sz)
    if not (far > TINY and along > TINY and side > TINY * far * along) then
        return
    end
    sx, sy, sz = sx / side, sy / side, sz / side
    local width = math.rad(spec.width) * far
    for strand = 1, spec.strands do
        local shift = width * ((strand - 1) / math.max(spec.strands - 1, 1) - 0.5)
        local ox, oy, oz = sx * shift, sy * shift, sz * shift
        line(self, self.objects[1], colour, ax + ox, ay + oy, az + oz, bx + ox, by + oy, bz + oz)
    end
end
local STEPS, ARC_STEP = 24, 25
local function aim_of(target, eye, normal)
    local long = normal and length(normal[1], normal[2], normal[3]) or 0
    if long > TINY then
        return normal[1] / long, normal[2] / long, normal[3] / long
    end
    local x, y, z = eye[1] - target[1], eye[2] - target[2], eye[3] - target[3]
    long = length(x, y, z)
    if not (long > TINY) then
        return nil
    end
    return x / long, y / long, z / long
end
local function place_mark(self, eye, normal, at)
    local ax, ay, az
    if eye ~= nil then
        ax, ay, az = aim_of(at, eye, normal)
    end
    if ax == nil then
        self.mark = nil
        return
    end
    local mark = self.mark
    if mark == nil then
        mark = { hit = {}, face = {} }
        self.mark = mark
    end
    mark.hit[1], mark.hit[2], mark.hit[3] = at[1], at[2], at[3]
    mark.face[1], mark.face[2], mark.face[3] = ax, ay, az
end
local function strands(out, width, spec, outline)
    for k = #out, 1, -1 do
        out[k] = nil
    end
    local half, pitch = width / 2, spec.pitch
    if outline then
        for k = 1, math.max(1, math.floor(spec.edge / pitch + 0.5)) do
            out[#out + 1], out[#out + 2] = -half - k * pitch, half + k * pitch
        end
        return out
    end
    local count = math.max(1, math.floor(width / pitch + 0.5))
    for k = 0, count - 1 do
        out[#out + 1] = count == 1 and 0 or width * k / (count - 1) - half
    end
    return out
end
local function point(c, u, v, scale, r, a)
    local ca, sa = math.cos(math.rad(a)), math.sin(math.rad(a))
    return c[1] + (u[1] * ca + v[1] * sa) * r * scale,
        c[2] + (u[2] * ca + v[2] * sa) * r * scale,
        c[3] + (u[3] * ca + v[3] * sa) * r * scale
end
local function shape_lines(self, top, colour, spec, shape, outline, c, n, u, v, scale)
    if shape.ring ~= nil or shape.dot ~= nil then
        local centre, axis, radii = self.from, self.to, self.radii
        for k = #radii, 1, -1 do
            radii[k] = nil
        end
        if shape.ring ~= nil then
            for _, o in ipairs(strands(self.strands, shape.width, spec, outline)) do
                radii[#radii + 1] = shape.ring + o
            end
        elseif outline then
            for k = 1, math.max(1, math.floor(spec.edge / spec.pitch + 0.5)) do
                radii[#radii + 1] = shape.dot + k * spec.pitch
            end
        else
            local r = shape.dot
            while r > 0 do
                radii[#radii + 1], r = r, r - spec.pitch
            end
        end
        centre[0], centre[1], centre[2] = c[1], c[2], c[3]
        axis[0], axis[1], axis[2] = n[1], n[2], n[3]
        for _, r in ipairs(radii) do
            if r > 0 then
                self:call("line_object_add_circle", top, colour, centre, r * scale, axis, STEPS)
            end
        end
        return
    end
    local count = math.max(1, math.ceil((shape.to - shape.from) / ARC_STEP))
    local step = (shape.to - shape.from) / count
    for _, o in ipairs(strands(self.strands, shape.width, spec, outline)) do
        for k = 0, count - 1 do
            local ax, ay, az = point(c, u, v, scale, shape.arc + o, shape.from + step * k)
            local bx, by, bz = point(c, u, v, scale, shape.arc + o, shape.from + step * (k + 1))
            line(self, top, colour, ax, ay, az, bx, by, bz)
        end
    end
end
local function marker(self, spec, colour, edge, eye)
    local mark = self.mark
    if mark == nil then
        return
    end
    local hit, face = mark.hit, mark.face
    local far, flat = length(hit[1] - eye[1], hit[2] - eye[2], hit[3] - eye[3]), length(face[1], face[2], face[3])
    if not (far > TINY and flat > TINY) then
        return
    end
    local n, u, v = self.axes[1], self.axes[2], self.axes[3]
    n[1], n[2], n[3] = face[1] / flat, face[2] / flat, face[3] / flat
    local ux, uy = n[2], -n[1]
    local across = length(ux, uy, 0)
    if across > TINY then
        ux, uy = ux / across, uy / across
    else
        ux, uy = 1, 0
    end
    u[1], u[2], u[3] = ux, uy, 0
    v[1], v[2], v[3] = n[2] * u[3] - n[3] * u[2], n[3] * u[1] - n[1] * u[3], n[1] * u[2] - n[2] * u[1]
    local shapes, top, scale = spec.styles[self.trail.style + 1], self.objects[2], math.rad(1) * far
    for _, outline in ipairs(OUTLINES) do
        for _, shape in ipairs(shapes) do
            shape_lines(self, top, outline and edge or colour, spec, shape, outline, hit, n, u, v, scale)
        end
    end
end
local function tint(colour, alpha)
    if alpha >= 1 then
        return colour
    end
    return math.floor(math.floor(colour / 16777216) * alpha + 0.5) * 16777216 + colour % 16777216
end
local function lines(self, world, eye, clock, trail, alpha)
    local spec = self.spec.lines
    if eye == nil then
        return clear_lines(self)
    end
    if self.objects == nil then
        self.objects = {}
        for index, depth in ipairs({ DEPTH, TOP }) do
            local object = self:call("line_object_create", world, depth, 0)
            if type(object) ~= "number" or object == 0 then
                drop(self)
                error("line-create", 0)
            end
            self.objects[index] = object
        end
        self.drawn, self.want = { false, false }, { false, false }
    end
    local path, drawn, want = trail.path, self.drawn, self.want
    want[1], want[2] = path ~= nil, trail.mark ~= nil and trail.reveal >= 1
    for index, object in ipairs(self.objects) do
        if drawn[index] then
            self:call("line_object_reset", object)
        end
    end
    local period = spec.dash + spec.gap
    local phase = (clock or 0) * spec.flow % period
    local colour = tint(trail.colour, alpha)
    local limit = math.huge
    if path ~= nil and trail.reveal < 1 then
        local total = 0
        for index = 4, #path - 2, 3 do
            total = total
                + length(
                    path[index] - path[index - 3],
                    path[index + 1] - path[index - 2],
                    path[index + 2] - path[index - 1]
                )
        end
        limit = total * trail.reveal
    end
    local travelled, walked, start = period - phase, 0, nil
    local sx, sy, sz
    for index = 4, path and #path - 2 or 0, 3 do
        local ax, ay, az = path[index - 3], path[index - 2], path[index - 1]
        local dx, dy, dz = path[index] - ax, path[index + 1] - ay, path[index + 2] - az
        local long = length(dx, dy, dz)
        if not (long > TINY) then
            long = 0
        end
        local stop = math.min(long, limit - walked)
        local last = index + 3 > #path - 2 or stop < long
        local from = 0
        while from < stop do
            local into = (travelled + from) % period
            local to = math.min(stop, from + (into < spec.dash and spec.dash - into or period - into))
            local p, q = from / long, to / long
            if into < spec.dash then
                if start == nil then
                    start, sx, sy, sz = true, ax + dx * p, ay + dy * p, az + dz * p
                end
                if into + (to - from) >= spec.dash or last then
                    band(self, spec, colour, eye, sx, sy, sz, ax + dx * q, ay + dy * q, az + dz * q)
                    start = nil
                end
            end
            from = to
        end
        if stop < long then
            break
        end
        travelled, walked = travelled + long, walked + long
    end
    if want[2] then
        marker(self, spec, tint(trail.mark, alpha), tint(trail.edge, alpha), eye)
    end
    for index, object in ipairs(self.objects) do
        if want[index] or drawn[index] then
            self:call("line_object_dispatch", world, object)
        end
        drawn[index] = want[index]
    end
end
local function make(self, world, rows)
    if not ready(self, world) then
        self.refused = "resource"
        return false
    end
    self.units = {}
    if #rows == 0 and spawn_hidden(self, world) == nil then
        self.units, self.refused = nil, "spawn"
        return false
    end
    return true
end
local function take(self, world, picture)
    local spare = table.remove(self.spare)
    if spare ~= nil then
        return spare
    end
    local unit, why = make_one(self, world, picture)
    if unit ~= nil then
        return unit
    end
    drop(self)
    self.refused = why
    return nil, why
end
local function ramp(self, state, on, clock)
    local toward, seconds = on and 1 or 0, self.spec.fade
    if state.toward ~= toward then
        state.toward = toward
        state.since = clock and clock - (on and state.alpha or 1 - state.alpha) * seconds
    end
    if clock == nil or state.since == nil then
        return toward
    end
    local now = math.min(1, math.max(0, (clock - state.since) / seconds))
    return on and now or 1 - now
end
local function fade(self, unit, on, clock)
    local toward, alpha = on and 1 or 0, unit.alpha
    if unit.toward == toward and alpha == toward then
        return
    end
    local now = ramp(self, unit, on, clock)
    if now == alpha then
        return
    end
    if now > 0 then
        self:call("material_float_set", unit.material, self.spec.alpha, now)
    end
    if alpha == 0 then
        self:call("unit_visibility_set", unit.id, 1, VISIBILITY_FLAG)
    elseif now == 0 then
        self:call("unit_visibility_set", unit.id, 0, VISIBILITY_FLAG)
    end
    unit.alpha = now
end
local function place(self, unit, x, y, z, w, d, h, yaw, picture, clock)
    if unit.picture ~= picture then
        paint(self, unit, picture)
    end
    local v = self.vector
    local at = unit.at
    if at == nil or at[1] ~= x or at[2] ~= y or at[3] ~= z then
        v[0], v[1], v[2] = x, y, z
        self:call("unit_local_position_set", unit.id, ROOT, v)
        at = at or {}
        at[1], at[2], at[3] = x, y, z
        unit.at = at
    end
    local size = unit.size
    if size == nil or size[1] ~= w or size[2] ~= d or size[3] ~= h then
        v[0], v[1], v[2] = w, d, h
        self:call("unit_local_scale_set", unit.id, ROOT, v)
        size = size or {}
        size[1], size[2], size[3] = w, d, h
        unit.size = size
    end
    if (unit.yaw or 0) ~= yaw then
        local q, base = self.turn, self.spec.rotation
        local s, c = math.sin(yaw / 2), math.cos(yaw / 2)
        q[0], q[1] = c * base[1] - s * base[2], c * base[2] + s * base[1]
        q[2], q[3] = c * base[3] + s * base[4], c * base[4] - s * base[3]
        self:call("unit_local_rotation_set", unit.id, ROOT, q)
        unit.yaw = yaw
    end
    fade(self, unit, true, clock)
end
local function axis_of(value)
    if value == nil or type(value[1]) ~= "number" or type(value[2]) ~= "number" then
        return nil
    end
    local x, y = value[1], value[2]
    if x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge or (x == 0 and y == 0) then
        return nil
    end
    return value
end
local function inside(me, at, outer, region, depth)
    if me == nil then
        return false
    end
    if region ~= nil then
        local x, y = me[1] - region.at[1], me[2] - region.at[2]
        local a, b = region.axis[1], region.axis[2]
        return math.abs(x * a + y * b) <= region.size[1] / 2
            and math.abs(-x * b + y * a) <= region.size[2] / 2
            and math.abs(me[3] - region.at[3]) <= depth / 2
    end
    return outer ~= nil and length(me[1] - at[1], me[2] - at[2], me[3] - at[3]) <= outer
end
local function draw(self, item, row, me, world, clock)
    local spec, at = self.spec, row.at
    local region, outer = row.region, row.outer
    local direction = axis_of(row.direction)
    if row.reference == true then
        if region ~= nil then
            local held = item.reference or {}
            held.at, held.axis, held.size = region.at, region.axis, spec.reference.strip
            item.reference, region = held, held
        else
            outer = spec.reference.radius
        end
    end
    local depth = region ~= nil and math.min(region.size[1], region.size[2]) or nil
    local warn = inside(me, at, outer, region, depth) and "warn" or "plain"
    local units = item.units
    for index = 1, direction ~= nil and 3 or 2 do
        local picture = index == 3 and "arrows_" .. warn or region ~= nil and index == 2 and "strip_" .. warn or warn
        if units[index] == nil then
            local unit, why = take(self, world, picture)
            if unit == nil then
                return false, why
            end
            units[index] = unit
        end
    end
    for index = 1, 2 do
        local picture = region ~= nil and index == 2 and "strip_" .. warn or warn
        local unit = units[index]
        local r = row.inner
        if index == 2 then
            r = outer
        end
        if region ~= nil and index == 2 then
            local s = region.size
            place(
                self,
                unit,
                region.at[1],
                region.at[2],
                region.at[3],
                s[1],
                depth,
                s[2],
                math.atan2(region.axis[2], region.axis[1]),
                picture,
                clock
            )
        elseif region == nil and r ~= nil and r > 0 and (index == 2 or not row.reference) then
            place(self, unit, at[1], at[2], at[3], 2 * r, 2 * r, 2 * r, 0, warn, clock)
        else
            fade(self, unit, false, clock)
        end
    end
    if direction ~= nil then
        local c, s = region ~= nil and region.at or at, region ~= nil and region.size or nil
        local w, h = s ~= nil and s[1] or spec.arrow, s ~= nil and s[2] or spec.arrow
        place(
            self,
            units[3],
            c[1],
            c[2],
            c[3],
            w,
            math.min(w, h),
            h,
            math.atan2(direction[2], direction[1]),
            "arrows_" .. warn,
            clock
        )
    elseif units[3] ~= nil then
        fade(self, units[3], false, clock)
    end
    return true
end
local function vanish(self, key, item, clock, live)
    local dark = true
    for _, unit in ipairs(item.units) do
        if unit.alpha > 0 then
            if live then
                fade(self, unit, false, clock)
            else
                unit.alpha = 0
            end
        end
        dark = dark and unit.alpha == 0
    end
    if not dark then
        return
    end
    for _, unit in ipairs(item.units) do
        self.spare[#self.spare + 1] = unit
    end
    self.items[key] = nil
end
local function lit_of(self)
    for _, item in pairs(self.items) do
        for _, unit in ipairs(item.units) do
            if unit.alpha > 0 then
                return true
            end
        end
    end
    return self.trail.alpha > 0
end
local function trail_step(self, world, shot, eye, clock)
    local trail = self.trail
    local on = shot ~= nil
    local drawn = self.drawn
    if not on and (world ~= self.at_world or not (drawn ~= nil and (drawn[1] or drawn[2]))) then
        trail.alpha, trail.toward, trail.path, trail.grown, trail.mark = 0, 0, nil, false, nil
        return clear_lines(self)
    end
    local now = ramp(self, trail, on, clock)
    trail.alpha = now
    if on then
        place_mark(self, eye, shot.normal, shot.at)
        trail.path = shot.path
        trail.grown = trail.grown or now >= 1
        trail.reveal = trail.grown and 1 or now
        trail.colour, trail.mark, trail.edge, trail.style = shot.colour, shot.mark, shot.edge, shot.style
    elseif now <= 0 then
        trail.path, trail.grown, trail.mark = nil, false, nil
        return clear_lines(self)
    end
    lines(self, world, eye, clock, trail, on and not trail.grown and 1 or now)
end
function Instance:step(world, clock, observer, rows, shot, eye)
    if #rows == 0 and shot == nil then
        if self.lit then
            if world ~= self.at_world then
                clock = nil
            end
            local live = next(self.items) ~= nil and living(self)
            for key, item in pairs(self.items) do
                vanish(self, key, item, clock, live)
            end
            trail_step(self, world, nil, eye, clock)
            self.lit = lit_of(self)
        end
        if not self.lit then
            clear_lines(self)
        end
        return true
    end
    if world ~= self.at_world then
        drop(self)
        self.at_world, self.refused = world, nil
    end
    if self.refused ~= nil then
        return false, self.refused
    end
    if living(self) == false then
        drop(self)
    end
    if self.units == nil then
        make(self, world, rows)
        if self.units == nil then
            return false, self.refused
        end
    end
    local frame = (self.frame or 0) + 1
    self.frame = frame
    for _, row in ipairs(rows) do
        if row.at ~= nil then
            local key = assert(row.key)
            local item = self.items[key]
            if item == nil then
                item = { units = {} }
                self.items[key] = item
            end
            item.seen = frame
            local okay, why = draw(self, item, row, observer, world, clock)
            if not okay then
                self.lit = lit_of(self)
                return false, why
            end
        end
    end
    for key, item in pairs(self.items) do
        if item.seen ~= frame then
            vanish(self, key, item, clock, true)
        end
    end
    trail_step(self, world, shot, eye, clock)
    self.lit = lit_of(self)
    return true
end
function Instance:close()
    if self.at_world == nil then
        return
    end
    drop(self)
    self.at_world, self.refused = nil, nil
end
return Core
