-- Exercise the real combined Update orchestrator with bounded synthetic leases.
-- No native calls or process access occurs in this fixture.
local root=assert(NATIVE_ADS_TEST_ROOT)
local Recovery=dofile(root..'/src/first_person/recovery.lua')
local function fixture()
 local entry=assert(loadfile(root..'/main.lua'))()
 local function locate(fn,key,seen)
  seen=seen or{};if seen[fn]then return end;seen[fn]=true;local nested={}
  for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end
   if name==key then return fn,i end
   if type(value)=='function'and debug.getinfo(value,'S').what=='Lua'then nested[#nested+1]=value end
  end
  for _,child in ipairs(nested)do local f,i=locate(child,key,seen);if f then return f,i end end
 end
 local function set(key,value)
  local f,i=locate(entry.on_update,key)
  if not f then f,i=locate(entry.on_enable,key)end
  assert(f,'Missing real runtime upvalue '..key);debug.setupvalue(f,i,value)
 end
 local f={now=0,player='p',body=1,world=100000,safe=true,updates=0,stops=0,suspends=0,full_snapshots=0}
 local c={enabled=true,lease={origin={player_identity='p',body=f.body,world=f.world}}}
 function c:is_enabled()return self.enabled end
 function c:is_clean()return not self.enabled and not self.lease end
 function c:result()return {enabled=self.enabled,mode='pose_offset',phase=self.lease and'running'or'waiting',player_identity=self.player_owner or'p'}end
 function c:update()f.updates=f.updates+1;if self.enabled and not self.lease then self.lease={origin={player_identity=f.player,body=f.body,world=f.world}};self.player_owner=f.player end end
 function c:suspend()f.suspends=f.suspends+1;self.lease=nil;return true end
 function c:stop()f.stops=f.stops+1;self.enabled=false;self.lease=nil;return true end
 local b={};function b:begin_frame()assert(not self.frame_active);self.frame_active=true end
 function b:end_frame()assert(self.frame_active);self.frame_active=false end
 function b:snapshot()
  f.full_snapshots=f.full_snapshots+1
  if f.on_snapshot then f.on_snapshot(f.full_snapshots)end
  return {player_identity=f.player,body=f.body,world=f.world,identity='firearm',safe=f.safe,camera_kind=6,controller_active=false,aiming=false}
 end
 local function manager()
  local m={calls=0,stops=0,owned=false,fail=false,cleanup_failures=0,failure={}}
  function m:update()self.calls=self.calls+1;self.owned=true;if self.fail then return false,'synthetic fault'end;return true end
  function m:stop()self.stops=self.stops+1;if self.cleanup_failures>0 then self.cleanup_failures=self.cleanup_failures-1;return false,'pending'end;self.owned=false;return true end
  function m:is_clean()return not self.owned end
  function m:result()
   local r={phase='active',armed=true,owned=self.owned};if self.fail then for k,v in pairs(self.failure)do r[k]=v end end;return r
  end
  return m
 end
 f.c,f.b,f.managers=c,b,{}
 for _,name in ipairs({'fov','blur','camera','head','movement','near','dof'})do local m=manager();f.managers[name]=m;set(name,m)end
 f.recovery=Recovery.new()
 set('backend',b);set('controller',c);set('recovery',f.recovery);set('recovery_enabled',true)
 set('runtime_clock',function()return f.now end);set('diagnostics',nil);set('presentation',nil);set('recovery_owner',nil);set('owner_draining',nil)
 set('stopping',false);set('log',function()end);set('foreign_camera',function()return false end)
 set('compat',{update=function()return true end});set('editor',{is_active=function()return false end,update=function()end})
 set('motion',{update=function()return true end});set('menu',{update=function()end})
 set('aim_markers',nil);set('fird',nil);set('fird_entry',nil);set('fird_warm',nil)
 function f:replace_manager(name,value)self.managers[name]=value;set(name,value)end
 function f:read(key)
  local fn,i=locate(entry.on_update,key);assert(fn,'Missing real runtime upvalue '..key)
  local _,value=debug.getupvalue(fn,i);return value
 end
 function f:enable_observer()
  set('presentation',{update=function()end,result=function()return{}end,reset=function()end})
  set('presentation_module',{native_ads=function(s)return s.controller_active end})
 end
 function f:update(t)self.now=t;entry.on_update();assert(not b.frame_active)end
 return f
end
local cases=0
local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));cases=cases+1 end
test('clean optional failure leaves FP active and never blindly rearms',function()
 local f=fixture();f.managers.blur.fail=true
 f:update(0);assert(f.c.enabled and f.stops==0 and f.managers.blur.stops==1)
 f:update(1);assert(f.c.enabled and f.managers.blur.calls==1 and f.updates==2)
end)
test('typed core read fault suspends then resumes only after paced fresh proof',function()
 local f=fixture();local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);assert(f.c.enabled and not f.c.lease and f.suspends==1 and f.stops==0)
 local before=f.updates;f:update(.1);assert(f.updates==before and m.calls==1)
 m.fail=false;f:update(.25);assert(f.updates==before+1 and m.calls==2 and f.c.enabled)
