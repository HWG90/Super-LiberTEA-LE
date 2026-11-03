"""First-pass RVA migration between two mapped-image captures of one HD2 module (old build -> new build).

Code RVAs: a byte window at the old RVA (and at its function start, when .pdata is known) is searched
in the new .text with rel32 branch/call targets and RIP-relative displacements masked; only a unique
match counts. Data RVAs: every RIP-relative instruction in old .text that addresses the RVA (or a field within
0x100 of it) is migrated as code, decoded at its new site, and its new target is a vote. Code RVAs
with no unique window are voted the same way by their rel32 call/jmp sites, then by lea/mov references.
Unresolved code rows between two high neighbours with the same delta are tried at that delta
(anchor_deltas; medium at best). An "X.end" row is derived from its mapped "X.entry"/"X.start" when the masked body is identical (the
protector refills inter-function padding each build, so ends have no stable window of their own).

Pages that are zero-filled (not captured) or still encrypted (entropy > 7.9) are never used as evidence.
This is a first pass: every result still needs a read-only live check, and per-mod analysers
(e.g. native-work/mom-port/analyze_mom_map.py) remain the authority for layouts and tables.

Input: JSON [{"name","rva","kind":"code"|"data"}] or text lines "name rva kind".
Usage: python3 -I migrate_rvas.py --old OLD.bin --new NEW.bin --input rvas.json --output map.json
       [--old-pdata F] [--new-pdata F] [--check MAP.json]  (--check: compare with an accepted MAP.json)
"""
import argparse, bisect, collections, json, math, os, struct, sys

sys.path.insert(0, os.environ.get("HD2_PYDEPS", "/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps"))
import numpy as np  # noqa: E402
from capstone import CS_ARCH_X86, CS_GRP_CALL, CS_GRP_JUMP, CS_MODE_64, Cs  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP  # noqa: E402

PAGE = 4096
WINDOWS = (160, 128, 96, 64, 48, 32)


