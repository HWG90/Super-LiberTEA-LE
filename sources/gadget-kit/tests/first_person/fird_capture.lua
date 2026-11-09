local F=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_person.lua')
local ffi=require('ffi')
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b))end
local function same(a,b)for i=1,#a do near(a[i],b[i])end end
local function multiply(a,b)
    return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function inverse(q)return{-q[1],-q[2],-q[3],q[4]}end
local function rotate(q,p)local v=multiply(multiply(q,{p[1],p[2],p[3],0}),inverse(q));return{v[1],v[2],v[3]}end
local function angle(a)return{0,0,math.sin(a*.5),math.cos(a*.5)}end
local function plus(a,b)return{a[1]+b[1],a[2]+b[2],a[3]+b[3]}end
local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return{...}end})
local handles={ffi.cast('void*',4),ffi.cast('void*',8),ffi.cast('void*',12)}
local camera_pose={p={10,20,30},q=angle(math.pi*.5)}
local local_weapon={.15,.8,-.12};local local_weapon_q=angle(.3)
local positions={[51]=camera_pose.p,[9]=plus(camera_pose.p,rotate(camera_pose.q,local_weapon)),
    [5]=plus(camera_pose.p,rotate(camera_pose.q,{0,.3,-.1})),
    [6]=plus(camera_pose.p,rotate(camera_pose.q,{0,.4,-.1})),
    [11]=plus(camera_pose.p,rotate(camera_pose.q,{-.2,.1,-.1})),[31]=plus(camera_pose.p,rotate(camera_pose.q,{.2,.1,-.1}))}
local topology={[0x10070]=107,[0x20070]=63,[0x40000+50*4]=0x60ED8C39,[0x40000+8*4]=0x4FDD3337,
    [0x30000+44*4]=0x03752C98,[0x30000+67*4]=0x1620B2CE,[0x40000+10*4]=0x03752C98,[0x40000+30*4]=0x1620B2CE,
    [0x31000+44*4]=42*65536+1,[0x31000+67*4]=65*65536+1}
local mutate
local sr={Vector3=V,Quaternion={from_matrix4x4=function(m)return m.q end,to_elements=function(q)return unpack(q)end},
    Application={main_world=function()return 'world'end},World={units=function()if mutate then mutate()end;return handles end},Unit={}}
function sr.Unit.node(handle,name)
    if name=='camera'then assert(handle==handles[2]);return 51 end
    if name=='l_shoulder'then return handle==handles[1]and 45 or 11 end
    if name=='r_shoulder'then return handle==handles[1]and 68 or 31 end
    error('Unexpected node '..tostring(name))
end
function sr.Unit.world_position(handle,node)assert(handle==handles[2]);return assert(positions[node])end
function sr.Unit.world_pose(handle,node)
    assert(handle==handles[2]);if node==51 then return camera_pose end
    if node==5 or node==6 then return{p=positions[node],q=camera_pose.q}end
    assert(node==9);return{p=positions[9],q=multiply(camera_pose.q,local_weapon_q)}
end
function sr.Unit.local_rotation(handle,node)assert(handle==handles[2]and node==6);return{0,0,0,1}end
sr.Matrix4x4={inverse=function(m)return{inverse=true,p=m.p,q=m.q}end,
    transform=function(m,v)assert(m.inverse);return rotate(inverse(m.q),{v[1]-m.p[1],v[2]-m.p[2],v[3]-m.p[3]})end}
local fov=ffi.new('float[1]',1.234);local reads=0;local resource='capture!'
local snapshot={safe=true,camera_kind=6,controller_active=false,body=1,viewmodel=2,camera=0x50000,record=0x80000,player_identity='player',identity='current-weapon-instance',weapon_unit=17,avatar_owner=0x60000,avatar_index=0}
local b={pose_placement={x=.1,y=.2,z=-.1,yaw=5,pitch=6,roll=7},player_snapshot=function()return snapshot end,
    snapshot=function()local out={};for k,v in pairs(snapshot)do out[k]=v end;return out end,_pose_context=function()return{weapon_object=0x70000}end,
    camera_config=function()return{camera_unit=3,forward=.18,up=.04}end,
    _alignment_context=function(_,s)return{object=s.viewmodel==1 and 0x10000 or s.viewmodel==2 and 0x20000 or 0x60000}end,
    _alignment_executable=function()return 0x140000000 end,
    _ptr=function(_,at)local rows={[0x100a0]=0x30000,[0x10098]=0x31000,[0x200a0]=0x40000};return assert(rows[at],at)end,
    _u32=function(_,at)return assert(topology[at],at)end,
    _read=function(_,at,size)
        reads=reads+1
        if at==0x140000000+0x2dcfc0 then assert(size==6);return '\243\015\016\065\052\195'end
        if at==0x70358 then assert(size==8);return resource end
        assert(at==snapshot.camera+0x34 and size==4);return ffi.string(fov,4)
    end}
