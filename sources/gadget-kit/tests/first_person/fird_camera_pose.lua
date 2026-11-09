local C=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_camera_pose.lua')
local P=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_projection.lua')
local ffi=TEST_PORT51 and TEST_PORT51.ffi or require('ffi')
local cases=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));cases=cases+1 end
local function near(a,b)assert(math.abs(a-b)<.00002,tostring(a)..' ~= '..tostring(b))end
local function copy(row)local out={};for k,v in pairs(row)do out[k]=v end;return out end
local function fixture()
 local f={mem={},reads=0,snapshots=0,exe=0x100000,foreign=false}
 local function u32(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
 function f:write(at,raw)for i=1,#raw do self.mem[at+i-1]=raw:byte(i)end end
 function f:u32(at,v)self:write(at,u32(v))end
 function f:ptr(at,v)self:write(at,u32(v%4294967296)..u32(math.floor(v/4294967296)))end
 function f:read(at,n)local out={};for i=0,n-1 do local value=assert(self.mem[at+i],'Unexpected camera read '..at..'+'..i);out[#out+1]=string.char(value)end;return table.concat(out)end
 function f:floats(values)local out=ffi.new('float[16]');for i=1,16 do out[i-1]=values[i]end;return ffi.string(out,64)end
 f.c={exe=f.exe,unit=17,index=2,generation=7,object=0x200000,units=0x300000,generations=0x400000}
 f.body={exe=f.exe,unit=20,index=3,generation=7,object=0x210000,units=f.c.units,generations=f.c.generations}
 f.s={identity='weapon',player_identity='player',base=0x10000000,context=0x600000,camera=0x500000,
  record=0x601f00,camera_kind=4,safe=true,controller_active=false,world=0x700000,avatar_owner=0x710000,
  avatar_index=0,avatar=100,body=20,viewmodel=30,weapon_unit=40}
 f.cal={identity='player',camera_context=f.c,body_context=f.body}
 f.locals=0x900000;f.links=0xa00000;f.native_world=0x800000
 for _,c in ipairs({f.c,f.body})do
  f:write(c.generations+c.index,string.char(c.generation));f:ptr(c.units+c.index*8,c.object)
  f:u32(c.object+8,c.unit);f:ptr(c.object+0x18,f.native_world)
 end
 f:ptr(f.s.context,f.s.camera);f:u32(f.s.context+8,f.c.unit)
 f:ptr(f.s.camera+0x18,f.c.object+0x60);f:u32(f.s.camera+0x20,0)
 f:u32(f.c.object+0x70,2);f:ptr(f.c.object+0x1d0,0);f:ptr(f.c.object+0x80,f.locals)
 f:ptr(f.c.object+0x98,f.links);f:u32(f.links,0);f:u32(f.links+4,0)
 function f:pose(position,yaw,node)
  position=position or{218.905,-155.735,25.3134};yaw=yaw or .35;node=node or 0
  local c,s=math.cos(yaw),math.sin(yaw)
  self:write(self.s.context+0x0c,self:floats({c,s,0,0,-s,c,0,0,0,0,1,0,position[1],position[2],position[3],1}))
  self:write(self.locals+node*64,self:floats({c,s,0,-s,c,0,0,0,1,position[1],position[2],position[3],1,1,1,0}))
 end
 f:pose()
 for rva,hex in pairs({
  [0x110be95]='41ff5120488b052856bd014c8d45008b5308488b0b4c8b482041ff5128',
  [0x110beb2]='488b050f56bd018b5308488b8b800100004c8b400841ff9000010000488b05f355bd0133d2488b4818488b81900000008b4b08ffd0',
  [0x110bee7]='33d20f10000f11430c0f1048100f114b1c0f1040200f11432c0f104830488b05bd55bd010f114b3c'})do
  f:write(f.s.base+rva,(hex:gsub('..',function(v)return string.char(tonumber(v,16))end)))
 end
 f:write(f.exe+0x28d310,'\072\141\065\096\195')
 f:write(f.exe+0x1f226b,'\072\139\203\072\193\225\006\072\131\193\036\072\139\064\032')
 local b={foreign_camera=function()return f.foreign end}
 function b:_read(at,n)
  f.reads=f.reads+1;local value=f:read(at,n)
  if f.during_read then f.during_read(at,n)end
  return value
 end
 function b:_u32(at)local a,c,d,e=f:read(at,4):byte(1,4);return a+c*256+d*65536+e*16777216 end
 function b:_ptr(at)local n=self:_u32(at)+self:_u32(at+4)*4294967296;assert(n>=65536 and n<2^47 and n%8==0,'Bad camera pointer');return n end
 function b:_u8(at)return f:read(at,1):byte()end
 function b:_alignment_executable()return f.exe end
 function b:snapshot()f.snapshots=f.snapshots+1;if f.during_snapshot then f.during_snapshot(f.snapshots)end;return copy(f.s)end
 f.b=b;f.expected=copy(f.s)
 return f
end
local function refuses(f)local ok=pcall(C.read,f.b,f.cal,f.expected);assert(not ok,'Invalid camera observation was accepted')end
test('paired actual camera is returned independently of a later animated head and a stale world cache',function()
 local f=fixture();local out=C.read(f.b,f.cal,f.expected)
 near(out.position[1],218.905);near(out.position[2],-155.735);near(out.position[3],25.3134)
 near(out.basis[1][1],math.cos(.35));near(out.basis[2][1],-math.sin(.35))
 -- Neither body head matrices nor camera world+88 exist in this fixture.
 -- Reading an orbit cache or reconstructing a head anchor therefore fails.
 assert(f.snapshots==2)
 out.position[1]=0;out.basis[1][1]=0
 local next=C.read(f.b,f.cal,f.expected);near(next.position[1],218.905);near(next.basis[1][1],math.cos(.35))
end)
test('camera epoch carries native FPS motion once while later head bob cannot move the weapon',function()
 local f=fixture();local out=C.read(f.b,f.cal,f.expected)
 local ref={projection={position={0,.8,0},rotation={0,0,0,1},fov=math.pi/2},reference={x=0,y=0,z=0}}
 local native={position={0,.8,0},rotation={0,0,0,1},fov=math.pi/2}
 local current={position={100,100.83,100},rotation={0,0,math.sin(.05),math.cos(.05)},frame_origin={100,100,100},frame_rotation={0,0,0,1}}
 local t=assert(P.follow(ref,current,out.position,out.basis,ref.reference,math.pi/2,native))
 local relative=P.capture(t.target,t.target_rotation,out.position,P.basis_rotation(out.basis))
 near(relative.position[2],.83);near(relative.rotation[3],math.sin(.05))
 f:pose({218.905,-155.735,25.3534},.6);out=C.read(f.b,f.cal,f.expected)
 t=assert(P.follow(ref,current,out.position,out.basis,ref.reference,math.pi/2,native))
 relative=P.capture(t.target,t.target_rotation,out.position,P.basis_rotation(out.basis))
 near(relative.position[2],.83);near(relative.rotation[3],math.sin(.05))
end)
test('the component must use the exact node zero requested by the pinned final getter',function()
 local f=fixture();f:u32(f.s.camera+0x20,1);f:pose({10,20,30},-.2,1)
 refuses(f)
end)
for _,field in ipairs({'identity','player_identity','base','context','camera','record','camera_kind','safe','controller_active','world',
 'avatar_owner','avatar_index','avatar','body','viewmodel','weapon_unit'})do
 test('ownership rejects changed '..field,function()
  local f=fixture();local v=f.s[field]
  if type(v)=='boolean'then f.s[field]=not v elseif type(v)=='number'then f.s[field]=v+1 else f.s[field]=v..'-changed'end
  refuses(f)
 end)
end
for _,change in ipairs({
 function(f)f:write(f.c.generations+f.c.index,string.char(8))end,
 function(f)f:ptr(f.c.units+f.c.index*8,f.body.object)end,
 function(f)f:u32(f.c.object+8,18)end,
 function(f)f:write(f.body.generations+f.body.index,string.char(8))end,
 function(f)f:ptr(f.s.context,f.s.camera+8)end,
 function(f)f:u32(f.s.context+8,18)end,
 function(f)f:ptr(f.s.camera+0x18,f.body.object+0x60)end,
 function(f)f:u32(f.c.object+0x70,0)end,
 function(f)f:u32(f.c.object+0x70,513)end,
 function(f)f:u32(f.s.camera+0x20,2)end,
 function(f)f:ptr(f.c.object+0x1d0,f.body.object)end,
 function(f)f:u32(f.links,1)end,
 function(f)f:u32(f.links,2)end,
 function(f)f:ptr(f.c.object+0x18,f.native_world+8)end,
 function(f)f.foreign=true end,
 function(f)f.exe=f.exe+8 end,
})do test('binding and Unit ownership refuse mismatches',function()local f=fixture();change(f);refuses(f)end)end
for _,offset in ipairs({0x110be95,0x110beb2,0x110bee7})do
 test('final camera dispatch fingerprint drift refuses',function()local f=fixture();f:write(f.s.base+offset,'X');refuses(f)end)
end
for _,offset in ipairs({0x28d310,0x1f226b})do
 test('camera graph/local layout fingerprint drift refuses',function()local f=fixture();f:write(f.exe+offset,'X');refuses(f)end)
end
for _,bad in ipairs({'translation_epoch','orientation_epoch','nan','world_bound','shear','mirror','scale','affine'})do
 test('invalid or mixed camera pose '..bad..' refuses',function()
  local f=fixture()
  if bad=='translation_epoch'then f:write(f.locals+0x24,f:floats({219,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}):sub(1,4))
  elseif bad=='orientation_epoch'then f:write(f.locals,f:floats({1,0,0,0,1,0,0,0,1,218.905,-155.735,25.3134,1,1,1,0}))
  elseif bad=='scale'then f:write(f.locals+0x30,f:floats({2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}):sub(1,4))
  elseif bad=='nan'then f:pose({0/0,0,0},0)
  elseif bad=='world_bound'then f:pose({1e6,0,0},0)
  else
   local m={1,0,0,0,0,1,0,0,0,0,1,0,218.905,-155.735,25.3134,1}
   if bad=='shear'then m[5]=.1 elseif bad=='mirror'then m[1]=-1 else m[16]=0 end
   f:write(f.s.context+0x0c,f:floats(m))
  end
  refuses(f)
 end)
end
test('pose changes during copied observation refuse',function()
 local f=fixture();local fired=false
 f.during_read=function(at)if at==f.s.context+0x0c and not fired then fired=true;f:pose({219,-155,25},.4)end end
 refuses(f)
end)
test('final snapshot and graph changes remain inside the pose bracket',function()
 local f=fixture();f.during_snapshot=function(n)if n==2 then f:pose({219,-155,25},.4)end end;refuses(f)
 f=fixture();f.during_snapshot=function(n)if n==2 then f:ptr(f.c.object+0x80,f.locals+64)end end;refuses(f)
 f=fixture();f.during_snapshot=function(n)if n==2 then f.s.identity='replacement'end end;refuses(f)
end)
print('Fird submitted camera pose: '..cases..' paired epoch, native motion, root/wrapper ownership, stale world cache and mutation cases passed')
