-- Player flags are separate from the avatar's packed action flags.
local M={}
local MASK=33554432 -- Player bit 25
local PIN=('4c8b15ef158302743e458b4a20'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
local function bytes(v)
    local out={}
    for i=1,4 do out[i]=string.char(v%256);v=math.floor(v/256) end
    return table.concat(out)
end
function M.new(backend)
    local self={lease=nil}
    local function resolve(c)
        local m=backend.mem
        if m:read(c.game+0x4AFFEA,#PIN)~=PIN then return nil,'Player flags fingerprint mismatch' end
        local unit=m:u32(c.player+0x3A8)
        local wi=unit and m:hashmap(c.world+0xF24990,unit)
        local entity=wi and m:u32(c.world+0xF349E0+wi*24+8)
        local manager=entity and m:ptr(c.game+0x2CE15E0)
        local index=manager and m:hashmap(manager+0x18,entity)
        local descriptors=index and m:ptr(manager+0x30)
        local descriptor=descriptors and m:ptr(descriptors+index*8)
        local records=index and m:ptr(manager+0x38)
        if not descriptor or not records or m:u32(descriptor+8)~=entity or m:u32(descriptor+16)~=unit then
            return nil,'Waiting for local Player flags'
        end
        local address=records+index*8
        local value=m:u32(address)
        if not value then return nil,'Player flags are unreadable' end
        return {identity=table.concat({c.game,c.player,c.world,entity,unit,manager,descriptor},':'),address=address,value=value}
    end
    function self:update(c,enabled)
        local current,why=resolve(c)
        if not current then self.lease=nil; return false,why end
        local lease=self.lease
        if lease and (lease.identity~=current.identity or lease.address~=current.address) then self.lease=nil;lease=nil end
        local set=math.floor(current.value/MASK)%2==1
        if enabled then
            self.lease=current
            if not set then
                return backend.mem:copy(current.address,bytes(current.value+MASK))
            end
            return true
        end
        if lease then
            if set then
                local ok,problem=backend.mem:copy(current.address,bytes(current.value-MASK))
                if not ok then return false,problem end
            end
            self.lease=nil
        end
        return true
    end
    function self:release()
        if not self.lease then return true end
        local c=backend:passive_ai_context()
        if not c then self.lease=nil;return true end
        return self:update(c,false)
    end
    return self
end
return M
