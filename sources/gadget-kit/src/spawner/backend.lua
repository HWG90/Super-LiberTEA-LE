local PORT51=mod.require('src/first_person/compat51.lua')
-- Vendored from Bridge Combat (src/backend.lua) for the Goose Gadget Kit spawner; FFI names kept
-- identical so either mod can declare them first.
-- Standalone Windows x64 backend. Loading/constructing this module performs no
-- game reads, writes or game-native calls. observe() is the first discovery step.
-- Layout proof: game.dll PE timestamp 6AB3B43F, hd2_addresses.lua avatar chain,
-- and nova_ship_combat.lua's reversible 0x1160 profile experiment. The larger
-- 0x1214 initializer experiment is deliberately absent from this backend.
local M = {}
local HIGH, LIMIT, LOW = 4294967296, 140737488355328, 65536
local STAMP, PROFILE_BYTES = 0x6AF322C1, 0x1160
local MAX_READ, MAX_WRITE, MAX_CAP, MAX_PROBES = 8192, 4096, 1048576, 4096
local GLOBAL = {
    player = 0x2CE1618, inventory = 0x2CE18E8, world = 0x2CE41B8,
    pm = 0x2CE1EE0, lc = 0x2CE1EB8, game_state = 0x2CE1508,
    input = 0x2E38250, projectiles = 0x2E381E0,
}
local SPECS = {
    add = {0xABC5B0, 'void (*)(void *, const void *)',
        '48895c2408574883ec20488b1a488bfa4c8b89980f00004c8bd94c234a10488b81900f000048234208483b4208488b81880f00000f94c24823c3483bc30f94c033c922d04c3b4f100fb6c20f44c884c9753d490b9b880f000041b00149899b880f0000488bd7488b47084883e3fe490983900f0000498bcb488b4710490983980f000049899b880f0000e841d3f9ff488b5c24304883c4205fc3'},
    remove = {0xABC6C0, 'void (*)(void *, const void *)',
        '48895c2418574883ec20488bb9880f00004c8bc94c8b5a10488bda4c8599980f00004c8b024c8b5208488b91900f00000f95c14985f80f95c00ac80fb6c14923d2b9010000000f45c184c0743349f7d049f7d24d2191900f00004c23c74983e0fe49f7d34d2199980f0000488bd34d8981880f0000498bc94533c0e840d2f9ff488b5c24404883c4205fc3'},
    profile = {0x83EB90, 'void (*)(void *, uint32_t, uint32_t)',
        '405355574883ec203b1532056002418bf88bda488be90f84e4000000448b8100010000448b9108010000488974244033f6440fafd38bd64c897c2450458d78ff4585c00f84ad0000004c8b99f80000004c89742448448bb1040100000f1f4000418bc7428d0c124823c8418b04cb4d8d0ccb413bc6740d3bc3740dffc2413bd072deeb6d3bc37569418b410483f8ff7460488b8cc510010000448bf0f6411401744fe819d6cdff3938740fffc648052c02000083fe0872efeb37496bc6784c8d8590785400ba12e2ae5f4c03c04189304a8b84f5100100008b4810e870ac6200488b0d41324a02448bc68bd3e85ff819004c8b742448488b7424404c8b7c24504883c4205f5d5bc3'},
    query = {0x1190920, 'uint64_t (*)(void *, uint64_t)',
        '48895c240848896c24104889742418574883ec204c8bd94c8bca488bcae81edf3fff418bb3509b0a0041c1e110440fb7d033c0450bd1458b8b489b0a00410faff2418d69ff4585c97435498b9b409b0a00418bbb4c9b0a000f1f8400000000008bcd8d14304823d18b0cd34c8d04d33bcf7423413bca7423ffc0413bc172e133c0488b5c2430488b6c2438488b7424404883c4205fc3413bca75e4418b4004488d0440488d80a74f0100498d04c3ebd1'},
    block = {0x1190350, 'void (*)(void *, uint64_t, uint32_t, float)',
        '48895c240848896c2410488974241848897c24204154415641574883ec20488bf1458be0488bca488bdae8e1e43fff448b86489b0a0033ff8bae509b0a008bcf440fb7c88bc3c1e010440bc8458d78ff410fafe94585c0743d4c8b96409b0a00448b9e4c9b0a00660f1f840000000000418bc78d14294823d0418b04d2413bc30f8487000000413bc10f8483000000ffc1413bc872da448b86347d0a00488d8e409b0a00418bd1418d40018986347d0a004b8d2c40e8463341000f57c048899cee3c7d0a000f2fc34489a4ee387d0a007714f30f591d0e730b01f3480f2cfb4803be287d0a004889bcee487d0a00488b5c2440488b6c2448488b742450488b7c24584883c420415f415e415cc3413bc17584418b44d2040f57c00f2fc3488d0c404489a4ce387d0a007723488b84ce487d0a00f30f591dad720b01f3480f2cfb4803be287d0a00483bc7480f47f84889bcce487d0a00eb96'},
    release = {0x11904b0, 'void (*)(void *, uint64_t)',
        '48896c2418564883ec204c8bd94c8bca488bcae898e33fff418bb3509b0a0041c1e110440fb7d033c0450bd1458b8b489b0a00410faff2418d69ff4585c9746448895c2430498b9b409b0a0048897c2438418bbb4c9b0a000f1f8400000000008bcd8d14304823d18b0cd34c8d04d33bcf740e413bca740effc0413bc172e1eb19413bca7514418b4004488d0c4041c784cb387d0a0000000000488b5c2430488b7c2438488b6c24404883c4205ec3'},
}
local NAMES = {'add', 'remove', 'profile', 'query', 'block', 'release'}
for _, name in ipairs(NAMES) do
    local spec = SPECS[name]
    spec.bytes = spec[3]:gsub('%x%x', function(pair) return string.char(PORT51.number(pair, 16)) end)
