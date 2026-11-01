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
    want = '6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    assert hashlib.sha256(image.data).hexdigest() == want
    specs = [('construct', 0x4ed1d0, 0x4ed4bd, 0x4ed2f2, 0x4ed49f),
             ('close', 0x4ed4c0, 0x4ed52f, 0x4ed4d2, 0x4ed4da)]
    calls = {0x4ed20e: 0x601f40, 0x4ed227: 0x601f40, 0x4ed2f2: 0x7989a0,
             0x4ed492: 0x4ec690, 0x4ed49a: 0x4ec360, 0x4ed4cd: 0x4f06d0,
             0x4ed4d5: 0x798b70, 0x4ed4f1: 0x287c70, 0x4ed517: 0x4f9df0,
             0x4ed52a: 0x602070}
    lines = ['/* Local captured code/constants, not a redistributable game package. */']
    rows = []
    for name, start, end, patch, resume in specs:
        code = image.data[start:end]
        instructions = {i.address: i for i in image.cs.disasm(code, start)}
        assert patch in instructions and resume in instructions
        assert instructions[end-1].mnemonic == 'ret' if name == 'construct' else instructions[0x4ed52a].mnemonic == 'jmp'
        for at, target in calls.items():
            if start <= at < end:
                ins = instructions[at]
                assert ins.mnemonic in ('call', 'jmp') and ins.operands[0].type == X86_OP_IMM and ins.operands[0].imm == target
        lines.append('static const unsigned char lifecycle_'+name+'_witness[] = {'+','.join(map(str, code))+'};')
        rows.append({'name': name, 'entry': hex(start), 'end': hex(end), 'patch': hex(patch),
                     'resume': hex(resume), 'sha256': hashlib.sha256(code).hexdigest(),
                     'calls': {hex(a): hex(t) for a, t in calls.items() if start <= a < end}})
    lines.append('#ifdef HD2_LIFECYCLE_TEST_DATA')
    for name, start, size in [('buffers', 0x4f06d0, 0x6e), ('gc_max_ms', 0x174d754, 4), ('gc_settings', 0x174dac0, 16)]:
        lines.append('static const unsigned char lifecycle_'+name+'_witness[] = {'+','.join(map(str, image.data[start:start+size]))+'};')
    lines.append('#endif')
    (ROOT/'work/lifecycle_witnesses.h').write_text('\n'.join(lines)+'\n')
    receipt = {'capture': str(image.path), 'capture_sha256': want, 'functions': rows,
        'constructor_kept': 'native allocator metadata, resource-manager pointer, vector buffer metadata, GC defaults, original native error reporter fields',
        'constructor_replaced': 'PUC newstate, internal GC/panic/registry setup, standard library setup and resource loader insertion',
        'destructor_kept': 'native buffer cleanup and native allocator teardown',
        'state_fields': 'native+0 and native+0x100148 stay null; lookup uses an external association',
        'close_target': 'requires a reachable rel32 target or a separately prepared nearby leaf jump stub',
        'boot_remaining': '0x6cde10 includes PUC stack reset, engine callback registration, config globals, require/init and error handling',
        'live_game_installable': False,
        'reason': 'No early loader installed; captured boot and game shutdown routes are separate proofs; timed GC, TLS/error context and remaining bindings still require adaptation'}
    (ROOT/'lifecycle-route-evidence.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps({'functions': len(rows), 'confirmed_calls': len(calls), 'live_game_installable': False}))


if __name__ == '__main__':
    prepare()
