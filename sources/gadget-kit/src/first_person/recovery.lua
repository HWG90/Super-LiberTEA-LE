-- Pure bounded recovery policy. Native leases remain owned by their managers.
-- A retry is authorized only by typed read-failure evidence, acknowledged
-- cleanup, and a fresh same-player proof; strings never grant that authority.
local M={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
local core={camera=true,fov=true}
local function positive(proof)
    return proof and proof.fresh==true and proof.safe==true and proof.same_player==true and proof.foreign==false
end
function M.classify(name,state,clean,proof)
    state=type(state)=='table'and state or{}
    proof=type(proof)=='table'and proof or{}
    if clean~=true then return 'cleanup'end
    if state.failure_kind=='temporary_read'and state.failure_native_error==3
        and positive(proof)then return 'retry'end
    -- Clean optional policies can be unavailable without disabling the camera.
    -- They remain disabled for this explicit FP session, including unknown
    -- errors. A failed optional policy is never silently rearmed.
    if not core[name]then return 'unavailable'end
    return 'fatal'
end
function M.new(options)
    options=options or{}
    local maximum=options.max_attempts or 4
    local base,cap=options.base_delay or .25,options.max_delay or 2
    local window=options.stable_seconds or 2
    assert(maximum>=1 and maximum<=16 and maximum%1==0)
    assert(finite(base)and base>0 and finite(cap)and cap>=base and cap<=30)
    assert(finite(window)and window>0 and window<=60)
    local self={};local states={};local session=0
    function self:reset()
        states={};session=session+1
    end
    function self:owner_reset()
        -- New-body recovery is not a reason to retry an unsupported/unknown
        -- optional policy. Those remain disabled until explicit off/on.
        local kept={};session=session+1
        for name,row in pairs(states)do
            if row.classification=='unavailable'or row.pending_classification=='unavailable'then
                row=copy(row);row.phase='unavailable';row.next_retry=nil;row.session=session;kept[name]=row
            end
        end
        states=kept
    end
    function self:failure(name,state,clean,proof,now,reason)
        assert(type(name)=='string'and #name<=32 and finite(now))
        local row=states[name]or{attempts=0};states[name]=row
        row.attempts=row.attempts+1;row.stable_since=nil
        row.reason=tostring(reason or 'Presentation policy unavailable'):sub(1,200)
        row.classification=M.classify(name,state,clean,proof)
        row.pending_classification=M.classify(name,state,true,proof)
        row.core=core[name]==true;row.session=session;row.proof_deadline=now+10
        if clean~=true then row.phase='cleanup';row.next_retry=nil
        elseif row.classification=='retry'and row.attempts<maximum then
            row.phase='waiting';row.next_retry=now+math.min(cap,base*2^(row.attempts-1));row.proof_deadline=now+10
        elseif row.classification=='retry'then row.phase='exhausted';row.next_retry=nil
        elseif row.classification=='fatal'then row.phase='fatal';row.next_retry=nil
        else row.phase='unavailable';row.next_retry=nil end
        return copy(row)
    end
    function self:cleanup(name,done,now)
        local row=states[name];if not row then return true end
        assert(finite(now))
        if row.phase~='cleanup'then return true end
        if done~=true then return false end
        row.classification=row.pending_classification
        if row.classification=='retry'and row.attempts<maximum then
            row.phase='waiting';row.next_retry=now+math.min(cap,base*2^(row.attempts-1));row.proof_deadline=now+10
        elseif row.classification=='retry'then row.phase='exhausted'
        elseif row.classification=='fatal'then row.phase='fatal'
        else row.phase='unavailable'end
        return true
    end
    local function action(name,now,advance)
        assert(finite(now));local row=states[name]
        if not row or row.phase=='healthy'then return 'update'end
        if row.phase=='cleanup'then return 'cleanup'end
        if row.phase=='waiting'or row.phase=='waiting_proof'then
            if now<row.next_retry then return 'wait'end
            if advance then row.phase='retrying'end
            return 'update'
        end
        if row.phase=='retrying'then return 'update'end
        return row.phase
    end
    function self:action(name,now)return action(name,now,true)end
    -- Healthy policies never need a player read just to return true below.
    -- Callers still obtain a fresh proof immediately before an actual retry.
    function self:needs_proof(name)
        local row=states[name]
        return row~=nil and row.phase=='retrying'
    end
    function self:has_policies()return next(states)~=nil end
    function self:revalidate(name,proof,now)
        local row=states[name];if not row or row.phase~='retrying'then return true end
        assert(finite(now))
        if positive(proof)then return true end
        if now>=row.proof_deadline then row.phase='exhausted';row.next_retry=nil
        else row.phase='waiting_proof';row.next_retry=now+.25 end
        return false
    end
    function self:success(name,now,active)
        assert(finite(now));local row=states[name];if not row then return end
        if row.phase~='retrying'and row.phase~='healthy'then return end
        if active~=true then return end -- waiting for a weapon is not recovery proof
        row.phase='healthy';row.stable_since=row.stable_since or now
        if now>=row.stable_since and now-row.stable_since>=window then states[name]=nil end
    end
    function self:blocks_view(now)
        for name,row in pairs(states)do if row.core then
            local wanted=action(name,now,false)
            if wanted~='update'then return true,name,wanted end
        end end
        return false
    end
    function self:snapshot()
        local out={session=session,policies={}}
        for name,row in pairs(states)do out.policies[name]=copy(row)end
        return out
    end
    return self
end
return M
