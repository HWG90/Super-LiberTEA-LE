local PORT51=mod.require('src/first_person/compat51.lua')
-- Own only camera/shadow pass bits on verified body/customization meshes.
-- The SDK publishes changes; native reads preserve every unrelated pass bit.
local Head={}
local SELECTED={{slot=0,part='head'},{slot=2,part='torso'},
    {slot=8,part='shoulder'},{slot=9,part='shoulder'}}
local PASSES={{mask=1,name='default',visible=false},{mask=2,name='shadow_caster',visible=true}}
local SHADOW_ONLY={{mask=2,name='shadow_caster',visible=false}}
local HIDDEN_NO_SHADOW={{mask=1,name='default',visible=false},{mask=2,name='shadow_caster',visible=false}}
local function passes(row)return row.shadow_only and SHADOW_ONLY or row.shadow_suppressed and HIDDEN_NO_SHADOW or PASSES end
local RIG_RESOURCE='\237\139\160\060\073\077\207\208'
local RIG_PADS={{name='g_l_shoulderpad',hash=0x44E19D12,node=57},{name='g_r_shoulderpad',hash=0xCB0E1712,node=58}}
-- Every owned pass is one bit of an unsigned byte (1 or 2). Avoid the
-- compatibility layer's 32-iteration integer operation for each mesh test.
local function has(value,mask)return value%(mask*2)>=mask end
local function assign(value,mask,on)
    if has(value,mask)==on then return value end
    return value+(on and mask or -mask)
end
local function invoke(object,name,...)
    local ok,a,b=pcall(object[name],object,...);if not ok then return nil,tostring(a)end;return a,b
