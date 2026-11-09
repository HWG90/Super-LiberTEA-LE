local root=assert(NATIVE_ADS_TEST_ROOT)
local real_require,real_debug=require,debug
local running_jit=type(rawget(_G,'jit'))=='table' and type(jit.version)=='string' and jit.version:match('^LuaJIT ')
local passed=0
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function rejected(body,part)
 local ok,why=pcall(body);assert(not ok and tostring(why):find(part,1,true),tostring(why))
end
local function adapter(options)
 options=options or {}
 local env=setmetatable({jit=options.jit or false,package={loaded=options.loaded or {},
  loadlib=function()error('No native helper may be loaded by this fixture')end},debug=real_debug}, {__index=_G})
 env._G=env
 env.require=function(name)
  if name=='jit.util' and options.utility then return options.utility end
  return real_require(name)
 end
 local chunk=assert(loadfile(root..'/src/compat51.lua'));setfenv(chunk,env)
 return chunk()
end
local function word(value,n)
 local bytes={}
 for _=1,n do bytes[#bytes+1]=string.char(value%256);value=math.floor(value/256)end
 return table.concat(bytes)
end
if not running_jit then test('stock CClosure fallback keeps protected header and executable checks',function()
 local a=adapter();local calls=0;local entry=0x12340000
 local header=string.rep('\0',8)..'\6\0\1'..string.rep('\0',21)..word(entry,8)
 local info=a.inspect_function(io.open,function(_,size)calls=calls+1;assert(size==40);return header end,
  function(address)return address==entry end)
 assert(info.addr==entry and calls==1)
 rejected(function()a.inspect_function(io.open,function()return string.rep('\0',40)end,function()error('unreachable')end)end,
  'CClosure header differs')
 rejected(function()a.inspect_function(io.open,function()return header end,function()return false end)end,
  'target is not executable')
end)end
test('stock nativeinfo target is validated and a failed bridge never falls back to raw layout',function()
 local reads=0
 local a=adapter({loaded={hd2_nativeinfo={function_address=function(fn)assert(fn==io.open);return 0x12340000 end}}})
 assert(a.jit_util.funcinfo(io.open).addr==0x12340000)
 for _,value in ipairs({0,65535,2^47,0/0,math.huge,65536.5,'12340000'})do
  local bad=adapter({loaded={hd2_nativeinfo={function_address=function()return value end}}})
  rejected(function()bad.jit_util.funcinfo(io.open)end,'Native binding address is unavailable')
 end
 local bad=adapter({loaded={hd2_nativeinfo={function_address=function()reads=reads+1;error('wrong host ABI')end}}})
 rejected(function()bad.jit_util.funcinfo(io.open)end,'wrong host ABI');assert(reads==1)
 bad=adapter({loaded={hd2_nativeinfo={}}})
 rejected(function()bad.jit_util.funcinfo(io.open)end,'Native binding helper API differs')
end)
test('Lua closures cannot enter any native binding address route',function()
 local called=false
 local a=adapter({loaded={hd2_nativeinfo={function_address=function()called=true;return 0x12340000 end}}})
 rejected(function()a.jit_util.funcinfo(function()end)end,'Native C function required')
 assert(not called)
end)
test('LuaJIT requires native runtime and introspection functions without stock fallback',function()
 local called=false
 local bridge={function_address=function()called=true;return 0x12340000 end}
 local a=adapter({jit={version='LuaJIT 2.1',status=function()return true end},loaded={hd2_nativeinfo=bridge}})
 rejected(function()a.jit_util.funcinfo(io.open)end,'Native LuaJIT runtime API differs')
 a=adapter({jit={version='LuaJIT 2.1',status=print},utility={funcinfo=function()return {addr=0x12340000}end},
  loaded={hd2_nativeinfo=bridge}})
 rejected(function()a.jit_util.funcinfo(io.open)end,'Native LuaJIT introspection API differs')
 assert(not called)
end)
-- Run the same file with the installed luajit binary to exercise its actual
-- GCfunc/native introspection, in addition to the migrated stock-CFFI suites.
if running_jit then
 test('real LuaJIT C binding uses its native function address without loading stock nativeinfo',function()
  local called=false
  local a=adapter({jit=jit,loaded={hd2_nativeinfo={function_address=function()called=true;error('stock bridge called')end}}})
  local expected=real_require('jit.util').funcinfo(io.open).addr
  assert(a.jit_util.funcinfo(io.open).addr==expected and not called)
  rejected(function()a.jit_util.funcinfo(function()end)end,'Native C function required')
 end)
end
print('Native binding runtime-family contracts: '..passed..' passed')
