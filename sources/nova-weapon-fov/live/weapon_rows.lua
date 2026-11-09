-- Nova weapon FOV, build 26251122: read-only. For every weapon entity in the weapon component
-- manager (game+0x2CE1EA0), print the presentation fields the native distance code at
-- game+0x110AC80 reads from its row (resolver game+0x512010): Z +74/+78/+7C, C +13C/+140/+144,
-- N +148/+14C, flag byte +150. Then the same fields of the resource row (game+0x511B30 table)
-- and every 4-byte field where the entity row differs from it. Reads only.
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local function fields(r)
 return fmt('Z %.4g %.4g %.4g C %.4g %.4g %.4g N %.4g %.4g flag %d',
  f32(r+0x74),f32(r+0x78),f32(r+0x7C),f32(r+0x13C),f32(r+0x140),f32(r+0x144),f32(r+0x148),f32(r+0x14C),u8(r+0x150))
end
local function resource_row(key_lo,key_hi)
 local T=ptr(ptr(game+0x2CE41B8)+0xF146A0);if not T then return nil end
 for b=0,0x2EA-1 do
  local lo,hi=u32(T+b*16),u32(T+b*16+4)
  if lo==key_lo and hi==key_hi then return T+0x2EA0+u32(T+b*16+8)*0x4D8 end
 end
end
-- descriptors: map M+0x30 (capacity +0x38, empty +0x3C), component pointers at M+0x48
local desc={}
local cap,empty,arr=u32(M+0x38),u32(M+0x3C),ptr(M+0x30)
for b=0,cap-1 do
 local k,v=u32(arr+b*8),u32(arr+b*8+4)
 if k~=empty and v~=0xFFFFFFFF then
  local d=ptr(ptr(M+0x48)+v*8)
  if d then desc[u32(d+8)]={lo=u32(d),hi=u32(d+4)} end
 end
end
out('F (TPV vertical FOV setting)',fmt('%.4g',f32(ptr(game+0x2CE1508)+0xAC488)))
local rcap,rempty,rarr,rows=u32(M+0x78),u32(M+0x7C),ptr(M+0x70),ptr(M+0xB0)
out('entity rows capacity',rcap)
for b=0,rcap-1 do
 local e,i=u32(rarr+b*8),u32(rarr+b*8+4)
 if e~=rempty and i~=0xFFFFFFFF then
  local r=rows+i*0x4D8
  local d=desc[e]
  local key=d and fmt('%08x%08x',d.hi,d.lo) or '?'
  out('ENTITY',e,'row',i,'res',key,fields(r))
  local rr=d and resource_row(d.lo,d.hi)
  if rr then
   out('  RESOURCE',fields(rr))
   local a,bb=read(r,0x4D8),read(rr,0x4D8)
   local ch={}
   for o=0,0x4D8-4,4 do if a:sub(o+1,o+4)~=bb:sub(o+1,o+4) then
    ch[#ch+1]=fmt('%X:%.4g/%.4g',o,get(a,o,'f32'),get(bb,o,'f32')) end end
   out('  DIFF entity/resource',#ch,table.concat(ch,' '))
  end
 end
end
return true
