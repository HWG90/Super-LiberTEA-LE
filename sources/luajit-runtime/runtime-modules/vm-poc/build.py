"""Build the portable environment core and its separate fixture executable."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent
PRIOR=Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison')

def build(platform):
    windows=platform=='windows';reference=platform=='reference'
    cc='x86_64-w64-mingw32-gcc' if windows else 'cc'
    src=PRIOR/'lua-5.1.4/src' if reference else ROOT/'work/runtime'/platform/'LuaJIT/src'
    lib=PRIOR/'liblua514.so' if reference else src/'libluajit.a'
    runtime_receipt=None if reference else json.loads((src.parents[1]/'BUILD.json').read_text())
    if runtime_receipt:
        assert runtime_receipt['gc64'] is False and hashlib.sha256(lib.read_bytes()).hexdigest()==runtime_receipt['library_sha256']
        # The private, read-only estimate adapter must use headers from the
        # exact source revision that produced the pinned FR1 library.
        vendor=ROOT.parent/'vendor/LuaJIT'
        revision=subprocess.check_output(['git','-C',str(vendor),'rev-parse','HEAD'],text=True).strip()
        assert revision==runtime_receipt['luajit_commit']
        for header in ['lj_obj.h','lj_arch.h','lj_def.h','lua.h','luaconf.h']:
            pinned=subprocess.check_output(['git','-C',str(vendor),'show',revision+':src/'+header])
            assert (src/header).read_bytes()==pinned,header
    runtime_headers={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(src.glob('*.h'))}
    out=ROOT/'dist'/platform;out.mkdir(parents=True,exist_ok=True)
    flags=['-std=c11','-O2','-g','-Wall','-Wextra','-Werror','-I'+str(src),'-I'+str(ROOT/'work')]
    if reference:flags+=['-DHD2ENV_PUC_REFERENCE','-Wl,-rpath,'+str(PRIOR)]
    libraries=[str(lib)]+([] if windows else ['-lm','-ldl','-pthread'])
    exe=out/('vm-poc.exe' if windows else 'vm-poc')
    sources=[str(ROOT/name) for name in ['environment.c','engine_curve.c','frame_routes.c','lifecycle_routes.c','boot_routes.c','shutdown_routes.c','gc_routes.c','engine_steam.c','engine_friends.c','engine_voip.c','engine_vectors.c','engine_puc.c','engine_resources.c']]
    harness=[str(ROOT/name) for name in ['harness.c','entry_tests.c','object_tests.c','frame_tests.c','lifecycle_tests.c','boot_tests.c','steam_tests.c','friends_tests.c','voip_tests.c','shutdown_tests.c','gc_tests.c']]
    files=[]
    if not reference:
        dll=out/('hd2_lua_environment.dll' if windows else 'libhd2_lua_environment.so')
        shared=['-shared','-fvisibility=hidden']
        implib=out/'libhd2_lua_environment.dll.a'
        shared+=['-DHD2ENV_DLL','-Wl,--out-implib,'+str(implib)] if windows else [
            '-fPIC','-Wl,-Bsymbolic','-Wl,--exclude-libs,ALL','-Wl,-soname,'+dll.name]
        subprocess.run([cc,*flags,*shared,*sources,*libraries,'-o',str(dll)],check=True)
        files.append(dll)
        linkage=[str(implib)] if windows else ['-L'+str(out),'-lhd2_lua_environment','-Wl,-rpath,$ORIGIN','-pthread']
        # Exercise the deliverable library itself, not another copy linked into the harness.
        subprocess.run([cc,*flags,*harness,*linkage,'-o',str(exe)],check=True)
        if windows:files.append(implib)
        copyright=out/'LuaJIT-COPYRIGHT.txt'
        shutil.copyfile(ROOT.parent/'vendor/LuaJIT/COPYRIGHT',copyright)
        files.append(copyright)
    else:
        subprocess.run([cc,*flags,*sources,*harness,*libraries,'-o',str(exe)],check=True)
    files.append(exe)
    fault=out/('object-fault-tests.exe' if windows else 'object-fault-tests')
    subprocess.run([cc,*flags,str(ROOT/'object_fault_tests.c'),str(ROOT/'engine_curve.c'),str(ROOT/'engine_steam.c'),str(ROOT/'engine_friends.c'),str(ROOT/'engine_voip.c'),str(ROOT/'engine_vectors.c'),str(ROOT/'engine_puc.c'),str(ROOT/'engine_resources.c'),
                    *libraries,'-o',str(fault)],check=True)
    files.append(fault)
    receipt={'platform':platform,'kind':'standalone fixture and portable integration core',
             'harness_linkage':'PUC reference' if reference else 'shared environment library',
             'runtime_library':str(lib),'runtime_library_sha256':hashlib.sha256(lib.read_bytes()).hexdigest(),
             'runtime_build':runtime_receipt,
             'runtime_headers':runtime_headers,
             'inputs':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in [ROOT/'environment.h',ROOT/'environment.c',ROOT/'gc_policy.h',ROOT/'gc_policy.inc',ROOT/'gc_runtime.inc',ROOT/'prepare_gc.py',ROOT/'work/gc_witnesses.h',ROOT/'gc-policy-evidence.json',ROOT/'engine_curve.c',
                                 ROOT/'frame_routes.h',ROOT/'frame_routes.c',ROOT/'frame_tests.c',ROOT/'frames.inc',
                                 ROOT/'lifecycle_routes.h',ROOT/'lifecycle_routes.c',ROOT/'lifecycle_tests.c',ROOT/'lifecycle.inc',
                                 ROOT/'native_steam.h',ROOT/'steam_test_fixture.h',ROOT/'engine_steam.c',ROOT/'steam.inc',ROOT/'steam_tests.c',
                                 ROOT/'prepare_steam.py',ROOT/'work/steam_witnesses.h',ROOT/'steam-binding-evidence.json',
                                 ROOT/'native_voip.h',ROOT/'engine_voip.c',ROOT/'voip.inc',ROOT/'voip_tests.c',ROOT/'voip_test_fixture.h',
                                 ROOT/'native_vectors.h',ROOT/'engine_vectors.c',ROOT/'vector2.inc',ROOT/'prepare_vectors.py',ROOT/'work/vector2_witnesses.h',ROOT/'vector2-binding-evidence.json',
                                 ROOT/'vector3.inc',ROOT/'work/vector3_witnesses.h',ROOT/'vector3-binding-evidence.json',
                                 ROOT/'vector3box.inc',ROOT/'work/vector3box_witnesses.h',ROOT/'vector3box-binding-evidence.json',
                                 ROOT/'vector4.inc',ROOT/'quaternion.inc',ROOT/'work/quaternion_witnesses.h',ROOT/'work/vector4_witnesses.h',ROOT/'vector4-binding-evidence.json',
                                 ROOT/'prepare_voip.py',ROOT/'work/voip_witnesses.h',ROOT/'voip-binding-evidence.json',
                                 ROOT/'native_friends.h',ROOT/'engine_friends.c',ROOT/'friends.inc',ROOT/'friends_tests.c',ROOT/'friends_test_fixture.h',
                                 ROOT/'prepare_friends.py',ROOT/'work/friends_witnesses.h',ROOT/'friends-binding-evidence.json',
                                 ROOT/'shutdown_routes.h',ROOT/'shutdown_routes.c',ROOT/'gc_routes.c',ROOT/'shutdown.inc',ROOT/'shutdown_tests.c',ROOT/'gc_tests.c',ROOT/'shutdown_test_fixture.h',
                                 ROOT/'prepare_shutdown.py',ROOT/'work/shutdown_witnesses.h',ROOT/'shutdown-route-evidence.json',
                                 ROOT/'boot_routes.h',ROOT/'boot_routes.c',ROOT/'boot_tests.c',ROOT/'boot.inc',ROOT/'boot_config.inc',
                                 ROOT/'prepare_boot.py',ROOT/'work/boot_witnesses.h',ROOT/'boot-route-evidence.json',
                                 ROOT/'prepare_lifecycle.py',ROOT/'work/lifecycle_witnesses.h',ROOT/'lifecycle-route-evidence.json',
                                 ROOT/'prepare_frames.py',ROOT/'work/frame_witnesses.h',ROOT/'frame-route-evidence.json',
                                 ROOT/'harness.c',ROOT/'entry_tests.c',ROOT/'objects.inc',ROOT/'object_tests.c',ROOT/'object_fault_tests.c',ROOT/'work/assets.h',ROOT/'work/curve_witness.h',
                                 ROOT/'load_compat.lua',ROOT/'work/load_compat.h',ROOT/'assemble_bootstrap.py',
                                 ROOT/'bootstrap_scenarios.lua',ROOT/'bootstrap_memory.lua',ROOT/'work/BOOTSTRAP.json',
                                 ROOT/'prepare.py',ROOT/'scenarios.lua',ROOT/'loader_scenarios.lua',ROOT/'trace.lua',ROOT/'build.py']},
             'in_game_installed':False,'native_windows_tested':False,
             'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    (out/'BUILD.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--platform',choices=['linux','windows','reference','all'],default='all')
    a=p.parse_args()
    for target in ['linux','windows','reference'] if a.platform=='all' else [a.platform]:build(target)
