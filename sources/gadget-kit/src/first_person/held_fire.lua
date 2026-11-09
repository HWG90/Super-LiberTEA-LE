local P=mod.require('src/first_person/compat51.lua')
-- A data-slot reservation filters only the owned body's native hipfire events.
-- Publication is separately authorized; this module never sets animation state
-- or gameplay input, and cannot authorize Source's animation-state setter.
local Host=mod
local M,Adapter={},{}
Adapter.__index=Adapter
local CONFIG={'game','exe','context','camera','avatar_owner','request','registry','units','generations',
 'body_object','instance','graph','native_world','avatar_index','avatar','body','ttl_ms'}
local STATS={'generation','deadline_ms','now_ms','seen','forwarded','suppressed_start','suppressed_end','rejected',
 'publications','pauses','in_flight','last_caller','body','body_generation','body_object','instance','graph',
 'context','camera','request','last_event','error'}
function Adapter.new(profile)return setmetatable({profile=profile,owned=nil},Adapter)end
function Adapter:_load()
 if self.library then return self.library end
 local ffi=P.ffi
 assert(ffi.os=='Windows'and ffi.abi('64bit'),'Windows x64 required for held-fire filter')
 if not pcall(ffi.typeof,'NADSHF_Config')then ffi.cdef([[
  typedef struct NADSHF_Config {
   uint32_t size,abi;
   uint64_t game,exe,context,camera,avatar_owner,request;
   uint64_t registry,units,generations,body_object,instance,graph,native_world;
   uint32_t avatar_index,avatar,body,ttl_ms;
   uint64_t reserved[2];
  } NADSHF_Config;
  typedef struct NADSHF_Stats {
   uint32_t size,abi,installed,armed,error,effective_armed,body,body_generation;
   uint64_t generation,deadline_ms,now_ms,seen,forwarded,suppressed_start,suppressed_end;
   uint64_t rejected,publications,pauses,in_flight,last_caller;
   uint64_t body_object,instance,graph,context,camera,request;
   uint32_t last_event,reserved;
  } NADSHF_Stats;
  uint32_t NADSHF_Begin(const NADSHF_Config*,uint64_t*);
  uint32_t NADSHF_Publish(uint64_t,const NADSHF_Config*);
  uint32_t NADSHF_Pause(uint64_t);
  uint32_t NADSHF_End(uint64_t);
  uint32_t NADSHF_ReadStats(uint64_t,NADSHF_Stats*);
  uint32_t NADSHF_Error(void);
  uint32_t NADSHF_LastError(void);
 ]])end
 assert(ffi.sizeof('NADSHF_Config')==144 and ffi.sizeof('NADSHF_Stats')==184,'Held-fire helper ABI mismatch')
 assert(self.profile and self.profile.abi==1 and P.kind(self.profile.library)=='string','Held-fire helper profile unavailable')
 assert(P.kind(Host.dir)=='string','Held-fire helper directory unavailable')
 self.ffi=ffi;self.library=ffi.load(Host.dir..'/'..self.profile.library)
 -- The callback can outlive a refused End. Keep the DLL loaded for the mod's
 -- entire scope, including partial Begin and foreign slot replacement.
 if P.kind(Host.scope)=='table'then
  Host.scope.native_ads_held_fire_libraries=Host.scope.native_ads_held_fire_libraries or{}
  table.insert(Host.scope.native_ads_held_fire_libraries,self.library)
 end
 return self.library
end
function Adapter:_error(operation)
 local ok,code=pcall(function()return P.number(self:_load().NADSHF_Error())end)
 return operation..' failed (native held-fire code '..tostring(ok and code or'unavailable')..')'
end
function Adapter:_config(value)
 self:_load();local c=self.ffi.new('NADSHF_Config');c.size=144;c.abi=1
 c.reserved[0]=0;c.reserved[1]=0
 for _,key in ipairs(CONFIG)do c[key]=assert(value[key],key..' unavailable')end
 return c
end
function Adapter:owned_handle()return self.owned end
function Adapter:begin(config)
 if self.owned then return false,'Held-fire generation still requires cleanup'end
 local library=self:_load();local c=self:_config(config)
 local handle={owner=self,disarmed=false,generation=self.ffi.new('uint64_t[1]')}
 local called,result=pcall(library.NADSHF_Begin,c,handle.generation)
 if P.number(handle.generation[0])~=0 then self.owned=handle end
 if not called then return false,'Held-fire Begin result uncertain: '..tostring(result)end
 result=P.number(result)
 if result~=1 or not self.owned then return false,self:_error(result==2 and'Held-fire partial installation'or'Held-fire Begin')end
 return true,handle
