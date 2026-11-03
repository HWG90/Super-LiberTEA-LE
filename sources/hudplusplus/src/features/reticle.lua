local Reticle = {}
Reticle.__index = Reticle
local function unique(rows, field, value, second, other)
    local found
    for _, row in ipairs(rows) do
        if row[field] == value and (second == nil or row[second] == other) then
            if found ~= nil then
                return nil
            end
            found = row
        end
    end
    return found
end
function Reticle.new(access, n)
    return setmetatable(
        { read = access.read, judge = access.call.judge, write = access.write, n = n, third = {}, first = {} },
        Reticle
    )
end
function Reticle:tables()
    local read, n = self.read, self.n
    local game = read:module("game")
    if game == nil then
        return
    end
    local owner = read:ptr(game + n.roots_entity_owner_rva)
    if owner == nil then
        return
    end
    local book = read:ptr(owner + n.weapon_data_registry_table)
    if book == nil then
        return
    end
    local rows = {}
    for i = 0, n.crosshair_count - 1 do
        local at = game + n.crosshair_table + i * n.crosshair_stride
        rows[#rows + 1] = {
            key = read:value(at + n.crosshair_key),
            mode = read:value(at + n.crosshair_mode),
            flags = read:value(at + n.crosshair_flags),
        }
    end
    if #rows == 0 then
        return
    end
    return owner, book, rows
end
function Reticle:third_target(book, rules)
    local read, n = self.read, self.n
    local hidden = unique(rules, "mode", n.crosshair_hidden_mode)
    if hidden == nil then
        return nil, "rule-not-one"
    end
    local found
    for i = 0, n.weapon_data_registry_last do
        local slot = book + i * n.registry_slot_stride
        if read:value(slot, "hex64") ~= nil then
            local row = book
                + n.weapon_data_registry_head
                + read:value(slot + n.registry_slot_row) * n.weapon_data_registry_size
            local at = row + n.crosshair_type
            local current = read:value(at)
            if current == hidden.key then
                if found ~= nil then
                    return nil, "target-not-one"
                end
                found = { at = at, row = row, from = current, to = rules[1].key }
            end
        end
    end
    if found == nil then
        return nil, "target-not-one"
    end
    return { found }
end
function Reticle:first_targets(owner, rules)
    local read, n, judge = self.read, self.n, self.judge
    local links = read:ptr(owner + n.linked_ammo_registry_table)
    if links == nil then
        return nil, "wait"
    end
    local call = judge:routine("weapon_data_find")
    if call == nil then
        return nil, "spec"
    end
    local targets = {}
    for i = 0, n.linked_ammo_registry_slots - 1 do
        local key = read:value(links + i * n.linked_ammo_registry_slot_stride, "hex64")
        if key ~= nil then
            local row = judge:call(call, judge:uint64_of(key))
            if row == nil then
                return nil, "wait"
            end
            if row ~= 0 then
                local at = row + n.crosshair_type
                local from = read:value(at)
                local current, to = unique(rules, "key", from), nil
                if current ~= nil then
                    local flag, flags = n.crosshair_first_person_flag, current.flags
                    if math.floor(flags / flag) % 2 == 0 then
                        flags = flags + flag
                    end
                    local selected = unique(rules, "mode", current.mode, "flags", flags)
                    if selected ~= nil then
                        to = selected.key
                    end
                end
                targets[#targets + 1] = { at = at, row = row, key = key, from = from, to = to }
            end
        end
    end
    if #targets == 0 then
        return nil, "target-none"
    end
    return targets
end
function Reticle:apply(state, targets, why, id, say)
    if targets == nil and why == "wait" then
        return
    end
    state.settled, state.applied = true, {}
    if targets == nil then
        say({ event = "write", id = id, action = why })
        return
    end
    local read, n, pack = self.read, self.n, self.read.bytes.pack
    for _, target in ipairs(targets) do
        local result
        for i = 0, n.sight_count - 1 do
            local at = target.row + n.sight_at + i * n.sight_stride
            if read:value(at) ~= 0 or read:value(at + n.sight_value) ~= 0 then
                result = "overridden"
                break
            end
        end
        if result == nil and target.to == nil then
            result = "rule-not-one"
        end
        if result == nil then
            local _, word = self.write:swap(target.at, pack(target.from, 4), pack(target.to, 4))
            result = word
            if word == "written" then
                state.applied[#state.applied + 1] = target
            end
        end
        say({ event = "write", id = id, action = result, value = target.key })
    end
end
function Reticle:restore(state, id, say)
    if not state.settled then
        return
    end
    local pack = self.read.bytes.pack
    for _, target in ipairs(state.applied or {}) do
        local _, word = self.write:swap(target.at, pack(target.to, 4), pack(target.from, 4))
        say({ event = "write", id = id, action = word == "written" and "restored" or word, value = target.key })
    end
    state.settled, state.applied = nil, nil
end
function Reticle:step(editing, say)
    if not editing then
        self:restore(self.third, "third_person", say)
        self:restore(self.first, "first_person", say)
        return
    end
    if self.third.settled and self.first.settled then
        return
    end
    local owner, book, rules = self:tables()
    if owner == nil then
        return
    end
    if not self.third.settled then
        local targets, why = self:third_target(book, rules)
        self:apply(self.third, targets, why, "third_person", say)
    end
    if not self.first.settled then
        local targets, why = self:first_targets(owner, rules)
        self:apply(self.first, targets, why, "first_person", say)
    end
end
return Reticle
