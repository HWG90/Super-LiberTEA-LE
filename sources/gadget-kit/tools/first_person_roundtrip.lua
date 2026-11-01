-- Short, bounded live activation through the integrated service. Always restores.
local root='Z:/home/goose/Documents/ChatGPT/GooseGadgets/Goose Gadget Kit'
local cache,env={},setmetatable({},{__index=_G})
local host={dir=root,config={first_person={}},scope={},log=function(s)out(s)end}
function host.set(key,value)host.config[key]=value;return true end
function host.require(name)
    if cache[name]then return cache[name]end
    local file=assert(io.open(root..'/'..name,'rb'));local source=file:read('*a');file:close()
    local chunk=assert(loadstring(source,'@first-person/'..name));setfenv(chunk,env)
    local value=chunk();cache[name]=value;return value
end
env.mod=host
local service=host.require('src/first_person.lua')
assert(service.enable())
local api=assert(rawget(_G,'NativeADSCameraTest'))
local begin=stingray.Application.time_since_launch()
local phase,frames='warmup',0
local cleaned=false
local function cleanup()
    local done,why=service.shutdown()
    if done then cleaned=true end
    out('FP cleanup',done,why)
    assert(done,why)
end
return function()
    frames=frames+1
    service.update()
    local elapsed=stingray.Application.time_since_launch()-begin
    if phase=='warmup'and elapsed>=.2 then
        local ready,why=api.preflight();out('FP integrated preflight',ready,why)
        if not ready then phase='cleanup';return end
        local ok,reason=api.start(20);out('FP integrated START',ok,reason)
        if not ok then phase='cleanup';return end
        phase='active';begin=stingray.Application.time_since_launch()
    elseif phase=='active'and elapsed>=15 then
        local label,state=api.status()
        out('FP active status',label,state.phase,state.enabled,state.camera and state.camera.phase,state.head and state.head.phase)
        local backend=host.require('src/first_person/backend.lua').new(out)
        local snapshot,why=backend:snapshot()
        out('FP active native camera',snapshot and snapshot.camera_kind,why)
        local depth,why=api.depth_stats();if depth then for k,v in pairs(depth)do out('FP depth',k,v)end else out('FP depth unavailable',why)end
        local done,why=api.stop();out('FP integrated STOP',done,why)
        phase='cleanup'
    elseif phase=='cleanup'then
        local done,why=service.shutdown()
        if done then cleaned=true;out('FP integrated roundtrip restored',frames);return true end
        if frames%30==0 then out('FP restoration pending',why)end
    end
end,function()if not cleaned then cleanup()end end
