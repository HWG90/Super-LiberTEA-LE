#!/usr/bin/env python3
"""Build/test the optional native fire bridge; never installs or edits a profile.

Run with no arguments to compile the DLL, run the production fixture and real
MinHook smoke test in a new disposable /tmp Wine prefix, then copy the verified
content-addressed DLL into dbf_modular/native. --check repeats that build/test
and requires an identical DLL already present there; it never publishes one.
--build-only is diagnostic: compile outputs remain in dist, without publication.
Use --zig / --wine to select tools. No active game prefix is read or reused.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'native' / 'heat_limiter'
OUT = ROOT / 'dist' / 'native' / 'heat-limiter'
RUNTIME = ROOT / 'dbf_modular' / 'native'
PIN = 'c3fcafdc10146beb5919319d0683e44e3c30d537'
ZIG_FALLBACK = Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/toolchain/zig-x86_64-linux-0.14.1/zig')
VENDOR_SOURCES = ('buffer.c', 'hook.c', 'trampoline.c', 'hde/hde64.c')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalize_own_pe(path: Path):
    """Remove link-time metadata from our unsigned output, never game binaries."""
    data = bytearray(path.read_bytes())
    if len(data) < 64 or data[:2] != b'MZ':
        raise RuntimeError(f'Compiler output is not a PE image: {path}')
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if pe + 88 + 4 > len(data) or data[pe:pe + 4] != b'PE\0\0':
        raise RuntimeError(f'Compiler output has an invalid PE header: {path}')
    # COFF TimeDateStamp and OptionalHeader.CheckSum are the only changed fields.
    struct.pack_into('<I', data, pe + 8, 0)
    struct.pack_into('<I', data, pe + 88, 0)
    path.write_bytes(data)


def system_imports(path: Path):
    """Read the built PE import table and refuse external C/C++ runtime DLLs."""
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    count, optional_size = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    optional = pe + 24
    if count == 0 or count > 96 or struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise RuntimeError('Expected an AMD64 PE32+ output.')
    section_at = optional + optional_size
    sections = []
    for i in range(count):
        row = section_at + i * 40
        virtual_size, virtual_at, raw_size, raw_at = struct.unpack_from('<IIII', data, row + 8)
        sections.append((virtual_at, max(virtual_size, raw_size), raw_at, raw_size))

    def offset(rva, length):
        for start, span, raw, raw_length in sections:
            if start <= rva and rva + length <= start + span and rva + length <= start + raw_length:
                result = raw + rva - start
                if result + length <= len(data):
                    return result
        raise RuntimeError('Built PE import table points outside initialized file bytes.')

    directory, size = struct.unpack_from('<II', data, optional + 120)
    if not directory or not 20 <= size <= 65536:
        raise RuntimeError('Built DLL has an invalid import directory.')
    imports = []
    for i in range(min(size // 20, 128)):
        row = offset(directory + i * 20, 20)
        if data[row:row + 20] == bytes(20):
            break
        name_rva = struct.unpack_from('<I', data, row + 12)[0]
        name_at = offset(name_rva, 1)
        end = data.find(b'\0', name_at, name_at + 256)
        if end < 0:
            raise RuntimeError('Unterminated DLL import name.')
        name = data[name_at:end].decode('ascii').lower()
        if name not in {'kernel32.dll', 'ntdll.dll', 'msvcrt.dll', 'ucrtbase.dll'} and not name.startswith('api-ms-win-crt-'):
            raise RuntimeError(f'Unexpected non-system DLL dependency: {name}')
        imports.append(name)
    else:
        raise RuntimeError('Unterminated DLL import directory.')
    if not imports:
        raise RuntimeError('Built DLL import inventory is empty.')
    return sorted(set(imports))


def command(args, *, env=None, log=None, timeout=120):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, env=env,
                            text=True, capture_output=True, timeout=timeout)
    output = result.stdout + result.stderr
    if log:
        log.write_text(output, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{args[0]} exited {result.returncode}:\n{output[-16000:]}')
    return output


def resolve_tool(value, name, fallback=None):
    candidate = value or shutil.which(name)
    if not candidate and fallback and fallback.is_file():
        candidate = fallback
    if not candidate:
        raise RuntimeError(f'{name} is required; specify --{name}.')
    path = Path(candidate).expanduser().resolve()
    if not path.is_file():
        raise RuntimeError(f'{name} executable unavailable: {path}')
    return path


def verify_vendor():
    vendor = NATIVE / 'vendor' / 'minhook'
    provenance = json.loads((vendor / 'PROVENANCE.json').read_text())
    if provenance.get('commit') != PIN or provenance.get('upstream_files_modified') is not False:
        raise RuntimeError('MinHook provenance does not match the pinned untouched source.')
    if provenance.get('license') != 'BSD-2-Clause':
        raise RuntimeError('MinHook license declaration changed.')
    expected = set()
    for row in provenance['files']:
        name = row['path']
        path = (vendor / name).resolve()
        if not path.is_relative_to(vendor.resolve()) or name in expected:
            raise RuntimeError(f'Invalid MinHook provenance path: {name}')
        expected.add(name)
        if path.stat().st_size != row['bytes'] or sha(path) != row['sha256']:
            raise RuntimeError(f'MinHook source differs from its pinned provenance: {name}')
    actual = {p.relative_to(vendor).as_posix() for p in vendor.rglob('*') if p.is_file()}
    if actual != expected | {'PROVENANCE.json'}:
        raise RuntimeError('MinHook file inventory differs from provenance.')
    if 'LICENSE.txt' not in expected:
        raise RuntimeError('MinHook license file is missing from provenance.')
    return vendor


def inventory():
    files = sorted(path for path in NATIVE.rglob('*') if path.is_file())
    files.append(Path(__file__).resolve())
    return {path.relative_to(ROOT).as_posix(): sha(path) for path in files}


def wine_tests(wine, env):
    # Both executables are synthetic. Their dedicated freshly created prefix
    # cannot refer to the user's game, LLL, or any existing Wine session.
    with tempfile.TemporaryDirectory(prefix='dbf-heat-limiter-', dir='/tmp') as scratch:
        prefix = Path(scratch) / 'prefix'
        test_env = {**env, 'WINEPREFIX': str(prefix), 'WINEARCH': 'win64',
                    'WINEDEBUG': '-all', 'WINEDLLOVERRIDES': 'winemenubuilder.exe=d;mscoree,mshtml=d',
                    'DBFH_TEST_DLL': 'Z:' + (OUT / 'heat_limiter.dll').as_posix()}
        try:
            for name in ('fixture', 'smoke'):
                output = command([wine, OUT / f'{name}.exe'], env=test_env,
                                 log=OUT / f'{name}.log', timeout=75)
                marker = 'Heat limiter fixture PASS' if name == 'fixture' else 'Heat limiter MinHook smoke PASS'
                if marker not in output:
                    raise RuntimeError(f'{name} exited without its required success marker:\n{output[-8000:]}')
                print(next(line for line in reversed(output.splitlines()) if marker in line), flush=True)
        finally:
            # Explicitly scope shutdown to this newly owned prefix, including
            # failure/timeout paths, before deleting its temporary filesystem.
            server = shutil.which('wineserver')
            if server:
                for args in ([server, '-k'], [server, '-w']):
                    subprocess.run(args, env=test_env, capture_output=True, timeout=15, check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Rebuild/test and verify the published runtime DLL.')
    parser.add_argument('--build-only', action='store_true', help='Compile diagnostic outputs without Wine tests or publication.')
    parser.add_argument('--zig', help='Zig 0.14.1 executable (otherwise PATH, then the local known toolchain).')
    parser.add_argument('--wine', help='Wine executable (otherwise PATH).')
    args = parser.parse_args()
    if args.check and args.build_only:
        parser.error('--check requires the native execution tests.')
    zig = resolve_tool(args.zig, 'zig', ZIG_FALLBACK)
    wine = None if args.build_only else resolve_tool(args.wine, 'wine')
    version = command([zig, 'version']).strip()
    if version != '0.14.1':
        raise RuntimeError(f'Expected verified Zig 0.14.1, got {version}.')
    vendor = verify_vendor()
    sources = inventory()
    for name in ('heat_limiter.cpp', 'heat_limiter.h', 'thermal.h', 'witnesses.h', 'fixture.cpp', 'smoke.cpp'):
        if not (NATIVE / name).is_file():
            raise RuntimeError(f'Native source is incomplete: {name}')
    OUT.mkdir(parents=True, exist_ok=True)
    # A failed rerun must not leave a previous passing receipt behind.
    receipt = OUT / 'BUILD.json'
    receipt.unlink(missing_ok=True)
    env = {**os.environ, 'ZIG_GLOBAL_CACHE_DIR': str(OUT / 'zig-global-cache'),
           'ZIG_LOCAL_CACHE_DIR': str(OUT / 'zig-local-cache')}
    objects = []
    for name in VENDOR_SOURCES:
        obj = OUT / ('minhook-' + Path(name).stem + '.o')
        command([zig, 'cc', '-target', 'x86_64-windows-gnu', '-O2', '-DNDEBUG',
                 '-c', vendor / 'src' / name, '-o', obj], env=env)
        objects.append(obj)
    common = [zig, 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17',
              '-fms-extensions', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror']
    raw = OUT / 'heat_limiter.dll'
    command([*common, '-shared', NATIVE / 'heat_limiter.cpp', *objects, '-o', raw], env=env)
    normalize_own_pe(raw)
    dependencies = system_imports(raw)
    command([*common, NATIVE / 'fixture.cpp', '-o', OUT / 'fixture.exe'], env=env)
    command([*common, NATIVE / 'smoke.cpp', *objects, '-o', OUT / 'smoke.exe'], env=env)
    digest = sha(raw)
    filename = f'DBFHeatLimiter26251122_{digest[:16]}.dll'
    dll = OUT / filename
    shutil.copyfile(raw, dll)
    if not args.build_only:
        wine_tests(wine, env)
    if inventory() != sources:
        raise RuntimeError('Native inputs changed during build/tests; rerun after the source is frozen.')
    published = RUNTIME / filename
    published_license = RUNTIME / 'MinHook-LICENSE.txt'
    if not args.build_only:
        if args.check:
            if not published.is_file() or sha(published) != digest:
                raise RuntimeError(f'Runtime DLL is missing or stale; build without --check: {filename}')
            if not published_license.is_file() or sha(published_license) != sha(vendor / 'LICENSE.txt'):
                raise RuntimeError('Runtime MinHook redistribution notice is missing or stale.')
        else:
            RUNTIME.mkdir(parents=True, exist_ok=True)
            if published.exists() and sha(published) != digest:
                raise RuntimeError(f'Existing content-addressed runtime DLL has different bytes: {published}')
            if not published.exists():
                temporary = published.with_suffix('.dll.tmp')
                try:
                    shutil.copyfile(dll, temporary)
                    os.replace(temporary, published)
                finally:
                    temporary.unlink(missing_ok=True)
            shutil.copyfile(vendor / 'LICENSE.txt', published_license)
    result = {'target_build': 26251122, 'architecture': 'x86_64-windows-gnu', 'abi': 1,
              'library': filename, 'sha256': digest, 'source_sha256': sources,
              'zig_version': version, 'zig_sha256': sha(zig),
              'system_dll_imports': dependencies,
              'fixture_passed': not args.build_only, 'real_minhook_smoke_passed': not args.build_only,
              'published': not args.build_only, 'check_only': args.check,
              'installed': False, 'in_game_tested': False,
              'minhook_commit': PIN, 'minhook_license': 'BSD-2-Clause',
              'runtime_license': 'native/MinHook-LICENSE.txt',
              'fixture_log': 'dist/native/heat-limiter/fixture.log',
              'smoke_log': 'dist/native/heat-limiter/smoke.log'}
    receipt.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'library': filename, 'sha256': digest, 'tests': not args.build_only,
                      'runtime': str(published) if not args.build_only else None}), flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, KeyError) as error:
        sys.exit(str(error))
