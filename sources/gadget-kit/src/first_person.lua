-- Shared kit lifecycle, settings and MCM ownership for Native ADS / True FPV.
local M={}
local KIT='goose_temporary_unlocks'
local NATIVE='goose_native_ads_camera_test'
local PREFIX='first_person_'
local runtime,active,handle,spec,facade,provider,last_error
local revision=0
local input_service
local defaults={placement={x=.15,y=0,z=-.12},motion_enabled=true,motion_scale=1,
    weapon_placements={},action_placements={},action_state_mapping={},
    fird_head_camera={x=0,y=0,z=.04},camera_kick_enabled=true,aim_markers={}}
function M.host(parent)
    local host=setmetatable({}, {__index=function(_,key)
        if key=='config' then return parent.config.first_person or defaults end
        return parent[key]
    end})
    function host.set(key,value)
        local config={}
        for k,v in pairs(defaults)do config[k]=v end
        for k,v in pairs(parent.config.first_person or {})do config[k]=v end
        config[key]=value
        return parent.set('first_person',config)
    end
    return host
end
function M.menu_api()
    local real=rawget(_G,'DBFMCM')
    if type(real)~='table' or type(real.register)~='function'then return nil end
    if provider==real and input_service==real.shared_input_service then return facade end
    input_service=real.shared_input_service
    provider=real
    facade=setmetatable({mods={}}, {__index=real})
    if not real.camera_input and type(input_service)=='table' then
        facade.camera_input=mod.require('src/first_person/input_adapter.lua').new(stingray,input_service)
    end
    local owner=facade
    function facade.register(value)
        local controls,defaults_by_id={},{ }
        for index,page in ipairs(value.pages)do
            page.id=index==1 and 'first_person' or 'first_person_motion'
            page.name=index==1 and 'First Person' or 'Bob and Sway'
            for _,control in ipairs(page.controls)do
                local id=control.id
                if id then
                    controls[id]=control;defaults_by_id[id]=control.default
                    control.id=PREFIX..id
                end
                local changed=control.on_change
                control.on_change=function(...)
                    if changed then changed(...)end
                    if value.on_change then value.on_change(...)end
                end
            end
        end
        local h={}
        function h.get(id)
            if handle and provider==real then return handle.get(PREFIX..id)end
            return defaults_by_id[id]
        end
        function h.set(id,value)
            if handle and provider==real and type(handle.set)=='function'then return handle.set(PREFIX..id,value)end
            return false,'First-person menu is not attached'
        end
        function h.unregister()
            owner.mods[NATIVE]=nil
            if spec==value then spec=nil;revision=revision+1 end
            return true
        end
        owner.mods[NATIVE]={handle=h,pages=value.pages,controls=controls}
        spec=value;revision=revision+1
        return h
    end
    return facade
end
function M.editor_api()return M.menu_api()end
function M.changed(...)
    if spec and spec.on_change then spec.on_change(...)end
end
function M.attach(value)handle=value end
function M.revision()return revision end
function M.status()
    if last_error then return 'Unavailable: '..last_error end
    return active and 'True First Person ready; F11 toggles' or 'First person is initializing'
end
function M.pages()
    if spec then return spec.pages end
    return {{id='first_person',name='First Person',require_confirmation=false,controls={
        {id='first_person_status',type='text',label='Status: '..M.status()},
    }}}
end
function M.page()return M.pages()[1]end
function M.enable()
    assert(not runtime,'Previous first-person cleanup is pending')
    runtime=mod.require('src/first_person/runtime.lua')
    local ok,why=pcall(runtime.on_enable)
    if not ok then
        last_error=tostring(why)
        local called,done=pcall(runtime.on_disable)
        if called and done==true then runtime=nil end
        mod.log('First person initialization: '..last_error)
        return false,last_error
    end
    active,last_error=true,nil
    return true
end
function M.update()
    if not runtime then return end
    if not active then M.poll_cleanup();return end
    local ok,why=pcall(runtime.on_update)
    if not ok then
        active=false;last_error=tostring(why)
        mod.log('First person stopped: '..last_error)
    end
    if not active then M.poll_cleanup()end
end
local function shutdown(method)
    active=false
    if not runtime then return true end
    local callback=runtime[method]or runtime.on_disable
    local ok,done,why=pcall(callback)
    if not ok then return false,tostring(done)end
    if done~=true then return false,why or 'First-person restoration pending'end
    runtime,handle,spec=nil,nil,nil;revision=revision+1
    return true
end
function M.shutdown()return shutdown('on_disable')end
-- Called only by the kit's normal Update or loader cleanup-poll callback.
function M.poll_cleanup()return shutdown('on_cleanup_poll')end
return M
