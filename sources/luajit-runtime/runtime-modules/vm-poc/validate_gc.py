"""Compare timed scheduling with captured code and exercise real VM collection."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib,json,os,subprocess
from validate import parse
ROOT=Path(__file__).resolve().parent
EXPECTED={**dict.fromkeys(['history','budget','full','cap','real_gc','finalizer_errors','errors','thread','reentry','rollback'],'pass'),'differential_cases':300,'guards':550,'finalizers':100,'native_routes':2}
ERROR='ERROR in finalizer: gc-test:1: timed GC finalizer failure'

def validate():
    evidence=json.loads((ROOT/'gc-policy-evidence.json').read_text())
    for prefix in ('','newer_'):
        assert hashlib.sha256(Path(evidence[prefix+'capture']).read_bytes()).hexdigest()==evidence[prefix+'capture_sha256']
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform;build=json.loads((folder/'BUILD.json').read_text())
        for n,h in build['inputs'].items():assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h,n
        for n,h in build['files'].items():assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h,n
        for n,h in build['runtime_headers'].items():assert hashlib.sha256(Path(n).read_bytes()).hexdigest()==h,n
        env=dict(os.environ);command=[str(folder/('vm-poc.exe' if platform=='windows' else 'vm-poc')),'gc']
        if platform=='windows':
            command.insert(0,'wine');env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        p=subprocess.run(command,env=env,capture_output=True,text=True,timeout=90)
        (folder/'gc.log').write_text(p.stdout+p.stderr)
        assert p.returncode==0 and parse(p.stdout,'POC_GC')==EXPECTED,(platform,p.returncode,p.stdout,p.stderr)
        warnings=[]
        if platform=='windows':
            warnings=[s for s in p.stderr.splitlines() if s.startswith(('MESA-EGL: warning:','pci id for fd '))]
        assert [s for s in p.stderr.splitlines() if s not in warnings]==([] if platform=='reference' else [ERROR]),p.stderr
        results[platform]={'gc':EXPECTED,'build':build,'execution':'Wine' if platform=='windows' else 'Linux with Win64 ABI caller execution','host_graphics_warnings':warnings}
    runtime=ROOT/'work/runtime/linux/LuaJIT/src';exe=ROOT/'work/gc-asan'
    sources=['environment.c','engine_curve.c','frame_routes.c','lifecycle_routes.c','boot_routes.c','shutdown_routes.c','gc_routes.c',
             'engine_steam.c','engine_friends.c','engine_voip.c','harness.c','entry_tests.c','object_tests.c','frame_tests.c',
             'lifecycle_tests.c','boot_tests.c','steam_tests.c','friends_tests.c','voip_tests.c','shutdown_tests.c','gc_tests.c']
    command=['cc','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',
             '-I'+str(runtime),'-I'+str(ROOT/'work'),*[str(ROOT/n) for n in sources],str(runtime/'libluajit.a'),'-lm','-ldl','-pthread','-o',str(exe)]
    subprocess.run(command,check=True,capture_output=True,text=True)
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    p=subprocess.run([str(exe),'gc'],env=env,capture_output=True,text=True,timeout=90)
    (ROOT/'dist/linux/gc-sanitizers.log').write_text(p.stdout+p.stderr)
    assert p.returncode==0 and parse(p.stdout,'POC_GC')==EXPECTED and p.stderr.splitlines()==[ERROR],(p.returncode,p.stdout,p.stderr)
    receipt={'status':'captured timed scheduler policy reproduced with replacement VM collection','validated_at':datetime.now(timezone.utc).isoformat(),
        'platforms':results,'evidence':evidence,'comparison':'300 deterministic cases against complete original scheduler instructions; VM steps, profiler and clocks are fixtures only in the oracle',
        'real_runtime':'same exported library exercises LuaJIT or PUC step/full/stop with read-only estimates from pinned headers; 100 unreachable userdata finalizers and runtime-specific error behavior',
        'routes':'patched 0x5eb310 and unchanged 0x6cd140 wrapper; native environment points to inaccessible page, original PUC collector helpers inaccessible',
        'frame_integration':'frame, boot, lifecycle and shutdown tests now invoke hd2env_collect_frame instead of a Lua test GC function',
        'limits':'clock failure/backwards time/overflow, bad settings, step/sample failures, unbound and wrong-thread native entries, reentry and destruction guards, every original caller byte checked before planning',
        'runtime_differences':'collector work granularity and estimates depend on runtime; same scheduling policy does not imply identical pause durations or reclamation. LuaJIT ERRFIN continues, PUC errors propagate into protected entry.',
        'remaining':'native settings and profiler wiring, early loader, native exception/TLS/error context, complete engine callbacks/resources/plugin APIs; no actual game integration yet',
        'sanitizers':{'address':True,'undefined_behavior':True,'leak_detection':True,'command':command,'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'scope':'C adapters/fixtures instrumented; LuaJIT library and captured machine code uninstrumented'},
        'in_game_vm_replaced':False,'native_windows_tested':False}
    (ROOT/'dist/GC-VALIDATION.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'platforms':list(results),'gc':EXPECTED,'sanitizers':'passed'},indent=2))
if __name__=='__main__':validate()
