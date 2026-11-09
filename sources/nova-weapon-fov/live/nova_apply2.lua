-- Nova weapon FOV, build 26251122: live test, second form. nova_apply.lua held D*tan(F/Z/2)
-- constant, which assumed the scope sits at the depth D places; the 11-07 sweeps (nova_sweep2.lua,
-- 3 s settled steps at 1x and 2.5x reached by stepping down) showed it does not, so this writes
-- distances measured on screen instead: the scope ring matched the 3.5x one (~434 px at 4K) at
-- D 0.217 for 2.5x and D -0.018 for 1x, with F 90. 3.5x keeps its own D.
-- For every spawned LAS-44 Nova (resource key 73d84eaae8c75342) still on its vanilla terms, solve
-- the native formula D = N + G / (tan(F/Z/2) * C) for each C with one shared N (+148 = +14C, so
-- N does not move with F) and write +13C..+14F in one journaled write; nova_restore.lua undoes it.
local G=0.033916
local N=-0.1
local TARGET={[2.5]=0.217,[1]=-0.018}
local KEY_LO,KEY_HI=0xe8c75342,0x73d84eaa
local VANILLA=f32le(0.6)..f32le(0.6)..f32le(0.6)..f32le(0)..f32le(0.1)
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local F=f32(ptr(game+0x2CE1508)+0xAC488)
local u=(F-45)/45
local desc={}
local cap,empty,arr=u32(M+0x38),u32(M+0x3C),ptr(M+0x30)
for b=0,cap-1 do
 local k,v=u32(arr+b*8),u32(arr+b*8+4)
 if k~=empty and v~=0xFFFFFFFF then
  local d=ptr(ptr(M+0x48)+v*8)
  if d and u32(d)==KEY_LO and u32(d+4)==KEY_HI then desc[u32(d+8)]=true end
 end
end
out('F',fmt('%.4g',F))
local rcap,rempty,rarr,rows=u32(M+0x78),u32(M+0x7C),ptr(M+0x70),ptr(M+0xB0)
local n=0
for b=0,rcap-1 do
 local e,i=u32(rarr+b*8),u32(rarr+b*8+4)
 if e~=rempty and i~=0xFFFFFFFF and desc[e] then
  local r=rows+i*0x4D8
  if read(r+0x13C,20)~=VANILLA then
   out('ENTITY',e,'row',i,'not on vanilla terms: left alone')
  else
   local N0=(1-u)*f32(r+0x148)+u*f32(r+0x14C)
   local bytes,parts='',{}
   for j=0,2 do
    local Z,C=f32(r+0x74+4*j),f32(r+0x13C+4*j)
    local t=math.tan(math.rad(F/Z)/2)
    local D=TARGET[Z] or (N0+G/(t*C))
    local c=G/(t*(D-N))
    bytes=bytes..f32le(c)
    parts[#parts+1]=fmt('Z %.3g D %.5f -> %.5f C %.5f',Z,N0+G/(t*C),D,c)
   end
   bytes=bytes..f32le(N)..f32le(N)
   local ok,why=write(r+0x13C,bytes)
   out('ENTITY',e,'row',i,table.concat(parts,' | '))
   out('  write',ok and 'ok' or ('FAILED '..tostring(why)),'readback',
    fmt('C %.5f/%.5f/%.5f N %.4g/%.4g',f32(r+0x13C),f32(r+0x140),f32(r+0x144),f32(r+0x148),f32(r+0x14C)))
   n=n+1
  end
 end
end
out('rows written',n)
return n
