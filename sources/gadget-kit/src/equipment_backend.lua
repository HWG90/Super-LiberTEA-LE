-- Build 6AD7C05D: ship player appearance/profile commit; Armory synchronization when open.
-- The commit consumes only the first 0x9C bytes synchronously. Use an owned
-- candidate buffer, preserving all non-equipment appearance fields verbatim.
-- This avoids depending on a currently open Armory controller.
local M={}
local F={primary={0x40,0x90,'weapons',1},pistol={0x44,0x94,'weapons',3},
 grenade={0x48,0x98,'weapons',4},helmet={0x150,0x68,'helmets',1},
 cape={0x154,0x6C,'capes',2},armor={0x158,0x70,'bodyarmor',0}}
local PINS={
 {0x12ED7A0,'48895c240848896c2410488974241848897c242041564883ec20488b1d4fa9b4014032ff8b8190000000440fb6f2394340740689434040b7018b8194000000394344740689434440b7018b8198000000394348740689434840b701488d716441b82c000000488d6938488bd6488bcde8fce7c90085c075074084ff7458eb054084ff7404c6433c01488b05e93d9f0183b88800000000740d488b80e80000004883c008eb07488d059818b5018b10488bcee89a0f47000f10068b46280f104e100f114500f20f1046200f114d10f20f1145208945284584f67405e8b18fd9ff488b5c2430488b6c2438488b742440488b7c24484883c420415ec3'},
 {0x175E7F0,'40535556574883ec284c896c2458488bf98b098bda4c89742460e871cb90ff33f6448bc64885c07403448b008bd3e8cd3b12ff4c8b35163858018bee4139b640'},
 {0x175EA7C,'0f1007488b0d8a966d0133d20f11814c0100000f104f100f11895c010000f20f104720f20f11816c0100008b47288981740100004883c4285f5e5d5be9'},
}
for _,p in ipairs(PINS)do p.bytes=p[2]:gsub('%x%x',function(h)return string.char(tonumber(h,16))end)end
local function le32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function id(s,o)local a,b,c,d=s:byte(o+1,o+4);if not d then return nil end;return a+b*256+c*65536+d*16777216 end
function M.new(backend)
 local mem=backend.mem
 local self={}
 local function context()
  local c,why=backend:context();if not c then return nil,why end
  local state=mem:ptr(c.game+0x2CE1508)
  if not state or mem:u32(state+0xAC29C)~=3 then return nil,'Waiting for ship equipment' end
  local profile=mem:ptr(c.game+0x2E38110)
  if not profile then return nil,'Waiting for equipment profile' end
  local count=mem:u32(c.player+0x88)
  local player=count and count>=1 and mem:ptr(c.player+0xE8)
  local player_id=player and mem:u32(player+8)
  if not player_id or player_id==4294967295 then return nil,'Waiting for local equipment owner' end
  local kits=mem:ptr(c.game+0x2CE16A8)
  if not kits or not mem:hashmap(kits+0x938,player_id)then return nil,'Waiting for player appearance' end
  c.profile,c.player_id=profile,player_id
  return c
 end
 local function sample(c)
  local result={version=1}
  for key,f in pairs(F)do result[key]=mem:u32(c.profile+f[1]);if not result[key]or result[key]==0 then return nil,'Equipment profile is initializing' end end
  return result
 end
 function self:capture()
  local c,why=context();if not c then return nil,why end
  local result,err=sample(c);if not result then return nil,err end
  local after=context()
  if not after or after.profile~=c.profile or not backend:same_context(c,after)then return nil,'Equipment owner changed' end
  return result
 end
 local function allowed(c,key,value)
  local f=F[key]
  if f[3]=='weapons'then
   local weapons=mem:ptr(c.game+0x2CE1BA0);if not weapons then return false end
   local first=mem:u32(weapons+0x1BFC+f[4]*4);local count=mem:u32(weapons+0x1C18+f[4]*4)
   if not first or not count or count>1024 or first+count>199 then return false end
   for i=first,first+count-1 do if mem:u32(weapons+i*32)==value then return true end end
   return false
  end
  local kits=backend:_kits(c.game)
  return kits and kits[value]==f[3]
 end
 function self:restore(saved,categories,expected)
  local c,why=context();if not c then return false,why end
  local current=sample(c);if not current then return false,'Equipment profile is unavailable' end
  for key in pairs(F)do if current[key]~=expected[key]then return false,'Equipment selection changed' end end
  local target={};local changed=false
  for key,f in pairs(F)do
   target[key]=current[key]
   if categories[f[3]]and saved[key]~=current[key]then
    if not allowed(c,key,saved[key])then return false,'Saved equipment is not in its catalogue slot: '..key end
    target[key]=saved[key];changed=true
   end
  end
  if not changed then return true end
  local appearance=mem:read(c.profile+0x14C,44)
  if not appearance then return false,'Appearance profile is unreadable' end
  -- No live Armory edit may race our one-time startup restore.
  local manager=mem:ptr(c.game+0x2CE2040)
  local n=manager and mem:u32(manager+0x166C)
  if not n or n>64 then return false,'Armory registry is unavailable' end
  local live_owner
  for i=0,n-1 do
   local row=manager+0x1670+i*16
   if mem:u32(row+8)==0xE2 then
    local owner=mem:ptr(row)
    if live_owner then return false,'Ambiguous Armory controller' end
    live_owner=owner
    if not owner or mem:u8(owner+0x34)~=0 or mem:read(owner+0x38,44)~=appearance or mem:read(owner+0x64,44)~=appearance then
     return false,'Finish the current Armory selection first'
    end
   end
  end
  local ffi=mem._ffi
  self.buffer=self.buffer or ffi.new('uint8_t[160]')
  ffi.fill(self.buffer,160)
  ffi.copy(self.buffer+0x38,appearance,44);ffi.copy(self.buffer+0x64,appearance,44)
  for key,f in pairs(F)do ffi.copy(self.buffer+f[2],le32(target[key]),4)end
  local before=self:capture()
  for key in pairs(F)do if not before or before[key]~=current[key]then return false,'Equipment changed before restore' end end
  local latest=context()
  if not latest or latest.profile~=c.profile or not backend:same_context(c,latest)
    or mem:read(c.profile+0x14C,44)~=appearance then return false,'Profile changed before restore' end
  -- false defers disk serialization to the normal game save; our own stable
  -- IDs are already on disk, so startup resets cannot erase the saved choice.
  if live_owner then
   for _,p in ipairs(PINS)do if mem:read(c.game+p[1],#p.bytes)~=p.bytes then return false,'Armory commit fingerprint mismatch' end end
   local fn=ffi.cast('void (*)(void *, bool)',c.game+0x12ED7A0)
   -- Keep an existing Armory controller synchronized too: closing it must not
   -- commit its old candidate back over the restored profile.
   local before_weapons=mem:read(live_owner+0x90,12)
   local before_appearance=mem:read(live_owner+0x64,44)
   if not before_weapons or before_appearance~=appearance then return false,'Armory changed before restore' end
   for key,f in pairs(F)do if f[3]=='weapons' and id(before_weapons,f[2]-0x90)~=current[key]then return false,'Armory weapon selection is pending' end end
   local gear=ffi.string(self.buffer+0x64,44);local weapons=ffi.string(self.buffer+0x90,12)
   local ok,err=mem:copy(live_owner+0x64,gear)
   if not ok then
    if mem:read(live_owner+0x64,44)==gear then mem:copy(live_owner+0x64,before_appearance) end
    return false,err or 'Armory appearance write failed'
   end
   ok,err=mem:copy(live_owner+0x90,weapons)
   if not ok then
    if mem:read(live_owner+0x64,44)==gear then mem:copy(live_owner+0x64,before_appearance) end
    if mem:read(live_owner+0x90,12)==weapons then mem:copy(live_owner+0x90,before_weapons) end
    return false,err or 'Armory weapon write failed'
   end
   fn(ffi.cast('void *',live_owner),false)
  else
   -- The Armory entry point stays packed until its menu opens. Startup must
   -- use the player appearance commit already used by ship initialization.
   local gear_changed=false
   for key,f in pairs(F)do if f[3]~='weapons' and target[key]~=current[key]then gear_changed=true end end
   if gear_changed then
    for i=2,3 do local p=PINS[i]
     if mem:read(c.game+p[1],#p.bytes)~=p.bytes then return false,'Startup appearance commit is not ready' end
    end
   end
   local weapons=ffi.string(self.buffer+0x90,12)
   local original_weapons=mem:read(c.profile+0x40,12)
   local dirty=mem:u8(c.profile+0x3C)
   if not original_weapons or (dirty~=0 and dirty~=1)then return false,'Profile save state is unavailable' end
   -- Match the weapon part of the native commit without entering Armory code.
   local ok,err=mem:copy(c.profile+0x40,weapons)
   if not ok then return false,err or 'Profile weapon restore failed' end
   ok,err=mem:copy(c.profile+0x3C,string.char(1))
   if not ok then
    if mem:read(c.profile+0x40,12)==weapons then mem:copy(c.profile+0x40,original_weapons)end
    return false,err or 'Profile save marker failed'
   end
   if gear_changed then
    local apply=ffi.cast('void (*)(void *, uint32_t)',c.game+0x175E7F0)
    apply(self.buffer+0x64,c.player_id)
   end
  end
  local after=self:capture()
  for key in pairs(F)do if not after or after[key]~=target[key]then return false,'Equipment commit not confirmed: '..key end end
  return true
 end
 return self
end
M.fields=F
return M
