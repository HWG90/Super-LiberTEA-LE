local root = assert(NATIVE_ADS_TEST_ROOT)
local Menu = dofile(root .. '/src/menu.lua')
local previous_api, previous_loader = rawget(_G, 'DBFMCM'), rawget(_G, 'LiveLuaLoader')
local passed = 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function test(name, body)
    local ok, why = pcall(body)
    rawset(_G, 'DBFMCM', previous_api); rawset(_G, 'LiveLuaLoader', previous_loader)
    assert(ok, name .. ': ' .. tostring(why)); passed = passed + 1
end
local function fixture(fallback)
    local f = { keys = {}, bindings = {}, opens = 0, cancels = 0, starts = 0, stops = 0, toggles = 0, unregisters = 0,
        marker_saves=0,framework_sets=0 }
    local c = { enabled = false, phase = 'idle' }
    function c:is_enabled() return self.enabled end
    function c:is_clean() return not self.enabled and self.phase == 'idle' end
    function c:status() return self.enabled and 'First person on' or 'First person off' end
    function c:display_status()
        f.status_reads=(f.status_reads or 0)+1
        return self.label or (self.enabled and 'First person on' or 'First person off')
    end
    function c:on_status_changed(listener)
        f.status_changed=listener
        return function()f.status_changed=nil;f.status_unsubscribed=(f.status_unsubscribed or 0)+1 end
    end
    function c:stop()
        f.stops = f.stops + 1; self.enabled, self.phase = false, 'idle'; return true
    end
    function c:start(seconds, mode)
        f.starts = f.starts + 1; f.duration, f.mode = seconds, mode
        self.enabled, self.phase = mode == 'pose_offset', 'running'; return true
    end
    local editor = { phase = 'idle' }
    function editor:is_active() return self.phase ~= 'idle' end
    function editor:request_open(kind) f.kind=kind;f.opens = f.opens + 1; self.phase, f.input_owner = 'active', 'dbf_freecam'; return true end
    function editor:cancel()
        f.cancels = f.cancels + 1
        if f.cancel_failure then self.phase = 'closing'; return false, 'input restoration pending' end
        self.phase, f.input_owner = 'idle', nil; return true
    end
    function f:make_api()
        local api = { mods = {} }
        api.camera_input = { down = function(key) return self.keys[key] == true end,
            focused = function() return not self.unfocused end }
        api.input_status = function() return { owner = self.input_owner, active = false, pending_restore = self.pending_restore } end
        api.menu_binding_status = function() return { focused = not self.unfocused, editing = self.editing == true, global_key = self.global_key or 46 } end
        api.is_open = function() return self.menu_open == true end
        api.register = function(spec)
            self.description=spec.description
            local controls, defaults = {}, {}
            for _, page in ipairs(spec.pages) do for _, control in ipairs(page.controls) do
                controls[control.id] = control; defaults[control.id] = control.default
            end end
            local handle = {}
            handle.get = function(id) if self.bindings[id] ~= nil then return self.bindings[id] end; return defaults[id] end
            handle.set = function(id,value)
                local control=assert(controls[id]);if control.disabled then return false,'Setting unavailable'end
                local old=handle.get(id);if old==value then return true end
                self.framework_sets=self.framework_sets+1;self.bindings[id]=value
                if control.on_change then control.on_change(value,id,old)end
                if spec.on_change then spec.on_change(value,id,old)end
                return true
            end
            handle.unregister = function() self.unregisters = self.unregisters + 1; api.mods[spec.id] = nil; return true end
            api.mods[spec.id] = { handle = handle, controls = controls, pages = spec.pages }
            self.controls = controls;self.setting_changed=spec.on_change
            return handle
        end
        return api
    end
    local actions = {}
    actions.start_pose = function(seconds) equal(seconds, 0); return c:start(seconds, 'pose_offset') end
    actions.stop = function()
        local ok, why = true, nil
        if editor:is_active() then ok, why = editor:cancel() end
        c:stop(); return ok, why
    end
    actions.toggle_pose = function()
        f.toggles = f.toggles + 1
        if c:is_enabled() then return actions.stop() end
        return actions.start_pose(0)
    end
    actions.aim_markers_setting=function()return f.marker_value==true end
    actions.set_aim_markers_setting=function(value)
        if f.marker_save_failure then return false,'Marker preference could not be saved'end
        if f.marker_save_throw then error('Marker save unavailable')end
        f.marker_saves=f.marker_saves+1;f.marker_value=value;f.marker_global=value;return true
    end
    f.controller, f.editor, f.api, f.actions = c, editor, f:make_api(), actions
    f.menu = Menu.new(c, function(message) f.message = message end, editor, fallback and {} or actions)
    rawset(_G, 'DBFMCM', f.api); rawset(_G, 'LiveLuaLoader', nil)
    function f:update() assert(self.menu:update()) end
    function f:press(key) self.keys[key] = true; self:update() end
    function f:release(key) self.keys[key] = false; self:update() end
    f:update()
    return f
