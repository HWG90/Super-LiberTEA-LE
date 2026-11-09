-- Persistent intent and compare-and-restore ownership for native ready poses.
-- The source owns all engine access and the final native-call authority.
local M={main_pose=true}
local COUNTS={[4]=78,[24]=10,[25]=4}
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
local function context_ok(c)
    return type(c)=='table'and c.phase=='qualified_update'and finite(c.tick)and c.tick>=1 and c.tick%1==0
end
local function action(s)
    return s.actualAim==true or s.reload==true or s.sprint==true or s.firing==true or s.foreign==true or s.ads==true or s.ADS==true
        or s.weapon_transition==true
end
local function eligible(s)return s.supported~=false and s.safeNormal4==true and not action(s)end
local function carry_eligible(s)
    return s.supported~=false and s.safeNormal4==true and not(s.actualAim or s.reload or s.sprint
        or s.foreign or s.ads or s.ADS or s.weapon_transition)
end
local function cohort(s)
    local l=s.layers
    return type(l)=='table'and(l[4]==67 or l[4]==59)and(l[24]==0 or l[24]==1 or l[24]==5 or l[24]==6)
        and(l[25]==3 or l[25]==1)
end
local function target(s)
    local l=s.layers
    return type(l)=='table'and l[4]==59 and(l[24]==1 or l[24]==6)and l[25]==1
