-- Pure FPS-to-TP arm retargeting. The torso attachment stays fixed; an optional
-- verified shoulder support can articulate without changing its bone length.
-- Native TP arm lengths determine reach, and the FPS pose supplies the grip,
-- elbow plane and twist. This module never calls or writes the engine.
local M={hashes={
    left={shoulder=0x03752C98,elbow=0x1CA2CD66,hand=0x5C0C68D3},
    right={shoulder=0x1620B2CE,elbow=0x31E34DAC,hand=0x248004F5},
},supports={left={node=43,hash=0xC4787B4E,parent=29},right={node=66,hash=0xB2BCD839,parent=29}}}
local EPS=.000001
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function point(p)
    assert(type(p)=='table','Retarget position unavailable');local out={}
    for i=1,3 do assert(finite(p[i])and math.abs(p[i])<1e6,'Retarget world position invalid');out[i]=p[i]end
    return out
end
local function add(a,b)return{a[1]+b[1],a[2]+b[2],a[3]+b[3]}end
local function sub(a,b)return{a[1]-b[1],a[2]-b[2],a[3]-b[3]}end
local function scale(a,n)return{a[1]*n,a[2]*n,a[3]*n}end
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function cross(a,b)return{a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]}end
local function length(a)return math.sqrt(dot(a,a))end
local function normalized(a)
    local n=length(a);assert(n>EPS,'Retarget direction is degenerate');return scale(a,1/n)
end
local function quaternion(q)
    assert(type(q)=='table','Retarget orientation unavailable');local n=0
    for i=1,4 do assert(finite(q[i]),'Retarget orientation invalid');n=n+q[i]*q[i]end
    assert(math.abs(n-1)<.02,'Retarget orientation is not normalized')
    n=math.sqrt(n);return{q[1]/n,q[2]/n,q[3]/n,q[4]/n}
end
local function inverse(q)return{-q[1],-q[2],-q[3],q[4]}end
local function multiply(a,b)
    return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function rotate(q,p)
    local v=multiply(multiply(q,{p[1],p[2],p[3],0}),inverse(q));return{v[1],v[2],v[3]}
end
local function frame(f)
    assert(type(f)=='table','Retarget frame unavailable')
    return{position=point(f.position),rotation=quaternion(f.rotation)}
end
local function transform(lock)
    local source,target=point(lock.source),point(lock.target)
    local rotation=quaternion(multiply(quaternion(lock.target_rotation),inverse(quaternion(lock.source_rotation))))
    return function(f)
        f=frame(f);assert(length(sub(f.position,source))<=2,'FPS limb is outside its weapon frame')
        return{position=add(target,rotate(rotation,sub(f.position,source))),rotation=quaternion(multiply(rotation,f.rotation))}
    end,rotation
end
local function projected(v,axis)return sub(v,scale(axis,dot(v,axis)))end
local function swing(from,to,pole)
    from,to=normalized(from),normalized(to)
    local d=math.max(-1,math.min(1,dot(from,to)))
    if d>-.999999 then
        local c=cross(from,to);local q={c[1],c[2],c[3],1+d};local n=0
        for i=1,4 do n=n+q[i]*q[i]end
        n=math.sqrt(n);for i=1,4 do q[i]=q[i]/n end;return q
    end
    local axis=normalized(projected(pole,from));return{axis[1],axis[2],axis[3],0}
