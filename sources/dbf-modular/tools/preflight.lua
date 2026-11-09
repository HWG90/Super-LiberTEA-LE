-- Exact LLL folder-project parser/instantiator, snapshotted as test-only fixtures.
-- Optional arg2 checks another current LLL checkout with the same interfaces.
local root = arg[1] or "dbf_modular"
local loader = arg[2] or "reference/lll"
local function read(path)
    local f = io.open(path, "rb")
    if not f then
        return
    end
    local text = f:read("*a")
    f:close()
    return text
end
local env = setmetatable({
    LLL_METADATA = assert(loadfile(loader .. "/metadata.lua"))(),
    LLL_CONFIG = assert(loadfile(loader .. "/config.lua"))(),
}, { __index = _G })
local chunk = assert(loadfile(loader .. "/project.lua"))
setfenv(chunk, env)
local Project = chunk()
local platform = { read = read, native_ffi = true }
local spec = Project.descriptor(platform, root)
local entry = { id = "dbf_modular", dir = root, metadata = { name = "DBF Modular" } }
local snapshot = Project.snapshot(platform, entry, spec)
local api = Project.instantiate(platform, entry, snapshot, function() end)
assert(api.live_lua_api == 1 and api.name == "DBF Modular")
for _, key in ipairs({ "on_enable", "on_update", "on_disable" }) do
    assert(type(api[key]) == "function")
end
assert(
    rawget(_G, "DBFModular") == nil and rawget(_G, "DiversBestFriend") == nil,
    "Preflight must not enable native access"
)
assert(api.on_disable() == true)
print("LLL folder preflight: " .. #snapshot.paths .. " sources compile; one lifecycle; native game access not enabled")
