"""Build HudPlusPlus (from HD2 HUD+ 0.2.9) for game build 26251122 under LLL's LuaJIT boot.

The original package (Arsenal folder from Nexus 15298, file 69465) is the only source. Its Lua bundle is
kept as is except for:
  - game.data: every value re-resolved for 26251122 (patterns re-derived where the old ones no longer
    match, plus hand-found values with evidence), the build pin moved to 26251122's executable and
    game.dll, and the names that could not be resolved listed in `unresolved`;
  - native.access: on the pinned build the unresolved names are reported as missing, so HUD+'s own
    feature graph switches those features off; on any other build it refuses instead of scanning
    (a scan reads code pages the protection runtime has not decrypted yet);
  - the bundle's tail: LLL loads the bundle as an archive addon and starts it on enable, the way HUD+'s
    own boot script (`f476df93691895fa`, replaced by LLL's boot) did with entry.start(_G).
The patch archive keeps every texture and material byte for byte and drops the boot script.

usage: python3 -I build_port.py [--out DIR] [--allow-incomplete] [--dry-run]
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE / "tools"
DATA = HERE / "data"
sys.path.insert(0, str(TOOLS))
import luadata  # noqa: E402

BUILD = "26251122"
SOURCE = Path("/home/goose/.config/hd2arsenal/mods/HD2 HUD Plus 0.2.9 15298 0.2.9 2026-10-19T15-18Z x2kcgwCqg_AR637103")
SOURCE_SHA = {
    "56e46a6dc1df0a13.lua": "31af81f2942cb6c0a1aae6d4ce83b6d9e86644392082d25037c829fa63c3b34e",
    "f476df93691895fa.lua": "4321f72f2e5a817eda3059a4e6789c99289d05a6443cab8a440f736b5ae7effe",
}
WS = Path("/home/goose/Projects/Linux HD2 Mods/builds") / BUILD
# the build's merged capture plus the HUD+ session's live dumps (tools/live_capture_session.py)
LIVE = WS / "mods/hud-plus/live"
EXE_IMAGE = LIVE / "helldivers2-6ae0964a.merged.bin"
GAME_IMAGE = LIVE / "game-6ae0e5ff.merged.bin"
OUT = Path("/home/goose/.config/hd2arsenal/mods/HudPlusPlus-LuaJIT-" + BUILD)
ARCHIVE = "9ba626afa44a3aa3.patch_0"
BUNDLE_KEY = 0x56E46A6DC1DF0A13  # mods/hd2_hud/hd2_hud_plus
BOOT_KEY = 0xF476DF93691895FA  # boot
NAME = "mods/hd2_hud/hd2_hud_plus"
GUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, "goose.hd2_hud_plus.luajit." + BUILD))
# Sources disagree and no check settles them; their modules stay off until verified in game.
DISTRUST = {n: "pattern, re-derived and duplicate sites give different handlers (game.reload)" for n in (
    "action_script_insert_rva", "action_script_room_rva", "action_script_switch_kind_rva",
    "action_script_all_full_rva", "action_script_can_reload_rva", "action_script_cock_rva",
    "action_script_stage_bit_rva", "action_script_set_stage_bit_rva", "action_script_mag_full_rva",
    "action_script_chamber_rva", "action_script_count_rva", "action_script_empty_rva",
    "action_script_reloadable_rva")}
CORE = ["game.panel", "game.ui", "game.weapon", "game.weapon_options", "game.equipment", "game.world_inputs"]
# Hand-found call targets on pages no capture has, each proven to be a function entry.
UNCAPTURED_CALLS = {
    "line_object_add_circle": "exe unwind records (.rdata 0x17fb0a0/0x17fb0b0, parent 0x17fb054) give a function "
                              "0x4f1200-0x4f148a with a 0x53-byte prologue saving xmm6-15, HUD+'s recorded head; its "
                              "page 0x4f1000 stays locked in play (checked 2026-11-03 after a mission)",
}

# Call targets whose recorded head no longer matches byte for byte, each checked by hand.
HEAD_EXPLAINED = {
    "assisted_reload_find": "same hash-table lookup; the modulo by a constant is compiled differently",
    "can_fire": "two independent HUD+ patterns (can_fire_head, weapon_can_fire_ask) agree; prologue recompiled",
    "gui_move": "body identical; the protector refilled the padding after its tail jump",
    "line_object_create": "body identical; padding after the tail jump refilled",
    "minigame_settings": "same instructions; only operand values differ",
    "projectile_weapon_default_of": "same instructions; the record stride immediate changed",
    "ui_context_push": "body identical; padding after ret refilled",
    "unit_alive": "body identical; padding after ret refilled",
    "weapon_data_find": "same template lookup (component map: table 0xf146a0); 746 slots, record 0x4d8",
    "widget_shown_set": "same instructions; only operand values differ",
    "camera_fov": "6-byte accessor movss xmm0,[rcx+0x34]; ret matches; refilled padding follows (found by the padding-masked pattern that also covers camera_fov_set)",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(cmd):
    subprocess.run(cmd, check=True)


def read_tsv(path):
    out = {}
    for line in open(path):
        name, state, old, new = line.rstrip("\n").split("\t")
        out[name] = (state, new)
    return out


def closure(requires, module, seen):
    if module in seen:
        return
    seen.add(module)
    for other in requires.get(module) or []:
        closure(requires, other, seen)


def resolve(original_bundle, work):
    """Final 26251122 values: name -> (value, evidence), and unresolved name -> reason."""
    data = json.load(open(DATA / "game-data-029.json"))
    results = {}
    for path in sorted((DATA / "rederive").glob("*.json"), key=lambda p: p.stat().st_mtime):
        results.update({k: v for k, v in json.load(open(path)).items() if v.get("status") == "ok"})
    patterned = work / "bundle-patterns.lua"
    run([sys.executable, "-I", str(TOOLS / "apply_rederive.py"), str(original_bundle), str(patterned)]
        + [str(p) for p in sorted((DATA / "rederive").glob("*.json"), key=lambda p: p.stat().st_mtime)])
    tsv, exact = work / "resolved.tsv", work / "resolved.json"
    run(["luajit", str(TOOLS / "resolve_offline.lua"), str(patterned), str(EXE_IMAGE), str(GAME_IMAGE), str(tsv),
         str(exact)])
    resolved, values = read_tsv(tsv), json.load(open(exact))
    final, unresolved = {}, {}
    for name, (state, text) in resolved.items():
        if not state.startswith("missing"):
            final[name] = (values[name], "pattern:" + state)
        else:
            unresolved[name] = state.split(":", 1)[1]
    copies_agree(work, patterned, final, unresolved)
    # values found without a unique pattern
    for name, res in results.items():
        if res.get("values_only"):
            for key, v in res["values"].items():
                if key in unresolved and v["new"] is not None:
                    final[key] = (v["new"], "values:" + res.get("evidence", "?"))
                    unresolved.pop(key)
    for name, row in json.load(open(DATA / "maps/fills-globals.json")).items():
        if name in unresolved:
            final[name] = (row["value"], "known-global:" + ",".join(row["sources"][:2]))
            unresolved.pop(name)
    for name, row in json.load(open(DATA / "manual-26251122.json")).items():
        if name == "_" or (name not in unresolved and not row.get("override")):
            continue
        # hex text for numbers; strings (hashes as text) and constant lists (e.g. eagle_degrees) as given
        value = row["value"] if row.get("string") or not isinstance(row["value"], str) else int(row["value"], 16)
        final[name] = (value, "manual:" + row["evidence"])
        unresolved.pop(name, None)
    component_gate(data, final, unresolved)
    for name in list(final):
        # the pattern is distrusted, not the name: a hand-proven value (manual, with its evidence) stands
        if name in DISTRUST and not final[name][1].startswith("manual:"):
            final.pop(name)
            unresolved[name] = "distrusted:" + DISTRUST[name]
    # gate every call target: head check, explained mismatch, or out
    calls = check_calls(data, final, work)
    for name, (result, first_diff) in calls.items():
        at = data["calls"][name]["at"]
        if at not in final:
            continue
        evidence = final[at][1]
        if result in ("head-match", "head-match-before-padding") or (result != "page-not-captured" and name in HEAD_EXPLAINED):
            continue
        if evidence.startswith("component-map"):
            continue  # the accessor scan found the template prologue loading this type's table
        if evidence.startswith("pattern:") and first_diff is not None and first_diff >= 24:
            continue  # unique pattern; the head agrees for 24+ bytes and differs only further in
        if result == "page-not-captured" and (final[at][1].startswith("pattern:") or at in UNCAPTURED_CALLS):
            # found by HUD+'s own unique pattern, or listed below with proof that it is a function entry; its page
            # was not in the capture. HUD+ checks no heads on a pinned build, so the first call runs the locked page
            # at that entry, which the game unlocks as it does for its own first call.
            continue
        unresolved[at] = "call-head:" + result
        final.pop(at)
    # two different old functions landing on one new address: at least one is wrong
    seen = {}
    for name, call in data["calls"].items():
        at = call["at"]
        if at in final and isinstance(final[at][0], int):
            seen.setdefault(final[at][0], set()).add(at)
    for value, names in seen.items():
        olds = {data["numbers"][n] for n in names}
        if len(names) > 1 and len(olds) > 1:
            for n in names:
                unresolved[n] = "collision:" + hex(value)
                final.pop(n, None)
    # the same for globals: roots_hud_manager_rva once landed on hud_scene_manager's global, and HUD+ never drew
    globals_seen = {}
    for row in data["patterns"].values():
        for key, take in row["take"].items():
            if isinstance(take, dict) and take.get("kind") == "rip" and key in final and isinstance(final[key][0], int):
                globals_seen.setdefault((row["module"], final[key][0]), set()).add(key)
    for (module, value), names in globals_seen.items():
        olds = {data["numbers"][n] for n in names}
        if len(names) > 1 and len(olds) > 1:
            for n in names:
                unresolved[n] = "collision:" + hex(value)
                final.pop(n, None)
    # a call target whose shift from 0.2.9 falls outside the shifts of its nearest neighbours below and above in its
    # module: a short generic head matched the wrong wrapper (r6's unit_alive: +0x785e10 between Unit functions at
    # -0xa200; the HUD+ world HUD faulted). Shifts drift across an image (exe: +0x10790 ... +0x87150), hence a range.
    for name, why in call_outliers(data, final).items():
        unresolved[name] = why
        final.pop(name)
    return data, final, unresolved, calls


def call_outliers(data, final, limit=0x10000):
    rows = {}
    for call in data["calls"].values():
        at = call["at"]
        if at in final and isinstance(final[at][0], int) and isinstance(data["numbers"].get(at), int):
            rows[at] = (call["module"], data["numbers"][at], final[at][0])
    out = {}
    for name, (module, old, new) in rows.items():
        if final[name][1].startswith("manual:"):
            continue
        others = [(o, n - o) for k, (m, o, n) in rows.items() if m == module and k != name]
        below = max((r for r in others if r[0] < old), default=None)
        above = min((r for r in others if r[0] > old), default=None)
        shifts = [r[1] for r in (below, above) if r is not None]
        if shifts and not min(shifts) - limit <= new - old <= max(shifts) + limit:
            out[name] = "outlier:%#x vs neighbours %s" % (new - old, ", ".join("%#x" % s for s in shifts))
    return out


def copies_agree(work, patterned, final, unresolved):
    """A pattern that matches more than once is still good when every match yields the same values."""
    import rederive as rd
    data = luadata.load(patterned)
    images = {"game": rd.Image(str(GAME_IMAGE)), "exe": rd.Image(str(EXE_IMAGE))}
    for pname, row in data["patterns"].items():
        keys = [k for k in row["take"] if unresolved.get(k) == "not-unique"]
        if not keys or "in" in row:
            continue
        image = images[row["module"]]
        raw, mask = bytes.fromhex(row["hex"]), bytes.fromhex(row["mask"])
        hits = rd.masked_hits(image, raw, mask, limit=8)
        if len(hits) < 2 or len(hits) >= 8:
            continue
        values = [{k: rd.take(image.data[h:h + len(raw)], h, row["take"][k]) for k in keys} for h in hits]
        if all(v == values[0] for v in values) and all(isinstance(x, (int, float)) for x in values[0].values()):
            for k, v in values[0].items():
                final[k] = (v, "pattern:copies-agree:%d" % len(hits))
                unresolved.pop(k)


def component_gate(data, final, unresolved):
    """Component accessors are one template per type: pin each to its type's registry table."""
    import component_map
    tables, accessor_old, accessor_new = component_map.build(DATA / "maps/components-old.json",
                                                             DATA / "maps/components-new.json")
    for name, old in data["numbers"].items():
        if not isinstance(old, int):
            continue
        if old in accessor_old:
            mapped = tables.get(accessor_old[old])
            if mapped is None:
                continue  # small table the alignment could not pair; the head check decides
            want = min(accessor_new[mapped[0]])
            if final.get(name, (None,))[0] != want:
                final[name] = (want, "component-map:%s->%s %s" % (hex(accessor_old[old]), hex(mapped[0]), mapped[1]))
                unresolved.pop(name, None)
        elif name.endswith("_table") and old in tables:
            want = tables[old][0]
            if final.get(name, (None,))[0] != want:
                final[name] = (want, "component-map:%s->%s %s" % (hex(old), hex(want), tables[old][1]))
                unresolved.pop(name, None)


