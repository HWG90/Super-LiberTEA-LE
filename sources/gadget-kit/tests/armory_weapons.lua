-- Exercise the registered ship inventory, category ordering, authored presets and cleanup.
local armory=dofile('src/armory_weapons.lua')
local guns=dofile('src/loadout_catalogue.lua').hidden
local function le(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216))
end
local function word(s)
    local a,b,c,d=s:byte(1,4);return a+b*256+c*65536+d*16777216
end
local function raw(s) return (s:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end)) end
local C={account=0x2E38230,account_count=0x1CE0,account_ready=0xDDCF8,records=0x1CE4,index=0xB9CE4,
    record_size=184,index_size=24,category_index=0xD1D48,weapons=0x2CE1BA0,weapon_count=199,weapon_size=32,max_rows=4096}
local game,account,world,base=0x10000000,0x20000000,0x30000000,0x40000000
local catalogue,scene,menu,profile,mission=0x51000000,0x52000000,0x53000000,0x54000000,0x55000000
local function fixture()
    local pages={}
    local function put(at,data)
        for i=1,#data do pages[at+i-1]=data:byte(i) end
    end
    local function get(at,n)
        local data={}
        for i=1,n do data[i]=string.char(pages[at+i-1] or 0) end
        return table.concat(data)
    end
    local pointers={[game+C.account]=account,[game+C.weapons]=catalogue,[game+0x2CE41B8]=world,[world+0xF147B8]=base,
        [game+0x2CE1508]=scene,[game+0x2E38160]=menu,[game+0x2E38110]=profile,[game+0x2E38188]=mission}
    local mem={writes=0}
    function mem:ptr(at)return pointers[at]end
    function mem:read(at,n)return get(at,n)end
    function mem:u32(at)return word(get(at,4))end
    function mem:copy(at,data)
        self.writes=self.writes+1
        if self.fail==self.writes then
            put(at,data:sub(1,2));return false,'short copy',2
        end
        put(at,data);return true,nil,#data
    end
    local host={constants=C,mem=mem}
    function host:_span(at,n)return get(at,n)end
    function host:_module()return game end
    function host:context()return {game=game,account=account,count=mem:u32(account+C.account_count)}end
    function host:same_context(a,b)return a.count==b.count end
    put(scene+0xAC29C,le(3));put(account+C.account_ready,le(12));put(account+C.account_count,le(3))
    for i,k in ipairs({1,0,9}) do
        local identity=le(i-1)..le(i)..le(i)
        put(account+C.records+(i-1)*184,identity..le(k));put(account+C.index+(i-1)*24,identity)
    end
    for k=0,24 do put(account+0xD1CE4+k*4,le(k==0 and 0 or k==1 and 1 or k<=9 and 2 or 3)) end
    put(account+C.category_index,le(1)..le(0)..le(2))
    put(base-28,raw('d0f3a8eb4c444c4401000000d0f3a8eba8bd0e000100000000000000'))
    for i,item in ipairs(guns) do
        local key=raw(item.type):reverse()
        put(catalogue+i*32,le(item.id)..le(0)..key..le(item.kind))
        put(base+(i-1)*16,key..le(i));put(base+0x1880+i*0x1308,le(3)..le(100+i))
    end
    return host,armory.new(host,guns),put,get
end
local function snapshot(get)
    return table.concat({get(account+C.records,184*6),get(account+C.index,24*6),
        get(account+0xD1CE4,100+24),get(account+0x1181AE4,148*3),get(account+C.account_count,4)})
end
local host,feature,put,get=fixture()
local before=snapshot(get)
feature:set_enabled(true)
put(menu+0x4294,le(5));feature:update(1);assert(host.mem.writes==0)
put(menu+0x4294,le(0));put(scene+0xAC29C,le(4));feature:update(1);assert(host.mem.writes==0)
put(scene+0xAC29C,le(3));feature:update(1)
assert(host:context().count==6,feature:status())
for i,item in ipairs(guns) do
    local root=account+C.records+(i+2)*184
    assert(word(get(root+8,4))==item.id and word(get(root+12,4))==1 and word(get(root+20,4))==2)
    local pr=account+0x1181AE4+(i-1)*148
    assert(word(get(pr,4))==item.id and word(get(pr+4,4))==(item.kind==1 and 0 or 1))
    for p=0,2 do assert(word(get(pr+12+12+p*40,4))==100+i)end
end
assert(get(account+C.category_index,24)==le(1)..le(0)..le(3)..le(4)..le(5)..le(2))
local writes=host.mem.writes;feature:update(1);assert(host.mem.writes==writes)
put(profile+0x44,le(guns[3].id));feature:set_enabled(false);feature:update(1);assert(not feature:is_clean())
put(profile+0x44,le(0));put(mission+0x2D800,le(1));put(mission+0x98,le(guns[3].id))
feature:update(1);assert(not feature:is_clean() and host:context().count==6)
put(mission+0x98,le(0));feature:update(1);assert(feature:is_clean() and snapshot(get)==before)
host,feature,put,get=fixture();before=snapshot(get)
feature:set_enabled(true);feature:update(1)
host.mem.fail=host.mem.writes+2
feature:set_enabled(false);feature:update(1)
assert(not feature:is_clean() and host:context().count==3)
feature:update(1);assert(feature:is_clean() and snapshot(get)==before)
host,feature,put,get=fixture();before=snapshot(get);host.mem.fail=6
feature:set_enabled(true);feature:update(1);assert(feature:is_clean() and snapshot(get)==before)
feature:update(1);assert(host:context().count==6)
-- A native rebuild in place should be eligible again.
put(account+C.account_count,le(3));put(account+0xD1CE4,before:sub(184*6+24*6+1,184*6+24*6+124))
feature:update(1);assert(host:context().count==6,feature:status())
host,feature,put,get=fixture()
local identity=le(0)..le(guns[1].id)..le(guns[1].id)
put(account+C.records,identity);put(account+C.index,identity)
put(account+0x1181AE4,le(guns[2].id)..le(0)..le(2))
before=snapshot(get);feature:set_enabled(true);feature:update(1)
assert(host:context().count==5 and word(get(account+0x1181AE4+8,4))==2)
assert(feature:shutdown() and snapshot(get)==before)
-- A pre-Armory equip can leave the engine's kind-4 placeholder with preferred modes.
host,feature,put,get=fixture()
local pos=account+0x1181AE4
local modes=le(0)..le(1)..le(1)..le(0)
put(pos,le(guns[1].id)..le(4)..string.rep('\0',124)..modes)
before=snapshot(get);feature:set_enabled(true);feature:update(1)
assert(get(pos+4,4)==le(0) and get(pos+24,4)==le(101) and get(pos+132,16)==modes)
assert(feature:shutdown() and snapshot(get)==before)
host,feature,put,get=fixture();put(account+C.category_index,le(0))
feature:set_enabled(true);feature:update(1);assert(host.mem.writes==0)
print('Armory registration, native defaults, existing records, scope, rollback, rebuild and cleanup passed')
