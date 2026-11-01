-- Integration scenarios. Stock scripts, LLL runtime files and the mod are
-- separate, unchanged assets. Only this test driver supplies fixture state.
if jit then jit.off(true, true) end
local function check(value, message) assert(value, message) end
require('stock/boot')
init(); update(1/60); render()
require('stock/animation_requires')
require('stock/wwise_visualization')
local refs = require('core/wwise/lua/wwise_bank_reference')
local preview = require('stock/wwise_preview')
-- This script installs globals and returns no module table.
preview = stingray.WwisePreview
check(ANIM_REQUIRES == true, 'stock require dependency was not loaded')
check(type(WwiseVisualization.render) == 'function', 'visualization chunk not loaded')
check(require('core/wwise/lua/wwise_bank_reference') == refs, 'require cache identity')
-- The complete stock census found three additional chunks. Load their real
-- top-level bodies, while retaining the selected game's boot callbacks.
local saved_init,saved_update,saved_render,saved_shutdown=init,update,render,shutdown
require('stock/79dc662443acf6f1') -- editor/debug boot; its frame path is not selected
init,update,render,shutdown=saved_init,saved_update,saved_render,saved_shutdown
local vf=require('stock/3425cb597039dd69').component
vf.world_created(17)
check(type(vf.entity_data[17])=='table','stock vector-field world creation')
vf.world_destroyed(17)
check(vf.entity_data[17]==nil,'stock vector-field world destruction')
check(type(require('stock/a95a92495dda0ba3').component)=='table','stock reflection module load')
require('poc/loader_scenarios.lua')

local curve = {unit=POC.unit(7), object='root', parameter='speed', float_index=0}
check(AnimationFlowCallbacks.get_animation_curve_value(curve) == curve, 'callback table identity')
check(curve.exists and curve.float_value == 3.5, 'native callback multi-return')
curve.float_index=1
AnimationFlowCallbacks.get_animation_curve_value(curve)
check(not curve.exists and curve.float_value == 0, 'missing animation curve')
curve.unit=POC.unit(8)
check(not pcall(AnimationFlowCallbacks.get_animation_curve_value,curve), 'backend error propagation')
curve.unit=POC.unit(7); curve.float_index=0
AnimationFlowCallbacks.get_animation_curve_value(curve)
check(curve.exists and curve.float_value==3.5, 'recovery after callback error')
local bad=pcall(stingray.Unit.animation_get_curve_value,-1,'root','speed',0)
check(not bad,'invalid engine handle accepted')

local world=stingray.Wwise.wwise_world(42)
collectgarbage('collect')
check(world==stingray.Wwise.wwise_world(42),'native handle identity across GC')
check(not pcall(stingray.WwiseWorld.enabled,{}),'foreign userdata accepted')
preview.play_event(42,'test_bank','test_event')
check(refs:count('test_bank')==1,'stock bank reference tracking')
preview.play_event(42,'test_bank','test_event') -- replaces prior event
preview.stop_event(42,'test_bank','test_event')
preview.stop_all_events(42,true)
check(refs:count('test_bank')==0,'stock bank reference release')
preview.play_event(42,'second_bank','second_event')
preview.stop_all_events(42,true)
check(refs:count('second_bank')==0,'stock event cleanup')
local co=coroutine.create(function()
    coroutine.yield(stingray.Application.build())
    return stingray.WwiseWorld.enabled(world)
end)
local ok,value=coroutine.resume(co);check(ok and value=='release','coroutine callback/yield')
ok,value=coroutine.resume(co);check(ok and value==true,'coroutine callback resume')
check(not pcall(dofile,'not/a/resource'),'missing resource should fail')
check(not pcall(require,'not/a/resource'),'missing module should fail')
check(stingray.Application.build()=='release','VM survives errors')
POC_FINALIZER=newproxy(true)
getmetatable(POC_FINALIZER).__gc=function()
    assert(stingray.Application.build()=='release','backend lifetime during lua_close')
    print('POC_FINALIZER backend_alive=true')
end
print('POC_REENTER')