def check_calls(data, final, work):
    tsv = work / "final.tsv"
    with open(tsv, "w") as f:
        for name, (value, _) in final.items():
            text = hex(value) if isinstance(value, int) else str(value)
            f.write("%s\tfinal\t-\t%s\n" % (name, text))
    out = work / "calls.json"
    subprocess.run([sys.executable, "-I", str(TOOLS / "check_calls.py"), str(DATA / "game-data-029.json"), str(tsv),
                    str(EXE_IMAGE), str(GAME_IMAGE), "--json", str(out)], check=True, stdout=subprocess.DEVNULL)
    return {k: (v["result"], v.get("first_diff")) for k, v in json.load(open(out)).items()}


ACCESS_OLD = '''okay, report = channel:pinned(pin)
if not okay then
why = "pin"
'''
ACCESS_NEW = '''okay, report = channel:pinned(pin)
-- 26251122 port: values that could not be resolved for this build switch their features off
if okay and baked.unresolved ~= nil and next(baked.unresolved) ~= nil then report.missing = baked.unresolved end
-- and no scan on any other build: it would read code pages the protection runtime has not decrypted
if not okay and baked.refuse_unpinned then
why = "unsupported-build"
return false, why, report
end
if not okay then
why = "pin"
'''
CHANNEL_CDEF_OLD = r'''"int hd2hud_protect(uintptr_t address, size_t size, uint32_t protect, void *previous)"
.. " __asm__(\"VirtualProtect\");",
'''
CHANNEL_CDEF_NEW = CHANNEL_CDEF_OLD + r'''"typedef struct hd2hud_region { uint64_t base, allocation_base; uint32_t allocation_protect, partition;"
.. " uint64_t size; uint32_t state, protect, type, padding; } hd2hud_region;",
"size_t hd2hud_query(uintptr_t address, hd2hud_region *region, size_t size) __asm__(\"VirtualQuery\");",
'''
CHANNEL_TEXT_OLD = '''function Channel:text(address, size)
if size <= 0 then return nil end
return self.ffi.string(self.ffi.cast("const uint8_t *", address), size)
end
'''
CHANNEL_TEXT_NEW = '''-- 26251122 port: a game.dll code page stays no-access until the game first runs it, and a direct read of one
-- crashes the game (2026-11-03, a hot join: the reinforce walker read 16 bytes at game+0xf74ff1, one byte into a
-- no-access page). Every page a read touches must be committed and readable; otherwise the answer is nil.
local MEM_COMMIT = 0x1000
local function readable(self, address, size)
local region = self.region
if region == nil then
region = self.ffi.new("hd2hud_region[1]")
self.region, self.region_size = region, self.ffi.sizeof("hd2hud_region")
end
local at, stop = address, address + size
while at < stop do
if self.kernel.hd2hud_query(at, region, self.region_size) == 0 then return false end
local r = region[0]
local protect = tonumber(r.protect)
-- no-access 0x01, execute-only 0x10 and guard 0x100 cannot be read
if tonumber(r.state) ~= MEM_COMMIT or protect % 256 == 0x01 or protect % 256 == 0x10
or math.floor(protect / 256) % 2 == 1 then return false end
local after = tonumber(r.base) + tonumber(r.size)
if after <= at then return false end
at = after
end
return true
end
function Channel:text(address, size)
if size <= 0 then return nil end
if not readable(self, address, size) then return nil end
return self.ffi.string(self.ffi.cast("const uint8_t *", address), size)
end
'''
# A module HUD+ leaves on that require()s a module its data lists as off: HUD+'s own off rule reads the data's
# requires table, so the off module would still run inside the on one. Each known case has a rewrite; any other
# refuses the build. (r6: features.world_hud runs features.weapon_3d, whose magazine values are unresolved, and
# stopped on a nil.)
WEAPON3D_WANTED_OLD = '''function Feature:wanted(values)
return values["hud.weapon3d.ammo"] == 1 or values["hud.weapon3d.reserve"] == 1
or values["hud.weapon3d.throwables"] == 1 or values["hud.weapon3d.stims"] == 1
or values["hud.weapon3d.functions"] == 1 or values["hud.weapon3d.fire_mode"] == 1
or values["hud.weapon3d.zeroing"] == 1 or values["hud.weapon3d.arc"] == 1
end
'''
WEAPON3D_WANTED_NEW = '''function Feature:wanted(values)
-- 26251122 port: features.weapon_3d is off (its values are unresolved), but features.world_hud builds it without
-- HUD+ listing the dependency; never wanted keeps every world HUD path away from it
return false
end
'''
HIDDEN_REWRITES = {("features.world_hud", "features.weapon_3d"): (
    (WEAPON3D_WANTED_OLD, WEAPON3D_WANTED_NEW, "weapon_3d wanted"),)}