end
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
function Head.new(backend,log,sr,deps)
    assert(PORT51.kind(backend)=='table','Head visibility backend required')
    deps=deps or {};log=log or function()end
    local memory=deps.memory
    if not memory then
        local ffi=PORT51.ffi
        pcall(ffi.cdef,'uint64_t NADSH_GetTickCount64(void) __asm__("GetTickCount64");')
        local kernel,address=ffi.load('kernel32'),bridge_address()
        memory={read=function(at,n)return backend:_read(at,n)end,
            handle_ref=function(handle)return math.floor(address(handle)/4)end,
            mesh_address=function(handle)return address(handle)end,
            world_address=function(world)return backend:_ptr(address(world))end,
            clock=function()return PORT51.number(kernel.NADSH_GetTickCount64())/1000 end}
    end
    local clock=deps.clock or memory.clock or os.clock
    local function view_snapshot()
        -- The persistent eye camera proves its own player/body independently
        -- of firearm availability and the current gameplay camera request.
        if PORT51.kind(deps.pinned_ready)=='function' and PORT51.kind(backend.pin_player_snapshot)=='function'then
            local s,why=invoke(backend,'pin_player_snapshot')
            if PORT51.kind(s)=='table'then return s end
        end
        return invoke(backend,'player_snapshot')
    end
    local function pinned_ready(s)
        if PORT51.kind(s)~='table' or PORT51.kind(deps.pinned_ready)~='function'then return false end
        local ok,ready=pcall(deps.pinned_ready,s)
        return ok and ready==true
    end
    local self={phase='idle',closing=false,reason=nil,hidden=0,hidden_head=0,hidden_torso=0,hidden_shoulders=0,hidden_body=0,hidden_backpack=0,
        preserved_partial=0,writes=0,restores=0,retired=0,foreign_masks=0}
    local owned,ignored={},{};local identity,observed,steady,handles,cache_world,cache_sdk_world,cache_time,cache_request
    local exe,checked,checked_game,setter,epoch,update_serial=nil,nil,nil,nil,nil,0
    local function report(phase,reason)
        self.phase=phase
        if reason and reason~=self.reason then log('FPV head visibility: '..tostring(reason))end
        self.reason=reason
    end
    local function read(at,n)
        assert(PORT51.kind(at)=='number' and at>=65536 and at+n<2^47 and n>0 and n<=256,'Head visibility read bounds changed')
        local value=memory.read(at,n);assert(PORT51.kind(value)=='string' and #value==n,'Head visibility read unavailable');return value
    end
    local function integer(bytes,offset)
        offset=offset or 0
        local a,b,c,d=bytes:byte(offset+1,offset+4);assert(d,'Customization integer unavailable')
        return a+b*256+c*65536+d*16777216
    end
    local function u32(at)return integer(read(at,4))end
    local function pointer(bytes,offset)
        offset=offset or 0
        local value=integer(bytes,offset)+integer(bytes,offset+4)*4294967296
        assert(value>=65536 and value<2^47,'Head visibility pointer unavailable');return value
    end
    local function ptr(at)
        return pointer(read(at,8))
    end
    local function hex(value)return(value:gsub('%x%x',function(pair)return string.char(PORT51.number(pair,16))end))end
    local function contract(s)
        assert(PORT51.kind(sr)=='table' and sr.Application and sr.World and sr.Unit
            and PORT51.kind(sr.Application.main_world)=='function' and PORT51.kind(sr.World.units)=='function'
            and PORT51.kind(sr.Unit.set_mesh_visibility)=='function','Head mesh SDK unavailable')
        assert(not setter or setter==sr.Unit.set_mesh_visibility or next(owned)==nil,
            'Head mesh SDK binding changed; original restoration remains pending')
        -- The executable and SDK binding are process-lifetime contracts. A
        -- fresh player snapshot supplies any changed module identity; unchanged
        -- frames need neither another executable scan nor another fingerprint.
        if checked and setter==sr.Unit.set_mesh_visibility and s.base==checked_game then return end
        local address=backend:_alignment_executable(backend.profile.pose)
        exe=address
        -- LLL imports SDK functions through a shared C dispatcher. Its Lua
        -- closure address is not the game's setter thunk. Qualify the current
        -- executable directly, retain this SDK function's identity, and use
        -- the same bounded high-level call plus native mask readback below.
        assert(read(exe+0x3f4ca0,8)==hex('488bd1e9a8f8ffff'),'Head mesh visibility binding changed')
        assert(read(exe+0x51fe80,14)==hex('40574883ec30440fb689dc000000'),'Head mesh pass-mask layout changed')
        assert(read(exe+0x3f4c23,24)==hex('3b3d970e48027504b101eb363b3d930e48027504b102eb2a')
            and read(exe+0x51feaa,26)==hex('84d27405450ac8eb0641f6d04522c8488b5908448889dc000000')
            and u32(exe+0x2875ac0)==0xF2760503 and u32(exe+0x2875ac8)==0x3100C3D2,
            'Head camera/shadow visibility contexts changed')
        assert(read(exe+0xa06d0,22)==hex('48895c24084889742410574883ec20488b351270a101'),'Head Unit registry changed')
        checked,checked_game=address,s.base;setter=sr.Unit.set_mesh_visibility;observed=nil
    end
    local function registry()
        local address=ptr(exe+0x1ab76f8);local fields=read(address+0x88,32)
        local capacity=integer(fields,16)
        assert(capacity>0 and capacity<=0x400000,'Head Unit registry capacity changed')
        return {address=address,objects=pointer(fields),capacity=capacity,generations=pointer(fields,24),types={}}
    end
    local function unit(ref,expected,context)
        assert(PORT51.kind(ref)=='number' and ref>0 and ref<4294967295 and ref==math.floor(ref),'Head Unit reference invalid')
        context=context or registry()
        local index=ref%0x400000;local generation=math.floor(ref/0x400000)%256
        assert(index<context.capacity,'Head Unit index changed')
        if read(context.generations+index,1):byte()~=generation then return nil end
        local object=ptr(context.objects+index*8)
        if expected and expected~=object then return nil end
        local header=read(object,32)
        if read(context.generations+index,1):byte()~=generation or ptr(context.objects+index*8)~=object then return nil end
        assert(integer(header,8)==ref,'Head Unit self reference changed')
        local vt=pointer(header)
        if not context.types[vt]then
            local methods=read(vt+0xC8,56)
            assert(pointer(methods,48)==exe+0x28d3e0 and pointer(methods)==exe+0x293600,'Head renderer type changed')
            context.types[vt]=true
        end
        return object,header
    end
    local function mesh_fields(object)
        local fields=read(object+0xC8,16);local count=integer(fields)
        assert(count<=128,'Head mesh count changed')
        return count,count>0 and pointer(fields,8)or nil
    end
    local function mesh_layout(object)
        local count,array=mesh_fields(object);local chunks={}
        for offset=0,count*16-1,256 do chunks[#chunks+1]=read(array+offset,math.min(256,count*16-offset))end
        return {count=count,array=array,bytes=table.concat(chunks)}
    end
    local function index_layout(layout)
        local indices={}
        for index=1,layout.count do
            local mesh=pointer(layout.bytes,(index-1)*16)
            assert(not indices[mesh],'Head mesh object is ambiguous');indices[mesh]=index
        end
        layout.indices=indices;return layout
    end
    -- A layout is observed once per renderer in this operation. Immediate
    -- generation, world, array and slot checks still surround every SDK write.
    local rig_mesh
    local function locate(row,layouts,check_rig)
        local layout=layouts[row.ref]
        local object,header=unit(row.ref,row.object)
        if not object or pointer(header,24)~=row.world then return nil end
        if row.rig and (read(object+0x358,8)~=RIG_RESOURCE
            or check_rig and row.rig_pad and rig_mesh(row.handle,row.rig_pad)~=row.mesh)then return nil end
        assert(memory.handle_ref(row.handle)==row.ref,'Head SDK handle changed')
        local count,array=mesh_fields(object)
        local index=layout and layout.indices[row.mesh]
        if not layout or layout.array~=array or layout.count~=count
            or index and ptr(array+(index-1)*16)~=row.mesh then
            layout=index_layout(mesh_layout(object));layouts[row.ref]=layout;index=layout.indices[row.mesh]
        end
        return index,layout
    end
    local function mask(row)return read(row.mesh+0xDC,1):byte()end
    local function set_pass(row,index,visible,pass)
        assert(sr.Unit and sr.Unit.set_mesh_visibility==row.setter,'Head mesh SDK binding ownership changed')
        row.setter(row.handle,index,visible,pass)
        assert(sr.Unit.set_mesh_visibility==row.setter,'Head mesh SDK binding changed during visibility update')
    end
    rig_mesh=function(handle,pad)
        local present=sr.Unit.has_mesh(handle,pad.name)
        assert(PORT51.kind(present)=='boolean','Named rig shoulder query unavailable')
        if not present then return nil end
        local mesh=assert(sr.Unit.mesh(handle,pad.name),'Named rig shoulder unavailable')
        local name,node,count=sr.Mesh.name(mesh),sr.Mesh.node(mesh),sr.Mesh.num_materials(mesh)
        local material=sr.Mesh.has_material(mesh,'m_armor_standard')
        assert(PORT51.kind(name)=='number' and PORT51.kind(node)=='number' and PORT51.kind(count)=='number' and PORT51.kind(material)=='boolean',
            'Rig shoulder metadata unavailable')
        -- A readable replacement is retired; an unavailable query keeps an old
        -- lease pending rather than restoring into geometry we cannot identify.
        if name%4294967296~=pad.hash or node~=pad.node or count~=1 or not material then return nil end
        local address=memory.mesh_address(mesh)
        assert(PORT51.kind(address)=='number' and address>=65536 and address<2^47,'Rig shoulder address unavailable')
        return address
    end
    local function restore(key,row,layouts,exiting)
        local index=locate(row,layouts,true)
        if not index then self.retired=self.retired+1;owned[key]=nil;return end
        local current=mask(row)
        -- Native exit can publish a complete visible mask after our shadow-only
        -- 0->2 write. That publication supersedes the old visibility lease;
        -- clearing its shadow bit would incorrectly turn TPV255 into253.
        if not row.restoring_default and has(current,1) and not has(row.written,1) and (current==255
            or exiting and exiting.camera_kind==4 and exiting.player_identity==row.owner
                and exiting.body==row.body_ref)then owned[key]=nil;return end
        local problem
        for _,pass in ipairs(passes(row))do if has(row.bits,pass.mask)then
            local ok,why=pcall(function()
                index=assert(locate(row,layouts,true),'Head mesh retired during restore')
                local before=mask(row)
                if has(before,pass.mask)~=has(row.written,pass.mask)then
                    self.foreign_masks=self.foreign_masks+1
                    ignored[key]=assign(ignored[key]or 0,pass.mask,true)
                else
                    if pass.mask==1 and has(row.before,1)then row.restoring_default=true end
                    set_pass(row,index,has(row.before,pass.mask),pass.name)
                    assert(locate(row,layouts,true) and mask(row)==assign(before,pass.mask,has(row.before,pass.mask)),
                        'Head mesh pass restore readback failed')
                    self.restores=self.restores+1
                end
                row.bits=assign(row.bits,pass.mask,false)
            end)
            if not ok then problem=tostring(why)end
        end end
        if row.bits==0 then owned[key]=nil end
        assert(not problem,problem)
    end
    local function count()
        local total,head,torso,shoulder,body,backpack,shadows=0,0,0,0,0,0,0
        for _,row in pairs(owned)do
            total=total+1
            if row.shadow_suppressed and has(row.bits,2)then shadows=shadows+1 end
            if row.shadow_only then
            elseif row.part=='torso'then torso=torso+1 elseif row.part=='shoulder'then shoulder=shoulder+1
            elseif row.part=='body'then body=body+1 elseif row.part=='backpack'then backpack=backpack+1 else head=head+1 end
        end
        self.hidden,self.hidden_head,self.hidden_torso,self.hidden_shoulders,self.hidden_body,self.hidden_backpack=total,head,torso,shoulder,body,backpack;self.shadows_disabled=shadows;return total
    end
    function self:is_clean()return next(owned)==nil end
    function self:stop()
        steady=nil
        local reason;local layouts={};local exiting
        if next(owned)then exiting=view_snapshot()end
        for key,row in pairs(owned)do local ok,why=pcall(restore,key,row,layouts,exiting);if not ok then reason=tostring(why)end end
        if count()>0 then report('cleanup_pending',reason or 'Head mesh restoration pending');return false,self.reason end
        identity,observed,ignored,epoch=nil,nil,{},nil;report('idle');return true
    end
    function self:shutdown()self.closing=true;return self:stop()end
    -- Immutable signature already validated by this manager's current update.
    -- Consumers must retain their own generation guards for SDK handles.
    function self:render_appearance()
        if observed then return observed.appearance,observed.owner,observed.world end
    end
    function self:result()
        local total=count()
        return {phase=self.phase,hidden=total,hidden_head=self.hidden_head,hidden_torso=self.hidden_torso,
            hidden_shoulders=self.hidden_shoulders,hidden_body=self.hidden_body,hidden_backpack=self.hidden_backpack,
            preserved_partial=self.preserved_partial,writes=self.writes,restores=self.restores,retired=self.retired,
            foreign_masks=self.foreign_masks,cleanup_pending=self.phase=='cleanup_pending',error_message=self.reason,
            model_shadow_error=self.model_shadow_error,shadows_disabled=self.shadows_disabled,
            steady_observations=self.steady_observations or 0,full_observations=self.full_observations or 0}
    end
    function self:status()
        count();return self.phase..'; owned head/torso/shoulder/body passes='..self.hidden_head..'/'..self.hidden_torso
            ..'/'..self.hidden_shoulders..'/'..self.hidden_body..'; '..tostring(self.reason or '')
    end
    local function foreign()
        if PORT51.kind(backend.foreign_camera)~='function'then return false end
        local ok,value=pcall(backend.foreign_camera);return not ok or value~=false
    end
    local function available(s)
        return PORT51.kind(s)=='table' and PORT51.kind(s.player_identity)=='string' and s.player_identity~=''
            and (pinned_ready(s) or (s.camera_kind==4 or s.camera_kind==6) and not s.seated
                and (s.safe or s.weapon_transition or s.head_camera_transition))
    end
    local function first_person(s)
        if pinned_ready(s)then return true end
        if s.camera_kind==6 then return true end
        if PORT51.kind(deps.fallback_ready)~='function'then return false end
        local ok,ready=pcall(deps.fallback_ready,s)
        if not ok or ready~=true then return false end
        -- Helper statistics may precede a new death/action state by one frame.
        -- Require a fresh positive body state before hiding head meshes in4.
        local state=invoke(backend,'action_state',s)
        return PORT51.kind(state)=='table' and state.owner==s.player_identity and state.body==s.body
            and invoke(backend,'on_foot',s,state)==true
    end
    local function collect(ref,spec,s,context,body,body_header,world_native,base,unchanged)
        local object,header
        if spec.body_only then object,header=body,body_header else object,header=unit(ref,nil,context)end
        assert(object,'Head customization generation retired')
        assert(pointer(header,24)==world_native and (spec.body_only and object==body
            or spec.rig and ref==s.viewmodel or spec.model_shadow and ptr(object+0x1D0)==spec.model_parent
            or not spec.body_only and not spec.rig and not spec.model_shadow and ptr(object+0x1D0)==body),
            'Head customization attachment changed')
        local handle=assert(handles[ref],'Head SDK Unit handle unavailable')
        assert(memory.handle_ref(handle)==ref,'Head SDK handle changed')
        local resource=spec.rig and read(object+0x358,8)or nil
        local layout=spec.rig and resource~=RIG_RESOURCE and {count=0,bytes='',indices={}}or mesh_layout(object)
        local old=unchanged and spec.layout
        local same=old and spec.object==object and spec.resource==resource
            and old.count==layout.count and old.array==layout.array and old.bytes==layout.bytes
        if same then layout=old end
        if same and spec.retry then
            local now=clock()
            if now>=spec.retry-.5 and now<spec.retry then return layout,false end
        end
        local changed=not same or spec.retry~=nil
        if not same or spec.retry then
            if not same then layout=index_layout(layout)end
            -- A weapon-tree change can rebuild specs while these renderers
            -- remain unchanged. Keep their last observation even when they
            -- own no bits, so a foreign pass change is not mistaken for an
            -- unseen native baseline. This history cannot authorize a write.
            local previous=observed and observed.owner==s.player_identity and observed.body_ref==s.body
                and observed.body==body and observed.world==world_native and observed.customization==base
                and observed.refs[ref]
            local history=previous and previous.rows
            spec.rows={};spec.layout,spec.object,spec.resource=layout,object,resource
            spec.retry=nil
            local selected
            if spec.rig and resource==RIG_RESOURCE then
                assert(layout.count==5,'Known rig shoulder layout changed');selected={}
                for _,pad in ipairs(RIG_PADS)do
                    local mesh=assert(rig_mesh(handle,pad),'Rig shoulder mesh identity changed')
                    assert(layout.indices[mesh] and not selected[mesh],'Named shoulder is not a unique current rig mesh')
                    selected[mesh]=pad
                end
            end
            for mesh in pairs(layout.indices)do
                if not spec.rig or spec.shadow_rig or selected and selected[mesh]then
                    local key=tostring(ref)..':'..tostring(mesh)
                    local earlier=history and history[key]
                    if earlier and(earlier.owner~=s.player_identity or earlier.body_ref~=s.body
                        or earlier.handle~=handle or earlier.setter~=setter or earlier.part~=spec.part)then earlier=nil end
                    local existing=owned[key]or earlier
                    local shadow_suppressed=spec.shadow_rig==true or spec.model_shadow==true
                    local shadow_only=spec.model_shadow==true or spec.shadow_rig==true and not(selected and selected[mesh])
                    local row=existing and existing.object==object and existing.body_object==body
                        and existing.shadow_suppressed==shadow_suppressed and existing.shadow_only==shadow_only
                        and existing.model_parent==spec.model_parent and existing or
                        {ref=ref,object=object,world=world_native,handle=handle,mesh=mesh,bits=0,before=0,written=0,setter=setter,
                            body_ref=s.body,body_object=body,customization=base,owner=s.player_identity}
                    row.offsets,row.part,row.body_only,row.rig=spec.offsets,spec.part,spec.body_only,spec.rig
                    row.backpack=spec.backpack
                    row.rig_pad=selected and selected[mesh]
                    row.shadow_suppressed=shadow_suppressed
                    row.shadow_only=shadow_only
                    row.model_owner,row.model_parent=spec.model_owner,spec.model_parent
                    spec.rows[key]=row
                end
            end
        end
        for _,row in pairs(spec.rows)do row.current=mask(row)end
        return layout,changed
    end
    local function inventory(world,refs)
        local list=sr.World.units(world);assert(PORT51.kind(list)=='table' and #list<=131072,'Head SDK Unit inventory unavailable')
        local found={}
        for _,handle in ipairs(list)do
            local ok,ref=pcall(memory.handle_ref,handle)
            if ok and refs[ref]then
                if found[ref]~=nil then
                    assert(refs[ref].rig,'Head SDK Unit reference is ambiguous');found[ref]=false
                else found[ref]=handle end
            end
        end
        return found
    end
    local function resolve(s,refresh)
        contract(s)
        local context=registry()
        local body,header=unit(s.body,nil,context);assert(body,'Head body generation retired')
        local world_native=pointer(header,24)
        local world=sr.Application.main_world();assert(world and memory.world_address(world)==world_native,'Head SDK world changed')
        assert(PORT51.kind(s.avatar_index)=='number' and s.avatar_index>=0 and s.avatar_index<8,'Head avatar index changed')
        local base=s.avatar_owner+0x546ab0+s.avatar_index*0x1B8
        local appearance=read(base+0xDC,120)
        local full_body=deps.full_body and deps.full_body()==true or false
        local hide_torso=deps.hide_torso and deps.hide_torso()==true or false
        local models,model_signature
        if not full_body and deps.model_shadows then
            models,model_signature=deps.model_shadows:probe(s,appearance)
            self.model_shadow_error=not models and model_signature or nil
        else self.model_shadow_error=nil end
        local kept_slots=full_body and hide_torso and{3,4,5,6,7,8,9}or{3,4,5,6,7}
        local rig_capable=PORT51.kind(memory.mesh_address)=='function' and PORT51.kind(sr.Unit.has_mesh)=='function'
            and PORT51.kind(sr.Unit.mesh)=='function' and PORT51.kind(sr.Mesh)=='table' and PORT51.kind(sr.Mesh.name)=='function'
            and PORT51.kind(sr.Mesh.node)=='function' and PORT51.kind(sr.Mesh.num_materials)=='function' and PORT51.kind(sr.Mesh.has_material)=='function'
        local backpack
        if PORT51.kind(backend.backpack)=='function' then backpack=invoke(backend,'backpack',s) end
        local pack_identity=backpack and backpack.identity
        local previous=observed
        local unchanged=previous and previous.owner==s.player_identity and previous.body==body and previous.body_ref==s.body
            and previous.world==world_native and previous.sdk_world==world and previous.customization==base
            and previous.pack_identity==pack_identity and previous.appearance==appearance and previous.viewmodel==s.viewmodel and previous.rig_capable==rig_capable
            and previous.full_body==full_body
            and previous.hide_torso==hide_torso
            and previous.model_signature==model_signature
        local refs=unchanged and previous.refs or {};local changed=not unchanged or refresh==true
        if not unchanged then
            for layer=0,2 do
                for _,spec in ipairs(SELECTED)do
                    if not full_body or spec.part=='head'or hide_torso and spec.part=='torso'then
                    local offset=layer*40+spec.slot*4;local ref=integer(appearance,offset)
                    if ref~=0 and ref~=4294967295 then
                        assert(ref~=s.body and ref~=s.viewmodel,'Customization reference overlaps player rig')
                        assert(not refs[ref] or refs[ref].part==spec.part,'Head and torso share an ambiguous renderer')
                        refs[ref]=refs[ref] or {part=spec.part,offsets={}}
                        refs[ref].offsets[#refs[ref].offsets+1]=0xDC+offset
                    end
                    end
                end
            end
            -- Never hide a combined renderer which also contains a kept limb.
            for layer=0,2 do for _,slot in ipairs(kept_slots)do
                local ref=integer(appearance,layer*40+slot*4)
                if full_body and hide_torso and refs[ref]and refs[ref].part=='torso'then refs[ref]=nil end
                assert(not refs[ref],'Selected customization renderer is shared with kept clothing')
            end end
            if full_body and hide_torso and backpack and refs[backpack.ref]and refs[backpack.ref].part=='torso'then
                refs[backpack.ref]=nil
            end
            if backpack and not full_body then
                assert(not refs[backpack.ref],'Backpack overlaps customization renderer')
                refs[backpack.ref]={part='backpack',backpack=pack_identity,offsets={}}
            end
            refs[s.body]={part='body',body_only=true,offsets={}}
            if not full_body and rig_capable and PORT51.kind(s.viewmodel)=='number' and s.viewmodel>0 and s.viewmodel<4294967295
                and s.viewmodel==math.floor(s.viewmodel) and s.viewmodel~=s.body then
                refs[s.viewmodel]={part='shoulder',rig=true,offsets={}}
            end
            for ref,spec in pairs(models or{})do
                assert(not refs[ref]or refs[ref].rig,'First-person shadow target overlaps hidden clothing')
                refs[ref]=spec
            end
        end
        if cache_world~=world_native or cache_sdk_world~=world then
            handles={};cache_world,cache_sdk_world,cache_request,cache_time=world_native,world,nil,nil
        end
        local missing,required_missing=false,false;local requested={}
        for ref,spec in pairs(refs)do
            requested[#requested+1]=ref
            if not handles[ref] or memory.handle_ref(handles[ref])~=ref then
                missing=true;required_missing=required_missing or not spec.rig
            end
        end
        -- No public Unit-created event exists here. Enumerate only on a missing
        -- required handle; a failed, unchanged request retries at most twice/sec.
        if missing then
            table.sort(requested);local request=table.concat(requested,':')
            local timestamp=clock();assert(PORT51.kind(timestamp)=='number' and timestamp==timestamp and math.abs(timestamp)<math.huge,'Head visibility clock unavailable')
            local due=cache_request~=request or not cache_time or timestamp<cache_time or timestamp-cache_time>=.5
            assert(due or not required_missing,'Head SDK Unit handle refresh pending')
            if due then
                cache_request,cache_time=request,timestamp
                local ok,found=pcall(inventory,world,refs)
                if ok then handles=found else assert(not required_missing,found)end
            end
        end
        local wanted,layouts={},{};local partial=0
        for ref,spec in pairs(refs)do
            local layout,dirty
            if spec.rig then
                -- The FPV rig may be absent during a weapon gap, or use an
                -- unsupported armor layout. It is optional; verified body and
                -- clothing passes keep working independently of its metadata.
                local ok,a,b=pcall(collect,ref,spec,s,context,body,header,world_native,base,unchanged)
                if ok then layout,dirty=a,b else spec.rows={};spec.retry=clock()+.5 end
            else layout,dirty=collect(ref,spec,s,context,body,header,world_native,base,unchanged)end
            if layout then
                changed=changed or dirty;layouts[ref]=layout
                for key,row in pairs(spec.rows)do wanted[key]=row end
            end
        end
        local kept_layouts=previous and previous.kept_layouts or{}
        if changed then
            kept_layouts={}
            local kept={}
            local function keep(ref)
                if ref~=0 and ref~=4294967295 and not kept[ref]then
                    local object,part_header=unit(ref,nil,context);assert(object,'Kept limb generation retired')
                    local parent=ptr(object+0x1D0)
                    if parent~=body then
                        local rig,rig_header=unit(s.viewmodel,nil,context)
                        assert(rig and parent==rig and pointer(rig_header,24)==world_native,'Kept limb rig attachment changed')
                    end
                    assert(pointer(part_header,24)==world_native,'Kept limb world changed')
                    local layout=mesh_layout(object);kept[ref]=true
                    kept_layouts[ref]={object=object,parent=parent,layout=layout}
                    for i=1,layout.count do kept[pointer(layout.bytes,(i-1)*16)]=true end
                end
            end
            for layer=0,2 do for _,slot in ipairs(kept_slots)do keep(integer(appearance,layer*40+slot*4))end end
            if full_body and hide_torso and backpack then keep(backpack.ref)end
            for key,row in pairs(wanted)do
                if kept[row.mesh]and full_body and hide_torso and row.part=='torso'then
                    -- A combined torso/limb mesh cannot be hidden selectively.
                    -- Remove its cached row too, so unchanged frames keep it.
                    wanted[key]=nil;refs[row.ref].rows[key]=nil
                elseif not row.shadow_only then assert(not kept[row.mesh],'Selected mesh is shared with kept clothing')end
            end
            local after,why=view_snapshot();assert(available(after) and after.player_identity==s.player_identity,why or 'Head player changed during observation')
            assert(unit(s.body,body)==body and not foreign() and first_person(after),'Head owner or first-person camera changed during observation')
            assert(read(base+0xDC,120)==appearance,'Customization changed during observation')
        end
        observed={owner=s.player_identity,body=body,body_ref=s.body,world=world_native,sdk_world=world,
            customization=base,appearance=appearance,pack_identity=pack_identity,viewmodel=s.viewmodel,rig_capable=rig_capable,
            full_body=full_body,hide_torso=hide_torso,refs=refs,kept_layouts=kept_layouts}
        observed.model_signature=model_signature
        self.preserved_partial=partial
        return wanted,layouts
    end
    local function new_epoch(s)
        local changed=not epoch or epoch.owner~=s.player_identity or epoch.kind~=s.camera_kind or epoch.record~=s.record
            or epoch.head~=s.head or epoch.tail~=s.tail or epoch.weapon~=s.request_weapon
            or epoch.ads~=(s.controller_active==true) or epoch.aim~=(s.aiming==true)
        if changed then
            epoch=epoch or {};epoch.owner,epoch.kind,epoch.record=s.player_identity,s.camera_kind,s.record
            epoch.head,epoch.tail,epoch.weapon=s.head,s.tail,s.request_weapon
            epoch.ads,epoch.aim=s.controller_active==true,s.aiming==true
            epoch.serial=(epoch.serial or 0)+1;epoch.started=clock()
        end
        return changed
    end
    local function native_reset(row,current,pass)
        if not epoch or (current~=0 and current~=1 and current~=254 and current~=255)then return false end
        local now=clock();if now<epoch.started or now-epoch.started>.25 then return false end
        if row.reset_epoch~=epoch.serial then row.reset_epoch,row.reset_bits=epoch.serial,0 end
        local field=pass.mask==1 and 'reset_default_frame' or 'reset_shadow_frame'
        if has(row.reset_bits,pass.mask)then return row[field]==update_serial end
        row[field]=update_serial
        row.reset_bits=assign(row.reset_bits,pass.mask,true);return true
    end
    local function same_epoch(s)
        return epoch and epoch.owner==s.player_identity and epoch.kind==s.camera_kind and epoch.record==s.record
            and epoch.head==s.head and epoch.tail==s.tail and epoch.weapon==s.request_weapon
            and epoch.ads==(s.controller_active==true)and epoch.aim==(s.aiming==true)
    end
    local function bindings()
        return {sr.Application,sr.Application.main_world,sr.World,sr.World.units,sr.Unit,sr.Unit.set_mesh_visibility,
            sr.Unit.has_mesh,sr.Unit.mesh,sr.Mesh,sr.Mesh and sr.Mesh.name,sr.Mesh and sr.Mesh.node,
            sr.Mesh and sr.Mesh.num_materials,sr.Mesh and sr.Mesh.has_material,memory.handle_ref,memory.mesh_address,
            memory.world_address,backend.player_snapshot,backend.pin_player_snapshot,backend.backpack,backend.foreign_camera}
    end
    local function retain_steady(s,wanted,layouts)
        steady=nil
        local models=deps.model_shadows
        if s.camera_kind~=6 or s.safe~=true or PORT51.kind(s.flags)~='string'or #s.flags~=24
            or not observed or observed.full_body or self.model_shadow_error
            or not models or PORT51.kind(models.unchanged)~='function' or PORT51.kind(models.has_observation)~='function'
            or not models:has_observation()then return end
        local shapes={}
        for ref,spec in pairs(observed.refs)do
            if spec.retry or not spec.layout or spec.layout~=layouts[ref]then return end
            shapes[ref]={object=spec.object,layout=spec.layout,rig=spec.rig,
                parent=not spec.body_only and not spec.rig and(spec.model_parent or observed.body)or nil}
        end
        for ref,kept in pairs(observed.kept_layouts)do
            local old=shapes[ref]
            if old then
                if old.object~=kept.object or old.layout.count~=kept.layout.count
                    or old.layout.array~=kept.layout.array or old.layout.bytes~=kept.layout.bytes then return end
            else shapes[ref]={object=kept.object,parent=kept.parent,layout=kept.layout}end
        end
        for _,row in pairs(wanted)do if row.last==nil then return end end
        -- Resource bytes and handles are cached as values only. A later
        -- matching observation cannot authorize even one SDK pass write.
        for ref,shape in pairs(shapes)do
            shape.resource=read(shape.object+0x358,8)
            shape.handle=handles[ref]
        end
        steady={observed=observed,wanted=wanted,layouts=layouts,shapes=shapes,models=models,bindings=bindings(),flags=s.flags}
    end
    local function observe_steady(s)
        local saved=assert(steady)
        assert(saved.observed==observed and s.safe==true and s.camera_kind==6 and same_epoch(s)and s.flags==saved.flags
            and observed.owner==s.player_identity and observed.body_ref==s.body and observed.viewmodel==s.viewmodel
            and observed.customization==s.avatar_owner+0x546ab0+s.avatar_index*0x1B8
            and not(deps.full_body and deps.full_body()==true)
            and observed.hide_torso==(deps.hide_torso and deps.hide_torso()==true or false)
            and deps.model_shadows==saved.models,'Head steady owner changed')
        local current_bindings=bindings()
        for i=1,20 do assert(current_bindings[i]==saved.bindings[i],'Head steady SDK binding changed')end
        contract(s)
        local context=registry();local objects={}
        local function inspect(ref,expected)
            local found=objects[ref]
            if not found then
                local object,header=unit(ref,expected,context);assert(object,'Head steady generation retired')
                found={object=object,header=header};objects[ref]=found
            end
            assert(not expected or expected==found.object,'Head steady object changed')
            return found.object,found.header
        end
        local body,header=inspect(s.body,observed.body)
        assert(pointer(header,24)==observed.world,'Head steady body world changed')
        local world=sr.Application.main_world()
        assert(world==observed.sdk_world and memory.world_address(world)==observed.world,'Head steady scene changed')
        local base=observed.customization;local appearance=read(base+0xDC,120)
        assert(appearance==observed.appearance,'Head steady appearance changed')
        local pack,problem
        if PORT51.kind(backend.backpack)=='function'then pack,problem=invoke(backend,'backpack',s)end
        assert(not problem and(pack and pack.identity)==observed.pack_identity,'Head steady backpack changed')
        assert(saved.models:unchanged(s,appearance,inspect),'Head steady model topology changed')
        for ref,shape in pairs(saved.shapes)do
            local object,part_header=inspect(ref,shape.object)
            assert(pointer(part_header,24)==observed.world and read(object+0x358,8)==shape.resource
                and(not shape.parent or ptr(object+0x1D0)==shape.parent),'Head steady renderer changed')
            local layout=mesh_layout(object);local old=shape.layout
            assert(layout.count==old.count and layout.array==old.array and layout.bytes==old.bytes,'Head steady mesh membership changed')
            if shape.handle then assert(handles[ref]==shape.handle and memory.handle_ref(shape.handle)==ref,'Head steady handle changed')end
        end
        for _,row in pairs(saved.wanted)do assert(mask(row)==row.last,'Head steady native pass changed')end
        -- Close player, appearance and registry ownership after the bounded
        -- read. No saved proof survives into a native/SDK mutation path.
        local after=assert(view_snapshot())
        assert(available(after)and after.safe==true and after.camera_kind==6 and first_person(after)
            and after.player_identity==s.player_identity and after.body==s.body and after.viewmodel==s.viewmodel and after.flags==s.flags
            and same_epoch(after)and not foreign(),'Head steady player changed during observation')
        assert(read(base+0xDC,120)==appearance,'Head steady appearance changed during observation')
        local closing=registry()
        assert(closing.address==context.address and closing.objects==context.objects
            and closing.generations==context.generations and closing.capacity==context.capacity,
            'Head steady registry changed during observation')
        for ref,row in pairs(objects)do
            local index=ref%0x400000;local generation=math.floor(ref/0x400000)%256
            assert(read(context.generations+index,1):byte()==generation and ptr(context.objects+index*8)==row.object,
                'Head steady generation changed during observation')
        end
        return true
    end
    function self:update(controller)
        if self.phase=='cleanup_pending'then return self:stop()end
        local result=controller:result()
        if self.closing or not controller:is_enabled() or result.mode~='pose_offset' or foreign()then return self:stop()end
        local s,why=view_snapshot()
        if not available(s) or not first_person(s)then return self:stop()end
        if identity and identity~=s.player_identity then local done,reason=self:stop();if not done then return false,reason end end
        local refresh=false
        if steady then
            local same=pcall(observe_steady,s)
            if same then
                self.steady_observations=(self.steady_observations or 0)+1
                count();report('active');return true
            end
            -- Any unreadable/changed fingerprint immediately takes the full
            -- observation path, including newly linked formerly-empty leaves.
            -- Retain row.last / ignored bits for foreign-mask arbitration.
            -- A forced full observation refreshes kept membership without
            -- erasing the ownership history of unchanged mesh objects.
            steady=nil;refresh=true
        end
        self.full_observations=(self.full_observations or 0)+1
        local ok,wanted,layouts=pcall(resolve,s,refresh)
        if not ok then
            local restored,reason=self:stop();if not restored then return false,reason end
            report('unavailable',tostring(wanted));return true,self.reason
        end
        identity=s.player_identity
        update_serial=update_serial+1
        local rebaseline=new_epoch(s)
        if rebaseline then ignored={} end
        local applied,problem=pcall(function()
            for key,row in pairs(owned)do if wanted[key]~=row then
                restore(key,row,layouts)
                if wanted[key]then wanted[key].current=mask(wanted[key])end
            end end
            for key,row in pairs(wanted)do
                local current=row.current
                if row.last~=nil and current==255 and not has(row.last,1)then
                    row.bits=0;owned[key]=nil -- Complete native/foreign visibility supersedes the old cohort.
                    if not native_reset(row,current,PASSES[1])then ignored[key]=row.shadow_suppressed and 1 or 3 end
                end
                for _,pass in ipairs(passes(row))do
                    local targeted=not row.body_only or pass.mask==2
                    if targeted and has(current,pass.mask)~=pass.visible and (has(row.bits,pass.mask)
                        or row.last~=nil and has(row.last,pass.mask)==pass.visible)then
                        row.bits=assign(row.bits,pass.mask,false)
                        if not(row.shadow_suppressed and pass.mask==2)and not native_reset(row,current,pass)then
                            self.foreign_masks=self.foreign_masks+1
                            ignored[key]=assign(ignored[key]or 0,pass.mask,true)
                        end
                    end
                end
                if row.bits==0 then owned[key]=nil end
                for _,pass in ipairs(passes(row))do
                    local desired=not row.body_only or pass.mask==2
                    if desired and has(current,pass.mask)~=pass.visible and not has(row.bits,pass.mask)
                        and not has(ignored[key]or 0,pass.mask)then
                    assert(unit(row.body_ref,row.body_object)==row.body_object
                        and (row.body_only or row.rig or row.model_owner and ptr(row.object+0x1D0)==row.model_parent
                            or not row.model_owner and ptr(row.object+0x1D0)==row.body_object) and not foreign(),
                        'Head owner changed before hide')
                    local present=row.body_only
                    if row.backpack then
                        local pack=invoke(backend,'backpack',s)
                        assert(pack and pack.ref==row.ref and pack.identity==row.backpack,'Backpack changed before pass update')
                        present=true
                    end
                    if row.rig then
                        assert(row.ref==s.viewmodel and read(row.object+0x358,8)==RIG_RESOURCE
                            and(not row.rig_pad or rig_mesh(row.handle,row.rig_pad)==row.mesh),'Owned rig shoulder changed before pass update')
                        present=true
                    end
                    if row.model_owner then
                        assert(deps.model_shadows and deps.model_shadows:valid(s,row.model_owner),
                            'First-person shadow owner changed before pass update')
                        present=true
                    end
                    for _,offset in ipairs(row.offsets)do if u32(row.customization+offset)==row.ref then present=true end end
                    local index=assert(locate(row,layouts),'Head mesh retired before hide')
                    assert(present and mask(row)==current,'Head customization changed before pass update')
                    row.before=assign(row.before,pass.mask,has(current,pass.mask))
                    row.written=assign(current,pass.mask,pass.visible)
                    if pass.mask==1 then row.restoring_default=nil end
                    row.bits=assign(row.bits,pass.mask,true);owned[key]=row -- Retain uncertain SDK outcomes before calling it.
                    set_pass(row,index,pass.visible,pass.name)
                    self.writes=self.writes+1
                    assert(locate(row,layouts) and mask(row)==row.written,'Head mesh pass update readback failed')
                    current=row.written;row.current=current
                    end
                end
                row.last=current
            end
        end)
        if not applied then
            local restored,reason=self:stop();if not restored then return false,reason end
            report('unavailable',tostring(problem));return true,self.reason
        end
        count();report('active')
        local cached=pcall(retain_steady,s,wanted,layouts);if not cached then steady=nil end
        return true
    end
    return self
end
return Head
