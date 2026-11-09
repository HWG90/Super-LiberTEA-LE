-- Build 26251122. Native inventory category permutation and weapon preset
-- initializer (game+EC5160). Only missing weapon roots and presets are added.
local M = {}
local PRESETS, STRIDE, CAPACITY = 0x1181AE4, 148, 512
local CATEGORIES, CATEGORY_COUNT = 0xD1CE4, 24
local function word(s, at)
    local a,b,c,d = s:byte(at+1,at+4)
    return a+b*256+c*65536+d*16777216
end
local function le(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216))
end
local function bytes(hex)
    return (hex:gsub('%x%x',function(pair) return string.char(tonumber(pair,16)) end))
end
local function zeros(n) return string.rep('\0',n) end

local function preset(item, defaults)
    local slots = {}
    for i=0,9 do
        local slot, id = word(defaults,i*8), word(defaults,i*8+4)
        assert(slot<=10,'Weapon customization slot changed')
        if slot>0 and slot<10 then
            assert(id~=0 and not slots[slot],'Weapon customization defaults changed')
            slots[slot]=le(id)
        end
    end
    local ordered={}
    for i=0,9 do ordered[#ordered+1]=slots[i] or le(0) end
    return le(item.id)..le(item.kind==1 and 0 or 1)..le(0)
        ..string.rep(table.concat(ordered),3)..zeros(16)
end

function M.prepare(host, ctx, weapons)
    local mem,C,n = host.mem,host.constants,ctx.count
    local function span(address,size) return assert(host:_span(address,size),'Armory memory unavailable') end
    local function read(offset,size) return span(ctx.account+offset,size) end
    local records=read(C.records,n*C.record_size)
    local indexes=read(C.index,n*C.index_size)
    local groups=read(CATEGORIES,(CATEGORY_COUNT+1)*4)
    local order=read(C.category_index,n*4)
    assert(word(groups,0)==0 and word(groups,96)==n,'Armory category bounds changed')
    local seen,present,kinds={},{},{}
    for i=0,n-1 do
        local r,x=i*C.record_size,i*C.index_size
        assert(word(records,r)==i and records:sub(r+1,r+12)==indexes:sub(x+1,x+12),'Armory row identity changed')
        local id,stable,kind=word(records,r+4),word(records,r+8),word(records,r+12)
        kinds[i]=kind
        present[id]=true
        if kind==1 then present[stable]=true end
    end
    for kind=0,CATEGORY_COUNT-1 do
        local first,last=word(groups,kind*4),word(groups,(kind+1)*4)
        assert(first<=last and last<=n,'Armory category range changed')
        for i=first,last-1 do
            local row=word(order,i*4)
            assert(not seen[row] and kinds[row]==kind,'Armory category permutation changed')
            seen[row]=true
        end
    end
    local missing={}
    for _,item in ipairs(weapons) do
        if not present[item.id] then missing[#missing+1]=item end
    end
    if #missing==0 then return {},missing end
    assert(n+#missing<=C.max_rows,'Armory catalogue is full')

    local catalogue=assert(mem:ptr(ctx.game+C.weapons),'Weapon catalogue unavailable')
    local native=span(catalogue,C.weapon_count*C.weapon_size)
    local world=assert(mem:ptr(ctx.game+0x2CE41B8),'Weapon definitions unavailable')
    local base=assert(mem:ptr(world+0xF147B8),'Weapon customization definitions unavailable')
    assert(span(base-28,28)==bytes('d0f3a8eb4c444c4401000000d0f3a8eba8bd0e000100000000000000'),
        'Weapon customization schema changed')
    local buckets=span(base,0x1880)
    local presets=read(PRESETS,STRIDE*CAPACITY)
    local existing,empty={},{}
    for i=CAPACITY-1,0,-1 do
        local at=i*STRIDE
        local id=word(presets,at)
        if id~=0 then existing[id]=i
        elseif presets:sub(at+1,at+STRIDE)==zeros(STRIDE) then empty[#empty+1]=i end
    end
    local edits,rows,links,inserted={},{},{},{}
    local function edit(offset,before,after)
        assert(#before==#after,'Armory edit length changed')
        if before~=after then edits[#edits+1]={offset=offset,before=before,after=after} end
    end
    for i,item in ipairs(missing) do
        local resource=bytes(item.type):reverse()
        local matches=0
        for at=0,#native-1,C.weapon_size do
            if word(native,at)==item.id then
                assert(native:sub(at+9,at+16)==resource and word(native,at+16)==item.kind,'Hidden weapon identity changed')
                matches=matches+1
            end
        end
        assert(matches==1,'Hidden weapon is missing or ambiguous')
        local index=existing[item.id]
        local prior=index and presets:sub(index*STRIDE+1,(index+1)*STRIDE)
        -- The native initializer writes kind 4 when a gun is used before its
        -- inventory root exists. An empty placeholder can retain mode preferences.
        local placeholder=prior and word(prior,4)==4 and prior:sub(9,132)==zeros(124)
        if not prior or placeholder then
            local definition
            for at=0,#buckets-1,16 do
                if buckets:sub(at+1,at+8)==resource then
                    local index=word(buckets,at+8)
                    assert(not definition and index<197,'Weapon customization index changed')
                    definition=base+0x1880+index*0x1308
                end
            end
            assert(definition,'Weapon attachment defaults unavailable')
            local defaults=preset(item,span(definition,80))
            if placeholder then
                edit(PRESETS+index*STRIDE+4,prior:sub(5,132),defaults:sub(5,132))
            else
                local free=assert(table.remove(empty),'Weapon preset table is full')
                edit(PRESETS+free*STRIDE,zeros(STRIDE),defaults)
            end
        end
        local index=n+i-1
        local identity=le(index)..le(item.id)..le(item.id)
        -- Owned root, quantity one, no prices, children or parent.
        rows[i]=identity..le(1)..le(0)..le(2)..le(0x7fffffff)..zeros(C.record_size-36)..le(1)..le(0)
        links[i]=identity..zeros(C.index_size-12)
        inserted[i]=le(index)
    end
    local function append(offset,data) edit(offset,read(offset,#data),data) end
    append(C.records+n*C.record_size,table.concat(rows))
    append(C.index+n*C.index_size,table.concat(links))
    local first=word(groups,8)*4 -- end of weapon category
    local suffix=order:sub(first+1)
    edit(C.category_index+first,suffix..read(C.category_index+#order,#missing*4),table.concat(inserted)..suffix)
    local ends={}
    for kind=2,CATEGORY_COUNT do ends[#ends+1]=le(word(groups,kind*4)+#missing) end
    edit(CATEGORIES+8,groups:sub(9),table.concat(ends))
    edit(C.account_count,le(n),le(n+#missing)) -- publish last, unpublish first
    return edits,missing
end

function M.new(host, weapons)
    local mem,C=host.mem,host.constants
    local self={wanted=false,elapsed=1,message='Off'}
    local lease,registered_account,registered_count
    local function closed(game)
        local menu=mem:ptr(game+0x2E38160)
        local frame=menu and mem:read(menu+0x4294,32)
        return frame and word(frame,0)==0 and word(frame,28)==0
    end
    local function equipped(ctx,ids)
        local profile=mem:ptr(ctx.game+0x2E38110)
        local mission=mem:ptr(ctx.game+0x2E38188)
        local n=mission and mem:u32(mission+0x2D800)
        if not profile or not n or n>32 then return true end
        local function used(address)
            local id=mem:u32(address)
            return not id or ids[id]
        end
        if used(profile+0x40) or used(profile+0x44) then return true end
        for i=0,n-1 do
            local loadout=mission+i*0x16C0
            if used(loadout+0x38) or used(loadout+0x98) then return true end
        end
        return false
    end
    local function has_tail(ctx)
        if ctx.count~=lease.context.count+#lease.items then return false end
        for i,item in ipairs(lease.items) do
            local at=ctx.account+C.records+(lease.context.count+i-1)*C.record_size
            if mem:u32(at+8)~=item.id then return false end
        end
        return true
    end
    local function roots_gone(owner,n)
        if not n or n==0 or n>C.max_rows or mem:u32(owner+C.account_ready)~=12 then return false end
        local records=host:_span(owner+C.records,n*C.record_size)
        if not records then return false end
        for i=0,n-1 do
            local at=i*C.record_size
            if word(records,at)~=i or lease.ids[word(records,at+4)]
                or (word(records,at+12)==1 and lease.ids[word(records,at+8)]) then return false end
        end
        return true
    end
    local function restore()
        if not lease then return true end
        local ctx=lease.context
        local game=host:_module()
        if game~=ctx.game then return false,'Waiting for original Armory' end
        local owner=mem:ptr(game+C.account)
        if not owner then return false,'Waiting for Armory catalogue' end
        if owner~=ctx.account then lease=nil;return true end
        if lease.uncertain then return false,'Armory write unacknowledged; restart the game' end
        if not closed(game) then return false,'Close the game menu to restore the Armory' end
        local count=mem:u32(owner+C.account_count)
        if lease.published and not has_tail({account=owner,count=count}) then
            -- When the game rebuilds this allocation, its replacement owns the
            -- category permutation and count. Only exact surviving presets are ours.
            if not roots_gone(owner,count) then return false,'Waiting for original Armory rows' end
            for i=#lease.journal,1,-1 do
                if lease.journal[i].offset<PRESETS then table.remove(lease.journal,i) end
            end
            lease.published=false
        end
        if lease.published and equipped(ctx,lease.ids) then return false,'Equip a different weapon to restore the Armory' end
        for i=#lease.journal,1,-1 do
            local edit=lease.journal[i]
            local current=mem:read(ctx.account+edit.offset,#edit.after)
            if edit.offset>=PRESETS and current and current~=edit.after and lease.committed then
                table.remove(lease.journal,i)
            elseif current~=edit.after then
                return false,'Armory changed; retaining the registered rows'
            end
        end
        -- A short restore can already have unpublished the count. Keep the
        -- remaining journal until each acknowledged prefix has been restored.
        lease.published=false
        for i=#lease.journal,1,-1 do
            local e=lease.journal[i]
            local called,ok,why,count=pcall(mem.copy,mem,ctx.account+e.offset,e.before)
            if not called then lease.uncertain=true;return false,tostring(ok) end
            if not ok or count~=#e.before then
                if count then e.after=e.before:sub(1,count)..e.after:sub(count+1) else lease.uncertain=true end
                return false,why
            end
            lease.journal[i]=nil
        end
        lease=nil
        return true
    end
    local function apply(ctx,edits,items)
        local after=host:context()
        if not host:same_context(ctx,after) or not closed(ctx.game)
            or mem:u32(ctx.account+C.account_ready)~=12 then return false,'Armory changed while preparing' end
        for _,e in ipairs(edits) do
            if host:_span(ctx.account+e.offset,#e.before)~=e.before then return false,'Armory changed before registration' end
        end
        lease={context=ctx,journal={},ids={},items=items}
        for _,item in ipairs(items) do lease.ids[item.id]=true end
        for _,e in ipairs(edits) do
            for pos=1,#e.after,4096 do
                local after=e.after:sub(pos,pos+4095)
                local at=e.offset+pos-1
                local called,ok,why,count=pcall(mem.copy,mem,ctx.account+at,after)
                if not called or not count then lease.uncertain=true
                elseif count>0 then
                    lease.journal[#lease.journal+1]={offset=at,before=e.before:sub(pos,pos+count-1),after=after:sub(1,count)}
                end
                if not called or not ok or count~=#after then
                    local restored,problem=restore()
                    return false,restored and (why or 'Armory write failed') or problem
                end
            end
        end
        lease.published,lease.committed=true,true
        return true
    end
    function self:set_enabled(value)
        if self.wanted~=value then self.wanted=value;self.elapsed=1 end
        return true
    end
    function self:is_clean() return not lease end
    function self:status() return 'Hidden weapons: '..self.message end
    local function refresh()
        if not self.wanted or (lease and not lease.published) then
            registered_account,registered_count=nil,nil
            local ok,why=restore()
            return ok and 'Off' or why
        end
        local ctx=host:context()
        if not ctx then return 'Waiting for local host' end
        if lease and ctx.account~=lease.context.account then lease=nil end
        if ctx.account==registered_account and ctx.count==registered_count then
            if not lease or has_tail(ctx) then return 'Registered' end
        end
        if mem:u32(ctx.account+C.account_ready)~=12 then return 'Waiting for Armory catalogue' end
        local state=mem:ptr(ctx.game+0x2CE1508)
        if not state or mem:u32(state+0xAC29C)~=3 then return 'Waiting for ship' end
        if not closed(ctx.game) then return 'Close the game menu to register weapons' end
        if lease then
            local done,why=restore()
            if not done then return why end
        end
        local edits,items=M.prepare(host,ctx,weapons)
        if #edits>0 then
            local ok,why=apply(ctx,edits,items)
            if not ok then return why end
        end
        registered_account,registered_count=ctx.account,ctx.count+#items
        return 'Registered'
    end
    function self:update(dt)
        if not self.wanted and not lease then self.message='Off';registered_account=nil;return end
        self.elapsed=self.elapsed+math.max(0,math.min(1,tonumber(dt) or 0))
        if self.elapsed<1 then return end
        self.elapsed=0
        local ok,message=pcall(refresh)
        self.message=ok and message or tostring(message):gsub('^.-:%d+: ','')
    end
    function self:shutdown()
        self.wanted=false
        return restore()
    end
    return self
end
return M
