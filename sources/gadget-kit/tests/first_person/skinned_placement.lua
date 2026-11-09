local S=dofile(NATIVE_ADS_TEST_ROOT..'/src/skinned_placement.lua')
local ffi=require('ffi')
local function fixture()
 local f={live=true,angle=0,travel=0,sets=0,publishes=0}
 local function mul(a,b)return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}end
 local Q={from_elements=function(...)return{...}end,to_elements=function(q)return unpack(q)end,
 inverse=function(q)return{-q[1],-q[2],-q[3],q[4]}end,multiply=mul,normalize=function(q)return q end}
 Q.rotate=function(q,v)local x=mul(mul(q,{v[1],v[2],v[3],0}),Q.inverse(q));return{x[1],x[2],x[3]}end
 Q.from_matrix4x4=function(m)return m.q end
 local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return{...}end})
 local A={}
 local float_position=ffi.new('float[3]')
 local float_rotation=ffi.new('float[4]')
 local function quantized(v)
  for i=1,3 do float_position[i-1]=v[i]end
  return{tonumber(float_position[0])or ffi.tonumber(float_position[0]),tonumber(float_position[1])or ffi.tonumber(float_position[1]),tonumber(float_position[2])or ffi.tonumber(float_position[2])}
 end
 local function quantized_q(q)
  local out={};for i=1,4 do float_rotation[i-1]=q[i];out[i]=tonumber(float_rotation[i-1])or ffi.tonumber(float_rotation[i-1])end;return out
 end
 A.transform=function(m,v)
  if m.inverse then local p={v[1]-m.p[1],v[2]-m.p[2],v[3]-m.p[3]};return Q.rotate(Q.inverse(m.q),p)end
  local r=Q.rotate(m.q,v);for i=1,3 do r[i]=r[i]+m.p[i]end;return r
 end
 A.inverse=function(m)return{q=m.q,p=m.p,inverse=true}end
 f.pos={[1]={0,0,0},[2]={.05,0,0},[3]={0,0,0}};f.rot={[1]={0,0,0,1},[2]={0,0,0,1},[3]={0,0,0,1}}
 local U={num_meshes=function()return 1 end,mesh=function()return ffi.cast('void *',700000)end,
 local_position=function(_,n)return f.pos[n]end,local_rotation=function(_,n)return f.rot[n]end,
 set_local_position=function(handle,n,v)assert(handle=='arm','Animated body must never be written');f.sets=f.sets+1;f.pos[n]=f.float_setter and quantized(v)or v end,
 set_local_rotation=function(handle,n,q)assert(handle=='arm','Animated body must never be written');f.sets=f.sets+1;f.rotation_sets=(f.rotation_sets or 0)+1;f.rot[n]=f.float_rotation_setter and quantized_q(q)or q end}
 U.world_pose=function(handle,n)
  if handle=='arm'and f.world_nodes and f.world_nodes[n]then
   local p=f.pos[n];return{q=f.rot[n],p={p[1]+(f.world_mismatch and 1 or 0),p[2],p[3]}}
  end
  return{q={0,0,math.sin(f.angle/2),math.cos(f.angle/2)},p={f.travel+n*.01+(handle=='fps'and 1 or 0),.2,0}}
 end
 U.world_position=function(handle,n)return U.world_pose(handle,n).p end
 local sr={Unit=U,Vector3=V,Quaternion=Q,Matrix4x4=A,World={update_unit=function()f.publishes=f.publishes+1 end}}
 local words={[100000+0x70]=3,[200000+0x70]=107,[100000+0x168]=0,[100000+0x16c]=0,
 [700000+0x80]=800000,[700000+0x84]=0,[800000]=2,[800008]=16,[800016]=1,[800020]=2,
 [300000]=10*65536+2,[300004]=1,[300008]=20*65536+2,[400000]=11,[400004]=12,[400008]=13}
 local pointers={[100000+0x98]=300000,[100000+0xa0]=400000,[100000+0x78]=500000,[200000+0x88]=500000}
 local b={_ptr=function(_,at)return assert(pointers[at],'Unexpected pointer read')end,
 _u32=function(_,at)if pointers[at]~=nil then return pointers[at]end;if pointers[at-4]~=nil then return 0 end;return assert(words[at],'Unexpected word read')end}
 local cal={body='body',world='world',body_context={object=200000}}
 f.a=S.new(b,sr,cal,{{context={object=100000},handle='arm',group='left',valid=function()return f.live end}})
 f.sr=sr;f.words=words;f.pointers=pointers;f.backend=b;f.cal=cal;f.quantized=quantized
 function f.transform(x,y,z,yaw)return{left={source={0,0,0},target={x,y,z},rotation={0,0,math.sin((yaw or 0)/2),math.cos((yaw or 0)/2)}}}end
 function f.world(node,parent)return A.transform(U.world_pose('body',parent),f.pos[node])end
 return f
