mod={require=function(name)return dofile(name)end}
local M=dofile('src/mcm.lua')
local c={}
function c:set_enabled(v) self.enabled=v;return true end
function c:set_unreleased()return true end
function c:stop_freezes()self.freezes={}end
function c:is_clean()return true end
function c:status()return 'Fixture' end
function c:set_categories(v)self.categories=v;return true end
function c:set_freezes(v)self.freezes=v;return true end
local spec,values,registered,removed
DBFMCM={mods={}}
function DBFMCM.register(s)
 spec=s;values={};local controls={}
 for _,page in ipairs(s.pages)do for _,control in ipairs(page.controls)do
  if control.type=='toggle'then values[control.id]=control.default;controls[control.id]=control end
 end end
 local h={get=function(id)return values[id]end,unregister=function()removed=true;DBFMCM.mods[s.id]=nil;return true end}
 DBFMCM.mods[s.id]={handle=h,pages=s.pages,controls=controls}
 return h
end
local menu=M.new(c);assert(menu:update(0))
assert(spec.pages[1].name=='Unlocks' and spec.pages[2].name=='Gameplay')
assert(spec.pages[3].id=='first_person')
for _,control in ipairs(spec.pages[3].controls)do assert(control.type=='text')end
local ids={instant_extract=true,passive_ai=true,freeze_timer=true,freeze_health=true,no_reload=true,freeze_ammo=true}
for _,control in ipairs(spec.pages[2].controls)do if control.type=='toggle'then assert(ids[control.id]);ids[control.id]=nil end end
assert(next(ids)==nil)
for _,key in ipairs({'instant_extract','passive_ai','freeze_timer','freeze_health','no_reload','freeze_ammo'})do assert(values[key]==false);values[key]=true end
assert(menu:update(0.3));assert(not c.enabled)
for _,key in ipairs({'instant_extract','passive_ai','freeze_timer','freeze_health','no_reload','freeze_ammo'})do assert(c.freezes[key]==true and c.categories[key]==nil)end
values.no_reload=false;assert(menu:update(0.3));assert(not c.freezes.no_reload and c.freezes.freeze_ammo)
menu:refresh_status();local status;for _,control in ipairs(spec.pages[2].controls)do if control.id=='gameplay_status'then status=control.label end end;assert(status=='Status: Fixture')
assert(menu:shutdown() and removed and next(c.freezes)==nil)
print('MCM tabs, independent toggles, defaults, routing and cleanup passed')
-- Complete all objectives: on the Gameplay page after its status line; the button only queues a request.
local requests=0
local mission={status=function()return 'Ready'end,request=function()requests=requests+1;return true end,shutdown=function()end}
menu=M.new(c,nil,nil,mission);assert(menu:update(0))
assert(#spec.pages==3 and spec.pages[2].id=='gameplay' and spec.pages[3].id=='first_person')
local order={};for _,control in ipairs(spec.pages[2].controls)do order[#order+1]=control.id or control.type end
assert(table.concat(order,',',#order-3)=='gameplay_status,mission_complete,text,mission_status',table.concat(order,','))
local button;for _,control in ipairs(spec.pages[2].controls)do if control.id=='mission_complete'then button=control end end
assert(button.type=='button' and button.on_activate()==true and requests==1)
mission.status=function()return 'Completed 2 objectives'end;menu:refresh_status()
local label;for _,control in ipairs(spec.pages[2].controls)do if control.id=='mission_status'then label=control.label end end
assert(label=='Status: Completed 2 objectives',label)
assert(menu:shutdown());assert(button.on_activate()==false and requests==1,'No requests after shutdown')
print('Complete all objectives on the Gameplay page: request button and status passed')
