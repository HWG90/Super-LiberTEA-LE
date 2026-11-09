local PORT51=mod.require('src/first_person/compat51.lua')
-- Own the native optic-selection policy together with the visible FOV lease.
-- Saved optic selection and player sensitivity settings stay in the game.
local Host=mod
local Zoom,Adapter={},{}
Adapter.__index=Adapter
function Adapter.new(profile)return setmetatable({profile=profile},Adapter)end
function Adapter:_load()
    if self.library and self.ffi then return self.library end
    local ffi=self.ffi or PORT51.ffi
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'Windows x64 required for native zoom')
    if not pcall(ffi.typeof,'NADZ_Config')then ffi.cdef([[
        typedef struct NADZ_Config {
            uint32_t size,abi;
            uint64_t game,exe,context,camera,avatar_owner,request;
            uint32_t avatar_index,avatar,body,weapon;
            uint64_t reserved;
        } NADZ_Config;
        typedef struct NADZ_Stats {
            uint32_t size,abi,installed,armed,error,reserved;
            uint64_t seen,forwarded,replaced,immediate_applies,binds,ads_forwarded;
            float last_native,last_applied,source_degrees,padding;
        } NADZ_Stats;
        uint32_t NADZ_Validate(const NADZ_Config*);
        uint32_t NADZ_Begin(const NADZ_Config*,uint64_t*);
        uint32_t NADZ_Bind(uint64_t,const NADZ_Config*);
        uint32_t NADZ_Update(uint64_t);
        uint32_t NADZ_End(uint64_t);
        uint32_t NADZ_ReadStats(uint64_t,NADZ_Stats*);
        uint32_t NADZ_Error(void);
    ]])end
    assert(ffi.sizeof('NADZ_Config')==80 and ffi.sizeof('NADZ_Stats')==88,'Zoom helper ABI mismatch')
    self.ffi=ffi
    if not self.library then
        self.library=ffi.load(Host.dir..'/'..self.profile.library)
        if PORT51.kind(Host.scope)=='table'then
            Host.scope.native_ads_zoom_libraries=Host.scope.native_ads_zoom_libraries or {}
            table.insert(Host.scope.native_ads_zoom_libraries,self.library)
        end
    end
    return self.library
end
function Adapter:_error(operation)
    return operation..' failed (native zoom code '..tostring(PORT51.number(self:_load().NADZ_Error()))..')'
end
function Adapter:_config(config)
    self:_load()
    local c=self.ffi.new('NADZ_Config');c.size=80;c.abi=self.profile.abi
    for _,key in ipairs({'game','exe','context','camera','avatar_owner','request','avatar_index','avatar','body','weapon'})do
        c[key]=assert(config[key],key..' unavailable')
    end
    return c
end
function Adapter:validate(config)
    if self.owned then return false,'Zoom generation still requires cleanup'end
    if self:_load().NADZ_Validate(self:_config(config))~=1 then return false,self:_error('Zoom validation')end
    return true
end
function Adapter:owned_handle()return self.owned end
function Adapter:begin(config)
    if self.owned then return false,'Zoom generation still requires cleanup'end
    local lib=self:_load();local handle={owner=self,generation=self.ffi.new('uint64_t[1]')}
    local called,code=pcall(lib.NADZ_Begin,self:_config(config),handle.generation)
    if PORT51.number(handle.generation[0])~=0 then self.owned=handle end
    if not called then return false,'Zoom arm result uncertain: '..tostring(code)end
    if code~=1 then return false,self:_error('Zoom arm')end
    if not self.owned then return false,'Zoom arm returned no owned generation'end
    return true,handle
end
function Adapter:bind(handle,config)
    if handle~=self.owned or handle.owner~=self then return false,'Zoom handle is not owned'end
    if self:_load().NADZ_Bind(handle.generation[0],self:_config(config))~=1 then return false,self:_error('Zoom binding')end
    return true
end
function Adapter:update(handle)
    if handle~=self.owned or handle.owner~=self then return false,'Zoom handle is not owned'end
    if self:_load().NADZ_Update(handle.generation[0])~=1 then return false,self:_error('Zoom update')end
    return true
end
function Adapter:stats(handle)
    if handle~=self.owned or not handle or handle.owner~=self then return nil,'Zoom handle is not owned'end
    local lib=self:_load();local s=self.stats_buffer or self.ffi.new('NADZ_Stats');self.stats_buffer=s
    s.size=88;s.abi=self.profile.abi
    if lib.NADZ_ReadStats(handle.generation[0],s)~=1 then return nil,self:_error('Zoom statistics')end
    if PORT51.number(s.size)~=88 or PORT51.number(s.abi)~=self.profile.abi then return nil,'Zoom statistics ABI changed'end
    return {armed=s.armed~=0,installed=s.installed~=0,error=PORT51.number(s.error)}
