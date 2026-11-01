"""Build the Arsenal drop-in boot patch for 26251122: the live boot patch with the release's native files inside.

The boot source is dropin_install.lua (rendered with the six files) in front of the same prologue and LLL source
as package/ (build_lll_boot.py, patch b3e3c6c7...), compiled and packed the same way. At boot the install block
writes cffi, nativeinfo, the LuaJIT runtime, the Steam service and launcher into LOCALAPPDATA/LLL/Helldivers2 when
they are missing, plus luajit-boot.enable and Service/game-root.txt when those are absent; then the boot runs
exactly as package/ does. A release that follows another moves that release's marker on to its own runtime, once
(RELEASES below). Inputs are checked against RECEIPT.json and the runtime's stage record.
Output, per release: package-dropin<suffix>/ (Arsenal package files), work/dropin-install<suffix>.lua (the rendered
block, for test_dropin_install.py), RECEIPT-DROPIN<suffix>.json. R38-26251122-luajit.1 has no suffix.
  python3 -I build_lll_dropin.py [--release R38-26251122-luajit.1 | R38-26251122-luajit.2]
"""
import argparse, hashlib, json, struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_lll_boot as B  # noqa: E402

ARCHIVE = "9ba626afa44a3aa3.patch_0"
RUNTIME = HERE.parent / "runtime"
# Each release's runtime (in ../runtime/out/) and its stage record. LLL's own release label stays B.LABEL in both
# the runtime and the Lua 5.1 fallback (War Journalist gates on it); the release name is what LLL-files.log shows.
# upgrade: the earlier release and the runtime its marker named. The first start after that release (LLL-files.log
# still names it) rewrites exactly that marker; "off", any other name and a later rollback are kept.
RELEASES = {
    "R38-26251122-luajit.1": dict(runtime="hd2_lua_environment.dll", record=RUNTIME / "STAGE-RECEIPT.json",
                                  upgrade=None, suffix=""),
    "R38-26251122-luajit.2": dict(runtime="hd2_lua_environment.9a596e2f.dll",
                                  record=Path("/home/goose/Worktrees/linux-hd2/runtime-lll-inproc/runtime-modules/boot-26251122/INPROC-STAGE.json"),
                                  upgrade=("R38-26251122-luajit.1", "hd2_luajit_runtime_8a19f22d787b667c.dll"), suffix="-luajit.2"),
}
LATEST = "R38-26251122-luajit.2"
UPGRADE = ("    -- %(old)s named its runtime here; this release's first start after it names %(new)s instead.\n"
           "    if slurp(base..'Native/luajit-boot.enable')=='%(marker)s\\n' and (slurp(base..'Logs/LLL-files.log') or '')"
           ":find(' %(old)s files: ',1,true) then os.remove(base..'Native/luajit-boot.enable') end\n")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def literal(data):
    # Same encoding as LLL tools/build_steam_release.literal().
    return '"' + "".join("\\%03d" % value for value in data) + '"'


def paths(release):
    suffix = RELEASES[release]["suffix"]
    return {"package": HERE / ("package-dropin" + suffix), "install": HERE / "work" / ("dropin-install%s.lua" % suffix),
            "source": HERE / "work" / ("dropin-boot-source%s.lua" % suffix), "chunk": HERE / "work" / ("dropin-boot%s.luac" % suffix),
            "receipt": HERE / ("RECEIPT-DROPIN%s.json" % suffix)}


def native_files(release=LATEST):
    """The six files as LOCALAPPDATA/LLL/Helldivers2-relative names, checked against the receipts."""
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    stage = json.loads(RELEASES[release]["record"].read_text())
    assert receipt["release_label"] == B.LABEL and B.LABEL in stage["embedded_lll"]
    files = {}
    for sub in ("Native", "Service"):
        for path in sorted((HERE / "native" / sub).iterdir()):
            data = path.read_bytes()
            assert sha(data) == receipt["native"][path.name] and path.stem.split("_")[-1] == sha(data)[:16], path.name
            files["%s/%s" % (sub, path.name)] = data
    runtime = (RUNTIME / "out" / RELEASES[release]["runtime"]).read_bytes()
    assert sha(runtime) == stage["sha256"] and stage["runtime"] == "hd2_luajit_runtime_%s.dll" % sha(runtime)[:16]
    files["Native/" + stage["runtime"]] = runtime
    assert len(files) == 5
    return dict(sorted(files.items())), stage["runtime"]


def render(files, runtime, release=LATEST):
    template = (HERE / "dropin_install.lua").read_text()
    lines = "\n".join("    place(%s,%s)" % (json.dumps(name), literal(data)) for name, data in files.items())
    upgrade = RELEASES[release]["upgrade"]
    upgrade = UPGRADE % dict(old=upgrade[0], marker=upgrade[1], new=runtime) if upgrade else ""
    out = template.replace("@FILES@", lines).replace("@UPGRADE@", upgrade).replace("@LABEL@", release).replace("@RUNTIME@", runtime)
    assert "@" not in out.replace("@native", ""), "unrendered placeholder"
    return out.encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", choices=sorted(RELEASES), default=LATEST)
    release = parser.parse_args().release
    out = paths(release)
    receipt = json.loads((HERE / "RECEIPT.json").read_text())
    lll_source = (HERE / "work" / "lll-source.lua").read_bytes()
    assert sha(lll_source) == receipt["lll_source_sha256"], "work/lll-source.lua is not the live build's LLL source"
    prologue = (B.MAIN / "prologue.lua").read_bytes()
    assert sha(prologue) == receipt["prologue_sha256"], "prologue.lua changed since the live build"
    boot = B.module(B.MAIN / "build_boot_patch.py", "build_boot_patch")
    boot.LUA32 = B.MAIN / "tools" / "lua32"
    original = boot.PACKAGE.read_bytes()
    assert sha(original) == boot.PACKAGE_SHA256

    files, runtime = native_files(release)
    install = render(files, runtime, release)
    out["install"].write_bytes(install)
    source = install + prologue + lll_source
    out["source"].write_bytes(source)
    chunk = boot.dump(out["source"], "@native-font-repair", out["chunk"])
    e = struct.unpack_from("<7Q6I", original, 104)
    assert chunk[:12] == original[e[2] + 8:e[2] + 20], "bytecode header differs from the game ABI"
    patch = boot.archive(original, chunk)
    for name, data in files.items():
        assert chunk.count(data) == 1, "%s not embedded once in the chunk" % name
    package = out["package"]
    package.mkdir(exist_ok=True)
    (package / ARCHIVE).write_bytes(patch)
    for suffix in (".gpu_resources", ".stream"):
        (package / (ARCHIVE + suffix)).write_bytes(b"")
    result = {"purpose": "Arsenal drop-in: the live boot patch (%s) with the release's native files in front" % receipt["patch_sha256"][:16],
              "release_label": B.LABEL, "install_block_sha256": sha(install), "prologue_sha256": sha(prologue),
              "lll_source_sha256": sha(lll_source), "boot_chunk_sha256": sha(chunk), "patch_sha256": sha(patch),
              "patch_bytes": len(patch), "files": {name: sha(data) for name, data in files.items()},
              "marker": runtime, "same_lll_and_prologue_as": receipt["patch_sha256"]}
    if release != B.LABEL:
        result = {"release": release, **result, "upgrade": dict(zip(("from_release", "from_marker"), RELEASES[release]["upgrade"]))}
    out["receipt"].write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
