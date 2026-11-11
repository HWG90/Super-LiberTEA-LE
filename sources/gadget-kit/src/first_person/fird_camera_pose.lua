local PORT51=mod.require('src/first_person/compat51.lua')
-- The native final-camera dispatch copies one complete submitted world matrix
-- to context+0C. Read its paired axes/translation, rather than a later head pose.
-- No SDK/native calls, pose writes, or publication occur in this reader.
local M={}
local ffi=PORT51.ffi
local pins={
    {0x110bff5,'41ff5120488b05c854bd014c8d45008b5308488b0b4c8b482041ff5128'},
    {0x110c012,'488b05af54bd018b5308488b8b800100004c8b400841ff9000010000488b059354bd0133d2488b4818488b81900000008b4b08ffd0'},
    {0x110c047,'33d20f10000f11430c0f1048100f114b1c0f1040200f11432c0f104830488b055d54bd010f114b3c'},
}
for _,pin in ipairs(pins)do pin[2]=pin[2]:gsub('..',function(v)return string.char(tonumber(v,16))end)end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function raw(b,at,n)
    local value=b:_read(at,n)
    assert(type(value)=='string'and #value==n,'Submitted camera copied read is incomplete')
    return value
end
local function ptr0(b,at)return b:_u32(at)+b:_u32(at+4)*4294967296 end
local function valid(b,c)
    return c and b:_u8(c.generations+c.index)==c.generation
        and b:_ptr(c.units+c.index*8)==c.object and b:_u32(c.object+8)==c.unit
end
local owner_fields={'identity','player_identity','base','context','camera','record','camera_kind','safe','controller_active',
    'world','avatar_owner','avatar_index','avatar','body','viewmodel','weapon_unit'}
local function same_owner(a,b)
    for _,key in ipairs(owner_fields)do assert(a[key]==b[key],'Submitted camera player/weapon/request changed')end
end
local function owner(b,cal,expected)
    local s,why=b:snapshot();assert(s,why or'Submitted camera player unavailable')
    same_owner(expected,s)
    assert(s.safe==true and s.camera_kind==4 and s.controller_active==false
        and s.player_identity==cal.identity,'Submitted camera is not an owned normal view')
    if b.foreign_camera then assert(b.foreign_camera()==false,'Another camera owns the submitted pose')end
    assert(valid(b,cal.camera_context)and valid(b,cal.body_context),'Submitted camera Unit generation changed')
    assert(cal.body_context.unit==s.body,'Submitted camera body Unit changed')
    return s
end
local function binding(b,cal,s)
    local c=cal.camera_context
    assert(b:_ptr(s.context)==s.camera and b:_u32(s.context+8)==c.unit,'Submitted camera wrapper/Unit changed')
    local graph=b:_ptr(s.camera+0x18);local node=b:_u32(s.camera+0x20)
    assert(graph==c.object+0x60,'Submitted camera graph is not the retained Unit')
    local count=b:_u32(graph+0x10)
    -- The pinned final world-pose getter requests node zero explicitly.
    assert(count>0 and count<=512 and node==0 and node<count,'Submitted camera graph index is invalid')
    assert(ptr0(b,c.object+0x1d0)==0,'Submitted camera Unit has an external parent')
    local locals=b:_ptr(graph+0x20);local links=b:_ptr(c.object+0x98)
    local link=b:_u32(links+node*4)
    assert(link%65536==0,'Submitted camera node is not an unparented root')
    local world=b:_ptr(c.object+0x18)
    assert(world==b:_ptr(cal.body_context.object+0x18),'Submitted camera belongs to another world')
    return{graph=graph,node=node,count=count,locals=locals,links=links,link=link,world=world}
end
local function same_binding(a,b)
    for _,key in ipairs({'graph','node','count','locals','links','link','world'})do
        assert(a[key]==b[key],'Submitted camera graph changed during observation')
    end
end
local function matrix(bytes)
    local buffer=ffi.new('float[16]');ffi.copy(buffer,bytes,64);local out={}
    for i=1,16 do out[i]=PORT51.number(buffer[i-1]);assert(finite(out[i]),'Submitted camera matrix is not finite')end
    return out
end
local function axes(m)
    local basis={{m[1],m[2],m[3]},{m[5],m[6],m[7]},{m[9],m[10],m[11]}}
    local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
    for i=1,3 do for j=i,3 do
        assert(math.abs(dot(basis[i],basis[j])-(i==j and 1 or 0))<.002,'Submitted camera basis is not orthonormal')
    end end
    local a,c=basis[1],basis[2]
    assert(dot({a[2]*c[3]-a[3]*c[2],a[3]*c[1]-a[1]*c[3],a[1]*c[2]-a[2]*c[1]},basis[3])>.998,
        'Submitted camera basis is mirrored')
    assert(math.abs(m[4])+math.abs(m[8])+math.abs(m[12])<.00001 and math.abs(m[16]-1)<.00001,
        'Submitted camera matrix is not affine')
    return basis
end
function M.read(b,cal,expected)
    assert(type(cal)=='table'and type(expected)=='table','Submitted camera calibration unavailable')
    local s=owner(b,cal,expected)
    local exe=b:_alignment_executable();assert(exe==cal.camera_context.exe,'Submitted camera executable changed')
    for _,pin in ipairs(pins)do assert(raw(b,s.base+pin[1],#pin[2])==pin[2],'Submitted camera dispatch contract changed')end
    assert(raw(b,exe+0x28d3c0,5)=='\072\141\065\096\195','Submitted camera graph getter changed')
    assert(raw(b,exe+0x1f232b,15)=='\072\139\203\072\193\225\006\072\131\193\036\072\139\064\032',
        'Submitted camera local layout changed')
    local bound=binding(b,cal,s)
    local pose=raw(b,s.context+0x0c,64)
    local local_at=bound.locals+bound.node*64;local local_pose=raw(b,local_at,64)
    -- The live normal4 camera root stores exactly the translation which the
    -- final dispatch copied into context. Cached world+88 is deliberately not
    -- consulted: it can still describe an old orbit at other script phases.
    assert(pose:sub(49,60)==local_pose:sub(37,48),'Submitted camera/local pose epochs differ')
    local m=matrix(pose);local basis=axes(m);local position={m[13],m[14],m[15]}
    local local_m=matrix(local_pose)
    for axis=1,3 do
        assert(math.abs(local_m[12+axis]-1)<.00001,'Submitted camera local scale changed')
        for i=1,3 do assert(math.abs(local_m[(axis-1)*3+i]-basis[axis][i])<.00001,
            'Submitted camera/local orientation epochs differ')end
    end
    for i=1,3 do assert(math.abs(position[i])<1e6,'Submitted camera position exceeds world bounds')end
    local after=owner(b,cal,s);same_binding(bound,binding(b,cal,after))
    assert(raw(b,s.context+0x0c,64)==pose and raw(b,local_at,64)==local_pose,
        'Submitted camera pose changed during observation')
    return{position=position,basis=basis}
end
return M
