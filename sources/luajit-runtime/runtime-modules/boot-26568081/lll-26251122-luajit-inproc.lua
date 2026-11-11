local function start()
local LLL_TRUST=(function()
-- Snapshot only loader dependencies; mod code still executes in its normal environment.
local M = {}
function M.capture(environment, options)
    local snapshot = {}
    local next, type = next, type
    local function copy(value)
        local result = {}
        if type(value) == "table" then for key, item in next, value do result[key] = item end end
        return result
    end
    for _, name in ipairs({"assert","error","pcall","xpcall","type","tostring","tonumber","rawget","rawset","rawequal","pairs","ipairs","next","select","unpack","loadstring","loadfile","dofile","setfenv","getfenv","setmetatable","getmetatable","collectgarbage","print"}) do
        snapshot[name] = environment[name]
    end
    for _, name in ipairs({"string","table","math","io","os","debug","coroutine","package"}) do snapshot[name] = copy(environment[name]) end
    local original_require = environment.require
    local portable = options and options.runtime == "lua51"
    local ffi = not portable and copy(original_require("ffi"))
    local bit = not portable and copy(original_require("bit"))
    snapshot.jit = copy(environment.jit)
    snapshot.jit.opt = copy(snapshot.jit.opt)
    snapshot.require = function(name)
        if name == "ffi" and ffi then return ffi end
        if name == "bit" and bit then return bit end
        if name == "jit" then return snapshot.jit end
        return original_require(name)
    end
    return snapshot
end
return M

end)().capture(_G,{runtime="lua51"})
local assert,error,pcall,xpcall,type,tostring,tonumber,rawget,rawset,rawequal,pairs,ipairs,next,select,unpack,loadstring,loadfile,dofile,setfenv,getfenv,setmetatable,getmetatable,collectgarbage,print,string,table,math,io,os,debug,coroutine,package,require=LLL_TRUST.assert,LLL_TRUST.error,LLL_TRUST.pcall,LLL_TRUST.xpcall,LLL_TRUST.type,LLL_TRUST.tostring,LLL_TRUST.tonumber,LLL_TRUST.rawget,LLL_TRUST.rawset,LLL_TRUST.rawequal,LLL_TRUST.pairs,LLL_TRUST.ipairs,LLL_TRUST.next,LLL_TRUST.select,LLL_TRUST.unpack,LLL_TRUST.loadstring,LLL_TRUST.loadfile,LLL_TRUST.dofile,LLL_TRUST.setfenv,LLL_TRUST.getfenv,LLL_TRUST.setmetatable,LLL_TRUST.getmetatable,LLL_TRUST.collectgarbage,LLL_TRUST.print,LLL_TRUST.string,LLL_TRUST.table,LLL_TRUST.math,LLL_TRUST.io,LLL_TRUST.os,LLL_TRUST.debug,LLL_TRUST.coroutine,LLL_TRUST.package,LLL_TRUST.require
local LLL_METADATA=(function()
-- Bounded data-only JSON; manifests are never executed as Lua.
local M = {}
function M.decode(text)
    assert(type(text) == "string" and #text <= 65536, "Manifest too large")
    local at = 1
    local parse
    local function space()
        local _, last = string.find(text, "^%s*", at)
        at = (last or at - 1) + 1
    end
    local function string_value()
        assert(string.sub(text, at, at) == '"')
        at = at + 1
        local out = {}
        while at <= #text do
            local ch = string.sub(text, at, at)
            at = at + 1
            if ch == '"' then
                return table.concat(out)
            end
            if ch == "\\" then
                ch = string.sub(text, at, at)
                at = at + 1
                local escape = {
                    ['"'] = '"',
                    ["\\"] = "\\",
                    ["/"] = "/",
                    b = "\b",
                    f = "\f",
                    n = "\n",
                    r = "\r",
                    t = "\t",
                }
                if ch == "u" then
                    local hex = string.sub(text, at, at + 3)
                    assert(string.match(hex, "^%x%x%x%x$"), "Invalid unicode escape")
                    at = at + 4
                    local n = tonumber(hex, 16)
                    assert(n < 0xd800 or n > 0xdfff, "Unsupported surrogate escape")
                    if n < 128 then
                        ch = string.char(n)
                    elseif n < 2048 then
                        ch = string.char(192 + math.floor(n / 64), 128 + n % 64)
                    else
                        ch = string.char(
                            224 + math.floor(n / 4096),
                            128 + math.floor(n / 64) % 64,
                            128 + n % 64
                        )
                    end
                else
                    ch = assert(escape[ch], "Invalid JSON escape")
                end
            else
                assert(string.byte(ch) >= 32, "Control in JSON string")
            end
            out[#out + 1] = ch
        end
        error("Unterminated JSON string")
    end
    function parse(depth)
        assert(depth < 12, "Manifest nesting too deep")
        space()
        local ch = string.sub(text, at, at)
        if ch == '"' then
            return string_value()
        end
        if ch == "{" or ch == "[" then
            local object = ch == "{"
            local closing = object and "}" or "]"
            at = at + 1
            space()
            local value = {}
            if string.sub(text, at, at) == closing then
                at = at + 1
                return value
            end
            while true do
                local key
                if object then
                    space()
                    key = string_value()
                    space()
                    assert(string.sub(text, at, at) == ":")
                    at = at + 1
                end
                local item = parse(depth + 1)
                if object then
                    value[key] = item
                else
                    value[#value + 1] = item
                end
                space()
                ch = string.sub(text, at, at)
                at = at + 1
                if ch == closing then
                    return value
                end
                assert(ch == ",", "Invalid JSON separator")
            end
        end
        for token, value in pairs({ ["true"] = true, ["false"] = false, ["null"] = M }) do
            if string.sub(text, at, at + #token - 1) == token then
                at = at + #token
                return value
            end
        end
        local token = string.match(text, "^%-?%d+%.?%d*[eE]?[%+%-]?%d*", at)
        assert(token and tonumber(token), "Invalid JSON value")
        at = at + #token
        return tonumber(token)
    end
    local value = parse(0)
    space()
    assert(at > #text, "Trailing JSON data")
    return value
end
local function label(value)
    if type(value) == "table" then
        value = value.name or value.Name
    end
    return type(value) == "string"
            and #value > 0
            and #value <= 512
            and not string.find(value, "[%c]")
            and value
        or nil
end
function M.fields(value)
    if type(value) ~= "table" then
        return {}
    end
    local logs={}
    if type(value.log_files)=="table" then for _,name in ipairs(value.log_files)do
        if type(name)=="string" and #logs<16 and name:match("^[%w_. -]+%.log$") then logs[#logs+1]=name end
    end end
    return { author=label(value.author or value.Author),name=label(value.name or value.Name),log_files=logs }
end
function M.files(id)
    if id~=nil then
        if type(id)=="string" and string.match(id,"^[%w_-]+$") then return {id..".json"} end
        return {}
    end
    return {"manifest.json","mod.json","metadata.json"}
end
function M.read(platform, dir, id)
    local files=M.files(id)
    local result={}
    for _, file in ipairs(files) do
        local text = platform.read(dir .. "/" .. file, 65536)
        if text then
            local ok, value = pcall(M.decode, text)
            if ok then
                local fields = M.fields(value)
                result.author=result.author or fields.author
                result.name=result.name or fields.name
                if not result.log_files or #result.log_files==0 then result.log_files=fields.log_files end
                if not result.path and (fields.author or fields.name) then result.path=dir.."/"..file end
                if result.author and result.name and result.log_files and #result.log_files>0 then return result end
            end
        end
    end
    return result
end
return M

end)()
local LLL_STEAM_SERVICE={pipe="lll_steam_05052a2fb04dbddc81b8070f45f2ae53",launcher=nil,release="R38-26251122-luajit.1"}
local LLL_STEAM_TRANSPORT=(function()
-- The LuaJIT boot runtime's in-process Steam service. Same byte protocol and same caller contract as transport.lua,
-- answered by native/steam_inproc.c inside the runtime (package.preload 'hd2.lll_host') instead of the external
-- service's pipes: no launcher, no pipe, no helper process. nativeinfo() gives ui/font the two nativeinfo calls it
-- uses, for this process only, so no nativeinfo DLL loads either.
local M={}
local ffi,host
local function connect()
    if host then return host end
    ffi=require('ffi')
    local module=require('hd2.lll_host')
    assert(type(module)=='table' and module.version==1 and type(module.exchange)=='userdata'
        and type(module.read_memory)=='userdata' and type(module.module_base)=='userdata','LLL in-process service unavailable')
    host={exchange=ffi.cast('uint32_t(*)(const char *,uint32_t,const char **)',module.exchange),
        read_memory=ffi.cast('int(*)(uint64_t,void *,uint32_t)',module.read_memory),
        module_base=ffi.cast('uint64_t(*)(const char *)',module.module_base),reply=ffi.new('const char *[1]')}
    return host
end
function M.nativeinfo()
    local native=connect()
    return {module_base=function(name)
        if type(name)~='string' or #name==0 or name:find('%z') then return nil end
        local base=tonumber(native.module_base(name))
        return base~=0 and base or nil
    end,read_memory=function(address,count)
        if type(address)~='number' or type(count)~='number' or count<1 or count>16777216 or count~=math.floor(count) then return nil end
        local buffer=ffi.new('uint8_t[?]',count)
        if native.read_memory(address,buffer,count)~=1 then return nil end
        return ffi.string(buffer,count)
    end}
end
return setmetatable(M,{__call=function(_,config)
    local self={}
    assert(type(config)=='table','LLL service configuration required')
    local native=connect()
    local failure,listener
    local function exchange(bytes)
        local count=native.exchange(bytes,#bytes,native.reply)
        assert(count>=8 and count<=67108864,'Filesystem service stopped')
        local reply=ffi.string(native.reply[0],count)
        assert(reply:sub(1,4)==bytes:sub(1,4),'Stale filesystem response')
        return reply
    end
    function self.exchange(bytes)
        -- Caller mistakes happen before the failure boundary and do not close
        -- a healthy connection. A refused request cannot be retried.
        assert(type(bytes)=='string'and #bytes>=12 and #bytes<=67108864,'Invalid filesystem request')
        local a,b,c,d=bytes:byte(9,12)
        assert(a+b*256+c*65536+d*16777216<=#bytes-12,'Invalid filesystem request path length')
        if bytes:sub(1,4)=='\0\0\0\0'or bytes:sub(5,8)=='\0\0\0\0'then
            assert(bytes==string.rep('\0',12),'Invalid filesystem startup request')
        end
        assert(not failure,failure)
        local ok,reply=pcall(exchange,bytes)
        if not ok then
            failure='Filesystem service unavailable: '..tostring(reply)
            if listener then pcall(listener,failure) end
            error(failure,2)
        end
        return reply
    end
    function self.failure()return failure end
    function self.on_failure(fn)
        assert(type(fn)=='function','Transport failure callback required')
        listener=fn
        if failure then pcall(listener,failure) end
    end
    function self.close()
        failure=failure or 'Filesystem transport closed'
    end
    return self
end})

end)()
local LLL_STEAM_BUILDS={exe_sha256="257fd7de21a04e8668e02e5c820edf3435176fbde3569765255cc52a5ea20f9d",game_sha256="61dcfcd201dacbf3545c97beb8a5a6186e9850d2670bf60b0e058320b477f6df"}
local LLL_STEAM_INPUT=(function()
-- Documented Stingray controller API; ids are resolved once, closed UI reads one key.
local M = {}
local names = {[8]='backspace',[9]='tab',[13]='enter',[16]='left shift',[17]='left ctrl',[18]='left alt',
    [20]='caps lock',[27]='esc',[32]='space',[33]='page up',[34]='page down',[35]='end',[36]='home',
    [37]='left',[38]='up',[39]='right',[40]='down',[45]='insert',[46]='delete',
    [160]='left shift',[161]='right shift',[162]='left ctrl',[163]='right ctrl',
    [164]='left alt',[165]='right alt',
    [186]='semicolon',[187]='equal',[188]='comma',[189]='minus',[190]='period',[191]='slash',
    [192]='backtick',[219]='open bracket',[220]='backslash',[221]='close bracket',[222]='quote'}
for code=48,57 do names[code]=string.char(code) end
for code=65,90 do names[code]=string.char(code+32) end
for code=112,135 do names[code]='f' .. (code-111) end
function M.new(sr,platform)
    local self, ids, cache = {}, {}, {}
    local mouse_names = {[1]='left',[2]='right',[4]='middle',[5]='extra_1',[6]='extra_2'}
    local mouse_bits={[1]=1,[2]=2,[4]=4,[5]=8,[6]=16}
    local visible,leased,pointer,wheel_taken=false,false,nil,false
    local external=platform and type(platform.pointer_snapshot)=='function'
    local keyboard_mask=platform and platform.keyboard_capture_mask
    local captured={}
    if external and type(keyboard_mask)=='string' and #keyboard_mask==32 then
        for code=0,255 do
            local at,power=math.floor(code/8)+1,2^(code%8)
            if math.floor(keyboard_mask:byte(at)/power)%2==1 then
                captured[code]={at=at,power=power}
            end
        end
    end
    local function snapshot()
        if not external or not visible then return end
        if not pointer then
            leased=true
            pointer=platform.pointer_snapshot()
        end
        return pointer
    end
    local function release_reader()
        if leased then
            assert(platform.release_pointer(),'Cannot release pointer reader')
            leased=false
        end
    end
    function self.visible(value)
        local changed=visible~=(value==true)
        visible=value==true
        if not visible then
            pointer=nil
            if changed then release_reader()end
        end
    end
    function self.release(prior_result)
        visible,pointer=false,nil
        if prior_result==true then leased=false
        elseif prior_result==nil then release_reader()end
        -- A failed prior attempt retains authority for explicit retry, without
        -- repeating the same backend release during this close transition.
    end
    local function resolve(code)
        if ids[code] ~= nil then return ids[code] end
        local device, name = mouse_names[code] and sr.Mouse or sr.Keyboard, mouse_names[code] or names[code]
        local ok, id = false, nil
        if name then ok,id=pcall(device.button_id,name) end
        ids[code]=ok and type(id)=='number' and {device=device,id=id} or false
        return ids[code]
    end
    for code=1,255 do resolve(code) end
    local cursor_id = sr.Mouse.axis_id('cursor')
    local wheel_id = sr.Mouse.axis_id('wheel')
    function self.frame()
        for code in pairs(cache) do cache[code]=nil end
        pointer,wheel_taken=nil,false
    end
    function self.down(code)
        if cache[code] ~= nil then return cache[code] end
        local keyboard=captured[code]
        if visible and keyboard then
            local value=snapshot()
            -- Masked keys never fall back to a frozen or revoked engine reader.
            -- ARMING is a retained lease with no input until held keys release.
            cache[code]=value and value.valid==true and value.keyboard_active==true
                and value.keyboard_state==2 and value.keyboard_mask==keyboard_mask
                and type(value.keyboard_keys)=='string' and #value.keyboard_keys==32
                and math.floor(value.keyboard_keys:byte(keyboard.at)/keyboard.power)%2==1 or false
            return cache[code]
        end
        if external and visible and mouse_bits[code] then
            local value=snapshot()
            cache[code]=value.valid and math.floor(value.buttons/mouse_bits[code])%2==1 or false
            return cache[code]
        end
        local binding=resolve(code)
        local value=binding and binding.device.button(binding.id)
        cache[code]=value==true or (type(value)=='number' and value>0.5) or false
        return cache[code]
    end
    function self.mouse()
        if external then
            local value=snapshot()
            if not value or not value.valid or value.width<=0 or value.height<=0 then return end
            local width,height=sr.Gui.resolution()
            return value.x*width/value.width,height-value.y*height/value.height
        end
        if cursor_id == nil then return end
        local value=sr.Mouse.axis(cursor_id)
        if value then return value.x,value.y end
    end
    function self.wheel()
        if external then
            if wheel_taken then return 0 end
            wheel_taken=true
            local value=snapshot()
            return value and value.valid and value.wheel or 0
        end
        if wheel_id == nil then return 0 end
        local value=sr.Mouse.axis(wheel_id)
        return value and value.y*120 or 0
    end
    return self
end
return M

end)()
local LLL_STEAM_INPUT_SERVICE=(function()
-- One helper connection, with exclusive cursor ownership for manager and mods.
local M={}
function M.new(platform,window,capture)
    local service,driver={version=1},{}
    local keyboard_mask=platform.keyboard_capture_mask
    local keyboard=type(platform.keyboard_prepare)=='function'and type(platform.keyboard_acquire)=='function'
        and type(platform.keyboard_snapshot)=='function'and type(platform.keyboard_release)=='function'
        and type(keyboard_mask)=='string'and #keyboard_mask==32
    local capabilities={menu=true,camera=type(platform.camera_snapshot)=='function',
        relative_mouse=type(platform.camera_snapshot)=='function',coordinates='client-top-left',
        keyboard=keyboard,keyboard_mask=keyboard and keyboard_mask or nil,
        keyboard_scope=keyboard and (platform.keyboard_scope or 'registered-keys') or nil}
    service.capabilities=setmetatable({},{__index=capabilities,__metatable=false,
        __newindex=function()error('Input capabilities are read-only',2)end})
    local lease,manager_reader,manager_busy=nil,false,function()return false end
    local mcm_frontend
    local sampled,sample_taken=false,false
    local manager_sample
    local manager_keyboard,manager_failed
    local sample={}
    local sample_keys={'x','y','width','height','buttons','wheel','dx','dy'}
    local invalid={valid=false,x=0,y=0,width=0,height=0,buttons=0,wheel=0,dx=0,dy=0}
    local function foreground()
        local ok,value=pcall(window.has_focus)
        return ok and value==true
    end
    local function valid_frontend(token)
        return token~=nil and mcm_frontend~=nil and mcm_frontend.token==token
            and rawget(_G,'DBFMCM')==mcm_frontend.provider
            and rawget(mcm_frontend.provider,'shared_input_service')==service
    end
    local function mcm_busy(frontend)
        if frontend and not valid_frontend(frontend) then return true end
        local provider=rawget(_G,'DBFMCM')
        if not provider then return false end
        if type(provider)~='table' then return true end
        if type(provider.input_status)=='function' then
            local ok,value=pcall(provider.input_status)
            if not ok or type(value)~='table' or value.pending_restore then return true end
            if frontend then
                if type(value.active)~='boolean' or type(value.pending_restore)~='boolean' then return true end
                if value.owner~=nil and value.owner~='DBF MCM' then return true end
                if value.active and value.owner~='DBF MCM' then return true end
            elseif value.owner or value.active then return true end
        elseif frontend then
            return true
        end
        if type(provider.is_open)~='function' then return true end
        local ok,value=pcall(provider.is_open)
        if frontend then return not ok or type(value)~='boolean' end
        return not ok or value~=false
    end
    local function manager_is_busy()
        local ok,value=pcall(manager_busy)
        return not ok or value==true
    end
    local function close_lease(reason)
        local current=lease
        if not current then return true end
        current.active=false
        current.reason=reason or current.reason or 'Released'
        sampled,sample_taken=false,false
        -- A request whose acknowledgement was lost may already own hotkeys.
        -- Keep its private handle and cursor lease until exact release ACK.
        if current.keyboard then
            local ok,value,why=pcall(platform.keyboard_release,current.keyboard)
            if not ok or value~=true then
                current.reason=ok and (why or 'Keyboard release refused') or tostring(value)
                return false,current.reason
            end
            current.keyboard=nil
        end
        local pointer_ok,pointer_why=true,nil
        if current.reader then
            local ok,value=pcall(platform.release_pointer)
            pointer_ok=ok and value==true
            if pointer_ok then current.reader=false
            else pointer_why=ok and 'Pointer release refused' or tostring(value) end
        end
        local restored,why=true,nil
        if current.capture then
            restored,why=capture.release(current.token)
            if restored then current.capture=false end
        end
        if pointer_ok and restored then lease=nil;return true end
        current.reason=pointer_why or why or 'Input restoration pending'
        return false,current.reason
    end
    function service.register_frontend(role,provider)
        if role~='mcm' or type(provider)~='table' or rawget(_G,'DBFMCM')~=provider
            or rawget(provider,'shared_input_service')~=service
            or type(provider.is_open)~='function' or type(provider.input_status)~='function' then
            return nil,'Published MCM frontend for this service required'
        end
        if mcm_frontend and (mcm_frontend.provider==provider or (lease and lease.frontend)) then
            return nil,'MCM frontend already registered or restoring'
        end
        local token={}
        mcm_frontend={token=token,provider=provider}
        return token
    end
    function service.unregister_frontend(token)
        if token==nil or not mcm_frontend or mcm_frontend.token~=token then
            return false,'MCM frontend registration not owned'
        end
        if lease and lease.frontend==token then return false,'Release MCM input before unregistering' end
        mcm_frontend=nil
        return true
    end
    function service.acquire(owner,mode,frontend,options)
        if type(owner)~='string' or owner=='' or #owner>128 or owner:find('%c') then
            return nil,'Owner name required (1-128 printable bytes)'
        end
        mode=mode or 'menu'
        if mode~='menu' and mode~='camera' then return nil,'Unsupported input mode' end
        if frontend~=nil and (not valid_frontend(frontend) or owner~='DBF MCM' or mode~='menu') then
            return nil,'MCM frontend registration not owned or mode unsupported'
        end
        if mode=='camera' and not capabilities.camera then return nil,'Relative camera input unavailable' end
        if options~=nil and (type(options)~='table'or options.keyboard~=nil and type(options.keyboard)~='boolean') then
            return nil,'Invalid input options'
        end
        local want_keyboard=options~=nil and options.keyboard==true
        if want_keyboard and not keyboard then return nil,'Keyboard capture unavailable' end
        if lease or manager_reader or manager_keyboard or manager_is_busy() or mcm_busy(frontend) then return nil,'Input lease already owned' end
        if not foreground() then return nil,'Game is not foreground' end
        local status=capture.status()
        if status.owner or status.pending_restore then return nil,'Cursor lease already owned or restoring' end
        local token,why=capture.acquire(owner)
        if not token then return nil,why end
        lease={token=token,owner=owner,mode=mode,frontend=frontend,active=false,capture=true,reader=false}
        local called,ok;called,ok,why=pcall(capture.activate,token,mode)
        if not called then why=tostring(ok);ok=false end
        if ok and want_keyboard then
            called,lease.keyboard,why=pcall(platform.keyboard_prepare)
            if not called then why=tostring(lease.keyboard);lease.keyboard=nil;ok=false
            elseif not lease.keyboard then ok=false
            else
                called,ok,why=pcall(platform.keyboard_acquire,lease.keyboard)
                if not called then why=tostring(ok);ok=false end
            end
        end
        if not ok then
            local restored=close_lease(why)
            return nil,why,not restored and token or nil
        end
        lease.active=true
        sampled,sample_taken=false,false
        return token
    end
    function service.owns(token)
        return token~=nil and lease~=nil and lease.token==token and lease.active
    end
    function service.release(token)
        if token==nil or not lease or lease.token~=token then return false,'Input lease not owned' end
        return close_lease('Released')
    end
    function service.set_mode(token,mode)
        if not service.owns(token) then return false,'Input lease inactive or not owned' end
        if mode~='menu'and mode~='camera' then return false,'Unsupported input mode' end
        if mode=='camera'and (not capabilities.camera or lease.frontend) then return false,'Camera mode unavailable for this lease' end
        if lease.mode==mode then return true end
        if not foreground() or mcm_busy(lease.frontend) then
            close_lease('Input ownership lost')
            return false,'Input ownership lost'
        end
        local called,ok,why=pcall(capture.set_mode,token,mode)
        if not called then why=tostring(ok);ok=false end
        if ok~=true then
            why=why or 'Cursor mode change refused'
            close_lease(why)
            return false,why
        end
        lease.mode=mode
        sampled,sample_taken=false,false
        return true
    end
    local function keyboard_sample(value)
        return type(value)=='table'and (value.keyboard_state==1 or value.keyboard_state==2)
            and value.keyboard_active==(value.keyboard_state==2)
            and type(value.keyboard_keys)=='string'and #value.keyboard_keys==32
            and type(value.keyboard_mask)=='string'and #value.keyboard_mask==32
    end
    local function copy_sample(value)
        sample.valid=value.valid==true
        for _,key in ipairs(sample_keys)do sample[key]=value[key] or 0 end
        sample.keyboard_active=value.keyboard_active
        sample.keyboard_state=value.keyboard_state
        sample.keyboard_generation=value.keyboard_generation
        sample.keyboard_keys=value.keyboard_keys
        sample.keyboard_mask=value.keyboard_mask
    end
    function service.snapshot(token)
        if not service.owns(token) then return nil,'Input lease inactive or not owned' end
        if not foreground() or mcm_busy(lease.frontend) then
            close_lease('Input ownership lost')
            return nil,'Input ownership lost'
        end
        if not sampled then
            local current=lease
            current.reader=true -- A failed request may still have started the reader.
            local ok,value
            if current.keyboard then ok,value=pcall(platform.keyboard_snapshot,current.keyboard,current.mode)
            else ok,value=pcall(current.mode=='camera' and platform.camera_snapshot or platform.pointer_snapshot) end
            local arming=current.keyboard and type(value)=='table'and value.keyboard_state==1
            if not ok or type(value)~='table' or value.valid~=true and not arming or current.keyboard and not keyboard_sample(value) then
                close_lease(ok and 'Pointer foreground unavailable' or tostring(value))
                return nil,ok and 'Pointer foreground unavailable' or tostring(value)
            end
            copy_sample(value)
            sampled=true
        end
        if sample_taken then sample.wheel,sample.dx,sample.dy=0,0,0 end
        sample_taken=true
        return sample
    end
    function service.status()
        return {owner=lease and lease.owner or nil,mode=lease and lease.mode or nil,
            frontend=lease and lease.frontend and 'mcm' or nil,
            active=lease~=nil and lease.active,pending_restore=lease~=nil and not lease.active,
            reason=lease and lease.reason or nil,keyboard=lease~=nil and lease.keyboard~=nil}
    end
    function driver.set_manager_busy(fn)manager_busy=assert(fn)end
    function driver.begin_frame()
        sampled,sample_taken=false,false
        manager_sample=nil
        if lease and lease.active and (not foreground() or mcm_busy(lease.frontend)) then close_lease('Input ownership lost') end
        if manager_keyboard and not manager_failed and not foreground() then driver.manager_release() end
    end
    function driver.manager_available()
        return lease==nil and not manager_failed
    end
    function driver.manager_failure()return manager_failed end
    function driver.manager_snapshot()
        if lease then return invalid end
        if not foreground() then
            if not manager_failed and (manager_keyboard or manager_reader) then driver.manager_release() end
            return invalid
        end
        if manager_sample then return manager_sample end
        if manager_failed then return invalid end
        if keyboard and platform.manager_engine_keyboard~=true and not manager_keyboard then
            local called,handle,why=pcall(platform.keyboard_prepare)
            if not called or not handle then
                manager_failed=called and (why or 'Keyboard preparation refused') or tostring(handle)
                return invalid
            end
            manager_keyboard=handle -- Store before the first native exchange.
            local ok;called,ok,why=pcall(platform.keyboard_acquire,handle)
            if not called or ok~=true then
                manager_failed=called and (why or 'Keyboard acquisition refused') or tostring(ok)
                return invalid
            end
        end
        manager_reader=true
        if manager_keyboard then
            local ok,value=pcall(platform.keyboard_snapshot,manager_keyboard,'menu')
            local arming=type(value)=='table'and value.keyboard_state==1
            if not ok or type(value)~='table'or value.valid~=true and not arming or not keyboard_sample(value) then
                manager_failed=ok and 'Keyboard foreground unavailable' or tostring(value)
                return invalid
            end
            manager_sample=value
        else manager_sample=platform.pointer_snapshot() end
        return manager_sample
    end
    function driver.manager_release()
        manager_sample=nil
        if lease then return true end -- Never release a shared owner's backend.
        local ok,why=true,nil
        if manager_keyboard then
            local called,value,problem=pcall(platform.keyboard_release,manager_keyboard)
            if not called or value~=true then
                manager_failed=called and (problem or 'Manager keyboard release refused') or tostring(value)
                return false,manager_failed
            end
            manager_keyboard=nil
        end
        if manager_reader then
            local called,value=pcall(platform.release_pointer)
            ok=called and value==true
            if ok then manager_reader=false else why=called and 'Manager pointer release refused' or tostring(value) end
        end
        if not lease then
            local restored,problem=capture.release()
            if not restored then ok,why=false,problem end
        end
        if ok then manager_failed=nil end
        return ok,why
    end
    function driver.close()
        local ok,why=close_lease('Loader shutting down')
        local manager_ok,manager_why=driver.manager_release()
        return ok and manager_ok,why or manager_why
    end
    driver.capture=capture
    return service,driver
end
return M

end)()
local LLL_STEAM_SCREENSHOT_SERVICE=(function()
-- One explicit asynchronous screenshot. This facade has no update/timer work.
local M={}
function M.new(platform)
    local directory=assert(platform.screenshot_directory):gsub('\\','/'):gsub('/+$','')
    local session=assert(platform.screenshot_session)
    assert(type(session)=='string'and session:match('^[a-z0-9_]+$')and #session<=96)
    local self={version=1,output_directory=directory}
    local values={async=true,game_window=true,format='png',color_space='sdr',max_jobs=1}
    self.capabilities=setmetatable({},{__index=values,__metatable=false,
        __newindex=function()error('Screenshot capabilities are read-only',2)end})
    local serial,issued,current,closing=0,nil,nil,false
    local states={pending=true,succeeded=true,failed=true,cancelled=true}
    local function text(value,limit)
        return type(value)=='string'and #value>0 and #value<=limit and not value:find('%c')
    end
    local function canonical(path)return path:gsub('\\','/'):lower()end
    local function output(path)
        if not text(path,32760)then return false end
        local normalized=path:gsub('\\','/')
        if normalized:sub(1,#directory+1):lower()~=directory:lower()..'/'then return false end
        local name=normalized:sub(#directory+2)
        if #name>128 or name:find('..',1,true)
            or not name:match('^[A-Za-z0-9_%-][A-Za-z0-9_. %-]*%.[Pp][Nn][Gg]$')then return false end
        local stem=name:match('^([^.]+)'):upper()
        if stem:match('[ .]$')then return false end
        return stem~='CON'and stem~='PRN'and stem~='AUX'and stem~='NUL'
            and not stem:match('^COM[0-9]$')and not stem:match('^LPT[0-9]$')
    end
    local function record()
        local r=current
        return {job_token=r.job_token,output_token=r.output_token,output_path=r.output_path,
            state=r.state,reason=r.reason,width=r.width,height=r.height,elapsed_ms=r.elapsed_ms,
            uncertain=r.uncertain==true,cancel_requested=r.cancel_requested==true}
    end
    local function owned(job,output_token)
        return current and current.job_token==job and current.output_token==output_token
    end
    local function clock()
        local ok,value=pcall(platform.now)
        if ok and type(value)=='number'and value==value and value>=0 and value<math.huge then return value end
    end
    local function uncertain(why)
        current.uncertain=true
        current.reason='Capture acknowledgement unavailable: '..tostring(why):sub(1,200)
        return record()
    end
    local function consume(reply)
        if type(reply)~='table'or not states[reply.state]or not text(reply.id,32)
            or #reply.id~=32 or not reply.id:match('^[0-9a-f]+$')
            or not text(reply.output_path,32760)or canonical(reply.output_path)~=canonical(current.output_path)
            or(current.id and current.id~=reply.id)then
            return uncertain('Invalid backend identity')
        end
        for _,key in ipairs({'error','width','height','elapsed_ms'})do
            local n=reply[key]
            if type(n)~='number'or n<0 or n>=4294967296 or n%1~=0 then
                return uncertain('Invalid backend metrics')
            end
        end
        if reply.state=='succeeded'and(reply.error~=0 or reply.width==0 or reply.height==0
            or reply.width>16384 or reply.height>16384 or reply.width*reply.height>67108864)then
            return uncertain('Invalid success dimensions')
        end
        current.id,current.state=reply.id,reply.state
        current.width,current.height,current.elapsed_ms=reply.width,reply.height,reply.elapsed_ms
        current.uncertain=false
        current.reason=reply.error~=0 and string.format('Screenshot error 0x%08x',reply.error)or nil
        return record()
    end
    function self.new_job_token()
        if closing then return nil,'Screenshot service is closing'end
        if current and current.state=='pending'then return nil,'Screenshot already active or unconfirmed'end
        if serial>=4294967295 then return nil,'Screenshot token counter exhausted'end
        serial=serial+1;issued='lll-shot:'..session..':'..string.format('%.0f',serial)
        return issued
    end
    function self.request(intent)
        if closing then return nil,'Screenshot service is closing'end
        if current and current.state=='pending'then return nil,'Screenshot already active or unconfirmed'end
        if type(intent)~='table'or intent.job_token~=issued or not issued
            or not text(intent.output_token,256)or not output(intent.output_path)then
            return nil,'Latest unused job token and safe output PNG path required'
        end
        local now=clock();if not now then return nil,'Application clock unavailable'end
        local pending={job_token=intent.job_token,output_token=intent.output_token,
            output_path=intent.output_path,state='pending',next_poll=now+.1}
        issued=nil
        local previous=current;current=pending
        local ok,reply,why=pcall(platform.screenshot_request,pending.output_path)
        if not ok then return uncertain(reply)end
        if reply==nil or reply==false then current=previous;return nil,why or 'Screenshot rejected'end
        return consume(reply)
    end
    function self.status(job,output_token)
        if not owned(job,output_token)then return nil,'Screenshot identity is stale or not owned'end
        if current.state~='pending'or not current.id then return record()end
        local now=clock();if not now then return uncertain('Application clock unavailable')end
        if now<current.next_poll then return record()end
        current.next_poll=now+.1
        local ok,reply,why=pcall(platform.screenshot_status,current.id)
        if not ok or not reply then return uncertain(ok and why or reply)end
        return consume(reply)
    end
    function self.cancel(job,output_token)
        if not owned(job,output_token)then return false,nil,'Screenshot identity is stale or not owned'end
        if current.state~='pending'then return true,record()end
        if not current.id then return false,record()end
        local reply
        if current.cancel_ack then
            reply=self.status(job,output_token)
        else
            local now=clock()
            if current.cancel_requested and now and now<current.next_poll then return false,record()end
            current.cancel_requested=true
            local ok,value,why=pcall(platform.screenshot_cancel,current.id)
            if now then current.next_poll=now+.1 end
            if not ok or not value then return false,uncertain(ok and why or value)end
            reply=consume(value)
            current.cancel_ack=not reply.uncertain
        end
        return reply.state~='pending',reply
    end
    local driver={}
    function driver.close()
        closing=true;issued=nil
        if not current or current.state~='pending'then return true end
        local done=self.cancel(current.job_token,current.output_token)
        return done,not done and 'Screenshot worker retirement pending'or nil
    end
    return self,driver
end
return M

end)()
local LLL_CFFI=(function()
-- Optional native module. Normal package.loadlib only; failures leave LLL usable.
local M={}
function M.open(config)
    if not config then return {available=false,reason='not configured'} end
    local path=config.path
    if type(path)~='string' or #path==0 or #path>32760 or path:find('%z') then
        return {available=false,reason='invalid cffi module path'}
    end
    if type(package)~='table' or type(package.loadlib)~='function' or type(package.loaded)~='table' then
        return {available=false,reason='package.loadlib unavailable'}
    end
    if package.loaded.cffi~=nil then return {available=false,reason='cffi already registered'} end
    local ok,entry,why=pcall(package.loadlib,path,'luaopen_hd2_cffi')
    if not ok then return {available=false,reason=tostring(entry)} end
    if type(entry)~='function' then return {available=false,reason=tostring(why or 'native loader refused cffi')} end
    local success,module=pcall(entry)
    if not success then return {available=false,reason=tostring(module)} end
    if type(module)~='table' then return {available=false,reason='native bootstrap did not return a validated module'} end
    for _,name in ipairs({'cdef','load','typeof','new','cast','tonumber'}) do
        if type(module[name])~='function' then return {available=false,reason='incomplete cffi module: '..name} end
    end
    package.loaded.cffi=module
    return {available=true,module_name='cffi',legacy_ffi_alias=false}
end
return M

end)().open({path="hd2-runtime:ffi"})
local LLL_RUNTIME=(function()
-- bingus_runtime.lua, version 1: the core of Bingus Shared Runtime.
-- Canonical copy: github.com/CowboyBingus/BingusSharedRuntime, runtime/bingus_runtime.lua.
--
-- Helldivers 2 runs the game and every Lua mod in one LuaJIT state, with one
-- global update chain. This file gives a mod the update guard every mod used
-- to write by hand, and the session table all runtime copies share. It uses no
-- FFI and no system function.
--
-- Loading: each runtime file is one chunk that returns a table and installs
-- nothing until the mod asks. A mod vendors byte-identical copies of the files
-- it needs and runs each once when it loads:
--   local runtime = <bingus_runtime.lua>              -- this file: shared(), guard()
--   local memory = <bingus_memory.lua>.new(runtime)   -- reads, page checks, module hashes, time()
--   <bingus_write.lua>.extend(memory)                 -- checked writes, added to memory
-- A mod that never touches memory vendors this file alone; one that only reads
-- vendors this file and bingus_memory.lua.
--
-- Copies of different versions can run in the same game. Their session state
-- lives in one global table, BingusRuntime = {hashes, statuses, versions,
-- hash_reads}, which every copy of every version shares.
--
-- runtime.shared([globals]) -> BingusRuntime, created or repaired.
-- runtime.guard(options) -> guard: the update and shutdown wrappers. The
-- previous update runs outside pcall, so its errors reach the game unchanged
-- (P1); the first failure survives shutdown as "stopped after: <reason>" (P2);
-- 8 errors stop the mod, counted per burst so rare transient errors never add
-- up (P3); a mod that can restore its state pauses after an error below it and
-- resumes when the updates below run cleanly again; every argument and return
-- value passes through; a status table per mod lands in BingusRuntime.statuses.
--
-- Per-frame cost of a guard: the mod's step under pcall, a few boolean tests
-- and stores and two integer counters around the previous update; no
-- allocation, closure or system call. Unmeasured in game.
local runtime = {VERSION = 1}

local type, pcall, error, tostring, rawget, rawset, ipairs = type, pcall, error, tostring, rawget, rawset, ipairs

-- Session state shared by every copy of every version ----------------------------

local SHARED = 'BingusRuntime'
local SHARED_TABLES = {'hashes', 'statuses', 'versions'}

-- Another copy, another version or another mod may have left the table
-- incomplete (even `BingusRuntime = {}`): missing or broken fields are filled in,
-- so one stray assignment cannot stop every mod on the runtime.
function runtime.shared(globals)
    globals = globals or _G
    local shared = rawget(globals, SHARED)
    if type(shared) ~= 'table' then
        shared = {}
        rawset(globals, SHARED, shared)
    end
    for _, field in ipairs(SHARED_TABLES) do
        if type(rawget(shared, field)) ~= 'table' then rawset(shared, field, {}) end
    end
    if type(rawget(shared, 'hash_reads')) ~= 'number' then rawset(shared, 'hash_reads', 0) end
    rawset(rawget(shared, 'versions'), runtime.VERSION, true)
    return shared
end

-- Update guard -----------------------------------------------------------------------

-- options:
--   name    key in BingusRuntime.statuses (required, one guard per name)
--   step    function(dt, ...) before the previous update, every frame while running
--   after   function() after the previous update returned, while running
--   stop    function(reason) once, when the guard stops or the game shuts down;
--           its errors are kept in status.stop_error, never raised
--   pause   function(reason), optional: an update below this mod raised; restore
--           the game state and reset the mod to a fresh start. With it the guard
--           pauses (no step, no after) and resumes once the updates below have
--           returned on `resume` frames in a row (default 60). Without it such an
--           error stops the guard. A pause that raises stops the guard.
--   log     function(line) for the guard's few lines (errors, pauses, resumes, stop)
--   errors  errors that stop the guard (default 8), counted separately for the
--           mod's own step and after and for the updates below it. A count starts
--           again after `clean` frames without such an error (default 3600, about a
--           minute at 60 FPS), so rare transient errors never add up to a stop.
--   env     the table holding update and shutdown (default _G)
-- guard.install() wraps env.update and env.shutdown and returns the guard.
-- guard.stop(reason) stops it from the mod (a refusal counts as the first failure).
-- guard.running() is true from install until a stop or shutdown.
-- guard.status: {name, version, state, installed, errors, lower_errors, pauses,
--   first_error, burst_error, first_failure, stop_error}; state is 'new', 'running',
--   'paused: <reason>', 'stopped: <reason>', then at shutdown 'stopped' or
--   'stopped after: <first failure>'.
function runtime.guard(options)
    local name = options.name
    if type(name) ~= 'string' or name == '' then error('guard name required', 0) end
    local shared = runtime.shared(options.env)
    if shared.statuses[name] and shared.statuses[name].installed then error('guard ' .. name .. ' already installed', 0) end
    local status = {name = name, version = runtime.VERSION, state = 'new', installed = false, errors = 0,
        lower_errors = 0, pauses = 0}
    shared.statuses[name] = status
    local step, after_step, stop_work, pause_work, log = options.step, options.after, options.stop, options.pause,
        options.log
    local limit, resume_after, clean_after = options.errors or 8, options.resume or 60, options.clean or 3600
    local previous_update, previous_shutdown
    local in_previous, stopped, paused, failed = false, false, false, false
    local clean_run, lower_run = 0, 0

    local function note(line)
        if log then pcall(log, line) end
    end

    local function halt(reason)
        if stopped then return end
        stopped, paused = true, false
        status.first_failure = status.first_failure or reason
        status.state = 'stopped: ' .. reason
        note(name .. ' stopped: ' .. reason)
        if stop_work then
            local ok, why = pcall(stop_work, reason)
            if not ok then status.stop_error = tostring(why) end
        end
    end

    -- The mod's own step or after raised: one log line per burst of errors.
    local function failed_step(problem)
        failed, clean_run = true, 0
        status.errors = status.errors + 1
        local text = tostring(problem)
        status.first_error = status.first_error or text
        if status.errors == 1 then
            status.burst_error = text
            note(name .. ' error: ' .. text)
        end
        if status.errors >= limit then halt('stopped after ' .. limit .. ' errors: ' .. status.burst_error) end
    end

    -- An update below this mod raised (seen on the next frame).
    local function failed_below()
        lower_run = 0
        status.lower_errors = status.lower_errors + 1
        if not pause_work then return halt('the previous update failed') end
        if status.lower_errors >= limit then
            return halt('stopped after ' .. limit .. ' failed updates below this mod')
        end
        if paused then return end
        paused = true
        status.pauses = status.pauses + 1
        status.state = 'paused: the previous update failed'
        note(name .. ' paused: the previous update failed')
        local ok, why = pcall(pause_work, 'the previous update failed')
        if not ok then halt('pause failed: ' .. tostring(why)) end
    end

    local function resume_when_clean()
        if paused and lower_run >= resume_after then
            paused = false
            status.state = 'running'
            note(name .. ' resumed after ' .. resume_after .. ' clean frames')
        end
    end

    -- Counts a frame without an own error, which also clears an old burst.
    local function count_clean()
        if failed then return end
        clean_run = clean_run + 1
        if clean_run == clean_after then status.errors = 0 end
    end

    local function finish(...)
        in_previous = false
        lower_run = lower_run + 1
        if lower_run == clean_after then status.lower_errors = 0 end
        if not stopped and not paused then
            if after_step then
                local ok, problem = pcall(after_step)
                if not ok then failed_step(problem) end
            end
            count_clean()
        end
        return ...
    end

    -- The previous update runs outside pcall: its errors (value and traceback)
    -- reach the game unchanged. One that raised leaves in_previous set, and the
    -- next frame pauses (or stops) this mod and keeps forwarding.
    local function update(...)
        failed = false
        if in_previous then
            in_previous = false
            if not stopped then failed_below() end
        end
        resume_when_clean()
        if step and not stopped and not paused then
            local ok, problem = pcall(step, ...)
            if not ok then failed_step(problem) end
        end
        in_previous = true
        return finish(previous_update(...))
    end

    local function shutdown(...)
        if in_previous then
            in_previous = false
            status.first_failure = status.first_failure or 'the previous update failed'
        end
        local failure = status.first_failure
        if not stopped then
            stopped = true
            if stop_work then
                local ok, why = pcall(stop_work, 'shutdown')
                if not ok then status.stop_error = tostring(why) end
            end
        end
        status.state = failure and ('stopped after: ' .. failure) or 'stopped'
        if previous_shutdown then return previous_shutdown(...) end
    end

    local guard = {status = status}

    function guard.install()
        local env = options.env or _G
        if status.installed then error('guard ' .. name .. ' already installed', 0) end
        previous_update = rawget(env, 'update')
        if type(previous_update) ~= 'function' then error('game update unavailable', 0) end
        previous_shutdown = rawget(env, 'shutdown')
        rawset(env, 'update', update)
        rawset(env, 'shutdown', shutdown)
        status.installed, status.state = true, 'running'
        return guard
    end

    function guard.stop(reason)
        halt(tostring(reason))
    end

    function guard.running()
        return status.installed and not stopped
    end

    return guard
end

return runtime

end)()
local LLL_CONFIG=(function()
-- Stable Lua-table settings encoding. Existing single-line tables remain readable.
local function serialize(value)
    local active = {}
    local function encode(item, depth)
        assert(depth < 16, "Settings nesting too deep")
        local kind = type(item)
        if kind == "string" then
            return string.format("%q", item)
        end
        if kind == "number" then
            assert(item == item and math.abs(item) < math.huge, "Non-finite settings number")
            return string.format("%.17g", item)
        end
        if kind == "boolean" then
            return item and "true" or "false"
        end
        assert(kind == "table", "Unsupported settings value")
        assert(not active[item], "Cyclic settings table")
        active[item] = true
        local keys = {}
        for key in pairs(item) do
            assert(type(key) == "string" or type(key) == "number", "Unsupported settings key")
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then
                return type(a) == "number"
            end
            return a < b
        end)
        local lines = {}
        for _, key in ipairs(keys) do
            lines[#lines + 1] = string.rep("    ", depth + 1)
                .. "["
                .. encode(key, depth + 1)
                .. "] = "
                .. encode(item[key], depth + 1)
                .. ","
        end
        active[item] = nil
        if #lines == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep("    ", depth) .. "}"
    end
    return encode(value, 0)
end
return { serialize = serialize }

end)()
local LLL_CLEANUP_QUEUE=(function()
-- Host retains retired callbacks until their asynchronous cleanup completes.
-- This queue does not install an update hook or mutate loader registrations.
return function()
    local self = {}
    local pending = {}
    function self.add(owner, poll)
        assert(owner ~= nil and type(poll) == "function")
        if pending[owner] then
            return false, "Cleanup owner already registered"
        end
        pending[owner] = poll
        return true
    end
    function self.contains(owner)
        return pending[owner] ~= nil
    end
    function self.frame(dt)
        local errors = {}
        for owner, poll in pairs(pending) do
            local ok, done, why = pcall(poll, dt)
            if ok and done == true then
                pending[owner] = nil
            elseif not ok then
                errors[#errors + 1] = { owner = owner, error = done }
            elseif done == nil then
                errors[#errors + 1] =
                    { owner = owner, error = why or "Cleanup completion was not explicit" }
            end
        end
        return errors
    end
    return self
end

end)()
local LLL_AFTER_STARTUP=(function()
-- One-shot callbacks after initial module startup, with bounded reentrant registration.
return function(status,report,record,health)
    local queue,accepted,next_index,ready,running,closed={},0,1,false,false,false
    local registering,current,refused
    local self={}
    local function drain()
        if running or closed then return end
        running=true
        while next_index<=#queue do
            local item=queue[next_index];queue[next_index]=false;next_index=next_index+1
            if not item.owner or (status(item.owner)=='loaded' and (not item.record or record(item.owner)==item.record)) then
                current=item.owner
                report("After startup","running "..(item.owner or "anonymous callback"))
                local mark
                if health then local ok,value=pcall(health.before);if ok then mark=value end end
                local ok,why=pcall(item.fn)
                if health and mark then pcall(health.after,item.owner or "after_startup",mark,"after_startup") end
                current=nil
                report("After startup","completed "..(item.owner or "anonymous callback"))
                if not ok then report(item.owner or 'after_startup','Callback failed: '..tostring(why)) end
            else report(item.owner,'After-startup callback skipped: module not loaded or ownership changed') end
        end
        running=false
    end
    function self.register(fn)
        if closed then return false,'Loader is shutting down' end
        if type(fn)~='function' then return false,'after_startup needs a function' end
        if accepted>=256 then if not refused then refused=true;report('After startup','callback limit (256) reached; later registrations refused')end;return false,'after_startup callback limit (256) reached' end
        accepted=accepted+1
        local owner=current or registering
        queue[#queue+1]={fn=fn,owner=owner,record=owner and record(owner)}
        if ready and not registering then drain() end
        return true
    end
    function self.begin(name)registering=name end
    function self.ending()registering=nil;if ready then drain() end end
    function self.finish()ready=true;drain() end
    function self.close()closed=true;queue={} end
    return self
end

end)()
local LLL_CAPABILITIES=(function()
-- Read-only feature declaration; session success is reported by the corresponding service.
return function(features)
    local values={api=1,implementation='Live Lua Loader',revision='R31-bsl-v20'}
    for key,value in pairs(features)do values[key]=value end
    return setmetatable({},{__index=values,__metatable=false,__newindex=function()error('Loader capabilities are read-only',2)end})
end

end)()
local LLL_HEALTH=(function()
-- Loader health report, embedded by build.py.
--
-- The loader log is what a player sends with a crash or slowdown report. Besides
-- each module's status it records the game build, how the previous session's log
-- ended, the newest crash dump the game wrote before this start (time, exception
-- code and faulting module offset), and what each module changed in the Lua state
-- every mod shares: globals, library functions, metatables, garbage collector
-- settings and the JIT. Dump file names contain the computer name, so the report
-- never includes them, and module paths are cut to file names.
--
-- Cost: nothing per frame; the report adds no update, render or shutdown hook.
-- Everything runs once while the game starts: one read of the previous log, one
-- listing of the game's dump folder, a few small reads from the newest dump, and
-- per installed module two walks over the shared tables. None of it is compiled
-- (jit.off below), so the report adds no machine code to the JIT code cache every
-- mod shares; tests/test_health.lua checks this in the game's lua51.dll. Startup
-- time unmeasured in game.
local health = {}

-- Captured when the loader starts, before any mod could replace them.
local next, type, rawget, rawequal, pcall, ipairs, tostring = next, type, rawget, rawequal, pcall, ipairs, tostring
local getmetatable, collectgarbage, floor, min = getmetatable, collectgarbage, math.floor, math.min
local sort, concat, format, char, error = table.sort, table.concat, string.format, string.char, error

-- Compiled, the report's functions would hold machine code that never runs
-- again, so the JIT is turned off for the function running this file and every
-- function defined in it, and for nothing else. This file therefore always runs
-- as a function of its own (dofile, or the wrapper build.py puts around it).
-- Under pcall, debug.getinfo level 2 is that function. Both calls are protected:
-- without the debug library, or in a LuaJIT built without the JIT compiler, the
-- report only stays compilable.
if type(debug) == 'table' and type(jit) == 'table' then
    local found, info = pcall(debug.getinfo, 2, 'f')
    if found and type(info) == 'table' then pcall(jit.off, info.func, true) end
end

-- Like assert, without the source position LuaJIT's assert adds to the message.
local function ensure(condition, message)
    if not condition then error(message, 0) end
    return condition
end

-- Library tables compared one level deep, besides the globals themselves.
health.LIBRARIES = {'string', 'table', 'math', 'os', 'io', 'coroutine', 'debug', 'package', 'bit', 'jit'}
health.SHOWN = 6      -- names listed per kind of change; the rest are only counted
health.KEPT = 64      -- names kept per kind of change, so a mod adding thousands costs little
health.LOG_BYTES = 65536
health.DUMP_STREAMS = 256
health.DUMP_MODULES = 4096
health.FOLDER_ENTRIES = 100000

function health.hex(value)
    if type(value) ~= 'number' then return 'unknown' end
    return format('%08X', value)
end

local function u32(bytes, offset)
    local a, b, c, d = string.byte(bytes, offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

-- Shared state ---------------------------------------------------------------

local function name_of(prefix, key)
    if type(key) == 'string' then return prefix .. key end
    return prefix .. '[' .. type(key) .. ']'
end

local function note(list, name)
    list.total = list.total + 1
    if #list < health.KEPT then list[#list + 1] = name end
end

-- Nil checks use rawequal: comparing a cdata value that has an __eq metamethod
-- (ffi.metatype) with nil runs that metamethod, which is a mod's own code.
local function copy(source)
    local seen, key, value = {}, next(source)
    while not rawequal(key, nil) do
        seen[key] = value
        key, value = next(source, key)
    end
    return seen
end

-- Identity, never a metamethod; NaN counts as unchanged.
local function same(a, b)
    if rawequal(a, b) then return true end
    return type(a) == 'number' and type(b) == 'number' and a ~= a and b ~= b
end

-- Notes what changed in one shared table since its baseline, then advances the
-- baseline so the next module is charged only with its own changes.
local function compare(current, seen, prefix, report_added, found)
    local key, value = next(current)
    while not rawequal(key, nil) do
        local before = seen[key]
        if rawequal(before, nil) then
            if report_added then note(found.added, name_of(prefix, key)) end
            seen[key] = value
        elseif not same(before, value) then
            note(found.replaced, name_of(prefix, key))
            seen[key] = value
        end
        key, value = next(current, key)
    end
    key = next(seen)
    while not rawequal(key, nil) do
        local following = next(seen, key)
        if rawequal(rawget(current, key), nil) then
            note(found.removed, name_of(prefix, key))
            seen[key] = nil
        end
        key = following
    end
end

-- collectgarbage cannot read a setting without writing it: write any value and
-- restore the old one at once. Nothing allocates in between, so no collection
-- step can see the temporary value.
local function gc_setting(collect, option)
    local ok, value = pcall(collect, option, 200)
    if not ok or type(value) ~= 'number' then return nil end
    pcall(collect, option, value)
    return value
end

local function jit_state(library)
    if type(library) ~= 'table' or type(library.status) ~= 'function' then return nil end
    local result = {pcall(library.status)}
    if not result[1] then return nil end
    local flags = {}
    for index = 3, #result do
        if type(result[index]) == 'string' then flags[result[index]] = true end
    end
    return {on = result[2] == true, flags = flags}
end

local function jit_changes(before, after, settings)
    if not before or not after then return end
    if before.on ~= after.on then settings[#settings + 1] = after.on and 'JIT turned on' or 'JIT turned off' end
    local changed = {}
    for flag in next, before.flags do
        if not after.flags[flag] then changed[#changed + 1] = '-' .. flag end
    end
    for flag in next, after.flags do
        if not before.flags[flag] then changed[#changed + 1] = '+' .. flag end
    end
    if #changed > 0 then
        sort(changed)
        settings[#settings + 1] = 'JIT options ' .. concat(changed, ' ')
    end
end

local function setting_change(settings, label, before, after)
    if before ~= nil and after ~= nil and before ~= after then
        settings[#settings + 1] = label .. ' ' .. tostring(before) .. ' -> ' .. tostring(after)
    end
end

-- Collector and JIT settings that changed between two settings() snapshots.
local function settings_changes(settings, before, now)
    setting_change(settings, 'GC pause', before.pause, now.pause)
    setting_change(settings, 'GC step multiplier', before.stepmul, now.stepmul)
    jit_changes(before.jit, now.jit, settings)
    if now.flushes and before.flushes and now.flushes > before.flushes then
        settings[#settings + 1] = 'JIT cache flushed ' .. (now.flushes - before.flushes) .. 'x'
    end
    if before.watching == true and now.watching == false then
        settings[#settings + 1] = "replaced the loader's JIT trace watcher"
    end
end

-- The list a whole shared table goes in when a module swapped it out.
local function swap_kind(found, before, current)
    if rawequal(before, nil) then return found.added end
    if rawequal(current, nil) then return found.removed end
    return found.replaced
end

-- Notes what changed in one scope (a shared table) since the previous module.
local function scope_changes(item, found)
    local current = item.resolve()
    if rawequal(current, item.value) then
        if item.seen then compare(current, item.seen, item.prefix, item.report_added, found) end
        return
    end
    if item.identity then note(swap_kind(found, item.value, current), item.identity) end
    item.value, item.seen = current, type(current) == 'table' and copy(current) or nil
end

-- globals: the table every mod shares. hooks: collect (collectgarbage), jit (the
-- jit library), clock (seconds), flushes() (the loader's JIT flush count) and
-- watching() (whether the loader's JIT watcher is still attached); all optional.
function health.observer(globals, hooks)
    hooks = hooks or {}
    local collect = hooks.collect or collectgarbage
    local scopes = {}
    local function scope(prefix, resolve, identity, report_added)
        local value = resolve()
        scopes[#scopes + 1] = {prefix = prefix, resolve = resolve, identity = identity,
            report_added = report_added, value = value, seen = type(value) == 'table' and copy(value) or nil}
    end
    scope('', function() return globals end, nil, true)
    for _, name in ipairs(health.LIBRARIES) do
        scope(name .. '.', function() return rawget(globals, name) end, nil, true)
    end
    -- Every require adds an entry here, so only replaced or removed entries count.
    scope('package.loaded.', function()
        local package = rawget(globals, 'package')
        if type(package) == 'table' then return rawget(package, 'loaded') end
    end, 'package.loaded', false)
    scope('string metatable.', function() return getmetatable('') end, 'string metatable', true)
    scope('_G metatable.', function() return getmetatable(globals) end, '_G metatable', true)

    local function settings()
        local current = {pause = gc_setting(collect, 'setpause'), stepmul = gc_setting(collect, 'setstepmul'),
            jit = jit_state(hooks.jit)}
        if hooks.flushes then current.flushes = hooks.flushes() end
        if hooks.watching then current.watching = hooks.watching() end
        return current
    end
    local baseline = settings()
    local observer = {initial = {heap_kb = floor(collect('count') + 0.5), pause = baseline.pause,
        stepmul = baseline.stepmul, jit_on = baseline.jit and baseline.jit.on}}

    -- Just before a module loads.
    function observer.mark()
        -- Live reloads may occur long after startup: refresh the before-load baseline.
        for _,item in ipairs(scopes)do item.value=item.resolve();item.seen=type(item.value)=="table" and copy(item.value) or nil end
        baseline=settings()
        local mark = {heap = collect('count')}
        if hooks.clock then mark.clock = hooks.clock() end
        return mark
    end

    -- Right after it loaded (or failed): what it changed.
    function observer.changes(mark)
        local heap = collect('count')
        local stop = hooks.clock and hooks.clock()
        local found = {heap_kb = floor(heap - mark.heap + 0.5), settings = {},
            added = {total = 0}, replaced = {total = 0}, removed = {total = 0}}
        if stop and mark.clock then found.ms = floor((stop - mark.clock) * 1000 + 0.5) end
        for _, item in ipairs(scopes) do scope_changes(item, found) end
        local now = settings()
        settings_changes(found.settings, baseline, now)
        baseline = now
        return found
    end
    return observer
end

function health.describe_start(initial)
    local parts = {'heap ' .. initial.heap_kb .. ' KB'}
    if initial.pause then parts[#parts + 1] = 'GC pause ' .. initial.pause end
    if initial.stepmul then parts[#parts + 1] = 'GC step multiplier ' .. initial.stepmul end
    if initial.jit_on ~= nil then parts[#parts + 1] = initial.jit_on and 'JIT on' or 'JIT off' end
    return concat(parts, ', ')
end

local function listed(label, list)
    if list.total == 0 then return nil end
    sort(list)
    local shown = {}
    for index = 1, min(#list, health.SHOWN) do shown[index] = list[index] end
    local text = label .. ' ' .. concat(shown, ', ')
    if list.total > #shown then text = text .. ' (+' .. (list.total - #shown) .. ' more)' end
    return text
end

-- One line: heap change and load time, then changed settings and names.
function health.describe(found)
    local first = 'heap ' .. (found.heap_kb >= 0 and '+' or '') .. found.heap_kb .. ' KB'
    if found.ms then first = first .. ', ' .. found.ms .. ' ms' end
    local parts = {first}
    for _, text in ipairs(found.settings) do parts[#parts + 1] = text end
    for _, kind in ipairs({'added', 'replaced', 'removed'}) do
        local text = listed(kind, found[kind])
        if text then parts[#parts + 1] = text end
    end
    return concat(parts, '; ')
end

-- Game build -----------------------------------------------------------------

-- The PE timestamp of a loaded module (nil for the executable), which
-- identifies the game build. Reads the module's own mapped header.
function health.image_stamp(ffi, kernel, name)
    local base = kernel.GetModuleHandleA(name)
    if base == nil then return nil end
    local bytes = ffi.cast('const uint8_t *', base)
    local header = ffi.cast('const int32_t *', bytes + 0x3C)[0]
    ensure(header >= 64 and header <= 4096, 'unexpected PE header offset')
    ensure(ffi.cast('const uint32_t *', bytes + header)[0] == 0x4550, 'not a PE image')
    return tonumber(ffi.cast('const uint32_t *', bytes + header + 8)[0])
end

-- Previous session -------------------------------------------------------------

-- How the previous session's log ended. The loader writes "Startup finished"
-- last; a log without it ended during startup, and the module it was then
-- loading is the one marked "loading". A log that still reads "After startup:
-- running" ended while the after_startup callbacks ran.
function health.previous_session(text)
    if type(text) ~= 'string' or text == '' then return 'no log' end
    local version = string.match(text, '^Live Lua Loader ([^\r\n]+)') or 'unknown loader'
    local started = string.match(text, '\nStarted: ([^\r\n]+)')
    if not started then return version .. ' log without session details' end
    local result = 'started ' .. started .. ' (' .. version .. ')'
    local finished = string.match(text, '\n(Startup finished[^\r\n]*)')
    if finished then
        result = result .. '; ' .. string.lower(string.sub(finished,1,1)) .. string.sub(finished, 2)
        local callback_state
        for line in string.gmatch(text,"[^\r\n]+")do callback_state=string.match(line,"^After startup: (.+)$") or callback_state end
        if callback_state and string.match(callback_state,"^running ") then
            return result .. '; its log ended while after_startup callbacks ran'
        end
        return result
    end
    local loading
    for line in string.gmatch(text, '[^\r\n]+') do
        loading = string.match(line, '^([^:]+): loading$') or loading
    end
    if loading then return result .. '; its log ended while loading ' .. loading end
    return result .. '; its log ended during startup'
end

-- Crash dumps ------------------------------------------------------------------

-- FILETIME (100 ns steps since 1601) to seconds since 1970.
function health.filetime(high, low)
    return floor((high * 4294967296 + low) / 10000000 - 11644473600)
end

-- 'dump' for a crash dump, 'gpu' for a GPU crash report, nil for anything else.
local function entry_kind(name)
    local lower = string.lower(name)
    if string.match(lower, '%.dmp$') then return 'dump' end
    if string.match(lower, '^gpu_dump') then return 'gpu' end
    return nil
end

-- Whether last write time (high, low) is later than the newest entry's.
local function later(newest, high, low)
    if not newest or high > newest.high then return true end
    return high == newest.high and low > newest.low
end

-- Counts one listed entry; words reads data (WIN32_FIND_DATAA) as uint32s.
-- Directories (attribute 0x10) are skipped.
local function folder_entry(ffi, data, words, found)
    if words[0] % 32 >= 16 then return end
    local name = string.match(ffi.string(data + 44, 260),'^[^%z]*')
    local kind = entry_kind(name)
    if not kind then return end
    local low, high = words[5], words[6]
    if kind == 'dump' then found.dumps = found.dumps + 1 end
    if later(found[kind], high, low) then found[kind] = {name = name, high = high, low = low} end
end

-- The newest crash dump and GPU crash report by last write time, and the dump
-- count. WIN32_FIND_DATAA: attributes at 0, last write time at 20, name at 44.
function health.dump_folder(ffi, kernel, folder)
    local data = ffi.new('uint8_t[320]')
    local handle = kernel.FindFirstFileA(folder .. '/*', data)
    local found = {dumps = 0}
    if handle == ffi.cast('void *', -1) then
        local code = kernel.GetLastError()
        ensure(code == 2 or code == 3 or code == 18, 'dump folder unreadable (error ' .. tostring(code) .. ')')
        return found
    end
    local ok, reason = pcall(function()
        local words = ffi.cast('const uint32_t *', data)
        for _ = 1, health.FOLDER_ENTRIES do
            folder_entry(ffi, data, words, found)
            if kernel.FindNextFileA(handle, data) == 0 then
                ensure(kernel.GetLastError() == 18, 'dump folder listing interrupted')
                return
            end
        end
    end)
    local closed = kernel.FindClose(handle)
    ensure(ok, reason)
    ensure(closed ~= 0, 'dump folder listing close failed')
    return found
end

local function module_name(at, rva)
    local length = u32(at(rva, 4), 0)
    ensure(length <= 2048 and length % 2 == 0, 'unexpected module name')
    local raw, chars = at(rva + 4, length), {}
    for index = 1, length - 1, 2 do
        local low, high = string.byte(raw, index, index + 1)
        chars[#chars + 1] = (high == 0 and low >= 32 and low < 127) and char(low) or '?'
    end
    return (string.match(concat(chars),'[^\\/]*$'))
end

-- Where the first exception stream (6) and module list stream (4) start, from
-- the stream directory (12 bytes per entry: kind at 0, offset at 8).
local function stream_offsets(entries, count)
    local exception, modules
    for index = 0, count - 1 do
        local kind, rva = u32(entries, index * 12), u32(entries, index * 12 + 8)
        if kind == 6 and not exception then exception = rva end
        if kind == 4 and not modules then modules = rva end
    end
    return exception, modules
end

-- Adds the module holding result.address and the executable's stamp. Each
-- MINIDUMP_MODULE is 108 bytes: base at 0, size at 8, stamp at 16, name at 20.
local function add_modules(at, modules, result)
    local total = u32(at(modules, 4), 0)
    ensure(total <= health.DUMP_MODULES, 'unexpected module count')
    local list = at(modules + 4, total * 108)
    for index = 0, total - 1 do
        local entry = index * 108
        local base = u32(list, entry) + u32(list, entry + 4) * 4294967296
        if result.address >= base and result.address - base < u32(list, entry + 8) then
            result.module, result.offset = module_name(at, u32(list, entry + 20)), result.address - base
            result.stamp = u32(list, entry + 16)
            break
        end
    end
    -- The executable is listed first; its stamp names the build that crashed.
    if total > 0 and string.lower(module_name(at,u32(list,20))) == 'helldivers2.exe' then
        result.game_stamp = u32(list, 16)
    end
end

-- The exception record of a minidump (stream 6) and the module it hit (stream
-- 4): {code, address, module, offset, stamp, game_stamp}, or {} without one.
function health.read_dump(file)
    local function at(offset, count)
        ensure(file:seek('set', offset) == offset, 'dump seek failed')
        if count == 0 then return '' end
        local bytes = file:read(count)
        ensure(bytes and #bytes == count, 'truncated dump')
        return bytes
    end
    local header = at(0, 32)
    ensure(u32(header, 0) == 0x504D444D, 'not a minidump')
    local count, directory = u32(header, 8), u32(header, 12)
    ensure(count > 0 and count <= health.DUMP_STREAMS, 'unexpected stream count')
    local exception, modules = stream_offsets(at(directory, count * 12), count)
    if not exception then return {} end
    local record = at(exception, 32)
    local result = {code = u32(record, 8), address = u32(record, 24) + u32(record, 28) * 4294967296}
    if modules then add_modules(at, modules, result) end
    return result
end

-- What read_dump found, as the rest of the crash dump line.
local function exception_text(dump)
    if not dump.code then return ', no exception record' end
    local text = ', exception ' .. format('0x%08X', dump.code) .. ' at '
    if dump.module then
        text = text .. dump.module .. format('+0x%X', dump.offset) .. ' (module stamp ' .. health.hex(dump.stamp) .. ')'
    else
        text = text .. format('0x%X', dump.address) .. ' (outside every module)'
    end
    if dump.game_stamp then text = text .. ', executable stamp ' .. health.hex(dump.game_stamp) end
    return text
end

-- Opens, reads and closes one dump. The path is never part of the result: dump
-- file names contain the computer name.
local function dump_text(open, path)
    local file = open(path, 'rb')
    if not file then return ', unreadable (cannot open)' end
    local ok, dump = pcall(health.read_dump, file)
    pcall(file.close, file)
    if not ok then return ', unreadable (' .. tostring(dump) .. ')' end
    return exception_text(dump)
end

-- Report lines for the dump folder. open: io.open; date(seconds): local time text.
function health.crashes(ffi, kernel, folder, open, date)
    local found = health.dump_folder(ffi, kernel, folder)
    local lines = {'Newest crash dump: none'}
    if found.dump then
        local when = date(health.filetime(found.dump.high, found.dump.low))
        local details = dump_text(open, folder .. '/' .. found.dump.name)
        local total = found.dumps .. (found.dumps == 1 and ' dump' or ' dumps') .. ' in total'
        lines[1] = 'Newest crash dump: ' .. when .. details .. '; ' .. total
    end
    if found.gpu then
        lines[#lines + 1] = 'Newest GPU crash report: ' .. date(health.filetime(found.gpu.high, found.gpu.low))
    end
    return lines
end

return health

end)()
local LLL_MANAGER=(function()
-- Original coordinator. Dependencies are injected for isolated validation.
local queue_factory = LLL_CLEANUP_QUEUE or dofile("src/cleanup_queue.lua")
return function(host, entries)
    assert(not rawget(_G, "CowboyBingusModLoader"), "Another Shared Loader is active")
    assert(not rawget(_G, "LiveLuaLoader"), "Live Lua Loader is already active")
    local loader = {
        api = 1,
        version = 1,
        modules = {},
        records = {},
        errors = {},
        pending_cleanup = {},
        origins = {},
    }
    local cleanup_queue = queue_factory()
    local compat =
        { api = 1, version = 18, modules = loader.modules, implementation = "Live Lua Loader" }
    compat.open_log = host.open_log
    compat.log_directory = host.log_directory
    loader.log_directory = host.log_directory
    loader.compatibility = compat
    loader.input_service=host.input_service
    compat.input_service=host.input_service
    loader.capture_service=host.capture_service
    compat.capture_service=host.capture_service
    loader.build=host.build
    compat.build=host.build
    local function allowed()
        if not host.build_allowed then return true end
        local ok,value=pcall(host.build_allowed)
        return ok and value==true
    end
    local function status(name, value)
        if loader.modules[name] == value then
            return
        end
        loader.modules[name] = value
        pcall(host.report, name, value)
        if loader.changed then
            pcall(loader.changed)
        end
    end
    local callbacks=(LLL_AFTER_STARTUP or dofile("src/after_startup.lua"))(function(name)return loader.modules[name]end,
        function(name,message)pcall(host.report,name,message)end,function(name)return loader.records[name]end,host.health)
    loader.after_startup=function(fn)
        if not allowed() then return false,'Unsupported game build' end
        return callbacks.register(fn)
    end
    compat.after_startup=loader.after_startup
    loader.capabilities=(LLL_CAPABILITIES or dofile("src/capabilities.lua"))({logs=type(host.open_log)=="function",
        discovery=host.discovery_supported==true,after_startup=true,health=host.health~=nil,jit_budget=host.jit_budget~=nil,
        build_gate=type(host.build_allowed)=='function',
        live_loading=true,deferred_cleanup=true,modular_projects=host.modular_projects==true,console_commands=host.console_commands==true,protected_runtime=host.protected_runtime==true,
        diagnostics=host.diagnostics~=nil,author_groups=true,resizable_manager=true,shared_input=host.input_service~=nil,
        game_screenshots=host.capture_service~=nil,
        revision=host.revision or 'R31-bsl-v20',runtime=host.runtime or 'LuaJIT',native_ffi=host.native_ffi~=false})
    compat.capabilities=loader.capabilities
    compat.discovery=host.discovery_state
    compat.revision="LLL-" .. (host.revision or 'R31-bsl-v20')
    loader.diagnostics=host.diagnostics
    loader.health=host.health and host.health.public
    compat.health=loader.health
    compat.jit=host.jit_budget
    local function lifecycle_call(fn,...)
        if host.jit_budget and host.jit_budget.pause then host.jit_budget.pause() end
        local function pack(...)return {n=select("#",...),...}end
        local result=pack(pcall(fn,...))
        if host.jit_budget and host.jit_budget.resume then host.jit_budget.resume() end
        return unpack(result,1,result.n)
    end
    -- Ownership stays with the old record until explicit async acknowledgement.
    local function cleanup(name, record, final_state, completed)
        if loader.pending_cleanup[name] then
            return false, "pending"
        end
        local function finish()
            if loader.records[name] ~= record then
                return false, "Lifecycle ownership changed"
            end
            loader.records[name] = nil
            loader.pending_cleanup[name] = nil
            status(name, final_state)
            if completed then
                return completed()
            end
            return true
        end
        local ok, done, why = true, nil, nil
        if record.on_disable then
            ok, done, why = lifecycle_call(record.on_disable)
        end
        if loader.records[name] ~= record then
            return false, "Lifecycle ownership changed"
        end
        if ok and done ~= false then
            return finish()
        end
        local problem = ok and (why or "Cleanup returned false") or done
        if type(record.on_cleanup_poll) == "function" then
            local job = { name = name, record = record, final_state = final_state }
            loader.pending_cleanup[name] = job
            cleanup_queue.add(job, function(dt)
                if loader.records[name] ~= record or loader.pending_cleanup[name] ~= job then
                    if loader.pending_cleanup[name] == job then
                        loader.pending_cleanup[name] = nil
                    end
                    return true
                end
                local ready, reason = record.on_cleanup_poll(dt)
                if ready == true then
                    finish()
                    return true
                end
                return ready, reason
            end)
            if ok then
                status(name, "cleanup pending")
            else
                status(name, "cleanup failed: " .. tostring(problem))
            end
            return false, "pending"
        end
        status(name, "cleanup failed: " .. tostring(problem))
        return false, problem
    end
    local function load(name)
        if not allowed() then status(name,'build refused');return end
        local other = rawget(_G, "HD2ModLoader")
        local previous = other and other.modules and other.modules[name]
        if previous == "loading" or previous == "loaded" then
            loader.origins[name] = { owner = "mdl", registry = other }
            status(name, previous)
            return
        end
        local ok, available = pcall(host.available, name)
        if not ok then
            status(name, "lookup failed: " .. tostring(available))
            return
        end
        if not available then
            status(name, "not installed")
            return
        end
        local can_live = false
        if host.can_retry then
            local ok, value = pcall(host.can_retry, name)
            can_live = ok and value == true
        end
        loader.origins[name] = { owner = can_live and "lll_live" or "lll_archive" }
        status(name, "loading")
        callbacks.begin(name)
        local marker
        if host.health then local ok,value=pcall(host.health.before);if ok then marker=value end end
        local function finish_health()
            if host.health and marker then local ok,why=pcall(host.health.after,name,marker);if not ok then pcall(host.report,name,"Health observer failed: "..tostring(why))end end
            callbacks.ending()
        end
        local success, result = pcall(host.require, name)
        if not success then
            status(name, "load failed: " .. tostring(result))
            finish_health()
            return
        end
        if type(result) == "table" and result.live_lua_api == 1 then
            loader.records[name] = result
            if result.on_enable then
                local enabled, why = pcall(result.on_enable)
                if not enabled then
                    cleanup(name, result, "enable failed: " .. tostring(why))
                    finish_health()
                    return
                end
            end
        end
        status(name, "loaded")
        finish_health()
    end
    function loader.retry(name)
        if not allowed() then return false,'Unsupported game build' end
        if not host.can_retry or not host.can_retry(name) then
            return false, "Retry is available only for managed live scripts"
        end
        if loader.modules[name] == "loaded" then
            return loader.reload(name)
        end
        if loader.modules[name] == "loading" or loader.records[name] then
            return false, "Unresolved lifecycle ownership; restart required"
        end
        local valid, problem = pcall(host.preflight, name)
        if not valid then
            return false, problem
        end
        host.evict(name)
        load(name)
        return loader.modules[name] == "loaded", loader.modules[name]
    end
    function loader.reload(name)
        if not allowed() then return false,'Unsupported game build' end
        local record = loader.records[name]
        if
            loader.modules[name] ~= "loaded"
            or not record
            or type(record.on_disable) ~= "function"
        then
            return false, "This mod has no supported cleanup contract; restart required"
        end
        if host.preflight then
            local valid, problem = pcall(host.preflight, name)
            if not valid then
                return false, problem
            end
        end
        local ok, why = cleanup(name, record, "disabled")
        if not ok then
            return false, why
        end
        host.evict(name)
        load(name)
        return loader.modules[name] == "loaded", loader.modules[name]
    end
    function loader.set_enabled(name, wanted)
        if not allowed() then return false,'Unsupported game build' end
        wanted = wanted == true
        if not host.can_retry or not host.can_retry(name) then
            return false, "Archive addon has no managed live lifecycle; restart required"
        end
        local active = loader.modules[name] == "loaded"
        if loader.records[name] and not active then
            return false, "Unresolved lifecycle ownership; restart required"
        end
        if active == wanted then
            return true
        end
        if not wanted then
            local record = loader.records[name]
            if not record or type(record.on_disable) ~= "function" then
                return false, "Cleanup contract unavailable; restart required"
            end
            local function save_disable()
                if not host.save_enabled then
                    return true
                end
                local called, ok, why = pcall(host.save_enabled, name, false)
                if not called or not ok then
                    host.evict(name)
                    load(name)
                    return false, called and why or ok
                end
                return true
            end
            return cleanup(name, record, "disabled", save_disable)
        else
            if loader.records[name] then
                return false, "Unresolved lifecycle ownership; restart required"
            end
            local ok, why = pcall(host.preflight, name)
            if not ok then
                return false, why
            end
            host.evict(name)
            load(name)
            if loader.modules[name] ~= "loaded" then
                return false, loader.modules[name]
            end
        end
        if host.save_enabled then
            local ok, why = host.save_enabled(name, wanted)
            if not ok then
                if wanted then
                    local record = loader.records[name]
                    cleanup(name, record, "disabled")
                else
                    host.evict(name)
                    load(name)
                end
                return false, why
            end
        end
        return true
    end
    function loader.frame(dt)
        if next(loader.pending_cleanup) then
            for _, failure in ipairs(cleanup_queue.frame(dt)) do
                local job = failure.owner
                if
                    loader.pending_cleanup[job.name] == job
                    and loader.records[job.name] == job.record
                then
                    status(job.name, "cleanup failed: " .. tostring(failure.error))
                end
            end
        end
        for _, name in ipairs(loader.order) do
            local record = loader.records[name]
            if
                loader.modules[name] == "loaded"
                and record
                and type(record.on_update) == "function"
            then
                local ok, why = pcall(record.on_update, dt)
                if
                    not ok
                    and loader.records[name] == record
                    and loader.modules[name] == "loaded"
                then
                    cleanup(name, record, "update failed: " .. tostring(why))
                end
            end
        end
    end
    function loader.shutdown()
        callbacks.close()
        for i = #loader.order, 1, -1 do
            local name = loader.order[i]
            local record = loader.records[name]
            if loader.modules[name] == "loaded" and record and record.on_disable then
                cleanup(name, record, "disabled")
            end
        end
    end
    rawset(_G, "CowboyBingusModLoader", compat)
    rawset(_G, "LiveLuaLoader", loader)
    loader.order = {}
    local seen = {}
    for _, name in ipairs(entries) do
        if not seen[name] then
            seen[name] = true
            loader.order[#loader.order + 1] = name
            load(name)
        end
    end
    callbacks.finish()
    function loader.add(name, enabled)
        if not allowed() then return false,'Unsupported game build' end
        if seen[name] then
            return false
        end
        seen[name] = true
        loader.order[#loader.order + 1] = name
        if enabled == false then
            status(name, "disabled")
        else
            load(name)
        end
        return loader.modules[name] == "loaded"
    end
    function loader.forget_removed()
        local retired, retained, order = {}, 0, {}
        for _, name in ipairs(loader.order) do
            local missing = string.match(name, "^live/") and loader.live_catalog
                and not loader.live_catalog[name]
            local state = loader.modules[name]
            local origin = loader.origins[name]
            if missing and not loader.records[name] and not loader.pending_cleanup[name]
                and state ~= "loaded" and state ~= "loading"
                and not (origin and origin.registry) then
                host.evict(name)
                loader.modules[name], loader.errors[name], loader.origins[name] = nil, nil, nil
                seen[name] = nil
                retired[#retired + 1] = name
            else
                order[#order + 1] = name
                if missing then retained = retained + 1 end
            end
        end
        loader.order = order
        return retired, retained
    end
    return loader
end

end)()
local LLL_LEGACY=(function()
-- Public resource identities, in established startup order.
return {
    "mods/cowboybingus/vanilla_plus_megapack",
    "mods/cowboybingus/better_stratagem_bounce",
    "mods/cowboybingus/hellpod_steering_unlocked",
    "mods/cowboybingus/wide_angle_stratagems",
    "mods/cowboybingus/reinforcement_beacon_fix_data",
    "mods/cowboybingus/consistent_vaulting",
    "mods/cowboybingus/shallow_water_dive",
    "mods/cowboybingus/sentry_aim_retention",
    "mods/cowboybingus/corpse_collision_repair",
    "mods/cowboybingus/vehicle_stability",
    "mods/cowboybingus/hover_pack_cancel",
    "mods/cowboybingus/enemy_intelligence",
    "mods/codex/gun_calibration",
    "mods/cowboybingus/armory_preview_cache",
}

end)()
local LLL_DISCOVER=(function()
-- Shared bounded archive catalog; transport supplies optional native hashing.
local default_hash = LLL_DISCOVERY_HASH
if not default_hash and type(jit)=='table' then
    local chunk=assert(loadfile('src/discovery_hash.lua'))
    setfenv(chunk,getfenv(1))
    default_hash=chunk()
end
return function(platform, force)
    local hash = assert(platform.hash or default_hash, 'Archive hash transport unavailable')
    local files = {}
    local winners = {}
    local copies = {}
    local copy_report = {by_name={},notes={}}
    local identities = {}
    local warnings = {}
    local counters = { lua = 0, envelopes = 0, markers = 0, mismatches = 0 }
    local sample
    local listed, stamps = platform.files(platform.data, "9ba626afa44a3aa3.patch_*")
    local diagnostics = "Archive scan: " .. tostring(platform.data) .. "; files=" .. #listed
    for _, name in ipairs(listed) do
        local index = string.match(name, "^9ba626afa44a3aa3%.patch_(%d+)$")
        if index then
            files[#files + 1] = { name = name, index = tonumber(index) }
        end
    end
    table.sort(files, function(a, b)
        if a.index == b.index then
            return a.name < b.name
        end
        return a.index < b.index
    end)
    local signature, cache_path
    if stamps and platform.settings then
        local parts = { "LLL archive cache 3", platform.data }
        for _, file in ipairs(files) do
            parts[#parts + 1] = file.name .. ":" .. assert(stamps[file.name])
        end
        signature = table.concat(parts, "|")
        cache_path = platform.settings .. "/archive_catalog_v3.txt"
        if not force then
            local cache = platform.read(cache_path, 1048576)
            if cache then
                local split = string.find(cache, "\n", 1, true)
                if split and string.sub(cache, 1, split - 1) == signature then
                    local check_end = string.find(cache, "\n", split + 1, true)
                    local body = check_end and string.sub(cache, check_end + 1)
                    local checksum = check_end and string.sub(cache, split + 1, check_end - 1)
                    local names,records = {},{}
                    local valid = body and checksum == hash(body)
                    for line in string.gmatch(body or "", "([^\n]+)\n") do
                        local tag,name,archive,hidden=string.match(line,"^([NH])\t([^\t]+)\t([^\t]+)\t(.*)$")
                        if not tag or not string.match(name,"^mods/[%w_/]+$") or string.find(name,"//",1,true)
                            or string.sub(name,-1)=="/" or name=="mods/codex/loader"
                            or not string.match(archive,"^9ba626afa44a3aa3%.patch_%d+$") then valid=false;break end
                        local duplicates={}
                        for file in string.gmatch(hidden,"[^,]+") do
                            if not string.match(file,"^9ba626afa44a3aa3%.patch_%d+$") then valid=false;break end
                            duplicates[#duplicates+1]=file
                        end
                        local description="Active archive: "..archive.."; hidden copies: "..(#duplicates>0 and table.concat(duplicates,", ") or "none")
                        if tag=="N" then names[#names+1]=name;copy_report.by_name[name]=description
                        else copy_report.notes[#copy_report.notes+1]=name..": declared copy hidden by undeclared/compiled resource in "..archive end
                        records[#records+1]=line
                    end
                    if valid and body==table.concat(records,"\n").."\n" then
                        return names, {}, diagnostics .. "; cached catalog; candidates=" .. #files, copy_report
                    end
                end
            end
        end
    end
    for _, file in ipairs(files) do
        local reader
        local ok, why = pcall(function()
            local path = platform.data .. "/" .. file.name
            reader = platform.archive and platform.archive(path)
            local data = reader and reader.read(0, math.min(104, reader.size))
                or (not platform.archive and platform.read(path))
            assert(data and #data >= 104, "Unreadable archive")
            local size = reader and reader.size or #data
            local function u32(i)
                assert(i >= 0 and i + 4 <= #data, "Truncated archive integer")
                local a,b,c,d = string.byte(data, i + 1, i + 4)
                return a + b * 256 + c * 65536 + d * 16777216
            end
            local function u64(i)
                return string.format("%08x%08x", u32(i + 4), u32(i))
            end
            assert(u32(0) == 0xf0000011, "Unsupported archive")
            local types, count = u32(4), u32(8)
            local table_start = 72 + types * 32
            local table_end = table_start + count * 80
            assert(types > 0 and types <= 100000 and count <= 100000
                and table_end <= size, "Invalid resource table")
            if reader then
                data = assert(reader.read(0, table_end), "Unreadable resource table")
            end
            for i = 0, count - 1 do
                local at = table_start + i * 80
                local key = u64(at)
                local kind = u64(at + 8)
                -- Every winner hides older declarations, including an unmarked override.
                if kind == "a14e8dfa2cd117e2" then
                    counters.lua = counters.lua + 1
                    if winners[key] == nil then
                        identities[#identities + 1] = key
                    end
                    winners[key] = { index = file.index, order = i, archive = file.name }
                    copies[key]=copies[key] or {files={}}
                    local history=copies[key].files
                    if history[#history]~=file.name then history[#history+1]=file.name end
                    local offset = u32(at + 16) + u32(at + 20) * 4294967296
                    local length = u32(at + 56)
                    assert(
                        offset >= table_end and length >= 8 and offset + length <= size,
                        "Invalid resource range"
                    )
                    local prefix = reader
                            and assert(
                                reader.read(offset, math.min(length, 264)),
                                "Unreadable resource prefix"
                            )
                        or string.sub(data, offset + 1, math.min(offset + length, offset + 264))
                    local function prefix_u32(at)
                        local a,b,c,d = string.byte(prefix, at + 1, at + 4)
                        return a + b * 256 + c * 65536 + d * 16777216
                    end
                    if
                        (prefix_u32(4) == 1 or prefix_u32(4) == 2)
                        and prefix_u32(0) == length - 8
                    then
                        counters.envelopes = counters.envelopes + 1
                        local head = string.sub(prefix, 9)
                        local name = string.match(head, "^%-%- HD2%-Addon: ([^\r\n]+)[\r\n]")
                        local computed
                        if name then
                            counters.markers = counters.markers + 1
                            computed = hash(name)
                            if computed ~= key then
                                counters.mismatches = counters.mismatches + 1
                                sample = sample
                                    or (name .. " computed=" .. computed .. " stored=" .. key)
                            end
                        end
                        local valid = name and string.sub(name, 1, 5) == "mods/" and string.sub(name, -1) ~= "/"
                        if valid then
                            local previous
                            for j = 1, #name do
                                local b = string.byte(name, j)
                                if
                                    not (
                                        (b >= 48 and b <= 57)
                                        or (b >= 65 and b <= 90)
                                        or (b >= 97 and b <= 122)
                                        or b == 95
                                        or b == 47
                                    )
                                    or (b == 47 and previous == 47)
                                then
                                    valid = false
                                    break
                                end
                                previous = b
                            end
                        end
                        if valid and name ~= "mods/codex/loader" and computed == key then
                            winners[key].name = name
                            copies[key].name = name
                        end
                    end
                end
            end
        end)
        if reader then
            reader.close()
        end
        if not ok then
            warnings[#warnings + 1] = file.name .. ": " .. tostring(why)
        end
    end
    diagnostics = diagnostics
        .. "; candidates="
        .. #files
        .. "; lua="
        .. counters.lua
        .. "; envelopes="
        .. counters.envelopes
        .. "; markers="
        .. counters.markers
        .. "; hash mismatches="
        .. counters.mismatches
        .. "; sample="
        .. tostring(sample)
    local entries = {}
    for _, key in ipairs(identities) do
        local entry = winners[key]
        if entry.name then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(a, b)
        if a.index == b.index then
            return a.order < b.order
        end
        return a.index < b.index
    end)
    local records = {}
    for key, history in pairs(copies) do
        if history.name then
            local winner=winners[key];local hidden={}
            for _, file in ipairs(history.files)do if file~=winner.archive then hidden[#hidden+1]=file end end
            local tag=winner.name and "N" or "H"
            records[#records+1]={index=winner.index,order=winner.order,text=tag.."\t"..history.name.."\t"..winner.archive.."\t"..table.concat(hidden,",")}
            if winner.name then copy_report.by_name[history.name]="Active archive: "..winner.archive.."; hidden copies: "..(#hidden>0 and table.concat(hidden,", ") or "none")
            else copy_report.notes[#copy_report.notes+1]=history.name..": declared copy hidden by undeclared/compiled resource in "..winner.archive end
        end
    end
    table.sort(records,function(a,b)return a.index==b.index and a.order<b.order or a.index<b.index end)
    for i,record in ipairs(records)do records[i]=record.text end
    local names = {}
    for _, entry in ipairs(entries) do
        names[#names + 1] = entry.name
    end
    if signature and #warnings == 0 and platform.write then
        local body = table.concat(records, "\n") .. "\n"
        pcall(platform.write, cache_path, signature .. "\n" .. hash(body) .. "\n" .. body)
    end
    return names, warnings, diagnostics, copy_report
end

end)()
local LLL_COMMANDS=(function()
-- Typed mod-owned console commands. Setters own validation and persistence.
local M={}
local Metadata=LLL_METADATA or dofile('src/metadata.lua')
function M.new()
    local providers={};local self={api=1}
    local function lookup(path)
        local namespace,rest=path:match('^([%w_-]+)%.(.+)$')
        local provider=namespace and providers[namespace]
        if provider and type(provider.owner)=="table" then assert(provider.owner.console_active~=false,"Mod cleanup is in progress")end
        return provider and provider.paths[rest]
    end
    function self.register(namespace,owner,spec)
        assert(type(namespace)=='string' and namespace:match('^[%w_-]+$'),'Console namespace required')
        assert(owner~=nil and type(spec)=='table','Console owner and fields required')
        assert(not providers[namespace],'Console namespace already owned: '..namespace)
        local paths={}
        local function flatten(values,prefix,depth)
            assert(depth<12,'Console schema nesting limit')
            for key,value in pairs(values)do
                assert(type(key)=='string' and key:match('^[%w_-]+$') and type(value)=='table','Invalid console field')
                local path=prefix=='' and key or prefix..'.'..key
                if value.get or value.set or value.call then
                    assert(not value.get or type(value.get)=='function');assert(not value.set or type(value.set)=='function');assert(not value.call or type(value.call)=='function')
                    paths[path]=value
                else flatten(value,path,depth+1)end
            end
        end
        flatten(spec,'',0)
        local token={owner=owner,paths=paths};providers[namespace]=token
        local function release()
            if providers[namespace]==token then providers[namespace]=nil end
            return true
        end
        return release
    end
    function self.list()
        local result={}
        for namespace,provider in pairs(providers)do for path in pairs(provider.paths)do result[#result+1]=namespace..'.'..path end end
        table.sort(result);return result
    end
    function self.suggest(command)
        if type(command)~='string' or #command>1024 then return {} end
        local result={};local leading,body=command:match('^(%s*)(.-)$')
        local verb,prefix=body:match('^(%a+)%s+([%w_%.%-]*)$')
        if verb and verb~='get' and verb~='run' and verb~='help' and verb~='list' then return result end
        local path,value=body:match('^([%w_%.%-]+)%s*=%s*([%a]*)$')
        local function add(text,label)result[#result+1]={text=leading..text,label=label or text}end
        if path then
            local namespace,rest=path:match('^([%w_-]+)%.(.+)$');local provider=providers[namespace]
            local field=provider and provider.paths[rest]
            if field and field.set and field.type=='boolean' and not (type(provider.owner)=='table' and provider.owner.console_active==false) then
                for _,choice in ipairs({'false','true'})do if choice:sub(1,#value)==value then add(path..' = '..choice)end end
            end
            return result
        end
        prefix=prefix or body
        if not prefix:match('^[%w_%.%-]*$') then return result end
        if not verb then for _,word in ipairs({'get ','help','list','run '})do if word:sub(1,#prefix)==prefix then add(word)end end end
        for namespace,provider in pairs(providers)do
            if not (type(provider.owner)=='table' and provider.owner.console_active==false) then
                for name,field in pairs(provider.paths)do
                    local full=namespace..'.'..name
                    if full:sub(1,#prefix)==prefix and (verb~='run' or field.call) and (verb~='get' or field.get) then
                        add((verb and verb..' ' or '')..full)
                    end
                end
            end
        end
        table.sort(result,function(a,b)return a.text<b.text end);return result
    end
    local function parse(value)
        local number=tonumber(value)
        if number then assert(number==number and math.abs(number)<math.huge,'Finite number required');return number end
        if value=='true' then return true elseif value=='false' then return false end
        return Metadata.decode(value)
    end
    function self.execute(command)
        local ok,success,message=pcall(function()
            assert(type(command)=='string' and #command<=1024,'Command exceeds 1024 characters')
            command=command:match('^%s*(.-)%s*$')
            if command=='help' or command=='list' or command:match('^help%s+[%w_%.%-]+$') or command:match('^list%s+[%w_%.%-]+$')then
                local prefix=command:match('^%w+%s+([%w_%.%-]+)$');local selected={}
                for _,path in ipairs(self.list())do if not prefix or path:sub(1,#prefix)==prefix then selected[#selected+1]=path end end
                return true,'Commands:\n'..table.concat(selected,'\n')
            end
            local path,value=command:match('^([%w_%.%-]+)%s*=%s*(.-)%s*$')
            local action=command:match('^run%s+([%w_%.%-]+)$')
            path=path or action or command:match('^get%s+([%w_%.%-]+)$') or command:match('^([%w_%.%-]+)$')
            assert(path,'Use namespace.field = value, get namespace.field, or run namespace.action')
            local field=assert(lookup(path),'Unknown command: '..path)
            if value~=nil then
                assert(field.set,'Read-only field: '..path)
                local typed=parse(value)
                if field.type then assert(type(typed)==field.type,'Expected '..field.type..' for '..path)end
                if type(typed)=='number' then assert(not field.min or typed>=field.min,'Value below minimum');assert(not field.max or typed<=field.max,'Value above maximum')end
                if field.validate then assert(field.validate(typed)~=false,'Value rejected')end
                local accepted,why=field.set(typed)
                if accepted==false then return false,tostring(why or 'Setter refused')end
                local reported=typed;if field.get then reported=field.get()end
                return true,why or (path..' = '..tostring(reported))
            end
            if action or (field.call and not field.get)then
                assert(field.call,'Command is not an action: '..path)
                local accepted,why=field.call();return accepted~=false,tostring(why or (accepted==false and 'Action refused' or 'Completed '..path))
            end
            assert(field.get,'Field is not readable: '..path)
            return true,path..' = '..tostring(field.get())
        end)
        if not ok then return false,tostring(success)end
        return success,message
    end
    return self
end
return M

end)()
local LLL_PROJECT=(function()
-- LLL-native folder projects. Per-instance scope/cache; no package.path mutation.
local M={}
local Metadata=LLL_METADATA or dofile('src/metadata.lua')
local Serialize=LLL_CONFIG or dofile('src/config.lua')
local function relative(path)
    assert(type(path)=='string' and #path>0 and #path<=240 and not path:find('[\\:%c]') and path:sub(1,1)~='/', 'Use a mod-relative path')
    for part in path:gmatch('[^/]+')do assert(part~='.' and part~='..','Path escapes the mod folder')end
    assert(not path:find('//',1,true),'Empty path segment')
    return path
end
local function module_path(name)
    assert(type(name)=='string','Module name required')
    if not name:find('/',1,true) and not name:match('%.lua$') then name=name:gsub('%.','/') end
    if not name:match('%.lua$') then name=name..'.lua' end
    return relative(name)
end
-- Runtime checks must not retain a token per word of large generated modules.
-- Keep only two token markers, and skip literal bodies with bounded searches.
local function native_long_literal(text,at)
    local opening=text:find('[^=]',at+1)
    if not opening or text:byte(opening)~=91 then return end
    local equals=opening-at-1
    if equals==0 then
        local closing=assert(text:find(']]',opening+1,true),'Unterminated long literal')
        return opening+1,closing-1,closing+2
    end
    local scan=opening+1
    while true do
        local closing=assert(text:find(']',scan,true),'Unterminated long literal')
        local finish=assert(text:find('[^=]',closing+1),'Unterminated long literal')
        if finish-closing-1==equals and text:byte(finish)==93 then
            return opening+1,closing-1,finish+1
        end
        scan=finish
    end
end
local function native_quoted_end(text,at,quote)
    local scan=at+1
    while true do
        local finish=assert(text:find(quote,scan,true),'Unterminated short literal')
        local back=finish-1
        while text:byte(back)==92 do back=back-1 end
        if (finish-back-1)%2==0 then return finish end
        scan=finish+1
    end
end
local function native_literal_name(text,first,last,quoted)
    if not quoted then
        -- Lua drops the first newline in a long literal, including CR/LF pairs.
        local newline=text:byte(first)
        if newline==10 or newline==13 then
            first=first+1
            local next_byte=text:byte(first)
            if (next_byte==10 or next_byte==13) and next_byte~=newline then first=first+1 end
        end
    end
    -- Three output bytes need at most three four-byte decimal escapes in 5.1.
    if last-first+1<3 or last-first+1>(quoted and 12 or 3) then return end
    local value=''
    while first<=last do
        local byte=text:byte(first);first=first+1
        if quoted and byte==92 then
            byte=text:byte(first);first=first+1
            if not byte then return end
            if byte>=48 and byte<=57 then
                local number=byte-48
                for _=1,2 do
                    local digit=text:byte(first)
                    if not digit or digit<48 or digit>57 then break end
                    number=number*10+digit-48;first=first+1
                end
                byte=number
            elseif byte==97 or byte==98 or byte==102 or byte==110 or byte==114 or byte==116 or byte==118
                or byte==10 or byte==13 then
                return -- A control-character escape cannot name these modules.
            end
        end
        if byte~=102 and byte~=105 and byte~=98 and byte~=116 and byte~=106 then return end
        value=value..string.char(byte)
        if #value>3 then return end
    end
    if value=='ffi' or value=='bit' or value=='jit' then return value end
end
local function native_dependency(text)
    -- Markers: 1 = _G, 2 = property dot, 3 = method colon; 0 = other.
    local at,previous,before,argument=1,0,0,0
    while true do
        at=text:find('%S',at)
        if not at then return end
        local byte=text:byte(at)
        if byte==45 and text:byte(at+1)==45 then
            local _,_,after
            if text:byte(at+2)==91 then _,_,after=native_long_literal(text,at+2) end
            at=after or ((text:find('[\r\n]',at+2) or #text)+1)
        elseif byte==39 or byte==34 then
            local finish=native_quoted_end(text,at,byte==39 and "'" or '"')
            if argument~=0 then
                local name=native_literal_name(text,at+1,finish-1,true)
                if name then return name end
            end
            at,previous,before,argument=finish+1,0,previous,0
        elseif byte==91 then
            local first,last,after=native_long_literal(text,at)
            if after then
                if argument~=0 then
                    local name=native_literal_name(text,first,last,false)
                    if name then return name end
                end
                at=after
            else at=at+1 end
            previous,before,argument=0,previous,0
        elseif (byte>=65 and byte<=90) or (byte>=97 and byte<=122) or byte==95 then
            local _,finish=text:find('^[%w_]+',at)
            local length=finish-at+1
            local marker=0
            if length==7 and byte==114 then
                local a,b,c,d,e,f,g=text:byte(at,finish)
                if a==114 and b==101 and c==113 and d==117 and e==105 and f==114 and g==101
                    and (previous~=2 and previous~=3 or previous==2 and before==1) then argument=1
                else argument=0 end
            else
                argument=0
                if length==2 and byte==95 and text:byte(at+1)==71 then marker=1 end
            end
            at,previous,before=finish+1,marker,previous
        else
            local marker=byte==46 and 2 or (byte==58 and 3 or 0)
            if byte==40 and argument==1 then argument=2 else argument=0 end
            at=at+1
            if byte==46 and text:byte(at)==46 then
                at=at+1
                if text:byte(at)==46 then at=at+1 end
                marker=0 -- Concatenation/varargs are not a property lookup.
            end
            previous,before=marker,previous
        end
    end
end
function M.check_runtime(platform,text,path)
    local vm=rawget(_G,'jit');if platform.native_ffi~=false or type(vm)=='table' and type(vm.version)=='string' and vm.version:sub(1,7)=='LuaJIT ' then return end -- LuaJIT boot: ffi/bit/jit are real
    local name=native_dependency(text)
    if name then error('Unsupported runtime: '..path..' requires LuaJIT '..name..'; script was not executed') end
end
-- LuaJIT accepts \z whitespace elision; Lua 5.1 decodes it as the letter z.
-- Ask the already-used compiler once so removed/foreign jit globals cannot
-- change literal interpretation. The probe chunk only returns a constant.
local quoted_z=loadstring([[return '\z']])
local has_quoted_z=quoted_z and quoted_z()==''
-- LuaJIT also supports ten-byte \u{hhhhhh} spellings of one ASCII byte.
local import_encoded_limit=has_quoted_z and 2400 or 960
local function compact_import_literal(text,first,last)
    local parts,size,at={},0,first
    local function append(a,b)
        if b<a then return end
        size=size+b-a+1
        assert(size<=import_encoded_limit,'Use a mod-relative path')
        parts[#parts+1]=text:sub(a,b)
    end
    while at<=last do
        local slash=text:find('\\',at,true)
        if not slash or slash>last then append(at,last);break end
        append(at,slash-1)
        if text:byte(slash+1)==122 then
            at=text:find('%S',slash+2) or last+1
        else
            append(slash,math.min(slash+1,last));at=slash+2
        end
    end
    return table.concat(parts)
end
local function import_literal(text,first,last,quoted)
    if quoted then
        -- Existing paths are limited to 240 bytes. A Lua 5.1 decimal escape
        -- needs at most four source bytes per decoded byte; reject giant
        -- actual arguments before copying or compiling them.
        if last-first+1>import_encoded_limit then
            assert(has_quoted_z,'Use a mod-relative path')
            local literal=compact_import_literal(text,first,last)
            local quote=text:sub(first-1,first-1)
            local chunk=assert(loadstring('return '..quote..literal..quote))
            setfenv(chunk,{})
            return module_path(chunk())
        end
        local escaped=text:find('\\',first,true)
        if not escaped or escaped>last then
            assert(last-first+1<=240,'Use a mod-relative path')
            return module_path(text:sub(first,last))
        end
        local chunk=assert(loadstring('return '..text:sub(first-1,last+1)))
        setfenv(chunk,{})
        return module_path(chunk())
    end
    local newline=text:byte(first)
    if newline==10 or newline==13 then
        first=first+1
        local next_byte=text:byte(first)
        if (next_byte==10 or next_byte==13) and next_byte~=newline then first=first+1 end
    end
    assert(last-first+1<=240,'Use a mod-relative path')
    return module_path(text:sub(first,last))
end
local function imports(text)
    -- Retain only the mod.require prefix and unique dependencies. Unrelated
    -- literals/comments are skipped without copying or compiling their bodies.
    local result,seen,at,state={},{},1,0
    local function add(first,last,quoted)
        local path=import_literal(text,first,last,quoted)
        if not seen[path] then
            assert(#result<512,'Module count limit')
            seen[path]=true;result[#result+1]=path
        end
    end
    while true do
        -- With no prefix pending, punctuation/numbers cannot begin an import.
        -- Skip them in C rather than visiting every generated-code token.
        at=text:find(state==0 and "[%a_'\"%[%-]" or '%S',at)
        if not at then return result end
        local byte=text:byte(at)
        if byte==45 and text:byte(at+1)==45 then
            local _,_,after
            if text:byte(at+2)==91 then _,_,after=native_long_literal(text,at+2) end
            at=after or ((text:find('[\r\n]',at+2) or #text)+1)
        elseif byte==39 or byte==34 then
            local finish=native_quoted_end(text,at,byte==39 and "'" or '"')
            if state==3 or state==4 then add(at+1,finish-1,true) end
            at,state=finish+1,0
        elseif byte==91 then
            local first,last,after=native_long_literal(text,at)
            if after then
                if state==3 or state==4 then add(first,last,false) end
                at=after
            else at=at+1 end
            state=0
        elseif (byte>=65 and byte<=90) or (byte>=97 and byte<=122) or byte==95 then
            local _,finish=text:find('^[%w_]+',at)
            local length=finish-at+1
            if byte==109 and length==3 and text:byte(at+1)==111 and text:byte(at+2)==100 then state=1
            elseif state==2 and byte==114 and length==7 and text:sub(at,finish)=='require' then state=3
            else state=0 end
            at=finish+1
        else
            if state==1 and byte==46 then state=2
            elseif state==3 and byte==40 then state=4
            else state=0 end
            at=at+1
        end
    end
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,item in pairs(value)do result[key]=copy(item)end;return result
end
local function merge(base,overlay)
    local result=copy(base)
    for key,value in pairs(overlay)do
        if type(value)=="table" and type(result[key])=="table" then result[key]=merge(result[key],value)
        else result[key]=copy(value)end
    end
    return result
end
local function json(value)
    Serialize.serialize(value)
    local function quote(text)
        return '"'..text:gsub('[%z\1-\31\\"]',function(c)
            local escapes={['"']='\\"',["\\"]='\\\\',["\n"]='\\n',["\r"]='\\r',["\t"]='\\t'}
            return escapes[c] or string.format('\\u%04x',string.byte(c))
        end)..'"'
    end
    local function encode(item)
        if type(item)=="string" then return quote(item)end
        if type(item)=="number" or type(item)=="boolean" then return tostring(item)end
        local rows,keys={},{};local array=true;local count=0
        for key in pairs(item)do count=count+1;if type(key)~="number" or key%1~=0 or key<1 then array=false end;keys[#keys+1]=key end
        if array and count>0 and #item==count then
            for index=1,count do rows[#rows+1]=encode(item[index])end
            return '['..table.concat(rows,',')..']'
        end
        table.sort(keys)
        for _,key in ipairs(keys)do assert(type(key)=="string","Config objects require string keys");rows[#rows+1]=quote(key)..':'..encode(item[key])end
        return '{'..table.concat(rows,',')..'}'
    end
    return encode(value)
end
local function data(text,path)
    if not text then return {} end
    local result=Metadata.decode(text)
    assert(type(result)=="table" and result~=Metadata,"Config must contain a JSON object")
    json(result);return result
end
function M.descriptor(platform,dir)
    local text=platform.read(dir..'/manifest.json',1048576)
    if not text then return end
    local ok,value=pcall(Metadata.decode,text)
    if not ok or type(value)~='table' or value.lll==nil then return end
    assert(type(value.lll)=='table' and value.lll~=Metadata,'Invalid LLL manifest descriptor')
    local spec=copy(value.lll)
    spec.entry=relative(spec.entry or 'main.lua')
    spec.defaults=relative(spec.defaults or 'config/defaults.cfg')
    assert(spec.entry:match('%.lua$'),'LLL entry must be Lua')
    if spec.modules then
        assert(type(spec.modules)=='table','modules must be a list')
        for _,path in ipairs(spec.modules)do assert(relative(path):match('%.lua$'),'Declared module must be Lua')end
    end
    assert(spec.restart_only==nil or type(spec.restart_only)=='boolean','restart_only must be boolean')
    assert(spec.retain_until_exit==nil or type(spec.retain_until_exit)=='boolean','retain_until_exit must be boolean')
    return spec
end
function M.snapshot(platform,entry,spec)
    local paths,seen={},{}
    local function add(path)
        path=relative(path);if not seen[path]then seen[path]=true;paths[#paths+1]=path end
    end
    add(spec.entry)
    if spec.modules then for _,path in ipairs(spec.modules)do add(path)end
    else
        local function walk(dir,depth)
            assert(depth<=12,'Module directory nesting limit')
            local files,_,dirs=platform.files(entry.dir..'/'..dir)
            for _,file in ipairs(files or {})do if file:match('%.lua$')then add(dir..'/'..file)end end
            for _,child in ipairs(dirs or {})do walk(dir..'/'..relative(child),depth+1)end
        end
        walk('src',1);walk('vendor',1)
    end
    assert(#paths<=512,'Module count limit')
    table.sort(paths)
    local result={spec=spec,code={},chunks={},paths=paths,config_path=platform.settings and platform.settings..'/'..entry.id..'/config.cfg'}
    for _,path in ipairs(paths)do
        local text=assert(platform.read(entry.dir..'/'..path,16777216),'Module unreadable: '..path)
        M.check_runtime(platform,text,path)
        result.code[path]=text;result.chunks[path]=assert(loadstring(text,'@'..entry.dir..'/'..path))
    end
    for path,text in pairs(result.code)do
        for _,dependency in ipairs(imports(text))do assert(result.code[dependency],path..': undeclared import '..dependency)end
    end
    result.defaults=data(platform.read(entry.dir..'/'..spec.defaults,1048576),entry.dir..'/'..spec.defaults)
    result.user=data(result.config_path and platform.read(result.config_path,1048576),result.config_path or 'config')
    return result
end
function M.fingerprint(platform,entry,spec)
    local paths={spec.entry,spec.defaults,'manifest.json'}
    if spec.modules then for _,path in ipairs(spec.modules)do paths[#paths+1]=path end
    else
        local function walk(dir,depth)
            assert(depth<=12,'Module nesting limit')
            local files,_,dirs=platform.files(entry.dir..'/'..dir)
            for _,file in ipairs(files or {})do if file:match('%.lua$')then paths[#paths+1]=dir..'/'..file end end
            for _,child in ipairs(dirs or {})do walk(dir..'/'..relative(child),depth+1)end
        end
        walk('src',1);walk('vendor',1)
    end
    assert(#paths<=515,'Module count limit');table.sort(paths)
    local parts={}
    for _,path in ipairs(paths)do
        local full=entry.dir..'/'..relative(path)
        local value=platform.stat and platform.stat(full) or platform.read(full,16777216) or '-'
        parts[#parts+1]=#path..':'..path..':'..#value..':'..value
    end
    return table.concat(parts,'|')
end
function M.instantiate(platform,entry,snapshot,report)
    local cache,loading={},{}
    local console_releases={}
    local settings=merge(snapshot.defaults,snapshot.user)
    local scope={};setmetatable(scope,{__index=_G})
    local api={console_active=true,retain_until_exit=snapshot.spec.retain_until_exit==true,id=entry.id,name=entry.metadata and entry.metadata.name or entry.id,dir=entry.dir,scope=scope,config=settings,config_path=snapshot.config_path,config_dir=platform.settings and platform.settings.."/"..entry.id,restart_only=snapshot.spec.restart_only==true}
    scope.mod=api
    if api.config_dir and platform.mkdir then assert(platform.mkdir(api.config_dir),"Cannot create mod config folder")end
    function api.expose(namespace,fields)
        if not platform.command_bus then return false,"Console unavailable" end
        local release=platform.command_bus.register(namespace,api,fields)
        console_releases[#console_releases+1]=release;return release
    end
    function api.release_console()
        for index=#console_releases,1,-1 do console_releases[index]();console_releases[index]=nil end
    end
    function api.require(name,...)
        local path=module_path(name)
        if cache[path]~=nil then return cache[path]end
        assert(not loading[path],'Circular module import: '..path)
        local chunk=assert(snapshot.chunks[path],'Module not declared in this project: '..path);setfenv(chunk,scope)
        loading[path]=true;local called,value=pcall(chunk,...);loading[path]=nil
        if not called then error(value,2)end
        if value==nil then value=true end;cache[path]=value;return value
    end
    function api.read(path)
        return platform.read(entry.dir..'/'..relative(path),16777216)
    end
    function api.set(key,value)
        local valid,problem=pcall(Serialize.serialize,{current=settings,next=value})
        if not valid then return false,tostring(problem)end
        assert(type(key)=='string' and not key:find('[%c]'),'Printable config key required')
        local next_values=copy(settings);next_values[key]=copy(value)
        local called,text=pcall(json,next_values)
        if not called then return false,tostring(text)end
        if not snapshot.config_path then return false,'Settings storage unavailable' end
        if platform.mkdir and not platform.mkdir(platform.settings..'/'..entry.id) then return false,'Cannot create mod settings folder' end
        if not platform.write(snapshot.config_path,text..'\n') then return false,'Cannot save mod config' end
        for field in pairs(settings)do settings[field]=nil end
        for field,item in pairs(next_values)do settings[field]=item end
        return true
    end
    function api.log(message)report('live/'..entry.id,tostring(message))end
    return api.require(snapshot.spec.entry),api
end
return M

end)()
local LLL_CATALOG_WATCH=(function()
-- Ignore output-only broad-root notifications while preserving discovery edits.
local function add(parts,key,value)
 value=tostring(value);parts[#parts+1]=key..'='..#value..':'..value
end
local function normalized(path)return type(path)=='string'and path:gsub('\\','/'):gsub('/+$',''):lower()or''end
local function catalog_filter(platform,project,handle)
 if not project or type(platform.roots)~='table'then return end
 local broad,separate
 for _,root in ipairs(platform.roots)do
  if normalized(root.path):match('/cowboybingus/helldivers2$')then broad=root.path:gsub('[/\\]+$','')end
 end
 if not broad then return end
 for _,root in ipairs(platform.roots)do if normalized(root.path)==normalized(broad)..'/mods'then separate=true end end
 if not separate then return end
 local descriptors={}
 local function listing(path)
  local files,stamps,dirs,status=platform.files(path)
  if status~=nil and status~=0 and status~=2 and status~=3 then return end
  if type(files)~='table'or type(stamps)~='table'then return end
  if type(dirs)~='table'and platform.directories then dirs=platform.directories(path)end
  if type(dirs)~='table'then return end
  local lowered={}
  for key,value in pairs(stamps)do if type(key)=='string'then lowered[key:lower()]=value end end
  for _,file in ipairs(files)do if type(file)~='string'or lowered[file:lower()]==nil then return end end
  return files,lowered,dirs
 end
 local function signature()
  local files,stamps,dirs=listing(broad);if not files then return end
  local mods_present=false
  for _,dir in ipairs(dirs)do if type(dir)=='string'and dir:lower()=='mods'then mods_present=true end end
  local parts={}
  -- A complete parent listing also proves an absent configured Mods root.
  -- Its creation/deletion changes this marker and forces normal discovery.
  add(parts,'separate-mods-present',mods_present)
  for _,file in ipairs(files)do
   if type(file)=='string'and(file:lower():match('%.lua$')or file:lower():match('%.json$'))then add(parts,'root:'..file,stamps[file:lower()]or'-')end
  end
  for _,dir in ipairs(dirs)do
   if type(dir)=='string'and dir:match('^[%w_-]+$')and dir:lower()~='mods'then
    add(parts,'directory',dir)
    local child=broad..'/'..dir
    -- Older transports stat every enumerated file. Inspect only the fixed
    -- discovery markers; logs can contain hundreds of unrelated files.
    local child_stamps={}
    for _,file in ipairs({'manifest.json','mod.json','metadata.json','main.lua','mod.lua'})do
     child_stamps[file]=platform.stat(child..'/'..file)
     add(parts,dir..':'..file,child_stamps[file]or'-')
    end
    local manifest_stamp=child_stamps['manifest.json']
    if manifest_stamp then
     local cached=descriptors[dir]
     if not cached or cached.stamp~=manifest_stamp then
      -- Decode through LLL's existing data-only descriptor; never execute metadata.
      local checked={read=function(path,limit)
       local text=platform.read(path,limit)
       assert(text~=nil,'Manifest temporarily unreadable')
       return text
      end}
      local spec=project.descriptor(checked,child)
      cached={stamp=manifest_stamp,entry=spec and spec.entry};descriptors[dir]=cached
     end
     if cached.entry then
      local stamp=child_stamps[cached.entry:lower()]
      if stamp==nil then stamp=platform.stat(child..'/'..cached.entry)end
      add(parts,dir..':entry:'..cached.entry,stamp or'-')
     end
    else descriptors[dir]=nil end
   end
  end
  table.sort(parts);return table.concat(parts,'|')
 end
 local last
 local ok,value=pcall(signature);if ok then last=value end
 local original=platform.changed
 local wrapper=function(path,...)
  if not handle.active then return original(path,...)end
  local changed=original(path,...)
  if changed~=true or normalized(path)~=normalized(broad)then return changed end
  local ok,current=pcall(signature)
  if not ok or not current then last=nil;handle.catalog_fallbacks=handle.catalog_fallbacks+1;return changed end
  local same=last==current;last=current
  if same then handle.catalog_ignored=handle.catalog_ignored+1;return false end
  handle.catalog_passed=handle.catalog_passed+1;return changed
 end
 return original,wrapper
end
return catalog_filter

end)()
local LLL_LIVE=(function()
-- Loose-script catalog and MDL API 2 lifecycle adapter.
return function(platform, report)
    local self = { entries = {}, catalog = {}, settings = {} }
    local sources, metadata_cache = {}, {}
    local project=LLL_PROJECT or dofile("src/project.lua")
    -- The broad Bingus compatibility root contains Logs as well as scripts.
    -- Output writes must not invalidate every source/metadata cache.
    local catalog_watch=LLL_CATALOG_WATCH or dofile("src/catalog_watch.lua")
    local watch_state={active=true,catalog_ignored=0,catalog_passed=0,catalog_fallbacks=0}
    if platform.changed and platform.stat then
        local _,filtered=catalog_watch(platform,project,watch_state)
        if filtered then platform.changed=filtered end
    end
    self.catalog_watch=watch_state
    local prepared,instances,retained_instances={},{},{}
    local last_names
    local pending_root_change=false
    local fingerprints = {}
    local project_watches = {}
    local function watch_key(path)
        return path:gsub('\\','/'):gsub('/+$',''):lower()
    end
    local function valid(id)
        return type(id) == "string" and string.match(id, "^[%w_-]+$")
    end
    local function config(path)
        local data = path and platform.read(path, 1048576)
        if not data then
            return {}
        end
        local chunk = loadstring(data, "@" .. path)
        if not chunk then
            return {}
        end
        setfenv(chunk, {})
        local ok, value = pcall(chunk)
        return ok and type(value) == "table" and value or {}
    end
    local mdl = config(platform.loader_config)
    if next(mdl) == nil then
        mdl = config(platform.migrated_config)
    end
    if next(mdl) == nil then
        mdl = config(platform.mdl_config)
    end
    local serialize = (LLL_CONFIG or dofile("src/config.lua")).serialize
    function self.loader_option(name)
        return mdl[name]
    end
    function self.save_loader_option(name, value)
        local old = mdl[name]
        mdl[name] = value
        local ok, text = pcall(serialize, mdl)
        if not ok or not platform.loader_config or not platform.write(platform.loader_config, "return " .. text .. "\n") then
            mdl[name] = old
            return false, "Could not save loader option"
        end
        return true
    end
    function self.scan(force)
        if platform.changed then
            local changed = pending_root_change
            pending_root_change=false
            for _, root in ipairs(platform.roots or { { kind = "lll", path = platform.live } }) do
                if root.path and platform.changed(root.path) then
                    changed = true
                end
            end
            if not force and last_names and not changed then
                return last_names
            end
            if changed or force then
                sources = {}
            end
        end
        if force then
            sources = {}
            metadata_cache = {}
        end
        local names = {}
        local seen = {}
        for _, root in ipairs(platform.roots or { { kind = "lll", path = platform.live } }) do
            if root.path then
                local candidates = {}
                local root_files, _, root_dirs, listing_status = platform.files(root.path)
                assert(listing_status == nil or listing_status == 0 or listing_status == 2 or listing_status == 3,
                    'Catalog listing incomplete: '..root.path..' (status '..tostring(listing_status)..')')
                for _, file in ipairs(root_files) do
                    local id = string.match(file, "^([%w_-]+)%.lua$")
                    if id then
                        candidates[#candidates + 1] = {
                            id = id,
                            path = root.path .. "/" .. file,
                            metadata_id = id,
                            dir = root.path,
                            kind = root.kind,
                        }
                    end
                end
                if platform.directories then
                    for _, id in ipairs(root_dirs or platform.directories(root.path)) do
                        if valid(id) then
                            local dir=root.path.."/"..id
                            local declared
                            if root.kind~="mdl" then
                                local ok,value=pcall(project.descriptor,platform,dir)
                                if ok then declared=value else report("live/"..id,"Manifest refused: "..tostring(value))end
                            end
                            if root.kind~="mdl" and not declared then
                                local main=platform.stat and platform.stat(dir.."/main.lua") or platform.read(dir.."/main.lua",16777216)
                                if main then declared={entry="main.lua",defaults="config/defaults.cfg",invalid=true}end
                            end
                            local path = dir .. "/" .. (declared and declared.entry or "mod.lua")
                            local exists
                            if platform.stat then
                                exists = platform.stat(path)
                            else
                                exists = platform.read(path, 16777216)
                            end
                            if exists then
                                candidates[#candidates + 1] = {
                                    id = id,
                                    path = path,
                                    dir = root.path .. "/" .. id,
                                    kind = root.kind,
                                    project = declared,
                                }
                            end
                        end
                    end
                end
                table.sort(candidates, function(a, b)
                    if a.id==b.id then
                        local af,bf=a.dir~=root.path,b.dir~=root.path
                        if af~=bf then return af end
                    end
                    return a.path < b.path
                end)
                for _, entry in ipairs(candidates) do
                    entry.source_root = root.path
                    if LLL_METADATA then
                        local key=entry.dir.."/"..(entry.metadata_id or "")
                        local signature
                        if platform.stat then
                            local stamps={}
                            for _,file in ipairs(LLL_METADATA.files(entry.metadata_id))do stamps[#stamps+1]=platform.stat(entry.dir.."/"..file) or "-"end
                            signature=table.concat(stamps,"|")
                        end
                        local cached = metadata_cache[key]
                        if signature and cached and cached.signature == signature then
                            entry.metadata = cached.value
                        else
                            entry.metadata = LLL_METADATA.read(platform, entry.dir, entry.metadata_id)
                            metadata_cache[key] =
                                { signature = signature, value = entry.metadata }
                        end
                    end
                    local gated = root.kind == "mdl"
                        or (type(mdl.enabled) == "table" and mdl.enabled[entry.id] ~= nil)
                    local name = "live/" .. entry.id
                    if not seen[name] then
                        seen[name] = true
                        self.catalog[name] = entry
                        if
                            not gated
                            or (type(mdl.enabled) == "table" and mdl.enabled[entry.id] == true)
                        then
                            self.entries[name] = entry
                            names[#names + 1] = name
                        else
                            self.entries[name] = nil
                        end
                    end
                end
            end
        end
        for name in pairs(self.catalog) do
            if not seen[name] then self.catalog[name] = nil end
        end
        -- Discovery caches and recursive watches belong to the final catalog,
        -- not to an instance's frozen modules or cleanup ownership. Sweep only
        -- after a complete scan; unchanged idle scans return above.
        local metadata_keys, watched_paths = {}, {}
        for name, entry in pairs(self.catalog) do
            metadata_keys[entry.dir..'/'..(entry.metadata_id or '')] = true
            if entry.project then watched_paths[watch_key(entry.dir)] = true end
        end
        for _, root in ipairs(platform.roots or {{path=platform.live}}) do
            if root.path then watched_paths[watch_key(root.path)] = true end
        end
        for name, cached in pairs(sources) do
            local entry = self.catalog[name]
            if not entry or cached.path ~= entry.path then sources[name] = nil end
        end
        for name, cached in pairs(fingerprints) do
            local entry = self.catalog[name]
            if not entry or not entry.project or cached.path ~= entry.path then fingerprints[name] = nil end
        end
        for key in pairs(metadata_cache) do
            if not metadata_keys[key] then metadata_cache[key] = nil end
        end
        for path in pairs(project_watches) do
            if not watched_paths[watch_key(path)] then
                local ok, released = pcall(platform.unwatch, path)
                -- A failed release remains owned for a later full scan. Never
                -- add an idle retry or discard a potentially live backend watch.
                if ok and released == true then project_watches[path] = nil end
            end
        end
        last_names = names
        return names
    end
    function self.enabled(name)
        return self.entries[name] ~= nil
    end
    function self.auto_reload()
        if mdl.auto_reload ~= nil then
            return mdl.auto_reload ~= false
        end
        return not (type(mdl.ui) == "table" and mdl.ui.auto_reload == false)
    end
    function self.set_auto_reload(value)
        local previous = mdl.auto_reload
        mdl.auto_reload = value == true
        local ok, text = pcall(serialize, mdl)
        if
            not ok
            or not platform.loader_config
            or not platform.write(platform.loader_config, "return " .. text .. "\n")
        then
            mdl.auto_reload = previous
            return false, "Auto-reload preference could not be saved"
        end
        return true
    end
    function self.set_enabled(name, value)
        local entry = assert(self.catalog[name], "Unknown live script")
        local old = mdl.enabled
        mdl.enabled = mdl.enabled or {}
        local previous = mdl.enabled[entry.id]
        mdl.enabled[entry.id] = value == true
        local ok, text = pcall(serialize, mdl)
        if
            not ok
            or not platform.loader_config
            or not platform.write(platform.loader_config, "return " .. text .. "\n")
        then
            mdl.enabled[entry.id] = previous
            if not old then
                mdl.enabled = nil
            end
            return false, "Loader selection could not be saved"
        end
        self.entries[name] = value and entry or nil
        last_names = nil
        return true
    end
    function self.source(name, force)
        local entry = assert(self.catalog[name] or self.entries[name], "Unknown live mod")
        local stamp = platform.stat and platform.stat(entry.path)
        local cached = sources[name]
        if
            not force
            and stamp
            and cached
            and cached.path == entry.path
            and cached.stamp == stamp
        then
            return cached.text
        end
        local text = assert(platform.read(entry.path, 16777216), "Live source unreadable")
        local after = platform.stat and platform.stat(entry.path)
        if stamp and stamp == after then
            sources[name] = { path = entry.path, stamp = stamp, text = text }
        else
            sources[name] = nil
        end
        return text
    end
    function self.fingerprint(name,force)
        local entry=assert(self.catalog[name] or self.entries[name],"Unknown live mod")
        if not entry.project then
            -- Only backends guaranteeing source-write notifications may skip
            -- stamp checks. Preserve a consumed root event for catalog discovery
            -- if a fingerprint is requested before the next scan.
            if platform.source_notifications and platform.changed then
                if platform.changed(entry.source_root or entry.dir) then
                    sources={}
                    pending_root_change=true
                end
                local cached=sources[name]
                if not force and cached and cached.path==entry.path then return cached.text end
            end
            return self.source(name,force)
        end
        -- Each project has its own recursive watcher. Idle ticks must not walk
        -- every module or reopen manifests; forced reads still confirm edits.
        local changed = not platform.changed or platform.changed(entry.dir)
        if platform.changed and type(platform.unwatch) == 'function' then project_watches[entry.dir] = true end
        local cached = fingerprints[name]
        if not force and not changed and cached and cached.path == entry.path then
            return cached.value
        end
        local spec=assert(project.descriptor(platform,entry.dir),"LLL project manifest missing")
        local value=project.fingerprint(platform,entry,spec)
        fingerprints[name]={path=entry.path,value=value}
        return value
    end
    function self.restart_only(name)
        local entry=self.catalog[name] or self.entries[name]
        return entry and entry.project and entry.project.restart_only==true or false
    end
    function self.preflight(name)
        local entry = assert(self.catalog[name] or self.entries[name], "Unknown live mod")
        if entry.project then
            local spec=assert(project.descriptor(platform,entry.dir),"LLL project manifest missing")
            prepared[name]=project.snapshot(platform,entry,spec)
            return prepared[name].chunks[spec.entry]
        end
        local text=self.source(name,true)
        project.check_runtime(platform,text,entry.path)
        return assert(loadstring(text, "@" .. entry.path))
    end
    function self.load(name)
        local entry = assert(self.catalog[name] or self.entries[name])
        local definition
        if entry.project then
            if not prepared[name] then self.preflight(name)end
            local snapshot=prepared[name];prepared[name]=nil
            local value,context=project.instantiate(platform,entry,snapshot,report)
            definition=value
            if instances[name] and instances[name].retain_until_exit then retained_instances[#retained_instances+1]=instances[name]end
            instances[name]=context
        else definition = self.preflight(name)() end
        assert(type(definition) == "table", "Live mod must return a lifecycle table")
        if definition.live_lua_api == 1 then
            assert(type(definition.on_disable) == "function", "LLL live mod requires cleanup")
            local context=instances[name]
            if context then
                local disable=definition.on_disable
                definition.on_disable=function(...)
                    context.console_active=false
                    local done,why=disable(...)
                    if done~=false then context.release_console()end
                    return done,why
                end
                if definition.on_cleanup_poll then
                    local poll=definition.on_cleanup_poll
                    definition.on_cleanup_poll=function(...)
                        local done,why=poll(...);if done==true then context.release_console()end;return done,why
                    end
                end
            end
            return definition
        end
        assert(
            type(definition.on_enable) == "function",
            "Unsupported live lifecycle: expected LLL API 1 or MDL on_enable(context)"
        )
        local cleanups, globals = {}, {}
        local settings_path = platform.settings
            and platform.settings .. "/mdl_" .. entry.id .. ".lua"
        local settings = config(settings_path)
        if
            next(settings) == nil
            and type(mdl.settings) == "table"
            and type(mdl.settings[entry.id]) == "table"
        then
            for key, value in pairs(mdl.settings[entry.id]) do
                settings[key] = value
            end
        end
        local ctx = {
            api = 2,
            id = entry.id,
            dir = entry.dir,
            settings = settings,
            config_dir=instances[name] and instances[name].config_dir,
            config=instances[name] and instances[name].config,
            loader = rawget(_G, "CowboyBingusModLoader"),
        }
        function ctx.log(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            report(name, table.concat(parts, " "))
        end
        function ctx.on_cleanup(fn)
            assert(type(fn) == "function")
            cleanups[#cleanups + 1] = fn
        end
        function ctx.global(key, value)
            assert(type(key) == "string")
            local saved = globals[key]
            if not saved then
                saved = { previous = rawget(_G, key) }
                globals[key] = saved
            end
            saved.owned = value
            rawset(_G, key, value)
            return value
        end
        function ctx.set(key, value)
            local previous = settings[key]
            settings[key] = value
            local ok, text = pcall(serialize, settings)
            if
                not ok
                or not settings_path
                or not platform.write(settings_path, "return " .. text .. "\n")
            then
                settings[key] = previous
                error("Settings could not be saved")
            end
        end
        local cleanup_started, waiting, base_failure = false, false, nil
        local cleanup_index
        local function finish_cleanup()
            while cleanup_index and cleanup_index > 0 do
                local ok, done, why = pcall(cleanups[cleanup_index])
                if not ok then
                    error(done)
                end
                if done == false then
                    return false, why or "pending"
                end
                cleanup_index = cleanup_index - 1
            end
            cleanups = {}
            for key, saved in pairs(globals) do
                if rawget(_G, key) == saved.owned then
                    rawset(_G, key, saved.previous)
                end
            end
            globals = {}
            return true
        end
        local function poll_cleanup(dt)
            if not cleanup_started then
                return nil, "Cleanup was not started"
            end
            if waiting or base_failure then
                if type(definition.on_cleanup_poll) ~= "function" then
                    return nil, base_failure or "Deferred MDL cleanup requires on_cleanup_poll"
                end
                local done, why = definition.on_cleanup_poll(ctx, dt)
                if done ~= true then
                    return done, why
                end
                waiting = false
                base_failure = nil
            end
            return finish_cleanup()
        end
        local function disable()
            if cleanup_started then
                return false, "pending"
            end
            cleanup_started = true
            if instances[name] then instances[name].console_active=false end
            cleanup_index = #cleanups
            if definition.on_disable then
                local ok, done, why = pcall(definition.on_disable, ctx)
                if not ok then
                    base_failure = done
                    error(done)
                end
                if done == false then
                    waiting = true
                    return false, why or "pending"
                end
            end
            return finish_cleanup()
        end
        if instances[name] then ctx.on_cleanup(instances[name].release_console)end
        return {
            live_lua_api = 1,
            name = definition.name or definition.Name,
            author = definition.author or definition.Author,
            on_enable = function()
                return definition.on_enable(ctx)
            end,
            on_update = definition.on_update and function(dt)
                return definition.on_update(ctx, dt)
            end,
            on_disable = disable,
            on_cleanup_poll = poll_cleanup,
            mdl_context = ctx,
        }
    end
    function self.forget_removed(name)
        assert(not self.catalog[name], "Available script cannot be forgotten")
        self.entries[name], sources[name] = nil, nil
    end
    return self
end

end)()
local LLL_STATUS=(function()
-- Original read-only status page using MCM's public registration API.
return function(loader, discovery, report)
    local owner, handle, last
    local function display(value)
        return string.sub(string.gsub(tostring(value or ""), "[%c]", " "), 1, 500)
    end
    local function controls()
        local loaded, failed, skipped, disabled = 0, 0, 0, 0
        local rows = {}
        for _, name in ipairs(loader.order) do
            local state = loader.modules[name] or "unknown"
            if state == "loaded" then
                loaded = loaded + 1
            elseif state == "disabled" then
                disabled = disabled + 1
            elseif state == "not installed" then
                skipped = skipped + 1
            else
                failed = failed + 1
            end
            rows[#rows + 1] = {
                type = "text",
                label = display(name),
                description = display(
                    state
                        .. (
                            loader.records[name] and "; managed live lifecycle"
                            or "; restart required for reload"
                        )
                ),
            }
            rows[#rows + 1] = { type = "text", label = display("  " .. state) }
        end
        local summary = {
            { type = "section", label = "LIVE LUA LOADER R20" },
            {
                type = "text",
                label = "Loaded: "
                    .. loaded
                    .. "   Failed / pending: "
                    .. failed
                    .. "   Disabled: "
                    .. disabled
                    .. "   Not installed: "
                    .. skipped,
            },
            { type = "text", label = "Discovered archive addons: " .. discovery.count },
            { type = "text", label = "Source limit: 16 MB; live scans every 0.5 seconds" },
            {
                type = "text",
                label = "Loaded means initialization returned successfully.",
                description = "This does not prove gameplay behavior or rendering.",
            },
            { type = "text", label = display(discovery.diagnostics) },
            { type = "text", label = "Supported game build: 25480438" },
        }
        return summary, rows
    end
    local function refresh()
        local api = rawget(_G, "DBFMCM")
        if not api or type(api.register) ~= "function" then
            return
        end
        if api ~= owner then
            if handle then
                pcall(handle.unregister)
            end
            owner = api
            handle = nil
            last = nil
        end
        local summary, rows = controls()
        local signature = ""
        for _, list in ipairs({ summary, rows }) do
            for _, row in ipairs(list) do
                signature = signature .. row.label .. (row.description or "")
            end
        end
        if signature == last and handle then
            return
        end
        if not handle then
            handle = api.register({
                id = "live_lua_loader",
                name = "Live Lua Loader - Diagnostics",
                description = "R20: loader status and addon discovery diagnostics.",
                pages = {
                    { id = "overview", name = "Overview", controls = summary },
                    { id = "mods", name = "Mod status", controls = rows },
                },
            })
            report("LLL status", "MCM status page registered")
        else
            local mod = api.mods and api.mods.live_lua_loader
            if not mod then
                handle = nil
                last = nil
                return
            end
            mod.pages[1].controls = summary
            mod.pages[2].controls = rows
            api.revision = api.revision + 1
        end
        last = signature
    end
    return {
        refresh = refresh,
        close = function()
            if handle then
                pcall(handle.unregister)
                handle = nil
            end
        end,
    }
end

end)()
local LLL_PROVENANCE=(function()
-- Runtime ownership and discovery location are separate facts.
return function(loader, live, environment)
    environment = environment or _G
    local order, seen, rows = {}, {}, {}
    local function include(name)
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            order[#order + 1] = name
        end
    end
    for _, name in ipairs(loader.order or {}) do
        include(name)
    end
    local registries = {}
    for _, item in ipairs({
        { "mdl", environment.HD2ModLoader },
        { "bingus", environment.CowboyBingusModLoader },
    }) do
        local registry = item[2]
        if
            type(registry) == "table"
            and registry ~= loader
            and registry ~= loader.compatibility
            and registry.modules ~= loader.modules
            and registry.implementation ~= "Live Lua Loader"
            and type(registry.modules) == "table"
        then
            registries[item[1]] = registry
        end
    end
    if registries.mdl and registries.mdl == registries.bingus then
        registries = { unknown = registries.mdl }
    end
    local extra = {}
    for name in pairs(live.catalog or {}) do
        if type(name) == "string" then
            extra[#extra + 1] = name
        end
    end
    for _, registry in pairs(registries) do
        for name in pairs(registry.modules) do
            if type(name) == "string" then
                extra[#extra + 1] = name
            end
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        include(name)
    end
    for _, name in ipairs(order) do
        local entry = live.catalog[name]
        local owned = loader.origins and loader.origins[name]
        local reports = {}
        for kind, registry in pairs(registries) do
            local status = registry.modules[name]
            if type(status) == "string" then
                reports[#reports + 1] = { kind = kind, status = status, registry = registry }
            end
        end
        local owner, state = "unknown", loader.modules[name] or "discovered"
        local own = owned and (owned.owner == "lll_live" or owned.owner == "lll_archive")
        local active_reports = {}
        for _, report in ipairs(reports) do
            if report.status == "loaded" or report.status == "loading" then
                active_reports[#active_reports + 1] = report
            end
        end
        if
            #active_reports > 1
            or (own and (state == "loaded" or state == "loading") and #active_reports > 0)
        then
            state = "conflicting loader reports"
        elseif #active_reports == 1 then
            owner, state = active_reports[1].kind, active_reports[1].status
        elseif own then
            owner = owned.owner
        elseif owned and owned.registry then
            if
                registries[owned.owner] ~= nil
                and type(registries[owned.owner].modules[name]) == "string"
            then
                owner, state = owned.owner, registries[owned.owner].modules[name]
            else
                state = "unverified previous loader report"
            end
        elseif #reports == 1 then
            owner, state = reports[1].kind, reports[1].status
        elseif entry then
            owner = "lll_live"
            if state == "loaded" then
                owner, state = "unknown", "unverified loaded report"
            end
        end
        local source = entry
                and ((entry.kind or "unknown") .. " folder: " .. (entry.source_root or entry.dir or "unknown"))
            or (
                string.match(name, "^mods/cowboybingus/") and "Bingus-compatible archive resource"
                or "Archive or unknown source"
            )
        local declared = loader.records and loader.records[name]
        local metadata = entry and entry.metadata
        local author = metadata and (metadata.author or metadata.Author)
        if not author and type(declared) == "table" then
            author = declared.author or declared.Author
        end
        if not author then
            for _, report in ipairs(reports) do
                local record = report.registry.records and report.registry.records[name]
                if type(record) == "table" then author = record.author or record.Author end
                if author then break end
            end
        end
        author = type(author) == "string" and string.gsub(string.gsub(author, "^%s+", ""), "%s+$", "") or nil
        if author == "" then author = nil end
        local overrides=loader.get_loader_option and loader.get_loader_option("metadata_overrides") or {}
        local override=type(overrides)=="table" and overrides[name] or nil
        if type(override)=="table" and type(override.author)=="string" and override.author~="" then author=override.author end
        rows[#rows + 1] = {
            display_name=type(override)=="table" and override.name or (metadata and (metadata.name or metadata.Name)),
            description=type(override)=="table" and override.description or (metadata and metadata.description),
            name = name,
            author = author or "Unknown author",
            owner = owner,
            state = state,
            loaded = state == "loaded",
            source = source,
        }
    end
    return rows
end

end)()
local LLL_UI_PREFERENCES=(function()
-- Loader-owned manager preferences, shared by each frontend registration.
local M={}
M.defaults={menu_toggle_key=45,apply_key=9,focus_key=117,ui_scale=1,font_scale=1}
function M.get(loader)
    local saved=loader.get_loader_option and loader.get_loader_option("manager_ui") or {}
    if type(saved)~="table" then saved={} end
    local result={}
    for key,default in pairs(M.defaults) do result[key]=type(saved[key])=="number" and saved[key]==saved[key] and math.abs(saved[key])<math.huge and saved[key] or default end
    if result.menu_toggle_key%1~=0 or result.menu_toggle_key<7 or result.menu_toggle_key>255 or result.menu_toggle_key==27 or (result.menu_toggle_key>=16 and result.menu_toggle_key<=18) then result.menu_toggle_key=M.defaults.menu_toggle_key end
    for _,key in ipairs({"apply_key","focus_key"}) do
        local value=result[key]
        if value%1~=0 or value<7 or value>255 or value==27 or (value>=16 and value<=18) then result[key]=M.defaults[key] end
    end
    if result.apply_key==result.menu_toggle_key or result.focus_key==result.menu_toggle_key or result.apply_key==result.focus_key then result.apply_key,result.focus_key=9,117 end
    result.ui_scale=math.max(.75,math.min(1.5,result.ui_scale))
    result.font_scale=math.max(.8,math.min(1.3,result.font_scale))
    return result
end
function M.set(loader,key,value)
    if not M.defaults[key] then return false,"Unknown manager preference" end
    if type(value)~="number" or value~=value then return false,"Numeric manager preference required" end
    if (key=="menu_toggle_key" or key=="apply_key" or key=="focus_key") and (value%1~=0 or value<7 or value>255 or value==27 or (value>=16 and value<=18)) then return false,"Choose a non-mouse key other than Escape or a modifier" end
    if key=="ui_scale" and (value<.75 or value>1.5) or key=="font_scale" and (value<.8 or value>1.3) then return false,"Scale outside supported range" end
    if not loader.save_loader_option then return false,"Loader preference storage unavailable" end
    local values=M.get(loader)
    if key=="menu_toggle_key" or key=="apply_key" or key=="focus_key" then
        for _,other in ipairs({"menu_toggle_key","apply_key","focus_key"}) do if other~=key and values[other]==value then return false,"This key is already bound to another manager action" end end
    end
    values[key]=value
    local ok,why=loader.save_loader_option("manager_ui",values)
    if not ok then return false,why end
    if loader.manager_preferences_changed then loader.manager_preferences_changed(values) end
    if loader.changed then loader.changed() end
    return true
end
function M.page(loader)
    local values=M.get(loader)
    local controls={{type="section",label="MANAGER APPEARANCE"}}
    for _,item in ipairs({
        {"menu_toggle_key","Open / close",type="keybind"},
        {"apply_key","Confirm / Apply",type="keybind"},
        {"focus_key","Switch focus",type="keybind"},
        {"ui_scale","UI scale",min=.75,max=1.5,step=.05},
        {"font_scale","Font size",min=.8,max=1.3,step=.05},
    }) do
        local key=item[1]
        controls[#controls+1]={id="manager_"..key,label=item[2],type=item.type or "slider",default=M.defaults[key],min=item.min,max=item.max,step=item.step,
            disabled=not loader.save_loader_option,
            description="Saved in LLL.cfg; shared by the independent manager and MCM registration.",
            validate=function(value)local ok,why=M.set(loader,key,value);assert(ok,why);return true end}
    end
    controls[#controls+1]={id="manager_metadata_editing",type="toggle",label="Allow metadata edits",default=not loader.get_loader_option or loader.get_loader_option("metadata_editing")~=false,disabled=not loader.save_loader_option,
        description="Controls local Name, Author and Description overrides. Runtime owner and resource identity stay fixed.",
        validate=function(value)local ok,why=loader.save_loader_option("metadata_editing",value);assert(ok,why);return true end,
        on_change=function()if loader.changed then loader.changed() end end}
    controls[#controls+1]={id="manager_reset_window",type="button",label="Window placement",button_label="Reset window",disabled=not loader.save_loader_option,
        on_activate=function()
            local ok,why=loader.save_loader_option("manager_window",{});assert(ok,why)
            if loader.reset_manager_window then loader.reset_manager_window() end
            return "Window placement reset"
        end}
    return {id="manager_settings",name="Manager settings",dynamic=true,controls=controls}
end
return M

end)()
local LLL_CONTROLS=(function()
-- Both frontends bind this authoritative loader state; neither owns selection settings.
return function(loader, live, report)
    local self = { bindings = {}, groups = {}, group_count = 0, expanded = {} }
    local preferences=LLL_UI_PREFERENCES or dofile("src/ui/preferences.lua")
    local syncing = false
    local function status_label(value)
        local text = tostring(value or "unknown"):gsub("[%c]", " ")
        if #text > 512 then text = text:sub(1, 509) .. "..." end
        return text
    end
    local function readable(value)
        return string.gsub(string.gsub(string.gsub(value, "[_-]+", " "), "(%l)(%u)", "%1 %2"), "(%a)([%w]*)", function(a, b)
            return string.upper(a) .. b
        end)
    end
    local function folder(name)
        local entry = live.catalog[name]
        local metadata = entry and entry.metadata
        local declared = loader.records and loader.records[name]
        if LLL_METADATA then
            local fields = LLL_METADATA.fields(declared)
            if not (metadata and metadata.author) and fields.author then
                metadata = fields
            end
        end
        if metadata and metadata.author then
            return "declared/" .. metadata.author,
                metadata.author,
                metadata.name or string.match(name, "([^/]+)$")
        end
        local author, child = string.match(name, "^mods/([^/]+)/(.+)$")
        if author then
            return "mods/" .. author, author, metadata and metadata.name or child
        end
        local entry = live.catalog[name]
        if entry then
            local root = string.gsub(string.gsub((entry.source_root or entry.dir), "\\", "/"), "/+$", "")
            return root, string.match(root, "([^/]+)$") or root, metadata and metadata.name or entry.id
        end
        local parent, leaf = string.match(name, "^(.*)/([^/]+)$")
        if parent then
            return parent, string.match(parent, "([^/]+)$"), leaf
        end
        return nil, nil, name
    end
    local function definition()
        local categories = {}
        local seen = {}
        local pages = {
            {
                id = "overview",
                name = "Overview",
                dynamic = true,
                controls = {
                    { type = "section", label = "LIVE LUA LOADER R31" },
                    {
                        type = "button",
                        id = "open_manager",
                        label = "Loader window",
                        button_label = "Open manager",
                        on_activate = function()
                            assert(loader.open_manager, "Manager unavailable")
                            loader.open_manager()
                        end,
                    },
                    {
                        type = "button",
                        id = "refresh",
                        label = "Refresh discovery",
                        button_label = "Refresh",
                        on_activate = function()
                            loader.refresh()
                            self.refresh()
                            return "Discovery refreshed"
                        end,
                    },
                    {
                        type = "button", id = "clear_removed",
                        label = "Clear removed entries", button_label = "Clear",
                        disabled = not loader.clear_removed_entries,
                        description = "Forget missing scripts only after lifecycle ownership is released. Active and pending cleanup records remain. Saved settings and logs are retained.",
                        on_activate = function()
                            local removed, retained = loader.clear_removed_entries()
                            self.refresh()
                            return string.format("Cleared %d entries; retained %d owned entries", removed, retained)
                        end,
                    },
                    {
                        type = "toggle",
                        id = "auto_reload",
                        label = "Auto-reload Lua changes",
                        default = loader.auto_reload and loader.auto_reload() or false,
                        disabled = not loader.set_auto_reload,
                        description = "Reload enabled lifecycle scripts after an edit stays unchanged across two scans. Compile before cleanup; invalid edits preserve the working instance. Saved in LLL.cfg. Manual reload remains available.",
                        on_change = function(value)
                            local ok, why = loader.set_auto_reload(value)
                            assert(ok, why)
                            self.refresh()
                        end,
                    },
                    {
                        type = "text",
                        label = "Live scripts support enable, disable and reload. Archive addons without cleanup require a restart.",
                    },
                },
            },
        }
        for index, name in ipairs(loader.order) do
            local path, parent, child = folder(name)
            local category
            if path then
                if not self.groups[path] then
                    self.group_count = self.group_count + 1
                    self.groups[path] = "author_" .. self.group_count
                end
                category = self.groups[path]
                if not seen[category] then
                    seen[category] = true
                    categories[#categories + 1] = { id = category, name = parent }
                end
            end
            local target = name
            local id = "entry_" .. index
            local managed = live.catalog[name] ~= nil and not (live.restart_only and live.restart_only(name))
            local controls =
                { { type = "text", label = status_label(loader.modules[name]), description = name } }
            controls[#controls + 1] = {
                type = "toggle",
                id = id .. "_enabled",
                label = "Enabled",
                default = loader.modules[name] == "loaded",
                disabled = not managed,
                description = managed
                        and "Changes apply immediately and save to LLL.cfg. Disable runs cleanup."
                    or "Archive addon without a supported live lifecycle. Use your mod manager and restart.",
                on_change = function(value)
                    if syncing then
                        return
                    end
                    local ok, why = loader.set_enabled(target, value)
                    self.refresh()
                    if not ok then
                        report(target, "Selection refused: " .. tostring(why))
                        error(why)
                    end
                end,
            }
            controls[#controls + 1] = {
                type = "button",
                id = id .. "_reload",
                label = "Reload script",
                button_label = "Reload",
                disabled = not managed or loader.modules[name] ~= "loaded",
                description = "Compile first, clean up, then load the edited source. Unresolved cleanup requires restart.",
                on_activate = function()
                    local ok, why = loader.reload(target)
                    self.refresh()
                    assert(ok, why)
                    return "Reloaded " .. target
                end,
            }
            pages[#pages + 1] = {
                id = id,
                name = readable(child),
                category = category,
                dynamic = true,
                controls = controls,
            }
        end
        pages[#pages+1]=preferences.page(loader)
        return {
            id = "lll_management",
            name = "Live Lua Loader",
            description = "R30 mod manager. The configured shortcut opens the independent window (Insert by default). All changes use shared loader state.",
            categories = categories,
            pages = pages,
        }
    end
    local function author_pages(spec)
        local pages = { spec.pages[1] }
        local assigned = {}
        for _, category in ipairs(spec.categories) do
            local rows = {}
            for index = 2, #spec.pages do
                local page = spec.pages[index]
                if page.category == category.id then
                    assigned[index] = true
                    rows[#rows + 1] = { type = "section", label = page.name }
                    for _, control in ipairs(page.controls) do
                        rows[#rows + 1] = control
                    end
                end
            end
            pages[#pages + 1] = {
                id = category.id,
                name = category.name,
                style = "author",
                dynamic = true,
                controls = rows,
            }
        end
        local other = {}
        for index = 2, #spec.pages do
            if spec.pages[index].id=="manager_settings" then pages[#pages+1]=spec.pages[index]
            elseif not assigned[index] then
                local page = spec.pages[index]
                other[#other + 1] = { type = "section", label = page.name }
                for _, control in ipairs(page.controls) do
                    other[#other + 1] = control
                end
            end
        end
        if #other > 0 then
            pages[#pages + 1] =
                { id = "other_mods", name = "Other mods", dynamic = true, controls = other }
        end
        return { id = spec.id, name = spec.name, description = spec.description, pages = pages }
    end
    local function origin_pages(spec, keep_opener)
        local snapshot = (LLL_PROVENANCE or dofile("src/provenance.lua"))(loader, live)
        local overview = {}
        for key, value in pairs(spec.pages[1]) do overview[key] = value end
        overview.controls = {}
        for _, control in ipairs(spec.pages[1].controls) do
            if keep_opener or control.id ~= "open_manager" then
                overview.controls[#overview.controls + 1] = control
            end
        end
        local pages, categories, by_name = { overview }, {}, {}
        for index = 2, #spec.pages do
            if spec.pages[index].id=="manager_settings" then pages[#pages+1]=spec.pages[index]
            else by_name[spec.pages[index].controls[1].description] = spec.pages[index] end
        end
        local groups = {
            { "lll_live", "LLL live scripts" },
            { "lll_archive", "Archive addons via LLL" },
            { "mdl", "MDL registry" },
            { "bingus", "Bingus registry" },
            { "unknown", "Unknown / conflicting owner" },
        }
        for _, group in ipairs(groups) do
            local count, loaded = 0, 0
            for _, row in ipairs(snapshot) do
                if row.owner == group[1] then
                    count = count + 1
                    if row.loaded then
                        loaded = loaded + 1
                    end
                end
            end
            if count > 0 then
                categories[#categories + 1] = {
                    id = "source_" .. group[1],
                    name = group[2] .. " (" .. loaded .. " loaded / " .. count .. ")",
                }
            end
        end
        self.author_categories = self.author_categories or {}
        local authors = {}
        for _, row in ipairs(snapshot) do
            local key = row.owner .. "/" .. row.author
            if not authors[key] then
                if not self.author_categories[key] then
                    self.author_category_count = (self.author_category_count or 0) + 1
                    self.author_categories[key] = "source_author_" .. self.author_category_count
                end
                authors[key] = self.author_categories[key]
                categories[#categories + 1] = {
                    id = authors[key], parent = "source_" .. row.owner, name = row.author,
                }
            end
        end
        for index, row in ipairs(snapshot) do
            local old = by_name[row.name]
            self.external_ids = self.external_ids or {}
            if not old and not self.external_ids[row.name] then
                self.external_count = (self.external_count or 0) + 1
                self.external_ids[row.name] = "external_" .. self.external_count
            end
            local details = "Author: " .. row.author .. "\nRuntime owner: "
                .. row.owner
                .. "\nSource: "
                .. row.source
                .. "\nDescription: " .. (row.description or "") .. "\nResource: "
                .. row.name
            local controls = {
                { type = "text", label = status_label("Status: " .. row.state),
                    description = details .. "\nStatus: " .. tostring(row.state):sub(1, 32000) },
                {
                    type = "text",
                    label = "Source: " .. row.source,
                    description = "Discovery location is not evidence of which loader ran the mod.",
                },
            }
            local managed = old and live.catalog[row.name] and (row.owner == "lll_live") and not (live.restart_only and live.restart_only(row.name))
            if old then
                for position = 2, #old.controls do
                    local copy = {}
                    for key, value in pairs(old.controls[position]) do
                        copy[key] = value
                    end
                    if copy.type == "toggle" then
                        copy.default = row.loaded
                    end
                    if not managed then
                        copy.disabled = true
                    end
                    controls[#controls + 1] = copy
                end
            end
            local short = row.loaded and "Loaded"
                or row.state == "loading" and "Loading"
                or row.state == "disabled" and "Disabled"
                or row.state == "not installed" and "Not installed"
                or row.state == "discovered" and "Discovered"
                or "Needs attention"
            pages[#pages + 1] = {
                id = old and old.id or self.external_ids[row.name],
                resource_id = row.name,
                name = "[" .. short .. "] " .. (row.display_name or (old and old.name) or readable(
                    string.match(row.name, "([^/]+)$") or row.name
                )),
                category = authors[row.owner .. "/" .. row.author],
                dynamic = true,
                controls = controls,
            }
        end
        return {
            id = spec.id,
            name = spec.name,
            description = spec.description,
            categories = categories,
            pages = pages,
        }
    end
    function self.provenance_snapshot()
        return (LLL_PROVENANCE or dofile("src/provenance.lua"))(loader, live)
    end
    -- Both frontends consume fresh rows from the same ownership/status model.
    loader.provenance_snapshot = self.provenance_snapshot
    function self.provenance_summary()
        local rows = (LLL_PROVENANCE or dofile("src/provenance.lua"))(loader, live)
        local count = 0
        for _, row in ipairs(rows) do
            if row.loaded then
                count = count + 1
            end
        end
        return "Loaded: " .. count .. "   Listed: " .. #rows
    end
    function self.summary()
        local loaded, failed = 0, 0
        for _, name in ipairs(loader.order) do
            local state = loader.modules[name]
            if state == "loaded" then
                loaded = loaded + 1
            elseif state ~= "disabled" and state ~= "not installed" then
                failed = failed + 1
            end
        end
        return "Loaded: "
            .. loaded
            .. "   Failed / pending: "
            .. failed
            .. "   Total: "
            .. #loader.order
    end
    local function enclosed(spec)
        local rows = {
            spec.pages[1].controls[1],
            spec.pages[1].controls[2],
            spec.pages[1].controls[3],
            spec.pages[1].controls[4],
        }
        local function child(page)
            local target = page.id
            rows[#rows + 1] = {
                type = "button",
                id = "select_" .. target,
                label = "    " .. page.name,
                button_label = "Select",
                description = (page.controls[1].description or "") .. "\n" .. page.controls[1].label,
                on_activate = function()
                    self.selected = target
                    self.refresh()
                end,
            }
            if self.selected == target then
                for _, control in ipairs(page.controls) do
                    rows[#rows + 1] = control
                end
            end
        end
        for _, category in ipairs(spec.categories) do
            local target = category.id
            rows[#rows + 1] = {
                type = "button",
                id = "expand_" .. target,
                label = category.name,
                button_label = self.expanded[target] and "[-]" or "[+]",
                on_activate = function()
                    self.expanded[target] = not self.expanded[target]
                    self.refresh()
                end,
            }
            if self.expanded[target] then
                for index = 2, #spec.pages do
                    local page = spec.pages[index]
                    if page.category == target then
                        child(page)
                    end
                end
            end
        end
        for index = 2, #spec.pages do
            if not spec.pages[index].category then
                child(spec.pages[index])
            end
        end
        local loaded, failed, disabled, missing = 0, 0, 0, 0
        for _, name in ipairs(loader.order) do
            local state = loader.modules[name]
            if state == "loaded" then
                loaded = loaded + 1
            elseif state == "disabled" then
                disabled = disabled + 1
            elseif state == "not installed" then
                missing = missing + 1
            else
                failed = failed + 1
            end
        end
        rows[#rows + 1] = { type = "section", label = "Loader status" }
        rows[#rows + 1] = {
            type = "text",
            label = "Loaded: " .. loaded .. "   Failed / pending: " .. failed,
            description = "Counts reflect loader lifecycle state. Successful initialization does not prove gameplay behavior. Select a mod above for its current status and source path.",
        }
        rows[#rows + 1] = {
            type = "text",
            label = "Disabled: "
                .. disabled
                .. "   Not installed: "
                .. missing
                .. "   Total: "
                .. #loader.order,
        }
        rows[#rows + 1] = {
            type = "text",
            label = "Discovery diagnostics",
            description = loader.discovery_diagnostics
                or "Archive and live-script discovery; Refresh checks for new scripts.",
        }
        return {
            id = spec.id,
            name = spec.name,
            description = spec.description,
            pages = { { id = "mods", name = "Mods", dynamic = true, controls = rows } },
        }
    end
    function self.bind(api, inside)
        if not api or type(api.register) ~= "function" then
            return
        end
        for _, binding in ipairs(self.bindings) do
            if binding.api == api then
                if inside then
                    binding.inside = inside
                    binding.signature = nil
                end
                return binding
            end
        end
        local binding = { api = api, inside = inside }
        self.bindings[#self.bindings + 1] = binding
        return binding
    end
    function self.follow(api)
        if self.provider == api then
            return
        end
        if self.provider then
            for index = #self.bindings, 1, -1 do
                local binding = self.bindings[index]
                if binding.api == self.provider then
                    if binding.handle then
                        pcall(binding.handle.unregister)
                    end
                    table.remove(self.bindings, index)
                end
            end
        end
        self.provider = api
        self.bind(api, "origins_mcm")
    end
    local last_refresh_mark
    local function refresh_mark()
        local parts={tostring(self.selected),tostring(loader.discovery_diagnostics)}
        for key,value in pairs(self.expanded)do parts[#parts+1]="expanded:"..key.."="..tostring(value)end
        for _,row in ipairs(self.provenance_snapshot() or {})do
            for _,key in ipairs({"name","state","owner","source","author","display_name","description"})do
                local value=tostring(row[key]);parts[#parts+1]=#value..":"..value
            end
        end
        for key,value in pairs(preferences.get(loader))do parts[#parts+1]=key.."="..tostring(value)end
        parts[#parts+1]="auto="..tostring(loader.auto_reload and loader.auto_reload())
        for _,binding in ipairs(self.bindings)do
            parts[#parts+1]=tostring(binding.api)..tostring(binding.handle)..tostring(binding.inside)
            local mod=binding.api.mods and binding.api.mods.lll_management
            parts[#parts+1]=tostring(mod)
            for key,value in pairs(mod and mod.values or {})do parts[#parts+1]=key.."="..tostring(value)end
        end
        table.sort(parts);return table.concat(parts,"|")
    end
    function self.refresh()
        if last_refresh_mark==refresh_mark() then return end
        local spec = definition()
        local signature = ""
        for _, group in ipairs(spec.categories) do
            signature = signature .. group.id .. group.name
        end
        for _, page in ipairs(spec.pages) do
            signature = signature .. page.id .. page.name .. (page.category or "")
        end
        for _, binding in ipairs(self.bindings) do
            local api = binding.api
            local bound_spec = spec
            local bound_signature = signature
            if binding.inside then
                bound_spec = (binding.inside == "origins" or binding.inside == "origins_mcm") and origin_pages(spec, binding.inside == "origins_mcm")
                    or binding.inside == "authors" and author_pages(spec)
                    or enclosed(spec)
                bound_signature = ""
                for _, category in ipairs(bound_spec.categories or {}) do
                    bound_signature = bound_signature .. category.id .. category.name
                end
                for _, page in ipairs(bound_spec.pages) do
                    bound_signature = bound_signature
                        .. page.id
                        .. page.name
                        .. (page.category or "")
                    for _, control in ipairs(page.controls) do
                        bound_signature = bound_signature
                            .. (control.id or "")
                            .. control.label
                            .. (control.button_label or "")
                            .. tostring(control.disabled)
                            .. tostring(control.default)
                    end
                end
            end
            if
                binding.signature ~= bound_signature
                or not binding.handle
                or not (api.mods and api.mods.lll_management)
            then
                if binding.handle then
                    pcall(binding.handle.unregister)
                end
                local ok, handle = pcall(api.register, bound_spec)
                if ok then
                    binding.handle = handle
                    binding.signature = bound_signature
                else
                    report("LLL manager", tostring(handle))
                end
            end
            local mod = api.mods and api.mods.lll_management
            local dirty = false
            local function assign(target,key,value)
                if target[key] ~= value then target[key]=value;dirty=true end
            end
            if mod and binding.handle then
                local values=preferences.get(loader)
                for key,value in pairs(values) do
                    local control=mod.controls["manager_"..key]
                    if control then assign(mod.values,control.id,value) end
                end
            end
            if mod and binding.handle and not binding.inside then
                syncing = true
                if mod.controls.auto_reload then
                    assign(mod.values,"auto_reload",loader.auto_reload and loader.auto_reload() or false)
                end
                for index, name in ipairs(loader.order) do
                    local page = mod.pages[index + 1]
                    local toggle = mod.controls["entry_" .. index .. "_enabled"]
                    local reload = mod.controls["entry_" .. index .. "_reload"]
                    assign(page.controls[1],"label",status_label(loader.modules[name]))
                    assign(toggle,"disabled",live.catalog[name] == nil or (live.restart_only and live.restart_only(name)))
                    assign(reload,"disabled",live.catalog[name] == nil or loader.modules[name] ~= "loaded" or (live.restart_only and live.restart_only(name)))
                    -- Native core rejects writes to disabled controls; update read-only display directly.
                    assign(mod.values,toggle.id,loader.modules[name] == "loaded")
                end
                syncing = false
                if dirty then api.revision = api.revision + 1 end
            end
        end
        last_refresh_mark=refresh_mark()
    end
    function self.primary()
        local api = self.provider
        local mod = api and api.mods and api.mods.lll_management
        if not mod then
            return
        end
        if type(api.surface) ~= "function" then
            return mod
        end
        local surface = api.surface(mod.handle)
        local copy = {}
        for key, value in pairs(mod) do
            copy[key] = value
        end
        copy.handle = {
            get = surface.get,
            preview = surface.preview,
            set = surface.set,
            edit = surface.set,
            queue = surface.activate,
            activate = surface.activate,
            confirm = surface.confirm,
            discard = surface.discard,
            reset = function(key)
                return surface.set(key, mod.controls[key].default)
            end,
        }
        return copy
    end
    function self.close()
        for _, b in ipairs(self.bindings) do
            if b.handle then
                pcall(b.handle.unregister)
            end
        end
        self.bindings = {}
    end
    loader.changed = self.refresh
    return self
end

end)()
local LLL_UI_CORE=(function()
-- Public, renderer-independent registration and persistence API.
local M = {}
local function id(s)
    assert(type(s) == "string" and #s <= 80 and string.match(s, "^[%w_-]+$"), "Invalid stable ID")
    return s
end
local function plain(s)
    assert(type(s) == "string" and #s <= 512 and not string.find(s, "[%c]"), "Invalid display text")
    return s
end
local function rich(s)
    if type(s) == "table" then
        local blocks = {}
        for _, block in ipairs(s) do
            assert(type(block) == "string", "Text blocks must be strings")
            blocks[#blocks + 1] = block
        end
        s = table.concat(blocks, "\n\n")
    end
    assert(
        type(s) == "string" and #s <= 65536 and not string.find(s, "[%z\1-\8\11\12\14-\31]"),
        "Invalid rich text"
    )
    return s
end
local function copy(t)
    local r = {}
    for k, v in pairs(t) do
        r[k] = v
    end
    return r
end
function M.color_hex(v)
    if type(v) == "string" then
        local hex = string.gsub(v, "^#", "")
        assert(#hex == 6 and string.match(hex, "^%x+$"), "Use six HEX digits")
        return "#" .. string.upper(hex)
    end
    assert(type(v) == "table", "Expected HEX or RGB table")
    local parts = { v.r or v[1], v.g or v[2], v.b or v[3] }
    for _, n in ipairs(parts) do
        assert(
            type(n) == "number" and n % 1 == 0 and n >= 0 and n <= 255,
            "RGB channels must be integers 0-255"
        )
    end
    assert(#parts == 3, "Three RGB channels required")
    return string.format("#%02X%02X%02X", parts[1], parts[2], parts[3])
end
function M.color_rgb(v)
    local hex = M.color_hex(v)
    return { tonumber(string.sub(hex, 2, 3), 16), tonumber(string.sub(hex, 4, 5), 16), tonumber(string.sub(hex, 6, 7), 16) }
end
function M.hsv_rgb(h, s, v)
    local sector = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local low = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local colors =
        { { v, t, low }, { q, v, low }, { low, v, t }, { low, q, v }, { t, low, v }, { v, low, q } }
    local c = colors[sector + 1]
    return {
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5),
    }
end
function M.rgb_hsv(rgb)
    local r, g, b = rgb[1] / 255, rgb[2] / 255, rgb[3] / 255
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    local delta = hi - lo
    local h = 0
    if delta > 0 then
        if hi == r then
            h = ((g - b) / delta) % 6
        elseif hi == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
    end
    return h, hi == 0 and 0 or delta / hi, hi
end
local function normalize(c, v)
    if c.type == "input" then
        if c.free_text then
            assert(type(v)=="string" and #v<=(c.max_length or 512) and not string.find(v,"[%c]"),"Metadata text exceeds its limit or contains control characters")
            return v
        end
        assert(
            type(v) == "string" and #v <= 48 and string.match(v, "^[%w _-]+$"),
            "Use letters, numbers, spaces, underscores or hyphens"
        )
        return v
    end
    if c.type == "color" then
        return M.color_hex(v)
    end
    if c.type == "toggle" then
        assert(type(v) == "boolean", "Expected boolean")
        return v
    end
    assert(type(v) == "number" and v == v and math.abs(v) < 1e12, "Expected finite number")
    if c.type == "slider" then
        assert(v >= c.min and v <= c.max, "Value outside slider range")
        return math.min(c.max, c.min + math.floor((v - c.min) / c.step + 0.5) * c.step)
    end
    if c.type == "choice" then
        assert(v % 1 == 0 and v >= 1 and v <= #c.choices, "Invalid choice")
        return v
    end
    if c.type == "keybind" then
        assert(v % 1 == 0 and v >= 0 and v <= 255, "Invalid virtual key")
        return v
    end
    error("Control has no stored value")
end
local function stored(c)
    return c.type == "input"
        or c.type == "toggle"
        or c.type == "slider"
        or c.type == "choice"
        or c.type == "keybind"
        or c.type == "color"
end
function M.new(store, log)
    local api = {
        api = 1,
        version = "0.1.30",
        color_hex = M.color_hex,
        color_rgb = M.color_rgb,
        hsv_rgb = M.hsv_rgb,
        rgb_hsv = M.rgb_hsv,
        mods = {},
        revision = 0,
    }
    log = log or function() end
    local palette = store and store.load("mcm_custom_palette") or {}
    local swatches = {}
    for i = 1, 12 do
        local ok, v = pcall(M.color_hex, palette["swatch_" .. i])
        if ok then
            swatches[#swatches + 1] = v
        end
    end
    function api.swatches()
        return copy(swatches)
    end
    function api.save_swatch(value)
        value = M.color_hex(value)
        for _, existing in ipairs(swatches) do
            if existing == value then
                return true
            end
        end
        local next_colors = copy(swatches)
        if #next_colors == 12 then
            table.remove(next_colors, 1)
        end
        next_colors[#next_colors + 1] = value
        local values = {}
        for i, v in ipairs(next_colors) do
            values["swatch_" .. i] = v
        end
        if store then
            local ok, err = store.save("mcm_custom_palette", values)
            if not ok then
                return false, err
            end
        end
        swatches = next_colors
        return true
    end
    function api.replace_swatch(index, value)
        assert(type(index) == "number" and index % 1 == 0 and swatches[index], "Unknown swatch")
        value = M.color_hex(value)
        local next_colors = copy(swatches)
        next_colors[index] = value
        local values = {}
        for i, v in ipairs(next_colors) do
            values["swatch_" .. i] = v
        end
        if store then
            local ok, err = store.save("mcm_custom_palette", values)
            if not ok then
                return false, err
            end
        end
        swatches = next_colors
        return true
    end
    function api.register(spec)
        assert(type(spec) == "table", "Expected mod definition")
        id(spec.id)
        plain(spec.name)
        assert(not api.mods[spec.id], "Mod already registered; unregister before replacing")
        local mod = {
            id = spec.id,
            name = spec.name,
            description = rich(spec.description or ""),
            pages = {},
            categories = {},
            controls = {},
            values = {},
            on_change = spec.on_change,
        }
        local categories = {}
        for _, category in ipairs(spec.categories or {}) do
            id(category.id)
            assert(not categories[category.id], "Duplicate category")
            local c = { id = category.id, name = plain(category.name), parent = category.parent }
            if c.parent then
                id(c.parent)
            end
            categories[c.id] = c
            mod.categories[#mod.categories + 1] = c
        end
        for _, c in ipairs(mod.categories) do
            local seen = { [c.id] = true }
            local parent = c.parent
            while parent do
                assert(categories[parent], "Unknown parent category")
                assert(not seen[parent], "Category cycle")
                seen[parent] = true
                parent = categories[parent].parent
            end
        end
        assert(type(spec.pages) == "table" and #spec.pages > 0, "At least one page required")
        local saved = store and store.load(mod.id) or {}
        local pages = {}
        for _, definition in ipairs(spec.pages) do
            id(definition.id)
            assert(not pages[definition.id], "Duplicate page")
            pages[definition.id] = true
            assert(
                definition.require_confirmation == nil
                    or type(definition.require_confirmation) == "boolean",
                "require_confirmation must be boolean"
            )
            assert(
                definition.category == nil or categories[definition.category],
                "Unknown page category"
            )
            local page = {
                category = definition.category,
                id = definition.id,
                resource_id = definition.resource_id,
                name = plain(definition.name),
                render_preview = definition.render_preview,
                controls = {},
                require_confirmation = definition.dynamic ~= true
                    and definition.require_confirmation ~= false,
                pending = {},
                actions = {},
            }
            for _, definition_control in ipairs(definition.controls or {}) do
                local c = copy(definition_control)
                c.page = page
                plain(c.label or "")
                c.description = rich(c.description or "")
                assert(
                    ({
                        input = true,
                        color = true,
                        toggle = true,
                        slider = true,
                        choice = true,
                        keybind = true,
                        button = true,
                        text = true,
                        section = true,
                    })[c.type],
                    "Unsupported control"
                )
                assert(c.column == nil or c.column == 1 or c.column == 2, "Column must be 1 or 2")
                if c.type ~= "text" and c.type ~= "section" then
                    id(c.id)
                    assert(not mod.controls[c.id], "Duplicate control ID")
                    mod.controls[c.id] = c
                end
                if c.type == "slider" then
                    assert(
                        type(c.min) == "number"
                            and type(c.max) == "number"
                            and type(c.step) == "number"
                            and c.min == c.min
                            and c.max == c.max
                            and c.step == c.step
                            and math.abs(c.min) < 1e12
                            and math.abs(c.max) < 1e12
                            and c.max > c.min
                            and c.step > 0
                            and c.step <= c.max - c.min,
                        "Invalid slider"
                    )
                elseif c.type == "choice" then
                    assert(
                        c.presentation == nil
                            or c.presentation == "dropdown"
                            or c.presentation == "selector"
                            or c.presentation == "combined",
                        "Invalid choice presentation"
                    )
                    assert(type(c.choices) == "table" and #c.choices > 0, "Choices required")
                    c.choices = copy(c.choices)
                    for _, label in ipairs(c.choices) do
                        plain(label)
                    end
                elseif c.type == "button" then
                    assert(type(c.on_activate) == "function", "Button callback required")
                end
                if stored(c) then
                    c.default = normalize(c, c.default)
                    local ok, value = pcall(normalize, c, saved[c.id])
                    if ok then
                        mod.values[c.id] = value
                    else
                        mod.values[c.id] = c.default
                    end
                end
                page.controls[#page.controls + 1] = c
            end
            mod.pages[#mod.pages + 1] = page
        end
        api.mods[mod.id] = mod
        api.revision = api.revision + 1
        local handle = { id = mod.id }
        function handle.get(key)
            assert(mod.controls[key], "Unknown control")
            return mod.values[key]
        end
        function handle.set(key, value)
            assert(api.mods[mod.id] == mod, "Retired registration")
            local c = assert(mod.controls[key], "Unknown control")
            assert(stored(c), "Control is not a setting")
            assert(not c.disabled, "Control disabled")
            value = normalize(c, value)
            if c.validate then
                assert(c.validate(value) ~= false, "Value rejected by mod")
            end
            if value == mod.values[key] then
                return true
            end
            local next_values = copy(mod.values)
            next_values[key] = value
            if store then
                local ok, err = store.save(mod.id, next_values)
                if not ok then
                    return false, err
                end
            end
            local old = mod.values[key]
            mod.values = next_values
            for _, callback in ipairs({ c.on_change or false, mod.on_change or false }) do
                if callback then
                    local ok, err = pcall(callback, value, key, old)
                    if not ok then
                        log("Callback failed for " .. mod.id .. "." .. key .. ": " .. tostring(err))
                    end
                end
            end
            api.revision = api.revision + 1
            return true
        end
        function handle.preview(key)
            local c = assert(mod.controls[key], "Unknown control")
            local pending = c.page.pending
            if pending[key] ~= nil then
                return pending[key]
            end
            return handle.get(key)
        end
        function handle.edit(key, value)
            assert(api.mods[mod.id] == mod, "Retired registration")
            local c = assert(mod.controls[key], "Unknown control")
            if not c.page.require_confirmation then
                return handle.set(key, value)
            end
            assert(stored(c) and not c.disabled, "Setting unavailable")
            value = normalize(c, value)
            if c.validate then
                assert(c.validate(value) ~= false, "Value rejected by mod")
            end
            if value == handle.get(key) then
                c.page.pending[key] = nil
            else
                c.page.pending[key] = value
            end
            return true
        end
        local function page_by_id(page_id)
            assert(api.mods[mod.id] == mod, "Retired registration")
            for _, p in ipairs(mod.pages) do
                if p.id == page_id then
                    return p
                end
            end
            error("Unknown page")
        end
        function handle.queue(key)
            assert(api.mods[mod.id] == mod, "Retired registration")
            local c = assert(mod.controls[key], "Unknown control")
            assert(c.type == "button" and not c.disabled, "Button unavailable")
            if not c.page.require_confirmation then
                return handle.activate(key)
            end
            c.page.actions[key] = true
            return true
        end
        function handle.discard(page_id)
            local p = page_by_id(page_id)
            p.pending = {}
            p.actions = {}
            return true
        end
        function handle.confirm(page_id)
            local p = page_by_id(page_id)
            local next_values = copy(mod.values)
            local changes = {}
            for _, c in ipairs(p.controls) do
                local v = p.pending[c.id]
                if v ~= nil then
                    assert(not c.disabled, "Setting disabled")
                    v = normalize(c, v)
                    if c.validate then
                        assert(c.validate(v) ~= false, "Value rejected by mod")
                    end
                    if v ~= mod.values[c.id] then
                        next_values[c.id] = v
                        changes[#changes + 1] = { c = c, v = v, old = mod.values[c.id] }
                    end
                end
                if p.actions[c.id] then
                    assert(not c.disabled, "Action disabled")
                end
            end
            if #changes > 0 and store then
                local ok, err = store.save(mod.id, next_values)
                if not ok then
                    return false, err
                end
            end
            mod.values = next_values
            p.pending = {}
            for _, change in ipairs(changes) do
                for _, callback in ipairs({ change.c.on_change or false, mod.on_change or false }) do
                    if callback then
                        local ok, err = pcall(callback, change.v, change.c.id, change.old)
                        if not ok then
                            log("Callback failed: " .. tostring(err))
                        end
                    end
                end
            end
            local actions = p.actions
            p.actions = {}
            api.revision = api.revision + 1
            local messages = {}
            for _, c in ipairs(p.controls) do
                if actions[c.id] then
                    local ok, result = handle.activate(c.id)
                    if not ok then
                        return false, result
                    end
                    if type(result) == "string" and #result > 0 then
                        messages[#messages + 1] = result
                    end
                end
            end
            return true, #messages > 0 and table.concat(messages, "; ") or nil
        end
        function handle.reset(key)
            return handle.set(key, assert(mod.controls[key], "Unknown control").default)
        end
        function handle.activate(key)
            local c = assert(mod.controls[key], "Unknown control")
            assert(c.type == "button" and not c.disabled, "Button unavailable")
            return pcall(c.on_activate)
        end
        function handle.unregister()
            if api.mods[mod.id] == mod then
                api.mods[mod.id] = nil
                api.revision = api.revision + 1
            end
        end
        mod.handle = handle
        return handle
    end
    function api.list()
        local list = {}
        for _, mod in pairs(api.mods) do
            if not mod.hidden then
                list[#list + 1] = mod
            end
        end
        table.sort(list, function(a, b)
            if a.name == b.name then
                return a.id < b.id
            end
            return a.name < b.name
        end)
        return list
    end
    function api.get(mod, key)
        local m = assert(api.mods[mod], "Unknown mod")
        return m.handle.get(key)
    end
    function api.set(mod, key, value)
        local m = assert(api.mods[mod], "Unknown mod")
        return m.handle.set(key, value)
    end
    return api
end
return M

end)()
local LLL_UI_THEME=(function()
-- UI colors and readable key labels.
local M={}
M.palette = {
    background = { 12, 14, 16 },
    panel = { 19, 21, 23 },
    header = { 25, 27, 29 },
    border = { 62, 66, 69 },
    border_hover = { 106, 111, 114 },
    line = { 34, 37, 40 },
    white = { 234, 235, 228 },
    muted = { 154, 159, 159 },
    brass = { 221, 184, 105 },
    focus = { 244, 202, 53 },
    hover = { 29, 31, 33 },
    selected = { 43, 39, 24 },
    text_selection = { 48, 117, 158 },
    field = { 29, 31, 34 },
    field_hover = { 39, 42, 45 },
    enabled = { 176, 205, 176 },
    disabled = { 105, 111, 113 },
}
-- Match Epic workspace hierarchy while retaining the loader font-scale preference.
M.typography={body=18,heading=21,title=27,hint=16}
function M.key_name(code)
    local names={[8]='Backspace',[9]='Tab',[13]='Enter',[16]='Shift',[17]='Ctrl',[18]='Alt',[27]='Esc',[32]='Space',
        [33]='Page Up',[34]='Page Down',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',[45]='Insert',[46]='Del'}
    if names[code]then return names[code]end
    if code>=48 and code<=90 then return string.char(code)end
    if code>=112 and code<=135 then return 'F'..tostring(code-111)end
    if code>=96 and code<=105 then return 'Num '..tostring(code-96)end
    return 'VK '..tostring(code)
end

M.layers={shell=90,row=95,focus=99,control=100,control_frame=101,fill=102,indicator=103,text_control=108,preview=110,popup=200,picker=300,console=400}
function M.overlay_layer(command,base)
    return base+(command.type=="text" and 8 or command.ui_role=="indicator" and 3 or command.ui_role=="fill" and 2 or command.ui_role=="control_frame" and 1 or command.ui_role=="frame" and -11 or command.ui_role=="surface" and -10 or command.ui_role=="selection" and -5 or 0)
end
function M.depth(command)
    return (command.layer or M.layers.control)+(command.type=="text" and 1 or 0)
end
return M

end)()
local LLL_UI_GEOMETRY=(function()
-- Logical window dimensions plus physical viewport bounds; no native input operations.
local M = {}
local function number(value, fallback)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge and value or fallback
end
function M.bounds(w, h, width, height, x, y, ui_scale)
    local preference=math.max(.75,math.min(1.5,number(ui_scale,1)))
    local s = math.min(math.min(w / 1920, h / 1080)*preference,w/1100,h/660)
    local W = math.max(1100, math.min(w / s, number(width,1500)))
    local H = math.max(660, math.min(h / s, number(height,820)))
    local ox = math.max(0, math.min(w-W*s, number(x,(w-W*s)/2)))
    local oy = math.max(0, math.min(h-H*s, number(y,(h-H*s)/2)))
    return {width=W,height=H,x=ox,y=oy,scale=s,viewport_width=w,viewport_height=h,ui_scale=preference}
end
function M.drag(g, edge, dx, dy)
    local W,H,x,y = g.width,g.height,g.x,g.y
    if string.find(edge,"left",1,true) then W=W-dx/g.scale end
    if string.find(edge,"right",1,true) then W=W+dx/g.scale end
    if string.find(edge,"bottom",1,true) then H=H-dy/g.scale end
    if string.find(edge,"top",1,true) then H=H+dy/g.scale end
    local next = M.bounds(g.viewport_width,g.viewport_height,W,H,x,y,g.ui_scale)
    if string.find(edge,"left",1,true) then next.x=x+(g.width-next.width)*g.scale end
    if string.find(edge,"bottom",1,true) then next.y=y+(g.height-next.height)*g.scale end
    return M.bounds(g.viewport_width,g.viewport_height,next.width,next.height,next.x,next.y,g.ui_scale)
end
return M

end)()
local LLL_UI_TEXT=(function()
-- UTF-8 layout and rich text; no native resources or input.
local M = {}
-- Whole-glyph viewport: never split UTF-8 or draw outside the allotted width.
function M.flow(value, width, size, time, measure)
    local glyphs = {}
    for glyph in string.gmatch(tostring(value), "[%z\1-\127\194-\244][\128-\191]*") do
        glyphs[#glyphs + 1] = glyph
    end
    local widths, total = {}, 0
    for i, g in ipairs(glyphs) do
        widths[i] = (measure and measure(g, size)) or size * 0.62
        total = total + widths[i]
    end
    if total <= width then
        return tostring(value), false
    end
    local last = #glyphs
    local tail = 0
    while last > 1 and tail + widths[last] <= width do
        tail = tail + widths[last]
        last = last - 1
    end
    last = math.min(#glyphs, last + 1)
    local travel = math.max(0, last - 1)
    local duration = travel * 0.25
    local phase = math.max(0, time or 0) % (duration * 2 + 3)
    local offset = phase < 1.5 and 0
        or phase < 1.5 + duration and math.floor((phase - 1.5) / 0.25)
        or phase < 3 + duration and travel
        or travel - math.floor((phase - 3 - duration) / 0.25)
    local first = math.max(1, math.min(last, offset + 1))
    local visible, used = {}, 0
    for i = first, #glyphs do
        if used + widths[i] > width then
            break
        end
        visible[#visible + 1] = glyphs[i]
        used = used + widths[i]
    end
    return table.concat(visible), true
end
-- Renderer-independent lightweight rich text: paragraphs, lists, headings and emphasis.
function M.rich(value, width, size, measure)
    local lines = {}
    value = string.gsub(tostring(value or ""), "\r\n", "\n")
    for paragraph in string.gmatch((value .. "\n"), "(.-)\n") do
        local heading, body = string.match(paragraph, "^(#+)%s+(.+)$")
        local font = heading and size + 3 or size
        body = body or paragraph
        body = string.gsub(body, "^%s*[-*]%s+", "• ")
        local spans, line, used = {}, {}, 0
        local strong, emphasis = false, false
        local function flush()
            lines[#lines + 1] = { spans = line, size = font }
            line = {}
            used = 0
        end
        local function add(word, style)
            local glyphs = {}
            for glyph in string.gmatch(word, "[%z\1-\127\194-\244][\128-\191]*") do
                glyphs[#glyphs + 1] = glyph
            end
            for _, glyph in ipairs(glyphs) do
                local gw = (measure and measure(glyph, font)) or font * 0.62
                if used + gw > width and #line > 0 then
                    flush()
                end
                if not (glyph == " " and #line == 0) then
                    local last = line[#line]
                    if last and last.style == style then
                        last.text = last.text .. glyph
                        last.width = last.width + gw
                    else
                        line[#line + 1] = { text = glyph, style = style, width = gw }
                    end
                    used = used + gw
                end
            end
        end
        local index = 1
        while index <= #body do
            if string.sub(body, index, index + 1) == "**" then
                strong = not strong
                index = index + 2
            elseif string.sub(body, index, index) == "*" then
                emphasis = not emphasis
                index = index + 1
            else
                local stop = string.find(body, "*", index, true) or (#body + 1)
                local chunk = string.sub(body, index, stop - 1)
                for word in string.gmatch(chunk, "%S+%s*") do
                    local ww = 0
                    for glyph in string.gmatch(word, "[%z\1-\127\194-\244][\128-\191]*") do
                        ww = ww + ((measure and measure(glyph, font)) or font * 0.62)
                    end
                    if used + ww > width and #line > 0 then
                        flush()
                    end
                    add(
                        word,
                        heading and "heading"
                            or strong and "strong"
                            or emphasis and "emphasis"
                            or "plain"
                    )
                end
                index = stop
            end
        end
        flush()
    end
    return lines
end
function M.width(value,size,measure)
    local width=0
    for glyph in string.gmatch(tostring(value),"[%z\1-\127\194-\244][\128-\191]*") do width=width+(measure and measure(glyph,size) or size*.62) end
    return math.max(width,measure and measure(tostring(value),size) or 0)
end
return M

end)()
local LLL_DIAGNOSTICS=(function()
-- Shared diagnostics and typed console input; borrows the parent menu input lease.
local M={}
local theme=LLL_UI_THEME or dofile("src/ui/theme.lua")
local Text=LLL_UI_TEXT or dofile("src/ui/text.lua")
local levels={debug=true,info=true,warn=true,error=true}
local function bounded(value,limit)
    local text=tostring(value or ''):gsub('%z',''):gsub('[\1-\8\11\12\14-\31]',' ')
    if #text>limit then
        while limit>0 and text:byte(limit+1)>=128 and text:byte(limit+1)<=191 do limit=limit-1 end
        text=text:sub(1,limit)..' [truncated]'
    end
    return text
end
function M.new(options)
    options=options or {}
    local capacity=math.max(16,math.min(512,options.capacity or 256))
    local ring,first,count,sequence={},1,0,0
    local owners={};local clock=options.clock or function()return os.time(),os.date('%H:%M:%S')end
    local api={api=1,revision=0,capacity=capacity,count=0,locations={},window={visible=false,width=740,height=320,scroll=0,dock='free'}}
    function api.emit(event)
        assert(type(event)=='table','Diagnostics event required')
        local source=bounded(event.source or 'Unknown',96)
        local severity=levels[event.severity] and event.severity or 'info'
        local message=bounded(event.message,1024);local details=bounded(event.details,1536)
        local path=bounded(event.log_path or api.locations[source],512)
        local timestamp,time=clock()
        local last=count>0 and ring[(first+count-2)%capacity+1]
        if last and last.source==source and last.severity==severity and last.message==message and last.details==details and last.log_path==path then
            last.repeats=last.repeats+1;last.timestamp=timestamp;last.time=time
        else
            sequence=sequence+1
            local index=(first+count-1)%capacity+1
            if count==capacity then index=first;first=first%capacity+1 else count=count+1 end
            ring[index]={seq=sequence,timestamp=timestamp,time=time,source=source,severity=severity,message=message,details=details,log_path=path,repeats=1}
            if severity=='error' then
                api.window.visible=true;api.window.scroll=0;api.window.anchor=nil
                -- Reveal within the active menu; preserve typing and input ownership.
            end
        end
        api.count=count;api.revision=api.revision+1
        return sequence
    end
    function api.record(source,message,severity,details,path)
        if not severity then
            local lower=tostring(message):lower()
            severity=(lower:find('failed',1,true) or lower:find('error',1,true) or lower:find('refused',1,true)) and 'error'
                or (lower:find('pending',1,true) or lower:find('warning',1,true)) and 'warn'
                or tostring(message):match('^MCM TEXT') and 'debug' or 'info'
        end
        return api.emit({source=source,severity=severity,message=message,details=details,log_path=path})
    end
    function api.read()
        local result={}
        for i=1,count do local item=ring[(first+i-2)%capacity+1];local copy={};for k,v in pairs(item)do copy[k]=v end;result[i]=copy end
        return result
    end
    function api.attach(source,path)
        source=bounded(source,96);local token={};owners[token]=source
        if path and path~='' then api.locations[source]=bounded(path,512)end
        return token
    end
    function api.detach(token)
        if not owners[token]then return false,'Unknown diagnostics owner'end
        owners[token]=nil
        if not next(owners)then api.window.visible=false;api.window.drag=nil;api.window.resize=nil;api.active_surface=nil end
        return true
    end
    return api
end
function M.shared()
    local key='dbf.diagnostics.v1';local value=rawget(_G,'DBFDiagnostics') or package.loaded[key]
    if value then assert(value.api==1 and type(value.emit)=='function' and type(value.attach)=='function','Incompatible diagnostics provider')
    else value=M.new()end
    package.loaded[key]=value;rawset(_G,'DBFDiagnostics',value)
    return value
end
local colors={debug={145,156,165},info={224,230,234},warn={244,202,53},error={255,116,116}}
local function wrap(value,width)
    local lines={};local current='';local size=0
    for glyph in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*')do
        if glyph=='\n' then lines[#lines+1]=current;current='';size=0
        else if size>=width then lines[#lines+1]=current;current='';size=0 end;current=current..glyph;size=size+1 end
    end
    if current~=''then lines[#lines+1]=current end
    return lines
end
function M.surface(model)
    assert(model and model.api==1,'Diagnostics provider required')
    local self={};local token={};local hits={};local bounds,parent,screen;local held={};local mouse_held=false
    local cache={};local lines={};local cached_revision=-1;local cached_width=-1;local visible=1;local repeats={}
    local state=model.window
    local function inside(x,y,b)return b and x and y and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h end
    local function release_drag()if state.drag and state.drag.owner==token then state.drag=nil end;if state.resize and state.resize.owner==token then state.resize=nil end end
    function self.release()state.input_focused=false;state.focused=false;repeats={};release_drag();if model.active_surface==token then model.active_surface=nil end;hits={};bounds=nil;self.bounds=nil end
    local function scroll(amount,absolute)
        local maximum=math.max(0,#lines-visible)
        state.scroll=math.max(0,math.min(maximum,absolute or (state.scroll+amount)));state.anchor=nil
    end
    state.command_text=state.command_text or ""
    state.command_history=state.command_history or {}
    local suggestions={};local suggestion_text;local selected=1;local dismissed
    local function refresh_suggestions()
        if suggestion_text~=state.command_text then suggestion_text=state.command_text;selected=1;dismissed=nil end
        suggestions={}
        if state.input_focused and not dismissed and state.command_text~='' and model.commands and model.commands.suggest then
            suggestions=model.commands.suggest(state.command_text)
        end
        selected=math.max(1,math.min(#suggestions,selected))
    end
    local function complete(index)
        refresh_suggestions();local item=suggestions[index or selected]
        if item then state.command_text=item.text;state.replace_input=false;suggestion_text=item.text;dismissed=true;suggestions={} end
    end
    function self.submit()
        local command=state.command_text:match("^%s*(.-)%s*$")
        if command=="" then return false,"Enter a command" end
        local bus=model.commands
        local ok,message=false,"Console command service unavailable"
        if bus then ok,message=bus.execute(command)end
        model.record("Console","> "..command,"info")
        if ok and (command=="help" or command=="list" or command:match("^help%s") or command:match("^list%s"))then
            for line in tostring(message):gmatch("[^\n]+")do model.record("Console",line,"info")end
        else model.record("Console",message,ok and "info" or "error")end
        state.command_history[#state.command_history+1]=command
        if #state.command_history>50 then table.remove(state.command_history,1)end
        state.history_index=#state.command_history+1;state.command_text="";state.scroll=0;state.anchor=nil
        return ok,message
    end
    local function character(code,shift)
        if code>=65 and code<=90 then local c=string.char(code);return shift and c or c:lower()end
        if code>=48 and code<=57 then return shift and (")!@#$%^&*("):sub(code-47,code-47) or string.char(code)end
        if code>=96 and code<=105 then return tostring(code-96)end
        if code==32 then return " " end
        local plain={[186]=";",[187]="=",[188]=",",[189]="-",[190]=".",[191]="/",[192]="`",[219]="[",[220]="\\",[221]="]",[222]="'",[109]="-",[110]="."}
        local upper={[186]=":",[187]="+",[188]="<",[189]="_",[190]=">",[191]="?",[192]="~",[219]="{",[220]="|",[221]="}",[222]='"'}
        return (shift and upper[code]) or plain[code]
    end
    function self.filter(input,open,dt)
        if not open then self.release();return input end
        if model.active_surface~=token then
            model.active_surface=token;state.drag=nil;state.resize=nil;state.input_focused=false
            held={};for _,key in ipairs({192,38,40,33,34,36,35})do held[key]=input.down(key)end
            mouse_held=input.down(1)
        else
            local down=input.down(192)
            if down and not held[192]then
                state.visible=not state.visible;state.input_focused=state.visible;state.focused=state.visible
                state.suppress_input=state.visible;repeats={};release_drag()
            end
            held[192]=down
        end
        local x,y;if input.mouse then x,y=input.mouse()end
        local down=input.down(1);local over=state.visible and inside(x,y,bounds)
        if state.visible and over and down and not mouse_held then
            state.focused=true
            for i=#hits,1,-1 do if inside(x,y,hits[i])then hits[i].click(x,y);break end end
        elseif down and not mouse_held then state.focused=false;state.input_focused=false end
        local dragging=state.visible and (state.drag or state.resize)
        if not down then
            if state.drag and state.drag.owner==token and parent and bounds then
                local gap=18*(screen.scale or 1)
                local b=bounds;local side
                if math.abs(b.x+b.w-parent.x)<gap then side='left'
                elseif math.abs(b.x-(parent.x+parent.w))<gap then side='right'
                elseif math.abs(b.y+b.h-parent.y)<gap then side='bottom'end
                if side then self.dock(side)end
            end
            release_drag()
        elseif x and y and screen then
            if state.drag and state.drag.owner==token then
                state.dock='free';state.x=math.max(0,math.min(screen.w-bounds.w,x-state.drag.dx));state.y=math.max(0,math.min(screen.h-bounds.h,y-state.drag.dy))
            elseif state.resize and state.resize.owner==token then
                local r=state.resize;local l,t,b,right=r.left,r.top,r.bottom,r.right;local s=screen.scale
                if r.edge:find('w',1,true)then l=math.max(0,math.min(right-420*s,x))end
                if r.edge:find('e',1,true)then right=math.min(screen.w,math.max(l+420*s,x))end
                if r.edge:find('s',1,true)then b=math.max(0,math.min(t-200*s,y))end
                if r.edge:find('n',1,true)then t=math.min(screen.h,math.max(b+200*s,y))end
                state.x,state.y=l,b;state.width,state.height=(right-l)/s,(t-b)/s;state.dock='free'
            end
        end
        local blocked={[192]=true}
        if state.visible and state.input_focused then
            refresh_suggestions()
            local shift,ctrl=input.down(16),input.down(17)
            if state.suppress_input then for code=8,255 do held[code]=input.down(code)end;repeats={};state.suppress_input=false end
            for code=8,255 do
                local down=input.down(code)
                if code~=121 then blocked[code]=true end
                local count=down and not held[code] and 1 or 0
                local repeatable=code==8 or code==38 or code==40 or (not ctrl and code~=192 and character(code,shift)~=nil)
                if down and repeatable then
                    if not held[code] then repeats[code]={age=0,next=.4}
                    elseif repeats[code] then
                        local r=repeats[code];r.age=r.age+math.max(0,math.min(.1,dt or 0))
                        while r.age>=r.next and count<4 do count=count+1;r.next=r.next+.04 end
                    end
                else repeats[code]=nil end
                for _=1,count do
                    if code==9 then complete()
                    elseif code==13 then self.submit()
                    elseif code==27 then if #suggestions>0 then dismissed=true;suggestions={} else state.input_focused=false end
                    elseif ctrl and code==65 then state.replace_input=true
                    elseif code==8 then
                        state.command_text=state.replace_input and "" or state.command_text:sub(1,-2);state.replace_input=false
                    elseif code==38 or code==40 then
                        if #suggestions>0 then selected=((selected-1+(code==38 and -1 or 1))%#suggestions)+1
                        else
                            state.history_index=math.max(1,math.min(#state.command_history+1,(state.history_index or #state.command_history+1)+(code==38 and -1 or 1)))
                            state.command_text=state.command_history[state.history_index] or ""
                        end
                    elseif not ctrl then
                        local c=character(code,shift)
                        if c then if state.replace_input then state.command_text="";state.replace_input=false end;if #state.command_text<1024 then state.command_text=state.command_text..c end end
                    end
                end
                held[code]=down
            end
        elseif state.visible and state.focused then
            repeats={}
            local changes={[38]=1,[40]=-1,[33]=visible,[34]=-visible}
            for _,key in ipairs({38,40,33,34,36,35})do
                local pressed=input.down(key);blocked[key]=true
                if pressed and not held[key]then if key==36 then scroll(0,math.max(0,#lines-visible))elseif key==35 then scroll(0,0)else scroll(changes[key])end end
                held[key]=pressed
            end
        else repeats={};for _,key in ipairs({38,40,33,34,36,35})do held[key]=input.down(key)end end
        if state.visible and over and input.wheel then scroll(input.wheel()/120*3)end
        mouse_held=down
        local result={}
        for k,v in pairs(input)do result[k]=v end
        result.down=function(key)if blocked[key]then return false end;return input.down(key)end
        if over or dragging then result.mouse=function()end;result.wheel=function()return 0 end end
        return result
    end
    function self.dock(side)
        if side=='free'then state.dock='free';return true end
        if not parent or not bounds or not screen then return false,'Parent geometry unavailable'end
        local x,y=parent.x,parent.y
        if side=='left'then x=parent.x-bounds.w
        elseif side=='right'then x=parent.x+parent.w
        elseif side=='bottom'then y=parent.y-bounds.h
        else return false,'Unknown docking side'end
        if x<0 or y<0 or x+bounds.w>screen.w or y+bounds.h>screen.h then return false,'Not enough space beside parent'end
        state.dock=side;state.x,state.y=x,y;return true
    end
    function self.compose(w,h,parent_bounds,open)
        parent=parent_bounds;screen={w=w,h=h,scale=math.min(w/1920,h/1080)}
        if not open or not state.visible then hits={};bounds=nil;return {}end
        local s=screen.scale;local ww=math.max(420,math.min(w/s,state.width));local wh=math.max(200,math.min(h/s,state.height))
        state.width,state.height=ww,wh
        local x=math.max(0,math.min(w-ww*s,state.x or (w-ww*s)/2));local y=math.max(0,math.min(h-wh*s,state.y or 12*s))
        bounds={x=x,y=y,w=ww*s,h=wh*s};self.bounds=bounds
        if state.dock~='free'then local ok=self.dock(state.dock);if ok then x,y=state.x,state.y;bounds.x,bounds.y=x,y else state.dock='free'end end
        state.x,state.y=x,y;visible=math.max(1,math.floor((wh-122)/18));hits={}
        local width=math.max(12,math.floor((ww-30)/(14*.62)))
        if cached_revision~=model.revision or cached_width~=width then
            lines={};local next_cache={}
            for _,event in ipairs(model.read())do
                local signature=event.repeats..'/'..event.time..'/'..width
                local entry=cache[event.seq]
                if not entry or entry.signature~=signature then
                    local value=event.time..' '..event.severity:upper()..' '..event.source..': '..event.message..(event.repeats>1 and (' (x'..event.repeats..')')or '')
                    if event.details~=''then value=value..'\n  '..event.details end
                    if event.log_path~=''then value=value..'\n  Log: '..event.log_path end
                    entry={signature=signature,lines=wrap(value,width)}
                end
                next_cache[event.seq]=entry
                for index,line in ipairs(entry.lines)do lines[#lines+1]={text=line,severity=event.severity,seq=event.seq,line=index}end
            end
            cache=next_cache;cached_revision=model.revision;cached_width=width
            if state.anchor then for index,item in ipairs(lines)do if item.seq==state.anchor.seq and item.line==state.anchor.line then state.scroll=math.max(0,#lines-visible-index+1);break end end end
        end
        state.scroll=math.floor(math.max(0,math.min(math.max(0,#lines-visible),state.scroll)))
        local first_line=math.max(1,#lines-visible-state.scroll+1);local anchor=lines[first_line]
        state.anchor=state.scroll>0 and anchor and {seq=anchor.seq,line=anchor.line}or nil
        local commands={}
        local function rect(rx,ry,rw,rh,color)commands[#commands+1]={type='rect',x=x+rx*s,y=y+ry*s,w=rw*s,h=rh*s,c=color,a=1,popup=true,layer=(color==theme.palette.background or color==theme.palette.header) and theme.layers.console-10 or theme.layers.console,diagnostic_console=true}end
        local function text(rx,ry,value,color,size)commands[#commands+1]={type='text',x=x+rx*s,y=y+ry*s,text=value,size=(size or 14)*s,c=color or colors.info,a=1,popup=true,layer=400,diagnostic_console=true}end
        local function hit(rx,ry,rw,rh,fn)hits[#hits+1]={x=x+rx*s,y=y+ry*s,w=rw*s,h=rh*s,click=fn}end
        rect(0,0,ww,wh,theme.palette.background);rect(0,wh-34,ww,34,theme.palette.header);text(12,wh-23,'LLL CONSOLE',theme.palette.brass,17)
        hit(0,wh-34,ww,34,function(mx,my)state.drag={owner=token,dx=mx-x,dy=my-y}end)
        for index,side in ipairs({'free','left','right','bottom'})do
            local bx=ww-240+(index-1)*50
            text(bx,wh-22,side:upper(),state.dock==side and theme.palette.focus or colors.info,12)
            hit(bx-3,wh-30,48,26,function()local ok,why=self.dock(side);self.notice=ok and ''or why end)
        end
        text(ww-27,wh-23,'X',colors.info,17);hit(ww-35,wh-32,30,28,function()state.visible=false;state.input_focused=false;release_drag()end)
        for index=first_line,math.min(#lines,first_line+visible-1)do local item=lines[index];text(12,wh-55-(index-first_line)*18,item.text,colors[item.severity])end
        if #lines==0 then text(12,wh-55,'No diagnostics events recorded yet.',colors.debug)end
        text(12,12,self.notice and self.notice~=''and self.notice or ('` toggles | '..(state.scroll==0 and 'Following latest' or 'History paused')..' | retained '..model.count..'/'..model.capacity),colors.debug,12)
        if #lines>visible then
            local track=wh-120;local thumb=math.max(16,track*visible/#lines);local maximum=#lines-visible
            local offset=track-thumb;rect(ww-10,72,4,track,theme.palette.line);rect(ww-12,72+offset*state.scroll/maximum,8,thumb,theme.palette.focus)
            hit(ww-16,72,16,track,function(_,my)scroll(0,math.floor(math.max(0,math.min(1,(my-y-72*s)/(track*s)))*maximum))end)
        end
        rect(30,28,ww-105,32,theme.palette.field)
        if state.input_focused then rect(30,28,2,32,theme.palette.focus);commands[#commands].layer=theme.layers.console+3 end
        local command=state.command_text
        local size=14*s;local available=(ww-125)*s
        local tail=command
        while #tail>0 and Text.width(tail,size)>available do tail=tail:sub(2)end
        text(12,38,">",theme.palette.brass,14)
        text(40,38,(tail=="" and not state.input_focused) and "help | namespace.field = value" or (tail..(state.input_focused and "|" or "")),colors.info,14)
        commands[#commands].layer=theme.layers.console+8
        hit(30,28,ww-105,32,function()state.input_focused=true;state.focused=true;state.suppress_input=true end)
        rect(ww-68,28,54,32,theme.palette.field_hover);text(ww-62,38,"RUN",theme.palette.brass,13)
        hit(ww-68,28,54,32,function()self.submit();state.input_focused=true;state.focused=true;state.suppress_input=true end)
        refresh_suggestions()
        if #suggestions>0 then
            local count=math.min(8,#suggestions,math.max(1,math.floor((wh-124)/24)))
            local first=math.max(1,math.min(selected-count+1,#suggestions-count+1))
            rect(30,64,ww-105,count*24+24,theme.palette.header);commands[#commands].layer=theme.layers.console+12
            for row=1,count do
                local index=first+row-1;local item=suggestions[index];local ry=64+(count-row)*24+24
                if index==selected then rect(32,ry,ww-109,24,theme.palette.selected);commands[#commands].layer=theme.layers.console+13 end
                local label=item.label
                while #label>0 and Text.width(label,13*s)>(ww-133)*s do label=label:sub(1,-2)end
                text(40,ry+6,label,index==selected and theme.palette.brass or colors.info,13);commands[#commands].layer=theme.layers.console+14
                hit(32,ry,ww-109,24,function()complete(index)end)
            end
            text(40,70,'Tab complete | Up/Down select | Esc dismiss',colors.debug,12);commands[#commands].layer=theme.layers.console+14
        end
        local function resize(edge,rx,ry,rw,rh)
            hit(rx,ry,rw,rh,function()state.drag=nil;state.resize={owner=token,edge=edge,left=x,right=x+ww*s,bottom=y,top=y+wh*s}end)
        end
        resize('w',0,12,5,wh-24);resize('e',ww-5,12,5,wh-24);resize('s',12,0,ww-24,5);resize('n',12,wh-5,ww-24,5)
        for _,corner in ipairs({{'sw',0,0},{'se',ww-12,0},{'nw',0,wh-12},{'ne',ww-12,wh-12}})do resize(corner[1],corner[2],corner[3],12,12);rect(corner[2]+3,corner[3]+3,5,5,theme.palette.focus)end
        return commands
    end
    return self
end
return M

end)()
local LLL_UI_INPUT=(function()
-- Pointer, wheel and drag ownership.
local MODULE = {}
function MODULE.install(context)
    local self,state,api,measure,M = context.self,context.state,context.api,context.measure,context.menu
    local geometry,theme = context.geometry,context.theme
    local active,selectable,change = context.active,context.selectable,context.change
    function self.wheel(delta, x, y)
        if not self.visible or self.capture or not state.wheel_bounds or not x or not y then
            return
        end
        if self.dropdown then
            local d = self.dropdown
            d.scroll = math.max(
                0,
                math.min(math.max(0, #d.control.choices - 8), d.scroll - delta / 120 * 3)
            )
            d.scroll = math.floor(d.scroll)
            return
        end
        if
            state.help_bounds
            and x >= state.help_bounds.x
            and x <= state.help_bounds.x + state.help_bounds.w
            and y >= state.help_bounds.y
            and y <= state.help_bounds.y + state.help_bounds.h
        then
            self.help_scroll = math.max(
                0,
                math.min(state.help_bounds.maximum, self.help_scroll - math.floor(delta / 120) * 3)
            )
            return
        end
        if
            state.nav_bounds
            and x >= state.nav_bounds.x
            and x <= state.nav_bounds.x + state.nav_bounds.w
            and y >= state.nav_bounds.y
            and y <= state.nav_bounds.y + state.nav_bounds.h
        then
            state.nav_scroll =
                math.max(0, math.min(state.nav_bounds.maximum, state.nav_scroll - math.floor(delta / 120) * 3))
            return
        end
        local b = state.wheel_bounds
        if x < b.x or x > b.x + b.w or y < b.y or y > b.y + b.h then
            return
        end
        state.wheel_remainder = state.wheel_remainder + delta
        local steps = state.wheel_remainder >= 0 and math.floor(state.wheel_remainder / 120)
            or math.ceil(state.wheel_remainder / 120)
        state.wheel_remainder = state.wheel_remainder - steps * 120
        if steps == 0 then
            return
        end
        local mod, page = active()
        if not mod then
            return
        end
        if x < b.split then
            state.tree_scroll = math.max(0, math.min(state.tree_max, state.tree_scroll - steps * 3))
            state.tree_manual = true
        else
            self.scroll =
                math.max(0, math.min(math.max(0, (self.display_total or #page.controls) - (self.visible_rows or 12)), self.scroll - steps * 3))
            state.manual_scroll = true
        end
    end
    function self.tick(input)
        if not self.visible then
            self.pointer_x,self.pointer_y=nil,nil
            state.scroll_drag=nil
            local down = input.down(121)
            if down and not state.held[121] then
                self.key(121)
            end
            state.held[121] = down
            return
        end
        if
            not self.color_picker
            and not state.drag
            and not state.window_drag
            and not state.resize_drag
            and not self.text_edit
            and input.wheel
            and input.mouse
        then
            local delta = input.wheel()
            local x, y = input.mouse()
            self.wheel(delta, x, y)
        end
        for code = 1, 255 do
            local down = input.down(code)
            if down and not state.held[code] and code ~= 1 and code ~= 2 then
                self.key(code, input.down(17), input.down(16))
            end
            state.held[code] = down
        end
        if self.visible and input.mouse then
            local x, y = input.mouse()
            self.pointer_x,self.pointer_y=x,y
            if x and y and input.down(2) and not self.right_held and not self.capture and not self.text_edit and not self.color_picker then
                for i=#state.hits,1,-1 do
                    local hit=state.hits[i]
                    if hit.right and x>=hit.x and x<=hit.x+hit.w and y>=hit.y and y<=hit.y+hit.h then hit.right(x,y);break end
                end
            end
            self.right_held=input.down(2)
            if x and y and input.down(1) and not self.mouse_held then
                local valid = self.finish_color_field()
                if
                    self.text_edit
                    and self.text_edit.control
                    and self.text_edit.control.type == "input"
                then
                    self.key(13)
                    valid = self.text_edit == nil
                end
                if valid then
                    self.text_edit = nil
                end
                for i = #state.hits, 1, -1 do
                    local h = state.hits[i]
                    if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
                        if valid then
                            h.click(x, y)
                        end
                        break
                    end
                end
            end
            if state.scroll_drag then
                if not input.down(1) then state.scroll_drag=nil
                elseif y then state.scroll_drag.move(y) end
            end
            if state.palette_drag then
                if not self.color_picker or not input.down(1) then
                    state.palette_drag = nil
                elseif x and y then
                    state.palette_drag(x, y)
                end
            end
            if state.color_drag then
                if not self.color_picker or not input.down(1) then
                    state.color_drag = nil
                elseif x and y then
                    self.color_picker.x = math.max(
                        0,
                        math.min(800, (x - state.color_drag.ox) / state.color_drag.scale - state.color_drag.dx)
                    )
                    self.color_picker.y = math.max(
                        0,
                        math.min(390, (y - state.color_drag.oy) / state.color_drag.scale - state.color_drag.dy)
                    )
                end
            end
            if state.split_drag then
                if not self.visible or not input.down(1) then
                    state.split_drag = nil
                elseif x then
                    self.sidebar_manual=true
                    self.sidebar_width =
                        math.max(300, math.min(650, (x - state.split_drag.ox) / state.split_drag.scale))
                end
            end
            if state.resize_drag then
                if not input.down(1) then
                    state.resize_drag = nil
                    if self.on_geometry_changed then self.on_geometry_changed(self.parent_geometry) end
                elseif x and y then
                    local g = geometry.drag(state.resize_drag.geometry, state.resize_drag.edge, x-state.resize_drag.x, y-state.resize_drag.y)
                    self.window_width,self.window_height,self.window_x,self.window_y = g.width,g.height,g.x,g.y
                end
            end
            if state.window_drag then
                if not self.visible or not input.down(1) then
                    if self.visible and self.on_geometry_changed then self.on_geometry_changed(self.parent_geometry) end
                    state.window_drag = nil
        state.resize_drag = nil
                elseif x and y then
                    self.window_x = math.max(0, math.min(state.window_drag.max_x, x - state.window_drag.dx))
                    self.window_y = math.max(0, math.min(state.window_drag.max_y, y - state.window_drag.dy))
                end
            end
            if state.drag then
                if not self.visible then
                    state.drag = nil
                elseif input.down(1) then
                    if x then
                        state.drag.move(x)
                    end
                else
                    local ok, err = (state.drag.mod.handle.edit or state.drag.mod.handle.set)(
                        state.drag.control.id,
                        state.drag.value
                    )
                    self.notice = ok
                            and (state.drag.control.page and state.drag.control.page.require_confirmation and "Pending confirmation" or "Saved")
                        or ("Could not save: " .. tostring(err))
                    state.drag = nil
                end
            end
            self.mouse_held = input.down(1)
        else
            self.mouse_held = input.down(1)
        end
    end
end
return MODULE

end)()
local LLL_UI_RENDER=(function()
-- Commands and matching hit regions; no native input or resources.
local MODULE = {}
function MODULE.install(context)
    local self,state,api,measure,M = context.self,context.state,context.api,context.measure,context.menu
    local geometry,theme = context.geometry,context.theme
    local active,selectable,change = context.active,context.selectable,context.change
    function self.compose(w, h)
        if not self.visible or not w or not h or w<=0 or h<=0 then
            state.hits = {}
            state.drag = nil
            state.window_drag = nil
            state.resize_drag = nil
            state.scroll_drag = nil
            self.pointer_x,self.pointer_y=nil,nil
            self.dropdown = nil
            self.text_edit = nil
            self.color_picker = nil
            return {}
        end
        local commands = {}
        state.hits = {}
        local g = geometry.bounds(w,h,self.window_width,self.window_height,self.window_x,self.window_y,self.ui_scale)
        self.window_width,self.window_height,self.window_x,self.window_y = g.width,g.height,g.x,g.y
        self.parent_geometry = g
        local font_scale=math.max(.8,math.min(1.3,self.font_scale or 1))
        local W,H,s,ox,oy = g.width,g.height,g.scale,g.x,g.y
        self.visible_rows = math.max(1,math.floor((H-327)/34))
        local tree_visible = math.max(1,math.floor((H-280)/31))
        self.sidebar_width = math.max(300,math.min(self.sidebar_manual and self.sidebar_width or math.max(300,math.min(360,W*.23)), W-600))
        local visible_text_age = {}
        local visible_switches={}
        state.switch_visual=state.switch_visual or {}
        self.window_x, self.window_y = ox, oy
        local T = theme.palette
        local white, muted, accent, selection_text = T.white, T.muted, T.focus, T.white
        local shape_layer = theme.layers.shell
        local function hovering(x,y,rw,rh)
            return self.pointer_x and self.pointer_y and self.pointer_x >= ox+x*s and self.pointer_x <= ox+(x+rw)*s and self.pointer_y >= oy+y*s and self.pointer_y <= oy+(y+rh)*s
        end
        local function rect(x, y, rw, rh, color, a)
            commands[#commands + 1] = {
                type = "rect",
                x = ox + x * s,
                y = oy + y * s,
                w = rw * s,
                h = rh * s,
                c = color,
                a = a or 1,
                layer = shape_layer,
                ui_role = (color == T.panel or color == T.background or color == T.header) and "surface" or ((color == T.selected or color == T.hover) and "selection" or "control"),
            }
        end
        local function mark(role,control_id)
            local command=commands[#commands]
            command.ui_role=role;command.control_id=control_id
            command.layer=theme.layers[role] or command.layer
        end
        -- Four edge strips never cover the interior when native handles are retained.
        local function border(x,y,width,height,color,id)
            local stroke=math.min(2,width/2,height/2)
            for _,edge in ipairs({{x,y,width,stroke},{x,y+height-stroke,width,stroke},
                {x,y+stroke,stroke,height-2*stroke},{x+width-stroke,y+stroke,stroke,height-2*stroke}}) do
                rect(edge[1],edge[2],edge[3],edge[4],color)
                mark("control_frame",id)
            end
        end
        local function text(x, y, value, size, color)
            local full = tostring(value)
            local width = math.max(0, (W-25) - x) * s
            local single = string.gsub(full, "[\r\n]+", " ")
            local visible = M.flow(single, width, (size or 20) * s * font_scale, 0, measure)
            commands[#commands + 1] = {
                type = "text",
                x = ox + x * s,
                y = oy + y * s,
                text = visible,
                full_text = full,
                text_width = width,
                size = (size or 20) * s * font_scale,
                c = color or white,
                a = 1,
                layer = theme.layers.text_control,
            }
        end
        local function bounded(x, y, value, size, color, width)
            local key = tostring(value) .. "|" .. x .. "|" .. y .. "|" .. width
            local animate = hovering(x,y-5,width,28) or (self.focus == "settings" and self.focused_label == tostring(value))
            local age=state.text_age[key]
            if not age or age.active~=animate then age={start=state.elapsed,active=animate} end
            visible_text_age[key]=age
            width = math.max(0, math.min(width, (W-25) - x))
            local result = M.flow(string.gsub(tostring(value), "[\r\n]+", " "), width * s, size * s * font_scale, animate and (state.elapsed - age.start) or 0, measure)
            text(x, y, result, size, color)
            commands[#commands].full_text = tostring(value)
            commands[#commands].text_width = width * s
        end
        local function hit(x, y, rw, rh, fn, right)
            state.hits[#state.hits + 1] = { x = ox + x * s, y = oy + y * s, w = rw * s, h = rh * s, click = fn, right=right }
        end
        local function scrollbar(role,x,y,height,total,visible,offset)
            if total<=visible then return end
            local thumb=math.max(20,height*visible/total)
            local travel=height-thumb;local maximum=total-visible
            local progress=math.max(0,math.min(1,offset/maximum));local ty=y+travel*(1-progress)
            rect(x,y,4,height,T.line)
            rect(x-1,ty,6,thumb,hovering(x-7,y,18,height) and T.focus or T.border)
            commands[#commands].scrollbar=role
            hit(x-7,y,18,height,function(_,my)
                local local_y=(my-oy)/s
                local grab=local_y>=ty and local_y<=ty+thumb and local_y-ty or thumb/2
                state.scroll_drag={move=function(pointer_y)
                    local position=((pointer_y-oy)/s-grab-y)/travel
                    local value=math.floor((1-math.max(0,math.min(1,position)))*maximum+.5)
                    if role=="mods" then state.tree_scroll=value;state.tree_manual=true
                    elseif role=="settings" then self.scroll=value;state.manual_scroll=true
                    elseif role=="help" then self.help_scroll=value
                    elseif role=="dropdown" and self.dropdown then self.dropdown.scroll=value end
                end}
                state.scroll_drag.move(my)
            end)
        end
        shape_layer=86
        rect(5,-5,W,H,{5,6,7},.7)
        shape_layer=theme.layers.shell
        rect(0, 0, W, H, T.border)
        rect(1, 1, W-2, H-2, T.background, 0.99)
        rect(1, 60, self.sidebar_width-1, H-120, T.panel)
        rect(1, (H-60), W-2, 59, T.header)
        rect(self.sidebar_width, 60, 1, H-120, T.line)
        rect(18, H-46, 3, 30, accent)
        -- Inset workspace frames, with squared industrial corners.
        border(10,154,self.sidebar_width-22,H-222,T.line,"navigation_panel")
        border(self.sidebar_width+12,202,W-self.sidebar_width-26,H-270,T.border,"settings_panel")
        for index=#commands-7,#commands do commands[index].layer=92 end
        local function hazard(y,height,period)
            for line=0,height-1,2 do
                for band=-1,math.ceil(W/period) do
                    local left=band*period+period/2-line
                    local start=math.max(2,left)
                    local finish=math.min(W-2,left+period/2)
                    if finish>start then
                        rect(start,y+line,finish-start,math.min(2,height-line),T.focus)
                        commands[#commands].hazard_stripe=true
                    end
                end
            end
        end
        hazard(H-14,12,26);hazard(2,3,30)
        -- Winged skull silhouette: native geometry, independent of font or game assets.
        local skull={"0000011111100000","0001111111111000","0011111111111100","0111111111111110",
            "0110001110001110","0110001110001110","0111110101111110","0011110001111100",
            "0001111111111000","0000111111110000","0000101010100000","0000101010100000"}
        local px,py,unit=20,H-43,2
        for row,bits in ipairs(skull) do
            local run
            for col=1,#bits+1 do
                if bits:sub(col,col)=="1" then run=run or col
                elseif run then
                    rect(px+(run-1)*unit,py+(#skull-row)*unit,(col-run)*unit,unit,T.focus)
                    commands[#commands].brand_skull=true;run=nil
                end
            end
        end
        for side=-1,1,2 do
            for feather=0,3 do
                rect(side<0 and px-10+feather*2 or px+30,py+9+feather*3,10-feather*2,2,T.focus)
                commands[#commands].brand_skull=true
            end
        end
        shape_layer = theme.layers.control
        hit(0, (H-60), W, 60, function(mx, my)
            if state.drag or self.capture then
                return
            end
            state.window_drag =
                { dx = mx - ox, dy = my - oy, max_x = math.max(0, w - W * s), max_y = math.max(
                    0,
                    h - H * s
                ) }
        end)
        state.wheel_bounds = { x = ox, y = oy + 196 * s, w = W * s, h = (H-316) * s, split = ox
            + self.sidebar_width * s }
        text(65, (H-43), "LIVE LUA LOADER", theme.typography.title, white)
        rect(W-220,H-45,150,30,hovering(W-220,H-45,150,30) and T.field_hover or T.field)
        text(W-210,H-38,"Settings",18,white)
        hit(W-220,H-45,150,30,function()
            for index,owner in ipairs(api.list()) do
                for page_index,candidate in ipairs(owner.pages) do
                    if candidate.id=="manager_settings" then
                        self.selected,self.page,self.row,self.scroll=index,page_index,1,0
                        state.manual_scroll=false;self.focus="settings";return
                    end
                end
            end
        end)
        rect((W-55), (H-45), 38, 30, T.field)
        text((W-43), (H-38), "X", 20, white)
        hit((W-55), (H-45), 38, 30, function()
            self.visible = false
            self.capture = false
            self.dropdown = nil
            self.text_edit = nil
            self.color_picker = nil
        end)
        text(25, (H-105), "LOADER SOURCES", 16, muted)
        local mods = api.list()
        local mod, page = active()
        local sidebar = self.sidebar()
        local layout={}
        local top,bottom=H-118,160
        for index,entry in ipairs(sidebar) do
            local name=entry.kind=="mod" and entry.mod.name or (entry.kind=="category" and entry.category.name or entry.page.name)
            local status,badge
            if entry.kind=="page" then status=name:match("^%[([^%]]+)%]");name=name:gsub("^%[[^%]]+%]%s*","") end
            if entry.kind=="category" then
                local loaded,total=name:match("%((%d+) loaded / (%d+)%)")
                if loaded then badge=loaded.."/"..total;name=name:gsub("%s*%(%d+ loaded / %d+%)","") end
                name=name:gsub("^LLL live scripts$","Live scripts"):gsub("^Archive addons via LLL$","Archive addons"):gsub("^Unknown / conflicting owner$","Needs review")
            end
            local icon_x=18+entry.depth*18
            local label_x=icon_x+22
            local label_width=self.sidebar_width-22-label_x-(badge and 50 or 0)
            local font=entry.kind=="mod" and 18 or 16
            local lines=M.rich(name,label_width*s,font*s*font_scale,measure)
            local labels={}
            local line_height=math.ceil(font*font_scale)+4
            local max_lines=math.max(1,math.floor((top-bottom-8)/line_height))
            for line_index=1,math.min(max_lines,#lines) do
                local parts={};for _,span in ipairs(lines[line_index].spans) do parts[#parts+1]=span.text end
                labels[#labels+1]=table.concat(parts)
            end
            if #lines>max_lines then labels[max_lines]=M.flow(labels[max_lines],math.max(0,label_width*s-M.width("...",font*s*font_scale,measure)),font*s*font_scale,0,measure).."..." end
            layout[index]={entry=entry,name=name,status=status,badge=badge,icon_x=icon_x,label_x=label_x,label_width=label_width,font=font,labels=labels,line_height=math.ceil(font*font_scale)+4,height=math.max(32,#labels*(math.ceil(font*font_scale)+4)+8)}
        end
        local tail,count=0,0
        for index=#layout,1,-1 do if tail+layout[index].height>top-bottom then break end;tail=tail+layout[index].height;count=count+1 end
        state.tree_max=math.max(0,#sidebar-count)
        state.tree_scroll=math.max(0,math.min(state.tree_scroll,state.tree_max))
        if not state.tree_manual then
            for index,node in ipairs(sidebar) do
                if node.kind=="mod" and node.index==self.selected and index<=state.tree_scroll then state.tree_scroll=index-1 end
            end
        end
        local y=top;local visible=0;local centers={}
        for index=state.tree_scroll+1,#layout do
            local node=layout[index];local entry=node.entry
            if y-node.height<bottom then break end
            local baseline=y-node.line_height
            local cy=baseline+node.font*font_scale*.4;centers[index]=cy
            local selected=entry.kind=="page" and entry.mod_index==self.selected and entry.index==self.page
                or entry.kind=="mod" and entry.index==self.selected and not entry.open
            rect(12,y-node.height+2,self.sidebar_width-28,node.height-4,selected and T.selected or (hovering(12,y-node.height+2,self.sidebar_width-28,node.height-4) and T.hover or T.panel))
            commands[#commands].layer=theme.layers.row
            if entry.depth>0 then
                local parent=index-1
                while parent>0 and sidebar[parent].depth>=entry.depth do parent=parent-1 end
                local parent_y=centers[parent] or top-2
                local spine=18+(entry.depth-1)*18+7
                local junction=cy
                local trunk_top=math.max(junction,math.min(top-2,parent_y))
                rect(spine,junction,1,trunk_top-junction,T.border)
                commands[#commands].tree_branch={row_y=oy+(cy-6)*s,junction=oy+junction*s,top=oy+trunk_top*s,parent=parent}
                rect(spine,junction,node.icon_x-spine+4,1,T.border)
            end
            if entry.kind~="page" then
                rect(node.icon_x+3,cy-1,9,2,muted);mark("indicator","tree/"..index)
                if not entry.open then rect(node.icon_x+6,cy-4,2,9,muted);mark("indicator","tree/"..index)end
            elseif node.status then
                local status_color=node.status=="Loaded" and T.enabled or (node.status=="Disabled" and T.disabled or T.brass)
                rect(node.icon_x+4,cy-2,6,6,status_color);mark("indicator","status/"..index)
            end
            for line_index,label in ipairs(node.labels) do
                bounded(node.label_x,baseline-(line_index-1)*node.line_height,label,node.font,selected and white or (entry.kind=="category" and T.brass or white),node.label_width)
                commands[#commands].full_text=entry.kind=="page" and entry.page.name or node.name
                commands[#commands].navigation_label=true
                commands[#commands].navigation_depth=entry.depth
            end
            if node.badge then bounded(self.sidebar_width-66,cy-5,node.badge,13,muted,44)end
            hit(12,y-node.height+2,self.sidebar_width-28,node.height-4,function()
                if entry.kind=="mod" then
                    self.selected=entry.index;state.tree_expanded[entry.mod.id]=not entry.open;self.page=1
                elseif entry.kind=="category" then state.expanded[entry.key]=not entry.open
                else self.selected,self.page=entry.mod_index,entry.index end
                self.row,self.scroll=1,0;state.manual_scroll=false;state.tree_manual=true;self.focus="settings"
            end)
            local node_hit=state.hits[#state.hits]
            node_hit.right=function(mx,my)
                local actions={{label=entry.kind=="page" and "Open" or "Expand / Collapse",run=node_hit.click},{label="Collapse all",run=self.collapse_all},{label="Expand all",run=self.expand_all}}
                if entry.kind=="page" and entry.page.resource_id and api.open_metadata then
                    actions[#actions+1]={label="Edit metadata",disabled=not api.can_edit_metadata(),run=function()local ok,why=api.open_metadata(entry.page.resource_id);if not ok then self.notice=why end end}
                end
                self.open_context(mx,my,actions)
            end
            y=y-node.height;visible=visible+1
        end
        self.mod_scroll=state.tree_scroll
        scrollbar("mods",self.sidebar_width-9,bottom,top-bottom,#sidebar,math.max(1,visible),state.tree_scroll)
        if not mod then
            text(365, (H-150), "No mods registered. See the author example.", 24)
        else
            bounded(self.sidebar_width+24,H-108,page.name,theme.typography.heading,white,W-self.sidebar_width-48)
            if mod.name~="Live Lua Loader" then bounded(self.sidebar_width+24,H-81,mod.name,14,muted,W-self.sidebar_width-48)end
            bounded(self.sidebar_width+24,90,
                "Page "..self.page.." / "..#mod.pages.."  |  PgUp / PgDn",
                theme.typography.hint,muted,
                page.require_confirmation and W-364-self.sidebar_width-24 or W-self.sidebar_width-48)
            if api.loader_summary then
                bounded(25, 90, api.loader_summary(), 14, accent, self.sidebar_width - 40)
            end
            if page.require_confirmation then
                local pending = 0
                for _ in pairs(page.pending) do
                    pending = pending + 1
                end
                for _ in pairs(page.actions) do
                    pending = pending + 1
                end
                bounded(self.sidebar_width+24,112,"CONFIRM REQUIRED ("..pending..")",
                    theme.typography.hint,accent,W-self.sidebar_width-48)
                rect((W-340), 81, 135, 29, T.field)
                text((W-330), 90, "APPLY", 18, accent)
                rect((W-190), 81, 135, 29, T.field)
                text((W-180), 90, "DISCARD", 18, white)
                hit((W-340), 81, 135, 29, function()
                    local ok, err = mod.handle.confirm(page.id)
                    self.notice = ok
                            and ("Confirmed and saved" .. (err and "; " .. tostring(err) or ""))
                        or tostring(err)
                end)
                hit((W-190), 81, 135, 29, function()
                    mod.handle.discard(page.id)
                    self.notice = "Pending edits discarded"
                end)
            end
            local rows = selectable(page)
            self.row = math.max(1, math.min(self.row, #rows))
            local selected = rows[self.row]
            local resettable=selected and selected.default~=nil and not selected.disabled and selected.type~="button"
            rect(20,116,self.sidebar_width-40,30,resettable and T.field or T.panel)
            bounded(30,123,"RESET SETTING",15,resettable and white or T.disabled,self.sidebar_width-60)
            hit(20,116,self.sidebar_width-40,30,function()
                if not resettable then return end
                local ok,why=(mod.handle.edit or mod.handle.set)(selected.id,selected.default)
                self.notice=ok and "Default restored" or tostring(why)
            end)
            local settings_x = self.sidebar_width + 24
            local available = (W-25) - settings_x
            local wide = available < 1050 or type(page.render_preview) ~= "function"
            for _, control in ipairs(page.controls) do
                if control.column and available >= 1050 then wide = false end
            end
            local row_width = math.min(800,wide and available or available / 2 - 12)
            local column_stride=row_width+24
            local display, columns, ordinal = {}, {0,0}, 0
            local selected_at, selected_column = 1, 1
            for _, control in ipairs(page.controls) do
                if control.type=="section" and control.label:match("^LIVE LUA LOADER R%d+") then
                    -- The application header already identifies the loader.
                else
                if control.type ~= "text" and control.type ~= "section" then ordinal=ordinal+1 end
                local col = wide and 1 or (control.column == 2 and 2 or 1)
                if control.type=="text" then
                    for _,line in ipairs(M.rich(control.label,row_width*s,18*s*font_scale,measure)) do
                        local parts={};for _,span in ipairs(line.spans) do parts[#parts+1]=span.text end
                        columns[col]=columns[col]+1
                        display[#display+1]={control=control,label=table.concat(parts),column=col,line=columns[col],row=ordinal}
                    end
                else
                    columns[col]=columns[col]+1
                    display[#display+1]={control=control,label=control.label,column=col,line=columns[col],row=ordinal}
                    if control==selected then selected_at,selected_column=columns[col],col end
                end
            end
                end
            self.display_total=math.max(columns[1],columns[2])
            local function column_offset(col)
                return math.min(self.scroll,math.max(0,columns[col]-self.visible_rows))
            end
            local selected_offset=column_offset(selected_column)
            if not state.manual_scroll and selected_at<=selected_offset then self.scroll=selected_at-1 end
            if not state.manual_scroll and selected_at>selected_offset+self.visible_rows then self.scroll=selected_at-self.visible_rows end
            self.scroll=math.max(0,math.min(self.scroll,math.max(0,self.display_total-self.visible_rows)))
            for i, entry in ipairs(display) do
                local c=entry.control
                local offset=column_offset(entry.column)
                if entry.line>offset and entry.line<=offset+self.visible_rows then
                    local col=entry.column
                    local x=settings_x+(col-1)*column_stride
                    local y=(H-157)-(entry.line-offset-1)*34
                    local selected_row=entry.row
                    local row_index = selected_row
                    local row_hover = not self.dropdown and not self.color_picker and hovering(x-5,y-7,row_width+5,30)
                    rect(x-5,y-7,row_width+5,30,c==selected and T.selected or (row_hover and T.hover or (i%2==0 and T.panel or T.background)))
                    commands[#commands].layer=theme.layers.row
                    commands[#commands].ui_role="setting_row"
                    commands[#commands].hovered=row_hover==true
                    commands[#commands].focused=c==selected and self.focus=="settings"
                    rect(x-5,y-7,2,30,c==selected and (self.focus=="settings" and T.focus or T.border) or T.background)
                    commands[#commands].layer=theme.layers.focus
                    self.focused_label=selected and selected.label
                    local color = c.disabled and muted or accent
                    local informational = c.type == "text" or c.type == "section"
                    local label = entry.label or ""
                    local button_label,button_width,choice_width,choice_total
                    if c.type=="choice" then
                        local value=(mod.handle.preview or mod.handle.get)(c.id)
                        local presentation=c.presentation or "combined"
                        local arrows=presentation=="dropdown" and 0 or 60
                        choice_width=math.max(180,math.min(row_width-160-arrows,M.width(tostring(c.choices[value]),18*s*font_scale,measure)/s+(presentation=="selector" and 24 or 60)))
                        choice_total=choice_width+arrows
                    end
                    if c.type=="button" or c.type=="keybind" then
                        local value=(mod.handle.preview or mod.handle.get)(c.id)
                        button_label=c.type=="button" and (c.button_label or c.label or "Activate") or (value==0 and "BIND KEY" or theme.key_name(value))
                        button_width=math.max(175,math.min(row_width-80,M.width(button_label,18*s*font_scale,measure)/s+24))
                    end
                    local label_width = informational and row_width or math.min(260,math.max(0,row_width - (choice_total and choice_total+18 or (button_width and button_width+14 or 290))))
                    bounded(
                        x,
                        y,
                        label,
                        18,
                        c.disabled and muted
                            or (
                                c == selected and selection_text
                                or (c.type == "section" and accent or white)
                            ),
                        label_width
                    )
                    if c.type ~= "text" and c.type ~= "section" then
                        local value = (mod.handle.preview or mod.handle.get)(c.id)
                        local control = c
                        local owner = mod
                        local vx = x + math.min(280,row_width-290) - 245
                        local function select()
                            self.row = row_index
                            self.focus = "settings"
                        end
                        hit(x - 5, y - 7, row_width + 5, 34, function()
                            select()
                        end,function(mx,my)
                            select()
                            local actions={
                                {label="Apply page",run=self.apply},
                                {label="Discard page",run=function()owner.handle.discard(page.id);self.notice="Pending edits discarded" end},
                                {label="Reset setting",disabled=control.disabled or control.default==nil or control.type=="button",run=function()
                                    local ok,why=(owner.handle.edit or owner.handle.set)(control.id,control.default);self.notice=ok and "Default restored" or tostring(why)
                                end},
                            }
                            if control.type=="keybind" then actions[#actions+1]={label="Rebind key",disabled=control.disabled,run=function()change(control,0)end}end
                            self.open_context(mx,my,actions)
                        end)
                        if c.type == "slider" then
                            if state.drag and state.drag.mod == mod and state.drag.control == c then
                                value = state.drag.value
                            end
                            local track = vx + 245
                            local width = 180
                            local fraction =
                                math.max(0, math.min(1, (value - c.min) / (c.max - c.min)))
                            rect(track, y + 5, width, 5, T.line)
                            rect(track, y + 5, width * fraction, 5, color)
                            mark("fill",mod.id.."/"..c.id)
                            rect(track + width * fraction - 6, y - 2, 12, 19, color)
                            mark("indicator",mod.id.."/"..c.id)
                            local editing = self.text_edit
                                and self.text_edit.mod == mod
                                and self.text_edit.control == c
                            rect(
                                vx + 435,
                                y - 5,
                                90,
                                29,
                                editing and T.selected
                                    or (c == selected and T.field_hover or T.field)
                            )
                            local display = editing and self.text_edit.text .. "|"
                                or string.gsub(string.gsub(string.format("%.3f", value), "0+$", ""), "%.$", "")
                            bounded(
                                vx + 440,
                                y,
                                display,
                                18,
                                editing and accent or (c == selected and selection_text or white),
                                80
                            )
                            hit(vx + 435, y - 5, 90, 29, function()
                                if control.disabled then
                                    return
                                end
                                select()
                                self.text_edit = {
                                    mod = owner,
                                    control = control,
                                    text = tostring(
                                        (owner.handle.preview or owner.handle.get)(control.id)
                                    ),
                                    replace = true,
                                }
                                self.notice = "Type value; Enter saves, Escape cancels"
                            end)
                            hit(track - 8, y - 7, width + 16, 34, function(mx)
                                if control.disabled then
                                    return
                                end
                                select()
                                local d = {
                                    mod = owner,
                                    control = control,
                                    value = (owner.handle.preview or owner.handle.get)(control.id),
                                }
                                function d.move(px)
                                    local f = math.max(
                                        0,
                                        math.min(1, (px - (ox + track * s)) / (width * s))
                                    )
                                    d.value = math.min(
                                        control.max,
                                        control.min
                                            + math.floor(
                                                    f * (control.max - control.min) / control.step
                                                        + 0.5
                                                )
                                                * control.step
                                    )
                                end
                                state.drag = d
                                d.move(mx)
                            end)
                        elseif c.type == "input" then
                            local editing = self.text_edit and self.text_edit.control == c
                            hit(vx + 245, y - 5, 250, 29, function()
                                select()
                                change(control, 0)
                            end)
                            rect(
                                vx + 245,
                                y - 5,
                                250,
                                29,
                                c == selected and T.field_hover or T.field
                            )
                            bounded(
                                vx + 255,
                                y,
                                editing and self.text_edit.text .. "|" or value,
                                18,
                                c == selected and selection_text or white,
                                230
                            )
                        elseif c.type == "color" then
                            rect(vx + 300, y - 3, 34, 23, api.color_rgb(value));mark("indicator",mod.id.."/"..c.id)
                            rect(
                                vx + 350,
                                y - 5,
                                175,
                                29,
                                c == selected and T.field_hover or T.field
                            )
                            bounded(
                                vx + 360,
                                y,
                                value,
                                18,
                                c == selected and selection_text or white,
                                155
                            )
                            hit(vx + 295, y - 7, 230, 34, function()
                                if control.disabled then
                                    return
                                end
                                select()
                                self.color_picker = {
                                    mod = owner,
                                    control = control,
                                    rgb = api.color_rgb(
                                        (owner.handle.preview or owner.handle.get)(control.id)
                                    ),
                                }
                            end)
                        elseif c.type == "toggle" then
                            hit(vx + 245, y - 5, 175, 29, function()
                                select()
                                change(control, 0)
                            end)
                            rect(
                                vx + 245,
                                y - 5,
                                175,
                                29,
                                c == selected and T.field_hover or T.field
                            )
                            local id=mod.id.."/"..c.id
                            local sx=vx+249
                            local target=value and 28 or 4
                            local visual=state.switch_visual[id] or {value=value,position=target,start=state.elapsed,from=target}
                            if visual.value~=value then visual={value=value,position=visual.position,from=visual.position,start=state.elapsed} end
                            local progress=math.min(1,math.max(0,(state.elapsed-visual.start)/.12))
                            visual.position=visual.from+(target-visual.from)*progress
                            visible_switches[id]=visual
                            rect(sx+2,y+1,52,17,c.disabled and T.panel or (value and T.selected or {52,56,59}))
                            mark("fill",id)
                            border(sx,y-1,56,21,c.disabled and T.line or (value and T.focus or T.border_hover),id)
                            rect(sx+visual.position,y+3,24,13,c.disabled and T.disabled or (value and T.focus or T.muted))
                            mark("indicator",id);commands[#commands].indicator_kind="sliding_switch"
                            text(
                                vx + 325,
                                y,
                                value and "ON" or "OFF",
                                19,
                                c.disabled and muted or (c == selected and selection_text or white)
                            )
                            mark("text_control",mod.id.."/"..c.id);commands[#commands].indicator_kind="toggle_label"
                        elseif c.type == "choice" then
                            local presentation = c.presentation or "combined"
                            local chosen = c == selected and selection_text or white
                            local symbol = c == selected and selection_text or color
                            local cw=choice_width
                            local cx=x+math.min(280,row_width-cw-60)+(presentation=="dropdown" and 0 or 30)
                            local previous_x,next_x=cx-30,cx+cw+3
                            if presentation ~= "dropdown" then
                                rect(
                                    previous_x,
                                    y - 5,
                                    27,
                                    29,
                                    c == selected and T.field_hover or T.field
                                )
                                text(previous_x + 7, y, "<", 18, symbol)
                                mark("text_control",mod.id.."/"..c.id);commands[#commands].indicator_kind="choice_previous"
                                rect(
                                    next_x,
                                    y - 5,
                                    27,
                                    29,
                                    c == selected and T.field_hover or T.field
                                )
                                text(next_x + 7, y, ">", 18, symbol)
                                mark("text_control",mod.id.."/"..c.id);commands[#commands].indicator_kind="choice_next"
                                hit(previous_x, y - 5, 27, 29, function()
                                    select()
                                    change(control, -1)
                                end)
                                hit(next_x, y - 5, 27, 29, function()
                                    select()
                                    change(control, 1)
                                end)
                            end
                            rect(cx, y - 5, cw, 29, c == selected and T.field_hover or T.field)
                            bounded(
                                cx + 9,
                                y,
                                tostring(c.choices[value]),
                                18,
                                chosen,
                                cw - (presentation == "selector" and 20 or 55)
                            )
                            if presentation ~= "selector" then
                                -- Reserve an opaque indicator cell above the value text.
                                rect(
                                    cx + cw - 32,
                                    y - 5,
                                    32,
                                    29,
                                    c == selected and T.field_hover or T.field
                                )
                                mark("indicator",mod.id.."/"..c.id)
                                text(cx + cw - 20, y, "v", 18, symbol)
                                mark("text_control",mod.id.."/"..c.id);commands[#commands].indicator_kind="choice_dropdown"
                                hit(cx, y - 5, cw, 29, function()
                                    if control.disabled then
                                        return
                                    end
                                    select()
                                    self.dropdown = {
                                        mod = owner,
                                        control = control,
                                        selected = value,
                                        scroll = math.max(
                                            0,
                                            math.min(math.max(0, #control.choices - 8), value - 4)
                                        ),
                                        x = cx,
                                        top = y - 8,
                                    }
                                end)
                            end
                        else
                            local label,bw=button_label,button_width
                            local bx=x+math.min(280,row_width-bw)
                            hit(bx,y-5,bw,29,function()select();change(control,0)end)
                            rect(bx,y-5,bw,29,c==selected and T.field_hover or T.field)
                            bounded(bx+12,y,label,18,c==selected and selection_text or color,bw-24)
                            mark("text_control",mod.id.."/"..c.id);commands[#commands].indicator_kind=c.type=="button" and "button_label" or "binding_label"

                        end
                    end
                end
            end
            scrollbar("settings", (W-20), 196, H-330, self.display_total, self.visible_rows, self.scroll)
            if self.display_total > self.visible_rows then
                text(
                    365,
                    166,
                    "Rows "
                        .. (self.scroll + 1)
                        .. "-"
                        .. math.min(self.scroll + self.visible_rows, self.display_total)
                        .. " of "
                        .. self.display_total,
                    16,
                    muted
                )
            end
            if type(page.render_preview) == "function" then
                local ok, preview = pcall(
                    page.render_preview,
                    { x = ox + 950 * s, y = oy + 285 * s, w = 460 * s, h = 350 * s, scale = s }
                )
                if ok and type(preview) == "table" then
                    for _, command in ipairs(preview) do
                        command.layer = 110
                        command.hud_preview = true
                        commands[#commands + 1] = command
                    end
                end
            end
            if wide and available-row_width-24>=260 then
                local dx=settings_x+row_width+24
                local dw=available-row_width-24
                local dy=H-168
                rect(dx-8,204,dw+8,H-360,T.panel);commands[#commands].layer=92
                local first=#commands+1
                border(dx-8,204,dw+8,H-360,T.line,"detail_panel")
                for index=first,#commands do commands[index].layer=92 end
                bounded(dx,dy,"SELECTION DETAILS",theme.typography.hint,T.focus,dw-12)
                bounded(dx,dy-30,selected and selected.label or page.name,theme.typography.heading,white,dw-12)
                local detail=selected and selected.description or mod.description or "Select a setting to view its details."
                local line_height=math.ceil(18*font_scale)+5
                local maximum=math.max(1,math.floor((H-438)/line_height))
                for index,line in ipairs(M.rich(detail,(dw-12)*s,18*s*font_scale,measure)) do
                    if index>maximum then break end
                    local parts={};for _,span in ipairs(line.spans)do parts[#parts+1]=span.text end
                    bounded(dx,dy-62-(index-1)*line_height,table.concat(parts),18,muted,dw-12)
                end
            end
            local help = selected and selected.description or mod.description
            local key = mod.id .. "/" .. page.id .. "/" .. tostring(help)
            if state.help_key ~= key then
                self.help_scroll = 0
                state.help_key = key
            end
            local hx = self.sidebar_width + 35
            local hw = (W-40) - hx
            local lines = M.rich(help, hw * s, 18 * s * font_scale, measure)
            local help_line_height=math.ceil(18*font_scale)+4
            local visible = math.max(1,math.floor(64/help_line_height))
            self.help_scroll = math.min(self.help_scroll, math.max(0, #lines - visible))
            state.help_bounds =
                { x = ox + hx * s, y = oy + 126 * s, w = hw * s, h = 64 * s, maximum = math.max(
                    0,
                    #lines - visible
                ) }
            for index = self.help_scroll + 1, math.min(#lines, self.help_scroll + visible) do
                local line = lines[index]
                local tx = hx
                local ty = 190 - help_line_height - (index - self.help_scroll - 1) * help_line_height
                for _, span in ipairs(line.spans) do
                    text(
                        tx,
                        ty,
                        span.text,
                        line.size / (s * font_scale),
                        span.style == "plain" and muted
                            or (span.style == "emphasis" and white or accent)
                    )
                    tx = tx + span.width / s
                end
            end
            scrollbar("help", (W-30), 126, 64, #lines, visible, self.help_scroll)
        end
        hit(self.sidebar_width - 6, 196, 12, H-310, function()
            state.split_drag = { ox = ox, scale = s }
        end)
        text(
            25,
            32,
            theme.key_name(api.menu_toggle_key or 45).." Close   "..theme.key_name(api.apply_key or 9).." Apply   "..theme.key_name(api.focus_key or 117).." Focus   Right-click Actions",
            17,
            muted
        )
        -- Show the actual status, not a fixed character slice of a Lua error.
        local notice = string.gsub(self.notice, "[%w_./\\-]+%.lua:%d+:%s*", "")
        local lines, line = {}, ""
        for word in string.gmatch(notice, "%S+") do
            if #line > 0 and #line + #word + 1 > 58 then
                lines[#lines + 1] = line
                line = word
            else
                line = #line == 0 and word or line .. " " .. word
            end
        end
        if #line > 0 then
            lines[#lines + 1] = line
        end
        for i, message in ipairs(lines) do
            text((W-600), 32 + (#lines - i) * 20, message, 15, accent)
        end
        if self.dropdown then
            local overlay_start = #commands + 1
            local d = self.dropdown
            local count = math.min(8, #d.control.choices)
            local height = count * 31 + 8
            local top = math.max(height + 8, math.min(752, d.top))
            local x = d.x
            -- Overlay hit regions take priority and consume outside clicks.
            hit(-ox / s, -oy / s, w / s, h / s, function()
                self.dropdown = nil
            end)
            rect(x - 2, top - height - 2, 254, height + 4, T.border)
            commands[#commands].ui_role="frame"
            rect(x, top - height, 250, height, T.panel)
            for index = d.scroll + 1, math.min(#d.control.choices, d.scroll + count) do
                local y = top - 29 - (index - d.scroll - 1) * 31
                local choice = index
                if index == d.selected then
                    rect(x + 3, y - 4, 234, 30, T.selected)
                end
                bounded(
                    x + 8,
                    y,
                    tostring(d.control.choices[index]),
                    18,
                    index == d.selected and selection_text or white,
                    226
                )
                hit(x + 3, y - 4, 234, 30, function()
                    local ok, err = (d.mod.handle.edit or d.mod.handle.set)(d.control.id, choice)
                    self.notice = ok
                            and (d.control.page and d.control.page.require_confirmation and "Pending confirmation" or "Saved")
                        or tostring(err)
                    self.dropdown = nil
                end)
            end
            scrollbar(
                "dropdown",
                x + 243,
                top - height + 4,
                height - 8,
                #d.control.choices,
                count,
                d.scroll
            )
            for index = overlay_start, #commands do
                commands[index].popup = true
                commands[index].layer = theme.overlay_layer(commands[index],theme.layers.popup)
            end
        end
        if self.color_picker then
            local p = self.color_picker
            local start = #commands + 1
            local px, py = p.x or 400, p.y or 195
            hit(-ox / s, -oy / s, w / s, h / s, function()
                self.color_picker = nil
                self.text_edit = nil
            end)
            hit(px - 2, py - 2, 704, 434, function() end)
            hit(px, py + 385, 700, 45, function(mx, my)
                state.color_drag = { ox = ox, oy = oy, scale = s, dx = (mx - ox) / s - px, dy = (my - oy)
                        / s
                    - py }
            end)
            rect(px - 2, py - 2, 704, 434, T.border)
            commands[#commands].ui_role="frame"
            rect(px, py, 700, 430, T.panel)
            rect(px + 650, py + 389, 32, 30, T.field)
            text(px + 660, py + 396, "X", 20, white)
            hit(px + 650, py + 389, 32, 30, function()
                self.color_picker = nil
                self.text_edit = nil
            end)
            text(px + 20, py + 397, "COLOR - RGB / HEX / SWATCHES", 22, accent)
            local hue, saturation, brightness = api.rgb_hsv(p.rgb)
            p.hue = p.hue or hue
            p.saturation = p.saturation or saturation
            p.brightness = p.brightness or brightness
            for col = 0, 15 do
                for row = 0, 11 do
                    rect(
                        px + 20 + col * 14,
                        py + 160 + row * 17,
                        15,
                        18,
                        api.hsv_rgb(col / 15, row / 11, p.brightness)
                    )
                end
            end
            for row = 0, 15 do
                rect(
                    px + 262,
                    py + 160 + row * 12.75,
                    25,
                    13.75,
                    api.hsv_rgb(p.hue, p.saturation, row / 15)
                )
            end
            rect(px + 17 + p.hue * 224, py + 157 + p.saturation * 204, 6, 6, white)
            rect(px + 259, py + 158 + p.brightness * 204, 31, 3, white)
            local function spectrum(mx, my)
                p.hue = math.max(0, math.min(1, ((mx - ox) / s - px - 20) / 224))
                p.saturation = math.max(0, math.min(1, ((my - oy) / s - py - 160) / 204))
                p.rgb = api.hsv_rgb(p.hue, p.saturation, p.brightness)
            end
            local function value_slider(mx, my)
                p.brightness = math.max(0, math.min(1, ((my - oy) / s - py - 160) / 204))
                p.rgb = api.hsv_rgb(p.hue, p.saturation, p.brightness)
            end
            hit(px + 20, py + 160, 224, 204, function(mx, my)
                state.palette_drag = spectrum
                spectrum(mx, my)
            end)
            hit(px + 262, py + 160, 25, 204, function(mx, my)
                state.palette_drag = value_slider
                value_slider(mx, my)
            end)
            rect(px + 595, py + 287, 85, 65, p.rgb)
            local fields = {
                { key = 1, label = "R", value = p.rgb[1] },
                { key = 2, label = "G", value = p.rgb[2] },
                { key = 3, label = "B", value = p.rgb[3] },
                { key = "hex", label = "HEX", value = api.color_hex(p.rgb) },
            }
            for index, field in ipairs(fields) do
                local fy = py + 343 - (index - 1) * 42
                text(px + 315, fy, field.label, 20, white)
                rect(px + 370, fy - 5, 210, 30, { 55, 63, 70 })
                local editing = self.text_edit and self.text_edit.color_channel == field.key
                text(
                    px + 380,
                    fy,
                    editing and self.text_edit.text .. "|" or tostring(field.value),
                    20,
                    editing and accent or white
                )
                hit(px + 370, fy - 5, 210, 30, function()
                    self.text_edit = {
                        color_channel = field.key,
                        text = string.gsub(tostring(field.value), "^#", ""),
                        replace = true,
                    }
                end)
            end
            text(px + 20, py + 126, "CUSTOM SWATCHES", 17, muted)
            for index, hex in ipairs(api.swatches()) do
                local sx = px + 20 + (index - 1) * 43
                if p.selected_swatch == index then
                    rect(sx - 3, py + 76, 41, 36, accent)
                end
                rect(sx, py + 79, 35, 30, api.color_rgb(hex))
                hit(sx, py + 79, 35, 30, function()
                    p.selected_swatch = index
                    p.rgb = api.color_rgb(hex)
                    p.hue, p.saturation, p.brightness = api.rgb_hsv(p.rgb)
                end)
            end
            rect(px + 550, py + 78, 130, 32, T.field)
            text(px + 560, py + 88, "SAVE SWATCH", 16, accent)
            hit(px + 550, py + 78, 130, 32, function()
                local ok, err = api.save_swatch(p.rgb)
                self.notice = ok and "Custom swatch saved" or tostring(err)
            end)
            rect(px + 550, py + 119, 130, 32, T.field)
            text(px + 557, py + 129, "REPLACE", 16, p.selected_swatch and accent or muted)
            hit(px + 550, py + 119, 130, 32, function()
                if not p.selected_swatch then
                    self.notice = "Select a saved swatch first"
                    return
                end
                local ok, err = api.replace_swatch(p.selected_swatch, p.rgb)
                self.notice = ok and "Selected swatch replaced" or tostring(err)
            end)
            rect(px + 20, py + 20, 300, 32, T.field)
            text(px + 35, py + 29, "USE COLOR", 18, accent)
            hit(px + 20, py + 20, 300, 32, function()
                self.commit_color()
            end)
            rect(px + 370, py + 20, 310, 32, T.field)
            text(px + 390, py + 29, "CANCEL", 18, white)
            hit(px + 370, py + 20, 310, 32, function()
                self.color_picker = nil
                self.text_edit = nil
            end)
            for index = start, #commands do
                commands[index].popup = true
                commands[index].layer = theme.overlay_layer(commands[index],theme.layers.picker)
            end
        end
        for _, edge in ipairs({
            {"left",0,0,8,H},{"right",W-8,0,8,H},{"bottom",0,0,W,8},{"top",0,H-8,W,8},
            {"left_bottom",0,0,14,14},{"right_bottom",W-14,0,14,14},
            {"left_top",0,H-14,14,14},{"right_top",W-14,H-14,14,14},
        }) do
            local name=edge[1]
            if string.find(name,"_",1,true) then
                local right=string.find(name,"right",1,true)~=nil
                local top=string.find(name,"top",1,true)~=nil
                local color=(state.resize_drag and state.resize_drag.edge==name or hovering(edge[2],edge[3],edge[4],edge[5])) and T.brass or T.focus
                local x=right and W-15 or 3
                local y=top and H-6 or 3
                rect(x,y,12,3,color)
                commands[#commands].resize_handle=name;mark("indicator","resize/"..name)
                rect(right and W-6 or 3,top and H-15 or 3,3,12,color)
                commands[#commands].resize_handle=name;mark("indicator","resize/"..name)
            end
            hit(edge[2],edge[3],edge[4],edge[5],function(mx,my)
                if state.drag or self.capture then return end
                state.resize_drag={edge=name,x=mx,y=my,geometry=g}
            end)
        end
        if self.context_menu then
            local popup=self.context_menu
            local pw=250;local ph=#popup.actions*34+8
            local px=math.max(2,math.min(W-pw-2,(popup.x-ox)/s))
            local py=math.max(2,math.min(H-ph-2,(popup.y-oy)/s-ph))
            local start=#commands+1
            hit(-ox/s,-oy/s,w/s,h/s,function()self.context_menu=nil end,function()self.context_menu=nil end)
            rect(px-1,py-1,pw+2,ph+2,T.border);commands[#commands].ui_role="frame"
            rect(px,py,pw,ph,T.panel)
            for index,action in ipairs(popup.actions) do
                local y=py+ph-34*index
                rect(px+3,y,pw-6,32,(popup.selected==index or hovering(px+3,y,pw-6,32)) and T.selected or T.panel)
                bounded(px+12,y+8,action.label,18,action.disabled and T.disabled or white,pw-24)
                hit(px+3,y,pw-6,32,function()
                    self.context_menu=nil
                    if not action.disabled then local ok,why=pcall(action.run);if not ok then self.notice=tostring(why) end end
                end)
            end
            for index=start,#commands do commands[index].popup=true;commands[index].context_action=true;commands[index].layer=theme.overlay_layer(commands[index],theme.layers.picker)end
        end
        local field_count=#commands
        for index=1,field_count do
            local field=commands[index]
            if field.type=="rect" and (field.c==T.field or field.c==T.field_hover) then
                local x,y=(field.x-ox)/s,(field.y-oy)/s
                local edge_color=hovering(x,y,field.w/s,field.h/s) and T.border_hover or T.border
                local start=#commands+1
                border(x,y,field.w/s,field.h/s,edge_color,field.control_id)
                for j=start,#commands do
                    commands[j].popup=field.popup
                    commands[j].layer=field.popup and field.layer+1 or theme.layers.control_frame
                end
            end
        end
        state.switch_visual=visible_switches
        state.text_age = visible_text_age
        return commands
    end
end
return MODULE

end)()
local LLL_UI_MENU=(function()
-- MCM layout/controller. Drawing is isolated from registry and settings storage.
local M = {}
local geometry = LLL_UI_GEOMETRY or dofile("src/ui/geometry.lua")
local text = LLL_UI_TEXT or dofile("src/ui/text.lua")
local theme = LLL_UI_THEME or dofile("src/ui/theme.lua")
local input_module = LLL_UI_INPUT or dofile("src/ui/input.lua")
local render_module = LLL_UI_RENDER or dofile("src/ui/render.lua")
M.flow, M.rich, M.width = text.flow, text.rich, text.width
function M.new(api, measure)
    local self = {
        visible = false,
        focus = "mods",
        selected = 1,
        page = 1,
        row = 1,
        mod_scroll = 0,
        scroll = 0,
        notice = "",
        capture = false,
    }
    local state = {}
    state.tree_expanded = {}
    state.tree_scroll = 0
    state.tree_manual = false
    state.tree_max = 0
    state.nav_bounds = nil
    state.nav_scroll = 0
    state.nav_mod = nil
    state.expanded = {}
    state.wheel_bounds = nil
    state.wheel_remainder = 0
    state.manual_scroll = false

    self.sidebar_width = 330
    self.help_scroll = 0
    state.help_bounds = nil
    state.help_key = nil
    state.hits = {}
    state.current = nil
    state.held = {}
    local active
    function self.expand_all()
        for _,mod in ipairs(api.list()) do
            state.tree_expanded[mod.id]=true
            for _,category in ipairs(mod.categories or {}) do state.expanded[mod.id.."/"..category.id]=true end
        end
    end
    function self.collapse_all()
        state.tree_expanded={};state.expanded={};state.tree_scroll=0;self.context_menu=nil
    end
    function self.open_context(x,y,actions)
        self.context_menu={x=x,y=y,actions=actions,selected=1}
    end
    function self.apply()
        local mod,page=active()
        if not mod or not page then return false end
        if not page.require_confirmation then self.notice="Settings apply immediately";return true end
        local called,ok,why=pcall(mod.handle.confirm,page.id)
        self.notice=called and ok and (why or "Applied and saved") or tostring(called and why or ok)
        return called and ok
    end
    function self.recover()
        self.visible = false
        self.context_menu=nil
        self.capture = false
        self.text_edit = nil
        self.color_picker = nil
        self.dropdown = nil
        self.mouse_held = false
        state.scroll_drag = nil
        self.pointer_x,self.pointer_y=nil,nil
        state.drag = nil
        state.window_drag = nil
        state.resize_drag = nil
        state.color_drag = nil
        state.palette_drag = nil
        state.split_drag = nil
        self.notice = "Menu closed after an error; "..theme.key_name(api.menu_toggle_key or 45).." reopens it"
    end
    active=function()
        local mods = api.list()
        self.selected = math.max(1, math.min(self.selected, #mods))
        state.current = mods[self.selected]
        if state.current then
            self.page = math.max(1, math.min(self.page, #state.current.pages))
            return state.current, state.current.pages[self.page]
        end
    end
    local function selectable(page)
        local rows = {}
        for _, c in ipairs(page and page.controls or {}) do
            if c.type ~= "text" and c.type ~= "section" then
                rows[#rows + 1] = c
            end
        end
        return rows
    end
    local function change(c, direction)
        if not state.current or c.disabled then
            return
        end
        local h = state.current.handle
        local ok, err = true
        if c.type == "button" then
            if direction == 0 then
                ok, err = (h.queue or h.activate)(c.id)
            end
        elseif c.type == "input" then
            self.text_edit =
                { mod = state.current, control = c, text = (h.preview or h.get)(c.id), replace = true }
            self.notice = "Type name; Enter accepts"
            return
        elseif c.type == "keybind" then
            self.capture = c
            self.notice = "Press a key. Escape cancels."
            return
        elseif c.type == "color" then
            self.color_picker =
                { mod = state.current, control = c, rgb = api.color_rgb((h.preview or h.get)(c.id)) }
            return
        else
            local v = (h.preview or h.get)(c.id)
            if c.type == "toggle" then
                v = not v
            elseif c.type == "choice" then
                v = (v - 1 + (direction == 0 and 1 or direction)) % #c.choices + 1
            elseif c.type == "slider" then
                v = math.max(
                    c.min,
                    math.min(c.max, v + (direction == 0 and 1 or direction) * c.step)
                )
            else
                return
            end
            ok, err = (h.edit or h.set)(c.id, v)
        end
        self.notice = ok
                and (c.page and c.page.require_confirmation and "Pending confirmation" or "Saved")
            or ("Could not save: " .. tostring(err))
    end
    function self.finish_color_field()
        local e = self.text_edit
        if not e or not e.color_channel then
            return true
        end
        if not self.color_picker then
            self.text_edit = nil
            return true
        end
        if e.color_channel == "hex" then
            local ok, rgb = pcall(api.color_rgb, e.text)
            if not ok then
                self.notice = "Use six HEX digits"
                return false
            end
            self.color_picker.rgb = rgb
        else
            local n = tonumber(e.text)
            if not n or n % 1 ~= 0 or n < 0 or n > 255 then
                self.notice = "RGB channels: integers 0-255"
                return false
            end
            self.color_picker.rgb[e.color_channel] = n
        end
        self.color_picker.hue, self.color_picker.saturation, self.color_picker.brightness =
            api.rgb_hsv(self.color_picker.rgb)
        self.text_edit = nil
        self.notice = "Color preview updated"
        return true
    end
    function self.commit_color()
        if not self.finish_color_field() then
            return
        end
        local p = self.color_picker
        if not p then
            return
        end
        local called, ok, err = pcall(p.mod.handle.edit or p.mod.handle.set, p.control.id, p.rgb)
        if called and ok then
            self.notice = p.control.page.require_confirmation and "Pending confirmation" or "Saved"
            self.color_picker = nil
        else
            self.notice = tostring(called and err or ok)
        end
    end
    function self.key(code, ctrl, shift)
        if self.capture then
            local mod=active();local c=self.capture;self.capture=false
            if code~=27 and mod then
                local called,ok,why=pcall(mod.handle.edit or mod.handle.set,c.id,code)
                self.notice=called and ok and "Binding saved" or tostring(called and why or ok)
            end
            return
        end
        if self.context_menu then
            local popup=self.context_menu
            if code==27 then self.context_menu=nil
            elseif code==38 or code==40 then popup.selected=math.max(1,math.min(#popup.actions,popup.selected+(code==38 and -1 or 1)))
            elseif code==13 then local action=popup.actions[popup.selected];self.context_menu=nil;if action and not action.disabled then action.run() end end
            return
        end
        if self.visible and code==(api.apply_key or 9) and self.text_edit and not self.text_edit.color_channel then
            self.key(13,ctrl,shift);if not self.text_edit then self.apply() end;return
        end
        if code == 121 then
            state.drag = nil
            state.window_drag = nil
        state.resize_drag = nil
            self.dropdown = nil
            self.text_edit = nil
            self.color_picker = nil
        end
        if code == 121 then
            self.visible = not self.visible
            self.capture = false
            return
        end -- Internal toggle event; frontend maps the configured physical key.
        if not self.visible then
            return
        end
        if self.text_edit then
            local e = self.text_edit
            if code == 27 then
                self.text_edit = nil
                return
            end
            if code == (api.apply_key or 9) and e.color_channel then
                self.finish_color_field()
                if not self.text_edit then
                    self.commit_color()
                    if not self.color_picker then self.apply() end
                end
                return
            end
            if code == 13 then
                if e.color_channel then
                    self.finish_color_field()
                    return
                end
                local value = e.control.type == "input" and e.text or tonumber(e.text)
                if
                    e.control.type ~= "input"
                    and (
                        not value
                        or value ~= value
                        or value < e.control.min
                        or value > e.control.max
                    )
                then
                    self.notice = "Enter a number from " .. e.control.min .. " to " .. e.control.max
                    return
                end
                local called, ok, err =
                    pcall(e.mod.handle.edit or e.mod.handle.set, e.control.id, value)
                if not called or not ok then
                    self.notice = tostring(called and err or ok)
                    return
                end
                self.notice = e.control.page
                        and e.control.page.require_confirmation
                        and "Pending confirmation"
                    or "Saved"
                self.text_edit = nil
                return
            end
            if ctrl and code == 65 then
                e.replace = true
                return
            end
            if code == 8 then
                if e.replace then
                    e.text = ""
                else
                    e.text = string.sub(e.text, 1, -2)
                end
                e.replace = false
                return
            end
            if code == 46 then
                e.text = ""
                e.replace = false
                return
            end
            local char
            if code >= 48 and code <= 57 then
                char = string.char(code)
            elseif code >= 96 and code <= 105 then
                char = tostring(code - 96)
            elseif code == 189 or code == 109 then
                char = "-"
            elseif code == 190 or code == 110 then
                char = "."
            end
            if e.control and e.control.type == "input" then
                if code >= 65 and code <= 90 then
                    char = e.control.free_text and (shift and string.char(code) or string.lower(string.char(code))) or string.char(code)
                elseif code == 32 then
                    char = " "
                end
            end
            if e.color_channel == "hex" and code >= 65 and code <= 70 then
                char = string.char(code)
            end
            if e.control and e.control.free_text then
                local plain={[186]=";",[187]="=",[188]=",",[191]="/",[192]="`",[219]="[",[220]="\\",[221]="]",[222]="'"}
                local shifted={[186]=":",[187]="+",[188]="<",[189]="_",[190]=">",[191]="?",[192]="~",[219]="{",[220]="|",[221]="}",[222]='"'}
                char=(shift and shifted[code] or plain[code]) or char
            end
            if char and not ctrl then
                if e.replace then
                    e.text = ""
                    e.replace = false
                end
                if #e.text < (e.control and e.control.type == "input" and (e.control.max_length or 48) or 24) then
                    e.text = e.text .. char
                end
            end
            return
        end
        if self.color_picker then
            if code == 27 then
                self.color_picker = nil
                return
            end
            if code == 13 or code==(api.apply_key or 9) then
                self.commit_color()
                if code==(api.apply_key or 9) and not self.color_picker then self.apply() end
            end
            return
        end
        if self.dropdown then
            local d = self.dropdown
            if code == 27 then
                self.dropdown = nil
                return
            end
            if code == 38 or code == 40 or code == 33 or code == 34 then
                local step = code == 33 and -8 or (code == 34 and 8 or (code == 38 and -1 or 1))
                d.selected = math.max(1, math.min(#d.control.choices, d.selected + step))
                if d.selected <= d.scroll then
                    d.scroll = d.selected - 1
                end
                if d.selected > d.scroll + 8 then
                    d.scroll = d.selected - 8
                end
                return
            end
            if code == 13 or code==(api.apply_key or 9) then
                local ok, err = (d.mod.handle.edit or d.mod.handle.set)(d.control.id, d.selected)
                self.notice = ok
                        and (d.control.page and d.control.page.require_confirmation and "Pending confirmation" or "Saved")
                    or tostring(err)
                self.dropdown = nil
                if ok and code==(api.apply_key or 9) then self.apply() end
                return
            end
            return
        end
        state.manual_scroll = false
        state.tree_manual = false
        local mod, page = active()
        if not mod then
            if code == 27 then
                self.visible = false
            end
            return
        end
        if self.capture then
            local c = self.capture
            self.capture = false
            if code ~= 27 then
                local ok, err = (mod.handle.edit or mod.handle.set)(c.id, code)
                self.notice = ok
                        and (c.page and c.page.require_confirmation and "Pending confirmation" or "Binding saved")
                    or tostring(err)
            end
            return
        end
        if code == 27 then
            self.visible = false
            return
        end
        if code==(api.apply_key or 9) then self.apply();return end
        if code == (api.focus_key or 117) then
            self.focus = self.focus == "mods" and "settings" or "mods"
            return
        end
        if code == 33 or code == 34 then
            self.page = (self.page - 1 + (code == 33 and -1 or 1)) % #mod.pages + 1
            self.row = 1
            self.scroll = 0
            return
        end
        if self.focus == "mods" then
            if code == 38 or code == 40 then
                self.selected =
                    math.max(1, math.min(#api.list(), self.selected + (code == 38 and -1 or 1)))
                self.page = 1
                self.row = 1
                self.scroll = 0
            elseif code == 13 or code == 39 then
                self.focus = "settings"
            end
        else
            local rows = selectable(page)
            self.row = math.max(1, math.min(self.row, #rows))
            local c = rows[self.row]
            if code == 38 or code == 40 then
                self.row = math.max(1, math.min(#rows, self.row + (code == 38 and -1 or 1)))
            elseif c and (code == 37 or code == 39 or code == 13) then
                change(c, code == 13 and 0 or (code == 37 and -1 or 1))
            end
        end
    end
    function self.sidebar()
        local rows = {}
        for index, mod in ipairs(api.list()) do
            local open = state.tree_expanded[mod.id] == true
            rows[#rows + 1] = { kind = "mod", mod = mod, index = index, open = open, depth = 0 }
            if open then
                local nodes = self.navigation(mod)
                for _, node in ipairs(nodes) do
                    if
                        not (
                            #(mod.categories or {}) == 1
                            and mod.categories[1].name == "HUD"
                            and node.kind == "category"
                            and node.depth == 0
                        )
                    then
                        local item = {}
                        for k, v in pairs(node) do
                            item[k] = v
                        end
                        item.mod = mod
                        item.mod_index = index
                        item.depth = node.depth + 1
                        if #(mod.categories or {}) == 1 and mod.categories[1].name == "HUD" then
                            item.depth = math.max(1, item.depth - 1)
                        end
                        rows[#rows + 1] = item
                    end
                end
            end
        end
        return rows
    end
    function self.navigation(mod)
        local rows = {}
        local function children(parent, depth)
            for _, category in ipairs(mod.categories or {}) do
                if category.parent == parent then
                    local key = mod.id .. "/" .. category.id
                    local open = state.expanded[key] == true
                    rows[#rows + 1] = {
                        kind = "category",
                        category = category,
                        key = key,
                        open = open,
                        depth = depth,
                    }
                    if open then
                        children(category.id, depth + 1)
                    end
                end
            end
            for index, page in ipairs(mod.pages) do
                if page.category == parent then
                    rows[#rows + 1] = { kind = "page", page = page, index = index, depth = depth }
                end
            end
        end
        children(nil, 0)
        return rows
    end
    state.text_age = {}
    state.elapsed = 0
    function self.advance(dt)
        if self.visible then
            state.elapsed = state.elapsed + math.max(0, math.min(1, tonumber(dt) or 0))
        else
            state.elapsed = 0
            state.text_age = {}
        end
    end
    local context = {self=self,state=state,api=api,measure=measure,menu=M,
        geometry=geometry,theme=theme,active=active,selectable=selectable,change=change}
    input_module.install(context)
    render_module.install(context)
    return self
end
return M

end)()
local LLL_UI_FONT=(function()
local PORT51={kind=type,number=tonumber}
-- Read the already loaded HUD font; exact-build gates precede descriptor reads.
-- Layout provenance: Epic LUT src/platform/ui_font.lua and Pick-your-bots
-- Test36 Source/replace_automatons.lua:7061-7089. No scan or memory writes.
local F={}
local HIGH=4294967296
local function u32(bytes,offset)
    offset=offset or 0
    if PORT51.kind(bytes)~='string' or #bytes<offset+4 then return nil end
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    return a+b*256+c*65536+d*16777216
end
local function hash(bytes)
    if PORT51.kind(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if lo==0 and hi==0 then return nil end
    return string.format('%08x%08x',hi,lo)
end
local function pointer(bytes)
    if PORT51.kind(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if hi>=0x8000 then return nil end
    local address=hi*HIGH+lo
    if address<0x10000 or address>0x800000000000-32 then return nil end
    return address
end
function F.new(memory,game,at)
    local function ensure_memory()
        if memory then return end
        local native=LLL_STEAM_TRANSPORT.nativeinfo()
        game=assert(native.module_base('game.dll'))
        memory={read=native.read_memory,address=function(value)return value end}
    end

    local self={}
    function self.resolve(sr)
        local ready=pcall(ensure_memory);if not ready then return nil end

        if not memory or PORT51.kind(memory.read)~='function' or PORT51.kind(memory.address)~='function' then return nil end
        if not sr or not sr.IdString64 or PORT51.kind(sr.IdString64.from_hex)~='function'
            or not sr.Application or PORT51.kind(sr.Application.can_get)~='function' then return nil end
        local ok,descriptor=pcall(function()
            -- Bingus memory.address converts pointers, never module names.
            -- Keep names separate so a Lua string's buffer cannot become the
            -- PE base (and silently leave the UI on the debug fallback).
            local module=game
            if PORT51.kind(module)=='string' then
                if PORT51.kind(memory.module)~='function' then return nil end
                module=memory.module(module)
                if module==nil then return nil end
            end
            local base=memory.address(module)
            if PORT51.kind(base)~='number' or base<0x10000 or base>=0x800000000000 or base~=math.floor(base) then return nil end
            local function read_address(address,count) return memory.read(at and at(address) or address,count) end
            local function read(offset,count) return read_address(base+offset,count) end
            local pe=u32(read(0x3c,4))
            if not pe or pe<0x40 or pe>0x1000 or u32(read(pe,4))~=0x4550
                or u32(read(pe+8,4))~=0x6AE0E5FF
                or u32(read(pe+80,4))~=0x3382000
                or u32(read(pe+88,4))~=0x2ED103A then return nil end
            local font,atlas=hash(read(0x312D998,8)),hash(read(0x312E618,8))
            local owner=pointer(read(0x3180C08,8))
            local material=owner and hash(read_address(owner+24,8))
            if not font or not atlas or not material then return nil end
            local I,app=sr.IdString64,sr.Application
            if not app.can_get('font',I.from_hex(font))
                or not app.can_get('texture',I.from_hex(atlas))
                or not app.can_get('material',I.from_hex(material)) then return nil end
            return {font=font,material=material,atlas=atlas}
        end)
        if ok then return descriptor end
        return nil
    end
    return self
end
return F

end)()
local LLL_UI_VIEW=(function()
-- Stock Stingray GUI; build-checked loaded main HUD font with compatibility fallback.
local M = {}
local theme = LLL_UI_THEME or dofile("src/ui/theme.lua")
function M.new(sr, preview_only)
    local gui, world
    local ids = {}
    local G = sr.Gui
    local self = {}
    local preview_view = not preview_only and M.new(sr, true) or nil
    local popup_view = not preview_only and M.new(sr, true) or nil
    local function live()
        for _, w in pairs(sr.Application.worlds() or {}) do
            if w == world then
                return true
            end
        end
        return false
    end
    local metrics = {}
    local font_source,active_font,font_key
    local function font_id()return active_font and sr.IdString64.from_hex(active_font.font) or "core/performance_hud/debug" end
    local function bind_font()
        if not active_font or not gui then return true end
        local ok,value=pcall(function()
            local material=G.material(gui,sr.IdString64.from_hex(active_font.material))
            return material and sr.Material.set_texture(material,sr.IdString64.from_hex("88BAC99B00000000"),sr.IdString64.from_hex(active_font.atlas))~=false
        end)
        return ok and value
    end
    function self.set_font_source(source)
        font_source=source
        if preview_view then preview_view.set_font_source(source) end
        if popup_view then popup_view.set_font_source(source) end
    end
    function self.accept_font(descriptor)
        local key=descriptor and table.concat({descriptor.font,descriptor.material,descriptor.atlas},"|")
        if key~=font_key then metrics={};self.clear();font_key=key;active_font=descriptor end
        if gui and not bind_font() then active_font=nil;font_key=nil;metrics={};self.clear() end
        if preview_view then preview_view.accept_font(active_font) end
        if popup_view then popup_view.accept_font(active_font) end
        self.font_name=active_font and "Main HUD" or "Compatibility fallback"
    end
    function self.refresh_font()
        local descriptor
        if font_source and G.material and sr.Material and sr.Material.set_texture then
            local ok,value=pcall(font_source.resolve,sr)
            if ok and type(value)=="table" then descriptor=value end
        end
        self.accept_font(descriptor)
    end
    function self.measure(glyph, size)
        local key = glyph .. "|" .. size
        if metrics[key] then
            return metrics[key]
        end
        -- Some game font extents report an advance smaller than the drawn glyph.
        -- Keep the stock-font estimate as a floor, including whole-word queries.
        local width = 0
        for _ in string.gmatch(glyph, "[%z\1-\127\194-\244][\128-\191]*") do
            width = width + size * 0.62
        end
        if gui and live() and type(G.text_extents) == "function" then
            local ok, value = pcall(function()
                if active_font then
                    local lo,hi=G.text_extents(gui,glyph,font_id(),size)
                    return hi.x-lo.x
                end
                local lo, hi = G.text_extents(gui, "M" .. glyph, font_id(), size)
                local base_lo, base_hi =
                    G.text_extents(gui, "M", font_id(), size)
                return (hi.x - lo.x) - (base_hi.x - base_lo.x)
            end)
            if ok and type(value) == "number" and value > 0 and value < 1000 then
                width = active_font and value or math.max(width, value)
            end
            metrics[key] = width
        end
        return width
    end
    function self.clear()
        if gui and live() then
            for _, item in ipairs(ids) do
                pcall(G["destroy_" .. item.type], gui, item.id)
            end
        end
        ids = {}
    end
    function self.release()
        if preview_view then
            preview_view.release()
        end
        if popup_view then
            popup_view.release()
        end
        if gui and live() then
            self.clear()
            sr.World.destroy_gui(world, gui)
        end
        gui, world = nil, nil
    end
    function self.draw(commands)
        self.refresh_font()
        if preview_view then
            local menu, preview, popup = {}, {}, {}
            for _, c in ipairs(commands) do
                local destination = c.hud_preview and preview or (c.popup and popup or menu)
                destination[#destination + 1] = c
            end
            preview_view.draw(preview)
            popup_view.draw(popup)
            commands = menu
        end
        if #commands == 0 then
            self.release()
            return
        end
        if gui and not live() then
            gui, world = nil, nil
            ids = {}
        end
        if not gui then
            local main = sr.Application.main_world()
            world = main
            for _, w in pairs(sr.Application.worlds() or {}) do
                if w ~= main then
                    world = w
                    break
                end
            end
            if not world then
                return
            end
            gui = sr.World.create_screen_gui(world, "scale", 1, 1)
            if active_font and not bind_font() then active_font=nil;font_key=nil;metrics={} end
        end
        local old_ids = ids
        ids = {}
        local signatures = {}
        for index, c in ipairs(commands) do
            local z = theme.depth(c)
            signatures[index] = table.concat({
                c.type,
                c.text or "",
                c.x,
                c.y,
                c.w or 0,
                c.h or 0,
                c.size or 0,
                c.a,
                c.c[1],
                c.c[2],
                c.c[3],
                z,
                font_key or "fallback",
                c.font_resource or "",
                c.font_material or "",
            }, "|")
        end
        -- Destroy all stale IDs before allocations: engines may reuse IDs immediately.
        for index, old in ipairs(old_ids) do
            if old.signature ~= signatures[index] then
                pcall(G["destroy_" .. old.type], gui, old.id)
                old_ids[index] = false
            end
        end
        for index, c in ipairs(commands) do
            local z = theme.depth(c)
            local signature = signatures[index]
            local old = old_ids[index]
            if old and old.signature == signature then
                ids[#ids + 1] = old
            else
                local color = sr.Color(math.floor(c.a * 255 + 0.5), c.c[1], c.c[2], c.c[3])
                local value
                if c.type == "rect" then
                    value = G.rect(gui, sr.Vector3(c.x, c.y, z), sr.Vector2(c.w, c.h), color)
                else
                    local font, material =
                        font_id(), active_font and sr.IdString64.from_hex(active_font.material) or "core/performance_hud/debug"
                    if c.font_resource then
                        font, material = c.font_resource, c.font_material
                    end
                    value =
                        G.text(gui, c.text, font, c.size, material, sr.Vector3(c.x, c.y, z), color)
                end
                if value then
                    ids[#ids + 1] = { type = c.type, id = value, signature = signature }
                else
                    ids[#ids + 1] = { type = c.type, id = nil, signature = nil }
                end
            end
        end
    end
    return self
end
return M

end)()
local LLL_UI_CAPTURE=(function()
-- Engine cursor lease. Does not install native message or process hooks.
local M = {}
function M.new(_, window, log)
    local self = {active=false}
    local saved, external
    local fields = {{'mouse_focus','set_mouse_focus','focus'}, {'show_cursor','set_show_cursor','cursor'}, {'clip_cursor','set_clip_cursor','clip'}}
    local modes={menu={focus=false,cursor=true,clip=true},camera={focus=false,cursor=false,clip=true}}
    local function snapshot()
        return {focus=window.mouse_focus(), cursor=window.show_cursor(), clip=window.clip_cursor()}
    end
    local function restore(value)
        if not value then return true end
        for _, field in ipairs(fields) do
            local ok, result = pcall(window[field[2]], value[field[3]])
            if not ok or result == false then return false, 'Cursor restoration refused: ' .. field[1] end
        end
        for _, field in ipairs(fields) do
            local ok, result = pcall(window[field[1]])
            if not ok or result ~= value[field[3]] then return false, 'Cursor restoration pending: ' .. field[1] end
        end
        return true
    end
    local function read_field(field)
        local ok,value=pcall(window[field[1]])
        if not ok then return nil,'Cursor readback failed: '..field[1]..': '..tostring(value) end
        if type(value)~='boolean' then return nil,'Invalid cursor state: '..field[1] end
        return value
    end
    local function closing(why)
        external.active,external.closing=false,true
        return false,why
    end
    local function external_current(field)
        local value,why=read_field(field)
        if why then return false,why end
        local key=field[3]
        -- Focus changes may already have restored an original flag. Do not
        -- rewrite it, or retain a restoration job that has already completed.
        if value==external.saved[key] then external.changed[key]=nil;return true end
        if value~=external.expected[key] then return false,'Cursor state belongs to another owner: '..field[1] end
        return true
    end
    function self.acquire(owner)
        if type(owner) ~= 'string' or owner == '' then return nil, 'Owner name required' end
        if saved or external then return nil, 'Input lease already owned' end
        local ok,baseline=pcall(snapshot)
        if not ok then return nil,tostring(baseline) end
        for _,field in ipairs(fields)do
            if type(baseline[field[3]])~='boolean' then return nil,'Invalid cursor state: '..field[1] end
        end
        external = {owner=owner, token={}, saved=baseline,changed={},expected={},active=false,closing=false}
        return external.token
    end
    function self.owns(token) return external ~= nil and external.token == token end
    function self.activate(token,mode)
        if not self.owns(token) then return false,'Input lease not owned' end
        mode=mode or 'menu'
        local target=modes[mode]
        if not target then return false,'Unsupported input mode' end
        if external.closing then return false,'Input lease restoration pending' end
        if external.active then
            if external.mode~=mode then return false,'Release the input lease before changing mode' end
            return true
        end
        if external.saved.focus~=true then return false,'Close the other input owner first' end
        -- A reservation never authorizes overwriting a new baseline owner.
        for _,field in ipairs(fields)do
            local value,why=read_field(field)
            if why then return closing(why) end
            if value~=external.saved[field[3]] then return closing('Cursor baseline changed: '..field[1]) end
        end
        for _,field in ipairs(fields)do
            local key=field[3]
            if external.saved[key]~=target[key] then
                external.changed[key],external.expected[key]=true,external.saved[key]
                local applied,result=pcall(window[field[2]],target[key])
                if applied and result~=false then external.expected[key]=target[key] end
                local value,why=read_field(field)
                if not why then
                    if value==external.saved[key] then external.changed[key]=nil
                    elseif value==target[key] then external.expected[key]=target[key] end
                end
                if not applied or result==false then return closing('Cursor acquisition refused: '..field[1]) end
                if why then return closing(why) end
                if value~=target[key] then return closing('Cursor acquisition readback failed: '..field[1]) end
            end
        end
        for _,field in ipairs(fields)do
            local value,why=read_field(field)
            if why then return closing(why) end
            if value~=target[field[3]] then return closing('Cursor acquisition readback failed: '..field[1]) end
        end
        external.active,external.mode=true,mode
        return true
    end
    function self.set_mode(token,mode)
        if not self.owns(token) then return false,'Input lease not owned' end
        local target=modes[mode]
        if not target then return false,'Unsupported input mode' end
        if external.closing or not external.active then return false,'Input lease inactive or restoring' end
        if external.mode==mode then return true end
        local previous=modes[external.mode]
        -- Unlike restoration, changing mode cannot adopt a field that another
        -- owner has reset to our baseline. Check the whole active state first.
        for _,field in ipairs(fields)do
            local value,why=read_field(field)
            if why then return closing(why) end
            if value~=previous[field[3]] then return closing('Cursor state belongs to another owner: '..field[1]) end
        end
        for _,field in ipairs(fields)do
            local key=field[3]
            if previous[key]~=target[key] then
                external.changed[key],external.expected[key]=true,previous[key]
                local applied,result=pcall(window[field[2]],target[key])
                if applied and result~=false then external.expected[key]=target[key] end
                local value,why=read_field(field)
                if not why then
                    if value==external.saved[key] then external.changed[key]=nil
                    elseif value==target[key] then external.expected[key]=target[key] end
                end
                if not applied or result==false then return closing('Cursor mode change refused: '..field[1]) end
                if why then return closing(why) end
                if value~=target[key] then return closing('Cursor mode change readback failed: '..field[1]) end
            end
        end
        for _,field in ipairs(fields)do
            local value,why=read_field(field)
            if why then return closing(why) end
            if value~=target[field[3]] then return closing('Cursor mode change readback failed: '..field[1]) end
        end
        external.mode=mode
        return true
    end
    function self.release(token)
        if token ~= nil then
            if not self.owns(token) then return false, 'Input lease not owned' end
            external.active,external.closing=false,true
            -- Check every changed field before making any restoration write.
            for _,field in ipairs(fields)do
                if external.changed[field[3]] then
                    local ok,why=external_current(field)
                    if not ok then return false,why end
                end
            end
            for _,field in ipairs(fields)do
                local key=field[3]
                if external.changed[key] then
                    local ok,why=external_current(field)
                    if not ok then return false,why end
                    if external.changed[key] then
                        local applied,result=pcall(window[field[2]],external.saved[key])
                        if applied and result~=false then external.expected[key]=external.saved[key] end
                        local value,problem=read_field(field)
                        if not problem and value==external.saved[key] then external.changed[key]=nil end
                        if not applied or result==false then return false,'Cursor restoration refused: '..field[1] end
                        if problem then return false,problem end
                        if value~=external.saved[key] then return false,'Cursor restoration pending: '..field[1] end
                    end
                end
            end
            external=nil
            return true
        end
        if external then return false, 'Input lease belongs to another owner' end
        self.active=false
        local ok, why = restore(saved)
        if ok then saved=nil end
        return ok, why
    end
    function self.status()
        return {owner=external and external.owner or (saved and 'lll' or nil),
            active=external and external.active or self.active,mode=external and external.mode or nil,
            pending_restore=external and external.closing or (saved ~= nil and not self.active),
            transport='engine-window', native_gate=false}
    end
    function self.sync(visible, focused)
        if not visible or not focused then
            if saved then return self.release() end
            return true
        end
        if external then return false, 'Input lease belongs to ' .. external.owner end
        if saved and not self.active then return false, 'Previous cursor restoration pending' end
        if not saved then
            saved=snapshot()
            if saved.focus ~= true then saved=nil; return false, 'Close the other input owner first' end
        end
        local ok, why = pcall(function()
            if window.mouse_focus() ~= false then assert(window.set_mouse_focus(false) ~= false) end
            if window.show_cursor() ~= true then assert(window.set_show_cursor(true) ~= false) end
            if window.clip_cursor() ~= true then assert(window.set_clip_cursor(true) ~= false) end
            assert(window.mouse_focus()==false and window.show_cursor()==true and window.clip_cursor()==true, 'Cursor acquisition readback failed')
        end)
        if not ok then self.release(); return false, tostring(why) end
        if not self.active then log('Engine window cursor lease acquired') end
        self.active=true
        return true
    end
    function self.shutdown()
        if external then local ok,why=self.release(external.token); if not ok then return false,why end end
        return self.release()
    end
    return self
end
return M

end)()
local LLL_UI_METADATA_EDITOR=(function()
local M={}
function M.install(api,loader,controls,get_menu)
    function api.open_metadata(resource)
        if loader.get_loader_option and loader.get_loader_option("metadata_editing")==false then return false,"Metadata editing is locked" end
        local rows=loader.provenance_snapshot();local row
        for _,candidate in ipairs(rows) do if candidate.name==resource then row=candidate end end
        if not row then return false,"Mod is no longer available" end
        local saved=loader.get_loader_option("metadata_overrides") or {};local current=saved[resource] or {}
        local editor=api.mods.lll_metadata_editor
        if editor then editor.handle.unregister() end
        local handle=api.register({id="lll_metadata_editor",name="Edit metadata",pages={{id="metadata",name=row.display_name or resource,controls={
            {type="input",id="name",label="Name",default=current.name or row.display_name or resource,free_text=true,max_length=128},
            {type="input",id="author",label="Author",default=current.author or row.author,free_text=true,max_length=128},
            {type="input",id="description",label="Description",default=current.description or row.description or "",free_text=true,max_length=512},
            {type="text",label="Changes stay local; original mod files are preserved."}
        }}}})
        local confirm=handle.confirm
        handle.confirm=function(page_id)
            if loader.get_loader_option("metadata_editing")==false then return false,"Metadata editing is locked" end
            local values={};for _,key in ipairs({"name","author","description"}) do values[key]=handle.preview(key) end
            if values.name:match("^%s*$") or values.author:match("^%s*$") then return false,"Name and Author cannot be empty" end
            local existing=loader.get_loader_option("metadata_overrides") or {};local next_values={}
            for key,value in pairs(existing) do next_values[key]=value end;next_values[resource]=values
            local ok,why=loader.save_loader_option("metadata_overrides",next_values)
            if not ok then return false,why end
            local accepted,message=confirm(page_id);controls.refresh();return accepted,message
        end
        local menu=get_menu()
        for index,mod in ipairs(api.list()) do if mod.id=="lll_metadata_editor" then menu.selected,menu.page,menu.row,menu.scroll=index,1,1,0 end end
        menu.focus="settings";menu.context_menu=nil;return true
    end
    api.can_edit_metadata=function()return loader.save_loader_option and (not loader.get_loader_option or loader.get_loader_option("metadata_editing")~=false)end
end
return M

end)()
local LLL_UI=(function()
-- Independent manager frontend with optional MCM integration.
return function(loader, platform, controls, report, input_driver)
    local self = {}
    local menu, view, capture, input, console_surface, raw
    local hotkey_held, suppress_toggle, hotkey_deferred = false, false, false
    local failed_shortcut
    local preferences=LLL_UI_PREFERENCES or dofile("src/ui/preferences.lua")
    local initialize
    local api = LLL_UI_CORE.new(nil, function(msg)
        report("LLL UI", msg)
    end)
    controls.bind(api, "origins")
    loader.manager_preferences_changed=function(values)
        if api.menu_toggle_key~=values.menu_toggle_key then hotkey_held,suppress_toggle=true,true end
        api.menu_toggle_key=values.menu_toggle_key
        api.apply_key,api.focus_key=values.apply_key,values.focus_key
        if menu then menu.ui_scale,menu.font_scale=values.ui_scale,values.font_scale end
    end
    loader.manager_preferences_changed(preferences.get(loader))
    loader.reset_manager_window=function()
        if menu then menu.window_width,menu.window_height,menu.window_x,menu.window_y=nil,nil,nil,nil end
    end
    self.api = api
    api.diagnostics = loader.diagnostics
    api.diagnostics_surface = loader.diagnostics_surface
    api.author_navigation = true
    api.loader_summary = controls.provenance_summary or controls.summary
    local function manager_failure()
        return input_driver and input_driver.manager_failure and input_driver.manager_failure()
    end
    local function require_manager_input()
        local failure=manager_failure()
        if failure then error(failure,2)end
    end
    function self.open()
        local recovering=manager_failure()
        if recovering then
            local released,why=input_driver.manager_release()
            if not released then return false,why end
        end
        if input_driver and not input_driver.manager_available() then return false,'Input lease belongs to another owner' end
        local mcm = rawget(_G, 'DBFMCM')
        if mcm and type(mcm) ~= 'table' then return false, 'MCM provider unavailable' end
        if not menu and initialize then
            local ok, why = pcall(initialize)
            if not ok then
                self.close()
                self.unavailable = tostring(why)
                return false, self.unavailable
            end
        end
        if not menu then
            return false, self.unavailable or "Native manager unavailable"
        end
        mcm = rawget(_G, "DBFMCM")
        if mcm and type(mcm) ~= 'table' then return false, 'MCM provider unavailable' end
        if mcm and type(mcm.close) == "function" then
            local ok, why = mcm.close()
            if ok == false then
                return false, why
            end
        end
        if failed_shortcut or recovering then
            failed_shortcut=nil
            hotkey_held,suppress_toggle=true,true
        end
        self.open_pending = true
        menu.visible = true
        return true
    end
    function self.close()
        local failed=manager_failure()
        if console_surface then console_surface.release() end
        self.open_pending = false
        if menu then
            menu.visible = false
        end
        local ok, why = true, nil
        if input_driver then
            ok,why=input_driver.manager_release()
        elseif capture then
            ok, why = capture.release()
        end
        if failed or manager_failure() then failed_shortcut='down' end
        if raw then
            local released,problem
            if input_driver then released,problem=pcall(raw.release,ok==true)
            else released,problem=pcall(raw.release) end
            if not released then ok,why=false,tostring(problem);report('LLL UI',why) end
        end
        if view then
            view.release()
        end
        return ok, why
    end
    loader.close_manager = self.close
    loader.input_status = function()
        local owner_capture=input_driver and input_driver.capture or capture
        return owner_capture and owner_capture.status() or { active = false }
    end
    loader.open_manager = function()
        local ok, why = self.open()
        assert(ok, why)
    end
    local sr = rawget(_G, "stingray")
    if not sr or not sr.Window or not platform.settings then
        self.unavailable = "Native GUI unavailable"
        return self
    end
    local input_platform=platform
    if input_driver then
        input_driver.set_manager_busy(function()return self.open_pending or (menu and menu.visible) or false end)
        -- The manager's engine-keyboard mode receives pointer-only samples.
        -- Advertise captured keys only when this reader owns a keyboard lease.
        local manager_keyboard_mask=false
        if platform.manager_engine_keyboard~=true then manager_keyboard_mask=platform.keyboard_capture_mask end
        input_platform=setmetatable({pointer_snapshot=input_driver.manager_snapshot,
            release_pointer=input_driver.manager_release,
            keyboard_capture_mask=manager_keyboard_mask},
            {__index=platform})
    end
    raw = LLL_STEAM_INPUT.new(sr,input_platform)
    local foreground = false
    local function mcm_binding(provider)
        if type(provider) ~= 'table' then return end
        local query = rawget(provider, 'menu_binding_status')
        if type(query) ~= 'function' then return end
        local status = query()
        if type(status) == 'table' and rawget(_G, 'DBFMCM') == provider then
            return rawget(status, 'global_key')
        end
    end
    local function shortcut_state(focused)
        local shortcut = api.menu_toggle_key or 45
        local down = raw.down(shortcut)
        if failed_shortcut then
            -- After native capture fails, the engine may report zero before a
            -- still-held key repeats. Observe a whole hidden down/up cycle.
            if not (menu and (menu.visible or self.open_pending)) then
                if failed_shortcut=='down' and down then failed_shortcut='up'
                elseif failed_shortcut=='up' and not down then failed_shortcut=nil end
            end
            hotkey_held,hotkey_deferred=down,failed_shortcut~=nil
            return false,false,focused
        end
        local edge = down and not hotkey_held
        if not down then
            hotkey_deferred = false
        elseif edge then
            if focused == nil then focused = sr.Window.has_focus() == true end
            -- MCM runs before this frontend and may already have closed on this
            -- edge. Its published binding owns the whole press, until release.
            if focused then
                local ok, binding = pcall(mcm_binding, rawget(_G, 'DBFMCM'))
                hotkey_deferred = ok and binding == shortcut
            end
        end
        hotkey_held = down
        return down and not hotkey_deferred, edge, focused
    end
    function self.tick()
        raw.frame()
        local down, edge, focused = shortcut_state()
        if down and edge and focused then
            local ok,why=self.open()
            if not ok then report('LLL UI',why) end
        end
    end
    initialize = function()
        capture=input_driver and input_driver.capture or LLL_UI_CAPTURE.new(nil,sr.Window,function(message)report('LLL UI',message)end)
        view=LLL_UI_VIEW.new(sr)
        view.set_font_source(LLL_UI_FONT.new())
        menu=LLL_UI_MENU.new(api,view.measure)
        self.menu=menu
        LLL_UI_METADATA_EDITOR.install(api,loader,controls,function()return menu end)
        loader.manager_preferences_changed(preferences.get(loader))
        if loader.diagnostics and loader.diagnostics_surface then console_surface=loader.diagnostics_surface(loader.diagnostics) end
        local saved=loader.get_loader_option and loader.get_loader_option('manager_window')
        if type(saved)=='table' then
            menu.window_width,menu.window_height,menu.window_x,menu.window_y=saved.width,saved.height,saved.x,saved.y
        end
        menu.on_geometry_changed=function(geometry)
            if loader.save_loader_option and geometry then
                local ok,why=loader.save_loader_option('manager_window',{
                    width=geometry.width,height=geometry.height,x=geometry.x,y=geometry.y})
                if not ok then report('LLL UI',why) end
            end
        end
        input={mouse=raw.mouse,wheel=raw.wheel}
        suppress_toggle=raw.down(api.menu_toggle_key or 45)
        function input.down(code)
            if not foreground then return false end
            if code==121 and failed_shortcut then return false end
            if menu.capture then return raw.down(code) end
            local shortcut=api.menu_toggle_key or 45
            if code==shortcut and code~=121 then return false end
            if code==121 then
                if hotkey_deferred then return false end
                if suppress_toggle then
                    if not raw.down(shortcut) then suppress_toggle=false end
                    return false
                end
                code=shortcut
            end
            return raw.down(code)
        end
        local hidden_clean=false
        function self.tick(dt)
            raw.frame()
            local ok,why=pcall(function()
                local showing=menu.visible or self.open_pending
                foreground=sr.Window.has_focus()==true
                if not foreground and showing then
                    local released,problem=self.close()
                    if not released then report('LLL UI',tostring(problem))end
                    showing=false
                end
                if foreground then
                    local down,edge=shortcut_state(true)
                    if down and edge and not showing and manager_failure() then
                        local opened,problem=self.open()
                        if not opened then failed_shortcut='up';report('LLL UI',tostring(problem))end
                    end
                else hotkey_held, hotkey_deferred = true, true end
                raw.visible(foreground and (menu.visible or self.open_pending))
                if menu.visible or self.open_pending then require_manager_input()end
                if self.open_pending then
                    if not foreground then self.open_pending=false;menu.visible=false
                    else
                        local held=false
                        for _,code in ipairs({1,2,4,5,6}) do held=held or raw.down(code) end
                        menu.visible=not held
                        if not held then self.open_pending=false end
                    end
                end
                local provider=rawget(_G,'DBFMCM')
                if not foreground or (provider and provider.is_open and provider.is_open()) then menu.visible=false end
                local was=menu.visible
                menu.tick(console_surface and console_surface.filter(input,menu.visible,dt) or input)
                if menu.visible then require_manager_input()end
                if menu.visible and not was and provider and provider.close then
                    local released,problem=provider.close()
                    if released==false then menu.visible=false;report('LLL UI',tostring(problem)) end
                end
                if showing and not menu.visible and not self.open_pending then
                    local released,problem=self.close()
                    if not released then report('LLL UI',tostring(problem))end
                end
                local acquired,problem=true,nil
                -- Keyboard retirement must be acknowledged before the manager
                -- cursor lease may restore; hidden frames never retry it.
                if not manager_failure() then acquired,problem=capture.sync(menu.visible or self.open_pending,foreground) end
                if not acquired then self.close();report('LLL UI',tostring(problem)) end
                if not menu.visible then
                    if not self.open_pending then raw.visible(false)end
                    if not hidden_clean then
                        menu.advance(dt);menu.compose()
                        if console_surface then console_surface.release() end
                        view.release();hidden_clean=true
                    end
                    return
                end
                hidden_clean=false
                local width,height=sr.Gui.resolution()
                if type(width)~='number' or type(height)~='number' or width<=0 or height<=0 then self.close();menu.recover();return end
                menu.advance(dt)
                local commands=menu.compose(width,height)
                if console_surface then
                    local g=menu.parent_geometry
                    local bounds=g and {x=g.x,y=g.y,w=g.width*g.scale,h=g.height*g.scale}
                    for _,command in ipairs(console_surface.compose(width,height,bounds,menu.visible)) do commands[#commands+1]=command end
                end
                view.draw(commands)
            end)
            if not ok then self.close();menu.recover();report('LLL UI',tostring(why)) end
        end
        report('LLL UI','Steam manager initialized; engine input and window cursor ownership')
    end
    report('LLL UI','Steam manager ready on configured shortcut')
    return self
end

end)()
local LLL_PLATFORM=(function()
-- Steam Lua 5.1 transport. The native helper uses no Lua state layout or hooks.
local P = {}
local release=type(LLL_STEAM_SERVICE)=='table' and LLL_STEAM_SERVICE.release
P.revision=type(release)=='string' and #release<=96 and release:match('^[%w][%w%._%-]*$') and release or 'R31-steam-lua51-candidate'
P.runtime, P.native_ffi = 'Lua 5.1', false
P.source_notifications=true
local sr = assert(stingray, 'Stingray runtime unavailable')
local base = assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA unavailable') .. '/LLL/Helldivers2'
local function read(path, limit)
    local file = io.open(path, 'rb')
    if not file then return end
    local size = file:seek('end')
    if not size or size > (limit or 67108864) then file:close(); return end
    file:seek('set', 0)
    local value = file:read('*a'); file:close()
    return value
end
local function u32(bytes, at)
    assert(type(bytes) == 'string' and at >= 1 and at + 3 <= #bytes, 'Truncated filesystem reply')
    local a,b,c,d = bytes:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function integer(value)
    assert(value >= 0 and value < 4294967296 and value == math.floor(value), 'Invalid filesystem integer')
    return string.char(value % 256, math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end
local function text(bytes, at)
    local length = u32(bytes, at)
    assert(at + 3 + length <= #bytes, 'Truncated filesystem string')
    return bytes:sub(at + 4, at + 3 + length), at + 4 + length
end
local transport=LLL_STEAM_TRANSPORT(LLL_STEAM_SERVICE)
P.transport_failure=transport.failure
P.on_transport_failure=transport.on_failure
local proof=transport.exchange(integer(0)..integer(0)..integer(0))
assert(u32(proof, 1) == 0 and u32(proof, 5) == 0, 'Steam filesystem helper refused this game build')
local pid = u32(proof, 9)
assert(pid == sr.Application.process_id(), 'Filesystem proof belongs to another process')
local position
P.exe, position = text(proof, 13)
P.root = text(proof, position)
P.data, P.local_app_data = P.root .. '/data', os.getenv('LOCALAPPDATA')
local sequence = 0
local function call(operation, path, bytes)
    assert(type(path) == 'string' and #path > 0 and #path <= 32760 and not path:find('%z'), 'Invalid filesystem path')
    sequence = sequence % 4294967295 + 1
    local reply=transport.exchange(integer(sequence)..integer(operation)..integer(#path)..path..(bytes or ''))
    assert(u32(reply, 1) == sequence, 'Stale filesystem response')
    return u32(reply, 5), reply
end
P.screenshot_directory=base..'/Screenshots'
P.screenshot_session=LLL_STEAM_SERVICE.pipe
local function screenshot_reply(status,reply)
    if status~=0 then return nil,string.format('Screenshot request refused (0x%08x)',status)end
    assert(#reply>=36,'Truncated screenshot reply')
    local states={'pending','succeeded','failed','cancelled'}
    local state=states[u32(reply,9)]
    assert(state,'Invalid screenshot state')
    local id,at=text(reply,29)
    local path;path,at=text(reply,at)
    assert(at==#reply+1,'Trailing screenshot reply bytes')
    return {state=state,error=u32(reply,13),width=u32(reply,17),height=u32(reply,21),
        elapsed_ms=u32(reply,25),id=id,output_path=path}
end
function P.screenshot_request(path)return screenshot_reply(call(13,path))end
function P.screenshot_status(id)return screenshot_reply(call(14,id))end
function P.screenshot_cancel(id)return screenshot_reply(call(15,id))end
P.read = read
function P.write(path, bytes) return call(5, path, bytes) == 0 end
function P.mkdir(path) return call(3, path) == 0 end
function P.guard()
    return {supported=true, reason=nil, exe_sha256=LLL_STEAM_BUILDS.exe_sha256,
        game_sha256=LLL_STEAM_BUILDS.game_sha256, lua_sha256='embedded Lua 5.1',
        jit_supported=false, lua_runtime='Lua 5.1', native_ffi=false}
end
function P.now() return sr.Application.time_since_launch() end
local function stamp(reply, at)
    return string.format('%08x%08x:%08x%08x', u32(reply, at), u32(reply, at + 4), u32(reply, at + 8), u32(reply, at + 12))
end
function P.stat(path)
    local status, reply = call(2, path)
    if status ~= 0 or math.floor(u32(reply, 9) / 16) % 2 == 1 then return end
    return stamp(reply, 13)
end
function P.files(directory, pattern)
    local status, reply = call(1, directory)
    local files, stamps, directories = {}, {}, {}
    if status ~= 0 then return files, stamps, directories, status end
    local at = 9
    local match = pattern and ('^' .. pattern:gsub('([%^%$%(%)%%%.%[%]%+%-])', '%%%1'):gsub('%*', '.*'):gsub('%?', '.') .. '$')
    while at <= #reply do
        local attributes, value = u32(reply, at), stamp(reply, at + 4)
        local name; name, at = text(reply, at + 20)
        if math.floor(attributes / 16) % 2 == 1 then directories[#directories + 1] = name
        elseif not match or name:match(match) then files[#files + 1] = name; stamps[name] = value end
    end
    return files, stamps, directories, 0
end
function P.directories(directory) local _,_,directories = P.files(directory); return directories end
local watches, generations, last_poll = {}, {}, -1
function P.changed(directory)
    local watch = watches[directory]
    if not watch then
        local status, reply = call(4, directory)
        assert(status == 0, 'Cannot register filesystem notification')
        watch = {index=u32(reply, 9), generation=0}; watches[directory] = watch
        last_poll = -1
    end
    local now = P.now()
    if now < last_poll or now - last_poll >= 0.45 then
        local status,reply=call(8,'poll');assert(status==0,'Filesystem event check failed');last_poll=now
        local bytes=reply:sub(9)
        assert(u32(bytes, 1) == pid, 'Filesystem events belong to another process')
        local count = u32(bytes, 5)
        assert(count <= 256 and #bytes == 8 + count * 4, 'Invalid filesystem event state')
        generations = {}
        for index = 1, count do generations[index] = u32(bytes, 5 + index * 4) end
    end
    local current = generations[watch.index] or 1
    local changed = current ~= watch.generation
    watch.generation = current
    return changed
end
function P.close_watches() assert(call(9,'close')==0);watches,generations,last_poll={},{},-1 end
function P.unwatch(path)
    local status=call(7,path)
    if status==0 then watches[path]=nil;last_poll=-1 end
    return status==0
end
local pointer={}
local function signed(bytes,at)
    local value=u32(bytes,at)
    return value>=2147483648 and value-4294967296 or value
end
function P.pointer_snapshot()
    local status,reply=call(10,'pointer')
    assert(status==0 and #reply==36,'Pointer service unavailable')
    pointer.valid=u32(reply,9)==1
    pointer.x,pointer.y=signed(reply,13),signed(reply,17)
    pointer.width,pointer.height=u32(reply,21),u32(reply,25)
    pointer.buttons,pointer.wheel=u32(reply,29),signed(reply,33)
    return pointer
end
function P.release_pointer() return call(11,'pointer')==0 end
local camera_pointer={}
function P.camera_snapshot()
    local status,reply=call(12,'pointer-v1')
    assert(status==0 and #reply==44,'Relative pointer service unavailable')
    camera_pointer.valid=u32(reply,9)==1
    camera_pointer.x,camera_pointer.y=signed(reply,13),signed(reply,17)
    camera_pointer.width,camera_pointer.height=u32(reply,21),u32(reply,25)
    camera_pointer.buttons,camera_pointer.wheel=u32(reply,29),signed(reply,33)
    camera_pointer.dx,camera_pointer.dy=signed(reply,37),signed(reply,41)
    return camera_pointer
end
-- Exact helper ABI 16-18. Preparing reserves cleanup authority before any I/O;
-- only a matching release acknowledgement retires that private authority.
local keyboard_mask=('00331f08ffe1ff03feffff27fffffff7ff0003003f0000fc010000f804000000'):gsub('%x%x',function(value)return string.char(tonumber(value,16))end)
P.keyboard_capture_mask=keyboard_mask
P.keyboard_scope='registered gameplay key whitelist; F12/Win/system shortcuts excluded'
local keyboard_owner,keyboard_client=nil,0
local function keyboard_owned(handle)
    return handle~=nil and keyboard_owner and keyboard_owner.handle==handle and keyboard_owner
end
local function keyboard_error(status)
    return string.format('Keyboard request refused (0x%08x)',status)
end
function P.keyboard_prepare()
    if keyboard_owner then return nil,'Keyboard request already owned or restoring' end
    if keyboard_client>=4294967295 then return nil,'Keyboard client IDs exhausted' end
    keyboard_client=keyboard_client+1
    local handle={}
    keyboard_owner={handle=handle,client=keyboard_client,generation=0,attempted=false,sample={}}
    return handle
end
function P.keyboard_acquire(handle)
    local current=keyboard_owned(handle)
    if not current then return false,'Keyboard request not owned' end
    if current.attempted then return current.accepted==true,current.reason end
    current.attempted=true -- An exchange failure may follow native registration.
    local ok,accepted,why=pcall(function()
        local status,reply=call(16,'keyboard-v1',integer(1)..integer(current.client)..keyboard_mask)
        if status~=0 then return false,keyboard_error(status) end
        assert(#reply==56 and u32(reply,9)==1 and u32(reply,13)==current.client,'Invalid keyboard acquisition acknowledgement')
        local generation,state=u32(reply,17),u32(reply,21)
        assert(generation>0 and state>=1 and state<=5,'Invalid keyboard generation or state')
        assert(reply:sub(25,56)==keyboard_mask,'Keyboard capture mask changed')
        current.generation=generation
        if state~=1 and state~=2 then return false,'Keyboard acquisition inactive (state '..state..')' end
        return true
    end)
    if not ok then why=tostring(accepted);accepted=false end
    current.accepted,current.reason=accepted==true,why
    return current.accepted,why
end
function P.keyboard_snapshot(handle,mode)
    local current=keyboard_owned(handle)
    if not current then return nil,'Keyboard request not owned' end
    if not current.accepted or current.generation==0 then return nil,current.reason or 'Keyboard acquisition unacknowledged' end
    local value=mode=='menu'and 0 or mode=='camera'and 1
    if value==nil then return nil,'Unsupported keyboard pointer mode' end
    local ok,result,why=pcall(function()
        local status,reply=call(17,'keyboard-v1',integer(current.client)..integer(current.generation)..integer(value))
        if status~=0 then return nil,keyboard_error(status) end
        assert(#reply==88 and u32(reply,45)==1 and u32(reply,49)==current.generation,'Invalid keyboard snapshot acknowledgement')
        local state=u32(reply,53)
        assert(state>=1 and state<=5,'Invalid keyboard snapshot state')
        local sample=current.sample
        sample.valid=u32(reply,9)==1
        sample.x,sample.y=signed(reply,13),signed(reply,17)
        sample.width,sample.height=u32(reply,21),u32(reply,25)
        sample.buttons,sample.wheel=u32(reply,29),signed(reply,33)
        sample.dx,sample.dy=signed(reply,37),signed(reply,41)
        sample.keyboard_active=state==2
        sample.keyboard_state,sample.keyboard_generation=state,current.generation
        sample.keyboard_keys,sample.keyboard_mask=reply:sub(57,88),keyboard_mask
        if state>=3 then current.accepted=false;current.reason='Keyboard lease inactive (state '..state..')' end
        return sample
    end)
    if not ok then return nil,tostring(result) end
    return result,why
end
function P.keyboard_release(handle)
    local current=keyboard_owned(handle)
    if not current then return false,'Keyboard request not owned' end
    local ok,released,why=pcall(function()
        local status,reply=call(18,'keyboard-v1',integer(current.client)..integer(current.generation))
        if status~=0 then return false,keyboard_error(status) end
        assert(#reply==20 and u32(reply,9)==1 and u32(reply,13)==current.client,'Invalid keyboard release acknowledgement')
        local generation=u32(reply,17)
        assert(current.generation==0 or generation==current.generation,'Stale keyboard release generation')
        return true
    end)
    if not ok then why=tostring(released);released=false end
    if released==true then keyboard_owner=nil;return true end
    current.reason=why or 'Keyboard restoration unacknowledged'
    return false,current.reason
end
function P.hash(bytes)
    local status, reply = call(6, 'hash', bytes)
    assert(status == 0 and #reply == 16, 'Resource hashing failed')
    return string.format('%08x%08x', u32(reply, 13), u32(reply, 9))
end
function P.archive(path)
    local file = io.open(path, 'rb')
    if not file then return end
    local size = file:seek('end')
    if not size or size > 67108864 then file:close(); return end
    file:seek('set', 0)
    local reader = {size=size, bytes=0, reads=0}
    function reader.read(at, count)
        assert(file and at >= 0 and count >= 0 and at + count <= size, 'Invalid archive read')
        assert(file:seek('set', at))
        local value = file:read(count)
        reader.reads = reader.reads + 1; reader.bytes = reader.bytes + (value and #value or 0)
        return value
    end
    function reader.close() if file then file:close(); file=nil end end
    return reader
end
P.live, P.settings, P.log_directory = base .. '/Mods', base .. '/Settings', base .. '/Logs'
for _, directory in ipairs({P.live, P.settings, P.log_directory}) do assert(P.mkdir(directory)) end
P.loader_config, P.migrated_config = base .. '/LLL.cfg', base .. '/MDL.cfg'
P.mdl_config = P.local_app_data .. '/MDL/Helldivers2/MDL.cfg'
P.roots = {{kind='lll',path=P.live}, {kind='mdl',path=P.local_app_data .. '/MDL/Helldivers2/Mods'},
    {kind='bingus',path=P.local_app_data .. '/CowboyBingus/Helldivers2/Mods'},
    {kind='bingus',path=P.local_app_data .. '/CowboyBingus/Helldivers2'},
    {kind='previous',path=P.local_app_data .. '/LiveLuaLoader/Helldivers2/Mods'}}
function P.open_log(name)
    if type(name) ~= 'string' or not name:match('^[%w_-]+%.log$') then return end
    return io.open(P.log_directory .. '/' .. name, 'wb')
end
return P

end)()
LLL_PLATFORM.cffi_status=LLL_CFFI;LLL_PLATFORM.native_cffi=LLL_CFFI.available
local platform = LLL_PLATFORM
local previous_text
local previous_path=platform.log_directory and platform.log_directory.."/LiveLuaLoader.log"
if previous_path then
    local file=io.open(previous_path,"rb")
    if file then previous_text=file:read(65536);file:close() end
end
local log = platform.open_log("LiveLuaLoader.log")
local diagnostic_service = LLL_DIAGNOSTICS and LLL_DIAGNOSTICS.shared()
local diagnostic_path = platform.log_directory and platform.log_directory .. "/LiveLuaLoader.log"
local diagnostic_owner = diagnostic_service and diagnostic_service.attach("LLL", diagnostic_path)
if log then
    log:write("Live Lua Loader 0.1.8 (" .. (platform.revision or 'R31-bsl-v20') .. "); API 1 compatibility\n")
end
local guarded, build = pcall(platform.guard)
if not guarded or type(build)~='table' then
    build={supported=false,reason=guarded and 'build check unavailable' or tostring(build),
        exe_sha256='unavailable',game_sha256='unavailable',lua_sha256='unavailable',jit_supported=false}
end
-- Capture the decision privately; changing the public report cannot enable loading.
local build_supported=build.supported==true
if not build_supported then
    local why=(build.reason or 'unsupported game build')..'; executable '..tostring(build.exe_sha256)
        ..'; game.dll '..tostring(build.game_sha256)
    local caps=LLL_CAPABILITIES({build_gate=true})
    local refused=function()return false,why end
    local state={api=1,version=1,build=build,modules={},capabilities=caps,after_startup=refused,
        add=refused,retry=refused,reload=refused,set_enabled=refused,refresh=refused}
    if not rawget(_G,'LiveLuaLoader') and not rawget(_G,'CowboyBingusModLoader') then
        rawset(_G,'LiveLuaLoader',state)
        rawset(_G,'CowboyBingusModLoader',{api=1,version=18,implementation='Live Lua Loader',
            revision='LLL-R31-bsl-v20',build=build,modules=state.modules,capabilities=caps,after_startup=refused})
    end
    if log then
        log:write("Refused startup: " .. tostring(why) .. "\n")
        log:close()
    end
    if diagnostic_service then diagnostic_service.detach(diagnostic_owner) end
    print("[LiveLuaLoader] Refused startup: " .. tostring(why))
    return
end
if log then log:write('Build supported: executable '..build.exe_sha256..'; game.dll '..build.game_sha256..'\n') end
if log and platform.cffi_status then
    log:write('cffi: '..(platform.cffi_status.available and 'ready (require cffi; no LuaJIT alias)' or ('unavailable: '..tostring(platform.cffi_status.reason)))..'\n')
    log:flush()
end
local entries = LLL_LEGACY
local ok, discovered, warnings, diagnostics, archive_copies = pcall(LLL_DISCOVER, platform)
if ok then
    for _, name in ipairs(discovered) do
        entries[#entries + 1] = name
    end
    if log then
        if diagnostics then
            log:write(diagnostics .. "\n")
        end
        log:write("Discovery: " .. #discovered .. " entries\n")
        for _, warning in ipairs(warnings or {}) do
            log:write(warning .. "\n")
        end
    end
else
    if log then
        log:write("Discovery failed: " .. tostring(discovered) .. "\n")
    end
    print("[LiveLuaLoader] Discovery failed: " .. tostring(discovered))
end
local function report(name, state)
    if diagnostic_service then pcall(diagnostic_service.record,name,state,nil,nil,diagnostic_path) end
    print("[LiveLuaLoader] " .. name .. ": " .. state)
    if log then
        log:write(name .. ": " .. state .. "\n")
        log:flush()
    end
end
local command_bus=LLL_COMMANDS.new()
platform.command_bus=command_bus
if diagnostic_service then diagnostic_service.commands=command_bus end
local live = LLL_LIVE(platform, report)
local source_cache = {}
local pending_edits = {}
for _, name in ipairs(live.scan()) do
    entries[#entries + 1] = name
end
if log then
    for _, root in ipairs(platform.roots or {}) do
        log:write("Search " .. root.kind .. ": " .. root.path .. "\n")
    end
end
local code_budget = LLL_JIT_BUDGET and LLL_JIT_BUDGET.start(LLL_TRUST.jit, live.loader_option("jit_code_cache"), report,{
    guard=function(cache)return LLL_JIT_CHURN.start(LLL_JIT_GUARD,LLL_TRUST.jit,cache,build,report)end})
local health
if LLL_HEALTH then
    local public={header={},changes={}}
    local function note(message)public.header[#public.header+1]=message;report("Health",message)end
    local observer
    local ok,value=pcall(LLL_HEALTH.observer,_G,{collect=collectgarbage,jit=LLL_TRUST.jit,clock=os.clock,
        flushes=code_budget and function()return code_budget.flushes end,watching=code_budget and code_budget.watching})
    if ok then observer=value;note(LLL_HEALTH.describe_start(observer.initial))else note("Observer unavailable: "..tostring(value))end
    local started="Started: "..os.date("%Y-%m-%d %H:%M:%S")
    if log then log:write(started.."\n")end
    note("Previous session: "..LLL_HEALTH.previous_session(previous_text))
    if platform.health then
        local ok,exe_stamp=pcall(LLL_HEALTH.image_stamp,platform.health.ffi,platform.health.kernel,nil)
        local game_ok,game_stamp=pcall(LLL_HEALTH.image_stamp,platform.health.ffi,platform.health.kernel,"game.dll")
        if ok and game_ok then note("Build stamps: "..LLL_HEALTH.hex(exe_stamp).." / "..LLL_HEALTH.hex(game_stamp))end
        for _,folder in ipairs({(os.getenv("APPDATA") or "").."/Arrowhead/Helldivers2/dumps",(os.getenv("LOCALAPPDATA") or "").."/CrashDumps"})do
            local ok,lines=pcall(LLL_HEALTH.crashes,platform.health.ffi,platform.health.kernel,folder,io.open,function(time)return os.date("%Y-%m-%d %H:%M:%S",time)end)
            if ok then for _,line in ipairs(lines)do note(line)end else note("Crash summary unavailable")end
        end
    end
    health={public=public,before=function()return observer and observer.mark()end,
        after=function(name,mark,stage)
            if observer and mark then
                local result=observer.changes(mark);local text=LLL_HEALTH.describe(result)
                if stage then text=string.sub((public.changes[name] or "").."; "..stage..": "..text,1,4096) end
                public.changes[name]=text;report(name,"Health: "..text)
            end
        end}
end
local shared_input,input_driver
-- Proton manager uses engine keys; native keyboard leases remain available to opt-in mods.
platform.manager_engine_keyboard = live.loader_option("manager_native_keyboard") ~= true
if LLL_STEAM_INPUT_SERVICE and stingray.Window and type(platform.pointer_snapshot)=='function' then
    shared_input,input_driver=LLL_STEAM_INPUT_SERVICE.new(platform,stingray.Window,
        LLL_UI_CAPTURE.new(nil,stingray.Window,function(message)report('LLL input',message)end))
end
local shared_capture,capture_driver
if LLL_STEAM_SCREENSHOT_SERVICE and type(platform.screenshot_request)=='function' then
    shared_capture,capture_driver=LLL_STEAM_SCREENSHOT_SERVICE.new(platform)
end
local manager = LLL_MANAGER({
    available = function(name)
        if live.catalog[name] then
            return pcall(live.source, name)
        end
        return stingray.Application.can_get("lua", name)
    end,
    require = function(name)
        if live.catalog[name] then
            source_cache[name] = live.fingerprint(name)
            return live.load(name)
        end
        return require(name)
    end,
    preflight = function(name)
        if live.catalog[name] then
            live.preflight(name)
        end
    end,
    can_retry = function(name)
        return live.catalog[name] ~= nil and not live.restart_only(name)
    end,
    save_enabled = live.set_enabled,
    evict = function(name)
        package.loaded[name] = nil
    end,
    open_log = platform.open_log,
    log_directory = platform.log_directory,
    report = report,
    health=health,jit_budget=code_budget,diagnostics=diagnostic_service,
    build=build,build_allowed=function()return build_supported end,
    revision=platform.revision,runtime=platform.runtime,native_ffi=platform.native_ffi,native_cffi=platform.native_cffi==true,cffi_status=platform.cffi_status,input_service=shared_input,
    capture_service=shared_capture,
    discovery_supported=LLL_DISCOVER~=nil,discovery_state=ok and (#discovered .. " declared entries") or "failed",protected_runtime=LLL_TRUST~=nil,modular_projects=true,console_commands=true,
}, entries)
if ok then
    manager.discovery_warnings = warnings
end
manager.console=command_bus
manager.diagnostics = diagnostic_service
manager.diagnostics_surface = LLL_DIAGNOSTICS and LLL_DIAGNOSTICS.surface
report("Startup","Startup finished; after-startup callbacks drained")
if log then log:write("Startup finished\n")end
manager.get_loader_option = live.loader_option
manager.save_loader_option = live.save_loader_option
manager.jit_budget = code_budget
manager.live_catalog = live.catalog
manager.discovery_diagnostics = diagnostics
manager.discovery_copies = archive_copies
if archive_copies then
    for name,description in pairs(archive_copies.by_name)do report(name,description)end
    for _,description in ipairs(archive_copies.notes)do report("Discovery",description)end
end
manager.auto_reload = live.auto_reload
manager.set_auto_reload = live.set_auto_reload
local controls = LLL_CONTROLS(manager, live, report)
local ui
local built, value = pcall(LLL_UI, manager, platform, controls, report, input_driver)
if built then
    ui = value
else
    report("LLL UI", value)
end
local function refresh_catalog(force)
    local found = live.scan(force)
    local all = {}
    for name in pairs(live.catalog) do
        all[#all + 1] = name
    end
    table.sort(all)
    for _, name in ipairs(all) do
        if manager.modules[name] == nil then
            manager.add(name, live.enabled(name))
        end
    end
    controls.follow(rawget(_G, "DBFMCM"))
    controls.refresh()
    return #all, found
end
manager.refresh = function()
    return refresh_catalog(true)
end
manager.clear_removed_entries = function()
    refresh_catalog(true)
    local retired, retained = manager.forget_removed()
    for _, name in ipairs(retired) do
        live.forget_removed(name)
        source_cache[name], pending_edits[name] = nil, nil
        report(name, "Removed stale loader record; saved settings retained")
    end
    controls.refresh()
    return #retired, retained
end
refresh_catalog()
-- Diagnostics now live at the bottom of the one LLL Mods page.
local status_page = { refresh = function() end, close = function() end }
status_page.refresh()
local clock = 0
local last_poll = platform.now and platform.now()
local retiring, detached = false, false
local capture_cleanup_report
local finish_detach
local maintenance_stopped,helper_reported,maintenance_report=false,false,nil
local helper_cleanup_pending=false
local function retire_helper(fn)
    local ok,value=pcall(fn)
    if not ok or value==false then helper_cleanup_pending=true end
end
local function maintenance_failure(problem)
    local failure
    if type(platform.transport_failure)=='function' then
        local ok,value=pcall(platform.transport_failure)
        if ok then failure=value end
    end
    if failure then
        maintenance_stopped=true
        if not helper_reported then
            helper_reported=true
            -- Retire the helper-dependent frontend once. Keep loaded module
            -- frames and explicit ownership cleanup alive below.
            if ui then retire_helper(ui.close) end
            if input_driver then retire_helper(input_driver.close) end
            if capture_driver then retire_helper(capture_driver.close) end
            report('LLL helper',tostring(failure)..'; restart required to reconnect')
        end
    elseif tostring(problem)~=maintenance_report then
        maintenance_report=tostring(problem)
        report('LLL maintenance',maintenance_report)
    end
end
if type(platform.on_transport_failure)=='function' then
    platform.on_transport_failure(maintenance_failure)
end
local function close_watches()
    if not platform.close_watches then return end
    local ok,why=pcall(platform.close_watches)
    if not ok then maintenance_failure(why) end
end
local function maintain()
    if platform.maintenance then platform.maintenance() end
    status_page.refresh()
    local _, names = refresh_catalog()
    for _, name in ipairs(names) do
        local valid, text
        if live.auto_reload() and live.enabled(name) and not live.restart_only(name) then
            valid, text = pcall(live.fingerprint, name, pending_edits[name] ~= nil)
        end
        if manager.modules[name] == nil then
            manager.add(name)
        elseif
            live.auto_reload()
            and live.enabled(name)
            and not live.restart_only(name)
            and valid
            and text
            and source_cache[name]
            and text ~= source_cache[name]
        then
            if pending_edits[name] == text then
                local success, problem = manager.retry(name)
                if not success and log then
                    log:write(name .. ": reload refused: " .. tostring(problem) .. "\n")
                end
                -- Suppress repeated failed reloads until another edit.
                source_cache[name] = text
                pending_edits[name] = nil
            else
                pending_edits[name] = text
            end
        else
            pending_edits[name] = nil
        end
    end
end
local function tick(dt)
    if not maintenance_stopped and input_driver then input_driver.begin_frame() end
    if retiring then
        manager.frame(dt)
        if not next(manager.pending_cleanup) and finish_detach then
            finish_detach()
        end
        return
    end
    manager.frame(dt)
    if not maintenance_stopped and ui and ui.tick then
        ui.tick(dt)
    end
    if maintenance_stopped then return end
    local now = platform.now and platform.now()
    clock = now and (now - last_poll) or (clock + (tonumber(dt) or 1 / 60))
    if now and now < last_poll then
        clock = 0.5
    end
    if clock < 0.5 then return end
    clock = 0
    if now then last_poll = now end
    local ok,why=pcall(maintain)
    if not ok then maintenance_failure(why) end
end
-- Preserve all prior callback results and trailing nils.
local function pack(...)
    return { n = select("#", ...), ... }
end
local prior = update
if type(prior) == "function" then
    local wrapper
    wrapper = function(dt, ...)
        local result = pack(prior(dt, ...))
        tick(dt)
        return unpack(result, 1, result.n)
    end
    update = wrapper
    finish_detach = function()
        if maintenance_stopped and helper_cleanup_pending then return false end
        if not maintenance_stopped then
            if ui then local ok,why=ui.close();if ok==false then report("LLL UI cleanup",why);return false end end
            if input_driver then local ok,why=input_driver.close();if not ok then report('LLL input cleanup',why);return false end end
            if capture_driver then
                local ok,why=capture_driver.close()
                if not ok then
                    local reason=why or 'Screenshot worker retirement pending'
                    if reason~=capture_cleanup_report then
                        report('LLL screenshot cleanup',reason)
                        capture_cleanup_report=reason
                    end
                    return false
                end
                capture_cleanup_report=nil
            end
        end
        if code_budget then
            local ok,why=code_budget.close()
            if not ok then report("LLL JIT cleanup",why);return false end
        end
        if diagnostic_service and diagnostic_owner then diagnostic_service.detach(diagnostic_owner);diagnostic_owner=nil end
        if update == wrapper then
            update = prior
        end
        if log then
            log:close()
            log = nil
        end
        detached = true
        return true
    end
    manager.detach = function()
        if retiring then
            if detached then return true end
            return false, "pending"
        end
        retiring = true
        if not maintenance_stopped and ui then
            ui.close()
        end
        controls.close()
        status_page.close()
        manager.shutdown()
        if not maintenance_stopped and input_driver then input_driver.close() end
        if not maintenance_stopped and capture_driver then capture_driver.close() end
        if code_budget then code_budget.close() end
        close_watches()
        if next(manager.pending_cleanup) then
            return false, "pending"
        end
        return finish_detach()
    end
else
    manager.frame_hook = "No global update callback; explicit LiveLuaLoader.frame(dt) required"
end
local old_shutdown = shutdown
if type(old_shutdown) == "function" then
    shutdown = function(...)
        if not maintenance_stopped and ui then
            ui.close()
        end
        controls.close()
        status_page.close()
        manager.shutdown()
        if not maintenance_stopped and input_driver then input_driver.close() end
        if not maintenance_stopped and capture_driver then capture_driver.close() end
        if code_budget then code_budget.close() end
        close_watches()
        if log then
            log:close()
            log = nil
        end
        return old_shutdown(...)
    end
end

end
local function finish(...) local ok,why=pcall(start);if not ok then local message="[LiveLuaLoader Steam] "..tostring(why);print(message);local f=io.open((os.getenv("LOCALAPPDATA") or "").."/LLL/Helldivers2/Logs/SteamStartupError.log","wb");if f then f:write(message);f:close() end end;return ... end
return finish(assert(loadstring("\027\076\117\097\081\000\001\004\004\004\008\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\002\003\027\000\000\000\036\000\000\000\007\000\000\000\036\064\000\000\007\064\000\000\036\128\000\000\007\128\000\000\036\192\000\000\007\192\000\000\005\000\001\000\006\064\065\000\006\128\065\000\028\128\128\000\087\192\065\000\022\128\000\128\005\000\002\000\065\064\002\000\028\064\000\001\005\128\002\000\069\192\002\000\133\000\003\000\028\128\128\001\026\000\000\000\022\128\000\128\005\000\003\000\006\064\067\000\028\064\128\000\030\000\128\000\014\000\000\000\004\005\000\000\000\105\110\105\116\000\004\009\000\000\000\115\104\117\116\100\111\119\110\000\004\007\000\000\000\117\112\100\097\116\101\000\004\007\000\000\000\114\101\110\100\101\114\000\004\009\000\000\000\115\116\105\110\103\114\097\121\000\004\012\000\000\000\065\112\112\108\105\099\097\116\105\111\110\000\004\006\000\000\000\098\117\105\108\100\000\004\008\000\000\000\114\101\108\101\097\115\101\000\004\008\000\000\000\114\101\113\117\105\114\101\000\004\006\000\000\000\100\101\098\117\103\000\004\007\000\000\000\114\097\119\103\101\116\000\004\003\000\000\000\095\071\000\004\004\000\000\000\106\105\116\000\004\004\000\000\000\111\102\102\000\004\000\000\000\000\000\000\000\001\000\000\000\004\000\000\000\000\000\000\002\001\000\000\000\030\000\128\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\006\000\000\000\006\000\000\000\000\000\000\002\001\000\000\000\030\000\128\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\007\000\000\000\007\000\000\000\000\001\000\002\001\000\000\000\030\000\128\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\008\000\000\000\008\000\000\000\000\000\000\002\001\000\000\000\030\000\128\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000","@stock_steam_boot"))(...))
