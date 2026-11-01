"""Pin the complete Steam registrar, callbacks, module helpers and language map."""
from pathlib import Path
import hashlib,json,struct,sys
from capstone.x86 import X86_OP_MEM,X86_OP_IMM,X86_REG_RIP
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    image=Image('early');want='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    assert hashlib.sha256(image.data).hexdigest()==want
    specs=[('connected',0x7f4500,0x7f453c,0x38),('client_running',0x7f4540,0x7f457c,0x40),
      ('overlay_active',0x7f4580,0x7f45bc,0x48),('user_id',0x7f45c0,0x7f4618,0x18),
      ('user_name',0x7f4620,0x7f4700,0x28),('language',0x7f4700,0x7f485c,0x50),
      ('is_installed',0x7f4860,0x7f48f5,0x70),('owns_app',0x7f4900,0x7f4998,0x98),
      ('install_event',0x7f49a0,0x7f4a02,0xa0),('app_id',0x7f4a10,0x7f4a50,0xa8),
      ('open_url',0x7f4a50,0x7f4abe,0xb0)]
    census=json.loads((ROOT.parent/'vm-trace/binding-inventory.json').read_text())['bindings']
    expected={r['name'].split('.',1)[1]:int(r['rva'],16) for r in census if r['name'].startswith('Steam.')}
    assert {name:a for name,a,_,_ in specs}==expected
    lines=['/* Generated local captured code for provenance/probes/reference tests. */'];rows=[]
    registrar=list(image.cs.disasm(image.data[0x7f4ac0:0x7f519d],0x7f4ac0))
    targets={i.address+i.size+o.mem.disp for i in registrar if i.mnemonic=='lea' for o in i.operands if o.type==X86_OP_MEM and o.mem.base==X86_REG_RIP}
    for name,start,end,slot in specs:
        assert start in targets
        instructions=list(image.cs.disasm(image.data[start:end],start))
        assert any(i.mnemonic=='call' and i.operands[0].type==X86_OP_MEM and i.operands[0].mem.disp==slot for i in instructions)
        rows.append({'name':name,'entry':hex(start),'end':hex(end),'vtable_slot':hex(slot),'sha256':hashlib.sha256(image.data[start:end]).hexdigest()})
    regions=[('registrar',0x7f4ac0,0x7f519d),('registry_module',0x4ece60,0x4ed005),('global_module',0x4ecc90,0x4ece51)]
    regions += [(n,a,b) for n,a,b,_ in specs]
    for name,a,b in regions:
        lines.append('static const unsigned char steam_'+name+'_witness[]={'+','.join(map(str,image.data[a:b]))+'};')
    lines.append('static const struct { uintptr_t rva;const unsigned char *bytes;size_t size; } steam_regions[]={')
    for name,a,b in regions:lines.append('{'+hex(a)+',steam_'+name+'_witness,sizeof(steam_'+name+'_witness)},')
    lines.append('};')
    languages=[];language_rvas=[]
    for i in range(20):
        pair=struct.unpack_from('<QQ',image.data,0x16f9e10+i*16)
        language_rvas.append([p-0x140000000 for p in pair])
        languages.append([image.data[p-0x140000000:].split(b'\0',1)[0].decode() for p in pair])
    lines.append('static const char *const steam_languages[][2]={'+','.join('{'+','.join(json.dumps(x) for x in pair)+'}' for pair in languages)+'};')
    lines.append('static const uintptr_t steam_language_rvas[][2]={'+','.join('{'+','.join(hex(x) for x in pair)+'}' for pair in language_rvas)+'};')
    (ROOT/'work/steam_witnesses.h').write_text('\n'.join(lines)+'\n')
    evidence={'capture':str(image.path),'capture_sha256':want,'registrar':{'entry':'0x7f4ac0','end':'0x7f519d'},
        'context_slot':'0x2860608','null_service':'store null and return without registering a module',
        'module':'registry Steam table with __index=self and _name=Steam, attached to stingray.Steam on first creation',
        'bindings':rows,'languages':languages,'fallback_language':'en',
        'conversions':{'user_id':'16 lowercase hexadecimal digits','user_name':'optional hexadecimal ID; no argument uses service user ID',
          'app_id':'signed int32 to Lua number','install_event':'nil if false; signed int32 ID otherwise',
          'app_argument':'Lua number/numeric string, truncate to signed int64 then low uint32; invalid conversion uses zero',
          'open_url':'Lua string/number conversion; other types pass null'},
        'invalid_user_name':'original unchecked sscanf leaves undefined data on bad input; replacement rejects unparseable IDs',
        'native_service_live_validated':False,'native_windows_tested':False}
    (ROOT/'steam-binding-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'bindings':len(rows),'language_codes':len(languages),'context_slot':evidence['context_slot']}))
if __name__=='__main__':prepare()
