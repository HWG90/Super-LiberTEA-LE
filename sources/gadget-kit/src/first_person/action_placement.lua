local PORT51=mod.require('src/first_person/compat51.lua')
-- Pure action-profile policy. No game reads, timers, or animation commands.
local M={}
-- Catalogue types are authored 64-bit IDs; placement keys are their exact
-- little-endian object bytes. Only catalogue-backed firearms get a family.
local weapons={}
local baselines={
    rifle={x=.15,y=0,z=-.12}, compact={x=.12,y=0,z=-.09},
    sidearm={x=.105,y=0,z=-.08}, marksman={x=.14,y=.015,z=-.115},
    shotgun={x=.14,y=.005,z=-.11}, energy={x=.15,y=0,z=-.115},
    support={x=.16,y=.015,z=-.14},
}
local function family(row)
    local name=row.name
    if PORT51.kind(name)~='string' or name:match('^CQC') or name:match('^Item ') or name:match('^Unidentified') or name:match('^B/') or name=='Breaching Hammer' then return nil end
    if row.kind==3 then return 'sidearm' end
    if row.kind==2 then return 'support' end
    if row.kind~=1 then return nil end
    if name:match('^SMG') or name:match('^MP%-') or name:match('^M7S ') or name:match('^StA%-11 ') then return 'compact' end
    if name:match('^SG%-') or name:match('^DBS%-') or name:match('^M90A ') then return 'shotgun' end
    if name:match('^R%-') or name:match('^R/') then return 'marksman' end
    if name:match('^LAS%-') or name:match('^PLAS%-') or name:match('^ARC%-') or name:match('^FLAM%-') then return 'energy' end
    if name:match('^AR') or name:match('^BR%-') or name:match('^MA5C ') or name:match('^StA%-52 ') then return 'rifle' end
