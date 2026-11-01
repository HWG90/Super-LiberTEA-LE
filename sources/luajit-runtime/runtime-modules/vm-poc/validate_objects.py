"""Verify owned native Lua values, allocation rollback and sanitizer results."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
from validate import parse

ROOT=Path(__file__).resolve().parent
EXPECTED=dict.fromkeys(['ownership','identity','metamethods','errors','collection','stale','foreign'],'pass')


def validate():
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform
        build=json.loads((folder/'BUILD.json').read_text())
        for name,want in build['inputs'].items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==want, name
        for name,want in build['files'].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==want, name
        env=dict(os.environ);prefix=[];suffix=''
        if platform=='windows':
            prefix=['wine'];suffix='.exe'
            env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        ordinary=subprocess.run([*prefix,str(folder/('vm-poc'+suffix)),'objects'],env=env,capture_output=True,text=True,timeout=60)
        (folder/'objects.log').write_text(ordinary.stdout+ordinary.stderr)
        assert ordinary.returncode==0,(platform,ordinary.stdout,ordinary.stderr)
        ownership=parse(ordinary.stdout,'POC_OBJECTS');assert ownership==EXPECTED
        fault=subprocess.run([*prefix,str(folder/('object-fault-tests'+suffix))],env=env,capture_output=True,text=True,timeout=60)
        (folder/'object-faults.log').write_text(fault.stdout+fault.stderr)
        assert fault.returncode==0,(platform,fault.stdout,fault.stderr)
        coverage=parse(fault.stdout,'POC_OBJECT_FAULTS')
        assert coverage['cases']==400 and coverage['faulted']>100
        assert coverage['faulted']==coverage['recovered'] and coverage['refused_after_rollback_failure']==0
        results[platform]={'objects':ownership,'allocation_failures':coverage,'build':build,
                           'execution':'Wine' if platform=='windows' else platform}
    # Instrument the actual core's C ownership bookkeeping. LuaJIT itself is
    # the existing pinned static library, not an instrumented VM build.
    runtime=ROOT/'work/runtime/linux/LuaJIT/src'
    executable=ROOT/'work/object-fault-tests-asan'
    command=['cc','-std=c11','-O1','-g','-Wall','-Wextra','-Werror',
             '-fsanitize=address,undefined','-fno-omit-frame-pointer',
             '-I'+str(runtime),'-I'+str(ROOT/'work'),str(ROOT/'object_fault_tests.c'),
             str(ROOT/'engine_curve.c'),str(ROOT/'engine_steam.c'),str(ROOT/'engine_friends.c'),str(ROOT/'engine_voip.c'),str(runtime/'libluajit.a'),'-lm','-ldl','-pthread','-o',str(executable)]
    subprocess.run(command,check=True,capture_output=True,text=True)
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    run=subprocess.run([str(executable)],capture_output=True,text=True,env=env,timeout=60)
    (ROOT/'dist/linux/objects-sanitizers.log').write_text(run.stdout+run.stderr)
    assert run.returncode==0,(run.stdout,run.stderr)
    assert parse(run.stdout,'POC_OBJECT_FAULTS')==results['linux']['allocation_failures']
    assert not run.stderr,run.stderr
    result={'status':'owned Lua values and rollback passed',
            'validated_at':datetime.now(timezone.utc).isoformat(),'platforms':results,
            'sanitizers':{'address':True,'undefined_behavior':True,'leak_detection':True,
                          'scope':'C core and fault harness; LuaJIT static library uninstrumented',
                          'command':command,'executable_sha256':hashlib.sha256(executable.read_bytes()).hexdigest()},
            'native_engine_calls':False,'native_windows_tested':False,'engine_luaobject_consumers_replaced':False}
    (ROOT/'dist/OBJECT-VALIDATION.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],
        'allocation_failures':{p:v['allocation_failures'] for p,v in results.items()},
        'sanitizers':'passed','engine_luaobject_consumers_replaced':False},indent=2))


if __name__=='__main__':validate()
