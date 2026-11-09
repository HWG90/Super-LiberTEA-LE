-- Build 26251122, local mission inventory and mission peer payload.
local M = {}
local EMPTY = 0xFFFFFFFF
local ZERO = string.rep('\0',8)
local offsets = {[1]=0,[2]=4,[3]=8,[6]=12}
local function word(bytes, offset)
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    assert(d,'Incomplete mission record')
    return a+b*256+c*65536+d*16777216
end
local function le(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216))
end
local function key(bytes)
    return (bytes:reverse():gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
local function list_has(list,kind)
    for off=0,#list-1,0x30 do if word(list,off)==kind then return true end end
    return false
end
function M.new(mem,io,observe,support,attachments)
    local self={attachments=attachments}
    local function read(at,n) return assert(io.read(at,n),'Mission memory unavailable') end
    local function ptr(at) return assert(mem:ptr(at),'Mission owner unavailable') end
    local function number(at) return word(read(at,4),0) end
    local function index(at,id,limit)
        local i=assert(io.hashmap(at,id),'Local entity unavailable')
        assert(i>=0 and i<limit,'Local entity row out of bounds')
        return i
    end
    function self:capture()
        local view,why=observe()
        assert(view and view.ready,why or (view and view.reason) or 'Enter normal on-foot mission gameplay')
        local v=view.base
        local net=ptr(v.game+0x2E38228)
        local peer=read(net+0xB398,8)
        local mission=ptr(v.game+0x2E38188)
        assert(peer~=ZERO and read(net+0xB3A8,8)==peer and number(mission+0x2D800)==1
            and read(mission,8)==peer and number(v.pm+0x70)==1,'Loadout Editor requires a solo hosted mission')
        local inv=ptr(v.game+0x2CE18E8)
        local invrow=index(inv+0x28,v.avatar,number(inv+0x18))
        assert(invrow<1048576 and ptr(ptr(inv+0x40)+invrow*8)==v.ep,'Inventory owner changed')
        local inv_at=ptr(inv+0x50)+invrow*0x30
        local weapons=read(inv_at,16)
        local session=read(mission,24)
        local state={session=session,view=view,owner=view.token,mission=mission,peer=peer,payload=mission+0x38,gear={},strats={}}
        for slot,offset in pairs(offsets) do
            local entity=word(weapons,offset)
            local id
            if entity~=EMPTY and entity~=0 then
                local row=index(v.world+0xF1C978,entity,1048576)
                local desc=read(v.world+0xF349E0+row*24,24)
                assert(word(desc,8)==entity and desc:byte(21)%2==1,'Inventory item was retired')
                id=key(desc:sub(1,8))
            end
            state.gear[slot]={entity=entity,id=id}
        end
        state.weapons={read(state.payload,0x54),read(state.payload+0x60,0x54)}
        local count=number(state.payload+0x788)
        assert(count<=32,'Mission stratagem list changed')
        local list=count>0 and read(state.payload+0x188,count*0x30) or ''
        state.list=list
        -- DBF's native shortcuts address entries 4..7. Shared calls carry the
        -- mission-issued flag at +9. A bonus call can follow the four player slots.
        local regular=count>=8
        for i=0,7 do
            if list:byte(i*0x30+10)~=(i<4 and 1 or 0) then regular=false end
        end
        if regular then
            for slot=1,4 do state.strats[slot]=word(list,(slot+3)*0x30) end
        end
        assert(read(inv_at,16)==weapons and number(state.payload+0x788)==count and
            ptr(v.game+0x2E38188)==mission and read(mission,24)==session and session:sub(1,8)==peer,'Mission loadout changed while reading')
        return state
    end

    -- The mission prepares the explicit stratagem package (+A8) and the
    -- catalogue item's LoadoutPackage (+F8). A support call can require both.
    local function packages(state,definition,stable)
        local result,seen={},{}
        local function add(raw)
            if raw~=ZERO and not seen[raw] then
                result[#result+1]=key(raw)
                seen[raw]=true
            end
        end
        add(definition:sub(0xA9,0xB0))
        local required=word(definition,0xF8)
        local v=state.view.base
        local cat=read(ptr(v.game+0x2CE1BA0),199*32)
        local types={}
        for i=0,198 do
            local id=word(cat,i*32)
            if id~=0 and (id==required or id==stable) then types[cat:sub(i*32+9,i*32+16)]=id end
        end
        if next(types) then
            local base=ptr(v.world+0xF14008)
            local entries=read(base,0x44C*16)
            for i=0,0x44C-1 do
                local id=types[entries:sub(i*16+1,i*16+8)]
                if id then
                    local row=word(entries,i*16+8)
                    assert(row<0x226,'Item package record changed')
                    local raw=read(base+0x44C0+row*32+8,8)
                    if raw~=ZERO then add(raw); if id==required then required=0 end end
                end
            end
        end
        assert(required==0,'Required stratagem item package is unavailable')
        assert(#result>0,'No verified package for this stratagem')
        return result
    end
    local restore_order={1,2,3,6,11,12,13,14}
    local function same_mission(saved,state)
        return saved.world==state.view.base.world and saved.mission==state.mission and saved.session==state.session
    end
    -- Keep only explicit edits for this mission. The native records usually survive
    -- reinforcement. Support and backpack have no slots in the spawn payload.
    local function remember(slot,item,state)
        local saved=self.retained
        if not saved or not same_mission(saved,state) then
            saved={game=state.view.base.game,world=state.view.base.world,mission=state.mission,
                session=state.session,unit=state.view.render,items={},elapsed=0}
            self.retained=saved
        end
        if item.record or item.previous_kind then
            local prior=saved.items[slot]
            -- An external loadout change establishes a new reinforcement baseline.
            if prior and (not item.record or prior.record==item.initial) then
                item.initial=prior.initial
                item.old_type=prior.old_type
                item.previous_kind=prior.previous_kind
            end
        end
        saved.items[slot]=item
        if saved.pending then saved.pending[slot]=nil end
    end
    function self:reinforce(dt)
        local saved=self.retained
        if not saved then return end
        saved.elapsed=saved.elapsed+dt
        if saved.elapsed<0.5 then return end
        saved.elapsed=0
        -- Poll only cheap identity fields while the same diver is alive. The Unit
        -- reference includes its generation and changes even when an ECS row is reused.
        local game=saved.game
        local scene=number(ptr(game+0x2CE1508)+0xAC29C)
        if scene==3 then self.retained=nil;return end
        if scene~=4 then return end
        if ptr(game+0x2CE41B8)~=saved.world or ptr(game+0x2E38188)~=saved.mission
            or read(saved.mission,24)~=saved.session then self.retained=nil;return end
        local unit=number(ptr(game+0x2CE1618)+0x3A8)
        if unit==0 or unit==EMPTY or (unit==saved.unit and not saved.pending) then return end
        local state=self:capture()
        if not same_mission(saved,state) or state.view.render~=unit then return end
        if unit~=saved.unit then
            saved.unit,saved.pending,saved.cursor,saved.attempts=unit,{},0,{}
            for slot,item in pairs(saved.items) do saved.pending[slot]=item end
        end
        -- Settle one slot per poll. Retire an attempt before any native call.
        -- Only a pending package requests a retry. Pickups stay in the player's hands.
        local cursor=saved.cursor
        for offset=1,#restore_order do
            local index=(cursor+offset-1)%#restore_order+1
            local slot=restore_order[index]
            local choice=saved.pending[slot]
            if choice then
                if support:loadout_busy() then return end
                saved.pending[slot]=nil
                local ready
                if slot==3 or slot==6 then
                    local gear=state.gear[slot]
                    if not gear.id then ready=support:replace_loadout_item(state.view,slot,choice,gear.entity) end
                elseif slot<=2 then
                    local gear,record=state.gear[slot],state.weapons[slot]
                    local reset=record==choice.initial and record~=choice.record
                    local issued=not gear.id or gear.id==choice.old_type or gear.id==choice.item.type
                    if issued and (reset or (record==choice.record and gear.id~=choice.item.type)) then
                        ready=self:apply({slot={index=slot},item=choice.item,expected=gear.entity,old_type=gear.id,
                            owner=state.owner,mission=state.mission,session=state.session,
                            restore_record=choice.record},state)
                    end
                else
                    local i=slot-10
                    if state.strats[i]==choice.previous_kind and not list_has(state.list,choice.item.kind) then
                        ready=self:apply({slot={index=i,strat=true},item=choice.item,expected=choice.previous_kind,
                            owner=state.owner,mission=state.mission,session=state.session,restoring=true},state)
                    end
                end
                if ready~=nil then saved.cursor=index end
                if ready==false then
                    saved.attempts[slot]=(saved.attempts[slot] or 0)+1
                    assert(saved.attempts[slot]<=24,'Reinforcement equipment package timed out')
                    saved.pending[slot]=choice
                    return
                end
                -- Inventory or the mission list may have changed. Re-sample on
                -- the next poll before making another mutation.
                if ready then break end
            end
        end
        if not next(saved.pending) then saved.pending=nil end
    end
    local function weapon_change(job,state,current)
        local slot,target=job.slot.index,job.item
        local old=state.weapons[slot]
        assert(not job.weapon_record or old==job.weapon_record,'Reinforcement loadout changed')
        local new
        if job.restore_record then new=job.restore_record
        elseif job.category then
            assert(current.id==target.type,'Primary changed before attachment edit')
            new=attachments:edit(old,target.id,job.category,job.part_id)
        else new=attachments:factory(target.id) end
        local mods,packages=attachments:spawn_parts(new)
        if #packages>0 and not support:prepare_loadout(state.view,packages) then return false,'Loading attachment packages' end
        local at=state.payload+(slot-1)*0x60
        local function owned()
            return ptr(state.view.base.game+0x2E38188)==state.mission and read(state.mission,24)==state.session
        end
        local committed=false
        local function commit()
            assert(owned() and read(at,#old)==old,'Reinforcement loadout changed before equip')
            if old==new then return end
            local ok,why,copied=mem:write(at,new)
            if not ok then
                if copied and copied>0 and owned() and read(at,#old)==new:sub(1,copied)..old:sub(copied+1) then
                    assert(mem:write(at,old),'Could not restore the previous reinforcement loadout')
                end
                error(why or 'Could not save the reinforcement loadout')
            end
            committed=true
            assert(read(at,#new)==new,'Reinforcement loadout write was not acknowledged')
        end
        local ok,done,why,swap=pcall(support.replace_loadout_item,support,state.view,slot,target,
            current.entity,mods,commit)
        if not ok then
            if committed and owned() and read(at,#new)==new then
                local captured,after=pcall(self.capture,self)
                if captured and after.owner==state.owner and after.gear[slot].entity==current.entity then
                    assert(mem:write(at,old),'Could not restore the previous reinforcement loadout')
                end
            end
            error(done,0)
        end
        if done and not job.restore_record then
            remember(slot,{item=target,record=new,initial=old,old_type=current.id},state)
        end
        if swap and not job.restore_record then job.swap=swap;return false,'Finishing weapon swap' end
        return done,why
    end
    function self:apply(job,state)
        assert(state.owner==job.owner and state.mission==job.mission and state.session==job.session,'Mission or player changed')
        if job.swap then
            assert(not job.swap.error,job.swap.error)
            if job.swap.complete then return true end
            return false,'Finishing weapon swap'
        end
        local slot,target=job.slot,job.item
        if not slot.strat then
            local current=state.gear[slot.index]
            assert(current.entity==job.expected and current.id==job.old_type,'Equipped item changed')
            if slot.index<=2 then return weapon_change(job,state,current) end
            local done,why,swap=support:replace_loadout_item(state.view,slot.index,target,job.expected)
            if done then remember(slot.index,target,state) end
            if swap then job.swap=swap;return false,'Finishing weapon swap' end
            return done,why
        end
        assert(state.strats[slot.index]==job.expected,'Equipped stratagem changed')
        assert(not list_has(state.list,target.kind),'This stratagem is already equipped or mission-issued')
        local game=state.view.base.game
        local address=ptr(game+0x31870E0+target.kind*8)
        local settings=ptr(game+0x2E4A228)
        assert(address>=settings and address+400<=settings+82384,'Stratagem settings unavailable')
        local def=read(address,400)
        assert(word(def,0)==target.kind and word(def,4)==target.id and word(def,0xBC)==1
            and math.floor(def:byte(0x81)/2)%2==1 and def:byte(0xC1)%2==1,'Stratagem definition changed')
        local ready=support:prepare_loadout(state.view,packages(state,def,target.id),target.id)
        if not ready then return false,'Loading stratagem packages' end
        local fresh=self:capture()
        assert(fresh.owner==state.owner and fresh.mission==state.mission and fresh.session==state.session
            and fresh.list==state.list and ptr(game+0x31870E0+target.kind*8)==address and read(address,400)==def,
            'Mission loadout changed before replacement')
        local off=(slot.index+3)*0x30
        local uses=word(def,0x50)
        assert(uses==EMPTY or uses<=255,'Stratagem use limit changed')
        local old=word(fresh.list,off+4)
        if uses~=EMPTY and old~=EMPTY then uses=math.min(uses,old) end
        -- Preserve slot timing, cooldown and mission flags. Keep finite charges
        -- within the replacement's allowance when changing between call types.
        local at=state.payload+0x188+off
        local data=le(target.kind)..le(uses)
        assert(mem:write(at,data))
        assert(read(at,8)==data,'Stratagem replacement was not acknowledged')
        if not job.restoring then
            remember(10+slot.index,{item=target,previous_kind=job.expected},state)
        end
        return true
    end
    return self
end
return M
