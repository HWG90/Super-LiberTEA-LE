"""List the component accessor functions of a game.dll image: registry table offset, capacity, record size.

Every component type has a find-by-id accessor built from one template:
    mov rax,[rip+registry root]; mov r8d,ecx; mov r10,[rax+TABLE]; <hash>; probe loop up to CAPACITY;
    imul rax,rcx,RECORD; add rax,BASE; add rax,r10
The registry keeps its tables in type order, so two builds' lists line up by TABLE order even when
capacities and record sizes change.

usage: python3 -I component_accessors.py <image> [--root RVA] [--json out]
"""
import json, os, re, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
sys.argv = sys.argv[:1]
import rederive as rd  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP  # noqa: E402


def scan(path, root):
    img = rd.Image(path)
    out = {}
    text_end = img.code[0][1]
    for m in re.finditer(rb"\x48\x8b\x05", img.data[:text_end]):
        at = m.start()
        if at + 7 + struct.unpack_from("<i", img.data, at + 3)[0] != root:
            continue
        ins = rd.decode_at(img, at, 60)
        table = capacity = record = base = None
        for i in ins[:4]:
            for op in i.operands:
                if op.type == X86_OP_MEM and op.mem.base != X86_REG_RIP and i.mnemonic == "mov" and "r10" in i.op_str:
                    table = op.mem.disp
        if table is None:
            continue
        for i in ins:
            if i.mnemonic == "cmp" and "r9d" in i.op_str and i.operands[1].type == X86_OP_IMM:
                capacity = i.operands[1].imm
            if i.mnemonic == "imul" and len(i.operands) == 3:
                record = i.operands[2].imm
            if i.mnemonic == "add" and record and i.operands[-1].type == X86_OP_IMM and base is None:
                base = i.operands[-1].imm
            if i.mnemonic == "ret" and capacity:
                break
        start = at
        for back in range(1, 16):  # function start: test rcx,rcx; je  just before
            if img.data[at - back:at - back + 3] == b"\x48\x85\xc9":
                start = at - back
                break
        out.setdefault(table, []).append({"at": hex(start), "capacity": capacity, "record": record, "base": base})
    return out


if __name__ == "__main__":
    path = args[0]
    root = int(args[args.index("--root") + 1], 16)
    found = scan(path, root)
    for table in sorted(found):
        rows = found[table]
        print(hex(table), len(rows), rows[0])
    if "--json" in args:
        json.dump({hex(k): v for k, v in sorted(found.items())}, open(args[args.index("--json") + 1], "w"), indent=1)
