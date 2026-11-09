local PORT51=mod.require('src/first_person/compat51.lua')
local Base=mod.require('src/first_person/fov.lua')
-- Reuse the existing FOV dispatch lease and its generation/cleanup machinery.
-- FirdPerson holds the captured display lens only on the owned normal camera;
-- native ADS keeps its own projection throughout the handoff.
local M,Adapter={},{}
Adapter.__index=Adapter
setmetatable(Adapter,{__index=Base.Adapter})
function Adapter.new(profile,clock)
    return setmetatable(Base.Adapter.new(profile,clock),Adapter)
end
function Adapter:_config(config)
    local c=Base.Adapter._config(self,config)
    c.reserved=0 -- Fird retains its separate native ADS passthrough policy.
    return c
end
function Adapter:_load()
    local library=Base.Adapter._load(self)
    if not pcall(self.ffi.typeof,'NADSF_FirdBindings')then self.ffi.cdef([[
        typedef struct NADSF_FirdBindings { uint32_t marker; } NADSF_FirdBindings;
        uint32_t NADSF_ValidateFird(const NADSF_Config *);
        uint32_t NADSF_BeginFird(const NADSF_Config *,float,uint64_t *);
        uint32_t NADSF_BindFird(uint64_t,uint64_t);
    ]])end
    return library
end
function Adapter:validate(config)
    self:_invalidate_stats()
    if self.owned then return false,'FirdPerson FOV cleanup remains pending'end
    if self:_load().NADSF_ValidateFird(self:_config(config))~=1 then
        return false,self:_error('FirdPerson FOV validation')
    end
    return true
end
function Adapter:begin(config,lens)
    self:_invalidate_stats()
    if self.owned then return false,'FirdPerson FOV cleanup remains pending'end
    local library=self:_load();local c=self:_config(config)
    local handle={owner=self,disarmed=false,generation=self.ffi.new('uint64_t[1]')}
    local called,result=pcall(library.NADSF_BeginFird,c,lens,handle.generation)
    if PORT51.number(handle.generation[0])~=0 then self.owned=handle end
    if not called then return false,'FirdPerson FOV arm result uncertain: '..tostring(result)end
    result=PORT51.number(result)
    if(result==1 or result==2)and not self.owned then return false,'FirdPerson FOV arm returned no owned generation'end
    if result~=1 then return false,self:_error(result==2 and 'FirdPerson FOV partial installation cleanup'or'FirdPerson FOV arm')end
    return true,handle
end
function Adapter:bind(handle,config)
    self:_invalidate_stats()
    if PORT51.kind(handle)~='table'or handle.owner~=self or self.owned~=handle or handle.disarmed then
        return false,'FirdPerson FOV bind handle is not owned'
    end
    if self:_load().NADSF_BindFird(handle.generation[0],config.request)~=1 then
        return false,self:_error('FirdPerson FOV camera binding')
    end
    return true
end
local function invoke(target,name,...)
    local called,a,b=pcall(target[name],target,...)
    if not called then return nil,tostring(a)end
    return a,b
end
local function valid_lens(lens)
    return PORT51.kind(lens)=='number'and lens==lens and lens>=math.rad(10)and lens<=math.rad(170)
end
function M.new(backend,log,helper,clock)
    if not helper then helper=Adapter.new(assert(mod.require('src/first_person/profile.lua').fov),clock)end
    local self={handle=nil,phase='idle',lensmatching=false,last={}}
    log=log or function()end
    local function problem(why)
        self.fault=tostring(why);log('FirdPerson FOV: '..self.fault);return false,self.fault
    end
    local function collect()
        local stats,why=invoke(helper,'stats',self.handle)
        if PORT51.kind(stats)~='table'then return false,why or'FirdPerson FOV statistics unavailable'end
        self.last=stats
        if stats.armed~=true or(stats.error and stats.error~=0)then return false,'FirdPerson FOV lease lost ownership'end
        return true
    end
    function self:is_clean()return self.handle==nil end
    function self:status()return self.phase..'; captured radians='..tostring(self.lens)end
    function self:result()
        local out={};for k,v in pairs(self.last)do out[k]=v end
        out.phase,out.cleanup_pending,out.error_message=self.phase,self.phase=='cleanup_pending',self.fault
        return out
    end
    function self:stop()
        self.lensmatching=false
        if self.handle then
            self.phase='cleanup_pending'
            local done,why=invoke(helper,'finish',self.handle)
            if done~=true then return problem(why or'FirdPerson FOV cleanup remains pending')end
        end
        self.handle,self.bound_request,self.player,self.lens=nil,nil,nil,nil
        self.phase='idle';return true
    end
    local function failed(why)
        self.lensmatching=false;self:stop();return problem(why)
    end
    function self:start(capture)
        if self.handle then return false,'FirdPerson FOV cleanup remains pending'end
        local lens=capture and(capture.source_fov or(capture.projection and capture.projection.fov))
        if not valid_lens(lens)then return false,'FirdPerson capture requires a finite10..170degree lens'end
        local s,why=invoke(backend,'player_snapshot')
        if not s or not s.safe or s.camera_kind~=4 or s.controller_active
            or s.player_identity~=capture.identity then return false,why or'FirdPerson FOV player/camera changed'end
        local config,reason=invoke(backend,'fird_fov_config',s)
        if PORT51.kind(config)~='table'then return false,reason or'FirdPerson normal camera unavailable'end
        local valid,problem_text=invoke(helper,'validate',config)
        if valid~=true then return false,problem_text end
        local done,handle=invoke(helper,'begin',config,lens)
        if done==true then self.handle=handle else self.handle=invoke(helper,'owned_handle')end
        if done~=true or not self.handle then return failed(handle or'FirdPerson FOV lease was not accepted')end
        self.player,self.lens,self.bound_request=capture.identity,lens,config.request
        local healthy,health_reason=collect();if not healthy then return failed(health_reason)end
        self.phase,self.fault,self.lensmatching='active',nil,true
        return true
    end
    function self:update(s)
        if not self.handle then return false,'FirdPerson FOV lease is not active'end
        if self.phase=='cleanup_pending'then return failed('FirdPerson FOV cleanup remains pending')end
        if not s then s=invoke(backend,'player_snapshot')end
        if not s or s.player_identity~=self.player then return failed('FirdPerson FOV player changed')end
        local healthy,why=collect();if not healthy then return failed(why)end
        if not s.safe or s.camera_kind~=4 or s.controller_active then
            self.phase,self.lensmatching='native action',false;return true
        end
        local config,reason=invoke(backend,'fird_fov_config',s)
        if PORT51.kind(config)~='table'then return failed(reason or'FirdPerson normal camera unavailable')end
        if not self.lensmatching or self.bound_request~=config.request then
            local done,bind_reason=invoke(helper,'bind',self.handle,config)
            if done~=true then return failed(bind_reason or'FirdPerson FOV binding failed')end
            self.bound_request=config.request
        end
        healthy,why=collect();if not healthy then return failed(why)end
        self.phase,self.fault,self.lensmatching='active',nil,true
        return true
    end
    return self
end
M.Adapter=Adapter
return M
