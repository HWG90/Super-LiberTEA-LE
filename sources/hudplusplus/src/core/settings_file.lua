local File = {}
local Native = require("native.channel")
function File.bind(settings, path)
    local replace = assert(Native.save())
    local function read()
        local file = io.open(path, "rb")
        if file == nil then
            return nil, "unavailable"
        end
        local okay, text = pcall(file.read, file, "*a")
        file:close()
        if not okay or text == nil then
            return nil, "read"
        end
        return text
    end
    local function save(text)
        return replace(path, text)
    end
    settings:bind(read, save, os.time)
    local _, why = settings:poll()
    assert(why == nil or why == "unavailable", why)
end
return File
