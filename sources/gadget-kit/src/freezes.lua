-- Session-only holds. Disabling releases the hold at its last value: never
-- rewind a running timer or restore old ammo into a recycled component row.
-- Ammo layout: LinksLinkToMemory hd2_addresses/demo_ammo (6AD7C05D).
-- Health layout independently read back on 6AD7C05D; descriptors are pointers,
-- current/max health are u32. Notify the engine only when restoring health.
local M = {}
M.names = {'freeze_health', 'freeze_timer', 'freeze_ammo', 'no_reload'}
local function finite(v, maximum)
    return type(v)=='number' and v==v and v>=0 and v<=maximum
end
function M.new(backend)
    local self = {preferences={}, holds={}, messages={}}
    for _,name in ipairs(M.names) do self.preferences[name]=false end
    local passive,extraction
    local function extraction_state()
        if not extraction then extraction=mod.require('src/extraction.lua').new(backend)end
        return extraction
    end
    local function passive_state()
        if not passive then passive=mod.require('src/passive_ai.lua').new(backend) end
        return passive
    end
    self.preferences.instant_extract=false
    self.preferences.passive_ai=false
    local context
    function self:clear() self.holds={}; context=nil end
    function self:set(values)
        for _,name in ipairs(M.names) do
            if type(values[name])~='boolean' then return false,'Invalid freeze preference: '..name end
        end
        for _,name in ipairs(M.names) do
            if self.preferences[name]~=values[name] then self.holds[name]=nil; self.messages[name]=nil end
            self.preferences[name]=values[name]
        end
        self.preferences.instant_extract=values.instant_extract==true
        if not self.preferences.instant_extract and extraction then extraction:stop()end
        self.preferences.passive_ai=values.passive_ai==true
        if not self.preferences.passive_ai and passive then passive:release() end
        return true
    end
    function self:stop()
        for _,name in ipairs(M.names) do self.preferences[name]=false end
        self.preferences.instant_extract=false;if extraction then extraction:stop()end
        self.preferences.passive_ai=false; if passive then passive:release() end
        self:clear(); self.messages={}
    end
    local function mission(c)
        local mem=backend.mem
        local state=mem:ptr(c.game+0x2CE1508)
        local mode=mem:ptr(c.game+0x2CE1850)
        if not state or not mode or mem:u32(state+0xAC29C)~=4 or mem:u32(mode+8)~=1 then
            return nil,'Waiting for a mission'
        end
        return state
    end
    local function held_bytes(name, identity, address, bytes)
        local hold=self.holds[name]
        if not hold or hold.identity~=identity or hold.address~=address then
            self.holds[name]={identity=identity,address=address,bytes=bytes}
            return true
        end
        if bytes~=hold.bytes then
            local ok,why=backend.mem:copy(address,hold.bytes)
            if not ok then self.holds[name]=nil; return false,why or 'Hold write failed' end
        end
        return true
    end
    local function timer(c,state)
        local mem=backend.mem
        local director=mem:ptr(c.game+0x2CE1ED0)
        if director~=state+0x8556A8 or mem:u32(director+0x684)~=1
            or mem:u8(director+0x5374C)~=0 then return false,'Waiting for an active mission timer' end
        local bytes=mem:read(director+0x53748,4)
        if not bytes then return false,'Timer is unreadable' end
        local ffi=mem._ffi
        local value=ffi.new('float[1]'); ffi.copy(value,bytes,4)
        if not finite(tonumber(value[0]),86400) or value[0]<=0 then return false,'Timer is expired or invalid' end
        return held_bytes('freeze_timer',tostring(state),director+0x53748,bytes)
    end
    local function avatar(c)
        local mem=backend.mem
        local unit=mem:u32(c.player+0x3A8)
        local index=unit and mem:hashmap(c.world+0xF24990,unit)
        if not index then return nil end
        local row=c.world+0xF349E0+index*24
        local entity=mem:u32(row+8)
        if not entity or entity==0xFFFFFFFF then return nil end
        return entity,unit
    end
    local ROUND_PINS={
        {0x762E4F,'4c8b255af05702'}, -- per-round manager global
        {0x763076,'498b4c24584b8d14b6eb7c'}, -- records +58, index *20
    }
    for _,pin in ipairs(ROUND_PINS) do pin.bytes=pin[2]:gsub('%x%x',function(v)return string.char(tonumber(v,16))end) end
    -- Match only a support weapon's own ammunition pack. Supply packs, drones
    -- and unrelated backpacks must never become weapon reserves.
    local function raw_type(hex)
        local bytes=hex:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
        return bytes:reverse()
    end
    local PACK_TYPES={}
    for _,pair in ipairs({
        {'a8cffb316f0b5c5f','e60ae045e0090f4c'}, -- Autocannon
        {'9f80d67a12a7e40f','96dfc6542aa22980'}, -- Recoilless Rifle
        {'25aa2fd4643cf4ee','8ec3026b5f2e579a'}, -- Spear
        {'26e40437ea275296','e75cd68e858a12ac'}, -- Airburst
        {'cc786f6491fe7e65','b8feb0cc191c1ef3'}, -- W.A.S.P.
        {'88c2d09ad85a7c9f','bb4b15b588f974fd'}, -- Belt-Fed Grenade Launcher
        {'43a58cb89cfa197c','056de1c5e21e723e'}, -- Maxigun
        {'78a8185f63a70795','43eb1c3c1a1860e0'}, -- Cremator variants
        {'0736bee2d6328726','43eb1c3c1a1860e0'},
    }) do PACK_TYPES[raw_type(pair[1])]=raw_type(pair[2]) end
    local function entity_type(mem,world,entity)
        local index=mem:hashmap(world+0xF1C978,entity)
        local record=index and world+0xF349E0+index*24
        if not record or mem:u32(record+8)~=entity then return nil end
        return mem:read(record,8)
    end
    local function backpack_reserves(c,inventory,entity,unit,weapon,backpack)
        if not backpack or backpack==0 or backpack==0xFFFFFFFF then return end
        local mem=backend.mem
        local kind=entity_type(mem,c.world,weapon)
        if not kind then return nil,nil,'Support weapon identity is unavailable' end
        local required=PACK_TYPES[kind]
        if not required then return end
        if entity_type(mem,c.world,backpack)~=required then return end
        local manager=mem:ptr(c.game+0x2CE1798)
        local index=manager and mem:hashmap(manager+0x20,backpack)
        local descriptors=index and mem:ptr(manager+0x38)
        local descriptor=descriptors and mem:ptr(descriptors+index*8)
        local records=index and mem:ptr(manager+0x50)
        if not descriptor or not records or mem:u32(descriptor+8)~=backpack then
            return nil,nil,'Waiting for owned ammunition backpack'
        end
        local address=records+index*8
        if not finite(mem:u32(address),10000) then return nil,nil,'Backpack reserves are invalid' end
        return address,table.concat({entity,unit,weapon,inventory,backpack,manager,descriptor},':')
    end
    local function ammo(c,_,name)
        local mem=backend.mem
        local entity,unit=avatar(c)
        local inventory=mem:ptr(c.game+0x2CE18E8)
        local index=entity and inventory and mem:hashmap(inventory+40,entity)
        local rows=index and mem:ptr(inventory+80)
        if not rows then return false,'Waiting for player inventory' end
        local row=mem:read(rows+index*48,48)
        if not row then return false,'Inventory is unreadable' end
        local function u32(offset)
            local a,b,d,e=row:byte(offset+1,offset+4)
            return a+b*256+d*65536+e*16777216
        end
        local slot=u32(28)
        local weapon=slot>=1 and slot<=3 and u32((slot-1)*4) or nil
        if slot==3 and name=='freeze_ammo' then
            local pack_address,pack_identity,why=backpack_reserves(c,inventory,entity,unit,weapon,u32(12))
            if why then return false,why end
            if pack_address then
                local bytes=mem:read(pack_address,4)
                if not bytes then return false,'Backpack reserves are unreadable' end
                return held_bytes(name,pack_identity,pack_address,bytes)
            end
        end
        local manager=weapon and mem:ptr(c.game+0x2CE17F8)
        local mi=manager and mem:hashmap(manager+0x20,weapon)
        local records=mi and mem:ptr(manager+0x50)
        local address=records and records+mi*12
        local rounds_offset=4
        local component='magazine'
        local descriptor
        if not mi then
            -- Individual-round reloads use a separate component, not magazines.
            -- Verified on 6AD7C05D: reserve u32 +0, loaded u32 +8, stride 20.
            for _,pin in ipairs(ROUND_PINS) do
                if mem:read(c.game+pin[1],#pin.bytes)~=pin.bytes then
                    return false,'Per-round ammo fingerprint mismatch'
                end
            end
            manager=weapon and mem:ptr(c.game+0x2CE1EB0)
            mi=manager and mem:hashmap(manager+0x28,weapon)
            records=mi and mem:ptr(manager+0x58)
            local descriptors=mi and mem:ptr(manager+0x40)
            descriptor=descriptors and mem:ptr(descriptors+mi*8)
            if not descriptor or mem:u32(descriptor+8)~=weapon then
                return false,'Waiting for a valid ammo component'
            end
            address=records and records+mi*20
            rounds_offset=8; component='per-round'
        end
        if not address then return false,'Ammo records are unavailable' end
        local reserves,rounds=mem:u32(address),mem:u32(address+rounds_offset)
        if not finite(reserves,10000) or not finite(rounds,10000) then return false,'Ammo counters are invalid' end
        local offset=name=='no_reload' and rounds_offset or 0
        local identity=table.concat({entity,unit,weapon,manager,inventory,component,descriptor or 0},':')
        local hold=self.holds[name]
        if name=='no_reload' and rounds==0
            and (not hold or hold.identity~=identity or hold.address~=address+offset) then
            return false,'Reload once to start holding rounds'
        end
        local bytes=mem:read(address+offset,4)
        if not bytes then return false,'Ammo counter is unreadable' end
        return held_bytes(name,identity,address+offset,bytes)
    end
    local HEALTH_PIN=('488bc4488958104889701848897820554154415541564157488d68a14881ecf00000000f2970c8'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
    local function health(c)
        local mem=backend.mem
        if mem:read(c.game+9631376,#HEALTH_PIN)~=HEALTH_PIN then return false,'Health layout fingerprint mismatch' end
        local entity,unit=avatar(c)
        local manager=entity and mem:ptr(c.game+0x2CE1838)
        local capacity=manager and mem:u32(manager+0x1010)
        local live=manager and mem:u32(manager+0x1020)
        local index=manager and mem:hashmap(manager+0x1030,entity)
        if not capacity or capacity>4096 or not live or live>capacity or not index or index>=live then
            return false,'Waiting for player health'
        end
        local descriptors=mem:ptr(manager+0x1048)
        local descriptor=descriptors and mem:ptr(descriptors+index*8)
        local records=mem:ptr(manager+0x1058)
        local extended=mem:ptr(manager+0x1060)
        if not descriptor or not records or not extended
            or mem:u32(descriptor+8)~=entity or mem:u32(descriptor+16)~=unit then
            return false,'Health owner changed'
        end
        local record=records+index*440
        local life=mem:u32(record+412)
        local value=mem:u32(record+20)
        local maximum=mem:u32(extended+index*28+20)
        if life~=0 or not finite(value,100000) or value<=0 or not finite(maximum,100000)
            or maximum<=0 or maximum<value then return false,'Waiting for a living local player' end
        local bytes=mem:read(record+20,4)
        if not bytes then return false,'Health is unreadable' end
        local goid=mem:u32(descriptor+16)
        if not goid then return false,'Health identity is unreadable' end
        local identity=table.concat({entity,unit,manager,descriptor,mem:u32(descriptor+12) or -1,goid,maximum},':')
        local hold=self.holds.freeze_health
        local refresh=not hold or hold.identity~=identity or hold.address~=record+20 or hold.bytes~=bytes
        local ok,why=held_bytes('freeze_health',identity,record+20,bytes)
        if not ok then return false,why end
        -- Raw counter writes leave the HUD's event-driven health value stale.
        -- A zero-amount heal publishes current health without adding health or
        -- repairing limbs. Acquisition also reconciles an already-stale HUD.
        if refresh then return mem:refresh_health(c.game,manager,entity) end
        return true
    end
    local actions={freeze_health=health,freeze_timer=timer,freeze_ammo=ammo,no_reload=ammo}
    local function update(dt)
        if self.preferences.instant_extract then
            extraction_state():update(dt)
            self.messages.instant_extract=extraction:status()
        end
        if self.preferences.passive_ai then
            local c,why=backend:passive_ai_context()
            if c then
                local ok,problem=passive_state():update(c,true)
                self.messages.passive_ai=ok and 'On' or tostring(problem)
            else if passive then passive.lease=nil end;self.messages.passive_ai=why end
        elseif passive and passive.lease then passive:release() end
        local active=false
        for _,name in ipairs(M.names) do active=active or self.preferences[name] end
        if not active then self:clear(); return end
        local called,c,why=pcall(backend.gameplay_context or backend.context,backend)
        if not called then why=c; c=nil end
        local state
        if c then state,why=mission(c) end
        if not c then
            self:clear()
            for _,name in ipairs(M.names) do if self.preferences[name] then self.messages[name]=why or 'Session unavailable' end end
            return
        end
        state=state or 0
        c.mission=state
        if not context or not backend:same_context(context,c) or context.mission~=state then
            self:clear(); context=c
            for _,name in ipairs(M.names) do if self.preferences[name] then self.messages[name]='Acquiring mission' end end
            return
        end
        for _,name in ipairs(M.names) do
            if self.preferences[name] then
                local ok,done,problem
                local supported,guard_problem=true,nil
                if backend.validate_gameplay then supported,guard_problem=backend:validate_gameplay(name,c)end
                if not supported then
                    ok,done,problem=true,false,guard_problem
                elseif name=='freeze_timer' and state==0 then
                    ok,done,problem=true,false,'Waiting for a mission'
                else
                    ok,done,problem=pcall(actions[name],c,state,name)
                end
                if not ok or not done then self.holds[name]=nil end
                self.messages[name]=ok and (done and 'Holding' or tostring(problem)) or tostring(done)
            end
        end
    end
    function self:update(dt)
        local mem=backend.mem
        if mem.begin_snapshot then mem:begin_snapshot() end
        local ok,why=pcall(update,dt)
        if mem.end_snapshot then mem:end_snapshot() end
        if not ok then error(why,0) end
    end
    function self:is_clean() return not passive or passive.lease==nil end
    function self:status()
        local parts={}
        for _,name in ipairs(M.names) do
            if self.preferences[name] then parts[#parts+1]=name:gsub('freeze_','')..': '..(self.messages[name] or 'Waiting') end
        end
        if self.preferences.passive_ai then parts[#parts+1]='Passive AI: '..(self.messages.passive_ai or 'Waiting') end
        if self.preferences.instant_extract then parts[#parts+1]='Extraction: '..(self.messages.instant_extract or 'Waiting')end
        return table.concat(parts,'; ')
    end
    return self
end
return M
