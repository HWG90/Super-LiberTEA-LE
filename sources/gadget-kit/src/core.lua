-- Pure local-inventory transaction logic. The host owns capture and memory access.
--
-- plan(records, enabled) -> plan (throws for malformed input).
-- apply(io, plan) -> journal, nil; or nil, reason, journal after rollback.
-- restore(io, journal) -> {restored, skipped, failed, pending}.
-- status(journal) -> {pending, active, total}.
--
-- io.matches(row) must return true for the captured owner/identity, false for a
-- definite replacement, and nil or an error when identity cannot be checked.
-- io.read(row, field) returns a uint32. io.write(row, field, value) returns true.
-- Fields are only "state" and "amount". The host must recheck identity in write.
-- A failed apply returns its journal even if rollback remains pending. Keep it
-- and retry restore before starting another transaction or dropping the host.

local M = {}
local categories = { 'weapons', 'bodyarmor', 'helmets', 'capes', 'stratagems' }
local allowed = {}
for _, name in ipairs(categories) do allowed[name] = true end
M.categories = categories

local function integer(value, maximum)
    return type(value) == 'number' and value >= 0 and value <= maximum
        and value == math.floor(value)
end

local function array(value, name)
    assert(type(value) == 'table', name .. ' must be an array')
    local count, highest = 0, 0
    for key in pairs(value) do
        assert(integer(key, 1000000) and key >= 1, name .. ' must be a dense array')
        count = count + 1
        if key > highest then highest = key end
    end
    assert(count == highest, name .. ' must be a dense array')
    return count
end

