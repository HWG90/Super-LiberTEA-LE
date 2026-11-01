-- Stock Lua 5.1 input. The loader owns the helper, foreground and cursor lease.
local S={}
local names={[8]='backspace',[9]='tab',[13]='enter',[16]='left shift',[17]='left ctrl',[18]='left alt',
 [20]='caps lock',[27]='esc',[32]='space',[33]='page up',[34]='page down',[35]='end',[36]='home',
 [37]='left',[38]='up',[39]='right',[40]='down',[45]='insert',[46]='delete',
 [160]='left shift',[161]='right shift',[162]='left ctrl',[163]='right ctrl',[164]='left alt',[165]='right alt',
 [186]='semicolon',[187]='equal',[188]='comma',[189]='minus',[190]='period',[191]='slash',
 [192]='backtick',[219]='open bracket',[220]='backslash',[221]='close bracket',[222]='quote'}
for code=48,57 do names[code]=string.char(code)end
for code=65,90 do names[code]=string.char(code+32)end
for code=112,135 do names[code]='f'..(code-111)end
-- The engine's Keyboard index is the virtual-key code. Every other key it
-- names (numpad, Pause, Print Screen, Num Lock, OEM keys...) is added from the
-- engine at startup; names ending in ** are its copies of mouse buttons.
local function add_engine_names(keyboard)
 if type(keyboard.button_name)~='function'then return end
 for code=7,255 do if not names[code]then
  local ok,name=pcall(keyboard.button_name,code)
  if ok and type(name)=='string'and name~=''and not name:find('**',1,true)then names[code]=name end
 end end
end
-- Shift, Ctrl and Alt are pressed on either side.
local sides={[16]={160,161},[17]={162,163},[18]={164,165}}
local buttons={[1]=1,[2]=2,[4]=4,[5]=8,[6]=16}
local sample_keys={'x','y','width','height','buttons','wheel'}
local mouse_names={[1]='left',[2]='right',[4]='middle',[5]='extra_1',[6]='extra_2',[256]='wheel_up',[257]='wheel_down'}
function S.binding_spec(code)
 if code==0 then return {}end
 local name=mouse_names[code]or names[code]
 if not name then return nil,'Input name is unavailable in the SDK'end
 return {device=mouse_names[code]and 'mouse'or 'keyboard',button=name,trigger='press'}
end
function S.new(sr,service,log)
 assert(type(service)=='table'and service.version==1 and service.capabilities.menu==true,'Loader shared input service v1 required')
 assert(type(sr.Window.has_focus)=='function'and type(sr.Application.time_since_launch)=='function','Steam focus/clock APIs unavailable')
 add_engine_names(sr.Keyboard)
 local input,capture={}, {active=false}
 local owner='DBF MCM';local token,pending,registration,registered_provider;local focused=false;local clock=0
 local ids,keys={},{};local sampled=false;local pointer={valid=false};local wheel_taken=false
 local function status()return service.status()end
 local function clear()token,pending=nil,false;capture.active=false;pointer.valid=false end
 function capture.release()
  if not token then return true end
  if not service.owns(token)then
   local value=status()
   if not value.pending_restore or value.owner~=owner then clear();return true end
  end
  local ok,why=service.release(token)
  if ok then clear()else pending=true;capture.active=false end
  return ok,why
 end
 function capture.register(provider)
  if registration then return true end
  if type(service.register_frontend)~='function'then return false,'Loader MCM registration API unavailable'end
  local why;registration,why=service.register_frontend('mcm',provider)
  if registration then registered_provider=provider end
  return registration~=nil,why
 end
 function capture.shutdown()
  local ok,why=capture.release();if not ok then return false,why end
  if registration then
   ok,why=service.unregister_frontend(registration)
   if not ok and rawget(_G,'DBFMCM')==registered_provider then return false,why end
   -- After provider replacement, an obsolete registration token has no
   -- authority over the replacement. Our input was restored above.
   registration,registered_provider=nil,nil
  end
  return true
 end
 function capture.status()
  return {owner=token and owner or nil,active=token~=nil and service.owns(token),pending_restore=pending==true}
 end
 function capture.sync(visible,foreground)
  if pending then return false,'Shared input restoration pending'end
  if not visible or not foreground then return capture.release()end
  if token then
   if service.owns(token)then capture.active=true;return true end
   local ok,why=capture.release();if not ok then return false,why end
   return false,'Shared input lease was revoked'
  end
  local why,cleanup
  token,why,cleanup=service.acquire(owner,'menu',registration)
  if not token then token=cleanup;pending=cleanup~=nil;return false,why end
  capture.active=true;return true
 end
 local function sample()
  if sampled then return pointer end
  sampled=true;pointer.valid=false
  if not token or not service.owns(token)then return pointer end
  local value,why=service.snapshot(token)
  if value and value.valid and value.width>0 and value.height>0 then
   -- The provider reuses its table; retain only copied scalar fields.
   for _,key in ipairs(sample_keys)do pointer[key]=value[key]or 0 end
   pointer.valid=true
  else
   capture.active=false
   if log then log('MCM pointer unavailable: '..tostring(why))end
  end
  return pointer
 end
 function input.poll()
  focused=sr.Window.has_focus()==true;clock=sr.Application.time_since_launch()
  for key in pairs(keys)do keys[key]=nil end
  sampled,wheel_taken=false,false;pointer.valid=false
 end
 function input.focused()return focused end
 function input.window()return focused and true or nil end
 function input.now()return clock end
 function input.down(code)
  if not focused then return false end
  if keys[code]~=nil then return keys[code]end
  local value=false
  if buttons[code]then
   local p=sample();value=p.valid and math.floor(p.buttons/buttons[code])%2==1
  elseif sides[code]then
   value=input.down(sides[code][1])or input.down(sides[code][2])
  else
   if ids[code]==nil then
    local ok,id=false,nil
    if names[code]then ok,id=pcall(sr.Keyboard.button_id,names[code])end
    ids[code]=ok and type(id)=='number'and id or false
   end
   if ids[code]~=false then
    local read=sr.Keyboard.button(ids[code]);value=read==true or type(read)=='number'and read>0.5
   end
  end
  keys[code]=value==true;return keys[code]
 end
 function input.mouse()
  local p=sample();if not p.valid then return end
  local w,h=sr.Gui.resolution();return p.x*w/p.width,h-p.y*h/p.height
 end
 function input.wheel()
  if wheel_taken then return 0 end
  wheel_taken=true;local p=sample();return p.valid and p.wheel or 0
 end
 return input,capture
end
return S
