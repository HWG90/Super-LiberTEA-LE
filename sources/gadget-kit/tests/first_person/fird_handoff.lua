local H=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_handoff.lua')
local function fixture()
    local f={time=0,stops=0,starts=0,ready=false}
    f.entry=H.new(function()f.stops=f.stops+1;if f.throw then error('cleanup error')end;return f.ready,'cleanup pending'end,
        function(reference)f.starts=f.starts+1;f.reference=reference;return not f.refuse,'start refused'end,
        function()return f.time end)
    return f
end
local f=fixture();local reference={source_fov=1.5}
assert(f.entry:request(reference));assert(f.entry:is_pending()and f.starts==0)
assert(not f.entry:request({}));f.time=.5;assert(f.entry:update());assert(f.starts==0)
f.ready=true;assert(f.entry:update());assert(f.starts==0 and f.entry:is_pending())
assert(f.entry:update());assert(f.starts==1 and f.reference==reference and not f.entry:is_pending())
assert(f.entry:update());assert(f.starts==1)
f=fixture();assert(f.entry:request(reference));assert(f.entry:cancel());f.ready=true;assert(f.entry:update());assert(f.starts==0)
f=fixture();assert(f.entry:request(reference));f.time=4;assert(not f.entry:update());assert(not f.entry:is_pending()and f.starts==0)
f=fixture();f.throw=true;assert(not f.entry:request(reference));assert(not f.entry:is_pending()and f.starts==0)
f=fixture();f.ready,f.refuse=true,true;assert(f.entry:request(reference));assert(not f.entry:update());assert(not f.entry:is_pending()and f.starts==1)
print('Fird Person handoff: cleanup acknowledgement, cancellation, timeout and one-shot start passed')
