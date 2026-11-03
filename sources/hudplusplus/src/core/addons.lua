local Addons = require("core.archive")
Addons.contracts = { lifecycle = 1, widgets = 1, map = 2, approach = 2, stratagem = 2 }
function Addons.compatible(available, part)
    if
        type(part) ~= "table"
        or type(part.id) ~= "string"
        or type(part.create) ~= "function"
        or type(part.requires) ~= "table"
        or type(part.options) ~= "table"
        or type(part.resources) ~= "table"
        or type(part.menu) ~= "table"
        or type(part.menu.template) ~= "number"
        or type(part.menu.resource) ~= "string"
    then
        return "shape"
    end
    if part.requires.lifecycle ~= available.lifecycle then
        return "contract", "lifecycle"
    end
    for name, version in pairs(part.requires) do
        if available[name] ~= version then
            return "contract", name
        end
    end
    local options = {}
    for _, entry in ipairs(part.options) do
        if type(entry) ~= "table" or type(entry.id) ~= "string" or options[entry.id] then
            return "option"
        end
        options[entry.id] = true
    end
    local resources = require("game.ui").public_resources
    for _, name in ipairs(part.resources) do
        if not resources[name] then
            return "resource", name
        end
    end
    for _, field in ipairs({ "slots", "provides" }) do
        if part[field] ~= nil and type(part[field]) ~= "table" then
            return "shape"
        end
        for _, name in ipairs(part[field] or {}) do
            if part.requires[name] == nil then
                return "contract", name
            end
        end
    end
end
function Addons.load(report, supplied, replacements)
    local native = require("native.channel")
    local source = supplied or native.files()
    local out, identities, options, providers = {}, {}, {}, {}
    for _, entry in ipairs(require("game.options")) do
        options[entry.id] = true
    end
    for _, resource in ipairs(source and Addons.discover(source) or {}) do
        local loaded, part = true, replacements and replacements[resource]
        if part == nil then
            loaded, part = pcall(require, resource)
        end
        local reason
        if loaded then
            reason = Addons.compatible(Addons.contracts, part)
        else
            reason = "load-failed"
        end
        if reason == nil and identities[part.id] then
            reason = "duplicate-addon"
        end
        if reason == nil then
            for _, entry in ipairs(part.options) do
                if options[entry.id] then
                    reason = "duplicate-option"
                    break
                end
            end
        end
        if reason == nil then
            for _, name in ipairs(part.provides or {}) do
                if providers[name] then
                    reason = "duplicate-provider"
                    break
                end
            end
        end
        if reason == nil then
            identities[part.id] = true
            for _, entry in ipairs(part.options) do
                options[entry.id] = true
            end
            for _, name in ipairs(part.provides or {}) do
                providers[name] = true
            end
            out[#out + 1] = part
        end
        if report ~= nil then
            report({ event = "addon", id = type(part) == "table" and part.id or nil, action = reason or "loaded" })
        end
    end
    return out
end
function Addons.options(base, parts)
    local out = {}
    for _, entry in ipairs(base) do
        out[#out + 1] = entry
    end
    for _, part in ipairs(parts) do
        for _, entry in ipairs(part.options) do
            out[#out + 1] = entry
        end
    end
    return out
end
local function nothing() end
local function call(owner, method, convert, a, b)
    if convert ~= nil then
        a = convert(a)
    end
    return owner[method](owner, a, b)
end
local function append(previous, guard, instances, id, method, convert)
    if guard.instance[method] == nil then
        return previous
    end
    return function(a, b)
        previous(a, b)
        if instances[id] ~= guard.instance then
            return
        end
        if not pcall(call, guard.instance, method, convert, a, b) then
            guard.fail()
        end
    end
end
local function attach(self, part, providers, report)
    local widgets, wrap = providers.widgets(part.resources)
    local api = { widgets = widgets, event = report }
    for name in pairs(part.requires) do
        if providers[name] ~= nil and name ~= "widgets" then
            api[name] = providers[name](wrap)
        end
    end
    local guard = {}
    function guard.fail()
        self.instances[part.id] = nil
        if guard.instance ~= nil then
            pcall(guard.instance.close, guard.instance)
        end
        if report ~= nil then
            pcall(report, { event = "addon", id = part.id, action = "failed" })
        end
    end
    local made, instance = pcall(part.create, api)
    if not made or type(instance) ~= "table" then
        guard.fail()
        return
    end
    guard.instance, self.instances[part.id] = instance, instance
    self._prepare = append(self._prepare, guard, self.instances, part.id, "prepare")
    self._sample = append(self._sample, guard, self.instances, part.id, "sample")
    self._finish = append(self._finish, guard, self.instances, part.id, "finish")
    self._leave = append(self._leave, guard, self.instances, part.id, "leave")
    for _, name in ipairs(part.slots or {}) do
        local slot = self.slots[name] or { put = nothing, hide = nothing, close = nothing }
        self.slots[name] = slot
        slot.put = append(slot.put, guard, self.instances, part.id, "world_put", wrap)
        slot.hide = append(slot.hide, guard, self.instances, part.id, "world_hide")
        slot.close = append(slot.close, guard, self.instances, part.id, "world_close")
    end
end
function Addons.new(parts, providers, report)
    local self = {
        state = {},
        slots = {},
        instances = {},
        _prepare = nothing,
        _sample = nothing,
        _finish = nothing,
        _leave = nothing,
    }
    for _, part in ipairs(parts) do
        local unavailable = false
        for name in pairs(part.requires) do
            if providers[name] == false then
                unavailable = true
            end
        end
        if unavailable then
            if report ~= nil then
                pcall(report, { event = "addon", id = part.id, action = "unavailable" })
            end
        else
            attach(self, part, providers, report)
        end
    end
    function self:slot(name)
        if self.slots[name] == nil then
            self.slots[name] = { put = nothing, hide = nothing, close = nothing }
        end
        return self.slots[name]
    end
    function self:prepare(values)
        for name in pairs(self.state) do
            self.state[name] = nil
        end
        self._prepare(values, self.state)
        for name, slot in pairs(self.slots) do
            slot.wanted = self.state[name] == true
        end
        return self.state
    end
    function self:sample(frame)
        self._sample(frame, self.state)
    end
    function self:finish(frame)
        self._finish(frame, self.state)
    end
    function self:leave()
        for name in pairs(self.state) do
            self.state[name] = nil
        end
        for _, slot in pairs(self.slots) do
            slot.wanted = false
        end
        self._leave()
    end
    function self:close()
        local failures = {}
        for id, instance in pairs(self.instances) do
            self.instances[id] = nil
            local okay, why = pcall(instance.close, instance)
            if not okay then
                failures[#failures + 1] = tostring(why)
            end
        end
        if #failures > 0 then
            error(table.concat(failures, "\n"))
        end
    end
    return self
end
return Addons
