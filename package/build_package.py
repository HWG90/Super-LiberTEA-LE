"""Build Super LiberTEA - LE (Linux Edition): one HD2 Arsenal mod for Steam build 26251122 on Linux/Proton.

Two steps, each a subcommand:
  collect  copies every input into out/inputs/ and records it in INPUTS.json: the Arsenal packages as they deploy
           today (their patch files must be the ones in the game's data/ folder), the LLL folder mods (DBF-MCM,
           ASS, Bridge Combat .10, the War Journalist Proton candidate built from WJ-Proton, Gadget Kit 0.5.10).
  build    reads only out/inputs/ and the LLL drop-in inputs (../lll), and writes out/package/ (the Arsenal mod),
           out/Super-LiberTEA-LE-<version>.zip, out/SHA256SUMS.txt and RECEIPT.json.
The boot patch is LLL R38-26251122-luajit.2's drop-in boot patch (../lll/build_lll_dropin.py, same install block,
prologue and LLL source) with mods_install.lua rendered after LLL's own install block: at boot it writes the LLL
folder mods into LOCALAPPDATA/LLL/Helldivers2/Mods. Gadget Kit LE = Gadget Kit 0.5.10 with gadget-kit-le/ over it
(Spawner and First Person pages only). Zip bytes depend on zlib: use /usr/bin/python3 (3.14, zlib-ng), as LLL R38.
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
VERSION = "1.0.0"
GAME_BUILD = "26251122"
LLL_RELEASE = "R38-26251122-luajit.2"
REPO = "https://github.com/HWG90/Super-LiberTEA-LE"
GUID = str(uuid.uuid5(uuid.NAMESPACE_URL, REPO))
STAMP = (2026, 11, 1, 0, 0, 0)
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
WJ_DEFAULT = Path("/tmp/claude-1000/-home-goose-Projects-Linux-HD2-Mods--claude-worktrees-democracy-overlord-arsenal-0a3429"
                  "/b9e63c6b-7bcd-4753-ab3f-ca83c3042c8c/scratchpad/src/wj-proton/dist/review/proton/le-9613fcf")

# Arsenal packages, in the LuaJIT Proton profile's order. Their options go into the one manifest under a prefix.
PARTS = [
    dict(key="wj-assets", source="War-Journalist-1.2.0-Assets_AR297988", folder="War Journalist Assets",
         title="War Journalist assets 1.2.0", docs=["ASSET-MANIFEST.json", "INSTALL.txt"]),
    dict(key="diverkit", source="DiverKit-8.14.31-LuaJIT-26251122", folder="DiverKit",
         title="DiverKit 8.14.31 r6", docs=["README-UPDATE.txt", "CHANGELOG-8.14.31.txt", "PORT-VALIDATION.json"]),
    dict(key="sgd", source="Smarter-Guard-Dogs-5.2.0-LuaJIT-26251122", folder="Smarter Guard Dogs",
         title="Guard Dogs", docs=["PORT-VALIDATION.json", "thumbnail.png"]),
    dict(key="megapack", source="Vanilla-Plus-Megapack-v42-CFFI-Development", folder="Vanilla Plus Megapack",
         title="Megapack", docs=["VanillaPlusMegapack-README.txt", "VanillaPlusMegapack-manifest.json", "thumbnail.png"]),
    dict(key="transmog", source="HD2-Transmog-Foundation-LuaJIT-26251122", folder="Transmog",
         title="Transmog", docs=["README.md", "README.ru.md", "README.txt", "THIRD-PARTY-LICENSES.txt", "PORT-VALIDATION.json", "mod-icon.png"]),
    dict(key="compat", source="LLL-Compat-Test", folder="LLL Compat Test", title="LLL Compat Test", docs=[]),
]
# Patch files and the Lua copies Arsenal scans; backups such as *.before-dbf-save stay out.
GAME_FILE = re.compile(r"^[0-9a-f]{16}\.(patch_\d+(\.gpu_resources|\.stream)?|lua)$")

# LLL folder mods, written at boot. "source" is where collect copies from.
FOLDER_MODS = [
    dict(id="dbf_mcm", title="Mod Configuration Menu (DBF-MCM)", version="0.1.74-luajit.5",
         source=Path("/home/goose/Worktrees/linux-hd2/dbf-mcm-inproc-font/luajit-ports/dbf_mcm"),
         git=("/home/goose/Worktrees/linux-hd2/dbf-mcm-inproc-font", "0c98387")),
    dict(id="divers_best_friend", title="Diver's Best Friend (ASS) R46", version="R46-luajit.2-26251122",
         source=ARSENAL / "DBF-ASS-R46-LuaJIT-26251122/Payload", luajit_only=True),
    dict(id="goose_bridge_combat", title="Goose Bridge Combat", version="0.1.17-experimental-26251122.10",
         source=WORKSPACE / "mods/bridge-combat/stage-original/goose_bridge_combat"),
    dict(id="dbf_freecam", title="War Journalist (Proton)", version="1.3.3-proton", source=None),
    dict(id="goose_temporary_unlocks", title="Goose Gadget Kit LE", version="0.5.10-cffi-26251122-le.1",
         source=PREFIX / "Mods/goose_temporary_unlocks", base_version="0.5.10-cffi-26251122"),
]
# Gadget Kit LE: what the Spawner and First Person pages never load.
LE_DROPPED = ["src/memory.lua", "src/core.lua", "src/backend.lua", "src/controller.lua", "src/freezes.lua", "src/passive_ai.lua",
              "src/equipment.lua", "src/equipment_backend.lua", "src/extraction.lua", "src/objectives.lua",
              "native/guarded_reads_fb18682bc3515a7a.dll", "native/native_ads_near_26251122_aee46b657684.dll"]
REQUIRE = re.compile(r"mod\.require\(\s*['\"]([^'\"]+)['\"]")


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
            entry.update(build=provenance["build"], package_sha256=receipt["sha256"], branch="WJ-Proton (HWG90/DBF_PhotoMode)")
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
    seen, queue = set(), REQUIRE.findall(out["main.lua"].decode())
    while queue:
        name = queue.pop()
        if name not in seen:
            seen.add(name)
            queue += REQUIRE.findall(out[name].decode())
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


def build(args):
    record = json.loads((HERE / "INPUTS.json").read_text())
    package, options = {}, []
    for part in PARTS:
        files = tree(INPUTS / part["key"])
        manifest = json.loads(files.pop("manifest.json"))
        assert {n: sha(d) for n, d in files.items() if re.search(r"\.patch_\d+$", n)} == record["parts"][part["key"]]["patches"]
        options += option_prefix(part, manifest)
        for name, data in files.items():
            package[part["folder"] + "/" + name] = data
    mods = {}
    for mod in FOLDER_MODS:
        files = tree(INPUTS / mod["id"])
        assert {n: sha(d) for n, d in files.items()} == record["mods"][mod["id"]]["files"], mod["id"] + ": inputs changed since collect"
        if mod["id"] == "goose_temporary_unlocks":
            files = gadget_le(files)
        manifest = json.loads(files["manifest.json"])
        assert manifest["id"] == mod["id"] and manifest["version"] == mod["version"]
        spec = manifest["lll"]
        for name in [spec["entry"]] + spec["modules"] + ([spec["defaults"]] if spec.get("defaults") else []):
            assert name in files, "%s: %s missing" % (mod["id"], name)
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
    manifest = {"Version": 1, "Guid": GUID, "Name": NAME,
                "Description": "Steam build %s, Linux/Proton only. Live Lua Loader with LuaJIT and its mods in one archive: "
                               "DBF-MCM, ASS, Bridge Combat, War Journalist (Proton) with assets, Goose Gadget Kit LE, DiverKit, "
                               "Transmog, Smarter Guard Dogs & Sentries, the Vanilla Plus Megapack and LLL Compat Test. "
                               "Keep it last in the load order. See README.txt." % GAME_BUILD,
                "IconPath": "icon.png", "Options": options}
    package["manifest.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    for option in options:
        for entry in [option] + (option.get("SubOptions") or []):
            for folder in entry.get("Include") or []:
                assert any(n.startswith(folder + "/") for n in package), folder
            assert not entry.get("Image") or entry["Image"] in package, entry["Image"]
    assert "icon.png" in package and "README.txt" in package
    package["FILES-SHA256.txt"] = "".join("%s  %s\n" % (sha(v), k) for k, v in sorted(package.items())).encode()
    write_tree(OUT / "package", package)
    zip_name = "Super-LiberTEA-LE-%s-%s.zip" % (VERSION, GAME_BUILD)
    with zipfile.ZipFile(OUT / zip_name, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(package.items()):
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type, info.external_attr = zipfile.ZIP_DEFLATED, 0o644 << 16
            z.writestr(info, data)
    with zipfile.ZipFile(OUT / zip_name) as z:
        assert z.testzip() is None and {i.filename: z.read(i) for i in z.infolist()} == package
    digest = sha((OUT / zip_name).read_bytes())
    (OUT / "SHA256SUMS.txt").write_text("%s  %s\n" % (digest, zip_name))
    result = {"name": NAME, "version": VERSION, "game_build": GAME_BUILD, "guid": GUID, "zip": zip_name, "zip_sha256": digest,
              "zip_bytes": (OUT / zip_name).stat().st_size, "patch_sha256": sha(patch), "patch_bytes": len(patch), "chunk_bytes": len(chunk),
              "boot": boot, "options": [o["Name"] for o in options],
              "mods": {i: {"version": json.loads(f["manifest.json"])["version"], "files": len(f), "bytes": sum(map(len, f.values())),
                           "manifest_sha256": sha(f["manifest.json"])} for i, f in mods.items()},
              "zip_contents": len(package), "live_acceptance": "pending"}
    (HERE / "RECEIPT.json").write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({k: result[k] for k in ("zip", "zip_sha256", "zip_bytes", "patch_bytes", "mods")}, indent=1))


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
