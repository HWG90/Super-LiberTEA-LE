-- Protected Windows heap I/O adapted from DBF's owned runtime backend.
-- Importing or constructing this module performs no game access.
local M = {}
local standard_tonumber,ffi_number=tonumber
local function tonumber(value,radix)
    if radix or type(value)=='number' or type(value)=='string' or value==nil then
        return standard_tonumber(value,radix)
    end
    return ffi_number and ffi_number(value) or nil
end
local HIGH, LIMIT, LOW = 4294967296, 140737488355328, 65536
local STAMP = 0x6AF322C1
local MAX_READ, MAX_WRITE, MAX_CAP, MAX_PROBES = 8192, 4096, 1048576, 4096
local DECLARATIONS = [[
    typedef struct TemporaryUnlockMemory_Region {
        uint64_t base, allocation_base;
        uint32_t allocation_protection;
        uint16_t partition, reserved;
        uint64_t size;
        uint32_t state, protection, type, padding;
    } TemporaryUnlockMemory_Region;
    void *TemporaryUnlockMemory_GetModuleHandleA(const char *name) __asm__("GetModuleHandleA");
    void *TemporaryUnlockMemory_GetCurrentProcess(void) __asm__("GetCurrentProcess");
    int TemporaryUnlockMemory_ReadProcessMemory(void *process, const void *address,
        void *buffer, size_t size, size_t *done) __asm__("ReadProcessMemory");
    int TemporaryUnlockMemory_WriteProcessMemory(void *process, void *address,
        const void *buffer, size_t size, size_t *done) __asm__("WriteProcessMemory");
    size_t TemporaryUnlockMemory_VirtualQuery(const void *address, TemporaryUnlockMemory_Region *region,
        size_t size) __asm__("VirtualQuery");
]]
local function integer(value, maximum)
    return type(value) == 'number' and value == math.floor(value)
        and value >= 0 and value <= maximum
end

local function u32_bytes(bytes, offset)
    offset = offset or 0
    if type(bytes) ~= 'string' or #bytes < offset + 4 then return nil end
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function pointer_bytes(bytes, offset)
    offset = offset or 0
    local low, high = u32_bytes(bytes, offset), u32_bytes(bytes, offset + 4)
    if not low or not high or high >= 32768 then return nil end
    local address = low + high * HIGH
    return address >= LOW and address < LIMIT and address or nil
end

local function product32(a, b)
    local al, ah, bl, bh = a % 65536, math.floor(a / 65536), b % 65536, math.floor(b / 65536)
    return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % HIGH
end


function M.new(io)
    local ffi = require('cffi')
    ffi_number=ffi.tonumber
    local self = setmetatable({_ffi=ffi, _io=io, _frame=0}, {__index=M})
    self._read_buffer=ffi.new('uint8_t[8192]')
    self._write_buffer=ffi.new('uint8_t[4096]')
    self._count=ffi.new('size_t[1]')
    return self
end
function M:_address(address, size)
    local ffi = self._ffi
    if type(address) == 'cdata' or type(address) == 'userdata' then
        local ok, number = pcall(function() return tonumber(ffi.cast('uintptr_t', address)) end)
        address = ok and number or nil
    end
    if not integer(address, LIMIT - 1) or address < LOW
        or not integer(size, MAX_READ) or address + size > LIMIT then
        return nil, 'Address or copy size is out of bounds'
    end
    return address
end

function M:_windows()
    if self._kernel then return self._kernel end
    if self._windows_error then return nil, self._windows_error end
    local ffi = self._ffi
    local ok, result = pcall(function()
        assert(ffi.os == 'Windows' and ffi.abi('64bit'), 'Windows x64 is required')
        if not pcall(ffi.typeof, 'TemporaryUnlockMemory_Region') then ffi.cdef(DECLARATIONS) end
        local library = ffi.load('kernel32')
        local kernel = {
            library = library,
            module = library.TemporaryUnlockMemory_GetModuleHandleA,
            process = library.TemporaryUnlockMemory_GetCurrentProcess(),
            read = library.TemporaryUnlockMemory_ReadProcessMemory,
            write = library.TemporaryUnlockMemory_WriteProcessMemory,
            query = library.TemporaryUnlockMemory_VirtualQuery,
        }
        self._region = ffi.new('TemporaryUnlockMemory_Region')
        return kernel
    end)
    if not ok then self._windows_error = tostring(result); return nil, self._windows_error end
    self._kernel = result
    return result
