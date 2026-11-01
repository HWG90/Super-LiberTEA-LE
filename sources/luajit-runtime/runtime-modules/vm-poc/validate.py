"""Run actual stock-bytecode reference, LuaJIT controls, and Win64 under Wine."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import statistics
import subprocess

ROOT=Path(__file__).resolve().parent

def parse(stdout,tag):
    lines=[line for line in stdout.splitlines() if line.startswith(tag+' ')]
    assert len(lines)==1,(tag,lines)
    result={}
    for key,value in re.findall(r'(\w+)=([^\s]+)',lines[0]):
        if value in ('true','false'):value=value=='true'
        elif re.fullmatch(r'\d+',value):value=int(value)
        elif re.fullmatch(r'\d+\.\d+',value):value=float(value)
        result[key]=value
    return result

def run(platform,mode,index=0):
    folder=ROOT/'dist'/platform
    command=[str(folder/('vm-poc.exe' if platform=='windows' else 'vm-poc')),mode]
    env=dict(os.environ)
    if platform=='windows':
        env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        command=['wine',*command]
    completed=subprocess.run(command,capture_output=True,text=True,env=env,timeout=60)
    (folder/f'{mode}-{index}.log').write_text(completed.stdout+completed.stderr)
    assert completed.returncode==0,(platform,mode,completed.stdout,completed.stderr)
    result={tag:parse(completed.stdout,tag) for tag in ['POC_SEMANTICS','POC_NATIVE','POC_JIT','POC_TIME','POC_OWNERSHIP','POC_FINALIZER','POC_LOADERS','POC_PROVIDER','POC_ENTRY','POC_OBJECTS']}
    assert result['POC_SEMANTICS']=={'stock':9,'curve':'pass','audio':'pass','identity':'pass',
        'coroutine':'pass','errors':'pass','mod':'LLL_Poll_Cache','lifecycle':'pass'}
    assert result['POC_OWNERSHIP']=={'reentrant_refused':1,'cross_thread_refused':1}
    assert result['POC_FINALIZER']=={'backend_alive':True}
    assert result['POC_LOADERS']=={'embedded':'pass','reader':'pass','file':'pass','require':'pass','mode':'pass','unknown_puc_refused':True}
    assert result['POC_PROVIDER']=={'framed_stock':'pass','override_precedence':'pass','invalid_rejected':'pass'}
    assert result['POC_ENTRY']=={'typed_arguments':'pass','results':'pass','binary_strings':'pass',
                                'errors':'pass','gc_lifetime':'pass','close_lifetime':'pass'}
    assert result['POC_OBJECTS']==dict.fromkeys(['ownership','identity','metamethods','errors','collection','stale','foreign'],'pass')
    jit=result['POC_JIT']
    expected=mode=='on' and platform!='reference'
    assert jit['enabled']==expected
    if expected:assert jit['mod_traces']>0 and jit['mod_machine_code']>0
    else:assert jit['mod_traces']==0 and jit['mod_machine_code']==0 and jit['total_traces']==0
    return result

def validate():
    from verify_native import verify
    builds={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform
        build=json.loads((folder/'BUILD.json').read_text())
        for name,expected in build['files'].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==expected, 'built artifact changed'
        for name,expected in build['inputs'].items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected, 'source changed after build'
        builds[platform]=build
    native_candidate=verify()
    reference=run('reference','off')
    runs={}
    for platform in ['linux','windows']:
        modes={'on':[],'off':[]}
        # Paired order alternates to reduce systematic warm-cache bias.
        for index in range(3):
            for mode in ['on','off'] if index%2==0 else ['off','on']:
                value=run(platform,mode,index)
                assert value['POC_NATIVE']==reference['POC_NATIVE'], (platform,mode,'native effects differ')
                modes[mode].append(value)
        on=statistics.median(r['POC_TIME']['cpu_seconds'] for r in modes['on'])
        off=statistics.median(r['POC_TIME']['cpu_seconds'] for r in modes['off'])
        runs[platform]={'runs':modes,'median_cpu_seconds':{'jit_on':on,'jit_off':off},
                        'synthetic_speed_ratio':off/on if on else None}
    provenance=json.loads((ROOT/'work/PROVENANCE.json').read_text())
    from prepare import LLL
    import build_poll_cache
    _,original=build_poll_cache.runtime_files()
    for name,expected in provenance['mod']['files'].items():
        assert hashlib.sha256((ROOT/'work/mod'/name).read_bytes()).hexdigest()==expected
        assert hashlib.sha256(original[name]).hexdigest()==expected, 'mod changed during validation'
    result={'status':'standalone proof passed','native_backend':'deterministic C fixture, not live game bindings',
            'validated_at':datetime.now(timezone.utc).isoformat(),'builds':builds,
            'harness_linkage':'LuaJIT test harnesses load the built shared environment libraries',
            'native_binding_candidate_validation':native_candidate,
            'stock_source_method':'unluac recovery followed by LuaJIT compilation',
            'reference':'original stock bytecode, size_t converted only, PUC Lua 5.1.4',
            'reference_results':reference,'platforms':runs,'mod_unchanged':True,
            'provenance':provenance,'single_lua_state_for_stock_and_mod':True,
            'independent_provider_test_state':True,'workers_used':False,
            'additional_cross_environment_ownership_test_states':2,
            'in_game_vm_replaced':False,'native_windows_tested':False,
            'limitations':['Archive loading precedence still requires the live engine resolver',
                'Unexercised stock function branches are not proven equivalent',
                'Visualization/vector callbacks are not implemented',
                'Early native bootstrap and engine detours not installed',
                'No live engine backend or in-game performance test']}
    (ROOT/'dist/VALIDATION.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'mod_unchanged':True,
        'platforms':{p:{'mod_machine_code':v['runs']['on'][0]['POC_JIT']['mod_machine_code'],
                       'synthetic_speed_ratio':v['synthetic_speed_ratio']} for p,v in runs.items()},
        'in_game_vm_replaced':False},indent=2))

if __name__=='__main__':validate()
