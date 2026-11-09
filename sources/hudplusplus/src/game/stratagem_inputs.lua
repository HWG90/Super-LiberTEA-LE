local Inputs = {}
Inputs.__index = Inputs
function Inputs.new(weapon)
    return setmetatable({ weapon = weapon, read = weapon.read, n = weapon.n }, Inputs)
end
function Inputs:ball(cell)
    local weapon, n = self.weapon, self.n
    local manager = weapon:manager(n.beacon_manager)
    if manager == nil then
        return nil
    end
    return weapon:find(manager + n.beacon_map, cell, weapon.invalid_entity), manager
end
function Inputs:wrapper(panel)
    return panel.mission + self.n.hud_widgets_panels_stratagem_hud_at
end
local function find_history(self, avatar, players)
    local weapon, read, n = self.weapon, self.read, self.n
    if avatar == nil or avatar == weapon.invalid_avatar or players == nil then
        return nil
    end
    local history = weapon:manager(n.stratagem_slots_global)
    if history == nil then
        return nil
    end
    local count = read:value(history + n.player_history_count, "u32")
    local key = weapon:local_key(players)
    if count == nil or count > n.player_history_limit or key == nil then
        return nil
    end
    for index = 0, count - 1 do
        local entry = history + index * n.player_history_stride
        local current = read:value(entry, "key64")
        if current == nil then
            return nil
        end
        if current == key then
            return entry + n.player_history_data
        end
    end
end
function Inputs:history(avatar, players)
    if self.mine == nil then
        self.mine = find_history(self, avatar, players) or false
    end
    return self.mine or nil
end
function Inputs:record(avatar, players, row)
    local read, n = self.read, self.n
    if row == nil or row < 0 or row >= n.stratagem_row_cap then
        return nil
    end
    local record = self:history(avatar, players)
    if record ~= nil and read:value(record + row * n.stratagem_row_stride + n.stratagem_row_record, "u32") ~= nil then
        return record
    end
end
function Inputs:selection(panel, world, select)
    local read, n = self.read, self.n
    local wrapper = self:wrapper(panel)
    self.mode = read:value(wrapper + n.stratagem_panel_input, "u8")
    if self.mode ~= nil and self.mode > 0 then
        self.listing = true
    end
    if not select then
        return
    end
    self.showing = true
    self.group, self.original = wrapper + n.stratagem_panel_group, wrapper + n.stratagem_list
    local input = world.manager + n.stratagem_input + world.index * n.roots_avatar_manager_controller_stride
    self.input = input
    if self.listing then
        return
    end
    local matched = read:value(input + n.stratagem_input_number, "u32")
    if matched ~= nil and matched > 0 then
        self.row = read:value(input + n.stratagem_input_row, "u32")
    end
end
function Inputs:prepare(panel, world, select, list)
    self.showing, self.listing, self.player, self.mode, self.row, self.card_record = nil, nil, nil, nil, nil, nil
    self.original, self.group, self.wanted, self.input = nil, nil, nil, nil
    self.mine = nil
    if not (select or list) or not panel.editable or world.ready ~= true then
        return false
    end
    local read, n = self.read, self.n
    local wanted =
        read:value(world.manager + n.avatar_wanted_slot + world.index * n.roots_avatar_manager_controller_stride, "u32")
    self.wanted = wanted == n.stratagem_ball_slot
    if self.wanted then
        self:selection(panel, world, select)
    end
    return select == true and (not self.wanted or (not self.listing and self.row == nil))
end
function Inputs:observe(panel, world, player, players, cell)
    if self.wanted == nil then
        return
    end
    local read, n = self.read, self.n
    local ball, beacon
    if not self.wanted then
        ball, beacon = self:ball(cell)
        if ball == nil then
            return
        end
        self:selection(panel, world, true)
    end
    if self.listing then
        self.player = player
        return
    end
    if self.row == nil then
        if beacon == nil then
            ball, beacon = self:ball(cell)
        end
        if ball ~= nil then
            local entries = read:ptr(beacon + n.beacon_entries)
            if entries ~= nil then
                self.row = read:value(entries + ball * n.beacon_entry_size + n.beacon_row, "u32")
            end
        end
    end
    self.card_record = self:record(world.avatar, players, self.row)
end
return Inputs
