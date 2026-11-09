-- Steam Lua 5.1 frontend. All native input remains owned by the loader service.
local api,menu,view,input,capture,legacy,registered,bindings,diagnostics,diagnostic_owner
local hud_integration;local ctx_owner,loader;local elapsed,restore_retry,restore_ticks=0,0,0;local retired=true
local VERSION='0.1.74-luajit.7'
local painted=false;local last_width,last_height=1920,1080
local function close_menu()
 if menu then menu.visible=false;menu.capture=false;if menu.release_console then menu.release_console()end end
 local ok,why=true,nil
 if capture then ok,why=capture.release()end
 if ok and view then view.release()end
 return ok,why
end
local function shutdown()
 local ok,why=close_menu();if not ok then return false,why end
 if retired then return true end
 if capture then ok,why=capture.shutdown();if not ok then return false,why end end
 if bindings then bindings.release()end
 if hud_integration then hud_integration.release();hud_integration=nil end
 if legacy then legacy.poll(rawget(_G,'ModOptionsMenu'));legacy.release()end
 if registered then registered.unregister()end
 if diagnostics and diagnostic_owner then diagnostics.detach(diagnostic_owner)end
 if rawget(_G,'DBFMCM')==api then rawset(_G,'DBFMCM',nil)end
 api,menu,view,input,capture,legacy,registered,bindings=nil,nil,nil,nil,nil,nil,nil,nil
 diagnostic_owner=nil;retired=true;return true
end
local descriptor={name='Mod Configuration Menu',version=VERSION,author='Goose',
 description='Shared mod configuration for the Steam Lua 5.1 runtime.'}
