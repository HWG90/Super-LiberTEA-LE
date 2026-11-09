local PORT51=mod.require('src/first_person/compat51.lua')
-- An optional lease of the game's existing complete native camera. Backend
-- owns entry/exit validation; a real gameplay ADS takeover always wins.
local M={}
local function invoke(target,name,...)
    local ok,a,b=pcall(target[name],target,...)
    if not ok then return nil,tostring(a)end
    return a,b
end
function M.new(backend,log,options)
    options=options or{};log=log or function()end
    assert(PORT51.kind(options.prepare)=='function','Native ADS needs a render-release callback')
    local self={lease=nil,phase='idle'};local blocked
    local function problem(why)
        self.fault=tostring(why);log('Fird Person native ADS: '..self.fault);return false,self.fault
    end
    local function foreign()
        if not options.foreign then return false end
        local ok,value=pcall(options.foreign);if not ok then return nil,tostring(value)end
        return value==true
    end
    function self:is_clean()return self.lease==nil end
    function self:status()return self.phase end
    function self:result()return{phase=self.phase,owned=self.lease~=nil,cleanup_pending=self.phase=='cleanup_pending',error_message=self.fault}end
    function self:stop()
        if not self.lease then self.phase='idle';return true end
        self.phase='cleanup_pending'
        local done,why=invoke(backend,'release',self.lease)
        if done~=true then return problem(why or'Native ADS cleanup is pending')end
        self.lease=nil;self.phase='idle';return true
    end
    function self:update(enabled,mode)
        local s,why=invoke(backend,'snapshot')
        local taken,issue=foreign()
        if taken==nil then self:stop();return problem(issue)end
        local requested=enabled==true and mode=='native'and taken~=true
        if not requested then blocked=nil end
        if self.lease then
            if self.phase=='cleanup_pending'or self.lease.cleanup_only or self.lease.error then return self:stop()end
            local origin=self.lease.origin
            local own=s and origin and s.identity==origin.identity and s.player_identity==origin.player_identity
                and s.record==self.lease.request and s.camera_kind==6
            -- A user/game ADS controller now owns its own camera semantics.
            -- Backend.release marks this takeover retired without native exit.
            if not requested or not own or not s.safe or not s.shoulder_aim or s.aiming or s.controller_active then
                local done,problem_text=self:stop();if done~=true then return false,problem_text end
            else self.phase='active';return true end
        end
        if not requested or not s or not s.safe or s.camera_kind~=4 or not s.shoulder_aim or s.aiming or s.controller_active then
            if not s or not s.shoulder_aim then blocked=nil end
            self.phase='idle';return true
        end
        if blocked==s.identity then self.phase='waiting for aim release';return true end
        local prepared,accepted,problem_text=pcall(options.prepare,s)
        if not prepared or accepted~=true then
            self.phase='waiting for render cleanup';return true,tostring(prepared and problem_text or accepted)
        end
        -- The callback can release presentation managers. Re-read both camera
        -- ownership and aim before asking Backend to enter a native request.
        local after,read_problem=invoke(backend,'snapshot');taken,issue=foreign()
        if taken==nil then return problem(issue)end
        if not after or after.identity~=s.identity or after.player_identity~=s.player_identity or after.record~=s.record
            or not after.safe or after.camera_kind~=4 or not after.shoulder_aim or after.aiming or after.controller_active or taken then
            self.phase='waiting for aim';return true,read_problem
        end
        local entered,lease=invoke(backend,'enter',after)
        if entered~=true or PORT51.kind(lease)~='table'then
            blocked=s.identity;self.phase='waiting for aim release';return true,lease or'Native ADS entry was refused'
        end
        -- Retain even uncertain/cleanup-only entry so no native request leaks.
        self.lease=lease
        if lease.error or lease.cleanup_only then
            blocked=s.identity;return self:stop()
        end
        self.phase,self.fault='active',nil;return true
    end
    return self
end
return M
