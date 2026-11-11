"""Make lll-26568081-luajit-inproc.lua, the LLL source the 26568081 in-process runtime embeds.

It is lll-26251122-luajit-inproc.lua (c4b4c220..., the source runtime 68d9c55a embeds) with the four build values
LLL commit 1cd9948 changed for 26568081, each found exactly once:
  1. LLL_STEAM_BUILDS exe_sha256 and 2. game_sha256 (steam-build.json);
  3. the HUD font map's game.dll stamp and 4. checksum (src/steam/font.lua; SizeOfImage and the three RVAs unchanged).
Everything else stays byte for byte, including the release label R38-26251122-luajit.1 (War Journalist gates on it).
The LLL checkout is read to prove the font lines are the committed ones.
  python3 -I make_embedded_lll_26568081.py
"""
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
LLL = Path("/home/goose/Worktrees/linux-hd2/lll-26568081")
SOURCE = HERE / "lll-26251122-luajit-inproc.lua"
SOURCE_SHA256 = "c4b4c22083821bcdc0604ac225f57cab27e68e207ef09f69aaee3eb7eae3a9ea"
OUTPUT = HERE / "lll-26568081-luajit-inproc.lua"
STEPS = [(b"257fd7de21a04e8668e02e5c820edf3435176fbde3569765255cc52a5ea20f9d", b"b434f6f326b7759978265f5863ef72e3c5edd4aa5315cc1ef4b640d204eae0bb"),
         (b"61dcfcd201dacbf3545c97beb8a5a6186e9850d2670bf60b0e058320b477f6df", b"08b756f535cdb9bdd1b4953fba53c3dfacd25730a155ea6593e5de63211acf5f"),
         (b"or u32(read(pe+8,4))~=0x6AE0E5FF", b"or u32(read(pe+8,4))~=0x6AF322C1"),
         (b"or u32(read(pe+88,4))~=0x2ED103A", b"or u32(read(pe+88,4))~=0x2ED4502")]
LABEL = b'release="R38-26251122-luajit.1"'


def main():
    out = SOURCE.read_bytes()
    assert hashlib.sha256(out).hexdigest() == SOURCE_SHA256, "26251122 embedded source changed"
    build = json.loads((LLL / "steam-build.json").read_text())
    assert build["build_id"] == "26568081"
    assert build["game"]["bin/helldivers2.exe"].encode() == STEPS[0][1] and build["game"]["data/game/game.dll"].encode() == STEPS[1][1]
    font = (LLL / "src/steam/font.lua").read_bytes()
    for old, new in STEPS:
        assert out.count(old) == 1, old
        out = out.replace(old, new)
    for _, new in STEPS[2:]:
        assert font.count(new) == 1, "LLL font.lua does not carry %r" % new
    assert out.count(LABEL) == 1, "release label not found once"
    assert b"26251122" not in out.replace(LABEL, b"") and b"6AE0" not in out
    OUTPUT.write_bytes(out)
    print("%s: %d bytes, sha256 %s" % (OUTPUT.name, len(out), hashlib.sha256(out).hexdigest()))


if __name__ == "__main__":
    main()
