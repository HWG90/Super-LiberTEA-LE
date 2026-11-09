-- Pure render placement math. The scene camera and native animation stay owned
-- by the game. Depth conversion matches projection at the weapon pivot;
-- one rigid transform cannot reproduce a second projection for every vertex.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function point(p,limit)
    assert(type(p)=='table','FirdPerson position unavailable')
    local out={}
    for i=1,3 do assert(finite(p[i])and(not limit or math.abs(p[i])<limit),'FirdPerson position out of bounds');out[i]=p[i]end
    return out
end
local function quaternion(q)
    assert(type(q)=='table','FirdPerson orientation unavailable')
    local n=0;for i=1,4 do assert(finite(q[i]),'FirdPerson orientation invalid');n=n+q[i]^2 end
    assert(math.abs(n-1)<.02,'FirdPerson orientation is not normalized')
    n=math.sqrt(n);return{q[1]/n,q[2]/n,q[3]/n,q[4]/n}
end
local function inverse(q)return{-q[1],-q[2],-q[3],q[4]}end
local function multiply(a,b)
    return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],
        a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],
        a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function rotate(q,p)
    local v=multiply(multiply(q,{p[1],p[2],p[3],0}),inverse(q));return{v[1],v[2],v[3]}
end
local function add(a,b)return{a[1]+b[1],a[2]+b[2],a[3]+b[3]}end
local function subtract(a,b)return{a[1]-b[1],a[2]-b[2],a[3]-b[3]}end
local function axis(index,radians)
    local q={0,0,0,math.cos(radians*.5)};q[index]=math.sin(radians*.5);return q
end
function M.lens(value)return finite(value)and value>.017 and value<3.125 end
function M.basis_rotation(basis)
    assert(type(basis)=='table','FirdPerson camera basis unavailable')
    local b={point(basis[1]),point(basis[2]),point(basis[3])}
    for i=1,3 do for j=i,3 do
        local dot=0;for k=1,3 do dot=dot+b[i][k]*b[j][k]end
        assert(math.abs(dot-(i==j and 1 or 0))<.02,'FirdPerson camera basis changed')
    end end
    local cross={b[1][2]*b[2][3]-b[1][3]*b[2][2],b[1][3]*b[2][1]-b[1][1]*b[2][3],b[1][1]*b[2][2]-b[1][2]*b[2][1]}
    assert(cross[1]*b[3][1]+cross[2]*b[3][2]+cross[3]*b[3][3]>.95,'FirdPerson camera basis is mirrored')
    -- The three native axes are the columns of the camera rotation matrix.
    local m00,m01,m02=b[1][1],b[2][1],b[3][1]
    local m10,m11,m12=b[1][2],b[2][2],b[3][2]
    local m20,m21,m22=b[1][3],b[2][3],b[3][3]
    local q,t
    if m00+m11+m22>0 then
        t=math.sqrt(1+m00+m11+m22)*2;q={(m21-m12)/t,(m02-m20)/t,(m10-m01)/t,t*.25}
    elseif m00>m11 and m00>m22 then
        t=math.sqrt(1+m00-m11-m22)*2;q={t*.25,(m01+m10)/t,(m02+m20)/t,(m21-m12)/t}
    elseif m11>m22 then
        t=math.sqrt(1+m11-m00-m22)*2;q={(m01+m10)/t,t*.25,(m12+m21)/t,(m02-m20)/t}
    else
        t=math.sqrt(1+m22-m00-m11)*2;q={(m02+m20)/t,(m12+m21)/t,t*.25,(m10-m01)/t}
    end
    return quaternion(q)
end
function M.capture(position,rotation,camera_position,camera_rotation)
    local q=quaternion(camera_rotation)
    return{position=point(rotate(inverse(q),subtract(point(position),point(camera_position))),2),
        rotation=quaternion(multiply(inverse(q),quaternion(rotation)))}
end
function M.reference(position,rotation)
    return{position=point(position,2),rotation=quaternion(rotation)}
end
function M.camera_anchor(head,basis,offset,body_forward)
    head=point(head);offset=offset or{x=0,y=0,z=.04}
    for _,key in ipairs({'x','y','z'})do assert(finite(offset[key])and math.abs(offset[key])<=.5,'FirdPerson head offset exceeds50cm')end
    local forward=point(basis[2]);local length=math.sqrt(forward[1]^2+forward[2]^2)
    if length<.0001 then forward=point(body_forward);length=math.sqrt(forward[1]^2+forward[2]^2)end
    assert(length>=.0001,'FirdPerson horizontal camera direction unavailable')
    local x,y=forward[1]/length,forward[2]/length
    return{head[1]+x*offset.y+y*offset.x,head[2]+y*offset.y-x*offset.x,head[3]+offset.z}
