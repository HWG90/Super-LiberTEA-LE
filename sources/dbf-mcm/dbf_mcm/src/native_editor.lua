-- Native Mod Bindings Menu editor. MBM owns the action and evaluates it; this
-- writes the desktop (keyboard/mouse) mappings of a native MBM action into the
-- game's live binding record the way MBM's own sweep writes records (header
-- verified, the whole mapping list rewritten, then the count). Controller
-- mappings are preserved. MCM keeps each edit and applies it again in a later
-- session while the game still loads the list the edit replaced; a later
-- native MODS-page edit takes priority and retires the MCM edit.
--
-- Encodings read live on build 26088801 (MBM's sweep documents the keyboard
-- one): flags = device | input type << 4 | trigger << 16 | 0xff00 (any device
-- slot) | engine button index << 20. Keyboard: device 3, key word 49 + virtual
-- key. Mouse button: device 4, key word 32 + mouse index (left, right, middle,
-- extra_1, extra_2). Wheel: device 4, input type 8, trigger 7 up / 8 down; a
-- wheel mapping is copied from one the game wrote, never made up.
local M={}
local KEYBOARD,MOUSE,BUTTON,WHEEL=3,4,4,8
local KEY_BASE,MOUSE_BASE,MAX_MAPPINGS=49,32,16
local MOUSE_INDEX={[1]=0,[2]=1,[4]=2,[5]=3,[6]=4}
local WHEEL_TRIGGER={[256]=7,[257]=8}
-- The game's own capture writes threshold 0.2 for mouse buttons and 0 for keys.
local MOUSE_THRESHOLD=0x3e4ccccd
local function device(m)return m[1]%16 end
local function input_type(m)return math.floor(m[1]/16)%16 end
local function desktop(m)local d=device(m);return d==KEYBOARD or d==MOUSE end
function M.key_name(code,vk_name)
    local vk=code-KEY_BASE
    if vk>=7 and vk<=255 and type(vk_name)=='function'then return vk_name(vk)end
end
function M.mouse_name(mapping)
    if mapping.input==BUTTON then
        local index=mapping.key-MOUSE_BASE
        if index>=0 and index<=4 then return 'Mouse '..(index+1)end
    elseif mapping.input==WHEEL then
        if mapping.trigger==7 then return 'MWheel Up'elseif mapping.trigger==8 then return 'MWheel Down'end
    end
end
-- FNV-1a over the desktop mappings' words (key word low half, as MBM compares).
local function fingerprint(bit,list)
    local hash=2166136261
    for _,m in ipairs(list)do if desktop(m)then
        for _,word in ipairs({m[1],m[2]%65536,m[3],m[4],m[5]})do
            hash=bit.bxor(bit.tobit(hash),bit.tobit(word));hash=bit.tobit(hash*403+bit.lshift(hash,24))
        end
    end end
    if hash<0 then hash=hash+4294967296 end
    return hash
