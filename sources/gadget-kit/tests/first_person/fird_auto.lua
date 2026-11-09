local Auto=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_auto.lua')
local cases=0
local function pass()cases=cases+1 end
local function fixture(known)
    local f={time=0,stops=0,begins=0,captures=0,enters=0,samples=0,clean=true,ready=true,live=false}
    f.target={safe=true,neutral=true,camera_kind=4,controller_active=false,known=known==true,
        player_identity='player',weapon_identity='weapon1',weapon_key='resource1'}
    function f:reference()return{identity=self.target.player_identity,weapon_identity=self.target.weapon_identity,weapon_key=self.target.weapon_key}end
    local callbacks={
        stop=function()f.stops=f.stops+1;if f.stop_throw then error('cleanup error')end;if not f.clean then return false,'cleanup pending'end;f.live=false;return true end,
        target=function()if f.target_throw then error('target error')end;return f.target end,
        foreign=function()return f.foreign==true end,
        running=function()return f.live end,
        cached=function()return f.cached or f:reference()end,
        begin_fp=function()f.begins=f.begins+1;if f.begin_refuse then return false,'entry refused'end;f.target.camera_kind=6;return true end,
        sample=function()f.samples=f.samples+1;if f.sample_throw then error('sample error')end;return f.ready,f.ready and {generation=17}or 'settling'end,
        capture=function(token)assert(token.generation==17);f.captures=f.captures+1;if f.capture_refuse then return nil,'capture refused'end;return f:reference()end,
        enter=function(c)f.enters=f.enters+1;if f.enter_refuse then return false,'Fird entry refused'end;f.entered=c;f.live=true;f.target.known=true;return true end,
    }
    f.callbacks=callbacks
    f.auto=Auto.new(callbacks,function()return f.time end)
    function f:step(dt)self.time=self.time+(dt or .1);return self.auto:update()end
    function f:begin()local before=self.begins;assert(self.auto:request());assert(self:step());assert(self.begins==before);assert(self:step());return self end
    function f:handoff()assert(self:step());assert(self.auto:is_pending()and not self.auto:uses_fp());self.target.camera_kind=4;assert(self:step());assert(self.enters==0);assert(self:step());return self end
    return f
end
local f=fixture():begin();assert(f.begins==1 and f.auto:uses_fp());f:handoff()
assert(f.enters==1 and f.captures==1 and not f.auto:is_pending()and f.auto:is_enabled());pass()
for i=1,10 do assert(f:step())end;assert(f.begins==1 and f.enters==1);pass()
f=fixture(true):begin();assert(f.enters==1 and f.begins==0 and f.captures==0);pass()
f=fixture();f.clean=false;assert(f.auto:request());for i=1,4 do assert(f:step())end;assert(f.begins==0)
f.clean=true;assert(f:step());assert(f.begins==0);assert(f:step());assert(f.begins==1);pass()
f=fixture();f.foreign=true;f:begin();assert(f.begins==0);f.foreign=false;f.target.neutral=false
assert(f:step());assert(f.begins==0);f.target.neutral=true;assert(f:step());assert(f.begins==1);pass()
f=fixture():begin();assert(f.auto:cancel());assert(not f.auto:is_enabled()and not f.auto:is_pending()and not f.auto:uses_fp())
for i=1,5 do assert(f:step())end;assert(f.enters==0 and f.captures==0);pass()
f=fixture():begin();f.ready=false;for i=1,6 do assert(f:step())end;assert(f.begins==1 and f.samples==6 and f.captures==0)
f.ready=true;f:handoff();assert(f.enters==1);pass()
for _,field in ipairs({'controller_active','neutral','safe'})do
    f=fixture():begin();f.target[field]=field=='controller_active';assert(f:step());assert(not f.auto:uses_fp())
    assert(f:step());assert(f:step());assert(f.begins==1 and f.captures==0)
    f.target[field]=field~='controller_active';f.target.camera_kind=4;assert(f:step(.3));assert(f.begins==2);pass()
end
f=fixture():begin();f.foreign=true;assert(f:step());assert(f:step());assert(f:step());assert(f.begins==1)
f.foreign=false;f.target.camera_kind=4;assert(f:step(.3));assert(f.begins==2);pass()
for _,field in ipairs({'player_identity','weapon_identity','weapon_key'})do
    f=fixture():begin();f.target[field]=f.target[field]..'-changed';assert(f:step());assert(f:step());assert(f:step());assert(f.captures==0)
    f.target.camera_kind=4;assert(f:step(.3));assert(f.begins==2);pass()
