"""Build/test the held-fire data-slot filter without editing profiles or installing it."""
from pathlib import Path
import hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent
OUT=HERE/'build'
ZIG=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig')
INPUTS=[HERE/'native_held_fire.cpp',HERE/'native_held_fire.h',HERE/'native_held_fire_cas.cpp',HERE/'native_held_fire_cas.h',HERE/'held_fire_fixture.cpp',HERE/'held_fire_dll_smoke.cpp',HERE/'held_fire_seh_test.cpp',Path(__file__),HERE.parent/'first_person/native_memory.h']
OUT.mkdir(exist_ok=True)
stamp=hashlib.sha256(b''.join(p.read_bytes() for p in INPUTS)).hexdigest()[:12]
dll=OUT/f'native_ads_heldfire_26568081_{stamp}.dll'
fixture=OUT/'held_fire_fixture.exe'
smoke=OUT/'held_fire_dll_smoke.exe'
seh=OUT/'held_fire_seh_test.dll'
env={**os.environ,'ZIG_GLOBAL_CACHE_DIR':str(OUT/'zig-global-cache'),'ZIG_LOCAL_CACHE_DIR':str(OUT/'zig-local-cache')}
def run(args,label,timeout=180):
    p=subprocess.run([str(a)for a in args],env=env,text=True,capture_output=True,timeout=timeout)
    (OUT/(label+'.log')).write_text(p.stdout+p.stderr)
    if p.returncode:raise RuntimeError(label+' failed\n'+p.stdout+p.stderr)
    return p
flags=[ZIG,'c++','-target','x86_64-windows-gnu','-std=c++17','-fms-extensions','-O2','-Wall','-Wextra','-Werror']
obj=OUT/'native_held_fire.obj'
production_flags=['-fno-exceptions','-fno-rtti','-fno-threadsafe-statics']
run(flags+production_flags+['-c',HERE/'native_held_fire.cpp','-o',obj],'compile-dll-object')
cas_obj=OUT/'native_held_fire_cas.obj'
run(flags+['-fexceptions','-fno-rtti','-c',HERE/'native_held_fire_cas.cpp','-o',cas_obj],'compile-cas-seh')
run([ZIG,'c++','-target','x86_64-windows-gnu','-nostdlib','-shared',obj,cas_obj,
    '-Wl,--entry,NADSHF_DllMain','-L/usr/x86_64-w64-mingw32/lib','-lkernel32','-lmsvcrt','-o',dll],'link-dll')
seh_obj=OUT/'held_fire_seh_test.obj'
run(flags+production_flags+['-c',HERE/'held_fire_seh_test.cpp','-o',seh_obj],'compile-seh-test')
run([ZIG,'c++','-target','x86_64-windows-gnu','-nostdlib','-shared',seh_obj,cas_obj,
    '-Wl,--entry,NADSHF_DllMain','-L/usr/x86_64-w64-mingw32/lib','-lkernel32','-lmsvcrt','-o',seh],'link-seh-test')
run(flags+[HERE/'held_fire_fixture.cpp','-o',fixture],'compile-fixture')
run(flags+[HERE/'held_fire_dll_smoke.cpp','-o',smoke],'compile-dll-smoke')
imports=run(['objdump','-p',dll],'production-imports').stdout
assert 'VirtualProtect'not in imports and'MinHook'not in imports and'libstdc++'not in imports,'Unexpected production DLL runtime/protection dependency'
passed=False
smoke_passed=False
if '--build-only' not in sys.argv:
    env['WINEPREFIX']=str(HERE.parents[2]/'fird-fov-wineprefix')
    env['WINEDEBUG']='-all'
    env['WINEDLLOVERRIDES']='winedbg.exe=d'
    p=run(['wine',fixture],'held-fire-fixture',60);print(p.stdout,flush=True);passed=True
    p=run(['wine',smoke,dll,seh],'held-fire-dll-smoke',60);print(p.stdout,flush=True);smoke_passed=True
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
result={'file':str(dll),'filename':dll.name,'sha256':digest(dll),'input_sha256':{str(p.relative_to(HERE.parent)):digest(p)for p in INPUTS},
 'fixture_passed':passed,'fixture_log':str(OUT/'held-fire-fixture.log'),'fixture':str(fixture),
 'production_dll_smoke_passed':smoke_passed,'production_dll_smoke_log':str(OUT/'held-fire-dll-smoke.log'),
 'production_imports_log':str(OUT/'production-imports.log'),'crt_startup':False,
 'windows_seh':True,'production_cas_protection_test':smoke_passed,
 'target_build':26568081,'abi':1,'config_bytes':144,'stats_bytes':184,'events':['6BD9C5E3','8BCD9161'],
 'mechanism':'Generation-owned writable UnitAPI+370 data slot; exact local-body caller/event suppression only.',
 'ttl_max_ms':250,'executable_writes':False,'protection_changes':False,'minhook_linked':False,'installed':False,'in_game_tested':False}
(OUT/'held-fire-build.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