end
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b))end
local function world_fixture(hash,mismatch)
 local f=fixture();f.world_nodes={[4]=true};f.world_mismatch=mismatch
 f.pos[4]={100.3,200.2,4.9};f.rot[4]={0,0,0,1}
 f.pointers[900000+0x88]=600000;f.pointers[100000+0x78]=600000
 f.words[900000+0x70]=63;f.words[100000+0x70]=4;f.words[800000]=1;f.words[800016]=3
 f.words[300012]=21*65536;f.words[400012]=hash or 0x58D886FB
 function f:new_adapter()
  return S.new(self.backend,self.sr,self.cal,{{context={object=100000},handle='arm',group='left',valid=function()return self.live end,
   parent_context={object=900000},parent_handle='fps'}})
 end
 return f
end
local function world_transform(source,target,source_yaw,target_yaw)
 local function q(a)return{0,0,math.sin(a/2),math.cos(a/2)}end
 return{left={source=source,target=target,rotation=q((target_yaw or 0)-(source_yaw or 0)),
  source_rotation=q(source_yaw or 0),target_rotation=q(target_yaw or 0)}}
end
local f=fixture();assert(f.a.nodes==2,'Skin map must climb FK nodes to linked roots')
assert(f.a:apply(f.transform(0,0,0)));assert(f.sets==0 and f.publishes==0,'Identity placement must stay idle')
f.a:apply(f.transform(.25,-.1,.05));local w=f.world(1,11);near(w[1],.11+.25);near(w[2],.2-.1);near(w[3],.05)
local before=f.sets;f.a:apply(f.transform(.25,-.1,.05));assert(f.sets==before,'Unchanged pose must coalesce')
f.angle=1.2;f.travel=.3;f.a:apply(f.transform(.25,-.1,.05));w=f.world(1,11);near(w[1],.41+.25);near(w[2],.1);near(w[3],.05)
assert(f.pos[2][1]==.05,'Local animated descendants must stay untouched')
f.a:restore();near(f.pos[1][1],0);near(f.pos[3][1],0)
f=fixture();f.a:apply(f.transform(0,0,0,math.pi/2));w=f.world(1,11);near(w[1],-.2);near(w[2],.11);near(f.rot[1][3],math.sin(math.pi/4))
f.a:restore();near(f.rot[1][4],1)
f=fixture();f.float_rotation_setter=true
for step=1,8 do
 local yaw=step*.0001;local count=f.rotation_sets or 0
 assert(f.a:apply(f.transform(0,0,0,yaw)));assert(f.rotation_sets==count+2,'Slow target rotation below .16 degrees must reach every linked root')
 near(f.rot[1][3],math.sin(yaw/2));before=f.sets
 assert(f.a:apply(f.transform(0,0,0,yaw)));assert(f.sets==before,'A truly unchanged float32 orientation must coalesce')