def hidden_requires(bundle, data, blocked):
    """(module, required) pairs where an on module require()s an off one that the data does not list."""
    parts = re.split(r'\nmodules\["([^"]+)"\] = function\(require\)\n', "\n" + bundle)
    out = []
    for module, source in zip(parts[1::2], parts[2::2]):
        if module in blocked:
            continue
        listed = set(data["requires"].get(module) or [])
        for needed in sorted(set(re.findall(r'require\("([^"]+)"\)', source))):
            if needed in blocked and needed not in listed:
                out.append((module, needed))
    return out


TAIL_OLD = "return import('entry')"
TAIL_NEW = '''-- LLL loads this archive entry under its LuaJIT boot and starts HD2 HUD+ here, the way HUD+'s own
-- boot script (replaced by LLL's boot) did: entry.start(_G) hooks the game's global update.
local entry = import('entry')
local runtime
return {
live_lua_api = 1,
on_enable = function()
if runtime == nil then runtime = entry.start(_G) end
return true
end,
on_disable = function()
if runtime ~= nil then runtime:stop("disabled") end
runtime = nil
return true
end,
}'''
HEADER = "-- HD2-Addon: " + NAME + "\n"


def bake(bundle, data, final, unresolved, pin, rewrites=()):
    out = dict(data)
    out["numbers"] = {k: v for k, (v, _) in sorted(final.items()) if k in data["numbers"]}
    out["unresolved"] = dict(sorted(unresolved.items()))
    out["pin"] = pin
    out["refuse_unpinned"] = True
    patterns = dict(data["patterns"])
    for path in sorted((DATA / "rederive").glob("*.json"), key=lambda p: p.stat().st_mtime):
        for name, res in json.load(open(path)).items():
            if res.get("status") == "ok" and not res.get("values_only"):
                patterns[name] = res["row"]
    out["patterns"] = patterns
    out["digest"] = sha(json.dumps(out["numbers"], sort_keys=True).encode())
    text = luadata.replace(bundle, out)
    assert text.count(ACCESS_OLD) == 1, "native.access anchor"
    text = text.replace(ACCESS_OLD, ACCESS_NEW)
    for old, new, anchor in ((CHANNEL_CDEF_OLD, CHANNEL_CDEF_NEW, "native.channel cdef"),
                             (CHANNEL_TEXT_OLD, CHANNEL_TEXT_NEW, "native.channel text")) + tuple(rewrites):
        assert text.count(old) == 1, anchor + " anchor"
        text = text.replace(old, new)
    assert text.rstrip().endswith(TAIL_OLD), "bundle tail"
    text = text.rstrip()[: -len(TAIL_OLD)] + TAIL_NEW + "\n"
    return HEADER + text


