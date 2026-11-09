-- Use the existing Lua render boundary. This module owns only its listener or
-- forwarding wrapper; camera, pose and frame ownership stay with the caller.
local M={}
function M.new(globals,callback,log,deps)
    assert(type(globals)=='table'and type(callback)=='function','Fird render callback unavailable')
    deps=deps or{};log=log or function()end
    local current,busy
    local self={frames=0,skipped=0,reentrant=0,errors=0,phase='off'}
    -- self stays alive through every registered callback/tombstone, so its
    -- address cannot be recycled into another active listener's identifier.
    local id='goose_fird_pose.'..tostring(self)
    local function cleanup(lease)
        lease.armed=false
        if lease.unsubscribe then
            local ok,value=pcall(lease.unsubscribe)
            if not ok or value==false then
                lease.pending=true
                return false,ok and'Render unsubscribe remains pending'or tostring(value)
            end
            lease.unsubscribe=nil
        elseif lease.wrapper and rawget(globals,'render')==lease.wrapper then
            rawset(globals,'render',lease.previous)
        end
        -- Another wrapper may retain ours. Its private lease stays disarmed
        -- even if this manager starts a new registration later.
        lease.pending=false
        if current==lease then current=nil end
        return true
    end
    local function failure(lease,problem)
        local reason=tostring(problem)
        self.errors=self.errors+1;self.last_error=reason
        local owned=current==lease
        lease.armed=false
        if owned then
            self.reason=reason;self.phase='failed'
            local done,why=cleanup(lease)
            if not done then self.phase='cleanup pending';self.cleanup_reason=why end
        end
        pcall(log,'Fird render disabled: '..reason)
    end
    local function eligible(...)
        if deps.active and deps.active()~=true then return false end
        if deps.foreign and deps.foreign()~=false then return false end
        return true,callback(...)
    end
    local function invoke(lease,...)
        if current~=lease or not lease.armed or not lease.ready then return end
        if busy then self.reentrant=self.reentrant+1;return end
        if lease.bridge and(rawget(globals,'HUDRenderBridge')~=lease.bridge
            or lease.bridge.api~=1 or lease.bridge.subscribe~=lease.subscribe)then
            failure(lease,'Existing render bridge owner changed');return
        end
        busy=true
        local ok,ran,accepted,why=pcall(eligible,...)
        busy=false
        if not ok then failure(lease,ran)
        elseif ran then
            self.frames=self.frames+1
            if accepted==false then failure(lease,why or'Fird render placement refused')end
        else self.skipped=self.skipped+1 end
    end
    function self:start()
        if current then
            if current.armed and current.ready then return true end
            return false,self.cleanup_reason or'Render cleanup remains pending'
        end
        local bridge=rawget(globals,'HUDRenderBridge')
        local previous=rawget(globals,'render')
        if bridge~=nil and(type(bridge)~='table'or bridge.api~=1 or type(bridge.subscribe)~='function')then
            return false,'Existing render bridge API is unavailable'
        end
        if type(previous)~='function'then return false,'Game render callback unavailable'end
        local lease={armed=true,ready=false,previous=previous}
        current=lease;self.reason,self.cleanup_reason=nil,nil
        if bridge then
            lease.bridge,lease.subscribe=bridge,bridge.subscribe
            local ok,release=pcall(lease.subscribe,id,function(...)invoke(lease,...)end)
            if not ok or type(release)~='function'then
                -- A provider may have retained the callback before failing.
                -- It remains a no-op; no private listener table is modified.
                lease.armed=false;current=nil;self.phase='failed'
                self.reason=ok and'Render bridge did not return an unsubscribe function'or tostring(release)
                return false,self.reason
            end
            lease.unsubscribe=release;self.source='bridge'
        else
            local saved=previous
            lease.wrapper=function(...)
                invoke(lease,...)
                return saved(...)
            end
            rawset(globals,'render',lease.wrapper);self.source='wrapper'
        end
        lease.ready=true;self.phase='running'
        return true
    end
    function self:stop()
        if not current then return true end
        local done,why=cleanup(current)
        if done then self.phase='off';self.cleanup_reason=nil
        else self.phase='cleanup pending';self.cleanup_reason=why end
        return done,why
    end
    function self:is_clean()return current==nil end
    function self:result()
        return{active=current~=nil and current.armed and current.ready or false,clean=current==nil,
            source=self.source,phase=self.phase,reason=self.reason,cleanup_reason=self.cleanup_reason,
            frames=self.frames,skipped=self.skipped,reentrant=self.reentrant,errors=self.errors,last_error=self.last_error}
    end
    return self
end
return M
