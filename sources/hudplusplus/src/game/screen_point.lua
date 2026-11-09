local Point = {}
Point.__index = Point
function Point.new(port, n)
    return setmetatable({
        port = port,
        width = n.hud_design_width[1],
        height = n.hud_design_height[1],
        width_div = n.ping_edge_width_div[1],
        height_div = n.ping_edge_height_div[1],
        point = assert(port:buffer("float", 3)),
        out = assert(port:buffer("float", 3)),
        project_call = assert(port:routine("camera_world_to_screen")),
        screen_call = assert(port:routine("screen_size")),
    }, Point)
end
function Point:project(camera, at)
    if camera == nil or at == nil then
        return
    end
    local point, out = self.point, self.out
    point[0], point[1], point[2] = at[1], at[2], at[3]
    self.port:call(self.project_call, out, camera, point)
    if not (out[2] <= 1) then
        return
    end
    local width, height = self.port:call(self.screen_call)
    if type(width) ~= "number" or type(height) ~= "number" then
        return
    end
    local scale = math.min(width / self.width, height / self.height)
    if not (scale > 0) then
        return
    end
    width, height = width / scale, height / scale
    local x_edge, y_edge = width / self.width_div, height / self.height_div
    return math.min(math.max(out[0] / scale, x_edge), width - x_edge),
        math.min(math.max(out[1] / scale, y_edge), height - y_edge)
end
return Point
