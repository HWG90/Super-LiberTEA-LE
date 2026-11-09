-- Atomic replacement protocol and real POSIX round trip. Only temporary test files.
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Storage = project.require("settings/storage.lua")
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
for _, failing in ipairs({ "create", "write", "flush", "close", "replace", "throw-write", "throw-replace", "none" }) do
    local calls, current, closed, removed, temporary = {}, "old committed data", false, false, nil
    local backend = { nonce = "fixture" }
    function backend.create(path)
        calls[#calls + 1] = "create"
        temporary = path
        if failing == "create" then
            return nil, "create refused"
        end
        return {}
    end
    function backend.write(_, text)
        calls[#calls + 1] = "write"
        eq(text, "new data")
        if failing == "throw-write" then
            error("write raised")
        end
        return failing ~= "write", "write refused"
    end
    function backend.flush()
        calls[#calls + 1] = "flush"
        return failing ~= "flush", "flush refused"
    end
    function backend.close()
        calls[#calls + 1] = "close"
        closed = true
        return failing ~= "close", "close refused"
    end
    function backend.replace(from, to)
        calls[#calls + 1] = "replace"
        eq(closed, true)
        eq(from, temporary)
        eq(to, "test.cfg")
        if failing == "throw-replace" then
            error("replace raised")
        end
        if failing == "replace" then
            return false, "replace refused"
        end
        current = "new data"
        return true
    end
    function backend.remove(path)
        eq(path, temporary)
        removed = true
        return true
    end
    local okay, why = Storage.atomic("test.cfg", "new data", backend)
    eq(okay, failing == "none")
    eq(current, failing == "none" and "new data" or "old committed data", failing)
    eq(closed, failing ~= "create")
    eq(removed, failing ~= "none" and failing ~= "create")
    if failing ~= "none" then
        eq(type(why), "string")
    end
    if failing == "none" then
        eq(table.concat(calls, ","), "create,write,flush,close,replace")
    end
    if failing == "write" or failing == "throw-write" then
        eq(table.concat(calls, ","), "create,write,close")
    end
end
eq(Storage.atomic(nil, "value"), false)
eq(Storage.atomic("bad\0path", "value"), false)
eq(Storage.atomic("test", string.rep("x", 1048577)), false)

local file = os.tmpname()
local old = assert(io.open(file, "wb"))
old:write("old data")
old:close()
local okay, why = Storage.atomic(file, "unicode value \195\169\nfalse=0\n")
assert(okay, why)
local saved = assert(io.open(file, "rb"))
eq(saved:read("*a"), "unicode value \195\169\nfalse=0\n")
saved:close()
eq(Storage.atomic(file, "second save"), true)
saved = assert(io.open(file, "rb"))
eq(saved:read("*a"), "second save")
saved:close()
assert(os.remove(file))
local store = Storage.default({ os = {
    getenv = function()
        return nil
    end,
} })
eq(store.path, nil)
eq(store.read(), nil)
eq(store.read_legacy("menu"), nil)
eq(store.write_atomic("data"), false)
print("settings storage: " .. checks .. " checks; atomic ordering/refusal and temporary-file replacement")
