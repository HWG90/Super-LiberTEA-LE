-- Mod Bindings Menu discovery and optional native keyboard editor. MBM owns
-- actions and trigger evaluation; the editor persists MCM keyboard overrides.
local M={}
local function upvalue(fn,wanted)
    if type(fn)~='function'or not debug or type(debug.getupvalue)~='function'then return end
    for index=1,64 do
        local ok,name,value=pcall(debug.getupvalue,fn,index)
        if not ok or not name then return end
        if name==wanted then return value end
    end
end
local function integer(value,maximum)
    return type(value)=='number'and value==value and value%1==0 and value>=0 and value<=maximum
end
local function text(value,fallback)
    if type(value)~='string'or value==''or #value>512 or value:find('[%c]')then return fallback end
    return value
end
local function backend(host)
    if type(host)~='table'or host.api~=1 or not(type(host.version)=='number'and host.version>=3) then return nil,'unsupported provider' end
    local state=upvalue(host.register_binding,'state')
    local header=upvalue(host.is_down,'live_header')
    local read=upvalue(header,'read_words')
    local words=upvalue(header,'words')
    if type(state)~='table'or type(state.registry)~='table'or type(state.order)~='table'
        or upvalue(host.is_down,'state')~=state
        or not integer(host.capacity,512)or #state.order>host.capacity
        or state.extended_order~=nil and(type(state.extended_order)~='table'or #state.extended_order>512)then return nil,'unsupported registry'end
    local native=upvalue(header,'state')==state and type(header)=='function'and type(read)=='function'
        and(type(words)=='cdata'or type(words)=='table')
    -- A v4 provider containing only SDK-backed registrations has no native
    -- header reader. Its documented public APIs are sufficient; never emulate
    -- native memory or reinterpret a native record as an extended binding.
    local portable=not native and host.version>=4 and #state.order==0
        and type(state.extended_order)=='table'and type(host.binding)=='function'and type(host.binding_info)=='function'
    if not native and not portable then return nil,'unsupported registry'end
    local reader={state=state,portable=portable}
    function reader.order()
        local result={};for _,record in ipairs(state.order)do result[#result+1]=record end
        for _,record in ipairs(state.extended_order or {})do result[#result+1]=record end
        return result
    end
    function reader.snapshot(record)
        if state.registry[record.id]~=record then return nil,'Binding registration changed'end
        if record.extended then
            if portable then
                local info=host.binding_info(record.id)
                if type(info)~='table'or info.backend~='extended'then return nil,'Extended provider is not ready'end
            end
            local bindings=host.binding(record.id);if not bindings then return nil,'Extended binding unavailable' end
            local mappings={};for _,value in ipairs(bindings)do mappings[#mappings+1]={display=(value.device or '')..' '..tostring(value.button or '')..' ('..tostring(value.trigger or 'press')..')'}end
            return mappings
        end
        if not state.build_rows then return nil,'Native bindings not ready' end
        if state.registry[record.id]~=record then return nil,'Binding registration changed' end
        local bucket,count=header(record);count=tonumber(count)
        if not bucket or not integer(count,16)then return nil,'Native binding unavailable' end
        local function matches()
            return read(bucket,8)and tonumber(words[0])==record.code and tonumber(words[1])==count
        end
        if not matches()then return nil,'Native binding changed; refreshing' end
        local mappings={}
        for index=0,count-1 do
            if not read(bucket+8+index*20,20)then return nil,'Native binding unavailable' end
            -- Copy the shared reader buffer before another provider read.
            local flags,key,trigger,combine,threshold=tonumber(words[0]),tonumber(words[1]),tonumber(words[2]),tonumber(words[3]),tonumber(words[4])
            if not integer(flags,4294967295)or not integer(key,4294967295)
                or not integer(trigger,4294967295)or not integer(combine,4294967295)
                or not integer(threshold,4294967295)then return nil,'Native mapping unavailable' end
            mappings[#mappings+1]={device=flags%16,input=math.floor(flags/16)%16,
                trigger_flags=math.floor(flags/65536)%16,key=key%65536,
                trigger=trigger,combine=combine,threshold_bits=threshold}
        end
        if not matches()then return nil,'Native binding changed; refreshing' end
        return mappings
    end
    -- The verified record address and each mapping's five words, for the
    -- native editor. The header is checked before and after the reads.
    function reader.raw(record)
        if not native or record.extended or not state.build_rows or state.registry[record.id]~=record then return nil,'Native binding unavailable' end
        local bucket,count=header(record);count=tonumber(count)
        if not bucket or not integer(count,16)then return nil,'Native binding unavailable' end
        local function matches()
            return read(bucket,8)and tonumber(words[0])==record.code and tonumber(words[1])==count
        end
        if not matches()then return nil,'Native binding changed; refreshing' end
        local list={}
        for index=0,count-1 do
            if not read(bucket+8+index*20,20)then return nil,'Native binding unavailable' end
            list[#list+1]={tonumber(words[0]),tonumber(words[1]),tonumber(words[2]),tonumber(words[3]),tonumber(words[4])}
        end
        if not matches()then return nil,'Native binding changed; refreshing' end
        return bucket,list
    end
    return reader
end
local function readable_id(value)
    value=text(value,'Native binding'):match('[^%.:/]+$')or 'Native binding'
    return value:gsub('[_%-]+',' '):gsub('(%a)([%w]*)',function(first,rest)return first:upper()..rest end)
end
-- Confirmed native ship-default codes. These are game input IDs, not the
-- virtual-key IDs accepted by Stingray Keyboard.button_name. Do not guess an
-- offset for unknown/custom mappings; a verified resolver may extend this.
local native_key_names={[58]='Tab',[161]='F1',[165]='F5',[166]='F6',[167]='F7',[168]='F8'}
function M.key_name(code)return native_key_names[code]end
local native_labels={
    [0xb46c8096]='Galactic Map',[0x19e97f02]='Armory',
    [0x2716885e]='Ship Management',[0xe89a91ef]='Hellpod Deployment',
}
local function binding_label(record,options)
    local resolved=text(record.text,text(record.label,nil))
    if not resolved and type(options.localize)=='function'and type(record.label)=='number'then
        local ok,value=pcall(options.localize,record.label)
        if ok then resolved=text(value,nil)end
    end
    return resolved or native_labels[record.label]or readable_id(record.id)
end
local native_description='Mod Bindings Menu owns this binding. Rebind in Options > Mouse & Keyboard > MODS. MCM displays the assigned keys without changing them.'
local editor_description='Select a binding and press its new key. Escape cancels. Right-click > Unbind key clears the keyboard mapping. MBM evaluates the native action; MCM persists keyboard edits. Later native MODS-page edits take priority.'
local function readout(mappings,key_name,mouse_key_name)
    if #mappings==0 then return 'Not bound' end
    local lines,seen={},{}
    for _,mapping in ipairs(mappings)do
        local name=mapping.device==3 and 'Unknown keyboard key'or 'Other input binding'
        if mapping.display then name=mapping.display end
        if mapping.device==3 and type(key_name)=='function'then
            local ok,value=pcall(key_name,mapping.key)
            if ok then name=text(value,name)end
        end
        local mouse
        if mapping.device==4 and type(mouse_key_name)=='function'then
            local ok,value=pcall(mouse_key_name,mapping);if ok and value then mouse=true;name=text(value,name)end
        end
        if not mapping.display and not(mouse and mapping.input==8)and (mapping.trigger~=0 or mapping.trigger_flags~=0)then name=name..' (Custom trigger)'end
        if not seen[name]then seen[name]=true;lines[#lines+1]=name end
    end
    return table.concat(lines,', ')
end
local function group_id(category)
    local hash=5381;for index=1,#category do hash=(hash*33+category:byte(index))%4294967296 end
    return 'native_bindings_'..string.format('%08x',hash)
end
function M.new(api,log,options)
    log=log or function()end;options=options or {}
    local has_editor=options.editor~=nil or options.extended_editor==true
    local self={};local owner,reader,signature;local handles,rows={},{};local status='host=false';local total=0
    local function clear()
        for _,handle in ipairs(handles)do handle.unregister()end
        handles,rows={},{};signature=nil;total=0
    end
    function self.release()clear();owner,reader=nil,nil;status='host=false';if options.editor then options.editor.release()end end
    function self.diagnostic()return status..' imported='..total end
    -- Saved native edits are applied in the background, without the menu open.
    function self.restore(host)
        if not options.editor or not options.editor.pending()then return end
        self.poll(host)
        options.editor.restore()
    end
    function self.poll(host,visible_category)
        if host~=owner then clear();owner=host;reader=nil end
        if not reader and host then local why;reader,why=backend(host);status=reader and 'host=true' or 'host=true '..why end
        if not reader then return end
        if options.editor then options.editor.poll(host,reader)end
        local groups,entries,parts={},{},{}
        for _,record in ipairs(reader.order())do
            if type(record)~='table'or type(record.id)~='string'or reader.state.registry[record.id]~=record
                or reader.portable and record.extended~=true
                or not record.extended and (not integer(record.code,4294967295)or not integer(record.group,65535)
                or not integer(record.action,65535)or record.code~=record.group*65536+record.action)then
                clear();status='host=true unsupported registration';return
            end
            local category=text(record.category,'Other mods'):upper()
            if #category>256 then category='Other mods'end
            local label=binding_label(record,options)
            local has_parent=false
            for id,mod in pairs(api.mods)do
                if not id:match('^native_bindings_')and mod.name:upper()==category and not mod.parent_name then has_parent=true;break end
            end
            groups[category]=groups[category]or {has_parent=has_parent}
            groups[category][#groups[category]+1]={record=record,label=label}
            parts[#parts+1]=category..'\0'..record.id..'\0'..label..'\0'..tostring(record)..'\0'..tostring(has_parent)
        end
        table.sort(parts);local next_signature=table.concat(parts,'\1')
        if signature~=next_signature then
            clear()
            for category in pairs(groups)do entries[#entries+1]=category end;table.sort(entries)
            for _,category in ipairs(entries)do
                local controls={{type='text',label=has_editor and 'Select an editable binding, then press its new input. Escape cancels.'or 'Rebind in the game\'s MODS controls tab.'}}
                local bindings=groups[category];table.sort(bindings,function(a,b)return a.record.id<b.record.id end)
                local group_rows={}
                for index,entry in ipairs(bindings)do
                    local value={id='binding_'..index,type='text',label=entry.label,description=native_description,
                        text_role='selection',native_binding_value='Unavailable',native_binding_id=entry.record.id}
                    controls[#controls+1]=value;group_rows[#group_rows+1]={record=entry.record,id=value.id}
                end
                local id=group_id(category)
                -- Never overwrite a registration owned by another author.
                if api.mods[id]then status='host=true registration ID occupied';clear();return end
                local has_parent=bindings.has_parent
                local handle=api.register({id=id,name=has_parent and category..' Keybindings'or category,
                    parent_name=has_parent and category or nil,description=has_editor and editor_description or native_description,
                    pages={{id='keybindings',name='Keybindings',require_confirmation=false,controls=controls}}})
                local mod=api.mods[id];mod.pages[1].native_binding_category=category;mod.pages[1].native_binding_description=has_editor and editor_description or native_description
                for _,row in ipairs(group_rows)do
                    for _,control in ipairs(mod.pages[1].controls)do if control.id==row.id then row.control=control;break end end
                    row.category=category;rows[#rows+1]=row
                    if options.editor and not row.record.extended or has_editor and row.record.extended and type(host.set_binding)=='function'and type(options.input_spec)=='function'then
                        local record,control=row.record,row.control
                        control.native_binding_available=function()
                            if host~=owner or reader.state.registry[record.id]~=record then return false,'Binding provider changed'end
                            if record.extended then
                                local ok,value=pcall(reader.snapshot,record)
                                return ok and value~=nil,'Binding provider is not ready'
                            end
                            return options.editor.available(record)
                        end
                        control.native_binding_bind=function(vk)
                            if host~=owner or reader.state.registry[record.id]~=record then return false,'Binding provider changed'end
                            local ok,why
                            if record.extended then
                                local ready,value=pcall(reader.snapshot,record)
                                if not ready or not value then return false,'Binding provider is not ready'end
                                local spec,error_text=options.input_spec(vk)
                                if not spec then return false,error_text end
                                local current=host.binding(record.id)
                                if type(current)~='table'then return false,'Binding is unavailable'end
                                local alternatives={}
                                -- Editing the desktop shortcut must not erase controller alternatives.
                                local desktop
                                for _,value in ipairs(current)do
                                    if value.device=='controller'then alternatives[#alternatives+1]=value
                                    elseif desktop and vk~=0 then return false,'Multiple desktop alternatives require the owner editor'
                                    else desktop=value end
                                end
                                if vk~=0 then
                                    if desktop then
                                        spec.trigger=desktop.trigger or spec.trigger
                                        if type(desktop.modifiers)=='table'then
                                            spec.modifiers={};for i,name in ipairs(desktop.modifiers)do spec.modifiers[i]=name end
                                        end
                                    end
                                    alternatives[#alternatives+1]=spec
                                end
                                ok,why=host.set_binding(record.id,alternatives)
                            else ok,why=options.editor.bind(record,vk)end
                            if ok then
                                local called,mappings=pcall(reader.snapshot,record)
                                if called and mappings then control.native_binding_value=readout(mappings,options.key_name or M.key_name,options.mouse_key_name);control.native_binding_snapshot=mappings;api.revision=api.revision+1 end
                            end
                            return ok,why
                        end
                        control.description=record.extended and 'Select this binding, then press a key, mouse button, or wheel direction. MBM saves and evaluates the binding. Controller alternatives are preserved. Right-click > Unbind key clears desktop inputs.'or 'Select this binding, then press a key, Mouse 1-5, or a wheel direction. Right-click > Unbind key clears the desktop mapping. Controller mappings are preserved. Wheel directions use native wheel triggers; switching between wheel and button input starts a plain Press binding. Later native MODS page edits take priority.'
                    end
                    row.description=row.control.description
                end
                handles[#handles+1]=handle
            end
            signature=next_signature;total=#rows;status='host=true'
            log('Imported '..total..' native bindings in '..#handles..' categories')
        end
        if not visible_category then return end
        for _,row in ipairs(rows)do if visible_category==true or row.category==visible_category:upper()then
            local previous_value,previous_description=row.control.native_binding_value,row.control.description
            local ok,mappings,why=pcall(reader.snapshot,row.record)
            row.control.native_binding_value=ok and mappings and readout(mappings,options.key_name or M.key_name,options.mouse_key_name)or 'Unavailable'
            row.control.native_binding_snapshot=ok and mappings or nil
            row.control.description=row.description or native_description
            if not(ok and mappings)then row.control.description=row.control.description..'\n\n'..(ok and why or 'Native binding unavailable')end
            if previous_value~=row.control.native_binding_value or previous_description~=row.control.description then api.revision=api.revision+1 end
        end end
    end
    return self
end
return M
