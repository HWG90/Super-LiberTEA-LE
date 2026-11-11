local mod=mod.require('src/first_person.lua').host(mod)
local PORT51=mod.require('src/first_person/compat51.lua')
local controller, menu, editor, fov, camera, motion, compat, head, movement, blur, api, foreign_camera, handoff_ready, backend, dof, near
local fird,fird_entry,fird_warm,fird_render
local fird_tick=0
local fp_dof_player
local fird_capture_phase
local probe_update
local aim_markers,native_aim
local ready_pose,ready_timing,ready_context
local held_fire
local ready_tick=0
local stopping = false
local recovery,diagnostics,presentation,runtime_clock,presentation_module
local recovery_enabled=false
local diagnostics_fault
local diagnostics_look,diagnostics_look_at
local recovery_owner,owner_draining
-- True once every sub-system stopped cleanly while first person is off; their per-frame stop
-- calls are no-ops until it is enabled again, so update_frame skips them.
local idle_clean = false
local function log(message) mod.log(tostring(message)) end
local function attempt(target,name,...)
    local called,done,why=pcall(target[name],target,...)
    if not called then return false,tostring(done) end
    return done,why
end



local function view_snapshot()
    if backend and backend.pin_first_person==true and PORT51.kind(backend.pin_player_snapshot)=='function'then
        local s=attempt(backend,'pin_player_snapshot')
        if PORT51.kind(s)=='table'then return s end
    end
    return backend and attempt(backend,'player_snapshot')or nil
end
local function pinned_ready(s)
    if not controller or attempt(controller,'is_enabled')~=true then return false end
    local state=attempt(controller,'result')
    if PORT51.kind(state)~='table' or state.mode~='pose_offset'then return false end
    if foreign_camera then
        local ok,held=pcall(foreign_camera)
        if not ok or held~=false then return false end
    end
    return camera and PORT51.kind(camera.is_pinned)=='function' and attempt(camera,'is_pinned',s)==true or false
end
local function first_person_view(fallback_ready)
    if foreign_camera and foreign_camera()then return false end
    local s=view_snapshot()
    if not s then return false end
    if pinned_ready(s)then return true end
    if not s.safe or(s.camera_kind~=4 and s.camera_kind~=6)then return false end
    if fird and fird:is_enabled()then
        return fird.weapon_snapshot and fird.weapon_snapshot.safe==true
            and fird.weapon_snapshot.player_identity==s.player_identity or false
    end
    local warm=backend.warm_lease
    if fird_entry and fird_entry:is_enabled()and warm and warm.origin
        and warm.origin.player_identity==s.player_identity and s.camera_kind==6 then return true end
    local state=controller:result()
    if not controller:is_enabled()or state.mode~='pose_offset'then return false end
    local lease=controller.lease
    if lease and lease.origin then fp_dof_player=lease.origin.player_identity end
    if not fp_dof_player or s.player_identity~=fp_dof_player then return false end
    return s.camera_kind==6 or fallback_ready()
end

-- Only loader Update/cleanup-poll dispatch opens this private authority.
-- API stop/disable requests outside it cancel intent and retain cleanup.
local function ready_update()
    if not ready_pose or not ready_context then return true end
    local called,done,why=pcall(ready_pose.update,ready_pose,ready_context)
    if not called then
        if held_fire then attempt(held_fire,'stop')end
        attempt(ready_pose,'stop')
        log('Ready stance cleanup retained: '..tostring(done))
        return false,tostring(done)
    end
    if held_fire then
        if not ready_pose:is_enabled()then
            attempt(held_fire,'stop')
        else
            local read,admission=pcall(ready_pose.filter_owner,ready_pose,ready_context)
            if not read then admission=nil end
            local updated=attempt(held_fire,'update',admission,ready_context)
            if updated~=true then
                -- Refused or uncertain publication retains cleanup ownership.
                -- Drain it here and on later Updates before a fresh Begin.
                attempt(held_fire,'stop')
            end
        end
    end
    return done,why
end

local function qualified_frame(callback)
    local frame_backend=backend
    if not frame_backend then return callback()end
    assert(not ready_context and not frame_backend.frame_active,'First-person Update frame is already owned')
    frame_backend:begin_frame()
    ready_tick=ready_tick+1
    ready_context={phase='qualified_update',tick=ready_tick}
    local ok,a,b=pcall(callback)
    ready_context=nil
    frame_backend:end_frame()
    if not ok then error(a,0)end
    return a,b
end

local function ensure_ready_pose()
    if ready_pose then return ready_pose end
    local Ready=mod.require('src/first_person/ready_pose.lua')
    local ReadySource=mod.require('src/first_person/ready_pose_source.lua')
    local Timing=mod.require('src/first_person/ready_pose_timing.lua')
    local HeldFire=mod.require('src/first_person/held_fire.lua')
    held_fire=HeldFire.new(backend,{authorized=function(context)
        return ready_context~=nil and context==ready_context and backend.frame_active==true
    end,log=log})
    local function native_ready_gate(expected,context)
        if not ready_context or context~=ready_context or backend.frame_active~=true then
            return false,'Ready stance requires the owned Update scope'
        end
        if expected.safeNormal4~=true or expected.actualAim or expected.reload or expected.sprint or expected.firing or expected.weapon_transition
            or expected.foreign or expected.ads then return false,'A native action owns the stance'end
        ready_timing=ready_timing or Timing.new(backend)
        local report,why=ready_timing:sample({phase='ready_pose_before_native',tick=context.tick,
            epoch=backend.frame_epoch,expected=expected.snapshot})
        if not report then return false,why end
        if report.observed_idle~=true or report.pending_batches~=0 or report.incomplete_after~=0
            or report.camera_kind~=4 or report.reloading or report.shoulder_aim then
            return false,'Animation work or a native action is active'
        end
        return true
    end
    ready_pose=Ready.new({source_factory=function()return ReadySource.new(backend,native_ready_gate)end,
        filter_valid=function(context,admission)return held_fire:matches(admission,context)end,
        log=function(reason,phase)log('Ready stance '..tostring(phase)..': '..tostring(reason))end,
        max_reapplications=0,retry_ticks=30})
    return ready_pose
end

local Actions
local function saved_placement(key,action)
    return Actions.resolve(mod.config,key,action or 'idle')
end

local function monotonic_clock()
    local application=stingray and stingray.Application
    local now=application and application.time_since_launch
    assert(PORT51.kind(now)=='function','Engine FPV clock unavailable')
    local previous
    return function()
        local value=now()
        assert(PORT51.kind(value)=='number'and value==value and value>=0 and value<math.huge,
            'Engine FPV clock sample invalid')
        assert(not previous or value>=previous,'Engine FPV clock moved backwards')
        previous=value
        return value
    end
end

local function render_fird_pose()
    if stopping or not fird or not fird:is_enabled()or not backend or backend.frame_active then return true end
    local frame_backend=backend
    frame_backend:begin_frame()
    local called,done,why=pcall(fird.render_pose,fird)
    frame_backend:end_frame()
    if not called then return false,tostring(done)end
    return done,why
end

