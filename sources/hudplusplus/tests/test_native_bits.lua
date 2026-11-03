-- Run: luajit tests/test_native_bits.lua src /path/to/original-bundle.lua [--benchmark]
local source, baseline = arg[1] or "src", assert(arg[2], "pass the original upstream bundle as argument 2")
local file = assert(io.open(baseline, "rb"))
local original = file:read("*a")
file:close()

local checks = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    checks = checks + 1
end
local old_modules = {}
local function old_require(name)
    if old_modules[name] ~= nil then
        return old_modules[name]
    end
    local marker = 'modules["' .. name .. '"] = function(require)\n'
    local first = assert(original:find(marker, 1, true), name) + #marker
    local last = assert(original:find('\nmodules["', first, true), name)
    local factory =
        assert(loadstring("return function(require)\n" .. original:sub(first, last - 1), "@upstream/" .. name))()
    local result = factory(old_require)
    old_modules[name] = result
    return result
end

local native_bit = require("bit")
local work = { band = 0, bxor = 0 }
local modules = {
    bit = {
        band = function(a, b)
            work.band = work.band + 1
            return native_bit.band(a, b)
        end,
        bxor = function(a, b)
            work.bxor = work.bxor + 1
            return native_bit.bxor(a, b)
        end,
    },
}
local function current_require(name)
    if modules[name] ~= nil then
        return modules[name]
    end
    local loader = assert(loadfile(source .. "/" .. name:gsub("%.", "/") .. ".lua"))
    setfenv(loader, setmetatable({ require = current_require }, { __index = _G }))
    modules[name] = loader()
    return modules[name]
end
local bytes, old_bytes = current_require("native.bytes"), old_require("native.bytes")
local addons, old_addons = current_require("core.addons"), old_require("core.addons")

-- Signed values, high unsigned bits, negative masks, fractional values, and >32-bit fallback.
local values = {
    -4294967296,
    -2147483648,
    -1,
    -0.5,
    0,
    0.5,
    1,
    2,
    10,
    65535,
    2147483647,
    2147483648,
    4294967295,
    4294967296,
    4503599627370495,
    math.huge,
    -math.huge,
    0 / 0,
}
local masks = {
    -2147483648,
    -1,
    -0.5,
    0,
    0.5,
    1,
    2,
    8,
    10,
    65535,
    2147483647,
    2147483648,
    4294967295,
    4294967296,
    4503599627370495,
    0 / 0,
}
for _, value in ipairs(values) do
    for _, mask in ipairs(masks) do
        equal(bytes.any_bit(value, mask), old_bytes.any_bit(value, mask), "flag behavior")
    end
end
equal(bytes.any_bit(nil, 0), old_bytes.any_bit(nil, 0), "zero mask does not read its value")
equal(bytes.any_bit(false, -1), old_bytes.any_bit(false, -1), "negative mask does not read its value")
local seed = 12345
local function random(limit)
    seed = (seed * 48271) % 2147483647
    return seed % limit
end
for _ = 1, 10000 do
    local value = random(65536) * 65536 + random(65536)
    local mask = random(65536) * 65536 + random(65536)
    if random(2) == 0 and value >= 2147483648 then
        value = value - 4294967296
    end
    equal(bytes.any_bit(value, mask), old_bytes.any_bit(value, mask), "random flag behavior")
end

-- Known archive resource hash (raw bytes are little-endian).
equal(bytes.hex(addons.hash("mods/hd2_hud/hd2_hud_plus")), "130adfc16d6ae456", "main addon resource key")
equal(bytes.hex(addons.hash("")), "0000000000000000", "empty-name hash")
for _, name in ipairs({
    "a",
    "scripts/boot/boot",
    "mods/hd2_hud/hd2_hud_plus",
    "mods/example/reticle",
    "1234567",
    "12345678",
    "123456789",
    "\0\255\128\001",
    string.rep("x", 1024),
}) do
    equal(addons.hash(name), old_addons.hash(name), "archive name hash")
end
for _ = 1, 300 do
    local chars = {}
    for i = 1, random(257) do
        chars[i] = string.char(random(256))
    end
    local name = table.concat(chars)
    equal(addons.hash(name), old_addons.hash(name), "random archive name hash")
end

work.band = 0
equal(bytes.any_bit(0, 4294967295), false)
equal(work.band, 1, "one native AND replaces up to 32 arithmetic bit iterations")
work.bxor = 0
addons.hash("mods/hd2_hud/hd2_hud_plus")
equal(work.bxor, 36, "36 native XOR operations replace 576 arithmetic bit iterations")
print(
    "native bits: "
        .. checks
        .. " differential checks passed; worst-case flag loop 32 -> 1, addon hash XOR loop 576 -> 36"
)

if arg[3] == "--benchmark" then
    -- Use real native helpers rather than the operation-counting wrappers above.
    local direct = { bit = native_bit }
    local function direct_require(name)
        if direct[name] ~= nil then
            return direct[name]
        end
        local loader = assert(loadfile(source .. "/" .. name:gsub("%.", "/") .. ".lua"))
        setfenv(loader, setmetatable({ require = direct_require }, { __index = _G }))
        direct[name] = loader()
        return direct[name]
    end
    local fast_bytes, fast_addons = direct_require("native.bytes"), direct_require("core.addons")
    local inputs, names = {}, {}
    for i = 1, 1024 do
        inputs[i] = random(65536) * 65536 + random(65536)
    end
    for i = 1, 32 do
        names[i] = "mods/hd2_hud/example_" .. i
    end
    local function flags(fn, masks)
        local checksum = 0
        for i = 1, 1000000 do
            if fn(inputs[i % #inputs + 1], masks[i % #masks + 1]) then
                checksum = checksum + 1
            end
        end
        return checksum
    end
    local function hashes(fn)
        local checksum = 0
        for i = 1, 10000 do
            local key = fn(names[i % #names + 1])
            checksum = checksum + key:byte(1) + key:byte(8)
        end
        return checksum
    end
    local function compare(label, run, before, after)
        run(before)
        run(after)
        local times = { {}, {} }
        for sample = 1, 3 do
            for index, fn in ipairs({ before, after }) do
                collectgarbage("collect")
                local started = os.clock()
                local checksum = run(fn)
                times[index][sample] = os.clock() - started
                equal(checksum, run(index == 1 and after or before), label .. " checksum")
            end
        end
        table.sort(times[1])
        table.sort(times[2])
        print(
            string.format("%s: original %.6fs, native %.6fs (median of 3; CPU time)", label, times[1][2], times[2][2])
        )
    end
    print("Local LuaJIT helper benchmarks; these do not measure in-game frame rates.")
    compare("1,000,000 common flag checks", function(fn)
        return flags(fn, { 2, 8, 10 })
    end, old_bytes.any_bit, fast_bytes.any_bit)
    compare("1,000,000 high-bit flag checks", function(fn)
        return flags(fn, { 2147483648 })
    end, old_bytes.any_bit, fast_bytes.any_bit)
    compare("10,000 archive-name hashes", hashes, old_addons.hash, fast_addons.hash)
end
