"""Build LLL's boot patch for 26568081: the Lua 5.1 (PUC) fallback with the LuaJIT handoff, staged only.

Same composition as the deployed 26251122 package (../../26251122/lll/build_lll_boot.py + build_lll_dropin.py):
LLL tools/build_steam_release.source() with the stock boot, the helper pipe and the native helper names,
prologue.lua in front, compiled by the 32-bit stock Lua 5.1.4 under LLL's chunk name, packed into LLL's
single-resource archive. The drop-in puts dropin_install.lua (rendered with the five native files) in front.

Toolchain check first, in work/toolchain-check/ (nothing of the old build is written):
  1. the released 26251122 checkout composes the shipped Lua 5.1 source (57fa4dc3...),
  2. it compiles to the live plain patch (b3e3c6c7...),
  3. with the 26251122 native files and runtime 9a596e2f it gives the deployed drop-in (1dc502e7...), byte for
     byte equal to the patch in the Arsenal library folder LLL-R38-26251122-luajit.2_AR622507.
Then the same steps for 26568081 from the LLL checkout with the new native files (native/, service/, launcher/).
LLL's release label stays R38-26251122-luajit.1 (War Journalist gates on that exact string); the package name,
shown in LLL-files.log, is --release.
Output: package/ (plain patch: LLL finds its native files in LOCALAPPDATA/LLL/Helldivers2), package-dropin/
(the same boot with the native files and the runtime inside), work/, RECEIPT.json, RECEIPT-DROPIN.json.
  python3 -I build_lll_boot.py [--runtime <runtime dll>] [--release R38-26568081-luajit.1] [--lll <checkout>]
"""
import argparse, hashlib, importlib.util, json, re, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILDS = HERE.parent.parent
OLD = BUILDS / "26251122"
DEPS = "/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps"   # lz4 for LLL's tools
MAIN = Path("/home/goose/Documents/ChatGPT/Linux HD2/runtime-modules/boot-handoff")   # read only: lua32, prologue, original archive
LUA32 = MAIN / "tools" / "lua32"
ORIGINAL = MAIN / "original" / "9ba626afa44a3aa3.patch_0"
ORIGINAL_SHA = "8c63e0c9b8d39711c49d4c1ddd0021a6994a25ed68a458035d05db8877b25423"
PROLOGUE_SHA = "3aad53105c0c383524bc898956de5e2eb41213d178388e6f3acf2ef9eecae376"
OLD_LLL = Path("/home/goose/Worktrees/linux-hd2/lll-r38-luajit2")       # LLL_JIT_Live 8b25fad, tag R38-26251122-luajit.2
NEW_LLL = Path("/home/goose/Worktrees/linux-hd2/lll-26568081")          # indev/lll-26568081
OLD_RUNTIME = OLD / "runtime" / "out" / "hd2_lua_environment.9a596e2f.dll"
NEW_RUNTIME = HERE.parent / "runtime" / "out" / "hd2_lua_environment.f45fe3e9.dll"
DEPLOYED = Path.home() / ".config/hd2arsenal/mods/LLL-R38-26251122-luajit.2_AR622507/LLL-R38/9ba626afa44a3aa3.patch_0"
OLD_SOURCE_SHA = "57fa4dc3ef1b48df37c86a39b90e1bd3fffd186c34492caa4f395eed86a8837b"
OLD_PLAIN_SHA = "b3e3c6c728004183544a6a41a0d1ca52e7dd145af110349f7d316d4dd04b5ee5"
OLD_DROPIN_SHA = "1dc502e733fc9dc41e0e46fe28dcd49fc94d76e72c64fc42274e1c8a92fdd672"
OLD_RELEASE = "R38-26251122-luajit.2"
OLD_UPGRADE = ("R38-26251122-luajit.1", "hd2_luajit_runtime_8a19f22d787b667c.dll")
PIPE = "lll_steam_05052a2fb04dbddc81b8070f45f2ae53"
LABEL = "R38-26251122-luajit.1"
ARCHIVE = "9ba626afa44a3aa3.patch_0"
CHUNK_NAME = "@native-font-repair"
BOOT, LUA = 0xf476df93691895fa, 0xa14e8dfa2cd117e2
UPGRADE = ("    -- %(old)s named its runtime here; this release's first start after it names %(new)s instead.\n"
           "    if slurp(base..'Native/luajit-boot.enable')=='%(marker)s\\n' and (slurp(base..'Logs/LLL-files.log') or '')"
           ":find(' %(old)s files: ',1,true) then os.remove(base..'Native/luajit-boot.enable') end\n")
