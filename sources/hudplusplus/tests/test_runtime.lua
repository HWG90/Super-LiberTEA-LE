-- Run with: luajit tests/test_runtime.lua [src-directory]
local source = arg[1] or "src"
package.path = source .. "/?.lua;" .. package.path
local Runtime = require("core.runtime")
local tests, passed = {}, 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function pack(...)
    return { n = select("#", ...), ... }
end
local function returns(actual, expected)
    equal(actual.n, expected.n, "return count")
    for index = 1, actual.n do
        equal(actual[index], expected[index], "return " .. index)
    end
end
local function fixture(update, shutdown)
    local seen = { steps = 0, after = 0, closes = 0, reports = 0 }
    local program = {
        step = function(_, ...)
            seen.steps = seen.steps + 1
            seen.arguments = pack(...)
        end,
        after = function(_, completed)
            seen.after = seen.after + 1
            seen.completed = completed
        end,
        close = function()
            seen.closes = seen.closes + 1
        end,
    }
    local environment = { update = update or function(...)
        return ...
    end, shutdown = shutdown }
    local runtime = Runtime.new(program, function(...)
        seen.reports = seen.reports + 1
        seen.report = pack(...)
    end)
    runtime:install(environment)
    return runtime, program, environment, seen
end
function tests.returns_and_stop()
    local original = function(...)
        return ...
    end
    local shutdown = function()
        return "shutdown"
    end
    local runtime, _, environment, seen = fixture(original, shutdown)
    returns(pack(environment.update(1, nil, 3, nil)), pack(1, nil, 3, nil))
    returns(seen.arguments, pack(1, nil, 3, nil))
    equal(seen.steps, 1)
    equal(seen.after, 1)
    equal(seen.completed, true)
    equal(runtime:stop("disabled"), true)
    equal(environment.update, original)
    equal(environment.shutdown, shutdown)
    equal(runtime.installed, false)
    equal(seen.closes, 1)
    equal(seen.reports, 1)
    equal(runtime:stop(), true)
    equal(seen.closes, 1)
    equal(seen.reports, 1)
end
function tests.enable_disable_does_not_accumulate()
    local original = function(...)
        return ...
    end
    local environment = { update = original }
    for _ = 1, 20 do
        local runtime = Runtime.new({ step = function() end, close = function() end })
        runtime:install(environment)
        equal(environment.update("alive"), "alive")
        runtime:stop()
        equal(environment.update, original)
        equal(environment.shutdown, nil)
    end
end
function tests.foreign_wrappers_and_outer_menu()
    local originals = 0
    local runtime, program, environment, seen = fixture(function(...)
        originals = originals + 1
        return ...
    end)
    local base = environment.update
    local foreign_calls = 0
    local foreign = function(...)
        foreign_calls = foreign_calls + 1
        return base(...)
    end
    environment.update = foreign
    program.menu_outermost = true
    returns(pack(environment.update(nil, 2)), pack(nil, 2))
    assert(environment.update ~= foreign, "menu must become outermost")
    returns(pack(environment.update(3, nil)), pack(3, nil))
    equal(seen.steps, 2)
    equal(seen.after, 2)
    equal(foreign_calls, 2)
    runtime:stop()
    equal(environment.update, foreign, "foreign wrapper survives")
    local original_pcall, calls = pcall, 0
    _G.pcall = function(...)
        calls = calls + 1
        return original_pcall(...)
    end
    local result = pack(environment.update(nil, 4, nil))
    _G.pcall = original_pcall
    returns(result, pack(nil, 4, nil))
    equal(calls, 0, "stopped wrappers must bypass protected dispatch")
    equal(seen.steps, 2)
    equal(seen.after, 2)
    equal(originals, 3)
end
function tests.foreign_wrapper_above_menu_survives()
    local runtime, program, environment, seen = fixture()
    local base = environment.update
    environment.update = function(...)
        return base(...)
    end
    program.menu_outermost = true
    environment.update()
    local outer = environment.update
    local foreign = function(...)
        return outer(...)
    end
    environment.update = foreign
    runtime:stop()
    equal(environment.update, foreign)
    returns(pack(environment.update(1, nil, 3)), pack(1, nil, 3))
    equal(seen.steps, 1)
    equal(seen.after, 1)
    local second = Runtime.new({ step = function() end, close = function() end }):install(environment)
    equal(environment.update(5), 5)
    second:stop()
    equal(environment.update, foreign)
end
function tests.menu_can_return_to_inner()
    local runtime, program, environment, seen = fixture()
    local base = environment.update
    local foreign = function(...)
        return base(...)
    end
    environment.update = foreign
    program.menu_outermost = true
    environment.update()
    program.menu_outermost = false
    environment.update()
    equal(environment.update, foreign)
    equal(seen.steps, 2)
    equal(seen.after, 2)
    runtime:stop()
    equal(environment.update(7), 7)
    equal(seen.steps, 2)
end
function tests.error_paths()
    local sentinel = {}
    local runtime, _, environment, seen = fixture(function()
        error(sentinel, 0)
    end)
    local okay, failure = pcall(environment.update)
    equal(okay, false)
    equal(failure, sentinel)
    equal(seen.completed, false)
    equal(runtime.running, true)
    runtime:stop()
    local original = function(...)
        return ...
    end
    runtime, _, environment, seen = fixture(original)
    runtime.program.step = function()
        error("step failure", 0)
    end
    equal(environment.update(8), 8)
    equal(runtime.running, false)
    equal(environment.update, original)
    equal(seen.closes, 1)
    equal(seen.after, 0)
    equal(seen.report[1], "step failure")
    equal(seen.report[3], "step")
    runtime, _, environment, seen = fixture(original)
    runtime.program.after = function()
        error("after failure", 0)
    end
    equal(environment.update(9), 9)
    equal(runtime.running, false)
    equal(environment.update, original)
    equal(seen.report[1], "after failure")
    equal(seen.report[3], "after")
    runtime, _, environment, seen = fixture(original)
    runtime.program.close = function()
        error("close failure", 0)
    end
    okay, failure = runtime:stop("disabled")
    equal(okay, false)
    equal(failure, "close failure")
    equal(environment.update, original)
    equal(seen.report[2], "close failure")
end
function tests.shutdown_and_foreign_shutdown()
    local original = function(...)
        return ...
    end
    local shutdown = function(...)
        return ...
    end
    local runtime, _, environment, seen = fixture(original, shutdown)
    returns(pack(environment.shutdown(nil, 2, nil)), pack(nil, 2, nil))
    equal(runtime.running, false)
    equal(seen.closes, 1)
    equal(environment.update, original)
    equal(environment.shutdown, shutdown)
    runtime, _, environment, seen = fixture(original, shutdown)
    local wrapper = environment.shutdown
    local foreign = function(...)
        return wrapper(...)
    end
    environment.shutdown = foreign
    runtime:stop()
    equal(environment.shutdown, foreign)
    equal(environment.shutdown(10), 10)
    equal(seen.closes, 1)
end
function tests.successor_still_runs()
    local runtime, program, environment, seen = fixture()
    local next_after, next_closed = 0, 0
    program.successor = {
        step = function() end,
        after = function()
            next_after = next_after + 1
        end,
        close = function()
            next_closed = next_closed + 1
        end,
    }
    environment.update()
    equal(runtime.program, program.successor)
    equal(next_after, 1)
    equal(seen.after, 0)
    runtime:stop()
    equal(next_closed, 1)
end
local names = {}
for name in pairs(tests) do
    names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
    tests[name]()
    passed = passed + 1
end
print("runtime: " .. passed .. " tests passed")
