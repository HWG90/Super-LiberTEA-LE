-- Offline check of HD2 HUD+'s direct memory read (native.channel Channel:text) in a built bundle.
-- usage: luajit tests/test_channel_text.lua <bundle.lua>
-- On 26251122 a game.dll code page stays no-access until the game first runs it. On 2026-11-03 07:14 a hot join
-- crashed the game: the reinforce markers' code walker read 16 bytes at game+0xf74ff1, the last 15 bytes of a
-- readable page plus one byte of a no-access page. Channel:text must ask VirtualQuery about every page a read
-- touches and answer nil instead of reading a page that is not committed and readable.
-- The test loads native.channel from the bundle with LuaJIT's real ffi and a fake kernel32 whose VirtualQuery
-- describes a buffer of ordinary memory, so a read the guard should have refused still returns bytes instead of
-- crashing the test.
local real = require("ffi")
local f = assert(io.open(assert(arg[1], "bundle path"), "rb"))
local bundle = f:read("*a")
f:close()

local function module_source(name)
    local head = 'modules["' .. name .. '"] = function(require)'
    local from = assert(bundle:find(head, 1, true), "no module " .. name)
    local to = bundle:find('\nmodules%["', from + #head) or error("no module after " .. name)
    return bundle:sub(from, to)
end

local PAGE = 4096
local block = real.new("uint8_t[?]", 5 * PAGE)
local first = math.ceil(tonumber(real.cast("uintptr_t", block)) / PAGE) * PAGE
for i = 0, 3 * PAGE - 1 do real.cast("uint8_t *", first)[i] = i % 251 end

-- the fake memory map: {base, size, state, protect} regions, everything else free
local map
local function region_at(address)
    for _, r in ipairs(map) do
        if address >= r[1] and address < r[1] + r[2] then return r end
    end
    return { math.floor(address / PAGE) * PAGE, PAGE, 0x10000, 0x01 }
end
local queries = 0
local kernel = {
    -- open() refuses without an exe handle; nothing in this test reads through it
    GetModuleHandleA = function() return real.cast("void *", first) end,
    hd2hud_query = function(address, region, size)
        queries = queries + 1
        if map.fail then return 0 end
        local r = region_at(tonumber(address))
        region[0].base, region[0].size = r[1], r[2]
        region[0].state, region[0].protect = r[3], r[4]
        return size
    end,
}
local ffi = setmetatable({
    load = function(name)
        if name == "kernel32" then return kernel end
        return {}
    end,
}, { __index = real })

local modules = assert(loadstring("local modules = {}\n" .. module_source("native.bytes") .. module_source("native.channel")
    .. "return modules", "=channel"))()
local loaded = {}
local function require(name)
    if name == "ffi" then return ffi end
    if loaded[name] == nil then loaded[name] = assert(modules[name], "no module " .. name)(require) end
    return loaded[name]
end
local channel = assert(require("native.channel").channel.open())

local failures = 0
local function expect(label, got, want)
    if got ~= want then
        failures = failures + 1
        print("FAIL " .. label .. ": got " .. (got == nil and "nil" or ("%d bytes"):format(#got))
            .. ", want " .. (want == nil and "nil" or ("%d bytes"):format(#want)))
    else
        print("ok   " .. label)
    end
end
local function bytes(at, n) return real.string(real.cast("const uint8_t *", at), n) end
local A, B, C = first, first + PAGE, first + 2 * PAGE
local READ, EXECUTE_READ, NOACCESS, GUARD_RW = 0x02, 0x20, 0x01, 0x104

map = { { A, PAGE, 0x1000, EXECUTE_READ }, { B, PAGE, 0x1000, NOACCESS } }
expect("read inside a readable page", channel:text(A + 16, 16), bytes(A + 16, 16))
expect("whole readable page", channel:text(A, PAGE), bytes(A, PAGE))
expect("16 bytes at page end - 15, next page no-access (the 07:14 crash)", channel:text(B - 15, 16), nil)
expect("read inside a no-access page", channel:text(B + 8, 4), nil)
map = { { A, PAGE, 0x1000, EXECUTE_READ }, { B, PAGE, 0x1000, GUARD_RW } }
expect("read into a guard page", channel:text(B - 4, 8), nil)
map = { { A, PAGE, 0x1000, EXECUTE_READ }, { B, PAGE, 0x2000, READ } }
expect("read into a reserved page", channel:text(B - 4, 8), nil)
map = { { A, 2 * PAGE, 0x1000, EXECUTE_READ }, { C, PAGE, 0x1000, READ } }
expect("read across two readable regions", channel:text(B - 8, PAGE + 16), bytes(B - 8, PAGE + 16))
map = { { A, PAGE, 0x1000, EXECUTE_READ }, fail = true }
expect("VirtualQuery fails", channel:text(A, 8), nil)
map = { { A, PAGE, 0x1000, EXECUTE_READ } }
expect("zero size", channel:text(A, 0), nil)
print(queries > 0 and "VirtualQuery was asked " .. queries .. " times" or "FAIL VirtualQuery was never asked")
if queries == 0 then failures = failures + 1 end
print(failures == 0 and "all passed" or failures .. " failed")
os.exit(failures == 0 and 0 or 1)
