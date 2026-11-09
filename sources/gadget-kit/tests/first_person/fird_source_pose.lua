local S=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_source_pose.lua')
local ffi=TEST_PORT51 and TEST_PORT51.ffi or require('ffi')
local cases=0
local function pass()cases=cases+1 end
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b))end
local function localrow(x,y,z,angle,scale)
    local c,s=math.cos(angle or 0),math.sin(angle or 0);scale=scale or{1,1,1}
    return{c,s,0,-s,c,0,0,0,1,x or 0,y or 0,z or 0,scale[1],scale[2],scale[3],0}
end
local function base()
    return{localrow(0,0,0),localrow(1,0,0),localrow(0,2,0)}, {0,1,65537},{11,22,33}
end
local rows,links,hashes=base();local out=S.reconstruct(rows,links,hashes)
near(out.by_index[3].position[1],1);near(out.by_index[3].position[2],2)
assert(out.parents[3]==2 and out.by_hash[33].node==3 and out.by_hash[33].parent==2);pass()
rows[1]=localrow(20,-5,8,math.pi/2);out=S.reconstruct(rows,links,hashes)
near(out.by_index[3].position[1],18);near(out.by_index[3].position[2],-4);near(out.by_index[3].position[3],8)
near(out.by_index[3].rotation[3],math.sqrt(.5));near(out.by_index[3].rotation[4],math.sqrt(.5));pass()
local function relative(a,b)
    local d={a.position[1]-b.position[1],a.position[2]-b.position[2],a.position[3]-b.position[3]};local p={}
    for i=1,3 do p[i]=(d[1]*b.basis[i][1]+d[2]*b.basis[i][2]+d[3]*b.basis[i][3])/(b.scale[i]^2)end
    return p
end
local changed=relative(out.by_index[3],out.by_index[2]);rows[1]=localrow(-111,70,-2,-.81)
out=S.reconstruct(rows,links,hashes);local changed2=relative(out.by_index[3],out.by_index[2])
for i=1,3 do near(changed[i],changed2[i])end;pass()
rows[3][11]=3;out=S.reconstruct(rows,links,hashes);near(relative(out.by_index[3],out.by_index[2])[2],3);pass()
rows,links,hashes=base();rows[1]=localrow(0,0,0,0,{2,2,2});out=S.reconstruct(rows,links,hashes)
near(out.by_index[3].position[1],2);near(out.by_index[3].position[2],4);near(out.by_index[3].scale[1],2);pass()
rows,links,hashes=base();links[1]=63*65536;out=S.reconstruct(rows,links,hashes)
assert(out.parents[1]==nil);near(out.by_index[3].position[1],1);pass()
for _,bad in ipairs({2,3,65537,999*65536+1})do
    rows,links,hashes=base();links[1]=bad;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
end
rows,links,hashes=base();links[1]=65537;links[2]=1;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
rows,links,hashes=base();hashes[3]=22;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
for _,at in ipairs({1,10,13})do
    rows,links,hashes=base();rows[2][at]=0/0;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
end
for _,scale in ipairs({0,-1,1/0,.0001,101})do
    rows,links,hashes=base();rows[2][13]=scale;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
end
rows,links,hashes=base();rows[1]=localrow(0,0,0,0,{2,1,1});rows[2]=localrow(0,0,0,.5)
assert(not pcall(S.reconstruct,rows,links,hashes));pass()
rows,links,hashes=base();rows[2][1]=-1;assert(not pcall(S.reconstruct,rows,links,hashes));pass()
rows,links,hashes=base();rows[2][1]=.4;assert(not pcall(S.reconstruct,rows,links,hashes));pass()

