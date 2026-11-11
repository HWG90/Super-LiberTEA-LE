local PORT51=mod.require('src/first_person/compat51.lua')
local Locomotion=mod.require('src/first_person/locomotion.lua')
local Projection=mod.require('src/first_person/fird_projection.lua')
-- FirdPerson placement edits the linked arm/weapon render skeletons only.
-- Their external links consume the untouched native animation source selected
-- by the presentation lease; weapon placement is locked to the live camera.
-- Render displacement and rotation verified in bounded ordinary-TPV captures.
-- FirdPerson remains opt-in; full editor/gameplay acceptance is separate.
local M={render_pose_verified=true,native_animation_default=true}
local function xyz(sr,v)return {sr.Vector3.x(v),sr.Vector3.y(v),sr.Vector3.z(v)}end
local function vector(sr,v)return sr.Vector3(v[1],v[2],v[3])end
local function bounded(v)
    for _,n in ipairs(v)do assert(PORT51.kind(n)=='number' and n==n and math.abs(n)<2,'Retarget position exceeds2metres')end
    return v
end
local function context(b,s,ref)return b:_alignment_context({viewmodel=ref,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index})end
-- The CFFI cast costs ~203 us per handle (16,068 mission units: 3.26 s, live
-- 2026-10-31); the native bridge it calls first returns the same number in
-- well under 1 us. Use the bridge once one cast has loaded and matched it.
local function bridge_address()
    local fast
    return function(value)
        if fast then return fast(value)end
        local slow=PORT51.number(PORT51.ffi.cast('uintptr_t',value))
        local native=package.loaded.hd2_nativeinfo
        if PORT51.kind(native)=='table'and PORT51.kind(native.userdata_address)=='function'then
            local ok,same=pcall(native.userdata_address,value)
            if ok and slow and same==slow then fast=native.userdata_address end
        end
        return slow
    end
end
local address=bridge_address()
local function valid(b,c)
    return b:_u8(c.generations+c.index)==c.generation and b:_ptr(c.units+c.index*8)==c.object
        and b:_u32(c.object+8)==c.unit
end
local function lens(b,s)
    local exe=b:_alignment_executable()
    if b.fird_projection_getter~=exe then
        assert(b:_read(exe+0x2dd070,6)=='\243\015\016\065\052\195','FirdPerson camera-FOV getter changed')
        b.fird_projection_getter=exe
    end
    assert(PORT51.kind(s.camera)=='number','FirdPerson camera pointer unavailable')
    local value=PORT51.ffi.new('float[1]');PORT51.ffi.copy(value,b:_read(s.camera+0x34,4),4)
    local radians=PORT51.number(value[0]);assert(Projection.lens(radians),'FirdPerson scene projection unavailable')
    return radians
end
local function neutral(b,s)
    if s.aiming or s.reloading or s.shoulder_aim then return false end
    local action=PORT51.kind(b.action_state)=='function'and b:action_state(s)or nil
    if b.actions and PORT51.kind(b.actions.sample)=='function'then action=b.actions:sample(s,{1,3,10,11,14})end
    local on_foot=PORT51.kind(b.on_foot)=='function'and b:on_foot(s,action)or false
    if Locomotion.sprinting(action,on_foot,s.flags)then return false end
    -- This firing signature is labelled for the supported weapon-layer graph.
    if action and action.resource_match and action.l10==235 and action.l11==622 then return false end
    return true
