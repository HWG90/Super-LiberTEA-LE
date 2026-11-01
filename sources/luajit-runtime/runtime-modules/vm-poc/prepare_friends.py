"""Pin Friends/Presence registration, callback bodies and native helper boundaries."""
from pathlib import Path
import hashlib,json,struct,sys
from capstone.x86 import X86_OP_MEM,X86_OP_REG,X86_OP_IMM,X86_REG_RIP,X86_REG_RAX,X86_REG_RDX
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');digest=hashlib.sha256(im.data).hexdigest()
    assert digest=='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    specs=[('num_friends',0x7ef620,0x7ef6e4),('id',0x7ef6f0,0x7ef7d1),('name',0x7ef7e0,0x7ef894),
      ('relationship',0x7ef8a0,0x7ef956),('status',0x7ef960,0x7efa16),('in_category',0x7efa20,0x7efb41),
      ('playing_game',0x7efb50,0x7eff35),('invite',0x7eff40,0x7f0466),('next_invite',0x7f0470,0x7f05e6),
      ('boot_invite',0x7f05f0,0x7f06eb),('advertise_playing',0x7f06f0,0x7f0bb4),
      ('stop_advertise_playing',0x7f0bc0,0x7f0bee),('set_presence',0x7f0bf0,0x7f0cce),('presence',0x7f0cd0,0x7f0e02)]
    helpers=[('native_name',0x7cb9b0,0x7cba23),('native_playing',0x7cbe70,0x7cbfbb),
      ('native_invite_lobby',0x7cc020,0x7cc323),('native_invite_server',0x7cc330,0x7cc633),
      ('native_next_invite',0x7cc690,0x7cc73a),('native_advertise_lobby',0x7ce390,0x7ce683),
      ('native_advertise_server',0x7ce690,0x7ce983)]
    instructions=list(im.cs.disasm(im.data[0x7f0e10:0x7f20f3],0x7f0e10))
    targets={i.address+i.size+o.mem.disp for i in instructions if i.mnemonic=='lea' for o in i.operands if o.type==X86_OP_MEM and o.mem.base==X86_REG_RIP}
    census=json.loads((ROOT.parent/'vm-trace/binding-inventory.json').read_text())['bindings']
    expected={r['name'].split('.',1)[1]:int(r['rva'],16) for r in census if r['name'].startswith(('Friends.','Presence.'))}
    assert expected=={n:a for n,a,_ in specs}
    for _,a,b in specs+helpers:
        body=list(im.cs.disasm(im.data[a:b],a))
        assert any(im.data[a:a+16]) and body[-1].address+body[-1].size==b
        assert body[-1].mnemonic=='ret' or (body[-1].mnemonic=='jmp' and a<=body[-1].operands[0].imm<b)
    assert all(a in targets for _,a,_ in specs)
    # Recover constants from the actual registrar's immediate register values.
    registers={};name=None;constants=[]
    for i in instructions:
        o=i.operands
        if i.mnemonic in ('mov','movabs') and len(o)==2 and o[0].type==X86_OP_REG and o[1].type==X86_OP_IMM:
            registers[o[0].reg]=o[1].imm
        if i.mnemonic=='lea' and len(o)==2 and o[0].type==X86_OP_REG and o[0].reg==X86_REG_RDX and o[1].type==X86_OP_MEM and o[1].mem.base==X86_REG_RIP:
            at=i.address+i.size+o[1].mem.disp;raw=im.data[at:at+80].split(b'\0')[0]
            if raw and all(32<=c<127 for c in raw):name=raw.decode()
        if i.address>=0x7f16b0 and i.mnemonic=='mov' and o[0].type==X86_OP_MEM and o[0].mem.base==X86_REG_RAX and o[0].mem.disp==0:
            n=registers[o[1].reg] if o[1].type==X86_OP_REG else o[1].imm
            value=struct.unpack('<d',struct.pack('<Q',n&0xffffffffffffffff))[0]
            assert name and value.is_integer()
            constants.append({'name':name,'value':int(value),'store':hex(i.address)})
    assert len(constants)==28 and len({r['name'] for r in constants})==28
    regions=[('registrar',0x7f0e10,0x7f20f3),('registry_module',0x4ece60,0x4ed005),('global_module',0x4ecc90,0x4ece51)]+specs+helpers
    lines=['/* Generated from the pinned local mapped capture. */']
    for name,a,b in regions:lines.append('static const unsigned char friends_'+name+'_witness[]={'+','.join(map(str,im.data[a:b]))+'};')
    lines.append('static const struct {uintptr_t rva;const unsigned char *bytes;size_t size;} friends_regions[]={')
    for name,a,b in regions:lines.append('{'+hex(a)+',friends_'+name+'_witness,sizeof(friends_'+name+'_witness)},')
    lines.append('};')
    lines.append('static const struct {const char *name;int value;} friends_constants[]={'+','.join('{'+json.dumps(r['name'])+','+str(r['value'])+'}' for r in constants)+'};')
    (ROOT/'work/friends_witnesses.h').write_text('\n'.join(lines)+'\n')
    evidence={'capture':str(im.path),'capture_sha256':digest,'registrar':{'entry':'0x7f0e10','end':'0x7f20f3'},
      'context_slot':'0x28605f0','interface_getter_iat':'0x148e7b8','interface_context':'0x19b65a0',
      'bindings':[{'name':('Friends.' if k<10 else 'Presence.')+n,'entry':hex(a),'end':hex(b),'sha256':hashlib.sha256(im.data[a:b]).hexdigest()} for k,(n,a,b) in enumerate(specs)],
      'native_helpers':[{'name':n,'entry':hex(a),'end':hex(b),'sha256':hashlib.sha256(im.data[a:b]).hexdigest()} for n,a,b in helpers],
      'constants':constants,'null_service':'store null, leave Lua modules untouched',
      'modules':'registry Friends and Presence tables, __index=self and _name, attached to stingray on first creation',
      'native_layouts':{'selected_category':'service+0xc0 int32; num_friends sets it, id reads it',
        'playing_game':'36 bytes: mod flag+0, signed app ID+4, native mod ID+8, lobby flag+12 and ID+16, server flag+24, IPv4+28, uint16 ports+32/+34',
        'next_invite':'16-byte-aligned 96-byte native result; kind+0, lobby+8, IPv4+16, signed port+20, sender+24, text+64 (32 bytes)',
        'boot_invite':'32 bytes at service+0xe8; same kind/lobby/address fields, no pop',
        'SteamLobby':'metatable identity plus native pointer in first 8 userdata bytes; native object lobby ID+0x178'},
      'parity_details':['playing_game false and absent/empty Presence.presence return zero values',
        'playing_game mod_id repeats app_id in captured Lua callback, despite separate native mod field',
        'all-hex destination means lobby; other strings use partial base-0 IPv4:port scan with zero defaults',
        'optional invite/presence strings default to empty for values other than string/number'],
      'native_service_live_validated':False,'native_windows_tested':False}
    (ROOT/'friends-binding-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'callbacks':len(specs),'constants':len(constants),'native_helpers':len(helpers)}))
if __name__=='__main__':prepare()
