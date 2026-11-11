"""Pin native shutdown and prove safe replacement instruction boundaries."""
from pathlib import Path
import hashlib,json,sys
from capstone.x86 import X86_OP_IMM
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');want='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    assert hashlib.sha256(im.data).hexdigest()==want
    newpath=Path('/home/goose/Projects/Linux HD2 Mods/builds/26568081/runtime/images/exe-26568081.bin');new=newpath.read_bytes()
    assert hashlib.sha256(new).hexdigest()=='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    start,end=0x6cd4a0,0x6cd89b;code=im.data[start:end];assert code==new[start:end]
    ins={i.address:i for i in im.cs.disasm(code,start)};assert ins[end-1].mnemonic=='ret'
    patches=[('named_shutdown',0x6cd4dd,0x6cd4f9),('full_collection',0x6cd4f9,0x6cd58a),('threshold_store',0x6cd591,0x6cd595)]
    for _,a,b in patches:assert a in ins and b in ins
    for i in ins.values():
        if i.mnemonic.startswith('j') and i.operands[0].type==X86_OP_IMM:
            for _,a,b in patches:assert not (a<i.operands[0].imm<b and not a<=i.address<b),(hex(i.address),hex(i.operands[0].imm))
    calls={0x6cd4f4:0x4f0470,0x6cd533:0x7a0f80,0x6cd541:0x7a0c10,0x6cd553:0x7a0f80,0x6cd6ca:0x1c4ce0,
           0x6cd6e5:0x7d47d0,0x6cd70f:0x7cba30,0x6cd791:0x7d0c50,0x6cd830:0x12af030,0x6cd845:0x6cf0d0,
           0x6cd85e:0x4ed590,0x6cd86a:0x602110,0x6cd876:0x602110,0x6cd87f:0x602110}
    for at,target in calls.items():assert ins[at].mnemonic=='call' and ins[at].operands[0].imm==target
    assert ins[0x6cd58a].mnemonic=='cmp' and ins[0x6cd591].mnemonic=='mov' and ins[0x6cd595].mnemonic=='je'
    (ROOT/'work/shutdown_witnesses.h').write_text('/* Pinned local captured game destructor. */\nstatic const unsigned char shutdown_game_witness[]={'+','.join(map(str,code))+'};\n')
    evidence={'capture':str(im.path),'capture_sha256':want,'newer_capture':str(newpath),'newer_capture_sha256':hashlib.sha256(new).hexdigest(),
        'function':{'entry':hex(start),'end':hex(end),'size':len(code),'sha256':hashlib.sha256(code).hexdigest(),'same_in_both_captures':True},
        'patches':[{'name':n,'start':hex(a),'end':hex(b),'size':b-a} for n,a,b in patches],
        'calls':{hex(a):hex(b) for a,b in calls.items()},'branch_edges':'no original branch enters the interior of a replacement from outside it',
        'preserved':'game vtable, native hook condition flags, plugin/handle/service cleanup, zeroed globals, mutex/buffer/allocator cleanup and native environment destruction',
        'replacement':'associated Lua shutdown callback, protected public lua_gc(LUA_GCCOLLECT), no writes to old PUC state or collector fields',
        'errors':'Lua shutdown errors are reported then cleanup continues; propagated collection errors and invalid/recursive sequencing use factory fatal handler before native service teardown',
        'finalizer_errors':'pinned LuaJIT handles ERRFIN and continues; PUC reference propagates into protected collection and fails before native cleanup',
        'remaining':'early loader, complete registrars/plugin VM API, resources, original TLS/error context and native GC settings/profiler wiring; no native Windows or game acceptance',
        'in_game_vm_replaced':False,'native_windows_tested':False}
    (ROOT/'shutdown-route-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'guard_bytes':len(code),'patches':len(patches),'known_direct_calls':len(calls)}))
if __name__=='__main__':prepare()