end
function M.new(store,log,options)
    log=log or function()end;options=options or {}
    -- Names by variable, as War Journalist does: LLL refuses a script with a
    -- literal ffi/bit require on a platform that reports no native FFI.
    local ffi_name,bit_name='ffi','bit'
    local loaded,ffi=pcall(require,ffi_name)
    local bit_loaded,bit=pcall(require,bit_name)
    local writable=loaded and bit_loaded and type(ffi)=='table'and type(ffi.cast)=='function'
    local self={};local reader;local saved=store.load('native_bindings')
    -- resolved: saved edits settled this session, by stored key.
    local resolved,wheel_template,attempts={},nil,0
    local function key(id)return(id:gsub('[^%w_-]','_'))end
    local function persist()
        local ok,why=store.save('native_bindings',saved)
        if not ok then log('MCM native binding save failed: '..tostring(why))end
        return ok,why
    end
    local function forget(id)
        local k=key(id);saved[k..'_code'],saved[k..'_base'],saved[k..'_left']=nil,nil,nil
    end
    local function remember_wheel(list)
        for _,m in ipairs(list)do if device(m)==MOUSE and input_type(m)==WHEEL then wheel_template=m;return end end
    end
    -- The one desktop mapping an MCM input code makes, or nil and a reason.
    local function mapping(code)
        if code>=7 and code<=255 and not MOUSE_INDEX[code]then
            return {0x43+0xff00+code*1048576,KEY_BASE+code,0,0,0}
        end
        local index=MOUSE_INDEX[code]
        if index then return {0x44+0xff00+index*1048576,MOUSE_BASE+index,0,0,MOUSE_THRESHOLD}end
        local trigger=WHEEL_TRIGGER[code]
        if trigger then
            local t=wheel_template
            if not t then return nil,'Bind a wheel direction once in Options > MODS; MCM then copies it'end
            local flags=t[1]-(math.floor(t[1]/65536)%16)*65536+trigger*65536
            return {flags,t[2],trigger,t[4],t[5]}
        end
        return nil,'This input cannot be bound natively'
    end
    -- Controller mappings unchanged; the new desktop mapping takes the place
    -- of the first desktop mapping it replaces (else it goes last).
    local function edited(list,code)
        local result,slot={},nil
        for _,m in ipairs(list)do
            if not desktop(m)then result[#result+1]=m elseif not slot then slot=#result+1 end
        end
        if code~=0 then
            local m,why=mapping(code);if not m then return nil,why end
            table.insert(result,slot or #result+1,m)
        end
        if #result>MAX_MAPPINGS then return nil,'The binding has too many mappings'end
        return result
    end
    local function write(record,bucket,list)
        local words=ffi.cast('uint32_t *',bucket)
        for index=0,MAX_MAPPINGS-1 do
            local m=list[index+1]
            for word=0,4 do words[2+index*5+word]=m and m[word+1]or 0 end
        end
        words[1]=#list
        local check,after=reader.raw(record)
        if check~=bucket or #after~=#list then return false,'Binding did not verify after writing'end
        for index,m in ipairs(list)do for word=1,5 do
            if after[index][word]~=m[word]then return false,'Binding did not verify after writing'end
        end end
        return true,after
    end
    function self.poll(host,current)reader=current end
    function self.release()reader=nil end
    function self.available(record)
        if not writable then return false,'Native editing needs the LuaJIT runtime'end
        if not reader then return false,'Binding provider is not ready'end
        local bucket,list=reader.raw(record)
        if not bucket then return false,list end
        remember_wheel(list);return true
    end
    function self.bind(record,code)
        local available,why=self.available(record);if not available then return false,why end
        if WHEEL_TRIGGER[code]and not wheel_template then
            for _,other in ipairs(reader.order())do
                if type(other)=='table'and not other.extended then
                    local found,list=reader.raw(other);if found then remember_wheel(list)end
                    if wheel_template then break end
                end
            end
        end
        local bucket,list=reader.raw(record)
        local next_list,problem=edited(list,code);if not next_list then return false,problem end
        local k=key(record.id)
        local base=saved[k..'_base']
        if base==nil or not resolved[k]then base=fingerprint(bit,list)end
        local ok,after=write(record,bucket,next_list);if not ok then return false,after end
        saved[k..'_code'],saved[k..'_base'],saved[k..'_left']=code,base,fingerprint(bit,after)
        resolved[k]=true
        persist()
        log('MCM bound '..record.id..' natively')
        return true,code==0 and 'Desktop binding cleared'or 'Binding saved'
    end
    -- Applies saved edits once per session, after MBM has swept the action (its
    -- first sweep can drop inherited developer mappings), never before.
    -- Pending while a saved edit is unsettled, for two minutes of attempts.
    function self.pending()
        if not writable or attempts>=120 then return false end
        for name in pairs(saved)do
            local k=name:match('^(.*)_code$')
            if k and not resolved[k]then return true end
        end
        return false
    end
    function self.restore()
        attempts=attempts+1
        if not writable or not reader then return end
        local swept=reader.state.swept_counts or {}
        local changed=false
        for _,record in ipairs(reader.order())do
            local k=type(record)=='table'and not record.extended and type(record.id)=='string'and key(record.id)
            local code=k and saved[k..'_code']
            if code and not resolved[k]and swept[record.code]~=nil then
                local bucket,list=reader.raw(record)
                if bucket then
                    remember_wheel(list)
                    local found=fingerprint(bit,list)
                    if found==saved[k..'_left']then
                        -- The game saved the edit: it now loads this list.
                        resolved[k]=true
                        if saved[k..'_base']~=found then saved[k..'_base']=found;changed=true end
                    elseif found==saved[k..'_base']then
                        local next_list=edited(list,code)
                        local ok=next_list and write(record,bucket,next_list)
                        resolved[k]=true
                        if ok then log('MCM restored the binding of '..record.id)
                        else log('MCM could not restore the binding of '..record.id)end
                    else
                        -- The player rebound it on the native MODS page since.
                        forget(record.id);changed=true;resolved[k]=true
                        log('MCM kept the MODS-page binding of '..record.id)
                    end
                end
            end
        end
        if changed then persist()end
    end
    return self
end
return M
