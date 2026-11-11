"""Build Super LiberTEA - LE (Linux Edition): one HD2 Arsenal mod for Steam build 26568081 on Linux/Proton.

The 26568081 line of ../../26251122/super-libertea (releases 1.0.0 to 1.0.4, in the democracy-overlord-arsenal
worktree): the same package, built from the mods as the game-update session ported them on 2026-11-11
(WORKSPACE/STATUS.md). Two steps, each a subcommand:
  collect  copies every input into out/inputs/ and records it in INPUTS.json: the 26568081 Arsenal packages, the
           LLL folder mods (DBF-MCM, DBF Modular, Bridge Combat, War Journalist Proton, Gadget Kit, Nova Weapon FOV).
  build    reads only out/inputs/ and the LLL drop-in inputs (WORKSPACE/lll), and writes out/package/ (the Arsenal
           mod), out/Super-LiberTEA-LE-<version>-<build>.zip, the separate downloads beside it (SEPARATE_ZIP: LLL
           alone, each Arsenal part, each LLL folder mod), out/SHA256SUMS.txt over all of them, and RECEIPT.json.
The boot patch is LLL R38-26568081-luajit.1's drop-in boot patch (WORKSPACE/lll/build_lll_boot.py: same install
block, prologue and LLL source; build proves it by composing that patch byte for byte first) with mods_install.lua
rendered after LLL's own install block: at boot it writes the LLL folder mods into LOCALAPPDATA/LLL/Helldivers2/Mods.
Gadget Kit LE = Gadget Kit GADGET_KIT with gadget-kit-le/ over it (Spawner and First Person pages only).
Not in this line: Diver's Best Friend (ASS) R46 LE and HudPlusPlus, neither ported to 26568081 (NOT_PORTED).
Zip bytes depend on zlib: use /usr/bin/python3 (3.14, zlib-ng), as LLL R38.
  /usr/bin/python3 -I build_package.py collect [--wj-candidate <dir>]
  /usr/bin/python3 -I build_package.py build
"""
import argparse, hashlib, json, re, shutil, struct, subprocess, sys, uuid, zipfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The game-update workspace of this build (the main checkout: builds/26568081 is not committed there yet). Read only.
WORKSPACE = Path("/home/goose/Projects/Linux HD2 Mods/builds/26568081")
LLL_DIR = WORKSPACE / "lll"
sys.path.insert(0, str(LLL_DIR))
import build_lll_boot as B  # noqa: E402

NAME = "Super LiberTEA - LE (Linux Edition)"
VERSION = "1.0.5"
GAME_BUILD = "26568081"
LLL_RELEASE = "R38-26568081-luajit.1"
REPO = "https://github.com/HWG90/Super-LiberTEA-LE"
GUID = str(uuid.uuid5(uuid.NAMESPACE_URL, REPO))
# Shown in every Arsenal manifest this build writes (STAMP_LINE): the repo branch it is released from, the game build,
# the patch number of VERSION and when this release was made. CREATED is set per release, so builds stay reproducible.
BRANCH = "main"
CREATED = "2026-11-11 16:45"
STAMP = tuple(int(n) for n in re.split(r"[- :]", CREATED)) + (0,)
STAMP_LINE = "Super LiberTEA - LE %s · branch %s · build %s · patch %s · created %s" % (VERSION, BRANCH, GAME_BUILD, VERSION.rsplit(".", 1)[1], CREATED)
ARCHIVE = "9ba626afa44a3aa3.patch_0"
OUT = HERE / "out"
INPUTS = OUT / "inputs"
ARSENAL = Path.home() / ".config/hd2arsenal/mods"
GAME_DATA = Path("/home/goose/.local/share/Steam/steamapps/common/Helldivers 2/data")
PREFIX = Path("/home/goose/.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2")
LLL_PACKAGE = ARSENAL / "LLL-R38-LuaJIT-26568081"
# The Megapack's 25 mods carry one licence (Zero-Clause BSD, CowboyBingus); LLL's conversions keep a copy per mod.
MEGAPACK_LICENSE = Path("/home/goose/Worktrees/linux-hd2/lll-r38-luajit2/bingus-conversions/BetterStratagemBounce/LICENSE")
WJ_DEFAULT = Path("/home/goose/Worktrees/linux-hd2/wj-proton-26568081/dist/review/proton/26568081")

