local Markers=dofile(NATIVE_ADS_TEST_ROOT..'/src/aim_markers.lua')
local passed=0
local function test(name,body)
    local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1
end
local A,B='0011223344556677','8899aabbccddeeff'
local function fixture()
    local f={saved={},global_saves=0,probes=0,writes={},logs={},hud={id=1,widgets={101,102}},visible={[101]=true,[102]=true,[999]=true}}
    f.current={key=A,identity='weapon-a',player_identity='player-a',aiming=false}
    local adapter={}
    function adapter:probe(mission_only)
        f.probes=f.probes+1
        if f.unreadable then error('unreadable HUD')end
        if f.retired or(mission_only and f.outside_mission)then return nil end
        return f.hud
    end
    function adapter:same(a,b)return a and b and a.id==b.id end
    function adapter:visible(at)return f.visible[at]end
    function adapter:show(hud,at,value)
        assert(hud==f.hud and(at==101 or at==102),'Unowned target')
        if value and(f.restore_failure or f.restore_at==at)then error('restore pending')end
        f.visible[at]=value;f.writes[#f.writes+1]={at,value}
        if f.partial then f.partial=false;error('failed after write')end
    end
    f.policy=Markers.new({},function(why)f.logs[#f.logs+1]=why end,{
        current=function(fresh)if fresh then return f.fresh or f.current end;return f.current end,
        settings=function()return f.saved end,
        save=function(value)if f.save_failure then return false,'save failed'end;f.saved=value;return true end,
        global_setting=function()if f.global_read_failure then error('global setting unavailable')end;return f.global end,
        save_global=function(value)
            if f.global_save_throw then error('global save error')end
            if f.global_save_failure then return false,'global save failed'end
            f.global_saves=f.global_saves+1;f.global=value;return true
        end,
    },adapter)
    return f
end
test('hip fire keeps native HUD; aiming hides only the two marker groups',function()
    local f=fixture();assert(f.policy:update());assert(#f.writes==0)
    f.current.aiming=true;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102]and f.visible[999])
    for _=1,100 do assert(f.policy:update())end;assert(#f.writes==2)
    f.current.aiming=false;assert(f.policy:update());assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
end)
test('per-weapon opt-in persists and never follows a different weapon',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update())
    assert(f.policy:toggle(A,'weapon-a'));assert(f.saved[A]and f.visible[101]and f.visible[102])
    f.current={key=B,identity='weapon-b',player_identity='player-a',aiming=true}
    assert(f.policy:update());assert(not f.visible[101]and not f.saved[B])
    assert(f.policy:toggle(B,'weapon-b'));assert(f.saved[A]and f.saved[B]and f.visible[101])
    assert(f.policy:toggle(B,'weapon-b'));assert(f.saved[A]and f.saved[B]==nil and not f.visible[101])
    f.current={key=A,identity='weapon-a-respawned',player_identity='player-b',aiming=true}
    assert(f.policy:update());assert(f.visible[101]and f.visible[102])
end)
test('fresh weapon identity rejects stale menu clicks, including same resource',function()
    local f=fixture();f.fresh={key=A,identity='different-instance',player_identity='player-a',aiming=true}
    assert(not f.policy:toggle(A,'weapon-a'));assert(next(f.saved)==nil and #f.writes==0)
    f.fresh.key=B;assert(not f.policy:toggle(A,'weapon-a'));assert(next(f.saved)==nil)
    f.fresh=f.current;f.save_failure=true;assert(not f.policy:toggle(A,'weapon-a'));assert(next(f.saved)==nil)
end)
test('initially hidden markers remain hidden after opt-in and shutdown',function()
    local f=fixture();f.visible[102]=false;f.current.aiming=true;assert(f.policy:update())
    assert(f.policy:toggle(A,'weapon-a'));assert(f.visible[101]and not f.visible[102])
    assert(f.policy:shutdown());assert(not f.visible[102]and not f.policy:toggle(A,'weapon-a'))
end)
test('weapon gaps, ownership loss, camera handoff and disabling release suppression',function()
    for _,reason in ipairs({'gap','owner','foreign','off'})do
        local f=fixture();f.current.aiming=true;assert(f.policy:update())
        f.current=nil;assert(f.policy:update(),reason);assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
    end
end)
test('replaced HUD is never restored with the old HUD state',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update());local n=#f.writes
    f.hud={id=2,widgets={101,102}};f.current=nil;assert(f.policy:update())
    assert(#f.writes==n and f.policy:is_clean())
end)
test('native scene changes restore the still-live groups; retired HUDs are forgotten',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update());f.outside_mission=true
    assert(f.policy:update());assert(f.visible[101]and f.policy:is_clean())
    f.outside_mission=false;assert(f.policy:update());f.retired=true
    assert(f.policy:stop());assert(f.policy:is_clean())
end)
test('partial native writes are owned before the call and restored on failure',function()
    local f=fixture();f.current.aiming=true;f.partial=true
    assert(not f.policy:update());assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
end)
test('failed restoration is retained and retried during shutdown',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update());f.restore_failure=true
    assert(not f.policy:shutdown());assert(not f.policy:is_clean()and f.policy:result().cleanup_pending)
    f.restore_failure=false;assert(f.policy:shutdown());assert(f.visible[101]and f.visible[102])
