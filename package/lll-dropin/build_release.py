"""Pack an LLL R38 LuaJIT release for HWG90/LLL: one HD2 Arsenal mod, nothing else to install.

LLL-<release>.zip holds the drop-in boot patch (build_lll_dropin.py --release <release>): the live boot patch with
the release's native files inside, which the boot writes to LOCALAPPDATA/LLL/Helldivers2 when they are missing.
Checks: the drop-in has the live build's LLL source and prologue (RECEIPT-DROPIN*.json against RECEIPT.json), the
release's LLL commit composes that same Lua 5.1 source and holds the LLL files the runtime compiled in, and the
embedded files are the copies that ran live in the Proton prefix, when the prefix exists. The archive is
reproducible (fixed order and timestamps). Output: release/<release>/ (or --out) with SHA256SUMS.txt and
RELEASE-RECEIPT.json; notes.md there is written by hand. LLL's tools need the lz4 module, and the deflate bytes
depend on zlib: R38's zips come from /usr/bin/python3 3.14 (zlib-ng 1.3.1), e.g. a venv on it with lz4 such as
~/Worktrees/linux-hd2/wj-26251122/dist/toolchain/venv (zlib 1.3.2 gives other bytes for the same members).
  <python> build_release.py [--release R38-26251122-luajit.1 | R38-26251122-luajit.2] [--out <dir>]
"""
import argparse, hashlib, json, re, subprocess, sys, zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_lll_boot as B  # noqa: E402
import build_lll_dropin as D  # noqa: E402

ICON = Path("/home/goose/Documents/ChatGPT/Linux HD2/runtime-modules/windows-test/release-lll/LLL-LuaJIT-Live-26088801.zip")
PREFIX = Path("/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2")
GUID = "d3345340-0392-4d91-9807-409ed41d241a"
OPTION = "LLL-R38"
ARCHIVE = "9ba626afa44a3aa3.patch_0"

MANIFEST = {"Version": 1, "Guid": GUID, "Name": "Live Lua Loader R38 - LuaJIT (26251122)",
            "Description": "Live Lua Loader with the LuaJIT VM for Steam build 26251122, Linux/Proton only. "
                           "Writes its native files to %LOCALAPPDATA%\\LLL\\Helldivers2 at boot. See README.txt.",
            "IconPath": "icon.png",
            "Options": [{"Name": "LuaJIT VM + Live Lua Loader", "Include": [OPTION],
                         "Description": "Required. LLL's boot patch with its native files; hands off to the LuaJIT "
                                        "runtime, or runs LLL in Lua 5.1 if the runtime declines."}]}

README_1 = """Live Lua Loader R38 - LuaJIT (Steam build 26251122)            release R38-26251122-luajit.1

LINUX / PROTON ONLY. IT WILL NOT WORK ON NATIVE WINDOWS (system error 577 for the runtime and cffi DLLs).

WHAT THIS IS
LLL's boot patch hands the game's Lua 5.1 VM over to a LuaJIT 2.1 runtime at startup. The stock scripts,
LLL and your mods then run in LuaJIT with JIT, ffi and bit. LLL keeps its Steam helper (filesystem, input
and screenshot services), so mods that need it, such as DBF-MCM and War Journalist, work. If the runtime
declines, LLL runs in the game's own Lua 5.1 with its cffi DLL.

INSTALL (game closed)
In HD2 Arsenal disable any other Live Lua Loader, import this ZIP, enable "LuaJIT VM + Live Lua Loader",
keep it last in the load order, then Purge / Deploy and start the game.

WHAT THE BOOT WRITES
The patch carries LLL's native files and puts them in %LOCALAPPDATA%\\LLL\\Helldivers2 (inside the game's
Proton prefix) when they are missing or damaged:
  Native\\hd2_cffi_915da533d47a3f9c.dll             cffi for Lua 5.1 mods
  Native\\hd2_nativeinfo_8d03e036881e4ddc.dll       native HUD font helper
  Native\\hd2_luajit_runtime_8a19f22d787b667c.dll   the LuaJIT runtime
  Service\\lll_steam_service_580905da64a3642d.exe   LLL's Steam helper
  Service\\lll_steam_launcher_e8a5c0fffbc8d802.exe  starts the helper
and, only if absent, Native\\luajit-boot.enable (the LuaJIT switch, naming the runtime) and
Service\\game-root.txt (the game folder, for the helper). Every start records the outcome in
LLL\\Helldivers2\\Logs\\LLL-files.log, for example
  R38-26251122-luajit.1 files: 0 written, 7 in place
LuaJITBoot.log in the same folder shows "LuaJIT ready ... running LLL boot source ba2148a7..." and
"handoff complete"; the first line of LiveLuaLoader.log names R38-26251122-luajit.1.

ROLLBACK
- LuaJIT off, LLL on: replace the contents of Native\\luajit-boot.enable with the word off, and restart.
  LLL then runs in Lua 5.1 with the same mods. Deleting the file does not work: the next start writes it again.
- Remove: disable the mod in Arsenal, Purge / Deploy, then delete the files listed above.

KNOWN LIMITS
- Steam build 26251122 only. LLL and the runtime check the game's exe and game.dll; on any other build
  the runtime declines and LLL reports the build as unsupported.
- War Journalist Proton gates screenshot capture, Subject and keyboard cleanup on LLL's release label;
  builds from 15c649b on accept R38-26251122-luajit.1.

FILES
FILES-SHA256.txt lists this archive. LICENSES/ holds the notices for LuaJIT, cffi-lua, libffi, Lua 5.1.4,
the Bingus Shared Loader helpers and this package.
"""

