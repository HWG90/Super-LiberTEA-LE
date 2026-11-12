"""Archive/package regression checks using small synthetic resources."""

from collections import Counter
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hud_package", ROOT / "tools/package.py")
pkg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pkg)
LUA, MATERIAL = 0xA14E8DFA2CD117E2, 0xE7A86F39513684F1


def archive(boot=True):
    resources = [(pkg.BUNDLE_KEY, LUA, b"old HUD"), (9, MATERIAL, b"texture\x00payload")]
    if boot:
        resources.insert(0, (pkg.BOOT_KEY, LUA, b"old boot"))
    counts = Counter(kind for _, kind, _ in resources)
    header = bytearray(bytes([0xAB]) * pkg.HEADER_SIZE)
    struct.pack_into("<III", header, 0, pkg.MAGIC, 2, len(resources))
    type_rows = [pkg.TYPE.pack(31, 32, kind, counts[kind], 41, 42, 43) for kind in (LUA, MATERIAL)]
    offset = pkg.HEADER_SIZE + 2 * pkg.TYPE_SIZE + len(resources) * pkg.ENTRY_SIZE
    entries, payloads = [], []
    for index, (key, kind, payload) in enumerate(resources):
        entries.append(pkg.ENTRY.pack(key, kind, offset, 111, 222, 333, 444, len(payload), 55, 66, 77, 88, index + 1))
        payloads.append(payload)
        offset += len(payload)
    return bytes(header) + b"".join(type_rows + entries + payloads)


class ArchiveTests(unittest.TestCase):
    def test_boot_removed_and_other_metadata_preserved(self):
        original = archive()
        old_header, old_types, old_entries, old_payloads = pkg.parse_archive(original)
        built = pkg.rewrite_archive(original, b"new HUD")
        header, types, entries, payloads = pkg.parse_archive(built)
        self.assertEqual(header[:8] + header[12:], old_header[:8] + old_header[12:])
        self.assertNotIn((pkg.BOOT_KEY, LUA), payloads)
        self.assertEqual(payloads[(pkg.BUNDLE_KEY, LUA)], struct.pack("<II", 7, 2) + b"new HUD")
        self.assertEqual(payloads[(9, MATERIAL)], old_payloads[(9, MATERIAL)])
        for old, new in zip(old_types, types):
            self.assertEqual(old[:16] + old[20:], new[:16] + new[20:])
        self.assertEqual([pkg.TYPE.unpack(row)[3] for row in types], [1, 1])
        remaining = [entry for entry in old_entries if entry[0] != pkg.BOOT_KEY]
        for old, new in zip(remaining, entries):
            self.assertEqual(old[:2] + old[3:7] + old[8:12], new[:2] + new[3:7] + new[8:12])
        self.assertEqual([entry[12] for entry in entries], [1, 2])

    def test_already_ported_archive_does_not_decrement_type_again(self):
        built = pkg.rewrite_archive(archive(False), b"new")
        _, types, entries, _ = pkg.parse_archive(built)
        self.assertEqual(len(entries), 2)
        self.assertEqual([pkg.TYPE.unpack(row)[3] for row in types], [1, 1])
        self.assertEqual(pkg.rewrite_archive(built, b"new"), built)

    def test_rejects_truncated_and_invalid_archives(self):
        original = archive()
        for malformed in (b"", original[:71], original[:140], original[:-1]):
            with self.subTest(length=len(malformed)), self.assertRaises(ValueError):
                pkg.rewrite_archive(malformed, b"new")
        wrong_magic = bytearray(original)
        struct.pack_into("<I", wrong_magic, 0, 0)
        with self.assertRaisesRegex(ValueError, "magic"):
            pkg.parse_archive(wrong_magic)
        huge_count = bytearray(original)
        struct.pack_into("<I", huge_count, 8, 0xFFFFFFFF)
        with self.assertRaisesRegex(ValueError, "tables"):
            pkg.parse_archive(huge_count)
        bad_offset = bytearray(original)
        struct.pack_into("<Q", bad_offset, pkg.HEADER_SIZE + 2 * pkg.TYPE_SIZE + 16, 1)
        with self.assertRaisesRegex(ValueError, "payload"):
            pkg.parse_archive(bad_offset)
        bad_count = bytearray(original)
        struct.pack_into("<I", bad_count, pkg.HEADER_SIZE + 16, 99)
        with self.assertRaisesRegex(ValueError, "count"):
            pkg.parse_archive(bad_count)

    def test_missing_bundle_is_rejected(self):
        missing = bytearray(archive())
        at = pkg.HEADER_SIZE + 2 * pkg.TYPE_SIZE + pkg.ENTRY_SIZE
        struct.pack_into("<Q", missing, at, 123)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            pkg.rewrite_archive(missing, b"new")


