local Comms = {}
Comms.__index = Comms
local CORNERS = { "ping_bracket_a", "ping_bracket_b", "ping_bracket_c", "ping_bracket_d" }
function Comms.fresh(read, n, at)
    return read:value(at + n.comms_flags, "bit", n.comms_fresh_bit)
end
function Comms.brackets(ui, n, ring, at, shown, red, green, blue)
    local pool = ring + n.ping_pool + (at - ring - n.comms_at) / n.comms_stride * n.ping_pool_stride
    for _, name in ipairs(CORNERS) do
        local node = { at = pool + n[name] }
        if shown ~= nil then
            ui:show(node, shown)
        end
        if red ~= nil then
            ui:colour(node, red, green, blue)
        end
    end
end
function Comms.new(weapon)
    local n = weapon.n
    return setmetatable({
        weapon = weapon,
        cells = weapon.read.layout({
            { n.comms_owner, "u32" },
            { n.comms_kind, "u32" },
            { n.comms_elapsed, "f32" },
            { n.comms_lifetime, "f32" },
        }),
        got = {},
    }, Comms)
end
function Comms:frame()
    self.read_head, self.ring, self.first, self.last = false, nil, nil, nil
end
function Comms:head()
    if not self.read_head then
        self.read_head = true
        local w, n = self.weapon, self.weapon.n
        local ring = w:manager(n.comms_global)
        if ring ~= nil then
            local first, last = w.read:value(ring + n.comms_first, "u32"), w.read:value(ring + n.comms_last, "u32")
            if first ~= nil and last ~= nil then
                self.ring, self.first, self.last = ring, first, last
            end
        end
    end
    return self.ring, self.first, self.last
end
function Comms:observe(enabled)
    self.pings, self.calls = nil, nil
    if not enabled then
        return
    end
    local w, n = self.weapon, self.weapon.n
    local ring, first, last = self:head()
    if ring == nil then
        return
    end
    local pings, calls = {}, {}
    for k = 0, (last - first) % (n.comms_ring_mask + 1) - 1 do
        local at = ring + n.comms_at + ((first + k) % (n.comms_ring_mask + 1)) * n.comms_stride
        local v = w.read:value(at, self.cells, self.got)
        local owner, kind, elapsed, lifetime = v[1], v[2], v[3], v[4]
        if
            owner == nil
            or kind == nil
            or elapsed == nil
            or lifetime == nil
            or elapsed ~= elapsed
            or lifetime ~= lifetime
            or math.abs(elapsed) == math.huge
            or math.abs(lifetime) == math.huge
        then
            return
        end
        if elapsed < lifetime then
            if kind == n.comms_call_kind then
                local list = calls[owner] or {}
                calls[owner] = list
                list[#list + 1] = at
            else
                pings[owner] = at
            end
        end
    end
    self.pings, self.calls = pings, calls
end
return Comms
