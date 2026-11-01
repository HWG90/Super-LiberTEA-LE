"""Run the drop-in install block (work/dropin-install<suffix>.lua, from build_lll_dropin.py) under Wine with a Windows Lua 5.1.4.

The block writes into the scratch prefix's own LOCALAPPDATA (C:\\users\\<user>\\AppData\\Local), as Proton's game does,
from a fake game folder with a space in its path. Cases: fresh install (folders created), repeat start, a damaged
and a missing file, an "off" marker, a stale game-root.txt, and a start outside the game folder. For a release that
follows another: the earlier release's install, then this one's first start (marker moved on), a rollback to the
earlier runtime (kept), and the earlier marker without a files log (kept).
work/wine-lua/lua51.exe is LLL's vendored Lua 5.1.4 (V=~/Worktrees/linux-hd2/lll-26251122/native/cffi/vendor/lua-5.1.4/src):
  x86_64-w64-mingw32-gcc -O2 -s -o work/wine-lua/lua51.exe $(ls $V/*.c | grep -v -E '/(luac|print)\\.c$') -I$V -lm
  python3 -I test_dropin_install.py --prefix <scratch WINEPREFIX> --scratch <scratch dir> [--release <name>]
"""
import argparse, os, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_lll_dropin as D  # noqa: E402


