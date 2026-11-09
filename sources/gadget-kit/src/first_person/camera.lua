local PORT51=mod.require('src/first_person/compat51.lua')
-- Stable player camera policy, independent of the current firearm lease.
local Host=mod
local Camera,Adapter={},{}
local function offsets(p)
 if PORT51.kind(p)~='table'then return false end
 for _,k in ipairs({'x','y','z'})do local n=p[k];if PORT51.kind(n)~='number'or n~=n or math.abs(n)>.5 then return false end end
 return true
end
Adapter.__index=Adapter
local fields={'seen','forwarded','replaced','native6_forwarded','resets','blend','head_distance','last_dt'}
function Adapter.new(profile,clock)return setmetatable({profile=profile,owned=false,clock=clock},Adapter)end
function Adapter:_invalidate_stats()
    self.stats_cache,self.stats_handle,self.stats_at,self.stats_due=nil,nil,nil,nil
end
function Adapter:_load()
    if self.library and self.ffi then return self.library end
    local ffi=self.ffi or PORT51.ffi 
    pcall(ffi.cdef,[[
        typedef struct NADSC_ParentStats45 {uint64_t samples,rejected,remaining_ms;float max_degrees,padding;} NADSC_ParentStats45;
        uint32_t NADSC_ObserveParent(uint64_t generation,uint32_t milliseconds);
        uint32_t NADSC_ParentStats(uint64_t generation,NADSC_ParentStats45*);
    ]])
    pcall(ffi.cdef,[[
        typedef struct NADSC_FreeStats {uint32_t size,gate;uint64_t applied,ads_bypassed,remaining_ms;float yaw,pitch;uint64_t measured;double total_us,max_us;} NADSC_FreeStats;
        uint32_t NADSC_FreeAim(uint64_t generation,uint32_t milliseconds);
        uint32_t NADSC_FreeAimStats(uint64_t generation,NADSC_FreeStats*);
        typedef struct NADSC_ParentStats45 {uint64_t samples,rejected,remaining_ms;float max_degrees,padding;} NADSC_ParentStats45;
        uint32_t NADSC_ObserveParent(uint64_t generation,uint32_t milliseconds);
        uint32_t NADSC_ParentStats(uint64_t generation,NADSC_ParentStats45*);
    ]])
    pcall(ffi.cdef,[[
        typedef struct NADSC_KickStats46Data {uint64_t pulses,frames;uint32_t enabled;float angle;} NADSC_KickStats46Data;
        uint32_t NADSC_SetKick46(uint64_t generation,uint32_t enabled);
        uint32_t NADSC_KickStats46(uint64_t generation,NADSC_KickStats46Data*);
    ]])
    pcall(ffi.cdef,[[
        uint32_t NADSC_SetPresentation47(uint64_t generation);
        typedef struct NADSC_Profile47Data {uint32_t remaining,count;double mean_us,p99_us,max_us;} NADSC_Profile47Data;
        uint32_t NADSC_Profile47(uint64_t generation,uint32_t count);
        uint32_t NADSC_ProfileStats47(uint64_t generation,NADSC_Profile47Data*);
        uint32_t NADSC_SetCameraMotion47(uint64_t generation,float x,float y,float z,float pitch,float yaw,float roll);
    ]])
    pcall(ffi.cdef,'uint32_t NADSC_SetOffsets(uint64_t generation,float right,float forward,float up);')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'Windows x64 required for native head camera')
    if not pcall(ffi.typeof,'NADSC_Config')then ffi.cdef([[
        typedef struct NADSC_Config {
            uint32_t size,abi;
            uint64_t game,exe,context,camera,avatar_owner;
            uint32_t avatar_index,avatar,body,camera_unit;
            float forward,up,smoothing_ms,blend_ms;
            uint32_t max_gap_ms,reserved;
        } NADSC_Config;
        typedef struct NADSC_Stats {
            uint32_t size,abi,installed,armed,error,reserved;
            uint64_t seen,forwarded,replaced,native6_forwarded,resets;
            float blend,head_distance,last_dt,padding;
        } NADSC_Stats;
        uint32_t NADSC_Validate(const NADSC_Config*);
        uint32_t NADSC_Begin(const NADSC_Config*,uint64_t*);
        uint32_t NADSC_End(uint64_t);
        uint32_t NADSC_ReadStats(uint64_t,NADSC_Stats*);
        uint32_t NADSC_Error(void);
    ]])end
    assert(ffi.sizeof('NADSC_Config')==88 and ffi.sizeof('NADSC_Stats')==80,'Head-camera helper ABI mismatch')
    self.ffi=ffi
    if self.library then return self.library end
    assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.dir)=='string','Head-camera mod directory unavailable')
    self.library=ffi.load(Host.dir..'/'..self.profile.library)
    if PORT51.kind(Host.scope)=='table'then
        Host.scope.native_ads_camera_libraries=Host.scope.native_ads_camera_libraries or {}
        table.insert(Host.scope.native_ads_camera_libraries,self.library)
    end
    return self.library
