local PORT51=mod.require('src/first_person/compat51.lua')
-- Narrow HUD leases, not an optic/render hook. The game keeps updating local
-- opacity/reticle materials; only these two groups' shown bits are suppressed.
local M,Adapter={},{}
Adapter.__index=Adapter
local checks={
    {0x12e4e20,'4883ec28448b014c8bd1418bc0458bc883e0ef4183c91084d2440f44c8448909'},
    {0x1635ccf,'4d8da510010000'}, -- fixed crosshair group
    {0x1635d61,'498db520020000'}, -- moving aiming-circle group
    {0x117c88d,'498d8f78a61900e887934b00498d9778a61900'},
}
local function hex(bytes)return(bytes:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function valid_key(key)
    return type(key)=='string'and #key==16 and key:match('^[0-9a-f]+$')~=nil and key~='0000000000000000'
end
local function same(a,b)
    return a and b and a.game==b.game and a.root==b.root and a.state==b.state
        and a.parent==b.parent and a.context==b.context and a.world==b.world
end
function Adapter.new(backend,setter)return setmetatable({b=backend,setter=setter},Adapter)end
function Adapter:_validate()
    local b=self.b;local game=b:_module('identity') -- build identity; HUD witnesses below stay exact
    for _,check in ipairs(checks)do
        assert(hex(b:_read(game+check[1],#check[2]/2))==check[2],'Aiming HUD fingerprint differs')
    end
    return game
end
function Adapter:probe(mission_only)
    local b=self.b;local game=self:_validate()
    local state=b:_ptr(game+0x2ce1508)
    if mission_only and b:_u32(state+0xac29c)~=4 then return nil end
    local root=b:_ptr(game+0x2e28788)
    if b:_u8(root+0x24e334)~=1 then return nil end
    local crosshair=root+0x24e340+0x19a678
    local parent=b:_ptr(crosshair+0xf0)
    assert(parent==root+0x820,'Aiming HUD parent differs')
    local context=b:_ptr(crosshair+0xf8)
    if b:_u8(context)~=1 then return nil end
    local world=b:_ptr(context+0x10)
    local widgets={crosshair+0x110,crosshair+0x220}
    for _,widget in ipairs(widgets)do
        assert(b:_ptr(widget+0xf0)==crosshair and b:_ptr(widget+0xf8)==context,
            'Aiming HUD child ownership differs')
        assert(b:_u32(widget)~=0,'Aiming HUD child is not initialized')
    end
    return {game=game,root=root,state=state,parent=parent,context=context,world=world,widgets=widgets}
end
function Adapter:same(a,b)return same(a,b)end
function Adapter:visible(widget)return math.floor(self.b:_u32(widget)/16)%2==1 end
function Adapter:show(identity,widget,value)
    assert(widget==identity.widgets[1]or widget==identity.widgets[2],'Unowned aiming HUD target')
    assert(same(self:probe(false),identity),'Aiming HUD changed before write')
    if self.setter then self.setter(widget,value)
    else
        local w=self.b:_windows();local address=identity.game+0x12e4e20;local r=w.region
        assert(PORT51.number(w.k.NativeADS_Query(w.ffi.cast('const void *',address),r,w.ffi.sizeof(r)))==w.ffi.sizeof(r)
            and r.state==0x1000 and (r.kind==0x1000000 or (r.kind==0x40000 and w.wine
                and PORT51.number(r.allocation)==identity.game))
            and (r.protect==0x20 or r.protect==0x40 or r.protect==0x80),'HUD setter is not executable')
        w.ffi.cast('void (*)(uintptr_t,uint8_t)',address)(widget,value and 1 or 0)
    end
    assert(self:visible(widget)==value,'Aiming HUD visibility readback differs')
end

-- Camera kind 6 also covers ordinary native ADS with the F11 mode switched off.
-- A pinned action/vehicle camera supplies only view ownership, never a weapon
-- identity or authorization for a legacy per-weapon preference.
function M.source(backend,controller,options)
    local cached_identity,cached_key
    local function pinned_view(fresh)
        if fresh or backend.pin_first_person~=true or type(backend.pin_player_snapshot)~='function'
            or type(options.pinned_ready)~='function' or not controller:is_enabled()
            or controller:result().mode~='pose_offset'then return nil end
        local s=backend:pin_player_snapshot()
        if not s or s.foreign_camera or type(s.player_identity)~='string' or s.player_identity==''
            or options.pinned_ready(s)~=true then return nil end
        return {view_only=true,identity=s.player_identity..':pinned-view',player_identity=s.player_identity,
            aiming=s.shoulder_aim==true or s.controller_active==true or s.aiming==true}
    end
    return function(fresh)
        if options.foreign()then return nil end
        local fird=options.fird()
        local fird_active=fird and fird:is_enabled()
        local s
        if fird_active and not fresh then s=fird.weapon_snapshot
        else s=backend:snapshot()end
        if not s or not s.safe then return pinned_view(fresh)end
        local in_fp=s.camera_kind==6
        if s.camera_kind==4 then
            in_fp=fird_active or(controller:is_enabled()and controller:result().mode=='pose_offset'
                and options.fallback_ready())
        end
        if not in_fp then return pinned_view(fresh)end
        local key
        if fird_active and not fresh then key=fird.weapon_key
        elseif not fresh and cached_identity==s.identity then key=cached_key
        else
            local ok,value=pcall(function()return hex(backend:_read(backend:_pose_context(s).weapon_object+0x358,8))end)
            if not ok then
                local view=pinned_view(fresh);if view then return view end
                error(value,0)
            end
            key=value
            cached_identity,cached_key=s.identity,key
        end
        return {key=key,identity=s.identity,player_identity=s.player_identity,
            aiming=s.shoulder_aim==true or s.controller_active==true or s.aiming==true}
    end
end

-- current(fresh) supplies the owned FP weapon and aim state. A fresh read is
-- required for menu clicks so a delayed click cannot change the next weapon.
function M.new(backend,log,options,adapter)
    options=assert(options);adapter=adapter or Adapter.new(backend)
    log=log or function()end
    local self={lease=nil,fault=nil,closing=false}
    local function problem(why)
        why=tostring(why)
        if self.fault~=why then log('Aiming markers: '..why)end
        self.fault=why;return false,why
    end
    local function current(fresh)
        local target=options.current(fresh)
        if type(target)~='table'or type(target.identity)~='string'
            or type(target.player_identity)~='string'then return nil end
        if target.view_only==true then
            -- The all-view hide choice needs no firearm. A pin-only owner must
            -- never become a fabricated per-weapon setting or menu target.
            if target.key~=nil or type(options.global_setting)~='function'
                or options.global_setting()~=false then return nil end
        elseif not valid_key(target.key)then return nil end
        return target
    end
    local function global_setting()
        if type(options.global_setting)=='function'then
            local value=options.global_setting()
            if type(value)=='boolean'then return value end
        end
    end
    local function legacy_allowed(key)
        local saved=options.settings()
        return type(saved)=='table'and rawget(saved,key)==true
    end
    local function allowed(key)
        local value=global_setting()
        if value~=nil then return value end
        return legacy_allowed(key)
    end
    function self:setting()
        local ok,value=pcall(global_setting)
        if ok and value~=nil then return value end
        local read,target=pcall(current,false)
        if read and target and target.aiming==true then
            local loaded,allowed=pcall(legacy_allowed,target.key)
            return loaded and allowed==true
        end
        -- Legacy suppression applied only during aim. Before entry and at
        -- hip the game still owns visible markers until the user chooses.
        return true
    end
    function self:set_setting(value)
        if self.closing then return false,'Mod is stopping'end
        if type(value)~='boolean'then return false,'Aim-marker setting must be on or off'end
        if type(options.save_global)~='function'then return false,'Aim-marker setting is unavailable'end
        local called,saved,why=pcall(options.save_global,value)
        if not called then return false,tostring(saved)end
        if saved~=true then return false,why or'Aim-marker setting was not saved'end
        return self:update()
    end
    function self:target()
        if self.closing then return nil end
        local target=current(false)
        if target and not target.view_only then return {key=target.key,identity=target.identity,allowed=allowed(target.key)}end
    end
    function self:is_clean()return self.lease==nil end
    function self:stop()
        local lease=self.lease
        if not lease then return true end
        lease.releasing=true
        local ok,why=pcall(function()
            local live=adapter:probe(false)
            if adapter:same(live,lease.hud)then
                for _,entry in ipairs(lease.rows)do
                    if not entry.done then
                        if adapter:visible(entry.widget)==false then adapter:show(lease.hud,entry.widget,entry.before)end
                        entry.done=true
                    end
                end
            end -- A retired/rebuilt HUD must never receive old visibility.
            self.lease=nil
        end)
        if not ok then return problem(why)end
        return true
    end
    function self:update()
        local ok,done,why=pcall(function()
            if self.lease and self.lease.releasing then
                local released,reason=self:stop();if not released then return false,reason end
            end
            local target=not self.closing and current(false)or nil
            local global=global_setting()
            -- Hip view keeps the game's native crosshair and moving circle.
            -- The explicit hide choice covers aiming in every owned FP view;
            -- unset preferences retain the legacy per-weapon aim behavior.
            local suppress=target and target.aiming==true and(global==false
                or global==nil and not legacy_allowed(target.key))
            if not suppress then return self:stop()end
            -- An explicit all-view choice also covers the initialized ship HUD
            -- and pinned action views. Legacy weapon preferences stay mission-only.
            local hud=adapter:probe(global~=false)
            if not hud then return self:stop()end
            local lease=self.lease
            if lease and (lease.weapon~=target.identity or lease.player~=target.player_identity
                or not adapter:same(hud,lease.hud))then
                local released,reason=self:stop();if not released then return false,reason end
                lease=nil
            end
            if not lease then
                lease={hud=hud,weapon=target.identity,player=target.player_identity,rows={},by_widget={}}
                self.lease=lease
            end
            for _,widget in ipairs(hud.widgets)do
                if adapter:visible(widget)then
                    local entry=lease.by_widget[widget]
                    if not entry then
                        entry={widget=widget,before=true};lease.rows[#lease.rows+1]=entry;lease.by_widget[widget]=entry
                    end
                    -- Record ownership before calling: a native call can fail after writing.
                    adapter:show(hud,widget,false)
                end
            end
            self.fault=nil;return true
        end)
        if not ok then self:stop();return problem(done)end
        if done~=true then return problem(why)end
        self.fault=nil
        return true
    end
    function self:toggle(key,identity)
        if self.closing then return false,'Mod is stopping'end
        local loaded,global=pcall(global_setting)
        if not loaded then return false,tostring(global)end
        if global~=nil then return false,'Use Show aim markers to change all weapons'end
        local read,target=pcall(current,true)
        if not read then return false,tostring(target)end
        if not target or target.key~=key or target.identity~=identity then
            return false,'Weapon changed; select the aiming-marker setting again'
        end
        local values={}
        local previous=options.settings()
        for saved,value in pairs(type(previous)=='table'and previous or {})do if valid_key(saved)and value==true then values[saved]=true end end
        values[key]=not allowed(key)or nil
        local saved,why=options.save(values)
        if saved~=true then return false,why or 'Aiming-marker setting was not saved'end
        return self:update()
    end
    function self:shutdown()self.closing=true;return self:stop()end
    function self:result()return {hidden=self.lease~=nil,error=self.fault,cleanup_pending=self.lease~=nil and (self.closing or self.fault~=nil)}end
    return self
end
M.Adapter=Adapter
return M
