"""Prepare pinned frame-caller witnesses for offline native routing tests."""
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
    specs=[('update',0x6ce6e0,0x6ce7e5,0x6ce724,0x6ce7ce),
           ('render',0x6ce7f0,0x6ce850,0x6ce7f4,0x6ce830)]
    calls={0x6ce717:0x6741e0,0x6ce71f:0x7fae50,0x6ce761:0x5eb340,
           0x6ce7c9:0x4f0470,0x6ce7e0:0x618d0,0x6ce82b:0x4f0470}
    lines=['/* Local captured engine code; not a redistributable game package. */']
    rows=[]
    for name,start,end,patch,resume in specs:
        code=image.data[start:end]
        decoded={i.address:i for i in image.cs.disasm(code,start)}
        assert patch in decoded and resume in decoded
        for at,target in calls.items():
            if start<=at<end:
                i=decoded[at]
                assert i.mnemonic in ('call','jmp') and i.operands[0].type==X86_OP_IMM and i.operands[0].imm==target
        lines.append('static const unsigned char frame_'+name+'_witness[] = {'+','.join(str(x) for x in code)+'};')
        rows.append({'name':name,'entry':hex(start),'end':hex(end),'patch':hex(patch),'resume':hex(resume),
                     'sha256':hashlib.sha256(code).hexdigest(),
                     'native_calls':{hex(a):hex(t) for a,t in calls.items() if start<=a<end}})
    work=ROOT/'work';work.mkdir(exist_ok=True)
    (work/'frame_witnesses.h').write_text('\n'.join(lines)+'\n')
    receipt={'capture':str(image.path),'capture_sha256':want,'callers':rows,
             'environment_in_game_offset':'0x190',
             'gc_context_in_environment_offset':'0x100148',
             'update_arguments':'RCX game, XMM1 float dt; preserved in RDI/XMM6 at patch boundary',
             'render_arguments':'RCX game at patch boundary',
             'gc_policy':'Original timed scheduler policy ported through gc_policy; pinned runtime estimates and public GC APIs replace PUC internals; native settings/profiler wiring remains',
             'surrounding_native_hooks':'Preserved machine instructions; transitive hook bodies not validated by fixture',
             'live_game_installable':False,'reason':'Early installation, error TLS, remaining callers and bindings incomplete; captured lifecycle, boot and shutdown routes are separate proofs'}
    (ROOT/'frame-route-evidence.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'callers':len(rows),'confirmed_calls_and_tail_calls':len(calls),'live_game_installable':False}))


if __name__=='__main__':prepare()