end
function Adapter:finish(handle)
    if handle and handle.owner==self and handle.disarmed then return true end
    if handle~=self.owned or not handle or handle.owner~=self then return false,'Zoom handle is not owned'end
    if self:_load().NADZ_End(handle.generation[0])~=1 then return false,self:_error('Zoom cleanup')end
    handle.disarmed=true;self.owned=nil;return true
end
local function invoke(target,key,...)
    local ok,a,b=pcall(target[key],target,...)
    if not ok then return false,tostring(a)end
    return a,b
end
function Zoom.new(backend,log,helper)
    helper=helper or Adapter.new(Host.require('src/first_person/profile.lua').zoom)
    log=log or function()end
    local self={phase='idle'}
    local function fail(why)
        self.phase='cleanup_pending';self.error=tostring(why);log('FPV zoom: '..self.error)
        return false,self.error
    end
    function self:is_clean()return self.handle==nil and self.lease==nil end
    function self:result()return {phase=self.phase,cleanup_pending=self.phase=='cleanup_pending',error_message=self.error}end
    function self:stop()
        -- End the selector first, before re-enabling the legacy compensation.
        if self.handle then
            local ok,why=invoke(helper,'finish',self.handle)
            if ok~=true then return fail(why)end
            self.handle=nil
        end
        if self.lease then
            local ok,why=invoke(backend,'set_pose_zoom_policy',self.lease,false)
            -- An ended/replaced pose lease cannot still apply old compensation.
            local a=self.lease.alignment
            if ok~=true and not self.lease.done and not(a and a.ended)and backend.alignment_lease==self.lease then return fail(why)end
            self.lease=nil
        end
        self.request,self.weapon=nil,nil;self.phase='idle';return true
    end
    function self:shutdown()self.closing=true;return self:stop()end
    function self:preflight()
        if not self:is_clean()then return false,'Zoom cleanup is pending'end
        local config,why=invoke(backend,'fov_config')
        if PORT51.kind(config)~='table'then return false,why end
        return invoke(helper,'validate',config)
    end
    function self:update(controller)
        if self.phase=='cleanup_pending'then return self:stop()end
        local result=controller:result();local lease=controller.lease
        if self.closing or not controller:is_enabled()or result.mode~='pose_offset'or result.phase~='running'or not lease then return self:stop()end
        if self.lease and self.lease~=lease then
            local ok,why=self:stop();if ok~=true then return false,why end
        end
        if not self.handle then
            local config,why=invoke(backend,'fov_config',lease)
            if PORT51.kind(config)~='table'then return fail(why)end
            local ok,value=invoke(backend,'set_pose_zoom_policy',lease,true)
            if ok~=true then return fail(value)end
            self.lease=lease
            ok,value=invoke(helper,'begin',config)
            self.handle=ok==true and value or invoke(helper,'owned_handle')or nil
            if ok~=true or not self.handle then self:stop();return fail(value or 'Zoom arm refused')end
            self.request,self.weapon=config.request,config.weapon
        end
        local ok,why=invoke(helper,'update',self.handle)
        if ok~=true then self:stop();return fail(why)end
        local stats;stats,why=invoke(helper,'stats',self.handle)
        if PORT51.kind(stats)~='table'or stats.armed~=true or stats.error~=0 then self:stop();return fail(why or 'Native zoom policy disarmed')end
        self.phase,self.error='active',nil;return true
    end
    return self
end
function Zoom.attach(fov,backend,log,helper)
    local zoom=Zoom.new(backend,log,helper);local group={}
    function group:is_clean()return fov:is_clean()and zoom:is_clean()end
    function group:result()local result=fov:result();result.zoom=zoom:result();return result end
    function group:status()return fov:status()end
    for _,operation in ipairs({'stop','shutdown','preflight'})do
        local key=operation
        group[key]=function()
            local a,why=invoke(zoom,key);local b,other=invoke(fov,key)
            if a~=true then return false,why end
            return b,other
        end
    end
    function group:update(controller)
        local ok,why=zoom:update(controller)
        if ok~=true then fov:stop();return false,why end
        ok,why=fov:update(controller)
        if ok~=true then zoom:stop()end
        return ok,why
    end
    return group
end
Zoom.Adapter=Adapter
return Zoom
