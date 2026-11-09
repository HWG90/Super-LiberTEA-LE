local N=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_native_ads.lua')
local count=0;local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));count=count+1 end
local function fixture()
    local f={entries=0,exits=0,releases=0,prepares=0}
    f.s={identity='w',player_identity='p',record=1,camera_kind=4,safe=true,shoulder_aim=true,aiming=false,controller_active=false}
    f.b={snapshot=function()if f.no_snapshot then return nil,'snapshot unavailable'end;local s={};for k,v in pairs(f.s)do s[k]=v end;return s end,
        enter=function(_,s)
            f.entries=f.entries+1;if f.refused then return false,'entry refused'end
            local origin={};for k,v in pairs(s)do origin[k]=v end
            f.s.camera_kind,f.s.record=6,2
            return true,{origin=origin,request=2,cleanup_only=f.partial}
        end,
        release=function(_,lease)
            f.releases=f.releases+1;if f.cleanup_failure then return false,'cleanup pending'end
            if not f.s.aiming and not f.s.controller_active and f.s.identity==lease.origin.identity and f.s.record==lease.request then
                f.s.camera_kind,f.s.record=4,1;f.exits=f.exits+1
            end
            lease.done=true;return true
        end}
    f.m=N.new(f.b,nil,{foreign=function()return f.foreign end,prepare=function(s)
        f.prepares=f.prepares+1;if f.on_prepare then f.on_prepare()end
        return not f.prepare_failure,'render cleanup pending'
    end})
    return f
end
test('modern shoulder aim enters once and release exits its exact native request',function()
    local f=fixture();assert(f.m:update(true,'native'));assert(f.entries==1 and f.s.camera_kind==6 and not f.m:is_clean())
    assert(f.m:update(true,'native'));assert(f.entries==1)
    f.s.shoulder_aim=false;assert(f.m:update(true,'native'));assert(f.exits==1 and f.m:is_clean())
end)
test('Fird mode, disabled intent, unsafe states and foreign camera never enter',function()
    for _,failure in ipairs({'mode','disabled','unsafe','foreign','legacy','controller','camera'})do
        local f=fixture();local mode,enabled='native',true
        if failure=='mode'then mode='fird'elseif failure=='disabled'then enabled=false
        elseif failure=='unsafe'then f.s.safe=false elseif failure=='foreign'then f.foreign=true
        elseif failure=='legacy'then f.s.aiming=true elseif failure=='controller'then f.s.controller_active=true
        else f.s.camera_kind=6 end
        assert(f.m:update(enabled,mode));assert(f.entries==0,failure)
    end
end)
test('render cleanup must acknowledge and still match aim/player/camera immediately before entry',function()
    local f=fixture();f.prepare_failure=true;assert(f.m:update(true,'native'));assert(f.entries==0)
    f.prepare_failure=false;assert(f.m:update(true,'native'));assert(f.entries==1);assert(f.m:stop())
    for _,failure in ipairs({'foreign','identity','released'})do
        f=fixture();f.on_prepare=function()
            if failure=='foreign'then f.foreign=true elseif failure=='identity'then f.s.identity='other'else f.s.shoulder_aim=false end
        end
        assert(f.m:update(true,'native'));assert(f.entries==0,failure)
    end
end)
test('cleanup failure retains its lease and retries instead of resuming or reentering',function()
    local f=fixture();assert(f.m:update(true,'native'));f.cleanup_failure=true;f.s.shoulder_aim=false
    assert(not f.m:update(true,'native'));local lease=f.m.lease;assert(lease and f.m:result().cleanup_pending)
    f.s.shoulder_aim=true;assert(not f.m:update(true,'native'));assert(f.m.lease==lease and f.entries==1)
    f.cleanup_failure=false;assert(f.m:update(true,'native'));assert(f.m:is_clean()and f.entries==1)
end)
test('partial entry always retains and retires its cleanup ownership',function()
    local f=fixture();f.partial=true;f.cleanup_failure=true
    assert(not f.m:update(true,'native'));assert(not f.m:is_clean()and f.entries==1)
    assert(not f.m:update(true,'native'));assert(f.entries==1)
    f.cleanup_failure=false;assert(f.m:update(true,'native'));assert(f.m:is_clean()and f.exits==1)
    assert(f.m:update(true,'native'));assert(f.entries==1,'Failed entry must wait for aim release')
end)
test('refused entries wait for aim release rather than repeatedly calling the game',function()
    local f=fixture();f.refused=true;assert(f.m:update(true,'native'));assert(f.entries==1)
    for _=1,10 do assert(f.m:update(true,'native'))end;assert(f.entries==1)
    f.s.shoulder_aim=false;assert(f.m:update(true,'native'));f.s.shoulder_aim=true;f.refused=false
    assert(f.m:update(true,'native'));assert(f.entries==2);assert(f.m:stop())
end)
test('ordinary gameplay ADS takeover and replaced native requests are never forcibly exited',function()
    local f=fixture();assert(f.m:update(true,'native'));f.s.controller_active=true;f.s.shoulder_aim=false
    assert(f.m:update(true,'native'));assert(f.m:is_clean()and f.s.camera_kind==6 and f.exits==0)
    f=fixture();assert(f.m:update(true,'native'));f.s.identity='other';f.s.record=3
    assert(f.m:update(true,'native'));assert(f.m:is_clean()and f.exits==0 and f.entries==1)
end)
test('mode change, disable and Photo handoff release owned native ADS before another view',function()
    for _,failure in ipairs({'mode','disabled','foreign'})do
        local f=fixture();assert(f.m:update(true,'native'));local mode,enabled='native',true
        if failure=='mode'then mode='fird'elseif failure=='disabled'then enabled=false else f.foreign=true end
        assert(f.m:update(enabled,mode));assert(f.m:is_clean()and f.exits==1,failure)
    end
end)
print('FirdPerson optional native ADS leases: '..count..' cases passed')
