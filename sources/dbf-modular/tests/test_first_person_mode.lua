local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Mode = project.require("sampling/first_person_mode.lua")
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local globals, polls = {}, 0
local detector = Mode.new(globals)
local view = detector:update()
eq(view.known, false)
eq(view.active, false)
eq(view.token, nil)
eq(detector:current(), false)
local result =
    { mode = "pose_offset", phase = "running", enabled = true, cleanup_pending = false, editor_active = false }
local function status(...)
    eq(select("#", ...), 0, "public status is called as a dot function")
    polls = polls + 1
    return "First Person active", result
end
local provider = { status = status }
globals.NativeADSCameraTest = provider
eq(detector:update(), view, "receipt table is retained")
eq(polls, 1)
eq(view.known, true)
eq(view.active, true)
eq(type(view.token), "string")
eq(detector:current(), true)
local first = view.token
eq(detector:current(), true)
eq(polls, 1, "publication checks never poll the provider")
detector:update()
eq(polls, 2)
eq(view.token, first, "normal frames retain provider epoch")
for _, phase in ipairs({ "idle", "disabled", "waiting", "reacquiring", "cleanup_pending" }) do
    result.phase = phase
    detector:update()
    eq(view.known, true)
    eq(view.active, false, "enabled intent is not an applied lease in " .. phase)
    eq(view.token, nil)
    eq(detector:current(), false)
end
result.phase = "running"
for _, field in ipairs({ "cleanup_pending", "editor_active" }) do
    result[field] = true
    detector:update()
    eq(view.known, true)
    eq(view.active, false)
    result[field] = false
end
result.mode = "unlinked_sights"
detector:update()
eq(view.known, true)
eq(view.active, false, "native ADS experiments are not True First Person")
result.mode = "pose_offset"
result.enabled = false
detector:update()
eq(view.active, false)
result.enabled = true
for _, fird in ipairs({ { enabled = true }, { enabled = true, pending = true }, { pending = true } }) do
    result.fird = fird
    detector:update()
    eq(view.active, false, "Fird's temporary native-FP capture is excluded")
end
result.fird = { enabled = false, phase = "off" }
result.camera = { phase = "waiting", armed = false, installed = false }
detector:update()
eq(view.active, true, "native kind6 can work while the separate head-camera helper waits")
result.camera = { phase = "cleanup_pending", error = 15 }
detector:update()
eq(view.active, true, "head-camera diagnostics do not replace controller/native-request proof")
result.fird = nil
local before = polls
provider.status = function()
    polls = polls + 1
    error("Provider temporarily unavailable")
end
detector:update()
eq(polls, before + 1, "one failed poll only")
eq(view.known, false)
eq(view.active, false)
eq(view.token, nil)
provider.status = status
for _, bad in ipairs({
    false,
    "active",
    1,
    {},
    { phase = "running", enabled = 1 },
    { phase = "future_mode", enabled = true },
    { phase = "running", enabled = true, fird = true },
    { phase = "running", enabled = true, cleanup_pending = 1 },
}) do
    provider.status = function()
        polls = polls + 1
        return "status", bad
    end
    before = polls
    detector:update()
    eq(polls, before + 1)
    eq(view.known, false)
    eq(view.active, false)
end
provider.status = function()
    polls = polls + 1
    return "status",
        {
            mode = "pose_offset",
            phase = "running",
            enabled = true,
            fird = { enabled = 1 },
        }
end
detector:update()
eq(view.known, false, "malformed Fird activity cannot be interpreted as inactive")
provider.status = function()
    polls = polls + 1
    return result
end
detector:update()
eq(view.known, false, "unsupported one-result API cannot masquerade as the current contract")
provider.status = status
detector:update()
eq(view.active, true)
eq(view.token ~= first, true, "a replaced status function advances provider epoch")
local token = view.token
globals.NativeADSCameraTest = { status = status }
eq(detector:current(), false, "same-shaped foreign provider cannot reuse a receipt")
detector:update()
eq(view.active, true)
eq(view.token ~= token, true)
provider = globals.NativeADSCameraTest
provider.status = function()
    polls = polls + 1
    globals.NativeADSCameraTest = { status = status }
    return "status", result
end
detector:update()
eq(view.known, false, "provider replacement inside its public callback invalidates publication")
eq(detector:current(), false)
provider = {
    status = function()
        polls = polls + 1
        provider.status = status
        return "status", result
    end,
}
globals.NativeADSCameraTest = provider
detector:update()
eq(view.known, false, "status replacement inside the callback also invalidates publication")
globals.NativeADSCameraTest = setmetatable({}, { __index = { status = status } })
before = polls
detector:update()
eq(view.known, false)
eq(polls, before, "unadvertised metatable methods are not probed")
globals.NativeADSCameraTest = { status = status }
detector:update()
eq(view.active, true)
eq(detector:close(), true)
eq(view.known, false)
eq(view.active, false)
eq(view.token, nil)
eq(detector.provider, nil)
eq(detector.status, nil)
eq(detector.globals, nil)
eq(detector:current(), false)
before = polls
eq(detector:update(), view)
eq(view.active, false)
eq(polls, before, "closed detector cannot resume provider polling")
print("First-person mode: " .. checks .. " checks passed")
