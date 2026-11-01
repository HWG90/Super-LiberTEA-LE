"""Build the read-only protected-read helper; validate it under Wine."""
from pathlib import Path
import subprocess,hashlib,re,os,json
ROOT=Path(__file__).resolve().parents[1]
ZIG='/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig'
out=ROOT/'dist/memory';out.mkdir(parents=True,exist_ok=True)
common=[ZIG,'cc','-target','x86_64-windows-gnu','-O2']
subprocess.run(common+['-shared',str(ROOT/'native/memory/guarded_reads.c'),'-o',str(out/'goose-guarded.dll')],check=True)
subprocess.run(common+[str(ROOT/'native/memory/fixture.c'),'-o',str(out/'fixture.exe')],check=True)
env={**os.environ,'WINEDEBUG':'-all','WINEPREFIX':os.environ.get('GADGET_WINEPREFIX','/home/goose/Documents/ChatGPT/Linux HD2/native-work/bridge-terminal/wine-prefix')}
r=subprocess.run(['wine',str(out/'fixture.exe')],env=env,capture_output=True,text=True,timeout=30);assert r.returncode==0,r.stdout+r.stderr
blob=(out/'goose-guarded.dll').read_bytes();sha=hashlib.sha256(blob).hexdigest();name='guarded_reads_'+sha[:16]+'.dll';(ROOT/'native'/name).write_bytes(blob)
p=ROOT/'src/memory.lua';p.write_text(re.sub(r'guarded_reads_[0-9a-f]+\.dll',name,p.read_text()))
(out/'build.json').write_text(json.dumps({'file':name,'sha256':sha,'fixture':r.stdout.strip(),'read_only':True},indent=2)+'\n');print(r.stdout.strip());print(name)
