-- One presentation clock for camera displacement, native rig additions and lens.
-- Pure scalar state: no pointers, engine calls, input sampling or bone poses.
local M={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function text(v)return type(v)=='string'and v~=''end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
-- Match the native camera's positive firearm-ADS classification. A seated
-- or scripted action may reuse the ADS-shaped byte without owning the sights.
function M.native_ads(s)
    if type(s)~='table'or s.controller_active~=true or s.seated~=false then return false end
    local bytes=s.controller_bytes
    if type(bytes)~='string'or #bytes~=6 or bytes:byte(6)~=0 or bytes:byte(5)==0 then return false end
    local a,b,c,d=bytes:byte(1,4);local mask=a+b*256+c*65536+d*16777216
    return mask==0 or mask==2
end
function M.new(options)
    options=options or{}
    local duration=options.duration or .18
    local max_gap=options.max_gap or .25
    assert(finite(duration)and duration>=.08 and duration<=.5,'Invalid transition duration')
    assert(finite(max_gap)and max_gap>=duration and max_gap<=1,'Invalid transition gap')
    local self={};local packet,previous,started,epoch=nil,nil,nil,0
    local function retire(reason)
        packet,previous,started=nil,nil,nil
        return nil,reason
    end
    function self:reset(reason)return retire(reason or'reset')end
    function self:update(s,now,enabled,blocked)
        if enabled~=true or blocked==true then return retire(blocked and'foreign'or'disabled')end
        if not finite(now)or type(s)~='table'or not text(s.player_identity)or not text(s.identity)
            or type(s.controller_active)~='boolean'then return retire('snapshot unavailable')end
        if previous and(now<previous.time or now-previous.time>max_gap or s.player_identity~=previous.player_identity)then
            -- A new world/body, teleport-shaped time gap or clock rollback is
            -- not a visual handoff. Discard every carried presentation term.
            retire('identity or clock changed')
        end
        local ads=s.controller_active
        local reason
        if not previous then reason='initial'
        elseif s.identity~=previous.identity then reason='weapon'
        elseif ads~=previous.ads then reason=ads and'ads_enter'or'ads_leave'
        elseif s.zoom_identity~=nil and previous.zoom_identity~=nil and s.zoom_identity~=previous.zoom_identity then reason='zoom'
        elseif s.shoulder_aim~=previous.shoulder_aim then reason='shoulder'
        elseif s.action~=nil and previous.action~=nil and s.action~=previous.action then reason='action'
        elseif s.seated~=previous.seated then reason='seat'
        elseif s.camera_kind~=previous.camera_kind and not((s.camera_kind==4 or s.camera_kind==6)and(previous.camera_kind==4 or previous.camera_kind==6))then reason='camera'end
        if reason then
            epoch=epoch+1;started=now
            packet={epoch=epoch,progress=reason=='initial'and 1 or 0,ads=ads,
                reason=reason,identity=s.identity,player_identity=s.player_identity,
                started=now,duration=duration,continuous=reason~='initial'and reason~='weapon'}
        elseif packet then packet.progress=math.max(packet.progress,math.max(0,math.min(1,(now-started)/duration)))end
        local observed_action=s.action~=nil and s.action or(previous and previous.action)
        local observed_zoom=s.zoom_identity~=nil and s.zoom_identity or(previous and previous.zoom_identity)
        previous={identity=s.identity,player_identity=s.player_identity,ads=ads,zoom_identity=observed_zoom,
            action=observed_action,shoulder_aim=s.shoulder_aim,seated=s.seated,camera_kind=s.camera_kind,time=now}
        if packet then packet.ads=ads;return copy(packet)end
    end
    -- The verified motion sampler learns native action edges after the main
    -- player snapshot. It may retarget this same Update, before lens/camera
    -- publication; no new frame/input authority is created here.
    function self:action(action,now)
        if not packet or not previous or not text(action)or not finite(now)or now<previous.time or now-previous.time>max_gap then return nil end
        if previous.action~=nil and previous.action~=action then
            epoch=epoch+1;started=now
            packet={epoch=epoch,progress=0,ads=previous.ads,reason='action',identity=previous.identity,
                player_identity=previous.player_identity,started=now,duration=duration,continuous=true}
        end
        previous.action=action
        return packet and copy(packet)or nil
    end
    function self:resume(identity,player_identity,now)
        if not packet or not previous or packet.identity~=identity or packet.player_identity~=player_identity
            or not finite(now)or now<previous.time or now-previous.time>max_gap then return nil end
        epoch=epoch+1;started=now
        packet={epoch=epoch,progress=0,ads=previous.ads,reason='reacquire',identity=identity,
            player_identity=player_identity,started=now,duration=duration,continuous=true}
        return copy(packet)
    end
    function self:result()return packet and copy(packet)or nil end
    return self
end
return M
