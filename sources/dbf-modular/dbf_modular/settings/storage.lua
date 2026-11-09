-- Filesystem-only persistence, independent of native HUD readiness. No game APIs.
-- Windows uses wide paths and a flushed same-directory atomic replacement;
-- POSIX uses a same-directory rename. An injected backend exercises failure order.
local Storage = {}
local LIMIT, serial = 1048576, 0
local function posix()
    local backend = { nonce = tostring({}):gsub("[^%w]", "") }
    function backend.read(path)
        local file, why, code = io.open(path, "rb")
        if not file then
            return nil, code ~= 2 and why or nil
        end
        local text, problem = file:read(LIMIT + 1)
        local closed, close_why = file:close()
        if text == nil and problem ~= nil then
            return nil, problem
        end
        text = text or ""
        if not closed then
            return nil, close_why
        end
        if #text > LIMIT then
            return nil, "Settings source exceeds size limit"
        end
        return text
    end
    function backend.create(path)
        return io.open(path, "wb")
    end
    function backend.write(file, text)
        local value, why = file:write(text)
        return value ~= nil, why
    end
    function backend.flush(file)
        return file:flush()
    end
    function backend.close(file)
        return file:close()
    end
    function backend.replace(from, to)
        return os.rename(from, to)
    end
    function backend.remove(path)
        return os.remove(path)
    end
    return backend
