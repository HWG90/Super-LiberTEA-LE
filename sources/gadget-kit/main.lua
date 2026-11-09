local controller, menu, backend, first_person, equipment, spawner, mission
local stopping = false
local function log(message) mod.log(tostring(message)) end
local function shutdown(qualified_poll)
    if backend and backend.mem.begin_frame then backend.mem:begin_frame() end
    stopping = true
    if equipment then equipment:shutdown() end
    if spawner then spawner:shutdown() end
    if mission then mission:shutdown() end
    if menu then menu:begin_shutdown() end
    local fp_done,fp_why=true,nil
    if first_person then
        if qualified_poll==true and first_person.poll_cleanup then fp_done,fp_why=first_person.poll_cleanup()
        else fp_done,fp_why=first_person.shutdown()end
    end
    if controller then
        local called, done, why = pcall(controller.shutdown, controller)
        if not called then return false, tostring(done) end
        if done ~= true then return false, why or 'Goose Gadget Kit restoration is pending' end
    end
    if fp_done~=true then return false,fp_why end
    if menu then
        local done, why = menu:shutdown()
        if done ~= true then return false, why end
    end
    controller, menu, spawner, mission = nil, nil, nil, nil
    return true
end
return {
    live_lua_api = 1,
    name = 'Goose Gadget Kit',
    author = 'Goose',
    on_enable = function()
        assert(not controller, 'Previous Goose Gadget Kit cleanup has not completed')
        stopping = false
        backend=mod.require('src/backend.lua').new(log)
        local captured,why=backend:capture()
        if captured then
            log('Read-only catalogue preflight ready: '..#captured.records..' equipment/parent rows; master switch remains in MCM')
        else log('Read-only catalogue preflight: '..tostring(why)) end
        local hidden=mod.require('src/loadout_catalogue.lua').hidden
        local unreleased=mod.require('src/armory_weapons.lua').new(backend,hidden)
        controller = mod.require('src/controller.lua').new(backend, log, unreleased)
        equipment=mod.require('src/equipment.lua').new(mod.require('src/equipment_backend.lua').new(backend),mod,log)
        first_person=mod.require('src/first_person.lua')
        first_person.enable()
        spawner = mod.require('src/spawner.lua').new(log,{extra_weapons=hidden})
        mission = mod.require('src/objectives.lua').new(backend, log)
        menu = mod.require('src/mcm.lua').new(controller, log, spawner, mission, spawner:loadout_editor())
        menu:update(0)
        log('Loaded; use MCM > Goose Gadget Kit > Enabled')
    end,
    on_update = function(dt)
        if not controller or stopping then return end
        if backend.mem.begin_frame then backend.mem:begin_frame() end
        menu:update(dt)
        controller:update(dt)
        equipment:update(dt,controller:equipment_ready(),controller.categories)
        first_person.update()
        spawner:update(dt)
        mission:update(dt)
        menu:refresh_status()
    end,
    on_disable = shutdown,
    on_cleanup_poll = function()return shutdown(true)end,
}