end
function M.new(options)
    options=options or{}
    assert(type(options.source_factory)=='function','Ready-pose source factory unavailable')
    local maximum=options.max_reapplications==nil and 0 or options.max_reapplications
    local retry=options.retry_ticks==nil and 30 or options.retry_ticks
    assert(finite(maximum)and maximum%1==0 and maximum>=0 and maximum<=3,'Ready-pose reapplication limit must be0through3')
    assert(finite(retry)and retry%1==0 and retry>=1 and retry<=600,'Ready-pose retry delay must be1through600updates')
    local self={desired=false,phase='off',reason='off',last_tick=0,source=nil,lease=nil,retired_layers={},
        applied_once=false,reapplications=0,churn_blocked=false,
        counters={factory_calls=0,factory_failures=0,apply_calls=0,restore_calls=0,source_calls=0,
            applied_layers=0,restored_layers=0,reapplications=0,native_overwrites=0,layer_retirements=0,
            retirements=0,action_intervals=0,activations=0,errors=0}}
    local last_context,admission_tick
    local function state(phase,reason)
        local changed=self.phase~=phase or self.reason~=reason
        self.phase=phase;self.reason=reason
        if changed and type(options.log)=='function'then pcall(options.log,reason,phase)end
    end
    local function reset_budget()
        self.applied_once=false;self.reapplications=0;self.churn_blocked=false;self.retired_layers={}
    end
    local function account_calls()
        if self.source and finite(self.source.calls)and self.source.calls>=0 then
            local previous=self.accounted_calls or 0
            if self.source.calls>previous then self.counters.source_calls=self.counters.source_calls+self.source.calls-previous end
            self.accounted_calls=self.source.calls
        end
    end
    local function drop_source()
        assert(not self.lease,'Ready-pose cleanup cannot discard owned layers')
        account_calls();self.source=nil;self.owner=nil;self.accounted_calls=nil;self.wanted=nil;self.variant=nil;self.weapon_token=nil
        admission_tick=nil
    end
    local function invoke(name,...)
        local ok,a,b=pcall(self.source[name],self.source,...)
        account_calls()
        if not ok then return nil,tostring(a)end
        return a,b
    end
    local function error_state(reason)
        self.last_error=tostring(reason or'Native pose operation was not acknowledged')
        self.counters.errors=self.counters.errors+1;self.desired=false;self.restart_pending=false
        self.need_cleanup=self.lease~=nil
        state(self.lease and'cleanup_pending'or'off','source_error')
    end
    local function observe_replacements(s)
        local lease=self.lease
        if not lease or s.ownerToken~=lease.owner or type(s.layers)~='table'then return end
        for layer in pairs(lease.original)do
            local current=s.layers[layer]
            if finite(current)and current%1==0 and current>=0 and current<COUNTS[layer]and current~=self.wanted[layer]then
                lease.original[layer]=nil;self.retired_layers[layer]=current
                self.counters.layer_retirements=self.counters.layer_retirements+1
            end
        end
        if not next(lease.original)then self.lease=nil end
    end
    local function owns_carry(s)
        return self.desired and self.lease and self.lease.original[4]==67 and self.wanted[4]==59
            and not(self.need_cleanup or self.action_open or self.churn_blocked)
            and s.ownerToken==self.owner and s.ownerToken==self.lease.owner
            and self.weapon_token~=nil and s.weapon_token==self.weapon_token and carry_eligible(s)and target(s)
    end
    local function admission(s,context)
        if not owns_carry(s)then return nil,'Owned raised main pose unavailable'end
        local ref,generation=s.body_ref,s.body_generation
        if not finite(ref)or ref%1~=0 or ref<=0 or ref>=0xffffffff
            or not finite(generation)or generation%1~=0 or generation<0 or generation>255
            or math.floor(ref/0x400000)%256~=generation then return nil,'Body generation unavailable'end
        if type(s.ownerToken)~='string'or #s.ownerToken==0 then return nil,'Body owner token unavailable'end
        return{body_ref=ref,body_generation=generation,owner_token=s.ownerToken,tick=context.tick}
    end
    local function cleanup(s,context)
        if not self.lease then return true end
        if s.ownerToken~=self.lease.owner then state('cleanup_pending','owner_mismatch_unproved');return false end
        observe_replacements(s)
        if not self.lease then return true end
        if not eligible(s)then state('cleanup_pending','native_action_or_unsafe');return false end
        if not cohort(s)then state('cleanup_pending','unknown_cohort');return false end
        local changes={}
        for layer,original in pairs(self.lease.original)do
            if s.layers[layer]==self.wanted[layer]and s.layers[layer]~=original then changes[layer]=original end
        end
        if not next(changes)then self.lease=nil;return true end
        local allowed,why=invoke('can_mutate',context,s)
        if allowed~=true then state('cleanup_pending',why or'mutation_phase_unqualified');return false end
        self.counters.restore_calls=self.counters.restore_calls+1
        local done,problem=invoke('restore',changes,s,context)
        if done~=true then error_state(problem);return false end
        for _ in pairs(changes)do self.counters.restored_layers=self.counters.restored_layers+1 end
        self.lease=nil;return true
    end
    local function clean_barrier(tick,reason,renew)
        self.need_cleanup=false;self.barrier_tick=tick
        if renew or self.restart_pending then
            reset_budget();self.restart_pending=false;drop_source();self.next_factory_tick=tick+1
        elseif not self.desired then drop_source()end
        state(not self.desired and'off'or self.churn_blocked and'churn_blocked'or'waiting_reentry',reason)
    end
    function self:request(enabled)
        assert(type(enabled)=='boolean','Ready-pose intent must be Boolean')
        if not enabled then
            admission_tick=nil
            self.desired=false;self.restart_pending=false;self.need_cleanup=self.lease~=nil
            state(self.lease and'cleanup_pending'or'off',self.lease and'stop_requested'or'off')
            return true
        end
        if self.desired then return true end
        self.desired=true;self.counters.activations=self.counters.activations+1
        if self.lease then
            self.restart_pending=true;self.need_cleanup=true;state('cleanup_pending','restart_waiting_for_cleanup')
        else
            drop_source();reset_budget();self.need_cleanup=false;self.action_open=false;self.action_verified=false
            self.next_factory_tick=self.last_tick+1;self.barrier_tick=self.last_tick
            state('waiting_source','requested')
        end
        return true
    end
    function self:stop()self:request(false);return self:is_clean(),self.reason end
    function self:is_clean()return self.lease==nil end
    function self:is_enabled()return self.desired end
    function self:filter_owner(context)
        if not context_ok(context)or context~=last_context or context.tick~=self.last_tick or admission_tick~=context.tick then
            return nil,'Current owned Update acknowledgement required'
        end
        if not self.source then return nil,'Ready-pose source unavailable'end
        local s,why=invoke('snapshot',context)
        if type(s)~='table'or s.retired==true then
            admission_tick=nil;return nil,why or'Body observation unavailable'
        end
        observe_replacements(s)
        local owner,reason=admission(s,context)
        if not owner then admission_tick=nil end
        return owner,reason
    end
    function self:result()
        account_calls()
        return{desired=self.desired,phase=self.phase,reason=self.reason,clean=self:is_clean(),owned=self.lease~=nil,
            main_pose=true,variant=self.variant,source_calls=self.counters.source_calls,counters=copy(self.counters),
            reapplications=self.reapplications,churn_blocked=self.churn_blocked,applied_once=self.applied_once,
            action_open=self.action_open==true,retired_layers=copy(self.retired_layers),last_error=self.last_error,
            barrier_tick=self.barrier_tick,next_factory_tick=self.next_factory_tick}
    end
    function self:update(context)
        admission_tick=nil
        if not self.desired and not self.lease then
            if self.source then drop_source()end
            state('off','off');return true
        end
        if not context_ok(context)then
            state(self.lease and'cleanup_pending'or'waiting_context','explicit_update_context_required');return false,self.reason
        end
        if context.tick<=self.last_tick then
            state(self.lease and'cleanup_pending'or'waiting_context','later_update_required');return false,self.reason
        end
        self.last_tick=context.tick
        last_context=context
        if not self.source then
            if self.barrier_tick and context.tick<=self.barrier_tick then state('waiting_reentry','later_update_required');return false,self.reason end
            if self.next_factory_tick and context.tick<self.next_factory_tick then state('waiting_source','source_retry_pending');return false,self.reason end
            self.counters.factory_calls=self.counters.factory_calls+1
            local ok,source,why=pcall(options.source_factory,context)
            local v=type(source)=='table'and source.ready_variant
            local pair=type(source)=='table'and source.main_pair
            local complete=ok and type(source)=='table'and type(v)=='table'and(v.hip24==0 or v.hip24==5)
                and v.target24==v.hip24+1 and type(pair)=='table'and pair.hip4==67 and pair.target4==59
            for _,name in ipairs({'snapshot','can_mutate','apply','restore'})do
                complete=complete and type(source[name])=='function'
            end
            if not complete then
                self.counters.factory_failures=self.counters.factory_failures+1
                self.next_factory_tick=context.tick+retry
                state('waiting_source',tostring(ok and(why or'Supported native hip pose unavailable')or source));return false,self.reason
            end
            self.source=source;self.variant=v.hip24;self.wanted={[4]=59,[24]=v.target24,[25]=1}
            self.accounted_calls=finite(source.calls)and source.calls or 0
        end
        local s,why=invoke('snapshot',context)
        if type(s)~='table'then state(self.lease and'cleanup_pending'or'waiting_owner',why or'snapshot_unavailable');return false,self.reason end
        if s.retired==true then
            if self.lease or self.owner then self.counters.retirements=self.counters.retirements+1 end
            self.lease=nil;self.action_open=false;self.action_verified=false
            clean_barrier(context.tick,'owner_retired',true);return true,self.reason
        end
        if s.ownerToken==nil then state(self.lease and'cleanup_pending'or'waiting_owner','owner_unavailable');return false,self.reason end
        if self.owner~=nil and s.ownerToken~=self.owner then
            state(self.lease and'cleanup_pending'or'waiting_owner','owner_mismatch_unproved');return false,self.reason
        end
        if self.owner==nil then self.owner=s.ownerToken end
        observe_replacements(s)
        local weapon_token=s.weapon_token
        local concrete_weapon=(type(weapon_token)=='string'and #weapon_token>0)or finite(weapon_token)
        local weapon_changed=concrete_weapon and self.weapon_token~=nil and weapon_token~=self.weapon_token
        if concrete_weapon then self.weapon_token=weapon_token end
        if weapon_changed then
            self.action_open=true;self.action_verified=true;self.need_cleanup=true
            state(self.lease and'cleanup_pending'or'waiting_action','weapon_changed');return false,self.reason
        end
        -- The filter has retained the same native held-fire state. Preserve
        -- its running animation and our restoration ledger without a setter,
        -- worker fence, action interval or reapplication budget change.
        if s.firing==true and owns_carry(s)and type(options.filter_valid)=='function'then
            local owner=admission(s,context)
            if owner then
                local ok,valid=pcall(options.filter_valid,context,owner)
                if ok and valid==true then
                    admission_tick=context.tick;state('active','owned_target');return true,self.reason
                end
            end
        end
        if action(s)then
            self.action_open=true;self.need_cleanup=true
            if s.action_verified==true then self.action_verified=true end
            state(self.lease and'cleanup_pending'or'waiting_action','native_action');return false,self.reason
        end
        if not eligible(s)then
            state(self.lease and'cleanup_pending'or'waiting_action',s.supported==false and'unsupported_graph'or'unsafe_normal_view');return false,self.reason
        end
        if self.action_open then
            if not cleanup(s,context)then return false,self.reason end
            local verified=self.action_verified==true
            self.action_open=false;self.action_verified=false
            if verified then self.counters.action_intervals=self.counters.action_intervals+1 end
            clean_barrier(context.tick,'native_action_released',verified);return true,self.reason
        end
        if self.need_cleanup or not self.desired then
            if not cleanup(s,context)then return false,self.reason end
            clean_barrier(context.tick,self.churn_blocked and'native_overwrite_limit'or'cleanup_complete',false)
            return true,self.reason
        end
        if self.barrier_tick and context.tick<=self.barrier_tick then state('waiting_reentry','later_update_required');return false,self.reason end
        if self.churn_blocked then state('churn_blocked','native_overwrite_limit');return false,self.reason end
        if not cohort(s)then
            if not self.applied_once and not self.lease then state('waiting_cohort','unknown_cohort');return false,self.reason end
            self.churn_blocked=true;self.need_cleanup=true
            cleanup(s,context)
            state(self.lease and'cleanup_pending'or'churn_blocked','unknown_cohort');return false,self.reason
        end
        if target(s)then
            if owns_carry(s)then admission_tick=context.tick end
            state('active',self.lease and'owned_target'or'borrowed_target');return true,self.reason
        end
        if s.layers[24]~=self.variant and s.layers[24]~=self.wanted[24]then
            if not self.applied_once and not self.lease then
                drop_source();self.next_factory_tick=context.tick+retry
                state('waiting_source','captured_family_changed');return false,self.reason
            end
            self.churn_blocked=true;self.need_cleanup=true
            if cleanup(s,context)then self.need_cleanup=false end
            state(self.lease and'cleanup_pending'or'churn_blocked','variant_changed');return false,self.reason
        end
        if self.applied_once then
            self.counters.native_overwrites=self.counters.native_overwrites+1
            if self.reapplications>=maximum then
                self.churn_blocked=true;self.need_cleanup=true
                if cleanup(s,context)then self.need_cleanup=false end
                state(self.lease and'cleanup_pending'or'churn_blocked','native_overwrite_limit');return false,self.reason
            end
        end
        local allowed,problem=invoke('can_mutate',context,s)
        if allowed~=true then state(self.lease and'cleanup_pending'or'waiting_context',problem or'mutation_phase_unqualified');return false,self.reason end
        local prior=self.lease and{owner=self.lease.owner,original=copy(self.lease.original)}or nil
        if not self.lease then self.lease={owner=s.ownerToken,original={}}end
        local changes={}
        for layer,wanted in pairs(self.wanted)do
            if s.layers[layer]~=wanted then
                changes[layer]=wanted
                if self.lease.original[layer]==nil then self.lease.original[layer]=s.layers[layer]end
            end
        end
        if self.applied_once then self.reapplications=self.reapplications+1;self.counters.reapplications=self.counters.reapplications+1 end
        self.applied_once=true;self.counters.apply_calls=self.counters.apply_calls+1
        local calls_before=self.source.calls
        local done,reason=invoke('apply',changes,s,context)
        if done~=true then
            if finite(calls_before)and finite(self.source.calls)and self.source.calls==calls_before then self.lease=prior end
            error_state(reason);return false,self.reason
        end
        for _ in pairs(changes)do self.counters.applied_layers=self.counters.applied_layers+1 end
        admission_tick=context.tick
        state('active','applied');return true,self.reason
    end
    return self
end
return M
