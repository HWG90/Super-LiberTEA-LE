-- Lease the same aim-mode byte the native input handler reads. The game owns
-- button handling, ADS entry/exit, sights and zoom; no input is synthesized.
local M={}
local function same(a,b)return a and b and a.key==b.key and a.at==b.at and a.descriptor==b.descriptor end
function M.source(b,memory)
 local self={};local writer
 local function hex(s)return(s:gsub('%x%x',function(v)return string.char(tonumber(v,16))end))end
 local function context(s,weapon,read_mode)
  local base=s.base;local player=b:_ptr(base+0x2ce1618)
  local settings=b:_ptr(s.avatar_owner+0x40);local mode=read_mode or b:_u32(settings+0xf0);assert(mode<=3,'Native aim memory mode changed')
  local r={base=base,player=player,settings=settings,mode=mode,owner=s.player_identity,weapon=weapon}
  if mode==1 or mode==3 then
   local pool=b:_ptr(base+0x2ce1ea0);local index=b:_map(pool+0x30,weapon)
   local descriptor=b:_ptr(b:_ptr(pool+0x48)+index*8);local bytes=b:_read(descriptor,20)
   assert(b:_u32(descriptor+8)==weapon,'Native weapon aim descriptor changed')
   r.pool,r.descriptor,r.descriptor_at=pool,bytes,descriptor
   r.at=b:_ptr(pool+0x50)+index*2;r.key=s.player_identity..':weapon:'..weapon
  else
   assert(b:_u32(player+0x88)>0,'Native local input unavailable')
   local selected=b:_ptr(player+0xe8);local entity=b:_u32(selected+8);local index=b:_map(player+0xd0,entity,8)
   r.selected,r.entity,r.descriptor=selected,entity,b:_read(selected,20)
   r.at=player+0x2ec+index*0x38;r.key=s.player_identity..':input:'..entity
  end
  r.value=b:_u8(r.at);assert(r.value==0 or r.value==1,'Native aim preference is not Boolean')
  return r
 end
 function self:probe()
  local s,why=b:snapshot();assert(s,why);assert(s.safe and(s.camera_kind==6 or s.camera_kind==4),'Native aim owner unavailable')
  for at,bytes in pairs({[0xa5ced3]='488b0506502802488b4840f781f0000000fdffffff',
   [0xa5cfc5]='8bc8498b42500fb60448',[0xa5d083]='486bc138420fb68408ec020000'})do
   assert(b:_read(s.base+at,#bytes/2)==hex(bytes),'Native aim selection contract changed')
  end
  local r=context(s,s.weapon);local after=assert(b:snapshot())
  assert(after.identity==s.identity and after.weapon_descriptor==s.weapon_descriptor and same(r,context(after,after.weapon)),'Native aim owner changed during read')
  return r
 end
 function self:read(r)
  -- Reading/restoring an existing input preference follows the proven local
  -- body, even while a vehicle or interaction owns the camera request. New
  -- preference leases still require the strict firearm probe above.
  local s,why
  if b.pin_first_person==true and type(b.pin_player_snapshot)=='function'then s,why=b:pin_player_snapshot()
  else s,why=b:player_snapshot()end
  assert(s,why)
  if s.player_identity~=r.owner or s.base~=r.base then return nil,'retired' end
  local current=context(s,r.weapon,r.mode)
  if not same(current,r)then return nil,'retired' end
  return current.value
 end
 function self:write(r,expected,value)
  assert(self:read(r)==expected,'Native aim preference changed before write')
  assert(not b.foreign_camera or b.foreign_camera()==false,'Another camera owns the view')
  writer=writer or(memory and memory()or mod.require('src/memory.lua').new())
  local done,why=writer:copy(r.at,string.char(value));assert(done,why)
  assert(self:read(r)==value,'Native aim preference readback differs')
 end
 return self
end
function M.new(source,enabled,foreign)
 local self={phase='idle',writes=0,restores=0};local lease,closing
 function self:is_clean()return lease==nil end
 function self:stop()
  if not lease then self.phase='idle';return true end
  local ok,why=pcall(function()
   assert(not foreign or foreign()==false,'Another camera owns the view')
   local value,reason=source:read(lease)
   if value==nil then assert(reason=='retired','Native aim preference unavailable')
   elseif value==1 then source:write(lease,1,lease.before);self.restores=self.restores+1 end
   lease=nil
  end)
  self.phase=ok and'idle'or'cleanup_pending';self.error_message=not ok and tostring(why)or nil
  return ok,self.error_message
 end
 function self:shutdown()closing=true;return self:stop()end
 function self:update(controller)
  if closing or not enabled()or not controller:is_enabled()or controller:result().mode~='pose_offset'then return self:stop()end
  if foreign and foreign()~=false then self.phase='suspended';return true end
  local ok,why=pcall(function()
   local r=source:probe()
   if lease and not same(lease,r)then local done,problem=self:stop();assert(done,problem)end
   if r.value==0 then
    lease=lease or r;lease.before=0
    source:write(lease,0,1);self.writes=self.writes+1
   end
   self.phase='active';self.error_message=nil
  end)
  if not ok then self.phase='waiting';self.error_message=tostring(why)end
  return true,self.error_message
 end
 function self:result()return {phase=self.phase,owned=lease~=nil,writes=self.writes,restores=self.restores,error_message=self.error_message}end
 return self
end
return M
