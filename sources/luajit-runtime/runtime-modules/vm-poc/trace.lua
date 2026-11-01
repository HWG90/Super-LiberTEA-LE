-- Attribute machine code to the unmodified mod, never to this observer.
if not jit then
    function poc_trace_report()print('POC_JIT enabled=false mod_traces=0 mod_machine_code=0 total_traces=0')end
    return
end
jit.off(true,true)
local u=require('jit.util')
local roots={}
local function trace(event,id,fn)
    if event=='start' and type(fn)=='function' then
        local info=u.funcinfo(fn)
        roots[id]=info.source or ''
    end
end
jit.attach(trace,'trace')
function poc_trace_report()
    local mod_traces,mod_bytes,total=0,0,0
    for id=1,65535 do
        if u.traceinfo(id) then
            total=total+1
            if (roots[id] or ''):find('mods/lll_poll_cache/src/poll_cache.lua',1,true) then
                local code=u.tracemc(id)
                mod_traces=mod_traces+1;mod_bytes=mod_bytes+(code and #code or 0)
            end
        end
    end
    print(string.format('POC_JIT enabled=%s mod_traces=%d mod_machine_code=%d total_traces=%d',
        tostring(jit.status()),mod_traces,mod_bytes,total))
end