end
function Adapter:_error(operation)
    local ok,code=pcall(function()return PORT51.number(self:_load().NADSC_Error())end)
    self.last_failure_code=ok and PORT51.kind(code)=='number'and code or nil
    return operation..' failed (native head-camera code '..tostring(ok and code or 'unavailable')..')'
end
function Adapter:_config(config)
    self:_load();assert(PORT51.kind(config)=='table','Head-camera configuration unavailable')
    local c=self.ffi.new('NADSC_Config');c.size=88;c.abi=self.profile.abi;c.reserved=0
    for _,name in ipairs({'game','exe','context','camera','avatar_owner','avatar_index','avatar','body','camera_unit',
        'forward','up','smoothing_ms','blend_ms','max_gap_ms'})do c[name]=assert(config[name],name..' unavailable')end
    return c
end
function Adapter:stats(handle)
    if handle and(PORT51.kind(handle)~='table' or handle.owner~=self or(self.owned and self.owned~=handle))then
        return nil,'Head-camera statistics handle is not owned'
    end
    if handle and handle.disarmed then return handle.stats end
    local library=self:_load()
    local s=self.stats_buffer
    if not s then s=self.ffi.new('NADSC_Stats');self.stats_buffer=s end
    s.size=80;s.abi=self.profile.abi
    local generation=handle and handle.generation[0] or 0
    local called,read=pcall(library.NADSC_ReadStats,generation,s)
    if not called then self:_invalidate_stats();error(read,0) end
    if read~=1 then self:_invalidate_stats();return nil,self:_error('Head-camera statistics') end
    if PORT51.number(s.size)~=80 or PORT51.number(s.abi)~=self.profile.abi then
        self:_invalidate_stats();return nil,'Head-camera statistics ABI changed'
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
            local due=(math.floor((now-.0333)/.1)+1)*.1+.0333
            self.stats_due=due>now and due or due+.1
        end
    end
    if now and code==0 then self.stats_at=now end
    out.installed,out.armed,out.error=s.installed~=0,s.armed~=0,code
    return out
end
function Adapter:validate(config)
    self:_invalidate_stats()
    if self.owned then return false,'Head-camera generation still requires cleanup'end
    if self:_load().NADSC_Validate(self:_config(config))~=1 then return false,self:_error('Head-camera read-only validation')end
    return true
end
function Adapter:begin(config)
    self:_invalidate_stats()
    if self.owned then return false,'Head-camera generation still requires cleanup'end
    local library=self:_load();local c=self:_config(config)
    local handle={owner=self,disarmed=false,generation=self.ffi.new('uint64_t[1]')}
    local called,result=pcall(library.NADSC_Begin,c,handle.generation)
    if PORT51.number(handle.generation[0])~=0 then self.owned=handle end
    if not called then return false,'Head-camera arm result uncertain: '..tostring(result)end
    result=PORT51.number(result)
    if(result==1 or result==2)and not self.owned then return false,'Head-camera arm returned no owned generation'end
    if result~=1 then return false,self:_error(result==2 and 'Head-camera partial installation cleanup' or 'Head-camera arm')end
    return true,handle
end
function Adapter:owned_handle()return self.owned end
function Adapter:set_offsets(handle,p)
    if not offsets(p)or self.owned~=handle or handle.disarmed then return false,'Head camera offsets are not owned'end
    if self:_load().NADSC_SetOffsets(handle.generation[0],p.x,p.y,p.z)~=1 then return false,self:_error('Head camera offset update')end
    return true
