"""Scan HUD Plus signature patterns over module images (RVA-indexed), the way native.signatures does.

usage: python3 -I scan_patterns.py <game-data.json> --game OLD_GAME [--exe OLD_EXE] --out hits.json
Every non-"in" pattern is searched in the executable sections; all masked matches are listed.
"""
import argparse, json, struct


def sections(data):
    o = struct.unpack_from("<I", data, 0x3C)[0]
    count, opt = struct.unpack_from("<HH", data, o + 6)[0], struct.unpack_from("<H", data, o + 20)[0]
    s = o + 24 + opt
    out = []
    for _ in range(count):
        vs, va = struct.unpack_from("<II", data, s + 8)
        chars = struct.unpack_from("<I", data, s + 36)[0]
        out.append((data[s:s + 8].rstrip(b"\0").decode("latin1"), va, vs, chars))
        s += 40
    return out


def prepared(row):
    raw, mask = bytes.fromhex(row["hex"]), bytes.fromhex(row["mask"])
    start = length = 0
    best, longest = 0, 0
    for i, m in enumerate(mask):
        if m == 255:
            if length == 0:
                start = i
            length += 1
            if length > longest:
                best, longest = start, length
        else:
            length = 0
    return raw, mask, best, raw[best:best + longest]


def matches(raw, mask, data, at):
    if at < 0 or at + len(raw) > len(data):
        return False
    for i, m in enumerate(mask):
        if m == 255 and data[at + i] != raw[i]:
            return False
    return True


def scan(data, row):
    raw, mask, lead, anchor = prepared(row)
    hits = []
    for name, va, vs, chars in sections(data):
        if not (chars & 0x20000000 and chars & 0x40000000) or vs == 0:
            continue
        end = min(va + vs, len(data))
        pos = va
        while anchor:
            found = data.find(anchor, pos, end)
            if found < 0:
                break
            at = found - lead
            if at >= va and matches(raw, mask, data, at):
                hits.append(at)
            pos = found + 1
            if len(hits) > 8:
                break
    return sorted(set(hits))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--game")
    ap.add_argument("--exe")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    d = json.load(open(a.data))
    images = {}
    if a.game:
        images["game"] = open(a.game, "rb").read()
    if a.exe:
        images["exe"] = open(a.exe, "rb").read()
    out = {}
    for name, row in sorted(d["patterns"].items()):
        if row["module"] not in images or "in" in row:
            continue
        out[name] = scan(images[row["module"]], row)
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    counts = {}
    for v in out.values():
        k = "none" if not v else ("unique" if len(v) == 1 else "many")
        counts[k] = counts.get(k, 0) + 1
    print(counts)


main()
