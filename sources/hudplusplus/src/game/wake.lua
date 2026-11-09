local Wake = {}
Wake.__index = Wake
local CHANGE_FLOOR = 1
function Wake.new(slots)
    return setmetatable({ slots = slots, last = {} }, Wake)
end
function Wake:clear()
    self.clock, self.until_at = nil, nil
    local last = self.last
    for index = 1, self.slots do
        last[index] = nil
    end
end
function Wake:step(clock, values, held, hold)
    if clock == nil then
        self:clear()
        return nil
    end
    if self.clock ~= nil and clock < self.clock then
        self:clear()
    end
    local last, until_at, changed = self.last, self.until_at or clock, false
    for index = 1, self.slots do
        local now, before = values[index], last[index]
        last[index] = now
        if now ~= nil and before ~= nil and now ~= before then
            changed = true
        end
    end
    if changed then
        until_at = math.max(until_at, clock + math.max(hold, CHANGE_FLOOR))
    end
    if held then
        until_at = math.max(until_at, clock + hold)
    end
    self.clock, self.until_at = clock, until_at
    return held == true or clock < until_at
end
return Wake
