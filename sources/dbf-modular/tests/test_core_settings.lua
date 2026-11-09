local Support = assert(loadfile("tests/support.lua"))()
local context, globals = Support.project()
globals.io = {
    open = function()
        error("Legacy settings IO forbidden")
    end,
}
globals.DBFMCM = {
    register = function()
        error("Second MCM owner forbidden")
    end,
}
local Schema = context.require("settings/schema.lua")
local Store = context.require("settings/store.lua")
local writes, fail = 0, false
local store = Store.new(context, globals, {
    read = function()
        return "schema_version=1\nnative_stratagem_radial.input_interval_ms=0\nkind_34=true\nkind_149=false\n"
    end,
    read_legacy = function()
        error("Canonical store must not import again")
    end,
    write_atomic = function()
        writes = writes + 1
        return not fail, "disk refused"
    end,
})
local facade = store:dbf_options()
local Settings = context.require("src/settings.lua")
local Blacklist = context.require("src/mission_blacklist.lua")
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local state, radial = {}, {}
local values = Settings.canary_settings(facade, state, radial, 1000)
eq(values.input_interval_ms, 0)
eq(values.selection_mode, 3, "original Wedge translation is unchanged")
eq(state.retry_registration, false)
local registrations = 0
for _, suffix in ipairs(Schema.dbf_keys) do
    eq(state.registered[suffix], true, "real Store accepts original spec " .. suffix)
    registrations = registrations + 1
end
eq(registrations, 32)
eq(writes, 0, "registration never rewrites saved settings")
eq(globals.DBFMenuSubscriptions, nil)
local available = {}
for _, row in ipairs(Schema.exclusions) do
    available[#available + 1] = row.kind
end
local exclusions = {}
local map = Blacklist.mission_blacklist_settings(facade, exclusions, available)
eq(exclusions.ready, true)
eq(map[34], true)
eq(exclusions.enabled[149], false, "known false remains distinct from unknown")
local count = 0
for _ in pairs(exclusions.registered) do
    count = count + 1
end
eq(count, 37)
eq(writes, 0, "all exclusions use the same Store without another writer")
eq(exclusions.save, nil)
eq(exclusions.save_pending, nil)
eq(exclusions.native, nil)
eq(store:set("kind_149", true), true)
eq(exclusions.dirty, true)
map = Blacklist.mission_blacklist_settings(facade, exclusions, available)
eq(map[149], true)
eq(writes, 1)
-- The native input reader already protects equipped kinds. Reused availability
-- arrays must be inspected by contents, not treated as immutable identities.
for i, kind in ipairs(available) do
    if kind == 34 then
        table.remove(available, i)
        break
    end
end
map = Blacklist.mission_blacklist_settings(facade, exclusions, available)
eq(map[34], nil)
eq(map[149], true)
map = Blacklist.mission_blacklist_settings(facade, exclusions, nil)
eq(next(map), nil, "unknown availability cannot exclude an equipped kind")
fail = true
eq(store:set("kind_149", false), false)
eq(facade.get("native_stratagem_radial.hide_sos"), true, "failed Store write never alters the Core view")
eq(exclusions.dirty, false)
eq(store:close(), true)
print("Core Store integration: " .. checks .. " checks passed")
