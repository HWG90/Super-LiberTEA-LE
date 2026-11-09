local PORT51=mod.require('src/first_person/compat51.lua')
-- Native focused locomotion: S-only for manual FPV, or view-aligned carry
-- for an independently owned natural Fird camera. No input, aim or bone writes.
local M={}
local U32=4294967296
local capacities={}
for exponent=0,16 do capacities[2^exponent]=true end
local anchors={
    {0x9de25c,'4c8b1d553c3002'},
    {0x9de2d9,'8bc8498b4350488d148948c1e2054488b40294000000415e'},
    {0x829b92,'8bc3488d0c8048c1e1054280bc31940000000074ceb001'},
    {0x9dd544,'488b6950488bf18bda488d3c9b48c1e70580bc2f94000000007407b001'},
    {0x9dc7ab,'4863d348c1e205420fb6442a0c428b0c2a4388843793000000'},
    {0x839073,'488bd6498bcde80208ffff84c07448488b4538f3420f10bc281c7c0a00f3420f10b428187c0a00f3460f108428207c0a00'},
}
local function uint(bytes,offset)
    offset=offset or 0;local a,b,c,d=bytes:byte(offset+1,offset+4)
    assert(d,'Incomplete locomotion integer');return a+b*256+c*65536+d*16777216
end
local function product(a,b)
    return ((a%65536)*(b%65536)+((math.floor(a/65536)*(b%65536)
        +(a%65536)*math.floor(b/65536))%65536)*65536)%U32
