local PORT51=mod.require('src/first_person/compat51.lua')
-- Read the animation locals and reconstruct FK in a private virtual frame.
-- No SDK call, graph publication, or native animation step is performed here.
-- Current EXE5AD870 uses 64-byte locals: three packed rotation columns,
-- translation+24, scale+30. Link1 selects internal parent; link2 is external.
local M={}
local ffi=PORT51.ffi
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function transform(a,v)
    return{a[1][1]*v[1]+a[2][1]*v[2]+a[3][1]*v[3],
        a[1][2]*v[1]+a[2][2]*v[2]+a[3][2]*v[3],
        a[1][3]*v[1]+a[2][3]*v[2]+a[3][3]*v[3]}
end
local function orientation(basis)
    local axes,scale={},{}
    for i=1,3 do
        local length=math.sqrt(dot(basis[i],basis[i]))
        assert(finite(length)and length>.00001 and length<1e4,'Source bone scale is invalid')
        scale[i]=length;axes[i]={basis[i][1]/length,basis[i][2]/length,basis[i][3]/length}
    end
    for i=1,3 do for j=i+1,3 do assert(math.abs(dot(axes[i],axes[j]))<.002,'Source bone transform is sheared')end end
    local cross={axes[1][2]*axes[2][3]-axes[1][3]*axes[2][2],axes[1][3]*axes[2][1]-axes[1][1]*axes[2][3],axes[1][1]*axes[2][2]-axes[1][2]*axes[2][1]}
    assert(dot(cross,axes[3])>.998,'Source bone orientation is mirrored')
    local a,b,c=axes[1][1],axes[2][1],axes[3][1]
    local d,e,f=axes[1][2],axes[2][2],axes[3][2]
    local g,h,i=axes[1][3],axes[2][3],axes[3][3]
    local q,t
    if a+e+i>0 then t=math.sqrt(1+a+e+i)*2;q={(h-f)/t,(c-g)/t,(d-b)/t,t*.25}
    elseif a>e and a>i then t=math.sqrt(1+a-e-i)*2;q={t*.25,(b+d)/t,(c+g)/t,(h-f)/t}
    elseif e>i then t=math.sqrt(1+e-a-i)*2;q={(b+d)/t,t*.25,(f+h)/t,(c-g)/t}
    else t=math.sqrt(1+i-a-e)*2;q={(c+g)/t,(f+h)/t,t*.25,(d-b)/t}end
    local n=0;for k=1,4 do assert(finite(q[k]),'Source bone quaternion is invalid');n=n+q[k]^2 end
    n=math.sqrt(n);assert(n>.99 and n<1.01,'Source bone quaternion is not normalized')
    for k=1,4 do q[k]=q[k]/n end
    return q,scale
end
local function point(v)
    for i=1,3 do assert(finite(v[i])and math.abs(v[i])<1e6,'Source bone position is invalid')end
    return v
end
local function topology(links,hashes,count)
    assert(type(count)=='number'and count%1==0 and count>0 and count<=256,'Source graph count is invalid')
    local parents,seen={},{}
    for node=1,count do
        local link,hash=links[node],hashes[node]
        assert(type(link)=='number'and link%1==0 and link>=0 and link<4294967296,'Source bone link is invalid')
        assert(type(hash)=='number'and hash%1==0 and hash>0 and hash<4294967296 and not seen[hash],'Source bone hash is invalid or duplicated')
        seen[hash]=true
        local flag=link%65536
        assert(flag==0 or flag==1,'Source graph has an unsupported external link')
        if flag==1 then
            local parent=math.floor(link/65536)+1
            assert(parent>=1 and parent<=count and parent~=node,'Source bone parent is invalid')
            parents[node]=parent
        end
    end
    local visiting,done={},{}
    local function visit(node)
        assert(not visiting[node],'Source bone hierarchy has a cycle')
        if done[node]then return end
        visiting[node]=true;if parents[node]then visit(parents[node])end
        visiting[node]=nil;done[node]=true
    end
    for node=1,count do visit(node)end
    return parents
end
local function output(frames,hashes,parents,count)
    local by_hash={}
    for node=1,count do
        local frame=frames[node];frame.node=node;frame.hash=hashes[node];frame.parent=parents[node]
        frame.rotation,frame.scale=orientation(frame.basis);point(frame.position)
        by_hash[hashes[node]]=frame
    end
    return{by_index=frames,by_hash=by_hash,parents=parents,weapon=frames[9],camera=frames[51]}
end
function M.reconstruct(locals,links,hashes,count)
    count=count or #locals
    local parents=topology(links,hashes,count);local frames={}
    local function build(node)
        if frames[node]then return frames[node]end
        local row=assert(locals[node],'Source local pose is missing');local basis={}
        for axis=1,3 do
            local scale=row[12+axis]
            assert(finite(scale)and scale>=.001 and scale<=100,'Source local scale is invalid')
            basis[axis]={}
            for k=1,3 do local value=row[(axis-1)*3+k]
                assert(finite(value)and math.abs(value)<=1.002,'Source local orientation is invalid')
                basis[axis][k]=value*scale
            end
            assert(math.abs(dot(basis[axis],basis[axis])/(scale*scale)-1)<.002,'Source local rotation axis is not normalized')
        end
        orientation(basis)
        local position=point({row[10],row[11],row[12]})
        if parents[node]then
            local parent=build(parents[node]);local p=transform(parent.basis,position)
            position=point({p[1]+parent.position[1],p[2]+parent.position[2],p[3]+parent.position[3]})
            for axis=1,3 do basis[axis]=transform(parent.basis,basis[axis])end
        end
        frames[node]={position=position,basis=basis};return frames[node]
    end
    for node=1,count do build(node)end
    return output(frames,hashes,parents,count)
