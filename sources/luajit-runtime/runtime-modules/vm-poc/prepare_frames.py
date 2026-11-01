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
    want='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    assert hashlib.sha256(image.data).hexdigest()==want
    specs=[('update',0x6ce620,0x6ce725,0x6ce664,0x6ce70e),
           ('render',0x6ce730,0x6ce790,0x6ce734,0x6ce770)]
    calls={0x6ce657:0x674100,0x6ce65f:0x7fad60,0x6ce6a1:0x5eb2b0,
           0x6ce709:0x4f03a0,0x6ce720:0x61840,0x6ce76b:0x4f03a0}
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