end)
test('real Camera manager callback read health uses cleanup paced retry and fresh proof',function()
 local f=fixture();local Camera=dofile(root..'/src/first_person/camera.lua')
 local native={armed=true,error=0,owned=nil,begins=0,ends=0,pending=false}
 local helper={}
 function helper:begin(config)native.begins=native.begins+1;native.armed=true;native.owned={body=config.body};return true,native.owned end
 function helper:owned_handle()return native.owned end
 function helper:stats(handle)assert(handle==native.owned);return {armed=native.armed,error=native.error}end
 function helper:finish(handle)
  assert(handle==native.owned);native.ends=native.ends+1
  if native.pending then self.last_failure_code=13;return false,'Native cleanup pending'end
  native.owned=nil;native.error=0;return true,{armed=false,error=0}
 end
 function f.b:camera_config()
  if f.foreign or not f.safe then return nil,'Current camera is not eligible'end
  return {camera_kind=6,game=1,exe=2,context=3,camera=4,avatar_owner=5,avatar_index=0,avatar=6,body=f.body,camera_unit=8}
 end
 local camera=Camera.new(f.b,nil,helper);f:replace_manager('camera',camera)
 f:update(0);assert(native.begins==1 and camera:result().phase=='active')
 native.error=3;native.armed=false;native.pending=true;f:update(.01)
 assert(f.c.enabled and f.suspends==1 and not f.c.lease and native.begins==1)
 local row=f.recovery:snapshot().policies.camera;assert(row.phase=='cleanup'and row.pending_classification=='retry')
 local before=f.updates;f:update(.5);assert(f.updates==before and native.begins==1)
 native.pending=false;f:update(.6);assert(camera:is_clean());assert(f.recovery:snapshot().policies.camera.phase=='waiting')
 f:update(.7);assert(native.begins==1 and f.updates==before)
 f.safe=false;f:update(.85);assert(native.begins==1 and f.updates==before)
 f.safe=true;f:update(1.1);assert(native.begins==2 and f.c.enabled and camera:result().phase=='active')
 assert(f.stops==0 and camera:result().failure_kind==nil)
end)
test('cleanup refusal blocks all reacquisition until acknowledgement plus backoff',function()
 local f=fixture();local m=f.managers.fov;m.fail=true;m.cleanup_failures=2
 m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);local before=f.updates;assert(f.c.enabled and m.owned)
 f:update(.5);assert(f.updates==before and m.calls==1 and m.owned)
 f:update(1);assert(f.updates==before and not m.owned)
 m.fail=false;f:update(1.1);assert(f.updates==before)
 f:update(1.25);assert(f.updates==before+1 and m.calls==2)
end)
test('signature or unknown core faults stop and do not retry',function()
 for _,code in ipairs({0,5,7,8})do
  local f=fixture();local m=f.managers.fov;m.fail=true
  m.failure={failure_kind=code==0 and nil or'unsafe',failure_native_error=code,armed=false}
  f:update(0);assert(not f.c.enabled and f.stops==1 and f.suspends==0)
 end
end)
test('player changes after cleanup cannot authorize a delayed retry',function()
 local f=fixture();local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);local before=f.updates;f.player='new-body';m.fail=false
 f:update(.25);assert(f.updates==before and m.calls==1 and not f.c.lease)
 f.player='p';f:update(.5);assert(f.updates==before+1 and m.calls==2)