def rewrite_archive(original, bundle_bytes):
    """The patch archive with the bundle replaced and the boot script left out."""
    magic, types, count = struct.unpack_from("<III", original)
    assert magic == 0xF0000011
    header = bytearray(original[:72])
    type_rows = [bytearray(original[72 + i * 32:72 + (i + 1) * 32]) for i in range(types)]
    entries = [list(struct.unpack_from("<7Q6I", original, 72 + types * 32 + i * 80)) for i in range(count)]
    payloads = {}
    for e in entries:
        payloads[e[0]] = original[e[2]:e[2] + e[7]]
    entries = [e for e in entries if e[0] != BOOT_KEY]
    lua_type = next(e[1] for e in entries if e[0] == BUNDLE_KEY)
    for row in type_rows:
        t = struct.unpack_from("<IIQIIII", row)
        if t[2] == lua_type:
            struct.pack_into("<I", row, 16, t[3] - 1)
    payloads[BUNDLE_KEY] = struct.pack("<II", len(bundle_bytes), 2) + bundle_bytes
    struct.pack_into("<I", header, 8, len(entries))
    offset = 72 + types * 32 + len(entries) * 80
    body = bytearray()
    for index, e in enumerate(entries):
        data = payloads[e[0]]
        e[2], e[7], e[12] = offset + len(body), len(data), index + 1
        body += data
    out = bytes(header) + b"".join(bytes(r) for r in type_rows)
    out += b"".join(struct.pack("<7Q6I", *e) for e in entries)
    return out + bytes(body)