end
local function windows()
    local ffi = require("ffi")
    -- Private aliases avoid collisions with other mods' Win32 declarations.
    ffi.cdef([[
        int __stdcall dbfm_cfg_wide(unsigned int, unsigned int, const char *, int, uint16_t *, int) __asm__("MultiByteToWideChar");
        void *__stdcall dbfm_cfg_open(const uint16_t *, uint32_t, uint32_t, void *, uint32_t, uint32_t, void *) __asm__("CreateFileW");
        int __stdcall dbfm_cfg_size(void *, int64_t *) __asm__("GetFileSizeEx");
        int __stdcall dbfm_cfg_read(void *, void *, uint32_t, uint32_t *, void *) __asm__("ReadFile");
        int __stdcall dbfm_cfg_write(void *, const void *, uint32_t, uint32_t *, void *) __asm__("WriteFile");
        int __stdcall dbfm_cfg_flush(void *) __asm__("FlushFileBuffers");
        int __stdcall dbfm_cfg_close(void *) __asm__("CloseHandle");
        int __stdcall dbfm_cfg_replace(const uint16_t *, const uint16_t *, uint32_t) __asm__("MoveFileExW");
        int __stdcall dbfm_cfg_delete(const uint16_t *) __asm__("DeleteFileW");
        uint32_t __stdcall dbfm_cfg_error(void) __asm__("GetLastError");
        uint32_t __stdcall dbfm_cfg_pid(void) __asm__("GetCurrentProcessId");
    ]])
    local kernel = ffi.load("kernel32")
    local function path(value)
        local count = kernel.dbfm_cfg_wide(65001, 8, value, #value, nil, 0)
        if count == 0 then
            return nil, "Invalid UTF-8 settings path"
        end
        local wide = ffi.new("uint16_t[?]", count + 1)
        if kernel.dbfm_cfg_wide(65001, 8, value, #value, wide, count) ~= count then
            return nil, "Settings path conversion refused"
        end
        return wide
    end
    local function open(value, access, share, creation)
        local wide, why = path(value)
        if not wide then
            return nil, why
        end
        local file = kernel.dbfm_cfg_open(wide, access, share, nil, creation, 0x80, nil)
        if file == nil or ffi.cast("intptr_t", file) == -1 then
            local code = tonumber(kernel.dbfm_cfg_error())
            return nil, (code ~= 2 and code ~= 3) and ("Settings open refused: " .. code) or nil
        end
        return file
    end
    local backend = { nonce = tostring(tonumber(kernel.dbfm_cfg_pid())) }
    function backend.read(value)
        local file, why = open(value, 0x80000000, 7, 3)
        if not file then
            return nil, why
        end
        local size, count = ffi.new("int64_t[1]"), ffi.new("uint32_t[1]")
        if kernel.dbfm_cfg_size(file, size) == 0 or size[0] < 0 or size[0] > LIMIT then
            kernel.dbfm_cfg_close(file)
            return nil, "Invalid settings source size"
        end
        local length = tonumber(size[0])
        local bytes = ffi.new("char[?]", math.max(1, length))
        local okay = kernel.dbfm_cfg_read(file, bytes, length, count, nil) ~= 0 and tonumber(count[0]) == length
        local closed = kernel.dbfm_cfg_close(file) ~= 0
        if not okay or not closed then
            return nil, "Settings read refused"
        end
        return ffi.string(bytes, length)
    end
    function backend.create(value)
        return open(value, 0x40000000, 0, 1)
    end
    function backend.write(file, text)
        local count = ffi.new("uint32_t[1]")
        local okay = kernel.dbfm_cfg_write(file, text, #text, count, nil) ~= 0 and tonumber(count[0]) == #text
        return okay, not okay and "Settings write incomplete" or nil
    end
    function backend.flush(file)
        return kernel.dbfm_cfg_flush(file) ~= 0, "Settings flush refused"
    end
    function backend.close(file)
        return kernel.dbfm_cfg_close(file) ~= 0, "Settings close refused"
    end
    function backend.replace(from, to)
        local a, why = path(from)
        if not a then
            return false, why
        end
        local b, problem = path(to)
        if not b then
            return false, problem
        end
        return kernel.dbfm_cfg_replace(a, b, 9) ~= 0, "Atomic settings replacement refused"
    end
    function backend.remove(value)
        local wide = path(value)
        return wide ~= nil and kernel.dbfm_cfg_delete(wide) ~= 0
    end
    return backend
end
local backend
local function native()
    if not backend then
        backend = package.config:sub(1, 1) == "\\" and windows() or posix()
    end
    return backend
end
function Storage.atomic(path, text, target)
    if type(path) ~= "string" or #path == 0 or path:find("\0", 1, true) then
        return false, "Settings path unavailable"
    end
    if type(text) ~= "string" or #text > LIMIT then
        return false, "Invalid settings payload"
    end
    target = target or native()
    serial = serial + 1
    local temporary = path .. ".tmp-" .. tostring(target.nonce or "dbfm") .. "-" .. serial
    local called, file, why = pcall(target.create, temporary)
    if not called or not file then
        return false, tostring(called and (why or "Settings temporary open refused") or file)
    end
    local okay, problem = true, nil
    for _, name in ipairs({ "write", "flush", "close" }) do
        if okay or name == "close" then
            local accepted, value, reason = pcall(target[name], file, name == "write" and text or nil)
            if not accepted or value ~= true then
                if okay then
                    problem = tostring(accepted and (reason or ("Settings " .. name .. " refused")) or value)
                end
                okay = false
            end
        end
    end
    if okay then
        local accepted, value, reason = pcall(target.replace, temporary, path)
        okay = accepted and value == true
        if not okay then
            problem = tostring(accepted and (reason or "Atomic settings replacement refused") or value)
        end
    end
    if not okay then
        pcall(target.remove, temporary)
    end
    return okay, problem
end
function Storage.default(globals, context)
    local environment = globals.os or os
    local appdata, localdata = environment.getenv("APPDATA"), environment.getenv("LOCALAPPDATA")
    local loader = rawget(globals, "CowboyBingusModLoader") or rawget(globals, "LiveLuaLoader")
    local logs = loader and loader.log_directory or localdata and localdata .. "/LLL/Helldivers2/Logs"
    local path = appdata and appdata .. "/dbf_modular.cfg"
    -- LLL overlays the original project's persisted JSON on its own defaults.
    context = context or {}
    local function parent(value)
        return type(value) == "string" and value:match("^(.*)[/\\][^/\\]+$") or nil
    end
    local settings = parent(context.config_dir) or localdata and localdata .. "/LLL/Helldivers2/Settings"
    local mods = parent(context.dir) or localdata and localdata .. "/LLL/Helldivers2/Mods"
    local function read(value)
        if not value then
            return nil
        end
        return native().read(value)
    end
    return {
        path = path,
        read = function()
            return read(path)
        end,
        read_legacy = function(name)
            if not logs then
                return nil
            end
            if name == "menu" then
                return read(logs .. "/ModOptionsMenu.values")
            end
            if name == "blacklist" then
                return read(logs .. "/DiversBestFriendBlacklist.log")
            end
            error("Unknown original DBF source: " .. tostring(name))
        end,
        read_preferences = function()
            local defaults, defaults_why = read(mods and mods .. "/divers_best_friend/config/defaults.cfg")
            assert(
                defaults ~= nil or defaults_why == nil,
                "Original DBF defaults unreadable: " .. tostring(defaults_why)
            )
            local user, user_why = read(settings and settings .. "/divers_best_friend/config.cfg")
            assert(user ~= nil or user_why == nil, "Original DBF saved preferences unreadable: " .. tostring(user_why))
            return defaults, user
        end,
        write_atomic = function(text)
            return Storage.atomic(path, text)
        end,
    }
end
return Storage
