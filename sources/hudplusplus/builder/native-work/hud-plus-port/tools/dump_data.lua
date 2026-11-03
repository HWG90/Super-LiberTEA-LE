-- Dump HUD Plus's game.data table as JSON.
-- usage: luajit dump_data.lua <bundle.lua> <out.json>
local f = assert(io.open(arg[1], "rb"))
local source = f:read("*a")
f:close()
local at = source:find("return import('entry')", #source - 200, true)
local import = assert(loadstring(source:sub(1, at - 1) .. "return import", "@bundle"))()
local data = import("game.data")

local function encode(v, out)
    local t = type(v)
    if t == "table" then
        local n = #v
        local is_list = n > 0
        if is_list then
            for k in pairs(v) do
                if type(k) ~= "number" then is_list = false break end
            end
        end
        if is_list then
            out[#out + 1] = "["
            for i = 1, n do
                if i > 1 then out[#out + 1] = "," end
                encode(v[i], out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = string.format("%q", k):gsub("\\\n", "\\n") .. ":"
                local value = v[k]
                if value == nil then value = v[tonumber(k)] end
                encode(value, out)
            end
            out[#out + 1] = "}"
        end
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
        elseif v == math.floor(v) and math.abs(v) < 2^53 then out[#out + 1] = string.format("%d", v)
        else out[#out + 1] = string.format("%.17g", v) end
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    else out[#out + 1] = "null" end
end

local out = {}
encode(data, out)
local o = assert(io.open(arg[2], "wb"))
o:write(table.concat(out))
o:close()
