-- Full maintained LLL bootstrap under the actual replacement VM. Only the
-- platform/engine input is a fixture; loader lifecycle and mod are unchanged.
assert(jit and not require('ffi').abi('gc64'))
jit.off(true,true)
local loose=[[local ffi,bit=require('ffi'),require('bit')
assert(require('jit').status() and ffi.new('int[1]',42)[0]==42 and bit.bxor(3,7)==4)
return {live_lua_api=1,on_enable=function()BOOTSTRAP_ENABLED=(BOOTSTRAP_ENABLED or 0)+1 end,
on_disable=function()BOOTSTRAP_DISABLED=(BOOTSTRAP_DISABLED or 0)+1;return true end}]]
local files={['loader.cfg']='return {}',['mods/loose.lua']=loose}
for _,name in ipairs({'main.lua','src/poll_cache.lua','manifest.json','config/defaults.cfg'})do
    local path='mods/lll_poll_cache/'..name
    files[path]=assert(POC.read(path))
end
local clock,reads,writes=0,0,0
local changed={}
local platform={data='data',roots={{kind='lll',path='mods'}},live='mods',
    settings='settings',loader_config='loader.cfg',revision='replacement-bootstrap-fixture',
    now=function()return clock end,open_log=function()end,
    guard=function()return {supported=true,exe_sha256='fixture',game_sha256='fixture'}end,
    hash=function()error('unexpected archive hash request')end,
    files=function(path)if path=='mods'then return {'loose.lua'},nil,{'lll_poll_cache'} end;return {},nil,{} end,
    directories=function(path)return path=='mods' and {'lll_poll_cache'} or {} end,
    changed=function(path)local v=changed[path];changed[path]=false;return v==true end,
    read=function(path)reads=reads+1;return files[path] end,
    stat=function(path)return files[path] end,
    write=function(path,body)writes=writes+1;files[path]=body;return true end,
    mkdir=function()return true end}
-- Native UI/game bindings are not covered by this lifecycle fixture.
stingray.Window=nil
stingray.Application.can_get=function()return false end
local loadlib=package.loadlib
package.loadlib=function()error('PUC native initializer attempted')end
local bootstrap=dofile('poc/bootstrap.lua')
bootstrap({platform=function()return platform end})
assert(not pcall(bootstrap,{platform=function()return platform end}),'double startup accepted')
local manager=assert(LiveLuaLoader)
assert(manager.modules['live/lll_poll_cache']=='loaded')
assert(manager.capabilities.native_ffi and manager.capabilities.runtime==jit.version)
assert(manager.jit_budget.accepted and manager.jit_budget.closed==false)
assert(not manager.jit_budget.watcher,'private old-runtime observer unexpectedly active')
assert(require('ffi').new('int[1]',42)[0]==42)
assert(require('bit').bxor(3,7)==4)
local Cache=dofile('mods/lll_poll_cache/src/poll_cache.lua')
local live,controls,actual_platform=Cache.interfaces(manager)
assert(actual_platform==platform)
local original_fp,original_refresh,original_changed=live.fingerprint,controls.refresh,platform.changed
update(1/60)
assert(live.fingerprint~=original_fp and controls.refresh~=original_refresh,'mod did not install')
local function handle_of(fn)
    for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then break end
        if type(v)=='table' and type(v.owned)=='function' and type(v.release)=='function' then return v end
    end
end
local handle=assert(handle_of(live.fingerprint))
assert(handle.owned())
local old=live.fingerprint('live/loose')
assert(old~=nil)
files['mods/loose.lua']=loose..'\n-- file edit'
assert(live.fingerprint('live/loose')~=old,'mod hid a file edit')
local baseline=live.fingerprint('live/loose')
for i=1,80 do controls.expanded['group'..i]=i%2==0 end
require('poc/trace.lua')
function poc_bootstrap_before_frame()
    clock=clock+1/60
    assert(live.fingerprint('live/loose')==baseline)
    controls.refresh()
end
jit.off(poc_bootstrap_before_frame)
function poc_bootstrap_step()
    poc_bootstrap_before_frame()
    update(1/60)
end
jit.off(poc_bootstrap_step)
function poc_bootstrap_before_shutdown()
    assert(handle.hits>100 and handle.refresh_hits>100,'unchanged cache code not exercised')
    -- Preserve maintained LLL behavior: restart_only prevents the enable toggle
    -- and automatic reload; explicit reload still accepts a cleanup contract.
    assert(not manager.set_enabled('live/lll_poll_cache',false))
    assert(handle.owned())
    assert(manager.reload('live/lll_poll_cache'))
    update(1/60)
    assert(not handle.active)
    handle=assert(handle_of(live.fingerprint));assert(handle.owned())
    local enabled,disabled=BOOTSTRAP_ENABLED,BOOTSTRAP_DISABLED or 0
    assert(manager.reload('live/loose'))
    assert(BOOTSTRAP_ENABLED==enabled+1 and BOOTSTRAP_DISABLED==disabled+1)
    assert(manager.set_enabled('live/loose',false))
    assert(BOOTSTRAP_DISABLED==disabled+2)
    assert(manager.set_enabled('live/loose',true))
    assert(BOOTSTRAP_ENABLED==enabled+2)
    local memory,why=dofile('poc/bootstrap_memory.lua').open()
    local ffi=require('ffi')
    if ffi.os=='Windows' then
        assert(memory,why)
        local buffer=ffi.new('char[8]','native')
        assert(memory.read(tonumber(ffi.cast('uintptr_t',buffer)),6)=='native')
        assert(memory.module('kernel32.dll'))
        assert(memory.read(1,8)==nil and memory.read(0x10000,4097)==nil)
        ffi.cdef[[void *VirtualAlloc(void *,size_t,uint32_t,uint32_t);
                   int VirtualFree(void *,size_t,uint32_t);]]
        local kernel=ffi.load('kernel32')
        local page=kernel.VirtualAlloc(nil,4096,0x3000,1) -- owned PAGE_NOACCESS
        assert(page~=nil)
        local unreadable=memory.read(tonumber(ffi.cast('uintptr_t',page)),8)
        assert(kernel.VirtualFree(page,0,0x8000)~=0)
        assert(unreadable==nil,'unreadable page accepted')
        print('POC_BOOTSTRAP_MEMORY self_read=pass invalid_reads=pass')
    else assert(memory==nil and why) end
end
function poc_bootstrap_after_shutdown()
    assert(live.fingerprint==original_fp and controls.refresh==original_refresh)
    assert(not handle.active and platform.changed==original_changed)
    assert(manager.jit_budget.closed)
    assert(manager.detach())
    package.loadlib=loadlib
    print('POC_BOOTSTRAP stock=pass startup=pass mod=LLL_Poll_Cache update=pass restart_policy=pass fixture_reload=pass fixture_disable=pass shutdown=pass ffi=real bit=real')
end
function poc_bootstrap_finish()
    poc_bootstrap_before_shutdown()
    shutdown()
    poc_bootstrap_after_shutdown()
end
jit.off(poc_bootstrap_before_shutdown)
jit.off(poc_bootstrap_after_shutdown)
jit.off(poc_bootstrap_finish)
