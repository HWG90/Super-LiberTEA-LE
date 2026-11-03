local Marks = {}
Marks.__index = Marks
local ORIGIN = { 0, 0, 0 }
function Marks.new(comms, sound, report)
    return setmetatable({ comms = comms, sound = sound, report = report, rows = {}, stamp = 0 }, Marks)
end
function Marks:say(word)
    if word ~= nil then
        self.report({ event = "write", id = "pings", action = word })
    end
end
function Marks:put(key, held, item, ring, sender, label, picture)
    local comms, n = self.comms, self.comms.n
    if ring == nil or type(sender) ~= "string" or type(item.seconds) ~= "number" then
        return
    end
    if held ~= nil and held.placed == nil and held.refused == item.again then
        return
    end
    local placed, word = comms:place(ring, sender, n.quiet_mark_kind, item.at or ORIGIN, item.target, self.sound)
    if placed == nil and word ~= "refused" then
        self:say(word)
        return
    end
    if held == nil then
        held = {}
        self.rows[key] = held
    end
    held.placed, held.again = placed, item.again
    held.refused = placed == nil and item.again or nil
    if placed == nil then
        self:say(word)
        return
    end
    if item.at ~= nil then
        held.at = { item.at[1], item.at[2], item.at[3] }
    end
    if type(label) ~= "number" or label == 0 then
        label = nil
    end
    if type(picture) ~= "string" then
        picture = nil
    end
    word = comms:set(placed, { label = label, picture = picture, tint = n.comms_label_red, seconds = item.seconds })
    self:say((word == "written" or word == "already") and "placed" or word)
end
function Marks:keep(held, item, terrain)
    local at, was = item.at, held.at
    local moved = at ~= nil
        and was ~= nil
        and terrain ~= nil
        and terrain > 0
        and (at[1] ~= was[1] or at[2] ~= was[2] or at[3] ~= was[3])
    local timed = held.again ~= item.again
    if not moved and not timed then
        return false
    end
    local word = self.comms:set(
        held.placed,
        { point = moved and at or nil, terrain = terrain, seconds = timed and item.seconds or nil, revive = true }
    )
    if word == "gone" or word == "ended" then
        return true
    end
    if word ~= "written" and word ~= "already" then
        return false
    end
    if moved then
        was[1], was[2], was[3] = at[1], at[2], at[3]
        self:say("moved")
    end
    if timed then
        held.again = item.again
        self:say("timed")
    end
    return false
end
function Marks:update(items, ring, sender, label, picture, terrain, left)
    self.stamp = self.stamp + 1
    for _, item in ipairs(items or {}) do
        local held = self.rows[item.key]
        local lost = held == nil or held.placed == nil
        if not lost then
            lost = self:keep(held, item, terrain)
            if lost then
                held.placed = nil
            end
        end
        if lost then
            self:put(item.key, held, item, ring, sender, label, picture)
        end
        held = self.rows[item.key]
        if held ~= nil then
            held.stamp = self.stamp
            if
                held.placed ~= nil
                and held.tinted ~= held.placed
                and self.comms:brackets(held.placed, self.comms.n.comms_label_red) == "tinted"
            then
                held.tinted = held.placed
            end
        end
    end
    for key, held in pairs(self.rows) do
        if held.stamp ~= self.stamp then
            if held.placed ~= nil then
                self:say(self.comms:take(held.placed, left and "left" or "taken"))
            end
            self.rows[key] = nil
        end
    end
end
return Marks
