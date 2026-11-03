-- Compare all native bindings, resource keys and settings against the immutable release.
local baseline, generated = assert(arg[1]), assert(arg[2])
local function importer(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local at = assert(source:find("-- LLL loads this archive entry", 1, true), "addon entry missing")
    return assert(loadstring(source:sub(1, at - 1) .. "return import", "@" .. path))()
end
local old, new = importer(baseline), importer(generated)
local fields = 0
local function equal(a, b, label)
    assert(type(a) == type(b), label .. ": type changed")
    if type(a) ~= "table" then
        assert(a == b, label .. ": value changed")
        fields = fields + 1
        return
    end
    for key, value in pairs(a) do
        equal(value, b[key], label .. "." .. tostring(key))
    end
    for key in pairs(b) do
        assert(a[key] ~= nil, label .. ": unexpected key " .. tostring(key))
    end
end
local before, after = old("game.data"), new("game.data")
for key, value in pairs(before) do
    -- The module graph changes with the source organization; native values do not.
    if key ~= "requires" and key ~= "uses" then
        equal(value, after[key], "game.data." .. key)
    end
end
for _, name in ipairs({ "game.options", "game.resources", "game.menu_data" }) do
    equal(old(name), new(name), name)
end
for module, uses in pairs(before.uses) do
    if module ~= "options" then
        equal(uses, after.uses[module], "uses." .. module)
    end
end
assert(after.refuse_unpinned == true, "unsupported build guard removed")
assert(next(after.unresolved) == nil, "unexpected unresolved binding")
for module, dependencies in pairs(after.requires) do
    for _, name in ipairs(dependencies) do
        assert(name ~= "options", module .. ": stale forwarding dependency")
    end
end
for index = 3, #arg do
    assert(loadfile(arg[index]))
end
local addon = assert(loadfile(generated))()
assert(addon.live_lua_api == 1 and type(addon.on_enable) == "function" and type(addon.on_disable) == "function")
assert(addon.on_disable() == true, "inactive disable failed")
print("bundle: " .. fields .. " native/settings/resource values preserved; all source modules compile; addon loads")
