"""Build a dedicated LuaJIT runtime matching the original mods' FR1 bytecode.

Do not alter the separate worker prototype's GC64 build trees or artifacts.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
COMMIT = 'a4c064539ea931274d407e1249b4bb575424a0f4'


def build(platform):
    vendor = ROOT.parent / 'vendor/LuaJIT'
    revision = subprocess.check_output(['git', '-C', str(vendor), 'rev-parse', 'HEAD'], text=True).strip()
    assert revision == COMMIT, 'unexpected LuaJIT revision'
    assert not subprocess.check_output(['git', '-C', str(vendor), 'status', '--porcelain', '--untracked-files=no'], text=True), 'vendor source modified'
    work = ROOT / 'work/runtime' / platform
    source = work / 'LuaJIT'
    work.mkdir(parents=True, exist_ok=True)
    if source.exists():
        shutil.rmtree(source)
    shutil.copytree(vendor, source, ignore=shutil.ignore_patterns('.git'))
    windows = platform == 'windows'
    flags = '-DLUAJIT_DISABLE_GC64' + ('' if windows else ' -fPIC')
    command = ['make', '-C', str(source), '-j2', 'BUILDMODE=static', 'XCFLAGS=' + flags]
    if windows:
        command += ['TARGET_SYS=Windows', 'CROSS=x86_64-w64-mingw32-']
    with (work / 'build.log').open('w') as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    library = source / 'src/libluajit.a'
    receipt = {'platform': platform, 'luajit_commit': revision, 'gc64': False,
               'bytecode_frame_layout': 'FR1', 'compiler_flags': flags,
               'library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
               'reason': 'Original installed mod bytecode has no BCDUMP_F_FR2 flag',
               'memory_limit': 'Non-GC64 LuaJIT limits GC-managed object address space; not full 64-bit GC'}
    (work / 'BUILD.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['linux', 'windows', 'all'], default='all')
    args = parser.parse_args()
    for platform in ['linux', 'windows'] if args.platform == 'all' else [args.platform]:
        build(platform)