end
function Adapter:_owned(handle)
 return P.kind(handle)=='table'and handle.owner==self and self.owned==handle and not handle.disarmed
end
function Adapter:publish(handle,config)
 if not self:_owned(handle)then return false,'Held-fire publication handle is not owned'end
 if P.number(self:_load().NADSHF_Publish(handle.generation[0],self:_config(config)))~=1 then return false,self:_error('Held-fire publication')end
 return true
end
function Adapter:pause(handle)
 if not self:_owned(handle)then return false,'Held-fire pause handle is not owned'end
 if P.number(self:_load().NADSHF_Pause(handle.generation[0]))~=1 then return false,self:_error('Held-fire pause')end
 return true
end
function Adapter:stats(handle)
 if not self:_owned(handle)then return nil,'Held-fire statistics handle is not owned'end
 local s=self.ffi.new('NADSHF_Stats');s.size=184;s.abi=1
 if P.number(self:_load().NADSHF_ReadStats(handle.generation[0],s))~=1 then return nil,self:_error('Held-fire statistics')end
 if P.number(s.size)~=184 or P.number(s.abi)~=1 then return nil,'Held-fire statistics ABI changed'end
 if P.number(s.generation)~=P.number(handle.generation[0])then return nil,'Held-fire statistics generation changed'end
 local out={installed=P.number(s.installed)==1,armed=P.number(s.armed)==1,effective_armed=P.number(s.effective_armed)==1}
 for _,key in ipairs(STATS)do out[key]=P.number(s[key])end
 return out
end
function Adapter:finish(handle)
 if P.kind(handle)~='table'or handle.owner~=self then return false,'Held-fire cleanup handle is not owned'end
 if handle.disarmed then return true end
 if self.owned~=handle then return false,'Held-fire generation ownership changed'end
 if P.number(self:_load().NADSHF_End(handle.generation[0]))~=1 then return false,self:_error('Held-fire cleanup')end
 handle.disarmed=true;self.owned=nil;return true
end
local function invoke(target,name,...)
 local ok,a,b=pcall(target[name],target,...)
 if not ok then return nil,tostring(a)end
 return a,b