end
local function resource_key(b,s)
    local wc=b:_pose_context(s)
    local key=b:_read(wc.weapon_object+0x358,8):gsub('.',function(c)return string.format('%02x',c:byte())end)
    assert(#key==16 and key~='0000000000000000','First-person weapon resource unavailable')
    return key
end
local function expected_target(s,key,projection_lens,expected)
    if not expected then return end
    assert(s.identity==expected.identity and s.player_identity==expected.player_identity
        and s.record==expected.request and key==expected.weapon_key,'First-person capture target changed')
    for _,name in ipairs({'weapon_unit','viewmodel','body','camera','context'})do
        assert(expected[name]==nil or expected[name]==s[name],'First-person capture '..name..' changed')
    end
    assert(Projection.lens(expected.lens)and math.abs(projection_lens-expected.lens)<=.0001,
        'First-person capture projection changed')
end
function M.capture(b,sr,support,expected,aim_helper)
    -- Bracket every SDK pose read with the complete equipped-weapon identity.
    -- A player-only snapshot cannot distinguish an outgoing weapon animation
    -- from a newly equipped resource sharing the same player and FPS Unit.
    local s=assert(b:snapshot());assert(s.safe and s.camera_kind==6 and not s.controller_active,'Enable normal FPV with ADS released before capturing FirdPerson')
    assert(neutral(b,s),'Release aiming, firing, reloading and sprinting before capturing first-person placement')
    local key=resource_key(b,s);local source_lens=lens(b,s)
    expected_target(s,key,source_lens,expected)
    local cfg=assert(b:camera_config());local handles={}
    local world=sr.Application.main_world();local units=sr.World.units(world)
    assert(PORT51.kind(units)=='table' and #units<=131072,'Unit inventory unavailable')
    for _,h in ipairs(units)do local ref=math.floor(address(h)/4)
        if ref==s.body or ref==s.viewmodel or ref==cfg.camera_unit then handles[ref]=h end
    end
    local body=assert(handles[s.body]);local fps=assert(handles[s.viewmodel]);local camera=assert(handles[cfg.camera_unit])
    local bc=context(b,s,s.body);local fc=context(b,s,s.viewmodel);local cc=context(b,s,cfg.camera_unit)
    assert(b:_u32(bc.object+0x70)==107 and b:_u32(fc.object+0x70)==63,'Experimental rig topology unsupported')
    local rows={};local source_camera=sr.Unit.node(fps,'camera')
    assert(source_camera==51 and b:_u32(b:_ptr(fc.object+0xA0)+50*4)==0x60ED8C39,'FPS camera assignment changed')
    local camera_pose=sr.Unit.world_pose(fps,source_camera)
    local inverse=sr.Matrix4x4.inverse(camera_pose)
    assert(b:_u32(b:_ptr(fc.object+0xA0)+8*4)==0x4FDD3337,'FPS weapon assignment changed')
    local weapon_pose=sr.Unit.world_pose(fps,9)
    local projection=Projection.capture(xyz(sr,sr.Unit.world_position(fps,9)),
        {sr.Quaternion.to_elements(sr.Quaternion.from_matrix4x4(weapon_pose))},
        xyz(sr,sr.Unit.world_position(fps,source_camera)),
        {sr.Quaternion.to_elements(sr.Quaternion.from_matrix4x4(camera_pose))})
    projection.fov=source_lens
    for _,entry in ipairs({{'l_shoulder',0x03752C98,44,10,42},{'r_shoulder',0x1620B2CE,67,30,65}})do
        local name,hash,dest,source,parent=unpack(entry)
        local dn,sn=sr.Unit.node(body,name),sr.Unit.node(fps,name)
        assert(dn==dest+1 and sn==source+1,'Semantic bone index changed')
        local hashes=b:_ptr(bc.object+0xA0);local links=b:_ptr(bc.object+0x98)
        assert(b:_u32(hashes+dest*4)==hash and math.floor(b:_u32(links+dest*4)/65536)==parent,'TPV shoulder assignment changed')
        assert(b:_u32(b:_ptr(fc.object+0xA0)+source*4)==hash,'FPS bone assignment changed')
        rows[#rows+1]={node=dn,parent=parent+1,hash=hash,hashes=hashes,links=links,
            target=bounded(xyz(sr,sr.Matrix4x4.transform(inverse,sr.Unit.world_position(fps,sn))))}
    end
    local grip
    if support then
        assert(b:_u32(b:_ptr(fc.object+0xA0)+8*4)==0x4FDD3337
            and b:_u32(b:_ptr(fc.object+0xA0)+13*4)==0x5C0C68D3,'FPS support assignments changed')
        local tag=assert(b.actions:sample(s,{10,11}))
        if tag.resource_match and tag.l10 and tag.l11 and tag.l11~=763 and tag.l11~=764 then
            grip={key=key,position=support.capture(sr,fps),tag=tag}
        end
    end
    local pivot=xyz(sr,sr.Matrix4x4.transform(inverse,sr.Unit.world_position(fps,6)))
    local aim,aim_reason
    if aim_helper then
        local function frame(node)
            local pose=sr.Unit.world_pose(fps,node)
            return {position=xyz(sr,sr.Unit.world_position(fps,node)),
                rotation={sr.Quaternion.to_elements(sr.Quaternion.from_matrix4x4(pose))}}
        end
        local branch=frame(6);branch.local_rotation={sr.Quaternion.to_elements(sr.Unit.local_rotation(fps,6))}
        local called,value,reason=pcall(aim_helper.capture,b,s,{fps_context=fc,parent=frame(5),branch=branch,
            weapon=frame(9),camera=frame(source_camera),reference=b.pose_placement,
            authored_rotation=expected and expected.authored_rotation,fov=projection.fov})
        if called then aim,aim_reason=value,reason else aim_reason=tostring(value)end
    end
    -- Ownership reads are uncached in Backend; also retire its immutable-code
    -- epoch so the closing check cannot reuse an earlier fingerprint decision.
    if PORT51.kind(b._invalidate_frame_checks)=='function'then b:_invalidate_frame_checks()end
    local ws=assert(b:snapshot());assert(ws.safe and ws.identity==s.identity and ws.player_identity==s.player_identity
        and ws.record==s.record and ws.weapon_unit==s.weapon_unit and ws.viewmodel==s.viewmodel
        and ws.camera_kind==6 and not ws.controller_active and neutral(b,ws)
        and sr.Application.main_world()==world,'First-person capture owner or neutral action changed')
    local final_key=resource_key(b,ws);local final_lens=lens(b,ws)
    assert(final_key==key and math.abs(final_lens-source_lens)<=.0001,'First-person capture weapon or projection changed')
    expected_target(ws,final_key,final_lens,expected)
    return {weapon_key=key,weapon_identity=ws.identity,weapon_unit=ws.weapon_unit,projection=projection,source_fov=projection.fov,reference=b.pose_placement,pivot=pivot,forward=cfg.forward,up=cfg.up,world=world,identity=s.player_identity,body=body,camera=camera,body_context=bc,fps_context=fc,fps=fps,support_grip=grip,aim=aim,aim_reason=aim_reason,camera_context=cc,rows=rows}
end
function M.new(b,sr,camera,head,movement,dof,compat,foreign,log,options)
    local ffi=PORT51.ffi ;local axes=ffi.new('float[12]')
    local retarget_policy={native_details=true,visible_arms=true}
    options=options or {};local profiles=options.profiles
    local function copy(p)return{x=p.x,y=p.y,z=p.z,yaw=p.yaw or 0,pitch=p.pitch or 0,roll=p.roll or 0}end
    local function copy_grip(grip)
        if not grip then return nil end
        local tag={};for key,item in pairs(grip.tag)do tag[key]=item end
        return {key=grip.key,position={unpack(grip.position)},tag=tag}
    end
    local function copy_aim(aim)
        if not aim then return nil end
        local projection=Projection.reference(aim.projection.position,aim.projection.rotation)
        assert(Projection.lens(aim.projection.fov),'FirdPerson sight projection invalid')
        projection.fov=aim.projection.fov
        local sight={};for key,item in pairs(aim.sight or{})do sight[key]=item end
        return {projection=projection,sight=sight,method=aim.method,
            reference=copy(aim.reference or{x=0,y=0,z=0}),
            pivot=aim.pivot and{unpack(aim.pivot)}or nil,source_fov=aim.source_fov or projection.fov}
    end
    local self={enabled=false,phase='off',writes=0,coalesced=0,reference_needed=false,native_animation=options.native_animation==true};local calibration
    local references,reference_identity,current_reference,rig_reference={},nil,nil,nil
    local draft,value,target,profile_key,profile_action,profile_revision,last_time
    local clock=options.clock or os.clock
    local render_signature,render_parts
    local skinned,source_reader,retarget_poles,weapon_children
    local support=options.support and options.support.new(sr)
    local native_ads_frames=0
    local refresh_epoch
    local attachment_deadline
    local render_ready
    local stage='idle'
    local function ptr0(at)return b:_u32(at)+b:_u32(at+4)*4294967296 end
    local function render_parent()
        if options.presentation then return calibration.fps_context,calibration.fps end
        return calibration.body_context,calibration.body
    end
    local function render_chain(s)
        if not sr.World or PORT51.kind(sr.World.update_unit)~='function' then return {}end
        local appearance,owner
        if head.render_appearance then appearance,owner=head:render_appearance()end
        if not appearance then return {}end
        assert(owner==s.player_identity and #appearance==120,'Render appearance owner changed')
        local weapon=self.weapon_unit or 0
        local parent_context,parent_handle=render_parent()
        assert(valid(b,parent_context),'Render animation source generation changed')
        local signature=appearance..':'..weapon..':'..tostring(self.weapon_identity)..':'..parent_context.object
        if not options.presentation and signature==render_signature then return render_parts end
        local refs={};local function integer(at)
            local a,b,c,d=appearance:byte(at+1,at+4);return a+b*256+c*65536+d*16777216
        end
        local slots=options.retarget and{2,6,7,8,9}or{6,7}
        for layer=0,2 do for _,slot in ipairs(slots)do
            local ref=integer(layer*40+slot*4)
            if ref~=0 and ref~=0xFFFFFFFF then refs[ref]=options.retarget and'body'or(slot==6 and'left'or'right')end
        end end
        if weapon~=0 then refs[weapon]='weapon' end
        local parents,signatures={},{}
        -- Native presentation only reparents the arm clothing. A held weapon
        -- can coherently retain its body parent; never relink it ourselves.
        for ref,group in pairs(refs)do
            local ctx=context(b,s,ref)
            local parent=options.presentation and ptr0(ctx.object+0x1D0)or b:_ptr(ctx.object+0x1D0)
            local pc,ph=parent_context,parent_handle
            if options.presentation and group=='weapon'and parent==calibration.body_context.object then
                pc,ph=calibration.body_context,calibration.body
            end
            if parent~=pc.object then
                local fps=calibration.fps_context
                if options.presentation and(parent==0 or parent==calibration.body_context.object)
                    or fps and valid(b,fps)and parent==fps.object then return nil end
                error('Render '..group..' is not attached to an owned animation source')
            end
            if options.presentation then
                local source=ptr0(pc.object+0x88);local linked=ptr0(ctx.object+0x78)
                if source==0 or linked==0 then return nil end
                if linked~=source then
                    local body_array=ptr0(calibration.body_context.object+0x88)
                    local fps_array=ptr0(calibration.fps_context.object+0x88)
                    if linked==body_array or linked==fps_array then return nil end
                    error('Render '..group..' animation matrix source changed')
                end
                signatures[#signatures+1]=ref..':'..parent..':'..linked
            end
            parents[ref]={context=pc,handle=ph,object=parent}
        end
        if options.presentation then table.sort(signatures);signature=signature..':'..table.concat(signatures,':')end
        if signature==render_signature then return render_parts end
        if skinned then assert(skinned:restore());skinned=nil end
        local found,handle_by_ref={},{};local list=sr.World.units(calibration.world)
        assert(PORT51.kind(list)=='table' and #list<=131072,'Render inventory unavailable')
        for _,h in ipairs(list)do
            local ref=math.floor(address(h)/4)
            if options.children then handle_by_ref[ref]=h end
            if refs[ref]then found[ref]=h end
        end
        local parts={}
        for ref,handle in pairs(found)do
            local ctx=context(b,s,ref)
            local native=assert(parents[ref]);local pc,ph=native.context,native.handle
            local parent=options.presentation and ptr0(ctx.object+0x1D0)or b:_ptr(ctx.object+0x1D0)
            local world=b:_ptr(ctx.object+24)
            assert(parent==native.object and valid(b,pc),'Render rig animation source changed')
            local owned_body=calibration.body_context
            local row={handle=handle,context=ctx,group=refs[ref],parent_context=pc,parent_handle=ph}
            row.valid=function()
                local current_parent=options.presentation and ptr0(ctx.object+0x1D0)or b:_ptr(ctx.object+0x1D0)
                return valid(b,owned_body)and valid(b,pc)and valid(b,ctx)and current_parent==parent
                    and b:_ptr(ctx.object+24)==world and world==b:_ptr(owned_body.object+24)
            end
            assert(row.valid(),'Render rig ownership changed');parts[#parts+1]=row
        end
        for ref in pairs(refs)do assert(found[ref],'Required render attachment unavailable')end
        weapon_children=nil
        if options.children then
            for _,part in ipairs(parts)do if part.group=='weapon'then
                weapon_children=options.children.new(b,sr,calibration,part.context,{by_ref=handle_by_ref})
                break
            end end
        end
        if options.skin then
            local adapter_cal={};for key,item in pairs(calibration)do adapter_cal[key]=item end
            adapter_cal.body_context,adapter_cal.body=parent_context,parent_handle
            skinned=options.skin.new(b,sr,adapter_cal,parts)
        end
        render_signature,render_parts=signature,parts
        self.render_rebuilds=(self.render_rebuilds or 0)+1
        return parts
    end
    local function editing()local e=options.editor and options.editor();return e and e.kind~='camera' and e:is_active()or false end
    local function editor_value(action)
        if b.action_placement then return b.action_placement(self.weapon_key,action or 'idle')end
        return current_reference and current_reference.reference or calibration and calibration.reference or {x=0,y=0,z=0,yaw=0,pitch=0}
    end
    local function player_cache(identity)
        if reference_identity==identity then return end
        references,reference_identity,current_reference,rig_reference={},identity,nil,nil
        if support then support:reset();support.grips={}end
    end
    function self:refresh_target()
        if b.frame_active and refresh_epoch==b.frame_epoch then return true end
        if b.frame_active then refresh_epoch=b.frame_epoch end
        local s=b:snapshot();self.weapon_unit=s and s.weapon_unit or nil
        self.weapon_snapshot=s
        if self.native_animation then
            if s and s.safe and self.weapon_identity~=s.identity then
                local wc=context(b,s,s.weapon_unit)
                assert(valid(b,wc),'Natural weapon generation changed')
                self.weapon_key=b:_read(wc.object+0x358,8):gsub('.',function(c)return string.format('%02x',c:byte())end)
                assert(#self.weapon_key==16 and self.weapon_key~='0000000000000000','Natural weapon resource unavailable')
            end
            self.weapon_identity=s and s.identity or nil
            self.reference_needed=false
            return true
        end
        if s then player_cache(s.player_identity)end
        if not s or not s.safe then self.weapon_key,self.weapon_identity=nil,nil;current_reference=nil;self.reference_needed=true;return true end
        if self.weapon_identity~=s.identity then
            local ctx=b:_pose_context(s)
            local resource=b:_read(ctx.weapon_object+0x358,8)
            self.weapon_key=resource:gsub('.',function(c)return string.format('%02x',c:byte())end)
            assert(#self.weapon_key==16 and self.weapon_key~='0000000000000000','Weapon resource unavailable')
            self.weapon_identity=s.identity;profile_key=nil;draft=nil
            if options.aim then options.aim:reset()end
        end
        current_reference=references[self.weapon_key];self.reference_needed=current_reference==nil
        return true
    end
    local function cached_rig(s)
        local c=rig_reference
        local ok,current=pcall(function()
            return c and s and sr.Application.main_world()==c.world and s.player_identity==c.identity
                and valid(b,c.body_context) and valid(b,c.camera_context)
                and(not(options.presentation or options.source)or c.fps_context and s.viewmodel==c.fps_context.unit and valid(b,c.fps_context))
        end)
        return ok and current==true
    end
    -- Read-only discovery for the automatic F11 coordinator. A known resource
    -- may still need a fresh bootstrap if its retained rig generation retired.
    function self:reference_status()
        self:refresh_target()
        local s=self.weapon_snapshot
        return {weapon_key=self.weapon_key,weapon_identity=self.weapon_identity,
            player_identity=s and s.player_identity,camera_kind=s and s.camera_kind,
            controller_active=s and s.controller_active==true or false,
            safe=s and s.safe==true or false,known=current_reference~=nil,
            neutral=s and s.safe==true and not s.controller_active and neutral(b,s)or false,
            cached_ready=s and s.safe==true and s.camera_kind==4 and not s.controller_active
                and current_reference~=nil and cached_rig(s)and true or false}
    end
    function self:cached_capture()
        local state=self:reference_status()
        if not state.cached_ready then return nil,'Current weapon requires a fresh first-person reference'end
        local out={};for key,item in pairs(rig_reference)do out[key]=item end
        local ref=current_reference
        out.weapon_key=self.weapon_key;out.weapon_identity=self.weapon_identity
        out.weapon_unit=self.weapon_unit;out.identity=state.player_identity
        out.projection=Projection.reference(ref.projection.position,ref.projection.rotation)
        out.projection.fov=ref.projection.fov;out.source_fov=ref.projection.fov
        out.reference=copy(ref.reference);out.pivot=ref.pivot and{unpack(ref.pivot)}or nil
        out.support_grip=copy_grip(ref.support_grip)
        out.aim=copy_aim(ref.aim);out.aim_reason=ref.aim_reason
        return out
    end
    function self:placement_target()if self.enabled and not self.reference_needed then return self.weapon_key,self.weapon_identity end end
    function self:get_placement()return copy(draft or value or editor_value('idle'))end
    function self:set_placement(p)
        if not self.enabled or self.reference_needed or not profiles or not profiles.valid(p)then return false,'FirdPerson placement unavailable'end
        draft=copy(p);return true
    end
    function self:result()return{mode='pose_offset',phase=self.enabled and 'running'or'idle',reference_needed=self.reference_needed,
        weapon=self.weapon_key,aim_weight=self.aim_weight or 0,aim_reason=self.aim_reason,native_ads_phase=self.native_ads_phase}end
    function self:is_clean()return not self.enabled and self.phase=='off'end
    local facade={is_enabled=function()return self.enabled end,result=function()return {mode='pose_offset',phase='running'}end}
    local function owned()
        local s=b:player_snapshot()
        return s and calibration and sr.Application.main_world()==calibration.world and s.player_identity==calibration.identity
            and valid(b,calibration.body_context) and valid(b,calibration.camera_context)
            and(not(options.presentation or options.source)or calibration.fps_context and s.viewmodel==calibration.fps_context.unit
                and valid(b,calibration.fps_context)),s
    end
    local focus_facade={is_enabled=facade.is_enabled,result=facade.result}
    function focus_facade:focus_owned(s)
        return calibration~=nil and facade:is_enabled()and options.native_animation==true
            and s.safe==true and s.camera_kind==4 and not s.controller_active
            and s.player_identity==calibration.identity and s.body==calibration.body_context.unit
            and sr.Application.main_world()==calibration.world
            and valid(b,calibration.body_context)and valid(b,calibration.camera_context)
    end
    local function restore()
        if not calibration then return true end
        if skinned then
            local done,why=skinned:restore()
            if done==true and weapon_children then weapon_children:publish(self.weapon_snapshot)end
            return done,why
        end
        return true
    end
    local function release_render()
        assert(restore())
        -- Native ADS reparents/remaps these same units and owns their locals.
        -- A later TPV return must capture fresh links and baselines once.
        skinned,render_parts,render_signature,weapon_children=nil,nil,nil,nil
        retarget_poles=nil
        attachment_deadline=nil
        if options.aim then options.aim:reset()end
    end
    function self:is_enabled()return self.enabled end
    function self:status()return self.phase end
    function self:prepare_native_ads(expected)
        if not self.enabled then return false,'FirdPerson is not enabled'end
        local called,done,why=pcall(function()
            local current,s=owned()
            assert(current and s.safe and s.camera_kind==4 and not foreign(),'Native ADS camera ownership changed')
            local equipped=assert(b:snapshot())
            assert(expected and equipped.safe and equipped.identity==expected.identity
                and equipped.player_identity==expected.player_identity and equipped.record==expected.record,
                'Native ADS equipped weapon changed')
            if options.fire_filter then
                local stopped,reason=options.fire_filter:stop()
                if stopped~=true then return false,reason end
            end
            release_render()
            if options.presentation then return options.presentation:stop()end
            return true
        end)
        if not called then return false,tostring(done)end
        return done,why
    end
    function self:start(c)
        if self.native_animation then return self:start_native()end
        render_ready=nil;self.render_error=nil;self.render_frames=0
        assert(self:is_clean(),'FirdPerson already active or cleaning up');calibration=c
        assert(c.projection and Projection.lens(c.projection.fov),'Capture a valid first-person projection first')
        Projection.reference(c.projection.position,c.projection.rotation)
        local ok,s=owned();assert(ok and s.safe and s.camera_kind==4,'Normal camera/player changed before FirdPerson')
        assert(PORT51.kind(c.weapon_key)=='string'and #c.weapon_key==16 and c.weapon_key:match('^%x+$')and c.weapon_key~='0000000000000000','First-person capture weapon resource unavailable')
        local equipped=assert(b:snapshot())
        assert(equipped.safe and equipped.camera_kind==4 and not equipped.controller_active
            and equipped.player_identity==c.identity and equipped.identity==c.weapon_identity
            and equipped.weapon_unit==c.weapon_unit and resource_key(b,equipped)==c.weapon_key,
            'Equipped weapon changed before FirdPerson')
        player_cache(c.identity)
        local captured=Projection.reference(c.projection.position,c.projection.rotation);captured.fov=c.projection.fov
        references[c.weapon_key]={identity=c.identity,projection=captured,source_fov=captured.fov,
            reference=copy(c.reference or b.pose_placement or{x=0,y=0,z=0}),pivot=c.pivot and{unpack(c.pivot)}or nil,
            support_grip=copy_grip(c.support_grip),aim=copy_aim(c.aim),aim_reason=c.aim_reason}
        rig_reference={};for key,item in pairs(c)do rig_reference[key]=item end
        b.fird_camera_active=true
        local ready,why=camera:prepare();if not ready then b.fird_camera_active=false;calibration=nil;return false,why end
        calibration.reference=copy(calibration.reference or b.pose_placement or {x=0,y=0,z=0})
        render_signature,render_parts,refresh_epoch,skinned,source_reader,retarget_poles,weapon_children=nil,nil,nil,nil,nil,nil,nil
        attachment_deadline=nil
        b.support_grip_tracking=support~=nil
        self.enabled=true;self:refresh_target()
        if options.fov and current_reference then
            local accepted,problem=options.fov:start(current_reference)
            if accepted~=true then self:stop();return false,problem end
        end
        self:refresh_target();
        if support then support:reset();local g=c.support_grip;if g then support:set(g.key,g.position,g.tag)end end
        native_ads_frames=0;self:refresh_target();value=copy(editor_value('idle'));draft=nil;profile_key=nil;last_time=nil
        self.phase=self.reference_needed and 'Fird Person: capture first-person placement for this weapon'or 'FirdPerson dev active';return true
    end
    function self:start_native()
        assert(self.native_animation,'Natural animation mode is unavailable')
        assert(self:is_clean(),'FirdPerson already active or cleaning up')
        local s,problem=b:snapshot();assert(s,problem or'Local player unavailable')
        assert(s.safe and s.camera_kind==4 and not s.controller_active and not foreign(),'Return to normal gameplay before Fird Person')
        local cfg=assert(b:camera_config())
        local c={identity=s.player_identity,world=sr.Application.main_world(),
            body_context=context(b,s,s.body),camera_context=context(b,s,cfg.camera_unit)}
        assert(valid(b,c.body_context)and valid(b,c.camera_context),'Natural Fird rig generation changed')
        local fov_capture={identity=s.player_identity,source_fov=options.lens and options.lens(s)or lens(b,s)}
        assert(Projection.lens(fov_capture.source_fov),'Natural Fird camera lens unavailable')
        calibration=c;self.native_fov_capture=fov_capture
        render_ready=nil;self.render_error=nil;self.render_frames=0
        b.fird_camera_active=true
        local ready,why=camera:prepare()
        if ready~=true then b.fird_camera_active=false;calibration=nil;self.native_fov_capture=nil;return false,why end
        self.enabled=true;self:refresh_target()
        if options.fov then
            local done,reason=options.fov:start(fov_capture)
            if done~=true then self:stop();return false,reason end
        end
        if options.ready_pose then options.ready_pose:request(true)end
        self.animation_source='native_third_person';self.scene_fov=fov_capture.source_fov
        self.phase='FirdPerson native animation active';return true
    end
    function self:stop()
        render_ready=nil;self.render_error=nil
        self.enabled=false
        b.fird_camera_active=false
        b.support_grip_tracking=false
        if support then support:reset()end
        if options.aim then options.aim:reset()end
        local ok,done,why=pcall(restore)
        local errors={}
        if not ok or done~=true then errors[#errors+1]=tostring(ok and(why or 'Render restoration remains pending')or done)end
        local managers={}
        if options.fire_filter then managers[#managers+1]=options.fire_filter end
        if options.ready_pose then managers[#managers+1]=options.ready_pose end
        if options.native_ads then managers[#managers+1]=options.native_ads end
        if options.presentation then managers[#managers+1]=options.presentation end
        for _,manager in ipairs({camera,head,movement,dof})do managers[#managers+1]=manager end
        if options.fov then managers[#managers+1]=options.fov end
        for _,target in ipairs(managers)do
            local called,done,reason=pcall(target.stop,target)
            if not called or done~=true then errors[#errors+1]=tostring(called and reason or done)end
        end
        if #errors>0 then self.phase='FirdPerson cleanup pending';return false,table.concat(errors,'; ')end
        skinned,render_parts,render_signature,refresh_epoch,source_reader,retarget_poles,weapon_children=nil,nil,nil,nil,nil,nil,nil
        calibration=nil;current_reference=nil;self.native_fov_capture=nil;draft,value,target=nil,nil,nil;self.weapon_key,self.weapon_identity=nil,nil;self.reference_needed=false;self.phase='off';return true
    end
    local function apply_pose(s)
        local placement_dt=1/60
        local placement=current_reference.reference
        if profiles and self.weapon_key then
            local now=clock();local dt=last_time and math.max(0,math.min(.1,now-last_time))or 1/60;last_time=now;placement_dt=dt
            if editing()and draft then placement=draft
            else
                draft=nil
                local a=self.weapon_snapshot and self.weapon_snapshot.action_state or b:action_state(s)
                local sample={ads=s.controller_active,shoulder_aim=s.shoulder_aim,stance_flags=s.flags,
                    action_resource=a and a.resource,action_verified=a and a.resource_match,
                    l1=a and a.l1,l3=a and a.l3,sprint=Locomotion.sprinting(a,b:on_foot(s,a),s.flags),
                    reload=s.reloading==true}
                local action=profiles.select(sample,b.action_mapping and b.action_mapping())
                local revision=b.action_placement_revision or 0
                if profile_key~=self.weapon_key or profile_action~=action or profile_revision~=revision then
                    target=copy(editor_value(action));profile_key,profile_action,profile_revision=self.weapon_key,action,revision
                end
                local blend=1-math.exp(-dt/.1)
                for _,axis in ipairs({'x','y','z','yaw','pitch','roll'})do
                    local delta=(target[axis]or 0)-(value[axis]or 0)
                    value[axis]=math.abs(delta)<.0001 and(target[axis]or 0)or(value[axis]or 0)+delta*blend
                end
                placement=value
            end
        end
        -- The camera setter may have consumed an earlier body pose. Pair its
        -- actual position and orientation; rebuilding the eye from a newer
        -- animated head introduces a walking-dependent displacement.
        stage='camera frame'
        local body_sample=options.source and options.source.world(b,calibration.body_context,107)or nil
        local basis,anchor
        if options.camera_frame then
            local frame=assert(options.camera_frame.read(b,calibration,s),'Presented camera pose unavailable')
            basis,anchor=frame.basis,frame.position
        else
            assert(not options.render_driven,'Render placement requires the presented camera pose')
            ffi.copy(axes,b:_read(s.context+0x0C,44),44)
            basis={{PORT51.number(axes[0]),PORT51.number(axes[1]),PORT51.number(axes[2])},
                {PORT51.number(axes[4]),PORT51.number(axes[5]),PORT51.number(axes[6])},
                {PORT51.number(axes[8]),PORT51.number(axes[9]),PORT51.number(axes[10])}}
            assert(b:_u32(b:_ptr(calibration.body_context.object+0xA0)+90*4)==0x8C5570C9,'Head assignment changed')
            local body_head,body_forward
            if body_sample then
                body_head=assert(body_sample.by_index[91],'Copied head pose unavailable').position
                body_forward=assert(body_sample.by_index[1],'Copied body root unavailable').basis[2]
            else
                body_head=xyz(sr,sr.Unit.world_position(calibration.body,91))
                local body_rotation=sr.Quaternion.from_matrix4x4(sr.Unit.world_pose(calibration.body,1))
                body_forward=xyz(sr,sr.Quaternion.rotate(body_rotation,sr.Vector3(0,1,0)))
            end
            local offset=b.fird_camera_offset or{x=0,y=calibration.forward or .18,z=calibration.up or .04}
            anchor=Projection.camera_anchor(body_head,basis,offset,body_forward)
        end
        for i=1,3 do local n=0;for j=1,3 do n=n+basis[i][j]^2 end;assert(math.abs(n-1)<.02,'Camera axis changed')end
        stage='render attachments'
        local children=render_chain(s)
        if not children then
            assert(restore())
            attachment_deadline=attachment_deadline or clock()+.5
            assert(clock()<=attachment_deadline,'Native render attachment reattachment timed out')
            self.phase='FirdPerson waiting for native render attachment reattachment'
            return
        end
        attachment_deadline=nil
        if options.skin then
            stage=options.source and'weapon animation placement'or'current weapon lock'
            assert(skinned,'Linked skinning layout unavailable')
            local source_context,source_handle=render_parent()
            local source_sample
            if options.source then
                source_reader=source_reader or options.source.new(b,calibration)
                source_sample=source_reader:sample(self.weapon_snapshot)
            end
            local body_hashes=b:_ptr(source_context.object+0xA0)
            local weapon_node=options.presentation and 9 or 85
            assert(b:_u32(body_hashes+(weapon_node-1)*4)==0x4FDD3337,'Native weapon assignment changed')
            local weapon_pose,current_weapon
            if source_sample then
                current_weapon={position=source_sample.weapon.position,rotation=source_sample.weapon.rotation,
                    frame_origin=source_sample.camera.position,frame_rotation=source_sample.camera.rotation}
            else
                weapon_pose=sr.Unit.world_pose(source_handle,weapon_node)
                current_weapon={position=xyz(sr,sr.Unit.world_position(source_handle,weapon_node)),
                    rotation={sr.Quaternion.to_elements(sr.Quaternion.from_matrix4x4(weapon_pose))}}
            end
            if options.presentation and not source_sample then
                -- The FPS graph may still be expressed at its last native
                -- camera origin. Validate its pose in that source frame;
                -- the live body head supplies the independent target frame.
                assert(b:_u32(body_hashes+50*4)==0x60ED8C39,'Native FPS camera assignment changed')
                current_weapon.frame_origin=xyz(sr,sr.Unit.world_position(source_handle,51))
            end
            local current_lens
            if options.fov and options.fov.lensmatching then current_lens=current_reference.projection.fov
            elseif options.lens then current_lens=options.lens(s)
            else current_lens=lens(b,s)end
            local projection_reference=current_reference
            if options.aim then
                local mode=options.aim_mode and options.aim_mode()or'fird'
                local aiming=mode=='fird'and(s.shoulder_aim==true or s.aiming==true)
                projection_reference,placement,self.aim_weight,self.aim_reason=options.aim:update(
                    current_reference,placement,editor_value('ads'),aiming,placement_dt)
            end
            local common,projection
            if source_sample then
                local neutral=current_reference.aim and current_reference.aim.projection
                if not neutral then
                    assert(restore());references[self.weapon_key]=nil;current_reference=nil
                    self.reference_needed=true;self.phase='Fird Person: capture the native weapon animation reference';return
                end
                common,projection=Projection.follow(projection_reference,current_weapon,anchor,basis,placement,current_lens,neutral)
            else common,projection=Projection.lock(projection_reference,current_weapon,anchor,basis,placement,current_lens)end
            if not common then
                assert(restore());self.phase='FirdPerson waiting for camera projection';return
            end
            local weapon_common=common
            if options.presentation or options.retarget then
                for _,part in ipairs(children)do if part.group=='weapon'and part.parent_context.object==calibration.body_context.object then
                    local hashes=b:_ptr(calibration.body_context.object+0xA0)
                    assert(b:_u32(hashes+84*4)==0x4FDD3337,'TPV held weapon assignment changed')
                    if body_sample then
                        weapon_common=Projection.rebase(common,assert(body_sample.by_index[85],'Copied weapon attachment unavailable'))
                    else
                        local pose=sr.Unit.world_pose(calibration.body,85)
                        weapon_common=assert(Projection.lock(projection_reference,
                            {position=xyz(sr,sr.Unit.world_position(calibration.body,85)),
                                rotation={sr.Quaternion.to_elements(sr.Quaternion.from_matrix4x4(pose))}},
                            anchor,basis,placement,current_lens))
                    end
                    self.weapon_parent='third_person_rig';break
                end end
                if weapon_common==common then self.weapon_parent='first_person_rig'end
            end
            if options.retarget then
                stage='first-person bone adaptation'
                assert(source_sample,'First-person animation source unavailable')
                local bones,stats=options.retarget.map(source_sample,body_sample,common,retarget_poles,retarget_policy)
                assert(bones,stats or'First-person arm adaptation unavailable')
                common.bones=bones;common.retarget_only=true
                self.retarget_stats=stats;retarget_poles=stats.poles
                common.parent_frames=body_sample.by_index
                weapon_common.parent_frames=body_sample.by_index
            end
            common.rotation=sr.Quaternion.from_elements(unpack(common.rotation))
            common.source_rotation=sr.Quaternion.from_elements(unpack(common.source_rotation))
            common.target_rotation=sr.Quaternion.from_elements(unpack(common.target_rotation))
            if weapon_common~=common then
                weapon_common.rotation=sr.Quaternion.from_elements(unpack(weapon_common.rotation))
                weapon_common.source_rotation=sr.Quaternion.from_elements(unpack(weapon_common.source_rotation))
                weapon_common.target_rotation=sr.Quaternion.from_elements(unpack(weapon_common.target_rotation))
            end
            local transforms={left=common,right=common,body=common,weapon=weapon_common}
            if support and self.weapon_key and not options.presentation and not options.retarget then
                assert(b:_u32(body_hashes+47*4)==0x5C0C68D3,'TPV support assignment changed')
                local action=self.weapon_snapshot and self.weapon_snapshot.action_state
                transforms.left=support:apply(self.weapon_key,common,weapon_pose,
                    sr.Unit.world_position(calibration.body,48),action,placement_dt)
                self.support_weight=support.weight
            end
            local before=skinned.writes
            stage='linked skinning update'
            assert(skinned:apply(transforms))
            if weapon_children then
                local published,problem=weapon_children:publish(self.weapon_snapshot)
                self.attachment_count=weapon_children.count
                self.attachment_publishes=weapon_children.publishes
                if published~=true then
                    -- A native reload can detach/reattach a magazine. The
                    -- next frame rediscovers that bounded child graph.
                    weapon_children=nil;render_signature=nil
                    self.attachment_reason=problem
                else self.attachment_reason=nil end
            end
            self.writes=self.writes+skinned.writes-before
            self.skin_nodes=skinned.nodes;self.skin_publishes=skinned.publishes
            self.animation_source=options.retarget and'first_person_bones_on_third_person_models'
                or(options.presentation and'first_person_rig'or'third_person_rig')
            self.projection_factor=projection.factor;self.scene_fov=current_lens
            self.phase='FirdPerson linked skinning active'
            return
        end
        error('Linked skinning adapter required')
    end
    function self:update()
        if not self.enabled then return true end
        if self.render_error then
            local problem=self.render_error;self.render_error=nil;self:stop()
            log('FirdPerson render placement stopped: '..problem);return false,problem
        end
        render_ready=nil;stage='player ownership'
        local ok,why=xpcall(function()
            local current,s=owned();assert(current,'FirdPerson player/rig generation changed')
            self:refresh_target()
            local native_ads_wait=false
            if options.native_ads then
                stage='native ADS handoff'
                local mode=options.aim_mode and options.aim_mode()or'fird'
                local ready,problem=options.native_ads:update(self.enabled,mode)
                local state=options.native_ads:result();self.native_ads_phase=state.phase
                native_ads_wait=ready~=true or state.phase=='waiting for render cleanup'
                self.native_ads_reason=problem
                -- Entry/exit may synchronously replace the native camera.
                current,s=owned();assert(current,'FirdPerson player changed during native ADS handoff')
                refresh_epoch=nil;self:refresh_target()
            end
            if foreign()then
                if options.fire_filter then assert(options.fire_filter:stop())end
                release_render();camera:stop();head:stop();movement:stop();dof:stop()
                if options.presentation then options.presentation:stop()end
                if options.fov then assert(options.fov:stop())end
                self.phase='FirdPerson waiting for camera';return
            end
            stage='camera and visibility'
            assert(camera:update(facade));assert(head:update(facade))
            if self.native_animation then assert(movement:update_fird(focus_facade,native_ads_wait))else movement:update(facade)end
            dof:update(facade,camera,compat)
            if native_ads_wait and s.camera_kind==4 then
                release_render();self.phase='FirdPerson waiting for native ADS cleanup';return
            end
            if s.camera_kind~=4 or not s.safe or s.controller_active then
                if options.fire_filter then assert(options.fire_filter:stop())end
                if options.fov and not options.fov:is_clean()then assert(options.fov:update(s))end
                release_render()
                if options.presentation then
                    local ready=options.presentation:stop()
                    if ready~=true then self.phase='FirdPerson waiting for native presentation cleanup';return end
                end
                if support then
                    support:reset()
                    native_ads_frames=s.camera_kind==6 and s.controller_active and native_ads_frames+1 or 0
                    if native_ads_frames==3 and self.weapon_key and calibration.fps_context
                        and calibration.fps_context.unit==s.viewmodel and valid(b,calibration.fps_context)then
                        local fc=calibration.fps_context;local hashes=b:_ptr(fc.object+0xA0)
                        if b:_u32(hashes+8*4)==0x4FDD3337 and b:_u32(hashes+13*4)==0x5C0C68D3 then
                            local tag=self.weapon_snapshot and self.weapon_snapshot.action_state
                            if tag and tag.resource_match and tag.l10 and tag.l11 and tag.l11~=763 and tag.l11~=764 then
                                local ok,p=pcall(options.support.capture,sr,calibration.fps)
                                if ok then support:set(self.weapon_key,p,tag)end
                            end
                        end
                    end
                end
                self.phase='FirdPerson native action';return
            end
            native_ads_frames=0
            if self.native_animation then
                -- One native skeleton animates the weapon, hands, twists and
                -- attachments together. No model placement or pose publication.
                release_render()
                if options.fov then
                    if options.fov:is_clean()then assert(options.fov:start(self.native_fov_capture))else assert(options.fov:update(s))end
                end
                self.animation_source='native_third_person'
                self.phase='FirdPerson native animation active';return
            end
            if not current_reference then
                release_render();if options.fov then assert(options.fov:stop())end
                if options.presentation then options.presentation:stop()end
                self.reference_needed=true;self.phase='Fird Person: capture first-person placement for this weapon';return
            end
            self.reference_needed=false
            if options.presentation then
                stage='native first-person presentation'
                local ready,problem
                if options.presentation:is_clean()then ready,problem=options.presentation:start(self.weapon_snapshot)
                else ready,problem=options.presentation:update(self.weapon_snapshot)end
                local presentation_state=options.presentation:result()
                if ready~=true and not options.presentation:is_clean()
                    and presentation_state.phase~='waiting'and presentation_state.phase~='suspended'then
                    error(problem or'Native first-person presentation unavailable')
                end
                if ready~=true or presentation_state.ready~=true then
                    release_render();self.phase='FirdPerson waiting for native first-person attachments';return
                end
            end
            if options.fov then
                if not options.fov:is_clean()and options.fov.lens and math.abs(options.fov.lens-current_reference.projection.fov)>.000001 then assert(options.fov:stop())end
                if options.fov:is_clean()then assert(options.fov:start(current_reference))else assert(options.fov:update(s))end
            end
            render_ready={player_identity=s.player_identity,identity=self.weapon_identity,record=s.record}
            if options.render_driven then
                if not skinned then self.phase='FirdPerson waiting for render' end
                return
            end
            apply_pose(s)
        end,function(problem)return debug.traceback(tostring(problem),2)end)
        if not ok then
            self.last_error_stage,self.last_error=stage,tostring(why)
            self:stop();log('FirdPerson stopped during '..stage..': '..tostring(why));return false,why
        end
        return true
    end
    -- Ownership and camera transitions run in update(). Render only samples
    -- fresh animation data and publishes one coherent model/attachment pose.
    function self:render_pose()
        if self.native_animation then return true end
        if not self.enabled or not render_ready then return true end
        local expected=render_ready
        stage='render ownership'
        local ok,why=xpcall(function()
            local current,s=owned()
            assert(current,'FirdPerson render player/rig generation changed')
            if foreign()or not s.safe or s.camera_kind~=4 or s.controller_active then
                render_ready=nil;return
            end
            local fresh,problem=b:snapshot();assert(fresh,problem or'FirdPerson render weapon unavailable')
            if not fresh.safe or fresh.camera_kind~=4 or fresh.controller_active
                or fresh.player_identity~=expected.player_identity or fresh.identity~=expected.identity
                or fresh.record~=expected.record then render_ready=nil;return end
            self.weapon_snapshot=fresh
            apply_pose(fresh)
            self.render_frames=(self.render_frames or 0)+1
        end,function(problem)return debug.traceback(tostring(problem),2)end)
        if not ok then
            self.last_error_stage,self.last_error=stage,tostring(why)
            self.render_error=tostring(why);render_ready=nil
            -- The next update drains camera/visibility owners. Never acquire
            -- or release a native camera lease from the render callback.
            return false,why
        end
        return true
    end
    return self
end
return M