end

-- Every Windows declaration has a private FFI identifier. Other mods may have
-- declared the ordinary Windows names with different prototypes in this VM.
local DECLARATIONS = [[
    typedef struct BridgeCombat_Region {
        uint64_t base, allocation_base;
        uint32_t allocation_protection;
        uint16_t partition, reserved;
        uint64_t size;
        uint32_t state, protection, type, padding;
    } BridgeCombat_Region;
    void *BridgeCombat_GetModuleHandleA(const char *name) __asm__("GetModuleHandleA");
    void *BridgeCombat_GetCurrentProcess(void) __asm__("GetCurrentProcess");
    int BridgeCombat_ReadProcessMemory(void *process, const void *address,
        void *buffer, size_t size, size_t *done) __asm__("ReadProcessMemory");
    int BridgeCombat_WriteProcessMemory(void *process, void *address,
        const void *buffer, size_t size, size_t *done) __asm__("WriteProcessMemory");
    size_t BridgeCombat_VirtualQuery(const void *address, BridgeCombat_Region *region,
        size_t size) __asm__("VirtualQuery");
]]

local function integer(value, maximum)
    return PORT51.kind(value) == 'number' and value == math.floor(value)
        and value >= 0 and value <= maximum
end

local function u32_bytes(bytes, offset)
    offset = offset or 0
    if PORT51.kind(bytes) ~= 'string' or #bytes < offset + 4 then return nil end
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

-- The 16-bit partial products stay below 2^53; using ordinary double-precision
-- key * multiplier would corrupt the low 32 bits of large u32 hash keys.
local function product32(a, b)
    local al, ah, bl, bh = a % 65536, math.floor(a / 65536), b % 65536, math.floor(b / 65536)
    return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % HIGH
end

function M.new(log, io)
    local ffi, bit = PORT51.ffi, PORT51.bit
    local self = setmetatable({bit = bit, ffi = ffi}, {__index = M})
    self._log = log or function() end
    self._io, self._ffi = io, ffi
    self._read_buffer = ffi.new('uint8_t[8192]')
    self._write_buffer = ffi.new('uint8_t[4096]')
    self._count = ffi.new('size_t[1]')
    self._word64 = ffi.new('uint64_t[1]')
    self._functions = {}
    self._native_types, self._native_functions = {}, {}
    return self
end

function M:_address(address, size)
    local ffi = self._ffi
    if PORT51.kind(address) == 'cdata' then
        local ok, number = pcall(function() return PORT51.number(ffi.cast('uintptr_t', address)) end)
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
        if not pcall(ffi.typeof, 'BridgeCombat_Region') then ffi.cdef(DECLARATIONS) end
        local library = ffi.load('kernel32')
        local kernel = {
            library = library,
            module = library.BridgeCombat_GetModuleHandleA,
            process = library.BridgeCombat_GetCurrentProcess(),
            read = library.BridgeCombat_ReadProcessMemory,
            write = library.BridgeCombat_WriteProcessMemory,
            query = library.BridgeCombat_VirtualQuery,
        }
        self._region = ffi.new('BridgeCombat_Region')
        return kernel
    end)
    if not ok then self._windows_error = tostring(result); return nil, self._windows_error end
    self._kernel = result
    return result
end

