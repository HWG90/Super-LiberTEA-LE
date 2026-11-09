-- Nova weapon FOV, build 26251122: undo nova_apply.lua. Every spawned LAS-44 Nova row (resource
-- key 73d84eaae8c75342) whose +13C..+14F no longer holds the vanilla terms gets them back:
-- C 0.6/0.6/0.6, N +148 0, +14C 0.1 (read from the resource row and every spawned entity, 11-03).
local KEY_LO,KEY_HI=0xe8c75342,0x73d84eaa
local VANILLA=f32le(0.6)..f32le(0.6)..f32le(0.6)..f32le(0)..f32le(0.1)
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local desc={}
local cap,empty,arr=u32(M+0x38),u32(M+0x3C),ptr(M+0x30)
for b=0,cap-1 do
 local k,v=u32(arr+b*8),u32(arr+b*8+4)
 if k~=empty and v~=0xFFFFFFFF then
  local d=ptr(ptr(M+0x48)+v*8)
  if d and u32(d)==KEY_LO and u32(d+4)==KEY_HI then desc[u32(d+8)]=true end
 end
end
local rcap,rempty,rarr,rows=u32(M+0x78),u32(M+0x7C),ptr(M+0x70),ptr(M+0xB0)
local n=0
for b=0,rcap-1 do
 local e,i=u32(rarr+b*8),u32(rarr+b*8+4)
 if e~=rempty and i~=0xFFFFFFFF and desc[e] then
  local r=rows+i*0x4D8
  if read(r+0x13C,20)~=VANILLA then
   local ok,why=write(r+0x13C,VANILLA)
   out('ENTITY',e,'row',i,'restore',ok and 'ok' or ('FAILED '..tostring(why)),
    fmt('C %.4g/%.4g/%.4g N %.4g/%.4g',f32(r+0x13C),f32(r+0x140),f32(r+0x144),f32(r+0x148),f32(r+0x14C)))
   n=n+1
  else out('ENTITY',e,'row',i,'already vanilla') end
 end
end
out('rows restored',n)
return n
