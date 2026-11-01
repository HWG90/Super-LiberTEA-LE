local root=assert(NATIVE_ADS_TEST_ROOT)
local Near=dofile(root..'/src/first_person/near_clip.lua')
local ffi=require('ffi')
local passed=0
local function equal(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
    local f={begins=0,sets=0,ends=0,configs=0,stats_reads=0,time=0,logs={},options={hip=.15,aim=0}}
    f.controller={lease={request=100,weapon=11,origin={player_identity='p1'}},enabled=true,phase='running',mode='pose_offset'}
    function f.controller:is_enabled()return self.enabled end
    function f.controller:result()return {mode=self.mode,phase=self.phase,enabled=self.enabled}end
    f.backend={fov_config=function(_,lease)
        f.configs=f.configs+1
        if f.config_failure then return nil,'fixture camera not owned' end
        return {game=1,exe=2,context=3,camera=4,avatar_owner=5,avatar_index=0,request=lease.request,weapon=lease.weapon}
    end}
    f.helper={
        begin=function(_,config)
            f.begins=f.begins+1;f.begun=config
            if f.begin_refusal then return false,'fixture refused' end
            f.handle={generation='opaque'}
            if f.partial then return false,'fixture partial installation' end
            return true,f.handle
        end,
        owned_handle=function()return f.handle end,
        set=function(_,handle,hip,aim)equal(handle,f.handle);f.sets=f.sets+1;f.hip,f.aim=hip,aim;return not f.set_failure,'fixture set refused' end,
        stats=function(_,handle)
            equal(handle,f.handle);f.stats_reads=f.stats_reads+1
            return {armed=not f.disarmed,installed=true,error=f.disarmed and 7 or 0,replaced=3,ads_forwarded=1,last_native=.05,last_applied=.15}
        end,
        finish=function(_,handle)
            equal(handle,f.handle);f.ends=f.ends+1
            if f.end_failure then return false,'fixture cleanup pending' end
            f.handle=nil;return true,{armed=false,installed=false,replaced=3}
        end,
    }
    f.manager=Near.new(f.backend,function(m)f.logs[#f.logs+1]=m end,f.helper,function()return f.time end,function()return f.options end)
    return f
end
test('off, disabled and native modes never install the slot',function()
    local f=fixture();f.options={hip=0,aim=0};assert(f.manager:update(f.controller));equal(f.begins,0)
    f.options={hip=.15,aim=0};f.controller.enabled=false;assert(f.manager:update(f.controller));equal(f.begins,0)
    f.controller.enabled=true;f.controller.mode='native';assert(f.manager:update(f.controller));equal(f.begins,0)
    assert(f.manager:is_clean())
end)
test('a running first-person lease arms once with the FOV camera contract and both distances',function()
    local f=fixture();assert(f.manager:update(f.controller));equal(f.begins,1)
    equal(f.begun.camera,4);equal(f.begun.avatar_owner,5);equal(f.begun.hip,.15);equal(f.begun.aim,0)
    for _=1,5 do f.time=f.time+.016;assert(f.manager:update(f.controller))end
    equal(f.begins,1);equal(f.sets,0);equal(f.manager:result().phase,'active')
end)
test('changed menu values are sent live without re-arming',function()
    local f=fixture();assert(f.manager:update(f.controller))
    f.options={hip=.25,aim=.25};assert(f.manager:update(f.controller));equal(f.sets,1);equal(f.hip,.25);equal(f.aim,.25)
    assert(f.manager:update(f.controller));equal(f.sets,1);equal(f.begins,1)
    f.options={hip=0,aim=0};assert(f.manager:update(f.controller));equal(f.ends,1);assert(f.manager:is_clean())
end)
test('health is polled at 4 Hz and a native disarm ends the lease',function()
    local f=fixture();assert(f.manager:update(f.controller));local reads=f.stats_reads
    for _=1,10 do f.time=f.time+.01;assert(f.manager:update(f.controller))end
    equal(f.stats_reads,reads+1)
    f.time=f.time+.3;f.disarmed=true;local ok=f.manager:update(f.controller);assert(not ok);equal(f.ends,1)
    assert(f.manager:is_clean());assert(f.logs[#f.logs]:find('code 7',1,true))
end)
test('weapon gaps keep the lease; FPV off or another player ends it',function()
    local f=fixture();assert(f.manager:update(f.controller))
    f.controller.phase='waiting';f.controller.lease=nil;assert(f.manager:update(f.controller));equal(f.ends,0)
    f.controller.phase='running';f.controller.lease={request=101,weapon=12,origin={player_identity='p1'}}
    assert(f.manager:update(f.controller));equal(f.begins,1);equal(f.ends,0)
    f.controller.lease={request=102,weapon=12,origin={player_identity='p2'}};assert(f.manager:update(f.controller))
    equal(f.ends,1);equal(f.begins,2)
    f.controller.enabled=false;assert(f.manager:update(f.controller));equal(f.ends,2)
end)
test('refusals retry once a second and log each new reason once',function()
    local f=fixture();f.config_failure=true
    for _=1,30 do assert(not f.manager:update(f.controller)or true);f.time=f.time+.016 end
    equal(f.configs,1);equal(#f.logs,1)
    f.time=f.time+1;f.manager:update(f.controller);equal(f.configs,2);equal(#f.logs,1)
    f.config_failure=false;f.begin_refusal=true;f.time=f.time+1;f.manager:update(f.controller);equal(f.begins,1);equal(#f.logs,2)
    f.begin_refusal=false;f.time=f.time+1;assert(f.manager:update(f.controller));equal(f.begins,2)
end)
test('partial installs keep their handle for cleanup; pending cleanup retries',function()
    local f=fixture();f.partial=true;f.manager:update(f.controller);equal(f.ends,1);assert(f.manager:is_clean())
    f.partial=false;f.time=f.time+1;assert(f.manager:update(f.controller))
    f.end_failure=true;assert(not f.manager:stop());assert(not f.manager:is_clean());equal(f.manager:result().cleanup_pending,true)
    f.end_failure=false;assert(f.manager:update(f.controller));assert(f.manager:is_clean())
    f.time=f.time+1;assert(f.manager:update(f.controller));assert(f.manager:shutdown());assert(f.manager:update(f.controller));equal(f.begins,3)
    assert(f.manager:is_clean())
end)
test('invalid option values fall back to the game distance',function()
    local f=fixture();f.options={hip=0/0,aim=5};assert(f.manager:update(f.controller));equal(f.begins,0)
    f.options={hip=.2,aim=-1};assert(f.manager:update(f.controller));equal(f.begun.hip,.2);equal(f.begun.aim,0)
end)
test('adapter keeps opaque uint64 generations and the 72/88-byte ABI',function()
    local adapter=Near.Adapter.new({abi=1,library='fixture'})
    local generation=ffi.new('uint64_t',0x200000)*ffi.new('uint64_t',4294967296)+41
    local state={owned=false,begins=0,ends=0,sets=0}
    adapter.library={
        NADSN_Begin=function(c,out)
            equal(tonumber(c.size),72);equal(tonumber(c.abi),1);equal(tonumber(c.reserved),0)
            assert(math.abs(c.hip-.15)<1e-6);equal(c.aim,0)
            state.begins=state.begins+1;out[0]=generation;state.owned=true;return state.partial and 2 or 1
        end,
        NADSN_Set=function(g,hip,aim)equal(g,generation);state.sets=state.sets+1;state.hip=hip;return 1 end,
        NADSN_End=function(g)equal(g,generation);state.ends=state.ends+1;if state.pending then return 0 end;state.owned=false;return 1 end,
        NADSN_ReadStats=function(g,s)
            if state.owned and g~=generation or not state.owned and g~=0 then return 0 end
            equal(tonumber(s.size),88);s.armed=state.owned and 1 or 0;s.installed=s.armed;s.replaced=9;s.last_applied=.15
            return 1
        end,
        NADSN_Error=function()return 13 end,
    }
    local config={game=1,exe=2,context=3,camera=4,avatar_owner=5,avatar_index=0,hip=.15,aim=0}
    local ready,handle=adapter:begin(config);assert(ready);equal(handle.generation[0],generation)
    local stats=adapter:stats(handle);equal(stats.armed,true);equal(stats.replaced,9)
    assert(adapter:set(handle,.3,0));equal(state.sets,1);assert(math.abs(state.hip-.3)<1e-6)
    local other=Near.Adapter.new({abi=1});assert(not other:finish(handle));equal(state.ends,0)
    state.pending=true;local done,why=adapter:finish(handle);assert(not done);assert(why:find('code 13',1,true))
    equal(adapter:owned_handle(),handle)
    state.pending=false;assert(adapter:finish(handle));assert(adapter:finish(handle));equal(state.ends,2)
    assert(not adapter:set(handle,.2,0))
    state.partial=true;assert(not adapter:begin(config));local partial=adapter:owned_handle();assert(partial and partial~=handle)
    assert(adapter:finish(partial));equal(state.ends,3)
end)
print('Native ADS near clip manager/ABI fixtures: '..passed..' passed')
