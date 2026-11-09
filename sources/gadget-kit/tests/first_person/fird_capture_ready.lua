local R=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_capture_ready.lua')
local ffi=require('ffi')
local count=0
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));count=count+1 end
local function fixture()
    local f={time=0}
    local s={safe=true,camera_kind=6,aiming=false,controller_active=false,shoulder_aim=false,reloading=false,
        identity='weapon-a',player_identity='player',record=1000,weapon_unit=21,viewmodel=22,body=23,camera=24,context=25}
    local lease={origin={identity=s.identity,player_identity=s.player_identity},request=s.record,
        alignment={kind='pose',context={object=30,weapon_object=31}}}
    f.sample={snapshot=s,lease=lease,controller={phase='running',mode='pose_offset',enabled=true},
        pose={installed=true,armed=true,error=0,expired=false,blend=1,target_weight=1},neutral=true,
        motion={phase='capture',capture_ready=true},
        fov={phase='active',installed=true,armed=true,error=0,last_applied=math.pi*.5,source_degrees=90},
        camera={phase='active',installed=true,armed=true,error=0},
        lens=math.pi*.5,tick=1,target={safe=true,player_identity=s.player_identity,weapon_identity=s.identity,camera_kind=6,weapon_key='0123456789abcdef'}}
    f.ready=R.new(function()if f.clock_error then error('clock failed')end;return f.time end)
    function f:update(time,tick)self.time=time;self.sample.tick=tick;return self.ready:update(self.sample)end
    return f
end
local function settled(f)
    assert(not f:update(0,1));assert(not f:update(.09,2));return f:update(.19,3)