end
local signed=f.transform(0,0,0,.0008);for i=1,4 do signed.left.rotation[i]=-signed.left.rotation[i]end
before=f.sets;assert(f.a:apply(signed));assert(f.sets==before,'Quaternion sign equivalence must not cause another render write')
f.rot[1]={0,0,math.sin(.001/2),math.cos(.001/2)};assert(f.a:restore());near(f.rot[1][3],0)
f=fixture();f.a:apply(f.transform(.2,0,0,.01));f.rot[1]={0,0,math.sin(.3/2),math.cos(.3/2)}
assert(not pcall(f.a.apply,f.a,f.transform(.3,0,0,.02)),'A real foreign orientation writer must still refuse')
local foreign_rotation=f.rot[1];assert(f.a:restore());assert(f.rot[1]==foreign_rotation,'Cleanup must preserve a foreign orientation')
f=fixture();f.a:apply(f.transform(.2,0,0));f.pos[1]={.8,0,0};assert(not pcall(f.a.apply,f.a,f.transform(.3,0,0)),'Foreign pose writer must refuse');f.a:restore();near(f.pos[1][1],.8)
f=fixture();f.a:apply(f.transform(.2,0,0));f.live=false;before=f.sets;f.a:restore();assert(f.sets==before,'Retired renderer must never be restored')
f=fixture();f.words[300000]=11*65536+2;assert(not pcall(f.a.apply,f.a,f.transform(.2,0,0)),'Changed skinning assignment must refuse')
for _,offset in ipairs({0x78,0x98,0xa0})do
 f=fixture();f.a:apply(f.transform(.2,0,0));f.pointers[100000+offset]=0;before=f.sets
 assert(f.a:restore());assert(f.sets==before,'Retired null graph must not receive restoration writes')
 assert(not pcall(f.a.apply,f.a,f.transform(.2,0,0)),'Null graph must refuse new render writes')
end
f=fixture();f.pointers[900000+0x88]=600000;f.pointers[100000+0x78]=600000;f.words[900000+0x70]=63
local a=S.new(f.backend,f.sr,f.cal,{{context={object=100000},handle='arm',group='left',valid=function()return f.live end,
 parent_context={object=900000},parent_handle='fps'}})
assert(a:apply(f.transform(0,0,0,math.pi/2)))
local world=f.sr.Matrix4x4.transform(f.sr.Unit.world_pose('fps',11),f.pos[1])
near(world[1],-.2);near(world[2],1.11);assert(a:restore())
for _,hash in ipairs({0x58D886FB,0x5A4BBAA2})do
 f=world_fixture(hash);a=f:new_adapter();assert(a.nodes==1)
 assert(a:apply(world_transform({100,200,4.5},{10,20,1})))
 near(f.pos[4][1],10.3);near(f.pos[4][2],20.2);near(f.pos[4][3],1.4)
 before=f.sets
 assert(a:apply(world_transform({200,300,8},{10,20,1},.8,0)))
 assert(f.sets==before,'Moving native weapon must not move the camera-locked auxiliary root')
 assert(a:apply(world_transform({200,300,8},{110,120,1},.8,math.pi/2)))
 near(f.pos[4][1],109.8);near(f.pos[4][2],120.3);near(f.pos[4][3],1.4)
 near(f.rot[4][3],math.sin(math.pi/4));assert(a:restore())
 near(f.pos[4][1],100.3);near(f.pos[4][2],200.2);near(f.pos[4][3],4.9);near(f.rot[4][4],1)
