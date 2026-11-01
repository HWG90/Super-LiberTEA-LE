"""Cross-compile the near-clip helper, run its fixture under wine, install it
into native/ and point profile.lua at it. Stamp covers this folder and the
shared native_memory.h only, so the five first-person helpers keep theirs."""
from pathlib import Path
import subprocess,hashlib,json,os,re,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1];OUT=ROOT/'dist/near-clip';OUT.mkdir(parents=True,exist_ok=True)
ZIG=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig')
SOURCES=sorted(p for p in HERE.iterdir() if p.suffix in ('.cpp','.h'))+[ROOT/'native/first_person/native_memory.h']
stamp=hashlib.sha256(b''.join(p.read_bytes() for p in SOURCES)).hexdigest()[:12]
dll=OUT/f'native_ads_near_26251122_{stamp}.dll';exe=OUT/'near_fixture.exe'
common=[str(ZIG),'c++','-target','x86_64-windows-gnu','-std=c++17','-fms-extensions','-O2','-Wall','-Werror']
for source,output,flags in [('native_ads_near.cpp',dll,['-shared']),('near_fixture.cpp',exe,[])]:
    proc=subprocess.run(common+flags+[str(HERE/source),'-o',str(output)],capture_output=True,text=True)
    if proc.returncode:raise SystemExit(source+'\n'+proc.stderr)
env={**os.environ,'WINEDEBUG':'-all','WINEPREFIX':os.environ.get('GADGET_WINEPREFIX','/home/goose/Documents/ChatGPT/Linux HD2/native-work/bridge-terminal/wine-prefix')}
proc=subprocess.run(['wine',str(exe)],env=env,capture_output=True,text=True,timeout=60)
(OUT/'near_fixture.log').write_text(proc.stdout+proc.stderr)
if proc.returncode:raise SystemExit('near_fixture\n'+proc.stdout+proc.stderr)
print(proc.stdout.splitlines()[-1])
for old in (ROOT/'native').glob('native_ads_near_26251122_*.dll'):
    if old.name!=dll.name:old.unlink()
shutil.copyfile(dll,ROOT/'native'/dll.name)
p=ROOT/'src/first_person/profile.lua';text=p.read_text()
text=re.sub(r"native_ads_near_26251122_[a-z0-9]+\.dll",dll.name,text);p.write_text(text)
digest=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
(OUT/'build.json').write_text(json.dumps({'target_build':26251122,'library':dll.name,'sha256':digest(dll),
    'sources':{f.name:digest(f) for f in SOURCES},'fixture_passed':True,'fixture_log':str(OUT/'near_fixture.log'),
    'abi':1,'config_bytes':72,'stats_bytes':88,'executable_writes':False,'protection_changes':False,
    'in_game_tested':False},indent=2)+'\n')
print(json.dumps({'library':dll.name,'sha256':digest(dll)}))
