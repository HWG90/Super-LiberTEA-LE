#!/usr/bin/env python3
"""Bundle editable Lua modules for the existing LLL archive-addon entry.

Run from any directory: python3 tools/build.py [--check] [--output FILE]
Only Python's standard library is needed. Run tools/check.py for offline checks.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "lua/56e46a6dc1df0a13.lua"
MODULE_MARKER = "    -- @modules@\n"
ADDON_MARKER = "-- @addon@\n"


def sources(root=ROOT):
    """Read modules in stable name order; addon.lua is the archive lifecycle entry."""
    modules = {}
    for path in sorted((root / "src").rglob("*.lua")):
        relative = path.relative_to(root / "src")
        if relative == Path("addon.lua"):
            continue
        name = ".".join(relative.with_suffix("").parts)
        if not re.fullmatch(r"[a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)*", name):
            raise ValueError("invalid module path: " + str(relative))
        if name in modules:
            raise ValueError("duplicate module: " + name)
        modules[name] = (path, path.read_text(encoding="utf-8"))
    if "entry" not in modules:
        raise ValueError("missing entry module")
    return modules


def render(root=ROOT):
    template = (root / "build/bundle.lua").read_text(encoding="utf-8")
    if template.count(MODULE_MARKER) != 1 or template.count(ADDON_MARKER) != 1:
        raise ValueError("bundle template must contain each insertion marker once")
    before, after = template.split(MODULE_MARKER)
    chunks, mapping = [before], []
    line = before.count("\n") + 1
    for name, (path, source) in sources(root).items():
        source = source.rstrip() + "\n"
        block = 'modules["' + name + '"] = function(require)\n' + source + "end\n"
        mapping.append({
            "module": name,
            "source": path.relative_to(root).as_posix(),
            "first_line": line + 1,
            "last_line": line + source.count("\n"),
        })
        chunks.append(block)
        line += block.count("\n")
    addon = (root / "src/addon.lua").read_text(encoding="utf-8").rstrip() + "\n"
    chunks.append(after.replace(ADDON_MARKER, addon))
    bundle = "".join(chunks).encode("utf-8")
    metadata = {
        "resource": "mods/hd2_hud/hd2_hud_plus",
        "sha256": hashlib.sha256(bundle).hexdigest(),
        "modules": mapping,
    }
    return bundle, (json.dumps(metadata, indent=2) + "\n").encode("utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if bundle or line map is stale; write nothing")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args(argv)
    try:
        bundle, mapping = render()
        outputs = ((args.output, bundle), (args.output.with_suffix(".map.json"), mapping))
        if args.check:
            for path, expected in outputs:
                if not path.is_file() or path.read_bytes() != expected:
                    raise ValueError("generated output is stale: " + str(path))
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            for path, contents in outputs:
                path.write_bytes(contents)
    except (OSError, ValueError) as error:
        parser.exit(1, "build: " + str(error) + "\n")
    print(("checked " if args.check else "wrote ") + str(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