end
f=world_fixture();a=f:new_adapter();assert(a:apply(world_transform({100,200,4.5},{10,20,1})))
f.pos[4]={50,60,70};assert(not pcall(a.apply,a,world_transform({100,200,4.5},{11,20,1})))
assert(a:restore());near(f.pos[4][1],50);near(f.pos[4][2],60)
f=world_fixture(0x12345678);assert(not pcall(f.new_adapter,f),'Unknown world-space root must refuse')
f=world_fixture(nil,true);assert(not pcall(f.new_adapter,f),'World/local mismatch must refuse')
f=world_fixture();f.pos[4][1]=1e6;assert(not pcall(f.new_adapter,f),'Absolute world bounds must remain finite and bounded')
f=world_fixture();a=f:new_adapter();assert(not pcall(a.apply,a,world_transform({90,200,4.5},{10,20,1})))
assert(f.sets==0,'Unrelated auxiliary root outside two metres must refuse before any write')
f=world_fixture();f.float_setter=true;f.pos[4]=f.quantized({218.905,-155.735,25.3134})
local baseline={unpack(f.pos[4])};a=f:new_adapter()
local source={218.6,-155.9,24.9};local target={218.851234,-155.712345,25.123456}
local transform=world_transform(source,target,.17,.83)
assert(a:apply(transform));before=f.sets
for _=1,12 do assert(a:apply(transform))end
assert(f.sets==before,'Float32 SDK readback must coalesce rather than appear to be a foreign writer')
transform=world_transform({318.6,-55.9,24.9},{318.923456,-55.823456,25.234567},-.7,1.1)
assert(a:apply(transform));before=f.sets;assert(a:apply(transform));assert(f.sets==before)
assert(a:restore());for i=1,3 do assert(f.pos[4][i]==baseline[i],'Float32 cleanup must restore the exact SDK baseline')end
assert(a:apply(world_transform(source,target,.17,.83)))
f.pos[4][1]=f.pos[4][1]+.001
assert(not pcall(a.apply,a,world_transform(source,target,.17,.83)),'Real foreign movement must still refuse after float32 normalization')
local foreign=f.pos[4][1];assert(a:restore());assert(f.pos[4][1]==foreign)
f=fixture();f.float_setter=true;f.pointers[900000+0x88]=600000;f.pointers[100000+0x78]=600000;f.words[900000+0x70]=63
a=S.new(f.backend,f.sr,f.cal,{{context={object=100000},handle='arm',group='left',valid=function()return f.live end,
 parent_context={object=900000},parent_handle='fps'}})
local frozen_source={1.09,.2,0};local frozen_camera={1.51,.2,0};local compensated
for _,travel in ipairs({{100,200,30,0},{200,300,35,.7}})do
 local yaw=travel[4];local camera={travel[1]+1.51,travel[2]+.2,travel[3]}
 local target={camera[1]-.42*math.cos(yaw),camera[2]-.42*math.sin(yaw),camera[3]}
 compensated=world_transform(frozen_source,target,0,yaw);compensated.left.frame_compensation=true
 compensated.left.source_origin=frozen_camera;compensated.left.target_origin=camera
 assert(a:apply(compensated));before=f.sets;assert(a:apply(compensated));assert(f.sets==before)
 local position=f.sr.Matrix4x4.transform(f.sr.Unit.world_pose('fps',11),f.pos[1])
 local expected={camera[1]-.4*math.cos(yaw),camera[2]-.4*math.sin(yaw),camera[3]}
 for i=1,3 do assert(math.abs(position[i]-expected[i])<.00004,'Stale FPS parent must still place its joint beside the moving camera')end
end
assert(math.abs(f.pos[1][1])>100,'Regression must exercise frame compensation beyond the old local bound')
f.pos[1][1]=f.pos[1][1]+.01
assert(not pcall(a.apply,a,compensated),'Frame compensation must not weaken native local writer ownership')
foreign=f.pos[1][1];assert(a:restore());assert(f.pos[1][1]==foreign)
f=fixture();compensated=world_transform({0,0,0},{100,0,0});compensated.left.frame_compensation=true
compensated.left.source_origin={0,0,0};compensated.left.target_origin={100,0,0}
assert(not pcall(f.a.apply,f.a,compensated),'Normal body palettes must not receive FPS origin compensation')
assert(f.sets==0)
f=fixture();f.float_setter=true;f.pos[1]={.02,.03,.04};f.rot[1]={0,0,math.sin(.1),math.cos(.1)}
a=S.new(f.backend,f.sr,f.cal,{{context={object=100000},handle='arm',group='body',valid=function()return f.live end}})
local function zq(yaw)return{0,0,math.sin(yaw/2),math.cos(yaw/2)}end
local selected={body={bones={[11]={position={.4,.5,.1},rotation=zq(math.pi/2)}},retarget_only=true,
 source={0,0,0},target={1000,2000,3000},rotation=zq(1),frame_compensation=true}}