local captured=F.capture(b,sr)
same(captured.projection.position,local_weapon);same(captured.projection.rotation,local_weapon_q)
same(captured.pivot,{0,.4,-.1});near(captured.projection.fov,1.234);near(captured.source_fov,1.234)
assert(captured.body==handles[1]and captured.fps==handles[2]and captured.camera==handles[3]and reads==5 and captured.weapon_key=='6361707475726521')
assert(captured.reference.roll==7 and captured.identity=='player')
assert(captured.weapon_identity=='current-weapon-instance'and captured.weapon_unit==17)
snapshot.shoulder_aim=true;assert(not pcall(F.capture,b,sr));snapshot.shoulder_aim=false
snapshot.aiming=true;assert(not pcall(F.capture,b,sr));snapshot.aiming=false
snapshot.reloading=true;assert(not pcall(F.capture,b,sr));snapshot.reloading=false
b.action_state=function()return{resource_match=true,l10=235,l11=622}end;assert(not pcall(F.capture,b,sr));b.action_state=nil
snapshot.controller_active=true;assert(not pcall(F.capture,b,sr))
snapshot.controller_active=false;snapshot.camera_kind=4;assert(not pcall(F.capture,b,sr))
snapshot.camera_kind=6
local token={identity=snapshot.identity,player_identity=snapshot.player_identity,request=snapshot.record,
    weapon_key=captured.weapon_key,lens=captured.source_fov,weapon_unit=17,viewmodel=2,body=1,camera=snapshot.camera}
assert(F.capture(b,sr,nil,token))
token.identity='outgoing-weapon';assert(not pcall(F.capture,b,sr,nil,token));token.identity=snapshot.identity
token.lens=1.5;assert(not pcall(F.capture,b,sr,nil,token));token.lens=captured.source_fov
mutate=function()snapshot.identity='incoming-weapon'end;assert(not pcall(F.capture,b,sr));snapshot.identity=token.identity
mutate=function()snapshot.record=0x81000 end;assert(not pcall(F.capture,b,sr));snapshot.record=token.request
mutate=function()snapshot.weapon_unit=18 end;assert(not pcall(F.capture,b,sr));snapshot.weapon_unit=17
mutate=function()resource='othergun'end;assert(not pcall(F.capture,b,sr));resource='capture!'
mutate=function()fov[0]=1.3 end;assert(not pcall(F.capture,b,sr));fov[0]=1.234
mutate=function()snapshot.reloading=true end;assert(not pcall(F.capture,b,sr));snapshot.reloading=false
mutate=nil;assert(F.capture(b,sr,nil,token))
local aim_calls=0
local aim_helper={capture=function(_,owner,frames)
    aim_calls=aim_calls+1;assert(owner.identity==snapshot.identity and frames.fps_context.object==0x20000)
    same(frames.parent.position,positions[5]);same(frames.branch.local_rotation,{0,0,0,1})
    same(frames.weapon.position,positions[9]);same(frames.camera.position,camera_pose.p)
    return{projection={position={0,.7,0},rotation={0,0,0,1},fov=frames.fov},
        reference={x=0,y=0,z=0},pivot={0,.3,-.1},source_fov=frames.fov,method='test-native-reference'}
end}
captured=F.capture(b,sr,nil,token,aim_helper);assert(aim_calls==1 and captured.aim.method=='test-native-reference')
aim_helper.capture=function()return nil,'Sight unavailable'end
captured=F.capture(b,sr,nil,token,aim_helper);assert(captured.aim==nil and captured.aim_reason=='Sight unavailable')
print('FirdPerson capture: FPS camera/weapon poses, full orientation, actual qualified scene lens and ADS refusal passed')
print('FirdPerson automatic capture token: full weapon/request/resource/lens bracket and mid-read action rejection passed')