-- Use actual LLL project loading and lifecycle code. Its platform is an
-- in-memory filesystem fixture, clearly separate from the native game backend.
LLL_CATALOG_WATCH=dofile('src/catalog_watch.lua')
local files={['loader.cfg']='return {}',['mods/loose.lua']='return true'}
for _,name in ipairs({'main.lua','src/poll_cache.lua','manifest.json','config/defaults.cfg'}) do
    local path='mods/lll_poll_cache/'..name
    files[path]=assert(POC.read(path))
end
local changed,counts={}, {read=0,stat=0,refresh=0}
local platform={roots={{kind='lll',path='mods'}},live='mods',loader_config='loader.cfg',settings='settings',
    files=function(path)if path=='mods'then return {'loose.lua'},nil,{'lll_poll_cache'} end;return {},nil,{} end,
    directories=function(path)return path=='mods' and {'lll_poll_cache'} or {} end,
    changed=function(path)local v=changed[path];changed[path]=false;return v==true end,
    read=function(path)counts.read=counts.read+1;return files[path] end,
    stat=function(path)counts.stat=counts.stat+1;return files[path] end,
    write=function(path,text)files[path]=text;return true end,
    mkdir=function()return true end}
local live=dofile('src/live.lua')(platform,function()end)
live.scan()
local controls={selected='lll_poll_cache',expanded={},bindings={},
    provenance_snapshot=function()return {{name='LLL Poll Cache',state='loaded'}} end,
    refresh=function()counts.refresh=counts.refresh+1;return 'refreshed',nil,4 end}
-- Exercise the original mod's mark() loops, not a synthetic numeric worker.
for i=1,80 do controls.expanded['group'..i]=i%2==0 end
local function refresh_catalog()assert(live);controls.refresh()end
local original_fp,original_refresh=live.fingerprint,controls.refresh
local factory=dofile('src/manager.lua')
local manager=factory({available=function()return true end,require=live.load,
    preflight=live.preflight,can_retry=function()return true end,evict=function()end,
    report=function(name,status)check(not tostring(status):find('error',1,true),name..':'..tostring(status))end,
    runtime=jit and 'LuaJIT' or 'Lua 5.1 reference',native_ffi=jit~=nil}, {'live/lll_poll_cache'})
manager.refresh=function()return refresh_catalog()end
check(LiveLuaLoader==manager,'real LLL manager not published')
manager.frame(1/60)
check(live.fingerprint~=original_fp,'unchanged mod failed to install')
local baseline=live.fingerprint('live/loose')
check(baseline~=nil,'initial fingerprint missing')
local before_refresh=counts.refresh
controls.refresh();controls.refresh()
check(counts.refresh==before_refresh+1,'mod failed to suppress duplicate refresh')
files['mods/loose.lua']='return false'
check(live.fingerprint('live/loose')~=baseline,'mod hid changed script')
local changed_value=live.fingerprint('live/loose')

function poc_step()
    check(live.fingerprint('live/loose')==changed_value,'cached script changed unexpectedly')
    controls.refresh()
    manager.frame(1/60)
end
function poc_finish()
    -- Calls use the normal protected native entry. Errors must not leave stack
    -- values or invalidate callbacks/handles from earlier calls.
    collectgarbage('collect')
    check(world==stingray.Wwise.wwise_world(42),'userdata identity lost')
    check(counts.refresh==before_refresh+1,'idle refresh count changed')
    controls.expanded.final_change=true;controls.refresh()
    check(counts.refresh==before_refresh+2,'mod swallowed metadata change')
    manager.shutdown()
    check(live.fingerprint==original_fp and controls.refresh==original_refresh,'mod cleanup did not restore owned callbacks')
    shutdown()
    print('POC_SEMANTICS stock=9 curve=pass audio=pass identity=pass coroutine=pass errors=pass mod=LLL_Poll_Cache lifecycle=pass')
end
function poc_fail()error({reason='deliberate non-string error'})end
function poc_recovery()check(stingray.Application.build()=='release','error recovery')end
if jit then jit.off(poc_step);jit.off(poc_finish);jit.off(poc_recovery) end
