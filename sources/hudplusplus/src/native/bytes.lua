local band = require("bit").band
local M = {}
M.WIDTH = { u32 = 4, u16 = 2, i32 = 4, f32 = 4, u8 = 1, bool = 1, bit = 1, hex64 = 8, key64 = 8 }
function M.pack(value, width)
    if type(value) ~= "number" or not (value >= 0 and value < 2 ^ (width * 8) and value % 1 == 0) then
        return nil
    end
    local out = {}
    for index = 1, width do
        out[index] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(out)
end
local function fits(bytes, at, width)
    return type(bytes) == "string" and at ~= nil and at >= 0 and at + width <= #bytes
end
function M.u8(bytes, at)
    if not fits(bytes, at, 1) then
        return nil
    end
    return string.byte(bytes, at + 1)
end
function M.u16(bytes, at)
    if not fits(bytes, at, 2) then
        return nil
    end
    local a, b = string.byte(bytes, at + 1, at + 2)
    return a + b * 256
end
function M.u32(bytes, at)
    if not fits(bytes, at, 4) then
        return nil
    end
    local a, b, c, d = string.byte(bytes, at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
function M.i32(bytes, at)
    local value = M.u32(bytes, at)
    if value == nil then
        return nil
    end
    if value >= 2147483648 then
        return value - 4294967296
    end
    return value
end
local function f32_bits(bits)
    if bits == nil then
        return nil
    end
    local sign = bits >= 2147483648 and -1 or 1
    local exponent = math.floor(bits / 8388608) % 256
    local fraction = bits % 8388608
    if exponent == 255 then
        if fraction ~= 0 then
            return 0 / 0
        end
        return sign * math.huge
    end
    if exponent == 0 then
        return math.ldexp(sign * fraction, -149)
    end
    return math.ldexp(sign * (8388608 + fraction), exponent - 150)
end
M.f32_bits = f32_bits
function M.f32(bytes, at)
    return f32_bits(M.u32(bytes, at))
end
function M.bit(bytes, at, n)
    if at == nil or type(n) ~= "number" or n < 0 or n % 1 ~= 0 then
        return nil
    end
    local byte = M.u8(bytes, at + math.floor(n / 8))
    if byte == nil then
        return nil
    end
    return math.floor(byte / 2 ^ (n % 8)) % 2
end
function M.any_bit(value, mask)
    -- Native flags are 32-bit integers. Preserve the arithmetic behavior for other inputs.
    if
        type(value) == "number"
        and type(mask) == "number"
        and value >= -2147483648
        and value <= 4294967295
        and value % 1 == 0
        and mask >= 0
        and mask <= 4294967295
        and mask % 1 == 0
    then
        return band(value, mask) ~= 0
    end
    local step = 1
    while step <= mask do
        if math.floor(mask / step) % 2 == 1 and math.floor(value / step) % 2 == 1 then
            return true
        end
        step = step * 2
    end
    return false
end
function M.hex(bytes, at, size)
    at = at or 0
    size = size or (#bytes - at)
    local digits = {}
    for step = 0, size - 1 do
        digits[step + 1] = string.format("%02x", string.byte(bytes, at + step + 1))
    end
    return table.concat(digits)
end
function M.hex_words(high, low)
    if low == nil or high == nil or (low == 0 and high == 0) then
        return nil
    end
    return string.format("%08x%08x", high, low)
end
function M.words_of(text)
    if type(text) ~= "string" or #text ~= 16 or string.find(text, "[^0-9a-f]") ~= nil then
        return nil
    end
    return tonumber(string.sub(text, 1, 8), 16), tonumber(string.sub(text, 9, 16), 16)
end
function M.hex64(bytes, at)
    at = at or 0
    return M.hex_words(M.u32(bytes, at + 4), M.u32(bytes, at))
end
function M.decode(row, at, form, bit)
    if form == "u32" then
        return M.u32(row, at)
    end
    if form == "u16" then
        return M.u16(row, at)
    end
    if form == "i32" then
        return M.i32(row, at)
    end
    if form == "f32" then
        return M.f32(row, at)
    end
    if form == "u8" then
        return M.u8(row, at)
    end
    if form == "bool" then
        local byte = M.u8(row, at)
        if byte == nil then
            return nil
        end
        return byte ~= 0
    end
    if form == "bit" then
        return M.bit(row, at, bit)
    end
    if form == "hex64" then
        return M.hex64(row, at)
    end
    if form == "key64" then
        local low, high = M.u32(row, at), M.u32(row, at + 4)
        if low == nil or high == nil then
            return nil
        end
        return M.hex_words(high, low) or false
    end
    return nil
end
return M
