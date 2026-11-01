"""Read-only validation of the curve binding candidate against a captured image.

This never calls an engine function or opens a live process.
"""
from pathlib import Path
import ctypes
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parent
CAPTURE = Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/current-mapped.bin')
CAPTURE_SHA256 = '8524c3520526db59e880372f05c30f546fce4cb0821b18c807b9b040ab4da6f0'


def verify():
    data = bytearray(CAPTURE.read_bytes())
    assert hashlib.sha256(data).hexdigest() == CAPTURE_SHA256, 'capture changed; re-trace first'
    evidence = json.loads((ROOT / 'native-curve-evidence.json').read_text())
    for witness in evidence['witnesses']:
        offset = int(witness['rva'], 16)
        expected = bytes.fromhex(witness['hex'])
        assert data[offset:offset + len(expected)] == expected, witness['meaning']
    function = bytes.fromhex(evidence['function_hex'])
    assert hashlib.sha256(function).hexdigest() == evidence['function_sha256']
    library = ctypes.CDLL(str(ROOT / 'dist/linux/libhd2_lua_environment.so'))
    probe = library.hd2env_probe_curve_image
    probe.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t]
    probe.restype = ctypes.c_int
    buffer = (ctypes.c_ubyte * len(data)).from_buffer(data)
    size = len(data)
    base = 0x140000000
    assert probe(buffer, size, base) == 1
    nt = struct.unpack_from('<I', data, 0x3c)[0]
    cases = {'null': probe(None, size, base),
             'short_buffer': probe(buffer, 0x29fe000 - 1, base),
             'wrong_mapping_base': probe(buffer, size, base + 0x10000),
             'overflowing_mapping_base': probe(buffer, size, (1 << 64) - 1)}
    for name, offset in [('dos_magic', 0), ('nt_offset', 0x3c), ('pe_magic', nt),
                         ('architecture', nt + 4), ('timestamp', nt + 8),
                         ('optional_magic', nt + 24), ('image_size', nt + 24 + 56),
                         ('native_table_pointer', 0x2870810), ('native_code', 0x1f8390)]:
        data[offset] ^= 0x80
        cases[name] = probe(buffer, size, base)
        data[offset] ^= 0x80
    assert all(value == 0 for value in cases.values()), cases
    assert probe(buffer, size, base) == 1, 'test did not restore the buffer'
    receipt = {'status': 'passed', 'capture': str(CAPTURE), 'capture_sha256': CAPTURE_SHA256,
               'witnesses': len(evidence['witnesses']), 'positive_probe': True,
               'rejected_mutations': list(cases), 'native_calls_performed': False,
               'live_process_accessed': False, 'binding': evidence}
    (ROOT / 'dist/NATIVE-VALIDATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    result = verify()
    print(json.dumps({'status': result['status'], 'witnesses': result['witnesses'],
                      'rejected_mutations': len(result['rejected_mutations']),
                      'native_calls_performed': False}))
