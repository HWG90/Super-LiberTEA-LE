local PORT51=mod.require('src/first_person/compat51.lua')
-- Sample and apply presentation motion without changing saved placement or
-- controlling the camera's lifecycle. Missing motion data is a neutral fallback.
local Host=mod
local Runtime={}
local function finite(n)return PORT51.kind(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function invoke(target,name,...)
    local ok,a,b=pcall(target[name],target,...)
    if not ok then return nil,tostring(a)end
    return a,b
end
local function vector(value)
    if PORT51.kind(value)~='table'then return false end
    for _,axis in ipairs({'dx','dy','dz'})do
        if not finite(value[axis]) or math.abs(value[axis])>.15 then return false end
    end
    local length=0
    for _,axis in ipairs({'qx','qy','qz','qw'})do
        if not finite(value[axis])then return false end
        length=length+value[axis]^2
    end
    if math.abs(length-1)>.0001 or value.qw<math.cos(math.rad(120)/2)then return false end
    return true
end
function Runtime.new(controller,backend,editor,log,clock,options,dependencies)
    assert(PORT51.kind(controller)=='table' and PORT51.kind(backend)=='table' and PORT51.kind(clock)=='function','Motion runtime dependencies required')
    dependencies=dependencies or {}
    local function module(name)
        assert(PORT51.kind(Host)=='table' and PORT51.kind(Host.require)=='function','Motion module loader unavailable')
        return Host.require(name)
    end
    local model=dependencies.motion or module('src/first_person/motion.lua').new()
    local locomotion
    if not dependencies.sampler or not dependencies.to_parent then locomotion=module('src/first_person/locomotion.lua')end
    local sampler=dependencies.sampler or locomotion.new(backend)
    local to_parent=dependencies.to_parent or locomotion.to_parent
    log=log or function()end
    local self={}
    local profile_lease,profile_revision,profile_action,profile_target,profile_value,action_policy
    local profile_epoch,profile_used,continuity
    local last_lease,last_time,last_options,last_message
    local sent_lease,sent,sent_phase,sent_ads,sent_authored=nil,{},nil,nil,nil
    local handoff,previous_ads
    local handoff_seconds=.15
    local axes={'dx','dy','dz','qx','qy','qz','qw'}
    local motion_keys={'enabled','scale','bob_strength','bob_speed','sway_strength','sway_speed','sprint_strength','camera_bob_strength','camera_bob_speed','camera_sway_strength','camera_sway_speed'}
    local camera=dependencies.camera
    local camera_zero={dx=0,dy=0,dz=0,pitch=0,yaw=0,roll=0}
    local state={phase='idle',applied=0,coalesced=0,read_failures=0,write_refusals=0,time_held=0,
        dx=0,dy=0,dz=0,qx=0,qy=0,qz=0,qw=1}
    local function report(reason)
        state.reason=reason
        if reason and reason~=last_message then log('FPV motion: '..tostring(reason))end
        last_message=reason
    end
    local function clear(keep_continuity)
        if not keep_continuity then continuity=nil end
        profile_epoch,profile_used=nil,nil
        if camera and(last_lease or state.phase~='idle')then invoke(camera,'set_motion',camera_zero)end
        profile_lease,profile_revision,profile_action,profile_target,profile_value=nil,nil,nil,nil,nil
        invoke(model,'reset');last_lease,last_time=nil,nil
        sent_lease,sent_phase,sent_ads,sent_authored=nil,nil,nil,nil
        handoff,previous_ads=nil,nil
        state.dx,state.dy,state.dz=0,0,0
        state.qx,state.qy,state.qz,state.qw=0,0,0,1
        state.sprint_weight,state.bob_weight,state.sprint_target,state.sprint_held,state.shoulder_weight=0,0,false,false,0
    end
    local function apply(lease,value,phase,reason)
        local ads=state.ads==true or(PORT51.kind(state.ads)=='number'and state.ads>=1)
        local authored=value.authored_ads==true
        local unchanged=sent_lease==lease and sent_phase==phase and sent_ads==ads and sent_authored==authored
        if unchanged then for _,axis in ipairs(axes)do if sent[axis]~=value[axis]then unchanged=false;break end end end
        if unchanged then
            state.coalesced=state.coalesced+1;state.phase=phase;report(reason);return true,reason
        end
        local accepted,why=invoke(backend,'set_pose_motion',lease,value)
        if accepted~=true then
            state.write_refusals=state.write_refusals+1;state.phase='unavailable'
            clear();report(why or 'Owned native pose did not accept motion')
            return true,state.reason
        end
        state.applied=state.applied+1;state.phase=phase
        for _,axis in ipairs(axes)do sent[axis]=value[axis]end
        sent_lease,sent_phase,sent_ads,sent_authored=lease,phase,ads,authored
        state.dx,state.dy,state.dz=value.dx,value.dy,value.dz
        state.qx,state.qy,state.qz,state.qw=value.qx,value.qy,value.qz,value.qw
        report(reason);return true,reason
    end
    local function shared_phase()
        if PORT51.kind(backend.presentation_transition)~='function'then return nil end
        local ok,value=pcall(backend.presentation_transition)
        if not ok or PORT51.kind(value)~='table'or not finite(value.progress)or value.progress<0 or value.progress>1 then return nil end
        return value
    end
    local function phase_step(packet)
        if profile_epoch~=packet.epoch then profile_epoch,profile_used=packet.epoch,0 end
        local e=packet.progress*packet.progress*(3-2*packet.progress)
        local step=packet.progress==1 and 1 or math.max(0,math.min(1,(e-profile_used)/math.max(.000001,1-profile_used)))
        profile_used=e;return step
    end
    -- Interpolate only our parent-local presentation additions. The engine's
    -- current arms/weapon animation is still consumed fresh by the native rig.
    local function handoff_parent(lease,value,ads,timestamp)
        local packet=shared_phase()
        local shared=packet and packet.ads==ads
        if (shared and (not handoff or handoff.epoch~=packet.epoch))or (previous_ads~=nil and previous_ads~=ads) or (previous_ads==nil and (ads or lease.pose_blend_entry)) then
            local from={dx=0,dy=0,dz=0,qx=0,qy=0,qz=0,qw=1}
            if sent_lease==lease then for _,axis in ipairs(axes)do from[axis]=sent[axis]end end
            handoff={from=from,at=timestamp,epoch=shared and packet.epoch or nil}
        end
        previous_ads=ads
        local mix=1
        if handoff then
            local t=shared and packet.progress or math.max(0,math.min(1,(timestamp-handoff.at)/handoff_seconds))
            mix=t*t*(3-2*t)
            local from=handoff.from
            if mix==0 then
                for _,axis in ipairs(axes)do value[axis]=from[axis]end
            elseif mix<1 then
                for _,axis in ipairs({'dx','dy','dz'})do value[axis]=from[axis]+(value[axis]-from[axis])*mix end
                -- Normalized interpolation keeps intermediate deltas within
                -- the validated 120-degree bound and never touches bones.
                local length=0
                for _,axis in ipairs({'qx','qy','qz','qw'})do
                    value[axis]=from[axis]+(value[axis]-from[axis])*mix
                    length=length+value[axis]^2
                end
                length=math.sqrt(length)
                for _,axis in ipairs({'qx','qy','qz','qw'})do value[axis]=value[axis]/length end
            end
            if t==1 then handoff=nil end
        end
        if ads and handoff and (value.qx~=0 or value.qy~=0 or value.qz~=0 or value.qw~=1)then value.authored_ads=true end
        state.ads_handoff=mix
        return value
    end
    local function neutral(lease,phase,reason)
        handoff,previous_ads=nil,nil
        if camera then invoke(camera,'set_motion',camera_zero)end
        if reason or state.phase~=phase then sent_lease=nil end
        invoke(model,'reset');last_time=nil
        state.dx,state.dy,state.dz=0,0,0
        state.sprint_weight,state.bob_weight,state.sprint_target,state.sprint_held,state.shoulder_weight=0,0,false,false,0
        return apply(lease,{dx=0,dy=0,dz=0,qx=0,qy=0,qz=0,qw=1},phase,reason)
    end
    function self:reset()
        clear();state.phase='idle';report(nil)
        return true
    end
    function self:result()
        local result={};for key,value in pairs(state)do result[key]=value end
        return result
    end
    -- Automatic calibration keeps the saved idle transform, without sampling
    -- presentation bob, sway, sprint offsets, or a previous action blend.
    function self:capture_neutral(native_ads)
        state.capture_ready=false
        local lease=controller.lease
        local result=controller:result()
        if not controller:is_enabled()or result.mode~='pose_offset'or result.phase~='running'
            or not lease or lease~=backend.alignment_lease or lease.done or lease.cleanup_only then
            return true
        end
        local sample,why=invoke(sampler,'sample',lease)
        if PORT51.kind(sample)~='table'then return false,why or'Capture motion sample unavailable'end
        local placement=backend.action_placement and backend.action_placement(backend.placement_weapon_key,'idle')
            or controller:get_placement()
        if native_ads then placement={x=0,y=0,z=0,yaw=0,pitch=0,roll=0}end
        local accepted,problem=invoke(controller,'set_placement',placement)
        if accepted~=true then return false,problem or'Capture idle placement unavailable'end
        clear();state.ads=false;state.action='idle'
        local output={dx=0,dy=0,dz=0,yaw=math.rad(placement.yaw or 0),
            pitch=math.rad(placement.pitch or 0),roll=math.rad(placement.roll or 0)}
        local ok,parent=pcall(to_parent,output,sample.camera_basis,sample.parent_basis)
        if not ok or not vector(parent)then return false,'Capture rotation basis unavailable'end
        if camera then
            accepted,problem=invoke(camera,'set_motion',camera_zero)
            if accepted~=true then return false,problem or'Capture camera motion unavailable'end
        end
        local done,reason=apply(lease,parent,'capture')
        state.capture_ready=done==true and state.phase=='capture'
        state.capture_native_ads=native_ads==true
        return state.capture_ready,reason
    end
    function self:update()
        local resumed_modifier=false
        state.capture_ready=false
        local result,why=invoke(controller,'result')
        local enabled=invoke(controller,'is_enabled')
        local lease=controller.lease
        if not enabled or PORT51.kind(result)~='table' or result.mode~='pose_offset' or result.phase~='running'
            or not lease or lease~=backend.alignment_lease or lease.done or lease.cleanup_only then
            local ok,timestamp=pcall(clock)
            if enabled and PORT51.kind(result)=='table'and result.mode=='pose_offset'and ok and finite(timestamp)then
                if last_lease and last_lease.origin and sent_lease==last_lease then
                    local origin=last_lease.origin
                    if PORT51.kind(origin.identity)=='string'and PORT51.kind(origin.player_identity)=='string'then
                        local value={};for _,axis in ipairs(axes)do value[axis]=sent[axis]end
                        continuity={identity=origin.identity,player_identity=origin.player_identity,at=timestamp,value=value,ads=previous_ads}
                    end
                end
                if continuity and(timestamp<continuity.at or timestamp-continuity.at>.25)then continuity=nil end
            else continuity=nil end
            clear(continuity~=nil);state.phase='idle';report(nil);return true
        end
        if last_lease~=lease then
            local carried=continuity;local ok,timestamp=pcall(clock)
            local origin=lease.origin
            local keep=carried and ok and finite(timestamp)and timestamp>=carried.at and timestamp-carried.at<=.25
                and PORT51.kind(origin)=='table'and origin.identity==carried.identity and origin.player_identity==carried.player_identity
            clear();last_lease=lease
            if keep then
                resumed_modifier=true
                for _,axis in ipairs(axes)do sent[axis]=carried.value[axis]end
                sent_lease=lease;previous_ads=carried.ads
                handoff={from=carried.value,at=timestamp}
                if PORT51.kind(backend.presentation_resume)=='function'then pcall(backend.presentation_resume,origin.identity,origin.player_identity,timestamp)end
            end
        end
        local current_options={enabled=true,scale=1}
        if PORT51.kind(options)=='function'then
            local ok,value=pcall(options)
            if not ok or PORT51.kind(value)~='table'then return neutral(lease,'neutral','Motion options unavailable')end
            current_options=value
        elseif PORT51.kind(options)=='table'then current_options=options end
        local on=current_options.enabled~=false
        local scale=current_options.scale==nil and 1 or current_options.scale
        if not finite(scale) or scale<0 or scale>2 then return neutral(lease,'neutral','Motion scale is invalid')end
        local options_changed=not last_options
        if not options_changed then for _,key in ipairs(motion_keys)do if last_options[key]~=current_options[key]then options_changed=true;break end end end
        if options_changed then
            local accepted,problem=invoke(model,'configure',current_options)
            if accepted~=true then return neutral(lease,'neutral',problem or 'Motion options were refused')end
            last_options={};for _,key in ipairs(motion_keys)do last_options[key]=current_options[key]end;last_time=nil
            sent_lease=nil
        end
        local editing=false
        if editor then
            local value,problem=invoke(editor,'is_active')
            if value==nil then return neutral(lease,'neutral',problem or 'Placement editor state unavailable')end
            editing=value==true
        end
        if editing then
            profile_lease=nil
            local preview=editor.preview_rotation and editor:preview_rotation()
            if not preview or (preview.yaw or 0)==0 and (preview.pitch or 0)==0 and (preview.roll or 0)==0 then return neutral(lease,'editor_frozen')end
            local sample,why=invoke(sampler,'sample',lease)
            if not sample then return neutral(lease,'editor_frozen',why)end
            local ok,parent=pcall(to_parent,{dx=0,dy=0,dz=0,yaw=math.rad(preview.yaw or 0),pitch=math.rad(preview.pitch or 0),roll=math.rad(preview.roll or 0)},sample.camera_basis,sample.parent_basis)
            if not ok or not vector(parent)then return neutral(lease,'editor_frozen','Rotation preview basis unavailable')end
            return apply(lease,parent,'editor_frozen')
        end
        if not backend.action_placement and(not on or scale==0)and(state.shoulder_weight or 0)==0 then
            -- This is the backend's fresh current-frame snapshot, never an
            -- inter-frame player cache. With no aiming stance to blend, avoid
            -- graph sampling and repeated zero writes while sway is disabled.
            local hint=invoke(backend,'player_snapshot')
            if PORT51.kind(hint)=='table' and PORT51.kind(hint.shoulder_aim)=='boolean' and PORT51.kind(hint.controller_active)=='boolean'then
                state.ads,state.shoulder_aim=hint.controller_active,hint.shoulder_aim
                if not hint.controller_active and not hint.shoulder_aim and not previous_ads and not handoff then
                    return neutral(lease,'disabled')
                end
            end
        end
        local ok,timestamp=pcall(clock)
        if not ok or not finite(timestamp)then return neutral(lease,'neutral','Motion clock unavailable')end
        if last_time and timestamp<last_time then return neutral(lease,'neutral','Motion clock moved backwards')end
        local sample,problem=invoke(sampler,'sample',lease)
        if PORT51.kind(sample)~='table'then
            state.read_failures=state.read_failures+1
            return neutral(lease,'neutral',problem or 'Motion sample unavailable')
        end
        local dt=last_time and timestamp-last_time or 1/60
        if backend.action_placement then
            action_policy=action_policy or dependencies.actions or module('src/first_person/action_placement.lua')
            local action=action_policy.select(sample,backend.action_mapping and backend.action_mapping())
            if PORT51.kind(backend.presentation_action)=='function'then pcall(backend.presentation_action,action,timestamp)end
            state.action=action
            local revision=backend.action_placement_revision or 0
            if profile_lease~=lease or profile_revision~=revision then
                local ads=backend.action_placement(backend.placement_weapon_key,'ads')
                local accepted,why=invoke(backend,'set_ads_placement',lease,ads)
                if accepted~=true then return neutral(lease,'neutral',why)end
                profile_action=nil
            end
            if profile_lease~=lease or profile_revision~=revision or profile_action~=action then
                profile_target=action=='ads' and controller:get_placement()
                    or backend.action_placement(backend.placement_weapon_key,action)
                if action=='ads'then
                    -- Keep the placement we reached before ADS. Retargeting to
                    -- idle here reverses the weapon just as native ADS takes over.
                    local ads=backend.action_placement(backend.placement_weapon_key,'ads')
                    profile_target.yaw,profile_target.pitch,profile_target.roll=ads.yaw or 0,ads.pitch or 0,ads.roll or 0
                end
                profile_value=controller:get_placement()
                profile_lease,profile_revision,profile_action=lease,revision,action
            end
            local next_value={};local changed=false
            local packet=shared_phase()
            local blend=packet and phase_step(packet)or(1-math.exp(-math.max(0,math.min(dt,.1))/.10))
            for _,axis in ipairs({'x','y','z','yaw','pitch','roll'})do
                local before=profile_value[axis]or 0;local target=profile_target[axis]or 0
                local angular=axis=='yaw' or axis=='pitch' or axis=='roll'
                local value=(action=='ads' and angular) and target
                    or(math.abs(before-target)<.0001 and target or before+(target-before)*blend)
                next_value[axis]=value;if before~=value then changed=true end
            end
            if changed then
                local accepted,why=invoke(controller,'set_placement',next_value)
                if accepted~=true then return neutral(lease,'neutral',why)end
                profile_value=next_value
            end
        end
        state.sprint_raw,state.l1,state.l3,state.l14=sample.sprint==true,sample.l1,sample.l3,sample.l14
        state.ads,state.shoulder_aim=sample.ads,sample.shoulder_aim
        state.sprint_evidence=sample.sprint_evidence
        local ads=sample.ads==true or(PORT51.kind(sample.ads)=='number'and sample.ads>=1)
        local output,math_problem
        if dt==0 then
            -- A held clock never advances motion history. A new ADS edge still
            -- starts from the submitted modifier instead of sending identity.
            state.time_held=state.time_held+1
            if previous_ads==ads then return true end
            if ads then invoke(model,'clear_ads')end
            output={dx=0,dy=0,dz=0,pitch=0,yaw=0,roll=0}
        else
            last_time=timestamp
            output,math_problem=invoke(model,'update',sample,dt)
        end
        if PORT51.kind(output)~='table'then return neutral(lease,'neutral',math_problem or 'Motion calculation unavailable')end
        if camera then
            local accepted,why=invoke(camera,'set_motion',{dx=output.camera_dx or 0,dy=output.camera_dy or 0,dz=output.camera_dz or 0,pitch=output.camera_pitch or 0,yaw=output.camera_yaw or 0,roll=output.camera_roll or 0})
            if accepted~=true then report(why or 'Camera movement unavailable')end
        end
        if output.reset and not resumed_modifier then
            handoff,previous_ads,sent_lease=nil,nil,nil
        end
        if profile_value then
            output.yaw=(output.yaw or 0)+math.rad(profile_value.yaw or 0)
            output.pitch=(output.pitch or 0)+math.rad(profile_value.pitch or 0)
            output.roll=(output.roll or 0)+math.rad(profile_value.roll or 0)
        end
        local converted,parent=pcall(to_parent,output,sample.camera_basis,sample.parent_basis)
        if not converted or not vector(parent)then
            state.read_failures=state.read_failures+1
            return neutral(lease,'neutral',converted and 'Converted motion exceeds native bounds' or tostring(parent))
        end
        -- Keep the preceding nonidentity modifier eligible for the first native
        -- ADS callback, before Lua observes the edge and starts its fade.
        parent.authored_ads=parent.qx~=0 or parent.qy~=0 or parent.qz~=0 or parent.qw~=1
        local transitioned,why=handoff_parent(lease,parent,ads,timestamp)
        if not transitioned or not vector(transitioned)then return neutral(lease,'neutral',why or'ADS handoff exceeds native bounds')end
        parent=transitioned
        state.speed,state.gait_phase,state.reset=output.speed,output.phase,output.reset
        state.sprint_weight,state.sprint_target,state.sprint_held=output.sprint_weight,output.sprint_target,output.sprint_held
        state.bob_weight=output.bob_weight
        state.shoulder_weight=output.shoulder_weight
        return apply(lease,parent,'active')
    end
    return self
end
return Runtime