assert(a:apply(selected));world=f.sr.Matrix4x4.transform(f.sr.Unit.world_pose('body',11),f.pos[1])
near(world[1],.37);near(world[2],.52);near(world[3],.14)
near(f.rot[1][3],math.sin((math.pi/2+.2)/2));near(f.pos[3][1],0);near(f.pos[2][1],.05)
before=f.sets;assert(a:apply(selected));assert(f.sets==before,'Unchanged per-bone targets must coalesce')
-- A missing helper is unowned even if a native/physics writer changes it.
f.pos[3]={4,5,6};assert(a:apply(selected));local same_helper=f.pos[3];assert(same_helper[1]==4 and same_helper[2]==5)
f.travel=100;f.angle=.5;selected.body.bones[11]={position={100.4,.5,.1},rotation=zq(.8)}
assert(a:apply(selected));world=f.sr.Matrix4x4.transform(f.sr.Unit.world_pose('body',11),f.pos[1])
local expected=f.sr.Matrix4x4.transform({p={100.4,.5,.1},q=zq(.8)},{.02,.03,.04})
for i=1,3 do near(world[i],expected[i])end
selected.body.bones={};assert(a:apply(selected));near(f.pos[1][1],.02);near(f.pos[1][2],.03);near(f.pos[1][3],.04)
assert(f.pos[3][1]==4,'Unmapped helper must not be rigidly moved or restored')
selected.body.bones[11]={position={100.4,.5,.1},rotation=zq(.8)};assert(a:apply(selected))
f.pos[1][1]=f.pos[1][1]+.01;assert(not pcall(a.apply,a,selected),'Mapped per-bone local ownership must stay strict')
foreign=f.pos[1][1];assert(a:restore());assert(f.pos[1][1]==foreign and f.pos[3][1]==4)
print('Linked skinning placement: identity, FK map, animated parents, translation, rotation, coalescing and ownership passed')
print('Quaternion target precision: sub-.16-degree motion, exact float32 coalescing, sign equivalence and independent ownership/cleanup guards passed')
print('Verified FPS auxiliary world roots: source-frame anchor, 100m movement, target rotation, bounds, foreign writer and exact restoration passed')
print('Float32 world-root SDK ownership: fractional coordinates, moving/rotated targets, coalescing, exact restore and foreign-write rejection passed')
print('Stale FPS origin compensation: 100m/200m camera movement, view rotation, bounded joint deformation, exact ownership and body refusal passed')
print('Selective TP render-bone targets: native body parent, bind offset/rotation, moving parent, coalescing, untouched helpers and conditional ownership passed')

local function copied_frames(f,yaw,travel,scale)
 local frames={};scale=scale or{1,1,1}
 for node=1,107 do
  local q=zq(yaw);local basis={}
  for axis=1,3 do local v={0,0,0};v[axis]=scale[axis];basis[axis]=f.sr.Quaternion.rotate(q,v)end
  frames[node]={node=node,position={travel+node*.01,.2,0},rotation=q,basis=basis,scale={unpack(scale)}}
 end
 return frames
end
local function copied_world(f,frame,local_position)
 local p=f.sr.Quaternion.rotate(frame.rotation,{local_position[1]*frame.scale[1],local_position[2]*frame.scale[2],local_position[3]*frame.scale[3]})
 for i=1,3 do p[i]=p[i]+frame.position[i]end;return p
