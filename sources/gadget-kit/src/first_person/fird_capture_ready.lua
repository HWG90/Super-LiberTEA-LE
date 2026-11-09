local PORT51=mod.require('src/first_person/compat51.lua')
-- A read-only gate for the short native-FP sampling session. Runtime supplies
-- one tick per host update, after its existing pose/FOV/camera owners update.
local M={}
local function finite(n)return PORT51.kind(n)=='number'and n==n and math.abs(n)<math.huge end
local function lens(n)return finite(n)and n>=math.rad(10)and n<=math.rad(170)end
local function enabled(n)return n==true or n==1 end
local function healthy(s,phase)
    return PORT51.kind(s)=='table'and enabled(s.installed)and enabled(s.armed)
        and s.error==0 and not enabled(s.expired)and not s.cleanup_pending and(not phase or s.phase==phase)
end
function M.scene_lens(b,s)
    local ok,value=pcall(function()
        assert(PORT51.kind(s)=='table'and finite(s.camera),'First-person camera unavailable')
        local exe=b:_alignment_executable()
        assert(b:_read(exe+0x2dcfc0,6)=='\243\015\016\065\052\195','First-person FOV getter changed')
        local out=PORT51.ffi.new('float[1]');PORT51.ffi.copy(out,b:_read(s.camera+0x34,4),4)
        local radians=PORT51.number(out[0]);assert(lens(radians),'First-person display lens is outside10..170degrees')
        return radians
    end)
    if not ok then return nil,tostring(value)end
    return value
end
local identity_fields={'identity','player_identity','request','weapon_key','weapon_unit','viewmodel','body','camera','context','rig_object','weapon_object'}
local function observation(sample)
    if PORT51.kind(sample)~='table'then return nil,'First-person observation unavailable'end
    local s,c,lease=sample.snapshot,sample.controller,sample.lease
    if PORT51.kind(s)~='table'or not s.safe or s.camera_kind~=6 or s.aiming or s.controller_active
        or s.shoulder_aim or s.reloading or sample.neutral~=true then return nil,'Waiting for a neutral first-person pose'end
    if PORT51.kind(c)~='table'or c.mode~='pose_offset'or c.phase~='running'or c.cleanup_pending or c.enabled==false then
        return nil,'Waiting for the first-person pose owner'
    end
    local a=PORT51.kind(lease)=='table'and lease.alignment or nil
    if not a or a.kind~='pose'or a.ended or lease.done or lease.cleanup_only
        or PORT51.kind(lease.origin)~='table'or lease.origin.identity~=s.identity
        or lease.origin.player_identity~=s.player_identity or lease.request~=s.record then
        return nil,'First-person request ownership changed'
    end
    local target=sample.target
    if PORT51.kind(target)~='table'or target.safe~=true or target.player_identity~=s.player_identity
        or target.weapon_identity~=s.identity or target.camera_kind~=6
        or PORT51.kind(target.weapon_key)~='string'or not target.weapon_key:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$')then
        return nil,'First-person weapon identity changed'
    end
    if not healthy(sample.pose)or not finite(sample.pose.blend)or sample.pose.blend<.9999
        or not finite(sample.pose.target_weight)or sample.pose.target_weight<.9999 then
        return nil,'Waiting for first-person placement to settle'
    end
    if PORT51.kind(sample.motion)~='table'or sample.motion.phase~='capture'or sample.motion.capture_ready~=true then
        return nil,'Waiting for neutral first-person motion'
    end
    if not healthy(sample.fov,'active')or not healthy(sample.camera,'active')then return nil,'Waiting for the camera and FOV owners'end
    local actual=sample.lens;local applied=sample.fov.last_applied;local degrees=sample.fov.source_degrees
    if not lens(actual)or not lens(applied)or not finite(degrees)or degrees<10 or degrees>170
        or math.abs(actual-applied)>.0001 or math.abs(actual-math.rad(degrees))>.0001 then
        return nil,'Waiting for the displayed first-person lens'
    end
    local tick=sample.tick or sample.frame
    if not finite(tick)or tick<0 or tick~=math.floor(tick)then return nil,'First-person update tick unavailable'end
    local context=a.context
    if PORT51.kind(context)~='table'or not finite(context.object)or not finite(context.weapon_object)then
        return nil,'First-person rig ownership unavailable'
    end
    local out={identity=s.identity,player_identity=s.player_identity,request=s.record,weapon_key=target.weapon_key,
        weapon_unit=s.weapon_unit,viewmodel=s.viewmodel,body=s.body,camera=s.camera,context=s.context,
        rig_object=context.object,weapon_object=context.weapon_object,lens=actual,tick=tick,lease=lease}
    if PORT51.kind(out.identity)~='string'or out.identity==''or PORT51.kind(out.player_identity)~='string'or out.player_identity==''then
        return nil,'First-person player identity unavailable'
    end
    for _,key in ipairs({'request','weapon_unit','viewmodel','body','camera','context','rig_object','weapon_object'})do
        if not finite(out[key])or out[key]<=0 then return nil,'First-person unit or camera identity unavailable'end
    end
    return out
end
function M.new(clock,options)
    assert(PORT51.kind(clock)=='function','First-person capture clock required')
    options=options or{}
    local settle=options.settle_seconds or .18;local frames=options.minimum_ticks or 3;local gap=options.max_gap_seconds or .25
    assert(finite(settle)and settle>=.15 and settle<=1 and finite(frames)and frames>=3 and frames<=60
        and frames==math.floor(frames)and finite(gap)and gap>=.05 and gap<=1,'Invalid first-person stabilization window')
    local self={};local first,last,start,previous,count
    function self:reset()first,last,start,previous,count=nil,nil,nil,nil,nil;return true end
    local function reset(reason)self:reset();return false,reason end
    function self:update(sample)
        local current,why=observation(sample);if not current then return reset(why)end
        local ok,now=pcall(clock)
        if not ok or not finite(now)or now<0 then return reset('First-person capture clock unavailable')end
        local changed=not first or current.lease~=first.lease
        if first then
            for _,key in ipairs(identity_fields)do if current[key]~=first[key]then changed=true;break end end
            if math.abs(current.lens-first.lens)>.0001 then changed=true end
        end
        if previous and(now<previous or now-previous>gap)then changed=true end
        if last and current.tick<last then changed=true end
        if changed then first,start,count=current,now,0;last=nil end
        if current.tick==last then return false,'Waiting for the next first-person update'end
        if current.tick~=last then count=count+1;last=current.tick end
        previous=now
        if count<frames or now-start<settle then return false,'Waiting for stable first-person placement and FOV'end
        return true,current
    end
    return self
end
return M