local function row_valid(row)
    assert(type(row) == 'table', 'Invalid inventory row')
    assert(integer(row.address, 9007199254740991) and row.address > 0, 'Invalid row address')
    assert(type(row.identity) == 'string' and #row.identity > 0, 'Invalid row identity')
    assert(type(row.category) == 'string', 'Invalid row category')
    assert(integer(row.state, 4294967295), 'Invalid row state')
    assert(integer(row.amount, 4294967295), 'Invalid row amount')
    if row.max_amount ~= nil then
        assert(integer(row.max_amount, 4294967295), 'Invalid maximum amount')
        assert(row.amount <= row.max_amount, 'Amount exceeds maximum')
    end
end

local function copy_row(row)
    return { address = row.address, identity = row.identity, category = row.category,
        state = row.state, amount = row.amount, max_amount = row.max_amount }
end

function M.plan(records, enabled)
    array(records, 'Records')
    assert(type(enabled) == 'table', 'Enabled categories must be a table')
    for name, value in pairs(enabled) do
        assert(allowed[name], 'Unknown enabled category')
        assert(type(value) == 'boolean', 'Category toggle must be boolean')
    end
    local plan = { version = 1, rows = {}, writes = {}, counts = {} }
    for _, name in ipairs(categories) do plan.counts[name] = 0 end
    local seen = {}
    for _, original in ipairs(records) do
        row_valid(original)
        assert(not seen[original.address], 'Duplicate row address')
        seen[original.address] = true
        -- Unclassified, resource and currency rows cannot enter a transaction.
        if allowed[original.category] and enabled[original.category] == true
            and original.state == 1 then
            local row = copy_row(original)
            plan.rows[#plan.rows + 1] = row
            plan.counts[row.category] = plan.counts[row.category] + 1
            plan.writes[#plan.writes + 1] = { row = row, field = 'state', before = 1, after = 2 }
            if row.amount == 0 and (row.max_amount == nil or row.max_amount >= 1) then
                plan.writes[#plan.writes + 1] = { row = row, field = 'amount', before = 0, after = 1 }
            end
        end
    end
    return plan
end

local function adapter_valid(io)
    assert(type(io) == 'table' and type(io.matches) == 'function'
        and type(io.read) == 'function' and type(io.write) == 'function', 'Invalid host adapter')
end

local function plan_valid(plan)
    assert(type(plan) == 'table' and plan.version == 1, 'Invalid transaction plan')
    array(plan.rows, 'Plan rows')
    array(plan.writes, 'Plan writes')
    local rows, fields, count = {}, {}, 0
    for _, row in ipairs(plan.rows) do
        row_valid(row)
        assert(allowed[row.category] and row.state == 1, 'Plan contains an ineligible row')
        assert(not rows[row.address], 'Duplicate plan row')
        rows[row.address], fields[row.address] = row, {}
    end
    for _, entry in ipairs(plan.writes) do
        assert(type(entry) == 'table' and type(entry.row) == 'table', 'Invalid plan write')
        local row, field = entry.row, entry.field
        assert(rows[row.address] == row, 'Write does not belong to plan')
        assert(not fields[row.address][field], 'Duplicate plan field')
        if field == 'state' then
            assert(entry.before == 1 and entry.after == 2, 'Invalid state write')
        elseif field == 'amount' then
            assert(row.amount == 0 and entry.before == 0 and entry.after == 1
                and (row.max_amount == nil or row.max_amount >= 1), 'Invalid amount write')
        else
            error('Unsupported field', 0)
        end
        fields[row.address][field] = true
        count = count + 1
    end
    for _, row in ipairs(plan.rows) do
        assert(fields[row.address].state, 'Plan row has no state write')
        if row.amount == 0 and (row.max_amount == nil or row.max_amount >= 1) then
            assert(fields[row.address].amount, 'Plan row has no owned amount write')
        end
    end
    return count
end

function M.status(journal)
    assert(type(journal) == 'table' and journal.version == 1
        and type(journal.entries) == 'table', 'Invalid transaction journal')
    local pending = 0
    for _, entry in ipairs(journal.entries) do
        if entry.pending then pending = pending + 1 end
    end
    return { pending = pending, active = pending, total = #journal.entries }
end

local function retire(entry, reason)
    entry.pending, entry.retired, entry.error = false, reason, nil
end

function M.restore(io, journal)
    adapter_valid(io)
    M.status(journal)
    local result = { restored = 0, skipped = 0, failed = 0, pending = 0 }
    for index = #journal.entries, 1, -1 do
        local entry = journal.entries[index]
        if entry.pending then
            local ok, why = pcall(function()
                local matches = io.matches(entry.row)
                if matches == false then
                    retire(entry, 'identity_changed')
                    result.skipped = result.skipped + 1
                    return
                end
                assert(matches == true, 'Identity unavailable during restore')
                local current = io.read(entry.row, entry.field)
                assert(integer(current, 4294967295), 'Restore read unavailable')
                if current == entry.before then
                    retire(entry, 'already_original')
                    result.skipped = result.skipped + 1
                    return
                elseif current ~= entry.after then
                    retire(entry, 'foreign_value')
                    result.skipped = result.skipped + 1
                    return
                end
                -- A failing write can still have taken effect. Readback decides
                -- whether this field is restored or remains owned for retry.
                local wrote, returned = pcall(io.write, entry.row, entry.field, entry.before)
                local after_identity = io.matches(entry.row)
                if after_identity == false then
                    retire(entry, 'identity_changed')
                    result.skipped = result.skipped + 1
                    return
                end
                assert(after_identity == true, 'Identity unavailable after restore')
                local after = io.read(entry.row, entry.field)
                assert(integer(after, 4294967295), 'Restore readback unavailable')
                if after == entry.before then
                    retire(entry, 'restored')
                    result.restored = result.restored + 1
                elseif after ~= entry.after then
                    retire(entry, 'foreign_value')
                    result.skipped = result.skipped + 1
                else
                    assert(wrote and returned == true, 'Restore write failed')
                    error('Restore readback differs', 0)
                end
            end)
            if not ok then
                entry.error = tostring(why)
                result.failed = result.failed + 1
            end
        end
    end
    result.pending = M.status(journal).pending
    journal.last_restore = result
    return result
end

function M.apply(io, plan)
    local journal = { version = 1, entries = {} }
    local ok, why = pcall(function()
        adapter_valid(io)
        plan_valid(plan)
        -- Check every identity and original field before the first mutation.
        for _, entry in ipairs(plan.writes) do
            assert(io.matches(entry.row) == true, 'Identity changed before apply')
            assert(io.read(entry.row, entry.field) == entry.before, 'Field changed before apply')
        end
        for _, entry in ipairs(plan.writes) do
            assert(io.matches(entry.row) == true, 'Identity changed during apply')
            assert(io.read(entry.row, entry.field) == entry.before, 'Field changed during apply')
            local owned = { row = copy_row(entry.row), field = entry.field,
                before = entry.before, after = entry.after, pending = true }
            -- Record intent before calling the host: a false return or exception
            -- must not lose a write that may already have reached memory.
            journal.entries[#journal.entries + 1] = owned
            assert(io.write(entry.row, entry.field, entry.after) == true, 'Apply write failed')
            assert(io.matches(entry.row) == true, 'Identity changed after apply')
            assert(io.read(entry.row, entry.field) == entry.after, 'Apply readback differs')
        end
    end)
    if ok then return journal, nil end
    journal.error = tostring(why)
    if #journal.entries > 0 then M.restore(io, journal) end
    return nil, journal.error, journal
end

return M
