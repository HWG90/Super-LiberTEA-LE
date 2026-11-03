local B = require("native.bytes")
local NativeChannel = require("native.channel").channel
local M = { bytes = B }
M.COUNT_LIMIT = 1024
function M.swap(channel, address, want, to)
    if type(to) ~= "string" or #to == 0 or (want ~= nil and (type(want) ~= "string" or #want ~= #to)) then
        return false, "value"
    end
    local now = channel:text(address, #to)
    if now == to then
        return true, "already"
    end
    if now == nil and want == nil then
        return false, "unread"
    end
    if want ~= nil and now ~= want then
        return false, "changed"
    end
    if not channel:put(address, to) then
        return false, "protect-refused"
    end
    return true, "written"
end
local ROUTINES = setmetatable({}, { __mode = "k" })
function M.head_of(spec)
    local head, mask, offset = spec.head, spec.head_mask, spec.head_at
    if head == nil then
        if mask ~= nil or offset ~= nil then
            return nil, "spec"
        end
        return nil, "head"
    end
    if type(head) ~= "string" or #head < 32 or #head % 2 ~= 0 or head:find("[^%x]") then
        return nil, "spec"
    end
    if offset == nil then
        offset = 0
    end
    if type(offset) ~= "number" or not (offset >= 0 and offset % 1 == 0) then
        return nil, "spec"
    end
    head = string.lower(head)
    if mask ~= nil then
        if type(mask) ~= "string" or #mask ~= #head then
            return nil, "spec"
        end
        mask = string.lower(mask)
        local kept = 0
        for index = 1, #mask, 2 do
            local byte = mask:sub(index, index + 1)
            if byte == "ff" then
                kept = kept + 1
            elseif byte ~= "00" then
                return nil, "spec"
            end
        end
        if kept < 16 then
            return nil, "spec"
        end
    end
    return { head = head, mask = mask, offset = offset }
end
function M.head_matches(channel, at, head)
    local size = #head.head / 2
    local bytes = channel:text(at + head.offset, size)
    if bytes == nil then
        return nil, "head-unread"
    end
    local actual = B.hex(bytes, 0, size)
    for index = 1, #head.head, 2 do
        if
            (head.mask == nil or head.mask:sub(index, index + 1) == "ff")
            and actual:sub(index, index + 1) ~= head.head:sub(index, index + 1)
        then
            return nil, "head"
        end
    end
    return true
end
function M.routine(channel, spec)
    if type(spec) ~= "table" or type(spec.at) ~= "number" or type(spec.ctype) ~= "string" then
        return nil, "spec"
    end
    if spec.result ~= nil and spec.result ~= "hex64" and spec.result ~= "f32x2" then
        return nil, "spec"
    end
    if spec.result ~= nil and not spec.ctype:match("^uint64_t %(%*%)") then
        return nil, "spec"
    end
    local fn, why = channel:entry(spec.at, spec.ctype)
    if fn == nil then
        return nil, why
    end
    local routine = {}
    ROUTINES[routine] = { fn = fn, result = spec.result }
    return routine
end
function M.hex64_of(ffi, value)
    local box = ffi.new("uint64_t[1]", value)
    local words = ffi.cast("uint32_t *", box)
    return string.format("%08x%08x", tonumber(words[1]), tonumber(words[0]))
end
function M.uint64_of(ffi, text)
    local high, low = B.words_of(text)
    if high == nil then
        return nil
    end
    return ffi.new("uint64_t", high) * 4294967296 + low
end
local function settled(ffi, result, ...)
    if select("#", ...) == 0 then
        return
    end
    local value = ...
    if result == "hex64" and type(value) == "cdata" then
        return M.hex64_of(ffi, value)
    end
    if result == "f32x2" and type(value) == "cdata" then
        local box = ffi.new("uint64_t[1]", value)
        local pair = ffi.cast("float *", box)
        return tonumber(pair[0]), tonumber(pair[1])
    end
    if type(value) ~= "cdata" then
        return value
    end
    local number = tonumber(value)
    if number ~= nil then
        return number
    end
    return tonumber(ffi.cast("uintptr_t", value))
end
local Instance = {}
Instance.__index = Instance
function M.bind(channel)
    return setmetatable({ channel = channel, ffi = channel.ffi, bytes = B }, Instance)
end
function Instance:text(address, size)
    return self.channel:text(address, size)
end
function Instance:own(text)
    return self.channel:own(text)
end
function Instance:bits(value)
    return self.channel:bits(value)
end
local HEADS = setmetatable({}, { __mode = "k" })
local SLOT = NativeChannel.layout({ { 0, "u32" }, { 4, "u32" } })
function Instance:find(base, layout, key, routine, invalid)
    if routine == nil then
        return nil, "uncalled"
    end
    if key == invalid then
        return nil, "absent"
    end
    local channel, got = self.channel, self.find_got
    if got == nil then
        got = {}
        self.find_got = got
    end
    local head = HEADS[layout]
    if head == nil then
        head = NativeChannel.layout({ { 0, "ptr" }, { layout.capacity, "u32" } })
        HEADS[layout] = head
    end
    channel:load(base, head, got)
    if got[2] == nil then
        return nil, "unread"
    end
    if got[2] == 0 then
        return nil, "absent"
    end
    if got[1] == nil then
        return nil, "unread"
    end
    local slot = self:call(routine, base, key, 1)
    if slot == nil then
        return nil, "uncalled"
    end
    if slot == 0 then
        return nil, "absent"
    end
    channel:load(slot, SLOT, got)
    if got[1] ~= key then
        return nil, "absent"
    end
    return got[2], "present"
end
function Instance:swap(address, want, to)
    return M.swap(self.channel, address, want, to)
end
function Instance:routine(spec)
    return M.routine(self.channel, spec)
end
function Instance:call(routine, ...)
    local entry = ROUTINES[routine]
    if entry == nil then
        return nil
    end
    return settled(self.ffi, entry.result, self.channel:call(entry.fn, ...))
end
return M
