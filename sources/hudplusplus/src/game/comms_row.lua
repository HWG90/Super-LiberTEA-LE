local Comms = require("game.comms_inputs")
local Row = {}
Row.__index = Row
function Row.new(access, n, ui)
    local judge = access.call.judge
    return setmetatable({
        read = access.read,
        judge = judge,
        write = access.write,
        n = n,
        ui = ui,
        insert = assert(judge:routine("comms_insert")),
        ground = assert(judge:routine("ground_height")),
        point = assert(judge:buffer("float", 3)),
        height = assert(judge:buffer("float", 1)),
    }, Row)
end
function Row:place(ring, sender, kind, point, target, sound)
    local n, read, judge = self.n, self.read, self.judge
    local tail = read:value(ring + n.comms_last, "u32")
    local peer = judge:uint64_of(sender)
    if peer == nil then
        return nil
    end
    for i = 1, 3 do
        self.point[i - 1] = point[i]
    end
    judge:call(self.insert, ring, peer, kind, self.point, target or 0, target ~= nil and 1 or 0, 0, 0, 0, 0)
    local at = ring + n.comms_at + (tail % (n.comms_ring_mask + 1)) * n.comms_stride
    if read:value(ring + n.comms_last, "u32") ~= (tail + 1) % (n.comms_ring_mask + 1) then
        return nil, "refused"
    end
    if read:value(at + n.comms_kind, "u32") ~= kind then
        return nil, "other"
    end
    if sound ~= nil then
        self.ui:call("menu_play_sound", 0, sound)
    end
    return { at = at, ring = ring, kind = kind, picture = read:value(at + n.comms_picture, "hex64") }
end
function Row:ours(placed)
    local n, read, at = self.n, self.read, placed.at
    return read:value(at + n.comms_kind, "u32") == placed.kind
        and read:value(at + n.comms_owner, "u32") == 0
        and read:value(at + n.comms_picture, "hex64") == placed.picture
end
function Row:brackets(placed, colour)
    if not self:ours(placed) then
        return "gone"
    end
    local fresh = Comms.fresh(self.read, self.n, placed.at)
    if fresh == nil then
        return "gone"
    end
    if fresh ~= 0 then
        return "fresh"
    end
    Comms.brackets(self.ui, self.n, placed.ring, placed.at, nil, colour[2], colour[3], colour[4])
    return "tinted"
end
function Row:in_ring(placed)
    local n, read, ring = self.n, self.read, placed.ring
    local head, tail = read:value(ring + n.comms_first, "u32"), read:value(ring + n.comms_last, "u32")
    local size = n.comms_ring_mask + 1
    local index = (placed.at - ring - n.comms_at) / n.comms_stride
    return (index - head) % size < (tail - head) % size
end
function Row:float(placed, name)
    return self.read:value(placed.at + self.n["comms_" .. name], "f32")
end
function Row:set(placed, change)
    if not self:ours(placed) then
        return "gone"
    end
    local n, judge, read, cells = self.n, self.judge, self.read, {}
    local function float(at, value)
        local bits = judge:bits(value)
        if bits == nil then
            return false
        end
        cells[#cells + 1] = { at, bits }
        return true
    end
    if change.label ~= nil then
        cells[1] = { n.comms_label, change.label }
    end
    if change.picture ~= nil then
        local high, low = read.bytes.words_of(change.picture)
        if high == nil then
            return "value"
        end
        cells[#cells + 1] = { n.comms_picture, low }
        cells[#cells + 1] = { n.comms_picture + 4, high }
    end
    for i, value in ipairs(change.tint or {}) do
        if not float(n.comms_tint + (i - 1) * 4, value) then
            return "bits"
        end
    end
    if change.point ~= nil then
        local point = change.point
        for i = 1, 3 do
            self.point[i - 1] = point[i]
        end
        self.height[0] = point[3]
        judge:call(self.ground, change.terrain, self.point, self.height, 1, 0, 0)
        if
            not (
                float(n.comms_point, point[1])
                and float(n.comms_point + 4, point[2])
                and float(n.comms_point + 8, self.height[0])
            )
        then
            return "bits"
        end
    end
    local deadline
    if change.seconds ~= nil then
        local elapsed, lifetime = self:float(placed, "elapsed"), self:float(placed, "lifetime")
        if elapsed >= lifetime and not (change.revive and self:in_ring(placed)) then
            return "ended"
        end
        deadline = elapsed + change.seconds
        if not float(n.comms_lifetime, deadline) then
            return "bits"
        end
    end
    if #cells == 0 then
        return "already"
    end
    local first, last = cells[1][1], cells[1][1] + 4
    for _, cell in ipairs(cells) do
        first, last = math.min(first, cell[1]), math.max(last, cell[1] + 4)
    end
    local before = read:text(placed.at + first, last - first)
    local after = before
    for _, cell in ipairs(cells) do
        local bytes = read.bytes.pack(cell[2], 4)
        if bytes == nil then
            return "value"
        end
        after = after:sub(1, cell[1] - first) .. bytes .. after:sub(cell[1] - first + 5)
    end
    local _, word = self.write:swap(placed.at + first, before, after)
    if word ~= "written" and word ~= "already" then
        return word
    end
    if change.picture ~= nil then
        placed.picture = change.picture
    end
    return word, deadline
end
function Row:take(placed, done)
    if not self:ours(placed) then
        return "gone"
    end
    local n = self.n
    local lifetime = self.read:value(placed.at + n.comms_lifetime, "u32")
    local _, word = self.write:swap(placed.at + n.comms_elapsed, nil, self.read.bytes.pack(lifetime, 4))
    return word == "written" and done or word
end
return Row
