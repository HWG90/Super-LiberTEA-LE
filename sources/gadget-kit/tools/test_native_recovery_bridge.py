"""Bridge real synthetic native fault events into real Lua51/CFFI policies.

The native fixture and Lua VM are separate processes. These checks bind their
numeric health contract; they are not an in-game fault-injection test.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,sys

ROOT=Path(__file__).resolve().parents[1]
WORK=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison')
sys.path.insert(0,str(WORK/'python-deps'))
from lupa import lua51
ctypes.CDLL(lua51.__file__,mode=ctypes.RTLD_GLOBAL)

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--policy',choices=['camera','fov','blur'],required=True)
parser.add_argument('--log',type=Path,required=True)
args=parser.parse_args()
log_text=args.log.read_text()
marker={'camera':'Native camera fixture PASS:','fov':'Native FOV fixture PASS:','blur':'Native blur fixture PASS:'}[args.policy]
assert marker in log_text and not any(line.startswith('FAIL ')for line in log_text.splitlines()),'Native fixture producer or completion does not match policy'
events=[]
for line in log_text.splitlines():
 if line.startswith('RECOVERY_EVENT '):events.append(json.loads(line[len('RECOVERY_EVENT '):]))
event=next(e for e in events if e['stage']=='callback_read_failed')
assert event['native_error']==3 and event['armed']==0 and event['installed']==1 and event['reserved']==1
assert event['token']>0 and event['rpm_failures']>0
lua=lua51.LuaRuntime(encoding=None,unpack_returned_tuples=True)
lua.globals().native_module=str(WORK/'build-linux/cffi.so').encode()
lua.execute(b"package.loaded.cffi=assert(package.loadlib(native_module,'luaopen_cffi'))()")
compat=lua.execute((ROOT/'src/first_person/compat51.lua').read_bytes())
compat[b'ffi'][b'os']=b'Windows';lua.globals().TEST_PORT51=compat
lua.globals().NATIVE_ADS_TEST_ROOT=str(ROOT).encode()
lua.globals().NATIVE_RECOVERY_NAME=args.policy.encode()
lua.globals().NATIVE_RECOVERY_EVENT=lua.table_from({k.encode():(v.encode()if isinstance(v,str)else v)for k,v in event.items()})
lua.execute(b"mod={dir=NATIVE_ADS_TEST_ROOT,scope={}};local cache={['src/first_person/compat51.lua']=TEST_PORT51};function mod.require(path)if cache[path]~=nil then return cache[path]end;local value=assert(loadfile(mod.dir..'/'..path))();cache[path]=value;return value end")
cases=lua.execute((ROOT/'tests/native_recovery_bridge.lua').read_bytes())
report={'policy':args.policy,'runtime':'Lua5.1 actual CFFI','native_fixture_log':str(args.log.resolve()),
 'native_fixture_log_sha256':hashlib.sha256(args.log.read_bytes()).hexdigest(),'captured_native_event':event,
 'lua_source_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in [
  f'src/first_person/{args.policy}.lua','src/first_person/recovery.lua','src/first_person/compat51.lua','tests/native_recovery_bridge.lua']},
 'cases':cases,'passed':True,'scope':'Separate-process captured health contract through actual Lua CFFI Adapter/Manager/Recovery; no game calls or live fault injection'}
out=ROOT/'dist'/f'{args.policy}-native-recovery-bridge.json';out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'policy':args.policy,'cases':cases,'passed':True,'receipt':str(out)},indent=2))
