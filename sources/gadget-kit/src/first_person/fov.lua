local PORT51=mod.require('src/first_person/compat51.lua')
-- Independent camera-FOV lease. The native helper reads the game's current
-- third-person setting and forwards normal ADS; no FOV setting is cached here.
local Host = mod
local Fov, Adapter = {}, {}
Adapter.__index = Adapter
local fields = {'seen','forwarded','replaced','immediate_applies','binds','ads_forwarded',
    'last_native','last_applied','source_degrees'}
function Adapter.new(profile,clock) return setmetatable({profile=profile,owned=false,clock=clock},Adapter) end
function Adapter:_invalidate_stats()
    self.stats_cache,self.stats_handle,self.stats_at,self.stats_due=nil,nil,nil,nil
end
function Adapter:_load()
    if self.library and self.ffi then return self.library end
    local ffi=self.ffi or PORT51.ffi 
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'Windows x64 required for native FOV')
    if not pcall(ffi.typeof,'NADSF_Config') then ffi.cdef([[
        typedef struct NADSF_Config {
            uint32_t size,abi;
            uint64_t game,exe,context,camera,avatar_owner,request;
            uint32_t avatar_index,avatar,body,weapon;
            uint64_t reserved;
        } NADSF_Config;
        typedef struct NADSF_Stats {
            uint32_t size,abi,installed,armed,error,reserved;
            uint64_t seen,forwarded,replaced,immediate_applies,binds,ads_forwarded;
            float last_native,last_applied,source_degrees,padding;
        } NADSF_Stats;
        uint32_t NADSF_Validate(const NADSF_Config *);
        uint32_t NADSF_Begin(const NADSF_Config *,uint64_t *);
        uint32_t NADSF_Bind(uint64_t,uint64_t,uint32_t);
        uint32_t NADSF_SetTransition(uint64_t,uint64_t,float,uint32_t);
        uint32_t NADSF_End(uint64_t);
        uint32_t NADSF_ReadStats(uint64_t,NADSF_Stats *);
        uint32_t NADSF_Error(void);
    ]]) end
    assert(ffi.sizeof('NADSF_Config')==80 and ffi.sizeof('NADSF_Stats')==88,'FOV helper ABI mismatch')
    self.ffi=ffi
    if self.library then return self.library end
    assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.dir)=='string','FOV helper mod directory unavailable')
    self.library=ffi.load(Host.dir..'/'..self.profile.library)
    if PORT51.kind(Host.scope)=='table' then
        Host.scope.native_ads_fov_libraries=Host.scope.native_ads_fov_libraries or {}
        table.insert(Host.scope.native_ads_fov_libraries,self.library)
    end
    return self.library
end
function Adapter:_error(operation)
    local ok,code=pcall(function()return PORT51.number(self:_load().NADSF_Error())end)
    self.last_failure_code=ok and PORT51.kind(code)=='number' and code~=0 and code or nil
    return operation..' failed (native FOV code '..tostring(ok and code or 'unavailable')..')'
end
function Adapter:_config(config)
    self:_load();assert(PORT51.kind(config)=='table','FOV configuration unavailable')
    local c=self.ffi.new('NADSF_Config');c.size=80;c.abi=self.profile.abi;c.reserved=self.profile.ads_blend_ms or 0
    for _,name in ipairs({'game','exe','context','camera','avatar_owner','request','avatar_index','avatar','body','weapon'}) do
        c[name]=assert(config[name],name..' unavailable')
    end
    return c
