local PORT51=mod.require('src/first_person/compat51.lua')
-- Near-clip lease beside the FOV lease. The native helper changes only the
-- game's own per-update near distance for the owned first-person camera;
-- full ADS always keeps the game's distance. Nothing here is cached for restore:
-- the game writes its own value again on the next update after End.
local Host = mod
local Near, Adapter = {}, {}
Adapter.__index = Adapter
local fields = {'seen','forwarded','replaced','ads_forwarded','aim_applied','other_kind',
    'last_native','last_applied','hip','aim'}
function Adapter.new(profile) return setmetatable({profile=profile,owned=false},Adapter) end
function Adapter:_load()
    if self.library and self.ffi then return self.library end
    local ffi=self.ffi or PORT51.ffi
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'Windows x64 required for native near clip')
    if not pcall(ffi.typeof,'NADSN_Config') then ffi.cdef([[
        typedef struct NADSN_Config {
            uint32_t size,abi;
            uint64_t game,exe,context,camera,avatar_owner;
            uint32_t avatar_index;
            float hip,aim;
            uint32_t reserved;
            uint64_t reserved2;
        } NADSN_Config;
        typedef struct NADSN_Stats {
            uint32_t size,abi,installed,armed,error,reserved;
            uint64_t seen,forwarded,replaced,ads_forwarded,aim_applied,other_kind;
            float last_native,last_applied,hip,aim;
        } NADSN_Stats;
        uint32_t NADSN_Begin(const NADSN_Config *,uint64_t *);
        uint32_t NADSN_Set(uint64_t,float,float);
        uint32_t NADSN_End(uint64_t);
        uint32_t NADSN_ReadStats(uint64_t,NADSN_Stats *);
        uint32_t NADSN_Error(void);
    ]]) end
    assert(ffi.sizeof('NADSN_Config')==72 and ffi.sizeof('NADSN_Stats')==88,'Near clip helper ABI mismatch')
    self.ffi=ffi
    if self.library then return self.library end
    assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.dir)=='string','Near clip helper mod directory unavailable')
    self.library=ffi.load(Host.dir..'/'..self.profile.library)
    if PORT51.kind(Host.scope)=='table' then
        Host.scope.native_ads_near_libraries=Host.scope.native_ads_near_libraries or {}
        table.insert(Host.scope.native_ads_near_libraries,self.library)
    end
    return self.library
end
function Adapter:_error(operation)
    local ok,code=pcall(function()return PORT51.number(self:_load().NADSN_Error())end)
    return operation..' failed (native near clip code '..tostring(ok and code or 'unavailable')..')'
end
function Adapter:_config(config)
    self:_load();assert(PORT51.kind(config)=='table','Near clip configuration unavailable')
    local c=self.ffi.new('NADSN_Config');c.size=72;c.abi=self.profile.abi;c.reserved=0;c.reserved2=0
    for _,name in ipairs({'game','exe','context','camera','avatar_owner','avatar_index','hip','aim'}) do
        c[name]=assert(config[name],name..' unavailable')
    end
    return c
end
function Adapter:stats(handle)
    if handle and (PORT51.kind(handle)~='table' or handle.owner~=self or (self.owned and self.owned~=handle)) then
        return nil,'Near clip statistics handle is not owned'
    end
    if handle and handle.disarmed then return handle.stats end
    local library=self:_load()
    local s=self.stats_buffer
    if not s then s=self.ffi.new('NADSN_Stats');self.stats_buffer=s end
    s.size=88;s.abi=self.profile.abi
    if library.NADSN_ReadStats(handle and handle.generation[0] or 0,s)~=1 then return nil,self:_error('Near clip statistics') end
    if PORT51.number(s.size)~=88 or PORT51.number(s.abi)~=self.profile.abi then return nil,'Near clip statistics ABI changed' end
    local out={}
    for _,name in ipairs(fields) do out[name]=PORT51.number(s[name]) end
    out.installed,out.armed,out.error=s.installed~=0,s.armed~=0,PORT51.number(s.error)
    return out
end
function Adapter:begin(config)
    if self.owned then return false,'Near clip generation still requires cleanup' end
    local library=self:_load();local c=self:_config(config)
    local handle={owner=self,disarmed=false,generation=self.ffi.new('uint64_t[1]')}
    local called,result=pcall(library.NADSN_Begin,c,handle.generation)
    if PORT51.number(handle.generation[0])~=0 then self.owned=handle end
    if not called then return false,'Near clip arm result uncertain: '..tostring(result) end
    result=PORT51.number(result)
    if (result==1 or result==2) and not self.owned then return false,'Near clip arm returned no owned generation' end
    if result~=1 then return false,self:_error(result==2 and 'Near clip partial installation cleanup' or 'Near clip arm') end
    return true,handle
end
function Adapter:set(handle,hip,aim)
    if PORT51.kind(handle)~='table' or handle.owner~=self or self.owned~=handle or handle.disarmed then
        return false,'Near clip handle is not owned'
    end
    if self:_load().NADSN_Set(handle.generation[0],hip,aim)~=1 then return false,self:_error('Near clip distance update') end
    return true
end
function Adapter:owned_handle() return self.owned end
function Adapter:finish(handle)
    if PORT51.kind(handle)~='table' or handle.owner~=self then return false,'Near clip cleanup handle is not owned' end
    if handle.disarmed then return true,handle.stats end
    if self.owned~=handle then return false,'Near clip generation ownership changed' end
    local read_ok,before=pcall(self.stats,self,handle)
    if not read_ok then before=nil end
    if self:_load().NADSN_End(handle.generation[0])~=1 then return false,self:_error('Near clip cleanup') end
    handle.disarmed=true;self.owned=false
    handle.stats=self:stats() or before
    return true,handle.stats
