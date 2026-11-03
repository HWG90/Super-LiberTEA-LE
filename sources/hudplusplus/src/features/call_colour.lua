local Comms = require("game.comms_inputs")
local Colour = {}
Colour.__index = Colour
function Colour.new(ui, weapon, comms)
    local judge = weapon.judge
    local self = setmetatable(
        { ui = ui, weapon = weapon, comms = comms, pending = {}, painted = {}, rgba = assert(judge:buffer("float", 4)) },
        Colour
    )
    for _, name in ipairs({ "player_of_avatar", "player_record", "player_colour" }) do
        self[name] = assert(judge:routine(name))
    end
    return self
end
function Colour:colour_of(owner)
    local w = self.weapon
    local judge, read, n = w.judge, w.read, w.n
    local players = w:manager(n.roots_player_manager_rva)
    if players == nil or judge:call(self.player_of_avatar, players, w.out, owner) == nil then
        return nil
    end
    local player = tonumber(w.out[0])
    if player == nil or player == w.invalid_local then
        return nil
    end
    local record = judge:call(self.player_record, 0, player)
    if record == nil or record == 0 then
        return nil
    end
    local key = read:value(record, "key64")
    if not key or key == w:local_key(players) then
        return nil
    end
    if judge:call(self.player_colour, 0, self.rgba, judge:uint64_of(key)) == nil then
        return nil
    end
    return self.rgba[1], self.rgba[2], self.rgba[3]
end
function Colour:paint(ring, first, last, k)
    local w, ui = self.weapon, self.ui
    local read, n = w.read, w.n
    local size = n.comms_ring_mask + 1
    if (k - first) % size >= (last - first) % size then
        return true
    end
    local at = ring + n.comms_at + k * n.comms_stride
    if read:value(at + n.comms_kind, "u32") ~= n.comms_call_kind then
        return true
    end
    local fresh = Comms.fresh(read, n, at)
    if fresh == nil then
        return true
    end
    if fresh ~= 0 then
        return false
    end
    local elapsed, lifetime = read:value(at + n.comms_elapsed, "f32"), read:value(at + n.comms_lifetime, "f32")
    if elapsed == nil or lifetime == nil or not (elapsed < lifetime) then
        return true
    end
    local owner = read:value(at + n.comms_owner, "u32")
    local red, green, blue
    if owner ~= nil then
        red, green, blue = self:colour_of(owner)
    end
    if red == nil then
        return true
    end
    Comms.brackets(ui, n, ring, at, true, red, green, blue)
    self.painted[at] = ring
    return true
end
function Colour:close()
    local w, ui = self.weapon, self.ui
    local read, n = w.read, w.n
    for at, ring in pairs(self.painted) do
        if read:value(at + n.comms_kind, "u32") == n.comms_call_kind and Comms.fresh(read, n, at) == 0 then
            Comms.brackets(ui, n, ring, at, false)
        end
    end
    self:forget()
end
function Colour:forget()
    self.ring, self.seen, self.pending, self.painted = nil, nil, {}, {}
end
function Colour:held()
    return next(self.painted) ~= nil
end
function Colour:step(enabled, editable)
    if not editable then
        self:forget()
        return
    end
    if not enabled then
        if self:held() or self.seen ~= nil then
            self:close()
        end
        return
    end
    local ring, first, last = self.comms:head()
    if ring == nil then
        return
    end
    if ring ~= self.ring then
        self:forget()
        self.ring = ring
    end
    local n = self.weapon.n
    local size = n.comms_ring_mask + 1
    local k = self.seen
    if k == nil then
        k = first
    end
    while k ~= last do
        self.painted[ring + n.comms_at + k * n.comms_stride] = nil
        self.pending[#self.pending + 1] = k
        k = (k + 1) % size
    end
    self.seen = last
    if #self.pending == 0 then
        return
    end
    local pending, kept = self.pending, 0
    for _, row in ipairs(pending) do
        if not self:paint(ring, first, last, row) then
            kept = kept + 1
            pending[kept] = row
        end
    end
    for index = #pending, kept + 1, -1 do
        pending[index] = nil
    end
end
return Colour
