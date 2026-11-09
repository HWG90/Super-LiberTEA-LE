local Ability = require("game.ability_script")
local Inputs = {}
Inputs.__index = Inputs
local function item(rows, index)
    if rows[index] == nil then
        rows[index] = {}
    end
    return rows[index]
end
local function trim(rows, count)
    for i = #rows, count + 1, -1 do
        rows[i] = nil
    end
end
function Inputs.new(weapon)
    local read, n = weapon.read, weapon.n
    return setmetatable({
        weapon = weapon,
        frames = {},
        seen = {},
        callers = {},
        spots = {},
        got = {},
        point = {},
        script = {
            jump_table = n.action_script_jump_table,
            seek = n.action_script_seek_rva,
            length = n.reload_script_length,
        },
        targets = { [n.reinforce_call] = true, [n.reinforce_call_alt] = true, [n.reinforce_request] = true },
        ability_cells = read.layout({
            { n.ability_running, "u8" },
            { n.ability_id, "u32" },
            { n.ability_time, "f32" },
            { n.ability_speed, "f32" },
        }),
        encounter_cells = read.layout({
            { n.encounter_waves_done, "u32" },
            { n.encounter_next_wave, "f32" },
            { n.encounter_kind, "u32" },
            { n.encounter_active, "u8" },
            { n.encounter_next_point, "u32" },
        }),
        point_cells = read.layout({ { 0, "f32" }, { 4, "f32" }, { 8, "f32" } }),
    }, Inputs)
end
function Inputs:calling(count, rows, owners)
    local read, n, now, made = self.weapon.read, self.weapon.n, {}, 0
    if count ~= nil and rows ~= nil and owners ~= nil then
        for i = 0, count - 1 do
            local got = read:value(rows + i * n.ability_stride, self.ability_cells, self.got)
            local id, time, speed = got[2], got[3], got[4]
            if got[1] ~= 0 and id > 0 then
                local frame = self.frames[id]
                if frame == nil then
                    frame = Ability.calling_frame_in(read, self.script, id, self.targets)
                    self.frames[id] = frame
                end
                if frame and speed > 0 then
                    local owner = read:ptr(owners + i * n.ability_owner_stride)
                    local entity
                    if owner ~= nil and owner ~= 0 then
                        entity = read:value(owner + n.ability_owner_entity, "u32")
                    end
                    if entity ~= nil then
                        local row = self.seen[entity]
                        if row == nil or row.id ~= id or time < row.time then
                            row = { id = id, round = (row and row.round or 0) + 1 }
                        end
                        row.time, now[entity] = time, row
                        if time * 60 < frame then
                            made = made + 1
                            local out = item(self.callers, made)
                            out.key, out.target, out.again, out.seconds =
                                entity, entity, row.round, (frame / 60 - time) / speed
                        end
                    end
                end
            end
        end
    end
    self.seen = now
    trim(self.callers, made)
end
function Inputs:spawning(count, rows, points, owners)
    local read, n, made = self.weapon.read, self.weapon.n, 0
    if count ~= nil and rows ~= nil and points ~= nil and owners ~= nil then
        for i = 0, count - 1 do
            local got = read:value(rows + i * n.encounter_stride, self.encounter_cells, self.got)
            if got[3] == n.encounter_enemy_call_kind and got[4] ~= 0 and got[2] ~= nil then
                local at = points + i * n.encounter_points_stride
                local total, turn = read:value(at + n.encounter_point_count, "u32"), got[5]
                if turn ~= nil and turn < total then
                    local order = read:value(at + n.encounter_point_order + turn * n.encounter_point_order_width, "u32")
                    if order < total then
                        local point = read:value(
                            at + (n.encounter_point_base + order) * n.encounter_point_stride,
                            self.point_cells,
                            self.point
                        )
                        local owner = read:ptr(owners + i * n.encounter_owner_stride)
                        local entity
                        if owner ~= nil and owner ~= 0 then
                            entity = read:value(owner + n.encounter_owner_entity, "u32")
                        end
                        if entity ~= nil and point[1] ~= nil and point[2] ~= nil and point[3] ~= nil then
                            made = made + 1
                            local out = item(self.spots, made)
                            out.at = out.at or {}
                            out.at[1], out.at[2], out.at[3] = point[1], point[2], point[3]
                            out.key, out.again, out.seconds = entity, got[1], math.max(0, got[2])
                        end
                    end
                end
            end
        end
    end
    trim(self.spots, made)
end
function Inputs:labels()
    local w, n = self.weapon, self.weapon.n
    local director = w:manager(n.enemy_faction_director)
    local known, faction
    if director ~= nil then
        known = w.read:value(director + n.enemy_faction_set, "u32")
        faction = w.read:value(director + n.enemy_faction, "u32")
    end
    self.label, self.picture = n.enemy_wave_label, nil
    if known ~= nil and known > 0 then
        if faction == n.faction_bugs then
            self.label = n.bug_breach_label
        elseif faction == n.faction_squids then
            self.label = n.squid_ships_label
        elseif faction == n.faction_bots then
            self.label = n.bot_drop_label
        end
    end
    if faction ~= nil then
        if w.read.bytes.any_bit(faction, n.faction_bugs_bit) then
            self.picture = n.faction_bugs_picture
        elseif w.read.bytes.any_bit(faction, n.faction_bots_bit) then
            self.picture = n.faction_bots_picture
        else
            self.picture = n.faction_squids_picture
        end
    end
    local record = w.read:ptr(w.game + n.stratagem_records + n.reinforce_stratagem * n.stratagem_record_stride)
    self.call_label = nil
    if record ~= nil then
        self.call_label = w.read:value(record + n.stratagem_record_name, "u32")
    end
end
function Inputs:observe(callers_due, spots_due)
    local w, n = self.weapon, self.weapon.n
    if callers_due then
        local director = w:manager(n.encounter_director)
        local cooldown
        if director ~= nil then
            cooldown = w.read:value(director + n.encounter_call_cooldown, "f32")
        end
        local count, rows, owners
        if cooldown ~= nil and cooldown <= 0 then
            local manager = w:manager(n.ability_manager)
            if manager ~= nil then
                count = w.read:value(manager + n.ability_count, "u32")
                rows, owners = w.read:ptr(manager + n.ability_rows), w.read:ptr(manager + n.ability_owners)
            end
        end
        self:calling(count, rows, owners)
    end
    if spots_due then
        local manager = w:manager(n.encounter_manager)
        local count, rows, points, owners
        if manager ~= nil then
            count = w.read:value(manager + n.encounter_count, "u32")
        end
        if count ~= nil and count > 0 then
            rows, points, owners =
                w.read:ptr(manager + n.encounter_rows),
                w.read:ptr(manager + n.encounter_points),
                w.read:ptr(manager + n.encounter_owners)
        end
        self:spawning(count, rows, points, owners)
    end
end
function Inputs:clear()
    self.seen = {}
    trim(self.callers, 0)
    trim(self.spots, 0)
end
return Inputs
