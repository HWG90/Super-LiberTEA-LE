# DBF Modular — Quiet Bracket

Version0.1.0-dev.23, Steam HD2 build26251122, LuaJIT LLL on Linux/Proton.

Original DBF R46 selection, hotkeys, filters, exclusions, cooldown modes and timers, weapon options,
input pacing and terminal routines remain under one lifecycle and settings owner. Quiet aiming hides
routine supporting HUD details; inspection or Detailed reveals them. Bracket uses unboxed text,
subtle token shadows, native artwork and thin bars.

The DBF Modular MCM entry has91 controls in11 categories. First-person anchors contains separate
health and ammo bone lists and X/Y sliders. The ten existing FPS-rig choices keep their IDs. The old DBF HUD editor's78 named weapon nodes are
appended, including the actual gun's StingrayEntityRoot origin, optic/sight mounts and moving parts.
Weapon nodes resolve on the equipped gun; missing or clipped points use the current screen fallback.
X/Y offsets are1080p pixels, positive right/down, scaled with resolution rather than HUD size.
Above health centers the complete ammo/heat/options section over the health bracket and adds ammo
offsets relative to that centered stack; cooldown widths do not recenter it. Measured spacing
keeps the sections clear. Hip, third-person aim and normal ADS retain their existing placement.

`hud/` owns visibility, geometry and placement; `sampling/` owns read-only combat facts;
`render/` owns retained drawing; `settings/` owns configuration; `core/dbf.lua` composes the original
`src/` routines. All Lua files are editable loose source. `sampling/first_person_bones.lua` supplies
shared bone choices and `sampling/attachments.lua` holds model-local calibration.

Heat supports percentage, bar or hybrid presentation and horizontal/vertical meters. Zero heat is
cold. The experimental native Heat Limiter remains unavailable and its DLL is excluded from this HUD
package. The complete source archive retains the experiment for offline investigation only.

Prefer LLL live reload with acknowledged cleanup and a rollback backup. Refused cleanup retains its
owners for retry; never force-remove loader records. Enable only one DBF provider. Native-FFI LLL,
MBM v2+ and DBF-MCM API1 supply the existing host services. No custom HUD+ asset companion is needed.
Source tests and package checks are separate from in-game visual acceptance and speed measurement.
