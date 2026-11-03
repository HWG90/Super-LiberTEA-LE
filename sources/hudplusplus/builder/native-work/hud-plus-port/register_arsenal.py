"""Register the HUD+ 0.2.9 LuaJIT 26251122 package in HD2 Arsenal.

--library  adds (or refreshes) the library record now; Arsenal may stay open (library records survive
           its own writes).
--row      waits until every Arsenal process has closed and hd2a_data.json has sat unchanged for two
           seconds, then puts an enabled row into the profile (default "LuaJIT Proton") just above the
           "LOADER — KEEP LAST" separator. Arsenal keeps profile rows in memory and writes them back,
           so rows only stick when written while it is closed. Refuses if Arsenal comes back.
--check    shows the current state.
Every write backs up hd2a_data.json into repair-backups/ and replaces it atomically, keeping Arsenal's
format (indent 2, raw UTF-8, no trailing newline). Nothing else in the profile is touched.
"""
import argparse
import datetime
import json
import os
import shutil
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = Path("/home/goose/.config/hd2arsenal/hd2a_data.json")
BACKUPS = CONFIG.parent / "repair-backups"
RECEIPT = json.loads((HERE / "BUILD-RECEIPT-26251122.json").read_text())
GUID = RECEIPT["guid"]
PACKAGE = Path("/home/goose/.config/hd2arsenal/mods/HudPlusPlus-LuaJIT-26251122")
LABEL = "HudPlusPlus"
VERSION = "r9 · LuaJIT 26251122"
DESCRIPTION = ("HudPlusPlus for game build 26251122, for the LuaJIT Proton profile: weapon row and 3D weapon HUD, "
               "health and stamina, reticle, throw distance, trajectory preview, stratagem indicators and cooldowns, "
               "backpack, squad status, eagle and bombardment attack preview, map pins, call colour, kill pulse, "
               "corpse and reinforce markers, ground decals, and its own page in the game's Options menu.")
LOADER_SEPARATOR = "LOADER — KEEP LAST"


def log(msg):
    print(datetime.datetime.now().strftime("%H:%M:%S"), msg, flush=True)


def arsenal_running():
    """Only argv[0] counts: the AppImage or the hd2arsenal binary it mounts."""
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv0 = (proc / "cmdline").read_bytes().split(b"\0", 1)[0]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        name = os.path.basename(argv0).lower()
        if name == b"hd2arsenal" or name.startswith(b"hd2arsenal-"):
            return True
    return False


def load():
    raw = CONFIG.read_bytes()
    data = json.loads(raw)
    assert json.dumps(data, indent=2, ensure_ascii=False).encode() == raw, "unexpected hd2a_data.json format"
    return data, CONFIG.stat().st_mtime_ns


def write(data, mtime, tag, closed_only=False):
    if CONFIG.stat().st_mtime_ns != mtime:
        raise SystemExit("hd2a_data.json changed while preparing the write; nothing written")
    BACKUPS.mkdir(exist_ok=True)
    backup = BACKUPS / ("hd2a_data-before-hudplus-luajit-%s-%s.json" % (tag, datetime.datetime.now().strftime("%Y%m%d-%H%M%S")))
    shutil.copy2(CONFIG, backup)
    fd, temp = tempfile.mkstemp(dir=CONFIG.parent, prefix=".hd2a_data.", suffix=".tmp")
    with os.fdopen(fd, "wb") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False).encode())
    if closed_only and arsenal_running():
        os.unlink(temp)
        return None
    os.replace(temp, CONFIG)
    return backup


def record():
    return {
        "uuid": GUID, "path": str(PACKAGE), "label": LABEL, "description": DESCRIPTION,
        "iconPath": str(PACKAGE / "icon.png"), "tags": ["misc"], "patchFileNames": [],
        "nexusData": {"version": VERSION, "updateTimestamp": int(time.time())},
        "options": [], "contentHash": None,
        "addedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "previousVersions": [], "hasLua": True, "luaPaths": [str(PACKAGE / "56e46a6dc1df0a13.lua")],
        "unitRepairAttempted": False, "unitScanStatus": "pending",
    }


def profile(data, label):
    for pid, prof in data["modsList"].items():
        if prof.get("label") == label:
            return pid, prof
    raise SystemExit("no profile called %r" % label)


def library():
    data, mtime = load()
    old = next((r for r in data["modsLibrary"] if r["uuid"] == GUID), None)
    new = record()
    if old is not None:
        new["addedAt"] = old.get("addedAt", new["addedAt"])
        # only the timestamp may differ; a version bump alone is a change
        same_version = (old.get("nexusData") or {}).get("version") == new["nexusData"]["version"]
        if same_version and {k: v for k, v in old.items() if k != "nexusData"} == {k: v for k, v in new.items() if k != "nexusData"}:
            log("library record already current")
            return
        data["modsLibrary"][data["modsLibrary"].index(old)] = new
    else:
        data["modsLibrary"].append(new)
    backup = write(data, mtime, "library")
    log("library record %s; backup %s" % ("refreshed" if old else "added", backup))


def add_row(data, label):
    pid, prof = profile(data, label)
    rows = prof["mods"]
    if any(r.get("uuid") == GUID for r in rows):
        return None
    at = next((i for i, r in enumerate(rows) if r.get("type") == "separator" and r.get("label") == LOADER_SEPARATOR), len(rows))
    rows.insert(at, {"uuid": GUID, "new": False, "enabled": True, "deployed": False, "changed": False, "optionsConfig": []})
    return at


def row(label, timeout):
    data, _ = load()
    if not any(r["uuid"] == GUID for r in data["modsLibrary"]):
        raise SystemExit("library record missing; run --library first")
    if add_row(json.loads(json.dumps(data)), label) is None:
        log("row already in %r" % label)
        return 0
    deadline, quiet, last, told = time.monotonic() + timeout, None, None, False
    while time.monotonic() < deadline:
        if arsenal_running():
            if not told:
                log("waiting for every Arsenal process to close...")
                told = True
            quiet = None
            time.sleep(2)
            continue
        st = CONFIG.stat()
        sig = (st.st_mtime_ns, st.st_size)
        if sig != last:
            last, quiet = sig, time.monotonic()
        if time.monotonic() - quiet < 2:
            time.sleep(0.5)
            continue
        data, mtime = load()
        at = add_row(data, label)
        if at is None:
            log("row appeared meanwhile; nothing to do")
            return 0
        backup = write(data, mtime, "row", closed_only=True)
        if backup is None:
            log("Arsenal came back before the write; waiting again")
            told = False
            continue
        log("row added to %r at index %d, enabled; backup %s" % (label, at, backup))
        return 0
    log("gave up: Arsenal did not close in time")
    return 2


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--library", action="store_true")
    ap.add_argument("--row", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--profile", default="LuaJIT Proton")
    ap.add_argument("--timeout", type=float, default=6 * 3600)
    a = ap.parse_args()
    if a.check:
        data, _ = load()
        pid, prof = profile(data, a.profile)
        print("library record:", any(r["uuid"] == GUID for r in data["modsLibrary"]),
              "| row in %r:" % a.profile, any(r.get("uuid") == GUID for r in prof["mods"]),
              "| Arsenal running:", arsenal_running())
        return 0
    if a.library:
        library()
    if a.row:
        return row(a.profile, a.timeout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
