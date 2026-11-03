local Hud = {}
Hud.__index = Hud
function Hud.new(panel, line)
    return setmetatable({ panel = panel, line = line, clock = 0, frame = 0, values = { {}, {}, {} } }, Hud)
end
function Hud:restore()
    if self.width_state == nil then
        return
    end
    local panel = self.panel.editable and self.panel.base or nil
    local state = self.line:reset(panel, self.width_state == "requested")
    if state == "cleared" then
        self.width_state = nil
    elseif state ~= nil then
        self.width_state = state
    end
end
function Hud:prepare(ammo, functions, fire_mode, zeroing)
    local panel, line = self.panel, self.line
    self.visible = false
    self.frame = self.frame + 1
    local dt = panel.dt
    self.clock = self.clock + (dt or 0)
    local parent, row, awake
    if ammo or functions or fire_mode or zeroing then
        parent, row, awake = panel:weapon_mount()
    end
    if parent == nil then
        if line.parent ~= nil then
            line:close()
        end
        self.next_content = nil
        self:restore()
        return
    end
    local alive = line:alive()
    if alive == nil then
        return
    end
    local fresh = line.parent ~= parent
        or line.row ~= row
        or alive == false
        or self.ammo ~= ammo
        or self.functions ~= functions
        or self.fire_mode ~= fire_mode
        or self.zeroing ~= zeroing
    if fresh then
        if line.parent ~= nil then
            line:close()
        end
        line:create(parent, row, self.frame, ammo, functions, fire_mode, zeroing)
        self.ammo, self.functions, self.fire_mode, self.zeroing = ammo, functions, fire_mode, zeroing
        self.next_content = nil
    end
    if not awake then
        line:show(false)
        self.next_content = nil
        self:restore()
        return
    end
    line:show(true)
    self.visible = true
    return dt == nil or self.next_content == nil or self.clock >= self.next_content
end
function Hud:put(count, slots)
    if self.ammo then
        self.line:put(count)
    end
    local values = self.values
    if self.functions then
        values[1][1], values[1][2], values[1][3] = unpack(slots[1], 1, 3)
    end
    if self.fire_mode then
        values[2][1], values[2][2], values[2][3] = unpack(slots[2], 1, 3)
    end
    if self.zeroing then
        values[3][1], values[3][2], values[3][3] = unpack(slots[3], 1, 3)
    end
    self.next_content = self.clock + 1 / 30
end
function Hud:finish()
    if not self.visible then
        return
    end
    local line = self.line
    line:update(self.frame, self.values)
    if line:extend(line.row, line.parent) then
        self.width_state = "applied"
    else
        self:restore()
    end
end
function Hud:close()
    self.line:close()
    self:restore()
end
return Hud
