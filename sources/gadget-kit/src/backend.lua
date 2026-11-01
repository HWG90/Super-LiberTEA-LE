-- Build-specific local catalogue access. No engine calls, requests or save API.
-- Provenance: game.dll 6AD7C05D, current runtime catalogue and selector fingerprints;
-- Fingerprints bind the current selectors, slot classifications and account owner.
-- World identity comes from the engine main_world API; no old world pointer is used.
local Memory = mod.require('src/memory.lua')
local M = {}
local C = {
    stamp=0x6AE0E5FF, max_rows=4096, record_size=0xB8, index_size=24,
    account=0x2E38230, account_count=0x1CE0, records=0x1CE4, index=0xB9CE4,
    account_ready=0xDDCF8,
    player=0x2CE1618, network=0x2E38228, roster=0x2E38210,
    local_peer=0xB398, host_peer=0xB3A8, roster_stride=0xC0, roster_count=8,
    weapons=0x2CE1BA0, weapon_count=199, weapon_size=32,
    weapon_starts=0x1BFC, weapon_counts=0x1C18,
    kits=0x2CE16A8, kit_count=8, kit_type=0x28, kit_read=44,
    stratagem_table=0x31870E0, stratagem_count=154,
    stratagem_buffer=0x2E4A228, stratagem_span=81920,
    stratagem_first=0xD1D0C, stratagem_last=0xD1D10, category_index=0xD1D48,
    state=0x14, amount=0xB0, max_amount=0x18,
}
local FPS = {
    {0x1609FA2,'8b420c4c896c24784c8d2d4f609ffe418b848520c606028941108b420c894120'},
    {0x10794A0,'48895c2408488b1df486c60141bb010000004c8d8b001c00000f1f8000000000458b41'},
    {0x1205FE0,'48895c2408488bd985d275094c8d15550ff801eb0d8bc24c8d15e210f8014d8b14c2'},
    {0x1206066,'418b00488b15c021c3014869c8b8000000488d82e41c00004803c1'},
    {0x175E8AB,'837928017514448bc08bd3498bc9e8824812ff4c8b0de32d5801'},
    {0x175E8F9,'837928027514448bc08bd3498bc9e8244a12ff4c8b0d952d5801'},
    {0x175E93D,'3971287514448bc08bd3498bc9e8d14b12ff4c8b0d522d5801'},
    {0x522B6F,'488b0db2569102488b9198b30000'},
    {0x1083907,'48891d1a69dc014883c304'},
}
for _, p in ipairs(FPS) do
    p.bytes=p[2]:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
