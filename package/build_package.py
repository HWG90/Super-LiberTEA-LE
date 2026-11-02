"""Build Super LiberTEA - LE (Linux Edition): one HD2 Arsenal mod for Steam build 26251122 on Linux/Proton.

Two steps, each a subcommand:
  collect  copies every input into out/inputs/ and records it in INPUTS.json: the Arsenal packages as they deploy
           today (their patch files must be the ones in the game's data/ folder), the LLL folder mods (DBF-MCM,
           ASS, Bridge Combat .12, the War Journalist Proton bone-posing candidate, Gadget Kit 0.5.10).
  build    reads only out/inputs/ and the LLL drop-in inputs (../lll), and writes out/package/ (the Arsenal mod),
           out/Super-LiberTEA-LE-<version>-<build>.zip, the separate downloads beside it (SEPARATE_ZIP: LLL alone, each
           Arsenal part, each LLL folder mod), out/SHA256SUMS.txt over all of them, and RECEIPT.json.
The boot patch is LLL R38-26251122-luajit.2's drop-in boot patch (../lll/build_lll_dropin.py, same install block,
prologue and LLL source) with mods_install.lua rendered after LLL's own install block: at boot it writes the LLL
folder mods into LOCALAPPDATA/LLL/Helldivers2/Mods. Gadget Kit LE = Gadget Kit 0.5.10 with gadget-kit-le/ over it
(Spawner and First Person pages only); ASS LE = the R46 port without DBF-HUD's weapon readout. Zip bytes depend on zlib: use /usr/bin/python3 (3.14, zlib-ng), as LLL R38.
  /usr/bin/python3 -I build_package.py collect [--wj-candidate <dir>]
  /usr/bin/python3 -I build_package.py build
"""
import argparse, hashlib, json, re, shutil, struct, subprocess, sys, uuid, zipfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
LLL_DIR = HERE.parent / "lll"
sys.path.insert(0, str(LLL_DIR))
import build_lll_boot as B  # noqa: E402
import build_lll_dropin as D  # noqa: E402

NAME = "Super LiberTEA - LE (Linux Edition)"
VERSION = "1.0.2"
GAME_BUILD = "26251122"
LLL_RELEASE = "R38-26251122-luajit.2"
REPO = "https://github.com/HWG90/Super-LiberTEA-LE"
GUID = str(uuid.uuid5(uuid.NAMESPACE_URL, REPO))
# Shown in every Arsenal manifest this build writes (STAMP_LINE): the repo branch it is released from, the game build,
# the patch number of VERSION and when this release was made. CREATED is set per release, so builds stay reproducible.
BRANCH = "main"
CREATED = "2026-11-02 18:20"
STAMP = tuple(int(n) for n in re.split(r"[- :]", CREATED)) + (0,)
STAMP_LINE = "Super LiberTEA - LE %s · branch %s · build %s · patch %s · created %s" % (VERSION, BRANCH, GAME_BUILD, VERSION.rsplit(".", 1)[1], CREATED)
ARCHIVE = "9ba626afa44a3aa3.patch_0"
OUT = HERE / "out"
INPUTS = OUT / "inputs"
ARSENAL = Path.home() / ".config/hd2arsenal/mods"
GAME_DATA = Path("/mnt/WORMHOLE/SteamLibrary/steamapps/common/Helldivers 2/data")
PREFIX = Path("/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2")
WORKSPACE = Path("/home/goose/Projects/Linux HD2 Mods/builds/26251122")
LLL_PACKAGE = ARSENAL / "LLL-R38-26251122-luajit.2_AR622507"
# The Megapack's 25 mods carry one licence (Zero-Clause BSD, CowboyBingus); LLL's conversions keep a copy per mod.
MEGAPACK_LICENSE = Path("/home/goose/Worktrees/linux-hd2/lll-r38-luajit2/bingus-conversions/BetterStratagemBounce/LICENSE")
WJ_DEFAULT = Path("/home/goose/Documents/ChatGPT/Linux HD2/.claude/worktrees/wj-proton-bone-posing-668ec2/prior-war-journalist"
                  "/dist/review/proton/bone-posing-dev.6")