end
function Adapter:stats(handle)
    if handle and (PORT51.kind(handle)~='table' or handle.owner~=self or (self.owned and self.owned~=handle)) then
        return nil,'FOV statistics handle is not owned'
    end
    if handle and handle.disarmed then return handle.stats end
    local library=self:_load()
    local s=self.stats_buffer
    if not s then s=self.ffi.new('NADSF_Stats');self.stats_buffer=s end
    s.size=88;s.abi=self.profile.abi
    local generation=handle and handle.generation[0] or 0
    local called,read=pcall(library.NADSF_ReadStats,generation,s)
    if not called then self:_invalidate_stats();error(read,0) end
    if read~=1 then self:_invalidate_stats();return nil,self:_error('FOV statistics') end
    if PORT51.number(s.size)~=88 or PORT51.number(s.abi)~=self.profile.abi then
        self:_invalidate_stats();return nil,'FOV statistics ABI changed'
    end
    -- Native ownership and health are read every call. Only display counters
    -- share a table/conversion between the staggered 10 Hz diagnostic ticks.
    local code=PORT51.number(s.error);local now
    if self.clock and handle and self.owned==handle then
        local ok,value=pcall(self.clock)
        if ok and PORT51.kind(value)=='number' and value==value and math.abs(value)~=math.huge then now=value end
    end
    if not now or code~=0 or (self.stats_at and now<self.stats_at) then self:_invalidate_stats() end
    local out=self.stats_handle==handle and self.stats_cache or nil
    if not out then out={} end
    if not now or code~=0 or not self.stats_cache or self.stats_handle~=handle or now>=self.stats_due then
        for _,name in ipairs(fields) do out[name]=PORT51.number(s[name]) end
        if now and code==0 then
            self.stats_cache,self.stats_handle=out,handle
            local due=(math.floor(now/.1)+1)*.1
            self.stats_due=due>now and due or due+.1
        end
    end
    if now and code==0 then self.stats_at=now end
    out.installed,out.armed,out.error=s.installed~=0,s.armed~=0,code
    return out
end
function Adapter:validate(config)
    self:_invalidate_stats()
    if self.owned then return false,'FOV generation still requires cleanup' end
    if self:_load().NADSF_Validate(self:_config(config))~=1 then return false,self:_error('FOV read-only validation') end
    return true
end
function Adapter:begin(config)
    self:_invalidate_stats()
    if self.owned then return false,'FOV generation still requires cleanup' end
    local library=self:_load();local c=self:_config(config)
    local handle={owner=self,disarmed=false,generation=self.ffi.new('uint64_t[1]')}
    local called,result=pcall(library.NADSF_Begin,c,handle.generation)
    if PORT51.number(handle.generation[0])~=0 then self.owned=handle end
    if not called then return false,'FOV arm result uncertain: '..tostring(result) end
    result=PORT51.number(result)
    if (result==1 or result==2) and not self.owned then return false,'FOV arm returned no owned generation' end
    if result~=1 then return false,self:_error(result==2 and 'FOV partial installation cleanup' or 'FOV arm') end
    return true,handle
end
function Adapter:bind(handle,config)
    self:_invalidate_stats()
    if PORT51.kind(handle)~='table' or handle.owner~=self or self.owned~=handle or handle.disarmed then
        return false,'FOV bind handle is not owned'
    end
    if self:_load().NADSF_Bind(handle.generation[0],config.request,config.weapon)~=1 then
        return false,self:_error('FOV camera binding')
    end
    return true
end
function Adapter:transition(handle,token)
    if PORT51.kind(handle)~='table' or handle.owner~=self or self.owned~=handle or handle.disarmed then
        return false,'FOV transition handle is not owned'
    end
    if PORT51.kind(token)~='table' or PORT51.kind(token.epoch)~='number' or token.epoch<1
        or token.epoch>=9007199254740992 or token.epoch%1~=0
        or PORT51.kind(token.progress)~='number' or token.progress~=token.progress
        or token.progress<0 or token.progress>1 or PORT51.kind(token.ads)~='boolean' then
        return false,'FOV shared presentation phase is invalid'
    end
    if self:_load().NADSF_SetTransition(handle.generation[0],token.epoch,token.progress,token.ads and 1 or 0)~=1 then
        return false,self:_error('FOV shared presentation phase')
    end
    return true
