"""Make lll-26251122-luajit-ffi.lua, the LLL source the 26251122 runtime embeds (prepare_handoff.py HD2_HANDOFF_LLL).

It is the R6 runtime's embedded R35 source (../boot-r6-reconstruct/lll-r35-luajit-ffi.lua) with the six values PUC LLL
got for 26251122 (exe and game.dll SHA-256, cffi/nativeinfo/launcher names, game.dll stamp and checksum), then LLL's
release label R38-26251122-luajit.1, as in the PUC boot patch (update workspace builds/26251122/lll/build_lll_boot.py).
Toolchain check first: without the label the substitutions must reproduce the 10-29 source 3952146e..., which
hd2_luajit_runtime_fcd57d52a0068175.dll embeds.
  python3 -I make_embedded_lll.py
"""
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "boot-r6-reconstruct" / "lll-r35-luajit-ffi.lua"
SOURCE_SHA256 = "dfc9450e6a730fa80c3e0a035fd3c5e44df35d88aaae82c4f0c7844bf339550e"
BUILD_SHA256 = "3952146e1cfc4ac99a8cc998a64fc177e3e2fc76e7f4053149681ea4a7e72c6a"
OUTPUT = HERE / "lll-26251122-luajit-ffi.lua"
BUILD = [(b"0acc07debe04714ae04281e1a66bd2eb9d3d85232953e32a93c8a3dd0874eabe", b"257fd7de21a04e8668e02e5c820edf3435176fbde3569765255cc52a5ea20f9d"),
         (b"6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f", b"61dcfcd201dacbf3545c97beb8a5a6186e9850d2670bf60b0e058320b477f6df"),
         (b"hd2_cffi_2e4bcd2f8d3df404.dll", b"hd2_cffi_915da533d47a3f9c.dll"),
         (b"hd2_nativeinfo_f6d3465944c1aea1.dll", b"hd2_nativeinfo_8d03e036881e4ddc.dll"),
         (b"lll_steam_launcher_59c847ffeacf0dcb.exe", b"lll_steam_launcher_e8a5c0fffbc8d802.exe"),
         (b"~=0x6AD7C05D", b"~=0x6AE0E5FF"), (b"~=0x2ED14F0", b"~=0x2ED103A")]
OLD_LABEL, LABEL = b"R35-26088801-cffi-insert-fix.2", b"R38-26251122-luajit.1"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    out = SOURCE.read_bytes()
    assert sha(out) == SOURCE_SHA256, "R35 source changed"
    for old, new in BUILD:
        assert out.count(old) >= 1, old
        out = out.replace(old, new)
    assert sha(out) == BUILD_SHA256, "build substitutions no longer reproduce 3952146e"
    assert out.count(b'release="%s"' % OLD_LABEL) == 1 and out.count(OLD_LABEL) == 1, "release label not found once"
    out = out.replace(OLD_LABEL, LABEL)
    for gone in (b"0acc07debe04714a", b"6d1d4d3bc6fc8480", b"0x6AD7C05D", b"2e4bcd2f8d3df404", b"f6d3465944c1aea1", b"59c847ffeacf0dcb", OLD_LABEL):
        assert gone not in out, gone
    OUTPUT.write_bytes(out)
    print("%s: %d bytes, sha256 %s (release %s)" % (OUTPUT.name, len(out), sha(out), LABEL.decode()))


if __name__ == "__main__":
    main()
