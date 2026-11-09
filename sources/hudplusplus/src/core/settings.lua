local Settings = {}
Settings.__index = Settings
local function copy(values)
    local result = {}
    for name, value in pairs(values) do
        result[name] = value
    end
    return result
end
local function valid(entry, value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
        return false
    end
    if entry.choices ~= nil then
        return value % 1 == 0 and value >= 0 and value < #entry.choices
    end
    return entry.range ~= nil and value >= entry.range[1] and value <= entry.range[2]
end
local function decimal(value)
    local plain = not string.format("%.17g", value):find("e", 1, true)
    for digits = 1, 17 do
        local text = string.format("%." .. digits .. "g", value):gsub(",", ".")
        if tonumber(text) == value and not (plain and text:find("e", 1, true)) then
            return text
        end
    end
end
function Settings.new(entries)
    local by_name, defaults, owners = {}, {}, {}
    for _, entry in ipairs(entries) do
        assert(by_name[entry.id] == nil, "duplicate-option")
        assert(valid(entry, entry.default), "invalid-default")
        by_name[entry.id], defaults[entry.id] = entry, entry.default
        owners[entry.id:match("^[^.]+")] = true
    end
    return setmetatable({
        entries = entries,
        by_name = by_name,
        defaults = defaults,
        values = copy(defaults),
        unknown = {},
        owners = owners,
    }, Settings)
end
function Settings.held(entry)
    return entry.title ~= nil
end
function Settings:parse(text)
    local values, unknown = copy(self.defaults), {}
    text = text:gsub("^\239\187\191", "")
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("//.*$", ""):gsub("#.*$", "")
        local name, raw = line:match("^%s*([%w_.%-]+)%s*=%s*(.-)%s*$")
        if name ~= nil then
            local entry, value = self.by_name[name], tonumber(raw)
            if entry == nil then
                if not self.owners[name:match("^[^.]+")] then
                    unknown[name] = raw
                end
            elseif Settings.held(entry) then
                if valid(entry, value) then
                    values[name] = value
                else
                    values[name] = self.defaults[name]
                end
            end
        end
    end
    return values, unknown
end
function Settings:load(text)
    self.values, self.unknown = self:parse(text)
    self.text = text
end
function Settings:bind(read, save, clock)
    self.read, self.save, self.clock = read, save, clock
end
function Settings:poll()
    if self.read == nil then
        return false
    end
    local now = self.clock()
    if self.polled ~= nil and now >= self.polled and now - self.polled < 1 then
        return false
    end
    self.polled = now
    local text, why = self.read()
    if text == nil then
        return false, why
    end
    if text == self.text then
        return false
    end
    self:load(text)
    return true
end
function Settings:begin()
    self.editing, self.begun, self.base = copy(self.values), copy(self.values), self.text
end
function Settings:dirty()
    for name, value in pairs(self.editing or {}) do
        if self.values[name] ~= value then
            return true
        end
    end
    return false
end
function Settings:edit(name, value)
    local entry = self.by_name[name]
    if entry == nil or not valid(entry, value) then
        return nil, "value"
    end
    if self.editing == nil then
        self:begin()
    end
    self.editing[name] = value
    return true
end
function Settings:cancel()
    self.editing, self.begun, self.base = nil, nil, nil
end
function Settings:commit(accept)
    if self.editing == nil then
        return false
    end
    local pending, unknown = copy(self.editing), self.unknown
    if self.read ~= nil then
        local current, why = self.read()
        if current == nil and why ~= nil and why ~= "unavailable" then
            return nil, why
        end
        if current ~= nil and current ~= self.base then
            pending, unknown = self:parse(current)
            for name, value in pairs(self.editing) do
                if value ~= self.begun[name] then
                    pending[name] = value
                end
            end
        end
    end
    if accept ~= nil then
        local okay, why = accept(pending)
        if not okay then
            return nil, why or "accept"
        end
    end
    local text = self:serialize(pending, unknown)
    if self.save ~= nil then
        local okay, why = self.save(text)
        if not okay then
            if accept ~= nil then
                accept(self.values)
            end
            return nil, why or "save"
        end
    end
    self.values, self.unknown, self.text = pending, unknown, text
    self:begin()
    return true
end
function Settings:serialize(values, preserved)
    values, preserved = values or self.values, preserved or self.unknown
    local lines = {}
    for _, entry in ipairs(self.entries) do
        if Settings.held(entry) then
            lines[#lines + 1] = entry.id .. "=" .. decimal(values[entry.id])
        end
    end
    local unknown = {}
    for name in pairs(preserved) do
        unknown[#unknown + 1] = name
    end
    table.sort(unknown)
    for _, name in ipairs(unknown) do
        lines[#lines + 1] = name .. "=" .. preserved[name]
    end
    return table.concat(lines, "\n") .. "\n"
end
return Settings