LUAJIT_NOTICES_1 = """LLL R38 LUAJIT - CONTENTS AND PROVENANCE

The boot patch carries five Windows-format binaries, written to LOCALAPPDATA/LLL/Helldivers2 at boot: the
LuaJIT VM runtime, the cffi and nativeinfo DLLs, LLL's Steam service and its launcher.

The LuaJIT VM runtime (Native/hd2_luajit_runtime_8a19f22d787b667c.dll) statically links LuaJIT 2.1
(commit a4c064539ea931274d407e1249b4bb575424a0f4, the library LuaJIT Live 1 used), MIT licence: see
LuaJIT-COPYRIGHT.txt. Its own C source is not part of the LLL repository.

For exact-byte translation of the game's stock Lua 5.1 bytecode into LuaJIT, the runtime embeds nine
stock startup chunks of Steam build 26251122 (original bytecode plus recovered Lua source) and LLL's
LuaJIT build (SHA256 ba2148a7fa1ee39ecb30e5cbef815dc2f5ce565559706cbc654c322997955178). The boot patch
preserves the stock startup script (resource f476df93691895fa, SHA256 with its envelope
e0c2f6b48225c07cc612d9f412c9b050abcf5c04093dd5f2b9b425d8878d0841) as LLL's Steam builds do. This
required preservation is disclosed; no claim of a licence grant over the game's code or assets is made.

The cffi DLL (hd2_cffi_<hash>.dll) is built from cffi-lua, libffi and Lua 5.1.4 headers: see cffi-lua.txt,
libffi.txt and lua-5.1.4.txt. The native helpers are built from the LLL repository's native/ tree.
LLL itself: see LLL-CONTENTS-NOTICES.txt. No repository-wide open-source licence has been selected.
"""

LLL_NOTICES = """CONTENTS AND PROVENANCE
Live Lua Loader for Steam build 26251122. Original LLL code by Goose; shared runtime helpers adapted from
CowboyBingus under the included 0BSD notices (BSL-V20-*.txt, BSL-HELPERS-LICENSE.txt). MCM UI primitives
come from this project.
The startup patch preserves the supported game startup bytecode in its wrapper; original envelope SHA256:
e0c2f6b48225c07cc612d9f412c9b050abcf5c04093dd5f2b9b425d8878d0841. No game executable, game DLL, font
asset, personal setting, log or third-party mod is included.
The Steam service and launcher are Windows-format x64 programs used through Proton.
No repository-wide open-source license has been selected. Source is available at https://github.com/HWG90/LLL.
"""

