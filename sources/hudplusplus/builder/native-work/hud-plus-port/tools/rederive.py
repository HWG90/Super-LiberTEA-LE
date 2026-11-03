"""Re-derive HUD Plus signature patterns for a new game build.

HUD Plus finds every native site with a masked byte pattern ("hex"/"mask") and pulls values out of the
matched bytes ("take": displacements, RIP targets, immediates, SIB scales). When the compiler moves or
re-encodes code, a pattern stops matching even though the instructions it reads are still there.

The pattern's hex is the old build's code, so it is disassembled as is. Each instruction gets a shape
(mnemonic, registers, memory form; operand values ignored). Windows of 5 shapes seed the search in a
linear sweep of the new image's captured code; seeds vote for where the pattern starts, and the old and
new shape sequences are then aligned (difflib). Every take must land on an aligned instruction with the
same shape. The new pattern is the run of new instructions around the takes, masked like the old one
(rel targets, RIP displacements, take fields and any field the old mask hid), grown until it matches
exactly once in the new image's code. "in" patterns (matched at parent + offset) are aligned inside a
window after the parent's new value and need not be unique.

usage: python3 -I rederive.py --data game-data.json --new-game G.bin --new-exe E.bin
           --resolved resolved.tsv [--names a,b] [--cache DIR] --out result.json
"""
import argparse, collections, difflib, hashlib, json, os, struct, sys

sys.path.insert(0, os.environ.get("HD2_PYDEPS", "/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps"))
import numpy as np  # noqa: E402
from capstone import CS_ARCH_X86, CS_MODE_64, Cs, CS_GRP_JUMP, CS_GRP_CALL  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_OP_REG, X86_REG_RIP  # noqa: E402

PAGE = 4096
SEED = 5
MAX_PATTERN = 192
md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True


