"""Build LLL's boot patch for 26251122 (LLL on PUC with Chef/Boot compatibility), staged only.

Same composition as the deployed patch (Linux HD2 worktree lua5-1-ports-4c2454,
runtime-modules/boot-handoff/build_compat_boot.py): LLL tools/build_steam_release.source() with the
stock boot, the helper pipe and the native helper names, prologue.lua in front, compiled by the
32-bit stock Lua 5.1.4 under LLL's chunk name, packed into LLL's single-resource archive.
Toolchain check first: the deployed compat checkout must reproduce the deployed patch byte for byte.
The release label is "R38-26251122-luajit.1". The deployed build kept "R35-26088801-cffi-insert-fix.2" because
War Journalist gated features on that exact string; WJ-Proton accepts the new label from the patch in
../maps/wj-proton/0001-lll-label-R38-26251122.patch. The toolchain check still composes the old label.
Output: package/ (Arsenal package files), native/ (DLLs and Service exes to install), RECEIPT.json.
Usage: python3 build_lll_boot.py   (needs lupa-free stdlib only; runs LLL's own tools)
"""
import hashlib, importlib.util, json, re, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAIN = Path("/home/goose/Documents/ChatGPT/Linux HD2/runtime-modules/boot-handoff")
OLD_LLL = Path("/home/goose/Worktrees/linux-hd2/lua5-1-ports-4c2454/lll-jit-live")   # claude/lll-chef-boot-compat dba5973
NEW_LLL = Path("/home/goose/Worktrees/linux-hd2/lll-26251122")                       # claude/lll-26251122
DEPLOYED_SOURCE = Path("/home/goose/Worktrees/linux-hd2/lua5-1-ports-4c2454/runtime-modules/boot-handoff/stage-compat/lll-source.lua")
DEPLOYED_PATCH = Path("/home/goose/.config/hd2arsenal/mods/LiveLuaLoader-R35-26088801-cffi-Arsenal_AR372513/9ba626afa44a3aa3.patch_0")
DEPLOYED_PATCH_SHA = "d0f0f7afb9fda69689447ec04e4eb79651e0558117e27b56c95a236d593fbbaa"
INSTALLED_SOURCE = Path("/home/goose/Documents/ChatGPT/Linux HD2/native-work/cffi-pointerfix-current/runtime-source-fixed.lua")
PIPE = "lll_steam_05052a2fb04dbddc81b8070f45f2ae53"
OLD_LABEL = "R35-26088801-cffi-insert-fix.2"
LABEL = "R38-26251122-luajit.1"
OLD_PARAMS = dict(release_label=OLD_LABEL, cffi_name="hd2_cffi_2e4bcd2f8d3df404.dll",
                  launcher_name="lll_steam_launcher_59c847ffeacf0dcb.exe", nativeinfo_name="hd2_nativeinfo_f6d3465944c1aea1.dll")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def compose(root, stock, params):
    sys.path.insert(0, str(root / "tools"))
    try:
        for name in [n for n in list(sys.modules) if n in ("build", "build_steam_release", "build_steam_probe", "steam_resources", "archive")]:
            del sys.modules[name]
        b = module(root / "tools" / "build_steam_release.py", "build_steam_release")
        return b.source(b"\0" * 8 + stock, PIPE, **params)
    finally:
        sys.path.remove(str(root / "tools"))


def content_name(prefix, path):
    data = path.read_bytes()
    return "%s_%s%s" % (prefix, sha(data)[:16], path.suffix), data


