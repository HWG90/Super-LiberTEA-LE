local PORT51=mod.require('src/first_person/compat51.lua')
-- World.update_unit rebuilds only the supplied Unit. Publish the weapon's
-- already linked descendants afterwards; their animation locals stay native.
local M={}
local MAX_UNITS,MAX_DEPTH=64,8
local function pointer(n)return type(n)=='number'and n>=65536 and n<140737488355328 and n%8==0 end
local function ptr0(b,at)return b:_u32(at)+b:_u32(at+4)*4294967296 end
local function bytes(b,at,n)
    local out={};for offset=0,n-1,1024 do
        local size=math.min(1024,n-offset);local value=b:_read(at+offset,size)
        assert(type(value)=='string'and #value==size,'Weapon child graph read is incomplete');out[#out+1]=value
    end
    return table.concat(out)
end
local function u32(raw,at)local a,b,c,d=raw:byte(at+1,at+4);return a+b*256+c*65536+d*16777216 end
local function valid(b,c)
    return b:_u8(c.generations+c.index)==c.generation and b:_ptr(c.units+c.index*8)==c.object
        and b:_u32(c.object+8)==c.unit
end
local function address(value)
    assert(PORT51.kind(value)~='number','Weapon child SDK requires a native Unit handle')
    local native=package.loaded.hd2_nativeinfo
    if native and PORT51.kind(native.userdata_address)=='function'then return native.userdata_address(value)end
    return PORT51.number(PORT51.ffi.cast('uintptr_t',value))
end
local function contract(b,context)
    local exe=b:_alignment_executable();assert(exe==context.exe,'Weapon child executable changed')
    for _,pin in ipairs({
        {0x1a95b4,'\076\137\182\208\001\000\000\073\139\134\216\001\000\000\072\137\134\224\001\000\000\073\137\182\216\001\000\000'},
        {0x3c10c4,'\232\007\246\205\255\072\139\208\072\139\203\232\060\191\222\255'},
        {0x1ad2e8,'\076\139\075\040\072\141\068\036\072\076\139\067\056\072\141\075\016\072\139\083\032\072\137\068\036\032\232\009\006\064\000'},
    })do assert(b:_read(exe+pin[1],#pin[2])==pin[2],'Weapon child publication contract changed')end
end
function M.new(b,sr,cal,weapon,unit_list,deps)
    deps=deps or{}
    assert(cal and cal.world and cal.body_context and weapon,'Weapon child owner unavailable')
    local publish=assert(sr.World and sr.World.update_unit,'Weapon child publisher unavailable')
    contract(b,weapon)
    assert(valid(b,weapon)and valid(b,cal.body_context),'Weapon child generation changed')
    local world=b:_ptr(weapon.object+0x18)
    assert(world==b:_ptr(cal.body_context.object+0x18),'Weapon child world is not owned')
    local rows,by_object={},{}
    local function resolve(object)
        assert(pointer(object),'Weapon child object pointer is invalid')
        local ref=b:_u32(object+8);local index=ref%4194304
        local c={exe=weapon.exe,object=object,unit=ref,index=index,generation=math.floor(ref/4194304)%256,
            units=weapon.units,generations=weapon.generations,registry=weapon.registry}
        assert(valid(b,c),'Weapon child generation is not owned');return c
    end
    local function describe(c,parent,depth)
        assert(depth<=MAX_DEPTH and #rows<MAX_UNITS and not by_object[c.object],'Weapon child hierarchy exceeds bounds or has a cycle')
        assert(valid(b,c)and b:_ptr(c.object+0x18)==world,'Weapon child world changed')
        local count=b:_u32(c.object+0x70);assert(count>0 and count<=512,'Weapon child scene graph is unavailable')
        local row={context=c,parent=parent,count=count,worlds=b:_ptr(c.object+0x88),locals=b:_ptr(c.object+0x80),
            links=b:_ptr(c.object+0x98),hashes=b:_ptr(c.object+0xa0),head=ptr0(b,c.object+0x1d8),next=ptr0(b,c.object+0x1e0)}
        row.link_bytes=bytes(b,row.links,count*4);row.hash_bytes=bytes(b,row.hashes,count*4)
        if parent then
            assert(b:_ptr(c.object+0x1d0)==parent.context.object and b:_ptr(c.object+0x78)==parent.worlds,
                'Weapon child external parent changed')
            local external,parents=false,{}
            for node=0,count-1 do
                local link=u32(row.link_bytes,node*4);local flag,index=link%65536,math.floor(link/65536)
                assert(flag<=2 and(flag~=1 or index<count and index~=node)and(flag~=2 or index<parent.count),
                    'Weapon child graph link is invalid')
                if flag==1 then parents[node+1]=index+1 end
                if flag==2 then external=true end
            end
            assert(external,'Weapon child has no verified external parent link')
            local visiting,done={},{}
            local function visit(node)
                assert(not visiting[node],'Weapon child graph has a cycle')
                if done[node]then return end
                visiting[node]=true;if parents[node]then visit(parents[node])end
                visiting[node]=nil;done[node]=true
            end
            for node=1,count do visit(node)end
        end
        rows[#rows+1]=row;by_object[c.object]=row
        local child=row.head
        while child~=0 do
            assert(pointer(child)and not by_object[child],'Weapon child sibling chain is invalid')
            local next_row=describe(resolve(child),row,depth+1);child=next_row.next
        end
        return row
    end
    describe(weapon,nil,0)
    local by_ref={};local get=deps.address or address
    if unit_list and unit_list.by_ref then by_ref=unit_list.by_ref
    else
        assert(type(unit_list)=='table'and #unit_list<=131072,'Weapon child Unit handle inventory unavailable')
        local wanted={};for i=2,#rows do wanted[rows[i].context.unit]=true end
        for _,handle in ipairs(unit_list)do
            assert(PORT51.kind(handle)~='number','Weapon child SDK requires a native Unit handle')
            local at=get(handle);assert(type(at)=='number'and at>=0 and at<17179869184,'Weapon child native handle is invalid')
            local ref=math.floor(at/4);if wanted[ref]then by_ref[ref]=handle end
        end
    end
    for i=2,#rows do
        local row=rows[i];local handle=assert(by_ref[row.context.unit],'Weapon child native Unit handle unavailable')
        assert(PORT51.kind(handle)~='number','Weapon child SDK requires a native Unit handle')
        local at=get(handle)
        assert(type(at)=='number'and at>=0 and at<17179869184 and math.floor(at/4)==row.context.unit,
            'Weapon child native handle does not match its generation')
        row.handle=handle
    end
    local function check_row(row)
        local c=row.context
        assert(valid(b,c)and b:_ptr(c.object+0x18)==world and b:_u32(c.object+0x70)==row.count
            and b:_ptr(c.object+0x80)==row.locals and b:_ptr(c.object+0x88)==row.worlds
            and b:_ptr(c.object+0x98)==row.links and b:_ptr(c.object+0xa0)==row.hashes
            and ptr0(b,c.object+0x1d8)==row.head and ptr0(b,c.object+0x1e0)==row.next
            and bytes(b,row.links,row.count*4)==row.link_bytes and bytes(b,row.hashes,row.count*4)==row.hash_bytes,
            'Weapon child graph or attachment set changed')
        if row.parent then assert(b:_ptr(c.object+0x1d0)==row.parent.context.object
            and b:_ptr(c.object+0x78)==row.parent.worlds,'Weapon child parent changed')end
    end
    local function check(expected)
        contract(b,weapon)
        assert(sr.World and sr.World.update_unit==publish,'Weapon child publisher identity changed')
        assert(valid(b,cal.body_context)and b:_ptr(cal.body_context.object+0x18)==world,'Weapon child player rig changed')
        if b.snapshot then
            local s=assert(b:snapshot(),'Weapon child player unavailable')
            assert(s.player_identity==cal.identity and s.body==cal.body_context.unit and s.weapon_unit==weapon.unit
                and s.safe and s.camera_kind==4 and not s.controller_active,'Weapon child player or camera owner changed')
            if expected then for _,key in ipairs({'identity','player_identity','weapon_unit','body','context','camera','record'})do
                assert(expected[key]==nil or expected[key]==s[key],'Weapon child owner changed before publication')
            end end
        end
        if b.foreign_camera then assert(b.foreign_camera()==false,'Another camera owns weapon child publication')end
        for _,row in ipairs(rows)do check_row(row)end
        return true
    end
    local self={count=#rows-1,publishes=0}
    function self:is_valid(expected)
        local ok,why=pcall(check,expected)
        if ok then return true end
        return false,tostring(why)
    end
    function self:publish(expected)
        local ok,why=self:is_valid(expected);if not ok then return false,why end
        -- The caller publishes the parent weapon first. rows is preorder,
        -- therefore every child sees its parent's newly rebuilt world array.
        for i=2,#rows do
            local row=rows[i]
            local live,problem=pcall(check_row,row)
            if not live then return false,tostring(problem)end
            local called,value=pcall(publish,cal.world,row.handle)
            if not called or value==false then return false,called and'Weapon child publication refused'or tostring(value)end
            self.publishes=self.publishes+1
        end
        return true
    end
    local ok,why=self:is_valid();assert(ok,why)
    return self
end
return M
