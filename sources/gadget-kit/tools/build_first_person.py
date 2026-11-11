"""Cross-compile the five current-build first-person helpers and run their independent fixtures."""
from pathlib import Path
import subprocess,concurrent.futures,hashlib,json,os,sys
ROOT=Path(__file__).resolve().parents[1];NATIVE=ROOT/'native/first_person';OUT=ROOT/'dist/first-person';OUT.mkdir(parents=True,exist_ok=True)
ZIG=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig')
PAIRS=[('alignment','fixture'),('editor','editor_fixture'),('fov','fov_fixture'),('camera','camera_fixture'),('blur','blur_fixture')]
def build(pair):
 name,fixture=pair
 stamp=hashlib.sha256(b''.join(p.read_bytes()for p in sorted(NATIVE.iterdir())if p.suffix in ('.cpp','.h'))).hexdigest()[:12]
 dll=OUT/f'native_ads_{name}_26568081_{stamp}.dll';exe=OUT/f'{fixture}.exe'
 common=[str(ZIG),'c++','-target','x86_64-windows-gnu','-std=c++17','-fms-extensions','-O2']
 for source,output,flags in [(f'native_ads_{name}.cpp',dll,['-shared']),(fixture+'.cpp',exe,[])]:
  proc=subprocess.run(common+flags+[str(NATIVE/source),'-o',str(output)],capture_output=True,text=True)
  if proc.returncode:raise RuntimeError(source+'\n'+proc.stderr)
 env={**os.environ,'WINEDEBUG':'-all','WINEPREFIX':os.environ.get('GADGET_WINEPREFIX','/home/goose/Documents/ChatGPT/Linux HD2/native-work/bridge-terminal/wine-prefix')}
 proc=subprocess.run(['wine',str(exe)],env=env,capture_output=True,text=True,timeout=60)
 (OUT/(fixture+'.log')).write_text(proc.stdout+proc.stderr)
 if proc.returncode:raise RuntimeError(fixture+'\n'+proc.stdout+proc.stderr)
 print(name+': '+proc.stdout.splitlines()[-1],flush=True)
 return {'name':name,'file':str(dll),'sha256':hashlib.sha256(dll.read_bytes()).hexdigest(),'fixture_passed':True,'fixture_log':str(OUT/(fixture+'.log')),'source_sha256':hashlib.sha256((NATIVE/f'native_ads_{name}.cpp').read_bytes()).hexdigest()}
with concurrent.futures.ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(build,PAIRS))
(OUT/'build.json').write_text(json.dumps({'target_build':26568081,'helpers':results,'in_game_tested':False},indent=2)+'\n')

import shutil,re
p=ROOT/'src/first_person/profile.lua';text=p.read_text()
for row in results:
 dll=Path(row['file']);shutil.copyfile(dll,ROOT/'native'/dll.name)
 text=re.sub(r"native_ads_"+row['name']+r"_[0-9]+_[a-z0-9]+\.dll",dll.name,text)
p.write_text(text)
