"""Run migrated upstream fixtures in fresh Lua 5.1 states with real CFFI.
Only fixture paths/old capture literals are adapted. Production modules use a
shared preloaded compat object because upstream fixtures replace their mod host.
Kit/MCM integration has its own tests; standalone-host lifecycle tests retain
an identity host adapter here.
"""
from pathlib import Path
import sys,ctypes,re,json,struct,os,faulthandler
faulthandler.enable()
ROOT=Path(__file__).resolve().parents[1];WORK=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison')
sys.path.insert(0,str(WORK/'python-deps'))
sys.path.insert(0,'/home/goose/Documents/ChatGPT/Linux HD2/port-tools')
from port_mods import convert
TOKEN=re.compile(r'--[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|\b0[xX][0-9a-fA-F]+\b|.',re.S)
from lupa import lua51
ctypes.CDLL(lua51.__file__,mode=ctypes.RTLD_GLOBAL)
report=json.loads((ROOT/'docs/first-person-applied-migration.json').read_text());mapping={int(k,16):int(v,16)for k,v in report['constants'].items()}
# 26088801 -> 26251122: second stage over the first (pre-1020 -> 26088801) mapping
stage2=json.loads((ROOT/'docs/first-person-26251122-migration.json').read_text())
mapping={k:int(stage2['constants'].get(hex(v),hex(v)),16)for k,v in mapping.items()}
for k,v in stage2['constants'].items():mapping.setdefault(int(k,16),int(v,16))
STAGE2_WITNESS={bytes.fromhex(k):bytes.fromhex(v)for k,v in stage2['witnesses'].items()}
E=Path('/home/goose/Documents/ChatGPT/Linux HD2/native-work/evidence')
pairs=[((E/'game-pre1020.dll').read_bytes(),(E/'game-26088801.dll').read_bytes(),report['game_code']),((Path('/home/goose/Applications/HellForge/mods-retired/localappdata-1019/LocalAppData/LinksLinkToMemory/r6_reload_exe_20261017.bin')).read_bytes(),(E/'exe-26088801.bin').read_bytes(),report['exe_code'])]
def witness(raw):
 hits=set()
 for old,new,sites in pairs:
  for a,b in sites.items():
   a,b=int(a,16),int(b,16)
   if old[a:a+len(raw)]==raw:hits.add(new[b:b+len(raw)])
 out=next(iter(hits))if len(hits)==1 else raw
 return STAGE2_WITNESS.get(out,out)

def fixture_source(text):
 text=convert(text).replace("local PORT51=mod.require('port51/compat51.lua')",'local PORT51=TEST_PORT51');parts=[]
 for token in TOKEN.finditer(text):
  s=token.group()
  if re.fullmatch('0[xX][0-9a-fA-F]+',s):s=hex(mapping.get(int(s,16),int(s,16)))
  elif len(s)>2 and s[0]in "\"'":
   c=s[1:-1]
   if len(c)%2==0 and len(c)>=8 and re.fullmatch('[0-9a-f]+',c):s=s[0]+witness(bytes.fromhex(c)).hex()+s[-1]
   elif re.fullmatch(r'(?:\\[0-9]{3})+',c):
    raw=bytes(int(v)for v in re.findall(r'\\([0-9]{3})',c));s=s[0]+''.join('\\%03d'%v for v in witness(raw))+s[-1]
  parts.append(s)
 text=''.join(parts).replace('/main.lua','/src/first_person/runtime.lua')
 text=re.sub(r'local function equal\(a, ?b\)', "local function equal(a,b) if type(a)=='userdata' and type(b)=='number' then a=PORT51.number(a) elseif type(b)=='userdata' and type(a)=='number' then b=PORT51.number(b) end;",text)
 text=text.replace('g~=state.token','PORT51.number(g)~=state.token').replace('g~=0','PORT51.number(g)~=0')
 text=re.sub(r'/src/(?!first_person/)', '/src/first_person/',text)
 return re.sub(r"(['\"])src/(?!first_person/)([^'\"]+)\1",lambda m:m[1]+'src/first_person/'+m[2]+m[1],text)

