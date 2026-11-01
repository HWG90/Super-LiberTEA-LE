"""Stage the drop-in's fresh-install live check, and undo it afterwards. Game closed for both.

--stage    renames LLL/Helldivers2/Native and Service in the Proton prefix to <name>.before-dropin-<stamp>, so the
           next start has to create both folders and write every file itself (as on a PC that never had LLL).
           Writes DROPIN-STAGE.json with the old marker and game-root.txt.
--restore  moves every file the boot did not write back from the renamed folders (older runtimes, rollback copies,
           installed-steam-preview.json), puts the old marker back if it named another runtime, removes the emptied
           folders, and records what the boot wrote next to what was there before.
Files that differ (other than the marker) stay in the renamed folder and are listed. Deploying the release zip in
Arsenal stays the user's step. --home <dir> runs it on a scratch copy (no process check, receipt in that folder).
  python3 -I stage_dropin_check.py --stage | --restore [--home <dir>]
"""
import datetime, json, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path("/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2")
RECEIPT = HERE / "DROPIN-STAGE.json"


def closed():
    names = subprocess.run(["ps", "-eo", "comm="], capture_output=True, text=True, check=True).stdout.lower().split()
    running = [n for n in names if n.startswith(("helldivers2", "lll_steam"))]
    assert not running, "game or LLL helper running: %s" % running


def text(path):
    return path.read_text() if path.exists() else None


def stage():
    closed()
    assert not RECEIPT.exists() or json.loads(RECEIPT.read_text()).get("state") == "restored", "a check is already staged"
    stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
    moved = {}
    for name in ("Native", "Service"):
        target = HOME / ("%s.before-dropin-%s" % (name, stamp))
        os.rename(HOME / name, target)
        moved[name] = str(target)
    receipt = {"state": "staged", "staged_at": stamp, "moved": moved,
               "marker_before": text(Path(moved["Native"]) / "luajit-boot.enable"),
               "game_root_before": text(Path(moved["Service"]) / "game-root.txt"),
               "files_log_before": text(HOME / "Logs" / "LLL-files.log")}
    RECEIPT.write_text(json.dumps(receipt, indent=1) + "\n")
    print(json.dumps(receipt, indent=1))


def restore():
    closed()
    receipt = json.loads(RECEIPT.read_text())
    assert receipt["state"] == "staged"
    written = {name: sorted(p.name for p in (HOME / name).iterdir()) if (HOME / name).exists() else None for name in ("Native", "Service")}
    receipt["after_boot"] = {"files": written, "marker": text(HOME / "Native" / "luajit-boot.enable"),
                             "game_root": text(HOME / "Service" / "game-root.txt"), "files_log": text(HOME / "Logs" / "LLL-files.log")}
    returned, receipt["left_in_renamed_folders"] = [], {}
    for name, old in receipt["moved"].items():
        old, new = Path(old), HOME / name
        if not new.exists():  # the boot never ran: put the folder back as it was
            os.rename(old, new)
            returned.append(name + "/ (whole folder)")
            continue
        for item in sorted(old.iterdir()):
            dest = new / item.name
            if not dest.exists():
                os.rename(item, dest)
                returned.append("%s/%s" % (name, item.name))
            elif item.read_bytes() == dest.read_bytes():
                item.unlink()  # the boot wrote the same bytes
            elif item.name == "luajit-boot.enable":
                os.replace(item, dest)  # the runtime that was staged before the check
                returned.append("%s/%s (old marker)" % (name, item.name))
        leftovers = sorted(p.name for p in old.iterdir()) if old.exists() else []
        if not leftovers and old.exists():
            old.rmdir()
        receipt["left_in_renamed_folders"][name] = leftovers
    receipt["returned"] = returned
    receipt["state"] = "restored"
    RECEIPT.write_text(json.dumps(receipt, indent=1) + "\n")
    print(json.dumps(receipt, indent=1))


if __name__ == "__main__":
    if "--home" in sys.argv:
        HOME = Path(sys.argv[sys.argv.index("--home") + 1])
        RECEIPT = HOME / "DROPIN-STAGE.json"
        closed = lambda: None  # noqa: E731
    {"--stage": stage, "--restore": restore}[sys.argv[1]]()
