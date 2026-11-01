"""Assemble maintained LLL sources for the replacement LuaJIT state.

This creates a bootstrap factory, not an archive to install into PUC Lua.
The native host must load stock resources and supply verified engine bindings.
Mod files and the shared LLL checkout are not changed.
"""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parent
LLL = Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/LLL')
sys.path.insert(0, str(LLL / 'tools'))
from build import MODULES
from build_steam_release import PROTECTED, OVERRIDES

EXCLUDE = {'LLL_MEMORY', 'LLL_BUILD_GATE', 'LLL_JIT_GUARD', 'LLL_JIT_CHURN'}


def assemble(stock):
    inputs = {}

    def read(path):
        data = path.read_bytes()
        inputs[str(path)] = hashlib.sha256(data).hexdigest()
        return data.decode('utf-8')

    def module(name):
        return '(function()\n' + read(LLL / 'src' / (name + '.lua')) + '\nend)()'

    body = [
        'local LLL_TRUST=' + module('trusted') + '.capture(_G)',
        'local ' + ','.join(PROTECTED) + '=' + ','.join('LLL_TRUST.' + n for n in PROTECTED),
        'local jit,ffi=LLL_TRUST.jit,require("ffi")',
        'assert(type(jit.status)=="function" and ffi.abi("64bit") and not ffi.abi("gc64"),"FR1 LuaJIT required")',
        'local LLL_METADATA=' + module('metadata'),
        'local LLL_STEAM_SERVICE=context.service',
        'local LLL_STEAM_TRANSPORT=' + module('steam/transport'),
        'local LLL_STEAM_BUILDS={exe_sha256="0acc07debe04714ae04281e1a66bd2eb9d3d85232953e32a93c8a3dd0874eabe",'
        'game_sha256="6d1d4d3bc6fc84801d9f8f1b310e13a603d07409f3d9495d74b42e1d0bb1c08f"}',
        'local LLL_STEAM_INPUT=' + module('steam/input'),
        'local LLL_STEAM_INPUT_SERVICE=' + module('steam/input_service'),
        'local LLL_STEAM_SCREENSHOT_SERVICE=' + module('steam/screenshot_service'),
        'local LLL_JIT_MEMORY=(function()\n' + read(ROOT / 'bootstrap_memory.lua') + '\nend)()',
    ]
    for variable, name in MODULES:
        if variable in EXCLUDE:
            continue
        value = module(OVERRIDES.get(name, name))
        if name == 'jit_budget':
            # The old private jit_State churn patch is specific to the removed
            # engine DLL. Retain only the maintained public jit.opt API policy.
            value = ('(function(base) return {start=function(library,settings,report) '
                     'return base.start(library,settings,report) end} end)(' + value + ')')
        elif name == 'ui/font':
            value = ('(function(base) return {new=function() '
                     'local memory=LLL_JIT_MEMORY.open(); '
                     'if not memory then return {resolve=function()return nil end} end; '
                     'return base.new(memory,"game.dll") end} end)(' + value + ')')
        elif name == 'platform':
            value = ('(function() if context.platform then return context.platform() end; '
                     'assert(type(LLL_STEAM_SERVICE)=="table","LLL service configuration required"); '
                     'return ' + value + ' end)()')
        body.append('local ' + variable + '=' + value)
    body.append('''
    -- Retain the host/platform build decision; runtime support comes from this
    -- real VM. It does not establish compatibility of engine memory addresses.
    LLL_PLATFORM.runtime=jit.version
    LLL_PLATFORM.native_ffi=true
    LLL_PLATFORM.native_cffi=false
    local original_guard=assert(LLL_PLATFORM.guard)
    LLL_PLATFORM.guard=function()
        local original=assert(original_guard())
        local report={};for k,v in pairs(original)do report[k]=v end
        report.jit_supported=true;report.lua_runtime=jit.version;report.native_ffi=true
        report.lua_sha256=context.runtime_sha256 or 'replacement runtime; fingerprint not supplied'
        return report
    end
    ''')
    body.append(read(LLL / 'src/start.lua'))
    literal = '"' + ''.join('\\%03d' % n for n in stock) + '"'
    source = ('return function(context,...)\n'
              'assert(type(context)=="table","bootstrap context required")\n'
              'assert(not rawget(_G,"LiveLuaLoader"),"LLL already initialized")\n'
              'local function start()\n' + '\n'.join(body) + '\nend\n'
              'local function finish(...) start();return ... end\n'
              'return finish(assert(loadstring(' + literal + ',"@stock_steam_boot"))(...))\n'
              'end\n').encode()
    receipt = {'kind': 'LuaJIT LLL bootstrap factory', 'sources': inputs,
               'source_sha256': hashlib.sha256(source).hexdigest(),
               'stock_input_sha256': hashlib.sha256(stock).hexdigest(),
               'excluded_modules': sorted(EXCLUDE), 'mod_sources_changed': False,
               'private_jit_state_churn_patch': False, 'puc_native_initializers_invoked': False,
               'native_font_reader': 'LuaJIT FFI ReadProcessMemory; engine descriptor still gated',
               'engine_deployed': False}
    return source, receipt


if __name__ == '__main__':
    source, receipt = assemble((ROOT / 'work/stock/f476df93691895fa.luac').read_bytes())
    (ROOT / 'work/bootstrap.lua').write_bytes(source)
    (ROOT / 'work/BOOTSTRAP.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'bytes': len(source), 'sha256': receipt['source_sha256']}))
