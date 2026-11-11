"""Make lll-26251122-luajit-inproc.lua, the LLL source the in-process runtime embeds (prepare_handoff.py
HD2_HANDOFF_LLL; build_runtime_26251122_inproc.sh, which compiles lll_host.c with HD2ENV_LLL_HOST).

It is lll-26251122-luajit-ffi.lua (ba2148a7..., the source 8a19f22d embeds) with four exact substitutions, each found
exactly once, taken from LLL branch claude/lll-luajit-inproc (~/Worktrees/linux-hd2/lll-luajit-inproc):
  1. LLL_STEAM_SERVICE.launcher: the io.popen launcher command -> nil (there is no helper to start);
  2. LLL_STEAM_TRANSPORT: src/steam/transport.lua (pipes) -> src/steam/transport_inproc.lua (hd2.lll_host);
  3. LLL_CFFI: the hd2_cffi_915da533d47a3f9c.dll path -> "hd2-runtime:ffi". The handoff answers luaopen_hd2_cffi with
     its proxy over LuaJIT's ffi by symbol, as it always did, so LLL still registers cffi and logs "cffi: ready";
     no file was ever opened, and now none is named;
  4. LLL_UI_FONT ensure_memory: package.loadlib of LLL's nativeinfo -> LLL_STEAM_TRANSPORT.nativeinfo().
Everything else stays byte for byte, including the release label R38-26251122-luajit.1 (War Journalist gates on it).
  python3 -I make_embedded_lll_inproc.py
"""
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
LLL = Path("/home/goose/Worktrees/linux-hd2/lll-luajit-inproc")
SOURCE = HERE / "lll-26251122-luajit-ffi.lua"
SOURCE_SHA256 = "ba2148a7fa1ee39ecb30e5cbef815dc2f5ce565559706cbc654c322997955178"
INPROC = LLL / "src/steam/transport_inproc.lua"
INPROC_SHA256 = "bd6a9c5845351a7bd3b0211f1d6b89477839dd4dbd4b7f0f4c097b6fa44169d8"
OUTPUT = HERE / "lll-26251122-luajit-inproc.lua"
LAUNCHER, PIPE = "lll_steam_launcher_e8a5c0fffbc8d802.exe", "lll_steam_05052a2fb04dbddc81b8070f45f2ae53"
CFFI = b'.open({path=(os.getenv("LOCALAPPDATA") or "").."/LLL/Helldivers2/Native/".."hd2_cffi_915da533d47a3f9c.dll"})'
FONT = (b"        local path=assert(os.getenv('LOCALAPPDATA'))..'/LLL/Helldivers2/Native/hd2_nativeinfo_8d03e036881e4ddc.dll'\n"
        b"        local entry=assert(package.loadlib(path,'luaopen_hd2_nativeinfo'))\n"
        b"        local native=assert(entry())\n")
LABEL = b'release="R38-26251122-luajit.1"'
GONE = (b"hd2_cffi_", b"hd2_nativeinfo_", b"lll_steam_launcher", b"io.popen", b"\\\\pipe\\\\", b"package.loadlib(path")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def module(name, body):
    # build_steam_release.source(): local NAME=(function()\n<file>\nend)()
    return b"local " + name + b"=(function()\n" + body + b"\nend)()"


def main():
    out = SOURCE.read_bytes()
    assert sha(out) == SOURCE_SHA256, "embedded R38 source changed"
    inproc = INPROC.read_bytes()
    assert sha(inproc) == INPROC_SHA256, "transport_inproc.lua changed: review it, then update INPROC_SHA256"
    launcher = (b"launcher=(function()\n" + (LLL / "src/steam/launcher.lua").read_bytes() + b"\nend)()"
                + ('("%s","%s")' % (LAUNCHER, PIPE)).encode())
    transport = module(b"LLL_STEAM_TRANSPORT", (LLL / "src/steam/transport.lua").read_bytes())
    steps = [(launcher, b"launcher=nil"),
             (transport, module(b"LLL_STEAM_TRANSPORT", inproc)),
             (CFFI, b'.open({path="hd2-runtime:ffi"})'),
             (FONT, b"        local native=LLL_STEAM_TRANSPORT.nativeinfo()\n")]
    for old, new in steps:
        assert out.count(old) == 1, old[:80]
        out = out.replace(old, new)
    assert out.count(LABEL) == 1, "release label not found once"
    for gone in GONE:
        assert gone not in out, gone
    OUTPUT.write_bytes(out)
    print("%s: %d bytes, sha256 %s (transport_inproc.lua %s)" % (OUTPUT.name, len(out), sha(out), INPROC_SHA256[:16]))


if __name__ == "__main__":
    main()
