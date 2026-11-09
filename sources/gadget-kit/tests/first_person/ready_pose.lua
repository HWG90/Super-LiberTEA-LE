local path=NATIVE_ADS_TEST_ROOT and(NATIVE_ADS_TEST_ROOT..'/src/ready_pose.lua')
    or'work/gadget-kit/src/first_person/ready_pose.lua'
local Manager=dofile(path)
local cases=0
local function check(v,why)assert(v,why or'Check failed')end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
local function fixture(options)
    options=options or{}
    local f={tick=0,authority={},scope=true,records={},sources={},logs={},factory_calls=0,snapshots=0,guards=0,filter_calls=0,filter_proof=true,
        s={ownerToken='actor:body:graph1',safeNormal4=true,supported=true,actualAim=false,reload=false,sprint=false,
            body_ref=0x80000f,body_generation=2,firing=false,foreign=false,ads=false,action_verified=true,
            weapon_token='weapon1',layers={[4]=67,[24]=options.variant or 5,[25]=3}}}
    local function factory(context)
        f.factory_calls=f.factory_calls+1
        if f.factory_error then error('Unsupported graph')end
        if f.factory_refuse then return nil,'Resource unavailable'end
        check(context.phase=='qualified_update','Factory outside Update')
        local hip=f.s.layers[24]
        if not f.s.safeNormal4 or f.s.actualAim or f.s.reload or f.s.sprint or f.s.firing or f.s.foreign or f.s.ads or f.s.weapon_transition
            or f.s.layers[4]~=67 or(hip~=0 and hip~=5)or f.s.layers[25]~=3 then return nil,'Released hip required'end
        local source={calls=0,ready_variant={hip24=hip,target24=hip+1},main_pair={hip4=67,target4=59}}
        f.sources[#f.sources+1]=source;f.current=source
        function source:snapshot()
            f.snapshots=f.snapshots+1
            if f.snapshot_error then error('Snapshot read failed')end
            if f.unavailable then return nil,'Owner temporarily unavailable'end
            local s=copy(f.s);s.layers=copy(f.s.layers);return s
        end
        function source:can_mutate(c,s)
            f.guards=f.guards+1
            return f.scope and c.phase=='qualified_update'and c.authority==f.authority,'Gate refused'
        end
        local function mutate(kind,changes,expected,c)
            if f.before_call then f.before_call(kind,source)end
            if source:can_mutate(c,expected)~=true then return false,'Final gate refused'end
            check(expected.ownerToken==f.s.ownerToken and not f.s.retired,'Wrong owner')
            check(f.s.safeNormal4 and not(f.s.actualAim or f.s.reload or f.s.sprint or f.s.firing or f.s.foreign or f.s.ads or f.s.weapon_transition),'Action overwritten')
            for _,layer in ipairs({4,24,25})do check(expected.layers[layer]==f.s.layers[layer],'Stale layer')end
            if f.refuse_restore and kind=='restore'then return false,'Restore unavailable'end
            if f.refuse_apply and kind=='apply'then return false,'Apply refused'end
            for layer,wanted in pairs(changes)do
                check(layer==4 or layer==24 or layer==25,'Unowned layer')
                check(f.s.layers[layer]~=wanted,'Same-state restart')
            end
            source.calls=source.calls+1
            f.records[#f.records+1]={kind=kind,changes=copy(changes),tick=c.tick,source=source}
            for layer,wanted in pairs(changes)do f.s.layers[layer]=wanted end
            if f.after_call then f.after_call(kind,source)end
            if f.uncertain then error('Uncertain native acknowledgement')end
            return true
        end
        function source:apply(changes,expected,c)return mutate('apply',changes,expected,c)end
        function source:restore(changes,expected,c)return mutate('restore',changes,expected,c)end
        return source
    end
    local opts={source_factory=factory,retry_ticks=options.retry_ticks or 3,max_reapplications=options.max_reapplications,
        log=function(reason,phase)if f.log_error then error('Logging failed')end;f.last_log={reason,phase};f.logs[#f.logs+1]=f.last_log end}
    if options.filter then opts.filter_valid=function(context,owner)
        f.filter_calls=f.filter_calls+1
        check(context==f.context and context.authority==f.authority,'Wrong filter scope')
        check(owner.body_ref==f.s.body_ref and owner.body_generation==f.s.body_generation
            and owner.owner_token==f.s.ownerToken and owner.tick==context.tick,'Wrong filter admission')
        if f.filter_error then error('Filter proof unavailable')end
        return f.filter_proof==true
    end end
    f.m=Manager.new(opts)
    function f:step(context)
        if not context then self.tick=self.tick+1;context={phase='qualified_update',tick=self.tick,authority=self.authority}end
        if context.phase=='qualified_update'and type(context.tick)=='number'and context.tick%1==0 and context.tick>self.tick then self.tick=context.tick end
        self.context=context
        return self.m:update(context)
    end
    function f:start()self.m:request(true);return self:step()end
    function f:release()self.m:stop();return self:step()end
    return f
end
local function test(name,fn)fn();cases=cases+1;print('PASS '..name)end
test('persistent goal does not expire or run steady native fences',function()
    local f=fixture();check(f:start());local gates=f.guards
    for _=1,1000 do check(f:step())end
    check(#f.records==1 and f.factory_calls==1 and f.guards==gates)
    check(f.m:result().desired and f.m:result().source_calls==1 and not f.m:is_clean())
end)
test('both captured hip families use three changed layers and restore exactly',function()
    for _,variant in ipairs({0,5})do
        local f=fixture{variant=variant};check(f:start())
        check(f.records[1].changes[4]==59 and f.records[1].changes[24]==variant+1 and f.records[1].changes[25]==1)
        check(f:release());check(f.m:is_clean()and #f.records==2)
        check(f.s.layers[4]==67 and f.s.layers[24]==variant and f.s.layers[25]==3)
    end
end)
test('request and stop outside Update never read or mutate',function()
    local f=fixture();check(f.m:request(true));check(f.snapshots==0 and f.factory_calls==0)
    check(f:step());local reads=f.snapshots;f.scope=false
    check(not f.m:stop());check(f.snapshots==reads and #f.records==1)
    check(not f:step());check(#f.records==1);f.scope=true;check(f:step());check(f.m:is_clean())
end)
test('phase and monotonic tick are required before factory or snapshot',function()
    local f=fixture();f.m:request(true)
    for _,c in ipairs({{}, {phase='render',tick=1}, {phase='qualified_update',tick=0}, {phase='qualified_update',tick=1.5}})do check(not f:step(c))end
    check(not f.m:update(nil));check(f.factory_calls==0 and f.snapshots==0)
    check(f:step());local reads=f.snapshots
    check(not f:step{phase='qualified_update',tick=1,authority=f.authority});check(f.snapshots==reads)
end)
test('valid phase alone cannot authorize a native call',function()
    local f=fixture();f.scope=false;check(not f:start());check(#f.records==0 and f.m:is_clean())
    f.scope=true;check(not f:step{phase='qualified_update',tick=2,authority={}});check(#f.records==0)
    check(f:step());check(#f.records==1)
end)
test('factory errors and unsupported cohorts retry with bounded pacing',function()
    local f=fixture();f.factory_error=true;check(not f:start());check(f.factory_calls==1)
    check(not f:step());check(not f:step());check(f.factory_calls==1)
    check(not f:step());check(f.factory_calls==2 and #f.records==0 and f.m:result().desired)
    f.factory_error=false;f.s.layers[24]=8
    for _=1,3 do f:step()end;check(#f.records==0)
    f.s.layers[24]=5;for _=1,3 do f:step()end;check(#f.records==1)
end)
test('off on bypasses a failed factory retry delay',function()
    local f=fixture{retry_ticks=30};f.factory_refuse=true;f:start();check(f.factory_calls==1)
    f.m:request(false);f.m:request(true);f.factory_refuse=false;check(f:step());check(f.factory_calls==2)
end)
test('native aimed24 handoffs never gate or restart',function()
    for _,variant in ipairs({0,5})do
        local f=fixture{variant=variant};f:start();local gates=f.guards
        f.s.layers[24]=variant==0 and 6 or 1
        for _=1,500 do check(f:step())end
        check(#f.records==1 and f.guards==gates and f.factory_calls==1)
        check(f.m:result().counters.reapplications==0 and f.m:result().counters.native_overwrites==0)
        check(f:release());check(f.records[2].changes[24]==nil)
    end
end)
test('aimed24 ABA never reacquires stale restoration ownership',function()
    local f=fixture();f:start();f.s.layers[24]=1;f:step();f.s.layers[24]=6;f:step();check(f:release())
    check(f.records[2].changes[4]==67 and f.records[2].changes[25]==3 and f.records[2].changes[24]==nil)
    check(f.s.layers[24]==6 and f.m:result().counters.layer_retirements==1)
end)
test('cleanup observes a native24 handoff before its first ordinary update',function()
    local f=fixture();f:start();f.s.layers[24]=1;f.m:stop();check(f:step())
    check(f.records[2].changes[24]==nil and f.records[2].changes[4]==67 and f.records[2].changes[25]==3)
    check(f.s.layers[24]==1 and f.m:is_clean())
end)
test('actual aim preserves unchanged owned targets until release cleanup',function()
    local f=fixture();f:start();f.s.actualAim=true
    for _=1,4 do check(not f:step())end
    check(not f.m:is_clean()and #f.records==1)
    f.s.actualAim=false;check(f:step());check(f.m:is_clean()and #f.records==2)
    local tick=f.tick;check(not f:step{phase='qualified_update',tick=tick,authority=f.authority})
    check(f:step());check(#f.records==3 and f.factory_calls==2 and f.records[3].tick>f.records[2].tick)
end)
test('every native action defers writes and reenters after clean later Update',function()
    for _,key in ipairs({'actualAim','reload','sprint','foreign','ads','ADS','weapon_transition'})do
        local f=fixture();f:start();f.s[key]=true;check(not f:step());check(#f.records==1)
        f.s[key]=false;check(f:step());check(#f.records==2 and f.m:is_clean())
        check(f:step());check(#f.records==3)
    end
end)
test('native action can select a new captured family after cleanup',function()
    local f=fixture();f:start();f.s.reload=true;f.s.layers[24]=0;f:step();f.s.reload=false
    check(f:step());check(f.records[2].changes[24]==nil and f.s.layers[24]==0)
    check(f:step());check(f.current.ready_variant.hip24==0 and f.s.layers[24]==1 and #f.sources==2)
end)
test('unverified action does not renew the ordinary churn budget',function()
    local f=fixture();f:start();f.s.layers[4]=67;f.s.layers[24]=5;f.s.layers[25]=3
    check(not f:step());check(f.m:result().churn_blocked)
    f.s.actualAim=true;f.s.action_verified=false;f:step();f.s.actualAim=false;check(f:step())
    for _=1,5 do f:step()end
    check(#f.records==1 and f.m:result().churn_blocked and f.factory_calls==1)
end)
test('all claims retired still cannot reopen zero reapplication episode',function()
    local f=fixture();f:start();f.s.layers[4]=67;f.s.layers[24]=5;f.s.layers[25]=3
    check(not f:step());check(f.m:is_clean()and f.m:result().applied_once)
    for _=1,100 do f:step();f.m:request(true)end
    check(#f.records==1 and f.factory_calls==1 and f.m:result().churn_blocked)
end)
test('explicit off on opens a fresh episode after all claims retired',function()
    local f=fixture();f:start();f.s.layers[4]=67;f.s.layers[24]=5;f.s.layers[25]=3;f:step()
    f.m:request(false);f.m:request(true);check(f:step());check(#f.records==2 and f.factory_calls==2)
end)
test('verified action interval renews exhausted budget only after release',function()
    local f=fixture();f:start();f.s.layers[4]=67;f.s.layers[24]=5;f.s.layers[25]=3;f:step()
    f.s.sprint=true;f:step();check(f.m:result().churn_blocked)
    f.s.sprint=false;check(f:step());check(not f.m:result().churn_blocked and #f.records==1)
    check(f:step());check(#f.records==2 and f.factory_calls==2 and f.m:result().counters.action_intervals==1)
end)
test('positive weapon token change opens one verified interval',function()
    local f=fixture();f:start();f.s.weapon_token='weapon2';check(not f:step());check(#f.records==1)
    check(f:step());check(#f.records==2 and f.m:is_clean());check(f:step());check(#f.records==3 and #f.sources==2)
    local gates=f.guards;for _=1,20 do check(f:step())end;check(f.guards==gates)
end)
test('qualified firing yields throughout and cleans before one later reentry',function()
    local f=fixture();f:start();local gates=f.guards
    f.s.firing=true;f.s.layers[4]=60
    for _=1,200 do check(not f:step())end
    check(#f.records==1 and f.guards==gates and f.factory_calls==1)
    check(f.m:result().retired_layers[4]==60 and not f.m:is_clean())
    f.s.firing=false;f.s.layers[4]=67;check(f:step())
    check(f.m:is_clean()and #f.records==2 and f.records[2].changes[4]==nil)
    check(f.records[2].changes[24]==5 and f.records[2].changes[25]==3)
    check(f:step());check(#f.records==3 and f.factory_calls==2 and f.records[3].tick>f.records[2].tick)
    check(f.m:result().counters.action_intervals==1 and f.m:result().counters.reapplications==0)
end)
test('verified firing releases an already blocked episode without steady reapplication',function()
    local f=fixture();f:start();f.s.layers={[4]=67,[24]=5,[25]=3};f:step()
    check(f.m:result().churn_blocked and f.m:is_clean())
    f.s.firing=true;f.s.layers={[4]=60,[24]=1,[25]=1}
    for _=1,20 do check(not f:step())end;check(#f.records==1 and f.m:result().churn_blocked)
    f.s.firing=false;f.s.layers={[4]=67,[24]=5,[25]=3};check(f:step())
    check(not f.m:result().churn_blocked and #f.records==1);check(f:step());check(#f.records==2)
    local gates=f.guards;for _=1,100 do check(f:step())end
    check(#f.records==2 and f.guards==gates and f.factory_calls==2)
end)
test('bare firing-shaped main state cannot renew budget or alternate blocked logs',function()
    local f=fixture();f:start();f.s.layers={[4]=67,[24]=5,[25]=3};f:step()
    local logs,gates=#f.logs,f.guards
    for i=1,100 do
        f.s.layers=i%2==0 and{[4]=67,[24]=5,[25]=3}or{[4]=60,[24]=1,[25]=1}
        check(not f:step());check(f.m:result().phase=='churn_blocked'and f.m:result().reason=='native_overwrite_limit')
    end
    check(#f.logs==logs and f.guards==gates and #f.records==1 and f.factory_calls==1)
    check(f.m:result().counters.action_intervals==0)
end)
test('unverified firing defers but never renews an exhausted budget',function()
    local f=fixture();f:start();f.s.layers={[4]=67,[24]=5,[25]=3};f:step()
    f.s.firing=true;f.s.action_verified=false;f.s.layers={[4]=60,[24]=1,[25]=1}
    check(not f:step());check(f.m:result().action_open)
    f.s.firing=false;f.s.layers={[4]=67,[24]=5,[25]=3};check(f:step())
    for _=1,10 do check(not f:step())end
    check(#f.records==1 and f.factory_calls==1 and f.m:result().churn_blocked)
    check(f.m:result().counters.action_intervals==0)
end)
test('stop during firing defers remaining claims and never reenters',function()
    local f=fixture();f:start();f.s.firing=true;f.s.layers[4]=60;f:step()
    local reads=f.snapshots;check(not f.m:stop());check(f.snapshots==reads)
    for _=1,5 do check(not f:step())end;check(#f.records==1 and not f.m:is_clean())
    f.s.firing=false;f.s.layers[4]=67;check(f:step());check(f.m:is_clean()and #f.records==2)
    check(f.records[2].changes[4]==nil and f.records[2].changes[24]==5 and f.records[2].changes[25]==3)
    for _=1,10 do check(f:step())end;check(#f.records==2 and f.factory_calls==1 and not f.m:is_enabled())
end)
test('positive owned filter keeps held firing and release continuous without pose writes',function()
    local f=fixture{filter=true};f:start();local gates=f.guards
    f.s.firing=true
    for _=1,300 do check(f:step());check(f.m:filter_owner(f.context))end
    check(#f.records==1 and f.guards==gates and f.factory_calls==1 and f.filter_calls==300)
    check(not f.m:result().action_open and not f.m:is_clean())
    f.s.firing=false
    for _=1,100 do check(f:step())end
    check(#f.records==1 and f.guards==gates and f.filter_calls==300)
    check(f.m:result().counters.action_intervals==0 and f.m:result().counters.reapplications==0)
    check(f:release());check(#f.records==2 and f.records[2].changes[4]==67)
end)
test('filter admission requires a successful latest private Update acknowledgement',function()
    local f=fixture{filter=true};f.m:request(true)
    check(not f.m:filter_owner{phase='qualified_update',tick=1});check(f.factory_calls==0)
    check(f:step());local owner=assert(f.m:filter_owner(f.context));local gates=f.guards
    check(owner.body_ref==f.s.body_ref and owner.body_generation==2 and owner.owner_token==f.s.ownerToken and owner.tick==f.tick)
    owner.body_ref=99;owner.owner_token='foreign';check(f.m:filter_owner(f.context).body_ref==f.s.body_ref)
    check(not f.m:filter_owner(copy(f.context)),'An equal context copy must not carry private authority')
    local old=f.context;check(f:step());check(not f.m:filter_owner(old));check(f.m:filter_owner(f.context))
    check(f.guards==gates and #f.records==1)
end)
test('refused and uncertain entry never admits the native filter',function()
    local f=fixture{filter=true};f.scope=false;check(not f:start());check(not f.m:filter_owner(f.context))
    f.scope=true;f.uncertain=true;check(not f:step());check(not f.m:filter_owner(f.context)and not f.m:is_clean())
end)
test('policy and fresh admission snapshot failures disarm that Update admission',function()
    local f=fixture{filter=true};f:start();check(f.m:filter_owner(f.context))
    f.unavailable=true;check(not f:step());check(not f.m:filter_owner(f.context))
    f.unavailable=false;check(not f.m:filter_owner(f.context));check(f:step());check(f.m:filter_owner(f.context))
    f.unavailable=true;check(not f.m:filter_owner(f.context));f.unavailable=false
    check(not f.m:filter_owner(f.context));check(f:step());check(f.m:filter_owner(f.context))
    check(#f.records==1 and not f.m:is_clean())
end)
test('fresh admission observation permanently retires a replaced main claim',function()
    local f=fixture{filter=true};f:start();f.s.layers[4]=67;check(not f.m:filter_owner(f.context))
    check(f.m:result().retired_layers[4]==67 and not f.m:is_clean())
    f.s.layers[4]=59;check(not f.m:filter_owner(f.context));check(f:step());check(not f.m:filter_owner(f.context))
    f.s.firing=true;check(not f:step());check(f.m:result().action_open and f.filter_calls==0)
    check(#f.records==1)
end)
test('fresh admission rejects a weapon change not yet processed by the policy',function()
    local f=fixture{filter=true};f:start();f.s.weapon_token='weapon2'
    check(not f.m:filter_owner(f.context));check(not f.m:is_clean()and #f.records==1)
    check(not f:step());check(f.m:result().action_open and f.filter_calls==0)
end)
test('native24 handoff while filtered firing preserves main ownership and animation',function()
    local f=fixture{filter=true};f:start();f.s.firing=true;f.s.layers[24]=1
    check(f:step());check(f.m:filter_owner(f.context));f.s.layers[24]=6
    check(f:step());check(f.m:filter_owner(f.context));check(#f.records==1)
    f.s.firing=false;check(f:step());check(f:release());check(f.records[2].changes[24]==nil and f.s.layers[24]==6)
end)
test('missing refused and throwing filter proofs preserve old firing recovery',function()
    for _,mode in ipairs({'missing','refused','throwing'})do
        local f=fixture{filter=mode~='missing'};f:start()
        f.filter_proof=false;f.filter_error=mode=='throwing';f.s.firing=true
        check(not f:step());check(f.m:result().action_open and #f.records==1)
        check(not f.m:filter_owner(f.context))
        f.s.firing=false;f.filter_error=false;check(f:step());check(f.m:is_clean()and #f.records==2)
    end
end)
test('filtered firing never masks another native action or a weapon change',function()
    for _,key in ipairs({'actualAim','reload','sprint','foreign','ads','ADS','weapon_transition'})do
        local f=fixture{filter=true};f:start();f.s.firing=true;f.s[key]=true
        check(not f:step());check(not f.m:filter_owner(f.context))
        check(f.filter_calls==0 and #f.records==1 and f.m:result().action_open)
    end
    local f=fixture{filter=true};f:start();f.s.firing=true;f.s.weapon_token='weapon2'
    check(not f:step());check(not f.m:filter_owner(f.context));check(f.filter_calls==0)
end)
test('positive filter proof cannot hold an existing cleanup or blocked interval',function()
    local f=fixture{filter=true};f:start();f.s.sprint=true;f:step();f.s.sprint=false;f.s.firing=true
    check(not f:step());check(f.m:result().action_open and f.filter_calls==0)
    check(not f.m:filter_owner(f.context))
    f=fixture{filter=true};f:start();f.s.layers={[4]=67,[24]=5,[25]=3};f:step()
    f.s.layers={[4]=59,[24]=6,[25]=1};f.s.firing=true;check(not f:step())
    check(not f.m:filter_owner(f.context)and f.filter_calls==0 and f.m:result().churn_blocked)
end)
test('native60 under a positive filter still uses verified firing fallback',function()
    local f=fixture{filter=true};f:start();f.s.firing=true;f.s.layers[4]=60
    for _=1,10 do check(not f:step())end
    check(f.m:result().action_open and f.filter_calls==0 and #f.records==1)
    check(not f.m:filter_owner(f.context))
    f.s.firing=false;f.s.layers[4]=67;check(f:step());check(#f.records==2)
    check(f:step());check(#f.records==3)
end)
test('stop during continuous filtered firing defers cleanup and cancels admission immediately',function()
    local f=fixture{filter=true};f:start();f.s.firing=true;check(f:step());check(f.m:filter_owner(f.context))
    local reads=f.snapshots;check(not f.m:stop());check(f.snapshots==reads)
    check(not f.m:filter_owner(f.context));check(not f:step());check(#f.records==1)
    f.s.firing=false;check(f:step());check(f.m:is_clean()and #f.records==2 and not f.m:is_enabled())
end)
test('filter admission rejects incomplete or inconsistent body primitives',function()
    for _,bad in ipairs({{body_ref=0},{body_ref=0xffffffff},{body_ref=1.5},{body_generation=-1},
        {body_generation=256},{body_generation=2.5},{body_generation=3},{body_ref=0/0}})do
        local f=fixture{filter=true};f:start();for k,v in pairs(bad)do f.s[k]=v end
        check(not f.m:filter_owner(f.context));check(#f.records==1 and not f.m:is_clean())
    end
    local f=fixture{filter=true};f:start();f.s.body_ref=nil;check(not f.m:filter_owner(f.context))
    f=fixture{filter=true};f:start();f.s.body_generation=nil;check(not f.m:filter_owner(f.context))
end)
test('unknown weapon token does not invent a swap or reset budget',function()
    local f=fixture();f:start();f.s.weapon_token=nil;check(f:step());f.s.weapon_token={};check(f:step())
    check(#f.records==1 and f.m:result().counters.action_intervals==0)
end)
test('other family hip cleans remaining layers then stays naturally blocked',function()
    local f=fixture();f:start();f.s.layers[24]=0;check(not f:step())
    check(#f.records==2 and f.records[2].changes[24]==nil and f.m:is_clean())
    for _=1,6 do f:step()end;check(#f.records==2 and f.factory_calls==1)
end)
test('unknown main retains other claims until known cohort returns',function()
    local f=fixture();f:start();f.s.layers[4]=8;check(not f:step());check(#f.records==1 and not f.m:is_clean())
    f.s.layers[4]=59;check(f:step());check(#f.records==2 and f.records[2].changes[4]==nil)
    check(f.s.layers[4]==59 and f.m:is_clean()and f.m:result().churn_blocked)
end)
test('unknown main blocks even a remaining layer25-only restore',function()
    local f=fixture();f:start();f.s.layers[4]=8;f.s.layers[24]=0;f.m:stop();check(not f:step())
    check(#f.records==1 and not f.m:is_clean());f.s.layers[4]=67;check(f:step())
    check(#f.records==2 and f.records[2].changes[25]==3 and f.records[2].changes[4]==nil)
end)
test('layer25 replacement and ABA never restores a native returned target',function()
    local f=fixture();f:start();f.s.reload=true;f.s.layers[25]=0;f:step();f.s.layers[25]=1;f.s.reload=false
    check(f:step());check(f.records[2].changes[25]==nil and f.s.layers[25]==1)
    check(not f:step());check(#f.records==2)
end)
test('missing negative and out of range observations never retire a claim',function()
    for _,value in ipairs({-1,78,1.5})do
        local f=fixture();f:start();f.s.layers[4]=value;f.m:stop();check(not f:step());check(not f.m:is_clean())
        f.s.layers[4]=59;check(f:step());check(f.records[2].changes[4]==67)
    end
    local f=fixture();f:start();f.s.layers[4]=nil;f.m:stop();check(not f:step());check(not f.m:is_clean())
end)
test('owner mismatch cannot release or restore owned layers',function()
    local f=fixture();f:start();f.s.ownerToken='otherbody';f.m:stop()
    for _=1,5 do check(not f:step())end
    check(not f.m:is_clean()and #f.records==1 and f.factory_calls==1)
    f.s.ownerToken='actor:body:graph1';check(f:step());check(f.m:is_clean()and #f.records==2)
end)
test('positive owner retirement drops old ledger and waits before new source',function()
    local f=fixture();f:start();f.s.retired=true;check(f:step());check(f.m:is_clean()and #f.records==1)
    f.s.retired=false;f.s.ownerToken='actor:body:graph2';f.s.layers={[4]=67,[24]=0,[25]=3}
    check(f:step());check(f.factory_calls==2 and #f.records==2 and f.current.ready_variant.hip24==0)
end)
test('unknown cohort before any native attempt waits without blocking an episode',function()
    local f=fixture();f.scope=false;f:start();check(#f.records==0)
    f.s.layers[4]=8;check(not f:step());check(not f.m:result().churn_blocked and f.m:is_clean())
    f.s.layers[4]=67;f.scope=true;check(f:step());check(#f.records==1)
end)
test('captured family change before any native attempt permits paced new capture',function()
    local f=fixture();f.scope=false;f:start();f.s.layers[24]=0;f.scope=true
    check(not f:step());check(not f.m:result().churn_blocked and f.m:is_clean())
    for _=1,2 do check(not f:step())end;check(f:step());check(#f.sources==2 and #f.records==1 and f.s.layers[24]==1)
end)
test('temporary snapshot failure preserves pending ledger',function()
    local f=fixture();f:start();f.unavailable=true;f.m:stop()
    for _=1,3 do check(not f:step())end;check(not f.m:is_clean()and #f.records==1)
    f.unavailable=false;check(f:step());check(f.m:is_clean())
end)
test('snapshot errors preserve intent and restoration obligations',function()
    local f=fixture();f:start();f.snapshot_error=true;check(not f:step());check(f.m:result().desired and not f.m:is_clean())
    f.snapshot_error=false;check(f:release());check(f.m:is_clean())
end)
test('pre-call numeric no-call proof removes provisional new claim',function()
    local f=fixture();f.refuse_apply=true;check(not f:start());check(f.m:is_clean()and #f.records==0)
    check(not f.m:result().desired and f.m:result().counters.apply_calls==1)
end)
test('revoked final gate never turns phase text into native authority',function()
    local f=fixture();f.before_call=function()f.scope=false end;check(not f:start())
    check(#f.records==0 and f.m:is_clean()and not f.m:result().desired)
end)
test('uncertain post-call apply retains cleanup until qualified Update',function()
    local f=fixture();f.uncertain=true;check(not f:start());check(#f.records==1 and not f.m:is_clean())
    f.uncertain=false;f.scope=false;check(not f:step());check(#f.records==1)
    f.scope=true;check(f:step());check(f.m:is_clean()and #f.records==2)
end)
test('missing actual-call counter retains uncertain provisional ownership',function()
    local f=fixture();f.before_call=function(_,source)source.calls=nil;f.scope=false end;check(not f:start())
    check(not f.m:is_clean()and #f.records==0);f.before_call=nil;f.scope=true
    check(f:step());check(f.m:is_clean()and #f.records==0)
end)
test('restore refusal never reports clean and retries on qualified Update',function()
    local f=fixture();f:start();f.refuse_restore=true;f.m:stop();check(not f:step());check(not f.m:is_clean())
    check(not f.m:result().desired and #f.records==1);f.refuse_restore=false;check(f:step());check(f.m:is_clean())
end)
test('off on during pending cleanup cannot bypass old ownership',function()
    local f=fixture();f:start();f.s.reload=true;f.m:stop();f.m:request(true);check(not f:step())
    check(f.factory_calls==1 and #f.records==1);f.s.reload=false;check(f:step());check(f.m:is_clean())
    check(f:step());check(f.factory_calls==2 and #f.records==3)
end)
test('optional churn allowance is finite across lease retirement',function()
    local f=fixture{max_reapplications=2};f:start()
    for _=1,2 do f.s.layers={[4]=67,[24]=5,[25]=3};check(f:step())end
    f.s.layers={[4]=67,[24]=5,[25]=3};check(not f:step());check(#f.records==3 and f.m:result().churn_blocked)
    for _=1,10 do f:step()end;check(#f.records==3 and f.m:result().counters.reapplications==2)
end)
test('result diagnostics are copied and logging errors stay isolated',function()
    local f=fixture();f.log_error=true;f:start();f.s.layers[24]=1;f:step()
    local r=f.m:result();r.retired_layers[24]=99;r.counters.apply_calls=99
    check(f.m:result().retired_layers[24]==1 and f.m:result().counters.apply_calls==1)
    check(f:release());check(f.m:result().source_calls==2)
end)
test('constructor bounds reject malformed retry and churn settings',function()
    for _,opts in ipairs({{retry_ticks=0},{retry_ticks=601},{max_reapplications=-1},{max_reapplications=4}})do
        opts.source_factory=function()end;check(not pcall(Manager.new,opts))
    end
end)
print('Persistent native ready pose: '..cases..' intent, ownership, action, handoff and cleanup cases passed')
