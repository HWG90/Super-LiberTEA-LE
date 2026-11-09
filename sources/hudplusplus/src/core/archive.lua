-- Archive addon discovery and resource-name hashing.
local Bytes = require("native.bytes")
local xor16 = require("bit").bxor
local Core = {}
local FAMILY = "9ba626afa44a3aa3"
local LUA_TYPE = "\226\023\209\044\250\141\078\161"
local DECLARATION = '^local HD2_HUD_ADDON = "(mods/[%w_]+/[%w_/]+)"\r?\n'
local HEADER, TYPE_ROW, ENTRY_ROW, MAGIC = 72, 32, 80, 0xf0000011
local PREFIX = 256
local LIMB = 65536
local M = { 0xe995, 0x5bd1, 0xa793, 0xc6a4 }
local function mul(a, b)
    local out, carry = {}, 0
    for i = 1, 4 do
        local sum = carry
        for j = 1, i do
            sum = sum + a[j] * b[i - j + 1]
        end
        out[i] = sum % LIMB
        carry = math.floor(sum / LIMB)
    end
    return out
end
local function xor(a, b)
    return { xor16(a[1], b[1]), xor16(a[2], b[2]), xor16(a[3], b[3]), xor16(a[4], b[4]) }
end
local function shift47(a)
    return { (math.floor(a[3] / 32768) + a[4] * 2) % LIMB, math.floor(a[4] / 32768), 0, 0 }
end
local function word(text, at)
    local limbs = {}
    for i = 1, 4 do
        local low = text:byte(at + 2 * i - 2) or 0
        local high = text:byte(at + 2 * i - 1) or 0
        limbs[i] = low + high * 256
    end
    return limbs
end
function Core.hash(name)
    local length = #name
    local h = mul({ length % LIMB, math.floor(length / LIMB), 0, 0 }, M)
    local whole = length - length % 8
    for at = 1, whole, 8 do
        local k = mul(word(name, at), M)
        k = mul(xor(k, shift47(k)), M)
        h = mul(xor(h, k), M)
    end
    if whole < length then
        h = mul(xor(h, word(name:sub(whole + 1) .. string.rep("\0", 8), 1)), M)
    end
    h = mul(xor(h, shift47(h)), M)
    h = xor(h, shift47(h))
    local bytes = {}
    for i = 1, 4 do
        bytes[#bytes + 1] = string.char(h[i] % 256, math.floor(h[i] / 256))
    end
    return table.concat(bytes)
end
function Core.declared(prefix)
    local name = type(prefix) == "string" and prefix:match(DECLARATION) or nil
    if name == nil or name:find("//", 1, true) or name:sub(-1) == "/" then
        return nil
    end
    return name
end
local u32 = Bytes.u32
local function u64(bytes, at)
    local high = u32(bytes, at + 4)
    if high > 2097151 then
        return nil
    end
    return u32(bytes, at) + high * 4294967296
end
local function read_at(file, at, count)
    if file:seek("set", at) ~= at then
        return nil
    end
    if count == 0 then
        return ""
    end
    local bytes = file:read(count)
    if bytes == nil or #bytes ~= count then
        return nil
    end
    return bytes
end
local function scan_file(file, seen, names, out)
    local size = file:seek("end")
    if size == nil or size < HEADER then
        return false
    end
    local header = read_at(file, 0, HEADER)
    if header == nil or u32(header, 0) ~= MAGIC then
        return false
    end
    local types, count = u32(header, 4), u32(header, 8)
    local first = HEADER + TYPE_ROW * types
    local last = first + ENTRY_ROW * count
    if types == 0 or last > size then
        return false
    end
    for index = 0, count - 1 do
        local row = read_at(file, first + index * ENTRY_ROW, ENTRY_ROW)
        if row == nil then
            return false
        end
        if row:sub(9, 16) == LUA_TYPE then
            local key = row:sub(1, 8)
            local at, length = u64(row, 16), u32(row, 56)
            if not seen[key] and at ~= nil and at >= last and length >= 8 and at <= size and length <= size - at then
                local envelope = read_at(file, at, 8)
                if envelope ~= nil and u32(envelope, 4) == 2 and u32(envelope, 0) <= length - 8 then
                    seen[key] = true
                    local prefix = read_at(file, at + 8, math.min(u32(envelope, 0), PREFIX))
                    local name = Core.declared(prefix)
                    if name ~= nil and not names[name] and Core.hash(name) == key then
                        names[name] = true
                        out[#out + 1] = name
                    end
                end
            end
        end
    end
    return true
end
function Core.scan(files, open)
    local ordered = {}
    for index = 1, #files do
        ordered[index] = files[index]
    end
    table.sort(ordered, function(a, b)
        if a.number ~= b.number then
            return a.number > b.number
        end
        return a.path < b.path
    end)
    local seen, names, out, faults = {}, {}, {}, 0
    for index = 1, #ordered do
        local ok, file = pcall(open, ordered[index].path, "rb")
        if ok and file ~= nil then
            local read, fine = pcall(scan_file, file, seen, names, out)
            pcall(file.close, file)
            if not read or not fine then
                faults = faults + 1
            end
        else
            faults = faults + 1
        end
    end
    return out, faults
end
function Core.data_folder(exe)
    if type(exe) ~= "string" then
        return nil
    end
    exe = exe:gsub("\\", "/")
    local tail = "/bin/helldivers2.exe"
    if exe:lower():sub(-#tail) ~= tail then
        return nil
    end
    return exe:sub(1, -#tail - 1) .. "/data/"
end
function Core.list(folder, source)
    local names, why = source.list(folder .. FAMILY .. ".patch_*")
    if names == nil then
        return nil, why
    end
    local files = {}
    for _, name in ipairs(names) do
        local number = name:match("^" .. FAMILY .. "%.patch_(%d+)$")
        if number ~= nil then
            files[#files + 1] = { path = folder .. name, number = tonumber(number) }
        end
    end
    return files
end
function Core.discover(source)
    local exe, why = source.executable()
    if exe == nil then
        return nil, why
    end
    local folder = Core.data_folder(exe)
    if folder == nil then
        return nil, "exe-name"
    end
    local files
    files, why = Core.list(folder, source)
    if files == nil then
        return nil, why
    end
    return (Core.scan(files, source.open))
end
return Core