end

test('registers persistent actions and rebindable F8/F11 without starting', function()
    local f = fixture()
    equal(f.starts, 0); equal(f.controls.editor_key.default, 119); equal(f.controls.toggle_key.default, 122)
    assert(f.controls.start_true_first_person.on_activate()); equal(f.duration, 0); equal(f.mode, 'pose_offset')
    f:update(); assert(f.controls.start_true_first_person.disabled); assert(not f.controls.edit_placement.disabled)
    assert(f.controls.stop_test.on_activate()); assert(not f.controller:is_enabled()); equal(f.stops, 1)
    assert(f.controls.start_native_test.on_activate()); equal(f.duration, 30); equal(f.mode, 'native')
end)

test('unchanged frames do not poll or redraw status; events refresh and unsubscribe',function()
    local f=fixture();local reads=f.status_reads
    for _=1,1000 do f:update()end
    equal(f.status_reads,reads)
    f.controller.label='Waiting for an equipped weapon';f.status_changed();f:update()
    equal(f.status_reads,reads+1)
    equal(f.controls.runtime_status.label,'Status: Waiting for an equipped weapon')
    for _=1,100 do f:update()end
    equal(f.status_reads,reads+1)
    assert(f.menu:shutdown());equal(f.status_unsubscribed,1);equal(f.status_changed,nil)
end)

test('F8 toggles editor once per press and leaves first person enabled', function()
    local f = fixture(); f.controller.enabled, f.controller.phase = true, 'running'
    f:press(119); equal(f.opens, 1)
    f:update(); equal(f.opens, 1)
    f:release(119); f:press(119); equal(f.cancels, 1); equal(f.stops, 0); assert(f.controller:is_enabled())
    f:update(); equal(f.cancels, 1)
end)

test('F11 toggles persistent first person and can turn it off during editing', function()
    local f = fixture()
    f:press(122); equal(f.toggles, 1); equal(f.starts, 1); assert(f.controller:is_enabled())
    f:update(); equal(f.toggles, 1)
    f:release(122); f:press(119); equal(f.opens, 1)
    f:release(119); f:press(122)
    equal(f.toggles, 2); equal(f.cancels, 1); equal(f.stops, 1); assert(not f.controller:is_enabled())
end)

test('held key at registration does not trigger until released', function()
    local f = fixture(); f.keys[119] = true
    local replacement = f:make_api(); rawset(_G, 'DBFMCM', replacement)
    f:update(); f:update(); equal(f.opens, 0); equal(f.unregisters, 1)
    f:release(119); f:press(119); equal(f.opens, 1)
end)

test('focus and MCM capture gates seed held keys across recovery', function()
    for _, field in ipairs({'unfocused', 'menu_open', 'editing', 'pending_restore'}) do
        local f = fixture(); f[field] = true
        f:press(119); f:update(); equal(f.opens, 0)
        f[field] = false; f:update(); f:update(); equal(f.opens, 0)
        f:release(119); f:press(119); equal(f.opens, 1)
    end
end)

