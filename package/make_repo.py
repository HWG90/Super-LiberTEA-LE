"""Assemble the shareable Super LiberTEA - LE repository: the package's build files and the source of every item.

Run after build_package.py collect + build. Writes <repo>/package/ (this folder's tracked files), <repo>/sources/<item>/
(each with SOURCE.md naming where it came from) and leaves README.md, CREDITS.md and .gitignore to the repo itself.
Nothing here is captured game code: the runtime's evidence and the Gadget Kit's research stay out, and binaries
are only the ones that ship. The release zip is uploaded as a release asset, never committed.

The 26568081 line. Against the 26251122 line's make_repo:
- sources/ass and sources/hudplusplus (1.0.4's items, not ported to 26568081) are left exactly as the repo has them.
- sources/gadget-kit comes from the kit's own repository (HWG90/GooseGadgetKit, private; GADGET_REPO at
  GADGET_COMMIT) under the rule of 1.0.0 to 1.0.3: the kit's source without its research and build output
  (GADGET_PRIVATE: dist/, docs/, port51/, native/memory/) and without binaries, then every non-binary file of the kit
  as it ships. Until 1.0.4 that folder was the kit's working copy, edited in the release repo: when it holds
  uncommitted changes this script stops before writing anything, so that work is never overwritten.
  /usr/bin/python3 -I make_repo.py --repo ~/Projects/Super-LiberTEA-LE
"""
import argparse, io, json, re, shutil, struct, subprocess, sys, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_package import PARTS, GADGET_KIT, GAME_BUILD, LLL_RELEASE, MODULAR_CREDITS, NOT_PORTED, WORKSPACE  # noqa: E402

INPUTS = HERE / "out" / "inputs"
SHIPPED = HERE / "out" / "package"
STAGE = HERE / "out" / "stage"  # the LLL folder mods as shipped (Gadget Kit LE and DBF Modular after their changes)
FOLDERS = {part["key"]: part["folder"] for part in PARTS}
LUA_TYPE = 0xA14E8DFA2CD117E2
BINARY = re.compile(r"\.(dll|exe|lib|pdb|obj|o|a|so|bin|dmp|zip)$", re.I)
WORKTREES = Path("/home/goose/Worktrees/linux-hd2")   # the 26568081 ports, one worktree and branch each (STATUS.md)
GADGET_REPO, GADGET_COMMIT, GADGET_FOLDER = Path("/home/goose/Worktrees/goose-gadgets/gadget-kit-26568081"), "15eaa54", "Goose Gadget Kit/"
GADGET_PRIVATE = ("dist/", "docs/", "port51/", "native/memory/")   # the kit's research and build output: never public
KEPT = ("ass", "hudplusplus")   # 26251122 items this line does not ship: their sources stay as the repo has them


def git_export(repo, commit, dest, paths=(), keep=lambda name: True, strip=""):
    """The files of <commit> (optionally only <paths>) into dest, as git stores them, less a leading <strip>."""
    data = subprocess.run(["git", "-C", str(repo), "archive", "--format=tar", commit, *paths], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if member.isfile() and keep(member.name):
                assert member.name.startswith(strip), member.name
                target = dest / member.name[len(strip):]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile(member).read())
    return subprocess.run(["git", "-C", str(repo), "rev-parse", commit], capture_output=True, text=True, check=True).stdout.strip()


def copy_tree(src, dest, keep=lambda rel: True):
    count = 0
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src).as_posix()
        if path.is_file() and keep(rel):
            (dest / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest / rel)
            count += 1
    return count


def lua_resources(patch):
    """Plain-text Lua resources of a patch archive: {key hex: text}. The envelope is a length and a format word."""
    data = patch.read_bytes()
    magic, types, count = struct.unpack_from("<III", data)
    assert magic == 0xF0000011, patch
    out = {}
    for index in range(count):
        entry = struct.unpack_from("<7Q6I", data, 72 + types * 32 + index * 80)
        if entry[1] != LUA_TYPE:
            continue
        body = data[entry[2]:entry[2] + entry[7]]
        size, kind = struct.unpack_from("<II", body)
        text = body[8:8 + size]
        assert kind == 2 and size == len(body) - 8 and not text.startswith(b"\x1bLua"), (patch, hex(entry[0]))
        out["%016x" % entry[0]] = text
    return out


def extract_part(part, dest, root=None):
    """Every Lua resource of every patch the package ships for an Arsenal part, by option folder (root: a part that
    ships only as a separate download, read from its inputs)."""
    count, root = 0, root or SHIPPED / FOLDERS[part]
    for patch in sorted(root.rglob("*.patch_*")):
        if re.search(r"\.patch_\d+$", patch.name):
            folder = patch.parent.relative_to(root).as_posix()
            for key, text in lua_resources(patch).items():
                target = dest / folder / (key + ".lua")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(text)
                count += 1
    return count


