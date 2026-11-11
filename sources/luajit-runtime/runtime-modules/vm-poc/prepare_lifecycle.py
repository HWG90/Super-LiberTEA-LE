"""Verify constructor/destructor boundaries against the pinned mapped image."""
from pathlib import Path
import hashlib
import json
import sys
from capstone.x86 import X86_OP_IMM

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / 'vm-trace'))
from trace import Image


def prepare():
    image = Image('early')
    want = '1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    assert hashlib.sha256(image.data).hexdigest() == want
    specs = [('construct', 0x4ed2a0, 0x4ed58d, 0x4ed3c2, 0x4ed56f),
             ('close', 0x4ed590, 0x4ed5ff, 0x4ed5a2, 0x4ed5aa)]
    calls = {0x4ed2de: 0x601fe0, 0x4ed2f7: 0x601fe0, 0x4ed3c2: 0x7989f0,
             0x4ed562: 0x4ec760, 0x4ed56a: 0x4ec430, 0x4ed59d: 0x4f07a0,
             0x4ed5a5: 0x798bc0, 0x4ed5c1: 0x287d00, 0x4ed5e7: 0x4f9ec0,
             0x4ed5fa: 0x602110}
    lines = ['/* Local captured code/constants, not a redistributable game package. */']
    rows = []
    for name, start, end, patch, resume in specs:
        code = image.data[start:end]
        instructions = {i.address: i for i in image.cs.disasm(code, start)}
        assert patch in instructions and resume in instructions
        assert instructions[end-1].mnemonic == 'ret' if name == 'construct' else instructions[0x4ed5fa].mnemonic == 'jmp'
        for at, target in calls.items():
            if start <= at < end:
                ins = instructions[at]
                assert ins.mnemonic in ('call', 'jmp') and ins.operands[0].type == X86_OP_IMM and ins.operands[0].imm == target
        lines.append('static const unsigned char lifecycle_'+name+'_witness[] = {'+','.join(map(str, code))+'};')
        rows.append({'name': name, 'entry': hex(start), 'end': hex(end), 'patch': hex(patch),
                     'resume': hex(resume), 'sha256': hashlib.sha256(code).hexdigest(),
                     'calls': {hex(a): hex(t) for a, t in calls.items() if start <= a < end}})
    lines.append('#ifdef HD2_LIFECYCLE_TEST_DATA')
    for name, start, size in [('buffers', 0x4f07a0, 0x6e), ('gc_max_ms', 0x174d74c, 4), ('gc_settings', 0x174dab0, 16)]:
        lines.append('static const unsigned char lifecycle_'+name+'_witness[] = {'+','.join(map(str, image.data[start:start+size]))+'};')
    lines.append('#endif')
    (ROOT/'work/lifecycle_witnesses.h').write_text('\n'.join(lines)+'\n')
    receipt = {'capture': str(image.path), 'capture_sha256': want, 'functions': rows,
        'constructor_kept': 'native allocator metadata, resource-manager pointer, vector buffer metadata, GC defaults, original native error reporter fields',
        'constructor_replaced': 'PUC newstate, internal GC/panic/registry setup, standard library setup and resource loader insertion',
        'destructor_kept': 'native buffer cleanup and native allocator teardown',
        'state_fields': 'native+0 and native+0x100148 stay null; lookup uses an external association',
        'close_target': 'requires a reachable rel32 target or a separately prepared nearby leaf jump stub',
        'boot_remaining': '0x6cded0 includes PUC stack reset, engine callback registration, config globals, require/init and error handling',
        'live_game_installable': False,
        'reason': 'No early loader installed; captured boot and game shutdown routes are separate proofs; timed GC, TLS/error context and remaining bindings still require adaptation'}
    (ROOT/'lifecycle-route-evidence.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps({'functions': len(rows), 'confirmed_calls': len(calls), 'live_game_installable': False}))


if __name__ == '__main__':
    prepare()
