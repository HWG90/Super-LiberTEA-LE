-- Separate-process evidence bridge: captured actual native callback health
-- passes through the real CFFI adapters/managers/retry policy. It does not
-- inject a fault in a game, or pretend the native DLL ran inside this Lua VM.
local root=assert(NATIVE_ADS_TEST_ROOT)
local name,event=assert(NATIVE_RECOVERY_NAME),assert(NATIVE_RECOVERY_EVENT)
assert(event.stage=='callback_read_failed'and event.native_error==3 and event.armed==0)
assert(event.installed==1 and event.reserved==1 and event.token>0)
local policies={camera={prefix='NADSC_',stats_size=80},fov={prefix='NADSF_',stats_size=88},blur={prefix='NADSB_',stats_size=80}}
local spec=assert(policies[name]);local Module=mod.require('src/first_person/'..name..'.lua')
local Recovery=mod.require('src/first_person/recovery.lua')
local checked=0
for _,pending in ipairs({false,true})do
 local state={error=0,armed=true,installed=true,owned=false,pending=pending,begins=0,ends=0,generation=event.token}
 local library={}
 library[spec.prefix..'Begin']=function(_,out)
  assert(not state.owned);state.begins=state.begins+1;state.owned=true;state.armed=true
  state.error=0;state.installed=true;out[0]=state.generation;return 1
 end
 library[spec.prefix..'Error']=function()return state.error end
 library[spec.prefix..'ReadStats']=function(g,out)
  assert(TEST_PORT51.number(out.size)==spec.stats_size and TEST_PORT51.number(out.abi)==1)
  assert(TEST_PORT51.number(g)==(state.owned and state.generation or 0))
  out.armed=state.owned and state.armed and 1 or 0;out.installed=state.installed and 1 or 0;out.error=state.error
  return 1
 end
 library[spec.prefix..'End']=function(g)
  assert(state.owned and TEST_PORT51.number(g)==state.generation);state.ends=state.ends+1
  if state.pending then state.error=13;return 0 end
  state.owned=false;state.installed=false;state.error=0;state.generation=state.generation+1;return 1
 end
 -- Match the real disarmed FOV transition refusal; health must be polled
 -- before a control call can overwrite the native callback cause.
 library.NADSF_SetTransition=function()
  if not state.armed then state.error=7;return 0 end;return 1
 end
 local adapter=Module.Adapter.new({abi=1,library='captured-native-event'})
 adapter.library=library
 local config={camera_kind=6,game=1,exe=2,context=3,camera=4,avatar_owner=5,avatar_index=0,avatar=6,body=7,
  camera_unit=8,request=100,weapon=11,forward=.18,up=.04,smoothing_ms=100,blend_ms=120,max_gap_ms=250}
 local backend={}
 backend[name=='camera'and'camera_config'or(name..'_config')]=function()return config end
 if name=='fov'then backend.presentation_transition=function()return {epoch=1,progress=1,ads=false}end end
 local controller={enabled=true,lease={request=100,weapon=11,origin={player_identity='player',weapon=11}}}
 function controller:is_enabled()return self.enabled end
 function controller:result()return {mode='pose_offset',phase='running'}end
 local manager=Module.new(backend,nil,adapter)
 assert(manager:update(controller));assert(state.begins==1 and not manager:is_clean())
 state.error=event.native_error;state.armed=event.armed~=0;state.installed=event.installed~=0
 assert(not manager:update(controller));local failure=manager:result()
 assert(failure.failure_native_error==event.native_error and failure.failure_kind=='temporary_read')
 assert(manager:is_clean()~=pending and state.begins==1)
 local recovery=Recovery.new();local proof={fresh=true,safe=true,same_player=true,foreign=false}
 local row=recovery:failure(name,failure,manager:is_clean(),proof,0)
 local start=0
 if pending then
  assert(row.phase=='cleanup'and row.pending_classification=='retry')
  assert(recovery:action(name,.5)=='cleanup'and state.begins==1)
  state.pending=false;assert(manager:stop()and manager:is_clean())
  assert(recovery:cleanup(name,true,1));start=1
 else assert(row.phase=='waiting')end
 assert(recovery:action(name,start+.1)=='wait'and state.begins==1)
 assert(recovery:action(name,start+.25)=='update')
 assert(not recovery:revalidate(name,{fresh=true,safe=true,same_player=false,foreign=false},start+.25))
 assert(state.begins==1 and recovery:action(name,start+.3)=='wait')
 assert(recovery:action(name,start+.5)=='update'and recovery:revalidate(name,proof,start+.5))
 assert(manager:update(controller));assert(state.begins==2 and manager:result().phase=='active')
 assert(manager:result().failure_kind==nil and controller.enabled)
 recovery:success(name,start+.5,true);assert(recovery:snapshot().policies[name].phase=='healthy')
 assert(manager:stop()and manager:is_clean());checked=checked+1
end
print('Captured native '..name..' health -> real CFFI Adapter/Manager -> cleanup/backoff/fresh proof -> rearm: '..checked..' cases PASS')
return checked