end

function M:_read_uncached(address, size)
    local checked, why = self:_address(address, size)
    if not checked then return nil, why end
    if size == 0 then return '' end
    if self._io then
        if type(self._io.read) ~= 'function' then return nil, 'Injected reader is unavailable' end
        local ok, bytes = pcall(self._io.read, checked, size)
        if ok and type(bytes) == 'string' and #bytes == size then return bytes end
        return nil, ok and 'Memory is unreadable' or tostring(bytes)
    end
    local kernel
    kernel, why = self:_windows()
    if not kernel then return nil, why end
    self._count[0] = 0
    local copied = kernel.read(kernel.process, self._ffi.cast('const void *', checked),
        self._read_buffer, size, self._count)
    if tonumber(copied) == 0 or tonumber(self._count[0]) ~= size then return nil, 'Memory is unreadable' end
    return self._ffi.string(self._read_buffer, size)
end

-- Reuse identical protected reads only within one synchronous freeze update.
-- Never enlarge a read: CFFI string extraction scales poorly with copy size.
function M:begin_snapshot()
    if not self._io then self._snapshot = {} end
end
function M:end_snapshot() self._snapshot=nil end
function M:read(address,size)
    local cache=self._snapshot
    if not cache then return self:_read_uncached(address,size) end
    local checked,why=self:_address(address,size)
    if not checked then return nil,why end
    local key=checked..':'..size
    if cache[key]~=nil then return cache[key] end
    local bytes,problem=self:_read_uncached(checked,size)
    if bytes then cache[key]=bytes end
    return bytes,problem
end

function M:_heap_writable(address, size)
    if self._io then
        if type(self._io.writable) ~= 'function' then return true end
        local ok, writable, why = pcall(self._io.writable, address, size)
        return ok and writable == true, ok and why or tostring(writable)
    end
    local kernel, why = self:_windows()
    if not kernel then return false, why end
    local ffi, region, cursor = self._ffi, self._region, address
    while cursor < address + size do
        if tonumber(kernel.query(ffi.cast('const void *', cursor), region, ffi.sizeof(region))) ~= ffi.sizeof(region) then
            return false, 'Write region is unavailable'
        end
        local base, length = tonumber(region.base), tonumber(region.size)
        if not base or not length or length <= 0 or base > cursor or base + length <= cursor
            or tonumber(region.state) ~= 0x1000 or tonumber(region.type) ~= 0x20000 or tonumber(region.protection) ~= 4 then
            return false, 'Writes require committed private read-write memory'
        end
        cursor = math.min(base + length, address + size)
    end
    return true
end

