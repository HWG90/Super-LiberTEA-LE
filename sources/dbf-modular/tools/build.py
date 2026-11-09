#!/usr/bin/env python3
"""Deterministic loose LLL and complete editable-source ZIPs, never installs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE = {'.git', 'dist', '__pycache__', '.pytest_cache'}

def archive(target, files, prefix=''):
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for path in sorted(files):
            name = prefix + path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(name, (2026, 11, 6, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            out.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(target) as check:
        assert check.testzip() is None
        for path in files:
            assert check.read(prefix + path.relative_to(ROOT).as_posix()) == path.read_bytes()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-checks', action='store_true', help='Only for a source already checked in this invocation chain.')
    args = parser.parse_args()
    if not args.skip_checks:
        subprocess.run([sys.executable, str(ROOT / 'tools/check.py')], cwd=ROOT, check=True)
    manifest = json.loads((ROOT / 'dbf_modular/manifest.json').read_text())
    version = manifest['version']
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    runtime = [p for p in (ROOT / 'dbf_modular').rglob('*') if p.is_file()]
    # Keep the experiment in the editable source archive, but never ship its
    # helper in a HUD update while live native acceptance is withdrawn.
    profile = (ROOT / 'dbf_modular/core/heat_limiter_profile.lua').read_text()
    if 'available = false' in profile:
        runtime = [p for p in runtime if p.suffix.lower() != '.dll']
    source = [p for p in ROOT.rglob('*') if p.is_file() and not any(part in EXCLUDE for part in p.relative_to(ROOT).parts)]
    lll = dist / f'DBF-Modular-{version}-LLL.zip'
    src = dist / f'DBF-Modular-{version}-source.zip'
    archive(lll, runtime)
    archive(src, source, 'DBF-Modular/')
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (lll, src)}
    (dist / 'SHA256SUMS').write_text(''.join(f'{value}  {name}\n' for name, value in hashes.items()))
    (dist / 'PACKAGE.json').write_text(json.dumps({
        'id':manifest['id'], 'version':version, 'target':'Steam HD2 build26251122 / LLL LuaJIT / Linux-Proton',
        'installed':False, 'runtime_files':len(runtime), 'complete_source_files':len(source), 'sha256':hashes,
        'acceptance':'Offline fixtures and exact LLL folder preflight only; native game preview pending.'
    }, indent=2)+'\n')
    print(lll)
    print(src)

if __name__ == '__main__':
    main()
