-- Declared-source test host; no game process, native memory or settings file access.
local Support = {}
function Support.project(root, globals)
    root = root or "dbf_modular"
    globals = globals or setmetatable({}, { __index = _G })
    local context, cache = { dir = root, config = { preferences = {} } }, {}
    local scope = setmetatable({ _G = globals }, { __index = globals })
    context.scope, scope.mod = scope, context
    function context.read(path)
        assert(type(path) == "string" and not path:find("..", 1, true) and path:sub(1, 1) ~= "/", "Invalid test module")
        local file = assert(io.open(root .. "/" .. path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    function context.require(path, ...)
        if cache[path] ~= nil then
            return cache[path]
        end
        local chunk = assert(loadstring(context.read(path), "@" .. root .. "/" .. path))
        setfenv(chunk, scope)
        local value = chunk(...)
        if value == nil then
            value = true
        end
        cache[path] = value
        return value
    end
    context.log = function() end
    return context, globals
end
return Support
