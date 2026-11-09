-- One DBF Modular MCM owner, available before native gameplay initialization.
local Schema = mod.require("settings/schema.lua")
local Menu = {}
Menu.__index = Menu
local ID = "dbf_modular"
local function key(id)
    if id:match("^kind_%d+$") then
        return id
    end
    return "s_" .. id:gsub("[^%w]", function(char)
        return string.format("_%02x", char:byte())
    end)
end
local function snapshot(self)
    local values = {}
    for id, control in pairs(self.controls) do
        values[control] = self.store:get(id)
    end
    return values
end
local function retire(self)
    if self.owner and not self.handle and self.framework.mods[ID] == self.owner then
        return false, "MCM cleanup handle unavailable"
    end
    if self.handle then
        if self.framework.mods[ID] and self.framework.mods[ID] ~= self.owner then
            return false, "MCM registration ownership changed"
        end
        local called, accepted, why = pcall(self.handle.unregister)
        if not called or accepted == false then
            return false, tostring(called and (why or "MCM close refused") or accepted)
        end
    end
    self.handle, self.owner, self.framework = nil, nil, nil
    return true
end
function Menu.new(store, get_mcm)
    return setmetatable({
        store = store,
        get_mcm = get_mcm or function()
            return rawget(_G, "DBFMCM")
        end,
        controls = {},
        status = "waiting for MCM",
        registered = 0,
    }, Menu)
end
function Menu:install(api)
    local accepted, why = retire(self)
    if not accepted then
        return false, why
    end
    if api.mods[ID] then
        return false, "MCM ID belongs to another owner"
    end
    local controls, buckets, used = {}, {}, {}
    for _, spec in ipairs(self.store.definitions) do
        local control = key(spec.id)
        if #control > 80 or used[control] then
            return false, "Invalid or conflicting MCM control ID"
        end
        controls[spec.id], used[control] = control, true
    end
    for _, spec in ipairs(self.store.definitions) do
        local id = spec.id
        local control = {
            id = controls[id],
            type = spec.type,
            label = spec.label,
            description = spec.description,
            default = spec.default,
            choices = spec.choices,
            min = spec.min,
            max = spec.max,
            step = spec.step,
            fine_step = spec.fine_step,
        }
        control.enabled_if = function(get)
            return Schema.enabled(id, function(dependency)
                local value = get(controls[dependency])
                if value == nil then
                    return self.store:get(dependency)
                end
                return value
            end)
        end
        local bucket = buckets[spec.page] or {}
        bucket[#bucket + 1] = control
        buckets[spec.page] = bucket
    end
    local pages = {}
    for _, page in ipairs(self.store.pages) do
        assert(buckets[page.id], "Empty settings purpose: " .. page.id)
        pages[#pages + 1] = { id = page.id, name = page.name, category = page.category, controls = buckets[page.id] }
    end
    self.controls = controls
    local storage = {}
    function storage.load()
        return snapshot(self)
    end
    function storage.save(_, values)
        if self.closed then
            return false, "MCM owner retired"
        end
        if self.framework ~= api or api.mods[ID] ~= self.owner then
            return false, "MCM ownership changed"
        end
        local changes = {}
        for id, control in pairs(controls) do
            if values[control] == nil then
                return false, "Missing MCM setting: " .. id
            end
            changes[id] = values[control]
        end
        local okay, problem = self.store:apply(changes)
        if not okay then
            return false, problem
        end
        for control, value in pairs(snapshot(self)) do
            values[control] = value
        end
        return true
    end
    local called, handle, problem = pcall(api.register, {
        id = ID,
        name = "DBF Modular",
        description = "Combat instruments, stratagem selection and terminal controls.",
        categories = self.store.categories,
        pages = pages,
        storage = storage,
    })
    if not called or type(handle) ~= "table" or type(handle.unregister) ~= "function" then
        if api.mods[ID] then
            self.framework, self.owner = api, api.mods[ID]
        end
        return false, tostring(called and (problem or "MCM registration refused") or handle)
    end
    self.framework, self.handle, self.owner = api, handle, api.mods[ID]
    if not self.owner then
        return false, "MCM did not publish its settings owner"
    end
    self.owner.values = snapshot(self)
    self.values_revision, self.registered = self.store.revision, #self.store.definitions
    self.status = "ready: " .. self.registered .. " controls"
    return true
end
function Menu:update()
    if self.closed then
        return false, "MCM owner retired"
    end
    local api = self.get_mcm()
    if type(api) ~= "table" or api.api ~= 1 or type(api.register) ~= "function" or type(api.mods) ~= "table" then
        return false, "waiting for MCM"
    end
    if self.framework ~= api or not self.handle then
        local okay, why = self:install(api)
        if not okay then
            self.status = tostring(why)
        end
        return okay, why
    end
    if api.mods[ID] ~= self.owner then
        self.status = "MCM ownership changed"
        return false, self.status
    end
    if self.values_revision ~= self.store.revision then
        self.owner.values = snapshot(self)
        if type(self.handle.refresh_conditions) == "function" then
            self.handle.refresh_conditions()
        end
        api.revision = (api.revision or 0) + 1
        self.values_revision = self.store.revision
    end
    return true
end
function Menu:close()
    local okay, why = retire(self)
    if not okay then
        self.status = tostring(why)
        return false, why
    end
    self.closed, self.status = true, "closed"
    return true
end
return Menu