local function shutdown()
    stopping = true
    local native_aim_done,native_aim_problem=true,nil
    if native_aim then native_aim_done,native_aim_problem=attempt(native_aim,'shutdown')end
    local fire_done,fire_problem=true,nil
    if held_fire then fire_done,fire_problem=attempt(held_fire,'stop')end
    if ready_pose then attempt(ready_pose,'stop')end
    if fird_entry then fird_entry:cancel()end
    if menu then menu:begin_shutdown() end
    local render_done,render_problem=true,nil
    if fird_render then render_done,render_problem=attempt(fird_render,'stop')end
    local markers_done,markers_problem=true,nil
    if aim_markers then markers_done,markers_problem=attempt(aim_markers,'shutdown')end
    local fird_done,fird_problem=true,nil
    if fird then fird_done,fird_problem=attempt(fird,'stop')end
    local warm_done,warm_problem=true,nil
    if fird_warm then warm_done,warm_problem=attempt(fird_warm,'stop')end
    local editor_done,editor_problem,controller_done,controller_problem,fov_done,fov_problem=true,nil,true,nil,true,nil
    if editor then
        editor_done,editor_problem=attempt(editor,'shutdown')
    end
    if controller then
        controller_done,controller_problem=attempt(controller,'shutdown')
    end
    if fov then fov_done,fov_problem=attempt(fov,'shutdown') end
    local blur_done,blur_problem=true,nil
    if blur then blur_done,blur_problem=attempt(blur,'shutdown')end
    local camera_done,camera_problem=true,nil
    if camera then camera_done,camera_problem=attempt(camera,'shutdown')end
    local head_done,head_problem=true,nil
    if head then head_done,head_problem=attempt(head,'shutdown')end
    local movement_done,movement_problem=true,nil
    if movement then movement_done,movement_problem=attempt(movement,'shutdown')end
    local dof_done,dof_problem=true,nil
    if dof then dof_done,dof_problem=attempt(dof,'shutdown')end
    local near_done,near_problem=true,nil
    if near then near_done,near_problem=attempt(near,'shutdown')end
    if motion then attempt(motion,'reset')end
    local compat_done,compat_problem=true,nil
    if compat then
        compat_done,compat_problem=attempt(compat,'shutdown')
        -- A recovered sharing error must not leave the old handoff latch
        -- blocking pose cleanup forever. foreign() still checks the current
        -- external camera lease, including a held or unavailable provider.
        handoff_ready=compat_done==true
    end
    -- Cleanup-poll enters the same qualified Update scope. Plain disable/API
    -- calls retain the ledger without invoking an animation-state restore.
    if ready_context then ready_update()end
    if ready_pose and not ready_pose:is_clean()then return false,'Ready stance restoration pending'end
    if native_aim_done==false then return false,native_aim_problem end
    if fire_done~=true then return false,fire_problem end
    if render_done~=true then return false,render_problem end
    if markers_done~=true then return false,markers_problem end
    if fird_done~=true then return false,fird_problem end
    if warm_done~=true then return false,warm_problem end
    if controller_done~=true then return false,controller_problem end
    if not editor_done then return false,editor_problem end
    if fov_done~=true then return false,fov_problem end
    if blur_done~=true then return false,blur_problem end
    if camera_done~=true then return false,camera_problem end
    if head_done~=true then return false,head_problem end
    if movement_done~=true then return false,movement_problem end
    if dof_done~=true then return false,dof_problem end
    if near_done~=true then return false,near_problem end
    if compat_done~=true then return false,compat_problem end
    if menu then
        local done, why = menu:shutdown()
        if done ~= true then return false, why end
    end
    if api and rawget(_G, 'NativeADSCameraTest') == api then rawset(_G, 'NativeADSCameraTest', nil) end
    controller, menu, editor, fov, camera, motion, compat, head, movement, blur, api, foreign_camera = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    backend,dof,fird,near,fird_entry,fird_warm,fird_render=nil,nil,nil,nil,nil,nil,nil
    aim_markers,native_aim=nil,nil
    ready_pose,ready_timing,held_fire=nil,nil,nil
    recovery,diagnostics,presentation,runtime_clock,presentation_module=nil,nil,nil,nil,nil;recovery_enabled=false;diagnostics_fault=nil;diagnostics_look,diagnostics_look_at=nil,nil;recovery_owner,owner_draining=nil,nil
    return true
end

local function recovery_time()
    if not runtime_clock then return 0 end
    return runtime_clock()
end
local function recovery_proof()
    local s=backend and attempt(backend,'snapshot')
    local state=controller and attempt(controller,'result')or{}
    local owner=state and state.player_identity
    if not owner and controller and controller.lease and controller.lease.origin then owner=controller.lease.origin.player_identity end
    local foreign=not foreign_camera or foreign_camera()
    return {fresh=backend and backend.frame_active==true and PORT51.kind(s)=='table',
        safe=s and s.safe==true or false,same_player=s and owner~=nil and s.player_identity==owner or false,
        foreign=foreign~=false},s
end
local function managed_update(name,target,...)
    if not recovery or not controller or not controller:is_enabled()then return attempt(target,'update',...)end
    local timestamp=recovery_time()
    local action=recovery:action(name,timestamp)
    if action=='cleanup'then
        local done,why=attempt(target,'stop')
        recovery:cleanup(name,done==true and attempt(target,'is_clean')==true,timestamp)
        local row=recovery:snapshot().policies[name]
        if row and row.core and row.phase=='fatal'then attempt(controller,'stop','First-person '..name..' cleanup completed after an unsafe fault')end
        return true,why
    elseif action~='update'then return true,'Presentation '..name..' '..action end
    if recovery:needs_proof(name)and not recovery:revalidate(name,recovery_proof(),timestamp)then return true,'Waiting for fresh presentation owner'end
    local done,why=attempt(target,'update',...)
    if done==true then
        local state=attempt(target,'result')or{}
        recovery:success(name,timestamp,state.phase=='active'and state.armed~=false)
        return true,why
    end
    local state=attempt(target,'result')or{}
    local proof=recovery_proof()
    local stopped=attempt(target,'stop')
    local clean=stopped==true and attempt(target,'is_clean')==true
    local row=recovery:failure(name,state,clean,proof,timestamp,why)
    if diagnostics then diagnostics:event(ready_context and ready_context.tick or 0,'policy_failure',
        {policy=name,reason=why,phase=row.phase,cleanup_pending=not clean})end
    if row.core then
        if row.phase=='fatal'then
            attempt(controller,'stop','First-person '..name..' fault: '..tostring(why))
        elseif PORT51.kind(controller.suspend)=='function'then
            attempt(controller,'suspend','Recovering '..name..': '..tostring(why))
        else attempt(controller,'stop','First-person '..name..' unavailable: '..tostring(why))end
    end
    return true,why -- cleanup/retry/degradation is now explicitly owned by recovery
end
-- A genuinely new body/world starts a new recovery episode only after every
-- old capability acknowledges cleanup, and a later Update proves that owner.
local function remember_recovery_owner(s)
    if owner_draining or not controller then return end
    local state=attempt(controller,'result')or{}
    local origin=controller.lease and controller.lease.origin
    local identity=state.player_identity or origin and origin.player_identity
    s=s or origin
    if PORT51.kind(s)=='table'and s.player_identity==identity
        and PORT51.kind(s.body)=='number'and PORT51.kind(s.world)=='number'then
        recovery_owner={identity=identity,body=s.body,world=s.world}
    end
