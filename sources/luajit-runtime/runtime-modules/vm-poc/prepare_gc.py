"""Pin the timed collector and its forwarding entry; no game memory changes."""
from pathlib import Path
import hashlib,json,struct,sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');new=Image('exe')
    assert hashlib.sha256(im.data).hexdigest()=='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    assert hashlib.sha256(new.data).hexdigest()=='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    spans={'caller':(0x5eb340,0x5eb566),'forward':(0x6cd170,0x6cd17c),'settings':(0x174dab0,0x174dac0),'maximum':(0x174d74c,0x174d750)}
    header=[];functions={}
    for name,(start,end) in spans.items():
        code=im.data[start:end];assert code==new.data[start:end]
        functions[name]={'start':hex(start),'end':hex(end),'sha256':hashlib.sha256(code).hexdigest(),'size':len(code)}
        header.append('static const unsigned char gc_'+name+'_witness[]={'+','.join(map(str,code))+'};')
    ins={i.address:i for i in im.cs.disasm(im.data[0x5eb340:0x5eb566],0x5eb340)}
    assert 0x5eb34c in ins and ins[0x5eb565].mnemonic=='ret'
    calls={0x5eb38b:0x74d70,0x5eb39e:0x74d70,0x5eb403:0x74d70,0x5eb420:0x797ea0,0x5eb479:0x74d70,0x5eb503:0x7a1180}
    for at,target in calls.items():assert ins[at].mnemonic=='call' and ins[at].operands[0].imm==target
    defaults=[*struct.unpack_from('<4f',im.data,0x174dab0),struct.unpack_from('<f',im.data,0x174d74c)[0]]
    assert defaults==[struct.unpack('<f',struct.pack('<f',.1))[0],.5,1,0,10]
    (ROOT/'work/gc_witnesses.h').write_text('/* Pinned local timed GC witnesses. */\n'+'\n'.join(header)+'\n')
    evidence={'capture':str(im.path),'capture_sha256':hashlib.sha256(im.data).hexdigest(),'newer_capture':str(new.path),'newer_capture_sha256':hashlib.sha256(new.data).hexdigest(),
        'functions':functions,'same_in_both_captures':True,'settings':dict(zip(['start_growth','growth_range','full_growth','min_ms','max_ms'],defaults)),
        'wrapper':'0x6cd170 adds 0x100148 to native environment and tail-calls 0x5eb340',
        'history':'peak/previous_peak at +8/+12, floor/previous_floor at +16/+20; cycle saves current then resets peak=0,floor=INT_MAX',
        'growth':'max(current_peak,previous_peak)/min(current_floor,previous_floor)-1; zero floor selects ratio zero',
        'budget':'excess=growth-start; full collection when excess>full_growth; interpolate min/max using excess/growth_range and clamp; retain pre-full excess',
        'loop':'at least one step; stop only when counter>deadline, not equal; at most 5000 steps; rotate history on every completed cycle',
        'native_time':'QueryPerformanceFrequency IAT 0x148d348; QueryPerformanceCounter IAT 0x148d370; float milliseconds/frequency arithmetic',
        'native_vm':'totalbytes +0x78, estimate +0x80, threshold +0x70, state +0x21 at PUC global; exit threshold UINT64_MAX-2 disables automatic GC',
        'replacement_vm':'pinned source headers read own VM estimates; lua_gc public STEP/COLLECT/STOP; defaults pause=200, stepmul=20 from constructor',
        'remaining':'early loader, native settings/profiler wiring and finalizer/TLS behavior; collector step granularity is runtime-specific; no live-game or native Windows acceptance'}
    (ROOT/'gc-policy-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'guard_bytes':len(im.data[0x5eb340:0x5eb566]),'settings':defaults}))
if __name__=='__main__':prepare()
