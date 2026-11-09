# Next live preview acceptance

Original DBF is backed up and its routines are retained inside DBF Modular. Standalone DBF remains disabled to avoid a second input owner. Its fresh
backup and merger archive are recorded in BASELINE.json and the adjacent restoration receipt.
No live result is claimed by package generation, Lua compilation, Wine filesystem tests or hashes.

Prefer normal LLL live update: stage and back up, acknowledge DBF Modular owner cleanup,
publicly disable the addon, atomically swap the folder, then enable the new version. A cleanup
refusal retains owners for retry; never force-forget records. Keep only dbf_modular enabled and
divers_best_friend/dbfplusplus disabled. Preserve all existing
bindings and settings. Leave existing installed asset companions untouched; do not activate two Lua providers. This new
source does not require the discarded HUD+ custom-resource companion.

1. Check the new LLL log names DBF Modular0.1.0-dev.11/build26251122 and MCM has84 controls in10
   categories. Ship/menu/death states show no Bracket or stale primitives; vanilla HUD stays intact.
2. In mission, test primary/secondary/support/throwable and non-reloadable weapons. Verify counts,
   reserve, health/stamina and fixed supply positions. Unknown capacity/heat must stay absent.
3. Test Quiet vs Detailed, third-person aim, first-person scope and release ADS. Quiet aiming hides
   routine details; ammo/heat and urgent damage/critical-health/no-stim/reload cues remain. First-person
   flanks the current sights. Independent offsets apply once and restore. Aim/attack are distinct.
4. Bind the optional Inspect combat HUD action in MBM. Inspection and Detailed reveal supporting
   details and original options/cooldowns. Repeatedly hide/reveal with active cooldowns: BOTH native
   icons and countdown text must return, retaining timer/charge/transition state. Critical vitals interrupt Quiet.
5. Test Player and weapon/Reticle/Beside anchoring, camera motion, reload, switch and missing anchors.
   Verify the actual engine handles and resolved bones; Original DBF unit references are distinct.
   Hip ammo follows the head; TP aim transitions it to the gun; FP uses left/right sight flanks, while cooldowns follow the chosen health/ammo section. Test both placement choices and
   sustained movement: native progress/count updates must keep their original250ms cadence.
   Missing gun data must not invalidate player vitals. Bone-local offsets follow rotation/scale;
   hidden native crosshair uses screen center.
   Check1080p/4K/ultrawide, edge clamping, native font scale, inventory/menu/input focus transitions.
6. Verify original List next/previous moves exactly one row, confirm and hold-release each select
   once, original slot hotkeys work, and Wedge/native modes preserve behavior. Test paced/instant
   input and terminal controls on the actual host/client path before asserting parity.
7. Change settings, restart, and verify persistence. Original DBF files must remain unchanged.
8. Disable/reload in safe gameplay/menu states; a cleanup refusal must retain owners and explain
   why. Restart if cleanup cannot complete. Confirm no stale HUD or modified vanilla subtree.

Capture before/after frame timings in the same scene/settings if performance comparison is needed.
No numerical speed improvement is inferred from the offline unchanged-frame test.

For the adaptive FP update, aim with a small sight and a large optic. Confirm geometry status is
weapon_bounds, then compare the measured exclusion to visible optic and whole-role placement.
Unknown or oversized geometry must explicitly fall back without hiding the main HUD. Test all
three Heat Display modes on a cold, warm and overheated laser; verify one heat source, percentage
consistency, bar growth, warning behavior, Quiet reveals and sight-line alignment in Bar mode.

Heat Limiter acceptance: validate the Weapon controls toggle, raw native99% admission and80% recovery on a projectile laser and a continuous beam. Check physical cessation of shots/beam as well as raw heat staying below its true limit. Test held trigger, cool/resume, hot weapon switch, alternate/unknown mode, toggle off, and acknowledged native cleanup during live reload. Unknown native paths must report unavailable.
