"""Run Super LiberTEA - LE's boot install blocks (out/work/install-blocks-<dbf>.lua: LLL R38-26568081-luajit.1's block,
then the mods block of that DBF variant) under Wine with LLL's Windows Lua 5.1.4 (the 26251122 line's
lll/work/wine-lua/lua51.exe), as the game runs them at boot.

The blocks write into the scratch prefix's own LOCALAPPDATA, from a fake game folder with a space in its path (the
real layout by name). Cases: fresh install, repeat start, a missing mod file, a file you changed, another build of a
mod installed over this one, receipts lost (folders adopted), a foreign mod folder on a fresh install, the first
start after an earlier release of this package, files an earlier release wrote and this one no longer ships (removed
unless you changed them), a development shim in place of a mod (set aside to Backups, the mod installed), a DBF
installed another way beside the chosen one (left alone, reported), switching the DBF choice both ways (the other DBF
goes to Backups), and the upgrades from the two published releases a player can come from, each run from that
release's own install blocks into each DBF choice of this one: 1.0.4 (game build 26251122, both of its DBF choices:
LLL's runtime marker moves to the new runtime, every mod follows, the old build's files leave the mod folders) and
1.0.5 (26568081, DBF Modular only: LLL's files stay, the mods are in place).
  /usr/bin/python3 -I test_install.py --prefix <scratch WINEPREFIX> --scratch <scratch dir>
"""
import argparse, hashlib, json, os, shutil, subprocess, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The 26251122 line of this package (releases 1.0.0 to 1.0.4): its Wine Lua and 1.0.4's install blocks as built.
OLD_LINE = Path("/home/goose/Projects/Linux HD2 Mods/.claude/worktrees/democracy-overlord-arsenal-0a3429/builds/26251122")
LUA = OLD_LINE / "lll" / "work" / "wine-lua" / "lua51.exe"
OLD_RELEASE = OLD_LINE / "super-libertea"
# 1.0.5 of this line, as published: its install block and staged mods, kept by hand before 1.0.6 was built
# (out/ is not tracked: out/released/1.0.5/), checked here against RECEIPT-1.0.5.json.
RELEASED_105 = HERE / "out" / "released" / "1.0.5"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    args = parser.parse_args()
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    version = receipt["version"]
    stage = HERE / "out" / "stage"
    every = {m: {p.relative_to(stage / m).as_posix(): p.read_bytes() for p in sorted((stage / m).rglob("*")) if p.is_file()}
             for m in receipt["mods"]}
    tools = args.scratch / "superlibertea-tools"
    shutil.rmtree(tools, ignore_errors=True)
    tools.mkdir(parents=True)
    shutil.copyfile(LUA, tools / "lua51.exe")
    mods, total = {}, 0

    def use(dbf):
        # The boot install of one DBF variant: its mods are what same() and the counts check.
        nonlocal mods, total
        shutil.copyfile(HERE / "out" / "work" / ("install-blocks-%s.lua" % dbf), tools / "blocks.lua")
        mods = {m: every[m] for m in receipt["variants"][dbf]["mods"]}
        total = sum(len(f) for f in mods.values())

    default, alternative = list(receipt["variants"])
    lll_release = receipt["variants"][default]["boot"]["lll_release"]
    marker = receipt["variants"][default]["boot"]["marker"]
    use(default)
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
    check("fresh install: LLL's files", lll, "%s files: 7 written, 0 in place" % lll_release)
    assert (home / "Native/luajit-boot.enable").read_bytes() == (marker + "\n").encode()
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

    # An earlier release shipped two files this one does not (1.0.1's ASS carried DBF-HUD's weapon readout): the one
    # still as it wrote it is removed, the one you changed stays.
    dbf = home / "Mods/goose_bridge_combat"
    gone, kept = b"-- a module as an earlier release wrote it\n", b"-- another one as it wrote it\n"
    (dbf / "src/retired_a.lua").write_bytes(gone)
    (dbf / "src/retired_b.lua").write_bytes(b"-- your edit\n")
    with (home / "SuperLiberTEA/goose_bridge_combat.txt").open("a") as f:
        for name, data in (("src/retired_a.lua", gone), ("src/retired_b.lua", kept)):
            f.write("%d\t%d\t%s\n" % (len(data), zlib.adler32(data), name))
    _, line = start()
    check("files an earlier release no longer ships", line, "mods: 0 written, %d in place, 1 removed; left alone: "
          "goose_bridge_combat/src/retired_b.lua (changed since an earlier release wrote it; no longer part of this mod)" % total)
    assert not (dbf / "src/retired_a.lua").exists() and (dbf / "src/retired_b.lua").read_bytes() == b"-- your edit\n"
    _, line = start()
    check("... next start", line, "mods: 0 written, %d in place" % total)
    assert "removed" not in line and "left alone" not in line
    same()

    shutil.rmtree(home.parent, ignore_errors=True)
    (home / "Mods/dbf_freecam").mkdir(parents=True)
    (home / "Mods/dbf_freecam/manifest.json").write_bytes(b'{"id":"dbf_freecam","version":"own"}\n')
    _, line = start()
    check("fresh install beside your own WJ", line, "mods: %d written, 0 in place; left alone: dbf_freecam (another build is installed)"
          % (total - len(mods["dbf_freecam"])))

    # A development shim in place of ASS, as on the porting machine: R46's manifest beside a main.lua that loads the
    # mod from an Arsenal folder by drive path. It is not a build: its folder goes to Backups as it is. This is also
    # the fresh install of the other DBF choice.
    use(alternative)
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
    assert not (home / "Mods/dbf_modular").exists()
    backups = list((home / "Backups").glob("divers_best_friend-shim-*"))
    assert len(backups) == 1 and (backups[0] / "main.lua").read_bytes() == shim and (backups[0] / "config").is_dir(), backups
    _, line = start()
    check("... next start", line, "mods: 0 written, %d in place" % total)
    assert "set aside" not in line

    # A DBF installed another way beside the variant's DBF: left alone and reported, never moved.
    use(default)
    shutil.rmtree(home.parent, ignore_errors=True)
    (home / "Mods/divers_best_friend").mkdir(parents=True)
    (home / "Mods/divers_best_friend/manifest.json").write_bytes(b'{"id":"divers_best_friend","version":"own"}\n')
    _, line = start()
    check("a DBF you installed beside the choice", line, "mods: %d written, 0 in place; left alone: divers_best_friend "
          "(another DBF provider is installed; set one to false in LLL.cfg)" % total)
    assert (home / "Mods/divers_best_friend/manifest.json").read_bytes() == b'{"id":"divers_best_friend","version":"own"}\n'

    # Switching the DBF choice in Arsenal: the next start installs the chosen DBF and moves the one this package wrote.
    shutil.rmtree(home.parent, ignore_errors=True)
    start()
    first = next(m for m in receipt["variants"][alternative]["sets_aside"])
    use(alternative)
    second = receipt["variants"][default]["sets_aside"][0]
    _, line = start()
    check("switch to %s" % alternative, line, "mods: %d written, %d in place; set aside: %s (the other DBF choice, now Backups/%s-superlibertea-"
          % (len(every[second]), total - len(every[second]), first, first))
    assert not (home / "Mods" / first).exists() and not (home / "SuperLiberTEA" / (first + ".txt")).exists()
    same()
    use(default)
    _, line = start()
    check("... and back to %s" % default, line, "mods: %d written, %d in place; set aside: %s (the other DBF choice"
          % (len(every[first]), total - len(every[first]), second))
    same()
    _, line = start()
    check("... next start", line, "mods: 0 written, %d in place" % total)
    assert "set aside" not in line and "left alone" not in line

    def upgrade(label, blocks, old_version, variant, old_stage, target):
        """A start of an earlier published release from its own install blocks, then this release's start (DBF choice
        target) over what it left."""
        shutil.rmtree(home.parent, ignore_errors=True)
        (tools / "blocks.lua").write_bytes(blocks)
        lll, line = start()
        before = {m: {p.relative_to(old_stage / m).as_posix() for p in (old_stage / m).rglob("*") if p.is_file()} for m in variant["mods"]}
        check("%s: its own start" % label, line, "Super LiberTEA - LE %s mods: %d written, 0 in place" % (old_version, sum(map(len, before.values()))))
        check("%s: LLL" % label, lll, "%s files: 7 written, 0 in place" % variant["boot"]["lll_release"])
        assert (home / "Native/luajit-boot.enable").read_bytes() == (variant["boot"]["marker"] + "\n").encode()
        use(target)
        lll, line = start()
        label = "upgrade from %s to %s" % (label, target)
        if variant["boot"]["lll_release"] == lll_release:
            check("%s: LLL" % label, lll, "%s files: 0 written, 7 in place" % lll_release)
        else:
            # LLL: the five new files and the marker; the game folder note stays. The old release's files stay beside them.
            check("%s: LLL" % label, lll, "%s files: 6 written, 1 in place" % lll_release)
            assert "Native/luajit-boot.enable" in lll and (home / "Native" / variant["boot"]["marker"]).is_file()
        assert "problems" not in lll and (home / "Native/luajit-boot.enable").read_bytes() == (marker + "\n").encode()
        shared = [m for m in mods if m in before]
        unchanged = sum(1 for m in shared for n, d in mods[m].items() if n in before[m] and (old_stage / m / n).read_bytes() == d)
        gone = sum(len(before[m] - set(mods[m])) for m in shared)
        aside = [m for m in receipt["variants"][target]["sets_aside"] if m in before]
        want = "Super LiberTEA - LE %s mods: %d written, %d in place" % (version, total - unchanged, unchanged)
        want += ", %d removed" % gone if gone else ""
        want += "".join("; set aside: %s (the other DBF choice, now Backups/%s-superlibertea-" % (m, m) for m in aside)
        check("%s: the mods" % label, line, want)
        assert "left alone" not in line and "problems" not in line and (aside or "set aside" not in line) and (gone or "removed" not in line)
        same()
        for m in shared:
            left = {p.relative_to(home / "Mods" / m).as_posix() for p in (home / "Mods" / m).rglob("*") if p.is_file()}
            assert left == set(mods[m]), (m, sorted(left ^ set(mods[m]))[:5])
        for m in aside:
            assert not (home / "Mods" / m).exists() and not (home / "SuperLiberTEA" / (m + ".txt")).exists()
            (backup,) = (home / "Backups").glob(m + "-superlibertea-*")
            assert {p.relative_to(backup).as_posix() for p in backup.rglob("*") if p.is_file()} == before[m]
        for m in mods:
            assert (home / "SuperLiberTEA" / (m + ".txt")).read_text().startswith("release\t%s\n" % version), m
        lll, line = start()
        check("... next start", line, "mods: 0 written, %d in place" % total)
        check("... next start: LLL", lll, "files: 0 written, 7 in place")
        assert "set aside" not in line and "left alone" not in line and "removed" not in line

    def published(blocks, old_version, variant):
        # The blocks are that release's own: LLL's install block, then its mods block, by the hashes in its receipt.
        cut = blocks.index(("do -- Super LiberTEA - LE %s:" % old_version).encode())
        assert hashlib.sha256(blocks[:cut]).hexdigest() == variant["boot"]["lll_install_block_sha256"]
        assert hashlib.sha256(blocks[cut:]).hexdigest() == variant["boot"]["mods_block_sha256"], "not %s's published mods block" % old_version

    # From the published 1.0.4 (game build 26251122), with each of its DBF choices.
    old = json.loads((OLD_RELEASE / "RECEIPT.json").read_text())
    assert old["version"] == "1.0.4" and old["game_build"] == "26251122"
    for choice, variant in old["variants"].items():
        blocks = (OLD_RELEASE / "out" / "work" / ("install-blocks-%s.lua" % choice)).read_bytes()
        published(blocks, "1.0.4", variant)
        for target in receipt["variants"]:
            upgrade("1.0.4 (%s)" % choice, blocks, "1.0.4", variant, OLD_RELEASE / "out" / "stage", target)

    # From the published 1.0.5 (this game build, DBF Modular only).
    old = json.loads((HERE / "RECEIPT-1.0.5.json").read_text())
    assert old["version"] == "1.0.5" and old["game_build"] == receipt["game_build"] and list(old["variants"]) == ["modular"]
    assert (RELEASED_105 / "install-blocks-modular.lua").is_file(), "%s is missing: 1.0.5's install block as built (see README.md)" % RELEASED_105
    blocks = (RELEASED_105 / "install-blocks-modular.lua").read_bytes()
    published(blocks, "1.0.5", old["variants"]["modular"])
    for m, row in old["mods"].items():
        staged = [q for q in (RELEASED_105 / "stage" / m).rglob("*") if q.is_file()]
        assert len(staged) == row["files"] and hashlib.sha256((RELEASED_105 / "stage" / m / "manifest.json").read_bytes()).hexdigest() == row["manifest_sha256"], m
    for target in receipt["variants"]:
        upgrade("1.0.5", blocks, "1.0.5", old["variants"]["modular"], RELEASED_105 / "stage", target)

    # LuaJIT switched off by hand ("off" in the marker) stays off through the upgrade from 1.0.4.
    shutil.rmtree(home.parent, ignore_errors=True)
    (tools / "blocks.lua").write_bytes((OLD_RELEASE / "out" / "work" / "install-blocks-modular.lua").read_bytes())
    start()
    (home / "Native/luajit-boot.enable").write_bytes(b"off\n")
    use(default)
    lll, _ = start()
    check("upgrade from 1.0.4 with LuaJIT off", lll, "%s files: 5 written, 2 in place" % lll_release)
    assert (home / "Native/luajit-boot.enable").read_bytes() == b"off\n"
    print("all cases pass")


if __name__ == "__main__":
    main()
