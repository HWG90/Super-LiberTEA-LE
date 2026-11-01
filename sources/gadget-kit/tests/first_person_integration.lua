local host={config={enabled=false,first_person={motion_scale=.5}},log=function()end}
function host.set(k,v)host.config[k]=v;return true end
mod=host
local FP=dofile('src/first_person.lua')
local runtime,virtual,starts,stops,pending,changed,updates
runtime={on_enable=function()
    virtual=FP.menu_api().register({pages={{controls={
        {id='start_test',type='button',on_activate=function()starts=(starts or 0)+1 end},
        {id='motion_strength',type='slider',default=100},
        {id='runtime_status',type='text',label='First person off'},
    }}},on_change=function()changed=(changed or 0)+1 end})
end,on_update=function()updates=(updates or 0)+1;if runtime.fail then error('fixture update failure')end end,
on_disable=function()stops=(stops or 0)+1;if pending then return false,'Pending camera restoration'end;virtual.unregister();return true end}
function host.require(name)
    if name=='src/first_person.lua'then return FP end
    assert(name=='src/first_person/runtime.lua');return runtime
end
DBFMCM={mods={}}
local registrations=0
function DBFMCM.register(spec)
    registrations=registrations+1
    local h,values,controls={},{},{}
    for _,page in ipairs(spec.pages)do for _,c in ipairs(page.controls)do
        if c.id then controls[c.id]=c;values[c.id]=c.default end
    end end
    function h.get(id)return values[id]end
    function h.unregister()DBFMCM.mods[spec.id]=nil;return true end
    DBFMCM.mods[spec.id]={handle=h,pages=spec.pages,controls=controls}
    return h
end
local child=FP.host(host)
assert(child.config.motion_scale==.5)
assert(child.set('placement',{x=.1,y=0,z=0}))
assert(host.config.enabled==false and host.config.first_person.motion_scale==.5)
assert(FP.enable())
assert(next(DBFMCM.mods)==nil,'Camera must not create a second MCM registration')
local controller={}
function controller:set_enabled(v)self.enabled=v;return true end
function controller:set_unreleased()return true end
function controller:stop_freezes()end
function controller:is_clean()return true end
function controller:status()return 'Off'end
function controller:set_categories(v)self.categories=v;return true end
function controller:set_freezes()return true end
local menu=dofile('src/mcm.lua').new(controller)
assert(menu:update(0))
assert(registrations==1)
local record=assert(DBFMCM.mods.goose_temporary_unlocks)
assert(record.pages[3].id=='first_person')
assert(record.controls.first_person_start_test)
record.controls.first_person_start_test.on_activate();assert(starts==1)
record.controls.first_person_motion_strength.on_change();assert(changed==1)
assert(virtual.get('motion_strength')==100)
assert(not controller.categories.first_person_motion_strength)
FP.update();assert(updates==1)
pending=true;assert(FP.shutdown()==false)
FP.update();assert(stops==2,'Failed cleanup must be retried on the next frame')
pending=false;FP.update();assert(stops==3)
assert(FP.shutdown())
assert(menu:shutdown()and next(DBFMCM.mods)==nil)
assert(FP.enable());pending=true;runtime.fail=true;FP.update();local before=stops
FP.update();assert(stops==before+1)
pending=false;FP.update();assert(FP.shutdown())
print('Shared MCM ownership, namespaced settings, controls, lifecycle and pending cleanup passed')
