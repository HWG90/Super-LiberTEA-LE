-- LuaJIT-native, read-only replacement for the PUC-only font helper. The font
-- resolver still validates its own exact engine image and resource witnesses.
local M = {}
function M.open()
    local ffi = require('ffi')
    if ffi.os ~= 'Windows' then return nil, 'Windows process reader unavailable' end
    ffi.cdef[[
        void *GetCurrentProcess(void);
        void *GetModuleHandleA(const char *name);
        int ReadProcessMemory(void *process, const void *address, void *buffer,
                              size_t count, size_t *read_count);
    ]]
    local kernel = ffi.load('kernel32')
    local process = kernel.GetCurrentProcess()
    local function address(value)
        if type(value) == 'number' then return value end
        return tonumber(ffi.cast('uintptr_t', value))
    end
    local function valid(value)
        return type(value) == 'number' and value == math.floor(value)
            and value >= 0x10000 and value < 0x800000000000
    end
    return {
        address = address,
        module = function(name)
            local p = kernel.GetModuleHandleA(name)
            if p == nil then return nil end
            return address(p)
        end,
        read = function(value, count)
            local at = address(value)
            if not valid(at) or type(count) ~= 'number' or count ~= math.floor(count)
                or count < 1 or count > 4096 or not valid(at + count - 1) then return nil end
            local buffer, got = ffi.new('uint8_t[?]', count), ffi.new('size_t[1]')
            if kernel.ReadProcessMemory(process, ffi.cast('const void *', at), buffer, count, got) == 0
                or tonumber(got[0]) ~= count then return nil end
            return ffi.string(buffer, count)
        end,
    }
end
return M