end)
test('a native re-show is suppressed again; hidden HUD needs no writes',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update());f.visible[101]=true
    assert(f.policy:update());assert(not f.visible[101]and #f.writes==3)
    f=fixture();f.visible[101],f.visible[102]=false,false;f.current.aiming=true
    assert(f.policy:update());assert(f.policy:stop());assert(#f.writes==0)
end)
test('partial restoration completes before a new aim lease starts',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:update());f.restore_at=102
    f.current.aiming=false;assert(not f.policy:update());assert(f.visible[101]and not f.visible[102])
    local n=#f.writes;f.current.aiming=true;assert(not f.policy:update());assert(#f.writes==n and f.visible[101])
    f.restore_at=nil;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102])
    f.current.aiming=false;assert(f.policy:update());assert(f.visible[101]and f.visible[102])
end)
test('global preference can be saved before entering first person without a weapon',function()
    local f=fixture();local legacy=f.saved;legacy[A]=true;legacy.extra='keep';f.current=nil
    assert(f.policy:setting()==true and f.global==nil and f.global_saves==0)
    assert(f.policy:set_setting(true));assert(f.global==true and f.policy:setting()==true)
    assert(f.saved==legacy and legacy[A]==true and legacy.extra=='keep')
    assert(f.global_saves==1 and #f.writes==0 and f.probes==0)
end)
test('global false hides both aimed groups for every owned weapon and restores native hip markers',function()
    local f=fixture();f.saved[A]=true;local legacy=f.saved
    assert(f.policy:set_setting(false));assert(f.visible[101]and f.visible[102]and f.visible[999]and #f.writes==0)
    f.current.aiming=true;assert(f.policy:update());assert(#f.writes==2)
    f.current={key=B,identity='weapon-b',player_identity='player-a',aiming=false}
    assert(f.policy:update());assert(f.visible[101]and f.visible[102])
    f.current.aiming=true;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102])
    assert(f.policy:setting()==false and f.policy:target().allowed==false)
    assert(f.saved==legacy and f.saved[A]==true and f.saved[B]==nil)
end)
test('explicit global hide covers initialized ship HUD circle and crosshair while legacy stays mission-only',function()
    local f=fixture();f.outside_mission=true;f.current.aiming=true
    assert(f.policy:update());assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
    assert(f.policy:set_setting(false));assert(not f.visible[101]and not f.visible[102]and f.visible[999])
    assert(f.policy:set_setting(true));assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
end)
test('pin-only action and vehicle owners hide both groups only for an explicit global false choice',function()
    local f=fixture();f.outside_mission=true
    f.current={view_only=true,identity='player-a:pinned-view',player_identity='player-a',aiming=false}
    assert(f.policy:update());assert(#f.writes==0 and f.policy:target()==nil)
    assert(f.policy:set_setting(false));assert(f.visible[101]and f.visible[102]and f.visible[999])
    f.current.aiming=true;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102])
    assert(f.policy:target()==nil and not f.policy:toggle(A,'player-a:pinned-view'))
    f.visible[102]=true;assert(f.policy:update());assert(not f.visible[102])
    f.current.aiming=false;assert(f.policy:update());assert(f.visible[101]and f.visible[102])
    f.current.aiming=true;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102])
    f.current=nil;assert(f.policy:update());assert(f.visible[101]and f.visible[102]and f.policy:is_clean())
