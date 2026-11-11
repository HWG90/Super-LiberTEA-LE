"""Port Nova Weapon FOV (LLL folder mod goose_nova_weapon_fov, 0.1.0-26251122) to 26568081.

The mod has no source tree of its own: the deployed folder equals the stage committed in Linux HD2 Mods branch
indev/nova-weapon-fov-zoom-92372e (cefd305, builds/26251122/mods/nova-weapon-fov). This copies the deployed folder
(read only) to the stage and applies asserted replacements; the offline harness is copied beside it unchanged.

Evidence (this folder): game.map.json: weapon manager global 0x2CE1EA0 unchanged (high, 63 reference votes, no
dissent); the aim-distance code 0x110AC80 -> 0x110ADE0 (high). layout-check.json: its 99 instructions to the ret are
the same (row terms +0x13C/+0x140/+0x148/+0x14C, request +0x90), the manager users found again read the same global,
and the row stride 0x4D8 is unchanged at the sampled code sites. The mod writes only rows that carry the Nova's key,
its three zooms and exactly the vanilla terms, so a layout change makes it do nothing.
Usage: python3 -I apply_26568081.py [--source DIR] [--stage DIR]
"""
import argparse, hashlib, json, shutil
from pathlib import Path

PFX = Path("/home/goose/.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser")
INSTALLED = PFX / "AppData/Local/LLL/Helldivers2/Mods/goose_nova_weapon_fov"  # read only
STAGE = Path(__file__).resolve().parents[2] / "mods/nova-weapon-fov/stage/goose_nova_weapon_fov"
EDITS = {
    "src/nova.lua": [
        ("-- LAS-44 Nova presentation terms, game.dll 6AE0E5FF (HD2 26251122).", "-- LAS-44 Nova presentation terms, game.dll 6AF322C1 (HD2 26568081).", 1),
        ("-- (game+0x110AC80, written to the kind-6 camera request +0x90):", "-- (game+0x110ADE0, written to the kind-6 camera request +0x90):", 1),
        ("M.STAMP = 0x6AE0E5FF", "M.STAMP = 0x6AF322C1", 1),
        ("M.MANAGER = 0x2CE1EA0", "M.MANAGER = 0x2CE1EA0", 1),  # unchanged on 26568081 (game.map.json)
    ],
    "main.lua": [
        ("(game.dll 6AE0E5FF)", "(game.dll 6AF322C1)", 1),
        ("0.1.0-26251122", "0.1.0-26568081", 2),
    ],
    "manifest.json": [
        ('"version": "0.1.0-26251122"', '"version": "0.1.0-26568081"', 1),
        ("Game build 26251122 only;", "Game build 26568081 only;", 1),
    ],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=INSTALLED)
    ap.add_argument("--stage", type=Path, default=STAGE)
    a = ap.parse_args()
    if a.stage.exists():
        shutil.rmtree(a.stage)
    shutil.copytree(a.source, a.stage)
    for rel, edits in EDITS.items():
        p = a.stage / rel
        text = p.read_text()
        for old, new, count in edits:
            assert text.count(old) == count, "%s: expected %d of %r, found %d" % (rel, count, old, text.count(old))
            text = text.replace(old, new)
        p.write_text(text)
    for p in a.stage.rglob("*"):
        if p.is_file():
            t = p.read_text()
            assert "6AE0E5FF" not in t.upper() and "26251122" not in t, p
    json.loads((a.stage / "manifest.json").read_text())
    receipt = {"stage": str(a.stage), "version": "0.1.0-26568081",
               "files": {str(p.relative_to(a.stage)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(a.stage.rglob("*")) if p.is_file()}}
    (a.stage.parent / "STAGE-RECEIPT.json").write_text(json.dumps(receipt, indent=1) + "\n")
    print("staged", a.stage, len(receipt["files"]), "files")


if __name__ == "__main__":
    main()
