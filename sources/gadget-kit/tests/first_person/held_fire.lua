local ROOT=NATIVE_ADS_TEST_ROOT or'.'
local base=TEST_PORT51 or{ffi=require('ffi'),number=tonumber,kind=type}
local loads,profiles,native=0,0,nil
local ffi=setmetatable({os='Windows',load=function()loads=loads+1;return assert(native)end},{__index=base.ffi})
local P={ffi=ffi,number=base.number,kind=base.kind}
local host={dir='mock-mod',scope={}}
function host.require(path)
 if path=='src/first_person/compat51.lua'then return P end
 if path=='src/first_person/profile.lua'then profiles=profiles+1;return{held_fire={abi=1,library='native/mock-held-fire.dll'}}end
 error('Unexpected held-fire dependency '..tostring(path))
end
mod=host
local Held=dofile(ROOT..'/src/first_person/held_fire.lua')
local passed=0
local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));passed=passed+1 end
local function same(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function copy(t)local x={};for k,v in pairs(t)do x[k]=v end;return x end
local function fixture()
 local f={reads=0,samples=0,begin=0,publish=0,pause=0,finish=0,stats=0,profile={abi=1,library='native/mock-held-fire.dll'}}
 f.c={exe=0x140000000,unit=3*0x400000+123,generation=3,index=123,registry=0x900000,
  units=0x910000,generations=0x920000,object=0x100000}
 f.instance,f.graph,f.world=0x200000,0x300000,0x400000
 f.s={base=0x700000,world=0x710000,context=0x720000,camera=0x730000,record=0x740000,
  avatar_owner=0x750000,avatar_index=0,avatar=8,avatar_descriptor=string.rep('a',20),body=f.c.unit,
  weapon=9,weapon_unit=10,weapon_descriptor=string.rep('w',20),identity='weapon/camera',player_identity='player/camera',
  controller=0x760000,safe=true,camera_kind=4,controller_active=false,flags=string.rep('\0',24)}
 f.layers={[4]=59,[24]=1,[25]=1}
 local function owner()
  local t={};for _,k in ipairs({'base','world','avatar_owner','avatar_index','avatar','body','avatar_descriptor'})do t[#t+1]=tostring(f.s[k])end
  for _,v in ipairs({f.c.unit,f.c.object,f.c.generation,f.instance,f.graph,'\151\250\77\41\77\51\28\77'})do t[#t+1]=tostring(v)end
  return table.concat(t,':')
 end
 local b={frame_active=true,frame_epoch=1}
 function b:snapshot()f.reads=f.reads+1;if f.on_snapshot then f:on_snapshot()end;if f.no_snapshot then return nil,'No current snapshot'end;return copy(f.s)end
 function b:_alignment_context()return copy(f.c)end
 function b:_alignment_executable()return f.c.exe end
 function b:_u8(at)assert(at==f.c.generations+f.c.index);return f.retired and 4 or f.c.generation end
 function b:_u32(at)if at==f.c.object+8 then return f.c.unit end;assert(at==f.c.object+0x70);return 107 end
 function b:_ptr(at)
  local t={[f.c.units+f.c.index*8]=f.c.object,[f.c.object+0x178]=f.instance,[f.instance+0x28]=f.graph,[f.c.object+0x18]=f.world}
  return assert(t[at],'Unexpected pointer read')
 end
 function b:_read(at,n)assert(at==f.c.object+0x358 and n==8);return f.bad_resource and string.rep('\0',8)or'\151\250\77\41\77\51\28\77'end
 function b.foreign_camera()return f.foreign or false end
 function b:on_foot()return not f.off_foot end
 b.actions={sample=function()
  f.samples=f.samples+1;if f.on_actions then f:on_actions()end
  return{resource_match=not f.bad_graph,layer_count=31,unknown_layers=f.unknown and{4}or{},body_object=f.c.object,
   instance=f.instance,graph=f.graph,states=copy(f.layers),l14=36,l3=f.sprint and 71 or 67,l1=59}
 end}
 local h={}
 function h:owned_handle()return self.owned end
 function h:begin(config)
  f.begin=f.begin+1;self.config=copy(config);self.owned={token=17};self.armed=true
  if f.begin_throw then error('Begin threw after installation')end
  if f.begin_fail then return false,'Partial Begin'end
  return true,self.owned
 end
 function h:publish(handle,config)
  same(handle,self.owned);f.publish=f.publish+1;self.config=copy(config);self.armed=true
  if f.publish_throw then error('Publish threw')end
  return not f.publish_fail,'Publish refused'
 end
 function h:pause(handle)
  same(handle,self.owned);f.pause=f.pause+1
  if f.pause_throw then error('Pause threw')end
  if f.pause_fail then return false,'Pause pending'end
  self.armed=false;return true
 end
 function h:finish(handle)
  same(handle,self.owned);f.finish=f.finish+1
  if f.end_throw then error('End threw')end
  if f.end_fail then return false,'End pending'end
  self.owned=nil;self.armed=false;return true
 end
 function h:stats(handle)
  same(handle,self.owned);f.stats=f.stats+1
  if f.on_stats then f:on_stats()end
  if f.stats_throw then error('Stats threw')end
  if f.stats_fail then return nil,'Stats unavailable'end
  local s=copy(self.config);s.installed=true;s.armed=self.armed;s.effective_armed=self.armed
  s.error=0;s.body_generation=f.c.generation;s.now_ms=1000;s.deadline_ms=1250
  for k,v in pairs(f.stats_override or{})do s[k]=v end
  return s
 end
 f.b,f.h=b,h
 function f:step()
  self.tick=(self.tick or 0)+1;self.context={phase='qualified_update',tick=self.tick}
  self.admission={body_ref=self.c.unit,body_generation=self.c.generation,owner_token=owner(),tick=self.tick}
  return self.admission,self.context
 end
 f:step()
 f.m=Held.new(b,{helper=h,profile=f.profile,authorized=function(context)return context==f.context end})
 function f:start()local done,why=self.m:update(self.admission,self.context);assert(done,why)end
 return f
end

test('private authority is mandatory and idle work never loads native code',function()
 assert(not pcall(Held.new,{},{}));local before=loads;local before_profiles=profiles
 local f=fixture();assert(f.m:update(nil));assert(not f.m:matches(f.admission,f.context));assert(f.m:stop())
 same(loads,before);same(profiles,before_profiles);same(f.begin,0);same(f.reads,0)
end)
test('one lease publishes across firing and accepts live previous-frame admission',function()
 local f=fixture();f:start();local handle=f.m.handle
 for i=1,12 do
  f:step();f.s.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11)
  assert(f.m:matches(f.admission,f.context));f:start();same(f.m.handle,handle)
 end
 same(f.begin,1);same(f.publish,12);same(f.pause,0);same(f.finish,0);assert(not f.m:is_clean())
end)
test('pause preserves the slot and resumes without another Begin',function()
 local f=fixture();f:start();assert(f.m:update(nil,f.context));assert(not f.m:is_clean()and f.m:result().phase=='paused')
 assert(not f.m:matches(f.admission,f.context));assert(f.m:update(nil));same(f.pause,1)
 f:step();f:start();same(f.begin,1);same(f.publish,1);same(f.finish,0)
end)
test('stop drains before cleanup and is idempotent',function()
 local f=fixture();f:start();assert(f.m:stop());assert(f.m:is_clean());same(f.pause,1);same(f.finish,1)
 assert(f.m:stop());same(f.finish,1);f:step();f:start();same(f.begin,2)
 assert(f.m:shutdown());f:step();assert(not f.m:update(f.admission,f.context));same(f.begin,2)
end)
test('phase text and stale ticks cannot authorize publication',function()
 local f=fixture();local fake={phase='qualified_update',tick=f.context.tick}
 assert(not f.m:update(f.admission,fake));same(f.begin,0)
 f:start();f.admission.tick=0;assert(not f.m:matches(f.admission,f.context));assert(not f.m:update(f.admission,f.context));same(f.pause,1)
end)
test('admission body reference generation and owner token are independently checked',function()
 for _,change in ipairs({function(f)f.admission.body_ref=f.admission.body_ref+1 end,
  function(f)f.admission.body_generation=4 end,function(f)f.admission.owner_token='wrong owner'end})do
  local f=fixture();change(f);assert(not f.m:update(f.admission,f.context));same(f.begin,0)
 end
end)
test('native actions and foreign cameras pause before publication',function()
 for _,change in ipairs({function(f)f.s.aiming=true end,function(f)f.s.shoulder_aim=true end,
  function(f)f.s.reloading=true end,function(f)f.s.weapon_transition=true end,function(f)f.s.controller_active=true end,
  function(f)f.s.camera_kind=6 end,function(f)f.foreign=true end,function(f)f.sprint=true end,
  function(f)f.s.flags=string.rep('\0',10)..string.char(4)..string.rep('\0',13)end})do
  local f=fixture();f:start();change(f);assert(not f.m:matches(f.admission,f.context));assert(not f.m:update(f.admission,f.context))
  same(f.pause,1);same(f.publish,0);assert(not f.m:is_clean())
 end
end)
test('target59 and both aimed24 variants are required',function()
 local f=fixture();f.layers[24]=6;f:start();assert(f.m:matches(f.admission,f.context))
 for _,pair in ipairs({{4,60},{24,0},{24,5},{25,3}})do
  f=fixture();f:start();f.layers[pair[1]]=pair[2];assert(not f.m:update(f.admission,f.context));same(f.pause,1)
 end
end)
test('unknown graph owner or missing snapshot cannot publish',function()
 for _,key in ipairs({'bad_graph','unknown','bad_resource','retired','off_foot','no_snapshot'})do
  local f=fixture();f:start();f[key]=true;assert(not f.m:update(f.admission,f.context));same(f.publish,0);same(f.pause,1)
 end
end)
test('closing snapshot and frame drift refuse before Begin',function()
 for _,change in ipairs({function(f)f.s.camera=f.s.camera+1 end,function(f)f.s.reloading=true end,
  function(f)f.b.frame_epoch=f.b.frame_epoch+1 end,function(f)f.c.units=f.c.units+16 end})do
  local f=fixture();function f:on_snapshot()if self.reads==2 then change(self)end end
  assert(not f.m:update(f.admission,f.context));same(f.begin,0)
 end
end)
test('native health expiry and binding identity must remain positive',function()
 for _,override in ipairs({{installed=false},{armed=false},{effective_armed=false},{error=1},
  {deadline_ms=1000},{body=1},{body_generation=4},{graph=0x888888},{camera=0x999999}})do
  local f=fixture();f:start();f.stats_override=override;assert(not f.m:matches(f.admission,f.context));same(f.publish,0)
 end
end)
test('bad acknowledgement pauses the retained token',function()
 local f=fixture();f.stats_override={graph=1};assert(not f.m:update(f.admission,f.context))
 assert(not f.m:is_clean()and f.m:result().cleanup_pending);same(f.pause,1);assert(f.m:stop())
end)
test('partial or throwing Begin retains cleanup ownership',function()
 for _,key in ipairs({'begin_fail','begin_throw'})do
  local f=fixture();f[key]=true;assert(not f.m:update(f.admission,f.context))
  assert(not f.m:is_clean()and f.m:result().cleanup_pending);same(f.pause,1);assert(f.m:stop())
 end
end)
test('publication and statistics errors pause without losing the handle',function()
 for _,key in ipairs({'publish_fail','publish_throw','stats_fail','stats_throw'})do
  local f=fixture();f:start();f[key]=true;assert(not f.m:update(f.admission,f.context))
  assert(not f.m:is_clean()and f.m:result().cleanup_pending);same(f.pause,1);assert(f.m:stop())
 end
end)
test('failed Pause and End retain ownership until successful End',function()
 for _,key in ipairs({'pause_fail','pause_throw'})do
  local f=fixture();f:start();f[key]=true;assert(not f.m:pause());assert(not f.m:is_clean());assert(f.m:stop());same(f.finish,1)
 end
 for _,key in ipairs({'end_fail','end_throw'})do
  local f=fixture();f:start();f[key]=true;assert(not f.m:stop());assert(not f.m:is_clean());f[key]=false;assert(f.m:stop());same(f.finish,2)
 end
end)
test('matches is read-only and cannot load reinstall or publish',function()
 local f=fixture();assert(not f.m:matches(f.admission,f.context));same(f.reads,0)
 f:start();local counts={f.begin,f.publish,f.pause,f.finish};assert(f.m:matches(f.admission,f.context))
 same(f.begin,counts[1]);same(f.publish,counts[2]);same(f.pause,counts[3]);same(f.finish,counts[4])
end)
test('authority retirement during native acknowledgement cannot remain armed',function()
 local f=fixture();f:start();function f:on_stats()self.context={}end
 assert(not f.m:matches(f.admission,f.context));same(f.pause,0)
 f=fixture();function f:on_stats()self.context={}end
 assert(not f.m:update(f.admission,f.context));same(f.pause,1);assert(f.m:result().cleanup_pending)
 assert(f.m:stop())
end)

test('actual FFI ABI layout and lazy DLL scope retention',function()
 local value=fixture();local c
 native={NADSHF_Begin=function(config,out)c=config;out[0]=23;return 1 end,
  NADSHF_Publish=function()return 1 end,NADSHF_Pause=function()return 1 end,NADSHF_End=function()return 1 end,
  NADSHF_Error=function()return 0 end,NADSHF_ReadStats=function(_,s)
   s.generation=23;s.installed=1;s.armed=1;s.effective_armed=1;s.body=value.c.unit;s.body_generation=3
   return 1
  end}
 local a=Held.Adapter.new(value.profile);local config={}
 for _,key in ipairs({'game','exe','context','camera','avatar_owner','request','registry','units','generations',
  'body_object','instance','graph','native_world','avatar_index','avatar','body','ttl_ms'})do config[key]=1 end
 config.body=value.c.unit;config.ttl_ms=250
 local before=loads;local done,handle=a:begin(config);assert(done,handle);same(loads,before+1)
 same(ffi.sizeof('NADSHF_Config'),144);same(ffi.sizeof('NADSHF_Stats'),184)
 same(ffi.offsetof('NADSHF_Config','ttl_ms'),124);same(ffi.offsetof('NADSHF_Stats','generation'),32)
 same(ffi.offsetof('NADSHF_Stats','last_event'),176)
 same(P.number(c.size),144);same(P.number(c.abi),1);same(P.number(c.reserved[0]),0);same(P.number(c.reserved[1]),0)
 same(P.number(c.body),value.c.unit);same(P.number(c.ttl_ms),250)
 assert(a:stats(handle));assert(a:publish(handle,config));assert(a:pause(handle));assert(a:finish(handle));assert(a:finish(handle))
 same(#host.scope.native_ads_held_fire_libraries,1);same(loads,before+1)
end)
local function native_fixture()
 local f={token=31,begin_result=1,publish_result=1,pause_result=1,end_result=1,read_result=1,ends=0,begins=0}
 native={NADSHF_Error=function()return 7 end,
  NADSHF_Begin=function(c,out)
   f.begins=f.begins+1;f.c=c;out[0]=f.no_token and 0 or f.token
   if f.begin_throw then error('Native Begin threw after token publication')end
   return f.begin_result
  end,
  NADSHF_Publish=function(_,c)f.c=c;return f.publish_result end,
  NADSHF_Pause=function()return f.pause_result end,
  NADSHF_End=function()f.ends=f.ends+1;if f.end_throw then error('Native End threw')end;return f.end_result end,
  NADSHF_ReadStats=function(_,s)
   s.size=f.bad_size and 1 or 184;s.abi=1;s.generation=f.bad_generation and 999 or f.token
   s.installed=1;s.armed=1;s.effective_armed=1;s.body=f.c.body;s.body_generation=3;s.now_ms=1000;s.deadline_ms=1250
   for _,key in ipairs({'body_object','instance','graph','context','camera','request'})do s[key]=f.c[key]end
   return f.read_result
  end}
 f.a=Held.Adapter.new({abi=1,library='native/mock-held-fire.dll'})
 f.config={}
 for _,key in ipairs({'game','exe','context','camera','avatar_owner','request','registry','units','generations',
  'body_object','instance','graph','native_world','avatar_index','avatar','body','ttl_ms'})do f.config[key]=1 end
 return f
end
test('native partial Begin and thrown Begin keep the exact token and DLL pinned',function()
 for _,key in ipairs({'partial','throw'})do
  local f=native_fixture();if key=='partial'then f.begin_result=2 else f.begin_throw=true end
  local before=#host.scope.native_ads_held_fire_libraries
  assert(not f.a:begin(f.config));local handle=assert(f.a:owned_handle());same(P.number(handle.generation[0]),31)
  same(#host.scope.native_ads_held_fire_libraries,before+1);assert(f.a:finish(handle));same(f.ends,1)
 end
end)
test('native success without an output token cannot create a false clean lease',function()
 local f=native_fixture();f.no_token=true;assert(not f.a:begin(f.config));assert(f.a:owned_handle()==nil)
end)
test('native End pending or throwing retains its original handle',function()
 local f=native_fixture();local done,h=f.a:begin(f.config);assert(done)
 f.end_result=2;assert(not f.a:finish(h));same(f.a:owned_handle(),h);assert(not h.disarmed)
 f.end_result=1;f.end_throw=true;assert(not pcall(f.a.finish,f.a,h));same(f.a:owned_handle(),h)
 f.end_throw=false;assert(f.a:finish(h));assert(h.disarmed and f.a:owned_handle()==nil);same(f.ends,3)
end)
test('native statistics must acknowledge ABI and the exact generation',function()
 local f=native_fixture();local done,h=f.a:begin(f.config);assert(done)
 f.bad_generation=true;assert(f.a:stats(h)==nil);f.bad_generation=false
 f.bad_size=true;assert(f.a:stats(h)==nil);f.bad_size=false
 f.read_result=0;assert(f.a:stats(h)==nil);f.read_result=1;assert(f.a:stats(h));assert(f.a:finish(h))
end)
test('default profile and DLL load only at first valid admission',function()
 local n=native_fixture();local f=fixture();local before_loads,before_profiles=loads,profiles
 f.m=Held.new(f.b,{authorized=function(c)return c==f.context end})
 assert(f.m:update(nil));assert(not f.m:matches(f.admission,f.context));same(loads,before_loads);same(profiles,before_profiles)
 f:start();same(profiles,before_profiles+1);same(loads,before_loads+1);same(n.begins,1)
 assert(f.m:matches(f.admission,f.context));assert(f.m:stop());same(n.ends,1)
end)
print('Held-fire Lua admission/filter lifecycle: '..passed..' cases passed (no engine calls)')
