"""Build the current optic policy and run its isolated synthetic fixtures."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=ROOT/'dist/first-person'
OUT.mkdir(parents=True,exist_ok=True)
ZIG=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig')
VENDOR=HERE/'vendor/minhook'
env={**os.environ}
env.setdefault('ZIG_GLOBAL_CACHE_DIR',str(ROOT.parent/'zig-global-cache'))
env.setdefault('ZIG_LOCAL_CACHE_DIR',str(ROOT.parent/'zig-local-cache'))
inputs=[HERE/'native_ads_zoom.cpp',HERE/'native_ads_zoom.h',HERE.parent/'first_person/native_memory.h']+sorted(p for p in VENDOR.rglob('*') if p.is_file())
stamp=hashlib.sha256(b''.join(p.read_bytes() for p in inputs)).hexdigest()[:12]
dll=OUT/f'native_ads_zoom_26251122_{stamp}.dll'
fixture=OUT/'zoom_fixture.exe'
smoke=OUT/'zoom_minhook_smoke.exe'

def run(args):
    result=subprocess.run([str(a) for a in args],env=env,text=True,capture_output=True)
    if result.returncode:
        raise RuntimeError(' '.join(map(str,args))+'\n'+result.stdout+result.stderr)
    return result

objects=[]
for source in ['buffer.c','hook.c','trampoline.c','hde/hde64.c']:
    obj=OUT/('zoom_mh_'+Path(source).stem+'.o')
    run([ZIG,'cc','-target','x86_64-windows-gnu','-O2','-DNDEBUG','-c',VENDOR/'src'/source,'-o',obj])
    objects.append(obj)
common=[ZIG,'c++','-target','x86_64-windows-gnu','-std=c++17','-fms-extensions','-O2']
run(common+['-shared',HERE/'native_ads_zoom.cpp',*objects,'-o',dll])
run(common+[HERE/'zoom_fixture.cpp','-o',fixture])
run(common+[HERE/'minhook_smoke.cpp',*objects,'-o',smoke])
passed=False
if '--build-only' not in sys.argv:
    wine_env={**env,'WINEDEBUG':'-all','WINEPREFIX':env.get('GADGET_WINEPREFIX','/tmp/ggk-fp-zoom-test-prefix')}
    for executable,log in [(fixture,'zoom_fixture.log'),(smoke,'zoom_minhook_smoke.log')]:
        result=subprocess.run(['wine',str(executable)],env=wine_env,text=True,capture_output=True,timeout=60)
        (OUT/log).write_text(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
        print(result.stdout.splitlines()[-1],flush=True)
    passed=True
shutil.copyfile(dll,ROOT/'native'/dll.name)
profile=ROOT/'src/first_person/profile.lua'
text=profile.read_text()
updated=re.sub(r'native_ads_zoom_[0-9]+_[a-z0-9]+\.dll',dll.name,text)
if updated!=text:profile.write_text(updated)
result={'name':'zoom','file':str(dll),'sha256':hashlib.sha256(dll.read_bytes()).hexdigest(),
        'fixture_passed':passed,'fixture_log':str(OUT/'zoom_fixture.log'),'real_minhook_smoke_passed':passed,
        'minhook_smoke_log':str(OUT/'zoom_minhook_smoke.log'),
        'source_sha256':hashlib.sha256((HERE/'native_ads_zoom.cpp').read_bytes()).hexdigest(),
        'target_build':26251122,'in_game_tested':False,
        'minhook_license':str(VENDOR/'LICENSE.txt')}
(OUT/'zoom-build.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
