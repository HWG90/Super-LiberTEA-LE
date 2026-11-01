"""Execute the guarded captured native boot route against the deliverable core."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
from validate import parse
ROOT=Path(__file__).resolve().parent
FAILURES=['registration','config','config-error','limit','missing','require','init','order','recursive']

def validate():
    evidence=json.loads((ROOT/'boot-route-evidence.json').read_text())
    assert hashlib.sha256(Path(evidence['capture']).read_bytes()).hexdigest()==evidence['capture_sha256']
    results={}
    for platform in ['linux','windows','reference']:
        folder=ROOT/'dist'/platform;build=json.loads((folder/'BUILD.json').read_text())
        for name,want in build['files'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==want,name
        for name,want in build['inputs'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==want,name
        env=dict(os.environ);command=[str(folder/('vm-poc.exe' if platform=='windows' else 'vm-poc'))]
        if platform=='windows':
            command.insert(0,'wine');env.update(WINEPREFIX=str(ROOT.parent/'build/wine-prefix'),WINEDEBUG='-all',WINEDLLOVERRIDES='mscoree,mshtml=')
        run=subprocess.run([*command,'boot'],env=env,capture_output=True,text=True,timeout=60)
        (folder/'boot.log').write_text(run.stdout+run.stderr)
        assert run.returncode==0,(platform,run.returncode,run.stdout,run.stderr)
        boot=parse(run.stdout,'POC_BOOT')
        expected=dict.fromkeys(['native_setup','registrations','steam','friends','config','plugins','stock','guards','rollback'],'pass')
        expected.update(states=2,frames=4001);assert boot==expected,(platform,boot)
        failures={}
        for name in FAILURES:
            mode='boot-fail-'+name
            failed=subprocess.run([*command,mode],env=env,capture_output=True,text=True,timeout=60)
            (folder/(mode+'.log')).write_text(failed.stdout+failed.stderr)
            assert failed.returncode==42,(platform,mode,failed.returncode,failed.stdout,failed.stderr)
            detail=parse(failed.stdout,'POC_BOOT_FAILURE');assert detail['mode']==mode
            failures[name]=dict(exit_code=failed.returncode,**detail)
        result={'boot':boot,'failures':failures,'build':build,
                'execution':'Wine' if platform=='windows' else 'Linux with Win64 ABI caller execution'}
        if platform!='reference':
            jit=parse(run.stdout,'POC_JIT');assert jit['enabled'] and jit['mod_traces']>0 and jit['mod_machine_code']>0
            bootstrap=parse(run.stdout,'POC_BOOTSTRAP')
            assert bootstrap=={'stock':'pass','startup':'pass','mod':'LLL_Poll_Cache','update':'pass',
                'restart_policy':'pass','fixture_reload':'pass','fixture_disable':'pass','shutdown':'pass','ffi':'real','bit':'real'}
            result.update(jit=jit,bootstrap=bootstrap)
        results[platform]=result
    from prepare import build_poll_cache
    _,original=build_poll_cache.runtime_files();mod=json.loads((ROOT/'work/PROVENANCE.json').read_text())['mod']
    for name,want in mod['files'].items():
        assert hashlib.sha256(original[name]).hexdigest()==want
        assert hashlib.sha256((ROOT/'work/mod'/name).read_bytes()).hexdigest()==want
    receipt={'status':'captured native boot route passed in an isolated owned image',
        'validated_at':datetime.now(timezone.utc).isoformat(),'platforms':results,'evidence':evidence,'mod':mod,
        'old_puc_state_fields':'null throughout; no PUC state allocated',
        'native_setup':'captured allocation and global bookkeeping instructions run; transitive allocator and API helper bodies are fixtures',
        'registration':'eight typed required adapters receive captured call arguments; Steam and Friends/Presence use the new registrars and native callback adapters; six other registrar bodies remain fixtures',
        'config':'original native dynamic-option layout read through bounded host reader; bool/narrowed-number globals set with protected Lua API',
        'plugins':'captured native iteration and optional setup/result handling tested with fixture callbacks; real plugin VM API remains unported',
        'stock_boot':'captured binary-config lookup selects stock/boot; protected require and init run in replacement state',
        'mod_execution':'after native stock boot, assembled LLL loads unchanged Poll Cache in that state for 4000 frames; second state runs one stock frame',
        'mod_sources_changed':False,'workers_used':False,'stock_and_mod_share_state_and_thread':True,
        'early_game_loader_installed':False,'native_registration_parity':False,'in_game_vm_replaced':False,
        'native_windows_tested':False,'shutdown':'Lua shutdown in this fixture; captured native game shutdown validated separately by validate_shutdown.py'}
    (ROOT/'dist/BOOT-VALIDATION.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'results':{p:{'boot':r['boot'],'jit':r.get('jit'),'failure_cases':len(r['failures'])} for p,r in results.items()},'in_game_vm_replaced':False},indent=2))
if __name__=='__main__':validate()