end
local function recover_new_owner()
    if not recovery or not controller:is_enabled()then recovery_owner,owner_draining=nil,nil;return false end
    if not owner_draining and not recovery:has_policies()then
        -- The controller already acquired this origin with fresh ownership.
        -- An empty recovery ledger has nothing to drain or re-authorize.
        remember_recovery_owner()
        return false
    end
    local s=attempt(backend,'snapshot')
    if PORT51.kind(s)~='table'then return owner_draining~=nil end
    local identity=controller:result().player_identity
    if not identity and controller.lease and controller.lease.origin then identity=controller.lease.origin.player_identity end
    if not owner_draining and s.player_identity==identity and PORT51.kind(s.body)=='number'and PORT51.kind(s.world)=='number'then
        remember_recovery_owner(s)
    end
    local owner_changed=recovery_owner and s.player_identity~=recovery_owner.identity
        and PORT51.kind(s.player_identity)=='string'and PORT51.kind(s.body)=='number'and PORT51.kind(s.world)=='number'
        and(s.body~=recovery_owner.body or s.world~=recovery_owner.world)
    local faulty=next(recovery:snapshot().policies)~=nil
    if not owner_draining and not(owner_changed and faulty)then return false end
    if not owner_draining or owner_draining.identity~=s.player_identity then
        owner_draining={identity=s.player_identity,body=s.body,world=s.world,frame=ready_context.tick}
        if PORT51.kind(controller.suspend)=='function'then attempt(controller,'suspend','New local body: retiring presentation policies')end
        if editor and attempt(editor,'is_active')==true then attempt(editor,'cancel','Local player changed')end
    end
    if controller.lease then attempt(controller,'retry_cleanup')end
    local clean=controller.lease==nil
    for _,target in pairs({fov=fov,blur=blur,camera=camera,head=head,movement=movement,near=near,dof=dof,native_aim=native_aim,aim_markers=aim_markers})do
        local done=attempt(target,'stop');clean=clean and done==true and attempt(target,'is_clean')==true
    end
    if clean then owner_draining.cleaned_at=owner_draining.cleaned_at or ready_context.tick else owner_draining.cleaned_at=nil end
    if clean and s.safe==true and foreign_camera()==false and ready_context.tick>owner_draining.cleaned_at then
        recovery:owner_reset();if presentation then presentation:reset('local body changed')end
        recovery_owner={identity=s.player_identity,body=s.body,world=s.world};owner_draining=nil
        return false
    end
    return true
end

local function observe_presentation()
    if not presentation or not backend or not runtime_clock then return end
    local s=attempt(backend,'snapshot')
    if PORT51.kind(s)~='table'then s=attempt(backend,'pin_player_snapshot')end
    if PORT51.kind(s)=='table'then
        if recovery and not recovery:has_policies()then remember_recovery_owner(s)end
        local value={};for k,v in pairs(s)do value[k]=v end
        -- Use the authored discrete selection already observed by the owned
        -- depth policy. A changing rendered FOV is output, never a zoom ID.
        local lease=controller.lease
        local a=lease and lease.alignment
        if a and lease==backend.alignment_lease and lease.origin and lease.origin.identity==s.identity
            and lease.origin.player_identity==s.player_identity and not a.ended and a.kind=='pose'
            and PORT51.kind(a.helper.depth_stats)=='function'then
            local depth=attempt(a.helper,'depth_stats',a.handle)
            if PORT51.kind(depth)=='table'and depth.supported==true and depth.armed==true
                and PORT51.kind(depth.zoom_index)=='number'and depth.zoom_index%1==0 and depth.zoom_index>=0 and depth.zoom_index<32 then
                value.zoom_identity=depth.zoom_index
            end
        end
        value.controller_active=presentation_module.native_ads(value)
        presentation:update(value,runtime_clock(),controller:is_enabled(),foreign_camera())
    else presentation:update(nil,runtime_clock(),controller:is_enabled(),true)end
end
local function record_presentation(ok,why)
    if not diagnostics or not ready_context then return end
    local s=view_snapshot()or{}
    local state=controller and attempt(controller,'result')or{}
    local cam=camera and attempt(camera,'result')or{}
    local lens=fov and attempt(fov,'result')or{}
    local transition=presentation and presentation:result()or{}
    local foreign=foreign_camera and foreign_camera()or false
    local edit=editor and attempt(editor,'is_active')==true or false
    local blocked=recovery and recovery:blocks_view(recovery_time())or false
    local pinned=camera and PORT51.kind(camera.is_pinned)=='function'and attempt(camera,'is_pinned',s)==true or false
    local timestamp=recovery_time()
    if camera and not camera.retired and PORT51.kind(camera.look_stats)=='function'and (not diagnostics_look_at or timestamp<diagnostics_look_at or timestamp-diagnostics_look_at>=.1)then
        diagnostics_look=attempt(camera,'look_stats');diagnostics_look_at=timestamp
    end
    local look=PORT51.kind(diagnostics_look)=='table'and diagnostics_look or{}
    local placement=controller and attempt(controller,'get_placement')or{}
    local movement=motion and attempt(motion,'result')or{}
    -- While first person is on but the native view is not held, record what
    -- the full snapshot says: this is the evidence for a slow return.
    local control_mask,control_guard,weapon_ready,entry_block
    if PORT51.kind(s.controller_bytes)=='string'and #s.controller_bytes==6 then
        local a,b,c,d=s.controller_bytes:byte(1,4);control_mask,control_guard=a+b*256+c*65536+d*16777216,s.controller_bytes:byte(6)
    end
    if state.enabled==true and state.phase~='running'and backend then
        local full,problem=attempt(backend,'snapshot')
        if PORT51.kind(full)=='table'then weapon_ready=full.weapon_ready~=false;entry_block=full.reason
        else entry_block=tostring(problem)end
    end
    local head_state=head and attempt(head,'result')or{}
    diagnostics:record(ready_context.tick,{time=recovery_time(),enabled=state.enabled==true,
        control_mask=control_mask,control_guard=control_guard,safe=s.safe==true,aiming=s.aiming==true,
        snapshot_reason=s.reason,weapon_ready=weapon_ready,entry_block=entry_block,action=movement.action,
        softened=movement.softened,head_calls=cam.replaced,camera_gate=cam.error,head_phase=head_state.phase,
        player=s.player_identity,weapon=backend and backend.placement_weapon_key,request=s.record,
        camera_kind=s.camera_kind,ads=s.controller_active==true,foreign=foreign,editor=edit,
        phase=state.phase,transition_epoch=transition.epoch,transition_progress=transition.progress,
        pinned=pinned,pin_expected=false,camera_retired=camera and camera.retired==true,
        view_expected=state.enabled==true and state.mode=='pose_offset'and s.safe==true and not blocked and not foreign and not edit,
        view_visible=s.camera_kind==6 or(s.camera_kind==4 and s.safe==true and cam.phase=='active'and cam.armed==true and cam.error==0),
        recovering=blocked,fov_native=lens.last_native,fov_applied=lens.last_applied,
        camera_blend=cam.blend,pose_blend=state.blend,cleanup_pending=state.cleanup_pending,
        camera_epoch=cam.transition_epoch,fov_epoch=lens.transition_epoch,
        pose_epoch=controller.lease and backend.presentation_pose_lease==controller.lease and backend.presentation_pose_epoch or nil,
        placement_x=placement.x,placement_y=placement.y,placement_z=placement.z,
        placement_yaw=placement.yaw,placement_pitch=placement.pitch,placement_roll=placement.roll,
        motion_x=movement.dx,motion_y=movement.dy,motion_z=movement.dz,
        look_sequence=look.sequence,look_samples=look.samples,look_skipped=look.skipped,
        look_yaw=look.yaw,look_pitch=look.pitch,ads_rebases=look.ads_rebases,
        reason=not ok and tostring(why)or state.wait_reason})
end