function M:read(address, size)
    local checked, why = self:_address(address, size)
    if not checked then return nil, why end
    if size == 0 then return '' end
    if self._io then
        if PORT51.kind(self._io.read) ~= 'function' then return nil, 'Injected reader is unavailable' end
        local ok, bytes = pcall(self._io.read, checked, size)
        if ok and PORT51.kind(bytes) == 'string' and #bytes == size then return bytes end
        return nil, ok and 'Memory is unreadable' or tostring(bytes)
    end
    local kernel
    kernel, why = self:_windows()
    if not kernel then return nil, why end
    self._count[0] = 0
    local copied = kernel.read(kernel.process, self._ffi.cast('const void *', checked),
        self._read_buffer, size, self._count)
    if PORT51.number(copied) == 0 or PORT51.number(self._count[0]) ~= size then return nil, 'Memory is unreadable' end
    return self._ffi.string(self._read_buffer, size)
end

function M:_heap_writable(address, size)
    if self._io then
        if PORT51.kind(self._io.writable) ~= 'function' then return true end
        local ok, writable, why = pcall(self._io.writable, address, size)
        return ok and writable == true, ok and why or tostring(writable)
    end
    local kernel, why = self:_windows()
    if not kernel then return false, why end
    local ffi, region, cursor = self._ffi, self._region, address
    while cursor < address + size do
        if PORT51.number(kernel.query(ffi.cast('const void *', cursor), region, ffi.sizeof(region))) ~= ffi.sizeof(region) then
            return false, 'Write region is unavailable'
        end
        local base, length = PORT51.number(region.base), PORT51.number(region.size)
        if not base or not length or length <= 0 or base > cursor or base + length <= cursor
            or PORT51.number(region.state) ~= 0x1000 or PORT51.number(region.type) ~= 0x20000 or PORT51.number(region.protection) ~= 4 then
            return false, 'Writes require committed private read-write memory'
        end
        cursor = math.min(base + length, address + size)
    end
    return true
end

