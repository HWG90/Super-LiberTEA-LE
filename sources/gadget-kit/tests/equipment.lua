local E=dofile('src/equipment.lua')
local function snapshot(n)return {version=1,primary=n,pistol=2,grenade=3,helmet=4,cape=5,armor=6}end
local disk={};local writes=0;local restores=0;local current=snapshot(1)
local host={config=disk,set=function(k,v)writes=writes+1;disk[k]=v;return true end}
local io={capture=function()return current end,restore=function(_,saved,categories,expected)
 restores=restores+1;assert(expected==current and categories.weapons);current=snapshot(saved.primary);return true
end}
local categories={weapons=true,helmets=true,capes=true,bodyarmor=true}
local function step(e,n,ready)for _=1,n do e:update(.5,ready~=false,categories)end end
local e=E.new(io,host);step(e,3);assert(writes==1 and disk.last_equipment.primary==1)
current=snapshot(99);step(e,2);assert(writes==1);step(e,1);assert(writes==2 and disk.last_equipment.primary==99)
-- Simulate a process restart with the game's defaults and only persisted IDs.
e:shutdown();current=snapshot(1)
e=E.new(io,host);step(e,5,false);assert(restores==0 and disk.last_equipment.primary==99)
step(e,3);assert(restores==1 and current.primary==99 and not e.pending)
step(e,10);assert(writes==2,'Restoration must not overwrite the saved loadout with startup defaults')
current=snapshot(88);step(e,3);assert(disk.last_equipment.primary==88)
-- Transient/unavailable reads must neither save defaults nor clear pending.
current=nil;e=E.new(io,host);step(e,6);assert(e.pending and disk.last_equipment.primary==88)
current=snapshot(1);local old=io.restore;io.restore=function()return false,'Busy' end
step(e,5);assert(e.pending and disk.last_equipment.primary==88)
io.restore=old;step(e,1);assert(not e.pending and current.primary==88)
-- Invalid stored IDs must not reach a native restore.
assert(not E.valid({version=1,primary=0}))
print('PASS: stable selection save, process restart, delayed unlock readiness, pending restore retention, no startup overwrite and selection updates')