end
function M.index(nodes)
    local ok,result=pcall(function()
        assert(type(nodes)=='table'and #nodes>0 and #nodes<=512,'Retarget node inventory invalid')
        local out={}
        for i,row in ipairs(nodes)do
            local hash,node=row.hash,row.node or i
            assert(finite(hash)and hash>=0 and hash<4294967296 and hash==math.floor(hash),'Retarget hash invalid')
            assert(finite(node)and node>=1 and node<=512 and node==math.floor(node),'Retarget SDK node invalid')
            if hash~=0 then assert(not out[hash],'Retarget semantic hash is ambiguous');out[hash]=node end
        end
        return out
    end)
    if not ok then return nil,tostring(result)end;return result
end
function M.solve_arm(source,target,lock,previous_pole)
    local ok,result=pcall(function()
        local map=transform(lock)
        local ss,se,sh=map(source.shoulder),map(source.elbow),map(source.hand)
        local ts,te,th=frame(target.shoulder),frame(target.elbow),frame(target.hand)
        local lengths=target.lengths or{}
        local upper=lengths.upper or length(sub(te.position,ts.position))
        local lower=lengths.lower or length(sub(th.position,te.position))
        assert(finite(upper)and finite(lower)and upper>.01 and lower>.01 and upper<1 and lower<1,'TP arm lengths invalid')
        local requested=sh.position;local original_shoulder=ts.position
        local clavicle,clavicle_length,clavicle_angle,clavicle_adjusted=nil,nil,0,false
        if target.clavicle then
            clavicle=frame(target.clavicle)
            local original_offset=sub(ts.position,clavicle.position)
            clavicle_length=length(original_offset)
            assert(clavicle_length>.001 and clavicle_length<.5,'TP shoulder support length invalid')
            if length(sub(requested,ts.position))>upper+lower+EPS then
                local to_goal=sub(requested,clavicle.position);local d=length(to_goal)
                assert(d>EPS,'Shoulder support target is degenerate')
                local toward=scale(to_goal,1/d);local reach=upper+lower
                local offset
                if math.abs(d-clavicle_length)>reach then
                    -- Even maximum support articulation cannot reach. Choose
                    -- its closest point without stretching any of the bones;
                    -- the ordinary arm solve reports the remaining grip error.
                    offset=scale(toward,clavicle_length)
                else
                    -- The two spheres intersect in a circle. Project the old
                    -- shoulder into that circle's plane to select its nearest
                    -- point, which is the minimum support-bone rotation.
                    local along=(clavicle_length^2-reach^2+d^2)/(2*d)
                    local radius=math.sqrt(math.max(0,clavicle_length^2-along^2))
                    local tangent=projected(original_offset,toward)
                    if radius>EPS and length(tangent)<=EPS then
                        tangent=projected(sub(se.position,clavicle.position),toward)
                        if length(tangent)<=EPS and previous_pole then tangent=projected(point(previous_pole),toward)end
                        if length(tangent)<=EPS then tangent=projected(sub(te.position,clavicle.position),toward)end
                    end
                    offset=scale(toward,along)
                    if radius>EPS then offset=add(offset,scale(normalized(tangent),radius))end
                end
                ts.position=point(add(clavicle.position,offset))
                local pole=cross(original_offset,offset)
                if length(pole)<=EPS then pole=sub(se.position,clavicle.position)end
                local rotation=swing(original_offset,offset,pole)
                clavicle.rotation=quaternion(multiply(rotation,clavicle.rotation))
                clavicle_angle=2*math.acos(math.min(1,math.abs(rotation[4])))
                clavicle_adjusted=length(sub(ts.position,original_shoulder))>EPS
            end
        end
        local travel=sub(requested,ts.position);local distance=length(travel)
        assert(distance>EPS and distance<=2,'Requested FP grip is outside the TP shoulder frame')
        local axis=scale(travel,1/distance)
        local source_upper=sub(se.position,ss.position);local source_lower=sub(sh.position,se.position)
        assert(length(source_upper)>EPS and length(source_lower)>EPS,'FPS arm segments are degenerate')
        local plane=cross(sub(sh.position,ss.position),source_upper)
        local pole=length(plane)>EPS and cross(normalized(plane),axis)or{0,0,0}
        local source_pole=projected(sub(se.position,ts.position),axis)
        if length(pole)>EPS then
            pole=normalized(pole);if dot(pole,source_pole)<0 then pole=scale(pole,-1)end
        else
            pole=previous_pole and projected(point(previous_pole),axis)or projected(sub(te.position,ts.position),axis)
            pole=normalized(pole)
        end
        local minimum,maximum=math.abs(upper-lower),upper+lower
        local solved=math.max(minimum,math.min(maximum,distance))
        assert(solved>EPS,'TP arm reach is degenerate')
        local along=(upper*upper-lower*lower+solved*solved)/(2*solved)
        local height=math.sqrt(math.max(0,upper*upper-along*along))
        local elbow=add(ts.position,add(scale(axis,along),scale(pole,height)))
        local hand=add(ts.position,scale(axis,solved))
        local shoulder_q=quaternion(multiply(swing(source_upper,sub(elbow,ts.position),pole),ss.rotation))
        local elbow_q=quaternion(multiply(swing(source_lower,sub(hand,elbow),pole),se.rotation))
        local error=math.abs(distance-solved)
        return{shoulder={position=ts.position,rotation=shoulder_q},elbow={position=point(elbow),rotation=elbow_q},
            hand={position=point(hand),rotation=sh.rotation},requested_hand=requested,pole=pole,
            clavicle=clavicle,clavicle_adjusted=clavicle_adjusted,clavicle_angle=clavicle_angle,
            shoulder_shift=length(sub(ts.position,original_shoulder)),
            lengths={upper=upper,lower=lower,clavicle=clavicle_length},reachable=error<=.00001,reach_error=error}
    end)
    if not ok then return nil,tostring(result)end
    return result,result.reachable and nil or 'Locked FP grip exceeds the preserved TP arm reach'
end
function M.finger(parent,source_parent,source_child,target_length,lock)
    local ok,result=pcall(function()
        parent=frame(parent)
        assert(finite(target_length)and target_length>EPS and target_length<.25,'TP finger length invalid')
        local map=transform(lock);local a,b=map(source_parent),map(source_child)
        return{position=add(parent.position,scale(normalized(sub(b.position,a.position)),target_length)),rotation=b.rotation}
    end)
    if not ok then return nil,tostring(result)end;return result
end
function M.map(source,target,lock,previous_poles,policy)
    local ok,bones,stats=pcall(function()
        assert(type(source)=='table'and type(source.by_hash)=='table'and type(source.by_index)=='table'
            and type(target)=='table'and type(target.by_hash)=='table'and type(target.by_index)=='table','Retarget semantic inventories unavailable')
        local native_details=type(policy)=='table'and policy.native_details==true
        local visible_arms=type(policy)=='table'and policy.visible_arms==true
        local out,report={},{mapped=0,helpers_preserved=0,reachable=true,reach_error=0,arms={},poles={},preserved_reasons={},native_details=native_details,visible_arms=visible_arms}
        local mapped=transform(lock)
        local roots,source_roots={},{}
        local function preserve(native,why)
            report.helpers_preserved=report.helpers_preserved+1;report.preserved_reasons[native.hash]=why
        end
        local function emit(native,desired)
            assert(type(native.node)=='number'and native.node>=1 and native.node==math.floor(native.node),'Retarget target SDK node invalid')
            desired.node,desired.parent,desired.hash=native.node,native.parent,native.hash
            out[native.node]=desired;report.mapped=report.mapped+1
        end
        for _,side in ipairs({'left','right'})do
            local src,dst={},{}
            for _,role in ipairs({'shoulder','elbow','hand'})do
                local hash=M.hashes[side][role]
                src[role]=assert(source.by_hash[hash],side..' FPS '..role..' unavailable')
                dst[role]=assert(target.by_hash[hash],side..' TP '..role..' unavailable')
            end
            local result,why
            if visible_arms then
                -- The visibility policy carries the live FPS primary frames
                -- directly. It makes no reach or torso-seam adjustment.
                result={shoulder=mapped(src.shoulder),elbow=mapped(src.elbow),hand=mapped(src.hand),
                    reachable=true,reach_error=0,direct=true}
            else
                local support=M.supports[side];local parent=target.by_index[dst.shoulder.parent]
                if parent and parent.node==support.node and parent.hash==support.hash and parent.parent==support.parent then
                    dst.clavicle=parent
                end
                result,why=M.solve_arm(src,dst,lock,previous_poles and previous_poles[side])
            end
            assert(result,why);report.arms[side]=result
            report.reachable=report.reachable and result.reachable;report.reach_error=math.max(report.reach_error,result.reach_error)
            roots[dst.shoulder.node]=true
            source_roots[src.shoulder.node]=true;report.poles[side]=result.pole
            if result.clavicle then emit(dst.clavicle,result.clavicle)end
            for _,role in ipairs({'shoulder','elbow','hand'})do emit(dst[role],result[role])end
        end
        local function arm_descendant(inventory,node,shoulders)
            local seen={}
            for _=1,128 do
                if shoulders[node]then return true end
                local row=inventory.by_index[node]
                if not row or row.hash==0x4FDD3337 or not row.parent then return false end
                assert(not seen[node],'TP arm hierarchy cycle');seen[node]=true;node=row.parent
            end
            error('TP arm hierarchy exceeds bounds')
        end
        local pending={}
        for node,row in pairs(target.by_index)do if not out[node]and arm_descendant(target,node,roots)then
            local child=source.by_hash[row.hash];local native_parent=target.by_index[row.parent]
            local parent=native_parent and source.by_hash[native_parent.hash]
            if native_details and(not child or arm_descendant(source,child.node,source_roots))then
                -- TP-only finger/twist helpers need the adapted ancestor too.
                -- A shared semantic in another FPS branch is an attachment,
                -- rather than an arm helper, and keeps its native placement.
                pending[#pending+1]=row
            elseif not native_details and child and parent and child.parent==parent.node and arm_descendant(source,child.node,source_roots)then
                pending[#pending+1]=row
            else preserve(row,'Source semantic parent or arm ancestry differs')end
        end end
        for _=1,#pending do
            local progress=false
            for i=#pending,1,-1 do
                local native=pending[i];local native_parent=target.by_index[native.parent]
                local desired_parent=out[native.parent]
                local source_parent=native_parent and source.by_hash[native_parent.hash]
                if desired_parent and(native_details or source_parent)then
                    local target_length=length(sub(point(native.position),point(native_parent.position)))
                    if target_length>=1 then
                        preserve(native,'TP helper segment exceeds the arm limit');table.remove(pending,i);progress=true
                    else
                    -- Optional native details retain the current TP relative
                    -- pose, including its position and full quaternion, under
                    -- the adapted parent. No FPS finger animation replaces it.
                    local parent,child
                    if native_details then parent,child=frame(native_parent),frame(native)
                    else parent,child=mapped(source_parent),mapped(source.by_hash[native.hash])end
                    local desired_q=quaternion(multiply(desired_parent.rotation,multiply(inverse(parent.rotation),child.rotation)))
                    local position=desired_parent.position
                    if native_details then
                        local offset=rotate(inverse(parent.rotation),sub(child.position,parent.position))
                        position=add(position,rotate(desired_parent.rotation,offset))
                    elseif target_length>EPS then
                        local local_direction=rotate(inverse(parent.rotation),sub(child.position,parent.position))
                        if length(local_direction)<=EPS then
                            local native_q=quaternion(native_parent.rotation)
                            local_direction=rotate(inverse(native_q),sub(native.position,native_parent.position))
                        end
                        position=add(position,scale(rotate(desired_parent.rotation,normalized(local_direction)),target_length))
                    end
                    emit(native,{position=point(position),rotation=desired_q})
                    table.remove(pending,i);progress=true
                    end
                end
            end
            if not progress then break end
        end
        for _,native in ipairs(pending)do preserve(native,'Semantic parent remains native')end
        return out,report
    end)
    if not ok then return nil,tostring(bones)end;return bones,stats
end
return M
