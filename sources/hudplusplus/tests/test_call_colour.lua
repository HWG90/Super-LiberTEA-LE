-- Run with: luajit tests/test_call_colour.lua [src-directory]
local source = arg[1] or "src"
package.path = source .. "/?.lua;" .. package.path
local Colour = require("features.call_colour")
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function sequence(actual, expected)
    equal(#actual, #expected, "queue length")
    for index, value in ipairs(expected) do
        equal(actual[index], value, "queue item " .. index)
    end
end
local ring, first, last = 1000, 0, 3
local pending, painted, attempts = {}, {}, {}
local ready = { [0] = true, [2] = true }
local feature = setmetatable({
    pending = pending,
    painted = painted,
    weapon = { n = { comms_ring_mask = 7, comms_at = 100, comms_stride = 16 } },
    comms = {
        head = function()
            return ring, first, last
        end,
    },
    paint = function(_, _, _, _, row)
        attempts[#attempts + 1] = row
        return ready[row] == true
    end,
}, Colour)
feature.ring = ring
feature:step(true, true)
equal(feature.pending, pending, "pending table reused")
sequence(pending, { 1 })
sequence(attempts, { 0, 1, 2 })
equal(pending[2], nil, "completed tail cleared")
last = 5
ready[1] = true
attempts = {}
feature:step(true, true)
equal(feature.pending, pending)
sequence(pending, { 3, 4 })
sequence(attempts, { 1, 3, 4 })
ready[3], ready[4] = true, true
feature:step(true, true)
sequence(pending, {})
equal(feature.pending, pending)
feature:step(true, true)
equal(feature.pending, pending, "empty queue reused")
-- Circular indices keep their discovery order across wrap-around.
first, last, feature.seen = 5, 2, 6
ready[6], ready[7], ready[0], ready[1] = false, false, false, false
attempts = {}
feature:step(true, true)
sequence(pending, { 6, 7, 0, 1 })
sequence(attempts, { 6, 7, 0, 1 })
-- Switching rings starts with a clean queue, as before.
ring, first, last = 2000, 2, 4
ready[2], ready[3] = true, false
feature:step(true, true)
assert(feature.pending ~= pending, "ring switch must forget prior entries")
sequence(feature.pending, { 3 })
feature:step(true, false)
sequence(feature.pending, {})
equal(feature.ring, nil)
-- A stale pending index is discarded before native memory is accessed.
local stale = setmetatable({ weapon = { n = { comms_ring_mask = 7 } } }, Colour)
equal(stale:paint(1000, 3, 6, 1), true)
print("call_colour: pending retries, compaction, ring wrap and reset passed")
