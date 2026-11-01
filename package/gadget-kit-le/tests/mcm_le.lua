-- Run from the staged LE kit folder: lua5.1 tests/mcm_le.lua (the full kit's tests/mcm.lua, for LE's pages).
mod={require=function(name)return dofile(name)end,log=function()end}
local M=dofile('src/mcm.lua')
local s={enabled=nil,queued=nil}
function s:set_enabled(v)self.enabled=v end
function s:choices()return {'A','B'}end
function s:stratagem_choices()return {'X'}end
function s:status()return 'Spawn fixture' end
function s:stratagem_status()return 'Slot fixture' end
function s:queue(v)self.queued=v;return true end
function s:queue_stratagem(v)self.slot=v;return true end
local spec,values,removed,closed
DBFMCM={mods={}}
function DBFMCM.close()closed=true;return true end
function DBFMCM.register(sp)
 spec=sp;values={};local controls={}
 for _,page in ipairs(sp.pages)do for _,control in ipairs(page.controls)do
  if control.id then values[control.id]=control.default;controls[control.id]=control end
 end end
 local h={get=function(id)return values[id]end,unregister=function()removed=true;DBFMCM.mods[sp.id]=nil;return true end}
 DBFMCM.mods[sp.id]={handle=h,pages=sp.pages,controls=controls}
 return h
end
local menu=M.new(nil,s);assert(menu:update(0))
assert(spec.id=='goose_temporary_unlocks' and #spec.pages==2,'Spawner and First Person only')
assert(spec.pages[1].name=='Spawner' and spec.pages[2].id=='first_person')
for _,page in ipairs(spec.pages)do assert(page.name~='Unlocks' and page.name~='Gameplay')end
for _,id in ipairs({'enabled','weapons','instant_extract','passive_ai','freeze_timer','mission_complete','runtime_status','gameplay_status'})do
 assert(values[id]==nil and DBFMCM.mods[spec.id].controls[id]==nil,id..' must not be registered')
end
assert(s.enabled==false,'spawner starts off')
values.spawner_enabled=true;assert(menu:update(0.3));assert(s.enabled==true)
local equip;for _,c in ipairs(spec.pages[1].controls)do if c.id=='spawner_equip'then equip=c end end
values.spawner_weapon=2;assert(equip.on_activate());assert(s.queued==2 and closed)
menu:refresh_status();local status;for _,c in ipairs(spec.pages[1].controls)do if c.id=='spawner_status'then status=c.label end end
assert(status=='Status: Spawn fixture')
assert(menu:shutdown() and removed and s.enabled==false)
print('Gadget Kit LE MCM: Spawner and First Person pages only, spawner routing and cleanup passed')
