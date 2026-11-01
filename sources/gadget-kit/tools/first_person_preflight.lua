-- No camera entry, dispatch replacement, gameplay hold or input capture.
local root='Z:/home/goose/Documents/ChatGPT/GooseGadgets/Goose Gadget Kit'
local cache,env={},setmetatable({},{__index=_G})
local host={dir=root,config={first_person={}},log=function(s)out(s)end}
function host.require(name)
    if cache[name]then return cache[name]end
    local file=assert(io.open(root..'/'..name,'rb'));local source=file:read('*a');file:close()
    local chunk=assert(loadstring(source,'@first-person/'..name));setfenv(chunk,env)
    local value=chunk();cache[name]=value;return value
end
env.mod=host
local backend=host.require('src/first_person/backend.lua').new(out)
local snapshot,why=backend:snapshot();assert(snapshot,why)
out('FP snapshot',snapshot.avatar,snapshot.body,snapshot.weapon,snapshot.camera_kind,snapshot.avatar_index,snapshot.safe,snapshot.reason,snapshot.action_state_error)
local player=assert(backend:player_snapshot())
out('FP player ownership',player.identity,player.safe)
local w=backend:_windows();local f=w.ffi;local root=backend:_ptr(snapshot.base+0x2ce14c8);local slot=backend:_ptr(root+0x20)+0x80
w.k.NativeADS_Query(f.cast('void *',slot),w.region,f.sizeof(w.region))
out('FP slot region',host.require('src/first_person/compat51.lua').number(w.region.base),host.require('src/first_person/compat51.lua').number(w.region.allocation),host.require('src/first_person/compat51.lua').number(w.region.protect),host.require('src/first_person/compat51.lua').number(w.region.kind))
for _,key in ipairs({'allowed','enter','exit'})do
 local address=snapshot.base+backend.profile.functions[key]
 w.k.NativeADS_Query(f.cast('void *',address),w.region,f.sizeof(w.region))
 local P=host.require('src/first_person/compat51.lua')
 out('FP game region',key,P.number(w.region.allocation),P.number(w.region.protect),P.number(w.region.kind),w.wine)
end
for _,name in ipairs({'fov','blur','camera'})do
    local policy=host.require('src/first_person/'..name..'.lua').new(backend,out,nil,stingray.Application.time_since_launch)
    local ok,reason=policy:preflight();out('FP '..name..' read-only validation',ok,reason)
    assert(ok,reason)
end
local ok,reason=backend:prepare_pose(snapshot);out('FP pose read-only validation',ok,reason);assert(ok,reason)
local alignment,why=backend:prepare_alignment(snapshot);out('FP alignment read-only validation',alignment~=nil,why);assert(alignment,why)
local action,reason=backend:action_state(snapshot);assert(action,reason)
out('FP animation',action.resource_match,action.layer_count,action.l14,action.l3)
assert(backend:renderer_dof_value(stingray.Application.render_setting,stingray.Application.set_render_setting)~=nil)
out('FP read-only preflight passed')
return true
