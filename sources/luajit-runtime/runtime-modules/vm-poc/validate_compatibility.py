"""Compile, never execute, original mod chunks in the selected runtime.

The GC64 negative control proves why the replacement needs the old FR1 layout.
Parsing proves bytecode/syntax acceptance, not gameplay compatibility.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parent
TRACE = ROOT.parent / 'vm-trace'


def check(platform, cases, control=False):
    windows = platform == 'windows'
    runtime = ROOT.parent / 'build/linux/LuaJIT' if control else ROOT / 'work/runtime' / platform / 'LuaJIT'
    executable = runtime / 'src' / ('luajit.exe' if windows else 'luajit')
    rows = []
    for case in cases:
        path = str(Path(case['path']).resolve())
        if windows:
            path = 'Z:' + path
        rows.append('{' + json.dumps(case['key']) + ',' + json.dumps(path) + '}')
    script = 'local cases={' + ',\n'.join(rows) + '}\n' + '''
jit.off()
for _,case in ipairs(cases) do
    local fn,message=loadfile(case[2])
    print(case[1]..'\t'..(fn and 'accepted' or 'rejected')..'\t'..tostring(message or ''):gsub('[\r\n\t]',' '))
end
os.exit(0)
'''.replace("'[\r\n\t]'", "'[\\r\\n\\t]'")
    label = platform + ('-gc64-control' if control else '-fr1')
    file = ROOT / 'work' / ('compile-' + label + '.lua')
    file.write_text(script)
    command = [str(executable), str(file) if not windows else 'Z:' + str(file)]
    env = dict(os.environ)
    if windows:
        command.insert(0, 'wine')
        env.update(WINEPREFIX=str(ROOT.parent / 'build/wine-prefix'), WINEDEBUG='-all',
                   WINEDLLOVERRIDES='mscoree,mshtml=')
    run = subprocess.run(command, capture_output=True, text=True, env=env, timeout=60)
    (ROOT / 'dist' / ('compatibility-' + label + '.log')).write_text(run.stdout + run.stderr)
    assert run.returncode == 0, (command, run.stdout, run.stderr)
    results = {}
    for line in run.stdout.splitlines():
        key, status, message = line.split('\t', 2)
        results[key] = {'accepted': status == 'accepted', 'message': message}
    assert len(results) == len(cases), (label, len(results), len(cases))
    return results


def validate():
    inventory = json.loads((TRACE / 'runtime-inventory.json').read_text())
    assert not inventory['failures']
    unique = {}
    for row in inventory['resources']:
        if row['origin'] != 'original-mod':
            continue
        key = row['chunk_sha256']
        path = TRACE / 'inventory-work/chunks' / (key + '.bin')
        assert hashlib.sha256(path.read_bytes()).hexdigest() == key
        unique[key] = {'key': key, 'path': str(path), 'format': row['format'],
                       'archive': row['archive'], 'id': row['id']}
    originals = list(unique.values())
    provenance = json.loads((ROOT / 'work/PROVENANCE.json').read_text())
    stock = [{'key': 'stock-' + row['id'], 'path': str(ROOT / 'work/stock' / (row['id'] + '.lua')),
              'format': 'recovered-stock-source', 'id': row['id']} for row in provenance['stock']]
    cases = originals + stock
    legacy = [case for case in originals if case['format'].startswith('luajit-bytecode')]
    assert len(legacy) == 2
    control = check('linux', legacy, control=True)
    assert all(not row['accepted'] and 'incompatible bytecode' in row['message'] for row in control.values())
    results = {platform: check(platform, cases) for platform in ['linux', 'windows']}
    failed = {platform: {key: row for key, row in rows.items() if not row['accepted']}
              for platform, rows in results.items()}
    receipt = {'original_mod_chunk_count': len(originals), 'recovered_stock_chunk_count': len(stock),
               'legacy_bytecode_chunks': len(legacy), 'gc64_negative_control': control,
               'runtime_layout': 'FR1 / non-GC64', 'results': results, 'cases': cases,
               'parse_only': True, 'mod_chunks_executed': False, 'native_windows_tested': False,
               'all_accepted': all(not value for value in failed.values()), 'failures': failed}
    (ROOT / 'dist/COMPATIBILITY.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert receipt['all_accepted'], failed
    print(json.dumps({key: receipt[key] for key in ['original_mod_chunk_count', 'recovered_stock_chunk_count',
                       'legacy_bytecode_chunks', 'runtime_layout', 'parse_only', 'all_accepted']}))
    return receipt


if __name__ == '__main__':
    validate()