end
local ZERO=string.rep('\0',8)
local KIT_CATEGORY={[0]='bodyarmor',[1]='helmets',[2]='capes'}
local RESERVED_STRATAGEM={[0x33BABE96]=true,[0xE4B4F558]=true,[0x84DF23BE]=true}
local function u32(s,o)return Memory.u32_bytes(s,o or 0)end
local function ptr(s,o)return Memory.pointer_bytes(s,o or 0)end
local function le32(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
local function integer(v,max)return type(v)=='number' and v==math.floor(v) and v>=0 and v<=max end

function M.new(log, injected)
    local mem=injected and type(injected._module)=='function' and injected or Memory.new(injected)
    return setmetatable({mem=mem,log=log or function()end},{__index=M})
end

function M:_module()
    local game,why=self.mem:_module()
    if not game then self._validated_game=nil;return nil,why end
    if why~=nil and why~=C.stamp then self._validated_game=nil;return nil,'Unsupported game.dll build' end
    local image_size=self.mem._image_size
    if not integer(image_size,0x80000000) or image_size<C.stratagem_table+C.stratagem_count*8 then
        self._validated_game=nil;return nil,'game.dll image does not contain the required catalogue tables'
    end
    if self._validated_game==game and self._validated_size==image_size and self._validated_stamp==why then
        return game
    end
    for _,p in ipairs(FPS) do
        if self.mem:read(game+p[1],#p.bytes)~=p.bytes then
            return nil,string.format('Catalogue fingerprint mismatch at game+%X',p[1])
        end
    end
    self._validated_game,self._validated_size,self._validated_stamp=game,image_size,why
    return game
end

function M:_span(address,size)
    local parts={}
    for offset=0,size-1,8192 do
        local raw,why=self.mem:read(address+offset,math.min(8192,size-offset))
        if not raw then return nil,why or 'Catalogue memory is unreadable' end
        parts[#parts+1]=raw
    end
    return table.concat(parts)
end

function M:context()
    local game,why=self:_module()
    if not game then return nil,why end
    local mem=self.mem
    local account=mem:ptr(game+C.account)
    local count=account and mem:u32(account+C.account_count)
    if not account or not integer(count,C.max_rows) or count==0 then return nil,'Waiting for account catalogue' end
    local sr=rawget(_G,'stingray')
    local application=sr and sr.Application
    local ok,world=pcall(function()return application and application.main_world()end)
    local player=mem:ptr(game+C.player)
    if not ok then return nil,'Main world is unavailable' end
    if not world or not player then return nil,'Waiting for an active player' end
    local network,roster=mem:ptr(game+C.network),mem:ptr(game+C.roster)
    if not network or not roster then return nil,'Waiting for session ownership' end
    local mine,host=mem:read(network+C.local_peer,8),mem:read(network+C.host_peer,8)
    if not mine or not host then return nil,'Session ownership is unreadable' end
    if mine==ZERO or host~=mine then return nil,'The local player must host this session' end
    local local_present=false
    if mem.roster_has and mem:_fast_reads() then
        local problem
        local_present,problem=mem:roster_has(roster,network+C.local_peer)
        if local_present==nil then return nil,problem end
    else
        local list=mem:read(roster,C.roster_stride*C.roster_count)
        if not list then return nil,'Session roster is unreadable' end
        for i=0,C.roster_count-1 do
            if list:sub(i*C.roster_stride+1,i*C.roster_stride+8)==mine then local_present=true end
        end
    end
    -- Debug build: other roster members do not block local holds.
    if not local_present then return nil,'Waiting for the local player in the roster' end
    return {game=game,account=account,count=count,world=world,player=player,
        network=network,roster=roster,local_peer=mine,host_peer=host}
end

function M.same_context(a,b,c)
    -- Accept both backend:same_context(a,b) and Backend.same_context(a,b).
    if c~=nil then a,b=b,c end
    if type(a)~='table' or type(b)~='table' then return false end
    for _,key in ipairs({'game','account','count','world','player','network','roster','local_peer','host_peer'}) do
        if a[key]~=b[key] then return false end
    end
    return true
end

function M:_weapons(game)
    local address=self.mem:ptr(game+C.weapons)
    if not address then return nil,'Weapon catalogue is unavailable' end
    local raw=self:_span(address,C.weapon_count*C.weapon_size)
    local ranges=self.mem:read(address+C.weapon_starts,56)
    if not raw or not ranges then return nil,'Weapon catalogue is unreadable' end
    local found,last={},0
    for i=0,C.weapon_count-1 do
        local at=i*C.weapon_size
        local id,kind=u32(raw,at),u32(raw,at+16)
        -- Native backpack metadata includes resident-only entries with ID zero
        -- (observed at rows 158/165/190..192). They never enter the weapon set.
        if not id or not kind or kind<1 or kind>6 or kind<last or (id==0 and kind~=6)
            or u32(raw,at+4)~=0 or raw:sub(at+9,at+16)==ZERO
            or raw:sub(at+25,at+32)~=ZERO then return nil,'Weapon catalogue layout changed' end
        last=kind
        if kind<=4 then found[id]=true end
    end
    for kind=0,6 do
        local first,count=u32(ranges,kind*4),u32(ranges,28+kind*4)
        if not first or not count or first+count>C.weapon_count then return nil,'Weapon catalogue range changed' end
        for i=first,first+count-1 do
            if u32(raw,i*C.weapon_size+16)~=kind then return nil,'Weapon catalogue kind range changed' end
        end
    end
    return found
end

function M:_kits(game)
    local manager=self.mem:ptr(game+C.kits)
    local count=manager and self.mem:u32(manager+C.kit_count)
    local array=manager and self.mem:ptr(manager)
    if not array or not integer(count,C.max_rows) or count==0 then return nil,'Armor kit catalogue is unavailable' end
    local pointers=self:_span(array,count*8)
    if not pointers then return nil,'Armor kit catalogue is unreadable' end
    local found={}
    for i=0,count-1 do
        local address=ptr(pointers,i*8)
        local raw=address and self.mem:read(address,C.kit_read)
        local id,kind=raw and u32(raw),raw and u32(raw,C.kit_type)
        if not id or id==0 or not KIT_CATEGORY[kind] then return nil,'Armor kit identity or slot is unavailable' end
        if found[id] and found[id]~=KIT_CATEGORY[kind] then return nil,'Armor kit identity is ambiguous' end
        found[id]=KIT_CATEGORY[kind]
    end
    return found
end

function M:_stratagems(game)
    local buffer=self.mem:ptr(game+C.stratagem_buffer)
    if not buffer then return nil,'Stratagem settings allocation is unavailable' end
    local pointers=self:_span(game+C.stratagem_table,C.stratagem_count*8)
    if not pointers then return nil,'Stratagem catalogue is unreadable' end
    local found={}
    for i=1,C.stratagem_count-1 do
        local pointer_bytes=pointers:sub(i*8+1,i*8+8)
        if pointer_bytes~=ZERO then
            local address=ptr(pointer_bytes)
            if not address or address<buffer or address+0xC1>buffer+C.stratagem_span then
                return nil,'Stratagem definition is outside its settings allocation'
            end
            local raw=address and self.mem:read(address,0xC1)
            if not raw then return nil,'Stratagem definition is unreadable' end
            local id=u32(raw,4)
            if u32(raw)~=i then return nil,'Stratagem definition type changed' end
            if id and id~=0 and not RESERVED_STRATAGEM[id]
                and math.floor(raw:byte(0x81)/2)%2==1 and raw:byte(0xC1)%2==1 then
                found[id]=true
            end
        end
    end
    return found
end

function M:capture()
    local ctx,why=self:context()
    if not ctx then return nil,why end
    local weapons,kits,stratagems
    weapons,why=self:_weapons(ctx.game);if not weapons then return nil,why end
    kits,why=self:_kits(ctx.game);if not kits then return nil,why end
    stratagems,why=self:_stratagems(ctx.game);if not stratagems then return nil,why end
    local definitions=self:_span(ctx.account+C.records,ctx.count*C.record_size)
    local indexes=self:_span(ctx.account+C.index,ctx.count*C.index_size)
    if not definitions or not indexes then return nil,'Account catalogue is unreadable' end
    local all,seen={},{}
    for i=0,ctx.count-1 do
        local ix=i*C.index_size
        local rec,id=u32(indexes,ix),u32(indexes,ix+4)
        if not rec or rec>=ctx.count or seen[rec] then return nil,'Account catalogue index is invalid' end
        seen[rec]=true
        local at=rec*C.record_size
        if u32(definitions,at)~=rec or u32(definitions,at+4)~=id
            or u32(definitions,at+8)~=u32(indexes,ix+8) then return nil,'Account catalogue identity mismatch' end
        all[i+1]={address=ctx.account+C.records+at,index_address=ctx.account+C.index+ix,
            identity=definitions:sub(at+1,at+20)..indexes:sub(ix+1,ix+12),
            stable=u32(definitions,at+8),kind=u32(definitions,at+12),back=u32(indexes,ix+16),
            state=u32(definitions,at+C.state),amount=u32(definitions,at+C.amount),
            max_amount=u32(definitions,at+C.max_amount),index=i}
    end
    local range=self.mem:read(ctx.account+C.stratagem_first,8)
    local first,last=range and u32(range),range and u32(range,4)
    if not first or not last or first>last or last>ctx.count then return nil,'Stratagem account range is invalid' end
    local ordering=self:_span(ctx.account+C.category_index+first*4,(last-first)*4)
    if not ordering then return nil,'Stratagem account range is unreadable' end
    local strat_order={}
    for position=0,last-first-1 do
        local i=u32(ordering,position*4)
        if not i or i>=ctx.count then return nil,'Stratagem account index is invalid' end
        local r=all[i+1]
        if r.kind~=10 then return nil,'Stratagem account range contains another category' end
        if strat_order[r.stable]==nil then strat_order[r.stable]=i end
    end
    local selected,order={},{}
    for _,r in ipairs(all) do
        local category
        if r.kind==1 and weapons[r.stable] then category='weapons'
        elseif r.kind==3 then
            category=kits[r.stable]
            if not category then return nil,'A catalogue armor kit has no verified slot' end
        elseif r.kind==10 and stratagems[r.stable] and strat_order[r.stable]==r.index then category='stratagems' end
        if category then
            r.category=category
            local key=category..':'..r.stable
            local previous=selected[key]
            local owned=r.state==2 or r.state==4
            if not previous then selected[key]=r;order[#order+1]=key
            elseif owned and previous.state~=2 and previous.state~=4 then selected[key]=r end
        end
    end
    local snapshot={context=ctx,records={},by_address={}}
    local function add(r,category,parent)
        if snapshot.by_address[r.address] then return true end
        if not integer(r.state,4) or not integer(r.amount,0xFFFFFFFF)
            or not integer(r.max_amount,0xFFFFFFFF) or r.amount>r.max_amount then return nil,'Catalogue quantity or state is invalid' end
        r.category=category
        -- A permit is a state-only ancestor lease, including a nonzero amount.
        if parent then r.max_amount=r.amount end
        snapshot.records[#snapshot.records+1]=r;snapshot.by_address[r.address]=r
        return true
    end
    for _,key in ipairs(order) do
        local child=selected[key]
        local ok,err=add(child,child.category,false);if not ok then return nil,err end
        local current,depth=child,0
        while current.back>0 do
            depth=depth+1
            if depth>16 then return nil,'Catalogue parent chain exceeds the supported depth' end
            if current.back>current.index then return nil,'Catalogue parent chain is invalid' end
            current=all[current.index-current.back+1]
            if current.kind==11 and current.state==1 then
                ok,err=add(current,child.category,true);if not ok then return nil,err end
            end
        end
    end
    local after=self:context()
    if not M.same_context(ctx,after) then return nil,'Session changed during catalogue capture' end
    return snapshot
end

function M:_matches(snapshot,row)
    local original=type(row)=='table' and snapshot.by_address[row.address]
    if not original or row.identity~=original.identity then return false end
    local game,why=self:_module();if not game then return nil,why end
    if game~=snapshot.context.game then return false end
    -- Restoration deliberately has no session/solo requirement. Only the exact
    -- retained account owner and record identity may receive its original bytes.
    local owner=self.mem:read(game+C.account,8)
    if not owner then return nil,'Account owner is unreadable' end
    if owner==ZERO then return nil,'Account owner is temporarily unavailable' end
    local account=ptr(owner)
    if not account then return nil,'Account owner is invalid' end
    if account~=snapshot.context.account then return false end
    local count=self.mem:u32(account+C.account_count)
    if count==nil then return nil,'Account count is unreadable' end
    if not integer(count,C.max_rows) then return nil,'Account count is invalid' end
    if original.index>=count or u32(row.identity)>=count then return false end
    local prefix=self.mem:read(row.address,20)
    local index=self.mem:read(original.index_address,12)
    if not prefix or not index then return nil,'Record identity is unreadable' end
    return prefix..index==row.identity
end

function M:adapter(snapshot)
    assert(type(snapshot)=='table' and snapshot.context and snapshot.by_address,'Invalid catalogue snapshot')
    local backend=self
    local io={}
    function io.matches(row)return backend:_matches(snapshot,row)end
    function io.read(row,field)
        local offset=field=='state' and C.state or field=='amount' and C.amount
        if not offset or io.matches(row)~=true then return nil end
        return backend.mem:u32(row.address+offset)
    end
    function io.write(row,field,value)
        local offset=field=='state' and C.state or field=='amount' and C.amount
        if not offset or not integer(value,2) or (field=='state' and value<1)
            or (field=='amount' and value>1) then return false,'Unsupported catalogue write' end
        if io.matches(row)~=true then return false,'Catalogue identity changed' end
        local current=backend.mem:u32(row.address+offset)
        if current==nil then return false,'Catalogue field is unreadable' end
        if field=='state' and current~=1 and current~=2 then return false,'Catalogue state is foreign' end
        if field=='amount' and current~=0 and current~=1 then return false,'Catalogue amount is foreign' end
        if (field=='state' and value==2) or (field=='amount' and value==1) then
            local ctx=backend:context()
            if not M.same_context(ctx,snapshot.context) then return false,'Hosted session changed' end
        end
        if io.matches(row)~=true then return false,'Catalogue identity changed before copy' end
        return backend.mem:copy(row.address+offset,le32(value))
    end
    return io
end

function M:inspect(snapshot)
    local ctx,why=self:context()
    if not ctx then return nil,why end
    if not M.same_context(ctx,snapshot.context) then return false,'Session changed' end
    for _,row in ipairs(snapshot.records) do
        local same,err=self:_matches(snapshot,row)
        if same~=true then return same,err or 'Catalogue identity changed' end
    end
    return true
end

M.constants=C
M.fingerprints=FPS
-- Independently validated witnesses per feature. Packed/lazy code for an
-- unrelated manager must not disable every gameplay control.
local GAMEPLAY_GROUPS={
    state={{0x3A1179,'488b0d8803940248bafd138a1d7b3bc55f4881c1d8fa0100'},{0x3A1AB3,'488b0d4efa930248bafd138a1d7b3bc55f4881c1d8fa0100'},{0x3AB394,'488b0d6d619302ba2b0000004881c1609ebb044883c4205b'}},
    mode={{0x386E3B,'488b050eaa9502488bd9837808000f84900000008b4040ff'},{0x38701C,'488b052da895028378080074268b4040ffc883f806771c48'},{0x38723D,'488b050ca69502837808000f84830000008b4040ffc883f8'}},
    director={{0x308A0A,'488b0dbf949d0283b9800600000076574881c1d436050033'},{0x308BEB,'488b0dde929d0283b9800600000076514881c1d436050033'},{0x379E8B,'488b053e809602488bd983b88006000000740980b84c3705'}},
    world={{0xBC783,'488b0d2e7ac2028b50084883c4205be91901db0033d2c34c'},{0xBC835,'488b0d7c79c2028b5008e86c00db00eb28488bcfe8d20b41'},{0xD0EBB,'488b0df632c1028b5008e9e6b9d900c34883ec20c381f97f'}},
    health={{0x391DF5,'488b0d3cfa94024533c04889b42488000000448b89381000'},{0x4AACBA,'4c8b15776b83027507b8ffffffffeb7e458b8a3810000045'},{0x4B5F25,'488b0d0cb98202448b89381000008b99401000000fafd841'}},
    inventory={{0x3B0B00,'4c8b05e10d930233db8bcb458b4830458b5038440fafd241'},{0x3B3B69,'4c8b0d78dd920248896c24304889742440458b4130458b59'},{0x429EAC,'488b0d357a8b0241b903000000f30f59e8f3410f116d0849'}},
    magazine={{0x3ADC09,'488b05e83b9302488b4850393c91400f9fc6b902000000e8'},{0x3ADC30,'488b05c13b9302488b4850833c9100400f9fc70f28c70f57'},{0x3B0B85,'488b056c0c9302488b4850833c9100400f9fc6b901000000'}},
}
for _,group in pairs(GAMEPLAY_GROUPS)do for _,pin in ipairs(group)do
    pin.bytes=pin[2]:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
end end
local REQUIRED={freeze_timer={'state','mode','director'},freeze_health={'world','health'},
    freeze_ammo={'world','inventory','magazine'},no_reload={'world','inventory','magazine'}}
function M:validate_gameplay(feature,c)
    self._gameplay_checks=self._gameplay_checks or {}
    for _,name in ipairs(REQUIRED[feature]or {})do
        if self._gameplay_checks[name]~=c.game then
            local matched=false
            for _,pin in ipairs(GAMEPLAY_GROUPS[name])do
                if self.mem:read(c.game+pin[1],#pin.bytes)==pin.bytes then matched=true;break end
            end
            if not matched then return false,'Gameplay '..name..' fingerprint mismatch' end
            self._gameplay_checks[name]=c.game
        end
    end
    return true
end
function M:gameplay_context()
    local c,why=self:context()
    if not c then return nil,why end
    c.world=self.mem:ptr(c.game+0x2CE41B8)
    if not c.world then return nil,'Gameplay world is unavailable' end
    return c
end
function M:passive_ai_context() return self:gameplay_context() end
return M
