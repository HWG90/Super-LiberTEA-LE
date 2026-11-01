do -- LuaJIT runtime handoff. LLL's original boot follows this block unchanged.
 if rawget(_G,'jit')==nil then
  local native=(os.getenv('LOCALAPPDATA') or '')..'/LLL/Helldivers2/Native/'
  local marker=io.open(native..'luajit-boot.enable','rb')
  if marker then
   -- The marker's first line names the runtime: hd2_luajit_runtime_<sha256 prefix>.dll
   local runtime=marker:read('*l');marker:close()
   runtime=runtime and runtime:match('^(hd2_luajit_runtime_%x+%.dll)%s*$')
   local ok,handed,why=pcall(function()
    if not runtime then return false,'marker does not name hd2_luajit_runtime_<hash>.dll' end
    local open,err=package.loadlib(native..runtime,'luaopen_hd2_luajit_boot')
    if not open then return false,err end
    return open()
   end)
   if ok and handed==true then return end
   print('[LuaJIT runtime] boot handoff not taken, LLL runs in PUC: '..tostring(ok and why or handed))
  end
 end
end