# Arsenal packages, in the LuaJIT Proton profile's order. Their options go into the one manifest under a prefix.
# The four ports are the folders the game-update session registered on 2026-11-11 (WORKSPACE/STATUS.md).
PARTS = [
    dict(key="wj-assets", source="War-Journalist-1.2.0-Assets_AR297988", folder="War Journalist Assets",
         title="War Journalist assets 1.2.0", docs=["ASSET-MANIFEST.json", "INSTALL.txt"],
         zip="War-Journalist-Assets", needs="Nothing; War Journalist (Proton) uses them (the War-Journalist-Proton download)."),
    dict(key="diverkit", source="DiverKit-8.14.31-LuaJIT-26568081", folder="DiverKit",
         title="DiverKit 8.14.31 r11", docs=["README-UPDATE.txt", "CHANGELOG-8.14.31.txt", "PORT-VALIDATION.json"], zip="DiverKit", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="sgd", source="Smarter-Guard-Dogs-5.2.0-LuaJIT-26568081", folder="Smarter Guard Dogs",
         title="Guard Dogs", docs=["PORT-VALIDATION.json", "thumbnail.png"], zip="Smarter-Guard-Dogs", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="megapack", source="Vanilla-Plus-Megapack-v42-LuaJIT-26568081", folder="Vanilla Plus Megapack",
         title="Megapack", docs=["VanillaPlusMegapack-README.txt", "VanillaPlusMegapack-manifest.json", "thumbnail.png"],
         zip="Vanilla-Plus-Megapack", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="transmog", source="HD2-Transmog-Foundation-LuaJIT-26568081", folder="Transmog",
         title="Transmog", docs=["README.md", "README.ru.md", "README.txt", "THIRD-PARTY-LICENSES.txt", "PORT-VALIDATION.json", "mod-icon.png"],
         zip="Transmog", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
]
# Arsenal mods released only as separate downloads beside the full package ("sha256" pins files to a build receipt).
# None on 26568081: 1.0.3 and 1.0.4 carried HudPlusPlus here, which has no 26568081 build (NOT_PORTED).
EXTRA_PARTS = []
# What 1.0.4 shipped for 26251122 and this line leaves out: both hold 26251122 addresses and were not ported
# (WORKSPACE/STATUS.md lists them as "ask before porting"). RECEIPT.json and the README name them.
NOT_PORTED = {"divers_best_friend": "Diver's Best Friend (ASS) R46 LE, the second DBF choice of 1.0.4 (R46-luajit.2-26251122-le.2)",
              "hud-plus": "HudPlusPlus Modular r1 (LuaJIT 26251122), a separate download of 1.0.3 and 1.0.4"}
# Patch files and the Lua copies Arsenal scans; backups such as *.before-dbf-save stay out.
GAME_FILE = re.compile(r"^[0-9a-f]{16}\.(patch_\d+(\.gpu_resources|\.stream)?|lua)$")

# The Gadget Kit build Gadget Kit LE is cut from (the staged kit's manifest version).
GADGET_KIT = "0.5.42-shear.1-cffi-26568081"
# LLL folder mods, written at boot. "source" is where collect copies from: each is the tree the game-update session
# staged and installed on 2026-11-11 (WORKSPACE/mods/*/stage, or the commit that stage was archived from). "dbf" marks
# a DBF provider: two cannot run together, so the boot patch comes in one variant per provider (DBF_VARIANTS).
FOLDER_MODS = [
    dict(id="dbf_mcm", title="Mod Configuration Menu (DBF-MCM)", version="0.1.74-luajit.8",
         source=Path("/home/goose/Worktrees/linux-hd2/dbf-mcm-26568081/luajit-ports/dbf_mcm"),
         git=("/home/goose/Worktrees/linux-hd2/dbf-mcm-26568081", "df61266a"), stage="mods/dbf-mcm/stage/dbf_mcm",
         zip="DBF-MCM", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(id="dbf_modular", title="DBF Modular", version="0.1.0-dev.25-26568081", dbf="modular", luajit_only=True,
         source=Path("/home/goose/Worktrees/linux-hd2/dbf-modular-26568081/dbf_modular"),
         git=("/home/goose/Worktrees/linux-hd2/dbf-modular-26568081", "01a5459"),
         zip="DBF-Modular", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; DBF-MCM and Mod Bindings Menu (in the Vanilla-Plus-Megapack download). "
         "Run one DBF: set [\"divers_best_friend\"] = false in LLL.cfg if Diver's Best Friend is installed."),
    dict(id="goose_bridge_combat", title="Goose Bridge Combat", version="0.1.17-experimental-26568081.1",
         source=WORKSPACE / "mods/bridge-combat/stage/goose_bridge_combat",
         zip="Bridge-Combat", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package. DBF-MCM is optional (its settings page)."),
    dict(id="dbf_freecam", title="War Journalist (Proton)", version="1.4.0-proton", source=None,
         branch="indev/wj-proton-26568081 (HWG90/DBF_PhotoMode, WJ-Proton line)", stage="mods/wj-proton/stage/dbf_freecam",
         zip="War-Journalist-Proton", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; the War-Journalist-Assets download."),
    dict(id="goose_temporary_unlocks", title="Goose Gadget Kit LE", version=GADGET_KIT + "-le.1",
         source=WORKSPACE / "mods/gadget-kit/stage/goose_temporary_unlocks", base_version=GADGET_KIT,
         zip="Gadget-Kit-LE", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; DBF-MCM (its pages are in the Mod Configuration Menu)."),
    dict(id="goose_nova_weapon_fov", title="Nova Weapon FOV", version="0.1.0-26568081",
         source=WORKSPACE / "mods/nova-weapon-fov/stage/goose_nova_weapon_fov",
         zip="Nova-Weapon-FOV", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
]
# The DBF choice in Arsenal's option selector: (dbf value, option name, package folder). The first is the default.
# One provider on 26568081, so the LLL option has no sub-options; DBF_RETIRED still goes to Backups when an earlier
# release of this package wrote it (1.0.4's second choice: it holds 26251122 addresses and was not ported).
DBF_VARIANTS = [("modular", "with DBF Modular", "LLL")]
DBF_RETIRED = ["divers_best_friend"]
# DBF Modular: its native Heat Limiter failed live acceptance, was not ported, and stays out of its HUD package (its
# README; the staged dev.25 has none either); the shipped CREDITS.md leaves out one sentence (the user's choice,
# 2026-11-09).
MODULAR_DROPPED = ["native/DBFHeatLimiter26251122_84c9ecdbe18e27e6.dll"]
MODULAR_CREDITS = (b"The Original DBF MIT notice is retained in `LICENSE`. It does not relicense third-party reference\n"
                   b"material or separately installed shared frameworks. ")
# Separate downloads beside the full package: each Arsenal part as its own Arsenal mod, LLL alone (its Arsenal package),
# and each LLL folder mod as a folder to extract into LLL's Mods folder. One boot patch is live at a time, so the
# folder mods cannot be Arsenal mods of their own.
SEPARATE_ZIP = "Super-LiberTEA-LE-%s-%s-%s.zip"
SEPARATE_NOTE = "SUPER-LIBERTEA-LE.txt"
ARSENAL_STEPS = ("1. Close the game. Import this zip in HD2 Arsenal.\n"
                 "2. Keep Live Lua Loader last in the load order (with first-mod priority on, first), then Purge / Deploy.")
FOLDER_STEPS = ("1. Close the game. Extract the {id} folder of this zip into %LOCALAPPDATA%\\LLL\\Helldivers2\\Mods inside the\n"
                "   game's Proton prefix (steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2/Mods),\n"
                "   so that Mods\\{id}\\manifest.json exists. Start the game once with LLL first if that folder does not exist yet.\n"
                "2. Start the game. To turn it off, set [\"{id}\"] = false inside the \"enabled\" table of LLL\\Helldivers2\\LLL.cfg.")
# Gadget Kit LE: what the Spawner and First Person pages never load (the Armory weapon registration of 0.5.35 feeds
# the Unlocks controller only). From 0.5.35 First Person's native ADS option writes through src/memory.lua, which loads
# the guarded_reads DLL, so both stay. The staged 26568081 kit carries one DLL per helper, each named by the Lua that
# loads it (gadget_le checks), so no DLL is dropped by name any more.
LE_DROPPED = ["src/core.lua", "src/backend.lua", "src/controller.lua", "src/freezes.lua", "src/passive_ai.lua",
              "src/equipment.lua", "src/equipment_backend.lua", "src/extraction.lua", "src/objectives.lua"]
# A module path in a mod's Lua. Mods load modules through mod.require, Host.require or helpers of their own (Gadget
# Kit's first-person runtime has a local module()), so every quoted path counts; LLL refuses one the manifest omits.
MODULE_PATH = re.compile(r"['\"]((?:src|config)/[^'\"]+\.lua)['\"]")
# The Megapack's bundle file 79e4f54aa542ec98 (in 24 options, as a Lua copy and inside the patch) carries the CFFI
# port's private adapter, whose helper-DLL folder was written in as the development package's Arsenal folder on the
# porting machine. The bundle code only calls PORT51.kind, so the DLL is never loaded: 1.0.1 drops the folder and
# pads the line to its old length, so every resource in the patch keeps its offset and size.
MEGAPACK_DIR = b'local mod={dir="/home/goose/.config/hd2arsenal/mods/Vanilla-Plus-Megapack-v42-CFFI-Development"}'
MEGAPACK_NO_DIR = b"local mod={} -- no helper DLL folder: this bundle file never loads it"
# What may not ship in a runtime file: a path into someone's Arsenal folder or a mod loaded from a drive path.
MACHINE_PATHS = (b"hd2arsenal", b"/.config/", b"io.open('Z:", b'io.open("Z:')


def sha(b):
    return hashlib.sha256(b).hexdigest()


def tree(root, keep=lambda rel: True):
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file() and keep(p.relative_to(root).as_posix())}


def write_tree(root, files):
    if root.exists():
        assert root.resolve().is_relative_to(OUT.resolve()), root
        shutil.rmtree(root)
    for name, data in files.items():
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        (root / name).write_bytes(data)


def deployed_patches():
    return {sha(p.read_bytes()) for p in GAME_DATA.iterdir() if re.match(r"^[0-9a-f]{16}\.patch_\d+$", p.name)}


def collect(args):
    record = {"purpose": "Inputs of %s %s, as collected; build reads only these copies" % (NAME, VERSION), "game_build": GAME_BUILD,
              "not_ported": NOT_PORTED, "parts": {}, "mods": {}}
    live = deployed_patches()
    for part in PARTS + EXTRA_PARTS:
        src = ARSENAL / part["source"]
        manifest = json.loads((src / "manifest.json").read_text())
        options = manifest.get("Options") or []
        # A manifest without options deploys the mod's root folder.
        folders = set() if options else {""}
        for option in options:
            for entry in [option] + (option.get("SubOptions") or []):
                folders.update(entry.get("Include") or [])
        images = {o.get("Image") for o in options if o.get("Image")} | {s.get("Image") for o in options for s in o.get("SubOptions") or [] if s.get("Image")}
        def keep(rel):
            top = rel.rsplit("/", 1)[0] if "/" in rel else ""
            return rel == "manifest.json" or rel in part["docs"] or rel in images or (top in folders and GAME_FILE.match(rel.rsplit("/", 1)[-1]) is not None)
        files = tree(src, keep)
        patches = {n: sha(d) for n, d in files.items() if re.search(r"\.patch_\d+$", n)}
        for name, digest in part.get("sha256", {}).items():
            assert sha(files[name]) == digest, "%s: %s is not the receipt's build" % (part["key"], name)
        # What runs live today: every patch of an option the profile deploys is in the game's data/ folder.
        unseen = sorted(n for n, h in patches.items() if h not in live)
        write_tree(INPUTS / part["key"], files)
        record["parts"][part["key"]] = {"source": str(src), "name": manifest["Name"], "guid": manifest["Guid"], "files": len(files),
                                        "patches": patches, "patches_not_deployed_now": unseen}
    for mod in FOLDER_MODS:
        src = mod["source"] or (args.wj_candidate / "candidate/dbf_freecam")
        files = tree(src)
        manifest = json.loads(files["manifest.json"])
        assert manifest["id"] == mod["id"] and manifest["version"] == mod.get("base_version", mod["version"]), (mod["id"], manifest["version"])
        entry = {"source": str(src), "version": manifest["version"], "files": {n: sha(d) for n, d in files.items()}}
        if "git" in mod:
            repo, commit = mod["git"]
            head = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
            dirty = subprocess.run(["git", "-C", repo, "status", "--porcelain", "--", str(src)], capture_output=True, text=True, check=True).stdout
            assert head.startswith(commit) and not dirty, (mod["id"], head, dirty)
            entry["git"] = {"repo": repo, "commit": head}
        if "stage" in mod:
            # The commit's tree is what the game-update session staged (and installed), byte for byte.
            staged = tree(WORKSPACE / mod["stage"])
            assert staged == files, "%s: %s differs from %s" % (mod["id"], src, WORKSPACE / mod["stage"])
            entry["same_as_stage"] = str(WORKSPACE / mod["stage"])
        if mod["id"] == "dbf_freecam":
            receipt = json.loads((args.wj_candidate / "BUILD-RECEIPT.json").read_text())
            provenance = json.loads(files["PROVENANCE.json"])
            assert all(sha(files[n]) == h for n, h in provenance["source_sha256"].items()) and receipt["module_audit"]["passed"]
            entry.update(build=provenance["build"], package_sha256=receipt["sha256"], branch=mod["branch"])
        if (PREFIX / "Mods" / mod["id"]).is_dir():
            installed = tree(PREFIX / "Mods" / mod["id"])
            entry["same_as_installed"] = installed == files
            if installed != files:
                entry["differs_from_installed"] = sorted(n for n in set(installed) | set(files) if installed.get(n) != files.get(n))
        write_tree(INPUTS / mod["id"], files)
        record["mods"][mod["id"]] = entry
    (HERE / "INPUTS.json").write_text(json.dumps(record, indent=1) + "\n")
    print(json.dumps({k: {n: v.get("version", v.get("name")) for n, v in record[k].items()} for k in ("parts", "mods")}, indent=1))


def lua_check(root, names, vms):
    """Every Lua file compiles under the mod's VMs: LLL on Proton runs LuaJIT, its fallback the game's Lua 5.1.
    A mod marked luajit_only (DBF Modular: ULL literals) is checked under LuaJIT alone."""
    checker = OUT / "work" / "check.lua"
    checker.parent.mkdir(parents=True, exist_ok=True)
    checker.write_text("for i=1,#arg do local f,e=loadfile(arg[i]) if not f then io.stderr:write(e,'\\n') os.exit(1) end end\n")
    for vm in vms:
        run = subprocess.run([vm, str(checker), *[str(root / n) for n in names]], capture_output=True, text=True)
        assert run.returncode == 0, "%s: %s" % (vm, run.stderr)


def gadget_le(files):
    """Gadget Kit (GADGET_KIT) with gadget-kit-le/ over it: only what the Spawner (with its loadout editor) and First
    Person pages load. DLLs no Lua of the kit names are older native builds that in-place updates left beside the
    current ones; they stay out too."""
    text = b"\n".join(d for n, d in files.items() if n.endswith(".lua"))
    stale = [n for n in files if n.endswith(".dll") and n.rsplit("/", 1)[-1][:-4].encode() not in text
             and n.rsplit("_", 1)[-1][:-4].encode() not in text]
    out = {n: d for n, d in files.items() if n not in LE_DROPPED and n not in stale}
    assert len(out) == len(files) - len(set(LE_DROPPED) | set(stale)), "an LE_DROPPED file is missing"
    for name in ("main.lua", "src/mcm.lua"):
        out[name] = (HERE / "gadget-kit-le" / name).read_bytes()
    manifest = json.loads(files["manifest.json"])
    seen, queue = set(), MODULE_PATH.findall(out["main.lua"].decode())
    while queue:
        name = queue.pop()
        if name not in seen and (name in out or name in LE_DROPPED):
            seen.add(name)
            queue += MODULE_PATH.findall(out[name].decode()) if name in out else []
    modules = [m for m in manifest["lll"]["modules"] if m in seen]
    assert set(modules) == seen and not seen & set(LE_DROPPED), sorted(seen ^ set(modules))
    text = b"\n".join(d for n, d in out.items() if n.endswith(".lua"))
    for name in out:
        if name.endswith(".dll"):
            assert name.rsplit("/", 1)[-1][:-4].encode() in text or name.rsplit("_", 1)[-1][:-4].encode() in text, name + " is not used"
    for name in LE_DROPPED:
        if name.endswith(".dll"):
            assert name.rsplit("/", 1)[-1][:-4].encode() not in text, name + " is still used"
    manifest.update(name="Goose Gadget Kit LE", version=GADGET_KIT + "-le.1",
                    description="Native ADS / True First Person and a support weapon spawner for build %s. " % GAME_BUILD +
                                "The Super LiberTEA - LE build of Goose Gadget Kit %s: no Unlocks or Gameplay pages." % GADGET_KIT.split("-")[0])
    manifest["lll"]["modules"] = modules
    out["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    note = ("> **Gadget Kit LE** (Super LiberTEA - LE): this build has only the **Spawner** and **First Person** pages. "
            "The Unlocks and Gameplay sections below describe the full kit and are not in this build.\n\n")
    out["README.md"] = note.encode() + files["README.md"]
    return out


def modular_package(files):
    """DBF Modular as its HUD package ships: without the withheld Heat Limiter DLL (MODULAR_DROPPED) and with
    CREDITS.md less MODULAR_CREDITS."""
    out = {n: d for n, d in files.items() if n not in MODULAR_DROPPED}
    assert len(out) == len(files) - len(MODULAR_DROPPED), "a MODULAR_DROPPED file is missing"
    assert files["CREDITS.md"].count(MODULAR_CREDITS) == 1, "DBF Modular's CREDITS.md changed"
    out["CREDITS.md"] = files["CREDITS.md"].replace(MODULAR_CREDITS, b"")
    return out


def megapack_portable(files):
    """The Megapack options without the porting machine's folder in the bundle file (MEGAPACK_DIR)."""
    out, changed = dict(files), []
    new = MEGAPACK_NO_DIR.ljust(len(MEGAPACK_DIR))
    assert len(MEGAPACK_NO_DIR) <= len(MEGAPACK_DIR)
    for name, data in files.items():
        if MEGAPACK_DIR in data:
            assert name.startswith("options/") and name.endswith(("/79e4f54aa542ec98.lua", ".patch_0")) and data.count(MEGAPACK_DIR) == 1, name
            out[name] = data.replace(MEGAPACK_DIR, new)
            changed.append(name)
    folders = sorted({n.rsplit("/", 1)[0] for n in changed})
    assert len(folders) == 24 and len(changed) == 48, (len(folders), len(changed))
    for folder in folders:
        # The Lua copy Arsenal scans is the patch's resource, byte for byte, before and after.
        lua, patch = folder + "/79e4f54aa542ec98.lua", folder + "/" + ARCHIVE
        assert files[lua] in files[patch] and out[lua] in out[patch] and len(out[patch]) == len(files[patch]), folder
    stage = OUT / "stage" / "megapack-bundle"
    write_tree(stage, {n: out[n] for n in changed if n.endswith(".lua")})
    lua_check(stage, [n for n in changed if n.endswith(".lua")], ("lua5.1", "luajit"))
    return out, changed


def literal(data):
    return B.literal(data)


def render_mods(mods, retire=()):
    """The mods block: install each mod, then set aside the DBF providers this variant does not ship (retire)."""
    blocks = []
    for mod_id, files in mods.items():
        names = sorted(n for n in files if n != "manifest.json") + ["manifest.json"]
        assert all(n.isascii() and '"' not in n and "\\" not in n for n in names), mod_id
        rows = ",\n".join("     {%s,%s,%d}" % (json.dumps(n), literal(files[n]), zlib.adler32(files[n])) for n in names)
        blocks.append("    install(%s,{\n%s,\n    })" % (json.dumps(mod_id), rows))
    blocks += ["    retire(%s)" % json.dumps(mod_id) for mod_id in retire]
    template = (HERE / "mods_install.lua").read_text()
    out = template.replace("@MODS@", "\n".join(blocks)).replace("@VERSION@", VERSION)
    assert "@MODS@" not in out and "@VERSION@" not in out
    return out.encode()


def lll_dropin():
    """LLL R38-26568081-luajit.1's drop-in inputs, each checked against the game-update session's receipts
    (WORKSPACE/lll/RECEIPT.json, RECEIPT-DROPIN.json): install block, prologue, composed LLL source, stock archive."""
    receipt = json.loads((LLL_DIR / "RECEIPT.json").read_text())
    dropin = json.loads((LLL_DIR / "RECEIPT-DROPIN.json").read_text())
    assert dropin["release"] == LLL_RELEASE, dropin["release"]
    lll_source = (LLL_DIR / "work" / "lll-source.lua").read_bytes()
    prologue = (B.MAIN / "prologue.lua").read_bytes()
    assert sha(lll_source) == receipt["lll_source_sha256"] == dropin["lll_source_sha256"]
    assert sha(prologue) == receipt["prologue_sha256"] == dropin["prologue_sha256"] == B.PROLOGUE_SHA
    files, marker = B.native_set(LLL_DIR / "native", (LLL_DIR / dropin["runtime_source"]).resolve())
    assert marker == dropin["marker"] and {n: sha(d) for n, d in files.items()} == dropin["files"], "LLL's native files are not the receipt's"
    upgrade = (dropin["upgrade"]["from_release"], dropin["upgrade"]["from_marker"])
    install = B.render((LLL_DIR / "dropin_install.lua").read_text(), files, marker, LLL_RELEASE, upgrade)
    assert sha(install) == dropin["install_block_sha256"], "LLL's install block is not %s's" % LLL_RELEASE
    original = B.ORIGINAL.read_bytes()
    assert sha(original) == B.ORIGINAL_SHA
    return dict(receipt=dropin, lll_source=lll_source, prologue=prologue, files=files, marker=marker, install=install, original=original)


def boot_patch(lll, mods_block, tag):
    """LLL R38-26568081-luajit.1's drop-in boot patch with the mods block after LLL's install block. tag names the
    work files of this variant (install-blocks-<tag>.lua is what test_install.py runs)."""
    work = OUT / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / ("install-blocks-%s.lua" % tag)).write_bytes(lll["install"] + mods_block)
    (work / ("boot-source-%s.lua" % tag)).write_bytes(lll["install"] + mods_block + lll["prologue"] + lll["lll_source"])
    chunk = B.dump(work / ("boot-source-%s.lua" % tag), work / ("boot-%s.luac" % tag))
    # Once each in LLL's block; a mod may carry the same bytes (Gadget Kit's port51 nativeinfo is LLL's).
    for name, data in lll["files"].items():
        assert chunk.count(data) >= 1, "%s not embedded" % name
    dropin = lll["receipt"]
    return B.archive(lll["original"], chunk), chunk, {"lll_release": LLL_RELEASE, "lll_install_block_sha256": sha(lll["install"]),
                                                      "mods_block_sha256": sha(mods_block), "prologue_sha256": sha(lll["prologue"]),
                                                      "lll_source_sha256": sha(lll["lll_source"]),
                                                      "lll_files": {n: sha(d) for n, d in lll["files"].items()},
                                                      "marker": lll["marker"], "lll_dropin_patch_sha256": dropin["patch_sha256"]}


def option_prefix(part, manifest):
    folder, single = part["folder"], len(manifest["Options"]) == 1
    def move(entry):
        entry = dict(entry)
        if entry.get("Include"):
            entry["Include"] = [folder + "/" + i for i in entry["Include"]]
        if entry.get("Image"):
            entry["Image"] = folder + "/" + entry["Image"]
        if entry.get("SubOptions"):
            entry["SubOptions"] = [move(s) for s in entry["SubOptions"]]
        return entry
    options = []
    for option in manifest["Options"]:
        option = move(option)
        option["Name"] = part["title"] if single else "%s · %s" % (part["title"], option["Name"])
        options.append(option)
    return options


def write_zip(path, files):
    """A reproducible zip of {name: bytes}, read back whole. Returns its sha256."""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type, info.external_attr = zipfile.ZIP_DEFLATED, 0o644 << 16
            z.writestr(info, data)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None and {i.filename: z.read(i) for i in z.infolist()} == files
    return sha(path.read_bytes())


def check_options(options, files):
    """Every option's folders and images are in the archive."""
    for option in options:
        for entry in [option] + (option.get("SubOptions") or []):
            for folder in entry.get("Include") or []:
                assert any(n.startswith(folder + "/") for n in files), folder
            assert not entry.get("Image") or entry["Image"] in files, entry["Image"]


def separate_zips(parts, mods, extras):
    """The separate downloads, {zip name: files}: LLL alone (its 26568081 Arsenal package), each Arsenal part with its own
    manifest, each LLL folder mod as its folder. Each carries SEPARATE_NOTE: how to install it and what it needs."""
    def note(title, steps, needs):
        return ("%s\nfrom %s %s, Helldivers 2 Steam build %s. Linux/Proton only.\n\nINSTALL\n%s\n\nNEEDS\n%s\n\n"
                "The full package, the other separate downloads, credits and every item's source: %s\n"
                % (title, NAME, VERSION, GAME_BUILD, steps, needs, REPO)).encode()
    def stamped(raw):
        manifest = json.loads(raw)
        manifest["Description"] = "From %s. %s" % (STAMP_LINE, manifest.get("Description", ""))
        return (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    out = {}
    lll = tree(LLL_PACKAGE)
    dropin = json.loads((LLL_DIR / "RECEIPT-DROPIN.json").read_text())
    packaged = json.loads((LLL_DIR / "ARSENAL-PACKAGE.json").read_text())
    assert sha(lll["LLL-R38/" + ARCHIVE]) == dropin["patch_sha256"], "the LLL package is not %s's" % LLL_RELEASE
    assert {n: sha(d) for n, d in lll.items()} == packaged["files"], "the LLL Arsenal folder is not the one the update session built"
    # The stamp changes the manifest, so its line in the package's own file list follows.
    listed = "%s  manifest.json\n" % sha(lll["manifest.json"])
    lll["manifest.json"] = stamped(lll["manifest.json"])
    assert lll["FILES-SHA256.txt"].decode().count(listed) == 1
    lll["FILES-SHA256.txt"] = lll["FILES-SHA256.txt"].decode().replace(listed, "%s  manifest.json\n" % sha(lll["manifest.json"])).encode()
    check_options(json.loads(lll["manifest.json"])["Options"], lll)
    lll[SEPARATE_NOTE] = note("Live Lua Loader R38 (LuaJIT) %s" % LLL_RELEASE, ARSENAL_STEPS + "\n   Turn off any other Live Lua Loader, "
                              "Bingus Shared Loader, Boot Mod Loader or Chef Shared Loader, and the full package.", "Nothing else.")
    out[SEPARATE_ZIP % (VERSION, GAME_BUILD, "Live-Lua-Loader-R38-LuaJIT")] = lll
    for part in PARTS + EXTRA_PARTS:
        manifest, files = (parts if part in PARTS else extras)[part["key"]]
        files = dict(files)
        files["manifest.json"] = stamped(files["manifest.json"])
        check_options(manifest.get("Options") or [], files)
        if part["key"] == "megapack":
            files["LICENSE"] = MEGAPACK_LICENSE.read_bytes()
        files[SEPARATE_NOTE] = note(manifest["Name"], ARSENAL_STEPS, part["needs"])
        out[SEPARATE_ZIP % (VERSION, GAME_BUILD, part["zip"])] = files
    for mod in FOLDER_MODS:
        files = {mod["id"] + "/" + n: d for n, d in mods[mod["id"]].items()}
        files[SEPARATE_NOTE] = note("%s (version %s)" % (mod["title"], mod["version"]), FOLDER_STEPS.format(id=mod["id"]), mod["needs"])
        out[SEPARATE_ZIP % (VERSION, GAME_BUILD, mod["zip"])] = files
    for name, files in out.items():
        for f, data in files.items():
            found = [p.decode() for p in MACHINE_PATHS if p in data]
            assert not found or f.rsplit("/", 1)[-1] == "PORT-VALIDATION.json", (name, f, found)
    return out


def build(args):
    record = json.loads((HERE / "INPUTS.json").read_text())
    package, options, megapack, parts = {}, [], [], {}
    for part in PARTS:
        files = tree(INPUTS / part["key"])
        raw = files.pop("manifest.json")
        manifest = json.loads(raw)
        assert {n: sha(d) for n, d in files.items() if re.search(r"\.patch_\d+$", n)} == record["parts"][part["key"]]["patches"]
        if part["key"] == "megapack":
            files, megapack = megapack_portable(files)
        options += option_prefix(part, manifest)
        parts[part["key"]] = (manifest, dict(files, **{"manifest.json": raw}))
        for name, data in files.items():
            package[part["folder"] + "/" + name] = data
    extras = {}
    for part in EXTRA_PARTS:
        files = tree(INPUTS / part["key"])
        assert {n: sha(d) for n, d in files.items() if re.search(r"\.patch_\d+$", n)} == record["parts"][part["key"]]["patches"]
        extras[part["key"]] = (json.loads(files["manifest.json"]), files)
    mods = {}
    for mod in FOLDER_MODS:
        files = tree(INPUTS / mod["id"])
        assert {n: sha(d) for n, d in files.items()} == record["mods"][mod["id"]]["files"], mod["id"] + ": inputs changed since collect"
        if mod["id"] == "goose_temporary_unlocks":
            files = gadget_le(files)
        if mod["id"] == "dbf_modular":
            files = modular_package(files)
        manifest = json.loads(files["manifest.json"])
        assert manifest["id"] == mod["id"] and manifest["version"] == mod["version"]
        spec = manifest["lll"]
        declared = [spec["entry"]] + spec["modules"] + ([spec["defaults"]] if spec.get("defaults") else [])
        for name in declared:
            assert name in files, "%s: %s missing" % (mod["id"], name)
        undeclared = sorted({n for f, d in files.items() if f.endswith(".lua") for n in MODULE_PATH.findall(d.decode(errors="replace"))
                             if n in files and n not in declared})
        assert not undeclared, "%s: shipped and loaded but not declared, LLL would refuse: %s" % (mod["id"], undeclared)
        stage = OUT / "stage" / mod["id"]
        write_tree(stage, files)
        lua_check(stage, [n for n in files if n.endswith(".lua")], ("luajit",) if mod.get("luajit_only") else ("lua5.1", "luajit"))
        mods[mod["id"]] = files
    test = subprocess.run(["lua5.1", str(HERE / "gadget-kit-le/tests/mcm_le.lua")], cwd=OUT / "stage" / "goose_temporary_unlocks", capture_output=True, text=True)
    assert test.returncode == 0, test.stderr
    print(test.stdout.strip())

    lll = lll_dropin()
    # The composition is LLL's own: with no mods block it gives the update session's drop-in patch byte for byte.
    plain, _, _ = boot_patch(lll, b"", "lll-only")
    assert sha(plain) == lll["receipt"]["patch_sha256"] == sha((LLL_PACKAGE / "LLL-R38" / ARCHIVE).read_bytes()), \
        "%s's drop-in patch is not reproduced" % LLL_RELEASE
    variants = {}
    assert len(DBF_VARIANTS) == 1, "more than one DBF: offer them as SubOptions of the LLL option, as 1.0.4 did"
    for dbf, option_name, folder in DBF_VARIANTS:
        chosen = {m["id"]: mods[m["id"]] for m in FOLDER_MODS if m.get("dbf") in (None, dbf)}
        other = [m["id"] for m in FOLDER_MODS if m.get("dbf") not in (None, dbf)] + DBF_RETIRED
        mods_block = render_mods(chosen, other)
        patch, chunk, boot = boot_patch(lll, mods_block, dbf)
        package[folder + "/" + ARCHIVE] = patch
        package[folder + "/" + ARCHIVE + ".gpu_resources"] = b""
        package[folder + "/" + ARCHIVE + ".stream"] = b""
        variants[dbf] = {"option": option_name, "folder": folder, "mods": list(chosen), "sets_aside": other, "patch_sha256": sha(patch),
                         "patch_bytes": len(patch), "chunk_bytes": len(chunk), "boot": boot}
    options.append({"Name": "Live Lua Loader R38 (LuaJIT) + LLL mods",
                    "Description": "Required, keep it on. LLL %s's boot patch: hands the game over to LuaJIT and "
                                   "writes LLL's native files and the LLL mods (DBF-MCM, DBF Modular, Bridge Combat, War Journalist Proton, "
                                   "Gadget Kit LE, Nova Weapon FOV) into %%LOCALAPPDATA%%\\LLL\\Helldivers2 at boot. "
                                   "Last option, so its patch loads last." % LLL_RELEASE,
                    "Include": [DBF_VARIANTS[0][2]]})
    for name in sorted(n for n in (LLL_PACKAGE / "LICENSES").iterdir()):
        package["LICENSES/LLL/" + name.name] = name.read_bytes()
    package["LICENSES/Vanilla-Plus-Megapack-0BSD.txt"] = MEGAPACK_LICENSE.read_bytes()
    for name in (HERE / "package").rglob("*"):
        if name.is_file():
            # README.txt names the Gadget Kit build LE is cut from as @GADGET@.
            data = name.read_bytes().replace(b"@GADGET@", GADGET_KIT.split("-")[0].encode())
            assert b"@GADGET@" not in data and b"@VERSION@" not in data, name
            package[name.relative_to(HERE / "package").as_posix()] = data
    manifest = {"Version": 1, "Guid": GUID, "Name": "%s %s" % (NAME, VERSION),
                "Description": STAMP_LINE + ". Steam build %s, Linux/Proton only. Live Lua Loader with LuaJIT and its mods in one archive: "
                               "DBF-MCM, DBF Modular, Bridge Combat, War Journalist (Proton) with assets, "
                               "Goose Gadget Kit LE, Nova Weapon FOV, DiverKit, Transmog, Smarter Guard Dogs & Sentries and the "
                               "Vanilla Plus Megapack. "
                               "Keep it last in the load order. See README.txt." % GAME_BUILD,
                "IconPath": "icon.png", "Options": options}
    package["manifest.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    check_options(options, package)
    assert "icon.png" in package and "README.txt" in package
    for name, data in package.items():
        # PORT-VALIDATION.json files are the ports' records of where they were validated, not code.
        found = [p.decode() for p in MACHINE_PATHS if p in data]
        assert not found or name.endswith("/PORT-VALIDATION.json"), (name, found)
    package["FILES-SHA256.txt"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(package.items())).encode()
    write_tree(OUT / "package", package)
    zip_name = "Super-LiberTEA-LE-%s-%s.zip" % (VERSION, GAME_BUILD)
    digest = write_zip(OUT / zip_name, package)
    sums, separate = ["%s  %s\n" % (digest, zip_name)], {}
    for name, files in separate_zips(parts, mods, extras).items():
        separate[name] = {"sha256": write_zip(OUT / name, files), "bytes": (OUT / name).stat().st_size, "files": len(files)}
        sums.append("%s  %s\n" % (separate[name]["sha256"], name))
    (OUT / "SHA256SUMS.txt").write_text("".join(sums))
    result = {"name": NAME, "version": VERSION, "game_build": GAME_BUILD, "guid": GUID, "branch": BRANCH, "created": CREATED, "zip": zip_name, "zip_sha256": digest,
              "zip_bytes": (OUT / zip_name).stat().st_size, "variants": variants, "options": [o["Name"] for o in options],
              "megapack_bundle_folder_removed": {"from": MEGAPACK_DIR.decode(), "to": MEGAPACK_NO_DIR.decode(), "files": megapack},
              "not_ported": NOT_PORTED,
              "mods": {i: {"version": json.loads(f["manifest.json"])["version"], "files": len(f), "bytes": sum(map(len, f.values())),
                           "manifest_sha256": sha(f["manifest.json"])} for i, f in mods.items()},
              "zip_contents": len(package), "separate": separate, "live_acceptance": "pending"}
    (HERE / "RECEIPT.json").write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({k: result[k] for k in ("zip", "zip_sha256", "zip_bytes", "mods", "separate")}, indent=1))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="step", required=True)
    c = sub.add_parser("collect")
    c.add_argument("--wj-candidate", type=Path, default=WJ_DEFAULT)
    sub.add_parser("build")
    args = parser.parse_args()
    (collect if args.step == "collect" else build)(args)


if __name__ == "__main__":
    main()
