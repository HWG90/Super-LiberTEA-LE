-- Own user intent and bounded first-person calibration attempts. Native camera
-- calls, pose readiness and all restoration remain with the existing owners.
local M={}
function M.new(callbacks,clock)
    assert(type(callbacks)=='table'and type(clock)=='function','Fird automatic entry callbacks required')
    for _,name in ipairs({'stop','target','foreign','running','cached','begin_fp','sample','capture','enter'})do
        assert(type(callbacks[name])=='function','Fird automatic entry callback unavailable: '..name)
    end
    local self={phase='off'}
    local desired,tick,last_time=false,0,nil
    local expected,reference,clean_tick,deadline,retry_at,blocked,candidate,candidate_tick,active_owner
    local reason
    local function invoke(name,...)
        local ok,a,b=pcall(callbacks[name],...)
        if not ok then return false,nil,tostring(a)end
        return true,a,b
    end
    local function identity(s)
        if type(s)~='table'then return nil end
        for _,name in ipairs({'player_identity','weapon_identity','weapon_key'})do
            if type(s[name])~='string'or s[name]==''then return nil end
        end
        return {player_identity=s.player_identity,weapon_identity=s.weapon_identity,weapon_key=s.weapon_key}
    end
    local function same(a,b)
        return a and b and a.player_identity==b.player_identity and a.weapon_identity==b.weapon_identity
            and a.weapon_key==b.weapon_key
    end
    local function released(s,kind)
        return identity(s)and s.safe==true and s.neutral==true and s.camera_kind==kind and s.controller_active==false
    end
    local function cached_ready(s)return s.known==true and s.cached_ready~=false end
    local function matches(c,s)
        return type(c)=='table'and c.identity==s.player_identity and c.weapon_identity==s.weapon_identity
            and c.weapon_key==s.weapon_key
    end
    local function cleanup(message,now)
        self.phase='cleanup';expected,reference,clean_tick,deadline,candidate,candidate_tick=nil,nil,nil,nil,nil,nil
        retry_at=now and now+.25 or nil;reason=message
    end
    local function fail(message,now,owner)
        blocked=identity(owner)or expected or blocked
        cleanup(message,now)
        return false,message
    end
    local function foreign()
        local ok,value,why=invoke('foreign')
        if not ok then return nil,why end
        if type(value)~='boolean'then return nil,'Camera ownership status unavailable'end
        return value==true
    end
    local function target()
        local ok,value,why=invoke('target')
        if not ok then return nil,why end
        return value
    end
    local function enter(c,s,now)
        local fresh,why=target();local taken,problem=foreign()
        if why or taken==nil then return fail(why or problem,now,s)end
        if not same(identity(s),identity(fresh))or not released(fresh,4)or taken then
            cleanup('Waiting for a stable released weapon camera',now);return true
        end
        if not matches(c,fresh)then return fail('First-person reference belongs to another weapon',now,s)end
        local ok,accepted,problem=invoke('enter',c)
        if not ok or accepted~=true then return fail(problem or 'Fird Person entry was refused',now,s)end
        expected,reference,clean_tick,deadline,candidate,candidate_tick=nil,nil,nil,nil,nil,nil
        active_owner=identity(fresh)
        self.phase='active';reason=nil;return true
    end
    function self:is_enabled()return desired end
    function self:is_pending()return desired and self.phase~='active'end
    function self:uses_fp()return desired and self.phase=='capture'end
    function self:status()
        if not desired then return 'Fird Person off'end
        if reason then return 'Fird Person: '..reason end
        local labels={cleanup='finishing camera cleanup',wait='waiting for a safe released weapon camera',initialize='initializing the native camera',
            capture='capturing first-person placement',handoff='switching to Fird Person',active='active',blocked='waiting for another weapon'}
        return 'Fird Person: '..(labels[self.phase]or self.phase)
    end
    function self:request()
        if desired then return true end
        desired=true;blocked=nil;last_time=nil;cleanup(nil);return true
    end
    function self:cancel()
        desired=false;self.phase='off';expected,reference,clean_tick,deadline,retry_at,blocked,candidate,candidate_tick,active_owner=nil,nil,nil,nil,nil,nil,nil,nil,nil
        last_time,reason=nil,nil;return true
    end
    function self:update()
        if not desired then return true end
        tick=tick+1
        local ok,now=pcall(clock)
        if not ok or type(now)~='number'or now~=now or now<0 or now==math.huge or(last_time and now<last_time)then
            local message='Calibration clock unavailable or moved backwards'
            fail(message,nil,expected)
            -- Clock failure must still retire the currently owned FP lease.
            invoke('stop');return false,message
        end
        last_time=now
        if self.phase=='cleanup'or self.phase=='handoff'then
            local stopping=self.phase
            local called,ready,why=invoke('stop')
            if not called then return false,why end
            if ready~=true then clean_tick=nil;reason=why or 'camera cleanup is pending';return true end
            if not clean_tick then clean_tick=tick;return true end
            if tick<=clean_tick then return true end
            if stopping=='cleanup'then self.phase='wait';clean_tick=nil end
        end
        local s,why=target()
        if why then return fail(why,now,expected)end
        local taken,problem=foreign()
        if taken==nil then return fail(problem,now,s or expected)end
        local current=identity(s)
        if self.phase=='active'then
            local called,running,problem=invoke('running')
            if not called then return fail(problem,now,s)end
            if running~=true then
                if current and active_owner and current.player_identity==active_owner.player_identity then
                    return fail('Placement stopped; change weapon or toggle F11 to retry',now,s)
                end
                cleanup('Waiting for the current player camera',now);return true
            end
            if taken or not released(s,4)or cached_ready(s)then candidate,candidate_tick=nil,nil;return true end
            if not same(candidate,current)then candidate=current;candidate_tick=tick;return true end
            if tick>candidate_tick then cleanup('Capturing placement for this weapon',now)end
            return true
        end
        if self.phase=='capture'then
            if not same(expected,current)or taken or not(released(s,6)or released(s,4))then
                cleanup('Waiting for aiming, actions or the weapon change to finish',now);return true
            end
            if now>=deadline then return fail('First-person placement did not become ready; switch weapon or toggle F11 to retry',now,s)end
            local called,ready,token=invoke('sample')
            if not called then return fail(token,now,s)end
            -- Native entry can await the next engine evaluation. Poll only
            -- this attempt; neither an accepted request nor a readiness token
            -- authorizes reading a still-normal third-person weapon pose.
            if s.camera_kind~=6 then reason='waiting for the first-person camera';return true end
            if ready~=true then reason=type(token)=='string'and token or 'waiting for first-person placement to settle';return true end
            if token==nil then return fail('First-person readiness returned no capture token',now,s)end
            local captured,value,problem=invoke('capture',token)
            if not captured or type(value)~='table'then return fail(problem or 'First-person placement capture failed',now,s)end
            if not matches(value,s)then return fail('First-person capture owner or weapon changed',now,s)end
            reference=value;self.phase='handoff';clean_tick=nil;reason=nil;return true
        end
        if self.phase=='handoff'then
            if current and not same(expected,current)then cleanup('Weapon changed before Fird Person entry',now);return true end
            if taken or not released(s,4)then reason='waiting for the released normal weapon camera';return true end
            return enter(reference,s,now)
        end
        if self.phase=='initialize'then
            if not same(expected,current)or taken or not(released(s,4)or released(s,6))then
                cleanup('Waiting for a stable camera during initialization',now);return true
            end
            if now>=deadline then return fail('Native camera initialization timed out',now,s)end
            local called,ready,problem=invoke('initialize',s)
            if not called then return fail(problem,now,s)end
            if ready~=true then reason=problem or'initializing the native camera';return true end
            self.phase='wait';expected=nil;reason=nil
            -- Read a new normal-camera owner on the next host update.
            return true
        end
        -- A hard failure is tied to the complete weapon instance. A genuine
        -- swap (or cancel/request) releases the block without camera churn.
        if blocked then
            if not current or same(blocked,current)then self.phase='blocked';return true end
            blocked=nil;reason=nil;self.phase='wait'
        end
        if taken or not released(s,4)or(retry_at and now<retry_at)then return true end
        if callbacks.initialize then
            local called,ready,problem=invoke('initialize',s)
            if not called then return fail(problem,now,s)end
            if ready~=true then
                self.phase='initialize';expected=current;deadline=now+3;reason=problem
                return true
            end
        end
        if cached_ready(s)then
            local called,c,problem=invoke('cached')
            if not called or not matches(c,s)then return fail(problem or 'Saved first-person reference is unavailable for this weapon',now,s)end
            return enter(c,s,now)
        end
        expected=current;reference=nil
        local called,started,problem=invoke('begin_fp')
        if not called or started~=true then return fail(problem or 'First-person calibration entry was refused',now,s)end
        self.phase='capture';deadline=now+3;reason=nil;return true
    end
    return self
end
return M
