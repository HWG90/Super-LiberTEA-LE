"""Assemble the shareable Super LiberTEA - LE repository: the package's build files and the source of every item.

Run after build_package.py collect + build. Writes <repo>/package/ (this folder's tracked files), <repo>/sources/<item>/
(each with SOURCE.md naming where it came from) and leaves README.md, CREDITS.md and .gitignore to the repo itself.
Nothing here is captured game code: the runtime's evidence and the Gadget Kit's research stay out, and binaries
are only the ones that ship. The release zip is uploaded as a release asset, never committed.
  /usr/bin/python3 -I make_repo.py --repo ~/Projects/Super-LiberTEA-LE
"""
import argparse, io, json, re, shutil, struct, subprocess, sys, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_package import PARTS  # noqa: E402

INPUTS = HERE / "out" / "inputs"
SHIPPED = HERE / "out" / "package"
STAGE = HERE / "out" / "stage"  # the LLL folder mods as shipped (ASS and Gadget Kit LE after their LE changes)
FOLDERS = {part["key"]: part["folder"] for part in PARTS}
LUA_TYPE = 0xA14E8DFA2CD117E2
BINARY = re.compile(r"\.(dll|exe|lib|pdb|obj|o|a|so|bin|dmp|zip)$", re.I)


def git_export(repo, commit, dest, paths=(), keep=lambda name: True):
    """The files of <commit> (optionally only <paths>) into dest, as git stores them."""
    data = subprocess.run(["git", "-C", str(repo), "archive", "--format=tar", commit, *paths], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if member.isfile() and keep(member.name):
                target = dest / member.name
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
    for sub in ("package", "sources"):
        shutil.rmtree(repo / sub, ignore_errors=True)
    package = repo / "package"
    for name in ["build_package.py", "make_repo.py", "mods_install.lua", "test_install.py", "icon.svg", "INPUTS.json", "RECEIPT.json"]:
        (package / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(HERE / name, package / name)
    copy_tree(HERE / "package", package / "package")
    copy_tree(HERE / "gadget-kit-le", package / "gadget-kit-le")
    lll_dropin = HERE.parent / "lll"
    for name in ["build_lll_boot.py", "build_lll_dropin.py", "dropin_install.lua", "test_dropin_install.py", "build_release.py",
                 "stage_dropin_check.py", "RECEIPT.json", "RECEIPT-DROPIN-luajit.2.json"]:
        (package / "lll-dropin" / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(lll_dropin / name, package / "lll-dropin" / name)
    src = repo / "sources"
    report = {}

    dest = src / "live-lua-loader"
    commit = git_export(Path("/home/goose/Worktrees/linux-hd2/lll-r38-luajit2"), "8b25fad", dest)
    source_md(dest, "Live Lua Loader (LLL) R38", [
        "HWG90/LLL, branch `LLL_JIT_Live`, commit `%s` (tag `R38-26251122-luajit.2`)." % commit,
        "The Lua 5.1 LLL in the boot patch is composed from this tree (`tools/build_steam_release.py`); the LuaJIT runtime",
        "embeds its in-process variant (see `../luajit-runtime`). The drop-in boot patch is built by `package/lll-dropin/`."])
    report["live-lua-loader"] = commit

    dest = src / "luajit-runtime"
    paths = ["runtime-modules/vm-poc", "runtime-modules/boot-handoff", "runtime-modules/boot-26251122"]
    commit = git_export(Path("/home/goose/Worktrees/linux-hd2/runtime-lll-inproc"), "ccafae1", dest, paths,
                        keep=lambda n: not BINARY.search(n) or n.endswith("tools/lua32"))
    source_md(dest, "LuaJIT boot runtime hd2_luajit_runtime_9a596e2f766ff92c.dll", [
        "The Linux HD2 workspace, branch `claude/runtime-lll-inproc`, commit `%s`: the three folders the runtime is built" % commit,
        "from. `runtime-modules/boot-26251122/INPROC-STAGE.json` gives the build command and the expected sha256",
        "(9a596e2f766ff92ca3a7234f4fc7a9add5e2b0e5d1bb1c02acb65b2b1c68ef64). LuaJIT 2.1 itself is upstream LuaJIT (MIT),",
        "linked as `libluajit.a`. `boot-handoff/tools/lua32` is the stock Lua 5.1.4 compiler that compiles the boot chunk."])
    report["luajit-runtime"] = commit

    dest = src / "war-journalist-proton"
    commit = git_export(Path("/home/goose/Documents/ChatGPT/Linux HD2/.claude/worktrees/wj-proton-bone-posing-668ec2/prior-war-journalist"),
                        "09a0940", dest)
    wj = inputs["mods"]["dbf_freecam"]
    source_md(dest, "War Journalist (Proton) 1.3.4, bone posing", [
        "HWG90/DBF_PhotoMode, branch `claude/wj-proton-bone-posing` (the bone-posing line on top of `WJ-Proton` 9613fcf),",
        "commit `%s`. The LLL folder mod `dbf_freecam` is built by" % commit,
        "`python3 tools/build_proton_candidate.py` (build %s). Its two native bridges" % wj["build"],
        "(`hd2_nativeinfo_c1578203689e39b9.dll`, `hd2_nativeinfo_8db3d96f8c3cbb24.dll`) come from `tools/build_steam_native_bridge.py`",
        "and `tools/build_steam_scene_bridge.py`. The 1.2.0 assets (compiled game resources) ship as they are; their shader",
        "sources are under `freecam/assets/`."])
    report["war-journalist-proton"] = commit

    for mod, folder, title, notes in [
        ("dbf_mcm", "dbf-mcm", "Mod Configuration Menu (DBF-MCM) 0.1.74-luajit.5",
         ["The LLL folder mod as shipped: `luajit-ports/dbf_mcm` of the Linux HD2 workspace, branch",
          "`claude/dbf-mcm-inproc-font`, commit `%s`." % inputs["mods"]["dbf_mcm"]["git"]["commit"]]),
        ("divers_best_friend", "ass", "Diver's Best Friend (ASS) R46, LuaJIT 26251122 (LE build)",
         ["The LLL folder mod as shipped (plain LuaJIT; no native files). Built from",
          "`native-work/dbf-ass-luajit/divers_best_friend` of the Linux HD2 workspace, commit `%s`." % inputs["mods"]["divers_best_friend"]["source_commit"],
          "The LE build leaves out DBF-HUD's weapon readout that the port also started (six `src/weapon_status*.lua`",
          "modules and their lines in main.lua; `package/build_package.py`, ASS_DROPPED and ASS_MAIN)."]),
    ]:
        dest = src / folder
        copy_tree(STAGE / mod, dest / mod)
        source_md(dest, title, notes)

    dest = src / "bridge-combat"
    copy_tree(STAGE / "goose_bridge_combat", dest / "goose_bridge_combat")
    commit = git_export(Path("/home/goose/Worktrees/linux-hd2/bridge-combat-26251122"), "39efa48", dest / "builder",
                        ["native-work/bridge-original"], keep=lambda n: "/out/" not in n and not BINARY.search(n))
    source_md(dest, "Goose Bridge Combat 0.1.17-experimental-26251122.12", [
        "`goose_bridge_combat/` is the LLL folder mod as shipped. `builder/native-work/bridge-original` (Linux HD2 workspace,",
        "branch `claude/bridge-combat-26251122`, commit `%s`) assembles it and builds the weapon menu DLL" % commit,
        "`native/BridgeCombatWeaponMenu-bcb24cbfd1cd.dll` from `dll/native/weapon_menu.cpp` (`build_dll.py`, Zig 0.14.1)."])
    report["bridge-combat"] = commit

    dest = src / "gadget-kit"
    kit = Path("/home/goose/Projects/Linux HD2 Mods/builds/26251122/mods/gadget-kit/src")
    copy_tree(kit, dest, keep=lambda rel: not rel.startswith(("dist/", "docs/", "port51/", "native/memory/")) and not BINARY.search(rel)
              and "/__pycache__/" not in rel)
    copy_tree(INPUTS / "goose_temporary_unlocks", dest, keep=lambda rel: not BINARY.search(rel))
    source_md(dest, "Goose Gadget Kit 0.5.10 (the LE build ships only Spawner and First Person)", [
        "The kit's source for Steam build 26251122 with the Lua exactly as 0.5.10 shipped. Super LiberTEA - LE builds",
        "Gadget Kit LE from it with `package/gadget-kit-le/` (its main.lua and src/mcm.lua) and leaves out the Unlocks and",
        "Gameplay modules (`package/build_package.py`, LE_DROPPED). Native ADS helpers: `native/first_person/` and",
        "`native/near_clip/` (`build*.py`); the binaries ship in the release."])

    for part, folder, title, notes in [
        ("diverkit", "diverkit", "DiverKit Alpha 8.14.31, LuaJIT 26251122 r6",
         ["Original: Nexus Mods (Helldivers 2) mod 16493. LuaJIT port for build 26251122 by Goose. Extracted from the shipped",
          "patch, by option folder; each file is one Lua resource named by its resource key."]),
        ("transmog", "transmog", "HD2 Transmog Foundation 0.2.4, LuaJIT 26251122",
         ["Original by its authors (see the package's README.md and THIRD-PARTY-LICENSES.txt). LuaJIT port by Goose.",
          "Extracted from the shipped patches, by option folder; each file is one Lua resource named by its resource key."]),
        ("sgd", "smarter-guard-dogs", "Smarter Guard Dogs & Sentries 5.2.0, LuaJIT 26251122",
         ["Original: Nexus Mods (Helldivers 2) mod 16610. LuaJIT port for builds 26088801 and 26251122 by Goose.",
          "Extracted from the shipped patches, by option folder; each file is one Lua resource named by its resource key."]),
        ("megapack", "vanilla-plus-megapack", "Vanilla Plus Megapack v42, LuaJIT 26251122",
         ["Original by CowboyBingus and the authors of the bundled mods (VanillaPlusMegapack-README.txt). 25 options ported",
          "to LuaJIT and build 26251122 by Goose. Extracted from the shipped patches, by option folder; each file is one Lua",
          "resource named by its resource key."]),
    ]:
        dest = src / folder
        count = extract_part(part, dest)
        source_md(dest, title, notes + ["", "%d Lua resources." % count])
        report[folder] = count
    dest = src / "hudplusplus"
    commit = git_export(Path("/home/goose/Worktrees/linux-hd2/bridge-combat-26251122"), "56de681", dest / "builder",
                        ["native-work/hud-plus-port"], keep=lambda n: not BINARY.search(n))
    count = extract_part("hud-plus", dest / "lua", INPUTS / "hud-plus")
    source_md(dest, "HudPlusPlus r9, LuaJIT 26251122", [
        "HudPlusPlus is HD2 HUD Plus 0.2.9 by DDRK1ng (Nexus Mods, helldivers2/mods/15298) rebuilt for game build 26251122",
        "and renamed. `builder/native-work/hud-plus-port` (Linux HD2 workspace, branch `indev/hud-plus-search-815c13`, commit",
        "`%s`) builds the Arsenal mod from HUD+ 0.2.9: `build_port.py`, the data it reads (`data/`, with" % commit,
        "`manual-26251122.json` giving the evidence for every value found by hand), `tools/` and `tests/`. Its README.md",
        "describes the method; LIVE-CHECK.md lists the first-launch checks. `lua/` holds the Lua the shipped patch",
        "carries, named by resource key (%d file%s)." % (count, "" if count == 1 else "s")])
    report["hudplusplus"] = commit
    for name in ("README.md", "README.ru.md", "THIRD-PARTY-LICENSES.txt"):
        shutil.copyfile(INPUTS / "transmog" / name, src / "transmog" / name)
    shutil.copyfile(INPUTS / "megapack" / "VanillaPlusMegapack-README.txt", src / "vanilla-plus-megapack" / "VanillaPlusMegapack-README.txt")
    shutil.copyfile(src / "live-lua-loader/bingus-conversions/BetterStratagemBounce/LICENSE", src / "vanilla-plus-megapack" / "LICENSE")
    (repo / "SHA256SUMS.txt").write_text((HERE / "out" / "SHA256SUMS.txt").read_text())
    print(json.dumps({"repo": str(repo), "zip": receipt["zip"], "sources": report}, indent=1))


if __name__ == "__main__":
    main()