end
function M.configure_catalogue(gear)
    local next_weapons={}
    for _,row in ipairs(PORT51.kind(gear)=='table' and gear or {})do
        local f=PORT51.kind(row)=='table' and family(row)
        local id=f and row.type
        if PORT51.kind(id)=='string' and #id==16 and id:match('^%x+$')then
            local bytes={};for at=15,1,-2 do bytes[#bytes+1]=id:sub(at,at+1):lower()end
            local key=table.concat(bytes)
            -- Duplicate types must agree; an ambiguous type never receives a
            -- composition guess just because one catalogue row came first.
            local old=next_weapons[key]
            if old and(old.name~=row.name or old.family~=f)then next_weapons[key]=false
            elseif old~=false then next_weapons[key]={key=key,name=row.name,family=f,kind=row.kind,item=row.id}end
        end
    end
    weapons=next_weapons
end
function M.weapon_info(key)
    local v=weapons[key];if not v then return nil end
    return {key=v.key,name=v.name,family=v.family,kind=v.kind,item=v.item}
end
function M.family_baseline(key)
    local v=weapons[key];v=v and baselines[v.family]
    if v then return {x=v.x,y=v.y,z=v.z,yaw=0,pitch=0,roll=0}end
end
local RESOURCE='4D1C334D294DFA97'
M.observed_actions={crouch=true,prone=true,slide=true,dive=true}
-- Labelled sequence 2026-10-18: stand / crouch / prone / slide / dive.
-- Flags are copied from the sampler's existing current-frame snapshot.
local function stance(sample)
    if sample.action_resource~=RESOURCE or sample.action_verified~=true then return nil end
    local f=sample.stance_flags
    if PORT51.kind(f)~='string' or #f~=24 then return nil end
    local posture=math.floor(f:byte(10)/32)%4*32
    -- Native posture/action flags survive locomotion blend-state changes and
    -- bridge/mission animation variants. Layer indices are not posture IDs.
    if posture==0x40 and math.floor(f:byte(13)/32)%2~=0 then return 'dive'end
    if posture==0x20 and math.floor(f:byte(11)/2)%2~=0 then return 'slide'end
    if posture==0x20 then return 'crouch'end
    if posture==0x40 then return 'prone'end
end
M.actions={{'idle','Idle'},{'aim','Normal aim'},{'ads','ADS'},{'sprint','Sprinting'},
    {'reload','Reloading'},{'crouch','Crouching'},{'prone','Prone'},{'slide','Sliding'},{'dive','Diving'}}
local allowed={};for _,a in ipairs(M.actions)do allowed[a[1]]=true end
function M.valid(p)
    if PORT51.kind(p)~='table'then return false end
    for _,axis in ipairs({'x','y','z'})do local n=p[axis]
        if PORT51.kind(n)~='number' or n~=n or math.abs(n)>.5 then return false end
    end
    for _,axis in ipairs({'yaw','pitch','roll'})do local n=p[axis]or 0
        if PORT51.kind(n)~='number' or n~=n or math.abs(n)>90 then return false end
    end;return true
end
local function copy(p)return {x=p.x,y=p.y,z=p.z,yaw=p.yaw or 0,pitch=p.pitch or 0,roll=p.roll or 0}end
function M.resolve(config,key,action)
    config=config or {};action=action or 'idle';assert(allowed[action],'Unknown placement action')
    local profiles=config.action_placements or {}
    local individual=key and profiles[key]
    local shared=profiles.__all
    local v=PORT51.kind(individual)=='table' and individual[action]
    if not M.valid(v)then v=PORT51.kind(shared)=='table' and shared[action]end
    if M.valid(v)then return copy(v),true end
    if action=='ads'then return {x=0,y=0,z=0},false end
    if action~='idle'then local idle=M.resolve(config,key,'idle');return idle,false end
    local old=config.weapon_placements or {}
    v=key and old[key] or nil
    if not M.valid(v)then v=old.__all end
    if M.valid(v)then return copy(v),false end
    -- All saved placements, including a customised global baseline, retain
    -- precedence. Family defaults are opt-in and never rewrite saved values.
    v=config.placement
    local standard=M.valid(v) and v.x==.15 and v.y==0 and v.z==-.12
        and(v.yaw or 0)==0 and(v.pitch or 0)==0 and(v.roll or 0)==0
    if config.family_placement_defaults==true and(not M.valid(v)or standard)then
        local baseline=M.family_baseline(key);if baseline then return baseline,false end
    end
    return M.valid(v)and copy(v)or{x=.15,y=0,z=-.12},false
end
function M.default_placement(config,key,action)
    if action=='ads'then return {x=0,y=0,z=0,yaw=0,pitch=0,roll=0}end
    local baseline=config and config.family_placement_defaults==true and M.family_baseline(key)
    return baseline or{x=.15,y=0,z=-.12,yaw=0,pitch=0,roll=0}
end
function M.saved(config,key,action,value,all)
    assert(allowed[action] and M.valid(value),'Invalid action placement')
    assert(PORT51.kind(key)=='string' and #key==16,'Invalid weapon identity')
    local out={}
    for id,profile in pairs((config or {}).action_placements or {})do
        if PORT51.kind(profile)=='table'then
            local row={};for a,v in pairs(profile)do
                if allowed[a] and M.valid(v) and not(all and a==action)then row[a]=copy(v)end
            end;out[id]=row
        end
    end
    local id=all and '__all' or key;out[id]=out[id]or{};out[id][action]=copy(value)
    return out
end
function M.select(sample,mapping)
    if sample.ads==true or PORT51.kind(sample.ads)=='number' and sample.ads>=1 then return 'ads'end
    local pose=stance(sample)
    if pose=='slide' or pose=='dive'then return pose end
    -- Reload animates over normal aim, sprint and posture; keep it visible.
    if sample.reload then return 'reload'end
    if sample.shoulder_aim then return 'aim'end
    if sample.sprint then return 'sprint'end
    if pose then return pose end
    -- Optional mappings remain scoped to a verified resource.
    local map=mapping and mapping[sample.action_resource]
    if sample.action_verified and PORT51.kind(map)=='table'then
        local action=map[tostring(sample.l1)..':'..tostring(sample.l3)]
        if allowed[action]then return action end
    end
    return 'idle'
end
return M
