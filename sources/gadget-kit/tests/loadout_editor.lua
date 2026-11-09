-- Run from the kit root with lua5.1 or luajit. Optional arg: DBF-MCM src/core.lua.
local catalogue=dofile('src/loadout_catalogue.lua')
local Adapter=dofile('src/loadout_backend.lua')
local part_data=dofile('src/loadout_parts.lua')
local attachments=dofile('src/loadout_attachments.lua').new(part_data)
local Editor=dofile('src/loadout_editor.lua')
local function le(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216))
end
local function bytes(s) return (s:gsub('..',function(x)return string.char(tonumber(x,16)) end)):reverse() end
local storage,pointers,mappings={},{},{}
local function put(at,s) for i=1,#s do storage[at+i-1]=s:sub(i,i) end end
local function get(at,n) local t={} for i=0,n-1 do t[#t+1]=assert(storage[at+i],('unmapped %x'):format(at+i)) end return table.concat(t) end
local function map(at,id,val) mappings[at]=mappings[at] or {};mappings[at][id]=val end
local io={read=get,hashmap=function(at,id)return mappings[at] and mappings[at][id] end}
local writes={}
local mem={ptr=function(_,at)return pointers[at] end,write=function(_,at,s)
    writes[#writes+1]={at=at,s=s};put(at,s);return true
end}
local g,w,pm,inv,net,mission,defs=0x10000000,0x20000000,0x30000000,0x31000000,0x32000000,0x33000000,0x34000000
local owner=72
local base={avatar=owner,game=g,world=w,pm=pm,ep=88888}
local view={render=111,token='diver A',base=base,ready=true}
local peer='selfpeer'
pointers[g+0x2E38228]=net;pointers[g+0x2E38188]=mission
put(net+0xB398,peer);put(net+0xB3A8,peer);put(mission,peer..string.rep('M',16));put(mission+0x2D800,le(1));put(pm+0x70,le(1))
pointers[g+0x2CE18E8]=inv;put(inv+0x18,le(1));map(inv+0x28,owner,0)
pointers[inv+0x40]=400000;pointers[400000]=base.ep;pointers[inv+0x50]=500000
local kinds={1,3,2,6};local equipped,alternatives={},{};
local function equip(i,item,eid)
    put(500000+(i-1)*4,le(eid))
    if item then
        map(w+0xF1C978,eid,eid)
        put(w+0xF349E0+eid*24,bytes(item.type)..le(eid)..le(404)..le(0)..le(1))
    end
end
for i,k in ipairs(kinds) do
    for _,r in ipairs(catalogue.gear) do
        if r.kind==k then if not equipped[i] then equipped[i]=r else alternatives[i]=r;break end end
    end
    equip(i,equipped[i],50+i)
end
-- Exercise Rover through the backpack equip and reinforcement cases below.
local roverName='AX/LAS-5 Guard Dog Rover'
local rover
for _,item in ipairs(catalogue.gear) do
    if item.kind==6 and item.name==roverName then
        assert(not rover and item.id==1440244352 and item.type=='af9b683ccb6ddc02')
        assert(item.package=='32cb44321da1b5a0' and item.unit=='a1a026c8bb37a96e')
        rover=item
    end
end
alternatives[4]=assert(rover)
local roverCall=catalogue.stratagems[118]
assert(roverCall.kind==118 and roverCall.id==951988742 and roverCall.selectable and roverCall.name==roverName)
pointers[g+0x2CE1508]=900000;pointers[g+0x2CE1618]=901000;pointers[g+0x2CE41B8]=w
put(900000+0xAC29C,le(4));put(901000+0x3A8,le(view.render))
put(mission+0x38,attachments:factory(equipped[1].id)..string.rep('P',12)..attachments:factory(equipped[2].id)..string.rep('S',12))
local at=mission+0x38+0x188
local selected={31,66,104,139}
local function entry(kind,uses,shared)
    return le(kind)..le(uses)..string.char(0,shared and 1 or 0)..string.rep('\0',6)..string.rep('T',32)
end
for i,k in ipairs({127,149,34,131,31,66,104,139,138,25}) do put(at+(i-1)*48,entry(k,2,i<=4 or i==9)) end
local count_at=mission+0x38+0x788
put(count_at,le(10))
local baseline=get(at,480)
local cat=0x35000000;pointers[g+0x2CE1BA0]=cat;put(cat,string.rep('\0',199*32))
pointers[g+0x2E4A228]=defs
local target=catalogue.stratagems[18]
local addr=defs+400
pointers[g+0x31870E0+target.kind*8]=addr
put(addr,string.rep('\0',400));put(addr,le(target.kind)..le(target.id))
put(addr+0x50,le(1));put(addr+0x80,le(3));put(addr+0xBC,le(1));put(addr+0xC0,le(1));put(addr+0xA8,bytes('1122334455667788'))
local ready=false;local prepared;local gear_calls=0
local last_mods
local support={loadout_busy=function()return false end,prepare_loadout=function(_,v,pkgs)
    assert(v==view);prepared=pkgs;return ready
end,replace_loadout_item=function(_,v,slot,item,expected,mods,commit)
    assert(v==view)
    local i=slot==6 and 4 or slot
    assert(item.kind==kinds[i] and get(500000+(i-1)*4,4)==le(expected))
    if commit then commit() end;last_mods=mods;gear_calls=gear_calls+1;equip(i,item,200+gear_calls);return true
end}
local adapter=Adapter.new(mem,io,function()return view end,support,attachments)
local function job(slot,strat,item,current)
    return {owner=view.token,session=get(mission,24),mission=mission,slot={index=slot,strat=strat},item=item,expected=current}
end
for i=1,4 do
    local state=adapter:capture();assert(state.strats[i]==selected[i])
    local j=job(i,true,target,selected[i])
    assert(adapter:apply(j,state)==false and prepared[1]=='1122334455667788' and #writes==i-1)
    ready=true;assert(adapter:apply(j,adapter:capture()))
    local off=(i+3)*48
    assert(get(at,480)==baseline:sub(1,off)..le(18)..le(1)..baseline:sub(off+9))
    assert(get(count_at,4)==le(10));put(at,baseline);ready=false
end
-- A changed owner, peer, selection, duplicate call or shared slot refuses the write.
local j=job(1,true,target,31)
local function refuses(f) local count=#writes;assert(not pcall(f));assert(#writes==count) end
view.token='diver B';refuses(function()adapter:apply(j,adapter:capture())end);view.token=j.owner
put(mission+8, 'another mission!');refuses(function()adapter:apply(j,adapter:capture())end);put(mission+8,string.rep('M',16))
put(net+0xB3A8,'not host');refuses(function()adapter:capture()end);put(net+0xB3A8,peer)
put(at+4*48,le(80));refuses(function()adapter:apply(j,adapter:capture())end);put(at,baseline)
put(at+8*48,le(18));refuses(function()adapter:apply(j,adapter:capture())end);put(at,baseline)
put(at+4*48+9,'\1');assert(not adapter:capture().strats[1]);put(at,baseline)
put(count_at,le(6));assert(not adapter:capture().strats[1]);put(count_at,le(10))
-- An explicit equipment dependency and the stratagem package must both load.
local required=273;put(addr+0xF8,le(required))
refuses(function()adapter:apply(j,adapter:capture())end)
local pack=0x36000000;pointers[w+0xF14008]=pack
local ty=bytes('0123456789abcdef')
put(cat,le(required)..le(0)..ty);put(pack,string.rep('\0',0x44C*16));put(pack,ty..le(2))
put(pack+0x44C0+2*32+8,bytes('abababababababab'))
assert(adapter:apply(j,adapter:capture())==false and prepared[2]=='abababababababab')
ready=true;local original_prepare=support.prepare_loadout
support.prepare_loadout=function() put(at+5*48,le(18));return true end
refuses(function()adapter:apply(j,adapter:capture())end)
support.prepare_loadout=original_prepare;put(at,baseline);put(addr+0xF8,le(0))
-- Each stratagem above ran against an independently reset mission.
adapter.retained=nil
-- All four inventory slots, including an empty pack. Preserve every other slot.
for i,slot in ipairs({1,2,3,6}) do
    if i==4 then equip(4,nil,0xFFFFFFFF) end
    local before=adapter:capture();local old=before.gear[slot]
    local req=job(slot,false,alternatives[i],old.entity);req.old_type=old.id
    assert(adapter:apply(req,before))
    local after=adapter:capture()
    assert(after.gear[slot].id==alternatives[i].type)
    for s,v in pairs(before.gear) do if s~=slot then assert(v.entity==after.gear[s].entity) end end
    refuses(function()adapter:apply(req,after)end)
end
assert(gear_calls==4)
-- Reinforcement payload, package residency, optimistic concurrency and a failed native equip.
local primary=alternatives[1]
local category=2
local choices=assert(attachments:menu(primary.id,category))
local opt=choices.ids[2]
local function part_job()
    local state=adapter:capture()
    local j=job(1,false,primary,state.gear[1].entity)
    j.old_type,j.category,j.part_id,j.weapon_record=primary.type,category,opt,state.weapons[1]
    return j,state
end
local pj,ps=part_job()
local before=get(mission+0x38,0xc0)
ready=false
assert(adapter:apply(pj,ps)==false and get(mission+0x38,0xc0)==before and gear_calls==4)
ready=true
local replace=support.replace_loadout_item
support.replace_loadout_item=function(_,v,slot,item,old,mods,commit)
    commit()
    assert(get(mission+0x38,0x54)~=ps.weapons[1])
    error('native refused before changing inventory')
end
assert(not pcall(adapter.apply,adapter,pj,ps));assert(get(mission+0x38,0xc0)==before)
support.replace_loadout_item=replace
assert(adapter:apply(pj,ps))
local expected=attachments:edit(ps.weapons[1],primary.id,category,opt)
assert(get(mission+0x38,0xc0)==expected..before:sub(0x55))
assert(last_mods[category]==part_data.parts[opt].modifier)
assert(attachments:selected(expected,primary.id,category)==opt)
local stale,st=part_job()
put(mission+0x38,ps.weapons[1])
assert(not pcall(adapter.apply,adapter,stale,st))
put(mission+0x38,expected)
-- Native reinforcement reads the persistent records for the two issued weapons.
local function reinforce(unit)
    view.render=unit;view.token='diver '..unit
    put(901000+0x3A8,le(unit));equip(1,primary,unit+100);equip(2,alternatives[2],unit+101)
    equip(3,nil,0xFFFFFFFF);equip(4,nil,0xFFFFFFFF)
end
assert(get(mission+0x38,4)==le(primary.id) and get(mission+0x98,4)==le(alternatives[2].id))
local calls=gear_calls
reinforce(700);adapter:reinforce(.5);adapter:reinforce(.5)
assert(gear_calls==calls+2 and adapter:capture().gear[6].id==alternatives[4].type)
assert(get(mission+0x38,0x54)==expected)
-- Dropping the pack on the same life stays effective, and an early pickup on
-- the next life is respected. A different mission receives no remembered gear.
equip(4,nil,0xFFFFFFFF);adapter:reinforce(.5);assert(not adapter:capture().gear[6].id)
reinforce(900);equip(4,equipped[4],777);adapter:reinforce(.5);adapter:reinforce(.5)
assert(adapter:capture().gear[6].id==equipped[4].type and gear_calls==calls+3)
put(mission+8,'different world!');adapter:reinforce(.5);assert(not adapter.retained)
put(mission+8,string.rep('M',16))
equip(4,alternatives[4],300)

if arg[1] then
    -- Exercise actual MCM normalization, registration, callbacks and saved indices.
    local gear_before,writes_before=gear_calls,#writes
    local open=true;local saves=0
    local store={load=function()return {loadout_primary=5}end,save=function()saves=saves+1;return true end}
    local api=dofile(arg[1]).new(store);api.is_open=function()return open end
    local editor=Editor.new(adapter,catalogue);local page=editor:page(function()return open end)
    local h=api.register({id='kit',name='Kit',pages={page}})
    local rec=api.mods.kit
    editor:update(0,api,rec);assert(gear_calls==gear_before and saves==0)
    local Menu=dofile((arg[1]:gsub('core.lua$','menu.lua')))
    local screen=Menu.new(api);screen.visible=true;screen.focus='settings';screen.window_width=1600
    local function placement()
        local labels={}
        for _,command in ipairs(screen.compose(1920,1080)) do
            if command.type=='text' then labels[command.full_text or command.text]=command end
        end
        return assert(labels.Primary),assert(labels.Optics),labels.Underbarrel
    end
    local left,right,first=placement()
    assert(right.x>left.x and (first or right).y==left.y,'Attachment column is not next to Primary')
    screen.window_width=1100
    left,right=placement();assert(left.x==right.x and left.y>right.y,'Compact attachment placement')
    local optic=rec.controls.loadout_primary_part_2;assert(optic.column==2 and optic.choices[h.get(optic.id)]==choices.labels[2]);assert(h.edit(optic.id,1));editor:update(.2,api,rec);assert(attachments:selected(adapter:capture().weapons[1],primary.id,2)==choices.ids[1])
    for _,pair in ipairs({{'primary',1},{'secondary',2},{'support',3},{'backpack',4}}) do
        local id='loadout_'..pair[1];local i=pair[2];local c=rec.controls[id]
        assert(h.available(id) and c.choices[h.get(id)]==alternatives[i].name)
        local wanted
        for k,v in ipairs(c.choices) do if v==equipped[i].name then wanted=k end end
        assert(h.edit(id,assert(wanted)));assert(editor.job and not h.available(id))
        editor:update(0.2,api,rec);assert(not editor.job and c.choices[h.get(id)]==equipped[i].name)
    end
    local c=rec.controls.loadout_stratagem_4;local n
    for i,v in ipairs(c.choices) do if v==target.name then n=i end end
    assert(h.edit(c.id,n));editor:update(.2,api,rec);assert(adapter:capture().strats[4]==target.kind)
    open=false;editor:update(0,api,rec);assert(not editor.state)
    assert(#writes==writes_before+4 and saves==6 and gear_calls==gear_before+5)
    -- The two laser rifles have different item IDs and use different heatsinks.
    open=true
    local shear,scythe
    for _,item in ipairs(catalogue.gear) do
        if item.type=='7e3145a5baa4b948' then shear=item end
        if item.type=='27ee1ed8f6fb6356' then scythe=item end
    end
    assert(shear.name=='LAS-22 SHEAR' and shear.id==2112173638 and scythe.name=='LAS-5 Scythe')
    equip(1,shear,765)
    local original=attachments:factory(shear.id)
    put(mission+0x38,original)
    editor:update(1,api,rec)
    screen.window_width=1600
    local rendered={}
    for _,cmd in ipairs(screen.compose(1920,1080)) do
        if cmd.type=='text' then rendered[cmd.full_text or cmd.text]=cmd end
    end
    local heat=rec.controls.loadout_primary_part_5
    assert(rendered[shear.name] and rendered.Optics.x>rendered.Primary.x and rendered.Optics.y==rendered.Primary.y)
    assert(rendered.Heatsink.x==rendered.Optics.x and rendered.Heatsink.y<rendered.Optics.y)
    assert(not (rendered.Underbarrel or rendered.Muzzle or rendered.Paint or rendered.Magazine))
    assert(h.available(optic.id) and h.available(heat.id))
    assert(heat.choices[1]=='Factory (Standard Heatsink)' and heat.choices[2]=='High Capacity Heatsink' and heat.choices[3]=='Rapid Heatsink')
    assert(h.edit(heat.id,3));editor:update(.2,api,rec)
    assert(editor.message=='Heatsink equipped Rapid Heatsink' and last_mods[5]==part_data.parts[1393691251].modifier)
    assert(h.edit(optic.id,2));editor:update(.2,api,rec)
    local saved=adapter:capture().weapons[1]
    assert(attachments:selected(saved,shear.id,2)==1713239419 and attachments:selected(saved,shear.id,5)==1393691251)
    for _,fixed in ipairs({1,3,4}) do
        assert(attachments:selected(saved,shear.id,fixed)==attachments:selected(original,shear.id,fixed))
    end
    assert(not pcall(attachments.edit,attachments,saved,shear.id,5,2272725875),'Scythe sink offered on SHEAR')
    -- Rebuilding the native record on a new life restores both choices together.
    reinforce(1010);equip(1,shear,766);put(mission+0x38,original)
    for i=1,8 do adapter:reinforce(.5) end
    assert(adapter:capture().weapons[1]==saved)
    local ballistic
    for _,item in ipairs(catalogue.gear) do
        local menu=item.kind==1 and attachments:menu(item.id,5)
        if menu and menu.label=='Magazine' then ballistic=item;break end
    end
    assert(ballistic);equip(1,ballistic,767);editor:update(1,api,rec);assert(heat.label=='Magazine')
    -- Each hidden firearm is selectable by name and writes its native reinforcement slot.
    open=true;editor:update(.6,api,rec)
    for _,item in ipairs(catalogue.hidden) do
        local slot=item.kind==1 and 1 or 2
        local control=rec.controls[slot==1 and 'loadout_primary' or 'loadout_secondary']
        local choice
        for i,label in ipairs(control.choices) do
            if label==item.name then assert(not choice);choice=i end
        end
        local before=adapter:capture()
        assert(h.edit(control.id,assert(choice)));editor:update(.2,api,rec)
        local after=adapter:capture()
        assert(after.gear[slot].id==item.type and after.weapons[slot]:sub(1,4)==le(item.id))
        local other=3-slot
        assert(after.weapons[other]==before.weapons[other] and after.gear[other].entity==before.gear[other].entity)
        assert(not editor.job and control.choices[h.get(control.id)]==item.name)
    end
    -- Start at the loader entry point and register the real Kit page in DBF-MCM.
    local function yes() return true end
    local service={mem={},status=function()return 'Ready' end,shutdown=yes,
        update=yes,equipment_ready=yes,set_enabled=yes,set_unreleased=yes,stop_freezes=yes,is_clean=yes,
        set_categories=yes,set_freezes=yes,capture=function()return nil,'fixture' end}
    local function wrapper()return {new=function()return service end} end
    local module={
        ['src/first_person.lua']={enable=yes,revision=function()return 1 end,attach=yes,
            pages=function()return {} end,changed=yes,update=yes,shutdown=yes},
        ['src/equipment.lua']=wrapper(),['src/equipment_backend.lua']=wrapper(),['src/backend.lua']=wrapper(),
        ['src/controller.lua']=wrapper(),['src/objectives.lua']=wrapper(),
        ['src/spawner/backend.lua']={new=function()return mem end},
        ['src/spawner/io.lua']={new=function()return io end},
        ['src/spawner/observer.lua']={observer=function()return function()return view end end},
        ['src/spawner/support_weapons.lua']={new=function()return setmetatable({
            choices=function()return {'Support'} end,update=yes,status=service.status,set_enabled=yes,shutdown=yes,
        },{__index=support}) end},
    }
    mod={log=function()end,require=function(path)return module[path] or dofile(path) end}
    DBFMCM=dofile(arg[1]).new({load=function()return {} end,save=yes})
    DBFMCM.is_open=function()return true end
    local app=dofile('main.lua');app.on_enable();app.on_update(.5)
    local registration=assert(DBFMCM.mods.goose_temporary_unlocks)
    assert(registration.controls.loadout_stratagem_4 and registration.handle.available('loadout_backpack'))
    assert(registration.handle.edit('loadout_support',2))
    app.on_update(.2)
    assert(not registration.controls.loadout_support.disabled)
    assert(app.on_disable())
end
-- A delayed hand acknowledgement finishes the existing job without issuing a second equip.
do
    local original=support.replace_loadout_item
    local receipt={}
    support.replace_loadout_item=function(...)
        assert(original(...))
        return true,nil,receipt
    end
    local st=adapter:capture()
    local req=job(1,false,primary,st.gear[1].entity)
    req.old_type=st.gear[1].id
    local before=gear_calls
    assert(adapter:apply(req,st)==false)
    assert(adapter:apply(req,adapter:capture())==false and gear_calls==before+1)
    receipt.complete=true
    assert(adapter:apply(req,adapter:capture()) and gear_calls==before+1)
    support.replace_loadout_item=original
end
-- Simulate a reinforcement that rebuilds the issued primary and stratagem from the old record.
local function retained_job(slot,strat,item)
    local st=adapter:capture()
    local old=not strat and st.gear[slot]
    local j=job(slot,strat,item,old and old.entity or st.strats[slot]);j.old_type=old and old.id
    return j,st
end
adapter.retained=nil;put(at,baseline)
local j,st=retained_job(1,false,primary)
local prior=st.weapons[1]
assert(adapter:apply(j,st));local saved_bytes=adapter:capture().weapons[1]
j,st=retained_job(3,true,target);assert(adapter:apply(j,st))
reinforce(1030);put(mission+0x38,prior);put(at,baseline)
for i=1,8 do adapter:reinforce(.5) end
assert(adapter:capture().weapons[1]==saved_bytes and adapter:capture().strats[3]==target.kind)
assert(get(count_at,4)==le(10))
print('Reinforcement records, per-life gear and stratagem restore, compatible attachments, equip rollback and MCM column layout passed')
