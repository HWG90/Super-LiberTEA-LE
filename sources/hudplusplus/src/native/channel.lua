local Bytes = require("native.bytes")
local NativeFiles, NativeClock, NativeSave
local NativeChannel = (function()
    local Module = {}
    local FLOOR = 0x10000
    local CEILING = 0x800000000000
    local CDEF = table.concat({
        "void *GetModuleHandleA(const char *name);",
        "uint32_t GetModuleFileNameW(void *module, uint16_t *path," .. " uint32_t capacity);",
        'void *hd2hud_process(void) __asm__("GetCurrentProcess");',
        "int hd2hud_working_set(void *process, void *info, uint32_t size)" .. ' __asm__("K32QueryWorkingSetEx");',
        "int hd2hud_protect(uintptr_t address, size_t size, uint32_t protect, void *previous)"
            .. ' __asm__("VirtualProtect");',
        "typedef struct hd2hud_region { uint64_t base, allocation_base; uint32_t allocation_protect, partition;"
            .. " uint64_t size; uint32_t state, protect, type, padding; } hd2hud_region;",
        'size_t hd2hud_query(uintptr_t address, hd2hud_region *region, size_t size) __asm__("VirtualQuery");',
        "void *CreateFileW(const uint16_t *path, uint32_t access, uint32_t share,"
            .. " void *security, uint32_t disposition, uint32_t flags,"
            .. " void *template_file);",
        "int ReadFile(void *file, void *buffer, uint32_t size, uint32_t *read," .. " void *overlapped);",
        "int CloseHandle(void *handle);",
        "int32_t BCryptOpenAlgorithmProvider(void **algorithm,"
            .. " const uint16_t *name, const uint16_t *provider, uint32_t flags);",
        "int32_t BCryptCloseAlgorithmProvider(void *algorithm, uint32_t flags);",
        "int32_t BCryptCreateHash(void *algorithm, void **hash, void *object,"
            .. " uint32_t object_size, const void *secret, uint32_t secret_size,"
            .. " uint32_t flags);",
        "int32_t BCryptHashData(void *hash, const void *data, uint32_t size," .. " uint32_t flags);",
        "int32_t BCryptFinishHash(void *hash, void *digest, uint32_t size," .. " uint32_t flags);",
        "int32_t BCryptDestroyHash(void *hash);",
    }, "\n")
    local Channel = {}
    Channel.__index = Channel
    local function native_kernel(declarations)
        local loader = require
        if loader == nil then
            return nil, "no-require"
        end
        local ok, ffi = pcall(loader, "ffi")
        if not ok or ffi == nil then
            return nil, "ffi-unavailable"
        end
        if not ffi.abi("64bit") then
            return nil, "not-64bit"
        end
        for line in string.gmatch(declarations, "[^\n]+") do
            pcall(ffi.cdef, line)
        end
        local loaded_kernel, kernel = pcall(ffi.load, "kernel32")
        if not loaded_kernel then
            return nil, "kernel32"
        end
        return ffi, kernel
    end
    NativeFiles = function()
        local ffi, kernel = native_kernel(table.concat({
            "uint32_t GetModuleFileNameA(void *module, char *filename, uint32_t size);",
            "void *FindFirstFileA(const char *pattern, void *data);",
            "int FindNextFileA(void *handle, void *data);",
            "int FindClose(void *handle);",
            "uint32_t GetLastError(void);",
        }, "\n"))
        if ffi == nil then
            return nil, kernel
        end
        local files = {}
        function files.executable()
            local buffer = ffi.new("char[32768]")
            local length = kernel.GetModuleFileNameA(nil, buffer, 32768)
            if length == 0 or length >= 32768 then
                return nil, "exe-path"
            end
            return ffi.string(buffer, length)
        end
        function files.list(pattern)
            local data = ffi.new("uint8_t[320]")
            local handle = kernel.FindFirstFileA(pattern, data)
            if handle == ffi.cast("void *", -1) then
                if kernel.GetLastError() == 2 then
                    return {}
                end
                return nil, "list-open"
            end
            local ok, names, why = pcall(function()
                local out = {}
                repeat
                    local attributes = tonumber(ffi.cast("uint32_t *", data)[0])
                    if math.floor(attributes / 16) % 2 == 0 then
                        out[#out + 1] = ffi.string(data + 44)
                    end
                until kernel.FindNextFileA(handle, data) == 0
                if kernel.GetLastError() ~= 18 then
                    return nil, "list-next"
                end
                return out
            end)
            local closed = kernel.FindClose(handle)
            if closed == 0 then
                return nil, "list-close"
            end
            if not ok then
                return nil, "list-read"
            end
            return names, why
        end
        function files.open(path)
            local file = io.open(path, "rb")
            if file == nil then
                return nil, "file-open"
            end
            return {
                read = function(_, count)
                    return file:read(count)
                end,
                seek = function(_, whence, offset)
                    return file:seek(whence, offset)
                end,
                close = function()
                    return file:close()
                end,
            }
        end
        return files
    end
    NativeSave = function()
        local ffi, kernel = native_kernel("int MoveFileExA(const char *from, const char *to, uint32_t flags);")
        if ffi == nil then
            return nil, kernel
        end
        return function(path, text)
            local temporary = path .. ".tmp"
            local file = io.open(temporary, "wb")
            if file == nil then
                return nil, "save-open"
            end
            local called, written = pcall(file.write, file, text)
            local closed, result = pcall(file.close, file)
            if not called or not written or not closed or not result then
                return nil, "save-write"
            end
            if kernel.MoveFileExA(temporary, path, 9) == 0 then
                return nil, "save-replace"
            end
            return true
        end
    end
    NativeClock = function()
        local ffi, kernel = native_kernel(table.concat({
            "int QueryPerformanceCounter(int64_t *count);",
            "int QueryPerformanceFrequency(int64_t *frequency);",
        }, "\n"))
        if ffi == nil then
            return nil
        end
        local box = ffi.new("int64_t[1]")
        if kernel.QueryPerformanceFrequency(box) == 0 then
            return nil
        end
        local per = tonumber(box[0]) / 1000000
        if per <= 0 then
            return nil
        end
        return function()
            if kernel.QueryPerformanceCounter(box) == 0 then
                return nil
            end
            return tonumber(box[0]) / per
        end
    end
    local function loads_of(ffi)
        local U8 = ffi.cast("const uint8_t *", 0)
        local U16, U16P = ffi.cast("const uint16_t *", 0), ffi.typeof("const uint16_t *")
        local U32, U32P = ffi.cast("const uint32_t *", 0), ffi.typeof("const uint32_t *")
        local I32, I32P = ffi.cast("const int32_t *", 0), ffi.typeof("const int32_t *")
        local F32, F32P = ffi.cast("const float *", 0), ffi.typeof("const float *")
        local function u32(address)
            if address % 4 == 0 then
                return U32[address / 4]
            end
            return ffi.cast(U32P, address)[0]
        end
        return {
            u8 = function(address)
                return U8[address]
            end,
            bool = function(address)
                return U8[address] ~= 0
            end,
            bit = function(address, bit)
                if type(bit) ~= "number" or bit < 0 or bit % 1 ~= 0 then
                    return nil
                end
                return math.floor(U8[address + math.floor(bit / 8)] / 2 ^ (bit % 8)) % 2
            end,
            u16 = function(address)
                if address % 2 == 0 then
                    return U16[address / 2]
                end
                return ffi.cast(U16P, address)[0]
            end,
            u32 = u32,
            hex64 = function(address)
                return Bytes.hex_words(u32(address + 4), u32(address))
            end,
            key64 = function(address)
                return Bytes.hex_words(u32(address + 4), u32(address)) or false
            end,
            i32 = function(address)
                if address % 4 == 0 then
                    return I32[address / 4]
                end
                return ffi.cast(I32P, address)[0]
            end,
            f32 = function(address)
                if address % 4 == 0 then
                    return F32[address / 4]
                end
                return ffi.cast(F32P, address)[0]
            end,
            ptr = function(address)
                local low, high
                if address % 4 == 0 then
                    local word = address / 4
                    low, high = U32[word], U32[word + 1]
                else
                    local words = ffi.cast(U32P, address)
                    low, high = words[0], words[1]
                end
                local value = high * 4294967296 + low
                if value < FLOOR or value >= CEILING then
                    return nil
                end
                return value
            end,
        }
    end
    local function counted_of(self, loads)
        local counted = {}
        for form, load in pairs(loads) do
            counted[form] = function(address, extra)
                self.reads = self.reads + 1
                return load(address, extra)
            end
        end
        return counted
    end
    function Module.open()
        local ffi, kernel = native_kernel(CDEF)
        if ffi == nil then
            return nil, kernel
        end
        local loaded_bcrypt, bcrypt = pcall(ffi.load, "bcrypt")
        if not loaded_bcrypt then
            return nil, "bcrypt:" .. tostring(bcrypt)
        end
        local self =
            setmetatable({ ffi = ffi, kernel = kernel, bcrypt = bcrypt, modules = {}, reads = 0, calls = 0 }, Channel)
        self.loads = loads_of(ffi)
        self.counted = counted_of(self, self.loads)
        local function as_address(handle)
            if handle == nil then
                return nil
            end
            local address = tonumber(ffi.cast("uintptr_t", handle))
            if address == 0 then
                return nil
            end
            return address
        end
        self.modules.exe = as_address(kernel.GetModuleHandleA(nil))
        self.modules.game = as_address(kernel.GetModuleHandleA("game.dll"))
        if self.modules.exe == nil then
            return nil, "exe-handle-null"
        end
        return self, nil
    end
    function Channel:module(which)
        return self.modules[which]
    end
    function Channel:load(address, form, extra)
        if type(form) == "table" then
            local loads = self.loads
            self.reads = self.reads + 1
            local at, forms = form.at, form.form
            for index = 1, form.n do
                extra[index] = loads[forms[index]](address + at[index])
            end
            return extra
        end
        local load = self.counted[form]
        if load == nil then
            return nil
        end
        return load(address, extra)
    end
    function Module.layout(fields)
        local at, forms = {}, {}
        for index, field in ipairs(fields) do
            at[index], forms[index] = field[1], field[2]
        end
        return { n = #fields, at = at, form = forms }
    end
    function Module.strided(count, stride, form)
        local fields = {}
        for index = 1, count do
            fields[index] = { (index - 1) * stride, form }
        end
        return Module.layout(fields)
    end
    -- 26251122 port: a game.dll code page stays no-access until the game first runs it, and a direct read of one
    -- crashes the game (2026-11-03, a hot join: the reinforce walker read 16 bytes at game+0xf74ff1, one byte into a
    -- no-access page). Every page a read touches must be committed and readable; otherwise the answer is nil.
    local MEM_COMMIT = 0x1000
    local function readable(self, address, size)
        local region = self.region
        if region == nil then
            region = self.ffi.new("hd2hud_region[1]")
            self.region, self.region_size = region, self.ffi.sizeof("hd2hud_region")
        end
        local at, stop = address, address + size
        while at < stop do
            if self.kernel.hd2hud_query(at, region, self.region_size) == 0 then
                return false
            end
            local r = region[0]
            local protect = tonumber(r.protect)
            -- no-access 0x01, execute-only 0x10 and guard 0x100 cannot be read
            if
                tonumber(r.state) ~= MEM_COMMIT
                or protect % 256 == 0x01
                or protect % 256 == 0x10
                or math.floor(protect / 256) % 2 == 1
            then
                return false
            end
            local after = tonumber(r.base) + tonumber(r.size)
            if after <= at then
                return false
            end
            at = after
        end
        return true
    end
    function Channel:text(address, size)
        if size <= 0 then
            return nil
        end
        if not readable(self, address, size) then
            return nil
        end
        return self.ffi.string(self.ffi.cast("const uint8_t *", address), size)
    end
    local SLOT_SIZE, PAGE = 16, 4096
    local PAGE_READWRITE = 4
    local OPEN = { [0x04] = true, [0x08] = true, [0x40] = true, [0x80] = true }
    local function open_now(self, address)
        local slot = self.slot
        if slot == nil then
            slot = self.ffi.new("uint64_t[2]")
            self.slot, self.flags, self.process =
                slot, self.ffi.cast("uint32_t *", slot) + 2, self.kernel.hd2hud_process()
        end
        slot[0], slot[1] = address, 0
        if self.kernel.hd2hud_working_set(self.process, slot, SLOT_SIZE) == 0 then
            return false
        end
        local flags = self.flags[0]
        return flags % 2 == 1 and OPEN[math.floor(flags / 16) % 2048] == true
    end
    local FUNCTION_TYPES = {}
    function Channel:entry(address, ctype)
        if type(ctype) ~= "string" or string.find(ctype, "(*)", 1, true) == nil then
            return nil, "ctype"
        end
        local kind = FUNCTION_TYPES[ctype]
        if kind == nil then
            local made
            made, kind = pcall(self.ffi.typeof, ctype)
            if not made then
                return nil, "ctype"
            end
            FUNCTION_TYPES[ctype] = kind
        end
        local cast, fn = pcall(self.ffi.cast, kind, address)
        if not cast then
            return nil, "ctype"
        end
        return fn
    end
    function Channel:call(fn, ...)
        self.calls = self.calls + 1
        return fn(...)
    end
    local OWNED = {}
    function Channel:own(text)
        if type(text) ~= "string" or #text == 0 then
            return nil
        end
        local ffi = self.ffi
        local block = ffi.new("uint8_t[?]", #text + 15)
        local base = tonumber(ffi.cast("uintptr_t", block))
        local at = base + (16 - base % 16) % 16
        ffi.copy(ffi.cast("uint8_t *", at), text, #text)
        OWNED[#OWNED + 1] = block
        return at
    end
    function Channel:bits(value)
        if type(value) ~= "number" or not (value > -math.huge and value < math.huge) then
            return nil
        end
        local ffi = self.ffi
        local box = self.float_box
        if box == nil then
            box = ffi.new("float[1]")
            self.float_box = box
        end
        box[0] = value
        if not (box[0] > -math.huge and box[0] < math.huge) then
            return nil
        end
        return tonumber(ffi.cast("uint32_t *", box)[0])
    end
    function Channel:put(address, text)
        local size = #text
        local ffi, kernel = self.ffi, self.kernel
        local previous, at, was = self.previous, self.unlocked_at, self.unlocked_was
        if previous == nil then
            previous, at, was = ffi.new("uint32_t[2]"), {}, {}
            self.previous, self.unlocked_at, self.unlocked_was = previous, at, was
        end
        local count = 0
        for page = math.floor(address / PAGE), math.floor((address + size - 1) / PAGE) do
            local from = math.max(address, page * PAGE)
            if not open_now(self, from) then
                if
                    kernel.hd2hud_protect(
                        from,
                        math.min(address + size, (page + 1) * PAGE) - from,
                        PAGE_READWRITE,
                        previous
                    ) == 0
                then
                    for index = count, 1, -1 do
                        kernel.hd2hud_protect(at[index], 1, was[index], previous + 1)
                    end
                    return false
                end
                count = count + 1
                at[count], was[count] = from, previous[0]
            end
        end
        ffi.copy(ffi.cast("uint8_t *", address), text, size)
        for index = 1, count do
            kernel.hd2hud_protect(at[index], 1, was[index], previous + 1)
        end
        return true
    end
    function Channel:fingerprint(which)
        local handle = self:module(which)
        if handle == nil then
            return nil, "no-module"
        end
        local ffi, kernel, bcrypt = self.ffi, self.kernel, self.bcrypt
        local path = ffi.new("uint16_t[32768]")
        local length = kernel.GetModuleFileNameW(ffi.cast("void *", handle), path, 32768)
        if length == 0 or length >= 32768 then
            return nil, "path"
        end
        local file = kernel.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
        if file == ffi.cast("void *", -1) then
            return nil, "open"
        end
        local algorithm, hash = ffi.new("void *[1]"), ffi.new("void *[1]")
        local buffer, count = ffi.new("uint8_t[1048576]"), ffi.new("uint32_t[1]")
        local name = ffi.new("uint16_t[7]", { 83, 72, 65, 50, 53, 54, 0 })
        local total, fault, hex = 0, nil, nil
        if bcrypt.BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) ~= 0 then
            fault = "provider"
        end
        if fault == nil and bcrypt.BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) ~= 0 then
            fault = "create"
        end
        while fault == nil do
            if kernel.ReadFile(file, buffer, 1048576, count, nil) == 0 then
                fault = "read"
                break
            end
            if count[0] == 0 then
                break
            end
            total = total + tonumber(count[0])
            if bcrypt.BCryptHashData(hash[0], buffer, count[0], 0) ~= 0 then
                fault = "update"
                break
            end
        end
        if fault == nil then
            local digest = ffi.new("uint8_t[32]")
            if bcrypt.BCryptFinishHash(hash[0], digest, 32, 0) ~= 0 then
                fault = "finish"
            else
                local parts = {}
                for index = 0, 31 do
                    parts[#parts + 1] = string.format("%02x", digest[index])
                end
                hex = table.concat(parts)
            end
        end
        if hash[0] ~= nil then
            bcrypt.BCryptDestroyHash(hash[0])
        end
        if algorithm[0] ~= nil then
            bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0)
        end
        kernel.CloseHandle(file)
        if hex == nil then
            return nil, fault or "unknown"
        end
        return hex, total
    end
    function Channel:pinned(expected)
        local report, okay = {}, true
        for _, which in ipairs({ "exe", "game" }) do
            local hex, detail = self:fingerprint(which)
            report[which] = {
                sha = hex,
                want = expected and expected[which],
                bytes = hex ~= nil and detail or nil,
                fault = hex == nil and detail or nil,
            }
            if hex == nil or (expected and expected[which] and expected[which] ~= hex) then
                okay = false
            end
        end
        return okay, report
    end
    return Module
end)()
return { channel = NativeChannel, files = NativeFiles, clock = NativeClock, save = NativeSave }