end
function M.lock(calibration,current,anchor,basis,placement,current_lens)
    local captured=assert(calibration.projection,'First-person projection reference unavailable')
    local source={position=point(current.position,1e6),rotation=quaternion(current.rotation)}
    local fp=M.reference(captured.position,captured.rotation)
    assert(M.lens(captured.fov),'First-person projection reference is invalid')
    if not M.lens(current_lens)then return nil,'Third-person projection is not ready'end
    local saved=assert(calibration.reference,'First-person placement reference unavailable')
    local delta={}
    for i,key in ipairs({'x','y','z'})do
        assert(finite(placement[key])and finite(saved[key])and math.abs(placement[key])<=.5 and math.abs(saved[key])<=.5,'FirdPerson placement exceeds50cm')
        delta[i]=placement[key]-saved[key]
    end
    local angles={}
    for i,key in ipairs({'yaw','pitch','roll'})do
        local a,b=placement[key]or 0,saved[key]or 0
        assert(finite(a)and finite(b)and math.abs(a)<=90 and math.abs(b)<=90,'FirdPerson angle exceeds90degrees')
        angles[i]=math.rad(a-b)
    end
    local authored=multiply(multiply(axis(3,angles[1]),axis(1,angles[2])),axis(2,angles[3]))
    local pivot=point(calibration.pivot or fp.position,2)
    local desired=add(add(pivot,rotate(authored,subtract(fp.position,pivot))),delta)
    local matched=math.abs(captured.fov-current_lens)<=.0001
    local factor=matched and 1 or math.tan(captured.fov*.5)/math.tan(current_lens*.5)
    desired[2]=desired[2]*factor
    -- A cached scope lens can briefly survive the native4 return. Yield the
    -- render correction until its real TP lens settles instead of clamping.
    -- With the exact same scene projection, an attachment may legitimately
    -- sit at/behind the eye while its mesh extends forward. Only the optional
    -- different-lens depth approximation requires a positive pivot depth.
    if not finite(factor)or not matched and(desired[2]<.03 or desired[2]>=1.9)then
        return nil,'Third-person projection depth is outside the render bound'
    end
    point(desired,2)
    local camera= M.basis_rotation(basis);anchor=point(anchor,1e6)
    -- Native FPS matrices can keep an older world origin under camera4. The
    -- weapon must remain close to its own verified FPS camera, not to the
    -- independently moving head camera where it will be rendered.
    local source_origin=current.frame_origin and point(current.frame_origin,1e6)or anchor
    point(subtract(source.position,source_origin),2)
    local target_rotation=quaternion(multiply(camera,multiply(authored,fp.rotation)))
    -- Constrain the current animated weapon, rather than its old neutral pose.
    -- One shared rigid transform locks its pivot and orientation to the camera
    -- while keeping the arm/finger articulation relative to that weapon.
    local world_delta=quaternion(multiply(target_rotation,inverse(source.rotation)))
    return{source=source.position,target=add(anchor,rotate(camera,desired)),rotation=world_delta,
        source_rotation=source.rotation,target_rotation=target_rotation,
        source_origin=source_origin,target_origin=anchor,frame_compensation=current.frame_origin~=nil},
        {factor=factor,captured_fov=captured.fov,current_fov=current_lens,depth=desired[2]}
end
function M.follow(calibration,current,anchor,basis,placement,current_lens,native_reference)
    if not native_reference then return nil,'Native weapon animation reference unavailable'end
    if not current.frame_origin or not current.frame_rotation then return nil,'Current FPS camera animation frame unavailable'end
    if not M.lens(native_reference.fov)or math.abs(native_reference.fov-calibration.projection.fov)>.0001 then
        return nil,'Native weapon animation reference uses a different display lens'
    end
    local neutral=M.reference(native_reference.position,native_reference.rotation)
    local animated=M.capture(current.position,current.rotation,current.frame_origin,current.frame_rotation)
    local base,info=M.lock(calibration,current,anchor,basis,placement,current_lens)
    if not base then return nil,info end
    -- B * inverse(N) * A: preserve the complete current FPS weapon motion A
    -- about its observed zero-offset reference N, around authored render base B.
    -- In particular, changing the ADS base never erases recoil or reload motion.
    local native_delta_position=rotate(inverse(neutral.rotation),subtract(animated.position,neutral.position))
    local native_delta_rotation=quaternion(multiply(inverse(neutral.rotation),animated.rotation))
    base.target=point(add(base.target,rotate(base.target_rotation,native_delta_position)),1e6)
    point(rotate(inverse(M.basis_rotation(basis)),subtract(base.target,point(anchor,1e6))),2)
    base.target_rotation=quaternion(multiply(base.target_rotation,native_delta_rotation))
    base.rotation=quaternion(multiply(base.target_rotation,inverse(base.source_rotation)))
    info.animated=true;info.native_position_delta=native_delta_position;info.native_rotation_delta=native_delta_rotation
    return base,info
end
function M.rebase(common,current)
    local source=point(current.position,1e6);local source_rotation=quaternion(current.rotation)
    local target=point(common.target,1e6);local target_rotation=quaternion(common.target_rotation)
    local origin=point(common.target_origin,1e6)
    point(subtract(source,origin),2)
    -- A body-parented weapon must use the very same animated target as the
    -- FPS arm retarget. Recomputing lock() here would cancel the motion again.
    return{source=source,target=target,source_rotation=source_rotation,target_rotation=target_rotation,
        rotation=quaternion(multiply(target_rotation,inverse(source_rotation))),
        source_origin=point(origin),target_origin=point(origin),frame_compensation=false}
end
function M.apply(transform,position,rotation)
    return add(transform.target,rotate(transform.rotation,subtract(position,transform.source))),
        rotation and quaternion(multiply(transform.rotation,quaternion(rotation)))or nil
end
return M