README_2 = """Live Lua Loader R38 - LuaJIT (Steam build 26251122)            release R38-26251122-luajit.2

LINUX / PROTON ONLY. IT WILL NOT WORK ON NATIVE WINDOWS (system error 577 for the runtime and cffi DLLs).

WHAT THIS IS
LLL's boot patch hands the game's Lua 5.1 VM over to a LuaJIT 2.1 runtime at startup. The stock scripts,
LLL and your mods then run in LuaJIT with JIT, ffi and bit. The runtime now serves LLL's Steam helper
inside the game (filesystem, keyboard and pointer services, same requests and checks), so in LuaJIT mode
no helper process runs and LLL opens no cffi or nativeinfo DLL. Mods that need the helper, such as DBF-MCM
and War Journalist, work. Screenshots are refused in-process, as they already failed on Proton (Wine's
capture API is a stub); War Journalist captures with its Linux host worker instead. If the runtime
declines, LLL runs in the game's own Lua 5.1 with its cffi DLL and the external Steam helper, exactly as
in R38-26251122-luajit.1. LLL still reports its release as R38-26251122-luajit.1; only the package is new.

INSTALL (game closed)
In HD2 Arsenal disable any other Live Lua Loader, import this ZIP, enable "LuaJIT VM + Live Lua Loader",
keep it last in the load order, then Purge / Deploy and start the game. It is the same Arsenal mod as
R38-26251122-luajit.1 (same ID and option).

WHAT THE BOOT WRITES
The patch carries LLL's native files and puts them in %LOCALAPPDATA%\\LLL\\Helldivers2 (inside the game's
Proton prefix) when they are missing or damaged:
  Native\\hd2_luajit_runtime_9a596e2f766ff92c.dll   the LuaJIT runtime, with LLL's Steam service inside
  Native\\hd2_cffi_915da533d47a3f9c.dll             cffi, for LLL in Lua 5.1
  Native\\hd2_nativeinfo_8d03e036881e4ddc.dll       native HUD font helper, for LLL in Lua 5.1
  Service\\lll_steam_service_580905da64a3642d.exe   LLL's Steam helper, for LLL in Lua 5.1
  Service\\lll_steam_launcher_e8a5c0fffbc8d802.exe  starts the helper, for LLL in Lua 5.1
and, only if absent, Native\\luajit-boot.enable (the LuaJIT switch, naming the runtime) and
Service\\game-root.txt (the game folder, for the helper). Coming from R38-26251122-luajit.1, the first start
switches a luajit-boot.enable that names its runtime (hd2_luajit_runtime_8a19f22d787b667c.dll) to the new
one, once; "off", any other name and a later rollback are kept. Every start records the outcome in
LLL\\Helldivers2\\Logs\\LLL-files.log, for example
  R38-26251122-luajit.2 files: 0 written, 7 in place
LuaJITBoot.log in the same folder shows "LLL in-process service registered: hd2.lll_host v1",
"LuaJIT ready ... running LLL boot source c4b4c220..." and "handoff complete"; Steam\\inprocess.log shows
"Stock game hashes verified" and which reader each pointer lease used. The first line of LiveLuaLoader.log
names R38-26251122-luajit.1.

ROLLBACK
- Previous runtime (if you came from R38-26251122-luajit.1): replace the contents of Native\\luajit-boot.enable
  with hd2_luajit_runtime_8a19f22d787b667c.dll and restart. It is still installed and uses the external helper.
- LuaJIT off, LLL on: replace the contents of Native\\luajit-boot.enable with the word off, and restart.
  LLL then runs in Lua 5.1 with the same mods. Deleting the file does not work: the next start writes it again.
- Remove: disable the mod in Arsenal, Purge / Deploy, then delete the files listed above.

KNOWN LIMITS
- Steam build 26251122 only. LLL and the runtime check the game's exe and game.dll; on any other build
  the runtime declines and LLL reports the build as unsupported.
- In LuaJIT mode, mouse movement and wheel for input leases (War Journalist freecam, DBF-MCM) are read from
  the game's own raw input through a read-only message hook; Steam\\inprocess.log names the reader.
- War Journalist Proton gates screenshot capture, Subject and keyboard cleanup on LLL's release label;
  builds from 15c649b on accept R38-26251122-luajit.1, which this release keeps.

FILES
FILES-SHA256.txt lists this archive. LICENSES/ holds the notices for LuaJIT, cffi-lua, libffi, Lua 5.1.4,
the Bingus Shared Loader helpers and this package.
"""

