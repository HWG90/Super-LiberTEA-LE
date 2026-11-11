# Goose Nova Weapon FOV (LLL folder `goose_nova_weapon_fov`): 26251122 → 26568081

- **Source:** none of its own. The deployed folder equals the stage committed in this repository on branch
  `indev/nova-weapon-fov-zoom-92372e` (cefd305, `builds/26251122/mods/nova-weapon-fov`, session worktree
  `transmog-armor-equip-bug-c59577`; not merged into the main checkout). The port starts from the deployed folder.
- **Output:** `../../mods/nova-weapon-fov/`: `stage/goose_nova_weapon_fov` (5 files, 0.1.0-26568081),
  `tests/harness.lua` (unchanged copy), `install.sh`. Nothing is committed: this repository's commits are the
  coordinator's.
- **No native code.** The module base comes from `GetModuleHandleA` at run time.

## Build-specific values

| Value | Old → new | Evidence |
|---|---|---|
| game stamp `M.STAMP` | 0x6AE0E5FF → 0x6AF322C1 | BUILD.json; the new image header |
| weapon manager global `M.MANAGER` | 0x2CE1EA0 unchanged | `game.map.json` high: 63 reference votes, no dissent |
| aim-distance code (comment only) | 0x110AC80 → 0x110ADE0 | `game.map.json` high |
| row terms +0x13C…+0x14C, request +0x90 | unchanged | `layout-check.json`: the 99 instructions from the aim-distance address to the ret are the same |
| row stride 0x4D8 | unchanged | `layout-check.json`: 65 of 68 sampled code sites found again hold it (the other 3 are context collisions) |
| manager fields +0x30/+0x48/+0x70/+0xB0, zooms +0x74 | not shown offline | three manager users found again are identical (one reads +0xB0); otherwise heap layout: live read |
| Nova key `73d84eaae8c75342`, zooms 3.5/2.5/1, vanilla terms | game data | cannot be read offline |

The mod writes only rows that map to the Nova's key, hold the Nova's three zooms and exactly the vanilla terms, on
private read-write heap. If any of that changed it writes nothing and logs "Waiting: …" or sets 0 rows.

## Files

`game-rvas.json` → `game.self.json`, `game.map.json`; `layout_check.py` → `layout-check.json`;
`apply_26568081.py` (asserted rewrite, stage, `STAGE-RECEIPT.json`); `images.sha256`.

Offline: `cd ../../mods/nova-weapon-fov/tests && luajit harness.lua` → 16 checks passed.