end
f=fixture():begin();f.ready=false;assert(not f:step(3));assert(f.auto:is_enabled()and f.auto:is_pending())
f.target.camera_kind=4;for i=1,8 do assert(f:step())end;assert(f.begins==1 and f.enters==0)
f.target.weapon_identity='weapon2';assert(f:step());assert(f.begins==2);pass()
for _,failure in ipairs({'begin_refuse','capture_refuse','enter_refuse','sample_throw'})do
    f=fixture();f[failure]=true
    assert(f.auto:request());assert(f:step());local ok=f:step()
    if failure~='begin_refuse'then assert(ok);ok=f:step()end
    if failure=='enter_refuse'then assert(ok);f.target.camera_kind=4;assert(f:step());ok=f:step()end
    assert(not ok);f.target.camera_kind=4
    for i=1,10 do assert(f:step())end;assert(f.begins==1 and f.auto:is_enabled())
    assert(f.auto:cancel());f[failure]=false;f:begin();assert(f.begins==2);pass()
end
f=fixture(true);f.cached={identity='old-player',weapon_identity='weapon1',weapon_key='resource1'}
assert(f.auto:request());assert(f:step());assert(not f:step());assert(f.enters==0 and f.begins==0);pass()
f=fixture(true):begin();f.target.weapon_identity='weapon2';f.target.weapon_key='resource2';f.target.known=true
for i=1,5 do assert(f:step())end;assert(f.begins==0 and f.enters==1);pass()
f.target.known=false;assert(f:step());assert(f.stops==2);assert(f:step());assert(f.auto:is_pending())
assert(f:step());assert(f.begins==0);assert(f:step(.3));assert(f.begins==1);pass()
f=fixture():begin();assert(f:step());f.target.camera_kind=4;f.target.weapon_identity='replacement';assert(f:step());assert(f:step())
assert(f.enters==0);assert(f:step(.3));assert(f:step());assert(f.begins==2);pass()
f=fixture():begin();assert(f:step());f.target.camera_kind=6;f.target.controller_active=true
assert(f:step());assert(f:step());assert(f:step());assert(f.begins==1 and f.enters==0)
f.target.controller_active=false;f.target.camera_kind=4;assert(f:step());assert(f.enters==1);pass()
f=fixture():begin();f.time=-1;assert(not f.auto:update());assert(f.stops==3 and not f.auto:uses_fp())
f.time=1;f.target.camera_kind=4;for i=1,5 do assert(f:step())end;assert(f.begins==1);pass()
f=fixture();f.stop_throw=true;assert(f.auto:request());assert(not f:step());assert(f.begins==0)
f.stop_throw=false;assert(f:step());assert(f:step());assert(f.begins==1);pass()
f=fixture():begin();assert(f:step());f.target.camera_kind=4;f.clean=false
for i=1,5 do assert(f:step())end;assert(f.enters==0 and f.begins==1 and f.captures==1)
f.clean=true;assert(f:step());assert(f.enters==0);assert(f:step());assert(f.enters==1 and f.captures==1);pass()
f=fixture();f.begin_refuse=true;assert(f.auto:request());assert(f:step());assert(not f:step())
for i=1,5 do assert(f.auto:request());assert(f:step())end;assert(f.begins==1)
f.target.weapon_identity='weapon2';f.begin_refuse=false;assert(f:step());assert(f.begins==2);pass()
f=fixture(true);f.cached={identity='player',weapon_identity='retired-instance',weapon_key='resource1'}
assert(f.auto:request());assert(f:step());assert(not f:step());assert(f.enters==0);pass()
f=fixture(true):begin();f.live=false;assert(not f:step());assert(f.auto:is_pending())
for i=1,8 do assert(f:step())end;assert(f.enters==1 and f.begins==0)
f.target.weapon_identity='weapon2';assert(f:step());assert(f.enters==2 and f.begins==0);pass()
f=fixture(true):begin();f.live=false;f.target.player_identity='new-player'
assert(f:step());assert(f:step());assert(f:step(.3));assert(f.enters==2 and f.begins==0);pass()
f=fixture(true);f.target.cached_ready=false;f:begin();assert(f.begins==1 and f.enters==0)
f.target.cached_ready=true;f:handoff();assert(f.enters==1);pass()
f=fixture(true):begin();f.target.cached_ready=false;assert(f:step());assert(f:step());assert(f.auto:is_pending())
assert(f:step());assert(f:step(.3));assert(f.begins==1);pass()
f=fixture():begin();f.target.camera_kind=4;f.ready=false
for i=1,5 do assert(f:step())end;assert(f.begins==1 and f.samples==5 and f.captures==0 and f.auto:uses_fp())
f.ready=true;assert(f:step());assert(f.captures==0);f.target.camera_kind=6;f:handoff();assert(f.enters==1 and f.begins==1);pass()
f=fixture():begin();f.target.camera_kind=4;assert(not f:step(3));for i=1,5 do assert(f:step())end
assert(f.begins==1 and f.captures==0 and f.auto:is_enabled());pass()
local function warming_fixture()
    local f=fixture();f.initializes,f.warm_starts,f.warm_exits=0,0,0
    local stop=f.callbacks.stop
    f.callbacks.stop=function()
        local ready,why=stop()
        if ready==true and f.warm then f.warm=false;f.warm_exits=f.warm_exits+1;f.target.camera_kind=4 end
        return ready,why
    end
    f.callbacks.initialize=function(s)
        f.initializes=f.initializes+1
        assert(s.weapon_identity==f.target.weapon_identity)
        if f.initialized then
            if f.warm then f.warm=false;f.warm_exits=f.warm_exits+1;f.target.camera_kind=4 end
            return true
        end
        if not f.warm then f.warm=true;f.warm_starts=f.warm_starts+1;f.target.camera_kind=6 end
        if f.initialize_throw then error('uncertain initialization entry')end
        return false,'initializing native FP pages'
    end
    return f
