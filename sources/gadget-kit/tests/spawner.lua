-- Spawner: catalogue rows, request lifecycle through the vendored Bridge Combat module (no
-- native call before a verified mission actor) and the MCM Spawner page. Run with luajit.
mod={require=function(name)return dofile(name)end,log=function()end}
package.preload.cffi=package.preload.cffi or function()return require('ffi')end  -- LuaJIT's ffi has the cffi API
local PORT51=dofile('src/first_person/compat51.lua')

-- catalogue
local catalogue=dofile('src/spawner/catalogue.lua')
assert(#catalogue==38,'catalogue rows: '..#catalogue)
local types,nova={},nil
for _,row in ipairs(catalogue)do
    assert(row.kind==2 and #row.type==16 and #row.package==16 and row.name~='')
    assert(not types[row.type],'duplicate type '..row.type);types[row.type]=true
    if row.backpack then assert(row.backpack.kind==6 and #row.backpack.type==16 and #row.backpack.package==16)end
    if row.name=='LAS-44 Nova'then nova=row end
end
assert(nova and nova.id==4146034362 and nova.type=='73d84eaae8c75342' and nova.package=='601d726de9c3962f')

-- request lifecycle: the real module with a fake IO that records native binding attempts
local natives=0
local io={read=function()return nil,'fixture: no game'end,hashmap=function()return nil end,
    module=function()return nil,'fixture: no game'end,native=function()natives=natives+1;return nil,'fixture'end,
    resident=function()return nil,'fixture'end}
local logged={}
local Spawner=dofile('src/spawner.lua')
local s=Spawner.new(function(m)logged[#logged+1]=m end,{catalogue=catalogue,backend={},io=io,
    observe=function()return nil,'Waiting for a local mission actor'end,now=function()return 0 end})
local choices=s:choices();assert(#choices==38)
local index;for i,name in ipairs(choices)do if name=='LAS-44 Nova'then index=i end end;assert(index)
local ok,why=s:queue(index);assert(not ok and why:find('disabled'),why)
assert(s:set_enabled(true));assert(s:status():find('ready'),s:status())
ok,why=s:queue(index);assert(ok,why);assert(s:status():find('Queued LAS%-44 Nova'),s:status())
ok,why=s:queue(1);assert(not ok and why:find('already pending'),why)
s:update()
assert(s:status():find('waiting for normal gameplay'),s:status())
assert(natives==0,'native bound before a verified mission actor')
-- intent that never entered delivery is discarded on disable
assert(s:set_enabled(false));assert(GOOSE_GADGET_SPAWNER_REQUESTS_V1.task==nil)
assert(s:set_enabled(true));ok=s:queue(index);assert(ok)
assert(s:shutdown());ok,why=s:queue(index);assert(not ok and why:find('unloading'),why)
GOOSE_GADGET_SPAWNER_REQUESTS_V1=nil

-- guard loop: an optional guard may be unreadable (packed); a readable mismatch or an unreadable
-- required guard refuses. Fake memory serves module headers, every guard and the slot enum.
do
    local src=_G.io.open('src/spawner/support_weapons.lua'):read('*a')
    local G,E=0x10000000,0x20000000
    local mem={}
    local function put(at,bytes)mem[#mem+1]={at=at,bytes=bytes}end
    local function le(v,n)local t={}for i=1,n do t[i]=string.char(v%256);v=math.floor(v/256)end;return table.concat(t)end
    local function pe(base,stamp,size)
        put(base,'MZ'..string.rep('\0',0x3A)..le(0x80,4))
        put(base+0x80,'PE\0\0\100\134'..string.rep('\0',2)..le(stamp,4)..string.rep('\0',12)..'\11\2'..string.rep('\0',54)..le(size,4))
    end
    pe(G,0x6AE0E5FF,0x3382000);pe(E,0x6AE0964A,0x29FE000)
    local guards=src:match('local CURRENT_GUARDS=(%b{})')
    local optional
    for m,off,hex in guards:gmatch('{"(%a+)",(%d+),"(%x+)"}')do
        local bytes=hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end)
        off=tonumber(off);if off==0x4D4190 then optional=bytes else put((m=='game'and G or E)+off,bytes)end
    end
    for i,name in pairs({[1]='Primary',[2]='Sidearm',[3]='Support',[6]='Backpack'})do
        local at=G+0x3000000+i*0x20;put(at,name..'\0');put(G+0x1FCAE80+i*8,le(at,8))
    end
    local function read(at,n)
        for _,m in ipairs(mem)do if at>=m.at and at+n<=m.at+#m.bytes then return m.bytes:sub(at-m.at+1,at-m.at+n)end end
        return nil,'unreadable'
    end
    local fio={read=read,hashmap=function()return nil end,native=function()natives=natives+1 end,resident=function()end,
        module=function(name)if name=='game.dll'then return G,0x3382000,0x6AE0E5FF end;return E,0x29FE000,0x6AE0964A end}
    local view={can_start=true,context=2,menu_closed=true,base={scene=4,game=G}}
    local function attempt(optional_guards)
        GOOSE_GADGET_SPAWNER_REQUESTS_V1=nil
        local m=dofile('src/spawner/support_weapons.lua').new({io=fio,load=mod.require,catalogue=catalogue,scene=4,
            anchor={x=0,y=0,z=0,facing_x=1,facing_y=0,radius=1,vertical=1},delivery='inventory',
            optional_guards=optional_guards,observe=function()return view end,now=function()return 0 end})
        m:set_enabled(true);assert(m:queue(1));m:update(view);return m:status()
    end
    -- past the guards, the next refusal is the absent DBF-MCM menu service
    local saved=DBFMCM;DBFMCM=nil
    local why=attempt({[0x4D4190]=true});assert(why:find('Close the console menu'),why)
    put(G+0x4D4190,string.rep('\204',#optional))
    why=attempt({[0x4D4190]=true});assert(why:find('contract differs'),why)
    mem[#mem]=nil;why=attempt(nil);assert(why:find('memory unavailable'),why)
    DBFMCM=saved;GOOSE_GADGET_SPAWNER_REQUESTS_V1=nil
    assert(natives==0,'native bound during guard checks')

    -- a resident package whose exact UNIT never registers cannot deliver that row: the request
    -- ends with a reason before any inventory change and the next one is accepted (live
    -- 2026-11-02: "Unidentified support 2739958254" held the queue for the rest of the session)
    do
        local W,AV,RENDER,EP,PM,ST,MENU,CHAT=0x61000000,0x1234,0x5678,0x62000000,0x63000000,0x64000000,0x65000000,0x66000000
        local TR,TROWS,LED,LEDROWS,APP,API,LOADER,URES,UMAN=0x67000000,0x68000000,0x69000000,0x6A000000,0x6B000000,0x6C000000,0x6D000000,0x6E000000,0x6F000000
        local EMPTY=string.rep('\255',8)
        local function ptr(at,v)put(at,le(v,8))end
        ptr(G+0x2ce1508,ST);ptr(G+0x2e38160,MENU);ptr(G+0x2e28788,CHAT);put(CHAT+0x27E50,'\0')
        put(EP,string.rep('\0',8)..le(AV,4)..le(RENDER,4)..le(0,4)..'\1\0\0\0')
        put(PM+0x70,le(1,4));ptr(PM+0x110,EP)
        put(ST+0xac29c,le(4,4));ptr(G+0x2ce41b8,W);ptr(G+0x2ce1ee0,PM);put(MENU+0x4294,le(0,4));put(MENU+0x42B0,le(0,4))
        ptr(G+0x2ce16b8,TR);ptr(TR+0x68,TROWS);put(TROWS+0x2E0,string.rep('\0',12))
        ptr(G+0x2e381e8,LED);ptr(G+0x2ce14c8,E+0x2870240);ptr(E+0x1ab7808,APP)
        ptr(E+0x2870240+0x10,API);ptr(APP+0x400,LOADER);ptr(LOADER+0x208,0x70000000)
        ptr(API+0x2F0,E+0x2F01E0);ptr(API+0x328,E+0x2F0860)
        put(LED,le(LEDROWS,8)..le(8,4)..le(0,4)..EMPTY..le(0,4))
        local ledger={at=LEDROWS,bytes=string.rep(EMPTY..le(0,8),8)};mem[#mem+1]=ledger
        put(LOADER+0x218,string.rep('\0',512*24+12))
        ptr(E+0x1AB7838,URES);ptr(URES+0x3F8,UMAN);put(UMAN+0x2C0,le(1,4));ptr(UMAN+0x2C8,0x71000000)
        local resident,calls=false,{}
        local fakes={SUPPORT_PRESENT=function()return 0 end,
            SUPPORT_REQUEST=function(_,ids)ledger.bytes=require('ffi').string(ids,8)..le(1,4)..le(0,4)..ledger.bytes:sub(17);resident=true end}
        local dio={read=read,module=fio.module,hashmap=function()return 0 end,resident=function()return resident end,
            native=function(_,_,_,label)return fakes[label]or function()calls[#calls+1]=label end end}
        local menu={is_open=function()return false end,menu_binding_status=function()return{focused=true,editing=false}end}
        local view={can_start=true,context=2,menu_closed=true,render=RENDER,token='actor',base={scene=4,game=G,world=W,avatar=AV,ep=EP,pm=PM}}
        local clock=0
        local m=dofile('src/spawner/support_weapons.lua').new({io=dio,load=mod.require,catalogue=catalogue,scene=4,
            anchor={x=0,y=0,z=0,facing_x=1,facing_y=0,radius=1,vertical=1},delivery='inventory',globals={DBFMCM=menu},
            optional_guards={[0x4D4190]=true},observe=function()return view end,now=function()return clock end})
        m:set_enabled(true);assert(m:queue(1))
        clock=clock+1;m:update(view);assert(m:status()=='Loading '..catalogue[1].name,m:status())
        for _=1,30 do clock=clock+1;m:update(view)end
        assert(m:status():find(catalogue[1].name..' cannot be delivered',1,true),m:status())
        assert(#calls==0,'native delivery step called: '..tostring(calls[1]))
        local ok,why=m:queue(2);assert(ok,why)
    end
end

-- fifth stratagem slot against fake mission memory
do
    local Slot=dofile('src/spawner/stratagem_slot.lua')
    local G,NET,MIS,PM,W=0x10000000,0x30000000,0x40000000,0x50000000,0x60000000
    local mem={}
    local function le(v,n)local t={}for i=1,n do t[i]=string.char(v%256);v=math.floor(v/256)end;return table.concat(t)end
    local function set(at,b)for i=1,#b do mem[at+i-1]=b:byte(i)end end
    local function get(at,n)local t={}for i=0,n-1 do t[#t+1]=string.char(mem[at+i]or 0)end;return table.concat(t)end
    local me=0xD12345;local rec=MIS;local pay=rec+0x38
    set(G+0x2E38228,le(NET,8));set(NET+0xB398,le(me,4));set(G+0x2E38188,le(MIS,8));set(MIS+0x2D800,le(1,4))
    set(rec,le(me,4));set(rec+8,'mission1');set(pay+0x788,le(2,4))
    set(pay+0x188,Slot.entry(127));set(pay+0x188+0x30,Slot.entry(139))
    local solo=true
    local function setpm()set(PM+0x70,le(solo and 1 or 2,4))end;setpm()
    local fio={module=function()return G end,read=function(at,n)return get(at,n)end}
    local writes=0
    local view={can_start=true,base={pm=PM,world=W}}
    local loaded,queued=false,nil
    local support={loaded=function(_,i,w)return loaded and w==W end,queue=function(_,i,d)queued={i,d};return true end,status=function()return'Loading fixture'end}
    local list={{name='Orbital Railcannon',kind=60},{name='Orbital Strike',kind=139},{name='RS-422 Railgun',kind=58,item=3078242205}}
    local slot=Slot.new({io=fio,observe=function()return view end,support=support,items={[3078242205]=7},stratagems=list,
        write=function(at,b)writes=writes+1;set(at,b);return true end})
    assert(slot:queue(1));slot:update(false);assert(writes==0,'wrote while disabled')
    slot:update(true);assert(slot:status():find('added as your fifth'),slot:status())
    assert(get(pay+0x788,4)==le(3,4) and get(pay+0x188+2*0x30,0x30)==Slot.entry(60))
    assert(slot:queue(3));slot:update(true);assert(slot:status():find('already added this mission'),slot:status())
    -- a new mission: support weapon waits for its preload, then appends
    set(rec+8,'mission2');slot=Slot.new({io=fio,observe=function()return view end,support=support,items={[3078242205]=7},stratagems=list,
        write=function(at,b)writes=writes+1;set(at,b);return true end})
    assert(slot:queue(2));slot:update(true);assert(slot:status():find('already available'),slot:status())
    assert(slot:queue(3));local before=writes;slot:update(true)
    assert(queued[1]==7 and queued[2]=='preload' and writes==before and slot:status()=='Loading fixture')
    loaded=true;slot:update(true);assert(slot:status():find('RS%-422 Railgun added'),slot:status())
    assert(get(pay+0x788,4)==le(4,4) and get(pay+0x188+3*0x30,4)==le(58,4))
    -- co-op refused
    set(rec+8,'mission3');solo=false;setpm()
    slot=Slot.new({io=fio,observe=function()return view end,support=support,items={},stratagems=list,write=function()error('no write')end})
    assert(slot:queue(1));slot:update(true);assert(slot:status():find('solo'),slot:status())
end

-- MCM Spawner page
local M=dofile('src/mcm.lua')
local c={}
function c:set_enabled(v)self.enabled=v;return true end
function c:set_unreleased()return true end
function c:stop_freezes()self.freezes={}end
function c:is_clean()return true end
function c:status()return'Fixture'end
function c:set_categories(v)self.categories=v;return true end
function c:set_freezes(v)self.freezes=v;return true end
local fake={queued={},enabled=nil}
function fake:choices()return{'A','B'}end
function fake:queue(i)self.queued[#self.queued+1]=i;return true end
function fake:set_enabled(v)self.enabled=v;return true end
function fake:status()return'Spawner fixture'end
function fake:stratagem_choices()return{'S1','S2','S3'}end
function fake:queue_stratagem(i)self.stratagem=i;return true end
function fake:stratagem_status()return'Slot fixture'end
local spec,values,closed
DBFMCM={mods={}}
function DBFMCM.close()closed=(closed or 0)+1;return true end
function DBFMCM.register(t)
    spec=t;values={}
    for _,page in ipairs(t.pages)do for _,control in ipairs(page.controls)do
        if control.id and control.default~=nil then values[control.id]=control.default end
    end end
    local h={get=function(id)return values[id]end,unregister=function()DBFMCM.mods[t.id]=nil;return true end}
    DBFMCM.mods[t.id]={handle=h,pages=t.pages,controls={}}
    return h
end
local menu=M.new(c,nil,fake);assert(menu:update(0))
local page=spec.pages[3];assert(page.id=='spawner'and page.name=='Spawner')
assert(spec.pages[4].id=='first_person','First Person page moved')
local byid={};for _,control in ipairs(page.controls)do if control.id then byid[control.id]=control end end
assert(byid.spawner_weapon.type=='choice'and #byid.spawner_weapon.choices==2)
assert(fake.enabled==false)
values.spawner_enabled=true;assert(menu:update(0.3));assert(fake.enabled==true)
values.spawner_weapon=2;assert(byid.spawner_equip.on_activate()==true)
assert(fake.queued[1]==2 and closed==1)
values.spawner_stratagem=3;assert(byid.spawner_add_stratagem.on_activate()==true and fake.stratagem==3 and closed==2)
-- a refusal reaches the menu: MCM shows a string result as the notice and drops a second value
function fake:queue()return false,'A support request is already pending'end
assert(byid.spawner_equip.on_activate()=='A support request is already pending' and closed==2)
function fake:queue_stratagem()return false,'A stratagem request is already pending'end
assert(byid.spawner_add_stratagem.on_activate()=='A stratagem request is already pending' and closed==2)
menu:refresh_status();assert(byid.spawner_status.label=='Status: Spawner fixture')
assert(byid.spawner_stratagem_status.label=='Status: Slot fixture')
assert(menu:shutdown());assert(fake.enabled==false)
print('Spawner catalogue (38 rows, LAS-44 Nova), request lifecycle without premature native calls, optional packed guard, model-less row ends its request, fifth stratagem slot, and MCM page with visible refusals passed')
