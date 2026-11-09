-- Fifth stratagem slot: append one stratagem to the local player's mission stratagem list once per
-- mission. The HUD radial and arrow-code input pick the entry up live (verified 2026-10-25).
-- The list is never shortened and existing entries are never changed: a lower count leaves a stale
-- HUD card, and a changed kind inherits that slot's cooldown. A stratagem that delivers a held
-- item first has its package made resident through the support path; without it the game later
-- fetches the item's animations, gets null and crashes (exe 0x55CC2E).
local M = {}
local NET, LOCAL_PEER = 0x2E38228, 0xB398            -- local peer id
local MISSION, PEERS, PEER = 0x2E38188, 0x2D800, 0x16C0  -- mission peer records
local PAYLOAD, LIST, STRIDE, COUNT, MAX = 0x38, 0x188, 0x30, 0x788, 32
local MARKER = 0x0EADDD1A                            -- mission-entry marker seen on every entry

local function word(s, o) o = o or 0; local a, b, c, d = s:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local function le(v, n) local t = {}; for i = 1, n do t[i] = string.char(v % 256); v = math.floor(v / 256) end; return table.concat(t) end

-- {kind, -1 (no use limit), loadout flag 0, 0, then the mission marker}, as appended live.
function M.entry(kind)
    return le(kind, 4) .. le(0xFFFFFFFF, 4) .. string.rep('\0', 16) .. le(MARKER, 4) .. string.rep('\0', 20)
end

function M.new(options)
    local io, write, observe = assert(options.io), assert(options.write), assert(options.observe)
    local stratagems, support, items = assert(options.stratagems), options.support, options.items or {}
    local now = options.now or os.clock
    local self = {reason = 'Choose a stratagem', pending = nil, added = nil}
    local function r(at, n) local s = io.read(at, n); assert(type(s) == 'string' and #s == n, 'Stratagem memory unavailable'); return s end
    local function p(at) local s = r(at, 8); local v = word(s) + word(s, 4) * 4294967296; assert(v >= 65536 and v < 2 ^ 47, 'Stratagem pointer unavailable'); return v end
    local function u(at) return word(r(at, 4)) end

    -- The local player's mission list, or an error.
    local function list()
        local g = assert(io.module('game.dll'), 'game.dll unavailable')
        local me, mission = u(p(g + NET) + LOCAL_PEER), p(g + MISSION)
        local peers = u(mission + PEERS); assert(peers >= 1 and peers <= 4, 'Mission peer count differs')
        for i = 0, peers - 1 do
            local rec = mission + i * PEER
            if u(rec) == me then
                local payload = rec + PAYLOAD; local count = u(payload + COUNT)
                assert(count >= 1 and count < MAX, 'Mission stratagem count differs')
                return {mission = mission, token = r(rec, 24), payload = payload, count = count}
            end
        end
        error('Local mission stratagems unavailable')
    end

    function self:choices() local t = {}; for i, row in ipairs(stratagems) do t[i] = row.name end; return t end
    function self:groups()
        local groups, by_name = {}, {}
        for _, name in ipairs({'Eagles', 'Orbitals', 'Weapons', 'Backpacks', 'Turrets', 'Deployables'}) do
            local group = {name=name, entries={}}
            groups[#groups + 1], by_name[name] = group, group
        end
        for index, row in ipairs(stratagems) do
            local entries = by_name[row.group].entries
            entries[#entries + 1] = {name=row.name, index=index}
        end
        for _, group in ipairs(groups) do
            table.sort(group.entries, function(a, b) return a.name:lower() < b.name:lower() end)
        end
        return groups
    end
    function self:queue(index)
        local row = stratagems[index]
        if not row then return false, 'Choose a stratagem' end
        if self.pending then return false, 'A stratagem request is already pending' end
        if row.item and not items[row.item] then return false, row.name .. ': no Spawner catalogue item' end
        self.pending = {index = index, row = row}
        self.reason = 'Queued ' .. row.name .. '; close the menu to add it'
        return true
    end
    function self:update(enabled)
        local job = self.pending
        if not job or not enabled or (job.next_poll and now() < job.next_poll) then return end
        local ok, why = pcall(function()
            local view, wait = observe()
            if not (view and view.can_start) then return wait or 'Waiting for normal mission gameplay' end
            assert(io.read(view.base.pm + 0x70, 4) == le(1, 4), 'The fifth slot needs a solo mission')
            local l = list()
            if job.mission and (job.mission ~= l.mission or job.token ~= l.token) then
                self.pending = nil
                return 'Mission changed. Choose a stratagem for this mission.'
            end
            job.mission, job.token = l.mission, l.token
            if self.added and self.added.mission == l.mission and self.added.token == l.token then
                self.pending = nil; return 'The fifth slot was already added this mission'
            end
            for i = 0, l.count - 1 do
                if u(l.payload + LIST + i * STRIDE) == job.row.kind then self.pending = nil; return job.row.name .. ' is already available' end
            end
            if job.row.item then
                local index = items[job.row.item]
                if not support:loaded(index, view.base.world) then
                    if not job.preload then
                        local queued, refused = support:queue(index, 'preload')
                        if not queued then return refused end
                        job.preload = true
                    elseif not support:preload_pending(index) then
                        self.pending = nil
                    end
                    return support:status()
                end
            end
            if job.row.package then
                local ready, reason = support:ensure_package(job.row.package, view)
                if not ready then
                    job.next_poll = now() + 0.5
                    return reason or ('Loading ' .. job.row.name)
                end
                -- A package request can yield to the engine before the append.
                local current = list()
                assert(current.mission == l.mission and current.token == l.token and current.count == l.count,
                    'Mission stratagem list changed during load')
            end
            local at = l.payload + LIST + l.count * STRIDE
            assert(r(at, STRIDE) == string.rep('\0', STRIDE), 'Next stratagem slot is not empty')
            local entry = M.entry(job.row.kind)
            local written, refused = write(at, entry)
            assert(written == true and r(at, STRIDE) == entry, refused or 'Stratagem entry write failed')
            written, refused = write(l.payload + COUNT, le(l.count + 1, 4))
            assert(written == true and u(l.payload + COUNT) == l.count + 1, refused or 'Stratagem count write failed')
            self.added, self.pending = {mission = l.mission, token = l.token, kind = job.row.kind}, nil
            return job.row.name .. ' added as your fifth stratagem'
        end)
        self.reason = tostring(why)
        if not ok then self.pending = nil end
    end
    function self:status() return self.reason end
    function self:cancel() self.pending = nil end
    return self
end
return M
