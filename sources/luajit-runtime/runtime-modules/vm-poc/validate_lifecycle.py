"""Validate captured construction -> LuaJIT frames -> captured destruction."""
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
    evidence = json.loads((ROOT / 'lifecycle-route-evidence.json').read_text())
    assert hashlib.sha256(Path(evidence['capture']).read_bytes()).hexdigest() == evidence['capture_sha256']
    for platform in ['linux', 'windows', 'reference']:
        folder = ROOT / 'dist' / platform
        build = json.loads((folder / 'BUILD.json').read_text())
        for name, want in build['files'].items():
            assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == want, name
        for name, want in build['inputs'].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == want, name
        command = [str(folder / ('vm-poc.exe' if platform == 'windows' else 'vm-poc'))]
        env = dict(os.environ)
        if platform == 'windows':
            command.insert(0, 'wine')
            env.update(WINEPREFIX=str(ROOT.parent / 'build/wine-prefix'), WINEDEBUG='-all',
                       WINEDLLOVERRIDES='mscoree,mshtml=')
        run = subprocess.run([*command, 'lifecycle'], env=env, capture_output=True, text=True, timeout=60)
        (folder / 'lifecycle.log').write_text(run.stdout + run.stderr)
        assert run.returncode == 0, (platform, run.returncode, run.stdout, run.stderr)
        lifecycle = parse(run.stdout, 'POC_LIFECYCLE')
        expected = dict.fromkeys(['construct', 'close', 'bookkeeping', 'no_puc_state',
                                 'finalizers', 'reuse', 'guards', 'rollback'], 'pass')
        expected.update(states=2, frames=4001)
        assert lifecycle == expected, (platform, lifecycle)
        assert run.stdout.splitlines().count('POC_LIFECYCLE_FINALIZER') == 2
        failed = subprocess.run([*command, 'lifecycle-fail'], env=env, capture_output=True, text=True, timeout=60)
        (folder / 'lifecycle-failure.log').write_text(failed.stdout + failed.stderr)
        assert failed.returncode == 42, (platform, failed.returncode, failed.stdout, failed.stderr)
        result = {'lifecycle': lifecycle, 'creation_failure_exit_code': failed.returncode,
                  'build': build, 'execution': 'Wine' if platform == 'windows' else 'Linux with Win64 ABI caller execution'}
        if platform != 'reference':
            jit = parse(run.stdout, 'POC_JIT')
            assert jit['enabled'] and jit['mod_traces'] > 0 and jit['mod_machine_code'] > 0
            bootstrap = parse(run.stdout, 'POC_BOOTSTRAP')
            assert bootstrap == {'stock': 'pass', 'startup': 'pass', 'mod': 'LLL_Poll_Cache',
                'update': 'pass', 'restart_policy': 'pass', 'fixture_reload': 'pass',
                'fixture_disable': 'pass', 'shutdown': 'pass', 'ffi': 'real', 'bit': 'real'}
            result.update(jit=jit, bootstrap=bootstrap)
        results[platform] = result
    from prepare import build_poll_cache
    _, original = build_poll_cache.runtime_files()
    mod = json.loads((ROOT / 'work/PROVENANCE.json').read_text())['mod']
    for name, want in mod['files'].items():
        assert hashlib.sha256(original[name]).hexdigest() == want
        assert hashlib.sha256((ROOT / 'work/mod' / name).read_bytes()).hexdigest() == want
    receipt = {
        'status': 'captured native construction, frames and destruction passed in isolated owned images',
        'validated_at': datetime.now(timezone.utc).isoformat(),
        'platforms': results, 'evidence': evidence, 'mod': mod,
        'mod_sources_changed': False, 'stock_and_mod_share_state_and_thread': True,
        'workers_used': False, 'in_game_vm_replaced': False, 'native_windows_tested': False,
        'native_factory': 'configured by the standalone host before captured constructor execution; no early game loader installed',
        'construction': 'native metadata instructions preserved; PUC creation, registry and library setup replaced by the LuaJIT factory',
        'destruction': 'captured native buffer cleanup, Lua finalizers, host close notification, captured allocator cleanup in that order',
        'transitive_helpers': 'allocator, engine and filesystem callbacks are fixtures',
        'boot': 'stock boot through core resource loader and assembled LLL; captured native boot is validated separately',
        'shutdown': 'Lua shutdown tested here; captured native game shutdown is validated separately by validate_shutdown.py',
        'gc': 'public-step fixture policy; original engine timed GC remains unported',
        'exceptions': 'native exception unwinding across copied code not exercised',
    }
    (ROOT / 'dist/LIFECYCLE-VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'],
                      'results': {p: {'lifecycle': r['lifecycle'], 'jit': r.get('jit'),
                                      'creation_failure_exit_code': r['creation_failure_exit_code']} for p, r in results.items()},
                      'in_game_vm_replaced': False}, indent=2))


if __name__ == '__main__':
    validate()
