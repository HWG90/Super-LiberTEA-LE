-- Nova weapon FOV, build 26251122: read-only. Search the settings tables listed at
-- [game+0x2CE41B8]+0xF13F20 (the array the WeaponData table +0xF146A0 belongs to) for the
-- primary's optic values seen in its live weapon row: zoom 2/3/4 and coefficients 0.8/1/1.25.
-- Prints every hit with its table slot, offset in the table and nearby floats. Reads only.
local owner=assert(ptr(game+0x2CE41B8),'owner')
local arr=assert(read(owner+0xF13F20,0x2000))
local tables={}
for o=0,0x2000-8,8 do
 local a=get(arr,o,'u64')
 if a>0x10000 and a<0x7FFFFFFFFFFF then tables[#tables+1]={a=a,slot=0xF13F20+o} end
end
table.sort(tables,function(x,y)return x.a<y.a end)
local pats={zoom234=f32le(2)..f32le(3)..f32le(4),coef=f32le(0.8)..f32le(1)..f32le(1.25),zoom1525=f32le(1.5)..f32le(2.5)..f32le(3.5)}
local hits=0
for i=1,#tables-1 do
 local T=tables[i].a;local size=tables[i+1].a-T
 if size>0 and size<16*1048576 then
  local s=read(T,size)
  if s then
   for name,p in pairs(pats) do
    local at=1
    while hits<80 do
     local f=s:find(p,at,true);if not f then break end
     local off=f-1;local ctx={}
     for k=-12,15 do local o=off+k*4;if o>=0 and o+4<=#s then ctx[#ctx+1]=fmt('%.4g',get(s,o,'f32')) end end
     out(fmt('HIT %s slot +%X table %X off 0x%X',name,tables[i].slot,T,off),table.concat(ctx,' '))
     hits=hits+1;at=f+4
    end
   end
  end
 end
end
out('tables',#tables,'hits',hits)
return true
