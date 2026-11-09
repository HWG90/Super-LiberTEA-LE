-- LLL loads this archive entry under its LuaJIT boot and starts HD2 HUD+ here, the way HUD+'s own
-- boot script (replaced by LLL's boot) did: entry.start(_G) hooks the game's global update.
local entry = import("entry")
local runtime
return {
    live_lua_api = 1,
    on_enable = function()
        if runtime == nil then
            runtime = entry.start(_G)
        end
        return true
    end,
    on_disable = function()
        if runtime ~= nil then
            runtime:stop("disabled")
        end
        runtime = nil
        return true
    end,
}
