-- Nova weapon FOV, build 26251122: read-only background watcher (task 'nova_watch', 900 s).
-- Each 3rd frame it reads the gameplay camera owner's current kind-6 request (owner game+0x2E287D0,
-- request owner+0x1F00 or ring owner+0x200, stride 0xE8; the native updater game+0x110AA20) and the
-- weapon row of the request's weapon (+8) in the weapon manager game+0x2CE1EA0. On every change of
-- the distance D (+0x90), the lens (+0x84) or the row's fields it appends a line to
-- LinksLinkToMemory\nova_watch.log, with the geometry term G the native formula implies:
--   D = N + G / (tan(F/Z/2) * C),  N = (1-u)*row[148] + u*row[14C],  u = (F-45)/45.
-- Reads only; no writes, no native calls.
local path=os.getenv('LOCALAPPDATA')..'\\LinksLinkToMemory\\nova_watch.log'
local log=assert(io.open(path,'a'))
local function line(...) log:write(os.date('%H:%M:%S'),' ',table.concat({...},' '),'\n') log:flush() end
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local function row_of(e)
 local cap,empty,arr=u32(M+0x78),u32(M+0x7C),ptr(M+0x70)
 for b=0,cap-1 do if u32(arr+b*8)==e then local i=u32(arr+b*8+4);if i~=0xFFFFFFFF then return ptr(M+0xB0)+i*0x4D8 end end end
end
local function key_of(e)
 local cap,empty,arr=u32(M+0x38),u32(M+0x3C),ptr(M+0x30)
 for b=0,cap-1 do if u32(arr+b*8)==e then local v=u32(arr+b*8+4)
  if v~=0xFFFFFFFF then local d=ptr(ptr(M+0x48)+v*8);if d then return fmt('%08x%08x',u32(d+4),u32(d)) end end end end
 return '?'
end
local frames,last,start=0,nil,os.clock()
line('watch started')
local function step()
 frames=frames+1
 if os.clock()-start>900 then line('watch ended (900 s)') return true end
 if frames%3~=0 then return false end
 local O=ptr(game+0x2E287D0);if not O then return false end
 local R=(u32(O+0x1F8)==u32(O+0x1FC)) and O+0x1F00 or O+0x200+((u32(O+0x1FC)-1)%32)*0xE8
 local kind=u16(R)
 local F=f32(ptr(game+0x2CE1508)+0xAC488)
 local cam=ptr(O);local vfov=cam and f32(cam+0x34) or 0
 local text
 if kind==6 then
  local e=u32(R+8);local r=row_of(e)
  local D,lens=f32(R+0x90),f32(R+0x84)
  if r then
   local u=(F-45)/45;local N=(1-u)*f32(r+0x148)+u*f32(r+0x14C)
   local Z={f32(r+0x74),f32(r+0x78),f32(r+0x7C)};local C={f32(r+0x13C),f32(r+0x140),f32(r+0x144)}
   local g={}
   for j=1,3 do g[j]=fmt('%.5f',(D-N)*math.tan(math.rad(F/Z[j])/2)*C[j]) end
   text=fmt('kind 6 weapon %d res %s D %.5f prevD %.5f lens %.3f deg scene %.3f deg F %.4g Z %.4g/%.4g/%.4g C %.4g/%.4g/%.4g N %.4g (148 %.4g 14C %.4g) G_if_j0/1/2 %s',
    e,key_of(e),D,f32(R+0x9C),math.deg(lens),math.deg(vfov),F,Z[1],Z[2],Z[3],C[1],C[2],C[3],N,f32(r+0x148),f32(r+0x14C),table.concat(g,'/'))
  else text=fmt('kind 6 weapon %d (no row) D %.5f lens %.3f scene %.3f',e,D,math.deg(lens),math.deg(vfov)) end
 else text=fmt('kind %d scene %.3f deg',kind,math.deg(vfov)) end
 if text~=last then line(text);last=text end
 return false
end
return background('nova_watch',step,function() pcall(function() line('watch closed') log:close() end) end)
