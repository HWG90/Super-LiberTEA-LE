"""Assemble the HD2 Arsenal library folder for LLL on 26568081 (same layout as LLL-R38-26251122-luajit.2).

Contents: manifest.json, icon.png, README.txt, LICENSES/, FILES-SHA256.txt and the option folder LLL-R38 with the
drop-in boot patch from build_lll_boot.py (package-dropin/, checked against RECEIPT-DROPIN.json) plus the readable
boot source as f476df93691895fa.lua (for Arsenal's Lua scan; not part of FILES-SHA256.txt, as in the deployed
folder). Always written to arsenal/<folder>/ here. --library also copies it to ~/.config/hd2arsenal/mods/<folder>:
a new folder only; an existing folder with other content is refused unless --replace. Nothing else is touched:
hd2a_data.json is register_lll.py's job, with Arsenal closed.
  python3 -I build_arsenal_package.py [--library] [--replace]
"""
import argparse, hashlib, json, shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIBRARY = Path.home() / ".config/hd2arsenal/mods"
DEPLOYED = LIBRARY / "LLL-R38-26251122-luajit.2_AR622507"     # icon only; never written
FOLDER = "LLL-R38-LuaJIT-26568081"
GUID = "a6b2d1f0-26568081-4c4c-8c50-554300000001"
OPTION, ARCHIVE = "LLL-R38", "9ba626afa44a3aa3.patch_0"
BUILD, OLD_BUILD = "26568081", "26251122"

README = """Live Lua Loader R38 - LuaJIT (Steam build %(build)s)            package %(release)s

LINUX / PROTON ONLY. IT WILL NOT WORK ON NATIVE WINDOWS (system error 577 for the runtime and cffi DLLs).

WHAT THIS IS
LLL's boot patch hands the game's Lua 5.1 VM over to a LuaJIT 2.1 runtime at startup. The stock scripts,
LLL and your mods then run in LuaJIT with JIT, ffi and bit. The runtime serves LLL's Steam helper inside
the game, so in LuaJIT mode no helper process runs and LLL opens no cffi or nativeinfo DLL. If the runtime
declines, LLL runs in the game's own Lua 5.1 with its cffi DLL and the external Steam helper.
LLL still reports its release as %(label)s (War Journalist checks that name); only the
package and the game build are new.

INSTALL (game closed)
In HD2 Arsenal disable any other Live Lua Loader, enable "LuaJIT VM + Live Lua Loader", keep it last in the
load order, then Purge / Deploy and start the game.

WHAT THE BOOT WRITES
The patch carries LLL's native files and puts them in %%LOCALAPPDATA%%\\LLL\\Helldivers2 (inside the game's
Proton prefix) when they are missing or damaged:
%(files)s
and, only if absent, Native\\luajit-boot.enable (the LuaJIT switch, naming the runtime) and
Service\\game-root.txt (the game folder, for the helper). Coming from %(old_release)s, the first start
switches a luajit-boot.enable that names its runtime (%(old_marker)s) to the new
one, once; "off", any other name and a later rollback are kept. Every start records the outcome in
LLL\\Helldivers2\\Logs\\LLL-files.log, for example
  %(release)s files: 0 written, 7 in place
LuaJITBoot.log in the same folder shows "handoff complete"; Steam\\inprocess.log shows "Stock game hashes
verified". The first line of LiveLuaLoader.log names %(label)s.

ROLLBACK
- LuaJIT off, LLL on: replace the contents of Native\\luajit-boot.enable with the word off, and restart.
  LLL then runs in Lua 5.1 with the same mods. Deleting the file does not work: the next start writes it again.
- Remove: disable the mod in Arsenal, Purge / Deploy, then delete the files listed above.
- Game build %(old_build)s: use the %(old_release)s package; its files stay installed side by side.

KNOWN LIMITS
- Steam build %(build)s only. LLL and the runtime check the game's exe and game.dll; on any other build
  the runtime declines and LLL reports the build as unsupported.

FILES
FILES-SHA256.txt lists this folder. LICENSES/ holds the notices for LuaJIT, cffi-lua, libffi, Lua 5.1.4,
the Bingus Shared Loader helpers and this package.
"""

LUAJIT_NOTICES = """LLL R38 LUAJIT - CONTENTS AND PROVENANCE

The boot patch carries five Windows-format binaries, written to LOCALAPPDATA/LLL/Helldivers2 at boot: the
LuaJIT VM runtime, the cffi and nativeinfo DLLs, LLL's Steam service and its launcher.

The LuaJIT VM runtime (Native/%(marker)s) statically links LuaJIT 2.1
(commit a4c064539ea931274d407e1249b4bb575424a0f4, the library LuaJIT Live 1 used), MIT licence: see
LuaJIT-COPYRIGHT.txt. It compiles in LLL's native/steam_inproc.c, steam_pointer.c and steam_keyboard.c
(the in-process Steam service). Its own C source is not part of the LLL repository.

For exact-byte translation of the game's stock Lua 5.1 bytecode into LuaJIT, the runtime embeds stock
startup chunks of Steam build %(build)s (original bytecode plus recovered Lua source) and LLL's LuaJIT
build. The boot patch preserves the stock startup script (resource f476df93691895fa, SHA256 with its
envelope %(stock)s) as LLL's Steam builds do. This
required preservation is disclosed; no claim of a licence grant over the game's code or assets is made.

The cffi DLL (hd2_cffi_<hash>.dll) is built from cffi-lua, libffi and Lua 5.1.4 headers: see cffi-lua.txt,
libffi.txt and lua-5.1.4.txt. The native helpers are built from the LLL repository's native/ tree.
LLL itself: see LLL-CONTENTS-NOTICES.txt. No repository-wide open-source licence has been selected.
"""

