"""Execute native game shutdown with replacement Lua/GC and fixture native services."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib,json,os,subprocess
from validate import parse
ROOT=Path(__file__).resolve().parent
EXPECTED={**dict.fromkeys(['lua','full_gc','native_order','hook_flags','errors','lifetime','frame_gate','guards','rollback'],'pass'),'states':4,'frames':4003}
FAILURES=['unbound','order','recursive','duplicate','boot','close']

def check_runtime(folder,platform):
    env=dict(os.environ);exe=folder/('vm-poc.exe' if platform=='windows' else 'vm-poc');prefix=[]
    if platform=='windows':
        prefix=['wine'];env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
    def run(mode):
        p=subprocess.run([*prefix,str(exe),mode],env=env,capture_output=True,text=True,timeout=90)
        (folder/(mode+'.log')).write_text(p.stdout+p.stderr);return p
    p=run('shutdown');assert p.returncode==0,(platform,p.returncode,p.stdout,p.stderr)
    assert parse(p.stdout,'POC_SHUTDOWN')==EXPECTED
    result={'shutdown':EXPECTED,'execution':'Wine' if platform=='windows' else 'Linux with Win64 ABI caller execution','failures':{}}
    if platform!='reference':
        jit=parse(p.stdout,'POC_JIT');assert jit['enabled'] and jit['mod_traces']>0 and jit['mod_machine_code']>0
        bootstrap=parse(p.stdout,'POC_BOOTSTRAP')
        assert bootstrap=={'stock':'pass','startup':'pass','mod':'LLL_Poll_Cache','update':'pass','restart_policy':'pass','fixture_reload':'pass','fixture_disable':'pass','shutdown':'pass','ffi':'real','bit':'real'}
        result.update(jit=jit,bootstrap=bootstrap)
    for failure in FAILURES:
        mode='shutdown-fail-'+failure;p=run(mode);assert p.returncode==42,(platform,mode,p.returncode,p.stdout,p.stderr)
        event=parse(p.stdout,'POC_SHUTDOWN_FAILURE');assert event=={'mode':mode,'operation':'close' if failure=='close' else 'shutdown'}
        result['failures'][failure]={'exit_code':p.returncode,**event}
    p=run('shutdown-finalizer-error')
    if platform=='reference':
        assert p.returncode==42,(platform,p.returncode,p.stdout,p.stderr)
        assert parse(p.stdout,'POC_SHUTDOWN_FAILURE')=={'mode':'shutdown-finalizer-error','operation':'shutdown-gc'}
        result['finalizer_error']='PUC propagates; factory fatal handler runs before native cleanup'
    else:
        assert p.returncode==0 and parse(p.stdout,'POC_SHUTDOWN')==EXPECTED,(platform,p.returncode,p.stdout,p.stderr)
        assert p.stderr.count('ERROR in finalizer: shutdown-gc-error:1: fixture shutdown GC failure')==4,p.stderr
        result['finalizer_error']='LuaJIT ERRFIN reports four finalizer errors; full GC and native cleanup complete'
    return result

def validate():
    evidence=json.loads((ROOT/'shutdown-route-evidence.json').read_text())
    for prefix in ('','newer_'):
        assert hashlib.sha256(Path(evidence[prefix+'capture']).read_bytes()).hexdigest()==evidence[prefix+'capture_sha256']
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform;build=json.loads((folder/'BUILD.json').read_text())
        for n,h in build['inputs'].items():assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h,n
        for n,h in build['files'].items():assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h,n
        result=check_runtime(folder,platform);result['build']=build;results[platform]=result
    runtime=ROOT/'work/runtime/linux/LuaJIT/src';exe=ROOT/'work/shutdown-asan'
    sources=['environment.c','engine_curve.c','frame_routes.c','lifecycle_routes.c','boot_routes.c','shutdown_routes.c','gc_routes.c',
             'engine_steam.c','engine_friends.c','engine_voip.c','harness.c','entry_tests.c','object_tests.c','frame_tests.c',
             'lifecycle_tests.c','boot_tests.c','steam_tests.c','friends_tests.c','voip_tests.c','shutdown_tests.c','gc_tests.c']
    command=['cc','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',
             '-I'+str(runtime),'-I'+str(ROOT/'work'),*[str(ROOT/n) for n in sources],str(runtime/'libluajit.a'),'-lm','-ldl','-pthread','-o',str(exe)]
    subprocess.run(command,check=True,capture_output=True,text=True)
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    for mode in ['shutdown','shutdown-finalizer-error']:
        p=subprocess.run([str(exe),mode],env=env,capture_output=True,text=True,timeout=90)
        (ROOT/'dist/linux'/(mode+'-sanitizers.log')).write_text(p.stdout+p.stderr)
        assert p.returncode==0 and parse(p.stdout,'POC_SHUTDOWN')==EXPECTED,(p.returncode,p.stdout,p.stderr)
        lines=p.stderr.splitlines()
        assert lines==(['ERROR in finalizer: shutdown-gc-error:1: fixture shutdown GC failure']*4 if mode.endswith('error') else []),p.stderr
    from prepare import build_poll_cache
    _,original=build_poll_cache.runtime_files();mod=json.loads((ROOT/'work/PROVENANCE.json').read_text())['mod']
    for n,h in mod['files'].items():assert hashlib.sha256(original[n]).hexdigest()==h and hashlib.sha256((ROOT/'work/mod'/n).read_bytes()).hexdigest()==h,n
    receipt={'status':'complete captured native shutdown caller passed with replacement Lua shutdown and full collection',
        'validated_at':datetime.now(timezone.utc).isoformat(),'platforms':results,'evidence':evidence,'mod':mod,
        'mod_sources_changed':False,'stock_and_mod_share_state_and_thread':True,'workers_used':False,
        'coverage':'four native construction/frame/shutdown cycles, 4003 frames, unchanged Poll Cache machine code, both native hook conditions in all four combinations, present/absent services, three plugin rows, native handle/global/buffer/allocator teardown and byte-for-byte restoration',
        'old_vm_memory':'both native state slots point to an inaccessible page; old PUC code/collector pages remain inaccessible',
        'full_collection':'protected public lua_gc(LUA_GCCOLLECT); global collectgarbage replaced with a throwing function in tests',
        'finalizers':'unreachable userdata finalized before native service teardown; reachable userdata finalized at environment close before host backend release',
        'errors':'ordinary shutdown Lua errors report through replacement frame reporter and still collect/teardown; six invalid sequencing/lifetime cases fail before native cleanup',
        'runtime_difference':'pinned LuaJIT catches finalizer errors and sends ERRFIN; PUC reference propagates them into the protected full-collection boundary, invoking the fatal handler; both tested without claiming identical error behavior',
        'native_helpers':'all transitive engine services, plugins, allocator and filesystem helpers remain controlled fixtures; the cleanup caller instructions are captured originals',
        'boot':'test constructs the environment and loads stock/LLL through the replacement core; captured boot is validated separately',
        'gc_policy':'shutdown full collection and captured timed per-frame scheduler implemented; native settings/profiler wiring remains',
        'sanitizers':{'address':True,'undefined_behavior':True,'leak_detection':True,'command':command,'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),
            'scope':'C core and fixtures; LuaJIT static library and captured native machine code uninstrumented'},
        'exceptions':'native exception unwinding across copied code and original engine TLS/error reporter parity not established',
        'in_game_vm_replaced':False,'native_windows_tested':False}
    (ROOT/'dist/SHUTDOWN-VALIDATION.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'results':{p:{'shutdown':v['shutdown'],'finalizer_error':v['finalizer_error'],'jit':v.get('jit')} for p,v in results.items()},'sanitizers':'passed'},indent=2))
if __name__=='__main__':validate()
