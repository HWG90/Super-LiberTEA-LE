-- MCM registration owns preferences; native work stays in controller:update.
local FirstPerson=mod.require('src/first_person.lua')
local M = {}
local ID = 'goose_temporary_unlocks'
local gameplay = {instant_extract=true,passive_ai=true,freeze_timer=true,freeze_health=true,no_reload=true,freeze_ammo=true}
local definitions = {
    {'instant_extract', 'Instant Extraction', false, 'Complete the active shuttle-arrival countdown. Flight and landing animations still run normally.'},
    {'passive_ai', 'Passive AI', false, 'Set the local Player no aggro flag (bit 25). Off clears the flag owned by this toggle.'},
    {'freeze_timer', 'Freeze Mission Timer', false, 'Hold the mission countdown. Off resumes from the held time.'},
    {'freeze_health', 'Freeze Health', false, 'Hold current health for the living local avatar; does not prevent instant death or limb damage.'},
    {'no_reload', 'Inf. Ammo', false, 'Hold loaded rounds for the equipped weapon. Reload once if empty.'},
    {'freeze_ammo', 'Inf. Reserves', false, 'Hold reserve ammunition for the equipped weapon, including its matching ammunition backpack.'},
    {'enabled', 'Enabled', false, 'Temporarily allow local equipment selection while local host. Off restores owned changes.'},
    {'weapons', 'Weapons', true, 'Primary, support, sidearm and throwable weapons in the local catalogue.'},
    {'bodyarmor', 'Armor', true, 'Body armor in the local catalogue.'},
    {'helmets', 'Helmets', true, 'Helmets in the local catalogue.'},
    {'capes', 'Capes', true, 'Capes in the local catalogue.'},
    {'stratagems', 'Stratagems', true, 'Active, selectable stratagems in the local catalogue.'},
}
function M.new(controller, log, spawner, mission)
    local self = {provider=nil, handle=nil, stopping=false}
    local elapsed, due, last_problem = 0, true, nil
    log = log or function() end
    local function problem(why)
        controller:set_enabled(false)
        controller:set_unreleased(false)
        controller:stop_freezes()
        why = tostring(why)
        if why ~= last_problem then log('Goose Gadget Kit MCM: ' .. why); last_problem = why end
        return false, why
    end
    local function registration()
        local records = self.provider and self.provider.mods
        local record = records and records[ID]
        return record and record.handle == self.handle and record or nil
    end
    local function unregister()
        if self.handle then
            local ok, result, why = pcall(self.handle.unregister)
            if not ok or result == false then return problem(ok and (why or 'Unregister refused') or result) end
        end
        self.handle, self.provider = nil, nil
        FirstPerson.attach(nil)
        return true
    end
    function self:refresh_status()
        local record = registration()
        if not record then return end
        local label=controller:status()
        local spawn_label=spawner and spawner:status() or ''
        local slot_label=spawner and spawner:stratagem_status() or ''
        local mission_label=mission and mission:status() or ''
        local stamp=label..spawn_label..slot_label..mission_label..tostring(self.stopping)
        if self.status_stamp==stamp and self.status_record==record then return end
        self.status_stamp,self.status_record=stamp,record
        for _, page in ipairs(record.pages or {}) do
            for _, control in ipairs(page.controls or {}) do
                if control.id == 'runtime_status' or control.id == 'gameplay_status' then control.label = 'Status: ' .. label end
                if control.id == 'spawner_status' then control.label = 'Status: ' .. spawn_label end
                if control.id == 'spawner_stratagem_status' then control.label = 'Status: ' .. slot_label end
                if control.id == 'mission_status' then control.label = 'Status: ' .. mission_label end
            end
        end
        for _, definition in ipairs(definitions) do
            local control = record.controls and record.controls[definition[1]]
            if control then
                control.disabled = self.stopping

            end
        end
    end
    function self:update(dt)
        if self.stopping then self:refresh_status(); return end
        if type(dt) ~= 'number' or dt ~= dt then dt = 0 end
        elapsed = elapsed + math.max(0, math.min(1, dt))
        local api = rawget(_G, 'DBFMCM')
        local supported = type(api) == 'table' and type(api.register) == 'function'
        local removed = self.provider and type(self.provider.mods) == 'table' and not registration()
        if not supported or api ~= self.provider or removed or self.first_person_revision~=FirstPerson.revision() then
            controller:set_enabled(false)
            controller:set_unreleased(false)
            controller:stop_freezes()
            if not controller:is_clean() then return problem('Waiting for restoration before MCM reload') end
            local done, why = unregister()
            if not done then return false, why end
            if not supported then return problem('Waiting for DBF-MCM') end
            local controls, gameplay_controls = {}, {}
            for _, definition in ipairs(definitions) do
                local id, label, default, description = unpack(definition)
                local target=gameplay[id] and gameplay_controls or controls
                target[#target + 1] = {
                    id=id, type='toggle', label=label, default=default, description=description,
                    require_confirmation=false,
                    on_change=function()
                        if not self.stopping and self.provider == api and rawget(_G, 'DBFMCM') == api then due = true end
                    end,
                }
            end
            controls[#controls + 1] = {type='text', label='Equipped weapons and armor are remembered and restored on the ship after restart while Enabled is on.'}
            controls[#controls + 1] = {id='runtime_status', type='text', label='Status: Off'}
            gameplay_controls[#gameplay_controls+1]={id='gameplay_status',type='text',label='Status: Off'}
            if mission then
                -- The button queues one request; on_update completes the objectives.
                local function complete()
                    if self.stopping or self.provider ~= rawget(_G, 'DBFMCM') then return false, 'Mission settings are not ready' end
                    return mission:request()
                end
                gameplay_controls[#gameplay_controls+1]={id='mission_complete', type='button', label='Complete all objectives', require_confirmation=false, on_activate=complete}
                gameplay_controls[#gameplay_controls+1]={type='text', label='Local host in a mission. Completes every unfinished objective, side objectives included, through the game\'s own completion step.'}
                gameplay_controls[#gameplay_controls+1]={id='mission_status', type='text', label='Status: '..mission:status()}
            end
            local pages={{id='general', name='Unlocks', require_confirmation=false, controls=controls},
                {id='gameplay', name='Gameplay', require_confirmation=false, controls=gameplay_controls}}
            if spawner then
                -- Buttons only queue intent; on_update performs the guarded native steps once
                -- MCM is closed, so the button closes MCM after a request is accepted.
                local function equip()
                    if self.stopping or self.provider ~= rawget(_G, 'DBFMCM') then return false, 'Spawner settings are not ready' end
                    local accepted, why = spawner:queue(self.handle.get('spawner_weapon'))
                    if accepted ~= true then return false, why end
                    if type(self.provider.close) == 'function' then
                        local closed, reason = self.provider.close()
                        if closed == false then return false, reason or 'Close MCM to deliver the queued weapon' end
                    end
                    return true
                end
                local function add_stratagem()
                    if self.stopping or self.provider ~= rawget(_G, 'DBFMCM') then return false, 'Spawner settings are not ready' end
                    local accepted, why = spawner:queue_stratagem(self.handle.get('spawner_stratagem'))
                    if accepted ~= true then return false, why end
                    if type(self.provider.close) == 'function' then
                        local closed, reason = self.provider.close()
                        if closed == false then return false, reason or 'Close MCM to add the queued stratagem' end
                    end
                    return true
                end
                pages[#pages+1] = {id='spawner', name='Spawner', require_confirmation=false, controls={
                    {id='spawner_enabled', type='toggle', label='Enabled', default=false, require_confirmation=false,
                        description='Allow support weapon requests. Local host, solo mission, normal on-foot gameplay.',
                        on_change=function() due = true end},
                    {id='spawner_weapon', type='choice', label='Support weapon', presentation='dropdown',
                        choices=spawner:choices(), default=1},
                    {id='spawner_equip', type='button', label='Equip in hands', require_confirmation=false, on_activate=equip},
                    {type='text', label='Replaces your support weapon with the chosen one and its default attachments; the matching backpack comes too.'},
                    {id='spawner_status', type='text', label='Status: Off'},
                    {id='spawner_stratagem', type='choice', label='Fifth stratagem', presentation='dropdown',
                        choices=spawner:stratagem_choices(), default=1},
                    {id='spawner_add_stratagem', type='button', label='Add to mission', require_confirmation=false, on_activate=add_stratagem},
                    {type='text', label='Adds one extra stratagem to this mission, called with its normal code. Once per mission; support weapons load first.'},
                    {id='spawner_stratagem_status', type='text', label='Status: Choose a stratagem'},
                }}
            end
            for _,page in ipairs(FirstPerson.pages())do pages[#pages+1]=page end
            local called, handle = pcall(api.register, {
                id=ID, name='Goose Gadget Kit',
                description='Temporary equipment access for your local game session.',
                pages=pages, on_change=FirstPerson.changed,
            })
            if not called then return problem(handle) end
            if type(handle) ~= 'table' or type(handle.get) ~= 'function' or type(handle.unregister) ~= 'function' then
                return problem('Unsupported MCM handle')
            end
            self.provider, self.handle, due, elapsed = api, handle, true, 0
            FirstPerson.attach(handle)
            self.first_person_revision=FirstPerson.revision()
        end
        if not due and elapsed < 0.25 then return end
        due, elapsed = false, 0
        local values = {}
        for _, definition in ipairs(definitions) do
            local id = definition[1]
            local ok, value = pcall(self.handle.get, id)
            local valid = type(value)=='boolean'
            if not ok or not valid then due = true; return problem(ok and ('Invalid preference: ' .. id) or value) end
            values[id] = value
        end
        local freezes={}
        for id in pairs(gameplay) do freezes[id]=values[id]; values[id]=nil end
        local enabled = values.enabled
        values.enabled = nil
        local accepted, why = controller:set_categories(values)
        if accepted ~= true then return problem(why or 'Categories were refused') end
        accepted, why = controller:set_enabled(enabled)
        if accepted ~= true then return problem(why or 'Enabled was refused') end
        accepted, why = controller:set_freezes(freezes)
        if accepted ~= true then return problem(why or 'Gameplay preferences were refused') end
        if spawner then
            local ok, value = pcall(self.handle.get, 'spawner_enabled')
            if not ok or type(value) ~= 'boolean' then due = true; return problem(ok and 'Invalid preference: spawner_enabled' or value) end
            spawner:set_enabled(value and not self.stopping)
        end
        last_problem = nil
        return true
    end
    function self:begin_shutdown()
        self.stopping = true
        if spawner then spawner:set_enabled(false) end
        if mission then mission:shutdown() end
        controller:set_enabled(false)
        controller:set_unreleased(false)
        controller:stop_freezes()
        self:refresh_status()
    end
    function self:shutdown()
        self:begin_shutdown()
        if not controller:is_clean() then return problem('Owned restoration is pending') end
        return unregister()
    end
    return self
end
M.definitions = definitions
return M
