local Inputs, Marks = require("game.reinforcement"), require("game.comms_marks")
local Feature = {}
Feature.__index = Feature
function Feature.new(comms, weapon, report)
    return setmetatable({
        weapon = weapon,
        inputs = Inputs.new(weapon),
        callers = Marks.new(comms, weapon.n.enemy_ping_sound, report),
        spots = Marks.new(comms, nil, report),
        time = 0,
    }, Feature)
end
function Feature:step(enabled, panel, players)
    if not enabled or panel.in_mission == false then
        self:close(panel.in_mission == false)
        return
    end
    if panel.in_mission ~= true then
        return
    end
    local dt = panel.dt
    self.time = self.time + (dt or 0)
    local callers_due = dt == nil or self.call_at == nil or self.time >= self.call_at
    local spots_due = dt == nil or self.spot_at == nil or self.time >= self.spot_at
    if not callers_due and not spots_due then
        return
    end
    local w, n, input = self.weapon, self.weapon.n, self.inputs
    input:observe(callers_due, spots_due)
    local ring, sender, terrain
    if (callers_due and #input.callers > 0) or (spots_due and #input.spots > 0) then
        input:labels()
        ring, terrain = w:manager(n.comms_global), w:manager(n.ground_world)
        sender = w:local_key(players)
    end
    if callers_due then
        self.callers:update(input.callers, ring, sender, input.call_label, input.picture, terrain)
        self.call_at = self.time + 1 / 4
    end
    if spots_due then
        self.spots:update(input.spots, ring, sender, input.label, input.picture, terrain)
        self.spot_at = self.time + 1 / 30
    end
end
function Feature:close(left)
    self.callers:update(nil, nil, nil, nil, nil, nil, left)
    self.spots:update(nil, nil, nil, nil, nil, nil, left)
    self.inputs:clear()
    self.time, self.call_at, self.spot_at = 0, nil, nil
end
return Feature
