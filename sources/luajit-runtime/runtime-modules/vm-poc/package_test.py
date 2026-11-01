"""Freeze a validated local Win64 proof without replacing any existing package."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent


def package(kind="lifecycle", revision=0):
    build = json.loads((ROOT / 'dist/windows/BUILD.json').read_text())
    receipts = ['FRAME-VALIDATION.json', 'LIFECYCLE-VALIDATION.json']
    if kind in ('boot', 'steam', 'friends', 'shutdown', 'gc'):
        receipts.append('BOOT-VALIDATION.json')
    if kind in ('steam', 'friends', 'shutdown', 'gc'):
        receipts.append('STEAM-VALIDATION.json')
    if kind in ('friends', 'shutdown', 'gc'):
        receipts.append('FRIENDS-VALIDATION.json')
    if kind in ('shutdown', 'gc'):
        receipts.extend(['VOIP-VALIDATION.json','SHUTDOWN-VALIDATION.json'])
    if kind == 'gc':
        receipts.append('GC-VALIDATION.json')
    for name in receipts:
        receipt = json.loads((ROOT / 'dist' / name).read_text())
        assert receipt['platforms']['windows']['build'] == build, name
        assert receipt['platforms']['windows']['execution'] == 'Wine', name
    for name, want in build['inputs'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == want, name
    for name, want in build['files'].items():
        assert hashlib.sha256((ROOT / 'dist/windows' / name).read_bytes()).hexdigest() == want, name
    assert revision >= 0
    destination = ROOT.parent / ('test-builds/2026-10-24-' + kind + '-poc' + ('-r'+str(revision) if revision else ''))
    archive = destination.with_suffix('.zip')
    assert not destination.exists() and not archive.exists(), 'Frozen package already exists'
    destination.mkdir(parents=True)
    for name in ['vm-poc.exe', 'hd2_lua_environment.dll', 'LuaJIT-COPYRIGHT.txt', 'BUILD.json']:
        shutil.copyfile(ROOT / 'dist/windows' / name, destination / name)
    for name in receipts:
        shutil.copyfile(ROOT / 'dist' / name, destination / name)
    (destination / 'README.txt').write_text("""LuaJIT restoration - standalone lifecycle proof, 2026-10-24

Extract this folder anywhere outside the game installation. Keep the EXE and
DLL together. Open PowerShell in the folder and run:

  .\\vm-poc.exe lifecycle *> lifecycle.log
  $LASTEXITCODE

Success: exit code 0. The log contains POC_LIFECYCLE with pass results,
POC_BOOTSTRAP with mod=LLL_Poll_Cache, and POC_JIT with enabled=true and
nonzero mod_traces. Additional focused frame checks:

  .\\vm-poc.exe frames *> frames.log
  $LASTEXITCODE

The lifecycle test runs captured native construction, stock boot plus unchanged
Poll Cache for 4,000 LLL frames, captured destruction, and another stock frame
in a recreated state. JIT compilation happens in the mod's own state/thread.
There are no worker routines or mod rewrites.

The game and filesystem inputs, allocators and engine callbacks are fixtures.
This is not an installable game mod or a complete in-game VM replacement. It
does not launch, patch or connect to the game. No game files are required at
runtime: the local research assets are embedded. Native boot/shutdown, full
callback parity, the engine GC policy and an early game loader remain incomplete.

Linux and Wine passed. Native Windows remains untested. Return the log files
and exit codes from a Windows run. SHA256SUMS checks the frozen files and the
JSON receipts record exact source/binary fingerprints and test limitations.
Do not copy these files into the game or replace installed mods with them.
Remove the extracted folder to remove this standalone proof.

The package includes locally extracted stock/caller data for local research;
it is not a public redistributable package. The LuaJIT copyright notice is
included. UCRT and KERNEL32 are the system DLL dependencies.
""")
    if kind in ('boot', 'steam', 'friends', 'shutdown', 'gc'):
        readme = (destination / 'README.txt').read_text()
        readme = readme.replace('standalone lifecycle proof', 'standalone native boot proof')
        readme = readme.replace('vm-poc.exe lifecycle *> lifecycle.log', 'vm-poc.exe boot *> boot.log')
        readme = readme.replace('The log contains POC_LIFECYCLE', 'The log contains POC_BOOT')
        begin = readme.index('The lifecycle test runs')
        end = readme.index('The game and filesystem inputs', begin)
        readme = readme[:begin] + """The boot test executes the captured native boot routine with guarded replacement
routes. Native allocation/global bookkeeping and plugin iteration remain in the
captured code. Eight typed registration callbacks are required, and configuration
globals are translated through the protected Lua API. Native binary-config lookup
selects stock boot, then require/init run in the replacement state.

The same state subsequently loads the assembled LLL bootstrap and unchanged Poll
Cache for 4,000 frames with actual JIT machine code. A second state runs one stock
frame. There are no worker routines or mod rewrites. Captured constructor and
destructor tests remain available with: .\\vm-poc.exe lifecycle

