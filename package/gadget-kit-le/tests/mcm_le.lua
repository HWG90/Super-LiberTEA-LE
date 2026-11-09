-- Run from the staged LE kit folder: lua5.1 tests/mcm_le.lua (the full kit's tests/mcm.lua, for LE's pages).
mod={require=function(name)return dofile(name)end,log=function()end}
local M=dofile('src/mcm.lua')
local s={enabled=nil,queued=nil}
function s:set_enabled(v)self.enabled=v end
function s:choices()return {'A','B'}end
function s:stratagem_groups()return {{name='Supply',entries={{name='X',index=7},{name='Y',index=9}}}}end
function s:status()return 'Spawn fixture' end
function s:stratagem_status()return 'Slot fixture' end
function s:queue(v)self.queued=v;return true end
function s:queue_stratagem(v)self.slot=v;return true end
local editor={resets=0,updates=0}
function editor:reset()self.resets=self.resets+1 end
function editor:page(current)self.current=current;return {id='loadout_editor',name='Loadouts',controls={}}end
function editor:update()self.updates=self.updates+1 end
local spec,values,removed,closed
DBFMCM={mods={},is_open=function()return true end}
function DBFMCM.close()closed=true;return true end
function DBFMCM.register(sp)
 spec=sp;values={};local controls={}
 local function collect(list)for _,control in ipairs(list)do
  if control.id then values[control.id]=control.default;controls[control.id]=control end
  if control.children then collect(control.children)end
 end end
 for _,page in ipairs(sp.pages)do collect(page.controls)end
 local h={get=function(id)return values[id]end,unregister=function()removed=true;DBFMCM.mods[sp.id]=nil;return true end}
 DBFMCM.mods[sp.id]={handle=h,pages=sp.pages,controls=controls}
 return h
end
local menu=M.new(nil,s,editor);assert(menu:update(0))
assert(spec.id=='goose_temporary_unlocks' and #spec.pages==3,'Spawner, its loadout editor and First Person only')
assert(spec.pages[1].name=='Spawner' and spec.pages[2].id=='loadout_editor' and spec.pages[3].id=='first_person')
for _,page in ipairs(spec.pages)do assert(page.name~='Unlocks' and page.name~='Gameplay')end
for _,id in ipairs({'enabled','weapons','instant_extract','passive_ai','freeze_timer','mission_complete','runtime_status','gameplay_status'})do
 assert(values[id]==nil and DBFMCM.mods[spec.id].controls[id]==nil,id..' must not be registered')
end
assert(s.enabled==false,'spawner starts off')
values.spawner_enabled=true;assert(menu:update(0.3));assert(s.enabled==true and editor.updates>0)
local controls=DBFMCM.mods[spec.id].controls
values.spawner_weapon=2;assert(controls.spawner_equip.on_activate());assert(s.queued==2 and closed)
-- the fifth stratagem: a category's button adds the entry chosen in that category
closed=nil;values.spawner_stratagem_supply=2
assert(controls.spawner_stratagem_supply_add.on_activate()==true and s.slot==9 and closed)
-- a refusal reaches the menu: MCM shows a string result as the notice and drops a second value
closed=nil;function s:queue()return false,'A support request is already pending'end
assert(controls.spawner_equip.on_activate()=='A support request is already pending' and not closed)
function s:queue_stratagem()return false,'A stratagem request is already pending'end
assert(controls.spawner_stratagem_supply_add.on_activate()=='A stratagem request is already pending' and not closed)
menu:refresh_status()
assert(controls.spawner_status.label=='Status: Spawn fixture' and controls.spawner_stratagem_status.label=='Status: Slot fixture')
local resets=editor.resets
assert(menu:shutdown() and removed and s.enabled==false and editor.resets>resets)
print('Gadget Kit LE MCM: Spawner, loadout editor and First Person pages only, spawner and stratagem routing, visible refusals and cleanup passed')