test('foreign MCM and LLL owners block hotkeys without releasing their leases', function()
    for _, owner in ipairs({'other frontend', 'dbf_freecam'}) do
        local f = fixture(); f.input_owner = owner
        f:press(122); equal(f.toggles, 0); equal(f.input_owner, owner)
        f.input_owner = nil; f:update(); equal(f.toggles, 0)
        f:release(122); f:press(122); equal(f.toggles, 1)
    end
    local f = fixture(); local owner = 'loader'
    rawset(_G, 'LiveLuaLoader', {input_status = function() return {owner = owner} end})
    f:press(119); equal(f.opens, 0)
    owner = nil; f:update(); equal(f.opens, 0)
    f:release(119); f:press(119); equal(f.opens, 1)
end)

test('rebinding to a held key seeds the edge and old bindings stop working', function()
    local f = fixture(); f.keys[118] = true; f.bindings.editor_key = 118
    f:update(); f:update(); equal(f.opens, 0)
    f:press(119); equal(f.opens, 0)
    f:release(118); f:press(118); equal(f.opens, 1)
end)

test('unbound keys and framework menu key never activate the mod', function()
    local f = fixture(); f.bindings.editor_key, f.bindings.toggle_key = 0, 0
    f:update(); f:press(119); f:press(122); equal(f.opens, 0); equal(f.toggles, 0)
    f.bindings.editor_key, f.bindings.toggle_key, f.global_key = 120, 121, 120
    f:release(120); f:release(121); f:press(120); equal(f.opens, 0)
    f:press(121); equal(f.toggles, 1)
end)

test('provider input replacement seeds held keys', function()
    local f = fixture(); f.keys[119] = true
    f.api.camera_input = {down = function(key) return f.keys[key] == true end, focused = function() return true end}
    f:update(); f:update(); equal(f.opens, 0)
    f:release(119); f:press(119); equal(f.opens, 1)
end)

test('duplicate hotkey bindings perform only the FPV toggle', function()
    local f = fixture(); f.bindings.toggle_key = 119; f:update()
    f:press(119); equal(f.toggles, 1); equal(f.opens, 0)
end)

test('waiting for a new weapon leaves placement action available', function()
    local f = fixture(); f.controller.enabled, f.controller.phase = true, 'waiting'; f:update()
    assert(not f.controls.edit_placement.disabled); assert(f.controls.start_true_first_person.disabled); assert(f.controls.start_native_test.disabled)
    f:press(119); equal(f.opens, 1)
end)

test('stop attempts native cleanup even when editor release is pending', function()
    local f = fixture(true); f.controller.enabled, f.controller.phase = true, 'running'
    f.editor:request_open(); f.cancel_failure = true
    assert(not f.controls.stop_test.on_activate()); equal(f.cancels, 1); equal(f.stops, 1); assert(not f.controller:is_enabled())
end)

test('shutdown disables shortcuts and waits for both owners before unregister', function()
    local f = fixture(); f.controller.enabled, f.controller.phase = true, 'running'
    f.menu:begin_shutdown(); f:press(119); f:press(122); equal(f.opens, 0); equal(f.toggles, 0)
    assert(not f.menu:shutdown()); equal(f.unregisters, 0)
    f.controller:stop(); f.editor.phase = 'closing'; assert(not f.menu:shutdown()); equal(f.unregisters, 0)
    f.editor.phase = 'idle'; assert(f.menu:shutdown()); equal(f.unregisters, 1)
end)

test('F8 and Shift F8 both edit TFP models without the parked Fird head camera',function()
 local f=fixture();f.keys[16]=true;f:press(119);equal(f.kind,'weapon');f:release(119);f.editor:cancel()
 f.keys[16]=false;f:press(119);equal(f.kind,'weapon')
end)

