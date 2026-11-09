local Markers=dofile(NATIVE_ADS_TEST_ROOT..'/src/aim_markers.lua')
local A,B='0011223344556677','8899aabbccddeeff'
local function fixture()
    local f={enabled=false,mode='pose_offset',fallback=false,foreign=false,pose_reads=0,snapshot_reads=0}
    f.snapshot={safe=true,camera_kind=6,identity='weapon-a',player_identity='player-a',controller_active=true}
    local backend,controller={},{};f.backend=backend
    function backend:snapshot()f.snapshot_reads=f.snapshot_reads+1;return f.snapshot end
    function backend:pin_player_snapshot()f.pin_reads=(f.pin_reads or 0)+1;return f.pin_snapshot end
    function backend:_pose_context(s)assert(s==f.snapshot);f.pose_reads=f.pose_reads+1;return{weapon_object=0x100000}end
    function backend:_read(at,n)
        assert(at==0x100358 and n==8)
        local key=f.snapshot.identity=='weapon-a'and A or B
        return(key:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))
    end
    function controller:is_enabled()return f.enabled end
    function controller:result()return{mode=f.mode}end
    f.current=Markers.source(backend,controller,{foreign=function()return f.foreign end,
        fallback_ready=function()return f.fallback end,fird=function()return f.fird end,
        pinned_ready=function(s)assert(s==f.pin_snapshot);return f.pinned==true end})
    return f
end
local f=fixture()
local target=assert(f.current());assert(target.key==A and target.aiming and not f.enabled)
f.snapshot.camera_kind=4;assert(f.current()==nil,'ordinary third person must keep its HUD')
f.snapshot.camera_kind=6;f.snapshot.controller_active=false
assert(not f.current().aiming,'FP hip fire must keep its markers')
f.enabled=true;f.snapshot.shoulder_aim=true;assert(f.current().aiming)
f.snapshot.camera_kind=4;assert(f.current()==nil,'TP transitions without a head-camera owner must be ignored')
f.fallback=true;assert(f.current().aiming,'verified True FP fallback is a first-person view')
f.mode='native';assert(f.current()==nil,'a native comparison cannot claim a third-person camera')
f.mode='pose_offset';f.snapshot.camera_kind=5;assert(f.current()==nil)
f=fixture();f.snapshot.camera_kind=4
f.fird={is_enabled=function()return true end,weapon_snapshot=f.snapshot,weapon_key=A}
assert(f.current().key==A and f.pose_reads==0 and f.snapshot_reads==0)
f.snapshot={safe=true,camera_kind=4,identity='weapon-b',player_identity='player-a',shoulder_aim=true}
target=assert(f.current(true));assert(target.key==B and target.identity=='weapon-b'and target.aiming)
f.fird.is_enabled=function()return false end;assert(f.current()==nil,'an old Fird snapshot cannot claim third person')
f=fixture();assert(f.current().key==A);assert(f.current().key==A and f.pose_reads==1)
assert(f.current(true).key==A and f.pose_reads==2)
f.snapshot.identity='weapon-b';assert(f.current().key==B and f.pose_reads==3)
f.foreign=true;assert(f.current()==nil)
f.foreign=false;f.snapshot.safe=false;assert(f.current()==nil)
f.snapshot=nil;assert(f.current()==nil)

-- The same saved exception must work across native ADS, True FP and Fird.
f=fixture();local shown={[101]=true,[102]=true};local hud={widgets={101,102}}
local adapter={probe=function()return hud end,same=function(_,a,b)return a==b end,
    visible=function(_,at)return shown[at]end,show=function(_,_,at,value)shown[at]=value end}
local saved={}
local policy=Markers.new({},nil,{current=f.current,settings=function()return saved end,
    save=function(value)saved=value;return true end},adapter)
