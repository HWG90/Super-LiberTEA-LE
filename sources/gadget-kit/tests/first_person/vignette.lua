local V=dofile(NATIVE_ADS_TEST_ROOT..'/src/vignette.lua')
local passed=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
 local f={time=10,active=true,world={},entities={},writes=0,foreign=false}
 function f:add(enabled,mapping,id)
  local e={alive=true,id=id or 0x35b0f6c2,enabled=enabled,mapping=mapping or'core/stingray_renderer/shading_environment_components/vignette'}
  self.entities[#self.entities+1]=e;return e
 end
 local a=f:add(true);f.a=a
 local sr={Application={main_world=function()return f.world end},World={entities=function()return f.entities end},
 EntityManager={alive=function(e)return e.alive end,render_data_component=function(w)return w end},RenderDataComponent={}}
 local p=sr.RenderDataComponent
 function p.instances(m,e)assert(m==f.world);return e.id end
 function p.get_property(m,e,id,path)assert(m==f.world and id==e.id and e.alive);if path[1]=='shading_environment_mapping'then return e.mapping end;assert(path[1]=='vignette_enabled');return e.enabled end
 function p.set_property(m,e,id,path,value)
  assert(not f.foreign and m==f.world and id==e.id and e.alive and e.mapping=='core/stingray_renderer/shading_environment_components/vignette')
  assert(path[1]=='vignette_enabled'and type(value)=='boolean');e.enabled=value;f.writes=f.writes+1
  if f.throw_after then error('setter uncertain')end
 end
 f.sr=sr;f.manager=V.new({foreign_camera=function()return f.foreign end},nil,sr,{clock=function()return f.time end,active_view=function()return f.active end})
 function f:step()self.time=self.time+.11;return self.manager:update()end
 return f
end
test('disables the actual vignette component and restores once',function()
 local f=fixture();assert(f:step());assert(not f.a.enabled and f.writes==1 and f.manager:result().disabled)
 for _=1,20 do assert(f:step())end;assert(f.writes==1)
 assert(f.manager:stop());assert(f.a.enabled and f.writes==2 and f.manager:is_clean());assert(f.manager:stop());assert(f.writes==2)
end)
test('ignores unrelated components mappings and already-disabled profiles',function()
 local f=fixture();f.a.enabled=false;local b=f:add(true,'foreign');local c=f:add(true,nil,7)
 assert(f:step());assert(f.manager:is_clean()and f.writes==0 and b.enabled and c.enabled)
 assert(f.manager:stop());assert(not f.a.enabled)
end)
test('reasserts after native reset and discovers later profiles',function()
 local f=fixture();assert(f:step());f.a.enabled=true;assert(f:step());assert(not f.a.enabled and f.manager.reassertions==1)
 local b=f:add(true);for _=1,12 do assert(f:step())end;assert(not b.enabled);assert(f.manager:stop());assert(b.enabled and f.a.enabled)
end)
test('retired and repurposed components are never restored',function()
 local f=fixture();assert(f:step());f.a.alive=false;assert(f.manager:stop());assert(not f.a.enabled and f.writes==1)
 f=fixture();assert(f:step());f.a.mapping='foreign';assert(f.manager:stop());assert(f.writes==1)
end)
test('foreign cameras suspend all writes and retain cleanup',function()
 local f=fixture();assert(f:step());f.foreign=true;assert(not f:step());assert(f.writes==1 and not f.manager:is_clean())
 f.foreign=false;f.active=false;assert(f:step());assert(f.a.enabled and f.manager:is_clean())
end)
test('uncertain setters retain restoration ownership',function()
 local f=fixture();f.throw_after=true;assert(f:step());assert(not f.manager:is_clean()and not f.a.enabled)
 f.throw_after=false;assert(f.manager:stop());assert(f.a.enabled and f.manager:is_clean())
end)
test('binding replacement cannot acquire or clean up through a foreign API',function()
 local f=fixture();assert(f:step());local setter=f.sr.RenderDataComponent.set_property;f.sr.RenderDataComponent.set_property=function()error('foreign called')end
 assert(not f.manager:stop());assert(f.writes==1);f.sr.RenderDataComponent.set_property=setter;assert(f.manager:stop());assert(f.a.enabled)
end)
test('world replacement retires old handles without touching the new world',function()
 local f=fixture();assert(f:step());f.world={};assert(f.manager:stop());assert(f.writes==1 and f.manager:is_clean())
end)
test('discovery spreads inventories across frames',function()
 local f=fixture();for _=1,300 do f:add(true,nil,7)end;local b=f:add(true)
 assert(f:step());assert(f.manager:result().phase=='discovering'and b.enabled)
 for _=1,3 do assert(f:step())end;assert(not b.enabled and f.manager:result().phase=='active');assert(f.manager:shutdown());assert(b.enabled and f.a.enabled)
end)
print('Environment vignette fixtures: '..passed..' passed')