local function update_frame()
    fird_tick=fird_tick+1
    if probe_update then probe_update()end
    -- Modern Photo exposes a local ownership flag. Observe it without
    -- changing its lease; older releases retain their reader-chain adapter.
    local sharing=attempt(compat,'update')
    handoff_ready=sharing==true
    if native_aim then attempt(native_aim,'update',controller)end
    if fird_entry and fird_entry:is_enabled()then
        local ready,why=attempt(fird_entry,'update')
        if ready~=true then log('Fird Person: '..tostring(why))end
        if fird_entry:is_pending()and not fird_entry:uses_fp()then
            if fird_warm and not fird_warm:is_clean()then attempt(dof,'update',controller,camera,compat)end
            menu:update();return
        end
    end
    if fird and fird:is_enabled()then
        if fird_render and not fird_render:result().active then
            local reason=fird_render:result().last_error or'Render callback is unavailable'
            attempt(fird,'stop');log('Fird Person: '..tostring(reason));menu:update();return
        end
        local ready,why=attempt(fird,'refresh_target')
        if ready~=true then
            attempt(aim_markers,'stop')
            attempt(editor,'cancel','Fird Person target changed');attempt(fird,'stop')
            log('Fird Person: '..tostring(why));menu:update();return
        end
        editor:update();fird:update();menu:update();return
    elseif fird and not fird:is_clean()then
        local ready=attempt(fird,'stop')
        if ready~=true then menu:update();return end
    end
    if fird_warm and not fird_warm:is_clean()then attempt(fird_warm,'stop');idle_clean=false end
    if recovery then
        local enabled=controller:is_enabled()
        if enabled~=recovery_enabled then recovery:reset();recovery_enabled=enabled end
    end
    if recover_new_owner()then menu:update();return end
    observe_presentation()
    if recovery and recovery:has_policies()then
        for name in pairs(recovery:snapshot().policies)do
            recovery:action(name,recovery_time()) -- only this owned Update advances retry state
            if recovery:needs_proof(name)then
                recovery:revalidate(name,recovery_proof(),recovery_time())
            end
        end
    end
    if not recovery or not recovery:blocks_view(recovery_time())then controller:update()
    elseif controller.lease then attempt(controller,'retry_cleanup')end
    editor:update()
    if fird_entry and fird_entry:uses_fp()then
        local done,why=attempt(motion,'capture_neutral',fird_capture_phase=='ads')
        if done~=true then log('Fird Person calibration: '..tostring(why))end
    else motion:update()end
    local idle=not controller:is_enabled() and not editor:is_active()
    if not idle then idle_clean=false
    elseif idle_clean and not foreign_camera() then menu:update();return end
    if foreign_camera()then
        attempt(fov,'stop');attempt(blur,'stop');attempt(camera,'stop');attempt(head,'stop');attempt(movement,'stop')
        attempt(near,'stop')
        attempt(dof,'update',controller,camera,compat)
        menu:update();return
    end
    local adjusted,why=managed_update('fov',fov,controller)
    local blur_ready,blur_problem=managed_update('blur',blur,controller)
    local camera_ready,camera_problem=managed_update('camera',camera,controller)
    local head_ready,head_problem=managed_update('head',head,controller)
    local movement_ready,movement_problem
    if editor:is_active()then movement_ready,movement_problem=attempt(movement,'stop')
    else movement_ready,movement_problem=managed_update('movement',movement,controller)end
    -- Optional: a refused near clip logs and leaves the game's distance.
    attempt(near,'update',controller)
    local dof_ready=attempt(dof,'update',controller,camera,compat)
    idle_clean=idle and adjusted==true and blur_ready==true and camera_ready==true and head_ready==true
        and movement_ready==true and dof_ready==true
        and near:is_clean()
        and(not fird_warm or fird_warm:is_clean())
        and (attempt(dof,'result') or {}).owned==false    -- dof:update returns true while still restoring
    menu:update()
end

