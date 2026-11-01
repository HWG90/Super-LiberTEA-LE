"""Validate the complete LLL lifecycle in the actual shared LuaJIT library."""
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
from pathlib import Path

from assemble_bootstrap import assemble
from validate import parse

ROOT = Path(__file__).resolve().parent


def validate():
    source, provenance = assemble((ROOT / 'work/stock/f476df93691895fa.luac').read_bytes())
    assert source == (ROOT / 'work/bootstrap.lua').read_bytes(), 'bootstrap sources changed'
    assert provenance == json.loads((ROOT / 'work/BOOTSTRAP.json').read_text())
    results = {}
    for platform in ['linux', 'windows']:
        folder = ROOT / 'dist' / platform
        build = json.loads((folder / 'BUILD.json').read_text())
        for name, expected in build['files'].items():
            assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected
        for name, expected in build['inputs'].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected
        command = [str(folder / ('vm-poc.exe' if platform == 'windows' else 'vm-poc')), 'bootstrap']
        env = dict(os.environ)
        if platform == 'windows':
            command.insert(0, 'wine')
            env.update(WINEPREFIX=str(ROOT.parent / 'build/wine-prefix'), WINEDEBUG='-all',
                       WINEDLLOVERRIDES='mscoree,mshtml=')
        run = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        (folder / 'bootstrap.log').write_text(run.stdout + run.stderr)
        assert run.returncode == 0, (platform, run.stdout, run.stderr)
        lifecycle, jit = parse(run.stdout, 'POC_BOOTSTRAP'), parse(run.stdout, 'POC_JIT')
        assert lifecycle == {'stock': 'pass', 'startup': 'pass', 'mod': 'LLL_Poll_Cache',
            'update': 'pass', 'restart_policy': 'pass', 'fixture_reload': 'pass',
            'fixture_disable': 'pass', 'shutdown': 'pass', 'ffi': 'real', 'bit': 'real'}
        assert jit['enabled'] and jit['mod_traces'] > 0 and jit['mod_machine_code'] > 0
        result = {'lifecycle': lifecycle, 'jit': jit, 'build': build,
                  'execution': 'Wine' if platform == 'windows' else 'Linux native'}
        result['native_entry'] = parse(run.stdout, 'POC_ENTRY')
        assert result['native_entry'] == {'typed_arguments': 'pass', 'results': 'pass',
            'binary_strings': 'pass', 'errors': 'pass', 'gc_lifetime': 'pass', 'close_lifetime': 'pass'}
        result['objects'] = parse(run.stdout, 'POC_OBJECTS')
        assert result['objects'] == dict.fromkeys(['ownership','identity','metamethods','errors','collection','stale','foreign'], 'pass')
        if platform == 'windows':
            result['memory'] = parse(run.stdout, 'POC_BOOTSTRAP_MEMORY')
            assert result['memory'] == {'self_read': 'pass', 'invalid_reads': 'pass'}
        results[platform] = result
    from prepare import build_poll_cache
    _, original = build_poll_cache.runtime_files()
    mod = json.loads((ROOT / 'work/PROVENANCE.json').read_text())['mod']
    for name, expected in mod['files'].items():
        assert hashlib.sha256(original[name]).hexdigest() == expected
        assert hashlib.sha256((ROOT / 'work/mod' / name).read_bytes()).hexdigest() == expected
    receipt = {'status': 'standalone full LLL bootstrap passed',
               'validated_at': datetime.now(timezone.utc).isoformat(), 'platforms': results,
               'provenance': provenance, 'mod': mod, 'mod_sources_changed': False,
               'stock_and_mod_share_state_and_thread': True, 'workers_used': False,
               'frame_entry': 'registry-owned LuaJIT function and argument objects, 4000 calls',
               'additional_cross_environment_ownership_test_states': 2,
               'native_backend': 'fixture; live service and engine UI not exercised',
               'puc_native_initializers_invoked': False, 'in_game_vm_replaced': False,
               'native_windows_tested': False}
    (ROOT / 'dist/BOOTSTRAP-VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'], 'jit': {p: r['jit'] for p, r in results.items()},
                      'in_game_vm_replaced': False}, indent=2))


if __name__ == '__main__':
    validate()
