local root = assert(NATIVE_ADS_TEST_ROOT)
local original_stingray=stingray
stingray={Application={time_since_launch=function()return 100 end}}
local Controller = dofile(root .. '/src/controller.lua')
local Menu = dofile(root .. '/src/menu.lua')
local Editor = dofile(root .. '/src/placement_editor.lua')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function contains(value, fragment) assert(tostring(value):find(fragment, 1, true), tostring(value)) end
local function fov_module(b)
    return {new=function()
        local f={}
        function f:is_clean()return not b.fov_active and not b.fov_pending end
        function f:stop()
            b.fov_stops=(b.fov_stops or 0)+1
            if b.fov_end_failure then b.fov_pending=true;return false,'fixture FOV cleanup pending' end
            b.fov_active,b.fov_pending=false,false;return true
        end
        function f:shutdown()return self:stop()end
        function f:update(c)
            b.fov_updates=(b.fov_updates or 0)+1
            if b.fov_pending or not c:is_enabled() then return self:stop() end
            if c:result().mode=='pose_offset' and c:result().phase=='running' and c.lease then b.fov_active=true end
            return true
        end
        function f:result()return {armed=b.fov_active or false,cleanup_pending=b.fov_pending or false}end
        function f:status()return 'fixture FOV'end
        function f:preflight()return true end
        return f
    end}
end
local function camera_module(b)
    return {new=function()
        local camera={}
        function camera:is_clean()return not b.camera_active and not b.camera_pending end
        function camera:prepare()
            b.camera_prepares=(b.camera_prepares or 0)+1
            if b.camera_prepare_failure then return false,'fixture head-camera prepare refused' end
            b.camera_active=true;return true
        end
        function camera:preflight()return true end
        function camera:stop()
            b.camera_stops=(b.camera_stops or 0)+1
            if b.camera_end_failure then b.camera_pending=true;return false,'fixture head-camera cleanup pending' end
            b.camera_active,b.camera_pending=false,false;return true
        end
        function camera:shutdown()return self:stop()end
        function camera:update(c)
            b.camera_updates=(b.camera_updates or 0)+1
            if b.camera_pending or not c:is_enabled() or c:result().mode~='pose_offset' then return self:stop() end
            b.camera_active=true;return true
        end
        function camera:status()return 'fixture head camera'end
        function camera:result()return {armed=b.camera_active or false,cleanup_pending=b.camera_pending or false}end
        return camera
    end}
end
local function motion_module(b)
    return {new=function()
        local motion={}
        function motion:reset()b.motion_resets=(b.motion_resets or 0)+1;return true end
        function motion:update()b.motion_updates=(b.motion_updates or 0)+1;return true end
        function motion:result()return {phase='idle',dx=0,dy=0,dz=0}end
        return motion
    end}
end
local function render_module(b)
    return {new=function(globals,callback,log,deps)
        assert(globals==_G and type(callback)=='function' and type(deps.active)=='function'
            and type(deps.foreign)=='function')
        b.render_callback,b.render_deps=callback,deps
        local renderer={}
        function renderer:start()
            b.render_starts=(b.render_starts or 0)+1
            if b.render_start_failure then return false,'fixture render unavailable'end
            b.render_active=true;return true
        end
        function renderer:stop()
            b.render_stops=(b.render_stops or 0)+1
            if b.render_stop_failure then return false,'fixture render cleanup pending'end
            b.render_active=false;return true
        end
        function renderer:is_clean()return not b.render_active end
        function renderer:result()return{active=b.render_active==true}end
        return renderer
    end}
end
local function presentation_module(b,prefix)
    return {new=function()
        local manager={}
        function manager:is_clean()return not b[prefix..'_active'] and not b[prefix..'_pending']end
        function manager:is_suppressed()
            return prefix=='dof' and b.dof_suppressed==true and b.dof_active==true
                and not b.dof_pending and not b.photo_held
        end
        function manager:stop()
            b[prefix..'_stops']=(b[prefix..'_stops'] or 0)+1
            if b[prefix..'_end_failure'] then b[prefix..'_pending']=true;return false,'fixture '..prefix..' cleanup pending'end
            b[prefix..'_active'],b[prefix..'_pending']=false,false;return true
        end
        function manager:shutdown()return self:stop()end
        function manager:preflight()return true end
        function manager:update(controller)
            b[prefix..'_updates']=(b[prefix..'_updates'] or 0)+1
            if not controller:is_enabled() or b[prefix..'_pending'] then return self:stop()end
            if prefix=='blur'and(controller:result().mode~='pose_offset'
                or controller:result().phase~='running'or not controller.lease)then return self:stop()end
            b[prefix..'_active']=true;return true
        end
        function manager:result()return {owned=b[prefix..'_active'] or false,cleanup_pending=b[prefix..'_pending'] or false}end
        function manager:status()return 'fixture '..prefix end
        return manager
    end}
end
local function compat_module(b)
    return {new=function(controller)
        local compat={}
        function compat:foreign()return b.photo_held==true,'Photo Mode'end
        function compat:prepare()
            b.compat_prepares=(b.compat_prepares or 0)+1
            if b.photo_held then return false,'Photo Mode owns render camera'end
            if b.compat_prepare_failure then return false,'fixture camera compatibility unavailable'end
            b.compat_installed=true
            return true
        end
        function compat:update()
            b.compat_updates=(b.compat_updates or 0)+1
            if not controller:is_enabled() then return self:stop()end
            return true
        end
        function compat:stop()
            b.compat_stops=(b.compat_stops or 0)+1
            if b.compat_stop_failure then return false,'fixture compatibility cleanup pending'end
            b.compat_installed=false
            return true
        end
        function compat:shutdown()b.compat_shutdowns=(b.compat_shutdowns or 0)+1;return self:stop()end
        function compat:is_clean()return not b.compat_installed end
        function compat:result()return {foreign=b.photo_held==true}end
        function compat:status()return b.photo_held and 'Photo Mode owns render camera' or 'clear'end
        return compat
    end}
end

