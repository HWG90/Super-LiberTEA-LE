-- Validate the installed kit, retaining its loader and menu registration.
local api=assert(rawget(_G,'NativeADSCameraTest'),'Installed first-person API unavailable')
local ready,why=api.preflight();assert(ready,why)
local started,reason=api.start(20);out('Installed FP START',started,reason);assert(started,reason)
local begin=stingray.Application.time_since_launch()
local phase='active'
local function stop()
    if not started then return true end
    assert(rawget(_G,'NativeADSCameraTest')==api,'Installed first-person owner changed')
    local done,why=api.stop()
    out('Installed FP STOP',done,why)
    if done then started=false end
    return done,why
end
return function()
    -- The installed kit owns normal per-frame updates.
    if phase=='active'and stingray.Application.time_since_launch()-begin>=15 then
        local label,state=api.status()
        out('Installed FP active',label,state.phase,state.enabled)
        local depth,why=api.depth_stats()
        if depth then for k,v in pairs(depth)do out('Installed FP depth',k,v)end
        else out('Installed FP depth',why)end
        phase='restore'
    end
    if phase=='restore'then
        local done,why=stop()
        if done then
            local label,state=api.status()
            assert(state.enabled==false,'First person remained enabled after stop')
            out('Installed FP restored; kit remains loaded',LiveLuaLoader.modules['live/goose_temporary_unlocks'],label)
            return true
        end
    end
end,function()local done,why=stop();assert(done,why)end
