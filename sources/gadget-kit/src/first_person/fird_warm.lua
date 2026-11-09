-- A single bounded stock-camera transaction initializes packed FP code before
-- pose-helper preparation. The backend owns the exact native request and exit.
local M={}
function M.new(b,clock,foreign,frame)
    assert(type(b)=='table'and type(clock)=='function'and type(foreign)=='function'and type(frame)=='function',
        'Native FP initialization dependencies unavailable')
    local self={phase='idle'}
    local lease,expected,started_frame,finished_frame,deadline,failure
    local function invoke(name,...)
        local ok,a,c=pcall(b[name],b,...)
        if not ok then return false,nil,tostring(a)end
        return true,a,c
    end
    local function tick(fn)
        local ok,value=pcall(fn)
        if not ok or type(value)~='number'or value~=value or value<0 or value==math.huge then return nil end
        return value
    end
    local function held()local ok,value=pcall(foreign);return not ok or value~=false end
    local function identity(s)return s and(s.identity or s.weapon_identity)end
    local function same(a,c)return a and c and identity(a)==identity(c)and a.player_identity==c.player_identity end
    local function neutral(s,hint)
        return s and s.safe==true and not s.controller_active and not s.aiming and not s.shoulder_aim and not s.reloading
            and(not hint or hint.neutral~=false)
    end
    local function ready()
        local ok,value,why=invoke('camera_ready')
        return ok and value==true,why or(not ok and 'FP initialization validation failed'or 'FP code is not initialized')
    end
    local function clear()
        lease,expected,started_frame,finished_frame,deadline,failure=nil,nil,nil,nil,nil,nil
        self.phase='idle'
    end
    local function cleanup()
        local owned=lease or b.warm_lease
        if not owned then lease=nil;return true end
        local ok,done,why=invoke('warm_finish',owned)
        if not ok or done~=true then return false,why or 'Native FP initialization cleanup is pending'end
        lease=nil;return true
    end
    function self:is_clean()return lease==nil and b.warm_lease==nil end
    function self:stop()
        self.phase='cleanup'
        local done,why=cleanup();if not done then return false,why end
        clear();return true
    end
    function self:update(hint)
        if self.phase=='failed'then error(failure or 'Native FP initialization failed',0)end
        local now,current_frame=tick(clock),tick(frame)
        if not now or not current_frame then
            if lease or b.warm_lease then failure='Native FP initialization clock or frame unavailable';self.phase='cleanup'
            else return false,'Waiting for the initialization clock'end
        end
        if self.phase=='idle'and b.warm_lease then
            lease=b.warm_lease;expected=lease.origin;started_frame=current_frame;deadline=now and now+2;self.phase='cleanup'
        end
        if self.phase=='cleanup'then
            local done,why=cleanup();if not done then return false,why end
            if failure then self.phase='failed';error(failure,0)end
            finished_frame=current_frame;self.phase='settle'
            return false,'Waiting for the normal camera after initialization'
        end
        if self.phase=='idle'then local initialized=ready();if initialized then return true end end
        local called,s,why=invoke('snapshot')
        if not called or not s then
            if lease and now and deadline and now>=deadline then
                failure=why or 'Native FP initialization owner remained unavailable';self.phase='cleanup'
                return self:update(hint)
            end
            return false,why or 'Waiting for the local initialization owner'
        end
        if self.phase=='idle'then
            if held()or not neutral(s,hint)or s.camera_kind~=4 or hint and not same(s,hint)then
                return false,'Waiting for a safe released normal camera to initialize FP'
            end
            local ok,accepted,value=invoke('warm_start',s)
            if not ok or accepted~=true or type(value)~='table'then
                lease=b.warm_lease;failure=value or 'Native FP initialization entry was refused';self.phase='cleanup'
                return self:update(hint)
            end
            lease=value;expected=s;started_frame=current_frame;deadline=now+2;self.phase='warming'
            if lease.cleanup_only then failure=lease.error or 'Native FP initialization entry is uncertain';self.phase='cleanup' end
            return false,'Initializing the native first-person camera'
        end
        if self.phase=='warming'then
            local interrupted=held()or not same(s,expected)or not neutral(s,hint)or(s.camera_kind~=4 and s.camera_kind~=6)
            if now>=deadline then failure='Native FP initialization timed out';self.phase='cleanup'
            elseif interrupted then self.phase='cleanup'
            elseif current_frame<=started_frame then return false,'Waiting for the next native initialization frame'
            else
                local initialized,problem=ready()
                if not initialized then failure=problem or 'Native FP evaluator remained uninitialized'end
                self.phase='cleanup'
            end
            return self:update(hint)
        end
        if self.phase=='settle'then
            if held()or not same(s,expected)or not neutral(s,hint)or s.camera_kind~=4 or not current_frame or current_frame<=finished_frame then
                return false,'Waiting for the released normal camera after initialization'
            end
            local initialized,problem=ready()
            if not initialized then failure=problem or 'Native FP code remained uninitialized';self.phase='failed';error(failure,0)end
            self.phase='complete';return true
        end
        if self.phase=='complete'then return ready()end
        return false,'Waiting for native FP initialization'
    end
    return self
end
return M