end
test('capture waits for three distinct updates and180ms, then returns the exact owner/lens token',function()
    local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
    local ready,token=f:update(.19,3);assert(ready)
    assert(token.identity=='weapon-a'and token.player_identity=='player'and token.request==1000)
    assert(token.weapon_key=='0123456789abcdef'and token.lens==math.pi*.5 and token.lease==f.sample.lease)
end)
test('repeated sampling in the same runtime tick cannot satisfy the settling window',function()
    local f=fixture();assert(not f:update(0,1));assert(not f:update(.01,2));assert(not f:update(.02,3))
    assert(not f:update(.20,3));assert(f:update(.21,4))
    f.ready:reset();assert(not f:update(.22,5))
end)
test('weapon, body, rig, request and camera identities restart the whole window',function()
    for _,field in ipairs({'weapon_unit','viewmodel','body','record','camera','context'})do
        local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
        f.sample.snapshot[field]=f.sample.snapshot[field]+1
        if field=='record'then f.sample.lease.request=f.sample.snapshot.record end
        assert(not f:update(.19,3),field);assert(not f:update(.28,4));assert(f:update(.39,5),field)
    end
    for _,field in ipairs({'object','weapon_object'})do
        local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
        f.sample.lease.alignment.context[field]=90
        assert(not f:update(.19,3));assert(not f:update(.28,4));assert(f:update(.39,5))
    end
end)
test('replaced leases and weapon-resource keys cannot reuse an earlier readiness window',function()
    local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
    local old=f.sample.lease;f.sample.lease={origin=old.origin,request=old.request,alignment=old.alignment}
    assert(not f:update(.19,3));assert(not f:update(.28,4));assert(f:update(.39,5))
    f.sample.target.weapon_key='fedcba9876543210';assert(not f:update(.4,6))
end)
test('displayed lens must match the accepted FOV owner and live hip source',function()
    for _,field in ipairs({'actual','applied','source'})do
        local f=fixture()
        if field=='actual'then f.sample.lens=.05 elseif field=='applied'then f.sample.fov.last_applied=.5 else f.sample.fov.source_degrees=75 end
        assert(not settled(f),field)
    end
    local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
    f.sample.lens=math.rad(80);f.sample.fov.last_applied=f.sample.lens;f.sample.fov.source_degrees=80
    assert(not f:update(.19,3));assert(not f:update(.28,4));assert(f:update(.39,5))
end)
test('aiming, firing-neutral loss, reload, unsafe gameplay and another camera prevent sampling',function()
    for _,field in ipairs({'aiming','controller_active','shoulder_aim','reloading','unsafe','kind','neutral'})do
        local f=fixture()
        if field=='unsafe'then f.sample.snapshot.safe=false
        elseif field=='kind'then f.sample.snapshot.camera_kind=4
        elseif field=='neutral'then f.sample.neutral=false
        else f.sample.snapshot[field]=true end
        assert(not settled(f),field)
    end
end)
test('all three helper owners must be armed, installed and healthy',function()
    for _,owner in ipairs({'pose','fov','camera'})do for _,failure in ipairs({'armed','installed','error','cleanup','phase'})do
        local f=fixture();local value=f.sample[owner]
        if failure=='armed'or failure=='installed'then value[failure]=false
        elseif failure=='error'then value.error=7
        elseif failure=='cleanup'then value.cleanup_pending=true
        elseif owner~='pose'then value.phase='waiting'
        else value.expired=true end
        assert(not settled(f),owner..'/'..failure)
    end end
end)
test('saved placement blend and explicitly neutral synthetic motion must settle first',function()
    for _,failure in ipairs({'blend','target','motion','motion_phase'})do
        local f=fixture()
        if failure=='blend'then f.sample.pose.blend=.9
        elseif failure=='target'then f.sample.pose.target_weight=0
        elseif failure=='motion'then f.sample.motion.capture_ready=false
        else f.sample.motion.phase='active'end
        assert(not settled(f),failure)
    end
end)
test('mismatched target or lease ownership cannot produce a capture token',function()
    for _,failure in ipairs({'target','target_player','origin','origin_player','done','ended','kind','resource'})do
        local f=fixture()
        if failure=='target'then f.sample.target.weapon_identity='other'
        elseif failure=='target_player'then f.sample.target.player_identity='other'
        elseif failure=='origin'then f.sample.lease.origin.identity='other'
        elseif failure=='origin_player'then f.sample.lease.origin.player_identity='other'
        elseif failure=='done'then f.sample.lease.done=true
        elseif failure=='ended'then f.sample.lease.alignment.ended=true
        elseif failure=='kind'then f.sample.lease.alignment.kind='native'
        else f.sample.target.weapon_key='not-a-resource'end
        assert(not settled(f),failure)
    end
end)
test('pause gaps, clock rollback and tick rollback restart rather than complete a window',function()
    for _,failure in ipairs({'gap','clock','tick'})do
        local f=fixture();assert(not f:update(0,1));assert(not f:update(.09,2))
        local time,tick=.19,3
        if failure=='gap'then time=.8 elseif failure=='clock'then time=.01 else tick=1 end
        assert(not f:update(time,tick),failure);assert(not f:update(time+.09,tick+1));assert(f:update(time+.2,tick+2))
    end
end)
test('nonfinite clocks and malformed ticks never produce readiness',function()
    for _,value in ipairs({0/0,math.huge,-1})do local f=fixture();assert(not f:update(value,1))end
    local f=fixture();f.clock_error=true;assert(not f:update(0,1))
    for _,value in ipairs({0/0,math.huge,-1,.5})do f=fixture();assert(not f:update(0,value))end
end)
test('scene lens reader verifies the existing getter and reads only the camera display lens',function()
    local value=ffi.new('float[1]',{math.pi*.5});local bad=false;local reads=0
    local b={_alignment_executable=function()return 0x100000 end,_read=function(_,at,n)
        reads=reads+1
        if at==0x100000+0x2dcfc0 and n==6 then return bad and'broken'or'\243\015\016\065\052\195'end
        assert(at==0x200000+0x34 and n==4);return ffi.string(value,4)
    end}
    local measured=assert(R.scene_lens(b,{camera=0x200000}));assert(math.abs(measured-math.pi*.5)<.00001 and reads==2)
    bad=true;assert(R.scene_lens(b,{camera=0x200000})==nil)
    bad=false;value[0]=0/0;assert(R.scene_lens(b,{camera=0x200000})==nil)
end)
print('FirdPerson automatic capture readiness: '..count..' owner/lens/timing cases passed')
