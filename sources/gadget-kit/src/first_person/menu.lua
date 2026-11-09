local PORT51=mod.require('src/first_person/compat51.lua')
local Integration=mod.require('src/first_person.lua')
local M = {}
local ID = 'goose_native_ads_camera_test'
-- Presets affect presentation additions only. The native weapon animation,
-- recoil and look input remain untouched. Custom retains every existing slider.
local motion_presets={
    [2]={bob_strength=.45,bob_speed=1,sway_strength=.45,sway_speed=1,sprint_strength=.35},
    [3]={bob_strength=.8,bob_speed=1,sway_strength=.8,sway_speed=1,sprint_strength=.55},
}
local function clip_cm(value)return PORT51.kind(value)=='number'and value==value and value%1==0 and value>=5 and value<=40 end
local function resource_key(value)return PORT51.kind(value)=='string'and #value==16 and value:match('^%x+$')~=nil end

function M.new(controller, log, editor, actions)
    local self = { owner = nil, handle = nil, closing = false }
    log, actions = log or function() end, actions or {}
    local hotkeys = {}
    local status_dirty, unsubscribe = true, nil
    local motion_dirty,motion_cache=true,nil
    local near_dirty,near_cache=true,nil
    local motion_controls={
        {'bob_strength','weapon_bob_strength','Weapon bob strength',0,300,100},
        {'bob_speed','weapon_bob_speed','Weapon bob speed',25,200,100},
        {'sway_strength','weapon_sway_strength','Weapon sway strength',0,300,100},
        {'sway_speed','weapon_sway_speed','Weapon sway response speed',25,200,100},
        {'sprint_strength','sprint_motion_strength','Sprint weapon movement',0,200,100},
    }
    local drawn_dev
    local drawn_marker_setting,drawn_marker_available
    local syncing_markers=false
    local syncing_family=false
    local clip_target,clip_source
    local drawn_weapon_key,drawn_weapon_identity
    local drawn_record, drawn_phase, drawn_enabled, drawn_clean, drawn_editing, drawn_closing
    if PORT51.kind(controller.on_status_changed)=='function' then
        unsubscribe=controller:on_status_changed(function()status_dirty=true end)
    end
    local function record()
        local value = self.owner and self.owner.mods and self.owner.mods[ID]
        return value and value.handle == self.handle and value or nil
    end
    local function plain(target, name, ...)
        if PORT51.kind(target) ~= 'table' or PORT51.kind(target[name]) ~= 'function' then return nil end
        local ok, value, why = pcall(target[name], ...)
        if ok then return value, why end
        return nil, tostring(value)
    end
    local function marker_setting()
        return plain(actions,'aim_markers_setting')==true
    end
    local function sync_marker_setting(value)
        if plain(self.handle,'get','show_aim_markers')==value then return end
        if PORT51.kind(self.handle)=='table'and PORT51.kind(self.handle.set)=='function'then
            -- MCM stores checkbox values through handle.set and invokes the
            -- callback. Display synchronization must not create a global
            -- override while the saved per-weapon preferences still apply.
            syncing_markers=true
            plain(self.handle,'set','show_aim_markers',value)
            syncing_markers=false
        end
    end
    local function enabled()
        if PORT51.kind(actions.is_enabled)=='function'then return actions.is_enabled()==true end
        if PORT51.kind(controller.is_enabled) ~= 'function' then return false end
        local ok, value = pcall(controller.is_enabled, controller)
        return ok and value == true
    end
    local function editor_active() return editor and editor:is_active() or false end
    local function start_guard()
        if self.closing then return false,'Mod is stopping'end
        if enabled()then return false,'Turn the active first-person view off first'end
        local clean=controller:is_clean()
        if actions.is_clean then clean=plain(actions,'is_clean')==true end
        if not clean or editor_active()then return false,'First-person cleanup or placement editing is pending'end
        return true
    end
    -- Fird entry remains archived with its commented-out controls.
    -- local function start_pose()
    --     local ready,problem=start_guard();if not ready then return false,problem end
    --     local done, why
    --     if actions.start_fird then done,why=actions.start_fird()
    --     elseif actions.start_pose then done, why = actions.start_pose(0)
    --     else done, why = controller:start(0, 'pose_offset') end
    --     if done ~= true then log(tostring(why)) end
    --     return done, why
    -- end
    local function start_true_first_person()
        local ready,problem=start_guard();if not ready then return false,problem end
        local done,why
        if actions.start_true_first_person then done,why=actions.start_true_first_person()
        else done,why=controller:start(0,'pose_offset')end
        if done~=true then log(tostring(why))end
        return done,why
    end
    local function stop()
        if actions.stop then return actions.stop() end
        local editor_done, editor_why = true, nil
        if editor_active() then editor_done, editor_why = editor:cancel('First person turned off') end
        -- Input restoration can remain pending; native camera cleanup still
        -- gets its independent attempt in this same action.
        local stopped, why = controller:stop('manual stop')
        if stopped ~= true then return false, why end
        return editor_done, editor_why
    end
    local function toggle_pose()
        if self.closing then return false, 'Mod is stopping' end
        if actions.toggle_pose then return actions.toggle_pose() end
        if enabled() then return stop() end
        return start_true_first_person()
    end
    local function toggle_editor(camera_mode)
        if self.closing or not editor then return false, 'Placement editor is unavailable' end
        if editor_active() then return editor:cancel('Placement editing cancelled; first person stays on') end
        return editor:request_open(camera_mode and 'camera'or 'weapon')
    end
    local function unregister()
        if self.handle then
            local called, done, why = pcall(self.handle.unregister)
            if not called or done == false then return false, called and why or done end
        end
        self.handle, self.owner, hotkeys = nil, nil, {};motion_cache=nil;motion_dirty=true;near_cache=nil;near_dirty=true
        return true
    end
    local function key(id, default)
        local value = plain(self.handle, 'get', id)
        if PORT51.kind(value) ~= 'number' or value ~= math.floor(value) or value < 0 or value > 255 then return default end
        return value
    end
    local function presentation_settings()
        local value=plain(actions,'presentation_settings')
        return PORT51.kind(value)=='table'and value or {}
    end
    local function current_weapon()
        local value=plain(actions,'current_weapon')
        if PORT51.kind(value)~='table'or not resource_key(value.key)or value.identity==nil then return nil end
        return value
    end
    local function clip_profile(key)
        local settings=presentation_settings();local all=settings.near_clip_profiles
        local row=key and PORT51.kind(all)=='table'and all[key]
        if PORT51.kind(row)=='table'and clip_cm(row.hip_cm)and clip_cm(row.aim_cm)then return row,all end
        return nil,all
    end
    local function global_near()
        local cm=plain(self.handle,'get','near_clip_cm')
        if not clip_cm(cm)then cm=15 end
        local aiming=plain(self.handle,'get','near_clip_aim')==true
        return cm,aiming and cm or 5
    end
    function self:motion_options(defaults)
        if motion_cache and not motion_dirty then return motion_cache end
        defaults=defaults or {};local enabled=plain(self.handle,'get','motion_enabled')
        local percent=plain(self.handle,'get','motion_strength')
        if PORT51.kind(enabled)~='boolean'then enabled=defaults.enabled~=false end
        if PORT51.kind(percent)~='number'or percent~=percent or percent<0 or percent>200 then percent=(defaults.scale or 1)*100 end
        local value={enabled=enabled,scale=percent/100,camera_bob_strength=0,camera_sway_strength=0}
        local preset=motion_presets[plain(self.handle,'get','motion_preset')]
        for _,row in ipairs(motion_controls)do
            local n=plain(self.handle,'get',row[2])
            if PORT51.kind(n)~='number'or n~=n or n<row[4]or n>row[5]then n=row[6]end
            value[row[1]]=preset and preset[row[1]]or n/100
        end
        motion_cache,motion_dirty=value,false;return value
    end
    -- Centimetres in storage; 5 is the game's own distance (off). A weapon
    -- profile supplies independent hip and normal-aim values. Full ADS remains
    -- an unconditional native path inside the existing near-clip helper.
    function self:near_options()
        local weapon=current_weapon();local key=weapon and weapon.key
        local profile=clip_profile(key)
        local hip,aim=global_near()
        if profile then hip,aim=profile.hip_cm,profile.aim_cm end
        if near_cache and not near_dirty and near_cache.cm==hip and near_cache.aim_cm==aim
            and near_cache.weapon_key==key and near_cache.profile==(profile~=nil)then return near_cache end
        near_cache,near_dirty={hip=hip>5 and hip/100 or 0,aim=aim>5 and aim/100 or 0,
            cm=hip,aim_cm=aim,while_aiming=aim>5,weapon_key=key,profile=profile~=nil},false
        return near_cache
    end
    local function save_clip(remove)
        if self.closing then return false,'Mod is stopping'end
        local weapon=current_weapon()
        if not weapon or not clip_target or weapon.key~=clip_target.key or weapon.identity~=clip_target.identity then
            return false,'Weapon changed; reopen its clipping controls'
        end
        local hip=plain(self.handle,'get','weapon_near_hip_cm')
        local aim=plain(self.handle,'get','weapon_near_aim_cm')
        if not remove and(not clip_cm(hip)or not clip_cm(aim))then return false,'Clip distances must be 5 to 40 cm'end
        local _,old=clip_profile(weapon.key);local profiles={}
        for key,row in pairs(PORT51.kind(old)=='table'and old or {})do
            if key~=weapon.key and resource_key(key)and PORT51.kind(row)=='table'and clip_cm(row.hip_cm)and clip_cm(row.aim_cm)then
                profiles[key]={hip_cm=row.hip_cm,aim_cm=row.aim_cm}
            end
        end
        if not remove then profiles[weapon.key]={hip_cm=hip,aim_cm=aim}end
        local done,why=plain(actions,'save_presentation','near_clip_profiles',profiles,weapon.key,weapon.identity)
        if done~=true then return false,why or 'Clipping settings could not be saved'end
        near_dirty,status_dirty=true,true;clip_source=nil
        return true
    end
    local function refresh_weapon_controls(registered)
        local weapon=current_weapon();local key,identity=weapon and weapon.key,weapon and weapon.identity
        local profile,source=clip_profile(key)
        local controls=registered.controls or {}
        local available=PORT51.kind(actions.save_presentation)=='function'
        if controls.family_placement_defaults then controls.family_placement_defaults.disabled=self.closing or not available end
        local family_enabled=presentation_settings().family_placement_defaults==true
        if not self.closing and available and plain(self.handle,'get','family_placement_defaults')~=family_enabled then
            syncing_family=true;plain(self.handle,'set','family_placement_defaults',family_enabled);syncing_family=false
        end
        local writable=not self.closing and weapon~=nil and available
        for _,id in ipairs({'weapon_near_hip_cm','weapon_near_aim_cm','save_weapon_near','reset_weapon_near'})do
            if controls[id]then controls[id].disabled=not writable end
        end
        if key~=drawn_weapon_key or identity~=drawn_weapon_identity or source~=clip_source then
            clip_target=weapon and{key=key,identity=identity}or nil
            clip_source=source
            local hip,aim=global_near();if profile then hip,aim=profile.hip_cm,profile.aim_cm end
            -- These are drafts, not live settings. Switching firearms can never
            -- apply the prior firearm's unsaved slider values to its successor.
            if self.handle then
                if plain(self.handle,'get','weapon_near_hip_cm')~=hip then plain(self.handle,'set','weapon_near_hip_cm',hip)end
                if plain(self.handle,'get','weapon_near_aim_cm')~=aim then plain(self.handle,'set','weapon_near_aim_cm',aim)end
            end
            drawn_weapon_key,drawn_weapon_identity=key,identity;status_dirty=true
        end
        for _,page in ipairs(registered.pages or {})do for _,control in ipairs(page.controls or {})do
            if control.id=='first_person_weapon_composition_status'or control.id=='weapon_composition_status'then
                control.label=weapon and('Weapon: '..tostring(weapon.label or weapon.key)..(weapon.family and(' ('..weapon.family..')')or''))or 'Weapon: enable First Person with a firearm to edit its clipping'
            end
        end end
    end
    function self:native_ads()return plain(self.handle,'get','true_native_ads')==true end
    function self:ads_mode()
        return plain(self.handle,'get','ads_mode')==2 and'native'or'fird'
    end
    local function poll_hotkeys(api)
        local input = api and api.camera_input
        if PORT51.kind(input) ~= 'table' or PORT51.kind(input.down) ~= 'function' or PORT51.kind(input.focused) ~= 'function' then
            hotkeys = {}; return
        end
        if type(input.frame)=='function'then input.frame()end
        local edit_key, toggle_key = key('editor_key', 119), key('toggle_key', 122)
        local edit_down = edit_key ~= 0 and plain(input, 'down', edit_key) == true
        local toggle_down = toggle_key ~= 0 and plain(input, 'down', toggle_key) == true
        local binding = plain(api, 'menu_binding_status')
        local capture = plain(api, 'input_status')
        local own_editor = editor and editor.phase == 'active' and PORT51.kind(capture) == 'table' and capture.owner == 'goose_first_person_editor'
        local clear_input = PORT51.kind(capture) == 'table' and not capture.pending_restore
            and ((not capture.owner and not capture.active) or own_editor)
        local eligible = not self.closing and plain(input, 'focused') == true
            and PORT51.kind(binding) == 'table' and binding.focused == true and binding.editing ~= true
            and plain(api, 'is_open') == false and clear_input
        local loader = rawget(_G, 'LiveLuaLoader')
        if PORT51.kind(loader) == 'table' and PORT51.kind(loader.input_status) == 'function' then
            local loader_capture = plain(loader, 'input_status')
            if PORT51.kind(loader_capture) ~= 'table' or loader_capture.owner or loader_capture.pending_restore then eligible = false end
        end
        local changed = hotkeys.provider ~= api or hotkeys.input ~= input
            or hotkeys.edit_key ~= edit_key or hotkeys.toggle_key ~= toggle_key
        if not eligible or changed or not hotkeys.ready then
            hotkeys = { provider = api, input = input, edit_key = edit_key, toggle_key = toggle_key,
                edit_down = edit_down, toggle_down = toggle_down, ready = eligible }
            return
        end
        local edit_edge, toggle_edge = edit_down and not hotkeys.edit_down, toggle_down and not hotkeys.toggle_down
        hotkeys.edit_down, hotkeys.toggle_down = edit_down, toggle_down
        -- The framework's own menu key always belongs to MCM. Duplicate mod
        -- bindings perform at most one action, with the FPV toggle taking priority.
        if toggle_edge and toggle_key ~= binding.global_key then
            local done, why = toggle_pose(); if done ~= true then log(tostring(why)) end
        elseif edit_edge and edit_key ~= binding.global_key then
            -- Fird head-camera editing is parked, including Shift+F8.
            -- local shift=plain(input,'down',16)==true or plain(input,'down',160)==true or plain(input,'down',161)==true
            local done, why = toggle_editor(false); if done ~= true then log(tostring(why)) end
        end
    end
    function self:refresh_status()
        local registered = record()
        if not registered then return end
        refresh_weapon_controls(registered)
        local dev=actions.dev_status and actions.dev_status()or nil
        local clean=controller:is_clean()
        if actions.is_clean then clean=actions.is_clean()==true end
        local is_enabled, editing = enabled(), editor_active()
        local markers=marker_setting()
        local markers_available=PORT51.kind(actions.aim_markers_setting)=='function'
            and PORT51.kind(actions.set_aim_markers_setting)=='function'
        if not self.closing then sync_marker_setting(markers)end
        if not status_dirty and drawn_dev==dev and drawn_record==registered and drawn_phase==controller.phase
            and drawn_marker_setting==markers and drawn_marker_available==markers_available
            and drawn_enabled==is_enabled and drawn_clean==clean and drawn_editing==editing
            and drawn_closing==self.closing then return end
        local label = PORT51.kind(controller.display_status)=='function' and controller:display_status() or controller:status()
        if dev then label=dev end
        drawn_dev=dev
        for _, page in ipairs(registered.pages or {}) do
            for _, control in ipairs(page.controls or {}) do
                if control.id == 'first_person_runtime_status' then control.label = 'Status: ' .. label end
            end
        end
        local controls = registered.controls or {}
        drawn_marker_setting,drawn_marker_available=markers,markers_available
        if controls.show_aim_markers then
            controls.show_aim_markers.disabled=self.closing or not markers_available
        end
        -- if controls.start_test then controls.start_test.disabled = self.closing or is_enabled or not clean or editing end
        if controls.start_true_first_person then controls.start_true_first_person.disabled = self.closing or is_enabled or not clean or editing end
        if controls.start_native_test then controls.start_native_test.disabled = self.closing or not clean or editing end
        if controls.edit_placement then
            controls.edit_placement.disabled = self.closing or not editor or editing or (not is_enabled and not clean)
        end
        if controls.stop_test then controls.stop_test.disabled = self.closing end
        status_dirty=false
        drawn_record,drawn_phase,drawn_enabled,drawn_clean,drawn_editing,drawn_closing=
            registered,controller.phase,is_enabled,clean,editing,self.closing
    end
    function self:update()
        if self.closing then self:refresh_status(); return true end
        local api = Integration.menu_api()
        local supported = PORT51.kind(api) == 'table' and PORT51.kind(api.register) == 'function'
        if self.owner and (api ~= self.owner or not record()) then
            local done, why = unregister()
            if done ~= true then return false, why end
        end
        if supported and not self.handle then
            local movement_controls={}
            for _,row in ipairs(motion_controls)do movement_controls[#movement_controls+1]={id=row[2],type='slider',label=row[3],min=row[4],max=row[5],step=5,default=row[6]}end
            local called, handle = pcall(api.register, {
                id = ID, name = 'Native ADS Camera Test',
                on_change=function()motion_dirty=true;near_dirty=true end,
                description = 'Use the game\'s first-person arms and weapon view. F11 toggles True First Person.',
                pages = {{ id = 'test', name = 'First person', require_confirmation = false, controls = {
                    -- Fird Person options are parked; True First Person is the active view.
                    -- { id = 'start_test', type = 'button', label = 'Enable Fird Person', require_confirmation = false,
                    --   on_activate = start_pose },
                    {id='start_true_first_person',type='button',label='Enable True First Person',require_confirmation=false,
                      on_activate=start_true_first_person},
                    { id = 'stop_test', type = 'button', label = 'Turn first-person view off', require_confirmation = false,
                      on_activate = stop },
                    {id='show_aim_markers',type='toggle',presentation='checkbox',label='Show aim markers',default=marker_setting(),require_confirmation=false,
                      description='Show the crosshair and aiming circle while aiming in first person. Both remain visible when not aiming. Saved weapon preferences apply until you change this option. Hit markers and scope markings keep their normal behavior.',
                      on_change=function(value)
                          if syncing_markers then return true end
                          if self.closing then return false,'Mod is stopping'end
                          if PORT51.kind(value)~='boolean'then return false,'Aim-marker setting must be on or off'end
                          if not actions.set_aim_markers_setting then return false,'Aim-marker setting is unavailable'end
                          local called,done,why=pcall(actions.set_aim_markers_setting,value)
                          if not called then why=tostring(done);done=false end
                          status_dirty=true
                          if done~=true then log(tostring(why))end
                          return done,why
                      end},
                    { id = 'edit_placement', type = 'button', label = 'Edit arms and weapon placement', require_confirmation = false,
                      on_activate = function()return toggle_editor(false)end },
                    {id='start_free_aim',type='button',label='Free aim (30 seconds)',require_confirmation=false,
                        description='Native FPV free aim for 30 seconds. Normal aim tightens the zone; full ADS stays native. F11 turns FPV off.',
                        on_activate=function()if actions.start_free_aim then return actions.start_free_aim()end;return false,'Free aim unavailable'end},
                    { id = 'editor_key' , type = 'keybind', label = 'Open / close placement editor', default = 119,
                      description = 'Default F8. Closing the editor restores unsaved placement and leaves first person on.' },
                    { id = 'toggle_key', type = 'keybind', label = 'Toggle True First Person', default = 122,
                      description = 'Default F11. Toggle True First Person; it stays enabled when changing weapons.' },
                    {id='true_native_ads',type='toggle',presentation='checkbox',label='True First Person: native ADS',default=false,
                      description='Use the game\'s native sights and zoom while aiming in True First Person.'},
                    -- {id='ads_mode',type='choice',presentation='dropdown',label='Fird Person: ADS behavior',
                    -- choices={'Third-person aim at the eye camera','Native first-person ADS'},default=1,
                    -- description='Keep the game\'s natural third-person aim motion at the eye camera, or use native first-person ADS while aiming.'},
                    {id='family_placement_defaults',type='toggle',presentation='checkbox',label='Use weapon-family placement defaults',
                      default=presentation_settings().family_placement_defaults==true,
                      description='Opt in to conservative defaults for catalogue-identified firearms. Saved weapon/action placements and your customised global placement take precedence. Unknown weapons retain the existing baseline.',
                      on_change=function(value)
                          if syncing_family then return true end
                          if self.closing or PORT51.kind(value)~='boolean'then return false,'Placement option unavailable'end
                          local done,why=plain(actions,'save_presentation','family_placement_defaults',value)
                          status_dirty=true;if done~=true then log(tostring(why or 'Placement preference could not be saved'))end;return done==true,why
                      end},
                    {id='motion_preset',type='choice',presentation='dropdown',label='Motion preset',choices={'Custom (keep existing sliders)','Comfort','Natural'},default=1,
                      description='Comfort adds restrained weapon movement. Natural adds more weapon motion. Custom restores your existing sliders; selecting a preset never overwrites them. The game controls camera movement.'},
                    {id='motion_enabled',type='toggle',label='Weapon movement',default=true,
                      description='Walking bob, turn inertia and a lowered sprint position. ADS remains steady.'},
                    {id='motion_strength',type='slider',label='Weapon movement strength',min=0,max=200,step=5,default=100},
                    {id='near_clip_cm',type='slider',label='Near clip distance (cm)',min=5,max=40,step=1,default=15,
                      description='Hides anything closer to the first-person camera than this, such as armor edges. 5 is the game\'s own distance (off). Full ADS always uses the game\'s distance.'},
                    {id='near_clip_aim',type='toggle',label='Near clip while aiming',default=false,
                      description='Keep the near clip during normal aim. Off returns to the game\'s distance while aiming so sights are not cut.'},
                    {id='weapon_composition_status',type='text',label='Weapon: no active firearm'},
                    {id='weapon_near_hip_cm',type='slider',label='This weapon: hip clearance (cm)',min=5,max=40,step=1,default=15,
                      description='Draft for this firearm only. Save below to apply. 5 keeps the game distance.'},
                    {id='weapon_near_aim_cm',type='slider',label='This weapon: normal-aim clearance (cm)',min=5,max=40,step=1,default=5,
                      description='Independent normal-aim clearance. Full native ADS always keeps the game distance.'},
                    {id='save_weapon_near',type='button',label='Save clipping for this weapon',require_confirmation=false,on_activate=function()return save_clip(false)end},
                    {id='reset_weapon_near',type='button',label='Use global clipping for this weapon',require_confirmation=false,on_activate=function()return save_clip(true)end},
                    { id = 'start_native_test', type = 'button', label = 'Compare native ADS camera (30 seconds)', require_confirmation = false,
                      on_activate = function()
                          if self.closing then return false, 'Mod is stopping' end
                          local done, why
                          if actions.start_native then done,why=actions.start_native(30)
                          else done,why=controller:start(30,'native') end
                          if done ~= true then log(tostring(why)) end
                          return done, why
                      end },
                    { id = 'runtime_status', type = 'text', label = 'Status: First person off' },
                }},{id='movement',name='Bob and sway',require_confirmation=false,controls=movement_controls}},
            })
            if not called then return false, handle end
            if PORT51.kind(handle) ~= 'table' or PORT51.kind(handle.unregister) ~= 'function' then
                return false, 'Unsupported DBF-MCM registration handle'
            end
            self.owner, self.handle = api, handle;motion_cache=nil;motion_dirty=true;near_cache=nil;near_dirty=true
            hotkeys = {}
        end
        self:refresh_status()
        if self.handle then poll_hotkeys(api) end
        return true
    end
    function self:begin_shutdown() self.closing = true; hotkeys = {}; self:refresh_status() end
    function self:shutdown()
        if not controller:is_clean() then return false, 'Native camera cleanup remains pending' end
        if editor_active() then return false, 'Placement input cleanup remains pending' end
        local done,why=unregister()
        if done and unsubscribe then unsubscribe();unsubscribe=nil end
        return done,why
    end
    return self
end
return M
