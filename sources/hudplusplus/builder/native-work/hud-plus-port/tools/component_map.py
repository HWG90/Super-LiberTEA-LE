"""Map component registry tables old -> new by aligning the accessors' capacity sequences.

Input: component_accessors.py JSON for the old and the new image. Tables are 8-byte slots in type
order; capacities change a little between builds (new items), slots shift when types are added.
A scored global alignment (equal capacity 3, within 5 % 2, within 10 % 1, else -3; gaps -1) pairs them.
"""
import json


def load(path):
    rows = {}
    for k, v in json.load(open(path)).items():
        t = int(k, 16)
        if t > 0xF00000 and v[0]["capacity"]:
            rows[t] = (v[0]["capacity"], [int(x["at"], 16) for x in v])
    return rows


def similar(a, b):
    if a == b:
        return 3
    d = abs(a - b)
    if d <= max(2, a // 20):
        return 2
    if d <= max(3, a // 10):
        return 1
    return -3


def build(old_path, new_path):
    """Needleman-Wunsch over the two capacity sequences: capacities grow a little, slots get inserted."""
    old, new = load(old_path), load(new_path)
    o, n = sorted(old), sorted(new)
    A, B = [old[t][0] for t in o], [new[t][0] for t in n]
    gap = -1
    score = [[0] * (len(B) + 1) for _ in range(len(A) + 1)]
    for i in range(1, len(A) + 1):
        score[i][0] = i * gap
    for j in range(1, len(B) + 1):
        score[0][j] = j * gap
    for i in range(1, len(A) + 1):
        for j in range(1, len(B) + 1):
            score[i][j] = max(score[i - 1][j - 1] + similar(A[i - 1], B[j - 1]),
                              score[i - 1][j] + gap, score[i][j - 1] + gap)
    out = {}
    i, j = len(A), len(B)
    while i > 0 and j > 0:
        if score[i][j] == score[i - 1][j - 1] + similar(A[i - 1], B[j - 1]):
            if similar(A[i - 1], B[j - 1]) > 0:
                out[o[i - 1]] = (n[j - 1], "exact" if A[i - 1] == B[j - 1] else "close")
            i, j = i - 1, j - 1
        elif score[i][j] == score[i - 1][j] + gap:
            i -= 1
        else:
            j -= 1
    accessor_old = {at: t for t, (_, ats) in old.items() for at in ats}
    accessor_new = {t: ats for t, (_, ats) in new.items()}
    return out, accessor_old, accessor_new
