"""Check every native function HUD Plus calls against its recorded function head.

HUD Plus keeps, for each callable ("calls"), the first bytes of the function ("head", "head_mask",
"head_at"). When it resolves by scanning it drops a call whose head no longer matches. This applies the
same check offline to a resolved TSV, so a wrong call target is caught before anything calls it.

For a head that fails, the function at the new address is disassembled and compared by instruction
shape with the old head, which tells a re-encoded prologue (same instructions, new offsets) apart from
a different function.

usage: python3 -I check_calls.py <game-data.json> <resolved.tsv> <exe image> <game image> [--json out]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.argv, args = sys.argv[:1], sys.argv[1:]
import rederive as rd  # noqa: E402


def main():
    data_path, resolved_path, exe_path, game_path = args[:4]
    out_path = args[args.index("--json") + 1] if "--json" in args else None
    data = json.load(open(data_path))
    images = {"exe": rd.Image(exe_path), "game": rd.Image(game_path)}
    resolved = {}
    for line in open(resolved_path):
        name, state, old, new = line.rstrip("\n").split("\t")
        resolved[name] = (state, new)
    report = {}
    for name, call in sorted(data["calls"].items()):
        at_name = call.get("at")
        state, text = resolved.get(at_name, ("missing", "nil"))
        row = {"at": at_name, "state": state}
        if state.startswith("missing") or not text.startswith("0x") or "head" not in call:
            row["result"] = "unresolved" if "head" in call else "no-head"
            report[name] = row
            continue
        image = images[call["module"]]
        at = int(text, 16) + call.get("head_at", 0)
        head, mask = bytes.fromhex(call["head"]), bytes.fromhex(call["head_mask"])
        got = image.data[at:at + len(head)]
        row["new"] = hex(at)
        # the protector refills inter-function padding each build: compare up to the first int3 run
        prefix = len(head)
        for k in range(len(head) - 1):
            if head[k] == 0xCC and head[k + 1] == 0xCC:
                prefix = k
                break
        if not image.captured(at, len(head)):
            row["result"] = "page-not-captured"
        elif all(m != 255 or got[k] == head[k] for k, m in enumerate(mask)):
            row["result"] = "head-match"
        elif prefix >= 8 and all(m != 255 or got[k] == head[k] for k, m in enumerate(mask[:prefix])):
            row["result"] = "head-match-before-padding"
            row["prefix"] = prefix
        else:
            row["first_diff"] = next(k for k, m in enumerate(mask) if m == 255 and got[k] != head[k])
            old_insns = rd.decode_pattern(head)
            new_insns = rd.decode_at(image, at, len(old_insns))
            same = len(new_insns) == len(old_insns) and all(
                rd.shape(o) == rd.shape(n) for o, n in zip(old_insns, new_insns))
            relaxed = len(new_insns) == len(old_insns) and all(
                rd.shape(o, True) == rd.shape(n, True) for o, n in zip(old_insns, new_insns))
            row["result"] = "head-reencoded" if same else ("head-relaxed" if relaxed else "head-differs")
            row["old_shapes"] = [rd.shape(i) for i in old_insns]
            row["new_shapes"] = [rd.shape(i) for i in new_insns]
        report[name] = row
    counts = {}
    for row in report.values():
        counts[row["result"]] = counts.get(row["result"], 0) + 1
    print(counts)
    for name, row in report.items():
        if row["result"] not in ("head-match", "unresolved", "no-head"):
            print(name, row["at"], row["state"], row.get("new"), row["result"])
    if out_path:
        json.dump(report, open(out_path, "w"), indent=1)


main()