end
f=fixture();f.pos[1]={.02,.03,.04};f.rot[1]=zq(.2)
a=S.new(f.backend,f.sr,f.cal,{{context={object=100000},handle='arm',group='body',valid=function()return f.live end}})
local frames=copied_frames(f,.3,100,{2,3,4})
local copied={body={bones={[11]={position={100.4,.5,.1},rotation=zq(.8)}},retarget_only=true,parent_frames=frames,
 source={100,.2,0},target={100,.2,0},rotation=zq(0)}}
f.sr.Unit.world_pose=function()error('Copied parents must not reread SDK world poses')end
f.sr.Matrix4x4.inverse=function()error('Copied parents must not invert an SDK matrix')end
f.sr.Matrix4x4.transform=function()error('Copied parents must not transform through an SDK matrix')end
assert(a:apply(copied));world=copied_world(f,frames[11],f.pos[1])
local offset=f.sr.Quaternion.rotate(zq(.8),{.02,.03,.04})
for i=1,3 do near(world[i],copied.body.bones[11].position[i]+offset[i])end
near(f.rot[1][3],math.sin((.8-.3+.2)/2))
before=f.sets;f.travel=900;f.angle=2;assert(a:apply(copied));assert(f.sets==before)
copied.body.parent_frames=copied_frames(f,.3,200,{2,3,4});copied.body.bones[11].position[1]=200.4
assert(a:apply(copied));world=copied_world(f,copied.body.parent_frames[11],f.pos[1]);near(world[1],200.4+offset[1])
assert(a:restore());near(f.pos[1][1],.02);near(f.pos[1][2],.03);near(f.pos[1][3],.04)

f=fixture();a=S.new(f.backend,f.sr,f.cal,{{context={object=100000},handle='arm',group='weapon',valid=function()return f.live end}})
frames=copied_frames(f,.4,100,{2,3,4})
local weapon={weapon={source={100.11,.2,0},target={100.31,.3,.05},rotation=zq(.7),parent_frames=frames}}
f.sr.Unit.world_pose=function()error('Weapon placement must use the copied TP parent')end
assert(a:apply(weapon));world=copied_world(f,frames[11],f.pos[1])
near(world[1],100.31);near(world[2],.3);near(world[3],.05)
world=copied_world(f,frames[21],f.pos[3]);local rel=f.sr.Quaternion.rotate(zq(.7),{.1,0,0})
near(world[1],100.31+rel[1]);near(world[2],.3+rel[2]);near(world[3],.05)
before=f.sets;f.travel=-900;f.angle=-2;assert(a:apply(weapon));assert(f.sets==before);assert(a:restore())

for _,bad in ipairs({'count','node','position','scale','negative_scale','quaternion','basis'})do
 f=fixture();frames=copied_frames(f,0,0)
 if bad=='count'then frames[107]=nil elseif bad=='node'then frames[11].node=12
 elseif bad=='position'then frames[11].position[1]=0/0 elseif bad=='scale'then frames[11].scale[1]=0
 elseif bad=='negative_scale'then frames[11].scale[1]=-1 elseif bad=='quaternion'then frames[11].rotation[4]=2
 else frames[11].basis[1][1]=.5 end
 local t=f.transform(.1,0,0);t.left.parent_frames=frames
 assert(not pcall(f.a.apply,f.a,t),'Invalid copied '..bad..' must refuse before writes');assert(f.sets==0)
end
f=fixture();a=S.new(f.backend,f.sr,f.cal,{
 {context={object=100000},handle='arm',group='left',valid=function()return f.live end},
 {context={object=100000},handle='arm',group='weapon',valid=function()return f.live end}})
local mixed=f.transform(.1,0,0);mixed.left.parent_frames=copied_frames(f,0,0)
mixed.weapon=f.transform(.1,0,0).left;mixed.weapon.parent_frames=copied_frames(f,0,0)
assert(not pcall(a.apply,a,mixed),'Parts sharing a parent must share one copied frame set');assert(f.sets==0)
print('Copied TP parent frames: per-bone and weapon transforms, nonuniform scale/inverse, stable SDK-independent snapshots, prewrite validation and shared-frame ownership passed')
