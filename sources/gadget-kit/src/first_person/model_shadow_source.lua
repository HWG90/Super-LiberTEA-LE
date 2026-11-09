-- Read-only identity of the native first-person models. SDK handles and pass
-- writes stay with the existing visibility owner; actor-body meshes are absent.
local M={}
local RIG='\237\139\160\60\73\77\207\208'
local function u(raw,o)local a,b,c,d=raw:byte(o+1,o+4);assert(d,'Incomplete model field');return a+b*256+c*65536+d*16777216 end
local function p(raw,o)return u(raw,o)+u(raw,o+4)*4294967296 end
local function ref(n)return type(n)=='number'and n>0 and n<4294967295 and n%1==0 end
function M.new(b)
 local self={};local fingerprint
 local function unit(id,s)
  assert(ref(id),'Model reference invalid')
  local c=b:_alignment_context({viewmodel=id,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index})
  assert(c.unit==id and b:_u32(c.object+8)==id and b:_u8(c.generations+c.index)==c.generation
   and b:_ptr(c.units+c.index*8)==c.object,'Model generation retired')
  return c
 end
 local function parent(c)return p(b:_read(c.object+0x1d0,8),0)end
 function self:probe(expected,appearance)
  fingerprint=nil
  local ok,result,signature=pcall(function()
   local s=assert(b:snapshot());assert(s.safe and s.camera_kind==6 and s.player_identity==expected.player_identity
    and s.body==expected.body and s.viewmodel==expected.viewmodel,'First-person model owner unavailable')
   if b.foreign_camera then assert(b.foreign_camera()==false,'Another camera owns the view')end
   local inspected={}
   local function watch(c,root)
    inspected[c.unit]={object=c.object,parent=not root and parent(c)or nil,world=b:_ptr(c.object+0x18)}
    return c
   end
   local body,rig=watch(unit(s.body,s),true),watch(unit(s.viewmodel,s))
   inspected[rig.unit].links=b:_read(rig.object+0x1d8,16)
   assert(body.object~=rig.object and b:_u32(rig.object+0x70)==63 and b:_read(rig.object+0x358,8)==RIG,'Native first-person rig changed')
   local world=b:_ptr(rig.object+0x18);assert(world==b:_ptr(body.object+0x18),'First-person rig world changed')
   local at=s.avatar_owner+0x546ab0+s.avatar_index*0x1b8+0xdc
   assert(b:_read(at,120)==appearance,'Arm appearance changed')
   local gun=watch(unit(s.weapon_unit,s));assert(parent(gun)==rig.object,'First-person weapon parent changed')
   local rows,signature,visited,closing={}, {s.identity,tostring(rig.object)},{},{}
   local function add(c,wanted_parent)
    assert(c.unit~=s.body and c.unit~=s.viewmodel and b:_ptr(c.object+0x18)==world and parent(c)==wanted_parent,'Model attachment changed')
    rows[c.unit]={part='model',offsets={},model_shadow=true,model_parent=wanted_parent,
     model_owner={identity=s.identity,rig=s.viewmodel,rig_object=rig.object,weapon=s.weapon_unit,weapon_object=gun.object,world=world,parent=wanted_parent,unit=c.unit,object=c.object}}
    closing[c.unit]={context=c,parent=wanted_parent}
    signature[#signature+1]=tostring(c.unit)..':'..tostring(c.object)..':'..tostring(wanted_parent)
   end
   for layer=0,2 do for slot=6,9 do local id=u(appearance,layer*40+slot*4)
    if ref(id)then local c=watch(unit(id,s));if parent(c)==rig.object then add(c,rig.object)end end
   end end
   local function weapon(id,wanted_parent,depth)
    assert(depth<=8 and not visited[id],'Weapon model cycle/depth exceeded');visited[id]=true
    local total=0;for _ in pairs(visited)do total=total+1 end;assert(total<=32,'Weapon model count exceeded')
    local c=watch(unit(id,s));add(c,wanted_parent)
    local links=b:_read(c.object+0x1d8,16);closing[id].links=links;inspected[id].links=links
    local child=p(links,0);local siblings={}
    while child~=0 do
     assert(child>=65536 and child<2^47 and not siblings[child],'Weapon sibling changed');siblings[child]=true
     local child_id=b:_u32(child+8);local next_child=p(b:_read(child+0x1e0,8),0)
     assert(unit(child_id,s).object==child,'Weapon child generation changed');weapon(child_id,c.object,depth+1)
     child=next_child
    end
   end
   weapon(s.weapon_unit,rig.object,0)
   rows[s.viewmodel]={part='shoulder',rig=true,shadow_rig=true,offsets={}}
   local after=assert(b:snapshot());assert(after.identity==s.identity and after.record==s.record and after.safe
    and after.camera_kind==6 and b:_read(at,120)==appearance,'First-person models changed during observation')
   assert(unit(s.viewmodel,after).object==rig.object
    and b:_read(rig.object+0x1d8,16)==inspected[rig.unit].links,'First-person rig retired or attachments changed')
   for id,row in pairs(closing)do
    local c=unit(id,after);assert(c.object==row.context.object and parent(c)==row.parent and b:_ptr(c.object+0x18)==world
     and(not row.links or b:_read(c.object+0x1d8,16)==row.links),'First-person attachment changed during observation')
   end
   -- This is an observation cache, never SDK mutation authority. A consumer
   -- must freshly resolve every encoded UnitRef and close its own registry /
   -- player bracket before admitting the no-write path below.
   if ref(s.weapon)and type(s.weapon_component_descriptor)=='number'and type(s.weapon_descriptor)=='string'
    and #s.weapon_descriptor==20 and type(b._descriptor)=='function'then
    fingerprint={owner=s.player_identity,body=s.body,rig=s.viewmodel,weapon=s.weapon,weapon_unit=s.weapon_unit,
     record=s.record,world=s.world,appearance=appearance,descriptor=s.weapon_descriptor,
     component=s.weapon_component_descriptor,inspected=inspected}
   end
   return rows,table.concat(signature,'|')
  end)
  if not ok then return nil,tostring(result)end
  return result,signature
 end
 -- No snapshots, native calls, SDK handles or writes. The original full
 -- probe / valid methods remain mandatory when a mesh needs any mutation.
 function self:has_observation()return fingerprint~=nil end
 function self:unchanged(s,appearance,inspect)
  local ok,why=pcall(function()
   local f=assert(fingerprint,'No qualified model observation')
   assert(type(inspect)=='function'and s.safe==true and s.camera_kind==6
    and s.player_identity==f.owner and s.body==f.body and s.viewmodel==f.rig and s.world==f.world
    and s.record==f.record and s.request_weapon==f.weapon and appearance==f.appearance,'Model observation owner changed')
   assert(b:_descriptor(s.world,f.weapon):sub(1,20)==f.descriptor
    and b:_read(f.component,20)==f.descriptor,'Model weapon descriptor changed')
   local observations={}
   for id,row in pairs(f.inspected)do
    local object,header=inspect(id,row.object)
    assert(object==row.object and p(header,24)==row.world,'Model observation generation/world changed')
    local raw=b:_read(object+0x1d0,row.links and 24 or 8)
    assert((row.parent==nil or p(raw,0)==row.parent)and(not row.links or raw:sub(9)==row.links),'Model observation topology changed')
    observations[object]=raw
   end
   local rig=assert(f.inspected[f.rig]).object
   assert(b:_u32(rig+0x70)==63 and b:_read(rig+0x358,8)==RIG,'Model observation rig changed')
   -- A previously empty leaf is part of this exact comparison, so a new
   -- attachment cannot hide behind an unchanged list of old renderers.
   for object,raw in pairs(observations)do assert(b:_read(object+0x1d0,#raw)==raw,'Model topology changed during observation')end
   assert(b:_descriptor(s.world,f.weapon):sub(1,20)==f.descriptor
    and b:_read(f.component,20)==f.descriptor,'Model weapon changed during observation')
  end)
  return ok,not ok and tostring(why)or nil
 end
 function self:valid(expected,owner)
  local ok,value=pcall(function()
   local s=assert(b:snapshot());assert(s.safe and s.camera_kind==6 and s.player_identity==expected.player_identity
    and s.identity==owner.identity and s.viewmodel==owner.rig and s.weapon_unit==owner.weapon,'First-person model target changed')
   local rig=unit(owner.rig,s);assert(rig.object==owner.rig_object and b:_ptr(rig.object+0x18)==owner.world
    and b:_u32(rig.object+0x70)==63 and b:_read(rig.object+0x358,8)==RIG,'First-person model rig changed')
   local gun=unit(owner.weapon,s);local target=unit(owner.unit,s)
   assert(gun.object==owner.weapon_object and parent(gun)==rig.object and target.object==owner.object
    and parent(target)==owner.parent and b:_ptr(target.object+0x18)==owner.world,'First-person shadow attachment changed')
   if b.foreign_camera then assert(b.foreign_camera()==false,'Another camera owns the view')end
   return true
  end)
  return ok and value==true
 end
 return self
end
return M
