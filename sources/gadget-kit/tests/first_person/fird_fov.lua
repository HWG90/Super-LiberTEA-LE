local root=assert(NATIVE_ADS_TEST_ROOT)
local previous_mod=mod
mod={require=function(path)return dofile(root..'/'..path)end}
local F=dofile(root..'/src/first_person/fird_fov.lua')
mod=previous_mod
local ffi=require('ffi')
local passed=0
local function equal(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
    local f={begins=0,binds=0,ends=0,validations=0,configs=0}
    f.player={player_identity='p',safe=true,camera_kind=4,controller_active=false,record=100}
    f.capture={identity='p',source_fov=math.rad(72)}
    f.backend={player_snapshot=function()return f.player end,fird_fov_config=function(_,s)
        f.configs=f.configs+1;if f.invalid_config then return nil,'camera refused'end
        return {request=s.record,weapon=0}
    end}
    f.helper={validate=function()f.validations=f.validations+1;return true end,
        begin=function(_,config,lens)
            f.begins=f.begins+1;f.lens=lens
            if f.refused then return false,'foreign lease'end
            f.handle={generation='opaque'}
            if f.partial then return false,'partial installation'end
            return true,f.handle
        end,
        owned_handle=function()return f.handle end,
        bind=function(_,handle,config)
            equal(handle,f.handle);f.binds=f.binds+1;f.bound=config.request
            if f.bind_failure then return false,'binding refused'end
            return true
        end,
        stats=function(_,handle)
            equal(handle,f.handle);if f.stats_failure then return nil,'stats refused'end
            return {armed=not f.disarmed,installed=true,error=f.native_error or 0,source_degrees=72}
        end,
        finish=function(_,handle)
            equal(handle,f.handle);f.ends=f.ends+1
            if f.cleanup_failure then return false,'cleanup pending'end
            f.handle=nil;return true
        end}
    f.manager=F.new(f.backend,nil,f.helper)
    return f
end
test('captured projection starts once, remains fixed, and binds each new normal request once',function()
    local f=fixture();assert(f.manager:start(f.capture));equal(f.validations,1);equal(f.begins,1)
    equal(f.lens,f.capture.source_fov);assert(f.manager.lensmatching)
    assert(f.manager:update(f.player));equal(f.binds,0)
    f.player.record=200;assert(f.manager:update(f.player));equal(f.binds,1);equal(f.bound,200)
    assert(f.manager:update(f.player));equal(f.binds,1);equal(f.begins,1)
    assert(f.manager:stop());assert(f.manager:is_clean());assert(not f.manager.lensmatching)
    assert(f.manager:stop());equal(f.ends,1)
end)
test('native ADS keeps its generation and restores the captured lens on normal return even at the same request address',function()
    local f=fixture();assert(f.manager:start(f.capture));local handle=f.manager.handle
    f.player.camera_kind=6;f.player.controller_active=true
    assert(f.manager:update(f.player));equal(f.manager.handle,handle);assert(not f.manager.lensmatching)
    equal(f.ends,0);equal(f.binds,0)
    f.player.camera_kind=4;f.player.controller_active=false
    assert(f.manager:update(f.player));equal(f.binds,1);equal(f.begins,1);assert(f.manager.lensmatching)
    f.player.safe=false;assert(f.manager:update(f.player));assert(not f.manager.lensmatching)
    f.player.safe=true;assert(f.manager:update(f.player));equal(f.binds,2);assert(f.manager:stop())
end)
test('player loss, native disarm, bad stats and bind refusal clean the owned generation',function()
    for _,failure in ipairs({'player','disarmed','native_error','stats_failure','bind_failure'})do
        local f=fixture();assert(f.manager:start(f.capture))
        if failure=='player'then f.player.player_identity='other'
        elseif failure=='native_error'then f.native_error=7
        else f[failure]=true end
        if failure=='bind_failure'then f.player.record=300 end
        assert(not f.manager:update(f.player),failure);equal(f.ends,1);assert(f.manager:is_clean())
    end
end)
test('partial Begin retains cleanup ownership and never starts another generation until cleaned',function()
    local f=fixture();f.partial=true;f.cleanup_failure=true
    assert(not f.manager:start(f.capture));equal(f.begins,1);equal(f.ends,1)
    assert(not f.manager:is_clean());equal(f.manager:result().cleanup_pending,true)
    assert(not f.manager:start(f.capture));equal(f.begins,1)
    f.cleanup_failure=false;assert(f.manager:stop());assert(f.manager:is_clean())
    f.partial=false;assert(f.manager:start(f.capture));equal(f.begins,2);assert(f.manager:stop())
    f=fixture();f.refused=true;assert(not f.manager:start(f.capture));equal(f.ends,0);assert(f.manager:is_clean())
end)
test('invalid capture lenses, wrong player and ADS entry never install a generation',function()
    for _,lens in ipairs({0,math.rad(9),math.rad(171),math.huge,0/0})do
        local f=fixture();f.capture.source_fov=lens;assert(not f.manager:start(f.capture));equal(f.begins,0)
    end
    for _,change in ipairs({'player','ads','unsafe'})do
        local f=fixture()
        if change=='player'then f.player.player_identity='other'
        elseif change=='ads'then f.player.camera_kind=6
        else f.player.safe=false end
        assert(not f.manager:start(f.capture));equal(f.begins,0)
    end
end)
test('adapter reuses opaque native generations and Fird exports with the original cleanup contract',function()
    local adapter=F.Adapter.new({abi=1,library='fixture',ads_blend_ms=180})
    local generation=ffi.new('uint64_t',0x200000)*ffi.new('uint64_t',4294967296)+37
    local state={owned=false,ends=0,binds=0,validations=0}
    adapter.library={
        NADSF_ValidateFird=function(c)equal(tonumber(c.size),80);equal(tonumber(c.weapon),0);equal(tonumber(c.reserved),0);state.validations=state.validations+1;return 1 end,
        NADSF_BeginFird=function(_,lens,out)equal(lens,.75);out[0]=generation;state.owned=true;return state.partial and 2 or 1 end,
        NADSF_BindFird=function(g,request)equal(g,generation);equal(request,200);state.binds=state.binds+1;return 1 end,
        NADSF_End=function(g)equal(g,generation);state.ends=state.ends+1;if state.pending then return 0 end;state.owned=false;return 1 end,
        NADSF_ReadStats=function(g,s)
            if state.owned and g~=generation or not state.owned and g~=0 then return 0 end
            s.armed=state.owned and 1 or 0;s.installed=s.armed;return 1
        end,
        NADSF_Error=function()return 13 end}
    local config={game=1,exe=2,context=3,camera=4,avatar_owner=5,request=100,avatar_index=0,avatar=6,body=7,weapon=0}
    assert(adapter:validate(config));equal(state.validations,1)
    local ok,handle=adapter:begin(config,.75);assert(ok);equal(handle.generation[0],generation)
    assert(adapter:bind(handle,{request=200}));equal(state.binds,1)
    state.pending=true;assert(not adapter:finish(handle));equal(adapter:owned_handle(),handle)
    state.pending=false;assert(adapter:finish(handle));assert(adapter:finish(handle));equal(state.ends,2)
    state.partial=true;assert(not adapter:begin(config,.75));local partial=adapter:owned_handle();assert(partial)
    assert(adapter:finish(partial));equal(state.ends,3)
end)
print('FirdPerson captured FOV: '..passed..' lifecycle/adapter cases passed')
