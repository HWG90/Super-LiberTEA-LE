local Inputs = {}
Inputs.__index = Inputs
function Inputs.new(weapon)
    local judge = weapon.judge
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        n = weapon.n,
        judge = judge,
        dead_call = assert(judge:routine("dead_of")),
        dropping_call = assert(judge:routine("dropping_of")),
        open = assert(judge:routine("weapon_data_open")),
        node = assert(judge:routine("unit_node")),
    }, Inputs)
end
function Inputs:bit(at, index)
    if at == nil then
        return nil
    end
    local value = self.read:value(at, "bit", index)
    if value ~= nil then
        return value ~= 0
    end
end
function Inputs:scene(needed)
    self.world = nil
    if not needed then
        return
    end
    local weapon, read, n = self.weapon, self.read, self.n
    local scene = weapon:manager(n.hud_scene_manager)
    if scene ~= nil then
        self.world = read:ptr(scene + n.game_world_at)
    end
end
function Inputs:view(needed)
    self.camera, self.eye = nil, nil
    if not needed then
        return
    end
    local read, n = self.read, self.n
    local camera = self.weapon:manager(n.camera_manager)
    if camera ~= nil then
        self.eye, self.camera = read:vector(camera + n.camera_eye_at, 3), read:ptr(camera)
    end
end
function Inputs:death(avatar)
    local health = self.weapon:manager(self.n.health_manager)
    if health ~= nil then
        self.dead = self.judge:call(self.dead_call, health, avatar)
    end
end
function Inputs:observe(panel, avatar, world, shared, landing)
    local weapon, read, n = self.weapon, self.read, self.n
    self.ready, self.first_person, self.third_person, self.aiming, self.switching, self.holding =
        nil, nil, nil, nil, nil, nil
    self.throwing, self.melee, self.engaged = nil, nil, nil
    self.avatar, self.manager, self.index, self.actions = avatar, nil, nil, nil
    self.dead, self.landed = nil, nil
    if avatar == nil then
        return nil
    end
    if shared then
        self:death(avatar)
    end
    local manager, index
    if world or (landing and self.dead == false) then
        manager = weapon:manager(n.roots_avatar_manager_rva)
        if manager ~= nil then
            index = weapon:find(manager + n.roots_avatar_manager_map, avatar, weapon.invalid_player)
        end
    end
    self.manager, self.index = manager, index
    local active = false
    if world and index ~= nil then
        local controller = manager
            + n.roots_avatar_manager_controller_base
            + index * n.roots_avatar_manager_controller_stride
        active = read:value(controller + n.avatar_controller_dive_identity_offset, "u32") == avatar
        if active then
            local actions = controller + n.avatar_action_words
            self.actions = actions
            self.first_person = self:bit(actions, n.first_person_action_bit)
            if self.first_person ~= nil then
                self.third_person = not self.first_person
            end
            self.aiming = self:bit(actions, n.aim_action_bit)
            self.switching = self:bit(actions + n.switch_action_word, n.switch_action_bit)
            self.holding = self:bit(
                manager + index * n.roots_avatar_manager_controller_stride + n.throw_holding_word,
                n.throw_holding_bit
            )
            if not shared then
                self:death(avatar)
            end
        end
    end
    if self.dead == false and index ~= nil and (active or landing) then
        local dropping = self.judge:call(self.dropping_call, manager, index)
        if dropping ~= nil then
            self.landed = not dropping
        end
    end
    if active and self.dead == false and self.landed == true and panel.opacity ~= nil and panel.opacity > 0 then
        self.ready = true
    end
    return self.ready
end
function Inputs:sample(need_action, need_throw)
    local actions, n = self.actions, self.n
    if actions == nil then
        return
    end
    if (need_action or need_throw) and self.holding then
        self.throwing = self:bit(actions, n.throw_action_bit)
    end
    if need_action then
        self.melee = self:bit(actions + n.melee_action_word, n.melee_action_bit)
        local attacking = self:bit(actions + n.fire_action_word, n.fire_action_bit)
        self.engaged = self.aiming == true
            or self.first_person == true
            or attacking == true
            or self.throwing == true
            or self.melee == true
    end
end
function Inputs:place(panel, seated, seat_row, wield, wield_record, reloading)
    local weapon, read, n = self.weapon, self.read, self.n
    self.clear, self.pinned, self.body, self.anchor, self.anchor_node, self.fire_found = nil, nil, nil, nil, nil, nil
    if self.ready ~= true then
        return
    end
    if self.first_person == true or seated == true then
        self.pinned = true
    elseif self.third_person == true then
        self.pinned = false
    end
    local driving
    if seated and seat_row ~= nil then
        driving = read:value(seat_row + n.seat_role_at, "u32") == n.seat_role_driver
    end
    local bright = read:value(panel.base + n.self_panel_bright, "u8")
    local wheel = read:value(panel.mission - n.hud_widgets_mission_hud + n.hud_weapon_wheel_closed, "u8")
    local terminal = read:value(self.manager + n.avatar_terminal_at + self.index * n.avatar_terminal_stride, "u32")
    if bright == 0 or driving == true or wheel == 0 or (terminal ~= nil and terminal ~= n.avatar_terminal_none) then
        return
    end
    self.clear = true
    if self.third_person ~= true then
        return
    end
    local record = weapon:record(self.avatar)
    if record ~= nil then
        self.body = read:value(record + n.record_engine_unit, "u32")
    end
    if self.aiming == true and reloading ~= true and self.switching ~= true then
        local data = weapon:manager(n.weapon_data_manager)
        local index
        if data ~= nil then
            index = weapon:find(data + n.weapon_data_map, wield, weapon.invalid_entity)
        end
        local rows
        if index ~= nil then
            rows = read:ptr(data + n.weapon_data_r1_at)
        end
        if rows ~= nil then
            local row = rows + index * n.weapon_data_r1_stride
            local count = read:value(row + n.weapon_data_fire_count, "u32")
            local entry, unit = wield_record, nil
            if entry ~= nil then
                unit = read:value(entry + n.record_engine_unit, "u32")
            end
            local records = read:ptr(data + n.weapon_data_records)
            local option_record, blob, left, right
            if records ~= nil then
                option_record = read:ptr(records + index * n.weapon_data_record_stride)
            end
            if option_record ~= nil then
                blob = self.judge:call(self.open, option_record)
            end
            if blob ~= nil and blob ~= 0 then
                left = read:value(blob + n.weapon_function_left, "u32")
                right = read:value(blob + n.weapon_function_right, "u32")
            end
            if
                unit ~= nil
                and unit > 0
                and left ~= n.weapon_function_detonator
                and right ~= n.weapon_function_detonator
            then
                if count ~= nil then
                    self.fire_found = count > 0
                end
                if self.fire_found then
                    self.anchor, self.anchor_node = unit, read:value(row + n.weapon_data_fire_node, "i32")
                    return
                end
            end
        end
    end
    if self.body ~= nil and self.body > 0 then
        local node = self.judge:call(self.node, self.body, n.avatar_head_node)
        if node ~= nil and node > 0 then
            self.anchor, self.anchor_node = self.body, node
        end
    end
end
return Inputs
