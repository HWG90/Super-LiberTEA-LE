local Ability = require("game.ability_script")
local ratio = require("game.ratio")
local Reload = {}
Reload.__index = Reload
local function get(read, at, offset, form)
    if at ~= nil and at ~= 0 then
        return read:value(at + offset, form)
    end
end
function Reload.new(weapon)
    local n, judge = weapon.n, weapon.judge
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = judge,
        n = n,
        state = {},
        values = {},
        active_call = assert(judge:routine("reloading")),
        open_call = assert(judge:routine("reload_open")),
        rounds_call = assert(judge:routine("rounds_open")),
        frame_call = assert(judge:routine("ability_frame")),
        assist_call = assert(judge:routine("assisted_reload_find")),
        entry = {
            jump_table = n.action_script_jump_table,
            seek = n.action_script_seek_rva,
            length = n.reload_script_length,
            insert = n.action_script_insert_rva,
            chamber = n.action_script_chamber_rva,
            mag_full = n.action_script_mag_full_rva,
            all_full = n.action_script_all_full_rva,
            can_reload = n.action_script_can_reload_rva,
            reloadable = n.action_script_reloadable_rva,
            room = n.action_script_room_rva,
            empty = n.action_script_empty_rva,
            count = n.action_script_count_rva,
            cock = n.action_script_cock_rva,
            switch_kind = n.action_script_switch_kind_rva,
            stage_bit = n.action_script_stage_bit_rva,
            set_stage_bit = n.action_script_set_stage_bit_rva,
        },
    }, Reload)
end
function Reload:clear()
    self.state.span, self.share = nil, nil
end
function Reload:row(manager, map, id, rows_at, stride)
    if manager == nil then
        return nil
    end
    local index = self.weapon:find(manager + map, id, self.weapon.invalid_entity)
    if index == nil then
        return nil
    end
    local rows = self.read:ptr(manager + rows_at)
    if rows ~= nil then
        return rows + index * stride, index
    end
    return nil, index
end
function Reload:select(id)
    if id == nil then
        return
    end
    local manager = self.weapon:manager(self.n.reload_manager)
    if manager ~= nil then
        return self.judge:call(self.active_call, manager, id)
    end
end
function Reload:observe(avatar, id, record, worn, active)
    local weapon, read, judge, n, v = self.weapon, self.read, self.judge, self.n, self.values
    self.share = nil
    if active ~= true or avatar == nil or id == nil or record == nil then
        self:clear()
        return
    end
    local book = judge:call(self.open_call, record)
    v.entity, v.frame = id, judge:call(self.frame_call, 0, avatar)
    v.ability = get(read, book, n.weapon_reload_instance_reload_ability, "u32")
    if v.ability == nil or v.frame == nil then
        self.state.span = nil
        return
    end
    local magazine = weapon:manager(n.weapon_magazine_manager)
    local chamber_row =
        self:row(magazine, n.weapon_magazine_map, id, n.weapon_magazine_r1_at, n.weapon_magazine_r1_stride)
    local primary = get(read, chamber_row, n.weapon_magazine_chamber_round, "u32")
    local rounds, round_row, index
    v.chamber = primary
    if primary == nil then
        rounds = weapon:manager(n.weapon_rounds_manager)
        round_row, index = self:row(rounds, n.weapon_rounds_map, id, n.weapon_rounds_at, n.weapon_rounds_stride)
        if index ~= nil then
            local rows = read:ptr(rounds + n.weapon_rounds_r1_at)
            if rows ~= nil then
                v.chamber = read:value(rows + index * n.weapon_rounds_r1_stride + n.weapon_rounds_chamber_round, "u32")
            end
        end
    end
    local result = Ability.timeline(read, self.state, v, self.entry, function()
        v.from_pack = get(read, book, n.weapon_reload_instance_reload_from_pack, "u8")
        local manager = weapon:manager(n.reload_manager)
        local reload_row =
            self:row(manager, n.weapon_reload_map, id, n.weapon_reload_rows_at, n.weapon_reload_rows_stride)
        v.stage = get(read, reload_row, n.weapon_reload_reload_stage, "u32")
        if primary ~= nil then
            rounds = weapon:manager(n.weapon_rounds_manager)
            round_row, index = self:row(rounds, n.weapon_rounds_map, id, n.weapon_rounds_at, n.weapon_rounds_stride)
        end
        v.r0, v.r1 =
            get(read, round_row, n.weapon_rounds_rounds_0, "u32"), get(read, round_row, n.weapon_rounds_rounds_1, "u32")
        v.sel, v.reserve =
            get(read, round_row, n.weapon_rounds_raw_selected, "u32"),
            get(read, round_row, n.weapon_rounds_reserve, "u32")
        local round_book = judge:call(self.rounds_call, record)
        v.cap0, v.cap1 =
            get(read, round_book, n.weapon_rounds_instance_capacity_0, "f32"),
            get(read, round_book, n.weapon_rounds_instance_capacity_1, "f32")
        v.thr0, v.thr1 =
            get(read, round_book, n.weapon_rounds_instance_threshold_0, "f32"),
            get(read, round_book, n.weapon_rounds_instance_threshold_1, "f32")
        v.kind0, v.kind1 =
            get(read, round_book, n.weapon_rounds_instance_kind_0, "u32"),
            get(read, round_book, n.weapon_rounds_instance_kind_1, "u32")
        v.chambered, v.amount =
            get(read, round_book, n.weapon_rounds_instance_chambered, "u8"),
            get(read, round_book, n.weapon_rounds_instance_reload_amount, "u32")
        local key, assist = weapon:key(record)
        if key ~= nil then
            if key == false then
                key = "0000000000000000"
            end
            assist = judge:call(self.assist_call, judge:uint64_of(key))
        end
        v.need, v.worn = get(read, assist, n.weapon_assisted_reload_assist_need, "u32"), worn
        return Ability.rounds_state(v)
    end)
    if result ~= nil then
        self.share = ratio(result.elapsed, result.length)
    end
end
return Reload
