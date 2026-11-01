-- Instant shuttle arrival: only the native Extract (152) call-in row.
-- Leave the engine to dispatch the countdown-completed transition normally.
local M={}
local PINS={
 {0x6B5E25,'43817c340c98000000f3430f1034340f85da010000'},
 {0x6B6014,'488b46780f28c6f3410f5cc5ba66f70961f3410f110406488b46604c8b46784d03c64a8b0cf88b4910e83e377b00'},
 {0x57A29B,'488d8f801300000f28cee816b61300'},
}
for _,p in ipairs(PINS)do p.bytes=p[2]:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)end
local SHORT=string.char(205,204,204,61) -- float 0.1 seconds
local function number(mem,bytes)
 if not bytes then return nil end
 local f=mem._ffi.new('float[1]');mem._ffi.copy(f,bytes,4)
 return tonumber(f[0])
end
function M.new(backend)
 local self={message='Waiting for extraction',seen={},cursor=0}
 local elapsed,context=0,nil
 function self:stop()self.seen={};context=nil;elapsed=0;self.message='Off'end
 function self:update(dt)
  elapsed=elapsed+math.max(0,math.min(1,tonumber(dt)or .1))
  if elapsed<.1 then return end;elapsed=0
  local c,why=backend:gameplay_context()
  if not c then self.seen={};context=nil;self.message=why or 'Session unavailable';return end
  local mem=backend.mem;local state=mem:ptr(c.game+0x2CE1508);local mode=mem:ptr(c.game+0x2CE1850)
  if not state or not mode or mem:u32(state+0xAC29C)~=4 or mem:u32(mode+8)~=1 then
   self.seen={};context=nil;self.message='Waiting for a mission';return
  end
  if not context or not backend:same_context(context,c)then self.seen={};context=c end
  for _,pin in ipairs(PINS)do
   if mem:read(c.game+pin[1],#pin.bytes)~=pin.bytes then self.message='Waiting for extraction code';return end
  end
  local manager=mem:ptr(c.game+0x2CE1860)
  if not manager or manager~=c.world+0x13C0 then self.message='Extraction manager ownership mismatch';return end
  local cap,n=mem:u32(manager+0x28),mem:u32(manager+0x38)
  if not cap or not n or n>cap or cap>1024 then self.message='Extraction manager bounds changed';return end
  if n==0 then self.message='Waiting for extraction';return end
  local rows,descriptors,settings=mem:ptr(manager+0x78),mem:ptr(manager+0x60),mem:ptr(manager+0x68)
  if not rows or not descriptors or not settings then self.message='Extraction rows unavailable';return end
  -- Process a bounded array and only the native arrival type. Ordinary
  -- stratagem call-ins, boarding, and mission time are never selected by ID.
  for _=1,math.min(n,16) do
   local i=self.cursor%n;self.cursor=(i+1)%n
   local address=rows+i*64
   if mem:u32(address+12)==152 and mem:u8(address+60)==1
    and mem:u32(settings+i*0x8F0+0x8E8)~=2 then
    local descriptor=mem:ptr(descriptors+i*8)
    local identity=descriptor and mem:read(descriptor,24)
    local timer=mem:read(address,4);local remaining=number(mem,timer)
    if identity and remaining and remaining==remaining and remaining>.1 and remaining<=900 then
     local key=tostring(manager)..':'..tostring(address)..':'..identity:sub(1,20)
     if not self.seen[key]then
      local fresh=backend:gameplay_context()
      if not fresh or not backend:same_context(c,fresh)or mem:ptr(c.game+0x2CE1860)~=manager
       or mem:ptr(manager+0x78)~=rows or mem:ptr(descriptors+i*8)~=descriptor
       or mem:read(descriptor,24)~=identity or mem:u32(address+12)~=152
       or mem:read(address,4)~=timer then self.message='Extraction changed; retrying';return end
      local ok,err=mem:copy(address,SHORT)
      if not ok then self.message=err or 'Extraction timer write failed';return end
      self.seen[key]=true;self.message='Arrival countdown completed';return
     end
    end
   end
  end
  self.message='Waiting for extraction'
 end
 function self:status()return self.message end
 return self
end
M.fingerprints=PINS
return M
