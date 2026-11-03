local type, math = type, math
local Core = {}
local BUDGET = 1024
local STATE_SHIFT = 2
local ARC_REACH, ARC_DROP = 100, 1.2
local SAG, TICK = 0.02, 1 / 60
local ARM = { 1.14, 0.62, 0.30 }
local ARM_LOW = { 1.32, -0.44, 0.56 }
local function length(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end
local function free_flight(profile, position, velocity, delta, steps)
    local h, g, cap = delta / steps, profile[1], profile[2]
    local x, y, z = position[1], position[2], position[3]
    local vx, vy, vz = velocity[1], velocity[2], velocity[3]
    local initial = vx * vx + vy * vy + vz * vz
    if initial > cap * cap then
        local scale = cap / math.sqrt(initial)
        vx, vy, vz = vx * scale, vy * scale, vz * scale
    end
    for _ = 1, steps do
        vx, vy, vz = vx + g[1] * h, vy + g[2] * h, vz + g[3] * h
        local squared = vx * vx + vy * vy + vz * vz
        if squared > cap * cap then
            local scale = cap / math.sqrt(squared)
            vx, vy, vz = vx * scale, vy * scale, vz * scale
        end
        x, y, z = x + vx * h, y + vy * h, z + vz * h
    end
    local damp = 1 - math.min(delta * profile[3], 1)
    position[1], position[2], position[3] = x, y, z
    velocity[1], velocity[2], velocity[3] = vx * damp, vy * damp, vz * damp
end
Core.free_flight = free_flight
local function spans(g, c, top, dt)
    if not (g > 0 and g < math.huge) then
        return BUDGET
    end
    local k = math.max(1, math.floor(math.sqrt(8 * SAG / g) / dt))
    if c > 0 then
        while k > 1 and g * (k * dt) ^ 2 / 8 * (1 + c * top * k * dt) > SAG do
            k = k - 1
        end
    end
    return k
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local FIELDS = {
    physics = function(n)
        return { { n.motion_gravity, "f32" }, { n.motion_speed, "f32" }, { n.motion_damping, "f32" } }
    end,
    actors = function(n)
        return { { n.actor_name, "u32" }, { n.next_actor, "u32" }, { n.actor_time, "f32" } }
    end,
    blast = function(n)
        local fields = { { n.radius_inner, "f32" }, { n.radius_outer, "f32" } }
        if n.children ~= nil then
            fields[3] = { n.children, "u32" }
        end
        return fields
    end,
    distribution = function(n)
        return {
            { n.scatter, "f32" },
            { n.drift, "f32" },
            { n.shots, "u32" },
            { n.salvos, "u32" },
            { n.shot_interval, "f32" },
            { n.salvo_interval, "f32" },
            { n.turn, "f32" },
            { n.centered, "f32" },
            { n.bomb_projectile, "u32" },
        }
    end,
    eagle = function(n)
        return { { n.mode_at, "u32" }, { n.pattern_at, "u32" }, { n.projectile_at, "u32" }, { n.guide_length, "f32" } }
    end,
    info = function(n)
        return { { n.info_expire, "u32" }, { n.info_impact, "u32" } }
    end,
    pattern = function(n)
        local fields = { { n.pattern_count, "u32" } }
        for index = 0, math.floor((n.pattern_stride - n.pattern_points) / n.point_stride) - 1 do
            local at = n.pattern_points + index * n.point_stride
            fields[#fields + 1] = { at, "f32" }
            fields[#fields + 1] = { at + 4, "f32" }
        end
        return fields
    end,
    tree = function(n)
        return { { 0, "u32" }, { 4, "u32" }, { n.tree_value, "u32" }, { n.tree_value + 4, "u32" } }
    end,
    motion = function(n)
        return {
            { 0, "f32" },
            { 4, "f32" },
            { 8, "f32" },
            { n.velocity, "f32" },
            { n.velocity + 4, "f32" },
            { n.velocity + 8, "f32" },
            { n.gravity_at, "f32" },
            { n.drag_at, "f32" },
            { n.mass_at, "f32" },
            { n.substeps_at, "u32" },
            { n.follow_at, "u32" },
        }
    end,
}
local CELLS = setmetatable({}, { __mode = "k" })
local function cells(read, n, which, at)
    local by = CELLS[n]
    if by == nil then
        by = {}
        CELLS[n] = by
    end
    local held = by[which]
    if held == nil then
        held = { layout = read.layout(FIELDS[which](n)), got = {} }
        by[which] = held
    end
    return read:value(at, held.layout, held.got)
end
local function motion_id(read, port, template, n, resource, name)
    local block = resource + read:value(resource + n.actor_block)
    local count = read:value(block + n.actor_count)
    for index = 0, count - 1 do
        local actor = block + read:value(block + n.actor_entries + index * 4)
        if read:value(actor + n.actor_name) == name then
            local row = port:call(template, read:value(actor + n.actor_template))
            if row == nil or row == 0 then
                return nil
            end
            return read:value(row + n.template_motion, "u16")
        end
    end
end
function Core.motion_ids(read, port, routines, v, n)
    local name = port:uint64_of(v.name)
    local resource = name ~= nil and port:call(routines.resource, n.resource_kind, name) or nil
    if type(resource) ~= "number" or resource == 0 then
        return nil
    end
    local actors = cells(read, n, "actors", v.settings)
    if actors == nil then
        return nil
    end
    local id = motion_id(read, port, routines.template, n, resource, actors[1])
    if id == nil then
        return nil
    end
    local out = { id = id }
    if actors[2] ~= 0 and actors[3] > 0 then
        out.next = motion_id(read, port, routines.template, n, resource, actors[2])
        if out.next == nil then
            return nil
        end
        out.swap = actors[3]
    end
    return out
end
function Core.motion(read, n, rows, id, gravity)
    if id == nil then
        return nil
    end
    local row = cells(read, n, "physics", rows + id * n.motion_stride)
    if row == nil then
        return nil
    end
    return { { gravity[1] * row[1], gravity[2] * row[1], gravity[3] * row[1] }, row[2], row[3] }
end
local function vector(read, at)
    if type(at) ~= "number" or at == 0 then
        return nil
    end
    return read:vector(at, 3)
end
local function buffer(port, state, name, form, size)
    if state[name] == nil then
        state[name] = port:buffer(form, size) or false
    end
    return state[name] or nil
end
local function node_at(read, port, routines, unit, node)
    if unit == 0 then
        return nil
    end
    return vector(read, port:call(routines.position, unit, node))
end
local function launch_speed(v)
    local speed = v.speed
    if v.scale ~= nil then
        speed = speed * v.scale
    end
    return speed * v.one
end
local function muzzle_pose(read, port, routines, v)
    local node = port:call(routines.muzzle, 0, v.entity)
    local from = type(node) == "number" and node_at(read, port, routines, v.unit, node) or nil
    if from == nil then
        return nil, "muzzle"
    end
    local dx, dy, dz = v.aim[1] - from[1], v.aim[2] - from[2], v.aim[3] - from[3]
    local long = length(dx, dy, dz)
    if not (long > 0) then
        return nil, "launch"
    end
    return from, { dx / long, dy / long, dz / long }
end
local function launch(read, port, routines, state, v, n)
    local speed = launch_speed(v)
    local from, d = muzzle_pose(read, port, routines, v)
    if from == nil then
        return nil, d
    end
    if not finite(speed) or not (speed > 0) then
        return nil, "launch"
    end
    local velocity = { d[1] * speed, d[2] * speed, d[3] * speed }
    local flags = v.flags
    if flags ~= nil and flags % (2 * n.inherit_mask) >= n.inherit_mask then
        local out = buffer(port, state, "inherit", "float", 3)
        if out == nil then
            return nil, "buffer"
        end
        out[0], out[1], out[2] = 0, 0, 0
        port:call(routines.velocity, 0, out, v.entity)
        for index = 1, 3 do
            if not finite(out[index - 1]) then
                return nil, "inherit"
            end
            velocity[index] = velocity[index] + out[index - 1]
            from[index] = from[index] + out[index - 1] * v.dt
        end
    end
    return from, velocity, speed
end
local function path_filter(read, n, filters, word, bit, index)
    if math.floor(word / 2 ^ bit) % 2 == 1 then
        return read:value(filters + n.filter_default)
    end
    local at = index()
    return at ~= nil and read:value(filters + n.filter_base + at * 4) or nil
end
local function explosion(read, v, n, kind)
    if kind == nil or not (kind > 0 and kind < n.kind_count) then
        return nil
    end
    local row = read:ptr(v.explosions + kind * n.explosion_stride)
    if row == nil or row == 0 then
        return nil
    end
    return cells(read, n, "blast", row)
end
local function blast(read, v, n, kind, out)
    local got = explosion(read, v, n, kind)
    if got == nil then
        return nil
    end
    local inner, outer = got[1], got[2]
    if not (finite(inner) and finite(outer) and finite(v.scale_outer) and finite(v.scale_inner)) then
        return got
    end
    out.outer = v.scale_outer * outer
    out.inner = v.scale_inner * (v.scale_outer * inner)
    return got
end
local function axis(origin, finish, angle)
    if origin == nil or not finite(angle) then
        return nil
    end
    local dx, dy = finish[1] - origin[1], finish[2] - origin[2]
    local size = length(dx, dy, 0)
    if not (finite(size) and size > 0) then
        return nil
    end
    dx, dy = dx / size, dy / size
    local c, s = math.cos(angle), math.sin(angle)
    return dx * c - dy * s, dy * c + dx * s
end
local function strip(out, finish, dx, dy, long, wide, shift, side)
    out.inner, out.outer = nil, nil
    out.region = {
        at = { finish[1] + dx * shift - dy * side, finish[2] + dy * shift + dx * side, finish[3] },
        axis = { dx, dy },
        size = { long, wide },
    }
end
local function distribution(n, got, finish, origin, out, children)
    if children then
        out.inner, out.outer, out.reference = nil, nil, true
        return
    end
    local radius = out.outer
    out.inner, out.outer = nil, nil
    local scatter, drift = got[1], got[2]
    if radius == nil or not (finite(scatter) and scatter >= 0 and finite(drift)) then
        return
    end
    radius = scatter + radius
    if drift == 0 then
        out.outer = radius
        return
    end
    local shots, salvos, interval, pause, turn, centered = got[3], got[4], got[5], got[6], got[7], got[8]
    if
        not (
            shots ~= nil
            and shots > 0
            and salvos ~= nil
            and salvos > 0
            and finite(interval)
            and interval >= 0
            and finite(pause)
            and pause >= 0
            and finite(turn)
            and finite(centered)
        )
    then
        return
    end
    local dx, dy = axis(origin, finish, turn * n.degrees[1])
    if dx == nil then
        return
    end
    local travel = (shots * salvos * interval + math.max(0, salvos - 1) * pause) * drift
    if not finite(travel) or travel == 0 then
        out.outer = radius
        return
    end
    if travel < 0 then
        dx, dy, travel = -dx, -dy, -travel
    end
    strip(out, finish, dx, dy, travel + 2 * radius, 2 * radius, centered ~= 0 and 0 or travel / 2, 0)
    out.direction = { dx, dy }
end
local function approach(v, n, finish, origin)
    if v.origin ~= nil then
        local dx, dy = axis(v.origin, finish, 0)
        return dx, dy, 1
    end
    local degrees = v.entry_degrees
    if not finite(degrees) then
        return nil
    end
    if v.heading_degrees ~= nil then
        if not finite(v.heading_degrees) then
            return nil
        end
        degrees = degrees + v.heading_degrees
    end
    local dx, dy = axis(origin, finish, degrees * n.degrees[1])
    return dx, dy, -1
end
local function pattern(read, v, n, set, children, finish, origin, out)
    local inner, radius = out.inner, out.outer
    out.inner, out.outer = nil, nil
    local dx, dy, side = approach(v, n, finish, origin)
    if dx == nil then
        return
    end
    if children then
        out.reference = true
        out.region = { at = { finish[1], finish[2], finish[3] }, axis = { dx, dy } }
        out.direction = { side * dx, side * dy }
        return
    end
    local index = set[2]
    if index == nil or v.patterns == nil then
        return
    end
    local row = cells(read, n, "pattern", v.patterns + index * n.pattern_stride)
    local count = row and row[1]
    if count == nil or count < 1 or count > (#row - 1) / 2 then
        return
    end
    local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
    for point_at = 0, count - 1 do
        local x, y = row[2 + point_at * 2], row[3 + point_at * 2]
        if not (finite(x) and finite(y)) then
            return
        end
        xmin, xmax = math.min(xmin, x), math.max(xmax, x)
        ymin, ymax = math.min(ymin, y), math.max(ymax, y)
    end
    if xmin == 0 and xmax == 0 and ymin == 0 and ymax == 0 then
        out.inner, out.outer, out.direction = inner, radius, { side * dx, side * dy }
        return
    end
    local pad = finite(radius) and math.max(0, radius) or 0
    local long, wide = xmax - xmin + 2 * pad, ymax - ymin + 2 * pad
    if not (long > 0 and wide > 0) then
        return
    end
    strip(out, finish, dx, dy, long, wide, (xmin + xmax) / 2, (ymin + ymax) / 2)
    out.direction = { side * dx, side * dy }
end
local function strafe(v, n, set, finish, origin, out)
    local radius = out.outer
    out.inner, out.outer = nil, nil
    local long = set[4]
    local dx, dy, side = approach(v, n, finish, origin)
    if radius == nil or dx == nil or not (finite(long) and long > 0) then
        return
    end
    dx, dy = side * dx, side * dy
    strip(out, finish, dx, dy, long + 2 * radius, 2 * radius, long / 2, 0)
    out.direction = { dx, dy }
end
local function attack_projectile(read, v, n, set)
    if v.bombardment ~= nil then
        return set[9]
    end
    if set[1] == n.strafing_mode then
        return v.weapon ~= nil and read:value(v.weapon + n.weapon_type) or nil
    end
    if set[1] == n.pattern_mode then
        return set[3]
    end
    return nil
end
local function attack_kind(read, v, n, projectile)
    if projectile == nil or projectile <= 0 or v.infos == nil then
        return nil
    end
    local info = read:ptr(v.infos + projectile * n.info_stride)
    if info == nil or info == 0 then
        return nil
    end
    local got = cells(read, n, "info", info)
    if got == nil then
        return nil
    end
    if got[1] ~= nil and got[1] ~= 0 then
        return got[1]
    end
    return got[2]
end
local function hit_point(read, hits, first)
    local out = {}
    for index = 0, 2 do
        out[index + 1] = read.bytes.f32_bits(hits[first + index])
    end
    return out
end
local function cell(n, at)
    return (n[at] - n.record_at) / 4
end
local TREE_KINDS = {}
local function tree_passes(read, port, routines, v, n, instance)
    if port:call(routines.tree_valid, v.world, instance) ~= true then
        return false
    end
    local kind = port:call(routines.tree_type, v.world, instance)
    local high, low = read.bytes.words_of(kind)
    if high == nil then
        return false
    end
    if TREE_KINDS[kind] ~= nil then
        return TREE_KINDS[kind]
    end
    for row = 0, n.tree_count - 1 do
        local got = cells(read, n, "tree", v.trees + row * n.tree_stride)
        if got[1] == low and got[2] == high then
            local value = got[3]
            local passes = got[4] == 0 and value > n.tree_low and value < n.tree_high and value ~= n.tree_keep
            TREE_KINDS[kind] = passes
            return passes
        end
    end
    TREE_KINDS[kind] = false
    return false
end
local function first_hit(read, port, routines, state, aircraft, v, n, hits, count, fx, fy, fz)
    local stride = n.hit_stride / 4
    local flags, unit, material = cell(n, "flags_at"), cell(n, "unit_at"), cell(n, "material_at")
    local best, nearest
    for index = 0, count - 1 do
        local row = index * stride
        local kind = hits[row + material]
        local passes = kind == n.near_miss or kind == n.skip_material
        if not passes and math.floor(hits[row + flags] / n.tree_flag) % 2 == 1 then
            passes = tree_passes(read, port, routines, v, n, hits[row + unit])
        elseif kind == n.shield then
            passes = port:call(routines.shield, 0, hits + row) == false
        elseif aircraft ~= nil and hits[row + unit] ~= 0 then
            local entity = buffer(port, state, "entity", "uint32_t", 1)
            if entity ~= nil then
                port:call(routines.entity_of, entity, hits[row + unit])
                passes = entity[0] == aircraft
            end
        end
        if not passes then
            local at = hit_point(read, hits, row)
            local far = at[1] and length(at[1] - fx, at[2] - fy, at[3] - fz)
            if far ~= nil and (nearest == nil or far < nearest) then
                best, nearest = index, far
            end
        end
    end
    return best, nearest
end
local function cast(
    read,
    port,
    routines,
    state,
    ignore,
    aircraft,
    v,
    n,
    filter,
    start,
    direction,
    long,
    hits,
    fx,
    fy,
    fz
)
    local count = port:call(routines.ray, filter, start, direction, long, ignore, hits, n.hits)
    if count == nil then
        return false
    end
    if count < 1 then
        return nil
    end
    return first_hit(read, port, routines, state, aircraft, v, n, hits, count, fx, fy, fz)
end
local function struck(port, routines, state, v, n, hits, row, out)
    if math.floor(hits[row + cell(n, "flags_at")] / n.tree_flag) % 2 == 1 then
        return nil
    end
    local unit = hits[row + cell(n, "unit_at")]
    local entity = buffer(port, state, "entity", "uint32_t", 1)
    if unit == 0 or entity == nil then
        return nil
    end
    port:call(routines.entity_of, entity, unit)
    if
        v.faction ~= nil
        and port:call(routines.hostile, v.factions, v.shooter_id, entity[0]) == true
        and port:call(routines.dead, v.health, entity[0]) ~= true
    then
        out.foe = true
    end
    return entity[0]
end
local function bounce(v, n, hits, row, normal, d, dist, pace, entity)
    if v.impact == 0 or (entity ~= nil and entity ~= v.no_entity) then
        return nil
    end
    if hits[row + cell(n, "material_at")] == n.water then
        return false
    end
    local arming, explode, ricochets, steep, floor =
        v.arming, v.explode_angle, v.ricochets, v.ricochet_angle, v.ricochet_speed
    if not (finite(arming) and finite(explode) and finite(steep) and finite(floor)) or ricochets == nil then
        return nil
    end
    local angle = 90
        - math.deg(math.asin(math.min(1, math.abs(normal[1] * d[0] + normal[2] * d[1] + normal[3] * d[2]))))
    local armed = dist >= arming
    if armed and angle <= explode then
        return false
    end
    return ricochets > 0 and pace > floor and (not armed or angle >= steep)
end
local function seen(read, port, routines, v, n, filter, start, direction, hits, out)
    local e, f, k = v.eye, out.finish, out.normal
    if e == nil or (k ~= nil and v.lift == nil) then
        return nil
    end
    local lift = k ~= nil and v.lift or 0
    local tx, ty, tz = f[1] + (k and k[1] or 0) * lift, f[2] + (k and k[2] or 0) * lift, f[3] + (k and k[3] or 0) * lift
    local long = length(tx - e[1], ty - e[2], tz - e[3])
    if not (long > 0) then
        return true
    end
    start[0], start[1], start[2] = e[1], e[2], e[3]
    direction[0], direction[1], direction[2] = (tx - e[1]) / long, (ty - e[2]) / long, (tz - e[3]) / long
    local index =
        cast(read, port, routines, nil, v.shooter, nil, v, n, filter, start, direction, long, hits, e[1], e[2], e[3])
    if index == false then
        return nil
    end
    return index == nil
end
local function known_arc(state, v, speed)
    local by_speed = state.arcs and state.arcs[v.info]
    return by_speed and by_speed[speed]
end
local function arcs(port, routines, state, v, body, record, at, speed, life)
    local known = known_arc(state, v, speed)
    if known ~= nil then
        return known
    end
    if not (v.dt > 0) then
        return nil
    end
    record[0], record[1], record[2] = 0, 0, 0
    record[at], record[at + 1], record[at + 2] = speed, 0, 0
    local per, elapsed, x, drop, moving = v.dt / body.substeps, 0, 0, 0, record + at
    for _ = 1, BUDGET do
        local was_x, was_drop = x, drop
        port:call(routines.step, 0, moving, record, 0, body.gravity, body.drag, body.mass, body.substeps, per)
        x, drop = record[0], -record[2]
        if x >= ARC_REACH and x > was_x then
            x, drop = ARC_REACH, was_drop + (drop - was_drop) * (ARC_REACH - was_x) / (x - was_x)
        end
        elapsed = elapsed + v.dt
        if
            x >= ARC_REACH
            or (life > 0 and elapsed >= life)
            or length(record[at], record[at + 1], record[at + 2]) / speed < v.floor
        then
            break
        end
    end
    local answer = { lob = { drop, x, speed }, lobbed = drop >= ARC_DROP }
    state.arcs = state.arcs or {}
    state.arcs[v.info] = state.arcs[v.info] or {}
    state.arcs[v.info][speed] = answer
    return answer
end
local function walk_bullet(body, port, routines, record, at, from, velocity)
    local gravity, drag, mass, substeps = body.gravity, body.drag, body.mass, body.substeps
    local per, moving = TICK / substeps, record + at
    local fall, gx, gy, gz = false, 0, 0, 0
    if drag > 0 then
        record[0], record[1], record[2], record[at], record[at + 1], record[at + 2] = 0, 0, 0, 0, 0, 0
        port:call(routines.step, 0, moving, record, 0, gravity, 0, mass, substeps, per)
        fall, gx, gy, gz = true, record[at], record[at + 1], record[at + 2]
    end
    record[0], record[1], record[2] = from[1], from[2], from[3]
    record[at], record[at + 1], record[at + 2] = velocity[1], velocity[2], velocity[3]
    local ux, uy, uz = record[at], record[at + 1], record[at + 2]
    port:call(routines.step, 0, moving, record, 0, gravity, drag, mass, substeps, per)
    local dx, dy, dz = record[at] - ux, record[at + 1] - uy, record[at + 2] - uz
    local g, c, top = length(dx, dy, dz) / TICK, 0, 0
    if fall then
        local launched, pace = length(ux, uy, uz), length(record[at], record[at + 1], record[at + 2])
        local slow = math.min(launched, pace)
        g = length(gx, gy, gz) / TICK
        if slow > 0 then
            c = length(dx - gx, dy - gy, dz - gz) / TICK / (slow * slow)
        end
        top = math.max(launched, pace)
        if c > 0 then
            top = math.max(top, math.sqrt(g / c))
        end
    end
    return function(k)
        port:call(routines.step, 0, moving, record, 0, gravity, drag, mass, substeps * k, per)
    end,
        spans(g, c, top, TICK)
end
local function bullet_ends(v, travelled, pace, speed)
    if travelled >= v.limit then
        return "distance"
    end
    if pace / speed < v.floor then
        return "slow"
    end
end
local function bullet_body(gravity, drag, mass, substeps)
    return { gravity = gravity, drag = drag, mass = mass, substeps = substeps, walk = walk_bullet, ends = bullet_ends }
end
local function physics_ends() end
local function walk_physics(body, _, _, record, at, from, velocity)
    local g, damping, cap = 0, 0, 0
    for _, profile in ipairs({ body.profile, body.next }) do
        local a = profile[1]
        g = math.max(g, length(a[1], a[2], a[3]))
        damping, cap = math.max(damping, profile[3]), math.max(cap, profile[2])
    end
    local position = { from[1], from[2], from[3] }
    local speed_now = { velocity[1], velocity[2], velocity[3] }
    local profile, time = body.profile, 0
    return function(k)
        for _ = 1, k do
            if body.next ~= nil and time >= body.swap then
                profile = body.next
            end
            free_flight(profile, position, speed_now, TICK, body.steps)
            time = time + TICK
        end
        record[0], record[1], record[2] = position[1], position[2], position[3]
        record[at], record[at + 1], record[at + 2] = speed_now[1], speed_now[2], speed_now[3]
    end,
        spans(g, cap > 0 and damping / cap or 0, cap, TICK)
end
local function shell(read, port, routines, state, v, n, record, at)
    if v.info == nil or v.speed == nil or v.aim == nil then
        return nil, "info"
    end
    local fast = launch_speed(v)
    if not (finite(fast) and fast > 0) then
        return nil, "launch"
    end
    local known = known_arc(state, v, fast)
    if known ~= nil and not known.lobbed then
        return nil, "straight", known
    end
    local info = v.info
    if info == 0 then
        return nil, "info"
    end
    local mass, drag, caliber, gravity, substeps, life = v.mass, v.drag, v.caliber, v.gravity, v.substeps, v.life
    if
        not (finite(mass) and finite(drag) and finite(caliber) and finite(gravity) and finite(life))
        or substeps == nil
        or substeps < 1
    then
        return nil, "info"
    end
    local radius = caliber * v.caliber_scale
    local body = bullet_body(gravity, radius * radius * v.drag_area * v.drag_air * drag, mass * v.mass_scale, substeps)
    local arc = arcs(port, routines, state, v, body, record, at, fast, life)
    if arc == nil then
        return nil, "dt"
    end
    if not arc.lobbed then
        return nil, "straight", arc
    end
    local from, velocity, speed = launch(read, port, routines, state, v, n)
    if from == nil then
        return nil, velocity
    end
    if v.flags == nil or v.filter == nil then
        return nil, "filter"
    end
    local filter = path_filter(read, n, v.filters, v.flags, n.path_bit - STATE_SHIFT, function()
        return v.filter
    end)
    if filter == nil then
        return nil, "filter"
    end
    return {
        body = body,
        life = life,
        info = info,
        arc = arc,
        filter = filter,
        ignore = v.shooter,
        from = from,
        velocity = velocity,
        speed = speed,
    }
end
local function physics_body(read, v, n)
    local ids = v.body_ids
    if ids == nil or v.motions == nil or v.acceleration == nil or v.solver_steps == nil then
        return nil, "physics"
    end
    local profile = Core.motion(read, n, v.motions, ids.id, v.acceleration)
    if profile == nil then
        return nil, "physics"
    end
    local body = { profile = profile, steps = v.solver_steps, walk = walk_physics, ends = physics_ends }
    if ids.next ~= nil then
        body.next, body.swap = Core.motion(read, n, v.motions, ids.next, v.acceleration), ids.swap
        if body.next == nil then
            return nil, "physics"
        end
    end
    return body
end
local function hand_pose(read, port, routines, v)
    local f = v.forward
    local long = f and length(f[1], f[2], f[3]) or 0
    if not (long > 0) then
        return nil, "forward"
    end
    local d = { f[1] / long, f[2] / long, f[3] / long }
    local ux, uy, uz = -d[1] * d[3], -d[2] * d[3], 1 - d[3] * d[3]
    local up = length(ux, uy, uz)
    if up > 0 then
        local a = v.throw_angle * v.degree
        local c, s = math.cos(a), math.sin(a)
        d = { d[1] * c + ux / up * s, d[2] * c + uy / up * s, d[3] * c + uz / up * s }
    end
    local hand
    if v.hand_node ~= nil then
        hand = v.hand_node >= 0 and node_at(read, port, routines, v.shooter, v.hand_node) or nil
    else
        hand = node_at(read, port, routines, v.unit, 0)
    end
    if hand == nil then
        return nil, "hand"
    end
    local shoulder = v.shoulder_node ~= nil
            and v.shoulder_node >= 0
            and node_at(read, port, routines, v.shooter, v.shoulder_node)
        or nil
    if shoulder == nil then
        return nil, "shoulder"
    end
    local cx, cy, cz = f[1] / long, f[2] / long, f[3] / long
    local flat = length(cx, cy, 0)
    if not (flat > 0) then
        return nil, "forward"
    end
    local rx, ry = cy / flat, -cx / flat
    local wx, wy, wz = ry * cz, -rx * cz, rx * cy - ry * cx
    if v.release_anim == nil or v.short_anim == nil then
        return nil, "anim"
    end
    local arm = v.release_anim == v.short_anim and ARM_LOW or ARM
    local ahead, above, side = arm[1], arm[2], arm[3]
    local base = {
        shoulder[1] + cx * ahead + wx * above + rx * side - d[1] * v.reach,
        shoulder[2] + cy * ahead + wy * above + ry * side - d[2] * v.reach,
        shoulder[3] + cz * ahead + wz * above - d[3] * v.reach,
    }
    return base, d, hand
end
local function pushed(read, port, routines, state, v, base, d, start, direction, hits)
    for k = 1, 3 do
        start[k - 1], direction[k - 1] = base[k], d[k]
    end
    local count = port:call(routines.ray, v.launch_filter, start, direction, v.one, 0, hits, 1)
    if count == nil then
        return nil, "ray"
    end
    local reach = v.reach
    if count >= 1 then
        local h = hit_point(read, hits, 0)
        reach = math.min(reach, length(h[1] - base[1], h[2] - base[2], h[3] - base[3]) * v.nudge)
    end
    local speed = v.fixed_speed
    if not (speed > 0) then
        if v.throw_power == nil or v.energy_min == nil or v.energy_max == nil or v.energy_scale == nil then
            return nil, "throw"
        end
        local power, m = v.throw_power, v.motion
        if
            m ~= nil
            and v.move_floor ~= nil
            and v.move_add ~= nil
            and v.move_sub ~= nil
            and length(m[1], m[2], m[3]) >= v.move_floor
        then
            local dot = m[1] * d[1] + m[2] * d[2] + m[3] * d[3]
            if dot > 0 then
                power = power + v.move_add
            elseif dot < 0 then
                power = power - v.move_sub
            end
        end
        speed = math.sqrt(math.max(0, v.energy_min + (v.energy_max - v.energy_min) * power) * v.energy_scale)
    end
    local cell = buffer(port, state, "boost", "float", 1)
    if cell == nil then
        return nil, "buffer"
    end
    cell[0] = speed
    port:call(routines.boost, 0, v.booster, cell)
    speed = cell[0]
    if not (finite(speed) and speed > 0) then
        return nil, "launch"
    end
    return reach, speed
end
local function thrown(read, port, routines, state, v, n, start, direction, hits)
    local body, why = physics_body(read, v, n)
    if body == nil then
        return nil, why
    end
    if v.reach == nil or v.nudge == nil or v.fixed_speed == nil or v.launch_filter == nil or v.booster == nil then
        return nil, "throw"
    end
    local base, d, hand
    if v.from_hand == true then
        if v.throw_angle == nil or v.degree == nil then
            return nil, "throw"
        end
        base, d, hand = hand_pose(read, port, routines, v)
    elseif v.aim ~= nil then
        base, d = muzzle_pose(read, port, routines, v)
    else
        return nil, "aim"
    end
    if base == nil then
        return nil, d
    end
    local reach, speed = pushed(read, port, routines, state, v, base, d, start, direction, hits)
    if reach == nil then
        return nil, speed
    end
    local filter = read:value(v.filters + n.filter_base)
    if filter == nil then
        return nil, "filter"
    end
    local life = 0
    if finite(v.fuse) and v.fuse > 0 then
        life = v.fuse - read.bytes.f32_bits(n.release_delay)
        if not (life > 0) then
            return nil, "fuse"
        end
    end
    local shot = {
        body = body,
        life = life,
        filter = filter,
        ignore = v.shooter,
        from = { base[1] + d[1] * reach, base[2] + d[2] * reach, base[3] + d[3] * reach },
        velocity = { d[1] * speed, d[2] * speed, d[3] * speed },
        speed = speed,
    }
    if hand ~= nil then
        shot.drawn = { hand[1] + d[1] * reach, hand[2] + d[2] * reach, hand[3] + d[3] * reach }
    end
    return shot
end
local function live(read, v, n)
    local m = cells(read, n, "motion", v.live)
    if m[11] ~= 0 then
        return nil, "unit"
    end
    local state = read:value(v.pool + n.pool_states + v.slot * n.state_stride, "u16")
    if state == nil then
        return nil, "filter"
    end
    local filter = path_filter(read, n, v.filters, state, n.path_bit, function()
        local kind = read:value(v.pool + n.pool_type + v.slot * n.type_stride)
        local info = kind ~= nil and kind ~= 0 and read:ptr(v.infos + kind * n.info_stride) or nil
        return info ~= nil and read:value(info + n.info_filter) or nil
    end)
    if filter == nil then
        return nil, "filter"
    end
    local ignore = 0
    if math.floor(state / n.shooter_bit) % 2 == 1 then
        ignore = read:value(v.pool + n.pool_shooter + v.slot * n.shooter_stride)
        if ignore == nil then
            return nil, "shooter"
        end
    end
    return {
        body = bullet_body(m[7], m[8], m[9], m[10]),
        life = 0,
        from = { m[1], m[2], m[3] },
        ignore = ignore,
        velocity = { m[4], m[5], m[6] },
        speed = length(m[4], m[5], m[6]),
        filter = filter,
        aircraft = v.aircraft,
    }
end
local function pass(path, points, x, y, z)
    if path == nil then
        return points
    end
    path[points * 3 + 1], path[points * 3 + 2], path[points * 3 + 3] = x, y, z
    return points + 1
end
local function bent(path, points, drawn)
    local shift = { path[1] - drawn[1], path[2] - drawn[2], path[3] - drawn[3] }
    local total, ax, ay, az = 0, path[1], path[2], path[3]
    for index = 2, points do
        local x, y, z = path[index * 3 - 2], path[index * 3 - 1], path[index * 3]
        total, ax, ay, az = total + length(x - ax, y - ay, z - az), x, y, z
    end
    if not (total > 0) then
        return
    end
    local along
    along, ax, ay, az = 0, path[1], path[2], path[3]
    for index = 1, points do
        local x, y, z = path[index * 3 - 2], path[index * 3 - 1], path[index * 3]
        along = along + length(x - ax, y - ay, z - az)
        ax, ay, az = x, y, z
        local k = 1 - along / total
        path[index * 3 - 2], path[index * 3 - 1], path[index * 3] = x - shift[1] * k, y - shift[2] * k, z - shift[3] * k
    end
end
local function ended(read, port, routines, v, n, shot, path, points, start, direction, hits, out)
    if path ~= nil then
        points = pass(path, points, out.finish[1], out.finish[2], out.finish[3])
        for index = points * 3 + 1, #path do
            path[index] = nil
        end
        if shot.drawn ~= nil then
            bent(path, points, shot.drawn)
        end
        out.path = path
    end
    if v.eye ~= nil then
        out.distance = length(out.finish[1] - v.eye[1], out.finish[2] - v.eye[2], out.finish[3] - v.eye[3])
    end
    out.origin = shot.from
    if shot.arc ~= nil then
        out.lob, out.lobbed = shot.arc.lob, true
    end
    if v.mark then
        out.seen = seen(read, port, routines, v, n, shot.filter, start, direction, hits, out)
    end
    return out
end
local function fly(read, port, routines, state, v, n, path)
    for kind in pairs(TREE_KINDS) do
        TREE_KINDS[kind] = nil
    end
    local at = n.velocity / 4
    local record = buffer(port, state, "record", "float", at + 3)
    local start, direction = buffer(port, state, "from", "float", 3), buffer(port, state, "direction", "float", 3)
    local hits = buffer(port, state, "hits", "uint32_t", math.ceil(n.hits * n.hit_stride / 4))
    if record == nil or start == nil or direction == nil or hits == nil then
        return nil, "buffer"
    end
    local shot, why, arc
    if v.live ~= nil then
        shot, why = live(read, v, n)
    elseif v.thrown == true then
        shot, why = thrown(read, port, routines, state, v, n, start, direction, hits)
    else
        shot, why, arc = shell(read, port, routines, state, v, n, record, at)
    end
    if shot == nil then
        if arc == nil then
            return nil, why
        end
        arc.straight = arc.straight or { why = why, lob = arc.lob, lobbed = false }
        return arc.straight
    end
    local body, life = shot.body, shot.life
    local from, velocity, speed, filter, info = shot.from, shot.velocity, shot.speed, shot.filter, shot.info
    local travelled, elapsed = 0, 0
    local advance, span = body.walk(body, port, routines, record, at, from, velocity)
    record[0], record[1], record[2] = from[1], from[2], from[3]
    record[at], record[at + 1], record[at + 2] = velocity[1], velocity[2], velocity[3]
    local points = pass(path, 0, from[1], from[2], from[3])
    local ticks = 0
    while ticks < BUDGET do
        local k = math.min(span, BUDGET - ticks)
        if life > 0 then
            k = math.max(1, math.min(k, math.ceil((life - elapsed) / TICK)))
        end
        local fx, fy, fz = record[0], record[1], record[2]
        advance(k)
        local x, y, z = record[0], record[1], record[2]
        local vx, vy, vz = record[at], record[at + 1], record[at + 2]
        if not (finite(x) and finite(y) and finite(z)) then
            return nil, "nan"
        end
        local moved, pace = length(x - fx, y - fy, z - fz), length(vx, vy, vz)
        start[0], start[1], start[2] = fx, fy, fz
        if moved > 0 then
            direction[0], direction[1], direction[2] = (x - fx) / moved, (y - fy) / moved, (z - fz) / moved
        else
            direction[0], direction[1], direction[2] = 0, 0, 0
        end
        ticks = ticks + k
        local index = cast(
            read,
            port,
            routines,
            state,
            shot.ignore,
            shot.aircraft,
            v,
            n,
            filter,
            start,
            direction,
            moved,
            hits,
            fx,
            fy,
            fz
        )
        if index == false then
            return nil, "ray"
        end
        if index ~= nil then
            local row = index * n.hit_stride / 4
            local normal = hit_point(read, hits, row + cell(n, "normal_at"))
            if normal[1] * direction[0] + normal[2] * direction[1] + normal[3] * direction[2] > 0 then
                normal = { -normal[1], -normal[2], -normal[3] }
            end
            local out = { finish = hit_point(read, hits, row), normal = normal, why = "hit" }
            local entity = struck(port, routines, state, v, n, hits, row, out)
            local f = out.finish
            local dist = travelled + length(f[1] - fx, f[2] - fy, f[3] - fz)
            if info ~= nil then
                out.bounce = bounce(v, n, hits, row, normal, direction, dist, pace, entity)
            end
            return ended(read, port, routines, v, n, shot, path, points, start, direction, hits, out)
        end
        travelled, elapsed = travelled + moved, elapsed + TICK * k
        local why_end = life > 0 and elapsed >= life and "life" or body.ends(v, travelled, pace, speed)
        if why_end ~= nil then
            return ended(
                read,
                port,
                routines,
                v,
                n,
                shot,
                path,
                points,
                start,
                direction,
                hits,
                { finish = { x, y, z }, why = why_end }
            )
        end
        points = pass(path, points, x, y, z)
    end
    return nil, "budget"
end
Core.predict = fly
function Core.heading(read, settings, n)
    return read:value(settings + n.block + n.read - n.copy, "f32")
end
function Core.blast(read, v, n)
    local at = v.at
    local finish, why, origin = at, nil, nil
    if at.why ~= nil or at.finish ~= nil then
        finish, why, origin = at.finish, at.why, at.origin
    end
    if finish == nil then
        return nil
    end
    local out = {}
    if v.eagle == nil and v.bombardment == nil then
        local got = blast(read, v, n, why == "hit" and v.impact ~= nil and v.impact ~= 0 and v.impact or v.expire, out)
        if got ~= nil and n.children ~= nil and got[3] ~= 0 then
            out.inner, out.outer = nil, nil
        end
        return out
    end
    local set = cells(read, n, v.bombardment ~= nil and "distribution" or "eagle", v.bombardment or v.eagle)
    if set == nil then
        return out
    end
    local got = blast(read, v, n, attack_kind(read, v, n, attack_projectile(read, v, n, set)), out)
    local children = got ~= nil and n.children ~= nil and got[3] ~= nil and got[3] ~= 0
    if v.bombardment ~= nil then
        distribution(n, set, finish, origin, out, children)
    elseif set[1] == n.pattern_mode then
        pattern(read, v, n, set, children, finish, origin, out)
    elseif set[1] == n.strafing_mode then
        strafe(v, n, set, finish, origin, out)
    else
        out.inner, out.outer = nil, nil
        local dx, dy, side = approach(v, n, finish, origin)
        if dx ~= nil then
            out.direction = { side * dx, side * dy }
        end
    end
    return out
end
function Core.scale(read, port, routines, state, v, n)
    local out = { outer = 1, inner = 1 }
    local entry = port:call(routines.tag_of, v.tags, v.kind)
    if type(entry) ~= "number" or entry == 0 then
        return out
    end
    local row = read:value(entry)
    if row == nil then
        return nil
    end
    local at = v.tags + row * n.tag_stride
    local count = read:value(at + n.tag_count)
    if count == nil then
        return nil
    end
    for index = 0, count - 1 do
        local hash = read:value(at + n.tag_hashes + index * 4)
        local part = hash == n.outer and "outer" or hash == n.inner and "inner" or nil
        if part ~= nil then
            local cell = buffer(port, state, "upgrade", "float", 1)
            if cell == nil then
                return nil
            end
            cell[0] = 1
            port:call(routines.upgrade, v.upgrades, cell, hash, 0)
            if not finite(cell[0]) then
                return nil
            end
            out[part] = cell[0]
        end
    end
    return out
end
return Core
