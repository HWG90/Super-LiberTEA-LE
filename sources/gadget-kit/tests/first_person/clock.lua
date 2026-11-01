-- Exercise the actual factory using the shipped engine API shape. These
-- injected samples validate units/ownership, not live clock resolution.
local original=stingray
local time=12.5
stingray={Application={time_since_launch=function()return time end}}
local entry=assert(loadfile(NATIVE_ADS_TEST_ROOT..'/main.lua'))()
local factory
for i=1,80 do
    local name,value=debug.getupvalue(entry.on_enable,i)
    if not name then break end
    if name=='monotonic_clock'then factory=value;break end
end
assert(type(factory)=='function','Runtime clock factory unavailable')
local clock=factory()
local first=clock();local previous=first
assert(type(first)=='number'and first==first and first>=0 and first<math.huge)
for _=1,2000 do
    time=time+.000125
    local current=clock()
    assert(current>=previous,'Runtime clock moved backwards')
    previous=current
end
assert(previous>first and math.abs(previous-first-.25)<1e-8,'Engine seconds were rescaled')
assert(clock()==previous,'Equal engine samples must be preserved')
time=time-1;assert(not pcall(clock),'Backward engine clock accepted')
for _,bad in ipairs({-1,math.huge,'bad'})do time=bad;assert(not pcall(clock))end
time=0/0;assert(not pcall(clock))
stingray={};assert(not pcall(factory),'Missing engine clock accepted')
stingray=original
print('Native ADS engine runtime clock contracts passed')