def main():
    installed = INSTALLED_SOURCE.read_bytes()
    stock = bytes(int(x) for x in re.findall(rb"\\(\d{3})", re.search(rb'loadstring\("((?:\\\d{3})*)","@stock_steam_boot"\)', installed).group(1)))
    expected_stock = json.loads((HERE.parent / "BUILD.json").read_text())["extra_pins"]["stock_startup_sha256"]
    # The stock boot embedded in LLL is the resource body after its 8-byte header; the extracted resource includes it.
    extracted = (HERE.parent / "stock" / "startup-f476df93691895fa.bin").read_bytes()
    assert sha(extracted) == expected_stock and extracted[8:] == stock, "embedded stock boot differs from the 26251122 stock startup"
    boot = module(MAIN / "build_boot_patch.py", "build_boot_patch")
    boot.LUA32 = MAIN / "tools" / "lua32"
    original = boot.PACKAGE.read_bytes()
    assert sha(original) == boot.PACKAGE_SHA256
    prologue = (MAIN / "prologue.lua").read_bytes()
    work = HERE / "work"
    work.mkdir(exist_ok=True)

    # 1. Toolchain: the deployed checkout reproduces the deployed source and patch.
    old_source = compose(OLD_LLL, stock, OLD_PARAMS)
    assert old_source == DEPLOYED_SOURCE.read_bytes(), "old checkout no longer reproduces the deployed LLL source"
    (work / "old-boot.lua").write_bytes(prologue + old_source)
    old_patch = boot.archive(original, boot.dump(work / "old-boot.lua", "@native-font-repair", work / "old-boot.luac"))
    assert sha(old_patch) == DEPLOYED_PATCH_SHA == sha(DEPLOYED_PATCH.read_bytes()), "deployed patch not reproduced"

    # 2. New native helpers, content-addressed like the deployed ones.
    native = HERE / "native"
    (native / "Native").mkdir(parents=True, exist_ok=True)
    (native / "Service").mkdir(parents=True, exist_ok=True)
    cffi_name, cffi = content_name("hd2_cffi", NEW_LLL / "native/cffi/windows/hd2_cffi.dll")
    info_name, info = content_name("hd2_nativeinfo", NEW_LLL / "native/cffi/windows/hd2_nativeinfo.dll")
    (native / "Native" / cffi_name).write_bytes(cffi)
    (native / "Native" / info_name).write_bytes(info)
    service_name = (HERE / "service" / "service.txt").read_text().strip()
    launcher_name = (HERE / "launcher" / "launcher.txt").read_text().strip()
    shutil.copyfile(HERE / "service" / service_name, native / "Service" / service_name)
    shutil.copyfile(HERE / "launcher" / launcher_name, native / "Service" / launcher_name)
    params = dict(release_label=LABEL, cffi_name=cffi_name, launcher_name=launcher_name, nativeinfo_name=info_name)

    # 3. New source and patch.
    new_source = compose(NEW_LLL, stock, params)
    for gone in (b"0acc07debe04714ae04281e1a66bd2eb9d3d85232953e32a93c8a3dd0874eabe", b"6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f",
                 b"0x6AD7C05D", OLD_LABEL.encode(), OLD_PARAMS["cffi_name"].encode(), OLD_PARAMS["nativeinfo_name"].encode(), OLD_PARAMS["launcher_name"].encode()):
        assert gone not in new_source, "26088801 value left in the composed source: %r" % gone
    assert new_source.count(('release="%s"' % LABEL).encode()) == 1, "release label not in the composed source"
    (work / "lll-source.lua").write_bytes(new_source)
    (work / "boot-source.lua").write_bytes(prologue + new_source)
    chunk = boot.dump(work / "boot-source.lua", "@native-font-repair", work / "boot.luac")
    e = __import__("struct").unpack_from("<7Q6I", original, 104)
    assert chunk[:12] == original[e[2] + 8:e[2] + 20], "bytecode header differs from the game ABI"
    patch = boot.archive(original, chunk)
    package = HERE / "package"
    package.mkdir(exist_ok=True)
    (package / "9ba626afa44a3aa3.patch_0").write_bytes(patch)
    for suffix in (".gpu_resources", ".stream"):
        (package / ("9ba626afa44a3aa3.patch_0" + suffix)).write_bytes(b"")
    receipt = {"purpose": "LLL on PUC for 26251122 (Chef/Boot compat), staged only", "release_label": LABEL,
               "toolchain_check": {"deployed_source_reproduced": True, "deployed_patch_reproduced": DEPLOYED_PATCH_SHA},
               "lll_checkout": str(NEW_LLL), "lll_source_sha256": sha(new_source), "lll_source_bytes": len(new_source),
               "prologue_sha256": sha(prologue), "boot_chunk_sha256": sha(chunk), "patch_sha256": sha(patch), "patch_bytes": len(patch),
               "native": {cffi_name: sha(cffi), info_name: sha(info), service_name: sha((native / "Service" / service_name).read_bytes()),
                          launcher_name: sha((native / "Service" / launcher_name).read_bytes())},
               "pipe": PIPE, "stock_startup_sha256": expected_stock}
    (HERE / "RECEIPT.json").write_text(json.dumps(receipt, indent=1) + "\n")
    print(json.dumps(receipt, indent=1))


if __name__ == "__main__":
    main()
