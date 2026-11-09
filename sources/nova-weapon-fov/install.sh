#!/usr/bin/env bash
# Install the LLL folder mod goose_nova_weapon_fov (Nova Weapon FOV, game build 26251122).
# An existing copy is moved to LLL Port-Candidate-Backups/ first; the receipt lists what moved where.
# Refuses while the game runs unless given --allow-running; the copy is then made beside Mods and
# renamed into it in one step, so LLL's hot reload never sees a half-copied folder.
# Rollback: delete Mods/goose_nova_weapon_fov (and copy any backup back).
set -euo pipefail
if [ "${1:-}" != "--allow-running" ] && ps -eo comm= | grep -qi '^helldivers2'; then
    echo "game is running; close it first (or pass --allow-running)" >&2; exit 1
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
STAGE="$HERE/stage/goose_nova_weapon_fov"
L=/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2
TS=$(date -u +%Y%m%dT%H%M%SZ); B="$L/Port-Candidate-Backups"
RECEIPT="$HERE/INSTALL-RECEIPT-$TS.txt"
log() { echo "$*" | tee -a "$RECEIPT"; }

[ -f "$STAGE/manifest.json" ] || { echo "missing stage $STAGE" >&2; exit 1; }
(cd "$HERE/tests" && luajit harness.lua >/dev/null) || { echo "offline harness failed" >&2; exit 1; }
if [ -e "$L/Mods/goose_nova_weapon_fov" ]; then
    mkdir -p "$B"
    mv "$L/Mods/goose_nova_weapon_fov" "$B/goose_nova_weapon_fov-$TS"
    log "goose_nova_weapon_fov: previous copy moved to $B/goose_nova_weapon_fov-$TS"
fi
INCOMING="$L/.goose_nova_weapon_fov-incoming-$TS"
cp -a "$STAGE" "$INCOMING"
mv "$INCOMING" "$L/Mods/goose_nova_weapon_fov"
log "goose_nova_weapon_fov: installed from $STAGE"
log "done $TS"
