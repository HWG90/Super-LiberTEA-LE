local M=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_weapon_children.lua')
local cases=0
local function pass()cases=cases+1 end
local function uint(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function fixture(empty)
    local f={values={},blocks={},calls={},published={},handles={},refs={},large=0}
    local function put(at,v)f.values[at]=v end
    local exe,world,units,generations=0x1000000,0x2000000,0x3000000,0x4000000
    local function context(object,index)
        local c={exe=exe,unit=index+4194304,index=index,generation=1,object=object,units=units,generations=generations,registry=123}
        put(units+index*8,object);put(generations+index,1);put(object+8,c.unit);put(object+0x18,world)
        put(object+0x70,2);put(object+0x80,object+0x1000);put(object+0x88,object+0x2000)
        put(object+0x98,object+0x3000);put(object+0xa0,object+0x4000)
        put(object+0x1d8,0);put(object+0x1e0,0)
        f.blocks[object+0x3000]=uint(2)..uint(1);f.blocks[object+0x4000]=uint(index*10)..uint(index*10+1)
        f.refs[object]=c;local handle={ref=c.unit};f.handles[#f.handles+1]=handle
        return c
    end
    f.body=context(0x50000,1);f.weapon=context(0x60000,2)
    f.child=context(0x70000,3);f.grandchild=context(0x80000,4);f.sibling=context(0x90000,5)
    put(f.weapon.object+0x1d0,f.body.object);put(f.weapon.object+0x78,f.body.object+0x2000)
    for _,pair in ipairs({{f.child,f.weapon},{f.grandchild,f.child},{f.sibling,f.weapon}})do
        put(pair[1].object+0x1d0,pair[2].object);put(pair[1].object+0x78,pair[2].object+0x2000)
    end
    if not empty then
        put(f.weapon.object+0x1d8,f.child.object);put(f.child.object+0x1e0,f.sibling.object)
        put(f.child.object+0x1d8,f.grandchild.object)
    end
    local pins={
        [0x1a9514]='4c89b6d0010000498b86d8010000488986e00100004989b6d8010000',
        [0x3c0fe4]='e8b7f6cdff488bd0488bcbe86cbfdeff',
        [0x1ad238]='4c8b4b28488d4424484c8b4338488d4b10488b53204889442420e819064000'}
    local b={}
    function b:_alignment_executable()return exe end
    function b:_u8(at)return assert(f.values[at],'Unexpected byte read')end
    function b:_u32(at)
        if f.values[at]~=nil then return f.values[at]%4294967296 end
        if f.values[at-4]~=nil then return math.floor(f.values[at-4]/4294967296)end
        error('Unexpected word read '..at)
    end
    function b:_ptr(at)local v=assert(f.values[at],'Unexpected pointer read');assert(v~=0);return v end
    function b:_read(at,n)
        if n>1024 then f.large=f.large+1 end
        local pin=pins[at-exe]
        if pin then if f.bad_pin then return string.rep('x',n)end;return(pin:gsub('..',function(x)return string.char(tonumber(x,16))end))end
        local value=f.blocks[at];assert(value and #value==n,'Unexpected graph read');return value
    end
    f.s={identity='weapon1',player_identity='player',body=f.body.unit,weapon_unit=f.weapon.unit,safe=true,camera_kind=4,controller_active=false}
    function b:snapshot()local s={};for k,v in pairs(f.s)do s[k]=v end;return s end
    b.foreign_camera=function()return f.foreign==true end
    f.sr={World={}}
    f.sr.World.update_unit=function(w,handle)
        assert(w=='owned-world'and type(handle)=='table','Numeric handle or foreign world reached SDK')
        f.calls[#f.calls+1]=handle.ref
        if f.throw then error('publication failed')end
        if f.refuse then return false end
        local c=f.refs[f.values[units+(handle.ref%4194304)*8]]
        local parent=f.values[c.object+0x1d0]
        assert(f.published[parent],'Parent was not published before child')
        f.published[c.object]=true
        if f.during then local fn=f.during;f.during=nil;fn()end
    end
    f.b=b;f.cal={world='owned-world',body_context=f.body,identity='player'}
    f.deps={address=function(h)assert(type(h)=='table');return h.ref*4 end}
    function f:new(list)return M.new(self.b,self.sr,self.cal,self.weapon,list or self.handles,self.deps)end
    function f:publish(m)self.published[self.weapon.object]=true;return m:publish(self.s)end
    f.put=put;return f
end
local f=fixture();local m=f:new();assert(m.count==3 and #f.calls==0 and m:is_valid())
assert(f:publish(m));assert(#f.calls==3 and f.calls[1]==f.child.unit and f.calls[2]==f.grandchild.unit and f.calls[3]==f.sibling.unit)
assert(m.publishes==3 and f.large==0);pass()
f=fixture(true);m=f:new();assert(m.count==0 and f:publish(m)and #f.calls==0);pass()
f=fixture();local by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
m=f:new({by_ref=by_ref});assert(f:publish(m)and #f.calls==3);pass()
f=fixture();by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
by_ref[f.child.unit]=f.child.unit;assert(not pcall(f.new,f,{by_ref=by_ref})and #f.calls==0);pass()
f=fixture();by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
by_ref[f.child.unit]=by_ref[f.sibling.unit];assert(not pcall(f.new,f,{by_ref=by_ref})and #f.calls==0);pass()
f=fixture();by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
for ref=100,16100 do by_ref[ref]={ref=ref}end
local selected={[f.child.unit]=true,[f.grandchild.unit]=true,[f.sibling.unit]=true};local addresses=0
f.deps.address=function(handle)
    assert(selected[handle.ref],'Unrelated world handle reached the slow compatibility conversion')
    addresses=addresses+1;return handle.ref*4
end
m=f:new({by_ref=by_ref,123,456});assert(addresses==3 and m.count==3)
assert(m:is_valid()and f:publish(m)and addresses==3,'Cached publication must not enumerate the world handle inventory');pass()
f=fixture();by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
local first=true;f.deps.address=function(handle)
    if first then first=false;f.put(f.child.generations+f.child.index,2)end
    return handle.ref*4
end
assert(not pcall(f.new,f,{by_ref=by_ref})and #f.calls==0,'Generation retirement during selected-handle validation must refuse initialization');pass()
f=fixture();by_ref={};for _,h in ipairs(f.handles)do by_ref[h.ref]=h end
f.deps.address=function(handle)f.s.weapon_unit=f.child.unit;return handle.ref*4 end
assert(not pcall(f.new,f,{by_ref=by_ref})and #f.calls==0,'Weapon swap during cached initialization must refuse publication');pass()
for _,change in ipairs({
    function(f)f.put(f.child.object+0x1d0,f.body.object)end,
    function(f)f.put(f.child.object+0x78,f.body.object+0x2000)end,
    function(f)f.put(f.child.object+0x18,0x3333330)end,
    function(f)f.put(f.child.generations+f.child.index,2)end,
    function(f)f.put(f.child.object+8,f.child.unit+1)end,
    function(f)f.put(f.weapon.object+0x1d8,f.sibling.object)end,
    function(f)f.put(f.child.object+0x1e0,0)end,
    function(f)f.put(f.weapon.object+0x88,0x1111110)end,
    function(f)f.put(f.child.object+0x80,0x1111110)end,
    function(f)f.blocks[f.child.object+0x3000]=uint(65538)..uint(1)end,
    function(f)f.blocks[f.child.object+0x4000]=uint(333)..uint(334)end,
})do
    f=fixture();m=f:new();change(f);assert(not m:is_valid()and not f:publish(m)and #f.calls==0);pass()
end
for _,change in ipairs({
    function(f)f.s.camera_kind=6 end,function(f)f.s.controller_active=true end,function(f)f.s.safe=false end,
    function(f)f.s.player_identity='replacement'end,function(f)f.s.weapon_unit=f.child.unit end,
    function(f)f.foreign=true end,function(f)f.bad_pin=true end,
})do f=fixture();m=f:new();change(f);assert(not f:publish(m)and #f.calls==0);pass()end
f=fixture();m=f:new();f.sr.World.update_unit=function()error('Foreign publisher called')end
assert(not f:publish(m)and #f.calls==0);pass()
f=fixture();f.put(f.child.object+0x1e0,f.child.object);assert(not pcall(f.new,f));pass()
f=fixture();f.put(f.child.object+0x1d8,f.weapon.object);assert(not pcall(f.new,f));pass()
f=fixture();f.blocks[f.child.object+0x3000]=uint(1)..uint(1);assert(not pcall(f.new,f));pass()
f=fixture();f.blocks[f.child.object+0x3000]=uint(2+99*65536)..uint(1);assert(not pcall(f.new,f));pass()
f=fixture();f.put(f.child.object+0x70,3)
f.blocks[f.child.object+0x3000]=uint(2)..uint(2*65536+1)..uint(65536+1)
f.blocks[f.child.object+0x4000]=uint(30)..uint(31)..uint(32);assert(not pcall(f.new,f));pass()
f=fixture();table.remove(f.handles,3);assert(not pcall(f.new,f));pass()
f=fixture();m=f:new();f.refuse=true;assert(not f:publish(m)and #f.calls==1 and m.publishes==0);pass()
f=fixture();m=f:new();f.throw=true;assert(not f:publish(m)and #f.calls==1 and m.publishes==0);pass()
f=fixture();m=f:new();f.during=function()f.put(f.grandchild.object+0x1d0,f.body.object)end
assert(not f:publish(m)and #f.calls==1 and m.publishes==1);pass()
f=fixture();m=f:new();f.during=function()f.put(f.grandchild.object+0x18,0x3333330)end
assert(not f:publish(m)and #f.calls==1 and m.publishes==1);pass()
print('Fird weapon children: '..cases..' discovery, publication order, generations, attachment changes and publisher guards passed')