test('motion settings are independently configurable and cached until a setting event',function()
 local f=fixture();local one=f.menu:motion_options();equal(one.sprint_strength,1);equal(one.camera_bob_strength,0)
 f.bindings.weapon_bob_strength=200;f.bindings.camera_bob_strength=0
 equal(f.menu:motion_options(),one)
 f.setting_changed();local two=f.menu:motion_options();equal(two.bob_strength,2);equal(two.camera_bob_strength,0)
 equal(two.sway_strength,1);equal(two.camera_sway_strength,0)
end)

test('primary menu action starts True First Person without invoking Fird',function()
 local f=fixture();local calls=0
 f.actions.start_fird=function()error('Parked Fird action was invoked')end
 f.actions.start_true_first_person=function()calls=calls+1;return f.controller:start(0,'pose_offset')end
 f:update();assert(not f.controls.start_true_first_person.disabled)
 assert(f.controls.start_true_first_person.on_activate());f:update();equal(calls,1);equal(f.starts,1)
 assert(f.controls.start_true_first_person.disabled and f.controls.start_native_test.disabled)
 assert(not f.controls.stop_test.disabled and not f.controls.edit_placement.disabled)
end)

test('F11 selects only True First Person and Fird options are absent',function()
 local f=fixture();local true_calls=0
 f.actions.start_fird=function()error('F11 must not enter Fird')end
 f.actions.start_true_first_person=function()true_calls=true_calls+1;return f.controller:start(0,'pose_offset')end
 f.actions.toggle_pose=function()
  f.toggles=f.toggles+1
  if f.controller:is_enabled()then return f.actions.stop()end
  return f.actions.start_true_first_person()
 end
 f:update()
 equal(f.controls.start_true_first_person.label,'Enable True First Person')
 equal(f.controls.toggle_key.label,'Toggle True First Person')
 assert(not f.controls.start_test and not f.controls.ads_mode)
 assert(f.description:find('F11 toggles True First Person',1,true)and not f.description:find('Fird',1,true))
 assert(f.controls.start_true_first_person.on_activate());f:update();equal(true_calls,1)
 equal(f.duration,0);equal(f.mode,'pose_offset');assert(f.controller:is_enabled())
 assert(not f.controls.start_true_first_person.on_activate());equal(true_calls,1)
 assert(f.controls.stop_test.on_activate());f:update()
 f:press(122);equal(true_calls,2);assert(f.controller:is_enabled())
 f:update();equal(true_calls,2)
 f:release(122);f:press(122);assert(not f.controller:is_enabled())
end)

test('True First Person enable rejects active views editing and pending cleanup',function()
 for _,reason in ipairs({'original','other_view','controller_cleanup','other_cleanup','editing','closing'})do
  local f=fixture();local calls=0
  f.actions.start_true_first_person=function()calls=calls+1;return true end
  if reason=='original'then f.controller.enabled=true;f.controller.phase='running'
  elseif reason=='other_view'then f.actions.is_enabled=function()return true end
  elseif reason=='controller_cleanup'then f.controller.phase='cleanup_pending'
  elseif reason=='other_cleanup'then f.actions.is_clean=function()return false end
  elseif reason=='editing'then f.editor.phase='active'
  else f.menu:begin_shutdown()end
  f:update();assert(f.controls.start_true_first_person.disabled)
  assert(not f.controls.start_true_first_person.on_activate());equal(calls,0)
 end
end)

test('True First Person fallback cannot route through the Fird pose alias',function()
 local f=fixture();f.actions.start_pose=function()error('Fird pose alias must not enable True First Person')end
 assert(f.controls.start_true_first_person.on_activate());equal(f.mode,'pose_offset');equal(f.duration,0)
 assert(f.controller:is_enabled()and f.starts==1)
end)

