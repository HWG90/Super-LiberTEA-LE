local type, math = type, math
local sqrt, atan2, math_cos, math_sin = math.sqrt, math.atan2, math.cos, math.sin
local Core, Instance = {}, {}
Instance.__index = Instance
function Instance:call(name, ...)
    return self.port:call(assert(self.port:routine(name)), ...)
end
local function pose_slot()
    return { x = { 0, 0, 0 }, y = { 0, 0, 0 }, z = { 0, 0, 0 }, o = { 0, 0, 0 } }
end
local function vec()
    return { 0, 0, 0 }
end
function Core.new(port, read, numbers)
    local matrix = port:buffer("float", 16)
    local margin = numbers.screen_edge_margin
    if
        matrix == nil
        or type(margin) ~= "table"
        or type(margin[1]) ~= "number"
        or type(numbers.camera_fov_view) ~= "number"
    then
        return nil, "pose"
    end
    local cells, place = {}, {}
    for row = 0, 3 do
        for column = 0, 2 do
            cells[#cells + 1] = { row * 16 + column * 4, "f32" }
        end
    end
    for column = 10, 12 do
        place[#place + 1] = cells[column]
    end
    local e = {}
    for index = 1, 16 do
        e[index] = 0
    end
    e[1], e[6], e[11], e[16] = 1, 1, 1, 1
    return setmetatable({
        port = port,
        read = read,
        margin = margin[1],
        matrix = matrix,
        view_index = numbers.camera_fov_view,
        pose_cells = read.layout(cells),
        pose_values = {},
        place_cells = read.layout(place),
        place_values = {},
        poses = { view = pose_slot(), game = pose_slot(), body = pose_slot() },
        plane = {},
        b = vec(),
        e = e,
    }, Instance)
end
local function world_of(pose, l, index)
    return pose.x[index] * l[1] + pose.y[index] * l[2] + pose.z[index] * l[3]
end
local function local_of(pose, v)
    local dx, dy, dz = v[1] - pose.o[1], v[2] - pose.o[2], v[3] - pose.o[3]
    v[1] = pose.x[1] * dx + pose.x[2] * dy + pose.x[3] * dz
    v[2] = pose.y[1] * dx + pose.y[2] * dy + pose.y[3] * dz
    v[3] = pose.z[1] * dx + pose.z[2] * dy + pose.z[3] * dz
end
local function from_local(pose, v)
    local x, y, z = world_of(pose, v, 1), world_of(pose, v, 2), world_of(pose, v, 3)
    v[1], v[2], v[3] = pose.o[1] + x, pose.o[2] + y, pose.o[3] + z
end
local ROWS = { "x", "y", "z", "o" }
local function pose_of(self, at, pose)
    if type(at) ~= "number" or at == 0 then
        return nil
    end
    local cells = self.read:value(at, self.pose_cells, self.pose_values)
    for row = 1, 4 do
        local base = (row - 1) * 3
        local a, b, c = cells[base + 1], cells[base + 2], cells[base + 3]
        if a == nil or b == nil or c == nil or a ~= a or b ~= b or c ~= c then
            return nil
        end
        if row < 4 then
            local length = math.sqrt(a * a + b * b + c * c)
            if not (length > 1e-6) then
                return nil
            end
            a, b, c = a / length, b / length, c / length
        end
        local axis = pose[ROWS[row]]
        axis[1], axis[2], axis[3] = a, b, c
    end
    return pose
end
local function half_tan(fov)
    if type(fov) ~= "number" or not (fov > 0 and fov < math.pi) then
        return nil
    end
    return math.tan(fov / 2)
end
function Instance:forget()
    self.fov_on, self.view_of = nil, nil
end
local function node_pose(self, unit, node)
    if unit == nil or node == nil then
        return nil, "unread:anchor"
    end
    if unit == 0 or not (node >= 0) then
        return nil, "no-unit"
    end
    if self:call("unit_alive", unit) ~= true then
        return nil, "dead"
    end
    local at = self:call("unit_world_pose", unit, node)
    if type(at) ~= "number" or at == 0 then
        return nil, "pose"
    end
    return at
end
function Instance:frame(gui, world, size, camera, eye, eye_pose, body)
    if gui == nil then
        return nil, "unread"
    end
    local fov = self:call("camera_fov", eye)
    local tan_v = half_tan(fov)
    if tan_v == nil then
        return nil, "eye-fov"
    end
    if self.fov_on ~= fov or self.fov_camera ~= camera then
        self:call("camera_fov_set", camera, fov, self.view_index)
        self.fov_on, self.fov_camera = fov, camera
    end
    if self.view_of ~= camera then
        if pose_of(self, self:call("camera_world_pose", camera), self.poses.view) == nil then
            return nil, "camera-pose"
        end
        self.view_of = camera
    end
    local width, height = self:call("screen_resolution")
    if type(width) ~= "number" or type(height) ~= "number" or not (width > 0 and height > 0) then
        return nil, "screen"
    end
    if pose_of(self, eye_pose, self.poses.game) == nil then
        return nil, "eye-pose"
    end
    if not world.fixed then
        local at, why = node_pose(self, body, 0)
        if at == nil then
            return nil, why
        end
        if pose_of(self, at, self.poses.body) == nil then
            return nil, "body"
        end
    end
    local plane, view, m = self.plane, self.poses.view, self.matrix
    plane.height = world.share * 2 * tan_v
    plane.mix, plane.cap = world.mix, math.rad(world.cap)
    plane.unit = plane.height / size[2]
    plane.pixel = 2 * tan_v / height
    plane.tan_v, plane.tan_h = tan_v, tan_v * width / height
    local unit = plane.unit
    for index = 1, 3 do
        m[index - 1] = view.x[index] * unit
        m[index + 3] = view.y[index] * unit
        m[index + 7] = view.z[index] * unit
        m[index + 11] = view.o[index] + view.y[index]
    end
    m[3], m[7], m[11], m[15] = 0, 0, 0, 1
    self:call("gui_move", gui, m)
    return true
end
local function inside(margin, value, half_view, extent)
    local limit = half_view * (1 - 2 * margin) - extent
    if limit < 0 then
        return 0
    end
    return math.max(-limit, math.min(limit, value))
end
local function follow(state, b, scene, dt)
    if not (scene.tau > 0) or type(dt) ~= "number" then
        state.held = nil
        return
    end
    local held = state.held
    if held == nil then
        state.held = { b[1], b[2], b[3] }
        return
    end
    local pull = 1 - math.exp(-dt / scene.tau)
    for index = 1, 3 do
        held[index] = held[index] + (b[index] - held[index]) * pull
    end
    local ox, oy, oz = b[1] - held[1], b[2] - held[2], b[3] - held[3]
    local gap = math.sqrt(ox * ox + oy * oy + oz * oz)
    if not (gap > scene.radius) then
        return
    end
    local k = scene.radius / gap
    b[1], b[2], b[3] = held[1] + ox * k, held[2] + oy * k, held[3] + oz * k
end
function Instance:pose(state, panel, size, unit, node)
    local plane = self.plane
    local scale = plane.unit
    local height = size[2] * scale
    local last = state.last
    local switched = last ~= nil and (state.offset ~= panel.offset or state.fixed ~= panel.fixed)
    if switched then
        state.held = nil
    end
    state.offset, state.fixed = panel.offset, panel.fixed
    local b, x, z = self.b, 0, 0
    if panel.fixed then
        x, z = panel.offset[1] * height, panel.offset[2] * height
        state.held = nil
    else
        local at, why = node_pose(self, unit, node)
        if at == nil then
            return nil, why
        end
        local cells = self.read:value(at, self.place_cells, self.place_values)
        b[1], b[2], b[3] = cells[1], cells[2], cells[3]
        if b[1] == nil or b[2] == nil or b[3] == nil or b[1] ~= b[1] or b[2] ~= b[2] or b[3] ~= b[3] then
            return nil, "pose"
        end
        local body = self.poses.body
        local_of(body, b)
        follow(state, b, panel.scene, panel.dt)
        from_local(body, b)
        local_of(self.poses.game, b)
        if not (b[2] > 1e-6) then
            return nil, "behind"
        end
        x = b[1] / b[2] + panel.offset[1] * height
        z = b[3] / b[2] + panel.offset[2] * height
        local ceiling = panel.scene.ceiling
        if ceiling ~= nil then
            z = math.min(z, -height / 2 - ceiling * height)
        end
    end
    local off = state.off
    if switched then
        off = {}
        state.off = off
        off[1], off[2] = last[1] - x, last[2] - z
    end
    if off ~= nil then
        local tau = panel.scene.tau
        local keep = Core.keep(tau, panel.dt)
        off[1], off[2] = off[1] * keep, off[2] * keep
        if Core.near(off[1], off[2], plane.pixel) then
            state.off = nil
        else
            x, z = x + off[1], z + off[2]
        end
    end
    x = inside(self.margin, x, plane.tan_h, size[1] * scale / 2)
    z = inside(self.margin, z, plane.tan_v, height / 2)
    if last == nil then
        last = {}
        state.last = last
    end
    last[1], last[2] = x, z
    local cos, sin, ax, az = 1, 0, 0, 0
    if not panel.fixed then
        local front, eye = self.poses.body.y, self.poses.game
        local f1, f2, f3, ex, ey, ez = front[1], front[2], front[3], eye.x, eye.y, eye.z
        local fx = f1 * ex[1] + f2 * ex[2] + f3 * ex[3]
        local fy = f1 * ey[1] + f2 * ey[2] + f3 * ey[3]
        local fz = f1 * ez[1] + f2 * ez[2] + f3 * ez[3]
        local side = sqrt(fx * fx + fz * fz)
        if side > 1e-6 then
            local angle = atan2(side, fy) * plane.mix
            if angle > plane.cap then
                angle = plane.cap
            end
            cos, sin, ax, az = math_cos(angle), math_sin(angle), fz / side, -fx / side
        end
    end
    local e, cx, cz, k = self.e, size[1] / 2, size[2] / 2, 1 - cos
    e[1], e[2], e[3] = cos + k * ax * ax, sin * az, k * ax * az
    e[5], e[6], e[7] = -sin * az, cos, sin * ax
    e[9], e[10], e[11] = k * ax * az, -sin * ax, cos + k * az * az
    e[13], e[14], e[15] = x / scale - cx * e[1] - cz * e[9], -cx * e[2] - cz * e[10], z / scale - cx * e[3] - cz * e[11]
    return e
end
function Core.drop(state)
    state.held, state.last, state.off, state.offset, state.fixed = nil, nil, nil, nil, nil
end
function Core.keep(tau, dt)
    return (tau > 0 and type(dt) == "number") and math.exp(-dt / tau) or 0
end
function Core.near(dx, dy, limit)
    return math.abs(dx) < limit and math.abs(dy) < limit
end
function Instance:pixel()
    return self.plane.pixel / self.plane.unit
end
return Core
