-- Scope binary-contract reuse to one callback, including early returns/errors.
local entry=assert(loadfile(NATIVE_ADS_TEST_ROOT..'/main.lua'))()
local original_frame
for i=1,80 do local name,value=debug.getupvalue(entry.on_update,i);if name=='update_frame'then original_frame=value;break end end
assert(original_frame)
local function locate(fn,key,seen)
    seen=seen or{};if seen[fn]then return end;seen[fn]=true
    local nested={}
    for i=1,80 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name==key then return fn,i,value end
        if type(value)=='function'and debug.getinfo(value,'S').what=='Lua'then nested[#nested+1]=value end
    end
    for _,value in ipairs(nested)do local owner,index,current=locate(value,key,seen);if owner then return owner,index,current end end
end
local function replace(key,value)
    local owner,index=locate(entry.on_update,key)
    if not owner then owner,index=locate(entry.on_disable,key)end
    if not owner then owner,index=locate(entry.on_cleanup_poll,key)end
    if not owner then owner,index=locate(entry.on_enable,key)end
    if owner then debug.setupvalue(owner,index,value);return end
    error('Runtime frame upvalue unavailable: '..key)
end
local function read_field(fn,key)local _,_,value=locate(fn,key);return value end
local calls={begin=0,finish=0,body=0,active=false}
local backend={}
function backend:begin_frame()
    assert(not calls.active);calls.active=true;self.frame_active=true;calls.begin=calls.begin+1
end
function backend:end_frame()
    assert(calls.active);calls.active=false;self.frame_active=false;calls.finish=calls.finish+1
end
replace('backend',backend);replace('controller',{});replace('stopping',false)
replace('update_frame',function()calls.body=calls.body+1;return end)
entry.on_update()
assert(calls.begin==1 and calls.finish==1 and calls.body==1 and not calls.active)
replace('update_frame',function()error('fixture update error')end)
local ok,why=pcall(entry.on_update)
assert(not ok and tostring(why):find('fixture update error'))
assert(calls.begin==2 and calls.finish==2 and not calls.active)
replace('stopping',true);entry.on_update()
replace('stopping',false);replace('controller',nil);entry.on_update()
assert(calls.begin==2 and calls.finish==2)
local function frame_field(key,value)
    for i=1,80 do
        local name=debug.getupvalue(original_frame,i);if not name then break end
        if name==key then debug.setupvalue(original_frame,i,value);return end
    end
    error('Frame field unavailable: '..key)
end
local order={};local foreign=false;local enabled=true;local refresh_failure=false
local function append(value)order[#order+1]=value end
frame_field('compat',{update=function()return true end})
frame_field('foreign_camera',function()return foreign end)
frame_field('fird_entry',nil)
frame_field('fird',{is_enabled=function()return enabled end,refresh_target=function()append('refresh');if refresh_failure then return false,'changed'end;return true end,
    update=function()append('fird')end,stop=function()append('fird-stop');return true end})
frame_field('aim_markers',{stop=function()append('markers-stop');return true end,update=function()append('markers');return true end})
frame_field('editor',{update=function()append('editor')end,cancel=function()append('cancel');return true end})
frame_field('menu',{update=function()append('menu')end});frame_field('log',function()end)
replace('controller',{});replace('update_frame',original_frame)
entry.on_update();assert(table.concat(order,',')=='refresh,editor,fird,menu,markers')
order={};foreign=true;entry.on_update();assert(table.concat(order,',')=='refresh,editor,fird,menu,markers')
order={};foreign=false;refresh_failure=true;entry.on_update()
assert(table.concat(order,',')=='refresh,markers-stop,cancel,fird-stop,menu,markers')
order={};enabled=false
frame_field('fird_entry',{is_enabled=function()return true end,is_pending=function()return true end,uses_fp=function()return false end,update=function()return true end})
entry.on_update();assert(table.concat(order,',')=='menu,markers')
order={};replace('update_frame',function()append('native-ads-or-idle');return end)
entry.on_update();assert(table.concat(order,',')=='native-ads-or-idle,markers')
order={};replace('update_frame',function()error('unexpected frame error')end)
assert(not pcall(entry.on_update));assert(table.concat(order,',')=='markers-stop'and not calls.active)
local render
for i=1,100 do
    local name,value=debug.getupvalue(entry.on_enable,i);if not name then break end
    if name=='render_fird_pose'then render=value;break end
end
assert(type(render)=='function','Runtime render frame adapter unavailable')
local render_calls,render_failure,render_refusal=0,false,false
frame_field('fird',{is_enabled=function()return enabled end,render_pose=function()
    assert(calls.active and backend.frame_active);render_calls=render_calls+1
    if render_failure then error('fixture render-only failure')end
    if render_refusal then return false,'fixture render-only refusal'end
    return true
end})
enabled=true;replace('stopping',false)
local before_begin,before_finish=calls.begin,calls.finish
assert(render());assert(render_calls==1 and calls.begin==before_begin+1 and calls.finish==before_finish+1)
assert(not calls.active and not backend.frame_active)
render_failure=true
local called,done,problem=pcall(render)
assert(called and done==false and tostring(problem):find('fixture render%-only failure'))
assert(calls.begin==before_begin+2 and calls.finish==before_finish+2 and not calls.active)
render_failure=false;render_refusal=true
done,problem=render();assert(done==false and problem=='fixture render-only refusal')
assert(calls.begin==before_begin+3 and calls.finish==before_finish+3 and not calls.active)
-- An update currently owns the backend, a stopped runtime, or an off view must
-- skip render work without beginning a nested/native lifecycle transaction.
backend.frame_active=true;assert(render());backend.frame_active=false
replace('stopping',true);assert(render());replace('stopping',false)
enabled=false;assert(render())
assert(render_calls==3 and calls.begin==before_begin+3 and calls.finish==before_finish+3)
-- Ready-state writes can drain only through normal Update/cleanup-poll. Plain
-- disable cancels intent and restores the independent camera/HUD managers.
replace('stopping',false);replace('controller',{shutdown=function()return true end})
replace('update_frame',function()append('body')end)
local ready={owned=true,updates=0,stops=0}
function ready:stop()self.stops=self.stops+1;return not self.owned,'pose pending'end
function ready:is_clean()return not self.owned end
local held=true
backend.foreign_camera=function()return read_field(entry.on_disable,'handoff_ready')~=true or held end
function ready:update(context)
    assert(context.phase=='qualified_update'and context.tick>0 and calls.active and backend.frame_active)
    self.updates=self.updates+1
    if not backend.foreign_camera()then self.owned=false;return true end
    return false,'foreign camera held'
end
replace('ready_pose',ready)
replace('handoff_ready',false)
replace('compat',{shutdown=function()return true end,foreign=function()return held end})
replace('fird',{stop=function()return ready:is_clean(),'ready pending'end})
replace('menu',{begin_shutdown=function()end,shutdown=function()return true end})
replace('aim_markers',nil);replace('fird_entry',nil);replace('editor',nil)
local before_updates=ready.updates
assert(entry.on_disable()==false and ready.updates==before_updates and ready.owned)
assert(read_field(entry.on_disable,'handoff_ready')==true,'Fresh clean sharing result must clear a stale failed handoff latch')
assert(entry.on_cleanup_poll()==false and ready.owned and ready.updates==before_updates+1)
assert(not calls.active and not backend.frame_active,'Foreign cleanup wait leaked its frame')
held=false
assert(entry.on_cleanup_poll()==false and not ready.owned and ready.updates==before_updates+2)
assert(entry.on_cleanup_poll()==true and not calls.active and not backend.frame_active)
assert(ready.stops>0)
-- A native event slot must be disarmed before deferred stance restoration;
-- failure to restore that slot retains the runtime after other owners drain.
local fire={armed=true,owned=true,release_allowed=false,stops=0}
function fire:stop()
 self.stops=self.stops+1;self.armed=false
 if not self.release_allowed then return false,'fixture event slot pending'end
 self.owned=false;return true
end
local carry={owned=true,updates=0,stops=0}
function carry:stop()self.stops=self.stops+1;return not self.owned end
function carry:is_clean()return not self.owned end
function carry:is_enabled()return false end
function carry:update(context)
 assert(calls.active and backend.frame_active and context.phase=='qualified_update')
 assert(not fire.armed,'Stance cleanup ran while event suppression was admitted')
 self.updates=self.updates+1;self.owned=false;return true
end
replace('backend',backend);replace('controller',{shutdown=function()return true end})
replace('stopping',false);replace('ready_pose',carry);replace('held_fire',fire)
assert(entry.on_disable()==false and not fire.armed and fire.owned and carry.updates==0)
assert(entry.on_cleanup_poll()==false and not carry.owned and fire.owned)
assert(not calls.active and not backend.frame_active)
fire.release_allowed=true
assert(entry.on_cleanup_poll()==true and not fire.owned and not calls.active)
assert(carry.updates>=1 and fire.stops>=3)
-- A refused publication must drain its retained slot during ordinary Update,
-- so a later healthy frame can reserve it again without an F11 restart.
local retry={owned=true,cleanup_only=false,release_allowed=false,stops=0,begins=0,updates=0}
function retry:update(owner,context)
 assert(owner and calls.active and backend.frame_active and context.phase=='qualified_update')
 self.updates=self.updates+1
 if self.cleanup_only then return false,'fixture retained event slot'end
 if self.updates==1 then self.cleanup_only=true;return false,'fixture refused Publish'end
 if not self.owned then self.owned=true;self.begins=self.begins+1 end
 return true
end
function retry:stop()
 self.stops=self.stops+1
 if not self.release_allowed then return false,'fixture slot drain pending'end
 self.owned=false;self.cleanup_only=false;return true
end
local desired=true
local stable={update=function()return true end,is_enabled=function()return desired end,
 filter_owner=function()return{body_ref=123,body_generation=0,owner_token='body',tick=1}end,
 stop=function()desired=false;return true end,is_clean=function()return true end}
replace('backend',backend);replace('controller',{shutdown=function()return true end});replace('stopping',false)
replace('update_frame',function()end);replace('ready_pose',stable);replace('held_fire',retry)
entry.on_update();assert(retry.cleanup_only and retry.stops==1)
entry.on_update();assert(retry.cleanup_only and retry.stops==2)
retry.release_allowed=true;entry.on_update();assert(not retry.owned and not retry.cleanup_only and retry.stops==3)
entry.on_update();assert(retry.owned and retry.begins==1 and retry.updates==4 and not calls.active)
assert(entry.on_disable()==true)
-- Persistent camera ownership, rather than a live firearm lease, owns the
-- renderer effect interval. A fresh body snapshot still gates every query.
local pin_ready=assert(read_field(entry.on_enable,'pinned_ready'))
local actual_view=assert(read_field(entry.on_enable,'first_person_view'))
local pin_snapshot={player_identity='pin-player',body=321,camera_unit=456,camera_kind=9,safe=false,seated=true}
local pin_effective,pin_enabled,pin_mode,pin_foreign,pin_reads=true,true,'pose_offset',false,0
local pin_body=pin_snapshot.body
local pin_backend={pin_first_person=true,pin_player_snapshot=function()return pin_snapshot end,
    player_snapshot=function()return nil,'No owned firearm camera'end}
local pin_camera={is_pinned=function(_,s)
    pin_reads=pin_reads+1;return pin_effective and s==pin_snapshot and s.body==pin_body
end}
replace('backend',pin_backend);replace('camera',pin_camera)
replace('controller',{is_enabled=function()return pin_enabled end,result=function()return{mode=pin_mode,phase='waiting'}end})
replace('foreign_camera',function()return pin_foreign end)
assert(pin_ready(pin_snapshot) and actual_view(function()return false end))
pin_foreign=true;local before_pin_reads=pin_reads;assert(not actual_view(function()return true end));assert(pin_reads==before_pin_reads)
pin_foreign=false;pin_effective=false;assert(not actual_view(function()return true end))
pin_effective=true;pin_snapshot.body=322;assert(not actual_view(function()return true end));pin_snapshot.body=pin_body
pin_enabled=false;assert(not actual_view(function()return true end));pin_enabled=true
pin_mode='native';assert(not actual_view(function()return true end));pin_mode='pose_offset'
pin_backend.pin_first_person=false;assert(not actual_view(function()return true end));pin_backend.pin_first_person=true
assert(actual_view(function()return false end))
pin_camera.is_pinned=function()error('Retired native camera')end
assert(not pin_ready(pin_snapshot) and not actual_view(function()return true end))
-- Camera pin/raw-look sampling is retired. No input token remains in the
-- operational runtime; native pose/effects cleanup is covered above.
assert(backend.camera_update_token==nil)
print('Ready-pose qualified Update, deferred disable, foreign ownership and retained cleanup-poll drain passed')
print('Held-fire disarm precedes stance restore; pending SDK slot cleanup retains runtime and drains independently')
print('Refused held-fire publication drains during Update and permits a later healthy reservation')
print('Persistent eye camera owns effects through seated/action cameras and yields on Photo, disable or body retirement')
