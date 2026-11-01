"""Validate Friends/Presence against captured callbacks, without live services."""
from datetime import datetime,timezone
import hashlib,json,os,subprocess
from pathlib import Path
from validate import parse
ROOT=Path(__file__).resolve().parent

def validate():
    evidence=json.loads((ROOT/'friends-binding-evidence.json').read_text())
    assert hashlib.sha256(Path(evidence['capture']).read_bytes()).hexdigest()==evidence['capture_sha256']
    expected={'callbacks':14,'constants':28,'differential_cases':101,'guards':15361,'registration':'pass',
              'order':'pass','contexts':'pass','errors':'pass','original_helpers':'fixtures','live_service':False}
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform;build=json.loads((folder/'BUILD.json').read_text())
        for name,want in build['files'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==want,name
        for name,want in build['inputs'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==want,name
        env=dict(os.environ);command=[str(folder/('vm-poc.exe' if platform=='windows' else 'vm-poc')),'friends']
        if platform=='windows':
            command.insert(0,'wine');env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        run=subprocess.run(command,env=env,capture_output=True,text=True,timeout=60)
        (folder/'friends.log').write_text(run.stdout+run.stderr)
        assert run.returncode==0,(platform,run.returncode,run.stdout,run.stderr)
        check=parse(run.stdout,'POC_FRIENDS');assert check==expected,(platform,check)
        results[platform]={'checks':check,'build':build,'execution':'Wine' if platform=='windows' else 'Linux with Win64 ABI callback execution'}
    runtime=ROOT/'work/runtime/linux/LuaJIT/src';exe=ROOT/'work/friends-asan'
    sources=['environment.c','engine_curve.c','frame_routes.c','lifecycle_routes.c','boot_routes.c','shutdown_routes.c','gc_routes.c','engine_steam.c','engine_friends.c','engine_voip.c',
             'harness.c','entry_tests.c','object_tests.c','frame_tests.c','lifecycle_tests.c','boot_tests.c','steam_tests.c','friends_tests.c','voip_tests.c','shutdown_tests.c','gc_tests.c']
    command=['cc','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',
             '-I'+str(runtime),'-I'+str(ROOT/'work'),*[str(ROOT/n) for n in sources],str(runtime/'libluajit.a'),'-lm','-ldl','-pthread','-o',str(exe)]
    subprocess.run(command,check=True,capture_output=True,text=True)
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    run=subprocess.run([str(exe),'friends'],env=env,capture_output=True,text=True,timeout=60)
    (ROOT/'dist/linux/friends-sanitizers.log').write_text(run.stdout+run.stderr)
    assert run.returncode==0 and not run.stderr,(run.returncode,run.stdout,run.stderr)
    assert parse(run.stdout,'POC_FRIENDS')==expected
    receipt={'status':'Friends and Presence registrar port passed captured-callback comparisons',
        'validated_at':datetime.now(timezone.utc).isoformat(),'platforms':results,'evidence':evidence,
        'registration':'engine-owned context slot; two registry modules; all fourteen callbacks, then twenty-eight constants; namespace observer verifies order',
        'oracle':'unchanged captured Lua callback machine code executes against owned PUC-like slots; PUC/CRT and native helper bodies are controlled fixtures',
        'services':'direct Steam interface and seven native helpers are fixtures; no invitation, presence update or Steam request is sent',
        'coverage':'all callbacks; numeric wrapping; hex ID conversions; eight playing_game flag combinations; zero/two/four result invitation branches; lobby userdata and server strings; partial base-0 scans; nil/empty presence; native state writes; registry identity and shared contexts',
        'intentional_differences':['unparseable IDs and invalid destinations raise Lua errors instead of unchecked null/uninitialized access',
            'undersized SteamLobby userdata and nonterminated invitation text are rejected',
            'overflowing server-number text follows bounded uint32 conversion; original overflowing scanf behavior is not promised'],
        'limits':'native returned strings limited to 1 MiB; host stabilizes native data, code and service lifetimes',
        'native_helper_internals':'retained original non-Lua helper entry points; their transitive engine/Steam behavior is not validated by this differential fixture',
        'sanitizers':{'address':True,'undefined_behavior':True,'leak_detection':True,'command':command,
            'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'scope':'C core and fixtures; LuaJIT and captured machine code are uninstrumented'},
        'native_service_live_validated':False,'native_windows_tested':False,'in_game_vm_replaced':False}
    (ROOT/'dist/FRIENDS-VALIDATION.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'platforms':{p:r['checks'] for p,r in results.items()},'sanitizers':'passed','in_game_vm_replaced':False},indent=2))
if __name__=='__main__':validate()
