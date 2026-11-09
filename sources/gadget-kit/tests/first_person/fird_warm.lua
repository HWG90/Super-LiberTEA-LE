local M=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_warm.lua')
local cases=0
local function pass()cases=cases+1 end
local function fixture(initialized)
    local f={time=1,frame=1,initialized=initialized==true,starts=0,finishes=0,foreign=false,cleanup=true}
    f.s={identity='weapon1',weapon_identity='weapon1',player_identity='player',safe=true,neutral=true,camera_kind=4,controller_active=false}
    local b={}
    function b:snapshot()if f.unreadable then return nil,'unreadable owner'end;local v={};for k,x in pairs(f.s)do v[k]=x end;return v end
    function b:camera_ready()return f.initialized,'cold FP evaluator'end
    function b:warm_start(s)
        f.starts=f.starts+1
        if f.refuse then return false,'entry refused'end
        local l={origin=s};b.warm_lease=l;f.s.camera_kind=6
        if f.partial then l.cleanup_only=true;l.error='uncertain entry'end
        return true,l
    end
    function b:warm_finish(l)
        assert(l==b.warm_lease);f.finishes=f.finishes+1
        if f.foreign or not f.cleanup then return false,'cleanup pending'end
        b.warm_lease=nil;if not f.player_ads then f.s.camera_kind=4 end;return true
    end
    f.b=b;f.m=M.new(b,function()return f.time end,function()return f.foreign end,function()return f.frame end)
    function f:step(dt,advance)self.time=self.time+(dt or .1);if advance~=false then self.frame=self.frame+1 end;return self.m:update(self.s)end
    return f
end
local f=fixture(true);assert(f.m:update(f.s));assert(f.starts==0 and f.m:is_clean());pass()
f=fixture();assert(not f.m:update(f.s));assert(f.starts==1 and not f.m:is_clean());f.initialized=true
assert(not f:step(.1,false));assert(f.finishes==0)
assert(not f:step());assert(f.finishes==1 and f.m:is_clean())
assert(not f:step(.1,false));assert(f:step());assert(f.starts==1);pass()
for _,key in ipairs({'foreign','controller_active','neutral','safe'})do
    f=fixture();if key=='foreign'then f.foreign=true else f.s[key]=key=='controller_active'end
    assert(not f.m:update(f.s));assert(f.starts==0 and f.m:is_clean());pass()
end
f=fixture();assert(not f.m:update(f.s));f.cleanup=false;f.initialized=true
for i=1,4 do assert(not f:step())end;assert(f.starts==1 and not f.m:is_clean())
f.cleanup=true;assert(not f:step());assert(f:step());assert(f.starts==1);pass()
f=fixture();assert(not f.m:update(f.s));local ok,why=pcall(f.step,f)
assert(not ok and tostring(why):find('cold FP evaluator',1,true));assert(f.finishes==1 and f.m:is_clean())
assert(not pcall(f.step,f));assert(f.starts==1);assert(f.m:stop());pass()
f=fixture();assert(not f.m:update(f.s));f.cleanup=false
assert(not f:step(3));assert(f.starts==1 and not f.m:is_clean())
f.cleanup=true;assert(not pcall(f.step,f));assert(f.m:is_clean()and f.starts==1);pass()
f=fixture();f.partial=true;assert(not f.m:update(f.s));assert(not pcall(f.step,f));assert(f.finishes==1 and f.m:is_clean());pass()
f=fixture();f.refuse=true;assert(not pcall(f.m.update,f.m,f.s));assert(f.starts==1 and f.m:is_clean());pass()
f=fixture();assert(not f.m:update(f.s));f.foreign=true;assert(not f:step());assert(not f.m:is_clean()and f.starts==1)
f.foreign=false;f.initialized=true;assert(not f:step());assert(f:step());assert(f.starts==1);pass()
f=fixture();assert(not f.m:update(f.s));f.player_ads=true;f.s.controller_active=true;f.initialized=true
assert(not f:step());assert(f.m:is_clean()and f.starts==1)
for i=1,3 do assert(not f:step())end;f.player_ads=false;f.s.controller_active=false;f.s.camera_kind=4
assert(f:step());assert(f.starts==1);pass()
f=fixture();assert(not f.m:update(f.s));f.s.identity='weapon2';f.s.weapon_identity='weapon2';f.initialized=true
assert(not f:step());for i=1,3 do assert(not f:step())end;assert(f.starts==1)
assert(f.m:stop());assert(f.m:update(f.s));assert(f.starts==1);pass()
f=fixture();assert(not f.m:update(f.s));f.cleanup=false;assert(not f.m:stop());assert(not f.m:is_clean())
f.cleanup=true;assert(f.m:stop());assert(f.m:is_clean());pass()
f=fixture();f.b.warm_lease={origin=f.s};assert(not f.m:is_clean());assert(f.m:stop());assert(f.m:is_clean()and f.starts==0);pass()
f=fixture();assert(not f.m:update(f.s));f.unreadable=true;f.initialized=true
assert(not f:step());assert(f.starts==1);f.unreadable=false;assert(not f:step());assert(f:step());pass()
print('Fird cold warm transaction: '..cases..' frame barriers, single entry, cleanup, failures and interruptions passed')
