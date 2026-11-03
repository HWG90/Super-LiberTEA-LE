local Options = {}
Options.__index = Options
function Options.new(weapon)
    local judge, n = weapon.judge, weapon.n
    return setmetatable({
        weapon = weapon,
        judge = judge,
        n = n,
        value_call = assert(judge:routine("axis_value")),
        candidate_call = assert(judge:routine("axis_candidate")),
        out = assert(judge:buffer("uint64_t", 1)),
        slots = {
            { offset = n.weapon_data_r1_axis_1, slot = n.option_slot_1, limit = n.axis_rows_1 },
            { offset = n.weapon_data_r1_axis_2, slot = n.option_slot_2, limit = n.axis_rows_2 },
            { offset = n.weapon_data_r1_axis_3, slot = n.option_slot_3, limit = n.axis_rows_3 },
        },
    }, Options)
end
function Options:clear()
    self.manager, self.id, self.row, self.index = nil, nil, nil, nil
    for _, slot in ipairs(self.slots) do
        slot.key, slot.output = nil, nil
    end
end
function Options:observe(id)
    local weapon, n = self.weapon, self.n
    local manager = weapon:manager(n.weapon_data_manager)
    local index
    if manager ~= nil then
        index = weapon:find(manager + n.weapon_data_map, id, weapon.invalid_entity)
    end
    local rows
    if index ~= nil then
        rows = weapon.read:ptr(manager + n.weapon_data_r1_at)
    end
    if rows == nil then
        self:clear()
        self.manager = manager
        return
    end
    self.manager, self.id, self.row, self.index = manager, id, rows + index * n.weapon_data_r1_stride, index
end
function Options:mode()
    if self.row == nil then
        return nil
    end
    local read, n = self.weapon.read, self.n
    local rows = read:ptr(self.manager + n.weapon_data_at)
    local mode
    if rows ~= nil then
        mode = read:value(rows + self.index * n.weapon_data_stride + n.weapon_data_raw_mode, "u32")
    end
    return mode, read:value(self.row + n.weapon_data_fire_count, "u32")
end
function Options:search(slot, axis, value, same)
    for index = 0, slot.limit - 1 do
        self.out[0] = 0
        local candidate = self.judge:call(self.candidate_call, self.manager, self.id, axis, index, self.out)
        if candidate == nil then
            return nil, false
        end
        if candidate == self.n.candidate_none then
            break
        end
        if (candidate == value) == same then
            return self.judge:hex64(self.out[0]), true
        end
    end
    return nil, true
end
function Options:left_axis(axis, value, equipment)
    if value ~= nil and value > 0 then
        return axis
    end
    local record
    if equipment ~= nil then
        record = equipment.record
    else
        record = self.weapon:record(self.id)
    end
    if record ~= nil then
        local manager = self.weapon:manager(self.n.customization_manager)
        local row
        if manager ~= nil then
            row = self.weapon:find(manager + self.n.customization_map, self.id, self.weapon.invalid_entity)
        end
        local rows
        if row ~= nil then
            rows = self.weapon.read:ptr(manager + self.n.customization_rows)
        end
        local unit
        if rows ~= nil then
            unit = self.weapon.read:value(rows + row * self.n.customization_row_stride, "u32")
        end
        if unit ~= nil and unit ~= self.n.unit_none then
            return nil
        end
    end
    return axis
end
function Options:sample(index, equipment)
    local slot = self.slots[index]
    if self.row == nil then
        return nil
    end
    local axis = self.weapon.read:value(self.row + slot.offset, "u32")
    local value
    if axis ~= nil then
        value = self.judge:call(self.value_call, self.manager, self.id, slot.slot)
    end
    if axis == nil or value == nil then
        slot.key, slot.output = nil, nil
        if index == 1 then
            axis = self:left_axis(axis, value, equipment)
        end
        return axis, value, nil
    end
    local key = slot.key
    if key == nil or key.manager ~= self.manager or key.id ~= self.id or key.axis ~= axis or key.value ~= value then
        local other, other_ok = self:search(slot, axis, value, false)
        local output, output_ok
        if other ~= nil then
            output, output_ok = self:search(slot, axis, value, true)
        end
        slot.key = nil
        if other_ok and (other == nil or output_ok) then
            slot.key = { manager = self.manager, id = self.id, axis = axis, value = value }
        end
        slot.output = output
    end
    if index == 1 then
        axis = self:left_axis(axis, value, equipment)
    end
    return axis, value, slot.output
end
return Options
