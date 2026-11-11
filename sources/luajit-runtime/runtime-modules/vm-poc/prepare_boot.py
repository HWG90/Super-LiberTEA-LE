"""Guard the native boot split against the pinned mapped capture."""
from pathlib import Path
import hashlib
import json
import sys
from capstone.x86 import X86_OP_IMM
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    image=Image('early')
    want='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    assert hashlib.sha256(image.data).hexdigest()==want
    start,end=0x6cded0,0x6ce6db
    code=image.data[start:end];ins={i.address:i for i in image.cs.disasm(code,start)}
    calls={0x6ce0ac:0x2a35e0,0x6ce11c:0x7f4d70,0x6ce12b:0x7f7550,0x6ce136:0x7eb7c0,
           0x6ce13e:0x7f9740,0x6ce161:0x7edd70,0x6ce16c:0x7f10c0,0x6ce17b:0x7f3e50}
    spans=[(0x6cdf0d,0x6cdf52),*[(a,a+5) for a in calls],(0x6ce250,0x6ce44d),
           (0x6ce578,0x6ce581),(0x6ce581,0x6ce6b9),(0x6ce6c1,0x6ce6c5)]
    for a,b in spans: assert a in ins and b in ins and b-a<=512
    for at,target in calls.items():
        i=ins[at];assert i.mnemonic=='call' and i.size==5 and i.operands[0].type==X86_OP_IMM and i.operands[0].imm==target
    assert ins[0x6ce256].op_str=='byte ptr [rip + 0x14ecb25], cl'
    assert ins[0x6ce6d4].mnemonic=='ret' and ins[0x6ce6da].mnemonic=='int3'
    # Every external branch into replaced interiors must have an explicit
    # preserved entry (the missing-key path lands three bytes into its patch).
    for at,i in ins.items():
        if i.mnemonic.startswith('j') and i.operands[0].type==X86_OP_IMM:
            target=i.operands[0].imm
            for a,b in spans:
                if not a<=at<b and a<target<b: assert target==0x6ce57b
    (ROOT/'work/boot_witnesses.h').write_text('/* Local captured boot code, not a redistributable game package. */\n'
        +'static const unsigned char boot_witness[] = {'+','.join(map(str,code))+'};\n')
    evidence={'capture':str(image.path),'capture_sha256':want,'entry':hex(start),'end':hex(end),
        'function_sha256':hashlib.sha256(code).hexdigest(),'patches':[(hex(a),hex(b)) for a,b in spans],
        'registration_calls':{hex(a):hex(b) for a,b in calls.items()},
        'kept':'native allocator/global initialization, native API setup helper, plugin setup, binary-config boot_script selection, epilogue',
        'replaced':'PUC stack accesses, eight PUC registrars, dynamic-config globals, require/init, PUC LuaObject error path',
        'config':'live 0x38-byte rows; value tags 1 boolean, 2 double narrowed to float; deleted and other tags skipped',
        'registration_parity':False,'live_game_installable':False,
        'remaining':'real native registration adapters and plugin VM interface, early installation, timed GC, TLS/errors, native resources'}
    (ROOT/'boot-route-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'patches':len(spans),'registrars':len(calls),'live_game_installable':False}))
if __name__=='__main__':prepare()
