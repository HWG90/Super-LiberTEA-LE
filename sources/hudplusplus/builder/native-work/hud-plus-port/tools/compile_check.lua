-- usage: luajit compile_check.lua <file.lua> <chunk name>: the file must compile as a Lua chunk.
local f = assert(io.open(arg[1], "rb"))
local source = f:read("*a")
f:close()
assert(loadstring(source, "@" .. arg[2]))
print("compiles: " .. #source .. " bytes")
