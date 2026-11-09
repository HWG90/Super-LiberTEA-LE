-- Recognize the selection ownership contract, never a HUD+ version string.
-- Future presentation changes may alter observe/put without changing handoff.
local function hud_plus_compat(active)
    local self={status='HUD+ not detected',scans=0}
    local top,runtimes,seen_programs,seen_features=nil,{},{},{}
    local installed=setmetatable({}, {__mode='k'})
    local bindings={}
    -- Only owner-provided lifecycle methods perform cleanup. Each contract
    -- fingerprints its Lua helper closures too, including held-input release.
    -- string.dump follows the VM's bytecode frame layout, so each pin holds the
    -- same reviewed HUD+ code twice: fr1 for non-GC64 LuaJIT (the original game's)
    -- and fr2 for GC64 (LLL's runtime). A layout without a pin never matches.
    local lifecycle_order={'prepare','vanilla','drop','close'}
    local lifecycle={prepare={fr1='0f6d0b5c',fr2='130b0b6c'},vanilla={fr1='c5fd46ff',fr2='d99d4712'},
        drop={fr1='057f16e2',fr2='0caa16f1'},close={fr1='8b14074f',fr2='8d6e075b'}}
    local picker_contracts={
        {name='immediate-picker',methods={reset={fr1='594d0655'}},absent={'frame','leave'}},
        {name='paced-picker',methods={reset={fr1='4dcd1a05',fr2='53e91a11'},frame={fr1='ae220d38',fr2='b2030d43'},
            leave={fr1='27a70348',fr2='287f0350'}},
            helpers={reset={start_cell={fr1='f0e31473',fr2='f5f41480'}},frame={unblock_aim={fr1='789b2088',fr2='82062099'}}}},
    }
    -- A LuaJIT dump starts ESC 'L' 'J', version, flags; flag 0x08 marks FR2.
    local ok,header=pcall(string.dump,function()end,true)
    if ok and type(header)=='string' and header:sub(1,3)=='\27LJ' and #header>=5 then
        self.layout=math.floor(header:byte(5)/8)%2==1 and 'fr2' or 'fr1'
    end
    local function member(t,k)
        if type(t)~='table' then return nil end
        local v=rawget(t,k)
        if v~=nil then return v end
        local mt=getmetatable(t)
        local index=type(mt)=='table' and rawget(mt,'__index')
        return type(index)=='table' and rawget(index,k) or nil
    end
    local function fingerprint(fn)
        if type(fn)~='function' then return nil end
        local ok,bytes=pcall(string.dump,fn,true)
        if not ok then return nil end
        local a,b=1,0
        for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
        return string.format('%08x',b*65536+a)
    end
    local function pinned(fn,pin)
        local want=self.layout and pin and pin[self.layout]
        return want~=nil and fingerprint(fn)==want
    end
    local function helpers_match(fn,expected)
        local found={}
        if not debug or type(debug.getupvalue)~='function' then return false end
        for i=1,64 do
            local name,value=debug.getupvalue(fn,i)
            if not name then break end
            if type(value)=='function' then
                if not expected or not pinned(value,expected[name]) then return false end
                found[name]=true
            end
        end
        for name in pairs(expected or {}) do if not found[name] then return false end end
        return true
    end
    local function picker_contract(pick)
        if pick==nil then return {name='no-picker'} end
        if type(pick)~='table' then return end
        for _,contract in ipairs(picker_contracts) do
            local matches=true
            for method,pin in pairs(contract.methods) do
                local fn=member(pick,method)
                if not pinned(fn,pin) or not helpers_match(fn,contract.helpers and contract.helpers[method]) then matches=false;break end
            end
            for _,method in ipairs(contract.absent or {}) do if member(pick,method)~=nil then matches=false end end
            if matches then return contract end
        end
    end
    local function bind(program)
        local feature=member(member(program,'world_hud'),'stratagem')
        if not feature then return end
        if installed[feature] then self.status=installed[feature];return end
        local function unsupported(reason)
            self.status='HUD+ stratagem adapter unsupported: '..reason..' ('..(self.layout or 'no LuaJIT')..' bytecode)'
        end
        for _,method in ipairs(lifecycle_order) do
            local fn=member(feature,method)
            if not pinned(fn,lifecycle[method]) or not helpers_match(fn) then unsupported('lifecycle '..method);return end
        end
        local pick=member(feature,'pick')
        local contract=picker_contract(pick)
        if not contract then unsupported('picker cleanup contract');return end
        for _,method in ipairs({'observe','put'}) do
            if type(member(feature,method))~='function' then unsupported('missing '..method);return end
        end
        local inputs=member(feature,'inputs')
        if type(inputs)~='table' or type(member(inputs,'observe'))~='function'
            or type(member(feature,'list'))~='table' or type(member(feature,'card'))~='table' then
            unsupported('selection feature shape');return
        end
        local originals={prepare=rawget(feature,'prepare'),observe=rawget(feature,'observe'),put=rawget(feature,'put')}
        local prepare,observe,put=feature.prepare,feature.observe,feature.put
        local vanilla,drop=feature.vanilla,feature.drop
        local reset=pick and member(pick,'reset')
        local frame=pick and member(pick,'frame')
        local yielding=false
        local function takeover(owner)
            if yielding then return end
            -- reset restores a held menu trigger; frame releases consumed aim.
            -- Capture the verified instance methods, not mutable global classes.
            if reset then reset(pick) end
            if frame then frame(pick,false) end
            vanilla(owner,false);drop(owner);owner.segment=false
            yielding=true
        end
        feature.prepare=function(owner,enabled,...)
            if active() then takeover(owner);enabled=false else yielding=false end
            return prepare(owner,enabled,...)
        end
        feature.observe=function(owner,enabled,world,player,players,arrow,cell,...)
            if not active() then
                yielding=false
                return observe(owner,enabled,world,player,players,arrow,cell,...)
            end
            takeover(owner)
            -- Preserve the extension's shared arrow input, while keeping the
            -- competing list/picker idle. No original observe/drop loop.
            if arrow then inputs:observe(owner.panel,world,player,players,cell) end
            owner.world=world
            return inputs.showing
        end
        feature.put=function(owner,...)
            if not active() then yielding=false;return put(owner,...) end
            takeover(owner)
        end
        bindings[#bindings+1]={feature=feature,originals=originals,wrappers={prepare=feature.prepare,observe=feature.observe,put=feature.put}}
        self.contract=contract.name
        self.status='HUD+ '..contract.name..' list/picker yield to ASS while enabled'
        installed[feature]=self.status
    end
    function self.close()
        for _,binding in ipairs(bindings) do
            for name,fn in pairs(binding.wrappers) do
                if rawget(binding.feature,name)~=fn then return false,'HUD+ handoff was replaced by another owner' end
            end
        end
        for _,binding in ipairs(bindings) do
            for name in pairs(binding.wrappers) do rawset(binding.feature,name,binding.originals[name]) end
        end
        bindings={}
        return true
    end
    function self.refresh(update)
        if update~=top and self.scans<8 and debug and debug.getupvalue then
            top=update;self.scans=self.scans+1
            local queue,seen,known={{fn=update,depth=0}},{},{}
            for _,runtime in ipairs(runtimes) do known[runtime]=true end
            local at=1
            while at<=#queue and at<=128 do
                local node=queue[at];at=at+1
                if type(node.fn)=='function' and not seen[node.fn] then
                    seen[node.fn]=true
                    for i=1,64 do
                        local name,value=debug.getupvalue(node.fn,i)
                        if not name then break end
                        if name=='runtime' and type(value)=='table' and rawget(value,'installed')==true
                            and type(rawget(value,'program'))=='table' and not known[value] and #runtimes<16 then
                            known[value]=true;runtimes[#runtimes+1]=value
                        elseif type(value)=='function' and node.depth<24 and #queue<128 then
                            queue[#queue+1]={fn=value,depth=node.depth+1}
                        end
                    end
                end
            end
        end
        for _,runtime in ipairs(runtimes) do
            local program=rawget(runtime,'program')
            local feature=member(member(program,'world_hud'),'stratagem')
            if program and (seen_programs[runtime]~=program or seen_features[runtime]~=feature) then
                seen_programs[runtime]=program;seen_features[runtime]=feature
                bind(program)
            end
        end
    end
    -- HUD+'s weapon line draws the game's own option cells for the first three
    -- option slots of the held weapon's data record, the record (and the kind
    -- numbers) the weapon strip reads. Recognized by shape, never by version:
    -- weapon_hud.values holds each slot's sampled {axis,value,output} and
    -- weapon_hud.line its cell nodes. A slot counts while its HUD+ option is on and
    -- its sample is complete: HUD+ draws the cell then, and hides it only while
    -- the weapon row is faded out. Read only; nothing of HUD+'s is changed.
    local weapon_slots={{'functions','function_cell'},{'fire_mode','fire_cell'},{'zeroing','zero_cell'}}
    function self.weapon_cells()
        local cells={}
        for _,runtime in ipairs(runtimes) do
            local hud=member(rawget(runtime,'program'),'weapon_hud')
            local line,values=member(hud,'line'),member(hud,'values')
            if type(values)=='table' and member(line,'parent')~=nil then
                for i,slot in ipairs(weapon_slots) do
                    local sample,node=rawget(values,i),member(member(line,slot[2]),'node')
                    local at=member(node,'at')
                    if member(hud,slot[1])==true and type(sample)=='table' and type(rawget(sample,1))=='number'
                        and rawget(sample,2)~=nil and rawget(sample,3)~=nil and type(at)=='number' and member(node,'live')==true then
                        cells[#cells+1]={kind=rawget(sample,1),at=at}
                    end
                end
            end
        end
        return cells
    end
    return self
end

return {hud_plus_compat=hud_plus_compat}
