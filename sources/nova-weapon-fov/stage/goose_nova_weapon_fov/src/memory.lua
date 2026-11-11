-- Protected Windows memory I/O for Nova Weapon FOV, after Height Over Bore's src/memory.lua.
-- Loading this file or calling new() makes no game access; the FFI declarations and kernel32
-- load happen on the first read. Writes go only to committed private read-write memory outside
-- any module image, and every write is read back.
local M = {}
local LOW, LIMIT = 65536, 2^47
local MAX_READ, MAX_WRITE = 8192, 64
local DECLARATIONS = [[
    typedef struct NovaFOV_Region {
        uint64_t base, allocation_base;
        uint32_t allocation_protection;
        uint16_t partition, reserved;
        uint64_t size;
        uint32_t state, protection, type, padding;
    } NovaFOV_Region;
    void *NovaFOV_GetModuleHandleA(const char *name) __asm__("GetModuleHandleA");
    void *NovaFOV_GetCurrentProcess(void) __asm__("GetCurrentProcess");
    int NovaFOV_ReadProcessMemory(void *process, const void *address,
        void *buffer, size_t size, size_t *done) __asm__("ReadProcessMemory");
    int NovaFOV_WriteProcessMemory(void *process, void *address,
        const void *buffer, size_t size, size_t *done) __asm__("WriteProcessMemory");
    size_t NovaFOV_VirtualQuery(const void *address, NovaFOV_Region *region,
        size_t size) __asm__("VirtualQuery");
]]

local function integer(value, maximum)
    return type(value) == 'number' and value == math.floor(value) and value >= 0 and value <= maximum
end

local function u32(bytes, offset)
    offset = offset or 0
    if type(bytes) ~= 'string' or #bytes < offset + 4 then return nil end
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

function M.new()
    return setmetatable({}, {__index = M})
end

function M:_windows()
    if self._kernel then return self._kernel end
    local ok, result = pcall(function()
        local ffi = require('ffi')
        assert(ffi.os == 'Windows' and ffi.abi('64bit'), 'Windows x64 is required')
        if not pcall(ffi.typeof, 'NovaFOV_Region') then ffi.cdef(DECLARATIONS) end
        local library = ffi.load('kernel32')
        self._ffi = ffi
        self._buffer = ffi.new('uint8_t[?]', MAX_READ)
        self._count = ffi.new('size_t[1]')
        self._region = ffi.new('NovaFOV_Region')
        return {
            library = library,
            module = library.NovaFOV_GetModuleHandleA,
            process = library.NovaFOV_GetCurrentProcess(),
            read = library.NovaFOV_ReadProcessMemory,
            write = library.NovaFOV_WriteProcessMemory,
            query = library.NovaFOV_VirtualQuery,
        }
    end)
    if not ok then return nil, tostring(result) end
    self._kernel = result
    return result
end

function M:read(address, size)
    if not integer(address, LIMIT - 1) or address < LOW or not integer(size, MAX_READ)
        or size == 0 or address + size > LIMIT then
        return nil, 'Read is out of bounds'
    end
    local kernel, why = self:_windows()
    if not kernel then return nil, why end
    local ffi = self._ffi
    self._count[0] = 0
    local copied = kernel.read(kernel.process, ffi.cast('const void *', address), self._buffer, size, self._count)
    if copied == 0 or tonumber(self._count[0]) ~= size then return nil, 'Memory is unreadable' end
    return ffi.string(self._buffer, size)
end

-- Base, image size and PE TimeDateStamp of a loaded module.
function M:module(name)
    local kernel, why = self:_windows()
    if not kernel then return nil, why end
    local base = tonumber(self._ffi.cast('uintptr_t', kernel.module(name)))
    if not integer(base, LIMIT - 1) or base < LOW then return nil, name .. ' is not loaded' end
    local dos = self:read(base, 64)
    if not dos or dos:sub(1, 2) ~= 'MZ' then return nil, name .. ' DOS header differs' end
    local offset = u32(dos, 0x3C)
    if not offset or offset < 64 or offset > 4096 then return nil, name .. ' PE offset differs' end
    local pe = self:read(base + offset, 96)
    if not pe or pe:sub(1, 4) ~= 'PE\0\0' or pe:sub(5, 6) ~= '\100\134' or pe:sub(25, 26) ~= '\11\2' then
        return nil, name .. ' is not an AMD64 PE32+ image'
    end
    local stamp, size = u32(pe, 8), u32(pe, 80)
    self._images = self._images or {}
    self._images[name] = {base = base, size = size}
    return base, size, stamp
end

function M:_writable(address, size)
    for _, image in pairs(self._images or {}) do
        if address < image.base + image.size and address + size > image.base then
            return false, 'Module image writes are forbidden'
        end
    end
    local kernel, why = self:_windows()
    if not kernel then return false, why end
    local ffi, region = self._ffi, self._region
    if kernel.query(ffi.cast('const void *', address), region, ffi.sizeof(region)) ~= ffi.sizeof(region) then
        return false, 'Write region is unavailable'
    end
    local base, length = tonumber(region.base), tonumber(region.size)
    if not base or not length or base > address or base + length < address + size
        or region.state ~= 0x1000 or region.type ~= 0x20000 or region.protection ~= 4 then
        return false, 'Writes require committed private read-write memory'
    end
    return true
end

function M:write(address, bytes)
    if type(bytes) ~= 'string' or #bytes == 0 or #bytes > MAX_WRITE
        or not integer(address, LIMIT - 1) or address < LOW or address + #bytes > LIMIT then
        return false, 'Write is out of bounds'
    end
    local writable, why = self:_writable(address, #bytes)
    if not writable then return false, why end
    local kernel = self._kernel
    local ffi = self._ffi
    ffi.copy(self._buffer, bytes, #bytes)
    self._count[0] = 0
    local copied = kernel.write(kernel.process, ffi.cast('void *', address), self._buffer, #bytes, self._count)
    if copied == 0 or tonumber(self._count[0]) ~= #bytes then return false, 'Memory write failed' end
    if self:read(address, #bytes) ~= bytes then return false, 'Memory write readback failed' end
    return true
end

return M