local function mock()
    local b = { current = { identity = 'context/avatar/weapon-A', player_identity='context/avatar-generation', camera_kind = 4,
        aiming = false, controller_active = false, safe = true }, entries = 0, exits = 0,
        snapshots = 0, releases = 0, cleanup_failures = 0,
        placement_defaults = {x=.15,y=0,z=-.12},default_placement_attempts=0,live_placement_attempts=0 }
    function b:set_placement_defaults(value)
        self.default_placement_attempts=self.default_placement_attempts+1
        if self.placement_defaults_failure then return false,'fixture defaults refused' end
        self.placement_defaults={x=value.x,y=value.y,z=value.z}
        return true
    end
    function b:set_pose_placement(lease,value)
        self.live_placement_attempts=self.live_placement_attempts+1
        if self.placement_live_failure then return false,'fixture live placement refused' end
        if not lease.pose or not self.current or self.current.identity~=lease.identity
            or self.current.camera_kind~=6 or self.current.safe~=true then return false,'fixture pose owner unavailable' end
        self.last_live_lease=lease
        self.placement_defaults={x=value.x,y=value.y,z=value.z}
        return true
    end
    function b:begin_frame()
        assert(not self.frame_active);self.frame_active=true
        self.frame_begins=(self.frame_begins or 0)+1
    end
    function b:end_frame()
        assert(self.frame_active);self.frame_active=false
        self.frame_ends=(self.frame_ends or 0)+1
    end
    function b:snapshot()
        self.snapshots = self.snapshots + 1
        if self.no_firearm then return nil,'fixture firearm transition' end
        if not self.current then return nil, 'transition' end
        local value = {}
        for key, field in pairs(self.current) do value[key] = field end
        if self.foreign_camera and self.foreign_camera()==true then
            value.safe=false;value.foreign_camera=true;value.reason='Photo Mode or another camera owns the view'
        end
        return value
    end
    function b:player_snapshot()
        local source=self.player_current or self.current
        if not source then return nil,'fixture local player unavailable' end
        local value={};for key,field in pairs(source) do value[key]=field end
        return value
    end
    function b:prepare_alignment(snapshot)
        if self.alignment_preflight_failure then return false,'fixture alignment preflight failed' end
        return true,{identity=snapshot.identity}
    end
    function b:alignment_status(lease)
        if self.alignment_status_failure then return nil,'fixture alignment unavailable' end
        return {armed=self.alignment_armed,expired=self.alignment_expired,
            skipped_position=3,skipped_rotation=3}
    end
    function b:prepare_pose(snapshot)
        self.pose_preparations = (self.pose_preparations or 0) + 1
        if self.on_pose_prepare then self:on_pose_prepare() end
        if self.pose_preflight_failure then return false,'fixture pose preflight failed' end
        return true,{identity=snapshot.identity,serial=self.pose_preparations}
    end
    function b:enter_pose(snapshot,token,duration_ms,blend_entry)
        equal(token.identity,snapshot.identity)
        assert(duration_ms >= 0 and duration_ms <= 30500 and duration_ms == math.ceil(duration_ms))
        if self.camera_before_entry then
            local ready,why=self.camera_before_entry()
            if ready~=true then return false,why end
        end
        self.pose_tokens=self.pose_tokens or {};self.pose_tokens[#self.pose_tokens+1]=token
        self.pose_durations = self.pose_durations or {}
        self.pose_durations[#self.pose_durations + 1] = duration_ms
        self.pose_entry_blends = self.pose_entry_blends or {}
        self.pose_entry_blends[#self.pose_entry_blends + 1] = blend_entry==true
        self.pose_armed = true
        self.pose_weapon_updates, self.pose_zero_restores = 3, 1
        local entered,lease = self:enter(snapshot)
        if entered then
            lease.pose = true
            lease.pose_blend_entry = blend_entry==true
            if self.pose_cleanup_only then lease.cleanup_only=true; self.current.camera_kind=4 end
        end
        return entered,lease
    end
    function b:pose_status(lease)
        self.pose_status_reads=(self.pose_status_reads or 0)+1
        assert(not lease.pose_suspended,'Ended helper must not be polled')
        if self.on_pose_status then self:on_pose_status(lease) end
        if self.pose_status_failure then return nil,'fixture pose unavailable' end
        if self.pose_status_error then
            lease.pose_error=self.pose_status_error
            lease.pose_stats={armed=false,error=0,
                weapon_updates=self.pose_weapon_updates,zero_restores=self.pose_zero_restores}
            return nil,'fixture native pose error '..self.pose_status_error
        end
        local target = self.current and (self.current.aiming or self.current.controller_active) and 0 or 1
        return {armed=self.pose_armed,expired=self.pose_expired,
            weapon_updates=self.pose_weapon_updates,zero_restores=self.pose_zero_restores,
            blend=target,target_weight=target}
    end
    function b:enter(snapshot,alignment_token)
        if self.unsupported then return false, 'Unsupported executable fingerprint' end
        if alignment_token then
            equal(alignment_token.identity,snapshot.identity)
            self.alignment_armed=true
        end
        self.entries = self.entries + 1
        local lease = { identity = snapshot.identity,player_identity=snapshot.player_identity,
            request=snapshot.record,alignment=alignment_token~=nil }
        self.current.camera_kind = 6
        if self.after_enter then self:after_enter() end
        return true, lease
    end
    function b:suspend_pose(lease)
        self.suspensions=(self.suspensions or 0)+1
        if self.suspend_unproved then
            self.pose_armed=false
            return false,'fixture request retired before retained-camera proof'
        end
        lease.swap_observed=true;self.pose_armed=false
        if self.pose_finish_failure then return false,'fixture pose disarm pending' end
        lease.pose_suspended=true
        lease.pose_stats={armed=false,weapon_updates=self.pose_weapon_updates,zero_restores=self.pose_zero_restores}
        return true
    end
    function b:release(lease)
        self.releases = self.releases + 1
        if lease.pose then
            if self.pose_finish_failure and not lease.pose_suspended then return false,'fixture pose disarm pending' end
            self.pose_armed=false
            if self.pose_end_restore and not lease.pose_finished then
                self.pose_zero_restores = self.pose_zero_restores + 1
                lease.pose_finished = true
                lease[self.pose_final_stats_field or 'pose_stats'] = {
                    weapon_updates=self.pose_weapon_updates,zero_restores=self.pose_zero_restores,
                    blend=0,target_weight=0}
            end
        end
        if lease.alignment then
            if self.alignment_finish_failure then return false,'fixture alignment disarm pending' end
            self.alignment_armed=false
        end
        if self.cleanup_failures > 0 then
            self.cleanup_failures = self.cleanup_failures - 1
            return false, 'fixture exit pending'
        end
        if self.after_release then self:after_release() end
        if not self.current then return false, 'transition' end
        if lease.pose_suspended and self.current.camera_kind==6 and not self.current.safe
            and self.current.player_identity==lease.player_identity then return false,'fixture swap inhibit pending' end
        -- This fixture models the backend contract; real backend ownership is
        -- validated separately. Never issue a foreign or gameplay-owned exit.
        local retained=lease.pose_suspended and self.current.player_identity==lease.player_identity
        if (self.current.identity ~= lease.identity and not retained) or self.current.camera_kind ~= 6
            or self.current.aiming or self.current.controller_active then return true, 'retired' end
        self.exits = self.exits + 1
        self.current.camera_kind = 4
        return true
    end
    function b:prepare_body_pose(snapshot)
        self.preparations = (self.preparations or 0) + 1
        equal(self.current.camera_kind,4)
        if self.preflight_failure then return false,self.preflight_failure end
        return true,{identity=snapshot.identity}
    end
    function b:release_body_pose(lease,token)
        equal(token.identity,lease.identity)
        self.pose_attempts = (self.pose_attempts or 0) + 1
        if self.pose_failure then return false, 'fixture event unavailable' end
        self.pose_events = (self.pose_events or 0) + 1
        return true
    end
    local clock = { value = 100 }
    local c = Controller.new(b, nil, function() return clock.value end)
    return c, b, clock
end

test('idle has no native mutations', function()
    local c, b = mock()
    for _ = 1, 50 do c:update() end
    equal(b.entries, 0); equal(b.exits, 0); assert(c:is_clean())
end)

test('hammer uses head fallback without firearm entry and returns to firearm ownership',function()
    local c,b,clock=mock()
    function b:camera_only_weapon()return self.hammer==true end
    b.hammer=true
    assert(c:start(0,'pose_offset'));equal(b.entries,0);equal(c.phase,'waiting')
    for _=1,8 do clock.value=clock.value+.1;c:update()end
    equal(b.entries,0);equal(c.lease,nil);contains(c:status(),'Breaching hammer')
    b.hammer=false;clock.value=clock.value+1;assert(c:update());equal(b.entries,1)
    b.hammer=true;b.current.camera_kind=4;b.current.identity='context/avatar/hammer'
    clock.value=clock.value+.1;assert(c:update());equal(c.lease,nil)
    clock.value=clock.value+.1;assert(c:update());equal(b.entries,1)
    assert(c:stop());assert(c:is_clean())
end)
test('single native entry with aim invariant observations', function()
    local c, b = mock()
    assert(c:start(10)); equal(b.entries, 1)
    assert(not c:start(10)); c:update(); equal(b.entries, 1)
    local result = c:result()
    equal(result.before_aiming, false); equal(result.after_aiming, false)
    equal(result.aiming_unchanged, true); equal(result.observed_native_without_aim, 2)
    equal(b.pose_attempts, nil); equal(result.mode, 'native')
    assert(c:stop()); equal(b.exits, 1); assert(c:is_clean())
end)

test('alignment mode exposes skips and disarms before normal timeout cleanup', function()
    local c,b,clock=mock(); assert(c:start(10,'unlinked_sights'))
    equal(b.alignment_armed,true); equal(c:result().skipped_position,3)
    equal(c:result().skipped_rotation,3); contains(c:status(),'centering calls skipped=3/3')
    clock.value=110; assert(c:update()); equal(b.alignment_armed,false); equal(b.exits,1)
end)

test('alignment preflight failure prevents native entry', function()
    local c,b=mock(); b.alignment_preflight_failure=true
    assert(not c:start(10,'unlinked_sights')); equal(b.entries,0); assert(c:is_clean())
end)

test('alignment yields and disarms on real aim or owner change', function()
    for _,change in ipairs({function(b)b.current.aiming=true end,function(b)b.current.identity='foreign' end}) do
        local c,b=mock(); assert(c:start(10,'unlinked_sights')); change(b); c:update()
        equal(b.alignment_armed,false); equal(b.exits,0); assert(c:is_clean())
    end
end)

test('alignment expiry or lost helper stops with ordinary cleanup', function()
    for _,field in ipairs({'alignment_expired','alignment_status_failure'}) do
        local c,b=mock(); assert(c:start(10,'unlinked_sights')); b[field]=true; c:update()
        equal(b.alignment_armed,false); equal(b.exits,1); assert(c:is_clean())
    end
end)

test('alignment disarm failure keeps lease and prevents unload', function()
    local c,b=mock(); assert(c:start(10,'unlinked_sights')); b.alignment_finish_failure=true
    assert(not c:shutdown()); assert(not c:is_clean()); equal(b.exits,0)
    b.alignment_finish_failure=false; assert(c:retry_cleanup()); equal(b.alignment_armed,false)
end)

test('pose offset preserves native movement and follows gameplay ADS without stopping', function()
    local c,b=mock(); assert(c:start(10,'pose_offset'))
    equal(b.pose_preparations,1); equal(b.entries,1); equal(b.pose_durations[1],10000)
    equal(c:result().weapon_updates,3); equal(c:result().zero_restores,1)
    b.pose_weapon_updates,b.pose_zero_restores=10,2
    b.current.aiming,b.current.controller_active=true,true; assert(c:update())
    equal(c.phase,'running'); equal(b.exits,0); equal(b.releases,0)
    equal(c:result().weapon_updates,10); equal(c:result().zero_restores,2)
    equal(c:result().target_weight,0); equal(c:result().aim_transitions,1)
    b.current.aiming,b.current.controller_active=false,false; assert(c:update())
    equal(c:result().target_weight,1); equal(c:result().aim_transitions,2)
    contains(c:status(),'weapon offset updates=10'); contains(c:status(),'hip blend=1')
    assert(c:stop()); equal(b.pose_armed,false); equal(b.exits,1)
end)

test('pose preflight rejects before entry and immediate native ADS remains active', function()
    local c,b=mock(); b.pose_preflight_failure=true
    assert(not c:start(10,'pose_offset')); equal(b.entries,0); assert(c:is_clean())
    c,b=mock(); b.after_enter=function(self)self.current.aiming=true;self.current.controller_active=true end
    assert(c:start(10,'pose_offset')); equal(c.phase,'running'); equal(b.releases,0)
    equal(c:result().aim_transitions,1)
    assert(c:stop()); equal(b.exits,0); equal(b.pose_armed,false)
end)

test('pose bounded thirty second duration preserves the original deadline through reacquisition', function()
    local c,b,clock=mock(); assert(c:start(30,'pose_offset'))
    equal(c:result().duration,30); equal(b.pose_durations[1],30000)
    clock.value=120; assert(c:update()); equal(c.phase,'running')
    b.current.aiming=true; assert(c:update())
    clock.value=129.125; b.current.aiming=false; b.current.camera_kind=4; assert(c:update())
    equal(b.entries,2); equal(b.pose_durations[2],875); equal(c:result().runs,1)
    clock.value=129.999; assert(c:update()); equal(c.phase,'running')
    clock.value=130; assert(c:update()); assert(c:is_clean()); equal(b.entries,2)
    contains(c:status(),'test timeout')
    c,b=mock(); assert(not c:start(31,'pose_offset')); equal(b.entries,0); equal(b.pose_preparations,nil)
end)

test('manual pose defaults to no timeout while native baseline retains its bounded default', function()
    for _,explicit in ipairs({false,true}) do
        local c,b,clock=mock(); assert(c:start(explicit and 0 or nil,'pose_offset'))
        equal(b.pose_durations[1],0); equal(c:result().duration,0); equal(c:result().manual,true)
        clock.value=7600; assert(c:update()); equal(c.phase,'running'); assert(c:is_enabled())
        assert(not c:is_clean()); assert(not c:start(0,'pose_offset'))
        assert(c:stop()); assert(not c:is_enabled()); assert(c:is_clean())
    end
    local c,b,clock=mock(); assert(c:start()); equal(c:result().duration,30)
    clock.value=130; c:update(); assert(c:is_clean()); assert(not c:is_enabled())
end)

test('manual ADS returns blend placement without changing their persistent lifetime',function()
    local c,b,clock=mock();b.current.record=11;assert(c:start(0,'pose_offset'))
    equal(b.pose_entry_blends[1],false)
    b.current.aiming=true;b.current.controller_active=true;assert(c:update())
    b.current.record=12;assert(c:update());equal(c.phase,'waiting');equal(b.entries,1)
    b.current.camera_kind=4;b.current.aiming=false;b.current.controller_active=false;clock.value=101
    assert(c:update());equal(b.entries,2);equal(b.pose_durations[2],0);equal(b.pose_entry_blends[2],true)
    clock.value=10000;assert(c:update());assert(c:is_enabled());equal(b.entries,2)
    assert(c:stop())
end)

test('manual ADS entry intent survives cleanup retries and a missing full firearm snapshot',function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'))
    b.current.controller_active=true;assert(c:update())
    b.current.camera_kind=4;b.current.controller_active=false;b.no_firearm=true;b.cleanup_failures=2;clock.value=101
    assert(not c:update());equal(c.phase,'cleanup_pending')
    assert(not c:update());equal(b.entries,1)
    assert(c:update());equal(c.phase,'waiting')
    assert(c:update());equal(b.entries,1)
    b.no_firearm=false;assert(c:update());equal(b.entries,2);equal(b.pose_entry_blends[2],true)
    assert(c:stop())
end)

test('manual ADS return never transfers its blend to a different body or firearm',function()
    for _,change in ipairs({'weapon','body','weapon-away-and-back'})do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'))
        b.current.controller_active=true;assert(c:update())
        b.current.camera_kind=4;b.current.controller_active=false;clock.value=101
        b.current.identity='other-owner/weapon'
        if change=='body'then b.current.player_identity='other-body-generation'end
        assert(c:update());equal(c.phase,'waiting')
        if change=='weapon-away-and-back'then b.current.identity='context/avatar/weapon-A'end
        assert(c:update());equal(b.entries,2);equal(b.pose_entry_blends[2],false)
        assert(c:stop())
    end
end)

test('ordinary manual reacquisition and a fresh session still use steady placement',function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'))
    b.current.controller_active=true;assert(c:update())
    b.current.controller_active=false;assert(c:update())
    b.current.camera_kind=4;clock.value=101;assert(c:update());assert(c:update())
    equal(b.pose_entry_blends[2],false)
    b.current.controller_active=true;assert(c:update());assert(c:stop())
    b.current.controller_active=false;b.current.camera_kind=4;assert(c:start(0,'pose_offset'))
    equal(b.pose_entry_blends[3],false);assert(c:stop())
    c,b,clock=mock();b.current.camera_kind=6;b.current.controller_active=true
    assert(c:start(0,'pose_offset'));equal(b.entries,0)
    assert(c:update());b.current.camera_kind=4;b.current.controller_active=false;clock.value=101
    assert(c:update());equal(b.pose_entry_blends[1],false);assert(c:stop())
end)

test('initial manual enable accepts held balls missing firearms actions and seated cameras as waiting intent', function()
    for _,state in ipairs({'held-ball','missing-firearm','action-camera','seated','real-ADS'})do
        for _,resume in ipairs({false,true})do
            local c,b,clock=mock()
            if state=='missing-firearm'then b.no_firearm=true
            elseif state=='real-ADS'then b.current.camera_kind=6;b.current.aiming=true;b.current.controller_active=true
            else
                b.current.safe=false;b.current.reason='fixture '..state
                if state=='held-ball'then b.current.weapon_ready=false
                elseif state=='action-camera'then b.current.camera_kind=7
                else b.current.seated=true end
            end
            assert(c:start(0,'pose_offset'));equal(c.phase,'waiting');assert(c:is_enabled())
            equal(c:result().manual,true);equal(c:result().runs,1);equal(b.entries,0);equal(b.releases,0)
            equal(b.pose_preparations or 0,0);equal(c.lease,nil)
            clock.value=200;assert(c:update());equal(b.entries,0)
            if not resume then assert(c:stop());assert(not c:is_enabled());assert(c:is_clean())end
            b.no_firearm=false;b.current.safe=true;b.current.camera_kind=4;b.current.seated=false
            b.current.aiming=false;b.current.controller_active=false;b.current.weapon_ready=true
            clock.value=201;assert(c:update())
            equal(b.entries,resume and 1 or 0)
            if resume then equal(c.phase,'running');assert(c:is_enabled());assert(c:stop())end
        end
    end
end)

test('initial manual enable still requires a stable local player and bounded starts remain strict',function()
    for _,missing in ipairs({'player','identity'})do
        local c,b=mock()
        if missing=='player'then b.current=nil else b.current.player_identity=nil end
        assert(not c:start(0,'pose_offset'));assert(not c:is_enabled());equal(b.entries,0);assert(c:is_clean())
    end
    for _,state in ipairs({'held-ball','missing-firearm','action-camera','seated','real-ADS'})do
        local c,b=mock()
        if state=='missing-firearm'then b.no_firearm=true
        elseif state=='real-ADS'then b.current.camera_kind=6;b.current.aiming=true
        else b.current.safe=false;if state=='action-camera'then b.current.camera_kind=7 end end
        assert(not c:start(10,'pose_offset'));assert(not c:is_enabled());equal(b.entries,0);assert(c:is_clean())
    end
end)

test('manual weapon swaps retire exact leases and require fresh preparation without a lifetime cap', function()
    local c,b,clock=mock(); assert(c:start(0,'pose_offset'))
    for index=1,10 do
        local previous=c.lease;local token=b.pose_tokens[#b.pose_tokens]
        b.current.identity='context/avatar/weapon-'..index;b.current.camera_kind=4;clock.value=100+index
        assert(c:update()); equal(c.phase,'waiting'); equal(c.lease,nil); assert(c:is_enabled())
        equal(b.entries,index); assert(not c:is_clean())
        assert(c:update()); equal(c.phase,'running'); assert(c.lease~=previous)
        assert(b.pose_tokens[#b.pose_tokens]~=token);equal(b.pose_durations[index+1],0)
        equal(b.entries,index+1);equal(c:result().runs,1)
    end
    equal(c:result().reacquisitions,10);assert(c:stop())
end)

test('manual mode waits through missing firearms and native aiming without forcing aim or entry', function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'));clock.value=101
    b.current.identity='context/avatar/weapon-B';b.current.camera_kind=6;b.current.aiming=true
    assert(c:update());equal(c.phase,'waiting');equal(b.exits,0);equal(b.entries,1)
    assert(c:update());equal(b.entries,1);equal(b.current.aiming,true)
    b.no_firearm=true;b.current.camera_kind=4;b.current.controller_active=true
    clock.value=200;assert(c:update());equal(b.entries,1);assert(c:is_enabled())
    b.no_firearm=false;b.current.aiming=false;b.current.controller_active=false;b.current.weapon_ready=false
    assert(c:update());equal(b.entries,1)
    b.current.weapon_ready=true;assert(c:update());equal(b.entries,2);equal(c.phase,'running')
    b.no_firearm=true;b.current.camera_kind=4;assert(c:update());equal(c.phase,'waiting')
    assert(c:update());equal(b.entries,2);assert(c:is_enabled());assert(c:stop())
end)

test('manual cleanup failure keeps desire and old lease but never permits a new entry', function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'));local lease=c.lease
    b.current.identity='context/avatar/weapon-B';b.current.camera_kind=4;b.cleanup_failures=2;clock.value=101
    assert(not c:update());equal(c.phase,'cleanup_pending');equal(c.lease,lease);assert(c:is_enabled())
    assert(not c:update());equal(c.lease,lease);equal(b.entries,1)
    assert(c:update());equal(c.phase,'waiting');equal(b.entries,1);assert(c:is_enabled())
    assert(c:update());equal(b.entries,2)
    b.current.camera_kind=4;b.cleanup_failures=2;assert(not c:update())
    assert(not c:stop());assert(not c:is_enabled());equal(c.phase,'cleanup_pending')
    assert(c:update());assert(c:is_clean());c:update();equal(b.entries,2)
end)

test('manual intent survives unsupported or missing players while explicit stop cancels waiting', function()
    for _,change in ipairs({
        function(c,b)b.current.player_identity='different-player-generation';assert(c:update()) end,
        function(c,b)b.current.safe=false;assert(c:update()) end,
        function(c,b)b.current=nil;assert(c:update()) end,
    }) do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'))
        b.current.camera_kind=4;assert(c:update());equal(c.phase,'waiting');assert(c:is_enabled())
        change(c,b);assert(c:is_enabled());assert(not c:is_clean());equal(c.phase,'waiting')
        assert(c:stop());assert(not c:is_enabled());assert(c:is_clean())
        clock.value=1000;c:update();equal(b.entries,1)
    end
end)

test('manual unsupported actions retire their exact lease and never enter an unsupported camera', function()
    for _,kind in ipairs({4,5,7,9}) do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'));local old=c.lease
        b.current.camera_kind=kind;b.current.safe=false;b.current.reason='fixture unsupported action'
        assert(c:update());equal(c.phase,'waiting');equal(c.lease,nil);assert(c:is_enabled())
        equal(b.releases,1);equal(b.pose_armed,false);equal(b.entries,1)
        clock.value=200;assert(c:update());equal(b.entries,1)
        b.current.safe=true
        if kind~=4 then assert(c:update());equal(b.entries,1) end
        b.current.camera_kind=4;assert(c:update());equal(b.entries,2);assert(c.lease~=old)
        assert(c:stop())
    end
end)

test('manual player loss retains cleanup and rebases only after an acknowledged old lease', function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'));local old=c.lease
    local former=b.current;b.current=nil;clock.value=101
    assert(not c:update());equal(c.phase,'cleanup_pending');equal(c.lease,old);assert(c:is_enabled())
    assert(not c:update());equal(c.lease,old);equal(b.entries,1);assert(c:is_enabled())
    b.current={identity='new-context/body/weapon',player_identity='new-context/body-generation',
        camera_kind=4,safe=true,aiming=false,controller_active=false}
    assert(c:update());equal(c.phase,'waiting');equal(c.lease,nil);equal(b.entries,1)
    assert(c:update());equal(c.phase,'running');equal(b.entries,2);assert(c.lease~=old)
    equal(c.lease.player_identity,'new-context/body-generation');assert(c:is_enabled())
    assert(c:update());equal(c.phase,'running');equal(b.entries,2)
    assert(c:stop());b.current=former;clock.value=200;c:update();equal(b.entries,2)
end)

test('manual new body cannot bypass old cleanup or adopt a foreign native request', function()
    local c,b,clock=mock();b.current.record=11;assert(c:start(0,'pose_offset'));local old=c.lease
    b.current.identity='new-avatar/weapon';b.current.player_identity='new-avatar-generation'
    b.current.camera_kind=6;b.current.record=12;b.cleanup_failures=2;clock.value=101
    assert(not c:update());equal(c.lease,old);assert(c:is_enabled())
    assert(not c:update());equal(c.lease,old);assert(c:is_enabled())
    assert(c:update());equal(c.phase,'waiting');equal(c.lease,nil);equal(b.entries,1);equal(b.exits,0)
    assert(c:update());equal(b.entries,1)
    b.current.camera_kind=4;b.current.player_identity=nil
    assert(c:update());equal(b.entries,1)
    b.current.player_identity='new-avatar-generation';assert(c:update());equal(b.entries,2)
    equal(c.lease.player_identity,'new-avatar-generation');assert(c:stop())
end)

test('manual pose poll ownership races yield instead of clearing persistent intent', function()
    for _,change in ipairs({
        function(b)b.current=nil end,
        function(b)b.current.safe=false;b.current.camera_kind=7 end,
        function(b)b.current.identity='new-context';b.current.player_identity='new-player';b.current.camera_kind=4 end,
    }) do
        local c,b=mock();assert(c:start(0,'pose_offset'));local old=c.lease
        b.pose_status_failure=true;b.on_pose_status=function(self)change(self) end
        c:update();assert(c:is_enabled());equal(b.entries,1);equal(b.pose_armed,false)
        assert(c.phase=='waiting' or c.phase=='cleanup_pending')
        if c.phase=='cleanup_pending' then equal(c.lease,old) end
        b.on_pose_status=nil;b.pose_status_failure=false
        b.current={identity='restored-player/weapon',player_identity='restored-player',
            camera_kind=4,safe=true,aiming=false,controller_active=false}
        assert(c:stop());assert(not c:is_enabled());c:update();equal(b.entries,1)
    end
end)

test('manual stop or shutdown clears intent in every yielded or pending state', function()
    for _,shutdown in ipairs({false,true}) do
        for _,state in ipairs({'unsupported','missing','new-player','cleanup'}) do
            local c,b,clock=mock();assert(c:start(0,'pose_offset'))
            local original=b.current
            if state=='unsupported' then b.current.safe=false;b.current.camera_kind=7
            elseif state=='missing' then b.current=nil
            elseif state=='new-player' then b.current.identity='other';b.current.player_identity='other-player';b.current.camera_kind=4
            else b.current.camera_kind=4;b.cleanup_failures=2 end
            c:update();assert(c:is_enabled())
            if shutdown then c:shutdown() else c:stop() end
            assert(not c:is_enabled());equal(b.entries,1)
            b.current=original;b.current.safe=true;b.current.camera_kind=4;b.cleanup_failures=0
            clock.value=1000;assert(c:update());assert(c:is_clean());equal(b.entries,1)
            equal(c.phase,shutdown and 'disabled' or 'idle')
        end
    end
end)

test('manual owner retirement errors and new ADS requests wait while genuine guard failures stop', function()
    for _,code in ipairs({7,8,6,14,15,16}) do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'));b.pose_status_error=code
        assert(c:update());equal(b.entries,1)
        if code==7 or code==8 then
            assert(c:is_enabled());equal(c.phase,'waiting');b.pose_status_error=nil;clock.value=101
            assert(c:update());equal(b.entries,2)
        else assert(not c:is_enabled());assert(c:is_clean()) end
        assert(c:stop())
    end
    local c,b,clock=mock();b.current.record=11;assert(c:start(0,'pose_offset'))
    b.current.record=12;b.current.aiming=true;assert(c:update())
    equal(c.phase,'waiting');equal(b.exits,0);assert(c:is_enabled())
    b.current.camera_kind=4;b.current.aiming=false;clock.value=101;assert(c:update());equal(b.entries,2)
    assert(c:stop())
end)

test('a recovered snapshot cannot turn an explicitly retired pose owner into a manual stop',function()
    for _,failures in ipairs({0,2})do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'));local old=c.lease
        b.cleanup_failures=failures
        b.on_pose_status=function(self,lease)
            lease.pose_owner_retired=true;lease.pose_retire_reason='fixture prior inhibit recovered'
            self.pose_status_failure=true;self.on_pose_status=nil
        end
        c:update();equal(b.entries,1);assert(c:is_enabled())
        if failures>0 then
            equal(c.phase,'cleanup_pending');equal(c.lease,old)
            assert(not c:update());equal(c.lease,old);assert(c:is_enabled())
            assert(c:update())
        end
        equal(c.phase,'waiting');equal(c.lease,nil);equal(b.entries,1)
        b.pose_status_failure=false;clock.value=101
        assert(c:update());equal(c.phase,'running');equal(b.entries,2);assert(c.lease~=old)
        assert(c:is_enabled());assert(c:stop())
    end
end)

test('manual entry churn is rate limited without disabling persistent intent', function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'))
    for index=1,100 do
        clock.value=100+index/100
        if c.lease then b.current.camera_kind=4 end
        assert(c:update());assert(c:is_enabled())
    end
    assert(b.entries<=5,'Unexpected rapid entry count '..b.entries);assert(c:stop())
end)

test('observed swap inhibit retires the original weapon before accepting a new one', function()
    for _,failures in ipairs({0,2}) do
        local c,b,clock=mock();assert(c:start(0,'pose_offset'));local old=c.lease
        b.current.safe=false;b.current.weapon_transition=true;b.cleanup_failures=failures
        c:update();assert(c:is_enabled());equal(b.entries,1)
        if failures>0 then equal(c.lease,old);c:update();assert(c:is_enabled());c:update() end
        equal(c.phase,'waiting');equal(b.current.camera_kind,4);equal(b.exits,1)
        b.current.identity='context/avatar/weapon-B';clock.value=101
        assert(c:update());equal(b.entries,1)
        b.current.safe=true;b.current.weapon_transition=false;assert(c:update())
        equal(b.entries,2);equal(c.phase,'running');equal(b.pose_durations[2],0);assert(c:stop())
    end
end)

test('manual stop during swap inhibit never resumes and bounded diagnostics still stop', function()
    local c,b=mock();assert(c:start(0,'pose_offset'))
    b.current.safe=false;b.current.weapon_transition=true;c:update()
    equal(c.phase,'waiting');assert(c:stop());assert(not c:is_enabled());equal(b.releases,1)
    b.current.safe=true;b.current.weapon_transition=false;assert(c:update());equal(b.entries,1)
    assert(c:is_clean());equal(b.exits,1)
    c,b=mock();assert(c:start(30,'pose_offset'))
    b.current.safe=false;b.current.weapon_transition=true;c:update()
    assert(not c:is_enabled());assert(c:is_clean());contains(c:status(),'unsafe')
    for _,field in ipairs({'blocked_mask_1','guard_byte_5','seated','foreign_owner'}) do
        c,b=mock();assert(c:start(0,'pose_offset'))
        b.current.safe=false;b.current.weapon_transition=false
        if field=='foreign_owner' then b.current.player_identity='foreign' end
        c:update();assert(c:is_enabled());equal(c.phase,'waiting');equal(b.entries,1)
        assert(c:stop());assert(not c:is_enabled())
    end
end)

test('placement XYZ copies stay independent of caller tables and accept inclusive bounds', function()
    local c,b=mock(); local original=c:get_placement()
    equal(original.x,.15); equal(original.y,0); equal(original.z,-.12)
    original.x=.4; equal(c:get_placement().x,.15)
    local value={x=.2,y=-.25,z=.3}; assert(c:set_placement(value))
    equal(b.default_placement_attempts,1); equal(b.live_placement_attempts,0)
    value.x=-.3; equal(c:get_placement().x,.2); equal(b.placement_defaults.x,.2)
    local returned=c:get_placement(); returned.y=.4; equal(c:get_placement().y,-.25)
    assert(c:set_placement({x=-.5,y=.5,z=-.5}))
    equal(c:get_placement().x,-.5); equal(c:get_placement().y,.5); equal(c:get_placement().z,-.5)
    assert(c:set_placement({x=.5,y=-.5,z=.5}))
    equal(c:get_placement().x,.5); equal(c:get_placement().y,-.5); equal(c:get_placement().z,.5)
end)

test('placement rejects missing nonfinite and out-of-bounds axes without backend calls', function()
    local c,b=mock()
    assert(not c:set_placement(nil)); assert(not c:set_placement('XYZ'))
    for _,axis in ipairs({'x','y','z'}) do
        for _,bad in ipairs({math.huge,-math.huge,0/0,.500001,-.500001,'0',false}) do
            local value={x=.15,y=0,z=-.12}; value[axis]=bad
            assert(not c:set_placement(value))
        end
        local value={x=.15,y=0,z=-.12}; value[axis]=nil; assert(not c:set_placement(value))
    end
    equal(b.default_placement_attempts,0); equal(b.live_placement_attempts,0)
    equal(c:get_placement().x,.15); equal(c:get_placement().y,0); equal(c:get_placement().z,-.12)
end)

test('live placement refusal preserves the accepted copy and cleanup pending changes defaults only', function()
    local c,b=mock(); local first={x=.2,y=.1,z=-.3}; assert(c:set_placement(first))
    assert(c:start(30,'pose_offset')); local lease=c.lease
    b.placement_live_failure=true
    assert(not c:set_placement({x=.3,y=.2,z=-.4})); equal(b.live_placement_attempts,1)
    equal(b.default_placement_attempts,1); equal(c:get_placement().x,.2); equal(b.placement_defaults.x,.2)
    b.placement_live_failure=false; assert(c:set_placement({x=.3,y=.2,z=-.4}))
    equal(b.last_live_lease,lease); equal(c:get_placement().y,.2); equal(b.default_placement_attempts,1)
    b.pose_finish_failure=true; assert(not c:stop()); equal(c.phase,'cleanup_pending')
    assert(c:set_placement({x=-.1,y=.05,z=.25})); equal(b.default_placement_attempts,2)
    equal(b.live_placement_attempts,2); equal(c:get_placement().x,-.1); equal(b.placement_defaults.z,.25)
    b.placement_defaults_failure=true
    assert(not c:set_placement({x=.4,y=.3,z=.2})); equal(c:get_placement().x,-.1)
    equal(b.live_placement_attempts,2); equal(c.lease,lease)
    b.pose_finish_failure=false; assert(c:retry_cleanup())
    local other,other_backend=mock(); assert(other:start(30,'native'))
    assert(not other:set_placement({x=.2,y=.1,z=.3}))
    equal(other_backend.default_placement_attempts,0); equal(other_backend.live_placement_attempts,0)
end)

test('pose camera reacquires after ADS release and aggregates per-lease counters', function()
    local c,b,clock=mock(); assert(c:start(10,'pose_offset'))
    b.current.aiming=true; b.current.controller_active=true; c:update()
    b.pose_weapon_updates,b.pose_zero_restores=5,2
    b.current.camera_kind=4; b.current.aiming=false; b.current.controller_active=false
    clock.value=108.125; assert(c:update())
    equal(b.entries,2); equal(b.releases,1); equal(b.exits,0)
    equal(b.pose_durations[2],1875); equal(c:result().runs,1); equal(c:result().reacquisitions,1)
    equal(c:result().weapon_updates,5); equal(c:result().zero_restores,2)
    c:update(); equal(c:result().weapon_updates,8); equal(c:result().zero_restores,3)
    equal(c:result().aim_transitions,2)
    clock.value=110; assert(c:update()); equal(b.entries,2); equal(b.exits,1)
    equal(c:result().weapon_updates,8); assert(c:is_clean()); contains(c:status(),'test timeout')
end)

test('pose reacquisition waits briefly for released native controller without forcing it', function()
    for _,field in ipairs({'aiming','controller_active'}) do
        local c,b,clock=mock(); assert(c:start(10,'pose_offset'))
        b.current[field]=true; assert(c:update())
        b.current.camera_kind=4; b.current[field]=true; clock.value=101
        assert(c:update()); equal(c.phase,'reacquiring'); equal(b.entries,1)
        equal(b.exits,0); equal(b.releases,1); assert(not c:is_clean()); assert(not c:start())
        clock.value=101.125; b.current[field]=false; assert(c:update())
        equal(c.phase,'running'); equal(b.entries,2); equal(b.pose_durations[2],8875)
        assert(c:stop())
    end
end)

test('pose reacquisition settling is bounded by elapsed time and update count', function()
    for _,advance in ipairs({true,false}) do
        local c,b,clock=mock(); assert(c:start(10,'pose_offset'))
        b.current.controller_active=true; assert(c:update())
        b.current.camera_kind=4; b.current.controller_active=true; clock.value=101
        assert(c:update())
        if advance then clock.value=101.25; assert(c:update())
        else for _=1,11 do assert(c:update()) end end
        equal(c.phase,'idle'); equal(b.entries,1); equal(b.exits,0); assert(c:is_clean())
        contains(c:status(),'did not release')
    end
end)

test('pose reacquisition honors session deadline during settling and preflight', function()
    local c,b,clock=mock(); assert(c:start(10,'pose_offset'))
    b.current.controller_active=true; assert(c:update())
    b.current.camera_kind=4; b.current.controller_active=true; clock.value=109.99
    assert(c:update()); clock.value=110; assert(c:update()); equal(b.entries,1)
    assert(c:is_clean()); contains(c:status(),'test timeout')
    c,b,clock=mock(); assert(c:start(10,'pose_offset'))
    b.current.aiming=true; assert(c:update()); b.current.aiming=false
    b.on_pose_prepare=function(self)if self.pose_preparations==2 then clock.value=110 end end
    clock.value=109; b.current.camera_kind=4; assert(c:update())
    equal(b.entries,1); assert(c:is_clean()); contains(c:status(),'test timeout')
end)

test('pose owner loss unsafe state and foreign camera stop without reacquiring', function()
    for _,change in ipairs({
        function(b)b.current.identity='foreign' end,
        function(b)b.current.safe=false end,
        function(b)b.current.camera_kind=5 end,
    }) do
        local c,b=mock(); assert(c:start(10,'pose_offset')); change(b); c:update()
        equal(b.entries,1); equal(b.pose_armed,false); assert(c:is_clean())
    end
    local c,b=mock(); assert(c:start(10,'pose_offset'))
    b.current.aiming=true; c:update(); b.current.aiming=false
    b.current.camera_kind=4; b.after_release=function(self)self.current.identity='foreign-after-release' end
    c:update(); equal(b.entries,1); assert(c:is_clean()); contains(c:status(),'weapon changed')
end)

test('pose reacquisition cannot adopt another native request while waiting', function()
    local c,b=mock(); assert(c:start(10,'pose_offset'))
    b.current.controller_active=true; assert(c:update())
    b.current.camera_kind=4; b.current.controller_active=true; assert(c:update())
    b.current.camera_kind=6; assert(c:update())
    equal(b.entries,1); equal(b.exits,0); equal(c.phase,'idle'); assert(c:is_clean())
end)

test('pose helper loss or expiry restores and cleanup failures retain the exact lease', function()
    for _,field in ipairs({'pose_expired','pose_status_failure'}) do
        local c,b=mock(); assert(c:start(10,'pose_offset')); b[field]=true; c:update()
        equal(b.pose_armed,false); equal(b.exits,1); assert(c:is_clean())
    end
    local c,b=mock(); assert(c:start(10,'pose_offset')); local lease=c.lease
    b.current.aiming=true; c:update(); b.current.aiming=false
    b.pose_finish_failure=true; b.current.camera_kind=4
    assert(not c:update()); equal(c.lease,lease); equal(c.phase,'cleanup_pending'); equal(b.entries,1)
    assert(not c:retry_cleanup()); equal(c.lease,lease); assert(not c:start())
    b.pose_finish_failure=false; assert(c:update()); equal(c.phase,'idle'); assert(c:is_clean())
    c:update(); equal(b.entries,1)
end)

test('unexpected camera retirement and cleanup-only entry cannot reacquire', function()
    local c,b=mock(); b.after_enter=function(self)self.current.camera_kind=4 end
    assert(not c:start(10,'pose_offset')); equal(b.entries,1); assert(c:is_clean())
    contains(c:status(),'without an observed ADS handoff')
    c:update(); equal(b.entries,1)
    assert(c:shutdown()); assert(c:is_clean()); equal(b.exits,0)
    c,b=mock(); b.pose_cleanup_only=true
    assert(not c:start(10,'pose_offset')); equal(b.entries,1); assert(c:is_clean())
    contains(c:status(),'requires cleanup'); equal(c:result().reacquisitions,0)
end)

test('pose reacquisition requires each lease to observe native ADS and caps repeated handoffs', function()
    local c,b=mock(); assert(c:start(10,'pose_offset'))
    for index=1,6 do
        b.current.aiming=true; assert(c:update())
        b.current.aiming=false; b.current.camera_kind=4; assert(c:update())
        equal(b.entries,index+1); equal(c:result().reacquisitions,index)
    end
    b.current.aiming=true; assert(c:update()); b.current.aiming=false; b.current.camera_kind=4
    assert(c:update()); equal(b.entries,7); assert(c:is_clean()); contains(c:status(),'limit reached')
    c,b=mock(); assert(c:start(10,'pose_offset'))
    b.current.aiming=true; c:update(); b.current.aiming=false; b.current.camera_kind=4; c:update()
    equal(b.entries,2); b.current.camera_kind=4; c:update()
    equal(b.entries,2); assert(c:is_clean()); contains(c:status(),'without an observed ADS handoff')
end)

test('pose final End restore is counted once after cleanup retries for either backend cache', function()
    for _,field in ipairs({'pose_stats','alignment_stats'}) do
        local c,b=mock(); b.pose_end_restore=true; b.pose_final_stats_field=field
        assert(c:start(10,'pose_offset')); equal(c:result().zero_restores,1)
        b.cleanup_failures=2; assert(not c:stop()); equal(c:result().zero_restores,1)
        assert(not c:retry_cleanup()); equal(c:result().zero_restores,1)
        assert(c:retry_cleanup()); equal(c:result().zero_restores,2)
        assert(c:stop()); c:update(); equal(c:result().zero_restores,2)
        equal(b.releases,3); assert(c:is_clean())
    end
end)

test('pose End deltas survive reacquisition and stale samples cannot duplicate counters', function()
    local c,b=mock(); b.pose_end_restore=true; assert(c:start(10,'pose_offset'))
    b.pose_weapon_updates,b.pose_zero_restores=7,4; c:update()
    b.pose_weapon_updates,b.pose_zero_restores=3,1; c:update()
    equal(c:result().weapon_updates,7); equal(c:result().zero_restores,4)
    b.pose_weapon_updates,b.pose_zero_restores=7,4; c:update()
    equal(c:result().weapon_updates,7); equal(c:result().zero_restores,4)
    b.current.aiming=true; c:update(); b.current.aiming=false; b.current.camera_kind=4
    assert(c:update()); equal(c:result().reacquisitions,1)
    equal(c:result().weapon_updates,7); equal(c:result().zero_restores,5)
    c:update(); equal(c:result().weapon_updates,10); equal(c:result().zero_restores,6)
    assert(c:stop()); equal(c:result().zero_restores,7); equal(c:result().weapon_updates,10)
    assert(c:retry_cleanup()); equal(c:result().zero_restores,7)
end)

test('body event mode is single dispatch with normal bounded cleanup', function()
    local c,b,clock=mock()
    assert(c:start(10,'release_body_event'))
    equal(b.entries,1); equal(b.pose_events,nil)
    equal(b.preparations,1)
    equal(c:result().body_event_pending,true)
    clock.value=100.2; c:update(); equal(b.pose_events,1)
    equal(c:result().body_exit_event_sent,true)
    equal(c:result().mode,'release_body_event')
    c:update(); equal(b.pose_events,1)
    clock.value=110; c:update(); equal(b.exits,1); assert(c:is_clean())
end)

test('body fingerprint or API mismatch refuses before any camera mutation', function()
    for _,reason in ipairs({'fingerprint mismatch','API pointer changed'}) do
        local c,b=mock(); b.preflight_failure=reason
        assert(not c:start(10,'release_body_event'))
        equal(b.entries,0); equal(b.exits,0); equal(b.pose_attempts,nil)
        equal(c:result().runs,0); assert(c:is_clean())
        contains(c:status(),'before camera entry'); contains(c:status(),reason)
    end
end)

test('body event failure retains ordinary cleanup retry', function()
    local c,b,clock=mock(); b.pose_failure=true; b.cleanup_failures=1
    assert(c:start(10,'release_body_event'))
    equal(b.pose_attempts,nil); clock.value=100.2; c:update()
    equal(b.pose_attempts,1); equal(b.pose_events,nil)
    equal(c:result().body_exit_event_sent,false); equal(c.phase,'cleanup_pending')
    assert(c:retry_cleanup()); equal(b.exits,1); assert(c:is_clean())
end)

test('body event never dispatches after immediate takeover or owner loss', function()
    for _,change in ipairs({
        function(b) b.current.aiming=true end,
        function(b) b.current.identity='other-owner' end,
    }) do
        local c,b=mock(); b.after_enter=change
        assert(not c:start(10,'release_body_event')); equal(b.pose_attempts,nil)
    end
    local c,b=mock(); assert(not c:start(10,'unknown')); equal(b.entries,0)
end)

test('body event waits for entry and cancels on player aim during delay', function()
    local c,b,clock=mock(); assert(c:start(10,'release_body_event'))
    clock.value=100.05; c:update(); equal(b.pose_attempts,nil)
    b.current.aiming=true; clock.value=100.2; c:update()
    equal(b.pose_attempts,nil); equal(b.exits,0); assert(c:is_clean())
end)
test('duration and unsafe starts refuse before entry', function()
    local c, b = mock()
    for _, duration in ipairs({0, -1, 31, math.huge, '10'}) do assert(not c:start(duration)) end
    assert(not c:start(0 / 0))
    b.current.safe = false; assert(not c:start())
    b.current.safe = true; b.current.camera_kind = 6; assert(not c:start())
    b.current.camera_kind = 4; b.current.aiming = true; assert(not c:start())
    b.current.aiming = false; b.current.controller_active = true; assert(not c:start())
    equal(b.entries, 0)
end)
test('unknown executable backend refuses entry', function()
    local c, b = mock(); b.unsupported = true
    assert(not c:start()); equal(b.entries, 0); assert(c:is_clean())
    contains(c:status(), 'Unsupported executable')
end)
test('monotonic timeout restores exactly once', function()
    local c, b, clock = mock(); assert(c:start(10))
    clock.value = 109.99; c:update(); equal(b.exits, 0)
    clock.value = 110; c:update(); equal(b.exits, 1); assert(c:is_clean())
    c:update(); equal(b.exits, 1); contains(c:status(), 'timeout')
end)
test('clock failure and backwards time stop', function()
    local c, b, clock = mock(); assert(c:start())
    clock.value = 99; c:update(); equal(b.exits, 1)
    clock.value = 100; assert(c:start())
    clock.value = 0 / 0; c:update(); equal(b.exits, 2)
end)
test('stale weapon identity retires without foreign exit', function()
    local c, b = mock(); assert(c:start())
    b.current.identity = 'context/avatar/weapon-B'; c:update()
    equal(b.entries, 1); equal(b.exits, 0); equal(b.releases, 1); assert(c:is_clean())
    equal(b.current.camera_kind, 6)
end)
test('native aim takeover receives no native exit', function()
    for _, field in ipairs({'aiming', 'controller_active'}) do
        local c, b = mock(); assert(c:start()); b.current[field] = true; c:update()
        equal(b.exits, 0); assert(c:is_clean()); contains(c:status(), 'Native aiming took control')
    end
end)
test('lost native camera receives no foreign exit', function()
    local c, b = mock(); assert(c:start()); b.current.camera_kind = 4; c:update()
    equal(b.exits, 0); assert(c:is_clean()); contains(c:status(), 'Native camera exited')
end)
test('manual stop retains failed cleanup lease', function()
    local c, b = mock(); assert(c:start()); b.cleanup_failures = 2
    local lease = c.lease
    assert(not c:stop()); equal(c.lease, lease); equal(c.phase, 'cleanup_pending')
    assert(not c:start()); assert(not c:retry_cleanup()); equal(c.lease, lease)
    assert(c:retry_cleanup()); equal(b.exits, 1); assert(c:is_clean())
end)
test('disable retries without accepting a new run', function()
    local c, b = mock(); assert(c:start()); b.cleanup_failures = 1
    assert(not c:shutdown()); assert(not c:is_clean()); assert(not c:start())
    assert(c:shutdown()); equal(b.exits, 1); equal(c.phase, 'disabled'); assert(not c:start())
end)
test('transition after entry retains cleanup handle', function()
    local c, b = mock()
    b.after_enter = function(self) self.current = nil end
    assert(not c:start()); assert(not c:is_clean()); equal(c.phase, 'cleanup_pending')
    assert(not c:retry_cleanup()); equal(b.exits, 0)
    b.current = { identity = 'new-context/avatar/weapon', camera_kind = 4,
        aiming = false, controller_active = false, safe = true }
    assert(c:retry_cleanup()); assert(c:is_clean()); equal(b.exits, 0)
end)
test('unsafe state after entry immediately restores', function()
    local c, b = mock()
    b.after_enter = function(self) self.current.safe = false end
    assert(not c:start()); equal(b.exits, 1); assert(c:is_clean())
end)
test('entry aim readback change cannot report invariance', function()
    local c, b = mock()
    b.after_enter = function(self) self.current.aiming = true end
    assert(not c:start()); assert(c:is_clean()); equal(b.exits, 0)
    local result = c:result()
    equal(result.before_aiming, false); equal(result.after_aiming, true)
    equal(result.aiming_unchanged, false); equal(result.observed_native_without_aim, 0)
end)
test('menu is optional and manual buttons only', function()
    local c, b = mock(); _G.DBFMCM = nil
    local menu = Menu.new(c); assert(menu:update()); equal(b.entries, 0)
    local registered, unregistered = 0, 0
    local api = { mods = {} }
    api.register = function(spec)
        registered = registered + 1
        local handle = { unregister = function() unregistered = unregistered + 1; api.mods[spec.id] = nil; return true end }
        local record = { handle = handle, pages = spec.pages, controls = {} }
        for _, page in ipairs(spec.pages) do for _, control in ipairs(page.controls) do record.controls[control.id] = control end end
        api.mods[spec.id] = record
        return handle
    end
    _G.DBFMCM = api; assert(menu:update()); equal(registered, 1); equal(b.entries, 0)
    local controls = api.mods.goose_native_ads_camera_test.controls
    assert(controls.start_true_first_person.on_activate()); equal(b.entries, 1)
    b.cleanup_failures = 1; assert(not controls.stop_test.on_activate())
    menu:begin_shutdown(); assert(not menu:shutdown()); equal(unregistered, 0)
    assert(c:retry_cleanup()); assert(menu:shutdown()); equal(unregistered, 1)
    _G.DBFMCM = nil
end)
test('LLL disable keeps API and state until cleanup acknowledges', function()
    local _, b = mock()
    local modules = { ['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'), ['src/backend.lua'] = { new = function() return b end },
        ['src/controller.lua'] = Controller, ['src/menu.lua'] = Menu,
        ['src/placement_editor.lua'] = Editor,['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),
        ['src/camera.lua']=camera_module(b),['src/motion_runtime.lua']=motion_module(b),
        ['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near') }
    _G.mod = { require = function(name) return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua'))) end, log = function() end }
    _G.NativeADSCameraTest = nil
    local runtime = dofile(root .. '/main.lua')
    runtime.on_enable(); local api = assert(_G.NativeADSCameraTest)
    equal(b.entries, 0); assert(api.start(10)); b.cleanup_failures = 1
    assert(not runtime.on_disable()); equal(_G.NativeADSCameraTest, api); assert(not api.start(10))
    assert((b.fov_stops or 0)>0);equal(b.fov_active,false)
    assert(runtime.on_cleanup_poll()); equal(_G.NativeADSCameraTest, nil); equal(b.exits, 1)
    assert(not api.start(10)); equal(b.entries, 1)
    _G.mod = nil
end)

test('runtime toggle disables manual first person during a weapon wait', function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},
        ['src/controller.lua']=Controller,['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,
        ['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),['src/camera.lua']=camera_module(b),
        ['src/motion_runtime.lua']=motion_module(b),['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end}
    _G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());local _,result=api.status();equal(result.enabled,true);equal(result.manual,true)
    equal(result.camera.cleanup_pending,false);equal(result.motion.phase,'idle');equal(result.motion.dx,0)
    b.current.camera_kind=4;runtime.on_update()
    _,result=api.status();equal(result.phase,'waiting');equal(result.enabled,true)
    assert(api.toggle());_,result=api.status();equal(result.enabled,false);equal(result.phase,'idle')
    runtime.on_update();equal(b.entries,1)
    assert(runtime.on_disable());_G.mod=nil
end)

test('runtime FOV cleanup blocks new starts independently of clean camera state', function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},
        ['src/controller.lua']=Controller,['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,
        ['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),['src/camera.lua']=camera_module(b),
        ['src/motion_runtime.lua']=motion_module(b),['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end}
    _G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());equal(b.fov_active,true);b.fov_end_failure=true
    assert(not api.stop());local _,state=api.status();equal(state.enabled,false);equal(state.fov.cleanup_pending,true)
    assert(not api.start());assert(not api.start_native());equal(b.entries,1)
    b.fov_end_failure=false;runtime.on_update();assert(api.start());equal(b.entries,2)
    assert(runtime.on_disable());_G.mod=nil
end)

test('runtime head-camera cleanup independently blocks pose and baseline starts plus shutdown', function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},
        ['src/controller.lua']=Controller,['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,
        ['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),['src/camera.lua']=camera_module(b),
        ['src/motion_runtime.lua']=motion_module(b),['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end}
    _G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());runtime.on_update();equal(b.camera_active,true)
    b.camera_end_failure=true
    assert(not api.stop());local _,state=api.status()
    equal(state.enabled,false);equal(state.fov.cleanup_pending,false);equal(state.camera.cleanup_pending,true)
    assert(not api.start());assert(not api.start_native());assert(not api.preflight());equal(b.entries,1)
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert((b.motion_resets or 0)>=2);equal(b.camera_pending,true)
    b.camera_end_failure=false
    assert(runtime.on_cleanup_poll());equal(_G.NativeADSCameraTest,nil);equal(b.camera_pending,false)
    assert(not api.start());equal(b.entries,1);_G.mod=nil
end)

test('runtime yields to held Photo Mode without prearming or updating head and FOV policies',function()
    local _,b,clock=mock();b.photo_held=true
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},
        ['src/controller.lua']={new=function(backend,log)return Controller.new(backend,log,function()return clock.value end)end},
        ['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,
        ['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),['src/camera.lua']=camera_module(b),
        ['src/motion_runtime.lua']=motion_module(b),['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end}
    _G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());local _,result=api.status()
    equal(result.enabled,true);equal(result.phase,'waiting');equal(b.entries,0)
    for _=1,3 do runtime.on_update()end
    equal(b.compat_prepares or 0,0);equal(b.camera_prepares or 0,0)
    equal(b.camera_updates or 0,0);equal(b.fov_updates or 0,0)
    assert(not api.edit_placement());equal(b.entries,0)
    b.photo_held=false;clock.value=clock.value+.2;runtime.on_update();_,result=api.status()
    equal(result.enabled,true);equal(result.phase,'running');equal(b.entries,1)
    equal(b.compat_prepares,1);equal(b.camera_prepares,1);equal(b.fov_active,true)
    local camera_updates,fov_updates=b.camera_updates,b.fov_updates
    b.photo_held=true;runtime.on_update();_,result=api.status()
    equal(result.enabled,true);equal(result.phase,'waiting')
    equal(b.camera_updates,camera_updates);equal(b.fov_updates,fov_updates)
    equal(b.camera_active,false);equal(b.fov_active,false);equal(b.entries,1)
    assert(api.stop());_,result=api.status();equal(result.enabled,false);equal(b.compat_installed,false)
    b.photo_held=false;runtime.on_update();equal(b.entries,1)
    assert(runtime.on_disable());_G.mod=nil
end)

test('compatibility cleanup independently blocks starts and retains API until shutdown retry',function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},
        ['src/controller.lua']=Controller,['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,
        ['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),['src/camera.lua']=camera_module(b),
        ['src/motion_runtime.lua']=motion_module(b),['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end}
    _G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());equal(b.compat_installed,true)
    b.compat_stop_failure=true
    assert(not api.stop());local _,result=api.status();equal(result.enabled,false)
    equal(b.camera_pending,false);equal(b.fov_pending,false);equal(b.compat_installed,true)
    assert(not api.start());assert(not api.start_native());assert(not api.preflight());equal(b.entries,1)
    local camera_stops,fov_stops=b.camera_stops,b.fov_stops
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert(b.camera_stops>camera_stops and b.fov_stops>fov_stops);equal(b.compat_shutdowns,1)
    b.compat_stop_failure=false;assert(runtime.on_cleanup_poll())
    equal(b.compat_shutdowns,2);equal(b.compat_installed,false);equal(_G.NativeADSCameraTest,nil)
    assert(not api.start());equal(b.entries,1);_G.mod=nil
end)

test('pose cleanup failure never skips independent head and movement restoration',function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},['src/controller.lua']=Controller,
        ['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),
        ['src/camera.lua']=camera_module(b),['src/motion_runtime.lua']=motion_module(b),
        ['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),
        ['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end};_G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());runtime.on_update();equal(b.head_active,true);equal(b.movement_active,true)
    local head_stops,movement_stops=b.head_stops or 0,b.movement_stops or 0
    b.pose_finish_failure=true
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert((b.head_stops or 0)>head_stops);assert((b.movement_stops or 0)>movement_stops)
    equal(b.head_active,false);equal(b.movement_active,false)
    local _,state=api.status();equal(state.cleanup_pending,true);equal(state.head.cleanup_pending,false)
    equal(state.movement.cleanup_pending,false);equal(state.enabled,false)
    b.pose_finish_failure=false;assert(runtime.on_cleanup_poll());equal(_G.NativeADSCameraTest,nil)
    equal(b.entries,1);equal(b.exits,1);_G.mod=nil
end)

test('DoF restoration independently blocks starts and retains API until acknowledged',function()
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},['src/controller.lua']=Controller,
        ['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),
        ['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),
        ['src/camera.lua']=camera_module(b),['src/motion_runtime.lua']=motion_module(b),
        ['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),
        ['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end};_G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    assert(api.start());runtime.on_update();equal(b.dof_active,true)
    b.dof_end_failure=true
    assert(not api.stop());local _,state=api.status()
    equal(state.enabled,false);equal(state.dof.cleanup_pending,true);equal(b.head_active,false)
    equal(b.movement_active,false);equal(b.camera_active,false);equal(b.blur_active,false)
    assert(not api.start());assert(not api.start_native());assert(not api.preflight());equal(b.entries,1)
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    b.dof_end_failure=false;assert(runtime.on_cleanup_poll());equal(_G.NativeADSCameraTest,nil)
    equal(b.dof_active,false);equal(b.dof_pending,false);assert(not api.start());_G.mod=nil
end)

local function coordinated_runtime(extra)
    local _,b=mock()
    local modules={['src/action_placement.lua']=dofile(root..'/src/action_placement.lua'),['src/backend.lua']={new=function()return b end},['src/controller.lua']=Controller,
        ['src/menu.lua']=Menu,['src/placement_editor.lua']=Editor,['src/zoom.lua']={attach=function(fov)return fov end},['src/fov.lua']=fov_module(b),
        ['src/blur.lua']=presentation_module(b,'blur'),['src/dof.lua']=presentation_module(b,'dof'),
        ['src/camera.lua']=camera_module(b),['src/motion_runtime.lua']=motion_module(b),
        ['src/camera_compat.lua']=compat_module(b),['src/head_visibility.lua']=presentation_module(b,'head'),
        ['src/first_person_movement.lua']=presentation_module(b,'movement'),['src/near_clip.lua']=presentation_module(b,'near')}
    if extra then for name,value in pairs(extra(b))do modules[name]=value end end
    local previous_mod,previous_api=_G.mod,_G.NativeADSCameraTest
    _G.mod={require=function(name)return assert(modules[name] or((name=='src/model_shadow_source.lua'or name=='src/vignette.lua'or name=='src/native_ads_option.lua')and dofile(root..'/'..name))or(name=='src/head_placement.lua'and dofile(root..'/src/head_placement.lua')) or(name=='src/aim_markers.lua'and dofile(root..'/src/aim_markers.lua')))end,log=function()end};_G.NativeADSCameraTest=nil
    local runtime=dofile(root..'/main.lua');runtime.on_enable();local api=assert(_G.NativeADSCameraTest)
    local function restore()_G.mod,_G.NativeADSCameraTest=previous_mod,previous_api end
    return b,runtime,api,restore
end
test('scoped blur remains filtered throughout acknowledged and pending renderer suppression',function()
    local b,runtime,api,restore=coordinated_runtime()
    assert(api.start());equal(b.blur_active,true);runtime.on_update();equal(b.dof_active,true)
    local updates=b.blur_updates
    -- A pending command and an unavailable/unowned lease cannot replace the
    -- native filter, even if the queried renderer value happens to be false.
    b.dof_suppressed=true;b.dof_pending=true;runtime.on_update();equal(b.blur_active,true);equal(b.blur_updates,updates+1)
    b.dof_active=false;runtime.on_update();equal(b.blur_active,true);equal(b.blur_updates,updates+2)
    b.dof_suppressed=false;runtime.on_update();equal(b.blur_active,true);equal(b.blur_updates,updates+3)
    b.dof_suppressed=true;runtime.on_update();equal(b.blur_active,true)
    updates=b.blur_updates
    for _=1,20 do runtime.on_update()end
    equal(b.blur_updates,updates+20);equal(b.entries,1);local _,state=api.status();equal(state.enabled,true)
    equal(b.camera_active,true);equal(b.head_active,true);assert(runtime.on_disable());restore()
end)
test('renderer suppression changes preserve scoped blur until Photo handoff',function()
    local b,runtime,api,restore=coordinated_runtime()
    assert(api.start());runtime.on_update();b.dof_suppressed=true;runtime.on_update();equal(b.blur_active,true)
    local updates=b.blur_updates
    b.dof_suppressed=false;runtime.on_update();equal(b.blur_active,true);equal(b.blur_updates,updates+1);equal(b.entries,1)
    runtime.on_update();equal(b.blur_active,true);equal(b.entries,1)
    b.dof_suppressed=true;runtime.on_update();equal(b.blur_active,true)
    b.photo_held=true;updates=b.blur_updates;local dof_updates=b.dof_updates
    runtime.on_update();equal(b.blur_updates,updates);equal(b.blur_active,false);equal(b.dof_updates,dof_updates+1)
    assert(runtime.on_disable());restore()
end)
test('scoped blur shutdown failure preserves cleanup and independent renderer restoration',function()
    local b,runtime,api,restore=coordinated_runtime()
    assert(api.start());runtime.on_update();b.dof_suppressed=true;b.blur_end_failure=true
    assert(not api.stop());local _,state=api.status()
    equal(state.enabled,false);equal(b.blur_pending,true);equal(b.dof_active,false)
    equal(b.head_active,false);equal(b.movement_active,false);equal(b.camera_active,false)
    assert(not api.start());assert(not api.start_native());assert(not api.preflight());equal(b.entries,1)
    local dof_stops=b.dof_stops;assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert(b.dof_stops>dof_stops)
    b.blur_end_failure=false;assert(runtime.on_cleanup_poll());equal(_G.NativeADSCameraTest,nil)
    equal(b.blur_pending,false);assert(not api.start());restore()
end)
local function automatic_runtime(warm)
    local time=100;local engine_clock=stingray.Application.time_since_launch
    stingray.Application.time_since_launch=function()return time end
    local manager={enabled=false,phase='off',cache={},starts=0,updates=0}
    local backend
    local function resource()
        return backend.resource_key or'aaaaaaaaaaaaaaaa'
    end
    local function status()
        local s=backend.current
        if not s then return{}end
        local key=resource();local known=manager.cache[s.player_identity..':'..key]~=nil
        return{safe=s.safe==true,neutral=not s.aiming and not s.controller_active and not s.reloading and not backend.not_neutral,
            player_identity=s.player_identity,weapon_identity=s.identity,weapon_key=key,camera_kind=s.camera_kind,
            controller_active=s.controller_active==true,known=known,cached_ready=known and s.camera_kind==4}
    end
    function manager:is_enabled()return self.enabled end
    function manager:is_clean()return not self.enabled and self.phase=='off'end
    function manager:status()return self.phase end
    function manager:reference_status()return status()end
    function manager:refresh_target()
        local s=status();self.weapon_key,self.weapon_identity=s.weapon_key,s.weapon_identity;return true
    end
    function manager:cached_capture()
        local s=status();local saved=self.cache[s.player_identity..':'..s.weapon_key]
        if not saved then return nil end
        local out={};for k,v in pairs(saved)do out[k]=v end
        out.weapon_identity=s.weapon_identity;return out
    end
    function manager:start(reference)
        local s=status();assert(s.camera_kind==4 and s.safe)
        assert(reference.identity==s.player_identity and reference.weapon_identity==s.weapon_identity and reference.weapon_key==s.weapon_key)
        assert(reference.aim and reference.aim.method=='native_zero_offset_capture')
        assert(reference.reference.x==.15 and reference.reference.z==-.12)
        assert(reference.aim.reference.x==0 and reference.aim.reference.y==0 and reference.aim.reference.z==0)
        assert(reference.source_fov==reference.aim.source_fov and reference.aim.projection.fov==1.5)
        self.cache[s.player_identity..':'..s.weapon_key]=reference
        self.last_capture=reference
        self.enabled,self.phase=true,'Fird Person';self.starts=self.starts+1;self:refresh_target();return true
    end
    function manager:stop()self.enabled,self.phase=false,'off';return true end
    function manager:prepare_native_ads(s)
        assert(self.enabled and backend.current.camera_kind==4 and s.identity==backend.current.identity)
        backend.native_ads_prepares=(backend.native_ads_prepares or 0)+1;return true
    end
    function manager:update()self.updates=self.updates+1;return true end
    function manager:render_pose()
        assert(backend.frame_active,'Render pose must own its fresh backend frame')
        backend.render_pose_calls=(backend.render_pose_calls or 0)+1
        if backend.render_pose_error then error('fixture render pose error')end
        if backend.render_pose_refused then return false,'fixture render pose refused'end
        return true
    end
    local b,runtime,api,base_restore=coordinated_runtime(function(value)
        backend=value;backend.current.record=900;backend.current.weapon_unit=901;backend.capture_calls=0
        if warm then
            backend.camera_ready=function()return backend.warm_ready==true,'fixture packed FP page'end
            backend.warm_start=function(_,s)
                assert(s.camera_kind==4 and not backend.warm_lease)
                backend.warm_entries=(backend.warm_entries or 0)+1;backend.warm_ready=true
                local lease={origin=s,request=901};backend.warm_lease=lease
                backend.current.camera_kind,backend.current.record=6,901;return true,lease
            end
            backend.warm_finish=function(_,lease)
                assert(lease==backend.warm_lease)
                backend.warm_finishes=(backend.warm_finishes or 0)+1
                if backend.warm_finish_failure then return false,'fixture warm cleanup pending'end
                backend.warm_exits=(backend.warm_exits or 0)+1;lease.done=true;backend.warm_lease=nil
                backend.current.camera_kind,backend.current.record=4,900;return true
            end
        end
        local motion=motion_module(backend)
        local new_motion=motion.new
        motion.new=function(...)
            local m=new_motion(...)
            function m:capture_neutral(native_ads)
                backend.motion_capture_calls=(backend.motion_capture_calls or 0)+1
                backend.motion_native_ads=native_ads==true;backend.motion_capture_ready=true;return true
            end
            function m:reset()backend.motion_capture_ready=false;backend.motion_native_ads=false;backend.motion_resets=(backend.motion_resets or 0)+1;return true end
            function m:result()return{phase=backend.motion_capture_ready and'capture'or'idle',capture_ready=backend.motion_capture_ready==true,
                capture_native_ads=backend.motion_native_ads==true,dx=0,dy=0,dz=0}end
            return m
        end
        return{
            ['src/motion_runtime.lua']=motion,
            ['src/fird_person.lua']={render_pose_verified=true,
                capture=function(_,_,_,token)
                    local s=status();assert(s.camera_kind==6 and s.safe and s.neutral)
                    assert(token.identity==s.weapon_identity and token.player_identity==s.player_identity and token.weapon_key==s.weapon_key)
                    backend.capture_calls=backend.capture_calls+1
                    local ads=backend.motion_native_ads==true
                    local counter=ads and'ads_capture_calls'or'hip_capture_calls';backend[counter]=(backend[counter]or 0)+1
                    return{identity=s.player_identity,weapon_identity=s.weapon_identity,weapon_key=s.weapon_key,weapon_unit=backend.current.weapon_unit,
                        source_fov=1.5,reference=ads and{x=0,y=0,z=0}or{x=.15,y=0,z=-.12},pivot={0,.5,0},
                        projection={fov=1.5,position=ads and{0,.8,0}or{.15,.8,-.12},rotation={0,0,0,1}}}
                end,
                new=function(_,_,_,_,_,_,_,_,_,options)
                    assert(options.fov and options.source and options.retarget and options.aim and options.native_ads and type(options.aim_mode)=='function')
                    assert(options.render_driven==true,'Production Fird must publish at render')
                    assert(options.camera_frame and options.camera_frame.fixture_camera,'Production Fird must use the paired presented camera pose')
                    assert(options.presentation==nil,'Automatic Fird must retain the third-person model links')
                    manager.options=options;return manager
                end},
            ['src/fird_auto.lua']=dofile(root..'/src/fird_auto.lua'),
            ['src/fird_warm.lua']=dofile(root..'/src/fird_warm.lua'),
            ['src/fird_capture_ready.lua']={scene_lens=function()return 1.5 end,new=function()return{
                reset=function()backend.readiness_resets=(backend.readiness_resets or 0)+1 end,
                update=function(_,sample)
                    backend.readiness_samples=(backend.readiness_samples or 0)+1
                    assert(sample.snapshot.identity==sample.target.weapon_identity)
                    if backend.readiness_hold or(backend.readiness_hold_ads and sample.motion.capture_native_ads)
                        or not sample.motion.capture_ready then return false,'Waiting for fixture pose'end
                    assert(sample.fov.armed and sample.camera.armed and sample.pose.armed)
                    return true,{identity=sample.snapshot.identity,player_identity=sample.snapshot.player_identity,
                        request=sample.snapshot.record,weapon_key=sample.target.weapon_key,lens=sample.lens}
                end}end},
            ['src/fird_fov.lua']={new=function()return{}end},
            ['src/fird_presentation.lua']={new=function()error('Native presentation changes are forbidden in retarget mode')end},
            ['src/fird_source_pose.lua']={fixture_source=true},['src/fird_retarget.lua']={fixture_retarget=true},
            ['src/fird_camera_pose.lua']={fixture_camera=true},
            ['src/fird_weapon_children.lua']={fixture_children=true},
            ['src/fird_render.lua']=render_module(backend),
            ['src/fird_aim.lua']=dofile(root..'/src/fird_aim.lua'),
            ['src/fird_native_ads.lua']=dofile(root..'/src/fird_native_ads.lua'),
            ['src/skinned_placement.lua']={},['src/support_hand.lua']={}}
    end)
    local function step(n)
        for _=1,n or 1 do time=time+.1;runtime.on_update()end
    end
    local function restore()base_restore();stingray.Application.time_since_launch=engine_clock end
    return b,runtime,api,manager,step,restore
end
test('retained Fird diagnostic API captures the current weapon while API start retains TFP',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    assert(api.start_fird());equal(b.entries,0);local _,state=api.status();assert(state.enabled and state.fird.pending)
    step(9);assert(m.enabled and m.starts==1 and m.updates>0)
    equal(b.entries,1);equal(b.exits,1);assert(b.capture_calls>=4 and b.hip_capture_calls>=2 and b.ads_capture_calls>=2 and b.motion_capture_calls>0)
    assert(m.last_capture.projection.position[1]==.15 and m.last_capture.aim.projection.position[1]==0)
    equal(m.options.aim_mode(),'fird')
    _,state=api.status();assert(state.enabled and state.fird.enabled and not state.fird.pending)
    assert(api.toggle());assert(not m.enabled);step(3);equal(b.entries,1)
    local captures=b.capture_calls;assert(api.start());equal(b.entries,2)
    _,state=api.status();assert(state.mode=='pose_offset'and state.manual and state.enabled)
    step(2);equal(b.capture_calls,captures);assert(not m.enabled)
    assert(api.toggle());assert(runtime.on_disable());restore()
end)
test('Fird automatic entry waits for asynchronous cleanup and does not overlap the FP and render owners',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    assert(api.start());step(1);b.dof_end_failure=true;assert(api.start_fird())
    assert(not api.start());assert(not api.start_native());step(4)
    assert(not m.enabled and m.starts==0);equal(b.entries,1);equal(b.dof_pending,true)
    b.dof_end_failure=false;step(10);assert(m.enabled and m.starts==1)
    equal(b.entries,2);equal(b.exits,2);assert(not b.fov_active and not b.camera_active)
    assert(api.toggle());assert(runtime.on_disable());restore()
end)
test('Fird render owns a fresh frame and forwards failures without native camera entry or unbalanced cleanup',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    assert(api.start_fird());step(9);assert(m.enabled and b.render_active and m.options.render_driven)
    local entries,exits=b.entries,b.exits
    local begins,ends=b.frame_begins,b.frame_ends
    assert(b.render_deps.active() and b.render_deps.foreign()==false)
    assert(b.render_callback());equal(b.render_pose_calls,1)
    equal(b.frame_begins,begins+1);equal(b.frame_ends,ends+1);assert(not b.frame_active)
    b.render_pose_error=true
    local called,done,why=pcall(b.render_callback)
    assert(called and done==false);contains(why,'fixture render pose error')
    equal(b.frame_begins,begins+2);equal(b.frame_ends,ends+2);assert(not b.frame_active)
    b.render_pose_error=false;b.render_pose_refused=true
    done,why=b.render_callback();assert(done==false);contains(why,'fixture render pose refused')
    equal(b.frame_begins,begins+3);equal(b.frame_ends,ends+3);assert(not b.frame_active)
    b.frame_active=true;assert(not b.render_deps.active());assert(b.render_callback())
    equal(b.frame_begins,begins+3);equal(b.frame_ends,ends+3);b.frame_active=false
    equal(b.entries,entries);equal(b.exits,exits)
    assert(api.toggle());assert(not b.render_deps.active());assert(b.render_callback())
    equal(b.frame_begins,begins+3);equal(b.frame_ends,ends+3)
    assert(runtime.on_disable());assert(not b.render_active and b.render_stops>0);restore()
end)
test('Fird render unsubscribe failure retains the runtime cleanup contract until the owned listener drains',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    assert(api.start_fird());step(9);assert(m.enabled)
    b.render_stop_failure=true
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert(not m.enabled and not b.render_deps.active())
    local calls=b.render_pose_calls;assert(b.render_callback());equal(b.render_pose_calls,calls)
    b.render_stop_failure=false;assert(runtime.on_cleanup_poll())
    equal(_G.NativeADSCameraTest,nil);assert(not b.render_active);restore()
end)
test('unknown weapon swaps capture once and cached weapons return without another native FP session',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    assert(api.start_fird());step(9);assert(m.enabled);equal(b.entries,1)
    b.current.identity='context/avatar/weapon-B';b.current.weapon_unit=902;b.resource_key='bbbbbbbbbbbbbbbb'
    step(14);assert(m.enabled and m.starts==2);equal(b.entries,2);equal(b.exits,2)
    local captures=b.capture_calls
    b.current.identity='context/avatar/weapon-A';b.current.weapon_unit=901;b.resource_key='aaaaaaaaaaaaaaaa'
    step(8);equal(b.entries,2);equal(b.capture_calls,captures);assert(m.enabled)
    assert(api.toggle());assert(runtime.on_disable());restore()
end)
test('toggle cancellation during retained diagnostic capture clears intent and never starts Fird Person later',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    b.readiness_hold=true;assert(api.start_fird());step(4);equal(b.entries,1);equal(b.current.camera_kind,6)
    assert(api.toggle());equal(b.current.camera_kind,4);equal(b.exits,1)
    b.readiness_hold=false;step(15);assert(not m.enabled and m.starts==0);equal(b.entries,1);equal(b.capture_calls,0)
    local _,state=api.status();assert(not state.enabled)
    assert(runtime.on_disable());restore()
end)
test('toggle cancellation during retained zero-offset sight sampling retires the same FP lease without starting a partial reference',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    b.readiness_hold_ads=true;assert(api.start_fird());step(6)
    assert((b.hip_capture_calls or 0)>=2 and not b.ads_capture_calls and b.motion_native_ads)
    equal(b.entries,1);assert(api.toggle());equal(b.exits,1)
    b.readiness_hold_ads=false;step(12);assert(not m.enabled and m.starts==0);equal(b.entries,1)
    assert(runtime.on_disable());restore()
end)
test('Photo Mode holds an automatic diagnostic Fird request without native entry and cancellation prevents a later bootstrap',function()
    local b,runtime,api,m,step,restore=automatic_runtime()
    b.photo_held=true;assert(api.start_fird());step(8);equal(b.entries,0);assert(not m.enabled)
    assert(api.toggle());b.photo_held=false;step(8);equal(b.entries,0);equal(b.capture_calls,0)
    assert(runtime.on_disable());restore()
end)
test('bounded Fird probes reject invalid/active requests and always cancel capture or active view at the deadline',function()
    for _,phase in ipairs({'capture','active'})do
        local b,runtime,api,m,step,restore=automatic_runtime()
        assert(not api.probe_fird(nil))
        for _,duration in ipairs({'2',0,.5,11,math.huge,0/0})do assert(not api.probe_fird(duration))end
        equal(b.entries,0);local _,state=api.status();assert(not state.enabled)
        b.readiness_hold=phase=='capture'
        assert(api.probe_fird(phase=='capture'and 1 or 2));assert(not api.probe_fird(1))
        step(phase=='capture'and 4 or 9)
        if phase=='capture'then assert(not m.enabled and b.current.camera_kind==6)
        else assert(m.enabled and m.starts==1)end
        assert(not api.probe_fird(1));step(20)
        _,state=api.status();assert(not state.enabled and not m.enabled and b.current.camera_kind==4,phase)
        equal(b.entries,1);equal(b.exits,1);local captures=b.capture_calls
        b.readiness_hold=false;step(8);equal(b.entries,1);equal(b.capture_calls,captures)
        assert(api.start());assert(not api.probe_fird(1));assert(api.toggle())
        assert(runtime.on_disable());restore()
    end
end)
test('F11 cancellation keeps polling an owned warm camera after automatic intent is off',function()
    local b,runtime,api,m,step,restore=automatic_runtime(true)
    b.warm_finish_failure=true;assert(api.start_fird());step(3)
    equal(b.warm_entries,1);assert(b.warm_lease and b.current.camera_kind==6)
    equal(b.entries,0);assert(not b.pose_preparations and m.starts==0)
    assert(not api.toggle());local _,state=api.status();assert(not state.enabled)
    assert(not api.probe_fird(1));local retries=b.warm_finishes;step(3)
    assert(b.warm_finishes>retries and b.warm_lease and b.entries==0)
    b.warm_finish_failure=false;step(2)
    assert(not b.warm_lease and b.current.camera_kind==4);equal(b.warm_exits,1)
    step(8);equal(b.entries,0);assert(not m.enabled and m.starts==0)
    assert(runtime.on_disable());restore()
end)

local function native_animation_runtime()
    local time=100;local engine_clock=stingray.Application.time_since_launch
    stingray.Application.time_since_launch=function()return time end
    local manager={enabled=false,phase='off',native_animation=true,starts=0,updates=0,stops=0}
    local backend
    function manager:is_enabled()return self.enabled end
    function manager:is_clean()return not self.enabled and self.phase=='off'end
    function manager:status()return self.phase end
    function manager:refresh_target()
        self.refreshes=(self.refreshes or 0)+1
        local s=backend.current;if not s then return false,'fixture player unavailable'end
        self.weapon_identity=s.identity;return true
    end
    function manager:start_native()
        self.starts=self.starts+1
        assert(backend.entries==backend.exits,'Native-animation view overlapped an owned FP camera')
        assert(not backend.camera_active and not backend.dof_pending,'Previous view cleanup was not acknowledged')
        if backend.native_start_partial then self.enabled,self.phase=true,'starting'end
        if backend.native_start_failure then return false,'fixture native animation start refused'end
        self.enabled,self.phase=true,'Native animation'
        if self.options.ready_pose then self.options.ready_pose:request(true)end
        return true
    end
    function manager:stop()
        self.stops=self.stops+1;self.enabled=false
        if self.options and self.options.ready_pose then self.options.ready_pose:stop()end
        if backend.native_stop_failure then self.phase='cleanup pending';return false,'fixture native animation cleanup pending'end
        self.phase='off';return true
    end
    function manager:update()self.updates=self.updates+1;return true end
    function manager:start()error('Native animation must not consume an FP capture')end
    function manager:render_pose()error('Native animation must not rewrite render poses')end
    function manager:reference_status()error('Native animation must not bootstrap a weapon reference')end
    function manager:cached_capture()error('Native animation must not discover captured placement')end
    local b,runtime,api,base_restore=coordinated_runtime(function(value)
        backend=value
        return{
            ['src/ready_pose.lua']=dofile(root..'/src/ready_pose.lua'),
            -- This fixture isolates camera ownership. Real ready-pose graph
            -- calls have their own backend/intent and Update-scope fixtures.
            ['src/ready_pose_source.lua']={new=function()error('Camera-only fixture has no authored pose graph')end},
            ['src/ready_pose_timing.lua']={new=function()error('Camera-only fixture must not mutate animation')end},
            ['src/held_fire.lua']={new=function()
                return{update=function()return true end,matches=function()return false end,
                    stop=function()return true end,is_clean=function()return true end,result=function()return{phase='off'}end}
            end},
            ['src/fird_person.lua']={native_animation_default=true,
                capture=function()error('Native animation must not capture FPS poses')end,
                new=function(_,_,_,_,_,_,_,_,_,options)
                    assert(options.native_animation==true and options.render_driven==false and options.fov and options.native_ads)
                    for _,key in ipairs({'source','retarget','skin','children','support','presentation','camera_frame','aim'})do
                        assert(options[key]==nil,'Native animation loaded pose owner '..key)
                    end
                    manager.options=options;return manager
                end},
            ['src/fird_fov.lua']={new=function()return{}end},
            ['src/fird_native_ads.lua']=dofile(root..'/src/fird_native_ads.lua')}
    end)
    local forbidden={}
    for _,name in ipairs({'fird_auto','fird_warm','fird_capture_ready','fird_render','fird_camera_pose','fird_source_pose',
        'fird_retarget','fird_aim','skinned_placement','support_hand','fird_weapon_children','fird_presentation'})do
        forbidden['src/'..name..'.lua']=true
    end
    local require_module=_G.mod.require
    _G.mod.require=function(name)
        assert(not forbidden[name],'Native-animation runtime must not load '..name)
        return require_module(name)
    end
    local function step(count)
        for _=1,count or 1 do time=time+.1;runtime.on_update()end
    end
    local function restore()base_restore();stingray.Application.time_since_launch=engine_clock end
    return b,runtime,api,manager,step,restore
end
test('retained native-animation API starts directly without FP capture retargeting or renderer owners',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    assert(api.start_fird());assert(m.enabled and m.starts==1)
    step(4);assert(m.updates==4 and m.refreshes>=4 and not b.frame_active)
    equal(b.entries,0);equal(b.exits,0);equal(b.pose_preparations,nil);equal(b.render_starts,nil)
    local _,state=api.status();assert(state.enabled and state.fird.enabled and not state.fird.pending)
    assert(api.toggle());assert(not m.enabled and m:is_clean())
    assert(api.start_fird());assert(m.enabled and m.starts==2);step(3)
    equal(b.entries,0);equal(b.render_callback,nil)
    assert(api.stop());assert(m:is_clean());assert(runtime.on_disable());restore()
end)
test('native-animation partial start failure drains its manager without starting FP capture',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    b.native_start_partial,b.native_start_failure=true,true
    local done,why=api.start_fird();assert(done==false);contains(why,'native animation start refused')
    assert(not m.enabled and m:is_clean()and m.stops>0);equal(b.entries,0)
    b.native_start_partial,b.native_start_failure=false,false
    assert(api.start_fird());step(2);assert(m.enabled and m.starts==2)
    equal(b.entries,0);assert(runtime.on_disable());restore()
end)
test('native-animation pending stop retains API and blocks all replacement owners until cleanup',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    assert(api.start_fird());step(1);b.native_stop_failure=true
    assert(not api.stop());assert(not m.enabled and not m:is_clean())
    local starts=m.starts;assert(not api.start_fird());equal(m.starts,starts)
    assert(not api.start());assert(not api.probe_fird(1))
    local head_stops=b.head_stops or 0
    assert(not runtime.on_disable());equal(_G.NativeADSCameraTest,api)
    assert((b.head_stops or 0)>head_stops and b.entries==0 and not b.frame_active)
    b.native_stop_failure=false;assert(runtime.on_cleanup_poll());equal(_G.NativeADSCameraTest,nil)
    assert(m:is_clean()and not api.start_fird());restore()
end)
test('native-animation bounded probe stops at deadline and explicit cancellation cannot expire a later manual view',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    for _,duration in ipairs({'2',0,.5,11,math.huge,0/0})do assert(not api.probe_fird(duration))end
    equal(m.starts,0);assert(api.probe_fird(1));assert(m.enabled)
    assert(not api.probe_fird(1));step(9);assert(m.enabled);step(2);assert(m:is_clean())
    local starts=m.starts;step(15);equal(m.starts,starts);assert(not m.enabled)
    assert(api.probe_fird(1));step(2);assert(api.stop());assert(api.start_fird())
    step(20);assert(m.enabled and m.starts==starts+2)
    equal(b.entries,0);equal(b.exits,0);assert(runtime.on_disable());restore()
end)
test('native-animation entry waits for previous diagnostic FP owner cleanup',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    assert(api.start());step(1);equal(b.entries,1)
    b.dof_end_failure=true;assert(not api.start_fird());equal(m.starts,0);assert(not m.enabled)
    b.dof_end_failure=false;assert(api.start_fird());assert(m.enabled and m.starts==1)
    equal(b.entries,1);equal(b.exits,1);equal(b.pose_preparations,1)
    assert(runtime.on_disable());restore()
end)
test('separate True First Person API retains original native rig and clean view ownership',function()
    local b,runtime,api,m,step,restore=native_animation_runtime()
    assert(type(api.start)=='function'and type(api.start_true_first_person)=='function')
    assert(api.start_true_first_person());step(1);equal(b.entries,1);equal(m.starts,0)
    local _,state=api.status();equal(state.mode,'pose_offset');assert(state.enabled and not state.fird)
    assert(not api.start_true_first_person());equal(b.entries,1)
    assert(api.stop());assert(api.start_fird());equal(m.starts,1);equal(b.entries,1)
    assert(not api.start_true_first_person());equal(b.entries,1)
    b.native_stop_failure=true;assert(not api.stop());assert(not api.start_true_first_person());equal(b.entries,1)
    b.native_stop_failure=false;assert(api.stop());assert(api.start_true_first_person());equal(b.entries,2);equal(m.starts,1)
    assert(api.toggle());assert(not m.enabled);equal(b.exits,2)
    assert(api.toggle());assert(not m.enabled and m.starts==1);equal(b.entries,3)
    _,state=api.status();assert(state.enabled and state.mode=='pose_offset')
    assert(api.stop());assert(runtime.on_disable());restore()
end)
test('persistent first-person intent can start inside a vehicle without forcing firearm ADS',function()
    local _,b=mock();b.pin_first_person=true;b.no_firearm=true
    b.current.camera_kind=12;b.current.safe=false;b.current.seated=true
    function b:pin_player_snapshot()self.pin_reads=(self.pin_reads or 0)+1;return self:player_snapshot()end
    local timestamp=0;local c=Controller.new(b,nil,function()return timestamp end)
    assert(c:start(0,'pose_offset'));equal(c:is_enabled(),true);equal(c.phase,'waiting');equal(b.entries,0)
    for _=1,20 do timestamp=timestamp+.1;assert(c:update())end
    equal(b.entries,0);assert(b.pin_reads>0)
    b.no_firearm=false;b.current.camera_kind=4;b.current.safe=true;b.current.seated=false
    timestamp=timestamp+.3;assert(c:update());equal(b.entries,1);equal(c.phase,'running')
    assert(c:stop());equal(c:is_enabled(),false)
end)
test('persistent eye intent survives unavailable native arms without forcing their entry',function()
    for _,fault in ipairs({'preflight','camera'})do
        local c,b,clock=mock();b.pin_first_person=true
        if fault=='preflight'then b.pose_preflight_failure=true
        else b.camera_before_entry=function()return false,'fixture camera generation settling'end end
        assert(c:start(0,'pose_offset'));equal(c:is_enabled(),true);equal(c.phase,'waiting');equal(b.entries,0)
        clock.value=clock.value+1;assert(c:update());equal(c:is_enabled(),true);equal(b.entries,0)
        b.pose_preflight_failure=false;b.camera_before_entry=nil
        clock.value=clock.value+1;assert(c:update());equal(c.phase,'running');equal(b.entries,1)
        assert(c:stop())
    end
end)
test('recoverable suspend preserves persistent intent but waits for acknowledged cleanup before fresh reentry',function()
    local c,b,clock=mock();assert(c:start(0,'pose_offset'));local entered=b.entries
    local player=c:result().player_identity;equal(player,b.current.player_identity)
    b.cleanup_failures=1;assert(not c:suspend('temporary read'))
    assert(c:is_enabled());equal(c.phase,'cleanup_pending');equal(b.entries,entered)
    assert(c:update());equal(b.entries,entered);assert(c:is_enabled())
    clock.value=clock.value+1;assert(c:update());equal(b.entries,entered+1);assert(c:is_enabled())
    assert(c:stop());assert(not c:suspend('after stop'))
    local timed=mock();assert(timed:start(1,'pose_offset'));assert(not timed:suspend('timed diagnostic'));assert(timed:stop())
end)
print('Native ADS controller/lifecycle fixtures: ' .. passed .. ' passed')

stingray=original_stingray
