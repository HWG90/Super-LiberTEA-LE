# Nova Weapon FOV (26251122)

The LAS-44 Nova's scope only looked right at its highest zoom. At 2.5x and 1x the gun sat too far
from the camera, so the scope and weapon looked smaller at each lower step. The fix gives every
zoom the 3.5x look while keeping each zoom's own magnification.

## Cause

When you aim, the game places the weapon at distance `D` in front of the camera
(`game+0x110AC80`, written to the camera request `+0x90`):

    D = N + G / (tan(F/Z/2) * C),   N = (1-u)*row[+148] + u*row[+14C],   u = (F-45)/45

The terms come from the spawned weapon's own row in the weapon manager `[game+0x2CE1EA0]`
(rows `+0xB0`, stride `0x4D8`). The Nova's optic sets zoom `Z` 3.5/2.5/1 with the same `C` 0.6
at every zoom, and its offset `N` is 0.1 at FOV 90. That combination is only right at 3.5x.

## Fix

At FOV 90, settled sweeps of `D` at each zoom (reached by stepping down, screenshot 2.4 s after
the view settled) put the scope ring at its 3.5x size (~434 px at 4K) for these distances:

| Zoom | D before | D after |
|---|---|---|
| 3.5x | 0.3477 | 0.3477 |
| 2.5x | 0.2740 | 0.217 |
| 1x | 0.1565 | -0.018 |

Those distances come from these row terms, written in one 20-byte write at `+13C..+14F`:

- C 0.33194 / 0.32928 / 0.41361
- N -0.1 at both FOV ends

Bytes: `edf3a93ec897a83ea8c4d33ecdccccbdcdccccbd`, replacing
`9a99193f9a99193f9a99193f00000000cdcccc3d`. The user confirmed the look live on 2026-11-07.

## The mod

`stage/goose_nova_weapon_fov` is an LLL folder mod:

- It checks the `game.dll` stamp `6AE0E5FF` and stays off on any other build.
- Twice a second it writes the patch to every Nova row (resource key `73d84eaae8c75342`, zooms
  3.5/2.5/1) that holds exactly the vanilla terms. Rows holding anything else are left alone.
- Disabling the mod writes the vanilla terms back over rows that still hold the patch.
- Writes go only to private read-write heap, never to a module image, and each is read back.

Limits:

- The values were measured at FOV setting 90. At other FOV settings the game still applies them,
  but they were not checked there.
- In first-person hip with 1x selected, the gun sits closer to the camera than before.

## Files

- `tests/harness.lua`: offline checks against a fake weapon manager (`cd tests && luajit harness.lua`).
- `install.sh`: installs the mod. It refuses while the game runs, runs the harness first, backs up
  any existing copy and writes a receipt.
- `live/`: LLtM probes. `nova_apply2.lua` / `nova_restore.lua` are the live test and its undo.
  `nova_sweep2.lua` is the calibration sweep. `mod_dryrun.lua` runs the mod's row finder
  read-only.