function descriptor.on_enable(ctx)
 assert(retired and not rawget(_G,'DBFMCM'),'Another MCM instance is active')
 assert(ctx.api==2 and type(ctx.on_cleanup)=='function'and type(ctx.global)=='function','Loader lifecycle API 2 required')
 local sr=assert(rawget(_G,'stingray'),'Stingray unavailable')
 loader=assert(rawget(_G,'LiveLuaLoader'),'Live Lua Loader required for shared input')
 local service=assert(loader.input_service,'Shared input service unavailable')
 local folder=assert(ctx.config_dir,'Loader-owned config directory required')
 ctx_owner=ctx;elapsed=0;painted=false;retired=false;ctx.on_cleanup(shutdown)
 input,capture=MCM.steam_input.new(sr,service,ctx.log)
 local storage=MCM.store.new(folder)
 local legacy_folder=assert(os.getenv('LOCALAPPDATA'))..'/MDL/Helldivers2/Mods/dbf_mcm/settings'
 local old=MCM.store.new(legacy_folder);local primary_load=storage.load
 storage.load=function(id)
  local file=io.open(folder..'/'..id..'.ini','rb')
  if file then file:close();return primary_load(id)end
  return old.load(id)
 end
 local runtime_mod=type(mod)=='table'and type(mod.scope)=='table'and mod.scope.MCM==MCM and mod or nil
 local runtime_values=storage.load('mcm_runtime')or{}
 local runtime_config=runtime_mod and runtime_mod.config or ctx.config or runtime_values
 local runtime_writer=runtime_mod or {set=function(key,value)
  local next_values={};for k,v in pairs(runtime_values)do next_values[k]=v end;next_values[key]=value
  local saved,why=storage.save('mcm_runtime',next_values)
  if saved then runtime_values=next_values end;return saved,why
 end}
 diagnostics=MCM.console.shared(loader.diagnostics)
 diagnostic_owner=diagnostics.attach('MCM',loader.log_directory)
 local logger=MCM.console.owner_logger(loader.log_directory or folder)
 api=MCM.core.new(storage,ctx.log,MCM.grouping,{mod_log=logger,
  verbose=MCM.preferences.verbose_registration(runtime_config)});api.version=VERSION
 local public=api
 local function current()return not retired and api==public and rawget(_G,'DBFMCM')==public end
 MCM.authoring.install(api);api.diagnostics=diagnostics;api.diagnostics_surface=MCM.console.surface
 api.runtime='Lua 5.1';api.shared_input_service=service
 view=MCM.view.new(sr,nil,ctx.log);view.set_font_source(MCM.ui_font.new());menu=MCM.menu.new(api,view.measure)
 menu.text_metrics=view.text_metrics
 menu.set_command_bus(MCM.commands.for_host(api,loader,diagnostics,{get_verbose=api.get_verbose,
  set_verbose=function(value)return MCM.preferences.set_verbose(api,value,runtime_writer)end}))
 function api.is_open()return current()and menu.visible or false end
 function api.input_status()return current()and capture.status()or {active=false,pending_restore=false}end
 function api.close()if not current()then return false,'MCM provider retired'end;return close_menu()end
 function api.open()
  if not current()then return false,'MCM provider retired'end
  if not input.focused()then input.poll()end
  if not input.focused()then return false,'Game is not focused'end
  if type(loader.close_manager)=='function'then
   local ok,why=loader.close_manager();if ok==false then return false,why end
  end
  menu.visible=true;return true
 end
 function api.menu_binding_status()
  if not current()then return {focused=false,editing=false,global_key=46}end
  return {focused=input.focused(),editing=menu.capture~=false or menu.text_edit~=nil or menu.color_picker~=nil,global_key=api.menu_toggle_key or 46}
 end
 function api.focus_page(id,page_id)
  if not current()then return false,'MCM provider retired'end
  for index,entry in ipairs(api.list())do if entry.id==id then
   for page_index,page in ipairs(entry.pages)do if page.id==page_id then
    local ok,why=api.open();if not ok then return false,why end
    menu.selected,menu.page,menu.row,menu.scroll,menu.focus=index,page_index,1,0,'settings';return true
   end end
  end end
  return false,'Requested page unavailable'
 end
 function api.photo_resolution()return sr.Gui.resolution()end
 function api.create_photo_view()return MCM.view.new(sr,nil,ctx.log)end
 function api.integration_status()
  return {runtime='Lua 5.1',input='Loader shared input v1',native='MBM native records edited live',bindings=bindings and bindings.diagnostic(),hud_plus=hud_integration and hud_integration.diagnostic()}
 end
 if not rawget(_G,'ModOptionsMenu')then
  local compat,registry=MCM.compat.new(storage,package.loaded['dbf_mcm.compat_registry'])
  package.loaded['dbf_mcm.compat_registry']=registry;ctx.global('ModOptionsMenu',compat)
 end
 ctx.global('DBFMCM',api)
 local attached,attach_reason=capture.register(api);assert(attached,attach_reason)
 legacy=MCM.legacy.new(api,ctx.log,MCM.core)
 hud_integration=MCM.hud_plus.new(api,ctx.log)
 -- SDK-backed v4 records use MBM's public persistence API. Native action
 -- records are edited in the game's live binding record (src/native_editor.lua).
 local editor=MCM.native_editor.new(storage,ctx.log)
 bindings=MCM.bindings.new(api,ctx.log,{extended_editor=true,input_spec=MCM.steam_input.binding_spec,editor=editor,
  key_name=function(code)return MCM.native_editor.key_name(code,MCM.ui_theme.key_name)end,mouse_key_name=MCM.native_editor.mouse_name})
 local definition=MCM.framework({example_action=function()ctx.log('MCM example activated')end},MCM.authoring)
 local settings_page=MCM.preferences.page(function(key)
  local ok,why=MCM.preferences.apply(api,menu,registered,key)
  if not ok then menu.notice=tostring(why)end
 end,{reset_window=function()return MCM.preferences.reset_window(menu,registered)end})
 settings_page.controls[#settings_page.controls+1]={id='loader_manager',type='button',label='Live Lua Loader',
  button_label='OPEN LOADER',require_confirmation=false,disabled=type(loader.open_manager)~='function',
  description='Restore MCM input, then open the loader manager.',on_activate=function()
   local restored,reason=api.close();assert(restored,reason)
   local called,result=pcall(loader.open_manager);assert(called,result)
   assert(result~=false,'Loader manager refused to open');return 'Opened loader manager'
  end}
 table.insert(definition.pages,1,settings_page)
 registered=api.register(definition);api.settings_mod_id=registered.id;api.settings_page_id='mcm_settings'
 local ok,why=MCM.preferences.apply(api,menu,registered);assert(ok,why)
 if runtime_mod and type(runtime_mod.expose)=='function'then
  local fields={}
  for key,value in pairs(MCM.preferences.defaults())do
   local field=key;fields[field]={type=type(value),get=function()return registered.get(field)end,
    set=function(v)return registered.set(field,v)end}
  end
  runtime_mod.expose('mcm',{settings=fields,verbose_registration={type='boolean',get=api.get_verbose,
   set=function(value)return MCM.preferences.set_verbose(api,value,runtime_writer)end}})
 end
 legacy.poll(rawget(_G,'ModOptionsMenu'));hud_integration.poll();bindings.poll(rawget(_G,'ModBindingsMenu'))
 ctx.log('MCM '..VERSION..' initialized; shared input ownership integration pending verification')
