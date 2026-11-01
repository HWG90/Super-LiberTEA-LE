"""Reproduce evidence for Native ADS migration. Does not activate or install anything."""
from pathlib import Path
import sys,re,struct,bisect,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=Path('/home/goose/Documents/ChatGPT/Linux HD2/native-work')
sys.path.insert(0,str(EVIDENCE))
import bindiff as d
from capstone.x86 import X86_OP_MEM,X86_REG_RIP
old_game,new_game=d.old,d.new
old_exe=Path('/mnt/LIGHTSPEED/Hellforge/mods-retired/localappdata-1019/LocalAppData/LinksLinkToMemory/r6_reload_exe_20261017.bin').read_bytes()
new_exe=(EVIDENCE/'evidence/exe-26088801.bin').read_bytes()
def select(kind):
 old,new=(old_game,new_game)if kind=='game'else(old_exe,new_exe)
 d.old,d.new=old,new;d.old_functions=d.functions(old);d.old_starts=[a for a,b in d.old_functions]
 d.new_functions=d.functions(new)if kind=='exe'else[struct.unpack_from('<III',(EVIDENCE/'evidence/game-26088801.pdata').read_bytes(),i)[:2]for i in range(0,(EVIDENCE/'evidence/game-26088801.pdata').stat().st_size,12)]
 pe=struct.unpack_from('<I',new,60)[0];n=struct.unpack_from('<H',new,pe+6)[0];opt=struct.unpack_from('<H',new,pe+20)[0];end=0
 for i in range(n):
  at=pe+24+opt+i*40
  if struct.unpack_from('<I',new,at+36)[0]&0x20000000:
   size,rva=struct.unpack_from('<II',new,at+8);end=max(end,rva+size)
 d.new_starts={a for a,b in d.new_functions if 0x1000<=a<b<=end};d.new_start_list=sorted(d.new_starts);d.code=new[0x1000:end]
 return old,new

def migrate(at):
 row=d.migrate(at)
 if row.get('mode')!='instruction window':
  # A changed prologue can be proven by a unique suffix and identical
  # instruction lengths before the suffix. Never infer arbitrary interior RVAs.
  for delta in [1,2,3,4,5,6,8,10,16]:
   sub=d.migrate(at+delta)
   if sub.get('mode')!='instruction window':continue
   target=int(sub['new'],16)-delta
   before=list(d.cs.disasm(d.old[at:at+delta],at));after=list(d.cs.disasm(d.new[target:target+delta],target))
   if sum(i.size for i in before)==delta and [(i.mnemonic,i.size)for i in before]==[(i.mnemonic,i.size)for i in after]:
    row={**sub,'old':hex(at),'new':hex(target),'mode':'unique suffix with matching prologue instruction shapes','suffix_delta':delta};break
 return row

result={'runtime_accepted':False,'images':{},'code':{},'globals':{},'fields':{}}
code={
'game':[0x127ddb0,0x127de20,0x127e9d0,0x1286330,0x12b29b0,0x12b2ae0,0x12b26a0,0x12b28a3,0xa41c0b,0x12b2d20,0x12b2dfb,0x12887c9,0x12887e9,0x1288420,0x12890db,0x1287a41,0x127a135,0x127a11a,0x127a127,0x100a80b,0x12873b3,0x12873d9,0x1287a91,0x1287b43,0x1287c04,0x1286335,0x128878b,0x12887d4],
'exe':[0x1fc720,0x1fc880,0x1fc7a0,0x1fc450,0x1fd220,0x2bd870,0x2bd890,0x2bd9c0,0x2bd9d0,0x2c3990,0x30d980,0x30d990,0x30deb0,0x310050,0x30ffc0,0x62adb0,0x310140,0x62a0c0,0x201710,0x201900,0x3fa3d0,0x3fa120,0x3fa262,0x3fa2f8,0x4128e0,0x50f620,0x412875,0x50f64a,0x9d8c0]}
globals_by_kind={'game':[0x3326308,0x3326340,0x3326420,0x3326468,0x3326a38,0x3326ce0,0x3326cf8,0x3326d20,0x346bf98,0x346d560,0x347ce70,0x3752c98], 'exe':[0x1a100f0,0x1a102b8,0x27ce5b0,0x27ce5c8]}
fields=[0xf1aeb0,0xf22ec8,0xf32f18,0x53e880,0x53e9b8,0x546a70,0xac21c,0xac408,0xf12bd8,0x1238,0x1b8]
for kind in ['game','exe']:
 old,new=select(kind)
 result['images'][kind]={'old_sha256':hashlib.sha256(old).hexdigest(),'new_sha256':hashlib.sha256(new).hexdigest()}
 result['code'][kind]=[migrate(v)for v in code[kind]]
 refs={v:[]for v in globals_by_kind[kind]}
 for m in re.finditer(b'[\x48\x4c][\x8b\x8d\x89\x3b][\x05\x0d\x15\x1d\x25\x2d\x35\x3d]....',old[:0x2111000 if kind=='game'else 0x900000],re.S):
  at=m.start();target=at+7+struct.unpack_from('<i',old,at+3)[0]
  if target in refs:refs[target].append(at)
 result['globals'][kind]=[]
 for target,sites in refs.items():
  proofs=[];new_sites=set()
  for at in sites:
   row=d.migrate(at)
   if row.get('mode')!='instruction window':continue
   found=int(row['new'],16)
   if found in new_sites:continue
   ins=next(d.cs.disasm(new[found:found+15],found),None)
   if not ins or ins.size!=7 or not any(op.type==X86_OP_MEM and op.mem.base==X86_REG_RIP for op in ins.operands):continue
   new_sites.add(found);row['new_global']=hex(found+7+struct.unpack_from('<i',new,found+3)[0]);proofs.append(row)
   if len(proofs)>=4:break
  candidates=sorted({r['new_global']for r in proofs});result['globals'][kind].append({'old':hex(target),'consensus':candidates,'proofs':proofs})
 if kind=='game':
  for field in fields:
   proofs=[];needle=struct.pack('<I',field);pos=0
   while len(proofs)<8:
    at=old.find(needle,pos,0x2111000)
    if at<0:break
    pos=at+1
    for begin in range(max(0,at-8),at):
     ins=next(d.cs.disasm(old[begin:begin+15],begin),None)
     if not ins or ins.disp_size!=4 or begin+ins.disp_offset!=at or not any(op.type==X86_OP_MEM and op.mem.disp==field for op in ins.operands):continue
     row=d.migrate(begin)
     if row.get('mode')=='instruction window':
      found=int(row['new'],16);ni=next(d.cs.disasm(new[found:found+15],found),None)
      if ni and ni.mnemonic==ins.mnemonic and ni.disp_size==4:
       row['new_field']=hex(struct.unpack_from('<I',ni.bytes,ni.disp_offset)[0]);row['old_instruction']=ins.mnemonic+' '+ins.op_str;row['new_instruction']=ni.mnemonic+' '+ni.op_str;proofs.append(row)
     break
   result['fields'][hex(field)]={'consensus':sorted({r['new_field']for r in proofs}),'proofs':proofs}
path=ROOT/'docs/first-person-migration-evidence.json';path.write_text(json.dumps(result,indent=2)+'\n')
for kind,rows in result['code'].items():
 print(kind,'code',[(r['old'],r.get('new'),r.get('mode'))for r in rows])
for kind,rows in result['globals'].items():print(kind,'globals',[(r['old'],r['consensus'])for r in rows])
print('fields',[(k,v['consensus'])for k,v in result['fields'].items()])
