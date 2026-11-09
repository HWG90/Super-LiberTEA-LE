local P=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_projection.lua')
local count=0
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));count=count+1 end
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b))end
local function same(a,b)for i=1,#a do near(a[i],b[i])end end
local function qsame(a,b)local d=0;for i=1,4 do d=d+a[i]*b[i]end;near(math.abs(d),1)end
local function angle(z)return{0,0,math.sin(z*.5),math.cos(z*.5)}end
local function current_from(local_pose,camera_position,camera_rotation)
    local p,q=P.apply({source={0,0,0},target=camera_position,rotation=camera_rotation},local_pose.position,local_pose.rotation)
    return{position=p,rotation=q,frame_origin=camera_position,frame_rotation=camera_rotation}
end
local I={0,0,0,1};local B={{1,0,0},{0,1,0},{0,0,1}}
local zero={x=0,y=0,z=0,yaw=0,pitch=0,roll=0}
local function fixture()
    local c={reference=zero,pivot={.1,.8,-.1},projection={position={.1,.8,-.1},rotation=angle(.3),fov=math.pi*.5}}
    return c,{position={-.2,.7,.05},rotation=angle(-.2)}
end
test('camera-relative FPS capture retains full position and native weapon orientation',function()
    local r=P.capture({10,21,30},angle(math.pi*.5+.3),{10,20,30},angle(math.pi*.5))
    same(r.position,{1,0,0});qsame(r.rotation,angle(.3))
end)
test('equal projections lock the current TP weapon exactly onto the complete FPS pose',function()
    local c,r=fixture();r.position={9.8,20.7,30.05};local t,info=P.lock(c,r,{10,20,30},B,zero,math.pi*.5)
    local p,q=P.apply(t,{9.8,20.7,30.05},r.rotation)
    same(p,{10.1,20.8,29.9});qsame(q,c.projection.rotation);near(info.factor,1)
end)
test('moving native weapon translation is cancelled on every frame',function()
    local c,r=fixture()
    for _,position in ipairs({r.position,{.3,.4,-.1},{-.4,.5,.3}})do
        local current={position=position,rotation=r.rotation}
        local t=P.lock(c,current,{0,0,0},B,zero,c.projection.fov)
        local p,q=P.apply(t,position,r.rotation)
        same(p,c.projection.position);qsame(q,c.projection.rotation)
    end
end)
test('moving native weapon rotation is cancelled while relative arm articulation remains',function()
    local c,r=fixture()
    for _,yaw in ipairs({-.2,.4,-1.1})do
        r.rotation=angle(yaw)
        local t=P.lock(c,r,{0,0,0},B,zero,c.projection.fov)
        local p,q=P.apply(t,r.position,r.rotation)
        same(p,c.projection.position);qsame(q,c.projection.rotation)
        for _,hand in ipairs({{.2,.1,-.1},{.3,.05,-.2}})do
            local native=P.apply({source={0,0,0},target=r.position,rotation=r.rotation},hand)
            local rendered=P.apply(t,native)
            local expected=P.apply({source={0,0,0},target=c.projection.position,rotation=c.projection.rotation},hand)
            same(rendered,expected)
        end
    end
end)
test('moving camera and animated weapon keep one fixed camera-relative pivot and quaternion',function()
    local c,r=fixture();local basis={{0,1,0},{-1,0,0},{0,0,1}}
    r.position={3.6,5.4,6.2};r.rotation=angle(-.7)
    local t=P.lock(c,r,{4,5,6},basis,zero,c.projection.fov)
    local p,q=P.apply(t,r.position,r.rotation)
    same(p,{4-.8,5+.1,6-.1});qsame(q,angle(math.pi*.5+.3))
    local relative=P.capture(p,q,{4,5,6},angle(math.pi*.5))
    same(relative.position,c.projection.position);qsame(relative.rotation,c.projection.rotation)
end)
test('body and native aim rotation cannot double or move the locked view orientation',function()
    local c,r=fixture();local basis={{0,1,0},{-1,0,0},{0,0,1}}
    r.position={-.7,-.2,.05};r.rotation=angle(.4)
    local t=P.lock(c,r,{0,0,0},basis,zero,c.projection.fov)
    local p,q=P.apply(t,r.position,r.rotation)
    same(p,{-.8,.1,-.1});qsame(q,angle(math.pi*.5+.3))
end)
test('current head-camera XYZ edits move the entire rendered rig with the real camera',function()
    local c,r=fixture()
    local a=P.camera_anchor({0,0,0},B,{x=0,y=0,z=.04})
    local b=P.camera_anchor({0,0,0},B,{x=.1,y=.2,z=.14})
    local first=P.lock(c,r,a,B,zero,c.projection.fov)
    local second=P.lock(c,r,b,B,zero,c.projection.fov)
    same(first.source,second.source)
    local x=P.apply(first,r.position);local y=P.apply(second,r.position)
    same({y[1]-x[1],y[2]-x[2],y[3]-x[3]},{.1,.2,.1})
end)
test('vertical camera look uses body yaw for horizontal head offset like the native camera helper',function()
    local basis={{1,0,0},{0,0,1},{0,-1,0}}
    same(P.camera_anchor({10,20,30},basis,{x=.1,y=.2,z=.04},{0,1,0}),{10.1,20.2,30.04})
end)
test('authored XYZ and all three placement angles are measured against the captured saved placement',function()
    local c,r=fixture();c.reference={x=.1,y=.2,z=-.1,yaw=10,pitch=20,roll=30}
    local v={x=.2,y=.3,z=0,yaw=10,pitch=20,roll=30}
    local t=P.lock(c,r,{0,0,0},B,v,c.projection.fov)
    same(t.target,{.2,.9,0});qsame(t.rotation,angle(.5))
    v.roll=60;t=P.lock(c,r,{0,0,0},B,v,c.projection.fov)
    same(t.target,{.2,.9,0})
    local _,q=P.apply(t,r.position,r.rotation);assert(math.abs(q[2])>.1,'Roll was discarded')
end)
test('projection law matches the calibrated pivot ray and apparent scale without changing the scene lens',function()
    local c,r=fixture();local scene=math.pi/3;local t,info=P.lock(c,r,{0,0,0},B,zero,scene)
    near(t.target[1]/(t.target[2]*math.tan(scene*.5)),c.projection.position[1]/(c.projection.position[2]*math.tan(c.projection.fov*.5)))
    near(1/(t.target[2]*math.tan(scene*.5)),1/(c.projection.position[2]*math.tan(c.projection.fov*.5)))
    near(info.factor,math.sqrt(3));near(c.projection.fov,math.pi*.5);near(scene,math.pi/3)
end)
test('transient narrow ADS lenses yield without clamping or corrupting captured references',function()
    local c,r=fixture();local t=P.lock(c,r,{0,0,0},B,zero,.05);assert(t==nil)
    same(r.position,{-.2,.7,.05});same(c.projection.position,{.1,.8,-.1})
    t=P.lock(c,r,{0,0,0},B,zero,c.projection.fov);assert(t)
    for _,fov in ipairs({0,0/0,math.huge,4})do assert(P.lock(c,r,{0,0,0},B,zero,fov)==nil)end
end)
test('exact captured projection locks an attachment behind the eye without waiting for positive depth',function()
    local c,r=fixture();c.projection.position={.1,-.04,-.1};c.pivot={.1,-.04,-.1}
    local t,info=P.lock(c,r,{0,0,0},B,zero,c.projection.fov)
    local p,q=P.apply(t,r.position,r.rotation)
    same(p,c.projection.position);qsame(q,c.projection.rotation);near(info.factor,1)
    assert(P.lock(c,r,{0,0,0},B,zero,math.pi/3)==nil)
end)
test('a frozen FPS world origin can target a moving camera without expanding either local pose bound',function()
    local c,r=fixture();r.frame_origin={0,0,0}
    local camera={100,200,30};local basis={{0,1,0},{-1,0,0},{0,0,1}}
    local t=P.lock(c,r,camera,basis,zero,c.projection.fov)
    local p,q=P.apply(t,r.position,r.rotation)
    local relative=P.capture(p,q,camera,angle(math.pi*.5))
    same(relative.position,c.projection.position);qsame(relative.rotation,c.projection.rotation)
    assert(t.frame_compensation);same(t.source_origin,{0,0,0});same(t.target_origin,camera)
    r.frame_origin=nil;assert(not pcall(P.lock,c,r,camera,basis,zero,c.projection.fov),'Unqualified source drift must still refuse')
    r.frame_origin={10,0,0};assert(not pcall(P.lock,c,r,camera,basis,zero,c.projection.fov),'Corrupt source-relative pose must still refuse')
    r.frame_origin={0,0,0};assert(not pcall(P.lock,c,r,{1e6,200,30},basis,zero,c.projection.fov))
end)
test('natural following preserves the exact authored base when the native source is neutral',function()
    local c=fixture();local n={position={0,.6,-.05},rotation=angle(.1),fov=c.projection.fov}
    c.reference={x=.15,y=0,z=-.12,yaw=10,pitch=5,roll=2}
    local current=current_from(n,{10,20,30},angle(.7))
    local fixed=P.lock(c,current,{100,200,40},B,c.reference,c.projection.fov)
    local t,info=P.follow(c,current,{100,200,40},B,c.reference,c.projection.fov,n)
    same(t.target,fixed.target);qsame(t.target_rotation,fixed.target_rotation);assert(info.animated)
    same(info.native_position_delta,{0,0,0});qsame(info.native_rotation_delta,I)
end)
test('native recoil reload translation and rotation are preserved immediately without smoothing',function()
    local c=fixture();local n={position={0,.6,-.05},rotation=angle(.1),fov=c.projection.fov}
    local a={position={.04,.57,-.03},rotation=angle(.3)}
    local current=current_from(a,{10,20,30},angle(.7))
    local t=P.follow(c,current,{0,0,0},B,zero,c.projection.fov,n)
    local p,q=P.apply(t,current.position,current.rotation)
    same(p,{.1+math.cos(.2)*.04+math.sin(.2)*.03,.8+math.sin(.2)*.04-math.cos(.2)*.03,-.08})
    qsame(q,angle(.5))
    a.position={-.05,.62,-.07};a.rotation=angle(-.2);current=current_from(a,{10,20,30},angle(.7))
    t=P.follow(c,current,{0,0,0},B,zero,c.projection.fov,n)
    qsame(t.target_rotation,angle(0))
end)
test('common FPS camera motion and stale world origins cancel while apparent weapon animation stays intact',function()
    local c=fixture();local n={position={0,.6,-.05},rotation=angle(.1),fov=c.projection.fov}
    local a={position={.03,.58,-.04},rotation=angle(.25)}
    local first=P.follow(c,current_from(a,{0,0,0},I),{218,-155,25},B,zero,c.projection.fov,n)
    local second=P.follow(c,current_from(a,{200,300,40},angle(1.2)),{218,-155,25},B,zero,c.projection.fov,n)
    same(first.target,second.target);qsame(first.target_rotation,second.target_rotation)
end)
test('the same animation delta remains present throughout hip to ADS base changes',function()
    local c=fixture();local n={position={0,.6,-.05},rotation=angle(.1),fov=c.projection.fov}
    local a={position={.04,.57,-.03},rotation=angle(.3)};local current=current_from(a,{0,0,0},I)
    for _,weight in ipairs({0,.5,1})do
        local base={projection={position={.1*(1-weight),.8-.2*weight,-.1+.05*weight},rotation=angle(.3-.2*weight),fov=n.fov},reference=zero}
        local still=P.follow(base,current_from(n,{0,0,0},I),{0,0,0},B,zero,n.fov,n)
        local animated=P.follow(base,current,{0,0,0},B,zero,n.fov,n)
        local distance=0;for i=1,3 do distance=distance+(animated.target[i]-still.target[i])^2 end
        near(distance,.04^2+.03^2+.02^2);qsame(animated.target_rotation,angle(.5-.2*weight))
        if weight==1 then same(animated.target,a.position);qsame(animated.target_rotation,a.rotation)end
    end
end)
test('body weapon rebasing shares the full animated arm target and discards selective bone policies',function()
    local c=fixture();local n={position={0,.6,-.05},rotation=angle(.1),fov=c.projection.fov}
    local current=current_from({position={.04,.57,-.03},rotation=angle(.3)},{0,0,0},I)
    local common=P.follow(c,current,{0,0,0},B,zero,n.fov,n)
    common.bones={[1]={}};common.retarget_only=true
    local body={position={.2,.7,-.1},rotation=angle(-.4)};local t=P.rebase(common,body)
    local p,q=P.apply(t,body.position,body.rotation)
    same(p,common.target);qsame(q,common.target_rotation)
    assert(t.frame_compensation==false and t.bones==nil and t.retarget_only==nil)
    assert(not pcall(P.rebase,common,{position={100,200,30},rotation=I}))
end)
test('natural following refuses unavailable or incompatible reference frames instead of silently pinning the gun',function()
    local c=fixture();local current=current_from(c.projection,{0,0,0},I)
    local t,why=P.follow(c,current,{0,0,0},B,zero,c.projection.fov,nil)
    assert(t==nil and why:match('reference'))
    current.frame_rotation=nil;t,why=P.follow(c,current,{0,0,0},B,zero,c.projection.fov,c.projection)
    assert(t==nil and why:match('camera'))
    current.frame_rotation=I
    assert(P.follow(c,current,{0,0,0},B,zero,c.projection.fov,{position={0,.6,0},rotation=I,fov=math.pi/3})==nil)
end)
test('malformed bases, nonunit quaternions and placements refuse before rendering',function()
    local c,r=fixture()
    assert(not pcall(P.lock,c,r,{0,0,0},{{1,0,0},{0,1,0},{0,0,-1}},zero,c.projection.fov))
    assert(not pcall(P.lock,c,r,{0,0,0},{{1,0,0},{1,0,0},{0,0,1}},zero,c.projection.fov))
    assert(not pcall(P.reference,{0,1,0},{0,0,0,0}))
    assert(not pcall(P.lock,c,r,{0,0,0},B,{x=1,y=0,z=0},c.projection.fov))
end)
print('FirdPerson live camera-relative weapon lock and native arm articulation: '..count..' passed')
