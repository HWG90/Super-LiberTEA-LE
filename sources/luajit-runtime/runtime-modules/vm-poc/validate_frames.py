"""Run captured Win64 frame callers against the real replacement library."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
from validate import parse

ROOT = Path(__file__).resolve().parent


def validate():
    results = {}
    evidence = json.loads((ROOT / 'frame-route-evidence.json').read_text())
    assert hashlib.sha256(Path(evidence['capture']).read_bytes()).hexdigest() == evidence['capture_sha256']
    for platform in ['linux', 'windows', 'reference']:
        folder = ROOT / 'dist' / platform
        build = json.loads((folder / 'BUILD.json').read_text())
        for name, want in build['files'].items():
            assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == want, name
        for name, want in build['inputs'].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == want, name
        command = [str(folder / ('vm-poc.exe' if platform == 'windows' else 'vm-poc')), 'frames']
        env = dict(os.environ)
        if platform == 'windows':
            command.insert(0, 'wine')
            env.update(WINEPREFIX=str(ROOT.parent / 'build/wine-prefix'), WINEDEBUG='-all',
                       WINEDLLOVERRIDES='mscoree,mshtml=')
        run = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        (folder / 'frames.log').write_text(run.stdout + run.stderr)
        assert run.returncode == 0, (platform, run.returncode, run.stdout, run.stderr)
        frames = parse(run.stdout, 'POC_FRAMES')
        count = 16 if platform == 'reference' else 4016
        expected = dict.fromkeys(['guards', 'float_abi', 'hooks', 'old_state_inaccessible',
                                  'errors', 'rebind', 'rollback', 'associations', 'thread',
                                  'lifetime', 'recursion'], 'pass')
        expected.update(callers=2, updates=count, renders=count, collections=count)
        assert frames == expected, (platform, frames)
        result = {'frames': frames, 'build': build,
                  'execution': 'Wine' if platform == 'windows' else 'Linux with Win64 ABI caller execution'}
        if platform != 'reference':
            jit = parse(run.stdout, 'POC_JIT')
            assert jit['enabled'] and jit['mod_traces'] > 0 and jit['mod_machine_code'] > 0
            lifecycle = parse(run.stdout, 'POC_BOOTSTRAP')
            assert lifecycle == {'stock': 'pass', 'startup': 'pass', 'mod': 'LLL_Poll_Cache',
                'update': 'pass', 'restart_policy': 'pass', 'fixture_reload': 'pass',
                'fixture_disable': 'pass', 'shutdown': 'pass', 'ffi': 'real', 'bit': 'real'}
            result.update(jit=jit, lifecycle=lifecycle)
        results[platform] = result
    from prepare import build_poll_cache
    _, original = build_poll_cache.runtime_files()
    mod = json.loads((ROOT / 'work/PROVENANCE.json').read_text())['mod']
    for name, want in mod['files'].items():
        assert hashlib.sha256(original[name]).hexdigest() == want
        assert hashlib.sha256((ROOT / 'work/mod' / name).read_bytes()).hexdigest() == want
    receipt = {
        'status': 'captured frame callers passed in isolated owned images',
        'validated_at': datetime.now(timezone.utc).isoformat(),
        'platforms': results, 'evidence': evidence, 'mod': mod,
        'mod_sources_changed': False, 'stock_and_mod_share_state_and_thread': True,
        'workers_used': False, 'in_game_vm_replaced': False, 'native_windows_tested': False,
        'old_state_fields': 'both duplicate PUC state pointers target an owned inaccessible page',
        'rollback': 'complete captured caller bytes restored and accepted again by planner',
        'transitive_native_calls': 'controlled C stubs; only captured update/render caller bytes executed',
        'gc_policy': 'captured timed scheduler with real replacement VM collection; separate GC-VALIDATION compares original policy',
        'error_context': 'Lua errors caught inside the replacement; original engine TLS and reporter unported',
        'bootstrap_frames': 4000,
        'frame_routes': 'captured callers directly target Win64 adapters exported by the replacement core',
        'native_exception_unwind': 'not exercised; no exception may cross the copied caller code',
    }
    (ROOT / 'dist/FRAME-VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'],
                      'frames': {p: r['frames'] for p, r in results.items()},
                      'jit': {p: r.get('jit') for p, r in results.items()},
                      'in_game_vm_replaced': False}, indent=2))


if __name__ == '__main__':
    validate()