end
function Adapter:owned_handle() return self.owned end
function Adapter:finish(handle)
    if PORT51.kind(handle)~='table' or handle.owner~=self then return false,'FOV cleanup handle is not owned' end
    if handle.disarmed then return true,handle.stats end
    if self.owned~=handle then return false,'FOV generation ownership changed' end
    self:_invalidate_stats()
    local read_ok,before=pcall(self.stats,self,handle)
    if not read_ok then before=nil end
    self:_invalidate_stats()
    if self:_load().NADSF_End(handle.generation[0])~=1 then return false,self:_error('FOV cleanup') end
    handle.disarmed=true;self.owned=false;self:_invalidate_stats()
    handle.stats=self:stats() or before
    return true,handle.stats
end

local function invoke(target,name,...)
    local called,a,b=pcall(target[name],target,...)
    if not called then return nil,tostring(a) end
    return a,b
end
function Fov.new(backend,log,helper,clock)
    assert(PORT51.kind(backend)=='table','FOV backend required')
    if not helper then
        assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.require)=='function','FOV module loader unavailable')
        helper=Adapter.new(assert(Host.require('src/first_person/profile.lua').fov,'FOV profile unavailable'),clock)
    end
    local self={handle=nil,bound=nil,closing=false,fault=nil,last={},phase='idle'}
    log=log or function()end
    local function problem(message)
        self.fault=tostring(message)
        self.failure_native_error=helper.last_failure_code
        self.failure_kind=self.failure_native_error==3 and'temporary_read'or(self.failure_native_error and'unsafe'or nil)
        log('Native FOV: '..self.fault)
        return false,self.fault
    end
    local function collect()
        if not self.handle then return true end
        local stats,why=invoke(helper,'stats',self.handle)
        if PORT51.kind(stats)~='table' then return problem(why or 'FOV statistics unavailable') end
        self.last=stats
        if PORT51.kind(stats.error)=='number' and stats.error~=0 then helper.last_failure_code=stats.error end
        return true
    end
    local function present()
        if not self.handle or PORT51.kind(backend.presentation_transition)~='function' then return true end
        local token,why=invoke(backend,'presentation_transition')
        if token==nil then return true end
        if PORT51.kind(token)~='table' then return problem(why or 'Shared presentation phase unavailable') end
        local done,reason=invoke(helper,'transition',self.handle,token)
        if done~=true then return problem(reason or 'FOV shared presentation phase was refused') end
        self.presentation_epoch,self.presentation_progress=token.epoch,token.progress
        return true
    end
    function self:is_clean() return self.handle==nil end
    function self:result()
        local result={};for k,v in pairs(self.last)do result[k]=v end
        result.phase,result.cleanup_pending=self.phase,self.phase=='cleanup_pending'
        result.error_message=self.fault
        result.failure_native_error,result.failure_kind=self.failure_native_error,self.failure_kind
        result.presentation_epoch,result.presentation_progress=self.presentation_epoch,self.presentation_progress
        -- Acknowledged publication only; diagnostics must not infer that all
        -- native consumers rendered this phase atomically in one callback.
        result.transition_epoch,result.transition_progress=self.presentation_epoch,self.presentation_progress
        return result
    end
    function self:status()
        return self.phase..'; TPV degrees='..tostring(self.last.source_degrees)
            ..'; native/output='..tostring(self.last.last_native)..'/'..tostring(self.last.last_applied)
            ..'; overrides='..tostring(self.last.replaced or 0)..'; ADS forwarded='..tostring(self.last.ads_forwarded or 0)
    end
    function self:stop()
        if not self.handle then self.bound,self.bound_request,self.bound_weapon,self.bound_player=nil,nil,nil,nil;self.presentation_epoch,self.presentation_progress=nil,nil;self.phase='idle';return true end
        self.phase='cleanup_pending'
        local done,stats=invoke(helper,'finish',self.handle)
        if done~=true then return problem(stats or 'FOV cleanup remains pending') end
        if PORT51.kind(stats)=='table' then self.last=stats end
        self.handle,self.bound,self.bound_request,self.bound_weapon,self.bound_player=nil,nil,nil,nil,nil;self.presentation_epoch,self.presentation_progress=nil,nil;self.phase='idle'
        return true
    end
    function self:shutdown() self.closing=true;return self:stop() end
    function self:preflight()
        helper.last_failure_code=nil;self.failure_native_error,self.failure_kind=nil,nil
        if self.handle then return false,'FOV cleanup is still active' end
        local config,why=invoke(backend,'fov_config')
        if PORT51.kind(config)~='table' then return false,why or 'FOV configuration unavailable' end
        local done,reason=invoke(helper,'validate',config)
        if done~=true then return problem(reason or 'FOV validation refused') end
        return true
    end
    function self:update(controller)
        helper.last_failure_code=nil;self.failure_native_error,self.failure_kind=nil,nil
        if self.phase=='cleanup_pending' then return self:stop() end
        local result=controller:result()
        if self.closing or not controller:is_enabled() or result.mode~='pose_offset' then return self:stop() end
        local lease=controller.lease
        if not lease or result.phase~='running' then
            -- The camera policy survives helper suspension and weapon gaps.
            if self.handle then
                local ready,why=present();if not ready then self:stop();return false,why end
                local ok,why=collect();if not ok then return false,why end
                -- Death/respawn and other owner changes can retire the stable
                -- lens generation while manual FPV intent waits for gameplay.
                if self.last.armed==false then return self:stop()end
            end
            return true
        end
        local player=lease.origin and lease.origin.player_identity
        if self.handle and self.bound_player and player~=self.bound_player then
            local done,why=self:stop();if done~=true then return false,why end
        end
        local weapon=lease.origin and lease.origin.weapon or lease.weapon
        if self.handle and self.bound==lease and self.bound_request==lease.request and self.bound_weapon==weapon then
            local ready,why=present();if not ready then self:stop();return false,why end
            local ok,why=collect();if not ok then self:stop();return false,why end
            if self.last.armed~=true or (self.last.error and self.last.error~=0) then
                local why='Native FOV policy disarmed or rejected ownership';problem(why);local done,issue=self:stop();return false,done==true and why or issue
            end
            return true
        end
        local config,why=invoke(backend,'fov_config',lease)
        if PORT51.kind(config)~='table' then return problem(why or 'Owned FOV camera is unavailable') end
        local had_handle=self.handle~=nil
        if had_handle then
            -- Bind can immediately submit a lens. Publish the current phase
            -- first so a same-body request handoff cannot use the old phase.
            local ready,reason=present();if not ready then self:stop();return false,reason end
        end
        local done,value
        if self.handle then
            if self.bound_request==config.request and self.bound_weapon==config.weapon then done=true
            else done,value=invoke(helper,'bind',self.handle,config) end
        else
            done,value=invoke(helper,'begin',config)
            if done==true then self.handle=value
            else
                local owned=invoke(helper,'owned_handle')
                if owned then self.handle=owned end
            end
        end
        if done~=true or not self.handle then
            local why=value or 'Native FOV policy was not accepted'
            problem(why);local stopped,issue=self:stop();return false,stopped==true and why or issue
        end
        self.bound,self.phase,self.fault=lease,'active',nil
        self.bound_request,self.bound_weapon=config.request,config.weapon
        self.bound_player=player
        if not had_handle then
            local ready,why=present();if not ready then self:stop();return false,why end
        end
        local ok,why=collect();if not ok then self:stop();return false,why end
        if self.last.armed~=true or (self.last.error and self.last.error~=0) then
            local why='Native FOV policy did not remain armed';problem(why);local stopped,issue=self:stop();return false,stopped==true and why or issue
        end
        return true
    end
    return self
end
Fov.Adapter=Adapter
return Fov
