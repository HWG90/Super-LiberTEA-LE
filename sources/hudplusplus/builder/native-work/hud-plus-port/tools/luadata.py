"""Read and write HUD Plus's game.data module (a Lua table literal) as JSON-like Python data.

The bundle's modules are separate `modules["name"] = function(require) ... end` blocks; game.data is a
single `return {...}` table with string keys, numbers, strings, booleans and lists.
"""
import json
import math
import re
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DUMP = HERE / "dump_data.lua"
HEAD = 'modules["game.data"] = function(require)\nreturn '


def module_span(bundle, name):
    """(start, end) of a module block inside the bundle text."""
    start = bundle.index('modules["%s"] = function(require)\n' % name)
    following = re.compile(r'^modules\["[^"]+"\] = function\(require\)\n', re.M)
    m = following.search(bundle, start + 1)
    end = m.start() if m else bundle.index("\nlocal function import(name)", start) + 1
    return start, end


def load(bundle_path):
    """game.data as Python data (through luajit and dump_data.lua)."""
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        subprocess.run(["luajit", str(DUMP), str(bundle_path), out.name], check=True)
        return json.load(open(out.name))


def lua_string(text):
    out = ['"']
    for ch in text.encode("utf-8"):
        c = chr(ch)
        if c == '"' or c == "\\":
            out.append("\\" + c)
        elif 32 <= ch < 127:
            out.append(c)
        else:
            out.append("\\%d" % ch if ch < 128 else chr(ch))
    s = "".join(out) + '"'
    return s.encode("latin1").decode("utf-8", "surrogateescape") if any(ord(x) > 127 for x in s) else s


def encode(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value == math.floor(value) and abs(value) < 2 ** 53:
            return "%d" % value if value != 0 or math.copysign(1, value) > 0 else "-0.0"
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, list):
        return "{" + ",".join(encode(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join('[%s]=%s' % (lua_string(k), encode(value[k])) for k in sorted(value)) + "}"
    if value is None:
        return "nil"
    raise TypeError(type(value))


def replace(bundle, data):
    """The bundle text with game.data rewritten from data."""
    start, end = module_span(bundle, "game.data")
    block = HEAD + encode(data) + "\nend\n"
    return bundle[:start] + block + bundle[end:]