def source_md(dest, title, lines):
    (dest / "SOURCE.md").write_text("# %s\n\n%s\n" % (title, "\n".join(lines)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", required=True, type=Path)
    repo = parser.parse_args().repo.expanduser()
    inputs = json.loads((HERE / "INPUTS.json").read_text())
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    assert sorted(KEPT) == sorted({"divers_best_friend": "ass", "hud-plus": "hudplusplus"}[k] for k in NOT_PORTED)
    dirty = subprocess.run(["git", "-C", str(repo), "status", "--porcelain", "--", "sources/gadget-kit"], capture_output=True, text=True, check=True).stdout
    if dirty:
        sys.exit("%s/sources/gadget-kit has uncommitted changes (%d paths): it was the Gadget Kit's working copy. Commit or move "
                 "that work first; this release takes the kit's source from %s at %s. Nothing was written."
                 % (repo, len(dirty.splitlines()), GADGET_REPO, GADGET_COMMIT))
    shutil.rmtree(repo / "package", ignore_errors=True)
    for path in (repo / "sources").iterdir() if (repo / "sources").exists() else []:
        if path.name not in KEPT:
            shutil.rmtree(path) if path.is_dir() else path.unlink()
    package = repo / "package"
    for name in ["build_package.py", "make_repo.py", "mods_install.lua", "test_install.py", "icon.svg", "INPUTS.json", "RECEIPT.json"]:
        (package / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(HERE / name, package / name)
    copy_tree(HERE / "package", package / "package")
    copy_tree(HERE / "gadget-kit-le", package / "gadget-kit-le")
    for name in ["build_lll_boot.py", "build_arsenal_package.py", "dropin_install.lua", "RECEIPT.json", "RECEIPT-DROPIN.json", "ARSENAL-PACKAGE.json"]:
        (package / "lll-dropin" / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(WORKSPACE / "lll" / name, package / "lll-dropin" / name)
    src = repo / "sources"
    report = {}

    dest = src / "live-lua-loader"
    commit = git_export(WORKTREES / "lll-26568081", "1cd9948", dest)
    source_md(dest, "Live Lua Loader (LLL) R38", [
        "HWG90/LLL, branch `indev/lll-26568081`, commit `%s` (package `%s`; LLL still reports" % (commit, LLL_RELEASE),
        "`R38-26251122-luajit.1`, the name War Journalist checks). The Lua 5.1 LLL in the boot patch is composed from this",
        "tree (`tools/build_steam_release.py`); the LuaJIT runtime embeds its in-process variant (see `../luajit-runtime`).",
        "The drop-in boot patch is built by `package/lll-dropin/build_lll_boot.py`. The Megapack's conversions under",
        "`bingus-conversions/` are the 26251122 ones; the 26568081 ports as shipped are in `../vanilla-plus-megapack`."])
    report["live-lua-loader"] = commit

    dest = src / "luajit-runtime"
    paths = ["runtime-modules/vm-poc", "runtime-modules/boot-handoff", "runtime-modules/boot-%s" % GAME_BUILD]
    commit = git_export(WORKTREES / "runtime-26568081", "427ebdfb", dest, paths,
                        keep=lambda n: not BINARY.search(n) or n.endswith("tools/lua32"))
    marker = receipt["variants"]["modular"]["boot"]["marker"]
    source_md(dest, "LuaJIT boot runtime %s" % marker, [
        "The Linux HD2 workspace, branch `indev/runtime-26568081`, commit `%s`: the three folders the runtime is built" % commit,
        "from. `runtime-modules/boot-%s/build_runtime_%s_inproc.sh` is the build; the shipped DLL's sha256 is" % (GAME_BUILD, GAME_BUILD),
        "%s. LuaJIT 2.1 itself is upstream LuaJIT (MIT)," % receipt["variants"]["modular"]["boot"]["lll_files"]["Native/" + marker],
        "linked as `libluajit.a`. `boot-handoff/tools/lua32` is the stock Lua 5.1.4 compiler that compiles the boot chunk."])
    report["luajit-runtime"] = commit

    dest = src / "war-journalist-proton"
    commit = git_export(WORKTREES / "wj-proton-26568081", "bfbaca9", dest, keep=lambda n: not n.endswith((".zip", ".dll", ".exe")))
    wj = inputs["mods"]["dbf_freecam"]
    bridges = sorted(p.name for p in (STAGE / "dbf_freecam").rglob("hd2_nativeinfo_*.dll"))
    assert len(bridges) == 2, bridges
    source_md(dest, "War Journalist (Proton) 1.4.0", [
        "HWG90/DBF_PhotoMode, branch `indev/wj-proton-26568081` (the Proton line, ported to game build %s)," % GAME_BUILD,
        "commit `%s`. The LLL folder mod `dbf_freecam` is built by `python3 tools/build_proton_candidate.py`" % commit,
        "(build %s). Its two native bridges (`%s`, `%s`)" % (wj["build"], *bridges),
        "come from `tools/build_steam_native_bridge.py` and `tools/build_steam_scene_bridge.py`. The 1.2.0 assets (compiled",
        "game resources) ship as they are; their shader sources are under `freecam/assets/`."])
    report["war-journalist-proton"] = commit

    dest = src / "dbf-mcm"
    copy_tree(STAGE / "dbf_mcm", dest / "dbf_mcm")
    source_md(dest, "Mod Configuration Menu (DBF-MCM) %s" % receipt["mods"]["dbf_mcm"]["version"], [
        "The LLL folder mod as shipped: `luajit-ports/dbf_mcm` of the Linux HD2 workspace, branch `indev/dbf-mcm-26568081`,",
        "commit `%s`." % inputs["mods"]["dbf_mcm"]["git"]["commit"]])

    dest = src / "bridge-combat"
    copy_tree(STAGE / "goose_bridge_combat", dest / "goose_bridge_combat")
    commit = git_export(WORKTREES / "bridge-combat-26568081", "eee9f695", dest / "builder",
                        ["native-work/bridge-original"], keep=lambda n: "/out/" not in n and not BINARY.search(n))
    (menu,) = sorted(p.name for p in (STAGE / "goose_bridge_combat" / "native").glob("BridgeCombatWeaponMenu-*.dll"))
    source_md(dest, "Goose Bridge Combat %s" % receipt["mods"]["goose_bridge_combat"]["version"], [
        "`goose_bridge_combat/` is the LLL folder mod as shipped. `builder/native-work/bridge-original` (Linux HD2 workspace,",
        "branch `indev/bridge-combat-26568081`, commit `%s`) assembles it and builds the weapon menu DLL" % commit,
        "`native/%s` from `dll/native/weapon_menu.cpp` (`build_dll.py`, Zig 0.14.1); `port-%s/` holds" % (menu, GAME_BUILD),
        "the port from the 26251122.12 package."])
    report["bridge-combat"] = commit

    # Gadget Kit: the kit's own repository at the commit the shipped kit was staged from, less GADGET_PRIVATE and
    # binaries; then the kit as it ships (non-binary), which must agree with that commit wherever both have a file.
    dest = src / "gadget-kit"
    commit = git_export(GADGET_REPO, GADGET_COMMIT, dest, [GADGET_FOLDER.rstrip("/")], strip=GADGET_FOLDER,
                        keep=lambda n: not BINARY.search(n) and not n[len(GADGET_FOLDER):].startswith(GADGET_PRIVATE) and "/__pycache__/" not in n)
    assert json.loads((dest / "manifest.json").read_text())["version"] == GADGET_KIT, "the Gadget Kit commit is not the collected kit"
    kit = INPUTS / "goose_temporary_unlocks"
    differ = [p.relative_to(kit).as_posix() for p in kit.rglob("*") if p.is_file() and not BINARY.search(p.name)
              and (dest / p.relative_to(kit)).is_file() and (dest / p.relative_to(kit)).read_bytes() != p.read_bytes()]
    assert not differ, "the Gadget Kit commit differs from the collected kit: %s" % differ[:5]
    copy_tree(kit, dest, keep=lambda rel: not BINARY.search(rel))
    source_md(dest, "Goose Gadget Kit %s (the LE build ships only Spawner and First Person)" % GADGET_KIT.split("-cffi-")[0], [
        "The kit's source for Steam build %s with the Lua exactly as %s ships. Super LiberTEA - LE builds" % (GAME_BUILD, GADGET_KIT),
        "Gadget Kit LE from it with `package/gadget-kit-le/` (its main.lua and src/mcm.lua) and leaves out the Unlocks and",
        "Gameplay modules (`package/build_package.py`, LE_DROPPED). Native helpers: `native/first_person/` and",
        "`native/near_clip/` (`build*.py`); the binaries ship in the release."])
    report["gadget-kit"] = "%s (%s)" % (GADGET_KIT, commit)

    dest = src / "dbf-modular"
    copy_tree(STAGE / "dbf_modular", dest / "dbf_modular")
    commit = git_export(WORKTREES / "dbf-modular-26568081", inputs["mods"]["dbf_modular"]["git"]["commit"], dest,
                        ["tests", "tools", "design", "README.md", "LICENSE", "CREDITS.md"], keep=lambda n: not BINARY.search(n))
    credits = (dest / "CREDITS.md").read_bytes()
    assert credits.count(MODULAR_CREDITS) == 1
    (dest / "CREDITS.md").write_bytes(credits.replace(MODULAR_CREDITS, b""))
    source_md(dest, "DBF Modular %s" % receipt["mods"]["dbf_modular"]["version"], [
        "`dbf_modular/` is the LLL folder mod as shipped (without the withheld native Heat Limiter). `tests/`, `tools/` and",
        "`design/` are the project's (branch `indev/dbf-modular-26568081`, commit `%s`). Its offline tests read" % commit,
        "snapshots of LLL and DBF-MCM, whose sources are in `../live-lua-loader` and `../dbf-mcm`."])
    report["dbf-modular"] = commit

    # Nova Weapon FOV has no repository of its own: the port's stage, tests and notes from the game-update workspace.
    dest = src / "nova-weapon-fov"
    assert {p.relative_to(STAGE / "goose_nova_weapon_fov").as_posix(): p.read_bytes() for p in (STAGE / "goose_nova_weapon_fov").rglob("*") if p.is_file()} == \
        {p.relative_to(WORKSPACE / "mods/nova-weapon-fov/stage/goose_nova_weapon_fov").as_posix(): p.read_bytes()
         for p in (WORKSPACE / "mods/nova-weapon-fov/stage/goose_nova_weapon_fov").rglob("*") if p.is_file()}
    copy_tree(STAGE / "goose_nova_weapon_fov", dest / "stage" / "goose_nova_weapon_fov")
    copy_tree(WORKSPACE / "mods/nova-weapon-fov/tests", dest / "tests")
    for name in ("README.md", "apply_26568081.py", "layout_check.py"):
        (dest / "port").mkdir(exist_ok=True)
        shutil.copyfile(WORKSPACE / "maps/nova-weapon-fov" / name, dest / "port" / name)
    source_md(dest, "Nova Weapon FOV %s" % receipt["mods"]["goose_nova_weapon_fov"]["version"], [
        "The Linux HD2 Mods workspace, `builds/%s`: `stage/goose_nova_weapon_fov` is the LLL folder mod as shipped," % GAME_BUILD,
        "`tests/harness.lua` its offline checks, `port/` the notes and scripts of the port from the 26251122 build."])
    report["nova-weapon-fov"] = "builds/%s" % GAME_BUILD

    for part, folder, title, notes in [
        ("diverkit", "diverkit", "DiverKit Alpha 8.14.31, LuaJIT %s r11" % GAME_BUILD,
         ["Original: Nexus Mods (Helldivers 2) mod 16493. LuaJIT port for build %s by Goose. Extracted from the shipped" % GAME_BUILD,
          "patch, by option folder; each file is one Lua resource named by its resource key."]),
        ("transmog", "transmog", "HD2 Transmog Foundation 0.2.4, LuaJIT %s" % GAME_BUILD,
         ["Original by its authors (see the package's README.md and THIRD-PARTY-LICENSES.txt). LuaJIT port by Goose.",
          "Extracted from the shipped patches, by option folder; each file is one Lua resource named by its resource key."]),
        ("sgd", "smarter-guard-dogs", "Smarter Guard Dogs & Sentries 5.2.0, LuaJIT %s" % GAME_BUILD,
         ["Original: Nexus Mods (Helldivers 2) mod 16610. LuaJIT port for build %s by Goose." % GAME_BUILD,
          "Extracted from the shipped patches, by option folder; each file is one Lua resource named by its resource key."]),
        ("megapack", "vanilla-plus-megapack", "Vanilla Plus Megapack v42, LuaJIT %s" % GAME_BUILD,
         ["Original by CowboyBingus and the authors of the bundled mods (VanillaPlusMegapack-README.txt). 25 options ported",
          "to LuaJIT and build %s by Goose. Extracted from the shipped patches, by option folder; each file is one Lua" % GAME_BUILD,
          "resource named by its resource key."]),
    ]:
        dest = src / folder
        count = extract_part(part, dest)
        source_md(dest, title, notes + ["", "%d Lua resources." % count])
        report[folder] = count
    for name in ("README.md", "README.ru.md", "THIRD-PARTY-LICENSES.txt"):
        shutil.copyfile(INPUTS / "transmog" / name, src / "transmog" / name)
    shutil.copyfile(INPUTS / "megapack" / "VanillaPlusMegapack-README.txt", src / "vanilla-plus-megapack" / "VanillaPlusMegapack-README.txt")
    shutil.copyfile(src / "live-lua-loader/bingus-conversions/BetterStratagemBounce/LICENSE", src / "vanilla-plus-megapack" / "LICENSE")
    (repo / "SHA256SUMS.txt").write_text((HERE / "out" / "SHA256SUMS.txt").read_text())
    report["kept as the repo has them"] = [k for k in KEPT if (src / k).exists()]
    print(json.dumps({"repo": str(repo), "zip": receipt["zip"], "sources": report}, indent=1))


if __name__ == "__main__":
    main()
