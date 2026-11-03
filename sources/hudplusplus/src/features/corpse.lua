local Feature = {}
Feature.__index = Feature
local function say(report, result)
    if result ~= nil then
        report({ event = "write", id = "mark", action = result })
    end
end
function Feature.new(comms, weapon, report)
    local self = setmetatable({ comms = comms, weapon = weapon, rows = {}, report = report }, Feature)
    for _, name in ipairs({ "unit_node", "unit_world_position" }) do
        self[name] = assert(weapon.judge:routine(name))
    end
    return self
end
function Feature:point(avatar)
    local w, n = self.weapon, self.weapon.n
    local record = w:record(avatar)
    local unit
    if record ~= nil then
        unit = w.read:value(record + n.record_engine_unit, "u32")
    end
    if unit == nil or unit <= 0 then
        return nil
    end
    local node = w.judge:call(self.unit_node, unit, n.avatar_head_node)
    if node == nil or node <= 0 then
        return nil
    end
    local at = w.judge:call(self.unit_world_position, unit, node)
    if at ~= nil and at ~= 0 then
        return w.read:vector(at, 3)
    end
end
function Feature:pending()
    for _, row in ipairs(self.rows) do
        if row.deadline == nil then
            return true
        end
    end
    return false
end
function Feature:step(enabled, in_mission, avatar, players, dead, landed)
    local w, n, comms = self.weapon, self.weapon.n, self.comms
    if not enabled or not in_mission or avatar == nil then
        dead, landed = nil, nil
    end
    if dead ~= false then
        landed = nil
    end
    self:advance(enabled, in_mission, dead, landed)
    if enabled and dead == true and not self.spent then
        local ring = w:manager(n.comms_global)
        local sender
        if players ~= nil then
            sender = w:local_key(players)
        end
        local point = self:point(avatar)
        if ring ~= nil and type(sender) == "string" and point ~= nil then
            local placed, word = comms:place(ring, sender, n.quiet_mark_kind, point)
            if word == "refused" then
                if not self.refused then
                    self.refused = true
                    say(self.report, word)
                end
            elseif placed ~= nil or word ~= nil then
                self.spent = true
                if placed ~= nil then
                    word = comms:set(placed, { label = n.dead_label, picture = n.seat_skull_picture })
                    if word == "written" or word == "already" then
                        self.rows[#self.rows + 1] = placed
                        word = "placed"
                    end
                end
                say(self.report, word)
            end
        end
    end
end
function Feature:advance(enabled, in_mission, dead, landed)
    if dead ~= true then
        self.spent, self.refused = nil, nil
    end
    local kept, comms = 0, self.comms
    for _, row in ipairs(self.rows) do
        local word, keep = nil, true
        if not enabled or in_mission == false then
            word, keep = comms:take(row, in_mission == false and "left" or "taken"), false
        elseif row.deadline == nil and landed == true then
            local deadline
            word, deadline = comms:set(row, { seconds = 15 })
            if deadline == nil then
                row.deadline = false
            else
                row.deadline, word = deadline, "timed"
            end
            keep = word ~= "gone"
        elseif type(row.deadline) == "number" and dead ~= true then
            if comms:float(row, "elapsed") >= row.deadline then
                keep = false
            elseif comms:float(row, "distance") <= 5 then
                word, keep = comms:take(row, "reached"), false
            end
        end
        say(self.report, word)
        if keep then
            kept = kept + 1
            self.rows[kept] = row
        end
    end
    for i = #self.rows, kept + 1, -1 do
        self.rows[i] = nil
    end
end
function Feature:close()
    self:advance(false, false)
end
return Feature
