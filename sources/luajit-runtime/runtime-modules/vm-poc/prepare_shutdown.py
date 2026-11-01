"""Pin native shutdown and prove safe replacement instruction boundaries."""
from pathlib import Path
import hashlib,json,sys
from capstone.x86 import X86_OP_IMM
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');want='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    assert hashlib.sha256(im.data).hexdigest()==want
    newpath=Path('/home/goose/Projects/Linux HD2 Mods/builds/26251122/runtime/images/exe-26251122.bin');new=newpath.read_bytes()
    assert hashlib.sha256(new).hexdigest()=='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    start,end=0x6cd510,0x6cd90b;code=im.data[start:end];assert code==new[start:end]
    ins={i.address:i for i in im.cs.disasm(code,start)};assert ins[end-1].mnemonic=='ret'
    patches=[('named_shutdown',0x6cd54d,0x6cd569),('full_collection',0x6cd569,0x6cd5fa),('threshold_store',0x6cd601,0x6cd605)]
    for _,a,b in patches:assert a in ins and b in ins
    for i in ins.values():
        if i.mnemonic.startswith('j') and i.operands[0].type==X86_OP_IMM:
            for _,a,b in patches:assert not (a<i.operands[0].imm<b and not a<=i.address<b),(hex(i.address),hex(i.operands[0].imm))
    calls={0x6cd564:0x4f03a0,0x6cd5a3:0x7a0f30,0x6cd5b1:0x7a0bc0,0x6cd5c3:0x7a0f30,0x6cd73a:0x1c4c30,
           0x6cd755:0x7d4530,0x6cd77f:0x7cb790,0x6cd801:0x7d09b0,0x6cd8a0:0x12aee70,0x6cd8b5:0x6cf010,
           0x6cd8ce:0x4ed4c0,0x6cd8da:0x602070,0x6cd8e6:0x602070,0x6cd8ef:0x602070}
    for at,target in calls.items():assert ins[at].mnemonic=='call' and ins[at].operands[0].imm==target
    assert ins[0x6cd5fa].mnemonic=='cmp' and ins[0x6cd601].mnemonic=='mov' and ins[0x6cd605].mnemonic=='je'
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