class PackageTests(unittest.TestCase):
    def test_command_refuses_stale_bundle_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stale = root / "stale.lua"
            stale.write_text("return {}\n")
            out = root / "out"
            with patch("sys.stderr"), self.assertRaises(SystemExit) as error:
                pkg.main(["--assets-from", str(root), "--bundle", str(stale), "--out", str(out)])
            self.assertEqual(error.exception.code, 1)
            self.assertFalse(out.exists())

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assets = self.root / "assets"
        self.assets.mkdir()
        self.bundle = self.root / "bundle.lua"
        self.bundle.write_bytes(b"new HUD")
        self.out = self.root / "output"
        (self.assets / "manifest.json").write_text(json.dumps({"Guid": "existing-id", "Name": "old", "Other": 123}))
        (self.assets / pkg.ARCHIVE).write_bytes(archive())
        for name, data in ((pkg.ARCHIVE + ".gpu_resources", b"gpu"), (pkg.ARCHIVE + ".stream", b""), ("icon.png", b"icon")):
            (self.assets / name).write_bytes(data)

    def test_package_keeps_guid_manifest_fields_and_companion_assets(self):
        receipt = pkg.package(self.assets, self.bundle, self.out)
        manifest = json.loads((self.out / "manifest.json").read_text())
        self.assertEqual(manifest, {"Guid": "existing-id", "Name": "HudPlusPlus", "Other": 123})
        for name in receipt["asset_sha256"]:
            self.assertEqual((self.out / name).read_bytes(), (self.assets / name).read_bytes())
        self.assertEqual((self.out / pkg.BUNDLE_FILE).read_bytes(), self.bundle.read_bytes())
        self.assertEqual(json.loads((self.out / "BUILD-RECEIPT.json").read_text()), receipt)

    def test_guid_option_replaces_manifest_guid_and_is_validated(self):
        guid = "0f8fad5b-d9cb-469f-a165-70867728950e"
        receipt = pkg.package(self.assets, self.bundle, self.out, guid=guid)
        manifest = json.loads((self.out / "manifest.json").read_text())
        self.assertEqual(manifest, {"Guid": guid, "Name": "HudPlusPlus", "Other": 123})
        self.assertEqual(receipt["guid"], guid)
        for bad in ("", "not-a-guid", guid.upper(), "{" + guid + "}"):
            with self.subTest(guid=bad), self.assertRaisesRegex(ValueError, "guid"):
                pkg.package(self.assets, self.bundle, self.root / "refused", guid=bad)
            self.assertFalse((self.root / "refused").exists())

    def test_receipt_note_and_line_map_are_recorded(self):
        line_map = self.root / "bundle.map.json"
        line_map.write_text('{"modules": []}\n')
        note = {"build": "123", "values": {"verified": 2, "inferred": 1}}
        receipt = pkg.package(self.assets, self.bundle, self.out, note=note, line_map=line_map)
        self.assertEqual(receipt["note"], note)
        self.assertEqual((self.out / "56e46a6dc1df0a13.map.json").read_bytes(), line_map.read_bytes())
        self.assertEqual(receipt["line_map_sha256"], pkg.sha256(line_map.read_bytes()))
        self.assertEqual(json.loads((self.out / "BUILD-RECEIPT.json").read_text()), receipt)
        with self.assertRaises(FileNotFoundError):
            pkg.package(self.assets, self.bundle, self.root / "refused", line_map=self.root / "absent.json")
        self.assertFalse((self.root / "refused").exists())
        with self.assertRaisesRegex(ValueError, "note"):
            pkg.package(self.assets, self.bundle, self.root / "refused", note=["not", "an", "object"])

    def test_default_receipt_has_no_optional_fields(self):
        receipt = pkg.package(self.assets, self.bundle, self.out)
        self.assertEqual(
            sorted(receipt), ["archive_sha256", "asset_sha256", "bundle_sha256", "guid", "source_archive_sha256"]
        )
        self.assertFalse((self.out / "56e46a6dc1df0a13.map.json").exists())

    def test_existing_output_and_source_directory_are_never_overwritten(self):
        self.out.mkdir()
        sentinel = self.out / "keep"
        sentinel.write_bytes(b"unchanged")
        with self.assertRaises(FileExistsError):
            pkg.package(self.assets, self.bundle, self.out)
        with self.assertRaises(FileExistsError):
            pkg.package(self.assets, self.bundle, self.assets)
        self.assertEqual(sentinel.read_bytes(), b"unchanged")

    def test_missing_assets_and_bad_manifest_leave_no_partial_output(self):
        (self.assets / (pkg.ARCHIVE + ".stream")).unlink()
        with self.assertRaises(FileNotFoundError):
            pkg.package(self.assets, self.bundle, self.out)
        self.assertFalse(self.out.exists())
        (self.assets / (pkg.ARCHIVE + ".stream")).write_bytes(b"")
        (self.assets / "manifest.json").write_text("[]")
        with self.assertRaisesRegex(ValueError, "Guid"):
            pkg.package(self.assets, self.bundle, self.out)
        self.assertFalse(self.out.exists())


if __name__ == "__main__":
    unittest.main()