DUMP = ("local src,name,out=...\nlocal f=assert(io.open(src,'rb'));local s=f:read('*a');f:close()\n"
        "local fn=assert(loadstring(s,name))\nlocal o=assert(io.open(out,'wb'));o:write(string.dump(fn));o:close()\n")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def compose(root, stock, params):
    """root's tools/build_steam_release.source(), with that checkout's own tool modules."""
    sys.path[:0] = [str(root / "tools"), DEPS]
    try:
        for name in [n for n in list(sys.modules) if n in ("build", "build_steam_release", "build_steam_probe", "steam_resources", "archive")]:
            del sys.modules[name]
        spec = importlib.util.spec_from_file_location("build_steam_release", root / "tools" / "build_steam_release.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.source(b"\0" * 8 + stock, PIPE, **params)
    finally:
        del sys.path[:2]


def dump(source, out):
    """string.dump under the 32-bit stock Lua 5.1.4 (same script as boot-handoff/build_boot_patch.dump)."""
    script = out.parent / "dump.lua"
    script.write_text(DUMP)
    subprocess.run([str(LUA32), str(script), str(source), CHUNK_NAME, str(out)], check=True)
    return out.read_bytes()


def archive(original, chunk):
    """boot-handoff/build_boot_patch.archive: LLL's single-resource archive with only the body and sizes changed."""
    magic, types, count = struct.unpack_from("<III", original)
    assert magic == 0xf0000011 and types == 1 and count == 1
    e = list(struct.unpack_from("<7Q6I", original, 104))
    assert e[0] == BOOT and e[1] == LUA and e[2] == 0xc0
    length, kind = struct.unpack_from("<II", original, e[2])
    assert kind == 1 and length == e[7] - 8 and struct.unpack_from("<I", original, 32)[0] == len(original)
    assert chunk[:12] == original[e[2] + 8:e[2] + 20], "bytecode header differs from the game ABI"
    body = struct.pack("<II", len(chunk), kind) + chunk
    total = e[2] + len(body)
    total += (-total) % 16
    out = bytearray(original[:e[2]])
    struct.pack_into("<I", out, 32, total)
    e[7] = len(body)
    struct.pack_into("<7Q6I", out, 104, *e)
    out += body
    return bytes(out) + b"\0" * (total - len(out))


def literal(data):
    # Same encoding as LLL tools/build_steam_release.literal().
    return '"' + "".join("\\%03d" % value for value in data) + '"'


def hashed(prefix, data, suffix):
    return "%s_%s%s" % (prefix, sha(data)[:16], suffix)


def native_set(root, runtime):
    """The five files as LOCALAPPDATA/LLL/Helldivers2-relative names; every name carries its own hash."""
    files = {}
    for sub in ("Native", "Service"):
        for path in sorted((root / sub).iterdir()):
            data = path.read_bytes()
            assert path.stem.split("_")[-1] == sha(data)[:16], path.name
            files["%s/%s" % (sub, path.name)] = data
    data = runtime.read_bytes()
    marker = hashed("hd2_luajit_runtime", data, ".dll")
    files["Native/" + marker] = data
    assert len(files) == 5, sorted(files)
    return dict(sorted(files.items())), marker


def params_for(files):
    pick = lambda prefix: next(n.split("/")[1] for n in files if n.split("/")[1].startswith(prefix))  # noqa: E731
    return dict(release_label=LABEL, cffi_name=pick("hd2_cffi_"), launcher_name=pick("lll_steam_launcher_"), nativeinfo_name=pick("hd2_nativeinfo_"))


def render(template, files, marker, release, upgrade):
    lines = "\n".join("    place(%s,%s)" % (json.dumps(name), literal(data)) for name, data in files.items())
    upgrade = UPGRADE % dict(old=upgrade[0], marker=upgrade[1], new=marker) if upgrade else ""
    out = template.replace("@FILES@", lines).replace("@UPGRADE@", upgrade).replace("@LABEL@", release).replace("@RUNTIME@", marker)
    assert "@" not in out.replace("@native", ""), "unrendered placeholder"
    return out.encode()


def build(work, lll, stock, prologue, original, files, marker, release, upgrade, template):
    """Returns the composed LLL source, the plain patch and the drop-in patch, with their intermediate hashes."""
    work.mkdir(parents=True, exist_ok=True)
    source = compose(lll, stock, params_for(files))
    (work / "lll-source.lua").write_bytes(source)
    (work / "boot-source.lua").write_bytes(prologue + source)
    chunk = dump(work / "boot-source.lua", work / "boot.luac")
    plain = archive(original, chunk)
    install = render(template, files, marker, release, upgrade)
    (work / "dropin-install.lua").write_bytes(install)
    (work / "dropin-boot-source.lua").write_bytes(install + prologue + source)
    dropin_chunk = dump(work / "dropin-boot-source.lua", work / "dropin-boot.luac")
    for name, data in files.items():
        assert dropin_chunk.count(data) == 1, "%s not embedded once in the chunk" % name
    dropin = archive(original, dropin_chunk)
    return dict(source=source, chunk=chunk, plain=plain, install=install, dropin_chunk=dropin_chunk, dropin=dropin)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runtime", type=Path, default=NEW_RUNTIME)
    parser.add_argument("--release", default="R38-26568081-luajit.1")
    parser.add_argument("--lll", type=Path, default=NEW_LLL)
    args = parser.parse_args()
    assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}", args.release)
    new_build = json.loads((HERE.parent / "BUILD.json").read_text())
    old_build = json.loads((OLD / "BUILD.json").read_text())
    extracted = (HERE.parent / "stock" / "startup-f476df93691895fa.bin").read_bytes()
    assert sha(extracted) == new_build["extra_pins"]["stock_startup_sha256"] == old_build["extra_pins"]["stock_startup_sha256"], \
        "the stock startup changed: the embedded stock boot must be re-extracted"
    stock = extracted[8:]   # the resource body after its 8-byte header, as LLL embeds it
    original = ORIGINAL.read_bytes()
    assert sha(original) == ORIGINAL_SHA
    prologue = (MAIN / "prologue.lua").read_bytes()
    assert sha(prologue) == PROLOGUE_SHA, "prologue.lua changed since the live build"
    old_template = (OLD / "lll" / "dropin_install.lua").read_text()
    template = (HERE / "dropin_install.lua").read_text()
    assert template == old_template, "dropin_install.lua differs from the deployed release's"

    # 1. Toolchain: the released checkout and the 26251122 inputs give the deployed patches byte for byte.
    old_files, old_marker = native_set(OLD / "lll" / "native", OLD_RUNTIME)
    old = build(HERE / "work" / "toolchain-check", OLD_LLL, stock, prologue, original, old_files, old_marker, OLD_RELEASE, OLD_UPGRADE, old_template)
    assert sha(old["source"]) == OLD_SOURCE_SHA, "released checkout no longer composes the shipped LLL source"
    assert sha(old["plain"]) == OLD_PLAIN_SHA == sha((OLD / "lll" / "package" / ARCHIVE).read_bytes()), "live plain patch not reproduced"
    assert old["dropin"] == DEPLOYED.read_bytes() and sha(old["dropin"]) == OLD_DROPIN_SHA, "deployed drop-in patch not reproduced"

    # 2. 26568081.
    for sub, src in (("Service", HERE / "service" / (HERE / "service" / "service.txt").read_text().strip()),
                     ("Service", HERE / "launcher" / (HERE / "launcher" / "launcher.txt").read_text().strip())):
        target = HERE / "native" / sub / src.name
        if not target.exists() or target.read_bytes() != src.read_bytes():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(src.read_bytes())
    files, marker = native_set(HERE / "native", args.runtime)
    launcher = json.loads((HERE / "launcher" / "launcher-build.json").read_text())
    service = next(n for n in files if n.startswith("Service/lll_steam_service_"))
    assert launcher["helper_sha256"] == sha(files[service]) and "Service/" + launcher["launcher"] in files, "launcher was built for another service"
    runtime = files["Native/" + marker]
    exe_sha, game_sha = (new_build["binaries"][k]["sha256"] for k in ("bin/helldivers2.exe", "data/game/game.dll"))
    assert LABEL.encode() in runtime, "runtime does not embed LLL %s" % LABEL
    assert exe_sha.encode() in runtime or bytes.fromhex(exe_sha) in runtime, "runtime is not for this game build"
    new = build(HERE / "work", args.lll, stock, prologue, original, files, marker, args.release, (OLD_RELEASE, old_marker), template)
    source = new["source"]
    gone = [old_build["binaries"][k]["sha256"] for k in ("bin/helldivers2.exe", "data/game/game.dll")]
    gone += [old_build["binaries"]["data/game/game.dll"][k].replace("0x", "0x") for k in ("timestamp", "checksum")]
    gone += [n.split("/")[1] for n in old_files if "runtime" not in n]
    for value in gone:
        assert value.encode() not in source, "26251122 value left in the composed source: %s" % value
    for value in (exe_sha, game_sha, new_build["binaries"]["data/game/game.dll"]["timestamp"], new_build["binaries"]["data/game/game.dll"]["checksum"]):
        assert value.encode() in source, "26568081 value missing from the composed source: %s" % value
    assert source.count(('release="%s"' % LABEL).encode()) == 1, "release label not in the composed source"
    for folder, patch in (("package", new["plain"]), ("package-dropin", new["dropin"])):
        (HERE / folder).mkdir(exist_ok=True)
        (HERE / folder / ARCHIVE).write_bytes(patch)
        for suffix in (".gpu_resources", ".stream"):
            (HERE / folder / (ARCHIVE + suffix)).write_bytes(b"")
    commit = subprocess.run(["git", "-C", str(args.lll), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", str(args.lll), "status", "--porcelain"], check=True, capture_output=True, text=True).stdout.strip()
    natives = {n.split("/")[1]: sha(d) for n, d in files.items() if n != "Native/" + marker}
    receipt = {"purpose": "LLL on PUC for 26568081 with the LuaJIT handoff in front, staged only", "release_label": LABEL,
               "toolchain_check": {"released_checkout": str(OLD_LLL), "lll_source_reproduced": OLD_SOURCE_SHA,
                                   "live_plain_patch_reproduced": OLD_PLAIN_SHA, "deployed_dropin_patch_reproduced": OLD_DROPIN_SHA,
                                   "deployed_patch": str(DEPLOYED)},
               "lll_checkout": str(args.lll), "lll_commit": commit, "lll_checkout_clean": not dirty,
               "lll_source_sha256": sha(source), "lll_source_bytes": len(source), "prologue_sha256": sha(prologue),
               "boot_chunk_sha256": sha(new["chunk"]), "patch_sha256": sha(new["plain"]), "patch_bytes": len(new["plain"]),
               "native": natives, "pipe": PIPE, "stock_startup_sha256": sha(extracted)}
    (HERE / "RECEIPT.json").write_text(json.dumps(receipt, indent=1) + "\n")
    dropin = {"release": args.release, "purpose": "Arsenal drop-in: the plain boot patch (%s) with the native files in front" % sha(new["plain"])[:16],
              "release_label": LABEL, "install_block_sha256": sha(new["install"]), "prologue_sha256": sha(prologue),
              "lll_source_sha256": sha(source), "boot_chunk_sha256": sha(new["dropin_chunk"]), "patch_sha256": sha(new["dropin"]),
              "patch_bytes": len(new["dropin"]), "files": {n: sha(d) for n, d in files.items()}, "marker": marker,
              "runtime_source": str(args.runtime), "same_lll_and_prologue_as": sha(new["plain"]),
              "upgrade": {"from_release": OLD_RELEASE, "from_marker": old_marker}}
    (HERE / "RECEIPT-DROPIN.json").write_text(json.dumps(dropin, indent=1) + "\n")
    print(json.dumps({"RECEIPT": receipt, "RECEIPT-DROPIN": dropin}, indent=1))


if __name__ == "__main__":
    main()
