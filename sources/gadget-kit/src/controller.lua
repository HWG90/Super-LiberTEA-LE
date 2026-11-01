-- Owns local catalogue leases. Menu callbacks only change preferences; all
-- capture, writes and restoration run here on the game update callback.
local Core = mod.require('src/core.lua')

local M = {}
local BATCH, CLEAN_BATCH, AUDIT_ENTRIES = 8, 1, 1
local AUDIT_INTERVAL = 0.0625 -- Same 16 entries/second, spread across smaller updates.

function M.new(backend, log, unreleased)
    local self = {enabled=false, categories={}, journals={}}
    for _, name in ipairs(Core.categories) do self.categories[name] = true end
    local freezes=mod.require('src/freezes.lua').new(backend)
    function self:set_freezes(values) return freezes:set(values) end
    function self:stop_freezes() freezes:stop() end
    function self:set_unreleased(value)
        if unreleased then return unreleased:set_enabled(value)end
        return value==false, 'Unreleased registration is unavailable'
    end
    local snapshot, plan, next_row, adapter
    local restoring, stopped, stable, last_context = false, false, 0, nil
    local clock, next_poll, next_audit, audit_batch, audit_entry = 0, 0, 0, 1, 1
    local scan_row = 1
    local message = 'Off'
    log = log or function() end
    local function status(text)
        if text ~= message then message = text; log('Goose Gadget Kit: ' .. text) end
    end
    local function discard_plan()
        snapshot, plan, next_row, adapter = nil, nil, nil, nil
        stable, last_context = 0, nil
        audit_batch,audit_entry,scan_row=1,1,1
    end
    local function request_restore(reason)
        restoring = true
        discard_plan()
        status(reason or 'Restoring')
    end
    local function clean_step(limit)
        local attempted = 0
        for index = #self.journals, 1, -1 do
            if attempted >= limit then break end
            local lease = self.journals[index]
            Core.restore(lease.io, lease.journal)
            attempted = attempted + 1
            if Core.status(lease.journal).pending == 0 then table.remove(self.journals, index) end
        end
        if #self.journals > 0 then
            -- Rotate failed leases so unreadable owners cannot starve others.
            if #self.journals > limit then
                for _ = 1, limit do table.insert(self.journals, 1, table.remove(self.journals)) end
            end
            status('Restoration pending; retrying')
            return false
        end
        restoring = false
        next_poll, next_audit, audit_batch = clock + 0.25, clock + 1, 1
        status(self.enabled and not stopped and 'Waiting for local host' or 'Off')
        return true
    end
    function self:set_enabled(value)
        if type(value) ~= 'boolean' then return false, 'Enabled must be boolean' end
        if stopped and value then return false, 'Mod is stopping' end
        if value ~= self.enabled then
            self.enabled = value
            request_restore(value and 'Preparing local overrides' or 'Restoring')
        end
        return true
    end
    function self:set_categories(values)
        if type(values) ~= 'table' then return false, 'Categories must be a table' end
        local allowed, changed = {}, false
        for _, name in ipairs(Core.categories) do allowed[name] = true end
        for name, value in pairs(values) do
            if not allowed[name] or type(value) ~= 'boolean' then return false, 'Invalid category preference' end
        end
        for _, name in ipairs(Core.categories) do
            if type(values[name]) ~= 'boolean' then return false, 'Missing category preference: ' .. name end
            changed = changed or values[name] ~= self.categories[name]
        end
        if changed then
            for _, name in ipairs(Core.categories) do self.categories[name] = values[name] end
            request_restore('Refreshing selected categories')
        end
        return true
    end
    function self:equipment_ready()
        return self.enabled and not stopped and not restoring and snapshot~=nil and next_row==nil
    end
    function self:is_clean() return freezes:is_clean() and #self.journals == 0 and snapshot == nil and (not unreleased or unreleased:is_clean()) end
    function self:status()
        local held=freezes:status()
        return message .. (held~='' and ('; '..held) or '') .. (unreleased and ('; '..unreleased:status()) or '')
    end
    local function same(a, b) return backend:same_context(a, b) == true end
    local function audit()
        if #self.journals == 0 then return true end
        local checked,empty=0,0
        while checked<AUDIT_ENTRIES do
            if audit_batch>#self.journals then audit_batch=1 end
            local entry=self.journals[audit_batch].journal.entries[audit_entry]
            if not entry then
                audit_batch,audit_entry=audit_batch+1,1
                empty=empty+1
                if empty>#self.journals then return true end
            else
                audit_entry=audit_entry+1
                checked=checked+1
                if entry.pending then
                    local ok,valid=pcall(function()
                        local lease=self.journals[audit_batch]
                        -- adapter.read already validates exact record ownership.
                        local current=lease.io.read(entry.row,entry.field)
                        if current==entry.before then
                            -- The game refreshed this exact owned row. Reapply the
                            -- lease directly instead of relocking the whole catalogue.
                            if lease.io.write(entry.row,entry.field,entry.after)~=true then return false end
                            current=lease.io.read(entry.row,entry.field)
                        end
                        return current==entry.after
                    end)
                    if not ok or not valid then return false end
                end
            end
        end
        return true
    end
    -- Also watch rows which were already unlocked during capture. A later
    -- account refresh may relock them without changing any context pointers.
    -- Keep this bounded rather than recapturing the entire catalogue per frame.
    local function reconcile_row()
        if not snapshot or #snapshot.records==0 then return true end
        if scan_row>#snapshot.records then scan_row=1 end
        local row=snapshot.records[scan_row]
        scan_row=scan_row+1
        if not self.categories[row.category] then return true end
        if adapter.matches(row)~=true then return false end
        local state=adapter.read(row,'state')
        if state==nil then return false end
        if state~=1 then return true end
        -- Existing leases own their original bytes and are repaired by audit.
        for _,lease in ipairs(self.journals) do
            for _,entry in ipairs(lease.journal.entries) do
                if entry.pending and entry.row.address==row.address then return true end
            end
        end
        local amount=adapter.read(row,'amount')
        if amount==nil then return false end
        local fresh={address=row.address,identity=row.identity,category=row.category,
            state=state,amount=amount,max_amount=row.max_amount}
        local called,partial=pcall(Core.plan,{fresh},self.categories)
        if not called then return false end
        local journal,why,failed=Core.apply(adapter,partial)
        local owned=journal or failed
        if owned and Core.status(owned).pending>0 then
            self.journals[#self.journals+1]={journal=owned,io=adapter}
        end
        return journal~=nil
    end
    function self:update(dt)
        if unreleased and not stopped then unreleased:update(dt)end
        if not stopped then freezes:update(dt) end
        if type(dt) ~= 'number' or dt ~= dt then dt = 0 end
        clock = clock + math.max(0, math.min(1, dt))
        if restoring then clean_step(CLEAN_BATCH); return end
        if stopped or not self.enabled then status('Off'); return end
        if snapshot then
            -- Guard every application batch and poll an active lease frequently.
            if next_row or clock >= next_poll then
                local current, why = backend:context()
                next_poll = clock + 0.25
                if not current or not same(snapshot.context, current) then
                    request_restore(why or 'Session changed; refreshing')
                    return
                end
            end
            if not next_row and clock >= next_audit then
                next_audit = clock + AUDIT_INTERVAL
                if not audit() or not reconcile_row() then request_restore('Catalogue refreshed; reacquiring'); return end
            end
            if next_row then
                local rows = {}
                for i = next_row, math.min(#plan.rows, next_row + BATCH - 1) do rows[#rows + 1] = plan.rows[i] end
                if #rows > 0 then
                    local partial = Core.plan(rows, self.categories)
                    local journal, why, failed = Core.apply(adapter, partial)
                    local owned = journal or failed
                    if owned and Core.status(owned).pending > 0 then
                        self.journals[#self.journals + 1] = {journal=owned, io=adapter}
                    end
                    if not journal then request_restore('Apply interrupted: ' .. tostring(why)); return end
                end
                next_row = next_row + BATCH
                if next_row > #plan.rows then
                    next_row = nil
                    status(string.format('On: %d local catalogue rows', #plan.rows))
                end
            end
            return
        end
        if clock < next_poll then return end
        next_poll = clock + 0.25
        local current, why = backend:context()
        if not current then
            stable, last_context = 0, nil
            status(why or 'Waiting for local host')
            return
        end
        stable = last_context and same(last_context, current) and stable + 1 or 1
        last_context = current
        if stable < 2 then status('Waiting for catalogue stability'); return end
        local captured, problem = backend:capture()
        if not captured then
            -- A stable session with a reader error needs a delayed retry, not
            -- an alternating stability/error message on every other update.
            next_poll = clock + 2
            status(problem or 'Capture unavailable')
            return
        end
        if not same(current, captured.context) then
            stable, next_poll = 0, clock + 2
            status('Catalogue changed during capture')
            return
        end
        local called, prepared = pcall(Core.plan, captured.records, self.categories)
        if not called then
            next_poll = clock + 2
            status('Invalid catalogue: ' .. tostring(prepared))
            return
        end
        snapshot, plan, next_row = captured, prepared, 1
        adapter = backend:adapter(snapshot)
        status('Applying local catalogue overrides')
    end
    function self:shutdown()
        stopped = true
        freezes:stop()
        self.enabled = false
        local released,problem=true,nil
        if unreleased then released,problem=unreleased:shutdown()end
        if not restoring then request_restore('Restoring') end
        if clean_step(CLEAN_BATCH) and released then return true end
        if not released then return false,problem end
        return false, 'Owned restoration is pending'
    end
    return self
end
return M