assert(policy:update());assert(not shown[101]and not shown[102],'native ADS hides without F11')
assert(policy:toggle(A,'weapon-a'));assert(shown[101]and shown[102]and saved[A])
f.enabled=true;f.snapshot.camera_kind=4;f.snapshot.controller_active=false;f.snapshot.shoulder_aim=true;f.fallback=true
assert(policy:update());assert(shown[101]and shown[102],'native ADS exception applies to True FP')
f.enabled=false;f.fallback=false
f.fird={is_enabled=function()return true end,weapon_snapshot=f.snapshot,weapon_key=A}
assert(policy:update());assert(shown[101]and shown[102],'same exception applies to Fird')
assert(policy:toggle(A,'weapon-a'));assert(not shown[101]and not shown[102])
f.fird=nil;assert(policy:update());assert(shown[101]and shown[102],'returning to third person restores native HUD')

-- A body-owned pin may survive missing weapons, waiting, actions and vehicles.
-- It carries no invented weapon key and needs an explicit all-view hide choice.
for _,kind in ipairs({'missing-firearm','unsafe','normal4','vehicle'})do
 f=fixture();f.backend.pin_first_person=true;f.enabled=true;f.pinned=true
 f.pin_snapshot={player_identity='player-a',identity='player-a',safe=false,camera_kind=12,seated=true}
 if kind=='missing-firearm'then f.snapshot=nil
 elseif kind=='unsafe'then f.snapshot.safe=false
 elseif kind=='normal4'then f.snapshot.camera_kind=4;f.fallback=false
 else f.snapshot.camera_kind=12;f.snapshot.safe=false end
 local view=assert(f.current());assert(view.view_only and view.key==nil and view.player_identity=='player-a'and not view.aiming)
 assert(f.current(true)==nil,'pin ownership cannot authorize a fresh per-weapon click')
 shown={[101]=true,[102]=true};hud={widgets={101,102}}
 adapter={probe=function()return hud end,same=function(_,a,b)return a==b end,
  visible=function(_,at)return shown[at]end,show=function(_,_,at,value)shown[at]=value end}
 local global=false
 policy=Markers.new({},nil,{current=f.current,settings=function()return{}end,global_setting=function()return global end},adapter)
 assert(policy:update());assert(shown[101]and shown[102],'pinned hip view keeps both native groups visible')
 f.pin_snapshot.aiming=true;assert(policy:update());assert(not shown[101]and not shown[102])
 f.pin_snapshot.aiming=false;assert(policy:update());assert(shown[101]and shown[102],'pin hip returns both owned groups')
 f.pin_snapshot.shoulder_aim=true;assert(policy:update());assert(not shown[101]and not shown[102])
 f.enabled=false;assert(policy:update());assert(shown[101]and shown[102],'F11 off releases pin-only circle/crosshair suppression')
 f.enabled=true;assert(policy:update());assert(not shown[101]and not shown[102])
 f.foreign=true;assert(policy:update());assert(shown[101]and shown[102],'Photo Mode retains its own HUD')
 f.foreign=false;f.pinned=false;assert(policy:update());assert(shown[101]and shown[102],'lost pin proof cannot claim an action HUD')
end
f=fixture();f.backend.pin_first_person=true;f.enabled=true;f.pinned=true;f.snapshot=nil
f.pin_snapshot={player_identity='player-a'}
view=f.current();assert(view and view.view_only)
shown={[101]=true,[102]=true};hud={widgets={101,102}}
adapter={probe=function()return hud end,same=function(_,a,b)return a==b end,visible=function(_,at)return shown[at]end,show=function(_,_,at,value)shown[at]=value end}
policy=Markers.new({},nil,{current=f.current,settings=function()return{}end},adapter)
assert(policy:update());assert(shown[101]and shown[102],'unset global retains conservative legacy behavior in pin-only views')
print('Aiming markers in every FP view: native ADS/F11 off, True FP, fallback, Fird, hip fire, ownership and shared per-weapon exceptions passed')