local function fixture(count)
    count=count or 63
    local f={reads=0,large=0,rows={},links={},hashes={},segments={},generation=7}
    f.c={exe=10000,unit=17,index=2,generation=7,object=20000,units=30000,generations=40000}
    f.s={identity='weapon1',player_identity='player',viewmodel=17,body=20,weapon=21,weapon_unit=22,context=23,camera=24,record=25}
    for node=1,count do f.rows[node]=localrow(node==1 and 10 or .01,0,0);f.links[node]=node==1 and 0 or 1;f.hashes[node]=1000+node end
    if count==63 then for node,hash in pairs({[9]=0x4fdd3337,[11]=0x03752c98,[14]=0x5c0c68d3,[31]=0x1620b2ce,[51]=0x60ed8c39})do f.hashes[node]=hash end end
    local function u32(v)return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
    local function bytes(values)
        local p=ffi.new('float[?]',count*16)
        for n=1,count do for k=1,16 do p[(n-1)*16+k-1]=values[n][k]end end
        return ffi.string(p,count*64)
    end
    function f:refresh()
        local l,h={},{};for n=1,count do l[n]=u32(self.links[n]);h[n]=u32(self.hashes[n])end
        self.segments[50000]=table.concat(l);self.segments[60000]=table.concat(h);self.segments[70000]=bytes(self.rows)
        local world={};for n=1,count do world[n]={1,0,0,0,0,1,0,0,0,0,1,0,n,2,3,1}end
        self.segments[80000]=bytes(world)
    end
    f:refresh()
    local pins={
        [0x28d310]='488d4160c3',[0x1f226b]='488bcb48c1e1064883c124488b4020',
        [0x5adf31]='664183f9010f85ab070000410fb75202',[0x5ae648]='f2420f10440724894538428b44072c'}
    local b={}
    function b:_alignment_executable()return f.c.exe end
    function b:_u8(at)assert(at==f.c.generations+f.c.index);return f.generation end
    function b:_ptr(at)
        if at==f.c.units+f.c.index*8 then return f.c.object end
        return assert(({[f.c.object+0x80]=70000,[f.c.object+0x88]=80000,[f.c.object+0x98]=50000,[f.c.object+0xa0]=60000})[at],'Unexpected pointer')
    end
    function b:_u32(at)if at==f.c.object+8 then return f.c.unit end;assert(at==f.c.object+0x70);return count end
    function b:_read(at,n)
        f.reads=f.reads+1
        if n>1024 then f.large=f.large+1 end
        local hex=pins[at-f.c.exe]
        if hex then if f.bad_pin then return string.rep('x',n)end;return(hex:gsub('..',function(v)return string.char(tonumber(v,16))end))end
        for base,raw in pairs(f.segments)do if at>=base and at+n<=base+#raw then
            local value=raw:sub(at-base+1,at-base+n)
            if f.during and at==70000 then local fn=f.during;f.during=nil;fn()end
            return value
        end end
        error('Unexpected read '..at..' '..n)
    end
    function b:snapshot()local s={};for k,v in pairs(f.s)do s[k]=v end;return s end
    f.b=b;f.cal={fps_context=f.c,identity='player'}
    return f
end
local f=fixture();local reader=S.new(f.b,f.cal);out=reader:sample(f.s)
assert(out.weapon==out.by_index[9]and out.camera==out.by_index[51]and f.large==0);near(out.weapon.position[1],10.01)
f.rows[9][11]=.3;f:refresh();near(reader:sample(f.s).weapon.position[2],.3);pass()
f=fixture();reader=S.new(f.b,f.cal);f.generation=8;assert(not pcall(reader.sample,reader,f.s));pass()
f=fixture();reader=S.new(f.b,f.cal);f.hashes[9]=999;f:refresh();assert(not pcall(reader.sample,reader,f.s));pass()
f=fixture();reader=S.new(f.b,f.cal);f.links[9]=65537;f:refresh();assert(not pcall(reader.sample,reader,f.s));pass()
f=fixture();reader=S.new(f.b,f.cal);f.during=function()f.generation=8 end;assert(not pcall(reader.sample,reader,f.s));pass()
f=fixture();reader=S.new(f.b,f.cal);f.s.identity='weapon2';assert(not pcall(reader.sample,reader,{identity='weapon1'}));pass()
f=fixture();reader=S.new(f.b,f.cal);f.s.player_identity='replacement';assert(not pcall(reader.sample,reader));pass()
f=fixture();f.bad_pin=true;assert(not pcall(S.new,f.b,f.cal));pass()
f=fixture(107);out=S.world(f.b,f.c,107);near(out.by_index[91].position[1],91);near(out.by_index[91].position[2],2)
assert(out.by_index[91].parent==1 and out.by_hash[1091]==out.by_index[91]and f.large==0);pass()
print('Fird source pose: '..cases..' FK, frame invariance, topology, float, fresh local and ownership cases passed')