end
function descriptor.on_update(ctx,dt)
 if retired then return end
 if rawget(_G,'DBFMCM')~=api then shutdown();return end
 local ok,why=pcall(function()
  input.poll()
  if capture.status().pending_restore then
   menu.visible=false;restore_retry=restore_retry+math.max(0,tonumber(dt)or 0)
   if restore_retry>=.25 then
    restore_retry=0;local restored=capture.release()
    if restored then menu.input_focus(false,input)end
   end
   return
  end
  restore_retry=0;elapsed=elapsed+math.max(0,tonumber(dt)or 0)
  if elapsed>=.25 then
   elapsed=0;legacy.poll(rawget(_G,'ModOptionsMenu'))
   restore_ticks=restore_ticks+1
   if restore_ticks>=4 then restore_ticks=0;bindings.restore(rawget(_G,'ModBindingsMenu'))end
   local selected=menu.visible and api.list()[menu.selected]
   local page=selected and selected.pages[menu.page]
   if menu.visible then bindings.poll(rawget(_G,'ModBindingsMenu'),page and page.native_binding_category)end
   -- Public bridge discovery/snapshots run only while the menu is active.
   -- No legacy native-owner recovery or HUD+ loading is performed here.
   if menu.visible then hud_integration.poll()end
  end
  local focused=input.focused();local process=menu.input_focus(focused,input)
  if process and not menu.visible then menu.tick(input);process=false end
  if focused and menu.visible and not capture.active and type(loader.close_manager)=='function'then
   local released,reason=loader.close_manager();if released==false then menu.visible=false;menu.notice=tostring(reason)end
  end
  local acquired,reason=capture.sync(menu.visible,focused)
  if not acquired then menu.visible=false;menu.capture=false;menu.notice=tostring(reason);capture.release()end
  if acquired and process then menu.tick(input)end
  if not menu.visible then capture.release()end
  menu.advance(dt)
  if menu.visible then
   last_width,last_height=stingray.Gui.resolution()
   view.refresh_font();menu.font_metric_key=view.metric_key
   view.draw(menu.compose(last_width,last_height,true));painted=true
  elseif painted then
   -- Clear transient menu state once on close, not on every idle frame.
   view.draw(menu.compose(last_width,last_height,true));painted=false
  end
 end)
 if not ok then
  ctx.log('MCM frame failed: '..tostring(why));menu.recover();capture.release();view.release()
 end
end
descriptor.on_disable=shutdown;descriptor.on_cleanup_poll=shutdown
return descriptor