function M:copy(address, bytes)
    -- Readback and subsequent ownership checks must observe the actual write.
    self:end_snapshot()
    if type(bytes) ~= 'string' or #bytes == 0 or #bytes > MAX_WRITE then
        return false, 'A write must contain 1..4096 bytes', 0
    end
    local checked, why = self:_address(address, #bytes)
    if not checked then return false, why, 0 end
    if self._game and checked < self._game + self._image_size and checked + #bytes > self._game then
        return false, 'Module image writes are forbidden', 0
    end
    local writable
    writable, why = self:_heap_writable(checked, #bytes)
    if not writable then return false, why or 'Write region is unavailable', 0 end
    local copied_count
    if self._io then
        if type(self._io.write) ~= 'function' then return false, 'Injected writer is unavailable', 0 end
        local ok, result, detail, count = pcall(self._io.write, checked, bytes)
        -- An injected writer can fail after copying data. An absent/invalid
        -- failure count stays unknown; inventing a prefix would claim foreign
        -- bytes during cleanup. Successful mocks default to a full copy.
        if not ok then return false, tostring(result), nil end
        if count == nil and result == true then count = #bytes end
        if integer(count, #bytes) then copied_count = count end
        if result ~= true then return false, detail or 'Memory write failed', copied_count end
        if copied_count ~= #bytes then return false, 'Memory write copied only part of the data', copied_count end
    else
        local kernel
        kernel, why = self:_windows()
        if not kernel then return false, why, 0 end
        local ffi = self._ffi
        ffi.copy(self._write_buffer, bytes, #bytes)
        self._count[0] = 0
        local copied = kernel.write(kernel.process, ffi.cast('void *', checked),
            self._write_buffer, #bytes, self._count)
        local count = tonumber(self._count[0])
        if integer(count, #bytes) then copied_count = count end
        if tonumber(copied) == 0 or copied_count ~= #bytes then
            return false, 'Memory write failed or copied only part of the data', copied_count
        end
    end
    -- A failed readback does not undo the copy. Report its exact prefix so the
    -- controller can retain and restore the lease instead of acknowledging it.
    if self:read(checked, #bytes) ~= bytes then return false, 'Memory write readback failed', copied_count end
    return true, nil, copied_count
end

function M:_fast_reads()
    if self._io or self._fast_unavailable then return nil end
    if self._fast then return self._fast end
    local ok,result=pcall(function()
        local ffi=self._ffi
        ffi.cdef('double GGR_scalar(double address, int size); double GGR_hashmap(double address, double key); double GGR_roster(double address, double peer); double GGR_module(void);')
        local lib=ffi.load(mod.dir..'/native/guarded_reads_218dbf400f24f282.dll')
        return {library=lib,GGR_scalar=lib.GGR_scalar,GGR_hashmap=lib.GGR_hashmap,GGR_roster=lib.GGR_roster,GGR_module=lib.GGR_module}
    end)
    if ok then self._fast=result else self._fast_unavailable=true end
    return self._fast
end
function M:roster_has(roster,peer)
    local helper=self:_fast_reads()
    if not helper then return nil,'Native roster reader unavailable' end
    local value=helper.GGR_roster(roster,peer)
    if value<0 then return nil,'Session roster is unreadable' end
    return value==1
end
local function scalar(self,address,size)
    local checked,why=self:_address(address,size)
    if not checked then return nil,why end
    local helper=self:_fast_reads()
    if not helper then return nil,nil,false end
    local value=helper.GGR_scalar(checked,size)
    if value<0 then return nil,'Memory is unreadable',true end
    return value,nil,true
end
function M:ptr(address)
    local value,why,used=scalar(self,address,8)
    if used then return value,why end
    local bytes, why = self:read(address, 8)
    local pointer = pointer_bytes(bytes)
    if pointer then return pointer end
    return nil, why or 'Pointer is unavailable or out of bounds'
end

function M:u8(address)
    local value,why,used=scalar(self,address,1)
    if used then return value,why end
    local bytes, why = self:read(address, 1)
    return bytes and bytes:byte(1) or nil, why
end

function M:u32(address)
    local value,why,used=scalar(self,address,4)
    if used then return value,why end
    local bytes, why = self:read(address, 4)
    return u32_bytes(bytes), why
end

function M:begin_frame()
    self:end_snapshot()
    self._frame=self._frame+1
end
function M:_module()
    local helper=self:_fast_reads()
    if helper then
        if self._validated_frame==self._frame and self._game then return self._game,STAMP end
        local base=helper.GGR_module()
        if base<0 then return nil,'game.dll is unavailable or does not match the supported build' end
        if self._game~=base then self._functions,self._validated_game={},nil end
        self._game,self._image_size,self._validated_frame=base,0x3382000,self._frame
        return base,STAMP
    end
    if self._validated_frame==self._frame and self._game then return self._game,STAMP end
    local base, why
    if self._io then
        if type(self._io.module) ~= 'function' then return nil, 'Injected module lookup is unavailable' end
        local ok, result = pcall(self._io.module, 'game.dll')
        if not ok then return nil, tostring(result) end
        base = result
    else
        local kernel
        kernel, why = self:_windows()
        if not kernel then return nil, why end
        base = kernel.module('game.dll')
    end
    base, why = self:_address(base, 64)
    if not base then return nil, why or 'game.dll is not loaded' end
    local dos = self:read(base, 64)
    if not dos or dos:sub(1, 2) ~= 'MZ' then return nil, 'game.dll DOS header is unavailable' end
    local pe_offset = u32_bytes(dos, 0x3C)
    if not pe_offset or pe_offset < 0x40 or pe_offset > 0x1000 then return nil, 'game.dll PE offset is invalid' end
    local pe = self:read(base + pe_offset, 96)
    if not pe or pe:sub(1, 4) ~= 'PE\0\0' or pe:sub(5, 6) ~= '\100\134'
        or pe:sub(25, 26) ~= '\11\2' then return nil, 'game.dll is not an AMD64 PE32+ image' end
    local stamp, image_size = u32_bytes(pe, 8), u32_bytes(pe, 80)
    if stamp ~= STAMP then return nil, string.format('Unsupported game.dll build %08X; required %08X', stamp or 0, STAMP) end
    if not image_size or image_size ~= 0x3382000 or base + image_size > LIMIT then
        return nil, 'game.dll image size is invalid'
    end
    if self._game ~= base then self._functions, self._validated_game = {}, nil end
    self._game, self._image_size = base, image_size
    self._validated_frame=self._frame
    return base, stamp
end

local function power_of_two(n)
    while n>1 and n%2==0 do n=n/2 end
    return n==1
end
function M:_map_header(address)
    local bytes = self:read(address, 20)
    local buckets = pointer_bytes(bytes)
    local cap, empty, mult = u32_bytes(bytes, 8), u32_bytes(bytes, 12), u32_bytes(bytes, 16)
    if not buckets or not cap or cap == 0 or cap > MAX_CAP or not power_of_two(cap)
        or buckets + cap * 8 > LIMIT then return nil, 'Hash map header is invalid' end
    return {bytes = bytes, buckets = buckets, cap = cap, empty = empty, mult = mult}
end

function M:hashmap(address, key)
    if not integer(key, HIGH - 1) then return nil, 'Hash map key is invalid' end
    local helper=self:_fast_reads()
    if helper then
        local checked,why=self:_address(address,20)
        if not checked then return nil,why end
        local value=helper.GGR_hashmap(checked,key)
        if value>=0 then return value end
        return nil,'Hash map entry is unavailable'
    end
    local map, why = self:_map_header(address)
    if not map then return nil, why end
    -- Empty keys never designate a live entry, including when key == empty.
    if key == map.empty then return nil, 'Hash map key is empty' end
    local product = product32(key, map.mult)
    for probe = 0, math.min(map.cap, MAX_PROBES) - 1 do
        local index = (product + probe) % map.cap
        local row = self:read(map.buckets + index * 8, 8)
        if not row then return nil, 'Hash map entry is unreadable' end
        local found = u32_bytes(row)
        if found == map.empty then return nil, 'Hash map entry is absent' end
        if found == key then
            local value = u32_bytes(row, 4)
            if value == 0xFFFFFFFF then return nil, 'Hash map value is invalid' end
            return value
        end
    end
    return nil, 'Hash map probe limit reached'
end

function M:refresh_health(game, manager, entity)
    self:end_snapshot()
    local pin=('488bc4488958104889701848897820554154415541564157488d68a14881ecf00000000f2970c8'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
    if self._io then return false,'Native health refresh is unavailable for injected I/O' end
    if self._game~=game or self:read(game+0x92F690,#pin)~=pin then
        return false,'Health refresh fingerprint mismatch'
    end
    -- Called on the game thread after freezes.lua verifies the living avatar
    -- and its descriptor. Zero fraction uses the normal health notifications.
    if self._health_refresh_game~=game then
        self._health_refresh=self._ffi.cast('void (*)(void *, uint32_t, float)',game+0x92F690)
        self._health_refresh_game=game
    end
    self._health_refresh(self._ffi.cast('void *',manager),entity,0)
    return true
end

function M:complete_objective(game, manager, key)
    self:end_snapshot()
    local pin=('48895c24184889742420574883ec203b159bd985028bfa488bf17507'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
    if self._io then return false,'Native objective completion is unavailable for injected I/O' end
    if self._game~=game or self:read(game+0x5E1720,#pin)~=pin then
        return false,'Objective completion fingerprint mismatch'
    end
    -- Called on the game thread after objectives.lua verifies host authority,
    -- the key's own map row and its open state (5E1720 has no bounds check).
    if self._objective_complete_game~=game then
        self._objective_complete=self._ffi.cast('void (*)(void *, uint32_t)',game+0x5E1720)
        self._objective_complete_game=game
    end
    self._objective_complete(self._ffi.cast('void *',manager),key)
    return true
end


M.u32_bytes=u32_bytes
M.pointer_bytes=pointer_bytes
return M
