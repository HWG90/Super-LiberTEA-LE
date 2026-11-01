-- LLL's unchanged src/steam/platform.lua over src/steam/transport_inproc.lua and the runtime's hd2.lll_host, driven
-- through the calls tests/test_steam_service.py drives against the external service, plus the input, screenshot and
-- font paths the in-process service changes.
local ffi=require('ffi')
ffi.cdef[[unsigned long GetCurrentProcessId(void); void Sleep(unsigned long);]]
local function load(path) return assert(loadfile(LLL_CHECKOUT..'/'..path)) end
local checks=0
local function check(condition,label) assert(condition,label);checks=checks+1 end
LLL_STEAM_SERVICE={pipe='lll_steam_hosttest_0123456789abcdef',launcher=nil,release='R38-26251122-luajit.1'}
LLL_STEAM_BUILDS={exe_sha256='fixture',game_sha256='fixture'}
LLL_STEAM_TRANSPORT=load('src/steam/transport_inproc.lua')()
local clock=0
stingray={Application={process_id=function()return tonumber(ffi.C.GetCurrentProcessId())end,time_since_launch=function()return clock end}}
local P=load('src/steam/platform.lua')()
check(P.guard().supported and P.exe:match('\\bin\\helldivers2%.exe$') and P.data==P.root..'/data','handshake: stock hashes, paths')
check(P.revision=='R38-26251122-luajit.1','release label')
check(P.hash('core/wwise/lua/wwise_flow_callbacks')=='7251fdd9bb62480a','resource hash')
local dir=P.local_app_data..'/LLL/Helldivers2/HostTest-'..os.time()
check(P.mkdir(dir) and P.mkdir(dir),'mkdir, twice')
check(P.changed(dir),'first watch reports a change')
check(P.write(dir..'/normal.lua','return 1') and P.read(dir..'/normal.lua')=='return 1','atomic write and read back')
check(type(P.stat(dir..'/normal.lua'))=='string' and P.stat(dir..'/missing.lua')==nil and P.stat(dir)==nil,'stat: file, missing, directory')
local files,stamps,directories,status=P.files(dir,'*.lua')
check(status==0 and #files==1 and files[1]=='normal.lua' and stamps['normal.lua']==P.stat(dir..'/normal.lua') and #directories==0,'listing')
check(P.mkdir(dir..'/sub') and #P.directories(dir)==1,'directories')
ffi.C.Sleep(600);clock=clock+1
check(P.changed(dir),'a write is seen as a change')
ffi.C.Sleep(100);clock=clock+1
check(not P.changed(dir),'no change without a write')
check(P.unwatch(dir),'unwatch')
local pointer=P.pointer_snapshot()
check(pointer.valid==false,'menu pointer: not the foreground process')
local camera=P.camera_snapshot()
check(camera.valid==false and camera.dx==0 and camera.dy==0,'camera pointer')
check(P.release_pointer(),'pointer release')
local handle=P.keyboard_prepare()
local accepted,why=P.keyboard_acquire(handle)
check(not accepted and tostring(why):find('0x00000005',1,true),'keyboard: refused for a process that is not the game ('..tostring(why)..')')
local record,reason=P.screenshot_request(P.screenshot_directory..'/War Journalist-host-test.png')
check(record==nil and reason=='Screenshot request refused (0x00000032)','screenshot refused: no WGC under Wine')
local native=LLL_STEAM_TRANSPORT.nativeinfo()
local kernel=native.module_base('kernel32.dll')
check(kernel and native.read_memory(kernel,2)=='MZ','font reader: module_base and read_memory')
check(native.module_base('no-such.dll')==nil and native.read_memory(0x1000,4)==nil and native.read_memory(kernel,0)==nil,'font reader refuses')
P.close_watches()
local failed
P.on_transport_failure(function(message)failed=message end)
local ok=pcall(LLL_STEAM_TRANSPORT(LLL_STEAM_SERVICE).exchange,string.rep('\0',11))
check(not ok and not P.transport_failure(),'a caller mistake is refused before the service and does not latch')
print(('platform.lua over hd2.lll_host: %d checks passed'):format(checks))