""" + readme[end:]
        readme = readme.replace('Native boot/shutdown, full\ncallback parity',
            'Actual native registrar bodies, plugin VM APIs, game shutdown, full\ncallback parity')
        if kind in ('steam', 'friends', 'shutdown', 'gc'):
            readme = readme.replace('standalone native boot proof', 'standalone native boot and Steam binding proof')
            readme = readme.replace('Actual native registrar bodies,', 'Remaining native registrar bodies,')
            readme += '''
This build replaces the Steam boot-stage fixture with the complete registrar
port and all eleven Lua-facing callbacks. The underlying native Steam service
is still a fixture; no Steam or game requests are sent. Seven other registrar
bodies remain fixtures. Run the focused callback comparisons with:

  .\\vm-poc.exe steam *> steam.log
  $LASTEXITCODE

Expected exit code: 0. POC_STEAM reports callbacks=11, differential_cases=65,
registration=pass, contexts=pass and errors=pass. Captured original callback
bodies are the comparison oracle; PUC/CRT support helpers are fixtures. The
original game VM is not loaded or replaced by this standalone executable.
'''
        if kind in ('friends', 'shutdown', 'gc'):
            readme = readme.replace('standalone native boot and Steam binding proof', 'standalone native boot, Steam and Friends binding proof')
            readme = readme.replace('Seven other registrar\nbodies remain fixtures.',
                'Friends/Presence also uses the complete new registrar. Six other registrar\nbodies remain fixtures.')
            readme += '''
Friends and Presence registration, all fourteen Lua callbacks and twenty-eight
constants are ported. The boot test calls this registrar. Native Steam interfaces
and seven non-Lua helper bodies are fixtures; no invitations or presence updates
are sent. Run the focused callback comparisons with:

  .\\vm-poc.exe friends *> friends.log
  $LASTEXITCODE

Expected exit code: 0. POC_FRIENDS reports callbacks=14, constants=28,
differential_cases=101, registration=pass, order=pass, contexts=pass and errors=pass.
The comparison covers all callbacks, lobby userdata and server destinations,
playing-game results and zero/two/four-result invitation branches. This still
requires the early game loader and remaining engine integrations before it can
replace the game's VM.
'''
        if kind in ('shutdown', 'gc'):
            readme = readme.replace('standalone native boot, Steam and Friends binding proof', 'standalone native shutdown and VM integration proof')
            readme = readme.replace('vm-poc.exe boot *> boot.log', 'vm-poc.exe shutdown *> shutdown.log')
            readme = readme.replace('The log contains POC_BOOT with pass results', 'The log contains POC_SHUTDOWN with pass results')
            begin=readme.index('The boot test executes');end=readme.index('The game and filesystem inputs',begin)
            readme=readme[:begin]+"""The shutdown test executes captured native construction, update/render and the
complete game destructor in four isolated cycles. The first runs unchanged LLL
Poll Cache for 4,000 frames with actual JIT machine code; three more cycles run
stock scripts and exercise native cleanup conditions and Lua errors.

The replacement calls Lua shutdown and public full collection, then preserves
native plugin/service/global/buffer/allocator teardown. Unreachable userdata
finalizes before service teardown; reachable userdata finalizes at state close.
Native services and transitive cleanup helpers remain fixtures. Both old PUC
state pointers target an inaccessible page during the test.

The separate captured native boot proof is also included:

  .\\vm-poc.exe boot *> boot.log
  $LASTEXITCODE

Expected exit code: 0. Six registrar bodies and plugin VM APIs remain incomplete.
There are no worker routines or mod rewrites.

"""+readme[end:]
            readme=readme.replace('plugin VM APIs, game shutdown, full','plugin VM APIs, full')
            readme+='''
Seven partial SteamVoip room/client bindings are included. This does not complete
the SteamVoip registrar or voice lifecycle/update. Run their 175 comparisons:

  .\\vm-poc.exe voip-views *> voip-views.log
  $LASTEXITCODE

Expected exit code: 0. The native single-member hash lookup remains a fixture.
The pinned LuaJIT reports finalizer errors through its ERRFIN event and continues;
PUC reference collection propagates them. Both behaviors were tested explicitly.
SHUTDOWN-VALIDATION.json records these limits and the C sanitizer results.
'''
        if kind == 'gc':
            readme = readme.replace('standalone native shutdown and VM integration proof', 'standalone native GC and VM integration proof')
            readme += '''
Timed frame garbage collection now uses the captured engine scheduling policy
with real LuaJIT memory estimates and public collection APIs. The frame, boot,
lifecycle and shutdown tests all exercise this adapter. Mod changes to Lua GC
pause and step multiplier are preserved after constructor defaults are applied.
Run 300 comparisons against the captured scheduler plus real collection tests:

  .\\vm-poc.exe gc *> gc.log
  $LASTEXITCODE

Expected exit code: 0, POC_GC pass results, differential_cases=300, guards=550.
An intentional finalizer failure prints ERROR in finalizer; this is expected in
this focused test. GC-VALIDATION.json records sanitizer and platform results.
Native GC settings/profiler wiring remains incomplete. Runtime-specific GC
steps do not imply identical pause durations or reclamation to the original VM.
'''
        (destination / 'README.txt').write_text(readme)
    files = sorted(destination.iterdir())
    (destination / 'SHA256SUMS').write_text(''.join(
        hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files))
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as output:
        for p in sorted(destination.iterdir()):
            output.write(p, p.name)
    with zipfile.ZipFile(archive) as check:
        assert check.testzip() is None
        for row in check.read('SHA256SUMS').decode().splitlines():
            want, name = row.split('  ', 1)
            assert hashlib.sha256(check.read(name)).hexdigest() == want, name
    print(json.dumps({'package': str(archive), 'bytes': archive.stat().st_size,
                      'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                      'validated_under_Wine': True, 'native_windows_tested': False}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--kind', choices=['lifecycle', 'boot', 'steam', 'friends', 'shutdown', 'gc'], default='lifecycle')
    parser.add_argument('--revision', type=int, default=0)
    args = parser.parse_args()
    package(args.kind, args.revision)
