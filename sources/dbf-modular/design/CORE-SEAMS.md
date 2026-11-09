# Original Core preservation

The runtime `src/` folder is the verified Original DBF source with the following narrow seams.
The full immutable41-file baseline is under `reference/original-dbf/`.

| File | Change |
|---|---|
| `core/dbf.lua` (new) | Factor the original main lifecycle into a private plain component, preserving Entry→weapon-status→terminal order and retaining owners when cleanup refuses. |
| `src/entry.lua` | Explicit current services getter and placement-only bridge for the existing cooldown view. Defer original drawing only during acknowledged Bracket placement; sampling/input stay unchanged. Private settings facade. No second global update callback or navigation source. |
| `src/settings.lua` | Use the injected single-store facade. Original option meanings, units, ranges and native consumers remain. |
| `src/mission_blacklist.lua` | Exclusion data routes to the same Store; original catalog/kinds retained, legacy writer retired in this new mod only. |
| `src/terminal.lua` | Settings lookup through the injected facade, preserving explicit false. Native terminal routines/guards retained. |
| `src/weapon_status.lua` | Publish the existing reader's verified DTO, split presentation from polling, and expose strip metrics/placement. No second weapon-option reader. |
| `src/weapon_status_strip.lua` | Original sprites, order, UV crops and assets with optional measured Bracket placement. Fresh parent/resource ownership, acknowledged original-position restoration, no integrated backing plate. |
| `src/cooldown_dock.lua` | Original model and native tiles plus pure measured Bracket geometry, shared-label export and placement/restoration APIs. Restore cached child visibility after presentation-only hiding. All original modes, timers, charges, transitions and controls remain. No second row collector. |
| `src/binding_warning.lua`, `expanded.lua` | Fixed-palette-only substitutions with shared style tokens; no new colours in gameplay data. |

The25 other native/input modules are byte-identical, verified by `test_core_native_preservation.lua`.
Before-write/native ABI guards, selection, release, input, pointing, camera and reader algorithms
retain their original values. Token-only changes are separate from native behavior changes.
No file under the restored standalone DBF installation is modified by this source candidate.

The read-only Bracket sampler is independent of original algorithms: it shares the original native
backend, reads current mission/UI/action facts, and uses six guarded read-only HUD+ getters for
reload/body/weapon positioning, including the witnessed full bone pose. It never creates a world-UI
slot or changes camera/FOV state. Presentation-only Quiet aiming does not reset the cooldown model.