return {
    live_lua_api = 1,
    name = 'Native ADS Camera Test', author = 'Goose',
    on_enable = function()
        assert(not controller, 'Previous native ADS cleanup has not completed')
        fp_dof_player=nil;fird_tick=0;ready_tick=0
        assert(rawget(_G, 'NativeADSCameraTest') == nil, 'NativeADSCameraTest global is already owned')
        Actions=mod.require('src/first_person/action_placement.lua')
        Actions.configure_catalogue(mod.require('src/loadout_catalogue.lua').gear)
        local Backend = mod.require('src/first_person/backend.lua')
        local Controller = mod.require('src/first_person/controller.lua')
        local Menu = mod.require('src/first_person/menu.lua')
        local Editor = mod.require('src/first_person/placement_editor.lua')
        local Fov = mod.require('src/first_person/fov.lua')
        local Blur=mod.require('src/first_person/blur.lua')
        local Dof=mod.require('src/first_person/dof.lua')
        local Camera=mod.require('src/first_person/camera.lua')
        local MotionRuntime=mod.require('src/first_person/motion_runtime.lua')
        local CameraCompat=mod.require('src/first_person/camera_compat.lua')
        local Head=mod.require('src/first_person/head_visibility.lua')
        local Movement=mod.require('src/first_person/first_person_movement.lua')
        local NearClip=mod.require('src/first_person/near_clip.lua')
        local clock=monotonic_clock()
        backend=Backend.new(log)
        -- Probe: keep the native first-person view through weapon put-away/draw.
        backend.hold_transition=true
        runtime_clock=clock
        recovery=mod.require('src/first_person/recovery.lua').new()
        diagnostics=mod.require('src/first_person/diagnostics.lua').new({capacity=720})
        presentation_module=mod.require('src/first_person/transition.lua')
        presentation=presentation_module.new({duration=.18,max_gap=.25})
        recovery_enabled=false
        backend.presentation_transition=function()if backend.frame_active==true and ready_context then return presentation:result()end end
        backend.presentation_coordinator=presentation
        backend.presentation_action=function(action)if backend.frame_active==true and ready_context then return presentation:action(action,clock())end end
        backend.presentation_resume=function(identity,player)if backend.frame_active==true and ready_context then return presentation:resume(identity,player,clock())end end
        backend.pin_first_person=false
        -- Restore pre-pin camera behavior: normal4 fallback only, native6
        -- pass-through; never publish an independent raw-look input token.
        backend.camera_update_token=nil
        controller = Controller.new(backend, log, clock)
        -- Quarantine the inline optic-selection policy after crash reports.
        -- Keep the pointer-owned camera FOV and original depth policy active.
        fov=Fov.new(backend,log,nil,clock)
        blur=Blur.new(backend,log,nil,clock)
        camera=Camera.new(backend,log,nil,clock)
        compat=CameraCompat.new(controller,log,_G)
        local function fallback_ready()
            local state=camera:result()
            return state.phase=='active' and state.armed==true and state.error==0
        end
        head=Head.new(backend,log,stingray,{fallback_ready=fallback_ready,pinned_ready=pinned_ready,
            model_shadows=mod.require('src/first_person/model_shadow_source.lua').new(backend),
            full_body=function()return fird and fird:is_enabled()or false end,
            hide_torso=function()return fird and fird:is_enabled()or false end})
        movement=Movement.new(backend,log,stingray,{fallback_ready=fallback_ready})
        dof=Dof.new(backend,log,stingray,{clock=clock,
            vignette_factory=mod.require('src/first_person/vignette.lua').new,active_view=function()
            return first_person_view(fallback_ready)
        end,fallback_ready=function()
            return fallback_ready() and head:result().phase=='active'
        end})
        near=NearClip.new(backend,log,nil,clock,function()
            if menu and menu.near_options then return menu:near_options()end
            return {hip=0,aim=0}
        end)
        handoff_ready=true
        foreign_camera=function()return not handoff_ready or compat:foreign()end
        backend.foreign_camera=foreign_camera
        local NativeAim=mod.require('src/first_person/native_ads_option.lua')
        native_aim=NativeAim.new(NativeAim.source(backend),function()
            return menu and menu:native_ads()and not(fird and fird:is_enabled())and not(fird_entry and fird_entry:is_enabled())or false
        end,foreign_camera)
        local Markers=mod.require('src/first_person/aim_markers.lua')
        aim_markers=Markers.new(backend,log,{
            settings=function()return(mod.config or {}).aim_markers end,
            save=function(value)return mod.set('aim_markers',value)end,
            global_setting=function()return(mod.config or {}).show_aim_markers end,
            save_global=function(value)return mod.set('show_aim_markers',value)end,
            current=Markers.source(backend,controller,{foreign=foreign_camera,fallback_ready=fallback_ready,pinned_ready=pinned_ready,
                global_setting=function()return(mod.config or {}).show_aim_markers end,
                fird=function()return fird end})})
        backend.camera_before_entry=function()
            local ready,why=compat:prepare();if ready~=true then return false,why end
            local clean,reason=blur:stop();if clean~=true then return false,reason end
            return camera:prepare() -- Exact pre-pin normal4 fallback; reserved0 never owns raw look.
        end
        local owned_compat=compat
        backend.placement_resolver=saved_placement
        backend.action_placement=function(key,action)return saved_placement(key,action)end
        backend.action_mapping=function()return (mod.config or {}).action_state_mapping end
        assert(controller:set_placement(saved_placement()))
        local edit_mode='weapon'
        local head_positioner=mod.require('src/first_person/head_placement.lua').new(backend,camera,
            function()return fird and fird:is_enabled()or false end,
            function()return (mod.config or {}).fird_head_camera end,
            function(value)return mod.set('fird_head_camera',value)end)
        local placement_controller={}
        for _,method in ipairs({'is_enabled','is_clean','get_placement','set_placement','result','placement_target','start'})do
            local name=method
            placement_controller[name]=function(_,...)local target=edit_mode=='camera'and head_positioner or(fird and fird:is_enabled()and fird or controller);return target[name](target,...)end
        end
        local store={get=function(...)if edit_mode=='camera'then return head_positioner:get_saved()end;return saved_placement(...)end,can_start=function()
            if fird_entry and fird_entry:is_pending()then return false,'Fird Person is switching views'end
            if edit_mode=='camera'and not(fird and fird:is_enabled())then return false,'Enable FirdPerson before editing its head camera'end
            if fird and fird:is_enabled()then
                if foreign_camera()then return false,'Another camera owns the view'end
                if fird.native_animation and edit_mode~='camera'then return false,'Natural Fird Person uses the game\'s arm and weapon placement. Shift+F8 edits the eye camera.'end
                return true
            end
            if not controller:is_enabled() and not fov:is_clean() then return false,'FOV cleanup is still pending' end
            if not controller:is_enabled() and not blur:is_clean() then return false,'Weapon blur cleanup is still pending'end
            if not controller:is_enabled() and not camera:is_clean() then return false,'Head-camera cleanup is still pending'end
            if not controller:is_enabled() and not head:is_clean() then return false,'Head visibility cleanup is still pending'end
            if not controller:is_enabled() and not movement:is_clean() then return false,'Movement cleanup is still pending'end
            if not controller:is_enabled() and not dof:is_clean()then return false,'DoF restoration is still pending'end
            if foreign_camera()then return false,'Photo Mode or another camera owns the view'end
            return true
        end,actions=Actions.actions,action_supported=function(action)
            if action=='camera'then return true end
            if action=='idle' or action=='aim' or action=='ads' or action=='sprint' or action=='reload' or Actions.observed_actions[action]then return true end
            for _,mapping in pairs((mod.config or {}).action_state_mapping or {})do
                if PORT51.kind(mapping)=='table'then for _,name in pairs(mapping)do if name==action then return true end end end
            end
            return false
        end,get_action=function(...)if edit_mode=='camera'then return head_positioner:get_saved()end;return saved_placement(...)end,target=function()return placement_controller:placement_target()end,save=function(value,key,identity,all_weapons,action)
            if edit_mode=='camera'then return head_positioner:save(value,key,identity)end
            local current=backend:snapshot()
            local target,owner=placement_controller:placement_target()
            if not key or target~=key or owner~=identity or not current or current.identity~=identity then return false,'Weapon changed; reopen placement editor' end
            if PORT51.kind(mod.set)~='function' then return false,'Placement settings storage unavailable' end
            local profiles=Actions.saved(mod.config,key,action or 'idle',value,all_weapons)
            local ok,why=mod.set('action_placements',profiles)
            if ok==true then backend.action_placement_revision=(backend.action_placement_revision or 0)+1 end
            return ok,why
        end}
        store.select_mode=function(kind)
            if kind~='weapon'and kind~='camera'then return false,'Unknown editor mode'end
            if kind=='camera'and camera.retired then return false,'Head-camera editing is unavailable because the camera policy was removed'end
            edit_mode=kind
            store.actions=kind=='camera'and{{'camera','Head camera'}}or Actions.actions
            store.title=kind=='camera'and 'HEAD CAMERA'or 'WEAPON PLACEMENT'
            store.rotation=kind~='camera'
            store.baseline=kind=='camera'and{x=0,y=0,z=.04}or function(key,action)return Actions.default_placement(mod.config,key,action)end
            store.single_save=kind=='camera'
            store.save_label=kind=='camera'and 'Save camera'or nil
            store.all_label=kind=='camera'and 'Save camera'or nil
            store.footer=kind=='camera'and 'Camera only; weapon placements are unchanged'or nil
            return true
        end
        store.reset_all=function()
            if edit_mode=='camera'then
                local key,owner=head_positioner:placement_target()
                return head_positioner:save({x=0,y=0,z=.04},key,owner)
            end
            local before={weapon_placements=mod.config.weapon_placements,action_placements=mod.config.action_placements,placement=mod.config.placement}
            local values={weapon_placements={},action_placements={},placement={x=.15,y=0,z=-.12}}
            for _,key in ipairs({'weapon_placements','action_placements','placement'})do
                local ok,why=mod.set(key,values[key])
                if not ok then for k,v in pairs(before)do mod.set(k,v)end;return false,why end
            end
            backend.action_placement_revision=(backend.action_placement_revision or 0)+1
            return true
        end
        editor=Editor.new(placement_controller,store,log,clock)
        motion=MotionRuntime.new(controller,backend,editor,log,clock,function()
            local config=mod.config or {}
            local defaults={enabled=config.motion_enabled~=false,scale=config.motion_scale or 1,camera_bob_strength=0,camera_sway_strength=0}
            if menu and menu.motion_options then return menu:motion_options(defaults)end
            return defaults
        end)
        local owned_controller = controller
        local owned_markers=aim_markers
        local owned_editor=editor
        local owned_fov=fov
        local owned_blur=blur
        local owned_camera,owned_motion,owned_head,owned_movement,owned_dof,owned_near=camera,motion,head,movement,dof,near
        local function start_pose(seconds,capture_entry)
            if not owned_markers:is_clean()then return false,'Aiming-marker restoration is pending'end
            if fird_entry and fird_entry:is_pending()and not capture_entry then return false,'Fird Person is switching views'end
            if fird and not fird:is_clean()then return false,'FirdPerson must finish cleanup first'end
            if owned_editor:is_active() then return false,'Placement editor or its cleanup is active' end
            if not owned_controller:is_clean() then return false,'A test or its cleanup is already active' end
            if not owned_fov:is_clean() then return false,'FOV cleanup is still pending' end
            if not owned_blur:is_clean() then return false,'Weapon blur cleanup is still pending'end
            if not owned_camera:is_clean() then return false,'Head-camera cleanup is still pending'end
            if not owned_head:is_clean() then return false,'Head visibility cleanup is still pending'end
            if not owned_movement:is_clean() then return false,'Movement cleanup is still pending'end
            if not owned_dof:is_clean()then return false,'DoF restoration is still pending'end
            if not owned_compat:is_clean()then return false,'Camera handoff cleanup is pending'end
            if recovery then recovery:reset();recovery_enabled=false end
            local ready,why=owned_controller:set_placement(saved_placement())
            if ready~=true then return false,why end
            local done,problem=owned_controller:start(seconds,'pose_offset')
            if done~=true then attempt(owned_camera,'stop');attempt(owned_compat,'stop');return done,problem end
            local adjusted,fov_problem=true,nil
            if not foreign_camera()then adjusted,fov_problem=managed_update('fov',owned_fov,owned_controller)end
            if adjusted==true and not foreign_camera()then adjusted,fov_problem=managed_update('blur',owned_blur,owned_controller)end
            if adjusted~=true then
                attempt(owned_controller,'stop','FOV policy unavailable')
                attempt(owned_fov,'stop')
                attempt(owned_blur,'stop')
                attempt(owned_camera,'stop')
                attempt(owned_compat,'stop')
                return false,fov_problem
            end
            return done and owned_controller:is_enabled(),problem
        end
        local probe_deadline
        local function stop_pose(keep_handoff)
            if recovery then recovery:reset();recovery_enabled=false end
            if presentation then presentation:reset('manual stop')end
            if not keep_handoff then probe_deadline=nil end
            if not keep_handoff and fird_entry then fird_entry:cancel()end
            fird_capture_phase=nil
            fp_dof_player=nil
            local fire_done,fire_problem=true,nil
            if held_fire then fire_done,fire_problem=attempt(held_fire,'stop')end
            local native_aim_done,native_aim_problem=true,nil
            if native_aim then native_aim_done,native_aim_problem=attempt(native_aim,'stop')end
            local markers_done,markers_problem=attempt(owned_markers,'stop')
            local fird_done,fird_problem=true,nil
            if fird then fird_done,fird_problem=attempt(fird,'stop')end
            local warm_done,warm_problem=true,nil
            if fird_warm then warm_done,warm_problem=attempt(fird_warm,'stop')end
            local editor_done,editor_problem=true,nil
            if owned_editor:is_active() then editor_done,editor_problem=attempt(owned_editor,'cancel','FPV switched off') end
            local done,why=attempt(owned_controller,'stop','manual stop')
            local fov_done,fov_problem=attempt(owned_fov,'stop')
            local blur_done,blur_problem=attempt(owned_blur,'stop')
            local camera_done,camera_problem=attempt(owned_camera,'stop')
            local head_done,head_problem=attempt(owned_head,'stop')
            local movement_done,movement_problem=attempt(owned_movement,'stop')
            local dof_done,dof_problem=attempt(owned_dof,'stop')
            local compat_done,compat_problem=attempt(owned_compat,'stop')
            local near_done,near_problem=attempt(owned_near,'stop')
            attempt(owned_motion,'reset')
            if fire_done~=true then return false,fire_problem end
            if native_aim_done~=true then return false,native_aim_problem end
            if markers_done~=true then return false,markers_problem end
            if fird_done~=true then return false,fird_problem end
            if warm_done~=true then return false,warm_problem end
            if done~=true then return false,why end
            if editor_done~=true then return false,editor_problem end
            if fov_done~=true then return false,fov_problem end
            if blur_done~=true then return false,blur_problem end
            if camera_done~=true then return false,camera_problem end
            if head_done~=true then return false,head_problem end
            if movement_done~=true then return false,movement_problem end
            if dof_done~=true then return false,dof_problem end
            if near_done~=true then return false,near_problem end
            if compat_done~=true then return false,compat_problem end
            return true
        end
        local start_fird
        local function toggle_pose()
            if owned_controller:is_enabled() or (fird and not fird:is_clean())or(fird_entry and fird_entry:is_enabled())then return stop_pose() end
            return start_pose(0)
        end
        local function start_native(seconds)
            if not owned_markers:is_clean()then return false,'Aiming-marker restoration is pending'end
            if fird_entry and fird_entry:is_pending()then return false,'Fird Person is switching views'end
            if owned_editor:is_active() then return false,'Placement editor or its cleanup is active' end
            if not owned_fov:is_clean() then return false,'FOV cleanup is still pending' end
            if not owned_blur:is_clean() then return false,'Weapon blur cleanup is still pending'end
            if not owned_camera:is_clean() then return false,'Head-camera cleanup is still pending'end
            if not owned_head:is_clean() then return false,'Head visibility cleanup is still pending'end
            if not owned_movement:is_clean() then return false,'Movement cleanup is still pending'end
            if not owned_dof:is_clean()then return false,'DoF restoration is still pending'end
            if not owned_compat:is_clean()then return false,'Camera handoff cleanup is pending'end
            if foreign_camera()then return false,'Photo Mode or another camera owns the view'end
            return owned_controller:start(seconds,'native')
        end
        local function start_free_aim()
            if owned_camera.retired then return false,'Free aim is unavailable because the camera policy was removed'end
            if owned_editor:is_active()then return false,'Close the placement editor first'end
            if fird and not fird:is_clean()then return false,'FirdPerson must be off'end
            if foreign_camera()then return false,'Return to normal gameplay first'end
            if not owned_controller:is_enabled()then return false,'Enable native FPV with F11 first'end
            owned_camera:observe_parent()
            return owned_camera:free_aim(30000)
        end
        start_fird=function()
            if owned_camera.retired then return false,'Fird Person is unavailable because the camera policy was removed'end
            if stopping then return false,'Mod is stopping'end
            if owned_editor:is_active()then return false,'Close the placement editor before Fird Person'end
            if fird_entry and fird_entry:is_enabled()then return true end
            local module=mod.require('src/first_person/fird_person.lua')
            local natural=module.native_animation_default==true
            if not natural and not module.render_pose_verified then return false,'Fird Person render placement is unavailable'end
            local ready=natural and ensure_ready_pose()or nil
            fird=fird or module.new(backend,stingray,camera,head,movement,dof,compat,foreign_camera,log,{
                native_animation=natural,render_driven=not natural,
                ready_pose=ready,fire_filter=natural and held_fire or nil,
                camera_frame=not natural and mod.require('src/first_person/fird_camera_pose.lua')or nil,
                skin=not natural and mod.require('src/first_person/skinned_placement.lua')or nil,
                support=not natural and mod.require('src/first_person/support_hand.lua')or nil,profiles=Actions,clock=clock,
                source=not natural and mod.require('src/first_person/fird_source_pose.lua')or nil,
                retarget=not natural and mod.require('src/first_person/fird_retarget.lua')or nil,
                children=not natural and mod.require('src/first_person/fird_weapon_children.lua')or nil,
                aim=not natural and mod.require('src/first_person/fird_aim.lua').new()or nil,
                aim_mode=function()return menu and menu:ads_mode()or'fird'end,
                native_ads=mod.require('src/first_person/fird_native_ads.lua').new(backend,log,{
                    foreign=foreign_camera,prepare=function(s)return fird:prepare_native_ads(s)end}),
                fov=mod.require('src/first_person/fird_fov.lua').new(backend,log,nil,clock),editor=function()return editor end})
            if natural then
                if fird:is_enabled()then return true end
                local done,why=stop_pose();if done~=true then return false,why end
                local called,ready,problem=pcall(fird.start_native,fird)
                if not called then attempt(fird,'stop');return false,tostring(ready)end
                if ready~=true then attempt(fird,'stop')end
                return ready,problem
            end
            fird_render=fird_render or mod.require('src/first_person/fird_render.lua').new(_G,render_fird_pose,log,{
                active=function()return not stopping and fird and fird:is_enabled()and backend and not backend.frame_active or false end,
                foreign=foreign_camera})
            local rendering,render_problem=fird_render:start()
            if rendering~=true then return false,render_problem end
            if not fird_entry then
                local Ready=mod.require('src/first_person/fird_capture_ready.lua')
                if PORT51.kind(backend.camera_ready)=='function'then
                    fird_warm=mod.require('src/first_person/fird_warm.lua').new(backend,clock,foreign_camera,function()return fird_tick end)
                end
                local gate=Ready.new(clock);local candidate,candidate_time,hip_capture
                local function sample_capture()
                    local done,why=owned_fov:update(owned_controller)
                    assert(done==true,why or'First-person FOV owner is unavailable')
                    done,why=owned_camera:update(owned_controller)
                    assert(done==true,why or'First-person camera owner is unavailable')
                    local snapshot=backend:snapshot();local target=fird:reference_status()
                    local lease=owned_controller.lease
                    local pose=lease and backend:pose_status(lease)or nil
                    local actual=Ready.scene_lens(backend,snapshot)
                    local ready,token=gate:update({snapshot=snapshot,target=target,lease=lease,
                        controller=owned_controller:result(),pose=pose,fov=owned_fov:result(),
                        camera=owned_camera:result(),motion=owned_motion:result(),
                        lens=actual,neutral=target.neutral,tick=fird_tick})
                    if not ready then candidate,candidate_time=nil,nil;return false,token end
                    local capture=module.capture(backend,stingray,mod.require('src/first_person/support_hand.lua'),token)
                    local now=clock();local stable=candidate and candidate.weapon_identity==capture.weapon_identity
                        and candidate.identity==capture.identity and candidate.weapon_key==capture.weapon_key
                        and math.abs(candidate.source_fov-capture.source_fov)<=.0001
                    if stable then
                        local distance,dot=0,0
                        for i=1,3 do distance=distance+(candidate.projection.position[i]-capture.projection.position[i])^2 end
                        for i=1,4 do dot=dot+candidate.projection.rotation[i]*capture.projection.rotation[i]end
                        stable=distance<=.02^2 and math.abs(dot)>=math.cos(math.rad(2)/2)
                    end
                    if not stable then candidate,candidate_time=capture,now;return false,'Waiting for the weapon draw animation to settle'end
                    if now-candidate_time<.05 then return false,'Waiting for the next settled weapon pose'end
                    if fird_capture_phase~='ads'then
                        hip_capture=capture;fird_capture_phase='ads'
                        gate:reset();candidate,candidate_time=nil,nil
                        return false,'Capturing native sight alignment'
                    end
                    assert(hip_capture and hip_capture.weapon_identity==capture.weapon_identity
                        and hip_capture.identity==capture.identity and hip_capture.weapon_key==capture.weapon_key,
                        'Weapon changed between hip and ADS calibration')
                    hip_capture.aim={projection=capture.projection,source_fov=capture.source_fov,
                        reference=capture.reference,pivot=capture.pivot,method='native_zero_offset_capture'}
                    token.capture=hip_capture;return true,token
                end
                fird_entry=mod.require('src/first_person/fird_auto.lua').new({
                    foreign=foreign_camera,running=function()return fird:is_enabled()end,
                    target=function()return fird:reference_status()end,
                    stop=function()return stop_pose(true)end,
                    cached=function()return fird:cached_capture()end,
                    initialize=fird_warm and function(s)return fird_warm:update(s)end or nil,
                    begin_fp=function()
                        gate:reset();candidate,candidate_time,hip_capture=nil,nil,nil;fird_capture_phase='hip'
                        local done,why=start_pose(0,true)
                        if done~=true then return done,why end
                        if not owned_controller.lease then return false,'This weapon has no native first-person placement to capture'end
                        return true
                    end,
                    sample=sample_capture,
                    capture=function(token)return assert(token.capture,'Settled first-person reference unavailable')end,
                    enter=function(reference)
                        if foreign_camera()then return false,'Another camera owns the view'end
                        backend.fird_camera_offset=head_positioner:get_saved()
                        local called,done,reason=pcall(fird.start,fird,reference)
                        if not called or done~=true then fird:stop();return false,tostring(called and reason or done)end
                        return true
                    end,
                },clock)
            end
            return fird_entry:request()
        end
        local function view_enabled()
            return owned_controller:is_enabled()or(fird and fird:is_enabled())or(fird_entry and fird_entry:is_enabled())or false
        end
        local function view_clean()
            return owned_controller:is_clean()and owned_markers:is_clean()and(not native_aim or native_aim:is_clean())and(not fird or fird:is_clean())
                and(not fird_warm or fird_warm:is_clean())and(not fird_entry or not fird_entry:is_pending())
        end
        local function start_true_first_person()return start_pose(0)end
        probe_update=function()
            if probe_deadline and clock()>=probe_deadline then
                probe_deadline=nil;stop_pose()
            end
        end
        menu = Menu.new(controller, log, editor, {start_pose=start_true_first_person,toggle_pose=toggle_pose,stop=stop_pose,
            start_native=start_native,start_free_aim=start_free_aim,
            -- start_fird=start_fird, -- Fird Person menu entry is parked.
            start_true_first_person=start_true_first_person,
            is_enabled=view_enabled,is_clean=view_clean,
            presentation_settings=function()return mod.config end,
            current_weapon=function()
                local key,identity=owned_controller:placement_target()
                if not key then return nil end
                local info=Actions.weapon_info(key)or{}
                return {key=key,identity=identity,label=info.name,family=info.family}
            end,
            save_presentation=function(name,value,expected_key,expected_identity)
                if name~='family_placement_defaults'and name~='near_clip_profiles'then return false,'Unknown presentation setting'end
                if name=='family_placement_defaults'and PORT51.kind(value)~='boolean'then return false,'Placement defaults must be on or off'end
                if name=='near_clip_profiles'and PORT51.kind(value)~='table'then return false,'Clipping profiles must be a table'end
                if expected_key then
                    local key,identity=owned_controller:placement_target()
                    local fresh=attempt(backend,'snapshot')
                    if key~=expected_key or identity~=expected_identity or not fresh or fresh.identity~=expected_identity or not fresh.safe then
                        return false,'Weapon changed; reopen its presentation settings'
                    end
                end
                local done,why=mod.set(name,value)
                if done==true and name=='family_placement_defaults'then backend.action_placement_revision=(backend.action_placement_revision or 0)+1 end
                return done,why
            end,
            aiming_markers=function()return owned_markers:target()end,
            toggle_aiming_markers=function(key,identity)return owned_markers:toggle(key,identity)end,
            aim_markers_setting=function()return owned_markers:setting()end,
            set_aim_markers_setting=function(value)return owned_markers:set_setting(value)end,
            -- fird_active=function()return(fird and fird:is_enabled())or(fird_entry and fird_entry:is_pending())or false end,
            dev_status=function()
                if recovery then
                    local blocked,name,phase=recovery:blocks_view(clock())
                    if blocked then return 'First person suspended: '..name..' ('..phase..')'end
                end
                if owned_markers.fault then return 'Aiming markers: '..owned_markers.fault end
                -- Fird status is hidden with its parked menu options.
                -- if fird_entry and fird_entry:is_pending()then return fird_entry:status()end
                -- return fird and not fird:is_clean()and fird:status()or nil
            end})
        api = {
            seamless_version='0.5.41-smooth.4-cffi-26568081',
            hold_transition=function(on)
                if on~=nil then backend.hold_transition=on==true end
                return backend.hold_transition==true,backend.holds
            end,
            presentation_state=function()return presentation and presentation:result()or nil end,
            diagnostics=function()return diagnostics and diagnostics:snapshot()or{}end,
            recovery_status=function()return recovery and recovery:snapshot()or{}end,
            clear_diagnostics=function()if diagnostics then diagnostics:clear()end;return true end,
            start = start_pose,
            start_true_first_person=start_true_first_person,
            start_fird=start_fird,
            probe_fird=function(seconds)
                if PORT51.kind(seconds)~='number'or seconds~=seconds or seconds<1 or seconds>10 then
                    return false,'Fird probe duration must be from1to10seconds'
                end
                if view_enabled()or not view_clean()then return false,'Turn the active view off before a bounded probe'end
                local done,why=start_fird()
                if done==true then probe_deadline=clock()+seconds end
                return done,why
            end,
            start_free_aim=start_free_aim,
            observe_camera_parent=function()return owned_camera:observe_parent()end,
            profile_camera=function()return owned_camera:profile()end,
            camera_profile=function()return owned_camera:profile_stats()end,
            camera_kick_stats=function()return owned_camera:kick_stats()end,
            camera_parent_stats=function()return owned_camera:parent_stats()end,
            stop_free_aim=function()return owned_camera:free_aim(0)end,
            free_aim_stats=function()return owned_camera:free_aim_stats()end,
            start_camera_only = start_pose,
            start_pose = start_pose,
            toggle = toggle_pose,
            start_native = start_native,
            edit_placement = function() return owned_editor:request_open() end,
            placement = function() return placement_controller:get_placement() end,
            stop = stop_pose,
            depth_stats = function()
                local lease=owned_controller.lease
                local alignment=lease and lease.alignment
                local helper=alignment and alignment.helper
                if not helper or alignment.kind~='pose' or PORT51.kind(helper.depth_stats)~='function' then
                    return nil,'No active depth-compensation lease'
                end
                local called,value,why=pcall(helper.depth_stats,helper,alignment.handle)
                if not called then return nil,tostring(value)end
                return value,why
            end,
            input_stats = function()
                local lease=owned_controller.lease
                local alignment=lease and lease.alignment
                local helper=alignment and alignment.helper
                if not helper or alignment.kind~='pose' or PORT51.kind(helper.input_stats)~='function' then
                    return nil,'No active first-person input lease'
                end
                local called,value,why=pcall(helper.input_stats,helper,alignment.handle)
                if not called then return nil,tostring(value)end
                return value,why
            end,
            status = function()
                local result=owned_controller:result()
                result.fird=fird and {phase=fird.phase,enabled=fird.enabled,writes=fird.writes,weapon=fird.weapon_key,
                    reference_needed=fird.reference_needed==true,scene_fov=fird.scene_fov,render_frames=fird.render_frames}or nil
                result.fird_renderer=fird_render and fird_render:result()or nil
                if fird_entry and fird_entry:is_pending()then result.fird={phase=fird_entry:status(),enabled=true,pending=true}end
                result.enabled=view_enabled()
                result.editor_active=owned_editor:is_active();result.editor_status=owned_editor:status()
                result.fov=owned_fov:result()
                result.blur=owned_blur:result()
                result.camera=owned_camera:result();result.motion=owned_motion:result()
                result.compat=owned_compat:result()
                result.head=owned_head:result()
                result.movement=owned_movement:result()
                result.dof=owned_dof:result()
                result.native_aim=native_aim and native_aim:result()
                result.near=owned_near:result()
                result.aim_markers=owned_markers:result()
                result.ready_pose=ready_pose and ready_pose:result()or nil
                result.held_fire=held_fire and held_fire:result()or nil
                return owned_controller:status()..'; FOV '..owned_fov:status()..'; camera '..owned_camera:status()..'; blur '..owned_blur:status()..'; DoF '..owned_dof:status()..'; near '..owned_near:status(),result
            end,
            preflight = function()
                if not owned_controller:is_clean() or owned_editor:is_active() then return false,'A test/editor is active' end
                if not owned_fov:is_clean() then return false,'FOV cleanup is still pending' end
                if not owned_blur:is_clean() then return false,'Weapon blur cleanup is still pending'end
                if not owned_camera:is_clean() then return false,'Head-camera cleanup is still pending'end
                if not owned_head:is_clean() then return false,'Head visibility cleanup is still pending'end
                if not owned_movement:is_clean() then return false,'Movement cleanup is still pending'end
                if not owned_dof:is_clean()then return false,'DoF restoration is still pending'end
                if not owned_compat:is_clean()then return false,'Camera handoff cleanup is pending'end
                if foreign_camera()then return false,'Photo Mode or another camera owns the view'end
                local snapshot,why=backend:snapshot()
                if not snapshot then return false,why end
                local ready,reason=backend:prepare_pose(snapshot)
                if ready~=true then return ready,reason end
                local fov_ready,fov_reason=owned_fov:preflight()
                if fov_ready~=true then return fov_ready,fov_reason end
                local blur_ready,blur_reason=owned_blur:preflight()
                if blur_ready~=true then return blur_ready,blur_reason end
                local camera_ready,camera_reason=owned_camera:preflight()
                return camera_ready,camera_ready and 'Ready; pose, FOV and pre-pin head-camera preparation passed' or camera_reason
            end,
        }
        rawset(_G, 'NativeADSCameraTest', api)
        stopping = false
        menu:update()
        log('Idle. F11 toggles True First Person; F8 edits arms and weapon placement.')
    end,
    on_update = function()
        if not controller or stopping then return end
        return qualified_frame(function()
            local ok,why=pcall(update_frame)
            if not ok then
                if held_fire then attempt(held_fire,'stop')end
                if ready_pose then attempt(ready_pose,'stop')end
            end
            -- The ready ledger drains after every path, including native ADS,
            -- foreign cameras and early returns while the eye camera stops.
            ready_update()
            if aim_markers then attempt(aim_markers,ok and not owner_draining and 'update'or 'stop')end
            local recorded,record_error=pcall(record_presentation,ok,why)
            if not recorded then
                local why=tostring(record_error)
                if why~=diagnostics_fault then diagnostics_fault=why;log('Presentation diagnostics unavailable: '..why)end
            else diagnostics_fault=nil end
            if not ok then error(why,0)end
            return true
        end)
    end,
    on_disable = shutdown,
    on_cleanup_poll = function()return qualified_frame(shutdown)end,
}
