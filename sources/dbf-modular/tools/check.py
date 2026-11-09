#!/usr/bin/env python3
"""Verify complete source candidate; no game, prefix, install or network access."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

def main():
    lua = shutil.which('luajit')
    if not lua:
        raise SystemExit('LuaJIT is required (Lua 5.1 + bit/FFI contracts).')
    baseline = json.loads((ROOT / 'design/BASELINE.json').read_text())
    for name, digest in baseline['original_files'].items():
        assert sha(ROOT / 'reference/original-dbf' / name) == digest, name
    print('Immutable Original DBF: all 41 files match', flush=True)
    witnesses = json.loads((ROOT / 'design/POSITIONING-SOURCES.json').read_text())
    for name, digest in witnesses['files'].items():
        assert sha(ROOT / 'reference/hudplus-positioning' / name) == digest, name
    fixtures = json.loads((ROOT / 'design/TEST-REFERENCES.json').read_text())
    for name, digest in fixtures['sha256'].items():
        assert sha(ROOT / name) == digest, name
    manifest = json.loads((ROOT / 'dbf_modular/manifest.json').read_text())
    declared = set(manifest['lll']['modules']) | {manifest['lll']['entry']}
    actual = {p.relative_to(ROOT / 'dbf_modular').as_posix() for p in (ROOT / 'dbf_modular').rglob('*.lua')}
    assert declared == actual, (declared - actual, actual - declared)
    assert manifest['id'] == 'dbf_modular' and manifest['target_build'] == '26251122'
    assert len(manifest['lll']['modules']) == len(set(manifest['lll']['modules']))
    receipt = ROOT / 'dist/native/heat-limiter/BUILD.json'
    native = json.loads(receipt.read_text()) if receipt.is_file() else {}
    inputs = sorted(p for p in (ROOT / 'native/heat_limiter').rglob('*') if p.is_file())
    inputs.append(ROOT / 'tools/build_heat_limiter.py')
    current_inputs = {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs}
    if not (native.get('check_only') and native.get('fixture_passed') and native.get('real_minhook_smoke_passed')
            and native.get('source_sha256') == current_inputs):
        run(sys.executable, 'tools/build_heat_limiter.py', '--check')
        native = json.loads(receipt.read_text())
    assert native['fixture_passed'] and native['real_minhook_smoke_passed']
    assert native['source_sha256'] == current_inputs, 'Native source changed after its tests'
    profile = (ROOT / 'dbf_modular/core/heat_limiter_profile.lua').read_text()
    assert native['library'] in profile and native['sha256'] in profile, 'Native profile differs from tested DLL'
    binaries = list((ROOT / 'dbf_modular/native').glob('*.dll'))
    assert len(binaries) == 1 and binaries[0].name == native['library'], 'Native package contains stale or missing helpers'
    assert sha(binaries[0]) == native['sha256'], 'Native DLL differs from tested build'
    for test in sorted((ROOT / 'tests').glob('test_*.lua')):
        run(lua, test.relative_to(ROOT).as_posix())
    for test in sorted((ROOT / 'tests').glob('test_*.py')):
        run(sys.executable, test.relative_to(ROOT).as_posix())
    run(lua, 'tools/preflight.lua')
    print('All source checks passed. In-game rendering/input/performance remain unverified.', flush=True)
    return 0

if __name__ == '__main__':
    sys.exit(main())
