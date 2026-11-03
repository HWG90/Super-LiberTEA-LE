"""Write re-derived patterns into a copy of the HUD Plus bundle.

usage: python3 -I apply_rederive.py <bundle.lua> <out bundle.lua> <rederive.json>... [--accept ok]
Only results whose status is "ok" are applied; a later file wins over an earlier one.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luadata  # noqa: E402


def main():
    bundle_path, out_path, *results = sys.argv[1:]
    bundle = open(bundle_path, encoding="utf-8", errors="surrogateescape").read()
    data = luadata.load(bundle_path)
    applied = {}
    for path in results:
        for name, res in json.load(open(path)).items():
            if res.get("status") == "ok" and not res.get("values_only"):
                applied[name] = res["row"]
    for name, row in applied.items():
        data["patterns"][name] = row
    open(out_path, "w", encoding="utf-8", errors="surrogateescape").write(luadata.replace(bundle, data))
    print("applied", len(applied))


main()
