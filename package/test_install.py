"""Run Super LiberTEA - LE's boot install blocks (out/work/install-blocks.lua: LLL luajit.2's block, then the mods block)
under Wine with LLL's Windows Lua 5.1.4 (../lll/work/wine-lua/lua51.exe), as the game runs them at boot.

The blocks write into the scratch prefix's own LOCALAPPDATA, from a fake game folder with a space in its path (the
real layout by name, as ../lll/test_dropin_install.py builds it). Cases: fresh install, repeat start, a missing mod
file, a file you changed, another build of a mod installed over this one, receipts lost (folders adopted), a
foreign mod folder on a fresh install, the first start after an earlier release of this package, and a development
shim in place of a mod (set aside to Backups, the mod installed).
  /usr/bin/python3 -I test_install.py --prefix <scratch WINEPREFIX> --scratch <scratch dir>
"""
import argparse, json, os, shutil, subprocess, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
LUA = HERE.parent / "lll" / "work" / "wine-lua" / "lua51.exe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    args = parser.parse_args()
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    version = receipt["version"]
    stage = HERE / "out" / "stage"
    mods = {m: {p.relative_to(stage / m).as_posix(): p.read_bytes() for p in sorted((stage / m).rglob("*")) if p.is_file()}
            for m in receipt["mods"]}
    total = sum(len(f) for f in mods.values())
    tools = args.scratch / "superlibertea-tools"
    shutil.rmtree(tools, ignore_errors=True)
    tools.mkdir(parents=True)
    shutil.copyfile(LUA, tools / "lua51.exe")
    shutil.copyfile(HERE / "out" / "work" / "install-blocks.lua", tools / "blocks.lua")
    game = args.scratch / "Steam Library" / "Helldivers 2"
    shutil.rmtree(game.parent, ignore_errors=True)
    (game / "data" / "game").mkdir(parents=True)
    (game / "data" / "9ba626afa44a3aa3.patch_0").write_bytes(b"")
    (game / "data" / "game" / "game.dll").write_bytes(b"")
    (game / "bin").mkdir()
    (game / "bin" / "helldivers2.exe").write_bytes(b"")
    env = dict(os.environ, WINEPREFIX=str(args.prefix), WINEDEBUG="-all")
    user = os.environ.get("USER", "steamuser")
    home = args.prefix / "drive_c" / "users" / user / "AppData" / "Local" / "LLL" / "Helldivers2"

    def start():
        run = subprocess.run(["wine", str(tools / "lua51.exe"), str(tools / "blocks.lua")], cwd=game, env=env,
                             capture_output=True, text=True, timeout=600)
        assert run.returncode == 0, run.stderr[-2000:]
        leftovers = sorted(str(p.relative_to(home)) for p in home.rglob("*.tmp"))
        assert not leftovers, leftovers
        lll = (home / "Logs" / "LLL-files.log").read_text().split(" ", 2)[2].strip()
        line = (home / "Logs" / "SuperLiberTEA-files.log").read_text().split(" ", 2)[2].strip()
        return lll, line

    def check(case, line, want):
        ok = want in line
        print("%-40s %s\n%40s %s" % (case, "PASS" if ok else "FAIL", "", line[:400]))
        assert ok, case

    def same(skip=()):
        for mod, files in mods.items():
            for name, data in files.items():
                if (mod, name) not in skip:
                    assert (home / "Mods" / mod / name).read_bytes() == data, (mod, name)

    shutil.rmtree(home.parent, ignore_errors=True)
    lll, line = start()
    check("fresh install: LLL's files", lll, "R38-26251122-luajit.2 files: 7 written, 0 in place")
    check("fresh install: the mods", line, "Super LiberTEA - LE %s mods: %d written, 0 in place" % (version, total))
    assert "left alone" not in line and "problems" not in line
    same()
    for mod, files in mods.items():
        text = (home / "SuperLiberTEA" / (mod + ".txt")).read_text()
        assert text.startswith("release\t%s\n" % version) and text.count("\n") == len(files) + 1, mod
    print("%40s every mod file byte-identical; %d receipts" % ("", len(mods)))
    lll, line = start()
    check("repeat start", line, "mods: 0 written, %d in place" % total)
    check("repeat start: LLL", lll, "files: 0 written, 7 in place")

    (home / "Mods/dbf_mcm/src/core.lua").unlink()
    _, line = start()
    check("a missing mod file", line, "mods: 1 written, %d in place" % (total - 1))
    same()

    (home / "Mods/goose_bridge_combat/config/defaults.cfg").write_bytes(b'{"mine":true}\n')
    _, line = start()
    check("a file you changed", line, "left alone: goose_bridge_combat/config/defaults.cfg (changed since this package wrote it)")
    assert (home / "Mods/goose_bridge_combat/config/defaults.cfg").read_bytes() == b'{"mine":true}\n'
    _, line = start()
    check("... still yours next start", line, "left alone: goose_bridge_combat/config/defaults.cfg")
    (home / "Mods/goose_bridge_combat/config/defaults.cfg").write_bytes(mods["goose_bridge_combat"]["config/defaults.cfg"])

    wj = home / "Mods/dbf_freecam"
    other = json.loads(mods["dbf_freecam"]["manifest.json"])
    other["version"] = "1.3.4-proton-dev"
    (wj / "manifest.json").write_text(json.dumps(other, indent=2) + "\n")
    (wj / "main.lua").write_bytes(b"-- another build\n")
    (wj / "src/look.lua").unlink()
    _, line = start()
    check("another build of a mod installed", line, "left alone: dbf_freecam (another build is installed)")
    assert (wj / "main.lua").read_bytes() == b"-- another build\n" and not (wj / "src/look.lua").exists()
    shutil.rmtree(wj)

    _, line = start()
    check("its folder removed: installed again", line, "mods: %d written" % len(mods["dbf_freecam"]))
    same()

    shutil.rmtree(home / "SuperLiberTEA")
    _, line = start()
    check("receipts lost: folders adopted", line, "mods: 0 written, %d in place" % total)
    assert len(list((home / "SuperLiberTEA").iterdir())) == len(mods)

    # The first start after an earlier release: its receipt names the earlier bytes, which are on disk.
    old = b"-- Super LiberTEA - LE 0.9 copy of this module\n"
    gadget = home / "Mods/goose_temporary_unlocks"
    (gadget / "src/spawner.lua").write_bytes(old)
    old_manifest = mods["goose_temporary_unlocks"]["manifest.json"].replace(b"-le.1", b"-le.0")
    (gadget / "manifest.json").write_bytes(old_manifest)
    record = (home / "SuperLiberTEA/goose_temporary_unlocks.txt").read_text().splitlines()
    patched = []
    for row in record:
        name = row.split("\t")[-1]
        if name == "src/spawner.lua":
            row = "%d\t%d\t%s" % (len(old), zlib.adler32(old), name)
        if name == "manifest.json":
            row = "%d\t%d\t%s" % (len(old_manifest), zlib.adler32(old_manifest), name)
        patched.append(row)
    (home / "SuperLiberTEA/goose_temporary_unlocks.txt").write_text("release\t0.9.0\n" + "\n".join(patched[1:]) + "\n")
    _, line = start()
    check("first start after an earlier release", line, "mods: 2 written, %d in place" % (total - 2))
    same()
    assert (home / "SuperLiberTEA/goose_temporary_unlocks.txt").read_text().startswith("release\t%s\n" % version)

    shutil.rmtree(home.parent, ignore_errors=True)
    (home / "Mods/dbf_freecam").mkdir(parents=True)
    (home / "Mods/dbf_freecam/manifest.json").write_bytes(b'{"id":"dbf_freecam","version":"own"}\n')
    _, line = start()
    check("fresh install beside your own WJ", line, "mods: %d written, 0 in place; left alone: dbf_freecam (another build is installed)"
          % (total - len(mods["dbf_freecam"])))

    # A development shim in place of ASS, as on the porting machine: R46's manifest beside a main.lua that loads the
    # mod from an Arsenal folder by drive path. It is not a build: its folder goes to Backups as it is.
    shutil.rmtree(home.parent, ignore_errors=True)
    dbf = home / "Mods/divers_best_friend"
    (dbf / "config").mkdir(parents=True)
    (dbf / "manifest.json").write_bytes(b'{"id":"divers_best_friend","version":"R46"}\n')
    shim = (b"-- Exact archive-code acceptance through LLL's supported lifecycle.\n"
            b"local f=assert(io.open('Z:/home/goose/.config/hd2arsenal/mods/DBF-ASS-R46-LuaJIT-26251122/Addon/63ab3b8f046c401d.lua','rb'));"
            b"local data=f:read('*a');f:close()\n"
            b"return assert(loadstring(data,'@DBF-ASS-current-archive'))()\n")
    (dbf / "main.lua").write_bytes(shim)
    _, line = start()
    check("a development shim in place of ASS", line, "mods: %d written, 0 in place; set aside: divers_best_friend "
          "(development shim, now Backups/divers_best_friend-shim-" % total)
    assert "left alone" not in line and "problems" not in line
    same()
    backups = list((home / "Backups").glob("divers_best_friend-shim-*"))
    assert len(backups) == 1 and (backups[0] / "main.lua").read_bytes() == shim and (backups[0] / "config").is_dir(), backups
    _, line = start()
    check("... next start", line, "mods: 0 written, %d in place" % total)
    assert "set aside" not in line
    print("all cases pass")


if __name__ == "__main__":
    main()