end
function Adapter:free_aim(handle,milliseconds)
    if self.owned~=handle or handle.disarmed then return false,'Free aim camera is not owned'end
    if self:_load().NADSC_FreeAim(handle.generation[0],milliseconds)~=1 then return false,self:_error('Free aim test')end
    return true
end
function Adapter:begin_profile(handle)
    if self.owned~=handle or handle.disarmed then return false,'Camera not owned'end
    return self:_load().NADSC_Profile47(handle.generation[0],400)==1
end
function Adapter:profile_stats(handle)
    if self.owned~=handle or handle.disarmed then return nil,'Camera not owned'end
    local s=self.ffi.new('NADSC_Profile47Data')
    if self:_load().NADSC_ProfileStats47(handle.generation[0],s)~=1 then return nil,'Camera timing unavailable'end
    return {remaining=PORT51.number(s.remaining),count=PORT51.number(s.count),mean_us=PORT51.number(s.mean_us),p99_us=PORT51.number(s.p99_us),max_us=PORT51.number(s.max_us)}
end
function Adapter:set_presentation(handle)
    if self.owned~=handle or handle.disarmed then return false,'Camera not owned'end
    return self:_load().NADSC_SetPresentation47(handle.generation[0])==1
end
function Adapter:set_motion(handle,value)
    if self.owned~=handle or handle.disarmed then return false,'Camera not owned'end
    return self:_load().NADSC_SetCameraMotion47(handle.generation[0],value.dx,value.dy,value.dz,value.pitch,value.yaw,value.roll)==1
end
function Adapter:set_kick(handle,enabled)
    if self.owned~=handle or handle.disarmed then return false,'Camera not owned'end
    return self:_load().NADSC_SetKick46(handle.generation[0],enabled and 1 or 0)==1
end
function Adapter:kick_stats(handle)
    if self.owned~=handle or handle.disarmed then return nil,'Camera not owned'end
    local s=self.ffi.new('NADSC_KickStats46Data')
    if self:_load().NADSC_KickStats46(handle.generation[0],s)~=1 then return nil,'Kick statistics unavailable'end
    return {pulses=PORT51.number(s.pulses),frames=PORT51.number(s.frames),enabled=s.enabled~=0,angle=PORT51.number(s.angle)}
end
function Adapter:observe_parent(handle)
    if self.owned~=handle or handle.disarmed then return false,'Camera not owned'end
    return self:_load().NADSC_ObserveParent(handle.generation[0],3000)==1
end
function Adapter:parent_stats(handle)
    if self.owned~=handle or handle.disarmed then return nil,'Camera not owned'end
    local s=self.ffi.new('NADSC_ParentStats45')
    if self:_load().NADSC_ParentStats(handle.generation[0],s)~=1 then return nil,'Parent statistics unavailable'end
    return {samples=PORT51.number(s.samples),rejected=PORT51.number(s.rejected),remaining_ms=PORT51.number(s.remaining_ms),max_degrees=PORT51.number(s.max_degrees)}
end
function Adapter:free_aim_stats(handle)
    if self.owned~=handle or handle.disarmed then return nil,'Free aim camera is not owned'end
    local s=self.ffi.new('NADSC_FreeStats')
    if self:_load().NADSC_FreeAimStats(handle.generation[0],s)~=1 then return nil,'Free aim statistics unavailable'end
    return {applied=PORT51.number(s.applied),ads_bypassed=PORT51.number(s.ads_bypassed),remaining_ms=PORT51.number(s.remaining_ms),gate=PORT51.number(s.gate),yaw=PORT51.number(s.yaw),pitch=PORT51.number(s.pitch),measured=PORT51.number(s.measured),total_us=PORT51.number(s.total_us),max_us=PORT51.number(s.max_us)}
end
function Adapter:finish(handle)
    if PORT51.kind(handle)~='table' or handle.owner~=self then return false,'Head-camera cleanup handle is not owned'end
    if handle.disarmed then return true,handle.stats end
    if self.owned~=handle then return false,'Head-camera generation ownership changed'end
    self:_invalidate_stats()
    local read_ok,before=pcall(self.stats,self,handle);if not read_ok then before=nil end
    self:_invalidate_stats()
    if self:_load().NADSC_End(handle.generation[0])~=1 then return false,self:_error('Head-camera cleanup')end
    handle.disarmed=true;self.owned=false;self:_invalidate_stats();handle.stats=self:stats() or before
    return true,handle.stats
