local PORT51=mod.require('src/first_person/compat51.lua')
-- Placement belongs on the linked render skeleton, not the animated body or
-- mesh anchor. Mesh skin bindings select these nodes directly (512b80/5b2990).
local M={}
local function close(a,b)
    return a and b and math.abs(a[1]-b[1])+math.abs(a[2]-b[2])+math.abs(a[3]-b[3])<.00001
end
local function sameq(a,b)
    if not a or not b then return false end
    local dot=0;for i=1,4 do dot=dot+a[i]*b[i]end
    return math.abs(math.abs(dot)-1)<.000001
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
function M.new(b,sr,cal,parts)
    local U,V,Q,A=sr.Unit,sr.Vector3,sr.Quaternion,sr.Matrix4x4
    local address=bridge_address()
    if b._alignment_executable then
        local exe=b:_alignment_executable()
        assert(b:_read(exe+0x523310,16)=='\064\085\087\072\141\108\036\168\072\129\236\088\001\000\000\072','Skinning palette builder changed')
    end
    local function point(v)return{V.x(v),V.y(v),V.z(v)}end
    local position_buffer=PORT51.ffi.new('float[3]')
    local rotation_buffer=PORT51.ffi.new('float[4]')
    local function quantized_position(values)
        for i=1,3 do position_buffer[i-1]=values[i]end
        return {PORT51.number(position_buffer[0]),PORT51.number(position_buffer[1]),PORT51.number(position_buffer[2])}
    end
    local function quantized_rotation(values)
        for i=1,4 do rotation_buffer[i-1]=values[i]end
        return {PORT51.number(rotation_buffer[0]),PORT51.number(rotation_buffer[1]),
            PORT51.number(rotation_buffer[2]),PORT51.number(rotation_buffer[3])}
    end
    local function same_target_rotation(a,b)
        a,b=quantized_rotation(a),quantized_rotation(b)
        local same,opposite=true,true
        for i=1,4 do same=same and a[i]==b[i];opposite=opposite and a[i]==-b[i]end
        return same or opposite
    end
    local function vec(v)return V(v[1],v[2],v[3])end
    local function quat(v)return Q.from_elements(unpack(v))end
    local function ptr0(at)return b:_u32(at)+b:_u32(at+4)*4294967296 end
    local function relative_bound(values,reason)
        local length=0
        for _,value in ipairs(values)do assert(value==value and math.abs(value)<=2,reason);length=length+value*value end
        assert(length<=4,reason)
    end
    local function finite(value)return type(value)=='number'and value==value and math.abs(value)<math.huge end
    local function copied_parent(frames,node,count)
        assert(type(frames)=='table'and #frames==count and count>0 and count<=256,'Copied render parent count changed')
        local frame=assert(frames[node],'Copied render parent is missing')
        assert(type(frame)=='table'and frame.node==node and type(frame.position)=='table'
            and type(frame.rotation)=='table'and type(frame.scale)=='table'and type(frame.basis)=='table',
            'Copied render parent frame is invalid')
        local position,scale,rotation={},{},{}
        for i=1,3 do
            assert(finite(frame.position[i])and math.abs(frame.position[i])<1e6,'Copied render parent position is invalid')
            assert(finite(frame.scale[i])and frame.scale[i]>.00001 and frame.scale[i]<1e4,'Copied render parent scale is invalid')
            position[i],scale[i]=frame.position[i],frame.scale[i]
        end
        local norm=0
        for i=1,4 do assert(finite(frame.rotation[i]),'Copied render parent orientation is invalid');norm=norm+frame.rotation[i]^2 end
        assert(math.abs(norm-1)<.002,'Copied render parent orientation is not normalized')
        norm=math.sqrt(norm);for i=1,4 do rotation[i]=frame.rotation[i]/norm end
        local x,y,z,w=unpack(rotation)
        local axes={{1-2*(y*y+z*z),2*(x*y+z*w),2*(x*z-y*w)},
            {2*(x*y-z*w),1-2*(x*x+z*z),2*(y*z+x*w)},
            {2*(x*z+y*w),2*(y*z-x*w),1-2*(x*x+y*y)}}
        for axis=1,3 do
            assert(type(frame.basis[axis])=='table','Copied render parent basis is missing')
            for i=1,3 do
                local value=frame.basis[axis][i]
                assert(finite(value)and math.abs(value/scale[axis]-axes[axis][i])<.004,
                    'Copied render parent basis differs from its orientation or scale')
            end
        end
        local q=quat(rotation)
        return{frames=frames,position=position,scale=scale,q=q,inverse_q=Q.inverse(q)}
    end
    local function forward(parent,value)
        if not parent.frames then return A.transform(parent.world,value)end
        local p=point(value)
        p=point(Q.rotate(parent.q,V(p[1]*parent.scale[1],p[2]*parent.scale[2],p[3]*parent.scale[3])))
        return V(p[1]+parent.position[1],p[2]+parent.position[2],p[3]+parent.position[3])
    end
    local function backward(parent,value)
        if not parent.frames then return A.transform(parent.inverse,value)end
        local p=point(value)
        p=point(Q.rotate(parent.inverse_q,V(p[1]-parent.position[1],p[2]-parent.position[2],p[3]-parent.position[3])))
        return V(p[1]/parent.scale[1],p[2]/parent.scale[2],p[3]/parent.scale[3])
    end
    local groups={};local self={writes=0,coalesced=0,nodes=0,publishes=0}
    local function graph_valid(g)
        if not g.part.valid()then return false end
        local source=ptr0(g.parent_context.object+0x88)
        return source~=0 and ptr0(g.ctx.object+0x98)==g.links
            and ptr0(g.ctx.object+0xa0)==g.hashes and ptr0(g.ctx.object+0x78)==source
    end
    for _,part in ipairs(parts)do
        local ctx=assert(part.context,'Render placement context missing')
        local count=b:_u32(ctx.object+0x70);assert(count>0 and count<=256,'Render node count changed')
        local g={part=part,ctx=ctx,links=b:_ptr(ctx.object+0x98),hashes=b:_ptr(ctx.object+0xa0),rows={},
            parent_context=part.parent_context or cal.body_context,parent_handle=part.parent_handle or cal.body}
        assert(graph_valid(g),'Render skeleton ownership changed')
        -- Arm clothing has no blender: parent body animation supplies its pose.
        -- Weapons may animate their internal nodes; only their external roots
        -- are edited, leaving those internal animation channels untouched.
        assert(part.group=='weapon' or ptr0(ctx.object+0x168)==0,'Arm renderer has its own animation writer')
        local parent_nodes=b:_u32(g.parent_context.object+0x70)
        g.parent_nodes=parent_nodes
        local selected={}
        local function include(node)
            for depth=1,count do
                assert(node>=0 and node<count,'Skinning node out of range')
                local link=b:_u32(g.links+node*4);local flag,parent=link%65536,math.floor(link/65536)
                if flag==2 then
                    assert(parent<parent_nodes,'External skinning parent changed')
                    selected[node]={parent=parent,link=link};return
                end
                if flag==0 then
                    -- Native FP arm skins retain two unlinked auxiliary roots.
                    -- Their SDK locals are absolute world poses; high16 is a
                    -- stale former parent, not a live hierarchy index.
                    local hash=b:_u32(g.hashes+node*4)
                    assert(part.group~='weapon'and parent_nodes==63
                        and(hash==0x58D886FB or hash==0x5A4BBAA2),'Unverified world-space skinning root')
                    selected[node]={world=true,link=link};return
                end
                assert(flag==1 and parent~=node,'Skinning node is not linked to an owned animation source')
                node=parent
            end
            error('Skinning hierarchy cycle')
        end
        local meshes=U.num_meshes(part.handle);assert(meshes<=128,'Render mesh count changed')
        for i=1,meshes do
            local mesh=U.mesh(part.handle,i);local p=address(mesh)
            local binding=ptr0(p+0x80)
            if binding~=0 then
                local n=b:_u32(binding);assert(n>0 and n<=128,'Skinning binding count changed')
                local offset=b:_u32(binding+8);assert(offset>=16 and offset<=65536,'Skinning map offset changed')
                for j=0,n-1 do include(b:_u32(binding+offset+j*4))end
            elseif part.group=='weapon' then
                include(sr.Mesh.node(mesh)-1)
            end
        end
        for node,info in pairs(selected)do
            local n=node+1
            local row={node=n,parent=info.parent and info.parent+1,link=info.link,world=info.world,
                hash=b:_u32(g.hashes+node*4),before=point(U.local_position(part.handle,n)),
                rotation={Q.to_elements(U.local_rotation(part.handle,n))}}
            if row.world then
                for _,value in ipairs(row.before)do assert(value==value and math.abs(value)<1e6,'World-space skinning root exceeds bounds')end
                assert(close(row.before,point(U.world_position(part.handle,n)))
                    and sameq(row.rotation,{Q.to_elements(Q.from_matrix4x4(U.world_pose(part.handle,n)))}),
                    'World-space skinning root is not an absolute SDK pose')
            end
            g.rows[#g.rows+1]=row
            self.nodes=self.nodes+1
        end
        assert(#g.rows>0,'No linked skinning nodes found')
        groups[#groups+1]=g
    end
    local function row_valid(g,r)
        return b:_u32(g.links+(r.node-1)*4)==r.link and b:_u32(g.hashes+(r.node-1)*4)==r.hash
    end
    function self:restore()
        for _,g in ipairs(groups)do
            if graph_valid(g)then
                local dirty=false
                for _,r in ipairs(g.rows)do
                    if row_valid(g,r)then
                        if r.last and close(point(U.local_position(g.part.handle,r.node)),r.last)then
                            U.set_local_position(g.part.handle,r.node,vec(r.before));dirty=true
                        end
                        if r.last_rotation and sameq({Q.to_elements(U.local_rotation(g.part.handle,r.node))},r.last_rotation)then
                            U.set_local_rotation(g.part.handle,r.node,quat(r.rotation));dirty=true
                        end
                    end
                    r.last,r.last_rotation=nil,nil
                end
                if dirty then assert(sr.World.update_unit(cal.world,g.part.handle)~=false,'Render restore refused')end
            end
        end
        return true
    end
    function self:apply(transforms)
        local parents={} -- SDK matrix temporaries are valid only within this frame.
        local function parent_for(g,r,t)
            local key=g.parent_context.object..':'..r.parent
            local parent=parents[key]
            if parent then
                assert(parent.frames==(t.parent_frames or false),'Render parts use different copied parent frames')
                return parent
            end
            if t.parent_frames then parent=copied_parent(t.parent_frames,r.parent,g.parent_nodes)
            else
                local world=U.world_pose(g.parent_handle,r.parent)
                parent={world=world,inverse=A.inverse(world),frames=false}
            end
            parents[key]=parent;return parent
        end
        -- Validate every supplied frame used by this batch before render writes.
        for _,g in ipairs(groups)do
            local t=assert(transforms[g.part.group],'Render placement group missing')
            if t.parent_frames then
                assert(type(t.parent_frames)=='table'and #t.parent_frames==g.parent_nodes
                    and g.parent_nodes>0 and g.parent_nodes<=256,
                    'Copied render parent count changed')
                for _,r in ipairs(g.rows)do if r.parent and(not t.retarget_only or t.bones and t.bones[r.parent])then
                    parent_for(g,r,t)
                end end
            end
        end
        for _,g in ipairs(groups)do
            assert(graph_valid(g),'Render placement generation/parent changed')
            local t=assert(transforms[g.part.group],'Render placement group missing');local dirty=false
            local compensating=t.frame_compensation and not(t.bones and t.retarget_only)
            if compensating then
                assert(g.parent_nodes==63 and t.source_origin and t.target_origin,'Render frame compensation requires the verified FPS source')
                for _,origin in ipairs({t.source_origin,t.target_origin})do for _,value in ipairs(origin)do
                    assert(value==value and math.abs(value)<1e6,'Render frame origin exceeds world bounds')
                end end
                relative_bound({t.source[1]-t.source_origin[1],t.source[2]-t.source_origin[2],t.source[3]-t.source_origin[3]},
                    'Native weapon is outside its FPS source frame')
                relative_bound({t.target[1]-t.target_origin[1],t.target[2]-t.target_origin[2],t.target[3]-t.target_origin[3]},
                    'Rendered weapon is outside its head camera frame')
            end
            local rotating=t.rotation and not same_target_rotation({Q.to_elements(t.rotation)},{0,0,0,1})or false
            local identity=not rotating and t.source and t.target and close(t.source,t.target)
            for _,r in ipairs(g.rows)do
                assert(row_valid(g,r),'Skinning bone mapping changed')
                local bone=t.bones and r.parent and t.bones[r.parent]
                local selective_unmapped=t.bones and t.retarget_only and not bone
                if selective_unmapped and not r.last and not r.last_rotation then
                    -- This helper was never authored by us. Keep native local
                    -- writers and physics entirely outside our reservation.
                    self.coalesced=self.coalesced+2
                else
                local position=point(U.local_position(g.part.handle,r.node))
                local rotation={Q.to_elements(U.local_rotation(g.part.handle,r.node))}
                -- A foreign writer owns its new value. Never accumulate the
                -- offset on the last authored pose, or stomp a replacement.
                if not selective_unmapped then
                    assert(close(position,r.last or r.before) and sameq(rotation,r.last_rotation or r.rotation),'Render local pose has another writer')
                end
                local next_position,next_q
                -- bones is keyed by the ONE-BASED external parent SDK node.
                -- Each value is a desired world-space joint frame. Render-only
                -- locals reproduce it while the body graph remains untouched.
                if bone then
                    assert(not r.world and type(bone.position)=='table'and type(bone.rotation)=='table','Retarget joint frame invalid')
                    local parent=parent_for(g,r,t)
                    local desired_q=quat(bone.rotation)
                    assert(sameq({Q.to_elements(desired_q)},{Q.to_elements(Q.normalize(desired_q))}),'Retarget joint orientation invalid')
                    local offset=point(Q.rotate(desired_q,vec(r.before)))
                    relative_bound(offset,'Retarget render bind offset exceeds bounds')
                    local moved=V(bone.position[1]+offset[1],bone.position[2]+offset[2],bone.position[3]+offset[3])
                    local native=point(forward(parent,vec(r.before)))
                    relative_bound({V.x(moved)-native[1],V.y(moved)-native[2],V.z(moved)-native[3]},'Retarget joint displacement exceeds bounds')
                    next_position=point(backward(parent,moved))
                    relative_bound(next_position,'Retarget render local exceeds bounds')
                    parent.q=parent.q or Q.from_matrix4x4(parent.world)
                    next_q=Q.normalize(Q.multiply(Q.multiply(Q.inverse(parent.q),desired_q),quat(r.rotation)))
                elseif t.bones and t.retarget_only then
                    -- Missing semantic targets keep their native TP bind pose.
                    -- In particular, never move torso/helpers by the fallback
                    -- rigid FP-weapon transform supplied alongside a bone map.
                    next_position=r.last and close(position,r.last)and r.before or position
                    next_q=r.last_rotation and sameq(rotation,r.last_rotation)and quat(r.rotation)or quat(rotation)
                elseif r.world then
                    assert(t.source_rotation and t.target_rotation,'World-space skinning root needs the locked weapon frames')
                    if not r.anchor_position then
                        local inverse_source=Q.inverse(t.source_rotation)
                        local relative=V(r.before[1]-t.source[1],r.before[2]-t.source[2],r.before[3]-t.source[3])
                        r.anchor_position=point(Q.rotate(inverse_source,relative))
                        local length=0;for _,value in ipairs(r.anchor_position)do
                            assert(value==value and math.abs(value)<=2,'World-space skinning root is outside the owned weapon frame')
                            length=length+value*value
                        end
                        assert(length<=4,'World-space skinning root exceeds two metres')
                        r.anchor_rotation={Q.to_elements(Q.normalize(Q.multiply(inverse_source,quat(r.rotation))))}
                    end
                    -- Anchor once to the native weapon frame, then carry that
                    -- fixed relative pose with the locked target. Reusing an
                    -- absolute world baseline would leave these roots behind
                    -- when the player travels, even for an identity delta.
                    local moved=point(Q.rotate(t.target_rotation,vec(r.anchor_position)))
                    next_position={moved[1]+t.target[1],moved[2]+t.target[2],moved[3]+t.target[3]}
                    for _,value in ipairs(next_position)do assert(value==value and math.abs(value)<1e6,'World-space render placement exceeds bounds')end
                    next_q=Q.normalize(Q.multiply(t.target_rotation,quat(r.anchor_rotation)))
                elseif identity then
                    -- Avoid a float32 world -> local round trip when unchanged.
                    next_position=r.before;next_q=quat(r.rotation)
                else
                local parent=parent_for(g,r,t)
                local native=point(forward(parent,vec(r.before)))
                local relative=V(native[1]-t.source[1],native[2]-t.source[2],native[3]-t.source[3])
                relative_bound(point(relative),'Native skinning bone is outside the owned weapon frame')
                local arm=rotating and Q.rotate(t.rotation,relative)or relative
                local moved=V(V.x(arm)+t.target[1],V.y(arm)+t.target[2],V.z(arm)+t.target[3])
                relative_bound({V.x(moved)-t.target[1],V.y(moved)-t.target[2],V.z(moved)-t.target[3]},
                    'Rendered skinning bone exceeds the locked weapon frame')
                next_position=point(backward(parent,moved))
                if compensating then
                    -- Large locals here are only the old-parent-origin to
                    -- live-camera-origin carrier translation. The actual joint
                    -- deformation around that carrier remains within two metres.
                    local carrier=point(backward(parent,vec(t.target)))
                    relative_bound({next_position[1]-carrier[1],next_position[2]-carrier[2],next_position[3]-carrier[3]},
                        'Render placement deforms beyond the rebased weapon carrier')
                else
                    for _,v in ipairs(next_position)do assert(v==v and math.abs(v)<2,'Render placement exceeds bounds')end
                end
                if rotating then
                    parent.q=parent.q or Q.from_matrix4x4(parent.world)
                    local pq=parent.q
                    next_q=Q.normalize(Q.multiply(Q.multiply(Q.multiply(Q.inverse(pq),t.rotation),pq),quat(r.rotation)))
                else next_q=quat(r.rotation)end
                end
                -- Engine Vector3 setters store float32. Keep the exact value
                -- submitted to them as our ownership token; world positions
                -- can have float ULPs larger than the local-pose comparison.
                if not selective_unmapped or not close(position,next_position)then
                    next_position=quantized_position(next_position)
                    local position_limit=(r.world or compensating)and 1e6 or 2
                    for _,value in ipairs(next_position)do assert(value==value and math.abs(value)<position_limit,'Quantized render placement exceeds bounds')end
                end
                -- Ownership tolerates SDK float error, but that angular test
                -- would suppress about .16 degrees of real target motion.
                -- Coalesce only equal float32 targets (q and -q are identical).
                local next_rotation=quantized_rotation({Q.to_elements(next_q)})
                if not close(position,next_position)then
                    U.set_local_position(g.part.handle,r.node,vec(next_position));r.last=next_position;dirty=true;self.writes=self.writes+1
                else self.coalesced=self.coalesced+1 end
                if not same_target_rotation(rotation,next_rotation)then
                    U.set_local_rotation(g.part.handle,r.node,quat(next_rotation));r.last_rotation=next_rotation;dirty=true;self.writes=self.writes+1
                end
                if selective_unmapped then r.last,r.last_rotation=nil,nil end
                end
            end
            if dirty then
                assert(sr.World.update_unit(cal.world,g.part.handle)~=false,'Render placement publish refused')
                self.publishes=self.publishes+1
            end
        end
        return true
    end
    return self
end
return M
