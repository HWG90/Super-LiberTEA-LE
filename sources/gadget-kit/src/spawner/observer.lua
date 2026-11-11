local PORT51=mod.require('src/first_person/compat51.lua')
-- Mission actor observer for the Goose Gadget Kit spawner, vendored from Bridge Combat's
-- src/runtime.lua (helpers, photo_state and M.observer). The only change: the game state must
-- be the one the caller passes (4 = in mission) instead of Bridge Combat's ship state 3.
local M = {}
local STAMP, EXE_STAMP = 0x6af322c1, 0x6af2d5e6
local BODY = string.char(0x97,0xFA,0x4D,0x29,0x4D,0x33,0x1C,0x4D)
local function word(bytes,offset)
    offset=offset or 0
    assert(PORT51.kind(bytes)=='string' and #bytes>=offset+4,'Ownership word is unreadable')
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    return a+b*256+c*65536+d*16777216
end
local function pointer(bytes)
    local n=word(bytes)+word(bytes,4)*4294967296
    assert(n>=65536 and n<2^47,'Ownership pointer is absent')
    return n
end
local function upvalue(fn,key,inspect)
    if PORT51.kind(fn)~='function' or PORT51.kind(inspect)~='function' then return end
    for index=1,100 do
        local name,value=inspect(fn,index)
        if not name then return end
        if name==key then return value end
    end
end
local function photo_state(globals)
    -- Current WJ publishes an acknowledged lifecycle state. Unknown or closing
    -- states retain the block; legacy discovery below remains available.
    local current=rawget(globals,'DBF_PHOTO_MODE_OWNER')
    if current~=nil then
        assert(PORT51.kind(current)=='table'and PORT51.kind(current.active)=='boolean','Photo Mode lifecycle owner is unreadable')
        if current.active then return true,true,tostring(current) end
        assert(current.state=='closed','Photo Mode cleanup is not acknowledged')
        return false,false,tostring(current)
    end

    local runtime=rawget(globals,'DBF_PHOTO_CAMERA_RUNTIME')
    local dbg=rawget(globals,'debug') or debug
    local inspect=PORT51.kind(dbg)=='table' and dbg.getupvalue
    local fn,controller=rawget(globals,'render'),nil
    for _=1,20 do
        if PORT51.kind(fn)~='function' then break end
        controller=upvalue(fn,'DBF_FREECAM',inspect)
            or upvalue(upvalue(fn,'bindings_step',inspect),'DBF_FREECAM',inspect)
        if controller then break end
        fn=upvalue(fn,'previous',inspect) or upvalue(fn,'original',inspect)
            or upvalue(fn,'forward',inspect)
    end
    if runtime==nil and controller==nil then return false,false,'none' end
    assert(runtime==nil or PORT51.kind(runtime)=='table','Photo runtime identity is unavailable')
    assert(PORT51.kind(controller)=='table','Photo pose ownership is unavailable')
    local photo=runtime and runtime.photo
        or upvalue(controller.camera_owned,'photo',inspect)
        or upvalue(controller.tick,'photo',inspect)
        or upvalue(upvalue(controller.tick,'original_tick',inspect),'photo',inspect)
    assert(PORT51.kind(photo)=='table' and PORT51.kind(photo.active)=='boolean','Photo camera ownership is unavailable')
    local poses=controller._poses
    assert(poses==nil or PORT51.kind(poses)=='table','Photo pose owner is unreadable')
    local fixed=poses and (poses.active or poses.pending) and true or false
    return photo.active,fixed,tostring(runtime)..'/'..tostring(controller)
end

-- Protected, read-only discovery. The key describes ownership, never movement,
-- weapon selection, stance or the Photo Mode epoch.

-- Missions have no ship loadout-definition row (lc) for the avatar, which Bridge Combat's backend
-- requires for its ship animations. Support delivery needs only the player manager row, its
-- descriptor and control row, so rebuild those with the backend's own checks.
local function mission_view(backend)
    local view,why=backend:observe()
    if PORT51.kind(view)~='table' or view.avatar or not view.pm or not view.world then return view,why end
    local avatar=backend:_avatar(view.game,view.world)
    if not avatar then return view,why end
    local pi=backend:hashmap(view.pm+0xF8,avatar)
    if not pi or pi>=128 then return view,'Local avatar player row is unavailable' end
    local ep=backend:ptr(view.pm+0x110+pi*8);local live=ep and backend:u8(ep+0x14)
    if not ep or backend:u32(ep+8)~=avatar or not live or backend.bit.band(live,1)==0 then
        return view,'Local avatar descriptor is unavailable or retired'
    end
    local pc=view.pm+0x53D8B0+pi*0x1240
    if not backend:read(pc+0xFE0,12) then return view,'Local avatar control row is unreadable' end
    view.avatar,view.ep,view.pc=avatar,ep,pc
    return view
end

function M.observer(backend,io,globals,scene)
    globals=globals or _G
    return function()
        local view,why=mission_view(backend)
        if PORT51.kind(view)~='table' or view.scene~=scene or view.stamp~=STAMP or not view.avatar then
            return nil,why or 'Waiting for a local mission actor'
        end
        local samples={}
        local function read(at,size)
            local bytes,reason=io.read(at,size)
            assert(PORT51.kind(bytes)=='string' and #bytes==size,reason or 'Actor ownership is unreadable')
            samples[#samples+1]={at,size,bytes};return bytes
        end
        local function p(at)return pointer(read(at,8))end
        local function u(at)return word(read(at,4))end
        local exe,_,stamp=io.module('helldivers2.exe')
        assert(exe and stamp==EXE_STAMP,'Unsupported animation executable')
        local state=p(view.game+0x2ce1508)
        assert(u(state+0xac29c)==scene and p(view.game+0x2ce41b8)==view.world
            and p(view.game+0x2ce1ee0)==view.pm and p(view.game+0x2ce1eb8)==view.lc,
            'Actor managers changed during observation')
        local player=p(view.game+0x2ce1618);local local_unit=u(player+0x3A8)
        assert(local_unit>0 and local_unit~=0xFFFFFFFF,'Local player Unit is absent')
        local local_count=u(player+0x88);assert(local_count>0 and local_count<=128,'Local player descriptors are unavailable')
        local local_descriptor=p(player+0xE8);local pid=u(local_descriptor+8)
        assert(pid>0 and pid~=0xFFFFFFFF,'Actual PlayerManager entity is absent')
        local descriptor=read(view.ep,24)
        assert(word(descriptor,8)==view.avatar and descriptor:byte(21)%2==1,'Actor descriptor is retired')
        local reference=word(descriptor,12)
        assert(reference>0 and reference~=0xFFFFFFFF,'Actor Unit reference is absent')
        local registry=p(exe+0x1ab76f8)
        local count=u(registry+0x98);local index=reference%4194304
        assert(count>0 and count<=0x1000000 and index<count,'Actor registry bounds differ')
        local generations,units=p(registry+0xA0),p(registry+0x88)
        assert(read(generations+index,1):byte()==math.floor(reference/4194304),'Actor generation changed')
        local unit=p(units+index*8)
        assert(u(unit+8)==reference and read(unit+0x358,8)==BODY,'Actor body Unit differs')
        local animator=p(unit+0x178);local graph=p(animator+0x28)
        assert(u(graph+4)==31,'Actor body graph differs')
        local states=p(animator+0x50)
        local context=backend.bit.band(u(view.pc+0xfd8),6)
        local menu=p(view.game+0x2e38160)
        local current,depth=u(menu+0x4294),u(menu+0x42B0)
        assert(current<53 and depth<=5,'Native menu bounds differ')
        local menu_closed=current==0 and depth==0
        local mcm=(rawget(globals,'GOOSE_BRIDGE_SERVICES')or rawget(globals,'DBFMCM'))
        local mcm_ready=PORT51.kind(mcm)=='table' and (PORT51.kind(mcm.register)=='function'or PORT51.kind(mcm.camera_input)=='table')
        local photo,fixed,photo_provider=photo_state(globals)
        local overlap=false
        for _,key in ipairs({'NOVA_BRIDGE_EXIT_POSE_TEST','NOVA_BRIDGE_BLEND_POSE_TEST',
            'NOVA_BRIDGE_BODY_LAYER_TEST','NOVA_BRIDGE_REST_POSE_TEST'}) do
            if rawget(globals,key) then overlap=true end
        end
        -- Re-read sampled identities; an in-progress Armory/actor transition is
        -- not a stable observation, even if each individual read succeeded.
        for _,sample in ipairs(samples)do
            assert(io.read(sample[1],sample[2])==sample[3],'Actor or menu changed during observation')
        end
        local reason=not mcm_ready and 'Waiting for DBF-MCM'
            or overlap and 'A private bridge test still owns the actor'
            or not menu_closed and 'A game menu is open'
            or fixed and 'Photo Mode owns a fixed pose'
            or photo and 'Photo Mode camera is active'
            or context~=2 and 'Waiting for combat controls' or nil
        local key={view.game,view.stamp,state,view.world,player,local_unit,local_descriptor,pid,view.pm,view.lc,view.avatar,view.ep,
            -- Current registry arrays were sealed above; their allocations can
            -- move without changing the captured logical Unit/body ownership.
            descriptor:sub(1,16),exe,registry,reference,unit,animator,graph,states,
            tostring(mcm),photo_provider}
        for i,value in ipairs(key)do key[i]=tostring(value)end
        return {token=table.concat(key,':'),base=view,pid=pid,resource=descriptor:sub(1,8),
            render=reference,context=context,menu_closed=menu_closed,photo=photo,fixed_pose=fixed,
            ready=mcm_ready and not overlap and menu_closed and not photo and not fixed and context==2,
            hold=mcm_ready and not overlap and menu_closed and photo and not fixed,
            can_start=mcm_ready and not overlap and menu_closed and not photo and not fixed,
            reason=reason}
    end
end


return M
