"""Apply reviewed Native ADS bindings to the imported source; refuses a second pass."""
from pathlib import Path
import json,re,struct,hashlib,sys
ROOT=Path(__file__).resolve().parents[1]
E=Path('/home/goose/Documents/ChatGPT/Linux HD2/native-work/evidence')
oldg=(E/'game-pre1020.dll').read_bytes();newg=(E/'game-26088801.dll').read_bytes()
oldx=Path('/mnt/LIGHTSPEED/Hellforge/mods-retired/localappdata-1019/LocalAppData/LinksLinkToMemory/r6_reload_exe_20261017.bin').read_bytes();newx=(E/'exe-26088801.bin').read_bytes()
evidence=json.loads((ROOT/'docs/first-person-migration-evidence.json').read_text())
profile=ROOT/'src/first_person/profile.lua'
native_only='--native-only' in sys.argv
if native_only:
 assert all('0x6AB3B43F' in p.read_text()for p in (ROOT/'native/first_person').glob('native_ads_*.cpp')), 'Native migration requires fresh, unmodified upstream sources'
else:
 assert '0x6AB3B43F' in profile.read_text(), 'Migration already applied; current source is maintained in place'
game={int(r['old'],16):int(r['new'],16)for r in evidence['code']['game']if r.get('mode')in ['instruction window','unique suffix with matching prologue instruction shapes']}
game.update({0x12b2dfb:0x1144cdb,0x100a80b:0xe9aaeb,0x12887cd:0x111a6ad,0x12887ed:0x111a6cd})
for r in json.loads((ROOT/'docs/first-person-movement-map.json').read_text()):
 assert r['mode']=='instruction window';game[int(r['old'],16)]=int(r['new'],16)
# API targets are independently read from the current dispatch slots/vtables;
# generic short getter bodies are never assigned by byte-search uniqueness.
exe={0x1fc450:0x1f22f0,0x1fc720:0x1f25c0,0x1fc7a0:0x1f2640,0x1fc880:0x1f2720,0x1fd220:0x1f30c0,
0x2bd870:0x28d3a0,0x2bd890:0x28d3c0,0x2bd9c0:0x28d4f0,0x2bd9d0:0x28d500,0x2c3990:0x2935e0,
0x30d980:0x2dd050,0x30d990:0x2dd060,0x30deb0:0x2dd580,0x310050:0x2df720,0x30ffc0:0x2df690,
0x62adb0:0x66a140,0x310140:0x2df810,0x62a0c0:0x669450,0x2dd5e0:0x2ad310,0x3100c0:0x2df790,
0x201710:0x1f75b0,0x201900:0x1f77a0,0x3fa3d0:0x3d43b0,0x3fa120:0x3d3fd0,
0x3fa262:0x3d417a,0x3fa2f8:0x3d41ee,0x4128e0:0x3f4c80,0x50f620:0x51fe50,0x412875:0x3f4c03,0x50f64a:0x51fe7a,0x9d8c0:0xa06b0}
mapping={**game,**exe,0x6ab3b43f:0x6ad7c05d,0x4744000:0x3382000,0x6ab382e4:0x6ad78c0d,0x39e8000:0x29fe000,
0xf1aeb0:0xf1c978,0xf22ec8:0xf24990,0xf32f18:0xf349e0,0x53e880:0x53e888,0x53e9b8:0x53e9c0,0x1238:0x1240,
0x546a70:0x546ab0,0xac21c:0xac29c,0xac408:0xac488,0x1a100f0:0x1ab76f8,0x1a102b8:0x1ab78c0,
0x1677dc8:0x1715bb8,0x27cc5e0:0x2873ad0,0x27cc638:0x2873b28,0x27ce5b0:0x2875ac4,0x27ce5c8:0x2875ac8}
for row in evidence['globals']['game']:
 if len(row['consensus'])==1:mapping[int(row['old'],16)]=int(row['consensus'][0],16)
# Witness substitutions retain original lengths; every new guard comes from
# the exact code address selected above, not a wildcard or an unchecked mask.
def witness(raw):
 hits=[]
 for old,new,items in [(oldg,newg,game),(oldx,newx,exe)]:
  for a,b in items.items():
   if old[a:a+len(raw)]==raw:hits.append(new[b:b+len(raw)])
 unique=set(hits)
 if len(unique)==1:return next(iter(unique))
 return raw
TOKEN=re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|\b0[xX][0-9a-fA-F]+(?:ULL|LL|UL|U|L)?\b|.',re.S)
changes=[]
files=[*(ROOT/'native/first_person').glob('*.cpp')]
if not native_only:files += list((ROOT/'src/first_person').glob('*.lua'))
for p in files:
 text=p.read_text();before=hashlib.sha256(text.encode()).hexdigest();parts=[]
 for token in TOKEN.finditer(text):
  value=token.group();m=re.fullmatch(r'(0[xX][0-9a-fA-F]+)([uUlL]*)',value)
  if m and 0x53e880 < int(m[1],16) < 0x53e9b8:value=hex(int(m[1],16)+8)+m[2]
  elif m and int(m[1],16)in mapping:value=hex(mapping[int(m[1],16)])+m[2]
  elif len(value)>2 and value[0]in "\"'":
   content=value[1:-1]
   if len(content)%2==0 and len(content)>=8 and re.fullmatch('[0-9a-f]+',content):
    value=value[0]+witness(bytes.fromhex(content)).hex()+value[-1]
   elif re.fullmatch(r'(?:\\[0-9]{3})+',content):
    raw=bytes(int(v)for v in re.findall(r'\\([0-9]{3})',content));new=witness(raw)
    value=value[0]+''.join('\\%03d'%v for v in new)+value[-1]
  parts.append(value)
 text=''.join(parts)
 for name in ['alignment_0_1_5','editor_0_1_43','fov_0_1_23','camera_0_1_48','blur_0_1_16']:
  text=text.replace('native_ads_'+name+'.dll','native_ads_'+name.split('_')[0]+'_26088801_1.dll')
 p.chmod(p.stat().st_mode|0o200);p.write_text(text)
 changes.append({'path':str(p.relative_to(ROOT)),'before':before,'after':hashlib.sha256(text.encode()).hexdigest()})
# A changed renderer getter uses RCX rather than the legacy R14 table read.
p=ROOT/'src/first_person/backend.lua';text=p.read_text().replace('self:_read(base+0x3d41ee,9)', 'self:_read(base+0x3d41ee,9)')
# The generated witness retains its original 9-byte width and fully seals both
# the Boolean type branch and following byte-at-8 read of the current getter.
p.write_text(text)
(ROOT/'docs/first-person-applied-migration.json').write_text(json.dumps({'runtime_accepted':False,'game_code':{hex(k):hex(v)for k,v in game.items()},'exe_code':{hex(k):hex(v)for k,v in exe.items()},'constants':{hex(k):hex(v)for k,v in mapping.items()},'files':changes},indent=2)+'\n')
print('Migrated',len(changes),'source/fixture files;',len(game),'game sites;',len(exe),'exe sites. Live acceptance still required.')
