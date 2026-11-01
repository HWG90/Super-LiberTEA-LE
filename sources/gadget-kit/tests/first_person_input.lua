local cache={}
mod={require=function(name)if not cache[name]then cache[name]=dofile(name)end;return cache[name]end}
local keys,focus,now={},true,1
local sr={Keyboard={button_id=function(name)return ({f11=122,f8=119,['left shift']=160})[name]end,button=function(id)return keys[id]and 1 or 0 end},Window={has_focus=function()return focus end},Gui={resolution=function()return 1920,1080 end},Application={time_since_launch=function()return now end}}
local token,owner,acquires,releases=nil,nil,0,0
local service={version=1,capabilities={menu=true,camera=true,keyboard=false}}
function service.acquire(id,mode)
 assert(not token);acquires=acquires+1;token={};owner=id;return token
end
function service.owns(t)return t==token and token~=nil end
function service.status()return {owner=owner,pending_restore=false}end
function service.release(t)assert(t==token);token=nil;owner=nil;releases=releases+1;return true end
function service.set_mode(t,mode)assert(t==token);return true end
function service.snapshot(t)assert(t==token);return {valid=true,x=400,y=200,width=1920,height=1080,buttons=0,wheel=1}end
local input=mod.require('src/first_person/input_adapter.lua').new(sr,service)
input.frame();assert(input.focused()and not input.down(122))
keys[122]=true;input.frame();assert(input.down(122))
keys[119]=true;keys[160]=true;input.frame();assert(input.down(119)and input.down(16))
assert(acquires==0,'Polling hotkeys must not capture gameplay input')
focus=false;input.frame();assert(not input.focused()and not input.down(122))
focus=true;assert(input.acquire());assert(owner=='goose_first_person_editor')
assert(input.set_focus(true));local sample=assert(input.menu_sample());assert(sample.x==400 and sample.y==880 and sample.dt==0)
now=1.025;sample=assert(input.menu_sample());assert(math.abs(sample.dt-.025)<1e-9)
assert(input.release()and releases==1 and service.status().owner==nil)
print('Engine F11/F8/modifier input, foreground gating, editor token capture, timing and restoration passed')
-- Reproduce the actual missing-camera_input API and traverse the merged menu.
stingray=sr
cache['src/first_person/compat51.lua']={kind=type,number=tonumber}
DBFMCM={shared_input_service=service,register=function()error('A second MCM registration is forbidden')end,
 menu_binding_status=function()return {focused=focus,editing=false,global_key=46}end,
 input_status=function()return {active=false,pending_restore=false}end,is_open=function()return false end}
local controller={enabled=false,starts=0,stops=0,phase='idle'}
function controller:is_enabled()return self.enabled end
function controller:is_clean()return true end
function controller:status()return 'Fixture'end
function controller:start()self.starts=self.starts+1;self.enabled=true;return true end
function controller:stop()self.stops=self.stops+1;self.enabled=false;return true end
local editor={phase='idle',opens=0}
function editor:is_active()return self.phase=='active'end
function editor:request_open()self.opens=self.opens+1;self.phase='active';return true end
function editor:cancel()self.phase='idle';return true end
local menu=mod.require('src/first_person/menu.lua').new(controller,nil,editor)
keys[122],keys[119],keys[160]=false,false,false
assert(menu:update())
keys[122]=true;assert(menu:update());assert(controller.starts==1)
assert(menu:update());assert(controller.starts==1,'Held F11 must not repeat')
keys[122]=false;menu:update();keys[122]=true;menu:update();assert(controller.stops==1)
keys[122]=false;menu:update();keys[119]=true;menu:update();assert(editor.opens==1)
focus=false;menu:update();focus=true;menu:update();assert(editor.opens==1,'Focus regain must not synthesize a key edge')
assert(editor:cancel());assert(menu:shutdown())
print('Merged F11 toggle/F8 editor work when modern MCM has no camera_input; key edges and focus recovery passed')
