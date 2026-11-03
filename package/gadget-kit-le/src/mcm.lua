-- MCM registration owns preferences; native work stays in the spawner's update.
-- Gadget Kit LE: the full kit's mcm.lua with the Unlocks and Gameplay pages removed.
local FirstPerson=mod.require('src/first_person.lua')
local M = {}
local ID = 'goose_temporary_unlocks'
function M.new(log, spawner)
    local self = {provider=nil, handle=nil, stopping=false}
    local elapsed, due, last_problem = 0, true, nil
    log = log or function() end
    local function problem(why)
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
        local spawn_label=spawner and spawner:status() or ''
        local slot_label=spawner and spawner:stratagem_status() or ''
        local stamp=spawn_label..slot_label..tostring(self.stopping)
        if self.status_stamp==stamp and self.status_record==record then return end
        self.status_stamp,self.status_record=stamp,record
        for _, page in ipairs(record.pages or {}) do
            for _, control in ipairs(page.controls or {}) do
                if control.id == 'spawner_status' then control.label = 'Status: ' .. spawn_label end
                if control.id == 'spawner_stratagem_status' then control.label = 'Status: ' .. slot_label end
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
            local done, why = unregister()
            if not done then return false, why end
            if not supported then return problem('Waiting for DBF-MCM') end
            local pages={}
            if spawner then
                -- Buttons only queue intent; on_update performs the guarded native steps once
                -- MCM is closed, so the button closes MCM after a request is accepted. MCM shows a
                -- button's string result as its notice and drops a second value, so a refusal
                -- returns its reason alone (a false, reason pair read "Action completed").
                local function equip()
                    if self.stopping or self.provider ~= rawget(_G, 'DBFMCM') then return 'Spawner settings are not ready' end
                    local accepted, why = spawner:queue(self.handle.get('spawner_weapon'))
                    if accepted ~= true then return why end
                    if type(self.provider.close) == 'function' then
                        local closed, reason = self.provider.close()
                        if closed == false then return reason or 'Close MCM to deliver the queued weapon' end
                    end
                    return true
                end
                local function add_stratagem()
                    if self.stopping or self.provider ~= rawget(_G, 'DBFMCM') then return 'Spawner settings are not ready' end
                    local accepted, why = spawner:queue_stratagem(self.handle.get('spawner_stratagem'))
                    if accepted ~= true then return why end
                    if type(self.provider.close) == 'function' then
                        local closed, reason = self.provider.close()
                        if closed == false then return reason or 'Close MCM to add the queued stratagem' end
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
                description='Support weapon spawner and first person for your local game session.',
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
        self:refresh_status()
    end
    function self:shutdown()
        self:begin_shutdown()
        return unregister()
    end
    return self
end
M.definitions = {}
return M
