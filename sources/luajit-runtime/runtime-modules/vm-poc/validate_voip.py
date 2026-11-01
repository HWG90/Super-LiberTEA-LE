"""Compare the partial SteamVoip views with captured original callbacks."""
from datetime import datetime,timezone
import hashlib,json,os,subprocess
from pathlib import Path
from validate import parse
ROOT=Path(__file__).resolve().parent
EXPECTED={'callbacks':7,'differential_cases':175,'guards':8799,'queries':'pass','selection':'pass',
          'userdata':'pass','contexts':'pass','errors':'pass','hash_lookup':'fixture',
          'complete_registrar':False,'live_service':False}

def validate():
    evidence=json.loads((ROOT/'voip-binding-evidence.json').read_text())
    for prefix in ('','newer_'):
        assert hashlib.sha256(Path(evidence[prefix+'capture']).read_bytes()).hexdigest()==evidence[prefix+'capture_sha256']
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform;build=json.loads((folder/'BUILD.json').read_text())
        for name,want in build['files'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==want,name
        for name,want in build['inputs'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==want,name
        env=dict(os.environ);command=[str(folder/('vm-poc.exe' if platform=='windows' else 'vm-poc')),'voip-views']
        if platform=='windows':
            command.insert(0,'wine');env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        run=subprocess.run(command,env=env,capture_output=True,text=True,timeout=60)
        (folder/'voip-views.log').write_text(run.stdout+run.stderr)
        assert run.returncode==0,(platform,run.returncode,run.stdout,run.stderr)
        checks=parse(run.stdout,'POC_VOIP_VIEWS');assert checks==EXPECTED,(platform,checks)
        results[platform]={'checks':checks,'build':build,'execution':'Wine' if platform=='windows' else 'Linux with Win64 ABI callback execution'}
    runtime=ROOT/'work/runtime/linux/LuaJIT/src';exe=ROOT/'work/voip-asan'
    sources=['environment.c','engine_curve.c','frame_routes.c','lifecycle_routes.c','boot_routes.c','shutdown_routes.c','gc_routes.c','engine_steam.c','engine_friends.c','engine_voip.c',
             'harness.c','entry_tests.c','object_tests.c','frame_tests.c','lifecycle_tests.c','boot_tests.c','steam_tests.c','friends_tests.c','voip_tests.c','shutdown_tests.c','gc_tests.c']
    command=['cc','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',
             '-I'+str(runtime),'-I'+str(ROOT/'work'),*[str(ROOT/n) for n in sources],str(runtime/'libluajit.a'),'-lm','-ldl','-pthread','-o',str(exe)]
    subprocess.run(command,check=True,capture_output=True,text=True)
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    run=subprocess.run([str(exe),'voip-views'],env=env,capture_output=True,text=True,timeout=60)
    (ROOT/'dist/linux/voip-sanitizers.log').write_text(run.stdout+run.stderr)
    assert run.returncode==0 and not run.stderr,(run.returncode,run.stdout,run.stderr)
    assert parse(run.stdout,'POC_VOIP_VIEWS')==EXPECTED
    receipt={'status':'seven SteamVoip room/client bindings passed; full registrar remains incomplete',
        'validated_at':datetime.now(timezone.utc).isoformat(),'platforms':results,'evidence':evidence,
        'oracle':'unchanged captured Lua callbacks and four native selection helpers execute in an owned image; PUC/CRT/temporary allocation and native member hash lookup are fixtures',
        'coverage':'175 comparisons across empty/sparse/deleted/growing collections, broken flags, 64-bit IDs, physical slot order, full/light userdata, truthiness, all/one/absent-member selection; native selection state writes compared',
        'full_userdata':'existing eight-byte Wwise test wrapper supplies the borrowed pointer; native SteamVoip.join_room allocation is NOT implemented or tested',
        'lifetime':'borrowed native pointers; no __gc/release; engine-owned manager slot shared between environments and preserved on destruction',
        'intentional_differences':['invalid room IDs, unparseable IDs, undersized/null userdata, refused reads/calls and excessive counts become Lua errors instead of unchecked access'],
        'limits':'at most 1048576 room/member slots; host must keep all native data/code stable for the entire call, including Lua allocations and finalizers',
        'remaining':'room create/destroy/join/leave, add/remove member and update/callback bridge unported; native hash lookup body unavailable; six boot registrars still incomplete',
        'sanitizers':{'address':True,'undefined_behavior':True,'leak_detection':True,'command':command,
            'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'scope':'C core and fixtures; LuaJIT and captured machine code uninstrumented'},
        'native_service_live_validated':False,'native_windows_tested':False,'in_game_vm_replaced':False,'complete_voip_registrar':False}
    (ROOT/'dist/VOIP-VALIDATION.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'platforms':{p:r['checks'] for p,r in results.items()},'sanitizers':'passed'},indent=2))
if __name__=='__main__':validate()
