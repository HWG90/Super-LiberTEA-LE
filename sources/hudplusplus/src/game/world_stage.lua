local Pose = require("game.world_pose")
local Stage = {}
Stage.__index = Stage
function Stage.new(ui, port, size)
    return setmetatable({
        ui = ui,
        read = ui.read,
        n = ui.n,
        size = size,
        racks = {},
        pose = assert(Pose.new(port, ui.read, ui.n)),
        matrix = assert(ui.port:buffer("float", 16)),
    }, Stage)
end
function Stage:rack(size)
    assert(self.root == nil, "rack-after-build")
    local rack = { size = size, state = {}, display = {} }
    self.racks[#self.racks + 1] = rack
    return rack
end
function Stage:hide()
    self.positioned = false
    self.pose:forget()
    if self.ui:alive(self.root) == true then
        self.ui:opacity(self.root, 0)
    end
end
function Stage:prepare(panel)
    self.context, self.gui, self.positioned = nil, nil, false
    local read, n, ui = self.read, self.n, self.ui
    if not panel.editable then
        self:hide()
        return false, "no-panel"
    end
    local game = read:module("game")
    local contexts = read:ptr(game + n.gui_contexts)
    local scene = read:ptr(game + n.hud_scene_manager)
    if contexts == nil or scene == nil then
        self:hide()
        return false, "no-world"
    end
    local world = read:ptr(scene + n.ui_world_at)
    local context = contexts + n.world_ui_slot * n.gui_context_stride
    local state = read:value(context, "u8")
    if world == nil then
        self:hide()
        return false, "no-world"
    end
    if state ~= n.ui_context_live or read:ptr(context + n.ui_context_world) ~= world then
        self:hide()
        if state == n.ui_context_empty then
            ui:call("ui_world_context_build", 0, n.world_ui_slot, world, 0, n.ui_context_world_kind)
            return false, "context"
        end
        return false, "stale"
    end
    self.context, self.scene = context, scene
    self.gui = read:ptr(context + n.ui_context_gui)
    if self.gui == nil then
        self:hide()
        return false, "no-gui"
    end
    if self.root == nil or not self.root.live then
        self:hide()
        for _, rack in ipairs(self.racks) do
            Pose.drop(rack.state)
        end
        ui:context(nil, function()
            self.root = ui:root(n.world_ui_slot, self.root)
            ui:size(self.root, self.size[1], self.size[2])
            ui:opacity(self.root, 0)
            for _, rack in ipairs(self.racks) do
                rack.node = ui:node(n.posed_frame_size, rack.node)
                ui:call("posed_frame_init", rack.node.at)
                ui:size(rack.node, rack.size[1], rack.size[2])
                ui:opacity(rack.node, 0)
                ui:attach(self.root.at, rack.node)
                for index = 1, 16 do
                    rack.display[index] = nil
                end
            end
            ui:call("widget_refresh", self.root.at)
        end, context)
    end
    return true
end
function Stage:place(frame, body, clear)
    if self.context == nil or clear ~= true then
        self:hide()
        return false
    end
    local read, n = self.read, self.n
    local camera_manager = read:ptr(read:module("game") + n.camera_manager)
    local camera = read:ptr(self.scene + n.ui_camera_at)
    local eye
    if camera_manager ~= nil then
        eye = read:ptr(camera_manager)
    end
    if camera == nil or eye == nil then
        self:hide()
        return false
    end
    local okay, why = self.pose:frame(self.gui, frame, self.size, camera, eye, camera_manager + n.camera_pose_at, body)
    if not okay then
        self:hide()
        return false, why
    end
    self.ui:opacity(self.root, 1)
    self.positioned = true
    return true
end
function Stage:place_rack(rack, placement, unit, node)
    if not self.positioned then
        return false
    end
    local e, why = self.pose:pose(rack.state, placement, rack.size, unit, node)
    if e == nil then
        self.ui:opacity(rack.node, 0)
        return false, why
    end
    local changed = false
    for index = 1, 16 do
        if rack.display[index] ~= e[index] then
            changed = true
            break
        end
    end
    if changed then
        for index = 1, 16 do
            rack.display[index], self.matrix[index - 1] = e[index], e[index]
        end
        self.ui:call("posed_frame_set", rack.node.at, self.matrix)
    end
    self.ui:opacity(rack.node, 1)
    return true
end
function Stage:hide_rack(rack)
    if rack.node ~= nil and rack.node.live then
        self.ui:opacity(rack.node, 0)
    end
end
function Stage:submit(dt)
    if self.context ~= nil and self.gui ~= nil and self.ui:alive(self.root) == true then
        self.ui:submit(self.root, dt)
    end
end
function Stage:close()
    self:hide()
    self:submit(0)
    self.ui:destroy(self.root)
    for _, rack in ipairs(self.racks) do
        self.ui:destroy(rack.node)
    end
    self.context, self.gui = nil, nil
end
return Stage