LUAJIT_NOTICES_2 = """LLL R38 LUAJIT - CONTENTS AND PROVENANCE

The boot patch carries five Windows-format binaries, written to LOCALAPPDATA/LLL/Helldivers2 at boot: the
LuaJIT VM runtime, the cffi and nativeinfo DLLs, LLL's Steam service and its launcher.

The LuaJIT VM runtime (Native/hd2_luajit_runtime_9a596e2f766ff92c.dll) statically links LuaJIT 2.1
(commit a4c064539ea931274d407e1249b4bb575424a0f4, the library LuaJIT Live 1 used), MIT licence: see
LuaJIT-COPYRIGHT.txt. It compiles in LLL's native/steam_inproc.c, steam_pointer.c and steam_keyboard.c
(the in-process Steam service) unchanged. Its own C source is not part of the LLL repository.

For exact-byte translation of the game's stock Lua 5.1 bytecode into LuaJIT, the runtime embeds nine
stock startup chunks of Steam build 26251122 (original bytecode plus recovered Lua source) and LLL's
LuaJIT build (SHA256 c4b4c22083821bcdc0604ac225f57cab27e68e207ef09f69aaee3eb7eae3a9ea). The boot patch
preserves the stock startup script (resource f476df93691895fa, SHA256 with its envelope
e0c2f6b48225c07cc612d9f412c9b050abcf5c04093dd5f2b9b425d8878d0841) as LLL's Steam builds do. This
required preservation is disclosed; no claim of a licence grant over the game's code or assets is made.

The cffi DLL (hd2_cffi_<hash>.dll) is built from cffi-lua, libffi and Lua 5.1.4 headers: see cffi-lua.txt,
libffi.txt and lua-5.1.4.txt. The native helpers are built from the LLL repository's native/ tree.
LLL itself: see LLL-CONTENTS-NOTICES.txt. No repository-wide open-source licence has been selected.
"""

# lll: the checkout tagged for the release. runtime_sources: LLL files the release's runtime compiled or embedded,
# with the hashes the runtime build pins (HD2 runtime-modules/vm-poc/lll_native/SHA256SUMS, make_embedded_lll_inproc.py).
RELEASES = {
    "R38-26251122-luajit.1": dict(lll=Path("/home/goose/Worktrees/linux-hd2/lll-26251122"),   # claude/lll-26251122
                                  stamp=(2026, 10, 31, 0, 0, 0), readme=README_1, notices=LUAJIT_NOTICES_1, runtime_sources={}),
    "R38-26251122-luajit.2": dict(lll=Path("/home/goose/Worktrees/linux-hd2/lll-r38-luajit2"),  # LLL_JIT_Live
                                  stamp=(2026, 11, 1, 0, 0, 0), readme=README_2, notices=LUAJIT_NOTICES_2,
                                  runtime_sources={"native/steam_inproc.c": "0cd8b2736372efc76737ba1cd69bbdf3c405110fb4d6ca5c7dacf5ed7cbcfa9c",
                                                   "native/steam_pointer.c": "38ad907bb8f2593cada46438ccd7d01e90d39bba8039578311202ece5fbf384b",
                                                   "native/steam_keyboard.c": "e96b5142f55789d15997e10d9a5bfcd4170f5973512106bf9c81209bdf47a136",
                                                   "src/steam/transport_inproc.lua": "bd6a9c5845351a7bd3b0211f1d6b89477839dd4dbd4b7f0f4c097b6fa44169d8"}),
}


def sha(b):
    return hashlib.sha256(b).hexdigest()


def pack(path, files, stamp):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, stamp)
            info.compress_type, info.external_attr = zipfile.ZIP_DEFLATED, 0o644 << 16
            z.writestr(info, data)
    return path.read_bytes()