LLL_NOTICES = """CONTENTS AND PROVENANCE
Live Lua Loader for Steam build %(build)s. Original LLL code by Goose; shared runtime helpers adapted from
CowboyBingus under the included 0BSD notices (BSL-V20-*.txt, BSL-HELPERS-LICENSE.txt). MCM UI primitives
come from this project.
The startup patch preserves the supported game startup bytecode in its wrapper; original envelope SHA256:
%(stock)s. No game executable, game DLL, font
asset, personal setting, log or third-party mod is included.
The Steam service and launcher are Windows-format x64 programs used through Proton.
No repository-wide open-source license has been selected. Source is available at https://github.com/HWG90/LLL.
"""

ROLES = (("hd2_luajit_runtime_", "the LuaJIT runtime, with LLL's Steam service inside"), ("hd2_cffi_", "cffi, for LLL in Lua 5.1"),
         ("hd2_nativeinfo_", "native HUD font helper, for LLL in Lua 5.1"), ("lll_steam_service_", "LLL's Steam helper, for LLL in Lua 5.1"),
         ("lll_steam_launcher_", "starts the helper, for LLL in Lua 5.1"))


def sha(b):
    return hashlib.sha256(b).hexdigest()


def tree(root):
    return {str(p.relative_to(root)): sha(p.read_bytes()) for p in sorted(root.rglob("*")) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--library", action="store_true")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    dropin = json.loads((HERE / "RECEIPT-DROPIN.json").read_text())
    patch = (HERE / "package-dropin" / ARCHIVE).read_bytes()
    assert sha(patch) == dropin["patch_sha256"] and dropin["same_lll_and_prologue_as"] == receipt["patch_sha256"]
    source = (HERE / "work" / "boot-source.lua").read_bytes()
    lll = Path(receipt["lll_checkout"])
    names = [n.replace("/", "\\") for prefix, _ in ROLES for n in dropin["files"] if n.split("/")[1].startswith(prefix)]
    width = max(map(len, names)) + 3
    values = dict(build=BUILD, old_build=OLD_BUILD, release=dropin["release"], label=dropin["release_label"], marker=dropin["marker"],
                  old_release=dropin["upgrade"]["from_release"], old_marker=dropin["upgrade"]["from_marker"],
                  stock=receipt["stock_startup_sha256"],
                  files="\n".join("  " + n.ljust(width) + role for n, (_, role) in zip(names, ROLES)))
    manifest = {"Version": 1, "Guid": GUID, "Name": "Live Lua Loader R38 - LuaJIT (%s)" % BUILD,
                "Description": "Live Lua Loader with the LuaJIT VM for Steam build %s, Linux/Proton only. "
                               "Writes its native files to %%LOCALAPPDATA%%\\LLL\\Helldivers2 at boot. See README.txt." % BUILD,
                "IconPath": "icon.png",
                "Options": [{"Name": "LuaJIT VM + Live Lua Loader", "Include": [OPTION],
                             "Description": "Required. LLL's boot patch with its native files; hands off to the LuaJIT "
                                            "runtime, or runs LLL in Lua 5.1 if the runtime declines."}]}
    vendor = lll / "native/cffi/vendor"
    files = {"manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(), "icon.png": (DEPLOYED / "icon.png").read_bytes(),
             "README.txt": (README % values).encode(),
             "LICENSES/LuaJIT-COPYRIGHT.txt": (lll / "docs/LUAJIT-COPYRIGHT.txt").read_bytes(),
             "LICENSES/cffi-lua.txt": (vendor / "cffi-lua/COPYING.md").read_bytes(),
             "LICENSES/libffi.txt": (vendor / "libffi/LICENSE").read_bytes(),
             "LICENSES/lua-5.1.4.txt": (vendor / "lua-5.1.4/COPYRIGHT").read_bytes(),
             "LICENSES/LLL-R38-LUAJIT-NOTICES.txt": (LUAJIT_NOTICES % values).encode(),
             "LICENSES/LLL-CONTENTS-NOTICES.txt": (LLL_NOTICES % values).encode(),
             OPTION + "/" + ARCHIVE: patch, OPTION + "/" + ARCHIVE + ".gpu_resources": b"", OPTION + "/" + ARCHIVE + ".stream": b""}
    for name in ("BSL-V20-LICENSE.txt", "BSL-HELPERS-LICENSE.txt", "BSL-V20-PROVENANCE.txt"):
        files["LICENSES/" + name] = (lll / "docs" / name).read_bytes()
    assert OLD_BUILD not in (README % values).replace(values["label"], "").replace(values["old_release"], "").replace("build %s:" % OLD_BUILD, "")
    files["FILES-SHA256.txt"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(files.items())).encode()
    files[OPTION + "/f476df93691895fa.lua"] = source
    out = HERE / "arsenal" / FOLDER
    shutil.rmtree(out, ignore_errors=True)
    for name, data in files.items():
        (out / name).parent.mkdir(parents=True, exist_ok=True)
        (out / name).write_bytes(data)
    result = {"folder": FOLDER, "staged": str(out), "manifest_guid": GUID, "release": dropin["release"], "lll_release_label": dropin["release_label"],
              "patch_sha256": dropin["patch_sha256"], "marker": dropin["marker"], "files": tree(out), "library": None}
    if args.library:
        target = LIBRARY / FOLDER
        if target.exists() and tree(target) != tree(out):
            assert args.replace, "%s exists with other content; --replace to overwrite it" % target
            shutil.rmtree(target)
        if not target.exists():
            shutil.copytree(out, target)
        assert tree(target) == tree(out)
        result["library"] = str(target)
    (HERE / "ARSENAL-PACKAGE.json").write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
