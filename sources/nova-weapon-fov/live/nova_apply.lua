-- Nova weapon FOV, build 26251122: live test. For every spawned LAS-44 Nova (resource key
-- 73d84eaae8c75342) in the weapon manager game+0x2CE1EA0, rewrite its row's presentation terms so
-- the native distance code at game+0x110AC80 keeps the weapon's on-screen size at every zoom
-- equal to the highest zoom's:
--   D = N + G / (tan(F/Z/2) * C)  ->  size ~ 1 / (N*tan(F/Z/2)/G + 1/C)
--   with N = 0 and every C = G / (N*tan(F/Zhi/2) + G/Chi), the old highest-zoom size.
-- G is the Nova's geometry term, measured live (D 0.27397 at Z 2.5, C 0.6, N 0.1): 0.033916.
-- One journaled 20-byte write per row (+13C..+14F); nova_restore.lua puts the vanilla values back.
local G=0.033916
local KEY_LO,KEY_HI=0xe8c75342,0x73d84eaa
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
  local Z={f32(r+0x74),f32(r+0x78),f32(r+0x7C)}
  local C={f32(r+0x13C),f32(r+0x140),f32(r+0x144)}
  local N=(1-u)*f32(r+0x148)+u*f32(r+0x14C)
  local hi=1
  for j=2,3 do if Z[j]>Z[hi] then hi=j end end
  local K=N*math.tan(math.rad(F/Z[hi])/2)+G/C[hi]
  local c=G/K
  out(fmt('ENTITY %d row %d Z %.4g/%.4g/%.4g C %.4g/%.4g/%.4g N %.4g highest Z %.4g -> C %.5f N 0',
   e,i,Z[1],Z[2],Z[3],C[1],C[2],C[3],N,Z[hi],c))
  if N==0 and C[1]==C[2] and C[2]==C[3] then
   out('  already flat (N 0, equal C): left alone')
  else
   local bytes=f32le(c)..f32le(c)..f32le(c)..f32le(0)..f32le(0)
   local ok,why=write(r+0x13C,bytes)
   out('  write',ok and 'ok' or ('FAILED '..tostring(why)),'readback',
    fmt('C %.5f/%.5f/%.5f N %.4g/%.4g',f32(r+0x13C),f32(r+0x140),f32(r+0x144),f32(r+0x148),f32(r+0x14C)))
   n=n+1
  end
 end
end
out('rows written',n)
return n