end)
test('pin-only views cannot borrow or save legacy weapon preferences',function()
    local f=fixture();f.saved[A]=true
    f.current={view_only=true,identity='player-a:pinned-view',player_identity='player-a',aiming=true}
    assert(f.policy:update());assert(#f.writes==0 and f.policy:target()==nil)
    assert(not f.policy:toggle(A,'player-a:pinned-view'));assert(f.saved[A]and f.global==nil)
    f.current.key=A;assert(f.policy:set_setting(false));assert(#f.writes==0 and f.policy:is_clean())
end)
test('global true releases only owned suppression and preserves native hidden groups',function()
    local f=fixture();f.visible[102]=false;f.current.aiming=true
    assert(f.policy:set_setting(false));assert(not f.visible[101]and not f.visible[102])
    assert(f.policy:set_setting(true));assert(f.visible[101]and not f.visible[102]and f.policy:is_clean())
    f.current={key=B,identity='weapon-b',player_identity='player-a',aiming=true}
    local writes=#f.writes;assert(f.policy:update());assert(#f.writes==writes and f.visible[999])
end)
test('ordinary third person stays native even with global false',function()
    local f=fixture();f.current=nil;assert(f.policy:set_setting(false));assert(#f.writes==0 and f.probes==0)
    f.visible[101]=false;assert(f.policy:update());assert(not f.visible[101]and f.visible[102]and f.visible[999])
    assert(f.policy:set_setting(true));assert(not f.visible[101]and #f.writes==0)
end)
test('unset global choice preserves legacy aimed-only behavior and per-weapon data',function()
    local f=fixture();f.saved[A]=true;local legacy=f.saved
    assert(f.policy:setting()==true);assert(f.policy:update());assert(#f.writes==0 and f.global==nil)
    f.current.aiming=true;assert(f.policy:update());assert(#f.writes==0)
    f.current={key=B,identity='weapon-b',player_identity='player-a',aiming=false}
    assert(f.policy:setting()==true);assert(f.policy:update());assert(#f.writes==0)
    f.current.aiming=true;assert(f.policy:setting()==false);assert(f.policy:update());assert(not f.visible[101])
    assert(f.saved==legacy and f.saved[A]and f.global==nil and f.global_saves==0)
end)
test('legacy per-weapon toggles cannot pretend to override an explicit global choice',function()
    for _,value in ipairs({true,false})do
        local f=fixture();assert(f.policy:set_setting(value));local legacy=f.saved
        local done,why=f.policy:toggle(A,'weapon-a')
        assert(done==false and why:find('Show aim markers',1,true)and f.saved==legacy and next(legacy)==nil)
    end
end)
test('global save refusal or exception does not migrate settings or touch the HUD',function()
    for _,failure in ipairs({'global_save_failure','global_save_throw'})do
        local f=fixture();f[failure]=true;f.saved[A]=true
        local done,why=f.policy:set_setting(false)
        assert(done==false and type(why)=='string'and f.global==nil and f.saved[A]==true)
        assert(f.global_saves==0 and #f.writes==0 and f.probes==0)
    end
end)
test('global setting accepts only booleans and cannot change during shutdown',function()
    local f=fixture()
    for _,value in ipairs({1,0,'false',{}})do assert(f.policy:set_setting(value)==false)end
    assert(f.policy:set_setting(nil)==false and f.global_saves==0 and f.global==nil)
    assert(f.policy:shutdown());assert(f.policy:set_setting(true)==false and f.global_saves==0)
end)
test('external global changes refresh suppression without changing saved weapon choices',function()
    local f=fixture();f.saved[A]=true;f.current.aiming=true;f.global=false;assert(f.policy:update());assert(not f.visible[101])
    f.global=true;assert(f.policy:update());assert(f.visible[101]and f.policy:setting())
    f.global=nil;assert(f.policy:update());assert(f.saved[A]and f.global_saves==0)
end)
test('saved show choice retains failed HUD cleanup and retries it',function()
    local f=fixture();f.current.aiming=true;assert(f.policy:set_setting(false));f.restore_failure=true
    assert(f.policy:set_setting(true)==false and f.global==true and f.policy:setting()==true)
    assert(not f.policy:is_clean()and f.policy:result().cleanup_pending)
    f.restore_failure=false;assert(f.policy:update());assert(f.policy:is_clean()and f.visible[101]and f.visible[102])
end)
test('UI setting reads do not save or change visibility even if the source is unavailable',function()
    local f=fixture();f.saved[A]=true
    for _=1,100 do assert(f.policy:setting()==true)end
    f.global_read_failure=true;f.current=nil;assert(f.policy:setting()==true)
    assert(f.global_saves==0 and #f.writes==0 and f.probes==0 and f.global==nil)
end)
test('one explicit hide choice before entry keeps hip visible then hides the first owned aim view',function()
    local f=fixture();local target=f.current;f.current=nil
    assert(f.policy:setting()==true);assert(f.policy:set_setting(false));assert(#f.writes==0)
    f.current=target;assert(f.policy:update());assert(f.visible[101]and f.visible[102])
    target.aiming=true;assert(f.policy:update());assert(not f.visible[101]and not f.visible[102])
    assert(f.global==false and f.global_saves==1 and next(f.saved)==nil)
end)
test('native adapter pins code and exact child parents before using the setter',function()
    local base,root,state,context,world=0x10000000,0x20000000,0x30000000,0x40000000,0x50000000
    local crosshair=root+0x24e340+0x19a678;local fixed,moving=crosshair+0x110,crosshair+0x220
    local raw,words,pointers={},{},{}
    local signatures={
        [0x12e4cc0]='4883ec28448b014c8bd1418bc0458bc883e0ef4183c91084d2440f44c8448909',
        [0x1635b6f]='4d8da510010000',[0x1635c01]='498db520020000',
        [0x117c72d]='498d8f78a61900e887934b00498d9778a61900'}
    for offset,value in pairs(signatures)do raw[base+offset]=(value:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))end
    pointers[base+0x2ce1508]=state;pointers[base+0x2e28788]=root
    pointers[crosshair+0xf0]=root+0x820;pointers[crosshair+0xf8]=context;pointers[context+0x10]=world
    words[root+0x24e334]=1;words[state+0xac29c]=4;words[context]=1
    for _,at in ipairs({fixed,moving})do pointers[at+0xf0]=crosshair;pointers[at+0xf8]=context;words[at]=0x1010 end
    local b={}
    function b:_module(scope)assert(scope=='identity','HUD checks must not require packed firearm code');return base end
    function b:_read(at,n)local value=assert(raw[at]);assert(#value==n);return value end
    function b:_u32(at)return assert(words[at])end
    function b:_u8(at)return assert(words[at])end
    function b:_ptr(at)return assert(pointers[at])end
    local writes={};local adapter=Markers.Adapter.new(b,function(at,shown)
        assert(at==fixed or at==moving);words[at]=shown and 0x1010 or 0x1000;writes[#writes+1]=at
    end)
    local hud=adapter:probe(true);assert(hud.widgets[1]==fixed and hud.widgets[2]==moving)
    words[state+0xac29c]=3;assert(adapter:probe(true)==nil)
    local ship=assert(adapter:probe(false));assert(ship.widgets[1]==fixed and ship.widgets[2]==moving)
    words[state+0xac29c]=4
    adapter:show(hud,fixed,false);assert(not adapter:visible(fixed)and adapter:visible(moving))
    assert(not pcall(adapter.show,adapter,hud,crosshair,false))
    pointers[moving+0xf0]=root;assert(not pcall(adapter.show,adapter,hud,fixed,true));assert(#writes==1)
    pointers[moving+0xf0]=crosshair;raw[base+0x12e4cc0]=string.rep('\0',32)
    assert(not pcall(adapter.probe,adapter,true));assert(#writes==1)
end)
print('Aiming-marker policy and HUD binding: '..passed..' passed')