test('True First Person native ADS remains available with the Fird choice commented out',function()
 local f=fixture();f:update();local control=assert(f.controls.true_native_ads)
 equal(control.type,'toggle');equal(control.presentation,'checkbox');equal(control.default,false)
 assert(not f.controls.ads_mode);equal(f.menu:native_ads(),false)
 f.bindings.true_native_ads=true;equal(f.menu:native_ads(),true)
 f.bindings.true_native_ads=false;equal(f.menu:native_ads(),false)
 equal(f.starts,0);equal(f.toggles,0)
end)

test('global aim-marker checkbox is available before entering first person',function()
 local f=fixture();local control=assert(f.controls.show_aim_markers)
 equal(control.type,'toggle');equal(control.presentation,'checkbox');equal(control.label,'Show aim markers')
 assert(not f.controller:is_enabled()and not control.disabled and not f.controls.aiming_markers)
 equal(f.marker_saves,0);equal(f.marker_global,nil)
 assert(f.menu.handle.set('show_aim_markers',true));f:update()
 equal(f.marker_global,true);equal(f.marker_saves,1);equal(f.starts,0);equal(f.toggles,0)
 assert(f.menu.handle.set('show_aim_markers',false));f:update()
 equal(f.marker_global,false);equal(f.marker_saves,2);assert(not control.disabled)
end)

test('effective marker display sync preserves unset global legacy preferences',function()
 local f=fixture();f.marker_value=true;f:update()
 equal(f.menu.handle.get('show_aim_markers'),true);equal(f.marker_saves,0);equal(f.marker_global,nil)
 f.marker_value=false;f:update();equal(f.menu.handle.get('show_aim_markers'),false)
 equal(f.marker_saves,0);equal(f.marker_global,nil);equal(f.framework_sets,2)
end)

test('cached menu status still repairs a replaced or stale framework value',function()
 local f=fixture();local reads=f.status_reads;f.bindings.show_aim_markers=true
 f:update();equal(f.menu.handle.get('show_aim_markers'),false);equal(f.marker_saves,0)
 equal(f.status_reads,reads)
end)

test('failed marker save is reported and checkbox returns to saved effective value',function()
 for _,failure in ipairs({'marker_save_failure','marker_save_throw'})do
  local f=fixture();f[failure]=true
  assert(f.menu.handle.set('show_aim_markers',true));f:update()
  equal(f.menu.handle.get('show_aim_markers'),false);equal(f.marker_global,nil);equal(f.marker_saves,0)
  assert(type(f.message)=='string'and f.message:find('save',1,true))
 end
end)

test('marker checkbox only disables for missing support or shutdown',function()
 local f=fixture(true);assert(f.controls.show_aim_markers.disabled)
 f=fixture();f.menu:begin_shutdown();assert(f.controls.show_aim_markers.disabled)
 assert(f.controls.show_aim_markers.on_change(true)==false);equal(f.marker_saves,0)
end)

test('marker callback rejects nonboolean values without saving',function()
 local f=fixture();assert(f.controls.show_aim_markers.on_change('true')==false)
 equal(f.marker_saves,0);equal(f.marker_global,nil)
end)

rawset(_G, 'DBFMCM', previous_api); rawset(_G, 'LiveLuaLoader', previous_loader)
print('Native ADS menu and hotkey fixtures: ' .. passed .. ' passed')

test('motion presets preserve custom sliders and leave native animation settings alone',function()
 local f=fixture();f.bindings.weapon_bob_strength=160;f.bindings.camera_bob_strength=70
 f.setting_changed();local custom=f.menu:motion_options();equal(custom.bob_strength,1.6);equal(custom.camera_bob_strength,0)
 f.bindings.motion_preset=2;f.setting_changed();local comfort=f.menu:motion_options()
 equal(comfort.bob_strength,.45);equal(comfort.camera_bob_strength,0);equal(comfort.camera_sway_strength,0)
 equal(f.bindings.weapon_bob_strength,160);equal(f.bindings.camera_bob_strength,70)
 f.bindings.motion_preset=3;f.setting_changed();local natural=f.menu:motion_options()
 equal(natural.bob_strength,.8);equal(natural.camera_bob_strength,0);equal(natural.camera_sway_strength,0)
 f.bindings.motion_preset=1;f.setting_changed();equal(f.menu:motion_options().bob_strength,1.6)
 equal(f.menu:motion_options().camera_bob_strength,0);equal(f.bindings.camera_bob_strength,70)
end)