class Image:
    def __init__(self, path):
        self.path = path
        self.data = open(path, "rb").read()
        o = struct.unpack_from("<I", self.data, 0x3C)[0]
        count, opt = struct.unpack_from("<H", self.data, o + 6)[0], struct.unpack_from("<H", self.data, o + 20)[0]
        s = o + 24 + opt
        self.code = []
        for _ in range(count):
            vs, va = struct.unpack_from("<II", self.data, s + 8)
            chars = struct.unpack_from("<I", self.data, s + 36)[0]
            if chars & 0x20000000 and chars & 0x40000000 and vs:
                self.code.append((va, min(va + vs, len(self.data))))
            s += 40
        self.zero = bytearray(len(self.data) // PAGE + 1)
        z = bytes(PAGE)
        for p in range(0, len(self.data), PAGE):
            chunk = self.data[p:p + PAGE]
            if chunk == z[:len(chunk)]:
                self.zero[p // PAGE] = 1

    def captured(self, rva, size):
        return all(not self.zero[p] for p in range(rva // PAGE, (rva + max(size, 1) - 1) // PAGE + 1))

    def functions(self):
        """(begin, end) rows of the image's own .pdata, when it is readable."""
        if not hasattr(self, "_functions"):
            o = struct.unpack_from("<I", self.data, 0x3C)[0]
            at, size = struct.unpack_from("<II", self.data, o + 24 + 112 + 3 * 8)
            rows = [struct.unpack_from("<II", self.data, at + i) for i in range(0, size - 11, 12)] if at else []
            self._functions = sorted((a, b) for a, b in rows if 0 < a < b <= len(self.data))
        return self._functions

    def function_of(self, rva):
        rows = self.functions()
        lo, hi = 0, len(rows)
        while lo < hi:
            mid = (lo + hi) // 2
            if rows[mid][0] <= rva:
                lo = mid + 1
            else:
                hi = mid
        if lo and rows[lo - 1][0] <= rva < rows[lo - 1][1]:
            return rows[lo - 1]
        return None


def reg(i, r):
    return i.reg_name(r) if r else ""


def shape(i, relaxed=False):
    ops = []
    for op in i.operands:
        if op.type == X86_OP_REG:
            ops.append("r%d" % op.size if relaxed else reg(i, op.reg))
        elif op.type == X86_OP_IMM:
            ops.append("rel" if (i.group(CS_GRP_JUMP) or i.group(CS_GRP_CALL)) else "i%d" % op.size)
        elif op.type == X86_OP_MEM:
            m = op.mem
            if m.base == X86_REG_RIP:
                ops.append("[rip]%d" % op.size)
            elif relaxed:
                ops.append("[%s%s%s]%d" % ("b" if m.base else "", "i" if m.index else "", m.scale if m.index else "", op.size))
            else:
                ops.append("[%s+%s*%d]%d" % (reg(i, m.base), reg(i, m.index), m.scale, op.size))
    return i.mnemonic + " " + ",".join(ops)


def fields(i):
    out = []
    if i.disp_size:
        out.append((i.disp_offset, i.disp_size, "disp"))
    if i.imm_size:
        out.append((i.imm_offset, i.imm_size, "imm"))
    return out


def fixed(i):
    fs = fields(i)
    return [k for k in range(i.size) if not any(s <= k < s + z for s, z, _ in fs)]


def is_rel(i):
    return bool(i.group(CS_GRP_JUMP) or i.group(CS_GRP_CALL)) and any(op.type == X86_OP_IMM for op in i.operands)


def is_rip(i):
    return any(op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP for op in i.operands)


def decode_at(image, rva, count):
    out = []
    for ins in md.disasm(image.data[rva:rva + 16 * count + 16], rva):
        out.append(ins)
        if len(out) >= count:
            break
    return out


def decode_pattern(raw):
    out = []
    for ins in md.disasm(raw, 0):
        if ins.address + ins.size > len(raw):
            break
        out.append(ins)
    return out


def locate(insns, offset):
    for n, ins in enumerate(insns):
        if ins.address <= offset < ins.address + ins.size:
            local = offset - ins.address
            for f, (fs, size, _) in enumerate(fields(ins)):
                if fs <= local < fs + size:
                    return n, f, local - fs
            return n, None, local
    return None


class ShapeIndex:
    """Linear sweep of every captured run of code pages, with 5-gram hashes of instruction shapes."""

    def __init__(self, image, relaxed, cache):
        key = hashlib.sha256(image.data).hexdigest()[:16]  # whole image: merged captures share headers
        path = os.path.join(cache, "shapes-%s-%s-v2.npz" % (key, "relaxed" if relaxed else "strict")) if cache else None
        if path and os.path.exists(path):
            z = np.load(path, allow_pickle=True)
            self.seq, self.addrs = z["seq"], z["addrs"]
            self.ids = dict(z["ids"].item())
        else:
            self._build(image, relaxed)
            if path:
                np.savez(path, seq=self.seq, addrs=self.addrs, ids=np.array(self.ids, dtype=object))
        self.names = {v: k for k, v in self.ids.items()}
        s = self.seq
        n = len(s) - (SEED - 1)
        h = np.zeros(n, dtype=np.int64)
        bad = np.zeros(n, dtype=bool)
        for k in range(SEED):
            h = h * 1000003 + s[k:k + n]
            bad |= s[k:k + n] < 0
        h[bad] = -1
        order = np.argsort(h, kind="stable")
        self.hash_sorted, self.hash_pos = h[order], order

    def _build(self, image, relaxed):
        ids, seq, addrs = {}, [], []
        for a, b in image.code:
            p = a
            while p < b:
                if image.zero[p // PAGE]:
                    p = (p // PAGE + 1) * PAGE
                    continue
                q = p
                while q < b and not image.zero[q // PAGE]:
                    q = (q // PAGE + 1) * PAGE
                q = min(q, b)
                at = p
                while at < q:
                    for ins in md.disasm(image.data[at:q], at):
                        seq.append(ids.setdefault(shape(ins, relaxed), len(ids)))
                        addrs.append(ins.address)
                        at = ins.address + ins.size
                    if at < q:
                        seq.append(-1)
                        addrs.append(at)
                        at += 1
                seq.append(-1)
                addrs.append(q)
                p = q
        self.ids = ids
        self.seq = np.array(seq, dtype=np.int64)
        self.addrs = np.array(addrs, dtype=np.int64)

    def code(self, shapes):
        return [self.ids.get(s, -2) for s in shapes]

    def seeds(self, want):
        """Sequence positions where a SEED-long run of shape ids occurs."""
        if any(w < 0 for w in want):
            return []
        key = 0
        for w in want:  # same wrap-around as the int64 numpy hashes
            key = (key * 1000003 + w) & 0xFFFFFFFFFFFFFFFF
        if key >= 1 << 63:
            key -= 1 << 64
        lo = np.searchsorted(self.hash_sorted, key, "left")
        hi = np.searchsorted(self.hash_sorted, key, "right")
        return [int(x) for x in self.hash_pos[lo:hi]]

    def runs(self, want):
        """Sequence positions where this run of shape ids occurs (any length)."""
        if any(w < 0 for w in want):
            return []
        if len(want) >= SEED:
            got = self.seeds(want[:SEED])
            return [p for p in got if p + len(want) <= len(self.seq)
                    and all(int(self.seq[p + k]) == want[k] for k in range(SEED, len(want)))]
        n = len(self.seq) - len(want) + 1
        hit = self.seq[:n] == want[0]
        for k in range(1, len(want)):
            hit &= self.seq[k:k + n] == want[k]
        return [int(x) for x in np.nonzero(hit)[0]]

    def position(self, rva):
        return int(np.searchsorted(self.addrs, rva, "left"))


FACT = {"scale": lambda v: 2 ** (v // 64), "lea": lambda v: 1 + 2 ** (v // 64), "shl": lambda v: 2 ** v}


def take(raw, rva, spec):
    if isinstance(spec, list):
        factor = spec[0]["kind"] in FACT
        value = 1 if factor else 0
        for part in spec:
            piece = take(raw, rva, part)
            if piece is None:
                return None
            value = value * piece if factor else value + piece
        return value
    at, size, kind = spec["offset"], spec["size"], spec.get("kind")
    if at + size > len(raw):
        return None
    if kind in FACT:
        return FACT[kind](raw[at])
    if kind == "here":
        return rva + at
    if kind == "f":
        return struct.unpack_from("<f", raw, at)[0]
    value = int.from_bytes(raw[at:at + size], "little")
    if kind in ("s", "rip") and value >= 1 << (8 * size - 1):
        value -= 1 << (8 * size)
    if kind == "rip":
        return rva + spec["end"] + value
    return value


def masked_hits(image, raw, mask, limit=3, span=None):
    best = length = start = lead = 0
    for i, m in enumerate(mask):
        if m == 255:
            if length == 0:
                start = i
            length += 1
            if length > best:
                best, lead = length, start
        else:
            length = 0
    anchor = raw[lead:lead + best]
    hits = []
    for a, b in ([span] if span else image.code):
        pos = a
        while anchor:
            f = image.data.find(anchor, pos, b)
            if f < 0:
                break
            at = f - lead
            if at >= a and at + len(raw) <= len(image.data) and all(
                    m != 255 or image.data[at + k] == raw[k] for k, m in enumerate(mask)):
                if image.captured(at, len(raw)):
                    hits.append(at)
                    if len(hits) >= limit:
                        return hits
            pos = f + 1
    return hits


def align(old_codes, new_codes):
    """old index -> new index for equal shapes, via longest matching blocks."""
    sm = difflib.SequenceMatcher(None, old_codes, new_codes, autojunk=False)
    out = {}
    for a, b, n in sm.get_matching_blocks():
        for k in range(n):
            out[a + k] = b + k
    return out, sm.ratio()


def build(image, index, seq_lo, seq_hi, old_insns, mapping, old_mask, take_specs, unique):
    """New pattern over new sequence positions [lo, hi) with the given takes, grown until unique."""
    inverse = {v: k for k, v in mapping.items()}

    def make(lo, hi):
        start = int(index.addrs[lo])
        insns = decode_at(image, start, hi - lo)
        if len(insns) != hi - lo or any(int(index.addrs[lo + k]) != insns[k].address for k in range(len(insns))):
            return None
        raw = bytearray()
        mask = bytearray()
        for k, ins in enumerate(insns):
            piece = bytearray(b"\xff" * ins.size)
            fs = fields(ins)
            old_k = inverse.get(lo + k)
            old = old_insns[old_k] if old_k is not None else None
            for f, (s, z, kind) in enumerate(fs):
                hide = is_rel(ins) or (is_rip(ins) and kind == "disp")
                if old is None:
                    hide = hide or kind == "disp" or z >= 4
                else:
                    ofs = fields(old)
                    if f < len(ofs):
                        os_, oz, _ = ofs[f]
                        if any(old.address + os_ + j < len(old_mask) and old_mask[old.address + os_ + j] != 255 for j in range(oz)):
                            hide = True
                    else:
                        hide = True
                if hide:
                    for j in range(z):
                        piece[s + j] = 0
            if old is not None:
                for ko, kn in zip(fixed(old), fixed(ins)):
                    if old.address + ko < len(old_mask) and old_mask[old.address + ko] != 255:
                        piece[kn] = 0
            raw += image.data[ins.address:ins.address + ins.size]
            mask += piece
        takes = {}
        for name, (pos, spec) in take_specs.items():
            got = place(insns, lo, pos, spec, start)
            if got is None:
                return None
            takes[name] = got
            for part in (got if isinstance(got, list) else [got]):
                if part.get("kind") not in FACT and part.get("kind") != "here":
                    for j in range(part["size"]):
                        mask[part["offset"] + j] = 0
        return start, bytes(raw), bytes(mask), takes

    def sole(lo, hi, start, raw, mask):
        """Does the shape run seq[lo:hi] with these bytes occur only here? (index first, bytes to confirm)"""
        want = [int(x) for x in index.seq[lo:hi]]
        if len(want) >= SEED:
            places = index.seeds(want[:SEED])
        else:
            places = [int(x) for x in np.nonzero(index.seq == want[0])[0]]
        others = 0
        for p in places:
            if p == lo or p + len(want) > len(index.seq):
                continue
            if any(int(index.seq[p + k]) != want[k] for k in range(len(want))):
                continue
            at = int(index.addrs[p])
            if all(m != 255 or image.data[at + k] == raw[k] for k, m in enumerate(mask)):
                others += 1
                break
        return others == 0

    lo, hi = seq_lo, seq_hi
    best = None
    for _ in range(64):
        made = make(lo, hi)
        if made is None:
            return None, "decode"
        start, raw, mask, takes = made
        if len(raw) > MAX_PATTERN:
            return best, "too-long"
        if not unique:
            return made, None
        if sole(lo, hi, start, raw, mask) and masked_hits(image, raw, mask) == [start]:
            return made, None
        best = made
        # grow toward the side that stays aligned
        grow_hi = (hi in inverse) or (hi - 1 in inverse)
        if grow_hi and hi < len(index.seq) and index.seq[hi] >= 0:
            hi += 1
        elif lo > 0 and index.seq[lo - 1] >= 0:
            lo -= 1
        elif hi < len(index.seq) and index.seq[hi] >= 0:
            hi += 1
        else:
            return best, "edge"
    return best, "not-unique"


def place(insns, lo, pos, spec, start):
    if isinstance(spec, list):
        parts = [place(insns, lo, p, s, start) for p, s in zip(pos, spec)]
        return None if any(p is None for p in parts) else parts
    seq_pos, field, byte_in, old_ins = pos
    k = seq_pos - lo
    if not 0 <= k < len(insns):
        return None
    ins = insns[k]
    rel = ins.address - start
    out = dict(spec)
    if field is None:
        fo, fn = fixed(old_ins), fixed(ins)
        if byte_in not in fo or len(fo) != len(fn):
            return None
        out["offset"] = rel + fn[fo.index(byte_in)]
    else:
        fs = fields(ins)
        ofs = fields(old_ins)
        if field >= len(fs) or field >= len(ofs):
            return None
        s, z, _ = fs[field]
        os_, oz, _ = ofs[field]
        if spec["size"] == oz and byte_in == 0:
            out["offset"], out["size"] = rel + s, z
        elif byte_in + spec["size"] <= z:
            out["offset"] = rel + s + byte_in
        else:
            return None
    if "end" in spec:
        if spec["end"] == old_ins.address + old_ins.size:
            out["end"] = rel + ins.size
        else:
            return None
    return out


def old_context(old_image, site, count):
    """Shapes of the old function around a pattern site, and the pattern's index inside it."""
    fn = old_image.function_of(site)
    if fn is None:
        return None
    begin, end = fn
    insns = []
    for ins in md.disasm(old_image.data[begin:min(end, begin + 0x6000)], begin):
        insns.append(ins)
    starts = [i.address for i in insns]
    if site not in starts:
        return None
    k = starts.index(site)
    # a long function: keep 200 instructions either side of the pattern
    lo, hi = max(0, k - 200), min(len(insns), k + count + 200)
    return insns[lo:hi], k - lo


def vote(index, codes):
    ranked = []
    whole = index.runs(codes)
    if len(whole) == 1:
        return [(whole[0], 1.0)], None
    for width in (8, SEED, 4, 3):
        if len(codes) < width:
            continue
        votes = collections.Counter()
        for j in range(0, len(codes) - width + 1):
            got = index.runs(codes[j:j + width])
            if 0 < len(got) <= 12:
                for g in got:
                    votes[g - j] += 1.0 / len(got)
        if votes:
            # votes for starts within one context length of each other are one place (repeated code)
            clusters = []
            for p, v in sorted(votes.items()):
                if clusters and p - clusters[-1][2] <= max(8, len(codes) // 4):
                    c = clusters[-1]
                    c[1] += v
                    c[2] = p
                    if v > c[3]:
                        c[0], c[3] = p, v
                else:
                    clusters.append([p, v, p, v])
            clusters.sort(key=lambda c: -c[1])
            top = [(c[0], c[1]) for c in clusters[:4]]
            if len(top) > 1 and top[1][1] >= top[0][1] * 0.8:
                return top, {"status": "tied-seeds", "width": width,
                             "votes": [(hex(int(index.addrs[max(0, p)])), round(v, 2)) for p, v in top]}
            return top, None
    return None, {"status": "no-seed"}


def finish(row, image, index, old_insns, old_mask, mapping, ratio, evidence, unique):
    """Rebuild the pattern from an old-instruction -> new-sequence-position mapping."""
    take_specs, used = {}, []

    def where(spec):
        if isinstance(spec, list):
            parts = [where(p) for p in spec]
            return None if any(p is None for p in parts) else parts
        got = locate(old_insns, spec["offset"])
        if got is None:
            return None
        n, f, k = got
        if n not in mapping:
            return None
        used.append(mapping[n])
        return (mapping[n], f, k, old_insns[n])

    fuzzy = []

    def nearby(n):
        """A new position for old instruction n that did not align: same relaxed shape, near its neighbours."""
        before = [k for k in mapping if k < n]
        after = [k for k in mapping if k > n]
        if before:
            guess = mapping[max(before)] + (n - max(before))
        elif after:
            guess = mapping[min(after)] - (min(after) - n)
        else:
            return None
        want = shape(old_insns[n], True)
        best = None
        for d in range(0, 9):
            for q in (guess - d, guess + d):
                if 0 <= q < len(index.seq) and q not in mapping.values() and int(index.seq[q]) >= 0:
                    ins = decode_at(image, int(index.addrs[q]), 1)
                    if ins and shape(ins[0], True) == want and len(fields(ins[0])) == len(fields(old_insns[n])):
                        best = q
                        break
            if best is not None:
                break
        return best

    for name, spec in row["take"].items():
        mark = len(used)
        got = where(spec)
        if got is None:
            for part in (spec if isinstance(spec, list) else [spec]):
                at = locate(old_insns, part["offset"])
                if at is not None and at[0] not in mapping:
                    q = nearby(at[0])
                    if q is not None:
                        mapping[at[0]] = q
                        fuzzy.append(name)
            del used[mark:]
            got = where(spec)
        if got is None:
            return {"status": "take-unaligned:" + name, "ratio": round(ratio, 3), "evidence": evidence}
        take_specs[name] = (got, spec)
    if not used:
        used = [min(mapping.values())]
    s_lo, s_hi = min(used), max(used) + 1
    # start at the first aligned instruction of the old pattern when it is close
    first = min(mapping.values())
    if 0 <= s_lo - first <= 12:
        s_lo = first
    made, why = build(image, index, s_lo, s_hi, old_insns, mapping, old_mask, take_specs, unique=unique)
    if made is None:
        return {"status": "build:" + str(why), "ratio": round(ratio, 3), "evidence": evidence}
    start, new_raw, new_mask, takes = made
    out = {"status": "ok" if why is None else "partial:" + why, "at": start, "ratio": round(ratio, 3),
           "aligned": "%d/%d" % (len(mapping), len(old_insns)), "evidence": evidence, "fuzzy": fuzzy,
           "row": dict(row, hex=new_raw.hex(), mask=new_mask.hex(), take=takes)}
    out["values"] = {k: take(new_raw, start, s) for k, s in takes.items()}
    return out


KNOWN = {}  # old data RVA -> new data RVA (from values both builds resolve), per module
KNOWN_CODE = {}  # old function RVA -> new function RVA (migrate_rvas high), per module


def target(ins):
    for op in ins.operands:
        if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP:
            return ins.address + ins.size + op.mem.disp
    return None


def value_score(old_image, ctx, image, index, lo, ctx_map, module):
    """How well the operands' values agree between aligned old and new instructions."""
    score = 0
    known = KNOWN.get(module, {})
    for k, q in ctx_map.items():
        o = ctx[k]
        n = decode_at(image, int(index.addrs[lo + q]), 1)
        if not n:
            continue
        n = n[0]
        if is_rel(o) and is_rel(n) and o.mnemonic == "call" and n.mnemonic == "call":
            oc = KNOWN_CODE.get(module, {}).get(o.operands[0].imm)
            if oc is not None:
                score += 3 if oc == n.operands[0].imm else -3
            continue
        ot, nt = target(o), target(n)
        if ot is not None and nt is not None:
            if ot in known:
                score += 3 if known[ot] == nt else -3
            elif image.captured(nt, 16) and old_image.data[ot:ot + 16] == image.data[nt:nt + 16] \
                    and old_image.data[ot:ot + 16].count(0) < 12:
                score += 2
            continue
        for oo, no in zip(o.operands, n.operands):
            if oo.type == X86_OP_MEM and no.type == X86_OP_MEM and oo.mem.disp and oo.mem.disp == no.mem.disp:
                score += 1
            elif oo.type == X86_OP_IMM and no.type == X86_OP_IMM and not is_rel(o) and oo.imm == no.imm \
                    and abs(oo.imm) > 1:
                score += 1
    return score


def rederive_at(row, image, index, hint, why):
    """Align the pattern inside a window at a location another tool found (migrate_rvas)."""
    raw = bytes.fromhex(row["hex"])
    old_mask = bytes.fromhex(row["mask"])
    old_insns = decode_pattern(raw)
    if not old_insns or not image.captured(hint, len(raw)):
        return {"status": "hint-not-captured", "evidence": why}
    old_codes = index.code([shape(i) for i in old_insns])
    lo, hi = index.position(max(0, hint - 0x40)), index.position(hint + len(raw) + 0x100)
    mapping, ratio = align(old_codes, [int(x) for x in index.seq[lo:hi]])
    mapping = {k: lo + v for k, v in mapping.items()}
    if not mapping:
        return {"status": "hint-unaligned", "evidence": why}
    return finish(row, image, index, old_insns, old_mask, mapping, ratio, why, unique=True)


def rederive(row, image, index, base=None, old_image=None, old_site=None):
    raw = bytes.fromhex(row["hex"])
    old_mask = bytes.fromhex(row["mask"])
    old_insns = decode_pattern(raw)
    if not old_insns:
        return {"status": "undecodable"}
    old_codes = index.code([shape(i) for i in old_insns])
    if base is not None:
        # an "in" pattern: align inside a window after the parent's new value
        lo, hi = index.position(max(0, base - 0x200)), index.position(base + 0x4000)
        mapping, ratio = align(old_codes, [int(x) for x in index.seq[lo:hi]])
        mapping = {k: lo + v for k, v in mapping.items()}
        if not mapping:
            return {"status": "unaligned", "evidence": "parent"}
        return finish(row, image, index, old_insns, old_mask, mapping, ratio, "parent", unique=False)
    context = old_context(old_image, old_site, len(old_insns)) if old_image is not None and old_site is not None else None
    if context is not None:
        ctx, k = context
        ctx_codes = index.code([shape(i) for i in ctx])
        ranked, failed = vote(index, ctx_codes)
        if ranked is None:
            failed["evidence"] = "old-function"
            return failed
        scored = []
        for c0, _ in ranked:
            lo, hi = max(0, c0 - 32), min(len(index.seq), c0 + len(ctx_codes) + 96)
            ctx_map, ratio = align(ctx_codes, [int(x) for x in index.seq[lo:hi]])
            scored.append((value_score(old_image, ctx, image, index, lo, ctx_map, row["module"]), ratio, c0, lo, ctx_map))
        scored.sort(key=lambda t: (-t[0], -t[1]))
        tie = None
        if failed:  # shapes tied: the operand values must pick one place clearly
            if len(scored) > 1 and scored[0][0] < scored[1][0] + 3:
                # templated copies: when every candidate yields the same values, the values stand
                agreed, seen = None, []
                for sc, ratio_c, c0_c, lo_c, map_c in scored:
                    mapping_c = {i: lo_c + map_c[k + i] for i in range(len(old_insns)) if k + i in map_c}
                    if not mapping_c:
                        continue
                    got = finish(row, image, index, old_insns, old_mask, mapping_c, ratio_c, "old-function", unique=False)
                    if got.get("status") != "ok":
                        continue
                    if any(isinstance(v, int) and row["take"][key].get("kind") in ("rip", "here")
                           for key, v in got["values"].items() if isinstance(row["take"][key], dict)):
                        agreed = False  # addresses differ per copy by nature
                        break
                    seen.append(got)
                    if agreed is None:
                        agreed = got["values"]
                    elif agreed != got["values"]:
                        agreed = False
                        break
                if agreed and len(seen) >= 2:
                    out = seen[0]
                    out["status"] = "ok"
                    out["evidence"] = "tied-copies-agree"
                    out["copies"] = [hex(int(index.addrs[c])) for _, _, c, _, _ in scored]
                    out["values_only"] = True
                    return out
                failed["evidence"] = "old-function"
                failed["scores"] = [(hex(int(index.addrs[c])), sc) for sc, _, c, _, _ in scored]
                return failed
            tie = [(hex(int(index.addrs[c])), sc) for sc, _, c, _, _ in scored]
        _, ratio, c0, lo, ctx_map = scored[0]
        # pattern instruction i is old-function instruction k + i
        mapping = {i: lo + ctx_map[k + i] for i in range(len(old_insns)) if k + i in ctx_map}
        if not mapping:
            return {"status": "context-unaligned", "ratio": round(ratio, 3), "evidence": "old-function"}
        out = finish(row, image, index, old_insns, old_mask, mapping, ratio, "old-function", unique=True)
        if tie:
            out["tie_broken_by_values"] = tie
        return out
    ranked, failed = vote(index, old_codes)
    if failed:
        failed["evidence"] = "pattern"
        return failed
    s0 = ranked[0][0]
    lo, hi = max(0, s0 - 16), min(len(index.seq), s0 + len(old_codes) + 48)
    mapping, ratio = align(old_codes, [int(x) for x in index.seq[lo:hi]])
    mapping = {k: lo + v for k, v in mapping.items()}
    if not mapping:
        return {"status": "unaligned", "evidence": "pattern"}
    return finish(row, image, index, old_insns, old_mask, mapping, ratio, "pattern", unique=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--new-game", required=True)
    ap.add_argument("--new-exe", required=True)
    ap.add_argument("--resolved", required=True)
    ap.add_argument("--old-game", help="the old build's game.dll image (gives each site its function)")
    ap.add_argument("--old-hits", help="JSON name -> [old site RVAs] from scan_patterns.py")
    ap.add_argument("--hints", action="append", default=[],
                    help="migrate_rvas.py output (pattern name -> new site); used when the vote fails")
    ap.add_argument("--alt-game", help="game.dll image of an earlier build whose code sits at the same RVAs (26088801)")
    ap.add_argument("--known-code", help="old -> new game.dll functions (migrate_rvas high)")
    ap.add_argument("--known", help="known-globals.json (old -> new game.dll globals from earlier ports)")
    ap.add_argument("--names")
    ap.add_argument("--cache")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    data = json.load(open(a.data))
    patterns, numbers = data["patterns"], data["numbers"]
    images = {"game": Image(a.new_game), "exe": Image(a.new_exe)}
    old_images = {"game": Image(a.old_game)} if a.old_game else {}
    alt = Image(a.alt_game) if a.alt_game else None
    old_hits = json.load(open(a.old_hits)) if a.old_hits else {}
    resolved = {}
    for line in open(a.resolved):
        name, state, old, new = line.rstrip("\n").split("\t")
        resolved[name] = (state, new)

    def new_number(name):
        state, text = resolved.get(name, ("missing", "nil"))
        if state.startswith("missing") or not text.startswith("0x"):
            return None
        return int(text, 16)

    for name, row in patterns.items():
        for key, spec in row["take"].items():
            if isinstance(spec, dict) and spec.get("kind") == "rip":
                state, text = resolved.get(key, ("missing", "nil"))
                if not state.startswith("missing") and text.startswith("0x") and isinstance(numbers.get(key), int):
                    KNOWN.setdefault(row["module"], {})[numbers[key]] = int(text, 16)
    if a.known:
        # earlier ports' consensus globals: old game.dll .data -> new .data (unchanged since 26088801)
        for o, row in json.load(open(a.known)).items():
            o, n = int(o, 16), int(row["new"], 16)
            if 0x263C000 <= o < 0x37D75FC and 0x24B5000 <= n < 0x3194000:
                KNOWN.setdefault("game", {}).setdefault(o, n)
    if a.known_code:
        for o, n in json.load(open(a.known_code)).items():
            KNOWN_CODE.setdefault("game", {})[int(o, 16)] = int(n, 16)
    if a.names:
        names = a.names.split(",")
    else:
        names = [n for n, r in sorted(patterns.items())
                 if any(resolved.get(k, ("missing",))[0].startswith("missing") for k in r["take"])]
    hints = {}
    for path in a.hints:
        for h in json.load(open(path)):
            if h.get("new") and h.get("confidence") in ("high", "medium") and h["name"] not in hints:
                hints[h["name"]] = (int(h["new"], 16), h["confidence"])
    indexes = {}
    results = {}
    for name in names:
        row = patterns[name]
        image = images[row["module"]]
        res = None
        for relaxed in (False,):
            key = (row["module"], relaxed)
            if key not in indexes:
                print("indexing", key, file=sys.stderr)
                indexes[key] = ShapeIndex(image, relaxed, a.cache)
            index = indexes[key]
            if "in" in row:
                parent, off = row["in"]
                base = new_number(parent)
                if base is None:
                    res = {"status": "parent-missing", "parent": parent}
                    break
                res = rederive(row, image, index, base=base + off)
                if res.get("status") == "ok":
                    res["row"]["in"] = [parent, res["at"] - base]
                    hits = masked_hits(image, bytes.fromhex(res["row"]["hex"]), bytes.fromhex(res["row"]["mask"]),
                                       span=(res["at"], res["at"] + len(res["row"]["hex"]) // 2))
                    if hits != [res["at"]]:
                        res["status"] = "in-mismatch"
            else:
                sites = old_hits.get(name) or []
                res = rederive(row, image, index, old_image=old_images.get(row["module"]),
                               old_site=sites[0] if len(sites) == 1 else None)
                if res.get("status") != "ok" and name in hints:
                    first = res
                    res = rederive_at(row, image, index, hints[name][0], "migrate-" + hints[name][1])
                    res["vote"] = {k: first.get(k) for k in ("status", "scores", "votes") if k in first}
                if res.get("status") == "hint-not-captured" and alt is not None and row["module"] == "game":
                    # game.dll code did not move since 26088801: read the site there, values only,
                    # and only values that are not addresses into the shifted .rdata
                    key = ("alt", False)
                    if key not in indexes:
                        print("indexing alt", file=sys.stderr)
                        indexes[key] = ShapeIndex(alt, False, a.cache)
                    got = rederive_at(row, alt, indexes[key], hints[name][0], "alt-26088801-" + hints[name][1])
                    if got.get("status") == "ok":
                        safe = True
                        for k, v in got["values"].items():
                            spec = row["take"][k]
                            kind = spec.get("kind") if isinstance(spec, dict) else None
                            if kind == "rip" and not (0x24B5000 <= v < 0x3194000 or v < 0x2246000):
                                safe = False
                        if safe:
                            got["values_only"] = True
                            res = got
            if res.get("status") == "ok":
                break
        res["module"] = row["module"]
        if "values" in res:
            res["values"] = {k: {"old": numbers.get(k), "new": v} for k, v in res["values"].items()}
        if "at" in res:
            res["at"] = hex(res["at"])
        results[name] = res
    json.dump(results, open(a.out, "w"), indent=1, sort_keys=True)
    print(dict(collections.Counter(r.get("status", "?").split(":")[0] for r in results.values())))


if __name__ == "__main__":
    main()
