-- Nova weapon FOV, build 26251122: read-only background watcher, second form (task 'nova_watch',
-- 900 s). nova_watch.lua's log line for the gameplay camera owner's current kind-6 request, plus
-- the request's mode bytes +8C..+8F and the prior lens +A0, which the evaluator at game+0x1119293
-- blends with: D_eff = (1-x)*D + x*prevD, x = |target-current| / |target-A0|. +98 moves every
-- frame in ADS, so it is only in the dumps.
-- Every settled Nova request (lens +84 == scene) that differs from the last one is also dumped
-- whole (0xE8 bytes as hex and as floats) to LinksLinkToMemory\nova_req.log. Reads only.
local dir=os.getenv('LOCALAPPDATA')..'\\LinksLinkToMemory\\'
local log=assert(io.open(dir..'nova_watch.log','a'))
local dump=assert(io.open(dir..'nova_req.log','a'))
local function line(...) log:write(os.date('%H:%M:%S'),' ',table.concat({...},' '),'\n') log:flush() end
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local function row_of(e)
 local cap,arr=u32(M+0x78),ptr(M+0x70)
 for b=0,cap-1 do if u32(arr+b*8)==e then local i=u32(arr+b*8+4);if i~=0xFFFFFFFF then return ptr(M+0xB0)+i*0x4D8 end end end
end
local function key_of(e)
 local cap,arr=u32(M+0x38),ptr(M+0x30)
 for b=0,cap-1 do if u32(arr+b*8)==e then local v=u32(arr+b*8+4)
  if v~=0xFFFFFFFF then local d=ptr(ptr(M+0x48)+v*8);if d then return fmt('%08x%08x',u32(d+4),u32(d)) end end end end
 return '?'
end
local frames,last,last_dump,start=0,nil,nil,os.clock()
line('watch started (form 2)')
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
  local e=u32(R+8);local r=row_of(e);local key=key_of(e)
  local D,lens=f32(R+0x90),f32(R+0x84)
  local mode=fmt('m %s A0 %.3f',hex(read(R+0x8C,4)),math.deg(f32(R+0xA0)))
  if r then
   local u=(F-45)/45;local N=(1-u)*f32(r+0x148)+u*f32(r+0x14C)
   text=fmt('kind 6 weapon %d res %s D %.5f prevD %.5f lens %.3f deg scene %.3f deg F %.4g Z %.4g/%.4g/%.4g C %.4g/%.4g/%.4g N %.4g %s',
    e,key,D,f32(R+0x9C),math.deg(lens),math.deg(vfov),F,f32(r+0x74),f32(r+0x78),f32(r+0x7C),
    f32(r+0x13C),f32(r+0x140),f32(r+0x144),N,mode)
  else text=fmt('kind 6 weapon %d (no row) D %.5f lens %.3f scene %.3f %s',e,D,math.deg(lens),math.deg(vfov),mode) end
  if key=='73d84eaae8c75342' and math.abs(lens-vfov)<0.0002 then
   local s=read(R,0xE8)
   local k=s:sub(1,0x98)..s:sub(0x9D)
   if k~=last_dump then
    last_dump=k
    local fl={}
    for o=0,0xE4,4 do fl[#fl+1]=fmt('%X:%.5g',o,get(s,o,'f32')) end
    dump:write(os.date('%H:%M:%S'),fmt(' settled lens %.3f D %.5f %s r98 %.4f\n  hex %s\n  f32 %s\n',math.deg(lens),D,mode,f32(R+0x98),hex(s),table.concat(fl,' ')))
    dump:flush()
   end
  end
 else text=fmt('kind %d scene %.3f deg',kind,math.deg(vfov)) end
 if text~=last then line(text);last=text end
 return false
end
return background('nova_watch',step,function() pcall(function() line('watch closed') log:close() dump:close() end) end)