test('per-weapon clip drafts never apply until saved and have independent aim clearance',function()
 local f=fixture();local settings={};local key='5663fbf6d81eee27';local owner='current-weapon'
 f.actions.current_weapon=function()return {key=key,identity=owner,label='LAS-5 Scythe',family='energy'}end
 f.actions.presentation_settings=function()return settings end
 f.actions.save_presentation=function(name,value,expected_key,expected_owner)
  if expected_key and(expected_key~=key or expected_owner~=owner)then return false,'Weapon changed'end
  settings[name]=value;return true
 end
 f:update();local record=f.api.mods.goose_native_ads_camera_test;local handle=record.handle
 assert(not f.controls.save_weapon_near.disabled)
 equal(handle.get('weapon_near_hip_cm'),15);equal(handle.get('weapon_near_aim_cm'),5)
 assert(handle.set('weapon_near_hip_cm',12));assert(handle.set('weapon_near_aim_cm',7))
 equal(f.menu:near_options().hip,.15);equal(f.menu:near_options().aim,0)
 assert(f.controls.save_weapon_near.on_activate())
 equal(f.menu:near_options().hip,.12);equal(f.menu:near_options().aim,.07)
 assert(f.menu:near_options().profile)
 key='33e4c47233056d41';owner='new-weapon'
 assert(not f.controls.save_weapon_near.on_activate(),'A stale draft must not save after switching firearm')
 equal(f.menu:near_options().hip,.15);equal(f.menu:near_options().aim,0)
 f:update();equal(handle.get('weapon_near_hip_cm'),15);equal(handle.get('weapon_near_aim_cm'),5)
 assert(handle.set('weapon_near_hip_cm',18));assert(handle.set('weapon_near_aim_cm',5));assert(f.controls.save_weapon_near.on_activate())
 equal(f.menu:near_options().hip,.18);equal(f.menu:near_options().aim,0)
 key='5663fbf6d81eee27';owner='returned-instance';f:update()
 equal(handle.get('weapon_near_hip_cm'),12);equal(handle.get('weapon_near_aim_cm'),7)
 assert(f.controls.reset_weapon_near.on_activate());equal(f.menu:near_options().hip,.15)
 assert(settings.near_clip_profiles['33e4c47233056d41'].hip_cm==18)
end)

test('unavailable and malformed clip profiles preserve global behavior',function()
 local f=fixture();f.actions.presentation_settings=function()return {near_clip_profiles={['5663fbf6d81eee27']={hip_cm=99,aim_cm=7}}}end
 f.actions.current_weapon=function()return {key='5663fbf6d81eee27',identity='owner'}end
 f:update();equal(f.menu:near_options().cm,15)
 assert(f.controls.save_weapon_near.disabled,'No settings writer must disable weapon save')
 f.actions.current_weapon=function()return {key='not-a-resource',identity='owner'}end
 f:update();equal(f.menu:near_options().weapon_key,nil)
 assert(f.controls.weapon_near_hip_cm.disabled)
end)

test('family-placement option only writes the explicit opt-in field',function()
 local f=fixture();local settings={placement={x=.13,y=0,z=0}}
 f.actions.presentation_settings=function()return settings end
 f.actions.save_presentation=function(key,value)settings[key]=value;return true end
 assert(f.controls.family_placement_defaults.on_change(true))
 assert(settings.family_placement_defaults);equal(settings.placement.x,.13)
 assert(not f.controls.family_placement_defaults.on_change('yes'))
end)
print('Composition, comfort/natural motion and per-weapon clipping menu fixtures passed')