def read_entry(archive, key):
    magic, types, count = struct.unpack_from("<III", archive)
    for i in range(count):
        e = struct.unpack_from("<7Q6I", archive, 72 + types * 32 + i * 80)
        if e[0] == key:
            return archive[e[2]:e[2] + e[7]]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--allow-incomplete", action="store_true", help="build even if a core module has gaps")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    for name, digest in SOURCE_SHA.items():
        assert sha((SOURCE / name).read_bytes()) == digest, "source changed: " + name
    build = json.load(open(WS / "BUILD.json"))
    pin = {"exe": build["binaries"]["bin/helldivers2.exe"]["sha256"],
           "game": build["binaries"]["data/game/game.dll"]["sha256"]}
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        original_bundle = SOURCE / "56e46a6dc1df0a13.lua"
        data, final, unresolved, calls = resolve(original_bundle, work)
        core = set()
        for module in CORE:
            closure(data["requires"], module, core)
        core_gaps = sorted({n for m in core for n in data["uses"].get(m, []) if n in unresolved})
        state = {}

        def off(module):  # HUD+'s own rule (product.lua Product.blocked): own uses, then requires
            if module not in state:
                state[module] = False
                state[module] = any(n in unresolved for n in data["uses"].get(module) or []) or any(
                    off(other) for other in data["requires"].get(module) or [])
            return state[module]

        blocked = sorted(m for m in data["uses"] if off(m))
        manual = json.load(open(DATA / "manual-26251122.json"))
        inferred = sorted(k for k, v in manual.items() if isinstance(v, dict) and v.get("inferred") and k in final)
        report = {
            "build": BUILD, "pin": pin, "resolved": len(final), "unresolved": len(unresolved),
            "inferred_verify_in_game": inferred,
            "core_gaps": core_gaps, "modules_off": blocked,
            "unresolved_names": dict(sorted(unresolved.items())),
            "evidence": {k: e for k, (_, e) in sorted(final.items())},
        }
        json.dump(report, open(HERE / ("REPORT-" + BUILD + ".json"), "w"), indent=1)
        print("resolved %d, unresolved %d, core gaps %d, modules off %d"
              % (len(final), len(unresolved), len(core_gaps), len(blocked)))
        if core_gaps:
            print("core gaps:", ", ".join(core_gaps))
            if not a.allow_incomplete:
                print("not building: HUD+ refuses to start while a core module has gaps")
                return 1
        bundle = open(original_bundle, encoding="utf-8", errors="surrogateescape").read()
        hidden = hidden_requires(bundle, data, set(blocked))
        unknown = [pair for pair in hidden if pair not in HIDDEN_REWRITES]
        if unknown:
            print("not building: on modules run off modules HUD+ does not list:",
                  ", ".join("%s -> %s" % pair for pair in unknown))
            return 1
        if hidden:
            print("kept off inside on modules:", ", ".join("%s -> %s" % pair for pair in hidden))
        text = bake(bundle, data, final, unresolved, pin, [r for pair in hidden for r in HIDDEN_REWRITES[pair]])
        bundle_bytes = text.encode("utf-8", errors="surrogateescape")
        check = work / "bundle.lua"
        check.write_bytes(bundle_bytes)
        run(["luajit", str(TOOLS / "compile_check.lua"), str(check), NAME])
        original_archive = (SOURCE / ARCHIVE).read_bytes()
        archive = rewrite_archive(original_archive, bundle_bytes)
        assert read_entry(archive, BOOT_KEY) is None
        assert read_entry(archive, BUNDLE_KEY)[8:] == bundle_bytes
        for key in [struct.unpack_from("<Q", original_archive, 72 + 4 * 32 + i * 80)[0] for i in range(38)]:
            if key not in (BOOT_KEY, BUNDLE_KEY):
                assert read_entry(archive, key) == read_entry(original_archive, key), hex(key)
        if a.dry_run:
            print("dry run: package not written")
            return 0
        out = Path(a.out)
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        (out / ARCHIVE).write_bytes(archive)
        for suffix in (".gpu_resources", ".stream"):
            shutil.copy2(SOURCE / (ARCHIVE + suffix), out / (ARCHIVE + suffix))
        (out / "56e46a6dc1df0a13.lua").write_bytes(bundle_bytes)
        shutil.copy2(SOURCE / "icon.png", out / "icon.png")
        manifest = json.load(open(SOURCE / "manifest.json"))
        manifest.update(Guid=GUID, Name="HudPlusPlus")
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
        receipt = {"build": BUILD, "guid": GUID, "pin": pin, "source": str(SOURCE),
                   "bundle_sha256": sha(bundle_bytes), "archive_sha256": sha(archive),
                   "resolved": len(final), "unresolved": len(unresolved), "core_gaps": core_gaps}
        (HERE / ("BUILD-RECEIPT-" + BUILD + ".json")).write_text(json.dumps(receipt, indent=1))
        print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
