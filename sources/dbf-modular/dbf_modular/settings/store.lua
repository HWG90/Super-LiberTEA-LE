-- One committed store. Persistence completes before values/revisions/callbacks change.
local Schema = mod.require("settings/schema.lua")
local Migrate = mod.require("settings/migrate.lua")
local Store = {}
Store.__index = Store
local function copy(values)
    local result = {}
    for id, value in pairs(values) do
        result[id] = value
    end
    return result
end
local function serialize(self, values)
    local all, keys = copy(self.unclaimed), {}
    for id, value in pairs(values) do
        all[id] = value
    end
    for id in pairs(all) do
        keys[#keys + 1] = id
    end
    table.sort(keys)
    local lines = { "schema_version=" .. Schema.version .. "\n" }
    for _, id in ipairs(keys) do
        local value = all[id]
        local text = type(value) == "boolean" and tostring(value) or string.format("%.17g", value):gsub(",", ".")
        lines[#lines + 1] = id .. "=" .. text .. "\n"
    end
    return table.concat(lines)
end
function Store.new(context, globals, storage)
    globals = globals or _G
    storage = storage or context.options_storage or context.require("settings/storage.lua").default(globals, context)
    assert(
        type(storage.read) == "function" and type(storage.write_atomic or storage.write) == "function",
        "Settings storage required"
    )
    local called, text, why = pcall(storage.read)
    assert(called and (text ~= nil or why == nil), "Settings read failed: " .. tostring(called and why or text))
    assert(text == nil or type(text) == "string" and #text <= 1048576, "Invalid owned settings source")
    local version = Migrate.parse(text).schema_version
    assert(version == nil or version == Schema.version, "Unsupported DBF Modular schema: " .. tostring(version))
    local sources, catalog, preferences = { owned = text }, nil, nil
    if version == nil then
        preferences = context.config and context.config.preferences or {}
        if type(storage.read_preferences) == "function" then
            local okay, defaults, user = pcall(storage.read_preferences)
            assert(okay, "Original DBF preferences read failed: " .. tostring(defaults))
            assert(
                (defaults == nil or type(defaults) == "string") and (user == nil or type(user) == "string"),
                "Invalid original DBF preference source"
            )
            preferences = copy(preferences)
            for _, original in ipairs({ defaults or false, user or false }) do
                if original ~= false then
                    local Json = context.require("settings/json.lua")
                    local decoded = Json.decode(original)
                    assert(
                        type(decoded) == "table" and decoded ~= Json and original:match("^%s*{"),
                        "Original DBF preferences must be a JSON object"
                    )
                    local values = decoded.preferences
                    assert(
                        values == nil or type(values) == "table" and values ~= Json,
                        "Original DBF preferences must be an object"
                    )
                    for _, key in ipairs(Schema.dbf_keys) do
                        local value = values and Schema.validate("native_stratagem_radial." .. key, values[key])
                        if value ~= nil then
                            preferences[key] = value
                        end
                    end
                end
            end
        end
        if type(storage.read_legacy) == "function" then
            for _, name in ipairs({ "menu", "blacklist" }) do
                local okay, value, problem = pcall(storage.read_legacy, name)
                assert(
                    okay and (value ~= nil or problem == nil),
                    "Original DBF import failed: " .. name .. ": " .. tostring(okay and problem or value)
                )
                assert(
                    value == nil or type(value) == "string" and #value <= 1048576,
                    "Invalid original DBF source: " .. name
                )
                sources[name] = value
            end
        end
        local original = rawget(globals, "ModOptionsMenu")
        if sources.menu == nil and type(original) == "table" and type(original.get) == "function" then
            local lines, ids = {}, {}
            for _, key in ipairs(Schema.dbf_keys) do
                ids[#ids + 1] = "native_stratagem_radial." .. key
            end
            for id in pairs(Schema.aliases) do
                ids[#ids + 1] = id
            end
            ids[#ids + 1], ids[#ids + 2] =
                "native_stratagem_radial.selection_mode", "native_stratagem_radial.select_on_release"
            for index = 1, 8 do
                ids[#ids + 1] = "native_stratagem_radial.blacklist_kind_" .. index
            end
            for _, id in ipairs(ids) do
                local okay, value = pcall(original.get, id)
                if
                    okay
                    and (
                        type(value) == "boolean"
                        or type(value) == "number" and value == value and math.abs(value) < math.huge
                    )
                then
                    lines[#lines + 1] = id .. "\t" .. tostring(value) .. "\n"
                end
            end
            sources.menu = table.concat(lines)
        end
        catalog = context.require("src/stratagems.lua").old_to_current
    end
    local values, migration, unknown = Migrate.run(sources, preferences, catalog)
    assert(values, migration)
    return setmetatable({
        values = values,
        migration = migration,
        unclaimed = unknown,
        storage = storage,
        definitions = Schema.definitions,
        by_id = Schema.by_id,
        categories = Schema.categories,
        pages = Schema.pages,
        callbacks = {},
        revision = 0,
        definition_revision = 0,
        path = storage.path,
    }, Store)
end
function Store:get(id)
    return self.values[Schema.resolve(id)]
end
function Store:snapshot()
    return copy(self.values)
end
function Store:apply(changes)
    if self.closed then
        return false, "Settings owner retired"
    end
    if type(changes) ~= "table" then
        return false, "Settings transaction required"
    end
    local next_values, normalized, changed = copy(self.values), {}, {}
    for id, value in pairs(changes) do
        local canonical = Schema.resolve(id)
        local checked = Schema.validate(canonical, value)
        if checked == nil then
            return false, "Invalid setting or value: " .. tostring(id)
        end
        if normalized[canonical] ~= nil and normalized[canonical] ~= checked then
            return false, "Conflicting setting aliases: " .. canonical
        end
        normalized[canonical] = checked
    end
    for id, value in pairs(normalized) do
        if value ~= self.values[id] then
            next_values[id], changed[#changed + 1] = value, id
        end
    end
    if #changed == 0 then
        return true
    end
    local okay, accepted, why = pcall(self.storage.write_atomic or self.storage.write, serialize(self, next_values))
    if not okay or accepted ~= true then
        return false, tostring(okay and (why or "Atomic settings write refused") or accepted)
    end
    self.values, self.revision = next_values, self.revision + 1
    table.sort(changed)
    for _, id in ipairs(changed) do
        local pending = {}
        for callback in pairs(self.callbacks[id] or {}) do
            pending[#pending + 1] = callback
        end
        for _, callback in ipairs(pending) do
            local called, problem = pcall(callback, self.values[id], id)
            if not called then
                self.notification_error = tostring(problem)
            end
        end
    end
    return true
end
function Store:set(id, value)
    return self:apply({ [id] = value })
end
function Store:on_change(id, callback)
    id = Schema.resolve(id)
    if self.closed or not id or type(callback) ~= "function" then
        return nil, "Invalid settings subscription"
    end
    local callbacks = self.callbacks[id] or {}
    self.callbacks[id] = callbacks
    callbacks[callback] = true
    return function()
        callbacks[callback] = nil
    end
end
function Store:dbf_options()
    if self.facade then
        return self.facade
    end
    local facade, owner = { api = 1, unified = true }, self
    function facade.get(id)
        if id == "native_stratagem_radial.selection_mode" then
            return 4 - owner:get("native_stratagem_radial.selection_mode_ordered")
        end
        if id == "native_stratagem_radial.select_on_release" then
            return owner:get("native_stratagem_radial.release_selection_mode") == 2
        end
        return owner:get(id)
    end
    function facade.set(id, value)
        return owner:set(id, value)
    end
    function facade.register_option(id, spec)
        local row = Schema.by_id[Schema.resolve(id)]
        if owner.closed or not row or type(spec) ~= "table" or spec.type ~= row.type then
            return false
        end
        if row.type == "choice" then
            return type(spec.choices) == "table" and #spec.choices == #row.choices
        end
        if row.type == "slider" then
            return spec.min == row.min and spec.max == row.max
        end
        return true
    end
    function facade.on_change(id, callback)
        if type(callback) ~= "function" then
            return false
        end
        return owner:on_change(id, function()
            callback(facade.get(id), id)
        end) ~= nil
    end
    self.facade = facade
    return facade
end
function Store:close()
    self.closed, self.callbacks = true, {}
    return true
end
return Store