function M:write(address, bytes)
    if PORT51.kind(bytes) ~= 'string' or #bytes == 0 or #bytes > MAX_WRITE then
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
        if PORT51.kind(self._io.write) ~= 'function' then return false, 'Injected writer is unavailable', 0 end
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
        local count = PORT51.number(self._count[0])
        if integer(count, #bytes) then copied_count = count end
        if PORT51.number(copied) == 0 or copied_count ~= #bytes then
            return false, 'Memory write failed or copied only part of the data', copied_count
        end
    end
    -- A failed readback does not undo the copy. Report its exact prefix so the
    -- controller can retain and restore the lease instead of acknowledging it.
    if self:read(checked, #bytes) ~= bytes then return false, 'Memory write readback failed', copied_count end
    return true, nil, copied_count
end

function M:ptr(address)
    local bytes, why = self:read(address, 8)
    local pointer = pointer_bytes(bytes)
    if pointer then return pointer end
    return nil, why or 'Pointer is unavailable or out of bounds'
end

function M:u8(address)
    local bytes, why = self:read(address, 1)
    return bytes and bytes:byte(1) or nil, why
end

function M:u32(address)
    local bytes, why = self:read(address, 4)
    return u32_bytes(bytes), why
end

function M:u64(address)
    local bytes, why = self:read(address, 8)
    if not bytes then return nil, why end
    self._ffi.copy(self._word64, bytes, 8)
    return self._word64[0]
end

function M:mask(bits)
    assert(integer(bits, HIGH - 1), 'Context mask must be a u32')
    return self._ffi.new('uint64_t[3]', bits, 0, 0)
end

function M:_module()
    local base, why
    if self._io then
        if PORT51.kind(self._io.module) ~= 'function' then return nil, 'Injected module lookup is unavailable' end
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
    return base, stamp
end

function M:_map_header(address)
    local bytes = self:read(address, 20)
    local buckets = pointer_bytes(bytes)
    local cap, empty, mult = u32_bytes(bytes, 8), u32_bytes(bytes, 12), u32_bytes(bytes, 16)
    if not buckets or not cap or cap == 0 or cap > MAX_CAP or self.bit.band(cap, cap - 1) ~= 0
        or buckets + cap * 8 > LIMIT then return nil, 'Hash map header is invalid' end
    return {bytes = bytes, buckets = buckets, cap = cap, empty = empty, mult = mult}
end

function M:hashmap(address, key)
    if not integer(key, HIGH - 1) then return nil, 'Hash map key is invalid' end
    local map, why = self:_map_header(address)
    if not map then return nil, why end
    -- Empty keys never designate a live entry, including when key == empty.
    if key == map.empty then return nil, 'Hash map key is empty' end
    local product = product32(key, map.mult)
    for probe = 0, math.min(map.cap, MAX_PROBES) - 1 do
        local index = self.bit.band(product + probe, map.cap - 1)
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

function M:_avatar(game, world)
    local player, inventory = self:ptr(game + GLOBAL.player), self:ptr(game + GLOBAL.inventory)
    if not world or not player or not inventory then return nil, 'Avatar managers are unavailable' end
    local unit = self:u32(player + 0x3A8)
    if not unit or unit == 0 or unit == 0xFFFFFFFF then return nil, 'Local avatar unit is unavailable' end
    local ui = self:hashmap(world + 0xF24990, unit)
    if not ui or ui >= MAX_CAP then return nil, 'Local avatar world row is unavailable' end
    local avatar = self:u32(world + 0xF349E0 + ui * 24 + 8)
    if not avatar or avatar == 0 or avatar == 0xFFFFFFFF then return nil, 'Local avatar entity is unavailable' end
    local ii = self:hashmap(inventory + 0x28, avatar)
    local rows = ii and ii < MAX_CAP and self:ptr(inventory + 0x50)
    if not rows or not self:read(rows + ii * 48, 48) then return nil, 'Local avatar inventory row is unavailable' end
    return avatar
end

function M:observe()
    local game, stamp = self:_module()
    if not game then return nil, stamp end
    local view = {game = game, stamp = stamp}
    -- Keep these identities even during loading/actor retirement. Restoration
    -- may still own a global input suppression or projectile flag afterwards.
    view.pm, view.lc = self:ptr(game + GLOBAL.pm), self:ptr(game + GLOBAL.lc)
    view.input, view.projectiles = self:ptr(game + GLOBAL.input), self:ptr(game + GLOBAL.projectiles)
    view.world = self:ptr(game + GLOBAL.world)
    local game_state = self:ptr(game + GLOBAL.game_state)
    view.scene = game_state and self:u32(game_state + 0xAC29C) or nil
    local avatar, why = self:_avatar(game, view.world)
    if not avatar or not view.pm or not view.lc then return view, why or 'Actor managers are unavailable' end
    local pi, di = self:hashmap(view.pm + 0xF8, avatar), self:hashmap(view.lc + 0x68, avatar)
    if not pi or pi >= 128 or not di or di >= 4096 or self:hashmap(view.lc + 0x88, di) ~= avatar then
        return view, 'Local avatar component ownership is unavailable'
    end
    local ep, definitions = self:ptr(view.pm + 0x110 + pi * 8), self:ptr(view.lc + 0xA8)
    local live = ep and self:u8(ep + 0x14)
    if not ep or not definitions or self:u32(ep + 8) ~= avatar or not live or self.bit.band(live, 1) == 0 then
        return view, 'Local avatar descriptor is unavailable or retired'
    end
    local def, pc, state = definitions + di * 0x1214, view.pm + 0x53D8B0 + pi * 0x1240,
        view.pm + 0x547870 + pi * 0x78
    local profile = self:u32(state + 0x20)
    if not self:read(def, PROFILE_BYTES) or not self:read(pc + 0xFE0, 12) or not profile or profile >= 8
        or not self:read(ep, 8) then return view, 'Local avatar profiles or control rows are unreadable' end
    view.avatar, view.di, view.def, view.pc, view.state, view.ep = avatar, di, def, pc, state, ep
    return view
end

function M:validate(view)
    local game, stamp = self:_module()
    if not game then return false, stamp end
    if PORT51.kind(view) ~= 'table' or view.game ~= game or view.stamp ~= stamp then
        return false, 'Observed game module identity changed'
    end
    -- Check cleanup entry points too before the first mutation. Do not leave
    -- partially populated callable state when any one fingerprint differs.
    local functions = {}
    for _, name in ipairs(NAMES) do
        local spec = SPECS[name]
        if self:read(game + spec[1], #spec.bytes) ~= spec.bytes then
            self._validated_game, self._functions = nil, {}
            return false, 'Native fingerprint mismatch: ' .. name
        end
        if not self._io then
            -- Parsing an anonymous function-pointer string creates a new
            -- LuaJIT CType. Reuse the parsed type and target binding across
            -- validations; the exact function bytes are still checked above.
            local ctype=self._native_types[spec[2]]
            if not ctype then ctype=self._ffi.typeof(spec[2]);self._native_types[spec[2]]=ctype end
            local key=spec[2]..':'..tostring(game+spec[1])
            local fn=self._native_functions[key]
            if not fn then fn=self._ffi.cast(ctype,game+spec[1]);self._native_functions[key]=fn end
            functions[name]=fn
        end
    end
    self._validated_game, self._functions = game, functions
    return true
end

function M:unique(view)
    if PORT51.kind(view) ~= 'table' or not view.avatar then return false, 'No observed avatar owns the definition' end
    local current, why = self:observe()
    if not current or not current.avatar then return false, why or 'Local avatar is unavailable' end
    for _, field in ipairs({'game', 'stamp', 'world', 'pm', 'lc', 'avatar', 'di', 'def', 'pc', 'state', 'ep'}) do
        if current[field] ~= view[field] then return false, 'Local avatar ownership changed: ' .. field end
    end
    local map
    map, why = self:_map_header(view.lc + 0x68)
    if not map or map.cap > MAX_PROBES then return false, why or 'Definition ownership map exceeds the scan limit' end
    local owners = 0
    for first = 0, map.cap - 1, MAX_READ / 8 do
        local count = math.min(MAX_READ / 8, map.cap - first)
        local rows = self:read(map.buckets + first * 8, count * 8)
        if not rows then return false, 'Definition ownership map is unreadable' end
        for i = 0, count - 1 do
            local key, value = u32_bytes(rows, i * 8), u32_bytes(rows, i * 8 + 4)
            if key ~= map.empty and value == view.di then
                owners = owners + 1
                if key ~= view.avatar or owners > 1 then return false, 'Locomotion definition has another owner' end
            end
        end
    end
    if owners ~= 1 or self:read(view.lc + 0x68, 20) ~= map.bytes
        or self:hashmap(view.lc + 0x88, view.di) ~= view.avatar then
        return false, 'Locomotion definition ownership is not unique'
    end
    return true
end

function M:base_profiles(view, bytes)
    bytes = bytes or PROFILE_BYTES
    if not integer(bytes, PROFILE_BYTES) or bytes == 0 then return nil, 'Only the bounded 0x1160 profile region is supported' end
    local owned, why = self:unique(view)
    if not owned then return nil, why end
    local descriptor = self:read(view.ep, 8)
    local table_address = view.world and self:ptr(view.world + 0xF148F8)
    local slots = table_address and self:read(table_address, 412 * 16)
    if not descriptor or not slots then return nil, 'Base locomotion resource table is unavailable' end
    for i = 0, 411 do
        if slots:sub(i * 16 + 1, i * 16 + 8) == descriptor then
            local index = u32_bytes(slots, i * 16 + 8)
            if not index or index >= 412 then return nil, 'Base locomotion definition index is invalid' end
            local result = self:read(table_address + 0x19C0 + index * 0x1214, bytes)
            if not result then return nil, 'Base locomotion profile block is unreadable' end
            if self:read(view.ep, 8) ~= descriptor or self:ptr(view.world + 0xF148F8) ~= table_address then
                return nil, 'Base locomotion resource identity changed'
            end
            return result
        end
    end
    return nil, 'Local avatar type has no base locomotion definition'
end

function M:call(name, ...)
    local spec = SPECS[name]
    assert(spec, 'Unsupported Bridge Combat native call: ' .. tostring(name))
    local game, why = self:_module()
    assert(game, why)
    assert(self._validated_game == game, 'Native functions have not been validated')
    assert(self:read(game + spec[1], #spec.bytes) == spec.bytes, 'Native fingerprint changed: ' .. name)
    local arguments = {...}
    local count = select('#', ...)
    -- All six ABIs use a void* first argument; add/remove additionally accept
    -- a const void* mask. Convert only pointer arguments, never u64 key values.
    local pointer_indexes = (name == 'add' or name == 'remove') and {1, 2} or {1}
    for _, index in ipairs(pointer_indexes) do
        local value = arguments[index]
        if PORT51.kind(value) == 'number' or PORT51.kind(value) == 'cdata' then
            local checked, detail = self:_address(value, 1)
            assert(checked, detail)
            -- Keep mask arrays themselves alive through the native invocation.
            if PORT51.kind(value) == 'number' and not self._io then arguments[index] = self._ffi.cast('void *', checked) end
        else
            error('Native pointer argument is unavailable', 2)
        end
    end
    local result
    if self._io then
        assert(PORT51.kind(self._io.call) == 'function', 'Injected native caller is unavailable')
        result = self._io.call(name, unpack(arguments, 1, count))
    else
        result = self._functions[name](unpack(arguments, 1, count))
    end
    if name == 'query' then
        result = PORT51.number(result)
        assert(result == 0 or (result and self:_address(result, 24)), 'Native suppression row is invalid')
        return result
    end
    return true
end

return M