def composes(lll, source, receipt):
    """The checkout's tools/build_steam_release.py gives the drop-in's Lua 5.1 source, with its stock boot and names."""
    stock = bytes(int(x) for x in re.findall(rb"\\(\d{3})", re.search(rb'loadstring\("((?:\\\d{3})*)","@stock_steam_boot"\)', source).group(1)))
    pick = lambda prefix: next(n for n in receipt["native"] if n.startswith(prefix))  # noqa: E731
    params = dict(release_label=B.LABEL, cffi_name=pick("hd2_cffi_"), launcher_name=pick("lll_steam_launcher_"),
                  nativeinfo_name=pick("hd2_nativeinfo_"))
    return B.compose(lll, stock, params) == source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", choices=sorted(RELEASES), default=D.LATEST)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    label, release = args.release, RELEASES[args.release]
    LLL, OUT = release["lll"], args.out or HERE / "release" / args.release
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    dropin = json.loads(D.paths(label)["receipt"].read_text())
    assert dropin.get("release", label) == label and dropin["same_lll_and_prologue_as"] == receipt["patch_sha256"]
    assert dropin["release_label"] == B.LABEL
    assert dropin["lll_source_sha256"] == receipt["lll_source_sha256"] and dropin["prologue_sha256"] == receipt["prologue_sha256"]
    patch = (D.paths(label)["package"] / ARCHIVE).read_bytes()
    assert sha(patch) == dropin["patch_sha256"]
    files, runtime = D.native_files(label)
    assert {k: sha(v) for k, v in files.items()} == dropin["files"] and runtime == dropin["marker"]
    # What ran live: the prefix holds these same bytes.
    installed = {name: (PREFIX / name).read_bytes() == data for name, data in files.items()} if PREFIX.exists() else {}
    assert all(installed.values()), installed
    # The release's commit is the source: it composes the Lua 5.1 LLL and holds what the runtime compiled in.
    assert composes(LLL, (HERE / "work" / "lll-source.lua").read_bytes(), receipt), "%s does not compose the shipped LLL source" % LLL
    for name, digest in release["runtime_sources"].items():
        assert sha((LLL / name).read_bytes()) == digest, "%s differs from the runtime's copy" % name

    vendor = LLL / "native/cffi/vendor"
    licences = {"LICENSES/LuaJIT-COPYRIGHT.txt": (LLL / "docs/LUAJIT-COPYRIGHT.txt").read_bytes(),
                "LICENSES/cffi-lua.txt": (vendor / "cffi-lua/COPYING.md").read_bytes(),
                "LICENSES/libffi.txt": (vendor / "libffi/LICENSE").read_bytes(),
                "LICENSES/lua-5.1.4.txt": (vendor / "lua-5.1.4/COPYRIGHT").read_bytes(),
                "LICENSES/LLL-R38-LUAJIT-NOTICES.txt": release["notices"].encode(),
                "LICENSES/LLL-CONTENTS-NOTICES.txt": LLL_NOTICES.encode()}
    for name in ("BSL-V20-LICENSE.txt", "BSL-HELPERS-LICENSE.txt", "BSL-V20-PROVENANCE.txt"):
        licences["LICENSES/" + name] = (LLL / "docs" / name).read_bytes()
    icon = zipfile.ZipFile(ICON).read("icon.png")
    arsenal = {"manifest.json": (json.dumps(MANIFEST, indent=2) + "\n").encode(), "icon.png": icon,
               "README.txt": release["readme"].encode(), **licences,
               OPTION + "/" + ARCHIVE: patch, OPTION + "/" + ARCHIVE + ".gpu_resources": b"", OPTION + "/" + ARCHIVE + ".stream": b""}
    arsenal["FILES-SHA256.txt"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(arsenal.items())).encode()

    OUT.mkdir(parents=True, exist_ok=True)
    name = "LLL-%s.zip" % label
    assets = {name: sha(pack(OUT / name, arsenal, release["stamp"]))}
    (OUT / "SHA256SUMS.txt").write_text("".join("%s  %s\n" % (v, k) for k, v in assets.items()))
    commit = subprocess.run(["git", "-C", str(LLL), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    result = {"release": label, "lll_commit": commit, "assets": assets, "patch_sha256": dropin["patch_sha256"],
              "live_patch_with_same_lll": receipt["patch_sha256"], "files": dropin["files"], "same_as_installed": installed}
    if label != B.LABEL:
        stage = json.loads(D.RELEASES[label]["record"].read_text())
        result.update(lll_release_label=B.LABEL, lll_source_composed_by_commit=True, runtime_sources=release["runtime_sources"],
                      runtime_record=str(D.RELEASES[label]["record"]), runtime_live=stage.get("live"),
                      upgrade=dropin["upgrade"], zip_contents={k: sha(v) for k, v in sorted(arsenal.items())})
    (OUT / "RELEASE-RECEIPT.json").write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