# Arsenal packages, in the LuaJIT Proton profile's order. Their options go into the one manifest under a prefix.
PARTS = [
    dict(key="wj-assets", source="War-Journalist-1.2.0-Assets_AR297988", folder="War Journalist Assets",
         title="War Journalist assets 1.2.0", docs=["ASSET-MANIFEST.json", "INSTALL.txt"],
         zip="War-Journalist-Assets", needs="Nothing; War Journalist (Proton) uses them (the War-Journalist-Proton download)."),
    dict(key="diverkit", source="DiverKit-8.14.31-LuaJIT-26251122", folder="DiverKit",
         title="DiverKit 8.14.31 r6", docs=["README-UPDATE.txt", "CHANGELOG-8.14.31.txt", "PORT-VALIDATION.json"], zip="DiverKit", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="sgd", source="Smarter-Guard-Dogs-5.2.0-LuaJIT-26251122", folder="Smarter Guard Dogs",
         title="Guard Dogs", docs=["PORT-VALIDATION.json", "thumbnail.png"], zip="Smarter-Guard-Dogs", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="megapack", source="Vanilla-Plus-Megapack-v42-CFFI-Development", folder="Vanilla Plus Megapack",
         title="Megapack", docs=["VanillaPlusMegapack-README.txt", "VanillaPlusMegapack-manifest.json", "thumbnail.png"],
         zip="Vanilla-Plus-Megapack", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(key="transmog", source="HD2-Transmog-Foundation-LuaJIT-26251122", folder="Transmog",
         title="Transmog", docs=["README.md", "README.ru.md", "README.txt", "THIRD-PARTY-LICENSES.txt", "PORT-VALIDATION.json", "mod-icon.png"],
         zip="Transmog", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
]
# Patch files and the Lua copies Arsenal scans; backups such as *.before-dbf-save stay out.
GAME_FILE = re.compile(r"^[0-9a-f]{16}\.(patch_\d+(\.gpu_resources|\.stream)?|lua)$")

# LLL folder mods, written at boot. "source" is where collect copies from.
FOLDER_MODS = [
    dict(id="dbf_mcm", title="Mod Configuration Menu (DBF-MCM)", version="0.1.74-luajit.5",
         source=Path("/home/goose/Worktrees/linux-hd2/dbf-mcm-inproc-font/luajit-ports/dbf_mcm"),
         git=("/home/goose/Worktrees/linux-hd2/dbf-mcm-inproc-font", "0c98387"), zip="DBF-MCM", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package."),
    dict(id="divers_best_friend", title="Diver's Best Friend (ASS) R46", version="R46-luajit.2-26251122-le.1",
         source=ARSENAL / "DBF-ASS-R46-LuaJIT-26251122/Payload", base_version="R46-luajit.2-26251122", luajit_only=True,
         zip="Divers-Best-Friend", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; Mod Bindings Menu for its hotkeys (in the Vanilla-Plus-Megapack download)."),
    dict(id="goose_bridge_combat", title="Goose Bridge Combat", version="0.1.17-experimental-26251122.12",
         source=WORKSPACE / "mods/bridge-combat/stage-original/goose_bridge_combat",
         zip="Bridge-Combat", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package. DBF-MCM is optional (its settings page)."),
    dict(id="dbf_freecam", title="War Journalist (Proton)", version="1.3.4-proton", source=None,
         branch="claude/wj-proton-bone-posing (HWG90/DBF_PhotoMode, from WJ-Proton)",
         zip="War-Journalist-Proton", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; the War-Journalist-Assets download."),
    dict(id="goose_temporary_unlocks", title="Goose Gadget Kit LE", version="0.5.10-cffi-26251122-le.1",
         source=PREFIX / "Mods/goose_temporary_unlocks", base_version="0.5.10-cffi-26251122",
         zip="Gadget-Kit-LE", needs="Live Lua Loader R38 (LuaJIT): the Live-Lua-Loader-R38-LuaJIT download of this release, or the full package; DBF-MCM (its pages are in the Mod Configuration Menu)."),
]
# Separate downloads beside the full package: each Arsenal part as its own Arsenal mod, LLL alone (luajit.2's files),
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
# Gadget Kit LE: what the Spawner and First Person pages never load.
LE_DROPPED = ["src/memory.lua", "src/core.lua", "src/backend.lua", "src/controller.lua", "src/freezes.lua", "src/passive_ai.lua",
              "src/equipment.lua", "src/equipment_backend.lua", "src/extraction.lua", "src/objectives.lua",
              "native/guarded_reads_fb18682bc3515a7a.dll", "native/native_ads_near_26251122_aee46b657684.dll"]
# ASS LE: the R46 port also starts DBF-HUD's weapon readout (a status strip beside the weapon row, read from game
# memory, logging to DBF-HUD.log). Published R46 has none of it; LE leaves its six modules and its four lines in
# main.lua out, as (port's line, LE's line).
ASS_DROPPED = ["src/weapon_status.lua", "src/weapon_status_memory.lua", "src/weapon_status_layouts.lua", "src/weapon_status_ammo.lua",
               "src/weapon_status_reader.lua", "src/weapon_status_strip.lua"]
ASS_MAIN = [(b"local weapon_status,terminal\n", b"local terminal\n"),
            (b"  weapon_status=mod.require('src/weapon_status.lua').new(mod.scope)\n", b""),
            (b"local result=callback(dt);weapon_status.update(dt);terminal.update(dt)", b"local result=callback(dt);terminal.update(dt)"),
            (b"  if weapon_status then local ok,why=weapon_status.close();if not ok then return false,why end end\n", b"")]
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
    record = {"purpose": "Inputs of %s %s, as collected; build reads only these copies" % (NAME, VERSION), "parts": {}, "mods": {}}
    live = deployed_patches()
    for part in PARTS:
        src = ARSENAL / part["source"]
        manifest = json.loads((src / "manifest.json").read_text())
        folders = set()
        for option in manifest["Options"]:
            for entry in [option] + (option.get("SubOptions") or []):
                folders.update(entry.get("Include") or [])
        images = {o.get("Image") for o in manifest["Options"] if o.get("Image")} | {s.get("Image") for o in manifest["Options"] for s in o.get("SubOptions") or [] if s.get("Image")}
        def keep(rel):
            top = rel.rsplit("/", 1)[0] if "/" in rel else ""
            return rel == "manifest.json" or rel in part["docs"] or rel in images or (top in folders and GAME_FILE.match(rel.rsplit("/", 1)[-1]) is not None)
        files = tree(src, keep)
        patches = {n: sha(d) for n, d in files.items() if re.search(r"\.patch_\d+$", n)}
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
        if mod["id"] == "divers_best_friend":
            entry["source_commit"] = json.loads((src.parent / "PORT-VALIDATION.json").read_text())["source_commit"]
        if mod["id"] == "dbf_freecam":
            receipt = json.loads((args.wj_candidate / "BUILD-RECEIPT.json").read_text())
            provenance = json.loads(files["PROVENANCE.json"])
            assert all(sha(files[n]) == h for n, h in provenance["source_sha256"].items()) and receipt["module_audit"]["passed"]
            entry.update(build=provenance["build"], package_sha256=receipt["sha256"], branch=mod["branch"])
        if (PREFIX / "Mods" / mod["id"]).is_dir():
            installed = tree(PREFIX / "Mods" / mod["id"])
            entry["same_as_installed"] = installed == files
        write_tree(INPUTS / mod["id"], files)
        record["mods"][mod["id"]] = entry
    (HERE / "INPUTS.json").write_text(json.dumps(record, indent=1) + "\n")
    print(json.dumps({k: {n: v.get("version", v.get("name")) for n, v in record[k].items()} for k in ("parts", "mods")}, indent=1))


def lua_check(root, names, vms):
    """Every Lua file compiles under the mod's VMs: LLL on Proton runs LuaJIT, its fallback the game's Lua 5.1.
    ASS's LuaJIT port is LuaJIT-only by design (0ULL literals), so it is checked under LuaJIT alone."""
    checker = OUT / "work" / "check.lua"
    checker.parent.mkdir(parents=True, exist_ok=True)
    checker.write_text("for i=1,#arg do local f,e=loadfile(arg[i]) if not f then io.stderr:write(e,'\\n') os.exit(1) end end\n")
    for vm in vms:
        run = subprocess.run([vm, str(checker), *[str(root / n) for n in names]], capture_output=True, text=True)
        assert run.returncode == 0, "%s: %s" % (vm, run.stderr)


def gadget_le(files):
    """Gadget Kit 0.5.10 with gadget-kit-le/ over it: only what the Spawner and First Person pages load."""
    out = {n: d for n, d in files.items() if n not in LE_DROPPED}
    assert len(out) == len(files) - len(LE_DROPPED), "an LE_DROPPED file is missing"
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
    manifest.update(name="Goose Gadget Kit LE", version="0.5.10-cffi-26251122-le.1",
                    description="Native ADS / True First Person and a support weapon spawner for build 26251122. "
                                "The Super LiberTEA - LE build of Goose Gadget Kit 0.5.10: no Unlocks or Gameplay pages.")
    manifest["lll"]["modules"] = modules
    out["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    note = ("> **Gadget Kit LE** (Super LiberTEA - LE): this build has only the **Spawner** and **First Person** pages. "
            "The Unlocks and Gameplay sections below describe the full kit and are not in this build.\n\n")
    out["README.md"] = note.encode() + files["README.md"]
    return out


def ass_le(files):
    """ASS R46's LuaJIT port without DBF-HUD's weapon readout (ASS_DROPPED, ASS_MAIN)."""
    out = {n: d for n, d in files.items() if n not in ASS_DROPPED}
    assert len(out) == len(files) - len(ASS_DROPPED), "an ASS_DROPPED file is missing"
    main = files["main.lua"]
    for old, new in ASS_MAIN:
        assert main.count(old) == 1, old
        main = main.replace(old, new)
    out["main.lua"] = main
    manifest = json.loads(files["manifest.json"])
    modules = manifest["lll"]["modules"]
    assert set(ASS_DROPPED) <= set(modules)
    manifest["lll"]["modules"] = [m for m in modules if m not in ASS_DROPPED]
    manifest.update(version="R46-luajit.2-26251122-le.1",
                    description=manifest["description"] + " The Super LiberTEA - LE build: without DBF-HUD's weapon readout.")
    out["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    text = b"\n".join(d for n, d in out.items() if n.endswith(".lua"))
    assert b"weapon_status" not in text and b"DBF-HUD" not in text, "the weapon readout is still referenced"
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
    return D.literal(data)


def render_mods(mods):
    blocks = []
    for mod_id, files in mods.items():
        names = sorted(n for n in files if n != "manifest.json") + ["manifest.json"]
        assert all(n.isascii() and '"' not in n and "\\" not in n for n in names), mod_id
        rows = ",\n".join("     {%s,%s,%d}" % (json.dumps(n), literal(files[n]), zlib.adler32(files[n])) for n in names)
        blocks.append("    install(%s,{\n%s,\n    })" % (json.dumps(mod_id), rows))
    template = (HERE / "mods_install.lua").read_text()
    out = template.replace("@MODS@", "\n".join(blocks)).replace("@VERSION@", VERSION)
    assert "@MODS@" not in out and "@VERSION@" not in out
    return out.encode()


def boot_patch(mods_block):
    """LLL R38-26251122-luajit.2's drop-in boot patch with the mods block after LLL's install block."""
    receipt = json.loads((LLL_DIR / "RECEIPT.json").read_text())
    dropin = json.loads(D.paths(LLL_RELEASE)["receipt"].read_text())
    lll_source = (LLL_DIR / "work" / "lll-source.lua").read_bytes()
    prologue = (B.MAIN / "prologue.lua").read_bytes()
    assert sha(lll_source) == receipt["lll_source_sha256"] == dropin["lll_source_sha256"]
    assert sha(prologue) == receipt["prologue_sha256"] == dropin["prologue_sha256"]
    files, runtime = D.native_files(LLL_RELEASE)
    install = D.render(files, runtime, LLL_RELEASE)
    assert sha(install) == dropin["install_block_sha256"], "LLL's install block is not luajit.2's"
    boot = B.module(B.MAIN / "build_boot_patch.py", "build_boot_patch")
    boot.LUA32 = B.MAIN / "tools" / "lua32"
    original = boot.PACKAGE.read_bytes()
    assert sha(original) == boot.PACKAGE_SHA256
    work = OUT / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / "install-blocks.lua").write_bytes(install + mods_block)
    (work / "boot-source.lua").write_bytes(install + mods_block + prologue + lll_source)
    chunk = boot.dump(work / "boot-source.lua", "@native-font-repair", work / "boot.luac")
    e = struct.unpack_from("<7Q6I", original, 104)
    assert chunk[:12] == original[e[2] + 8:e[2] + 20], "bytecode header differs from the game ABI"
    # Once each in LLL's block; a mod may carry the same bytes (Gadget Kit's port51 nativeinfo is LLL's).
    for name, data in files.items():
        assert chunk.count(data) >= 1, "%s not embedded" % name
    return boot.archive(original, chunk), chunk, {"lll_release": LLL_RELEASE, "lll_install_block_sha256": sha(install),
                                                 "mods_block_sha256": sha(mods_block), "prologue_sha256": sha(prologue),
                                                 "lll_source_sha256": sha(lll_source), "lll_files": {n: sha(d) for n, d in files.items()},
                                                 "marker": runtime, "lll_luajit2_patch_sha256": dropin["patch_sha256"]}


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


def separate_zips(parts, mods):
    """The separate downloads, {zip name: files}: LLL alone (luajit.2's Arsenal package), each Arsenal part with its own
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
    lll["manifest.json"] = stamped(lll["manifest.json"])
    dropin = json.loads(D.paths(LLL_RELEASE)["receipt"].read_text())
    assert sha(lll["LLL-R38/" + ARCHIVE]) == dropin["patch_sha256"], "the LLL package is not luajit.2's"
    check_options(json.loads(lll["manifest.json"])["Options"], lll)
    lll[SEPARATE_NOTE] = note("Live Lua Loader R38 (LuaJIT) %s" % LLL_RELEASE, ARSENAL_STEPS + "\n   Turn off any other Live Lua Loader, "
                              "Bingus Shared Loader, Boot Mod Loader or Chef Shared Loader, and the full package.", "Nothing else.")
    out[SEPARATE_ZIP % (VERSION, GAME_BUILD, "Live-Lua-Loader-R38-LuaJIT")] = lll
    for part in PARTS:
        manifest, files = parts[part["key"]]
        files = dict(files)
        files["manifest.json"] = stamped(files["manifest.json"])
        check_options(manifest["Options"], files)
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
    mods = {}
    for mod in FOLDER_MODS:
        files = tree(INPUTS / mod["id"])
        assert {n: sha(d) for n, d in files.items()} == record["mods"][mod["id"]]["files"], mod["id"] + ": inputs changed since collect"
        if mod["id"] == "goose_temporary_unlocks":
            files = gadget_le(files)
        if mod["id"] == "divers_best_friend":
            files = ass_le(files)
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

    mods_block = render_mods(mods)
    patch, chunk, boot = boot_patch(mods_block)
    package["LLL/" + ARCHIVE] = patch
    package["LLL/" + ARCHIVE + ".gpu_resources"] = b""
    package["LLL/" + ARCHIVE + ".stream"] = b""
    options.append({"Name": "Live Lua Loader R38 (LuaJIT) + LLL mods",
                    "Description": "Required, keep it on. LLL R38-26251122-luajit.2's boot patch: hands the game over to LuaJIT and "
                                   "writes LLL's native files and the LLL mods (DBF-MCM, ASS, Bridge Combat, War Journalist Proton, "
                                   "Gadget Kit LE) into %LOCALAPPDATA%\\LLL\\Helldivers2 at boot. Last option, so its patch loads last.",
                    "Include": ["LLL"]})
    for name in sorted(n for n in (LLL_PACKAGE / "LICENSES").iterdir()):
        package["LICENSES/LLL/" + name.name] = name.read_bytes()
    package["LICENSES/Vanilla-Plus-Megapack-0BSD.txt"] = MEGAPACK_LICENSE.read_bytes()
    for name in (HERE / "package").rglob("*"):
        if name.is_file():
            package[name.relative_to(HERE / "package").as_posix()] = name.read_bytes()
    manifest = {"Version": 1, "Guid": GUID, "Name": "%s %s" % (NAME, VERSION),
                "Description": STAMP_LINE + ". Steam build %s, Linux/Proton only. Live Lua Loader with LuaJIT and its mods in one archive: "
                               "DBF-MCM, ASS, Bridge Combat, War Journalist (Proton) with assets, Goose Gadget Kit LE, DiverKit, "
                               "Transmog, Smarter Guard Dogs & Sentries and the Vanilla Plus Megapack. "
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
    for name, files in separate_zips(parts, mods).items():
        separate[name] = {"sha256": write_zip(OUT / name, files), "bytes": (OUT / name).stat().st_size, "files": len(files)}
        sums.append("%s  %s\n" % (separate[name]["sha256"], name))
    (OUT / "SHA256SUMS.txt").write_text("".join(sums))
    result = {"name": NAME, "version": VERSION, "game_build": GAME_BUILD, "guid": GUID, "branch": BRANCH, "created": CREATED, "zip": zip_name, "zip_sha256": digest,
              "zip_bytes": (OUT / zip_name).stat().st_size, "patch_sha256": sha(patch), "patch_bytes": len(patch), "chunk_bytes": len(chunk),
              "boot": boot, "options": [o["Name"] for o in options],
              "megapack_bundle_folder_removed": {"from": MEGAPACK_DIR.decode(), "to": MEGAPACK_NO_DIR.decode(), "files": megapack},
              "ass_weapon_readout_removed": ASS_DROPPED,
              "mods": {i: {"version": json.loads(f["manifest.json"])["version"], "files": len(f), "bytes": sum(map(len, f.values())),
                           "manifest_sha256": sha(f["manifest.json"])} for i, f in mods.items()},
              "zip_contents": len(package), "separate": separate, "live_acceptance": "pending"}
    (HERE / "RECEIPT.json").write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({k: result[k] for k in ("zip", "zip_sha256", "zip_bytes", "patch_bytes", "mods", "separate")}, indent=1))


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
