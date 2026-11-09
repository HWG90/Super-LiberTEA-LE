local Ability = require("game.ability_script")
local ratio = require("game.ratio")
local Cycle = {}
Cycle.__index = Cycle
function Cycle.new(weapon)
    local n = weapon.n
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = weapon.judge,
        n = n,
        unlocked = {},
        one = weapon.read:value(weapon.game + n.fire_speed_unit, "f32"),
        frame_call = assert(weapon.judge:routine("ability_frame")),
        targets = { [n.melee_unlock_rva] = true },
        entry = {
            jump_table = n.action_script_jump_table,
            seek = n.action_script_seek_rva,
            length = n.reload_script_length,
        },
    }, Cycle)
end
function Cycle:shot(id, hidden, count, charge_index)
    self.left = nil
    if hidden ~= true or count == nil or count <= 0 or charge_index ~= nil then
        return
    end
    local weapon, read, n = self.weapon, self.read, self.n
    local manager = weapon:manager(n.arc_weapon_manager)
    if manager == nil then
        return
    end
    local index = weapon:find(manager + n.arc_weapon_map, id, weapon.invalid_entity)
    if index == nil then
        return
    end
    local rows = read:ptr(manager + n.arc_weapon_rows_at)
    if rows == nil then
        return
    end
    local row = rows + index * n.arc_weapon_rows_stride
    self.left = ratio(read:value(row + n.arc_weapon_wait, "f32"), read:value(row + n.arc_weapon_interval, "f32"))
end
function Cycle:melee(avatar, avatar_row, acting, hidden, count)
    self.progress = nil
    if hidden ~= true or count ~= 0 then
        return
    end
    self.progress = self.one
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    if acting ~= true or avatar_row == nil or read:value(avatar_row + n.avatar_melee_lock_at, "bool") ~= true then
        return
    end
    local manager = weapon:manager(n.ability_manager)
    if manager == nil then
        return
    end
    local index = weapon:find(manager + n.ability_map, avatar, weapon.invalid_player)
    if index == nil then
        return
    end
    local rows = read:ptr(manager + n.ability_rows)
    if rows == nil then
        return
    end
    local id = read:value(rows + index * n.ability_stride + n.ability_id, "u32")
    if id == nil then
        return
    end
    local unlock = self.unlocked[id]
    if unlock == nil then
        unlock = Ability.calling_frame_in(read, self.entry, id, self.targets)
        self.unlocked[id] = unlock
    end
    if type(unlock) ~= "number" then
        return
    end
    local value = ratio(judge:call(self.frame_call, 0, avatar), unlock)
    if value ~= nil then
        self.progress = value
    end
end
return Cycle
