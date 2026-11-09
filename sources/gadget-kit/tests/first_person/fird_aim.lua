local A=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_aim.lua')
local n=0;local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));n=n+1 end
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b))end
local function same(a,b)for i=1,#a do near(a[i],b[i])end end
local Z={x=0,y=0,z=0,yaw=0,pitch=0,roll=0}
local function fixture()
    return{projection={position={.2,.8,-.15},rotation={0,0,0,1},fov=1.5},reference={x=.15,y=0,z=-.12},pivot={0,.5,0},
        aim={projection={position={0,.75,0},rotation={0,0,0,1},fov=1.5},reference=Z,pivot={0,.5,0},source_fov=1.5}}
end
test('observed hip and zero-authored native sight endpoints remain exact at the captured FOV',function()
    local c=fixture();local hip=A.blend(c,c.reference,Z,0);same(hip.projection.position,c.projection.position)
    local ads,placement,w=A.blend(c,c.reference,Z,1);same(ads.projection.position,c.aim.projection.position)
    same(ads.projection.rotation,c.aim.projection.rotation);near(ads.projection.fov,1.5);near(w,1)
    assert(placement.x==0 and placement.y==0 and placement.z==0)
end)
test('each endpoint applies its own captured placement baseline and pivot before blending',function()
    local c=fixture();local p={x=.1,y=.02,z=-.03,yaw=10,pitch=0,roll=0}
    local ads=A.blend(c,c.reference,p,1)
    same(ads.projection.position,{.1-.25*math.sin(math.rad(10)),.52+.25*math.cos(math.rad(10)),-.03})
    near(ads.projection.rotation[3],math.sin(math.rad(5)));near(ads.projection.fov,1.5)
    local half=A.blend(c,c.reference,p,.5)
    for i=1,3 do near(half.projection.position[i],(c.projection.position[i]+ads.projection.position[i])*.5)end
    same(c.projection.position,{.2,.8,-.15});same(c.aim.projection.position,{0,.75,0})
end)
test('aim and release finish in100ms with continuous reversal',function()
    local c=fixture();local m=A.new();local _,_,w=m:update(c,c.reference,Z,true,.025);near(w,.15625)
    _,_,w=m:update(c,c.reference,Z,true,.075);near(w,1)
    _,_,w=m:update(c,c.reference,Z,false,.025);near(w,.84375)
    _,_,w=m:update(c,c.reference,Z,true,0);near(w,.84375)
    _,_,w=m:update(c,c.reference,Z,false,.1);near(w,0)
end)
test('weapon changes and explicit handoffs reset the interpolation state',function()
    local c=fixture();local m=A.new();m:update(c,c.reference,Z,true,.1);near(m.weight,1)
    local other=fixture();local _,_,w=m:update(other,other.reference,Z,true,0);near(w,0)
    m:update(other,other.reference,Z,true,.1);assert(m:reset());near(m.weight,0)
end)
test('antipodal quaternion representations take the same physical orientation',function()
    local c=fixture();c.aim.projection.rotation={0,0,0,-1}
    local half=A.blend(c,c.reference,Z,.5);same(half.projection.rotation,{0,0,0,1})
end)
test('missing or incompatible sight captures preserve hip lock without a guessed offset',function()
    for _,failure in ipairs({'missing','lens','quaternion'})do
        local c=fixture()
        if failure=='missing'then c.aim=nil elseif failure=='lens'then c.aim.projection.fov=1 else c.aim.projection.rotation={0,0,0,0}end
        local m=A.new();local cal,p,w,why=m:update(c,c.reference,Z,true,.1)
        assert(cal==c and p==c.reference and w==0 and type(why)=='string',failure)
    end
end)
test('invalid authored values and clock deltas refuse before target output',function()
    local c=fixture();assert(not pcall(A.blend,c,c.reference,{x=1,y=0,z=0},1))
    assert(not pcall(A.blend,c,c.reference,Z,0/0));assert(not pcall(A.new().update,A.new(),c,c.reference,Z,true,-1))
end)
print('FirdPerson calibrated sight targets: '..n..' cases passed')
