local ratio = require("game.ratio")
local Throwable = {}
Throwable.__index = Throwable
function Throwable.new(weapon)
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = weapon.judge,
        n = weapon.n,
        fuse_call = assert(weapon.judge:routine("throwable_fuse_seconds")),
        capacity_call = assert(weapon.judge:routine("throwable_capacity")),
        explosive_call = assert(weapon.judge:routine("explosive_data_of")),
    }, Throwable)
end
function Throwable:wheel(id)
    self.id, self.mode, self.pick, self.seconds = nil, nil, nil, nil
    local weapon, read, n = self.weapon, self.read, self.n
    local manager = weapon:manager(n.throwable_manager)
    if manager == nil then
        return
    end
    local index = weapon:find(manager + n.throwable_map, id, weapon.invalid_entity)
    if index == nil then
        return
    end
    self.id = id
    local rows = read:ptr(manager + n.throwable_fuse_rows)
    if rows == nil then
        return
    end
    self.mode = read:value(rows + index * n.throwable_fuse_row_stride + n.throwable_fuse_mode, "u32")
    if self.mode ~= n.throwable_fuse_mode_pick then
        return
    end
    local states = read:ptr(manager + n.throwable_fuse_states)
    if states == nil then
        return
    end
    local state = states + index * n.throwable_fuse_state_stride
    self.pick = read:value(state + n.throwable_fuse_pick, "u32")
    if self.pick == nil then
        return
    end
    local seconds = read:value(state + n.throwable_fuse_copies + self.pick * n.throwable_fuse_copy_stride, "f32")
    if seconds ~= nil and seconds > 0 and seconds < math.huge then
        self.seconds = math.floor(seconds)
    end
end
function Throwable:choice(cell, holding)
    self.fuse_choice = nil
    if holding and cell ~= nil then
        self.fuse_choice = self.judge:call(self.fuse_call, 0, cell)
    end
    return self.fuse_choice
end
function Throwable:remaining(cell)
    if cell == nil then
        return nil
    end
    local weapon, read, n = self.weapon, self.read, self.n
    local manager, row = weapon:manager(n.explosive_manager)
    if manager ~= nil then
        local index = weapon:find(manager + n.explosive_map_at, cell, weapon.invalid_entity)
        if index ~= nil then
            local rows = read:ptr(manager + n.explosive_rows_at)
            if rows ~= nil then
                row = rows + index * n.explosive_row_stride
            end
        end
    end
    if row ~= nil and read:value(row + n.explosive_armed_at, "bool") == true then
        local mode = read:value(row + n.explosive_mode_at, "u32")
        if mode ~= nil and mode ~= n.explosive_external_mode then
            return read:value(row + n.explosive_remaining_at, "f32")
        end
    end
end
function Throwable:progress(avatar, cell, inventory, throwing, count, left)
    self.share = nil
    if not throwing then
        return
    end
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    if left ~= nil then
        local total = self.fuse_choice
        if total == nil or total <= 0 then
            total = nil
            local record = weapon:record(cell)
            local book
            if record ~= nil then
                book = judge:call(self.explosive_call, record)
            end
            if book ~= nil and book ~= 0 then
                local delay = read:value(book + n.explosive_blast_delay_at, "f32")
                local arm = read:value(book + n.explosive_arm_delay_at, "f32")
                if delay ~= nil and arm ~= nil then
                    total = delay + arm
                end
            end
        end
        self.share = ratio(left, total)
    end
    if self.share == nil and avatar ~= nil and inventory ~= nil then
        self.share = ratio(count, judge:call(self.capacity_call, inventory, avatar))
    end
end
return Throwable
