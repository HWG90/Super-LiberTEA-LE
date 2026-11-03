"""Grow the 26251122 game.dll / exe capture during play, for the HUD+ port.

Waits until Helldivers 2 runs with LLtM loaded, then every --every seconds dumps game.dll and
helldivers2.exe through LLtM (GooseGadgets capture_modules.py: ReadProcessMemory on the game's own
process, read-only; pages the protector has not decrypted yet come back zero-filled) and merges every
dump of this session with the build's existing merged images into the port's own images (the build's
canonical capture is left alone). After each round it logs page coverage and whether the sites the
port is waiting for are now readable. Stops when the game exits.

The LLtM bridge has one command slot: while a file named PAUSE exists in the session folder, no
capture starts.

usage: python3 -I live_capture_session.py [--every 240] [--once]
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = os.path.dirname(HERE)
RELAY = "/home/goose/Documents/ChatGPT/GooseGadgets/relay-tools"
CAPTURES = "/home/goose/Documents/ChatGPT/GooseGadgets/module-captures"
WS = "/home/goose/Projects/Linux HD2 Mods/builds/26251122"
MERGE = "/home/goose/.claude/skills/hd2-game-update/scripts/merge_captures.py"
SESSION = os.path.join(WS, "mods/hud-plus/live")
STATUS = "/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LinksLinkToMemory/status.txt"
MODULES = {"game": ("game-6ae0e5ff", "game-6ae0e5ff.merged.bin"), "exe": ("helldivers2-6ae0964a", "helldivers2-6ae0964a.merged.bin")}
PAGE = 4096


def log(text):
    line = time.strftime("%H:%M:%S ") + text
    print(line, flush=True)
    with open(os.path.join(SESSION, "session.log"), "a") as f:
        f.write(line + "\n")


def game_pid():
    out = subprocess.run(["pgrep", "-f", "helldivers2.exe --bundle-dir"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def ready(pid):
    try:
        text = open(STATUS).read()
        # after any batch the status reads "done batch N" instead of "loaded, waiting"
        idle = "loaded, waiting" in text or re.search(r"done batch \d+\s*$", text) is not None
        return idle and os.stat(STATUS).st_mtime >= os.stat("/proc/%d" % pid).st_mtime
    except OSError:
        return False


def capture(started):
    before = set(glob.glob(os.path.join(CAPTURES, "*")))
    run = subprocess.run([sys.executable, "-I", os.path.join(RELAY, "capture_modules.py"), "--only",
                          "game.dll,helldivers2.exe"], capture_output=True, text=True, timeout=900)
    folders = sorted(set(glob.glob(os.path.join(CAPTURES, "*"))) - before)
    tail = (run.stdout.strip().splitlines() or ["(no output)"])[-3:]
    log("capture exit %d: %s" % (run.returncode, " | ".join(tail)))
    with open(os.path.join(SESSION, "captures.txt"), "a") as f:
        for folder in folders:
            f.write(folder + "\n")
    return run.returncode == 0


def merge():
    folders = [l.strip() for l in open(os.path.join(SESSION, "captures.txt")) if l.strip()]
    for key, (prefix, merged) in MODULES.items():
        inputs = [os.path.join(WS, "capture", merged)]
        for folder in folders:
            inputs += sorted(glob.glob(os.path.join(folder, prefix + "-*.bin")))
        out = os.path.join(SESSION, merged)
        run = subprocess.run([sys.executable, "-I", MERGE, "--output", out] + inputs, capture_output=True, text=True)
        if run.returncode != 0:
            log("merge %s failed: %s" % (key, (run.stderr or run.stdout).strip().splitlines()[-1:]))
            continue
        meta = json.load(open(out + ".json"))
        log("merged %s: .text %s (%d inputs)" % (key, meta["coverage"].get(".text"), len(inputs)))


def targets():
    """Which waiting sites are now readable in the merged game.dll."""
    path = os.path.join(SESSION, MODULES["game"][1])
    if not os.path.exists(path):
        return
    data = open(path, "rb").read()
    zero = bytes(PAGE)
    sites = json.load(open(os.path.join(PORT, "data/maps/live-targets.json")))
    have = [n for n, at in sites.items() if data[int(at, 16) // PAGE * PAGE:(int(at, 16) // PAGE + 1) * PAGE] != zero]
    # the charge-stage site has no hint: look for its row reads (+0x18 float, compare, +0x1c/+0x20/+0x28)
    found = []
    for m in re.finditer(rb"\xf3[\x40-\x4f]?\x0f\x10[\x40-\x7f]\x18", data[:0x1f99000]):
        window = data[m.start():m.start() + 24]
        if b"\x0f\x2f" in window and (b"\x1c" in window[6:] and b"\x20" in window[6:] and b"\x28" in window[6:]):
            found.append(m.start())
    log("targets readable: %d/%d (%s); charge-stage candidates %d" % (len(have), len(sites), ", ".join(sorted(have)) or "-", len(found)))
    json.dump({"time": time.strftime("%H:%M:%S"), "readable": sorted(have), "charge_candidates": [hex(x) for x in found[:20]]},
              open(os.path.join(SESSION, "targets.json"), "w"), indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--every", type=int, default=240)
    ap.add_argument("--once", action="store_true")
    a = ap.parse_args()
    os.makedirs(SESSION, exist_ok=True)
    open(os.path.join(SESSION, "captures.txt"), "a").close()
    log("waiting for Helldivers 2 with LLtM")
    pid = None
    while True:
        pid = game_pid()
        if pid and ready(pid):
            break
        time.sleep(5)
    log("game %d ready; settling 60 s" % pid)
    time.sleep(60)
    started = time.time()
    while game_pid() == pid:
        if os.path.exists(os.path.join(SESSION, "PAUSE")):
            time.sleep(10)
            continue
        if capture(started):
            merge()
            targets()
        if a.once:
            break
        for _ in range(a.every // 5):
            if game_pid() != pid:
                break
            time.sleep(5)
    log("game exited; session over")


if __name__ == "__main__":
    main()
