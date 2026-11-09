#!/usr/bin/env python3
"""Build a HudPlusPlus package from a bundle and existing licensed assets.

Usage: python3 tools/package.py --assets-from DIR --bundle FILE --out NEW_DIR

DIR must contain manifest.json, 9ba626afa44a3aa3.patch_0, and its
.gpu_resources and .stream companions. An optional icon.png is copied.
NEW_DIR must not exist. This command creates a package; it never installs it.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile


ARCHIVE = "9ba626afa44a3aa3.patch_0"
BUNDLE_KEY = 0x56E46A6DC1DF0A13
BOOT_KEY = 0xF476DF93691895FA
BUNDLE_FILE = "56e46a6dc1df0a13.lua"
MAGIC = 0xF0000011
HEADER_SIZE, TYPE_SIZE, ENTRY_SIZE = 72, 32, 80
TYPE = struct.Struct("<IIQIIII")
ENTRY = struct.Struct("<7Q6I")


def parse_archive(data):
    """Read archive metadata and bounded CPU payloads without interpreting assets."""
    if len(data) < HEADER_SIZE:
        raise ValueError("truncated archive header")
    magic, types, count = struct.unpack_from("<III", data)
    if magic != MAGIC:
        raise ValueError("unsupported archive magic")
    table_end = HEADER_SIZE + types * TYPE_SIZE + count * ENTRY_SIZE
    if table_end > len(data):
        raise ValueError("truncated archive tables")

    type_rows = [
        bytearray(data[at : at + TYPE_SIZE])
        for at in range(HEADER_SIZE, HEADER_SIZE + types * TYPE_SIZE, TYPE_SIZE)
    ]
    type_ids = [TYPE.unpack(row)[2] for row in type_rows]
    if len(set(type_ids)) != len(type_ids):
        raise ValueError("duplicate archive type")

    start = HEADER_SIZE + types * TYPE_SIZE
    entries = [list(ENTRY.unpack_from(data, start + i * ENTRY_SIZE)) for i in range(count)]
    payloads = {}
    counts = Counter()
    known_types = set(type_ids)
    for entry in entries:
        key = (entry[0], entry[1])
        if key in payloads:
            raise ValueError("duplicate archive resource")
        if entry[1] not in known_types:
            raise ValueError("resource references an unknown archive type")
        at, size = entry[2], entry[7]
        if at < table_end or at > len(data) or size > len(data) - at:
            raise ValueError("resource payload outside archive")
        payloads[key] = data[at : at + size]
        counts[entry[1]] += 1
    for row in type_rows:
        fields = TYPE.unpack(row)
        if fields[3] != counts[fields[2]]:
            raise ValueError("archive type count disagrees with entries")
    return bytearray(data[:HEADER_SIZE]), type_rows, entries, payloads


def rewrite_archive(original, bundle_bytes):
    """Replace the HUD Lua resource, drop its old boot, and preserve other payloads."""
    header, type_rows, entries, payloads = parse_archive(original)
    bundles = [entry for entry in entries if entry[0] == BUNDLE_KEY]
    if len(bundles) != 1:
        raise ValueError("archive must contain exactly one HudPlusPlus bundle")
    lua_type = bundles[0][1]
    entries = [entry for entry in entries if (entry[0], entry[1]) != (BOOT_KEY, lua_type)]
    counts = Counter(entry[1] for entry in entries)
    for row in type_rows:
        struct.pack_into("<I", row, 16, counts[TYPE.unpack(row)[2]])
    payloads[(BUNDLE_KEY, lua_type)] = struct.pack("<II", len(bundle_bytes), 2) + bundle_bytes
    struct.pack_into("<I", header, 8, len(entries))

    offset = HEADER_SIZE + len(type_rows) * TYPE_SIZE + len(entries) * ENTRY_SIZE
    body = bytearray()
    for index, entry in enumerate(entries):
        payload = payloads[(entry[0], entry[1])]
        entry[2], entry[7], entry[12] = offset + len(body), len(payload), index + 1
        body.extend(payload)
    return b"".join(
        [bytes(header), *map(bytes, type_rows), *(ENTRY.pack(*entry) for entry in entries), bytes(body)]
    )


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def package(assets_from, bundle, out):
    """Create a new package directory and return its source/output hash receipt."""
    assets_from, bundle, out = Path(assets_from), Path(bundle), Path(out)
    if out.exists() or out.is_symlink():
        raise FileExistsError("output already exists: " + str(out))
    for name in ("manifest.json", ARCHIVE, ARCHIVE + ".gpu_resources", ARCHIVE + ".stream"):
        if not (assets_from / name).is_file():
            raise FileNotFoundError("missing asset: " + str(assets_from / name))
    manifest = json.loads((assets_from / "manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or not manifest.get("Guid"):
        raise ValueError("asset manifest must contain its existing Guid")
    manifest["Name"] = "HudPlusPlus"
    source = (assets_from / ARCHIVE).read_bytes()
    bundle_bytes = bundle.read_bytes()
    archive = rewrite_archive(source, bundle_bytes)
    receipt = {
        "source_archive_sha256": sha256(source),
        "archive_sha256": sha256(archive),
        "bundle_sha256": sha256(bundle_bytes),
        "guid": manifest["Guid"],
        "asset_sha256": {},
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".hudplusplus-", dir=out.parent) as temporary:
        staged = Path(temporary) / "package"
        staged.mkdir()
        (staged / ARCHIVE).write_bytes(archive)
        (staged / BUNDLE_FILE).write_bytes(bundle_bytes)
        (staged / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        for name in (ARCHIVE + ".gpu_resources", ARCHIVE + ".stream", "icon.png"):
            asset = assets_from / name
            if asset.is_file():
                shutil.copy2(asset, staged / name)
                receipt["asset_sha256"][name] = sha256((staged / name).read_bytes())
        (staged / "BUILD-RECEIPT.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        # Recheck before the rename so an existing directory is never replaced.
        if out.exists() or out.is_symlink():
            raise FileExistsError("output already exists: " + str(out))
        staged.rename(out)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-from", required=True, type=Path)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        # Build to a temporary file and compare before touching the package destination.
        # This also works when the tools are imported outside their own directory.
        with tempfile.TemporaryDirectory(prefix="hudplusplus-bundle-") as temporary:
            current = Path(temporary) / BUNDLE_FILE
            subprocess.run([
                sys.executable, str(Path(__file__).with_name("build.py")), "--output", str(current),
            ], check=True, stdout=subprocess.DEVNULL)
            if args.bundle.read_bytes() != current.read_bytes():
                raise ValueError("bundle is stale or belongs to another source; run tools/build.py first")
        receipt = package(args.assets_from, args.bundle, args.out)
    except (OSError, ValueError, struct.error, subprocess.CalledProcessError) as error:
        parser.exit(1, "package: " + str(error) + "\n")
    print("wrote " + str(args.out) + " (bundle sha256 " + receipt["bundle_sha256"] + ")")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