def block(release):
    files, runtime = D.native_files(release)
    data = D.paths(release)["install"].read_bytes()
    assert data == D.render(files, runtime, release), "%s is stale: rerun build_lll_dropin.py --release %s" % (D.paths(release)["install"].name, release)
    return files, runtime, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--release", choices=sorted(D.RELEASES), default=D.LATEST)
    args = parser.parse_args()
    files, runtime, install = block(args.release)
    tools = args.scratch / "dropin-tools"
    shutil.rmtree(tools, ignore_errors=True)
    tools.mkdir(parents=True)
    shutil.copyfile(HERE / "work" / "wine-lua" / "lua51.exe", tools / "lua51.exe")
    (tools / "block.lua").write_bytes(install)
    upgrade = D.RELEASES[args.release]["upgrade"]
    if upgrade:
        old_files, old_runtime, old_install = block(upgrade[0])
        assert old_runtime == upgrade[1]
        (tools / "earlier.lua").write_bytes(old_install)
    # The fake game folder copies the real layout by name, including what it does not have: the boot archive
    # 9ba626afa44a3aa3 exists only as .patch_N files. `elsewhere` has those but no exe or game.dll.
    game = args.scratch / "Steam Library" / "Helldivers 2"
    elsewhere = args.scratch / "elsewhere"
    shutil.rmtree(game.parent, ignore_errors=True)
    shutil.rmtree(elsewhere, ignore_errors=True)
    for folder in (game, elsewhere):
        (folder / "data").mkdir(parents=True)
        (folder / "data" / "9ba626afa44a3aa3.patch_0").write_bytes(b"")
    (game / "bin").mkdir()
    (game / "bin" / "helldivers2.exe").write_bytes(b"")
    (game / "data" / "game").mkdir()
    (game / "data" / "game" / "game.dll").write_bytes(b"")
    env = dict(os.environ, WINEPREFIX=str(args.prefix), WINEDEBUG="-all")
    user = os.environ.get("USER", "steamuser")
    home = args.prefix / "drive_c" / "users" / user / "AppData" / "Local" / "LLL" / "Helldivers2"
    winpath = subprocess.run(["winepath", "-w", str(game)], env=env, capture_output=True, text=True, check=True).stdout.strip()
    expected = dict(files)
    expected["Native/luajit-boot.enable"] = (runtime + "\n").encode()
    expected["Service/game-root.txt"] = (winpath + "\n").encode()

    def start(cwd=game, script="block.lua"):
        run = subprocess.run(["wine", str(tools / "lua51.exe"), str(tools / script)], cwd=cwd, env=env,
                             capture_output=True, text=True, timeout=180)
        assert run.returncode == 0, run.stderr[-2000:]
        log = (home / "Logs" / "LLL-files.log").read_text()
        leftovers = sorted(str(p.relative_to(home)) for p in home.rglob("*.tmp"))
        assert not leftovers, leftovers
        return log.split(" ", 2)[2].strip(), [l for l in run.stdout.splitlines() if l.startswith("[LLL files]")]

    def check(case, line, want, printed=False):
        ok = want in line
        print("%-34s %s\n%34s %s" % (case, "PASS" if ok else "FAIL", "", line))
        assert ok, case
        return printed

    def marker():
        return (home / "Native" / "luajit-boot.enable").read_bytes()

    shutil.rmtree(home.parent, ignore_errors=True)
    line, printed = start()
    check("fresh install (no LLL folder)", line, "%s files: 7 written, 0 in place" % args.release)
    assert not printed
    for name, data in expected.items():
        assert (home / name).read_bytes() == data, name
    print("%34s every file byte-identical; game-root.txt = %s" % ("", winpath))
    line, _ = start()
    check("repeat start", line, "files: 0 written, 7 in place")
    (home / "Native" / "hd2_cffi_915da533d47a3f9c.dll").write_bytes(b"damaged")
    (home / "Service" / "lll_steam_launcher_e8a5c0fffbc8d802.exe").unlink()
    line, _ = start()
    check("damaged cffi, missing launcher", line, "files: 2 written, 5 in place")
    assert all((home / n).read_bytes() == d for n, d in expected.items())
    (home / "Native" / "luajit-boot.enable").write_bytes(b"off\n")
    line, _ = start()
    check("marker says off", line, "files: 0 written, 7 in place")
    assert marker() == b"off\n"
    (home / "Service" / "game-root.txt").write_bytes(b"C:\\nowhere\\Helldivers 2\n")
    line, _ = start()
    check("stale game-root.txt", line, "files: 1 written, 6 in place (Service/game-root.txt)")
    assert (home / "Service" / "game-root.txt").read_bytes() == expected["Service/game-root.txt"]
    (home / "Service" / "game-root.txt").unlink()
    line, printed = start(elsewhere)
    check("start outside the game folder", line, "problems: Service/game-root.txt: game folder not found")
    assert printed and not (home / "Service" / "game-root.txt").exists()

    if upgrade:
        old_marker = (upgrade[1] + "\n").encode()
        shutil.rmtree(home.parent, ignore_errors=True)
        line, _ = start(script="earlier.lua")
        check("earlier release, fresh install", line, "%s files: 7 written, 0 in place" % upgrade[0])
        assert marker() == old_marker
        line, _ = start()
        check("first start after it", line, "%s files: 2 written, 5 in place (Native/%s, Native/luajit-boot.enable)" % (args.release, runtime))
        assert all((home / n).read_bytes() == d for n, d in expected.items())
        assert (home / "Native" / upgrade[1]).read_bytes() == old_files["Native/" + upgrade[1]]
        print("%34s marker = %s; %s kept for rollback" % ("", runtime, upgrade[1]))
        (home / "Native" / "luajit-boot.enable").write_bytes(old_marker)
        line, _ = start()
        check("rollback to the earlier runtime", line, "files: 0 written, 7 in place")
        assert marker() == old_marker
        (home / "Logs" / "LLL-files.log").unlink()
        line, _ = start()
        check("earlier marker, no files log", line, "files: 0 written, 7 in place")
        assert marker() == old_marker
        (home / "Native" / "hd2_luajit_runtime_0123456789abcdef.dll").write_bytes(b"own build")
        (home / "Native" / "luajit-boot.enable").write_bytes(b"hd2_luajit_runtime_0123456789abcdef.dll\n")
        line, _ = start(script="earlier.lua")
        line, _ = start()
        check("own runtime after earlier release", line, "files: 0 written, 7 in place")
        assert marker() == b"hd2_luajit_runtime_0123456789abcdef.dll\n"
    print("all cases pass")


if __name__ == "__main__":
    main()