end
local function invoke(target,name,...)
    local called,a,b=pcall(target[name],target,...);if not called then return nil,tostring(a)end;return a,b
end
function Camera.new(backend,log,helper,clock)
    assert(PORT51.kind(backend)=='table','Head-camera backend required')
    if not helper then
        assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.require)=='function','Head-camera module loader unavailable')
        helper=Adapter.new(assert(Host.require('src/first_person/profile.lua').camera,'Head-camera profile unavailable'),clock)
    end
    local self={handle=nil,bound=nil,closing=false,fault=nil,last={},phase='idle'};log=log or function()end
    local identity_fields={'game','exe','context','camera','avatar_owner','avatar_index','avatar','body','camera_unit'}
    local function same_identity(a,b)
        if PORT51.kind(a)~='table' or PORT51.kind(b)~='table'then return false end
        for _,name in ipairs(identity_fields)do if a[name]~=b[name]then return false end end
        return true
    end
    local function problem(message)
        self.fault=tostring(message)
        self.failure_native_error=helper.last_failure_code
        self.failure_kind=self.failure_native_error==3 and'temporary_read'or(self.failure_native_error and'unsafe'or nil)
        log('Native head camera: '..self.fault);return false,self.fault
    end
    local function collect()
        local stats,why=invoke(helper,'stats',self.handle)
        if PORT51.kind(stats)~='table'then return problem(why or 'Head-camera statistics unavailable')end
        self.last=stats
        if PORT51.kind(stats.error)=='number'and stats.error~=0 then helper.last_failure_code=stats.error end
        return true
    end
    function self:is_clean()return self.handle==nil end
    function self:result()
        local result={};for k,v in pairs(self.last)do result[k]=v end
        result.phase,result.cleanup_pending=self.phase,self.phase=='cleanup_pending';result.error_message=self.fault
        result.failure_native_error,result.failure_kind=self.failure_native_error,self.failure_kind
        return result
    end
    function self:status()
        return self.phase..'; normal head calls='..tostring(self.last.replaced or 0)
            ..'; native ADS calls='..tostring(self.last.native6_forwarded or 0)..'; blend='..tostring(self.last.blend or 0)
            ..'; gate='..tostring(self.last.error or 0)
    end
    local pending_motion={dx=0,dy=0,dz=0,pitch=0,yaw=0,roll=0};local motion_handle
    function self:set_motion(value)
        local changed=motion_handle~=self.handle
        for _,key in ipairs({'dx','dy','dz','pitch','yaw','roll'})do
            local n=value[key]or 0;if PORT51.kind(n)~='number'or n~=n or math.abs(n)>.03 then return false,'Camera motion exceeds bounds'end
            if pending_motion[key]~=n then changed=true end
        end
        if not changed then return true end
        for _,key in ipairs({'dx','dy','dz','pitch','yaw','roll'})do pending_motion[key]=value[key]or 0 end
        if not self.handle then motion_handle=nil;return true end
        local ok,why=invoke(helper,'set_motion',self.handle,pending_motion);if ok then motion_handle=self.handle end;return ok,why
    end
    function self:profile()
        if not self.handle then return false,'Camera is inactive'end
        return invoke(helper,'begin_profile',self.handle)
    end
    function self:profile_stats()
        if not self.handle then return nil,'Camera is inactive'end
        return invoke(helper,'profile_stats',self.handle)
    end
    function self:kick_stats()
        if not self.handle then return nil,'Camera is inactive'end
        return invoke(helper,'kick_stats',self.handle)
    end
    function self:observe_parent()
        if not self.handle then return false,'Enable native FPV first'end
        return invoke(helper,'observe_parent',self.handle)
    end
    function self:parent_stats()
        if not self.handle then return nil,'Camera is inactive'end
        return invoke(helper,'parent_stats',self.handle)
    end
    function self:free_aim(milliseconds)
        if not self.handle then return false,'Enable native FPV first'end
        return invoke(helper,'free_aim',self.handle,milliseconds)
    end
    function self:free_aim_stats()
        if not self.handle then return nil,'No active native camera'end
        return invoke(helper,'free_aim_stats',self.handle)
    end
    function self:set_offsets(p)
        if not offsets(p)then return false,'Head camera offsets exceed bounds'end
        if not self.handle then return true end
        return invoke(helper,'set_offsets',self.handle,p)
    end
    function self:stop()
        if not self.handle then self.bound=nil;self.phase='idle';return true end
        self.phase='cleanup_pending';local done,stats=invoke(helper,'finish',self.handle)
        if done~=true then return problem(stats or 'Head-camera cleanup remains pending')end
        if PORT51.kind(stats)=='table'then self.last=stats end
        self.handle,self.bound=nil,nil;self.phase='idle';return true
    end
    function self:shutdown()self.closing=true;return self:stop()end
    function self:preflight()
        if self.handle then return false,'Head-camera cleanup is still active'end
        local config,why=invoke(backend,'camera_config')
        if PORT51.kind(config)~='table'then return false,why or 'Head-camera configuration unavailable'end
        if config.camera_kind~=4 and config.camera_kind~=6 then return false,'Camera preparation requires an owned on-foot gameplay view'end
        return invoke(helper,'validate',config)
    end
    function self:prepare()
        helper.last_failure_code=nil;self.failure_native_error,self.failure_kind=nil,nil
        if self.closing then return false,'Head-camera manager is shutting down'end
        if self.phase=='cleanup_pending'then return false,'Head-camera cleanup remains pending'end
        local config,why=invoke(backend,'camera_config')
        if PORT51.kind(config)~='table'then return false,why or 'Head-camera configuration unavailable'end
        if config.camera_kind~=4 and config.camera_kind~=6 then return false,'Camera preparation requires an owned on-foot gameplay view'end
        if self.handle then
            local ok,why=collect();if not ok then self:stop();return false,why end
            if self.last.armed==true and same_identity(self.bound,config)then return true end
            local stopped,issue=self:stop();if not stopped then return false,issue end
        end
        local done,value=invoke(helper,'begin',config)
        if done==true then self.handle=value else self.handle=invoke(helper,'owned_handle') or nil end
        if done~=true or not self.handle then
            local why=value or 'Head-camera policy was not accepted';self:stop();return problem(why)
        end
        if config.right then
            local updated,why=invoke(helper,'set_offsets',self.handle,{x=config.right,y=config.forward,z=config.up})
            if not updated then self:stop();return false,why end
        end
        if config.presentation_enabled==true then
            local ok,why=invoke(helper,'set_presentation',self.handle)
            if not ok then self:stop();return false,why or 'Camera handoff preparation refused'end
        end
        if config.kick_enabled==true then
            local ok,why=invoke(helper,'set_kick',self.handle,true)
            if not ok then self:stop();return false,why or 'Camera kick preparation refused'end
        end
        self.bound={};for _,name in ipairs(identity_fields)do self.bound[name]=config[name]end
        self.phase,self.fault='active',nil
        local ok,why=collect();if not ok then self:stop();return false,why end
        if self.last.armed~=true then self:stop();return problem('Head-camera policy did not remain armed')end
        return true
    end
    self.prearm=self.prepare
    function self:update(controller)
        helper.last_failure_code=nil;self.failure_native_error,self.failure_kind=nil,nil
        if self.phase=='cleanup_pending'then return self:stop()end
        local result=controller:result()
        if self.closing or not controller:is_enabled() or result.mode~='pose_offset'then return self:stop()end
        if not self.handle then
            -- The rebuilt native6 path is exact passthrough. Fresh local
            -- on-foot ownership permits rearming after acknowledged cleanup.
            local config,why=invoke(backend,'camera_config')
            if PORT51.kind(config)~='table' or(config.camera_kind~=4 and config.camera_kind~=6)then self.phase='waiting';return true,why end
            return self:prepare()
        end
        local ok,why=collect();if not ok then self:stop();return false,why end
        if self.last.armed~=true then
            local stopped,issue=self:stop();if not stopped then return false,issue end
            self.phase='waiting';self.fault=nil
            return true,'Head-camera player changed; waiting for a fresh normal camera'
        end
        -- Error14/15/16 describe a forwarded transient pose/space/graph gate.
        -- Native ownership remains authoritative; do not tear down for a gate.
        self.phase='active';return true
    end
    return self
end
Camera.Adapter=Adapter
return Camera
