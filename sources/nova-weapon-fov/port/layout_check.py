"""Nova Weapon FOV: check the weapon-manager layout the mod relies on against the 26568081 image.

1. The aim-distance code (game+0x110AC80 on 26251122, +0x160 on 26568081): every instruction up to the function's
   ret has the same mnemonic and operands (so the row terms +0x74..+0x7C, +0x13C..+0x14C and the request field +0x90).
2. Every old .text site that loads the weapon manager global (0x2CE1EA0) and uses the row array (+0xB0) or the row
   stride (0x4D8) within the next 96 bytes: the same instructions are found in the new image (migrate_rvas on the
   loading instruction) with the same global, field and stride.
3. offsets.py drift check for the stride 0x4D8.
Usage: python3 -I layout_check.py > layout-check.json
"""
import json, os, struct, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent; WS = HERE.parents[1]
sys.path.insert(0, os.path.expanduser('~/.claude/skills/hd2-game-update/scripts')); sys.path.insert(0, str(HERE.parent / '_group_lib'))
import migrate_rvas as M, offsets
import capstone
from capstone import x86
old = M.Image(str(WS / 'runtime/images/game-26251122.rebased.dll')); new = M.Image(str(WS / 'runtime/images/game-26568081.dll'))
cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64); cs.detail = True
MANAGER, ROWS, STRIDE, AIM, AIM_NEW = 0x2CE1EA0, 0xB0, 0x4D8, 0x110AC80, 0x110ADE0


def sig(i):
    out, targets = [], []
    for op in i.operands:
        if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP: out.append(('rip', op.size)); targets.append(i.address + i.size + op.mem.disp)
        elif op.type == x86.X86_OP_IMM and (i.group(capstone.CS_GRP_JUMP) or i.group(capstone.CS_GRP_CALL)): out.append(('rel',)); targets.append(op.imm)
        elif op.type == x86.X86_OP_MEM: out.append(('mem', op.mem.base, op.mem.index, op.mem.scale, op.mem.disp, op.size))
        elif op.type == x86.X86_OP_IMM: out.append(('imm', op.imm))
        else: out.append(('reg', op.reg))
    return (i.mnemonic, tuple(out)), targets


def walk(a0, b0, limit=2000, stop_ret=True, span=None):
    """Compare instruction by instruction; returns (count, differences, memory displacements seen, rip targets)."""
    a, b, n, bad, disps, rips = a0, b0, 0, [], set(), []
    while n < limit and (span is None or a - a0 < span):
        x = next(cs.disasm(old.data[a:a + 16], a, 1), None); y = next(cs.disasm(new.data[b:b + 16], b, 1), None)
        if x is None or y is None: bad.append((hex(a), 'undecodable')); break
        (sx, tx), (sy, ty) = sig(x), sig(y)
        if sx != sy or x.size != y.size: bad.append((hex(a), x.mnemonic + ' ' + x.op_str, y.mnemonic + ' ' + y.op_str)); break
        for op in x.operands:
            if op.type == x86.X86_OP_MEM and op.mem.base != x86.X86_REG_RIP: disps.add(op.mem.disp)
            if op.type == x86.X86_OP_IMM: disps.add(('imm', op.imm))
        rips += [(hex(a), hex(p), hex(q)) for p, q in zip(tx, ty) if x.mnemonic != 'call' and not x.mnemonic.startswith('j')]
        n += 1; a += x.size; b += y.size
        if stop_ret and x.mnemonic == 'ret': break
    return n, bad, disps, rips


out = {}
n, bad, disps, rips = walk(AIM, AIM_NEW)
want = [0x74, 0x78, 0x7C, 0x13C, 0x140, 0x144, 0x148, 0x14C, 0x90]
out['aim_distance'] = {'old': hex(AIM), 'new': hex(AIM_NEW), 'instructions_to_ret': n, 'different': bad,
                       'row_and_request_fields_seen': {hex(w): w in disps for w in want}}
sys.stderr.write('aim distance: %d instructions to ret, %d different, fields %s\n' % (n, len(bad), out['aim_distance']['row_and_request_fields_seen']))
# manager users
sites, at = [], old.text_start
needle_rows = struct.pack('<I', ROWS); needle_stride = struct.pack('<I', STRIDE)
while True:
    at = old.data.find(b'\x8b', at, old.text_end)
    if at < 0: break
    # 48 8b 0d/05/15/... disp32 : mov r64,[rip+d]
    if old.data[at - 1] in (0x48, 0x4C) and old.data[at + 1] & 0xC7 == 0x05:
        if at + 6 + struct.unpack_from('<i', old.data, at + 2)[0] == MANAGER:
            w = old.data[at + 6:at + 6 + 96]
            if needle_stride in w or needle_rows in w: sites.append(at - 1)
    at += 1
res = {'sites': len(sites), 'found': 0, 'same': 0, 'rows': []}
for s in sites:
    r = M.migrate_code(old, new, s)
    if not r or not r.get('new'): res['rows'].append({'old': hex(s), 'new': None}); continue
    ns = int(r['new'], 16) if isinstance(r['new'], str) else r['new']
    n, bad, disps, rips = walk(s, ns, limit=80, stop_ret=False, span=110)
    ok = not bad and any(q == hex(MANAGER) for _, p, q in rips[:1])
    uses = {'rows+0xB0': ROWS in disps, 'stride 0x4D8': ('imm', STRIDE) in disps or STRIDE in disps}
    res['found'] += 1; res['same'] += ok
    res['rows'].append({'old': hex(s), 'new': hex(ns), 'confidence': r.get('confidence'), 'instructions_compared': n, 'different': bad, 'manager_target_new': rips[0][2] if rips else None, 'uses': uses})
out['manager_users'] = res
sys.stderr.write('manager users with rows/stride: %d sites, %d found in new, %d identical with the same global\n' % (res['sites'], res['found'], res['same']))
out['stride_drift'] = offsets.check('game', STRIDE)
sys.stderr.write('stride drift %s\n' % out['stride_drift'])
for name, v in (('map_descriptors+0x30', 0x30), ('slots+0x48', 0x48), ('map_entities+0x70', 0x70)):
    pass  # too common as plain displacements to census; covered by the identical manager-user code above where present
json.dump(out, sys.stdout, indent=1)
