local P=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_presentation.lua')
local cases=0
local function pass()cases=cases+1 end
local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
local function fixture(mode)
    local f={time=1,calls={},mode=mode or 0,foreign=false,dead=false,ack=false,reads=0}
    local function ctx(ref)return{unit=ref,index=ref,generation=1,object=ref*100,registry=77,units=88,generations=99}end
    f.s={identity='weapon1',player_identity='player',base=1000,context=2000,camera=3000,world=4000,
        avatar_owner=5000,avatar_index=0,avatar=11,body=12,viewmodel=13,weapon=14,weapon_unit=15,record=6000,
        safe=true,camera_kind=4,controller_active=false}
    f.state={mode_address=7000,appearance='appearance',body=ctx(12),fps=ctx(13),weapon=ctx(15),
        world=4000,body_matrices=8000,fps_matrices=9000}
    local deps={clock=function()return f.time end,foreign=function()return f.foreign end,
        retired=function()return f.dead end,
        probe=function()
            f.reads=f.reads+1;if f.unreadable then error('probe unreadable')end
            local v=copy(f.state);v.mode=f.mode;v.snapshot=copy(f.s)
            local parent=f.null and 0 or f.foreign_parent and 3333 or f.ack and v.fps.object or v.body.object
            local external=f.null and 0 or f.ack and v.fps_matrices or v.body_matrices
            v.parts={{kind='arm',parent=parent,external=external,world=v.world},{kind='weapon',parent=parent,external=external,world=v.world}}
            if f.weapon_body then v.parts[2].parent=v.body.object;v.parts[2].external=v.body_matrices end
            if f.weapon_cross then v.parts[2].parent=v.body.object;v.parts[2].external=v.fps_matrices end
            return v
        end,
        invoke=function(_,s,enabled)
            f.calls[#f.calls+1]={enabled=enabled,identity=s.identity,player=s.player_identity}
            if f.call_unreadable then f.unreadable=true end
            if not f.defer_mode then f.mode=enabled and 1 or 0 end
            if f.throw then error('uncertain queued presentation')end
            if f.refuse then return false,'presentation refused'end
            return true
        end}
    f.deps=deps;f.m=P.new({},nil,deps)
    function f:start()return self.m:start(copy(self.s))end
    function f:update(dt)self.time=self.time+(dt or .1);return self.m:update(copy(self.s))end
    return f
end
local f=fixture();assert(f:start());assert(#f.calls==1 and f.calls[1].enabled and not f.m:result().ready)
assert(f:update());assert(not f.m:result().ready);f.ack=true;assert(f:update());assert(f.m:result().ready)
assert(f.m:stop());assert(f.mode==0 and #f.calls==2 and not f.calls[2].enabled and f.m:is_clean());pass()
f=fixture(1);f.ack=true;assert(f:start());assert(#f.calls==0 and f.m:result().borrowed and not f.m:result().ready)
assert(f:update());assert(f.m:result().ready);assert(f.m:stop());assert(f.mode==1 and #f.calls==0);pass()
f=fixture();f.foreign=true;assert(not f:start());assert(f.m:is_clean()and #f.calls==0)
f.foreign=false;f.s.camera_kind=6;assert(not f:start());assert(#f.calls==0);pass()
f=fixture();assert(f:start());f.null=true;assert(f:update());assert(not f.m:result().ready)
f.null=false;f.ack=true;assert(f:update());assert(f.m:result().ready);assert(f.m:stop());pass()
f=fixture();assert(f:start());f.null=true;assert(not f:update(.6));assert(not f.m:is_clean());f.null=false;assert(f.m:stop());pass()
f=fixture();assert(f:start());f.foreign_parent=true;assert(not f:update());assert(#f.calls==1)
assert(not f.m:stop());assert(#f.calls==1);f.foreign_parent=false;assert(f.m:stop());pass()
f=fixture();f.foreign_parent=true;assert(not f:start());assert(f.m:is_clean()and #f.calls==0);pass()
f=fixture();assert(f:start());f.s.camera_kind=6;f.s.controller_active=true;assert(f:update());assert(not f.m:result().ready)
assert(not f.m:stop());assert(#f.calls==1);f.mode=0;assert(f.m:stop());assert(f.m:is_clean()and #f.calls==1);pass()
f=fixture();assert(f:start());f.foreign=true;assert(f:update());assert(not f.m:stop());assert(#f.calls==1)
f.foreign=false;assert(f.m:stop());assert(#f.calls==2);pass()
f=fixture();assert(f:start());f.mode=0;assert(not f:update());assert(f.m:is_clean()and #f.calls==1);pass()
f=fixture();assert(f:start());f.dead=true;f.unreadable=true;assert(f.m:stop());assert(f.m:is_clean()and #f.calls==1);pass()
f=fixture();assert(f:start());f.s.player_identity='replacement';assert(not f:update());assert(not f.m:stop());assert(#f.calls==1)
f.dead=true;assert(f.m:stop());pass()
f=fixture();f.throw=true;assert(not f:start());assert(not f.m:is_clean()and f.mode==1)
f.throw=false;assert(f.m:stop());assert(f.mode==0 and #f.calls==2);pass()
f=fixture();assert(f:start());f.defer_mode=true;assert(not f.m:stop());assert(#f.calls==2)
assert(not f.m:stop());assert(#f.calls==2);f.mode=0;assert(f.m:stop());assert(f.m:is_clean());pass()
f=fixture();assert(f:start());f.ack=true;assert(f:update());f.s.identity='weapon2';f.s.weapon=24;f.s.weapon_unit=25
f.state.weapon={unit=25,index=25,generation=2,object=2500,registry=77,units=88,generations=99};f.ack=false
assert(f:update());assert(#f.calls==2 and f.calls[2].enabled and f.calls[2].identity=='weapon2')
assert(f:update());assert(#f.calls==2);f.ack=true;assert(f:update());assert(f.m:result().ready)
assert(f.m:stop());assert(#f.calls==3 and not f.calls[3].enabled and f.calls[3].identity=='weapon2');pass()
f=fixture(1);f.ack=true;assert(f:start());assert(f:update());f.s.identity='weapon2';f.ack=false
assert(f:update());assert(#f.calls==0);assert(f.m:stop());assert(f.mode==1);pass()
f=fixture();assert(f:start());f.unreadable=true;assert(not f.m:stop());assert(#f.calls==1)
f.unreadable=false;assert(f.m:stop());assert(#f.calls==2);pass()
assert(f.m:stop());assert(#f.calls==2);pass()
f=fixture();assert(f:start());f.unreadable=true;assert(f:update());assert(not f.m:result().ready and #f.calls==1)
f.unreadable=false;f.ack=true;assert(f:update());assert(f.m:result().ready);assert(f.m:stop());pass()
f=fixture();assert(f:start());f.unreadable=true;assert(not f:update(.6));assert(#f.calls==1 and not f.m:is_clean())
f.unreadable=false;assert(f.m:stop());pass()
f=fixture();f.weapon_body=true;assert(f:start());f.ack=true;assert(f:update());assert(f.m:result().ready)
assert(f.m:stop());assert(f.mode==0);pass()
f=fixture();assert(f:start());f.ack=true;f.weapon_cross=true;assert(f:update());assert(not f.m:result().ready and #f.calls==1)
f.weapon_cross=false;f.weapon_body=true;assert(f:update());assert(f.m:result().ready);assert(f.m:stop());pass()
f=fixture();f.frame=7;f.deps.frame=function()return f.frame end;f.ack=true
assert(f:start());assert(f:update());assert(not f.m:result().ready and #f.calls==1)
f.frame=8;assert(f:update());assert(f.m:result().ready)
f.s.identity='weapon2';assert(f:update());assert(not f.m:result().ready)
assert(f:update());assert(not f.m:result().ready);f.frame=9;assert(f:update());assert(f.m:result().ready)
assert(f.m:stop());pass()
print('Fird native presentation lease: '..cases..' ownership, asynchronous attachment, borrowed mode, ADS/foreign and swap cases passed')
