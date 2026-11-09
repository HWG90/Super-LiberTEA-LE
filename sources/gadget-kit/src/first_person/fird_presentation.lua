-- Lease the game's existing local FP presentation switch independently of the
-- camera request. No graph links, animation states or executable bytes are set
-- here; the guarded backend invokes the same function as native FP entry/exit.
local M={}
local function ptr0(b,at)
    local low,high=b:_u32(at),b:_u32(at+4)
    local value=low+high*4294967296
    assert(value==0 or value>=65536 and value<2^47,'Presentation pointer is invalid')
    return value
end
local function same_context(a,b)
    if not a or not b then return false end
    for _,key in ipairs({'unit','index','generation','object','registry','units','generations'})do
        if a[key]~=b[key]then return false end
    end
    return true
end
local function live(b,c)
    return c and b:_u8(c.generations+c.index)==c.generation and ptr0(b,c.units+c.index*8)==c.object
        and b:_u32(c.object+8)==c.unit
end
local function default_probe(b)
    local s,why=b:snapshot();assert(s,why or 'Presentation player unavailable')
    local function context(ref)return b:_alignment_context({viewmodel=ref,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index})end
    local body,fps,weapon=context(s.body),context(s.viewmodel),context(s.weapon_unit)
    assert(live(b,body)and live(b,fps)and live(b,weapon),'Presentation rig generation changed')
    local row=s.avatar_owner+0x546AB0+s.avatar_index*0x1B8
    local mode=b:_u8(row+0x70);assert(mode==0 or mode==1,'Presentation mode changed')
    local appearance=b:_read(row+0xDC,120)
    local parts,seen={},{}
    local function add(ref,kind)
        if ref==0 or ref==0xFFFFFFFF or seen[ref]then return end
        seen[ref]=true;local c=context(ref)
        assert(live(b,c),'Presentation attachment generation changed')
        parts[#parts+1]={context=c,kind=kind,parent=ptr0(b,c.object+0x1D0),external=ptr0(b,c.object+0x78),world=ptr0(b,c.object+24)}
    end
    local function integer(at)local a,c,d,e=appearance:byte(at+1,at+4);return a+c*256+d*65536+e*16777216 end
    for layer=0,2 do for _,slot in ipairs({6,7})do add(integer(layer*40+slot*4),'arm')end end
    add(s.weapon_unit,'weapon');assert(#parts>0,'Presentation attachments unavailable')
    local world=ptr0(b,body.object+24)
    assert(world~=0 and ptr0(b,fps.object+24)==world and ptr0(b,weapon.object+24)==world,'Presentation rigs belong to different worlds')
    local value={snapshot=s,mode=mode,mode_address=row+0x70,appearance=appearance,body=body,fps=fps,weapon=weapon,
        body_matrices=ptr0(b,body.object+0x88),fps_matrices=ptr0(b,fps.object+0x88),world=world,parts=parts}
    assert(value.body_matrices~=0 and value.fps_matrices~=0,'Presentation world matrices unavailable')
    local final,problem=b:snapshot()
    assert(final and final.identity==s.identity and final.player_identity==s.player_identity and final.record==s.record
        and final.viewmodel==s.viewmodel and final.camera_kind==s.camera_kind,'Presentation owner changed during observation')
    assert(live(b,body)and live(b,fps)and live(b,weapon)and b:_u8(row+0x70)==mode
        and b:_read(row+0xDC,120)==appearance,'Presentation metadata changed during observation')
    return value
end
local function same_owner(a,b)
    if not a or not b or a.mode_address~=b.mode_address or a.world~=b.world then return false end
    for _,key in ipairs({'player_identity','base','context','camera','world','avatar_owner','avatar_index','avatar','body','viewmodel'})do
        if a.snapshot[key]~=b.snapshot[key]then return false end
    end
    return same_context(a.body,b.body)and same_context(a.fps,b.fps)
end
function M.new(backend,log,deps)
    deps=deps or {};log=log or function()end
    local clock=deps.clock or os.clock
    local self={};local lease,serial,reason=nil,0,nil
    local phase='off'
    local function report(value,why)phase,reason=value,why end
    local function probe()
        local ok,value=pcall(deps.probe or default_probe,backend)
        if not ok then return nil,tostring(value)end
        if type(value)~='table'or type(value.snapshot)~='table'or(value.mode~=0 and value.mode~=1)then return nil,'Presentation observation unavailable'end
        return value
    end
    local function foreign()
        local fn=deps.foreign or backend.foreign_camera
        if not fn then return false end
        local ok,value=pcall(fn);return not ok or value~=false
    end
    local function time()
        local ok,value=pcall(clock)
        if not ok or type(value)~='number'or value~=value or value<0 or value==math.huge then return nil end
        return value
    end
    local function frame()
        if not deps.frame then return serial end
        local ok,value=pcall(deps.frame)
        if not ok or type(value)~='number'or value~=value or value<0 or value==math.huge then return nil end
        return value
    end
    local function invoke(state,enabled)
        local fn=deps.invoke or backend._invoke_presentation
        if type(fn)~='function'then return false,'Native FP presentation operation unavailable'end
        local ok,value,why=pcall(fn,backend,state.snapshot,enabled)
        if not ok then return false,tostring(value)end
        return value==true,why or(value~=true and 'Native FP presentation operation was refused'or nil)
    end
    local function retired(state)
        if deps.retired then local ok,value=pcall(deps.retired,backend,state);return ok and value==true end
        local ok,value=pcall(function()
            return not live(backend,state.body)or not live(backend,state.fps)
        end)
        return ok and value
    end
    local function attachment_ready(state)
        for _,p in ipairs(state.parts or {})do
            if p.world~=state.world then return false,'Presentation attachment world changed',true end
            if p.parent~=0 and p.parent~=state.body.object and p.parent~=state.fps.object then return false,'Presentation attachment has a foreign parent',true end
            if p.external~=0 and p.external~=state.body_matrices and p.external~=state.fps_matrices then return false,'Presentation attachment has foreign parent matrices',true end
            local fp=p.parent==state.fps.object and p.external==state.fps_matrices
            local body=p.parent==state.body.object and p.external==state.body_matrices
            -- The native appearance switch reparents arm clothing. The held
            -- weapon can retain its body parent; the render adapter maps each
            -- part from its own verified parent onto the shared camera target.
            -- Crossed/null parent-array pairs never authorize render writes.
            if not fp and not(p.kind=='weapon'and body)then return false,'Waiting for native FP attachment acknowledgement'end
        end
        return #(state.parts or {})>0,'Presentation attachments unavailable'
    end
    function self:is_clean()return lease==nil end
    function self:is_active()return lease~=nil and lease.ready==true end
    function self:result()return{phase=phase,ready=lease~=nil and lease.ready==true,owned=lease~=nil and lease.owned==true,
        borrowed=lease~=nil and not lease.owned,cleanup_pending=phase=='cleanup_pending',reason=reason}end
    function self:stop()
        if not lease then report('off');return true end
        lease.ready=false
        if not lease.owned then lease=nil;report('off');return true end
        if retired(lease.state)then lease=nil;report('off');return true end
        local current,why=probe()
        if not current then report('cleanup_pending',why);return false,why end
        if not same_owner(lease.state,current)then report('cleanup_pending','Presentation owner changed; awaiting native retirement');return false,reason end
        if current.mode==0 then lease=nil;report('off');return true end
        if foreign()or current.snapshot.camera_kind==6 or current.snapshot.controller_active then
            report('cleanup_pending','Native ADS or another camera owns presentation');return false,reason
        end
        if current.snapshot.safe~=true or current.snapshot.camera_kind~=4 then report('cleanup_pending','Waiting for a safe normal presentation owner');return false,reason end
        local _,problem,fatal=attachment_ready(current)
        if fatal then report('cleanup_pending',problem);return false,problem end
        if lease.restoring then
            report('cleanup_pending','Waiting for native presentation restoration acknowledgement');return false,reason
        end
        -- Reserve an uncertain operation before it can enqueue native work.
        lease.restoring=true
        local ok,problem=invoke(current,false)
        if not ok then report('cleanup_pending',problem);return false,problem end
        current,why=probe()
        if current and same_owner(lease.state,current)and current.mode==0 then lease=nil;report('off');return true end
        report('cleanup_pending',why or 'Waiting for native presentation restoration acknowledgement');return false,reason
    end
    function self:start(expected)
        if lease then return false,'FP presentation already owns a lease'end
        if foreign()then return false,'Another camera owns the view'end
        local current,why=probe();if not current then return false,why end
        local s=current.snapshot
        if not expected or s.identity~=expected.identity or s.player_identity~=expected.player_identity or s.record~=expected.record
            or s.safe~=true or s.camera_kind~=4 or s.controller_active then return false,'FP presentation requires the current released normal camera'end
        local _,problem,fatal=attachment_ready(current)
        if fatal then return false,problem end
        local now=time();if not now then return false,'Presentation clock unavailable'end
        local current_frame=frame();if not current_frame then return false,'Presentation frame unavailable'end
        lease={state=current,owned=current.mode==0,ready=false,started=serial,deadline=now+.5,
            start_frame=current_frame,target=s.identity..':'..current.appearance,reasserted=true}
        report('waiting')
        if lease.owned then
            local ok,problem=invoke(current,true)
            if not ok then report('cleanup_pending',problem);return false,problem end
        end
        return true
    end
    function self:update(expected)
        serial=serial+1
        if not lease then return false,'FP presentation is not active'end
        lease.ready=false
        local current,why=probe()
        if not current then
            -- Queued unlink/link and matrix publication can expose a partial
            -- rig for a frame. Observe only while the original deadline holds.
            local now=time()
            if now and now<=lease.deadline then report('waiting',why);return true end
            report('cleanup_pending',why or 'Native FP attachment observation timed out');return false,reason
        end
        if not same_owner(lease.state,current)or expected and(current.snapshot.identity~=expected.identity or current.snapshot.player_identity~=expected.player_identity)then
            report('cleanup_pending','FP presentation owner changed');return false,reason
        end
        if current.mode==0 then lease=nil;report('off','Native FP presentation was retired');return false,reason end
        if foreign()or current.snapshot.camera_kind==6 or current.snapshot.controller_active or not current.snapshot.safe then
            report('suspended','Native ADS or another camera owns presentation');return true
        end
        local target=current.snapshot.identity..':'..current.appearance
        if target~=lease.target then
            local now=time();if not now then report('cleanup_pending','Presentation clock unavailable');return false,reason end
            local current_frame=frame();if not current_frame then report('cleanup_pending','Presentation frame unavailable');return false,reason end
            lease.target=target;lease.reasserted=false;lease.started=serial;lease.start_frame=current_frame;lease.deadline=now+.5
        end
        local ready,problem,fatal=attachment_ready(current)
        if fatal then report('cleanup_pending',problem);return false,problem end
        local current_frame=frame()
        if ready and current_frame and current_frame>lease.start_frame then lease.ready=true;report('active');return true end
        if ready then problem='Waiting for a later native presentation frame'end
        if not ready and lease.owned and not lease.reasserted then
            -- The mode belongs to this avatar across ordinary weapon swaps.
            -- A new equipped renderer may still carry its normal body links;
            -- let the game's own switch rebuild them once for this target.
            lease.reasserted=true
            local ok,why=invoke(current,true)
            if not ok then report('cleanup_pending',why);return false,why end
        end
        local now=time()
        if not now or now>lease.deadline then report('cleanup_pending','Native FP attachment acknowledgement timed out');return false,reason end
        report('waiting',problem);return true
    end
    return self
end
return M