end
local function valid(b,c)
    return b:_u8(c.generations+c.index)==c.generation and b:_ptr(c.units+c.index*8)==c.object
        and b:_u32(c.object+8)==c.unit
end
local function read_chunks(b,address,size)
    local chunks={}
    for offset=0,size-1,1024 do
        local n=math.min(1024,size-offset);local bytes=b:_read(address+offset,n)
        assert(type(bytes)=='string'and #bytes==n,'Source pose read is incomplete');chunks[#chunks+1]=bytes
    end
    return table.concat(chunks)
end
local function uints(raw,count)
    local out={}
    for i=1,count do local a,b,c,d=raw:byte((i-1)*4+1,(i-1)*4+4);out[i]=a+b*256+c*65536+d*16777216 end
    return out
end
local function contract(b,c)
    local exe=b:_alignment_executable()
    assert(exe==c.exe,'Source executable identity changed')
    for _,pin in ipairs({{0x28d3c0,'\072\141\065\096\195'},
        {0x1f232b,'\072\139\203\072\193\225\006\072\131\193\036\072\139\064\032'},
        {0x5adfd1,'\102\065\131\249\001\015\133\171\007\000\000\065\015\183\082\002'},
        {0x5ae6e8,'\242\066\015\016\068\007\036\137\069\056\066\139\068\007\044'}})do
        assert(b:_read(exe+pin[1],#pin[2])==pin[2],'Source scene graph contract changed')
    end
end
local function read_graph(b,c,count,world,expected_links,expected_hashes)
    assert(valid(b,c),'Source Unit generation changed')
    assert(b:_u32(c.object+0x70)==count,'Source graph topology changed')
    local array=b:_ptr(c.object+(world and 0x88 or 0x80));local links_at=b:_ptr(c.object+0x98);local hashes_at=b:_ptr(c.object+0xa0)
    local links=read_chunks(b,links_at,count*4);local hashes=read_chunks(b,hashes_at,count*4)
    assert(not expected_links or links==expected_links,'Source bone links changed')
    assert(not expected_hashes or hashes==expected_hashes,'Source bone assignments changed')
    local raw=read_chunks(b,array,count*64)
    assert(valid(b,c)and b:_u32(c.object+0x70)==count and b:_ptr(c.object+(world and 0x88 or 0x80))==array
        and b:_ptr(c.object+0x98)==links_at and b:_ptr(c.object+0xa0)==hashes_at
        and read_chunks(b,links_at,count*4)==links and read_chunks(b,hashes_at,count*4)==hashes,
        'Source graph changed during observation')
    local values=ffi.new('float[?]',count*16);ffi.copy(values,raw,#raw)
    local rows={}
    for node=1,count do local row={};for k=1,16 do row[k]=PORT51.number(values[(node-1)*16+k-1])end;rows[node]=row end
    return rows,uints(links,count),uints(hashes,count),links,hashes
end
function M.world(b,c,count)
    contract(b,c)
    local rows,links,hashes=read_graph(b,c,count,true);local parents=topology(links,hashes,count);local frames={}
    for node=1,count do local row=rows[node]
        frames[node]={position=point({row[13],row[14],row[15]}),basis={{row[1],row[2],row[3]},{row[5],row[6],row[7]},{row[9],row[10],row[11]}}}
    end
    local result=output(frames,hashes,parents,count)
    -- These aliases are semantic FPS anchors, never generic body indices.
    result.weapon,result.camera=nil,nil
    return result
end
function M.new(b,cal)
    local c=assert(cal.fps_context,'Source FPS context unavailable');contract(b,c)
    local rows,links,hashes,link_bytes,hash_bytes=read_graph(b,c,63,false)
    for node,hash in pairs({[9]=0x4fdd3337,[11]=0x03752c98,[14]=0x5c0c68d3,[31]=0x1620b2ce,[51]=0x60ed8c39})do
        assert(hashes[node]==hash,'Source FPS semantic assignment changed')
    end
    M.reconstruct(rows,links,hashes,63)
    local function owner(expected)
        local s=assert(b:snapshot(),'Source player unavailable')
        assert(s.player_identity==cal.identity and s.viewmodel==c.unit,'Source FPS owner changed')
        if expected then for _,key in ipairs({'identity','player_identity','viewmodel','body','weapon','weapon_unit','context','camera','record'})do
            assert(expected[key]==nil or expected[key]==s[key],'Source player changed during observation')
        end end
        return s
    end
    local reader={}
    function reader:sample(expected)
        contract(b,c);local before=owner(expected)
        local current,l,h=read_graph(b,c,63,false,link_bytes,hash_bytes)
        local result=M.reconstruct(current,l,h,63)
        owner(before);result.identity=before.identity;result.player_identity=before.player_identity
        return result
    end
    return reader
end
return M
