-- Disable the actual environment component, rather than an optional renderer
-- setting. All entity/instance tokens come from the engine's own inventory.
local M={}
local CLASS=0x35b0f6c2
local MAPPING='core/stingray_renderer/shading_environment_components/vignette'
function M.new(backend,log,sr,deps)
 deps=deps or{};log=log or function()end
 local clock=deps.clock or os.clock
 local self={phase='idle',writes=0,restores=0,reassertions=0}
 local context,scan,rows,closing,next_scan,next_poll=nil,nil,{},false,0,0
 local function report(phase,why)
  self.phase=phase
  if why and why~=self.error_message then log('FPV vignette: '..tostring(why))end
  self.error_message=why
 end
 local function foreign(compat)
  local fn=compat and compat.foreign
  if fn then local ok,v=pcall(fn,compat);return not ok or v~=false end
  if backend.foreign_camera then local ok,v=pcall(backend.foreign_camera);return not ok or v~=false end
  return false
 end
 local function api()
  assert(sr and sr.Application and sr.World and sr.EntityManager and sr.RenderDataComponent,'Vignette component API unavailable')
  local a={world=sr.Application.main_world,entities=sr.World.entities,manager=sr.EntityManager.render_data_component,
   alive=sr.EntityManager.alive,instances=sr.RenderDataComponent.instances,get=sr.RenderDataComponent.get_property,set=sr.RenderDataComponent.set_property}
  for _,v in pairs(a)do assert(type(v)=='function','Vignette component binding unavailable')end
  assert(a.world and a.entities and a.manager and a.alive and a.instances and a.get and a.set,'Vignette component binding incomplete')
  return a
 end
 local function bindings(c)
  local a=api();for k,v in pairs(c.api)do assert(a[k]==v,'Vignette component binding changed')end
 end
 local function instances(c,e)
  local ids={c.api.instances(c.manager,e)};if #ids==1 and type(ids[1])=='table'then ids=ids[1]end
  assert(#ids<=64,'Vignette instance count changed');return ids
 end
 local function valid(c,r)
  bindings(c)
  if not c.api.alive(r.entity)then return false end
  local found=false;for _,id in ipairs(instances(c,r.entity))do if id==r.id then found=true end end
  return found and c.api.get(c.manager,r.entity,r.id,{'shading_environment_mapping'})==MAPPING
 end
 local function get(c,r)
  local v=c.api.get(c.manager,r.entity,r.id,{'vignette_enabled'})
  assert(type(v)=='boolean','Vignette enabled property unavailable');return v
 end
 local function write(c,r,v)
  bindings(c);assert(c.api.world()==c.world and valid(c,r),'Vignette owner changed before write')
  assert(c.api.set(c.manager,r.entity,r.id,{'vignette_enabled'},v)~=false,'Vignette setter refused')
  assert(get(c,r)==v,'Vignette property readback differs')
 end
 function self:is_clean()for _,r in ipairs(rows)do if r.owned then return false end end;return true end
 function self:stop()
  scan=nil
  if not context then report('idle');return true end
  local ok,why=pcall(function()
   bindings(context)
   -- Entity handles from a destroyed/replaced world must never be reused.
   if context.api.world()~=context.world then rows={};return end
   if foreign()then assert(self:is_clean(),'Another camera owns the view');return end
   for _,r in ipairs(rows)do if r.owned then
    if valid(context,r)and get(context,r)==false then write(context,r,r.before);self.restores=self.restores+1 end
    r.owned=false
   end end
  end)
  if not ok then report('cleanup_pending',tostring(why));return false,self.error_message end
  rows,context,next_scan,next_poll={},nil,0,0;report('idle');return true
 end
 function self:shutdown()closing=true;return self:stop()end
 local function active(controller,camera,compat)
  if closing or foreign(compat)then return false end
  if deps.active_view then return deps.active_view()==true end
  local s=backend:player_snapshot();local state=controller and controller:result()
  return s and s.safe and s.camera_kind==6 and controller:is_enabled()and state.mode=='pose_offset'
 end
 function self:update(controller,camera,compat)
  local eligible,enabled=pcall(active,controller,camera,compat)
  if not eligible or not enabled then return self:stop()end
  local ok,why=pcall(function()
   local now=clock();assert(type(now)=='number'and now==now,'Vignette clock unavailable')
   local a=api();local world=assert(a.world(),'Vignette world unavailable')
   if context and context.world~=world then rows,context,scan={},nil,nil end
   if not context then context={api=a,world=world,manager=assert(a.manager(world),'Vignette provider unavailable')}end
   bindings(context)
   if now>=next_scan and not scan then
    local entities=assert(a.entities(world),'Vignette entities unavailable');assert(type(entities)=='table'and #entities<=32768,'Vignette entity count changed')
    scan={entities=entities,index=1};next_scan=now+1
   end
   if scan then
    for _=1,96 do
     local e=scan.entities[scan.index];if not e then scan=nil;break end;scan.index=scan.index+1
     if a.alive(e)then for _,id in ipairs(instances(context,e))do
      if type(id)=='number'and id%4294967296==CLASS then
       local r={entity=e,id=id};local known=false
       for _,p in ipairs(rows)do if p.entity==e and p.id==id then known=true;break end end
       if not known and valid(context,r)then assert(#rows<32,'Vignette profile count changed');get(context,r);rows[#rows+1]=r end
      end
     end end
    end
   end
   if now>=next_poll then
    next_poll=now+.1
    for i=#rows,1,-1 do
     local r=rows[i]
     if not valid(context,r)then table.remove(rows,i)
     elseif get(context,r)then
      if r.owned then self.reassertions=self.reassertions+1 else r.before=true;r.owned=true end
      -- Acquire before the setter, which can throw after changing the value.
      assert(not foreign(compat),'Another camera owns the view')
      write(context,r,false);self.writes=self.writes+1
     end
    end
   end
   report(scan and 'discovering'or #rows>0 and 'active'or'unavailable',#rows==0 and not scan and 'No vignette components found'or nil)
  end)
  if not ok then report('unavailable',tostring(why));return true,self.error_message end
  return true
 end
 function self:result()
  local owned=not self:is_clean()
  return {phase=self.phase,disabled=self.phase=='active',owned=owned,profiles=#rows,writes=self.writes,restores=self.restores,
   reassertions=self.reassertions,error_message=self.error_message,cleanup_pending=self.phase=='cleanup_pending'}
 end
 function self:status()return self.phase..'; environment vignette disabled='..tostring(self.phase=='active')..'; profiles='..#rows..'; '..tostring(self.error_message or'')end
 return self
end
return M