end
f=warming_fixture():begin();assert(f.initializes==1 and f.warm_starts==1 and f.begins==0)
assert(f.auto.phase=='initialize'and f.auto:is_pending()and not f.auto:uses_fp())
assert(f:step());assert(f.initializes==2 and f.warm_starts==1 and f.begins==0 and f.samples==0)
f.initialized=true;assert(f:step());assert(not f.warm and f.warm_exits==1 and f.begins==0)
assert(f:step());assert(f.begins==1 and f.auto:uses_fp());f:handoff();assert(f.enters==1);pass()

f=warming_fixture();f.initialized=true;f:begin();assert(f.warm_starts==0 and f.begins==1 and f.initializes==1);pass()

f=warming_fixture():begin();f.foreign=true;f.clean=false;assert(f:step());assert(f.auto.phase=='cleanup')
for i=1,3 do assert(f:step())end;assert(f.warm and f.initializes==1 and f.begins==0)
f.foreign=false;f.clean=true;f.initialized=true;assert(f:step());assert(not f.warm and f.begins==0)
assert(f:step());assert(f.begins==1 and f.warm_starts==1);pass()

f=warming_fixture():begin();assert(not f:step(3.1));assert(f.auto:is_enabled()and f.auto:is_pending())
for i=1,8 do assert(f:step())end
assert(not f.warm and f.warm_exits==1 and f.warm_starts==1 and f.begins==0)
local calls=f.initializes;for i=1,6 do assert(f:step())end;assert(f.initializes==calls)
f.target.weapon_identity='weapon2';f.initialized=true;assert(f:step());assert(f.begins==1);pass()

f=warming_fixture():begin();assert(f.auto:cancel());assert(f.callbacks.stop());assert(not f.warm and f.warm_exits==1)
local calls=f.initializes;for i=1,6 do assert(f:step())end;assert(f.initializes==calls and f.begins==0 and f.enters==0);pass()

f=warming_fixture();f.initialize_throw=true;assert(f.auto:request());assert(f:step());assert(not f:step())
assert(f.warm and f.begins==0);for i=1,6 do assert(f:step())end
assert(not f.warm and f.warm_exits==1 and f.warm_starts==1 and f.begins==0);pass()
print('Fird automatic entry: '..cases..' lifecycle, capture, interruption, cache and bounded retry cases passed')