end
local function integer(n,lo,hi)return P.kind(n)=='number'and n==n and n%1==0 and n>=lo and n<=hi end
local function flag(s,byte,bit)return math.floor(s.flags:byte(byte)/2^bit)%2==1 end
local function token(s,c,instance,graph,resource)
 local parts={}
 for _,key in ipairs({'base','world','avatar_owner','avatar_index','avatar','body','avatar_descriptor'})do parts[#parts+1]=tostring(s[key])end
 for _,v in ipairs({c.unit,c.object,c.generation,instance,graph,resource})do parts[#parts+1]=tostring(v)end
 return table.concat(parts,':')
end
local function normal(s)
 return P.kind(s)=='table'and s.safe==true and s.camera_kind==4 and not s.controller_active and not s.weapon_transition
  and not s.aiming and not s.shoulder_aim and not s.reloading and P.kind(s.flags)=='string'and #s.flags==24
  and not(flag(s,7,0)or flag(s,11,2)or flag(s,16,5)or flag(s,16,1)or flag(s,10,2))
end
function M.new(b,options)
 options=options or{}
 assert(P.kind(b)=='table'and P.kind(options.authorized)=='function','Held-fire private Update authority required')
 local self={handle=nil,phase='idle',last={},closing=false};local helper=options.helper
 local function log(why)
  why=tostring(why)
  if why~=self.fault and P.kind(options.log)=='function'then pcall(options.log,'Held fire: '..why)end
  self.fault=why;return false,why
 end
 local function authorized(admission,context)
  if P.kind(context)~='table'or context.phase~='qualified_update'or not integer(context.tick,1,9007199254740991)
   or P.kind(admission)~='table'or admission.tick~=context.tick then return false end
  local ok,value=pcall(options.authorized,context)
  return ok and value==true and b.frame_active==true
 end
 local function config(admission)
  assert(integer(admission.body_ref,1,0xfffffffe)and integer(admission.body_generation,0,255)
   and admission.body_generation==math.floor(admission.body_ref/0x400000)%256
   and P.kind(admission.owner_token)=='string'and #admission.owner_token>0,'Held-fire body admission unavailable')
  local epoch=b.frame_epoch
  local s,why=b:snapshot();assert(normal(s),why or'Held-fire requires the released normal camera')
  if b.foreign_camera then assert(b.foreign_camera()==false,'Held-fire foreign camera active')end
  local c=b:_alignment_context({viewmodel=s.body,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index})
  local exe=b:_alignment_executable();assert(c.exe==exe and c.unit==s.body and c.unit==admission.body_ref
   and c.generation==admission.body_generation,'Held-fire body generation changed')
  local function valid()
   assert(b:_u8(c.generations+c.index)==c.generation and b:_ptr(c.units+c.index*8)==c.object
    and b:_u32(c.object+8)==c.unit,'Held-fire body registry retired')
  end
  valid()
  local resource=b:_read(c.object+0x358,8)
  assert(resource=='\151\250\77\41\77\51\28\77'and b:_u32(c.object+0x70)==107,'Held-fire body resource changed')
  local instance=b:_ptr(c.object+0x178);local graph=b:_ptr(instance+0x28);local world=b:_ptr(c.object+0x18)
  assert(integer(instance,65536,2^47-1)and integer(graph,65536,2^47-1)and integer(world,65536,2^47-1),'Held-fire body graph unavailable')
  local a=assert(b.actions:sample(s,{1,3,4,14,24,25}))
  assert(a.resource_match==true and a.layer_count==31 and #a.unknown_layers==0 and a.body_object==c.object
   and a.instance==instance and a.graph==graph and b:on_foot(s,a)==true,'Held-fire action graph unavailable')
  assert(a.states[4]==59 and(a.states[24]==1 or a.states[24]==6)and a.states[25]==1,'Held-fire aimed target is not current')
  assert(not((a.l14==36 or a.l14==3)and(a.l3==71 or a.l14==3 and a.l3==68 and(a.l1==75 or a.l1==78))),
   'Held-fire native sprint owns the body')
  assert(token(s,c,instance,graph,resource)==admission.owner_token,'Held-fire body owner token changed')
  -- Firing bits may advance. Every closing observation must independently
  -- remain eligible, while body/camera/request ownership stays unchanged.
  local after,problem=b:snapshot();assert(normal(after),problem or'Held-fire action changed during publication')
  for _,key in ipairs({'base','world','context','camera','record','avatar_owner','avatar_index','avatar','avatar_descriptor',
   'body','weapon','weapon_unit','weapon_descriptor','identity','player_identity','controller'})do
   assert(after[key]==s[key],'Held-fire player/camera changed during publication: '..key)
  end
  if b.foreign_camera then assert(b.foreign_camera()==false,'Held-fire foreign camera changed')end
  local fresh=b:_alignment_context({viewmodel=after.body,avatar_owner=after.avatar_owner,avatar_index=after.avatar_index})
  for _,key in ipairs({'exe','unit','object','index','generation','registry','units','generations'})do
   assert(fresh[key]==c[key],'Held-fire registry context changed during publication: '..key)
  end
  valid();assert(b:_ptr(c.object+0x178)==instance and b:_ptr(instance+0x28)==graph and b:_ptr(c.object+0x18)==world
   and b:_read(c.object+0x358,8)==resource,'Held-fire body graph changed during publication')
  local final=assert(b.actions:sample(after,{4,24,25}))
  assert(final.resource_match==true and final.layer_count==31 and #final.unknown_layers==0 and final.instance==instance
   and final.graph==graph and final.body_object==c.object and final.states[4]==59
   and(final.states[24]==1 or final.states[24]==6)and final.states[25]==1,'Held-fire aimed target changed during publication')
  assert(b.frame_active==true and b.frame_epoch==epoch,'Held-fire Update frame retired during publication')
  return{game=s.base,exe=exe,context=s.context,camera=s.camera,avatar_owner=s.avatar_owner,request=s.record,
   registry=c.registry,units=c.units,generations=c.generations,body_object=c.object,instance=instance,graph=graph,
   native_world=world,avatar_index=s.avatar_index,avatar=s.avatar,body=s.body,ttl_ms=250}
 end
 local function get_helper()
  if not helper then
   local profile=options.profile or assert(Host.require('src/first_person/profile.lua').held_fire,'Held-fire profile unavailable')
   helper=Adapter.new(profile)
  end
  return helper
 end
 function self:is_clean()return self.handle==nil end
 function self:result()
  local out={};for k,v in pairs(self.last)do out[k]=v end
  out.phase=self.phase;out.owned=self.handle~=nil;out.cleanup_pending=self.cleanup_only==true
  out.armed=out.armed==true and self.phase=='active'and self.binding~=nil
  out.effective_armed=out.effective_armed==true and out.armed
  out.error_message=self.fault;return out
 end
 function self:pause()
  local already=self.phase=='paused'and not self.cleanup_only
  self.binding=nil
  if not self.handle then self.phase='idle';return true end
  if already then return true end
  local done,why=invoke(helper,'pause',self.handle)
  if done~=true then self.cleanup_only=true;self.phase='cleanup_pending';return log(why or'Held-fire pause pending')end
  self.phase=self.cleanup_only and'cleanup_pending'or'paused';return true
 end
 function self:stop()
  self.binding=nil
  if not self.handle then self.phase='idle';self.cleanup_only=nil;return true end
  -- End also disarms; attempt it even if Pause's drain was refused.
  invoke(helper,'pause',self.handle)
  local done,why=invoke(helper,'finish',self.handle)
  if done~=true then self.cleanup_only=true;self.phase='cleanup_pending';return log(why or'Held-fire cleanup pending')end
  self.handle=nil;self.cleanup_only=nil;self.phase='idle';return true
 end
 function self:shutdown()self.closing=true;return self:stop()end
 local function healthy(stats,c,admission)
  if P.kind(stats)~='table'or stats.installed~=true or stats.armed~=true or stats.effective_armed~=true or stats.error~=0
   or stats.body~=admission.body_ref or stats.body_generation~=admission.body_generation
   or not integer(stats.deadline_ms,1,9007199254740991)or not integer(stats.now_ms,0,9007199254740991)
   or stats.deadline_ms<=stats.now_ms then return false end
  for _,key in ipairs({'body_object','instance','graph','context','camera','request'})do if stats[key]~=c[key]then return false end end
  return true
 end
 function self:matches(admission,context)
  if self.closing or self.cleanup_only or not self.handle or not self.binding or not authorized(admission,context)then return false end
  if admission.owner_token~=self.binding.owner_token or admission.body_ref~=self.binding.body_ref
   or admission.body_generation~=self.binding.body_generation then return false end
  local ok,c=pcall(config,admission);if not ok then return false end
  local stats=invoke(helper,'stats',self.handle)
  if not healthy(stats,c,admission)or not authorized(admission,context)then return false end
  self.last=stats;return true
 end
 function self:update(admission,context)
  if admission==nil then return self:pause()end
  if self.closing then self:pause();return false,'Held-fire filter is shutting down'end
  if self.cleanup_only then return false,self.fault or'Held-fire filter cleanup is pending'end
  if not authorized(admission,context)then self:pause();return log('Held-fire publication requires private Update authority')end
  local ok,c=pcall(config,admission)
  if not ok then self:pause();return log(c)end
  -- Fresh reads may revalidate module ownership. They cannot change the
  -- caller's private context or retire its frame before publication.
  if not authorized(admission,context)then self:pause();return log('Held-fire Update authority retired during validation')end
  local loaded,h=pcall(get_helper)
  if not loaded then self:pause();return log(h)end
  local done,why
  if not self.handle then
   done,why=invoke(h,'begin',c)
   self.handle=done==true and why or invoke(h,'owned_handle')
  else done,why=invoke(h,'publish',self.handle,c)end
  if done~=true or not self.handle then
   self:pause();self.cleanup_only=self.handle~=nil;self.phase=self.handle and'cleanup_pending'or'idle'
   return log(why or'Held-fire publication refused')
  end
  self.binding={owner_token=admission.owner_token,body_ref=admission.body_ref,body_generation=admission.body_generation}
  local stats,problem=invoke(h,'stats',self.handle)
  if not healthy(stats,c,admission)or not authorized(admission,context)then
   self:pause();self.cleanup_only=true;self.phase='cleanup_pending';return log(problem or'Held-fire admission not acknowledged')
  end
  self.last=stats;self.phase='active';self.fault=nil;return true
 end
 return self
end
M.Adapter=Adapter
return M
