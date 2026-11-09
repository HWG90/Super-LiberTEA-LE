#!/usr/bin/env python3
"""Run offline regression checks without opening the game or changing an install."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import build


ROOT = build.ROOT


def run(*command):
    subprocess.run(command, cwd=ROOT, check=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, help="original v1.0.3 bundle; otherwise read the recorded Git commit")
    args = parser.parse_args(argv)
    if shutil.which("luajit") is None:
        parser.exit(1, "checks require LuaJIT (the runtime this source targets)\n")
    bundle, mapping = build.render()
    if build.OUTPUT.read_bytes() != bundle or build.OUTPUT.with_suffix(".map.json").read_bytes() != mapping:
        parser.exit(1, "generated bundle is stale; run tools/build.py first\n")
    with tempfile.TemporaryDirectory(prefix="hudplusplus-check-") as temporary:
        baseline = Path(temporary) / "upstream.lua"
        if args.upstream:
            baseline.write_bytes(args.upstream.read_bytes())
        else:
            provenance = json.loads((ROOT / "UPSTREAM.json").read_text())
            baseline.write_bytes(subprocess.check_output([
                "git", "show", provenance["commit"] + ":sources/hudplusplus/" + provenance["bundle"],
            ], cwd=ROOT))
        provenance = json.loads((ROOT / "UPSTREAM.json").read_text())
        if hashlib.sha256(baseline.read_bytes()).hexdigest() != provenance["sha256"]:
            parser.exit(1, "upstream bundle does not match the recorded v1.0.3 source\n")
        run("python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v")
        source_files = [str(path) for path in sorted((ROOT / "src").rglob("*.lua"))]
        run("luajit", "tests/test_bundle.lua", str(baseline), str(build.OUTPUT), *source_files)
        for test in sorted((ROOT / "tests").glob("test_*.lua")):
            if test.name == "test_bundle.lua":
                continue
            if test.name == "test_native_bits.lua":
                run("luajit", str(test), "src", str(baseline))
            else:
                run("luajit", str(test))
        run("luajit", "builder/native-work/hud-plus-port/tests/test_channel_text.lua", str(build.OUTPUT))
    print("All offline checks passed. These checks do not exercise in-game behavior.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