end

local function invoke(target,name,...)
    local called,a,b=pcall(target[name],target,...)
    if not called then return nil,tostring(a) end
    return a,b
end
-- options() returns {hip=metres,aim=metres}; zero keeps the game's distance.
function Near.new(backend,log,helper,clock,options)
    assert(PORT51.kind(backend)=='table','Near clip backend required')
    if not helper then
        assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.require)=='function','Near clip module loader unavailable')
        helper=Adapter.new(assert(Host.require('src/first_person/profile.lua').near,'Near clip profile unavailable'))
    end
    clock=clock or os.clock;options=options or function()return {hip=0,aim=0}end
    local self={handle=nil,closing=false,fault=nil,last={},phase='idle',hip=nil,aim=nil,retry_at=nil,next_collect=nil,last_collect=0}
    log=log or function()end
    local function problem(message)
        message=tostring(message)
        if message~=self.fault then log('Native near clip: '..message)end
        self.fault=message;return false,message
    end
    local function wanted()
        local value=options()
        local hip=PORT51.kind(value)=='table' and value.hip or 0
        local aim=PORT51.kind(value)=='table' and value.aim or 0
        if PORT51.kind(hip)~='number' or hip~=hip or hip<0 or hip>1 then hip=0 end
        if PORT51.kind(aim)~='number' or aim~=aim or aim<0 or aim>1 then aim=0 end
        return hip,aim
    end
    local function collect()
        local stats,why=invoke(helper,'stats',self.handle)
        if PORT51.kind(stats)~='table' then return problem(why or 'Near clip statistics unavailable') end
        self.last=stats;return true
    end
    function self:is_clean() return self.handle==nil end
    function self:result()
        local result={};for k,v in pairs(self.last)do result[k]=v end
        result.phase,result.cleanup_pending=self.phase,self.phase=='cleanup_pending'
        result.error_message=self.fault
        return result
    end
    function self:status()
        return self.phase..'; near hip/aim='..tostring(self.hip)..'/'..tostring(self.aim)
            ..'; native/output='..tostring(self.last.last_native)..'/'..tostring(self.last.last_applied)
            ..'; clipped='..tostring(self.last.replaced or 0)..'; ADS forwarded='..tostring(self.last.ads_forwarded or 0)
    end
    function self:stop()
        self.next_collect=nil
        if not self.handle then self.bound_player,self.hip,self.aim=nil,nil,nil;self.phase='idle';return true end
        self.phase='cleanup_pending'
        local done,stats=invoke(helper,'finish',self.handle)
        if done~=true then return problem(stats or 'Near clip cleanup remains pending') end
        if PORT51.kind(stats)=='table' then self.last=stats end
        self.handle,self.bound_player,self.hip,self.aim=nil,nil,nil,nil;self.phase='idle'
        return true
    end
    function self:shutdown() self.closing=true;return self:stop() end
    function self:update(controller)
        if self.phase=='cleanup_pending' then return self:stop() end
        local result=controller:result()
        local hip,aim=wanted()
        if self.closing or not controller:is_enabled() or result.mode~='pose_offset' or (hip==0 and aim==0) then
            self.retry_at=nil;return self:stop()
        end
        local lease=controller.lease
        if not lease or result.phase~='running' then
            -- Like the FOV lens, survive weapon gaps; the helper itself keeps
            -- the game's distance whenever the first-person request is absent.
            if self.handle then
                local ok,why=collect();if not ok then return false,why end
                if self.last.armed==false then return self:stop()end
            end
            return true
        end
        local player=lease.origin and lease.origin.player_identity
        if self.handle and self.bound_player and player~=self.bound_player then
            local done,why=self:stop();if done~=true then return false,why end
        end
        if self.handle then
            if hip~=self.hip or aim~=self.aim then
                local done,why=invoke(helper,'set',self.handle,hip,aim)
                if done~=true then self:stop();return problem(why or 'Near clip distance update refused') end
                self.hip,self.aim,self.next_collect=hip,aim,nil
            end
            -- Health is polled at 4 Hz; the helper disarms itself immediately.
            local now=clock()
            if self.next_collect and now>=self.last_collect and now<self.next_collect then return true end
            self.last_collect,self.next_collect=now,now+.25
            local ok,why=collect();if not ok then self:stop();return false,why end
            if self.last.armed~=true then
                local code=self.last.error;self:stop();return problem('Native near clip disarmed (code '..tostring(code)..')')
            end
            return true
        end
        local now=clock()
        if self.retry_at and now<self.retry_at then return true end
        self.retry_at=now+1
        local config,why=invoke(backend,'fov_config',lease)
        if PORT51.kind(config)~='table' then return problem(why or 'Owned near-clip camera is unavailable') end
        config.hip,config.aim=hip,aim
        local done,value=invoke(helper,'begin',config)
        if done==true then self.handle=value
        else
            local owned=invoke(helper,'owned_handle')
            if owned then self.handle=owned end
        end
        if done~=true or not self.handle then
            local reason=value or 'Native near clip was not accepted'
            self:stop();return problem(reason)
        end
        self.hip,self.aim,self.bound_player,self.phase,self.fault,self.retry_at=hip,aim,player,'active',nil,nil
        local ok,reason=collect();if not ok then self:stop();return false,reason end
        if self.last.armed~=true then self:stop();return problem('Native near clip did not remain armed')end
        return true
    end
    return self
end
Near.Adapter=Adapter
return Near
