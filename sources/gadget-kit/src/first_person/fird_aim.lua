-- Pure camera-relative targets from two observed FPS poses: saved hip
-- placement and the same native FP request with zero authored ADS offsets.
local M={}
local ZERO={x=0,y=0,z=0,yaw=0,pitch=0,roll=0}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function point(p)
    assert(type(p)=='table','Aim position unavailable');local out={}
    for i=1,3 do assert(finite(p[i])and math.abs(p[i])<2,'Aim position is invalid');out[i]=p[i]end
    return out
end
local function quaternion(q)
    assert(type(q)=='table','Aim orientation unavailable');local norm=0
    for i=1,4 do assert(finite(q[i]),'Aim orientation is invalid');norm=norm+q[i]*q[i]end
    assert(math.abs(norm-1)<.02,'Aim orientation is not normalized')
    norm=math.sqrt(norm);return{q[1]/norm,q[2]/norm,q[3]/norm,q[4]/norm}
end
local function multiply(a,b)
    return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function rotate(q,p)
    local v=multiply(multiply(q,{p[1],p[2],p[3],0}),{-q[1],-q[2],-q[3],q[4]});return{v[1],v[2],v[3]}
end
local function axis(i,a)local q={0,0,0,math.cos(a/2)};q[i]=math.sin(a/2);return q end
local function target(c,p)
    assert(type(c)=='table'and type(c.projection)=='table','Captured aim reference unavailable')
    local fov=c.projection.fov
    assert(finite(fov)and fov>=math.rad(10)and fov<=math.rad(170),'Captured aim lens is invalid')
    local source=point(c.projection.position);local pivot=point(c.pivot or source)
    local saved=c.reference or ZERO;p=p or ZERO
    local angles={}
    for i,k in ipairs({'yaw','pitch','roll'})do
        local a,b=p[k]or 0,saved[k]or 0
        assert(finite(a)and finite(b)and math.abs(a)<=90 and math.abs(b)<=90,'Aim angle exceeds90degrees')
        angles[i]=math.rad(a-b)
    end
    local authored=multiply(multiply(axis(3,angles[1]),axis(1,angles[2])),axis(2,angles[3]))
    local arm=rotate(authored,{source[1]-pivot[1],source[2]-pivot[2],source[3]-pivot[3]});local position={}
    for i,k in ipairs({'x','y','z'})do
        assert(finite(p[k])and finite(saved[k])and math.abs(p[k])<=.5 and math.abs(saved[k])<=.5,'Aim placement exceeds50cm')
        position[i]=pivot[i]+arm[i]+p[k]-saved[k]
    end
    return{position=point(position),rotation=quaternion(multiply(authored,quaternion(c.projection.rotation))),fov=fov}
end
local function slerp(a,b,w)
    local dot=0;for i=1,4 do dot=dot+a[i]*b[i]end
    if dot<0 then b={-b[1],-b[2],-b[3],-b[4]};dot=-dot end
    dot=math.min(1,dot)
    local x,y=1-w,w
    if dot<.9995 then local angle=math.acos(dot);local sine=math.sin(angle);x=math.sin((1-w)*angle)/sine;y=math.sin(w*angle)/sine end
    local out={};for i=1,4 do out[i]=a[i]*x+b[i]*y end;return quaternion(out)
end
function M.available(reference)
    if type(reference)~='table'or type(reference.aim)~='table'then return false,'A calibrated native sight pose is unavailable'end
    local ok,reason=pcall(function()
        local hip=target(reference,reference.reference or ZERO)
        local ads=target(reference.aim,reference.aim.reference or ZERO)
        assert(math.abs(hip.fov-ads.fov)<=.0001,'Hip and sight captures use different display lenses')
    end)
    if ok then return true end
    return false,tostring(reason)
end
function M.blend(reference,hip_placement,ads_placement,weight)
    assert(finite(weight)and weight>=0 and weight<=1,'Aim weight is invalid')
    local hip=target(reference,hip_placement)
    local available,why=M.available(reference)
    if not available then return reference,hip_placement,0,why end
    local ads=target(reference.aim,ads_placement or ZERO);local position={}
    for i=1,3 do position[i]=hip.position[i]+(ads.position[i]-hip.position[i])*weight end
    local projection={position=point(position),rotation=slerp(hip.rotation,ads.rotation,weight),fov=hip.fov}
    return{projection=projection,source_fov=hip.fov,reference=ZERO,pivot=projection.position},ZERO,weight
end
function M.new()
    local self={weight=0};local owner
    function self:reset()self.weight=0;owner=nil;return true end
    function self:update(reference,hip_placement,ads_placement,aiming,dt)
        if owner~=reference then self.weight=0;owner=reference end
        assert(finite(dt)and dt>=0,'Aim clock delta unavailable')
        local available,why=M.available(reference)
        if not available then self.weight=0;return reference,hip_placement,0,why end
        local target_weight=aiming==true and 1 or 0
        local step=math.min(.1,dt)/.1
        self.weight=target_weight==1 and math.min(1,self.weight+step)or math.max(0,self.weight-step)
        local eased=self.weight*self.weight*(3-2*self.weight)
        return M.blend(reference,hip_placement,ads_placement,eased)
    end
    return self
end
return M
