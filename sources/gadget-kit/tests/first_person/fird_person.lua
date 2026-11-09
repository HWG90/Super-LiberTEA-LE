local F=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_person.lua')
local A=dofile(NATIVE_ADS_TEST_ROOT..'/src/action_placement.lua')
local P=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_projection.lua')
local Aim=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_aim.lua')
local Retarget=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_retarget.lua')
local function fixture(use_fov,use_presentation,use_aim,use_retarget,use_children,render_driven,native_animation,ready_pose)
 local ffi=require('ffi')
 local f={kind=4,foreign=false,retired=false,time=1,weapon='a',applies=0,restores=0,builds=0,body_writes=0,
  policy_stops=0,native_ads_stops=0,operations={}}
 local world={};local V=setmetatable({x=function(v)return v[1]end,y=function(v)return v[2]end,z=function(v)return v[3]end},{__call=function(_,...)return{...}end})
 local function mul(a,b)return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}end
 local Q={from_elements=function(...)return{...}end,to_elements=function(q)return unpack(q)end,from_matrix4x4=function(m)return m.q end,multiply=mul,identity=function()return{0,0,0,1}end,axis_angle=function(v,a)local t=math.sin(a/2);return{v[1]*t,v[2]*t,v[3]*t,math.cos(a/2)}end}
 Q.rotate=function(q,v)local r=mul(mul(q,{v[1],v[2],v[3],0}),{-q[1],-q[2],-q[3],q[4]});return{r[1],r[2],r[3]}end
 local function weapon_position(node)
  local a=f.camera_yaw or 0;local shift=(node==9 and f.fp_weapon_shift)or f.weapon_shift or{0,0,0}
  return{.2-.8*math.sin(a)+shift[1],.8*math.cos(a)+shift[2],shift[3]}
 end
 local sr={Vector3=V,Quaternion=Q,Application={main_world=function()return world end},
 World={units=function()f.inventory_reads=(f.inventory_reads or 0)+1;return f.inventory or{ffi.cast('void*',12),ffi.cast('void*',16)}end,update_unit=function()error('No body publication permitted')end},
 Unit={world_pose=function(handle,n)assert(not(use_retarget and handle=='fps'),'Retarget mode must read FPS locals instead of its frozen SDK world cache');assert(n==85 or n==9 or n==1);local a=n==1 and(f.body_yaw or 0)or((f.camera_yaw or 0)+((n==9 and f.fp_weapon_yaw)or f.weapon_yaw or 0));return{p=weapon_position(n),q={0,0,math.sin(a*.5),math.cos(a*.5)}}end,world_position=function(handle,n)assert(not(use_retarget and handle=='fps'),'Retarget mode must not read the FPS SDK world cache');if n==91 then return{.2,0,-.04}end;if n==51 then return{.2,0,0}end;if n==85 or n==9 then return weapon_position(n)end;return{n==45 and 1 or -1,0,0}end,
 set_local_position=function()f.body_writes=f.body_writes+1;error('No body writes permitted')end}}
 local bc={index=1,generation=1,units=100,generations=200,object=10000,unit=1}
 local cc={index=2,generation=1,units=100,generations=200,object=20000,unit=2}
 local rc={index=3,generation=1,units=100,generations=200,object=30000,unit=3}
 local wc={index=4,generation=1,units=100,generations=200,object=40000,unit=4}
 local fc={index=5,generation=1,units=100,generations=200,object=60000,unit=5}
 local b={fird_camera_offset={x=0,y=0,z=.04},_u8=function()return f.retired and 2 or 1 end,
 _ptr=function(_,at)local p={[108]=10000,[116]=20000,[124]=30000,[132]=40000,[140]=60000,[40464]=f.waiting and 60000 or 10000,[40024]=50000,[10160]=1000,[60160]=2000,[30464]=f.arm_waiting and 60000 or 10000,[30024]=50000,[10024]=50000};return assert(p[at],at)end,
 _u32=function(_,at)local parent=f.presentation_active and 60000 or 10000;local matrix=f.presentation_active and 70000 or 50000
 local p={[10008]=1,[20008]=2,[30008]=3,[40008]=4,[60008]=5,[1360]=0x8C5570C9,[1336]=0x4FDD3337,[2032]=0x4FDD3337,[2200]=0x60ED8C39,
 [30464]=f.pres_attach_wait and 0 or parent,[30468]=0,[40464]=f.weapon_stays_body and 10000 or parent,[40468]=0,
 [30120]=f.pres_graph_wait and 0 or matrix,[30124]=0,[40120]=f.weapon_stays_body and 50000 or matrix,[40124]=0,[60136]=70000,[60140]=0,[10136]=50000,[10140]=0}
 return assert(p[at],at)end}
 b.player_snapshot=function()return{safe=true,camera_kind=f.kind,controller_active=f.kind==6,aiming=f.legacy_aiming==true,shoulder_aim=f.aim==true,reloading=f.reload==true,player_identity=f.player_identity or 'p',weapon_unit=4,viewmodel=(use_presentation or use_retarget)and 5 or nil,body=1,context=40000,flags=string.rep('\0',9)..string.char(f.action=='crouch'and 32 or 0)..string.rep('\0',14)}end
 b.snapshot=function()local s=b.player_snapshot();s.identity=f.weapon;return s end
 b._pose_context=function()return{weapon_object=50000}end
 b._alignment_context=function(_,s)return s.viewmodel==1 and bc or s.viewmodel==2 and cc or s.viewmodel==4 and wc or rc end
 b.camera_config=function()return{camera_unit=2}end
 b._read=function(_,at,n)if at==50856 or at==40856 then return string.rep(f.weapon,8)end;local angle=f.camera_yaw or 0;local c,s=math.cos(angle),math.sin(angle);local a=ffi.new('float[12]',{c,s,0,0,-s,c,0,0,0,0,1,0});return ffi.string(a,44)end
 f.config={placement={x=0,y=0,z=0}}
 b.action_placement=function(key,action)return A.resolve(f.config,key,action)end
 b.action_state=function()return{resource='4D1C334D294DFA97',resource_match=true,layer_count=31,l14=36,l10=f.firing and 235 or nil,l11=f.firing and 622 or nil,l1=f.action=='crouch'and 16 or 59,l3=f.sprint and 71 or(f.action=='crouch'and 4 or 67)}end
 b.on_foot=function()return true end
 local c={prepare=function()f.policy_prepares=(f.policy_prepares or 0)+1;return true end,
 update=function()f.policy_updates=(f.policy_updates or 0)+1;return true end,
 stop=function()f.policy_stops=(f.policy_stops or 0)+1;return true end}
 local h={update=c.update,stop=c.stop,render_appearance=function()return string.rep('\0',24)..string.char(3,0,0,0)..string.rep('\0',92),f.player_identity or 'p'end}
 local movement={update=function()f.movement_updates=(f.movement_updates or 0)+1;return c.update()end,
  update_fird=function(_,owner,skip)
   f.focus_facade=owner;f.focus_calls=(f.focus_calls or 0)+1
   if skip or not owner:focus_owned(b.player_snapshot())then f.movement_stops=(f.movement_stops or 0)+1;return c.stop()end
   f.focus_updates=(f.focus_updates or 0)+1;return c.update()
  end,
  stop=function()f.movement_stops=(f.movement_stops or 0)+1;if f.movement_stop_fail then return false,'Focus restoration pending'end;return c.stop()end}
 local skin={new=function(_,_,cal,parts)
  f.skin_source,f.skin_object=cal.body,cal.body_context.object
  f.skin_parts=parts
  assert(#parts==2);for _,part in ipairs(parts)do assert(part.valid())end;f.builds=f.builds+1
  return{nodes=1,publishes=0,writes=0,apply=function(self,t)
   f.applies=f.applies+1;f.transform=t;self.writes=self.writes+1
   if render_driven then
    f.publication_order=f.publication_order or{};f.publication_order[#f.publication_order+1]='weapon'
    local native=sr.Unit.world_pose('body',85)
    f.rendered_weapon,f.rendered_rotation=P.apply(t.weapon,native.p,native.q)
   end
   return true end,
  restore=function()f.restores=f.restores+1;f.operations[#f.operations+1]='render restore';if f.restore_fail then return false,'Render restore pending'end;return true end}
 end}
 local fov
 if use_fov then
  fov={is_clean=function()return not f.fov_active end,start=function(self,capture)f.fov_starts=(f.fov_starts or 0)+1;f.fov_active=true;self.lensmatching=true;self.lens=capture.source_fov or capture.projection.fov;return true end,
   update=function()f.fov_updates=(f.fov_updates or 0)+1;return not f.fov_update_fail end,
   stop=function(self)f.fov_stops=(f.fov_stops or 0)+1;if f.fov_end_fail then return false,'Pending lens cleanup'end;f.fov_active=false;self.lensmatching=false;self.lens=nil;return true end}
 end
 local presentation
 if use_presentation then
  presentation={is_clean=function()return not f.presentation_active end,
   start=function(_,s)assert(s.identity==f.weapon,'Presentation start requires the full equipped-weapon snapshot');f.presentation_starts=(f.presentation_starts or 0)+1;f.presentation_active=true;return true end,
   update=function()if f.pres_retire_once then f.pres_retire_once=false;f.presentation_active=false;return false,'Native presentation retired'end;return true end,
   result=function()return{ready=f.presentation_active and not f.pres_wait}end,
   stop=function()f.operations[#f.operations+1]='presentation stop';if f.pres_stop_fail then return false,'Presentation restoration pending'end;f.presentation_active=false;return true end}
 end
 local source
 if use_retarget then
  f.source_origin={100,100,100}
  local function rig(fps)
   local origin=fps and f.source_origin or{0,0,0};local indexed,hashed={},{}
   local function add(node,hash,parent,p,rotation)
    rotation=rotation or{0,0,0,1}
    if fps and node~=51 then
     local yaw=f.source_weapon_yaw or 0;local anim={0,0,math.sin(yaw/2),math.cos(yaw/2)}
     local relative=Q.rotate(anim,{p[1],p[2]-.8,p[3]})
     p={relative[1]+(f.source_weapon_x or 0),relative[2]+.8+(f.source_weapon_y or 0),relative[3]+(f.source_weapon_z or 0)}
     rotation=mul(anim,rotation)
    end
    local basis={};for axis=1,3 do local v={0,0,0};v[axis]=1;basis[axis]=Q.rotate(rotation,v)end
    local row={node=node,hash=hash,parent=parent,position={p[1]+origin[1],p[2]+origin[2],p[3]+origin[3]},rotation=rotation,basis=basis,scale={1,1,1}}
    if indexed[node]then hashed[indexed[node].hash]=nil end
    indexed[node]=row;hashed[hash]=row;return row
   end
   if fps then
    local camera=add(51,0x60ED8C39,nil,{0,0,0});local weapon=add(9,0x4FDD3337,nil,{0,.8,0})
    add(11,0x03752C98,nil,{-.2,.4,0});add(13,0x1CA2CD66,11,{-.4,.6,0});add(14,0x5C0C68D3,13,{-.2,.8,f.source_hand_z or 0})
    add(31,0x1620B2CE,nil,{.2,.4,0});add(33,0x31E34DAC,31,{.4,.6,0});add(35,0x248004F5,33,{.2,.8,0})
    return{by_index=indexed,by_hash=hashed,weapon=weapon,camera=camera}
   end
   for node=1,107 do add(node,0xC00000+node,nil,{0,0,0})end
   local body_yaw=f.body_yaw or 0;add(1,0x12345001,nil,{0,0,0},{0,0,math.sin(body_yaw/2),math.cos(body_yaw/2)})
   local head_shift=f.body_head_shift or{0,0,0}
   add(91,0x8C5570C9,1,{.2+head_shift[1],head_shift[2],-.04+head_shift[3]})
   local weapon_yaw=(f.camera_yaw or 0)+(f.weapon_yaw or 0)
   add(85,0x4FDD3337,1,weapon_position(85),{0,0,math.sin(weapon_yaw/2),math.cos(weapon_yaw/2)})
   add(45,0x03752C98,nil,{0,.3,-.15});add(47,0x1CA2CD66,45,{-.1,.55,-.15});add(48,0x5C0C68D3,47,{0,.8,-.15})
   add(68,0x1620B2CE,nil,{.4,.3,-.15});add(70,0x31E34DAC,68,{.5,.55,-.15});add(72,0x248004F5,70,{.4,.8,-.15})
   return{by_index=indexed,by_hash=hashed}
  end
  source={new=function(_,cal)
   assert(cal.fps_context==fc and not f.presentation_active);f.source_builds=(f.source_builds or 0)+1
   return{sample=function(_,expected)
    assert(expected.identity==f.weapon and not f.presentation_active)
    f.source_samples=(f.source_samples or 0)+1;return rig(true)
   end}
  end,world=function(_,ctx,count)
   assert(ctx==bc and count==107);f.body_samples=(f.body_samples or 0)+1;return rig(false)
  end}
 end
 local children
 if use_children then
  children={new=function(backend,sdk,cal,weapon,inventory)
   assert(backend==b and sdk==sr and weapon==wc and cal.world==world)
   assert(type(inventory.by_ref)=='table'and #inventory==0,'Children must reuse the existing decoded handle inventory')
   assert(inventory.by_ref[3]and inventory.by_ref[4])
   f.child_inventory=inventory.by_ref;f.children_builds=(f.children_builds or 0)+1
   return{count=3,publishes=0,publish=function(self,expected)
    assert(f.applies>0 and expected.identity==f.weapon,'Child publication must follow parent placement')
    if f.child_changed then return false,'Native attachment changed'end
    if render_driven then
     f.publication_order[#f.publication_order+1]='children'
     local offset=Q.rotate(f.rendered_rotation,{.02,.06,.01})
     f.rendered_scope={f.rendered_weapon[1]+offset[1],f.rendered_weapon[2]+offset[2],f.rendered_weapon[3]+offset[3]}
    end
    self.publishes=self.publishes+3;return true
   end}
  end}
 end
 f.backend=b;f.fov=fov
 local native_ads
 if render_driven or native_animation then
  native_ads={update=function()f.native_ads_updates=(f.native_ads_updates or 0)+1;return true end,
   result=function()return{phase='idle'}end,is_clean=function()return true end,
   stop=function()f.native_ads_stops=(f.native_ads_stops or 0)+1;return true end}
 end
 local camera_frame
 if render_driven then
  camera_frame={read=function(backend,cal,s)
   assert(backend==b and cal.camera_context==cc and s.identity==f.weapon)
   f.camera_reads=(f.camera_reads or 0)+1
   local angle=f.camera_yaw or 0;local c,sn=math.cos(angle),math.sin(angle)
   local offset=b.fird_camera_offset
   local position=f.delivered_camera_position or{.2-sn*offset.y+c*offset.x,c*offset.y+sn*offset.x,offset.z-.04}
   return{position={unpack(position)},basis={{c,sn,0},{-sn,c,0},{0,0,1}}}
  end}
 end
 local m=F.new(b,sr,c,h,movement,c,c,function()return f.foreign end,function()end,{skin=skin,profiles=A,fov=fov,presentation=presentation,
 camera_frame=camera_frame,ready_pose=ready_pose,
 source=source,retarget=use_retarget and Retarget or nil,children=children,render_driven=render_driven,native_animation=native_animation,native_ads=native_ads,
 aim=use_aim and Aim.new()or nil,aim_mode=function()return f.aim_mode or'fird'end,
 lens=function()return f.lens or math.pi*.5 end,clock=function()f.time=f.time+.016;return f.time end,editor=function()return{is_active=function()return f.editing end}end})
 f.capture={weapon_key='6161616161616161',weapon_identity='a',weapon_unit=4,projection={position={0,.8,0},rotation={0,0,0,1},fov=math.pi*.5},pivot={0,.8,0},identity='p',world=world,body='body',fps='fps',camera='camera',body_context=bc,fps_context=fc,camera_context=cc,rows={{node=45,target={.3,0,0}},{node=68,target={-.3,0,0}}}}
 if use_aim then f.capture.aim={projection={position={0,.65,0},rotation={0,0,0,1},fov=math.pi*.5},
  source_fov=math.pi*.5,pivot={0,.65,0},reference={x=0,y=0,z=0}}end
 if use_retarget then
  f.capture.aim={projection={position={0,.8,0},rotation={0,0,0,1},fov=math.pi*.5},
   source_fov=math.pi*.5,pivot={0,.8,0},reference={x=0,y=0,z=0}}
 end
 assert(m:start(f.capture))
 function f:recapture(weapon,fov)
  assert(m:stop());self.weapon=weapon;self.capture.weapon_key=string.rep(string.format('%02x',weapon:byte()),8)
  self.capture.weapon_identity=weapon
  self.capture.identity=self.player_identity or 'p';self.capture.projection.fov=fov or math.pi*.5;assert(m:start(self.capture))
 end
 f.m=m;f.sr=sr;return f
end
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b))end
local f=fixture();assert(f.m:update());near(f.transform.left.target[1],.2);assert(f.body_writes==0 and f.builds==1)
assert(f.m:update());assert(f.builds==1,'Steady state must not rescan render attachments')
f.editing=true;assert(f.m:set_placement({x=.1,y=0,z=0,yaw=90,pitch=0}));assert(f.m:update());near(f.transform.left.target[1],.3);near(f.transform.left.target[2],.8);assert(math.abs(f.transform.left.rotation[3])>.7)
near(f.transform.weapon.target[1],.3);assert(f.m:stop());assert(f.restores>0)
f=fixture();f.m:update();local n=f.applies;f.foreign=true;assert(f.m:update());assert(f.applies==n and f.restores>0)
f=fixture();f.m:update();f.kind=6;n=f.applies;assert(f.m:update());assert(f.applies==n and f.restores>0 and f.m:is_enabled())
f=fixture();f.m:update();f.retired=true;n=f.applies;assert(not f.m:update());assert(f.applies==n and not f.m:is_enabled())
f=fixture();f.config.action_placements=A.saved(f.config,'6161616161616161','crouch',{x=.2,y=0,z=0,yaw=0,pitch=0},false);f.action='crouch'
for i=1,100 do assert(f.m:update())end;near(f.transform.left.target[1],.4)
f.weapon='b';local applies=f.applies;for i=1,3 do assert(f.m:update())end;assert(f.applies==applies and f.m.reference_needed and f.m:placement_target()==nil)
f:recapture('b');for i=1,100 do assert(f.m:update())end;near(f.transform.left.target[1],.2)
local key,owner=f.m:placement_target();assert(key=='6262626262626262'and owner=='b');assert(f.m:stop())
print('FirdPerson linked adapter: editor rotation/position, action/weapon selection, cached discovery, ADS/foreign/retired cleanup; zero body writes')

f=fixture();f.waiting=true;assert(f.m:update());assert(f.applies==0 and f.builds==0 and f.m:is_enabled())
f.waiting=false;assert(f.m:update());assert(f.applies==1 and f.builds==1);assert(f.m:stop())
f=fixture();f.waiting=true;for i=1,3 do assert(f.m:update())end;f.time=f.time+1;assert(not f.m:update());assert(f.applies==0 and not f.m:is_enabled())
print('Native FPS-to-TPV weapon reattachment: bounded wait, no discovery while pending, resume and timeout passed')

f=fixture();f.arm_waiting=true;assert(f.m:update());assert(f.applies==0 and f.builds==0 and f.m:is_enabled());f.arm_waiting=false;assert(f.m:update());assert(f.applies==1);assert(f.m:stop())
print('Verified FPS-owned arm reattachment waits before discovering or writing render nodes')

f=fixture();assert(f.m:update());assert(f.transform.left==f.transform.right and f.transform.left==f.transform.weapon,'All rendered pieces must share one rigid transform')
f.kind=6;assert(f.m:update());local n=f.builds;f.kind=4;assert(f.m:update());assert(f.builds==n+1,'Native ADS handoff must recapture renderer baselines')
assert(f.m:stop());n=f.restores;assert(f.m:stop());assert(f.restores==n,'Successful cleanup must discard retired adapter and be idempotent')
print('Shared grip transform, native ADS cache invalidation and repeated cleanup passed')

f=fixture();assert(f.m:update());local original=f.transform.weapon.target
f.backend.fird_camera_offset={x=.1,y=.2,z=.14};assert(f.m:update())
near(f.transform.weapon.target[1]-original[1],.1);near(f.transform.weapon.target[2]-original[2],.2);near(f.transform.weapon.target[3]-original[3],.1)
f:recapture('b');assert(f.m:update());local rebuilt=f.transform.weapon
assert(f.m:update());for i=1,3 do near(f.transform.weapon.source[i],rebuilt.source[i]);near(f.transform.weapon.target[i],rebuilt.target[i])end
assert(f.m:stop())
f=fixture();assert(f.m:update());n=f.applies;f.lens=.05;assert(f.m:update())
assert(f.m:is_enabled()and f.applies==n and f.m:status()=='FirdPerson waiting for camera projection')
f.lens=math.pi*.5;assert(f.m:update());assert(f.applies==n+1);assert(f.m:stop())
print('FirdPerson head-camera edits move rendered rig; transient lens mismatch yields and resumes')

f=fixture();assert(f.m:update());f.body_yaw=.4;f.camera_yaw=math.pi*.5;assert(f.m:update())
local q=f.transform.weapon.rotation
near(q[1],0);near(q[2],0);near(q[3],0);near(math.abs(q[4]),1)
assert(f.body_writes==0);assert(f.m:stop())
print('FirdPerson live weapon lock counts camera orientation once even when body yaw differs')

f=fixture(true);assert(f.fov_starts==1 and f.fov_active);f.lens=.05
assert(f.m:update());near(f.m.projection_factor,1);assert(f.fov_updates==1)
f.foreign=true;assert(f.m:update());assert(not f.fov_active)
f.foreign=false;assert(f.m:update());assert(f.fov_starts==2 and f.fov_active)
f.kind=6;n=f.applies;assert(f.m:update());assert(f.applies==n and f.m:is_enabled())
f.kind=4;assert(f.m:update());assert(f.applies==n+1)
f.fov_end_fail=true;assert(not f.m:stop());assert(not f.m:is_clean()and f.m:status()=='FirdPerson cleanup pending')
f.fov_end_fail=false;assert(f.m:stop());assert(f.m:is_clean())
f=fixture(true);assert(f.m:update());f.fov_update_fail=true;assert(not f.m:update());assert(not f.m:is_enabled()and not f.fov_active)
print('FirdPerson exact scene-FOV owner: normal, ADS, foreign handoff, error and pending cleanup passed')
f=fixture(true);assert(f.m:update());f.restore_fail=true
assert(not f.m:stop());assert(not f.m:is_clean()and not f.fov_active)
n=f.restores;f.restore_fail=false;assert(f.m:stop());assert(f.restores==n+1 and f.m:is_clean())
print('FirdPerson failed renderer restoration retains ownership while camera/FOV cleanup proceeds')

f=fixture(true);assert(f.m:update());n=f.applies;local inventories=f.builds
f.weapon='b';for _=1,4 do assert(f.m:update())end
assert(f.m.reference_needed and f.m:result().reference_needed and f.m:placement_target()==nil)
assert(f.m:status()=='Fird Person: capture first-person placement for this weapon')
assert(f.applies==n and f.builds==inventories and not f.fov_active and f.m:is_enabled())
f.weapon='a';assert(f.m:update());assert(not f.m.reference_needed and f.applies==n+1 and f.fov_active)
f:recapture('b',math.pi/3);assert(f.m:update());near(f.m.scene_fov,math.pi/3)
f.weapon='a';assert(f.m:update());near(f.m.scene_fov,math.pi*.5)
f.weapon='b';assert(f.m:update());near(f.m.scene_fov,math.pi/3)
assert(not f.m.reference_needed,'Same-player cached weapon capture was discarded across stop')
f.player_identity='new-player';f:recapture('b');assert(f.m:update())
f.weapon='a';assert(f.m:update());assert(f.m.reference_needed,'Old player projection escaped its generation')
assert(f.m:stop())
print('FirdPerson resource-bound references: unknown yields, known reuse, recapture, per-weapon lens and player retirement passed')

f=fixture()
for _,action in ipairs({'aim','reload','sprint','firing'})do
 n=f.applies;f[action]=true;assert(f.m:update());assert(f.applies==n+1 and f.builds==1 and f.m:is_enabled());f[action]=false
end
assert(f.m:update());n=f.applies
f.aim,f.reload,f.sprint,f.firing=true,true,true,true
assert(f.m:update());assert(f.applies==n+1,'Live weapon lock blocked native arm articulation')
assert(f.m:stop())
print('FirdPerson live weapon lock needs no TP neutral calibration during aim/reload/sprint/fire')
f=fixture();assert(f.m:update());f:recapture('b');assert(f.m:update())
for _,action in ipairs({'aim','reload','sprint','firing'})do
 f.weapon='a';assert(f.m:update());n=f.applies
 f.weapon='b';f[action]=true;assert(f.m:update())
 assert(f.applies==n+1 and f.m:is_enabled(),'Cached weapon rebuild waited for an obsolete TP neutral reference')
 f[action]=false;assert(f.m:update());assert(f.applies==n+2)
end
assert(f.m:stop())
print('FirdPerson cached weapon changes immediately lock the live native weapon without latching an action pose')

f=fixture(true)
for _,motion in ipairs({{0,0,0,0,0},{.2,-.1,.1,.6,0},{-.1,.2,-.05,-.8,math.pi*.5}})do
 f.weapon_shift={motion[1],motion[2],motion[3]};f.weapon_yaw=motion[4];f.camera_yaw=motion[5];f.aim=true
 assert(f.m:update());local native=f.sr.Unit.world_pose('body',85)
 local position,rotation=P.apply(f.transform.weapon,f.sr.Unit.world_position('body',85),native.q)
 local a=f.camera_yaw;local relative=P.capture(position,rotation,{.2,0,0},{0,0,math.sin(a*.5),math.cos(a*.5)})
 near(relative.position[1],0);near(relative.position[2],.8);near(relative.position[3],0)
 near(relative.rotation[1],0);near(relative.rotation[2],0);near(relative.rotation[3],0);near(math.abs(relative.rotation[4]),1)
 assert(f.transform.weapon==f.transform.right and f.transform.weapon==f.transform.left and f.body_writes==0)
end
assert(f.m:stop())
print('FirdPerson moving weapon/camera and shoulder aim stay locked to captured FP position/orientation with zero body writes')

f=fixture(true,true);f.pres_wait=true;assert(f.m:update());assert(f.presentation_active and f.applies==0 and f.builds==0)
f.pres_wait=false;f.pres_attach_wait=true;assert(f.m:update());assert(f.applies==0 and f.builds==0 and f.m:is_enabled())
f.pres_attach_wait=false;f.pres_graph_wait=true;assert(f.m:update());assert(f.applies==0 and f.builds==0)
f.pres_graph_wait=false;assert(f.m:update());assert(f.applies==1 and f.skin_source=='fps'and f.skin_object==60000)
assert(f.m.animation_source=='first_person_rig'and f.body_writes==0)
f.weapon_shift={.2,.1,-.1};f.weapon_yaw=.7;assert(f.m:update())
local native=f.sr.Unit.world_pose('fps',9);local position,rotation=P.apply(f.transform.weapon,f.sr.Unit.world_position('fps',9),native.q)
near(position[1],.2);near(position[2],.8);near(position[3],0);near(rotation[3],0);near(math.abs(rotation[4]),1)
f.operations={};f.kind=6;f.pres_stop_fail=true;assert(f.m:update());assert(f.presentation_active and f.m:is_enabled())
assert(f.operations[1]=='render restore'and f.operations[2]=='presentation stop')
f.pres_stop_fail=false;assert(f.m:update());assert(not f.presentation_active and f.m:is_enabled())
f.kind=4;assert(f.m:update());assert(f.presentation_active and f.presentation_starts==2 and f.skin_source=='fps')
f.pres_retire_once=true;assert(f.m:update());assert(f.m:is_enabled()and not f.presentation_active)
assert(f.m:update());assert(f.presentation_active and f.presentation_starts==3)
f.operations={};f.pres_stop_fail=true;assert(not f.m:stop());assert(f.operations[1]=='render restore'and f.operations[2]=='presentation stop')
assert(not f.m:is_clean()and not f.fov_active)
f.pres_stop_fail=false;assert(f.m:stop());assert(f.m:is_clean()and not f.presentation_active and f.body_writes==0)
print('FirdPerson native FPS presentation: attachment/graph acknowledgement, FPS parent palette and weapon lock, ADS yield and ordered cleanup passed')

f=fixture(true,true);f.weapon_stays_body=true
f.weapon_shift={.3,-.2,.1};f.weapon_yaw=.8;f.fp_weapon_shift={-.1,.2,-.05};f.fp_weapon_yaw=-.4
assert(f.m:update());assert(f.transform.left==f.transform.right and f.transform.left~=f.transform.weapon)
for _,part in ipairs(f.skin_parts)do
 assert(part.parent_handle==(part.group=='weapon'and'body'or'fps'))
 assert(part.parent_context.object==(part.group=='weapon'and 10000 or 60000))
end
for _,entry in ipairs({{'fps',9,f.transform.left},{'body',85,f.transform.weapon}})do
 local pose=f.sr.Unit.world_pose(entry[1],entry[2])
 local position,rotation=P.apply(entry[3],f.sr.Unit.world_position(entry[1],entry[2]),pose.q)
 near(position[1],.2);near(position[2],.8);near(position[3],0);near(rotation[3],0);near(math.abs(rotation[4]),1)
end
n=f.builds;f.weapon_stays_body=false;assert(f.m:update());assert(f.builds==n+1 and f.transform.left==f.transform.weapon)
f.operations={};assert(f.m:prepare_native_ads(f.backend:snapshot()))
assert(f.m:is_enabled()and not f.presentation_active and f.fov_active and f.operations[1]=='render restore'and f.operations[2]=='presentation stop')
local stale=f.backend:snapshot();stale.identity='retired';assert(not f.m:prepare_native_ads(stale));assert(f.m:is_enabled())
assert(f.m:stop());assert(f.body_writes==0)
print('FirdPerson mixed parents: native FPS arms and body/FPS weapon share one fixed target; native ADS preparation preserves intent')

f=fixture(true,true,true);f.weapon_stays_body=true;assert(f.m:update());near(f.transform.weapon.target[2],.8)
f.aim=true;for _=1,12 do assert(f.m:update())end
near(f.m:result().aim_weight,1);near(f.transform.left.target[2],.65);near(f.transform.weapon.target[2],.65)
f.config.action_placements=A.saved(f.config,'6161616161616161','ads',{x=.05,y=.02,z=-.01,yaw=10,pitch=0,roll=0},false)
assert(f.m:update());near(f.transform.left.target[1],.25);near(f.transform.weapon.target[2],.67);near(f.transform.weapon.target[3],-.01)
f.aim_mode='native';for _=1,12 do assert(f.m:update())end
near(f.m:result().aim_weight,0);near(f.transform.weapon.target[2],.8)
assert(f.m:stop());assert(f.body_writes==0)
print('FirdPerson calibrated ADS blend applies saved ADS placement to the same locked arm/weapon target and yields to native option')

f=fixture(true);assert(f.m:update());assert(f.m:stop())
f.capture.support_grip={key='6161616161616161',position={.1,.2,.3},tag={resource='grip-resource',l10=235,l11=585}}
f.capture.aim={projection={position={0,.7,-.02},rotation={0,0,0,1},fov=math.pi*.5},
 reference={x=.01,y=0,z=0,yaw=1,pitch=2,roll=3},pivot={0,.4,0},source_fov=math.pi*.5,method='native-zero-placement'}
assert(f.m:start(f.capture));assert(f.m:stop())
local state=f.m:reference_status()
assert(state.known and state.cached_ready and state.safe and state.neutral and state.camera_kind==4 and state.controller_active==false)
assert(state.weapon_key=='6161616161616161'and state.weapon_identity=='a'and state.player_identity=='p')
local cached=assert(f.m:cached_capture());assert(cached.weapon_key==state.weapon_key and cached.weapon_identity=='a'and cached.weapon_unit==4)
cached.projection.position[1]=.6;cached.reference.x=.3;cached.support_grip.position[1]=.7;cached.support_grip.tag.l11=622
cached.aim.projection.position[1]=.6;cached.aim.reference.roll=30;cached.aim.pivot[1]=.4
cached=assert(f.m:cached_capture());near(cached.projection.position[1],0);near(cached.reference.x,0)
near(cached.support_grip.position[1],.1);assert(cached.support_grip.tag.l11==585)
near(cached.aim.projection.position[1],0);near(cached.aim.reference.roll,3);near(cached.aim.pivot[1],0)
near(cached.aim.source_fov,math.pi*.5)
assert(f.m:start(cached));assert(f.m:update());assert(f.m:stop())
f.weapon='b';state=f.m:reference_status();assert(not state.known and not state.cached_ready and f.m:cached_capture()==nil)
f:recapture('b',math.pi/3);assert(f.m:update());assert(f.m:stop())
f.weapon='a';cached=assert(f.m:cached_capture());near(cached.source_fov,math.pi*.5)
assert(f.m:start(cached));assert(f.m:update());near(f.m.scene_fov,math.pi*.5);assert(f.m:stop())
for _,action in ipairs({'legacy_aiming','aim','reload','sprint','firing'})do
 f[action]=true;state=f.m:reference_status();assert(state.known and not state.neutral);f[action]=false
end
f.kind=6;state=f.m:reference_status();assert(state.known and not state.cached_ready and not state.neutral and state.controller_active==true)
f.kind=4;f.retired=true;state=f.m:reference_status();assert(state.known and not state.cached_ready and f.m:cached_capture()==nil)
f.retired=false;f.player_identity='replacement';state=f.m:reference_status();assert(not state.known and not state.cached_ready)
print('FirdPerson automatic entry discovery: stopped cache reuse, copied references, unknown resources, neutral actions and retired rig/player guards passed')
f=fixture(true);assert(f.m:stop());n=f.fov_starts;f.weapon='b'
assert(not pcall(f.m.start,f.m,f.capture));assert(f.fov_starts==n and not f.fov_active and f.m:is_clean())
f.weapon='a';f.capture.weapon_identity='outgoing-instance'
assert(not pcall(f.m.start,f.m,f.capture));assert(f.fov_starts==n and f.m:is_clean())
f.capture.weapon_identity='a';f.capture.weapon_unit=7
assert(not pcall(f.m.start,f.m,f.capture));assert(f.fov_starts==n and f.m:is_clean())
f.capture.weapon_unit=4;assert(f.m:start(f.capture));assert(f.m:stop())
print('FirdPerson start refuses stale equipped resource, instance and Unit before acquiring camera/FOV owners')

f=fixture(true,false,true,true);assert(f.m:update())
assert(f.skin_object==10000 and f.skin_source=='body','Retarget mode must keep the TP body as the render parent')
for _,part in ipairs(f.skin_parts)do
 assert(part.parent_context.object==10000 and part.parent_handle=='body')
 assert(part.group=='body'or part.group=='weapon')
end
assert(not f.presentation_active and not f.presentation_starts,'Retarget mode invoked native presentation')
assert(f.transform.body==f.transform.left and f.transform.left==f.transform.right)
assert(f.transform.body.retarget_only and f.transform.body.bones[48]and f.transform.body.bones[72])
assert(f.transform.body.parent_frames==f.transform.weapon.parent_frames and #f.transform.body.parent_frames==107)
near(f.transform.left.source[1],100);near(f.transform.left.source[2],100.8)
near(f.transform.weapon.source[1],.2);near(f.transform.weapon.source[2],.8)
for i=1,3 do near(f.transform.left.target[i],f.transform.weapon.target[i])end
near(f.transform.body.bones[48].position[1],0);near(f.transform.body.bones[48].position[2],.8)
near(f.transform.body.bones[48].position[3],0)
assert(f.source_samples==1 and f.body_samples==1 and f.body_writes==0)
assert(f.m.animation_source=='first_person_bones_on_third_person_models'and f.m.weapon_parent=='third_person_rig')
local target={unpack(f.transform.weapon.target)};local hand={unpack(f.transform.body.bones[48].position)}
f.source_origin={-450,250,10};assert(f.m:update())
for i=1,3 do near(f.transform.weapon.target[i],target[i]);near(f.transform.body.bones[48].position[i],hand[i])end
f.reload=true;f.source_hand_z=.03;assert(f.m:update())
near(f.transform.body.bones[48].position[3],.03)
for i=1,3 do near(f.transform.weapon.target[i],target[i])end
assert(f.source_builds==1 and f.source_samples==3 and f.body_writes==0)
f.source_weapon_y=.03;f.source_weapon_yaw=.1;assert(f.m:update())
near(f.transform.weapon.target[2],target[2]+.03)
assert(math.abs(f.transform.weapon.target_rotation[3])>.04,'Natural FPS weapon animation was canceled')
for i=1,3 do near(f.transform.left.target[i],f.transform.weapon.target[i])end
local animated={unpack(f.transform.weapon.target)};f.weapon_shift={.1,-.1,.02};assert(f.m:update())
for i=1,3 do near(f.transform.weapon.target[i],animated[i])end
assert(f.source_samples==5 and f.body_samples==5,'The TP parent snapshot must be read once per retarget frame')
assert(f.m:prepare_native_ads(f.backend:snapshot()))
assert(f.operations[#f.operations]=='render restore'and f.m:is_enabled()and not f.presentation_active)
n=f.source_samples;f.kind=6;assert(f.m:update());assert(f.source_samples==n)
f.kind=4;f.reload=false;assert(f.m:update());assert(f.source_samples==n+1 and f.builds==2)
assert(f.m:stop());assert(f.body_writes==0 and not f.presentation_starts)
print('FirdPerson retarget manager: TP model links, distant virtual FPS origin, live source reload motion, shared locked weapon target and native ADS handoff passed')

f=fixture(true,false,false,false,true)
local inventory_ffi=require('ffi')
f.inventory={inventory_ffi.cast('void*',12),inventory_ffi.cast('void*',16)}
for ref=6,16005 do f.inventory[#f.inventory+1]=inventory_ffi.cast('void*',ref*4)end
assert(f.m:update());assert(f.inventory_reads==1 and f.children_builds==1 and f.builds==1)
assert(f.child_inventory[16005]and f.m.attachment_count==3 and f.m.attachment_publishes==3)
assert(f.m:update());assert(f.inventory_reads==1 and f.children_builds==1 and f.builds==1,
 'Steady placement must reuse both the render inventory and the selected child handles')
f.child_changed=true;assert(f.m:update());assert(f.inventory_reads==1 and f.m.attachment_reason)
f.child_changed=false;assert(f.m:update());assert(f.inventory_reads==2 and f.children_builds==2 and f.builds==2)
assert(f.m:stop())
print('FirdPerson child inventory performance: one existing 16k-handle pass, decoded map handoff, no steady rescans, and bounded attachment invalidation passed')

f=fixture(true,false,true,true,true,true)
assert(f.m:render_pose());assert(f.applies==0 and not f.source_samples and not f.body_samples)
assert(f.m:update());assert(f.applies==0 and f.builds==0 and not f.source_samples and not f.body_samples,
 'Render-driven lifecycle update must not sample or publish the earlier native pose')
local policy_updates,policy_stops=f.policy_updates,f.policy_stops
local ads_updates,ads_stops=f.native_ads_updates,f.native_ads_stops
local fov_updates,fov_starts,fov_stops=f.fov_updates,f.fov_starts,f.fov_stops
-- The ordinary scene update advances both native rigs after on_update. Only
-- render_pose may sample this epoch and publish the gun followed by its parts.
f.weapon_shift={.2,-.1,.05};f.weapon_yaw=.5;f.body_yaw=.3;f.camera_yaw=.4
f.source_weapon_y=.04;f.source_weapon_yaw=.2
assert(f.m:render_pose());assert(f.applies==1 and f.builds==1 and f.source_samples==1 and f.body_samples==1)
assert(f.m.render_frames==1 and f.publication_order[1]=='weapon'and f.publication_order[2]=='children')
local live=f.sr.Unit.world_pose('body',85)
for i=1,3 do
 near(f.transform.weapon.parent_frames[85].position[i],live.p[i])
 near(f.transform.weapon.source[i],live.p[i]);near(f.rendered_weapon[i],f.transform.body.target[i])
end
near(f.rendered_weapon[1],.2-.84*math.sin(.4));near(f.rendered_weapon[2],.84*math.cos(.4))
local relative=P.capture(f.rendered_weapon,f.rendered_rotation,{.2,0,0},{0,0,math.sin(.2),math.cos(.2)})
near(relative.position[2],.84);near(relative.rotation[3],math.sin(.1))
local function scope_coherent()
 local p=P.capture(f.rendered_scope,f.rendered_rotation,f.rendered_weapon,f.rendered_rotation)
 near(p.position[1],.02);near(p.position[2],.06);near(p.position[3],.01)
end
scope_coherent()
f.weapon_shift={-.1,.15,-.02};f.weapon_yaw=-.6;f.source_weapon_y=.06;f.source_weapon_yaw=-.1
assert(f.m:render_pose());assert(f.source_samples==2 and f.body_samples==2 and f.applies==2)
near(f.rendered_weapon[2],.86*math.cos(.4));near(f.rendered_rotation[3],math.sin(.3/2));scope_coherent()
assert(f.publication_order[3]=='weapon'and f.publication_order[4]=='children')
assert(f.policy_updates==policy_updates and f.policy_stops==policy_stops and f.native_ads_updates==ads_updates and f.native_ads_stops==ads_stops)
assert(f.fov_updates==fov_updates and f.fov_starts==fov_starts and f.fov_stops==fov_stops,
 'Render publication must not acquire/update camera, visibility, DoF, FOV or native ADS owners')
f.kind=6;n=f.applies;assert(f.m:render_pose());assert(f.applies==n and f.source_samples==2 and f.policy_updates==policy_updates)
f.kind=4;assert(f.m:update());f.weapon='b';n=f.applies;assert(f.m:render_pose());assert(f.applies==n and f.m:is_enabled())
f.weapon='a';assert(f.m:update());policy_stops=f.policy_stops;fov_stops=f.fov_stops;ads_stops=f.native_ads_stops
f.retired=true;assert(not f.m:render_pose());assert(f.m:is_enabled()and f.m.render_error)
assert(f.policy_stops==policy_stops and f.fov_stops==fov_stops and f.native_ads_stops==ads_stops,
 'Render failure must defer native owner cleanup to lifecycle update')
assert(not f.m:update());assert(not f.m:is_enabled()and f.policy_stops>policy_stops and f.native_ads_stops>ads_stops)
assert(f.body_writes==0)
print('FirdPerson render-driven placement: fresh post-update body/FPS epochs, native recoil, coherent gun/children and lifecycle-only owner changes passed')

-- Native camera output consumes the previous body epoch. A later animated
-- head must not move the rig relative to that already submitted camera.
f=fixture(true,false,true,true,true,true)
f.delivered_camera_position={.2,0,0};assert(f.m:update());assert(f.m:render_pose())
local fixed_weapon={unpack(f.rendered_weapon)}
local fixed_hand={unpack(f.transform.body.bones[48].position)}
for tick=1,10 do
 f.body_head_shift={.04*math.sin(tick),-.03*math.cos(tick),.02*math.sin(tick*.5)}
 f.weapon_shift={.06*math.cos(tick),.05*math.sin(tick),.01*math.cos(tick*.5)}
 assert(f.m:render_pose())
 for i=1,3 do near(f.rendered_weapon[i],fixed_weapon[i]);near(f.transform.body.bones[48].position[i],fixed_hand[i])end
 scope_coherent()
end
f.delivered_camera_position={.3,-.2,.04};assert(f.m:render_pose())
for i,delta in ipairs({.1,-.2,.04})do
 near(f.rendered_weapon[i]-fixed_weapon[i],delta)
 near(f.transform.body.bones[48].position[i]-fixed_hand[i],delta)
end
-- An edited head offset takes effect only when the native camera applies it.
f.backend.fird_camera_offset={x=.2,y=.2,z=.2};f.source_weapon_y=.03
assert(f.m:render_pose());near(f.rendered_weapon[1],fixed_weapon[1]+.1)
near(f.rendered_weapon[2],fixed_weapon[2]-.2+.03);near(f.rendered_weapon[3],fixed_weapon[3]+.04)
assert(f.camera_reads==f.m.render_frames and f.body_writes==0);scope_coherent();assert(f.m:stop())
print('FirdPerson camera epoch regression: advancing body/head cannot shake a held camera; delivered camera movement, native animation and gun parts stay coherent')

f=fixture(true,false,false,false,true,false,true)
assert(f.m.native_animation and f.m:is_enabled()and f.m.phase=='FirdPerson native animation active')
assert(f.fov_active and f.m.native_fov_capture.source_fov==math.pi*.5)
for tick=1,12 do
 f.weapon_shift={math.sin(tick)*.12,math.cos(tick)*.08,.04*math.sin(tick*.5)}
 f.weapon_yaw=.2*math.cos(tick);f.body_yaw=.1*math.sin(tick)
 f.aim=tick%2==0;f.reload=tick%3==0;f.sprint=tick%4==0
 assert(f.m:update());assert(f.m:render_pose())
 assert(not f.inventory_reads and f.builds==0 and f.applies==0 and not f.source_samples and not f.children_builds)
 assert(f.body_writes==0 and f.m.writes==0 and f.m.render_frames==0)
 assert(not f.movement_updates and f.focus_updates==tick,'Natural Fird must use its separately qualified view-aligned native locomotion')
end
assert(f.focus_calls==12 and f.m.animation_source=='native_third_person')
f.weapon='b';assert(f.m:update());assert(not f.m.reference_needed and f.m.weapon_key=='6262626262626262')
assert(f.m:prepare_native_ads(f.backend:snapshot()));f.kind=6;assert(f.m:update());assert(f.m:is_enabled())
local focused=f.focus_updates
f.kind=4;assert(f.m:update());assert(f.focus_updates==focused+1)
f.foreign=true;assert(f.m:update());assert(not f.fov_active and f.m:is_enabled()and f.focus_updates==focused+1)
f.foreign=false;assert(f.m:update());assert(f.fov_active and f.applies==0 and not f.inventory_reads)
f.retired=true;assert(not f.m:update());assert(not f.m:is_enabled()and f.body_writes==0 and f.m.writes==0)
assert(f.m:render_pose());assert(f.m:stop());assert(f.m:is_clean())
assert(not f.focus_facade:focus_owned(f.backend:player_snapshot()))
print('Natural Fird Person: native arms/weapon, zero retarget/placement/publication, view-aligned native locomotion, weapon swaps, ADS/foreign handoff and retired cleanup passed')

f=fixture(true,false,false,false,false,false,true)
assert(f.m:update());assert(f.focus_updates==1)
f.movement_stop_fail=true;assert(not f.m:stop());assert(not f.m:is_clean()and not f.m:is_enabled())
assert(not f.focus_facade:focus_owned(f.backend:player_snapshot()),'Stopped Fird must revoke focused movement before pending restoration')
f.movement_stop_fail=false;assert(f.m:stop());assert(f.m:is_clean()and f.body_writes==0 and f.m.writes==0)

-- Fird owns intent; the runtime owns the qualified Update that drains the
-- animation ledger. A pending ledger must keep the controller restorable.
local ready={desired=false,owned=false,requests=0,activations=0,updates=0,stops=0,native_operations=0}
function ready:request(enabled)
 assert(type(enabled)=='boolean');self.requests=self.requests+1;self.desired=enabled
 if enabled then self.activations=self.activations+1 end
 return true
end
function ready:update(context)
 assert(context.phase=='qualified_update'and context.tick>=1,'Only the runtime may drain the ready ledger')
 self.updates=self.updates+1
 if self.owned~=self.desired then self.owned=self.desired;self.native_operations=self.native_operations+1 end
 return true
end
function ready:stop()
 self.stops=self.stops+1;self:request(false)
 return not self.owned,self.owned and'Ready stance restoration pending'or'off'
end
function ready:apply()error('Fird must not directly apply native animation states')end
function ready:restore()error('Fird must not directly restore native animation states')end
f=fixture(true,false,false,false,false,false,true,ready)
assert(ready.activations==1 and ready.requests==1 and ready.desired and not ready.owned)
assert(ready.updates==0 and ready.native_operations==0,'Activation must only queue ready intent')
assert(ready:update({phase='qualified_update',tick=1}));assert(ready.owned and ready.native_operations==1)
for tick=1,12 do
 f.aim=tick%2==0;f.reload=tick%3==0;f.sprint=tick%4==0
 assert(f.m:update());assert(f.m:render_pose())
end
assert(ready.activations==1 and ready.requests==1 and ready.updates==1 and ready.native_operations==1,
 'Natural Fird updates must neither restart ready intent nor drive native animation calls')
assert(not f.m:stop());assert(not f.m:is_enabled()and not f.m:is_clean())
assert(f.m:status()=='FirdPerson cleanup pending'and not ready.desired and ready.owned)
assert(ready.stops==1 and ready.updates==1 and ready.native_operations==1,
 'Stop must retain owned animation cleanup for a later qualified runtime Update')
assert(ready:update({phase='qualified_update',tick=2}));assert(not ready.owned and ready.native_operations==2)
assert(f.m:stop());assert(f.m:is_clean()and f.m:status()=='off'and ready.stops==2)
assert(ready.activations==1 and ready.updates==2 and ready.native_operations==2 and f.body_writes==0 and f.m.writes==0)
print('Natural Fird ready lifecycle: one queued activation, no steady native calls, pending stop and later qualified cleanup passed')

local runtime=dofile(NATIVE_ADS_TEST_ROOT..'/main.lua');local drained=false
for i=1,80 do local name=debug.getupvalue(runtime.on_disable,i);if not name then break end
 if name=='fird'then debug.setupvalue(runtime.on_disable,i,{stop=function()error('synthetic Fird cleanup failure')end})
 elseif name=='controller'then debug.setupvalue(runtime.on_disable,i,{shutdown=function()drained=true;return true end})end
end
local ok=runtime.on_disable();assert(ok==false and drained,'Fird cleanup failure must not block normal FPV shutdown')
print('Independent FPV cleanup runs even when Fird cleanup fails')