end)
test('explicit off prevents automatic reentry',function()
 local f=fixture();local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);f.c:stop();m.fail=false;f:update(1)
 assert(not f.c.enabled and not f.c.lease and f.suspends==1)
end)
test('a new body starts a fresh episode only after old cleanup and a later Update',function()
 local f=fixture();f.body=1;f.world=100000
 local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);local before=f.updates
 f.player='new-body';f.body=2;m.fail=false
 f:update(.1);assert(f.updates==before and not f.c.lease,'First cleanup frame cannot reenter')
 f:update(.2);assert(f.updates==before+1 and f.c.lease and f.c.player_owner=='new-body')
end)
test('healthy recovery performs no extra full snapshots across 100 Updates',function()
 local f=fixture()
 for i=1,100 do f:update(i*.016)end
 assert(f.full_snapshots==0,'Empty recovery must not generate proofs')
 assert(f.updates==100 and f.suspends==0 and f.stops==0)
 for _,name in ipairs({'fov','blur','camera','head','movement'})do assert(f.managers[name].calls==100)end
 local owner=f:read('recovery_owner')
 assert(owner.identity=='p'and owner.body==1 and owner.world==100000,'The acquired origin preserves the old owner without a read')
end)
test('healthy presentation sampling is reused without recovery reads',function()
 local f=fixture();f:enable_observer()
 -- Older/synthetic origins can omit the rig fields; the existing observer
 -- still supplies that owner proof without a separate backend read.
 f.c.lease.origin.body=nil;f.c.lease.origin.world=nil
 for i=1,100 do f:update(i*.016)end
 assert(f.full_snapshots==100,'Exactly the existing observer snapshot is needed')
 local owner=f:read('recovery_owner');assert(owner.identity=='p'and owner.body==1 and owner.world==100000)
 local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(2);local before=f.updates
 f.player='new-body';f.body=2;m.fail=false
 f:update(2.1);assert(f.updates==before and not f.c.lease,'Observer owner must survive the old lease being suspended')
 f:update(2.2);assert(f.updates==before+1 and f.c.player_owner=='new-body')
end)
test('a fault after healthy frames retains the original rig until later-frame cleanup',function()
 local f=fixture();f:update(0);f:update(.01)
 assert(f.full_snapshots==0)
 local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(.02);assert(f.full_snapshots==1,'A new fault still obtains a fresh classification proof')
 local owner=f:read('recovery_owner');assert(owner.identity=='p'and owner.body==1)
 f.player='new-body';f.body=2;m.fail=false;local before=f.updates
 f:update(.1);assert(f.updates==before and not f.c.lease)
 f:update(.2);assert(f.updates==before+1 and f.c.player_owner=='new-body')
end)
test('retry admission is sampled again after controller update changes ownership',function()
 local f=fixture();local m=f.managers.fov;m.fail=true;m.failure={failure_kind='temporary_read',failure_native_error=3,armed=false}
 f:update(0);m.fail=false
 local before=m.calls;local update=f.c.update
 function f.c:update()update(self);f.player='different-observation'end
 local snapshots=f.full_snapshots;f:update(.25)
 assert(m.calls==before,'An outer-loop proof cannot authorize the later retry')
 assert(f.full_snapshots-snapshots==3,'Owner observation and both retry boundaries must remain fresh')
 assert(f.recovery:snapshot().policies.fov.phase=='waiting_proof')
end)
test('unavailable optional rows do not request retry proofs',function()
 local f=fixture();f.managers.blur.fail=true;f:update(0)
 local before=f.full_snapshots;f:update(.1)
 assert(f.full_snapshots-before==1,'Only new-body observation remains for an outstanding fault ledger')
 assert(f.managers.blur.calls==1 and f.c.enabled)
end)
print('Real runtime recovery orchestration: '..cases..' cases passed')