end
local function hex(bytes)return(bytes:gsub('%x%x',function(pair)return string.char(PORT51.number(pair,16))end))end
function M.new(backend,log,sr,deps)
    assert(PORT51.kind(backend)=='table','Focused movement backend required')
    log=log or function()end;deps=deps or {};sr=sr or {}
    local self={};local owned,verified,key,keyboard,closing=nil,nil,nil,nil,false
    local draining=false
    local state={phase='idle',writes=0,restores=0,foreign_changes=0}
    local function report(phase,why)
        if why and why~=state.reason then log('First-person movement: '..tostring(why))end
        state.phase,state.reason=phase,why
    end
    local function validate(base)
        if verified==base then return end
        for _,anchor in ipairs(anchors)do
            local expected=hex(anchor[2])
            assert(backend:_read(base+anchor[1],#expected)==expected,'Focused movement build fingerprint mismatch')
        end
        verified=base
    end
    local function location(s)
        assert(PORT51.kind(s)=='table' and PORT51.kind(s.avatar_descriptor)=='string' and #s.avatar_descriptor==20
            and PORT51.kind(s.avatar)=='number' and s.avatar>0 and s.avatar<0xFFFFFFFF,'Locomotion player unavailable')
        validate(s.base)
        local pool=backend:_ptr(s.base+0x2ce1eb8)
        local active=backend:_u32(pool+0xC)
        assert(active>0 and active<=16384,'Locomotion pool unavailable')
        local h=backend:_read(pool+0x20,20)
        local cap,empty,mult=uint(h,8),uint(h,12),uint(h,16)
        assert(capacities[cap] and s.avatar~=empty,
            'Locomotion registry unavailable')
        local buckets=backend:_ptr(pool+0x20);local index
        for n=0,math.min(cap,128)-1 do
            local row=backend:_read(buckets+((product(s.avatar,mult)+n)%cap)*8,8)
            local id=uint(row)
            assert(id~=empty,'Local locomotion component absent')
            if id==s.avatar then index=uint(row,4);break end
        end
        assert(index and index<active,'Locomotion component index unavailable')
        local descriptors=backend:_ptr(pool+0x38)
        local descriptor=backend:_ptr(descriptors+index*8)
        assert(backend:_ptr(s.avatar_owner+0x110+s.avatar_index*8)==descriptor
            and backend:_read(descriptor,20)==s.avatar_descriptor,'Locomotion descriptor ownership changed')
        local rows=backend:_ptr(pool+0x50)
        return {base=s.base,world=s.world,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index,
            avatar=s.avatar,body=s.body,descriptor=descriptor,descriptor_bytes=s.avatar_descriptor,
            pool=pool,index=index,descriptors=descriptors,rows=rows,address=rows+index*0xA0+0x94}
    end
    local identity_fields={'base','world','avatar_owner','avatar_index','avatar','body','descriptor','descriptor_bytes',
        'pool','index','descriptors','rows','address'}
    local function same(a,b)
        for _,field in ipairs(identity_fields)do if a[field]~=b[field]then return false end end
        return true
    end
    local function same_player(s,r)
        return PORT51.kind(s)=='table' and s.base==r.base and s.world==r.world and s.avatar_owner==r.avatar_owner
            and s.avatar_index==r.avatar_index and s.avatar==r.avatar and s.body==r.body
            and s.avatar_descriptor==r.descriptor_bytes
    end
    local function writable(address)
        if deps.writable then return deps.writable(address)==true end
        local w=backend:_windows();local r=w.region
        if PORT51.number(w.k.NativeADS_Query(w.ffi.cast('const void *',address),r,w.ffi.sizeof(r)))~=w.ffi.sizeof(r)then return false end
        local protection=PORT51.number(r.protect)
        return PORT51.number(r.state)==0x1000 and PORT51.number(r.kind)==0x20000
            and (protection==4 or protection==8) and address>=PORT51.number(r.base)
            and address+1<=PORT51.number(r.base)+PORT51.number(r.size)
    end
    local function store(address,value)
        assert(writable(address),'Focused locomotion byte is not writable private data')
        local accepted
        if deps.write then accepted=deps.write(address,value)
        else
            local w=backend:_windows();local ffi=w.ffi
            if not pcall(ffi.typeof,'NativeADSMovement_Byte')then ffi.cdef([[
                typedef uint8_t NativeADSMovement_Byte;
                int NativeADSMovement_Write(void *,void *,const void *,size_t,size_t *) __asm__("WriteProcessMemory");
            ]])end
            local out=ffi.new('NativeADSMovement_Byte[1]',value:byte())
            local count=ffi.new('size_t[1]')
            accepted=w.k.NativeADSMovement_Write(w.process,ffi.cast('void *',address),out,1,count)~=0
                and PORT51.number(count[0])==1
        end
        assert(accepted==true and backend:_read(address,1)==value,'Focused locomotion byte write/readback failed')
    end
    local function snapshot()
        local s,why
        -- Pin mode can prove the original body independently of a vehicle's
        -- camera request. Keep its unsafe/seated fields intact: this permits
        -- exact cleanup, never movement acquisition in that camera.
        if backend.pin_first_person==true and PORT51.kind(backend.pin_player_snapshot)=='function'then
            s,why=backend:pin_player_snapshot()
        else s,why=backend:player_snapshot()end
        assert(s,why or 'Local locomotion player unavailable');return s
    end
    function self:is_clean()return owned==nil end
    function self:result()
        local result={};for k,v in pairs(state)do result[k]=v end
        result.owned=owned~=nil;result.cleanup_pending=state.phase=='cleanup_pending';result.closing=closing
        return result
    end
    function self:status()return state.phase..'; focused writes='..state.writes..'; restores='..state.restores end
    function self:stop()
        if state.scope=='fird'then draining=false;state.scope=nil end
        if not owned then report('idle');return true end
        local r=owned
        local ok,why=pcall(function()
            local s=snapshot()
            -- A positively replaced local avatar retires our old data lease.
            -- An unreadable owner does not authorize any write or retirement.
            if not same_player(s,r)then owned=nil;return end
            local current=location(s)
            if not same(current,r)then owned=nil;return end
            local value=backend:_read(r.address,1)
            if value~='\1'then state.foreign_changes=state.foreign_changes+1;draining=true;owned=nil;return end
            assert(same(location(snapshot()),r),'Locomotion owner changed before restoration')
            store(r.address,r.before)
            state.restores=state.restores+1;owned=nil
        end)
        if not ok then
            -- If a reported write failure still produced the desired original
            -- byte, a later stop verifies it and retires without another write.
            report('cleanup_pending',tostring(why));return false,state.reason
        end
        report('idle');return true
    end
    function self:shutdown()closing=true;return self:stop()end
    local function input_focus()
        local window=sr.Window
        if PORT51.kind(window)=='table'then
            if PORT51.kind(window.mouse_focus)=='function'and window.mouse_focus()~=true then return false end
            if PORT51.kind(window.show_cursor)=='function'and window.show_cursor()~=false then return false end
        end
        return true
    end
    local function backward()
        local input=sr.Keyboard
        assert(PORT51.kind(input)=='table' and PORT51.kind(input.button)=='function','Game keyboard input unavailable')
        if input~=keyboard then key=nil;keyboard=input end
        if key==nil then
            local find=input.button_index or input.button_id
            assert(PORT51.kind(find)=='function','Game S binding lookup unavailable');key=find('s')
        end
        assert(PORT51.kind(key)=='number' and key==math.floor(key) and key>=0 and key<512,'Game S binding unavailable')
        if not input_focus()then return false end
        local value=input.button(key)
        assert(value==0 or value==1,'Game S input state unavailable')
        return value==1
    end
    local function update(controller,skip,focused)
        if closing or skip then return self:stop()end
        if owned and state.phase=='cleanup_pending'then return self:stop()end
        local ok,why=pcall(function()
            assert(PORT51.kind(controller)=='table' and PORT51.kind(controller.is_enabled)=='function','Movement controller unavailable')
            if not controller:is_enabled() or controller:result().mode~='pose_offset' then return self:stop()end
            state.scope=focused and'fird'or'manual'
            if backend.foreign_camera then
                local foreign=backend.foreign_camera()
                assert(PORT51.kind(foreign)=='boolean','Camera ownership unavailable')
                if foreign then return self:stop()end
            end
            -- Manual FPV retains its original S-only behavior. Natural Fird
            -- owns a separate, continuous focus interval, without key queries.
            if focused then
                if PORT51.kind(controller.focus_owned)~='function'or not input_focus()then return self:stop()end
            elseif not backward()then draining=false;return self:stop()end
            if draining then
                report('foreign',focused and'Focused locomotion changed externally; switch Fird Person off before retrying'
                    or'Focused locomotion changed externally; release S before retrying');return
            end
            local s=snapshot()
            if not s.safe or s.seated or (s.camera_kind~=4 and s.camera_kind~=6)then return self:stop()end
            local function focused_owner(current)
                return not focused or current.safe==true and current.camera_kind==4 and not current.controller_active
                    and input_focus()and controller:focus_owned(current)==true and PORT51.kind(deps.fallback_ready)=='function'
                    and deps.fallback_ready(current)==true
            end
            if not focused_owner(s)then return self:stop()end
            local action=backend:action_state(s)
            if backend:on_foot(s,action)~=true then
                return self:stop()
            end
            if not focused and s.camera_kind==4 and (PORT51.kind(deps.fallback_ready)~='function' or deps.fallback_ready(s)~=true)then
                return self:stop()
            end
            local current=location(s)
            if owned and not same(current,owned)then
                local clean,problem=self:stop();assert(clean,problem)
                -- Never acquire another slot in the update which retired one.
                return
            end
            local value=backend:_read(current.address,1)
            assert(value=='\0' or value=='\1','Focused locomotion flag has a foreign value')
            if owned then
                if value~='\1'then
                    state.foreign_changes=state.foreign_changes+1;draining=true;owned=nil
                    report('foreign','Focused locomotion changed externally; release S before retrying')
                end
                return
            end
            if value=='\1'then report('native','Focused locomotion is already native');return end
            local before=snapshot()
            assert(before.safe and not before.seated and(before.camera_kind==4 or before.camera_kind==6)
                and focused_owner(before)and same(location(before),current),'Locomotion owner changed before acquisition')
            assert(backend:_read(current.address,1)=='\0','Focused locomotion changed before acquisition')
            current.before=value;owned=current
            store(current.address,'\1')
            local after=snapshot()
            assert(after.safe and not after.seated and(after.camera_kind==4 or after.camera_kind==6)
                and focused_owner(after)and same(location(after),current),'Locomotion owner changed during acquisition')
            state.writes=state.writes+1;report('active')
        end)
        if not ok then
            local reason=tostring(why)
            local clean,problem=self:stop()
            if not clean then return false,problem end
            report('unavailable',reason);return true,reason
        end
        if owned and state.phase=='cleanup_pending'then return false,state.reason end
        return true
    end
    function self:update(controller,skip)return update(controller,skip,false)end
    function self:update_fird(controller,skip)return update(controller,skip,true)end
    return self
end
return M