class Image:
    def __init__(self, path, pdata=None):
        self.path = path
        self.data = open(path, "rb").read()
        o = struct.unpack_from("<I", self.data, 0x3C)[0]
        count, opt = struct.unpack_from("<H", self.data, o + 6)[0], struct.unpack_from("<H", self.data, o + 20)[0]
        s = o + 24 + opt
        self.sections = []
        for _ in range(count):
            vs, va = struct.unpack_from("<II", self.data, s + 8)
            chars = struct.unpack_from("<I", self.data, s + 36)[0]
            self.sections.append((self.data[s:s + 8].rstrip(b"\0").decode(), va, vs, chars))
            s += 40
        text = next(x for x in self.sections if x[3] & 0x20000000)
        self.text_start, self.text_end = text[1], text[1] + text[2]
        self.usable = bytearray(len(self.data) // PAGE + 1)
        for p in range(0, len(self.data), PAGE):
            page = self.data[p:p + PAGE]
            if page.count(0) == len(page):
                continue
            counts = collections.Counter(page)
            entropy = -sum(c / len(page) * math.log2(c / len(page)) for c in counts.values())
            self.usable[p // PAGE] = entropy <= 7.9 or not (text[1] <= p < text[1] + text[2])
        self.functions = self._functions(pdata, o)
        self.starts = [a for a, _ in self.functions]

    def _functions(self, pdata, o):
        raw = open(pdata, "rb").read() if pdata else None
        if raw is None:
            at, size = struct.unpack_from("<II", self.data, o + 24 + 112 + 3 * 8)
            raw = self.data[at:at + size] if at and size else b""
        rows = [struct.unpack_from("<II", raw, i) for i in range(0, len(raw) - 11, 12)]
        rows = [(a, b) for a, b in rows if self.text_start <= a < b <= self.text_end]
        return sorted(rows) if len(rows) > 100 else []

    def ok(self, rva, length):
        if rva < 0 or rva + length > len(self.data):
            return False
        return all(self.usable[p] for p in range(rva // PAGE, (rva + length - 1) // PAGE + 1))

    def owner(self, rva):
        i = bisect.bisect_right(self.starts, rva) - 1
        return self.functions[i] if i >= 0 and self.functions[i][0] <= rva < self.functions[i][1] else None


cs = Cs(CS_ARCH_X86, CS_MODE_64)
cs.detail = True


def masked(img, rva, length, relaxed):
    raw = img.data[rva:rva + length]
    keep = [True] * len(raw)
    for ins in cs.disasm(raw, rva):
        off = ins.address - rva
        if ins.group(CS_GRP_JUMP) or ins.group(CS_GRP_CALL):
            for i in range(ins.imm_offset, ins.imm_offset + ins.imm_size):
                keep[off + i] = False
        for op in ins.operands:
            if op.type == X86_OP_MEM and (relaxed or op.mem.base == X86_REG_RIP):
                for i in range(ins.disp_offset, ins.disp_offset + ins.disp_size):
                    keep[off + i] = False
    return raw, keep


def search(new, raw, keep):
    runs, start = [], None
    for i, k in enumerate(keep + [False]):
        if k and start is None:
            start = i
        if not k and start is not None:
            runs.append((start, i))
            start = None
    if not runs:
        return []
    a, b = max(runs, key=lambda r: r[1] - r[0])
    if b - a < 6:
        return []
    hits, pos, body = [], new.text_start, new.data
    while len(hits) <= 2:
        at = body.find(raw[a:b], pos, new.text_end)
        if at < 0:
            break
        pos = at + 1
        begin = at - a
        if begin >= new.text_start and all(not k or body[begin + i] == raw[i] for i, k in enumerate(keep)):
            hits.append(begin)
    return hits


def migrate_code(old, new, rva, xrefs=True):
    fn = old.owner(rva)
    sites = [(rva, "instruction window")] + ([(fn[0], "containing function")] if fn and fn[0] != rva else [])
    for site, mode in sites:
        for relaxed in (False, True):
            for length in WINDOWS:
                if not old.ok(site, length):
                    continue
                raw, keep = masked(old, site, length, relaxed)
                hits = search(new, raw, keep)
                if len(hits) == 1:
                    return {"new": hits[0] + (rva - site), "mode": mode, "window": length, "relaxed": relaxed,
                            "confidence": "high" if length >= 64 and not relaxed else "medium"}
    if xrefs:  # short or duplicated bodies: let the call sites, then lea/mov references, vote
        for branches, mode in ((True, "call sites"), (False, "address references")):
            result = vote(old, new, rva, refs_to(old, rva, 0, branches=branches))
            if result:
                result["mode"] = mode
                return result
    return {"status": "unresolved" if old.ok(rva, 16) else "old page not captured or encrypted"}


def refs_to(img, target, spread, branches, limit=64, decode=256):
    """Old .text instructions whose disp32 resolves near target: RIP-relative operands (data) or
    rel32 call/jmp (code). Returns (site, mnemonic, delta) with delta = resolved - target.
    Exact references are preferred over field references (delta != 0). Heavily used globals have
    thousands of references, so candidates are sampled evenly across all of .text, never just the
    lowest addresses (those can sit in one function that no longer migrates)."""
    lo, hi = img.text_start, img.text_end - 4
    raw = np.frombuffer(img.data, dtype=np.uint8, count=hi + 4)
    found = []
    for align in range(4):
        start = lo + ((align - lo) % 4)
        n = (hi - start) // 4
        disp = np.frombuffer(raw[start:start + n * 4].tobytes(), dtype="<i4").astype(np.int64)
        where = start + np.arange(n, dtype=np.int64) * 4
        for tail in ((0,) if branches else (0, 1, 2, 4)):
            resolved = where + 4 + tail + disp
            hit = (resolved >= target - spread) & (resolved <= target + spread)
            if branches:
                hit &= (raw[where - 1] == 0xE8) | (raw[where - 1] == 0xE9)
            found.extend(zip((int(x) for x in where[hit]), (int(x) - target for x in resolved[hit])))
    found = sorted(set(found))
    exact = [f for f in found if f[1] == 0]
    pool = [p for p, _ in (exact or found)]
    pool = sorted(set(pool))
    if len(pool) > decode:
        pool = [pool[i * len(pool) // decode] for i in range(decode)]
    refs = []
    for p in pool:
        if not img.ok(p - 16, 48):
            continue
        for s in ([p - 1] if branches else range(p - 1, p - 11, -1)):
            ins = next(cs.disasm(img.data[s:s + 16], s), None)
            if not ins or ins.address + ins.size <= p + 3:
                continue
            if branches:
                if ins.mnemonic in ("call", "jmp") and ins.operands and ins.operands[0].type == X86_OP_IMM and \
                        ins.operands[0].imm == target:
                    refs.append((s, ins.mnemonic, 0))
                break
            for op in ins.operands:
                if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP and s + ins.disp_offset == p:
                    refs.append((s, ins.mnemonic, s + ins.size + op.mem.disp - target))
                    break
            else:
                continue
            break
    exact = [r for r in refs if r[2] == 0]
    refs = exact or refs
    if len(refs) > limit:
        refs = [refs[i * len(refs) // limit] for i in range(limit)]
    return refs


def vote(old, new, rva, refs):
    votes, evidence = collections.Counter(), []
    for site, mnemonic, delta in refs:
        m = migrate_code(old, new, site, xrefs=False)
        if "new" not in m:
            continue
        ins = next(cs.disasm(new.data[m["new"]:m["new"] + 16], m["new"]), None)
        if not ins or ins.mnemonic != mnemonic:
            continue
        if ins.operands and ins.operands[0].type == X86_OP_IMM:  # direct rel32 call/jmp
            target = ins.operands[0].imm
        else:
            ops = [op for op in ins.operands if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP]
            if not ops:
                continue
            target = m["new"] + ins.size + ops[0].mem.disp - delta
        votes[target] += 1
        evidence.append({"old_site": hex(site), "new_site": hex(m["new"]), "ins": "%s %s" % (ins.mnemonic, ins.op_str),
                         "delta": delta, "implies": hex(target)})
    if not votes:
        return None
    best, n = votes.most_common(1)[0]
    total = sum(votes.values())
    fields_only = all(e["delta"] for e in evidence)
    confidence = "high" if n >= 2 and n == total and not fields_only else "medium" if n > total - n else "low"
    return {"new": best, "votes": n, "dissent": total - n, "evidence": evidence[:8], "confidence": confidence}


def migrate_data(old, new, rva):
    return vote(old, new, rva, refs_to(old, rva, 0x100, branches=False)) or {"status": "no migratable references"}


def body_identical(old, new, old_start, length, new_start):
    """Whole-body comparison with rel32 and RIP displacements masked."""
    if not (old.ok(old_start, length) and new.ok(new_start, length)):
        return None
    raw, keep = masked(old, old_start, length, False)
    body = new.data[new_start:new_start + length]
    return all(not k or body[i] == raw[i] for i, k in enumerate(keep))


def derive_ends(old, new, out):
    """X.end from a mapped X.entry/X.start: the protector refills the padding after a function each build,
    so an exclusive end has no stable window. Accept new_entry + length only when the body is identical."""
    by_name = {r["name"]: r for r in out}
    for r in out:
        if "new" in r or not r["name"].endswith(".end"):
            continue
        base = r["name"][:-len(".end")]
        start = by_name.get(base + ".entry") or by_name.get(base + ".start")
        if not start or "new" not in start or start.get("confidence") != "high":
            continue
        length = int(r["old"], 16) - int(start["old"], 16)
        if not 0 < length <= 0x40000:
            continue
        same = body_identical(old, new, int(start["old"], 16), length, int(start["new"], 16))
        r.pop("status", None)
        if same:
            r.update(new=hex(int(start["new"], 16) + length), mode="entry + identical body", confidence="high")
        else:
            r.update(status="body changed" if same is False else "body not fully captured", entry_new=start["new"])


def anchor_deltas(old, new, out, reach=0x4000, window=24):
    """Unresolved code rows between two high-confidence neighbours that moved by the same delta: accept
    old + delta when a masked window there matches (relaxed masking). Recompiled builds move code in long
    blocks by one delta, so this resolves short or duplicated bodies that have no unique window or callers.
    Never better than medium: it is interpolation, confirmed only by a short window."""
    anchors = sorted((int(r["old"], 16), int(r["new"], 16)) for r in out if r.get("confidence") == "high" and r["kind"] == "code")
    starts = [a for a, _ in anchors]
    for r in out:
        if "new" in r or r["kind"] != "code":
            continue
        o = int(r["old"], 16)
        i = bisect.bisect_left(starts, o)
        if i == 0 or i >= len(anchors):
            continue
        (a0, n0), (a1, n1) = anchors[i - 1], anchors[i]
        if n0 - a0 != n1 - a1 or o - a0 > reach or a1 - o > reach:
            continue
        cand = o + (n0 - a0)
        if not (old.ok(o, window) and new.ok(cand, window)):
            continue
        raw, keep = masked(old, o, window, True)
        body = new.data[cand:cand + window]
        if all(not k or body[j] == raw[j] for j, k in enumerate(keep)):
            r.pop("status", None)
            r.update(new=hex(cand), mode="anchored delta %+#x" % (n0 - a0), confidence="medium",
                     anchors=[hex(a0), hex(a1)])


def load_input(path):
    text = open(path).read()
    if text.lstrip().startswith(("[", "{")):
        rows = json.loads(text)
        return rows if isinstance(rows, list) else rows["rows"]
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 2 and not line.startswith("#"):
            rows.append({"name": parts[0], "rva": parts[1], "kind": parts[2] if len(parts) > 2 else "code"})
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--old", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--old-pdata")
    ap.add_argument("--new-pdata")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--check", help="accepted MAP.json: report agreement per row name")
    a = ap.parse_args()
    old, new = Image(a.old, a.old_pdata), Image(a.new, a.new_pdata)
    print("old %s: %d functions, %d usable pages; new %s: %d functions, %d usable pages" % (
        os.path.basename(a.old), len(old.functions), sum(old.usable), os.path.basename(a.new), len(new.functions), sum(new.usable)))
    out = []
    for row in load_input(a.input):
        rva = int(str(row["rva"]), 16)
        result = migrate_data(old, new, rva) if row.get("kind") == "data" else migrate_code(old, new, rva)
        if "new" in result:
            result["new"] = hex(result["new"])
        out.append(dict(name=row["name"], kind=row.get("kind", "code"), old=hex(rva), **result))
    derive_ends(old, new, out)
    anchor_deltas(old, new, out)
    json.dump(out, open(a.output, "w"), indent=1)
    done = sum("new" in r for r in out)
    print("mapped %d of %d -> %s" % (done, len(out), a.output))
    if a.check:
        accepted = {r["name"]: r.get("new") for r in json.load(open(a.check))["rows"]}
        agree = disagree = 0
        for r in out:
            want = accepted.get(r["name"])
            if "new" not in r or not isinstance(want, str):
                continue
            if int(want, 16) == int(r["new"], 16):
                agree += 1
            else:
                disagree += 1
                print("  DIFFERS %-40s ours %s (%s) accepted %s" % (r["name"], r["new"], r.get("confidence"), want))
        print("check against %s: %d agree, %d differ" % (a.check, agree, disagree))
    print("by confidence:", dict(collections.Counter(r.get("confidence", r.get("status")) for r in out)))


if __name__ == "__main__":
    main()
