-- Run with: luajit tests/test_product.lua [src-directory]
local source = arg[1] or "src"
package.path = source .. "/?.lua;" .. package.path
local Product = require("product")
local Dependencies = require("core.dependencies")
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function members(actual, expected)
    for name in pairs(expected) do
        equal(actual[name], true, name .. " blocked")
    end
    for name in pairs(actual) do
        equal(expected[name], true, name .. " unexpectedly blocked")
    end
end
-- The existing Product API remains available after extracting the feature graph.
equal(Product.blocked, Dependencies.blocked)
members(Product.blocked(nil), {})
members(Product.blocked({}), {})
members(Product.blocked({ missing = {} }), {})
local graph = {
    missing = { native_call = "unresolved" },
    uses = { core = { "native_call" }, feature = {}, addon = {}, independent = { "available" } },
    requires = { feature = { "core" }, addon = { "feature" } },
}
members(Product.blocked(graph), { core = true, feature = true, addon = true })
-- A dependency can be visited even when it has no direct native requirements.
graph.requires.feature = { "bridge" }
graph.requires.bridge = { "core" }
members(Product.blocked(graph), { core = true, feature = true, addon = true })
-- Cycles without missing values terminate and leave unrelated features available.
graph.requires.independent = { "peer" }
graph.requires.peer = { "independent" }
members(Product.blocked(graph), { core = true, feature = true, addon = true })
local inputs, clock = { world = {}, eye = {} }, 12.5
local trajectory_row, attack_row, second_attack_row = {}, {}, {}
local trajectory = { row = trajectory_row, observer = {}, shot = {} }
local attack = { rows = { attack_row, second_attack_row } }
local reused, received = {}, nil
local product = setmetatable({
    ground_rows = reused,
    ground = {
        step = function(_, ...)
            received = { n = select("#", ...), ... }
        end,
    },
}, Product)
local function draw(with_trajectory, with_attack, expected)
    product.trajectory, product.attack = with_trajectory, with_attack
    product:draw(inputs, clock)
    equal(product.ground_rows, reused, "row table reused")
    equal(received.n, 6, "ground argument count")
    equal(received[1], inputs.world)
    equal(received[2], clock)
    equal(received[3], with_trajectory and with_trajectory.observer)
    equal(received[4], reused)
    equal(received[5], with_trajectory and with_trajectory.shot)
    equal(received[6], inputs.eye)
    equal(#reused, #expected, "draw row count")
    for index, row in ipairs(expected) do
        equal(reused[index], row, "draw row " .. index)
    end
end
draw(trajectory, attack, { trajectory_row, attack_row, second_attack_row })
draw(nil, attack, { attack_row, second_attack_row })
equal(reused[3], nil, "previous trajectory tail removed")
draw(trajectory, nil, { trajectory_row })
equal(reused[2], nil, "previous attack tail removed")
draw(nil, nil, {})
equal(reused[1], nil, "empty draw clears prior rows")
trajectory.row = nil
draw(trajectory, attack, { attack_row, second_attack_row })
print("product: dependency graph, optional previews and row reuse passed")
