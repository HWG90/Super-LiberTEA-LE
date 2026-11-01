-- Preserve the native loader for source and string buffers. Bytecode takes the
-- exact-input translation path: foreign PUC bytes, and legacy LuaJIT (FR1) bytes
-- with a verified source; other LuaJIT bytecode reaches the native loader there.
local compile = assert(_HD2_COMPILE)
local native_load, native_loadstring, native_loadfile = load, loadstring, loadfile
local open, concat, sub, kind, protected = io.open, table.concat, string.sub, type, pcall

local function foreign(value)
    return kind(value) == 'string' and (sub(value, 1, 4) == '\27Lua' or sub(value, 1, 3) == '\27LJ')
end

local function collect(reader)
    local chunks = {}
    while true do
        local chunk = reader()
        if chunk == nil or chunk == '' then break end
        if kind(chunk) ~= 'string' and kind(chunk) ~= 'number' then
            error('reader function must return a string')
        end
        chunks[#chunks + 1] = chunk
    end
    return concat(chunks)
end

local function compatible_load(value, name, mode, env)
    if kind(value) == 'function' then
        local ok, result = protected(collect, value)
        if not ok then return nil, result end
        value, name = result, name or '=(load)'
    end
    if foreign(value) then return compile(value, name, mode, env) end
    -- PUC reference lacks LuaJIT's string overload and env argument.
    if not jit and (kind(value) == 'string' or kind(value) == 'number') then
        return compile(value, name, mode, env)
    end
    return native_load(value, name, mode, env)
end

load, loadstring = compatible_load, compatible_load
loadfile = function(filename, mode, env)
    local fn, message = native_loadfile(filename, mode, env)
    if fn or filename == nil then return fn, message end
    local file = open(filename, 'rb')
    if not file then return nil, message end
    local data = file:read('*a')
    file:close()
    if foreign(data) then return compile(data, '@' .. filename, mode, env) end
    return nil, message
end

-- The native Lua file searcher bypasses global loadfile. Supply equivalent
-- search behavior so a cached PUC module also works through normal require.
local separator = sub(package.config or '/', 1, 1)
package.loaders[2] = function(name)
    local module_path = name:gsub('%.', separator)
    local failures = {}
    for template in package.path:gmatch('[^;]+') do
        local filename = template:gsub('%?', function() return module_path end)
        local file = open(filename, 'rb')
        if file then
            file:close()
            local fn, message = loadfile(filename)
            if not fn then error("error loading module '" .. name .. "' from file '" .. filename .. "':\n\t" .. message) end
            return fn
        end
        failures[#failures + 1] = "\n\tno file '" .. filename .. "'"
    end
    return concat(failures)
end
