-- Goose Gadget Kit LE (Super LiberTEA - LE): the Spawner and First Person pages only.
-- Same lifecycle as the full kit's main.lua; the Unlocks and Gameplay parts (catalogue backend,
-- controller, remembered equipment, freezes, objectives) are never loaded.
local menu, first_person, spawner
local stopping = false
local function log(message) mod.log(tostring(message)) end
local function shutdown()
    stopping = true
    if spawner then spawner:shutdown() end
    if menu then menu:begin_shutdown() end
    local fp_done,fp_why=true,nil
    if first_person then fp_done,fp_why=first_person.shutdown()end
    if fp_done~=true then return false,fp_why end
    if menu then
        local done, why = menu:shutdown()
        if done ~= true then return false, why end
    end
    menu, spawner = nil, nil
    return true
end
return {
    live_lua_api = 1,
    name = 'Goose Gadget Kit LE',
    author = 'Goose',
    on_enable = function()
        assert(not menu, 'Previous Goose Gadget Kit cleanup has not completed')
        stopping = false
        first_person=mod.require('src/first_person.lua')
        first_person.enable()
        spawner = mod.require('src/spawner.lua').new(log)
        menu = mod.require('src/mcm.lua').new(log, spawner)
        menu:update(0)
        log('Loaded (Spawner, First Person); use MCM > Goose Gadget Kit')
    end,
    on_update = function(dt)
        if not menu or stopping then return end
        menu:update(dt)
        first_person.update()
        spawner:update()
        menu:refresh_status()
    end,
    on_disable = shutdown,
    on_cleanup_poll = shutdown,
}