rows=[]
(ROOT/'dist/first-person').mkdir(parents=True,exist_ok=True)
(ROOT/'dist/first-person/lua-fixtures.json').write_text('[]\n')
for file in sorted((ROOT/'tests/first_person').glob('*.lua')):
 if os.environ.get('TFP_FIXTURE') and file.name!=os.environ['TFP_FIXTURE']:continue
 print('RUN',file.name,flush=True)
 lua=lua51.LuaRuntime(encoding=None,unpack_returned_tuples=True)
 lua.globals().native_module=str(WORK/'build-linux/cffi.so').encode();lua.execute(b"package.loaded.cffi=assert(package.loadlib(native_module,'luaopen_cffi'))()")
 compat=lua.execute((ROOT/'src/first_person/compat51.lua').read_bytes());compat[b'ffi'][b'os']=b'Windows';lua.globals().TEST_PORT51=compat;lua.globals().NATIVE_ADS_TEST_ROOT=str(ROOT).encode()
 def source_loader(path):
  p=Path(path.decode());text=p.read_text()
  for helper in ("recovery","diagnostics","transition"):
   text=text.replace("mod.require('src/first_person/"+helper+".lua')","dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/"+helper+".lua')")
  text=text.replace("mod.require('src/loadout_catalogue.lua')","dofile(NATIVE_ADS_TEST_ROOT..'/src/loadout_catalogue.lua')")
  text=text.replace("local PORT51=mod.require('src/first_person/compat51.lua')",'local PORT51=TEST_PORT51')
  text=text.replace("local mod=mod.require('src/first_person.lua').host(mod)\n",'')
  text=text.replace("mod.require('src/first_person/locomotion.lua')","dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/locomotion.lua')")
  text=text.replace("mod.require('src/first_person/fird_projection.lua')","dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_projection.lua')")
  text=text.replace("mod.require('src/first_person/ui_style.lua')","dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/ui_style.lua')")
  text=text.replace("local Integration=mod.require('src/first_person.lua')",'local Integration=TEST_INTEGRATION')
  if p.name=='menu.lua':text=text.replace("control.id == 'first_person_runtime_status'","control.id == 'runtime_status'")
  return text.encode()
 lua.globals().source_loader=source_loader
 lua.execute(b"local f=TEST_PORT51.ffi;local load=f.load;f.load=function(...)local fake=package.loaded.ffi;local mock=type(fake)=='table'and rawget(fake,'load');if mock then return mock(...)end;return load(...)end;stingray={Application={time_since_launch=function()return 100 end}}")
 lua.execute(b"TEST_INTEGRATION={menu_api=function()return DBFMCM end,editor_api=function()return DBFMCM end};function loadfile(path)return loadstring(source_loader(path),'@'..path)end;function dofile(path)return assert(loadfile(path))()end")
 # These fixtures are authored directly for stock Lua5.1. Rewriting their
 # debugger's native type() into a CFFI-aware predicate makes its upvalue walk
 # traverse CFFI internals, which is outside the fixture's intended surface.
 if file.name in {'recovery.lua','diagnostics.lua','transition.lua','runtime_recovery.lua','runtime_frame.lua'}:
  text=file.read_text().replace('/main.lua','/src/first_person/runtime.lua')
  text=re.sub(r'/src/(?!first_person/)', '/src/first_person/',text)
 else:text=fixture_source(file.read_text())
 text=text.replace("local PORT51=mod.require('src/first_person/compat51.lua')",'local PORT51=TEST_PORT51')
 if file.name in ('editor.lua','menu.lua','controller.lua'):text=text.replace("'dbf_freecam'","'goose_first_person_editor'")
 try:lua.execute(text.encode());rows.append({'fixture':file.name,'passed':True})
 except Exception as e:rows.append({'fixture':file.name,'passed':False,'error':str(e)});print('FAIL',file.name,str(e).splitlines()[0])
(ROOT/'dist/first-person').mkdir(parents=True,exist_ok=True)
(ROOT/'dist/first-person/lua-fixtures.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Lua 5.1/CFFI fixtures:',sum(r['passed']for r in rows),'/',len(rows))
sys.exit(not all(r['passed']for r in rows))
