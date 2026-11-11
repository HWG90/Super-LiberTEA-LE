# DBF Modular settings contract

DBF Modular has one MCM registration (`dbf_modular`), one committed Store and one file:
`%APPDATA%/dbf_modular.cfg`. All definitions exist before native gameplay initialization.
The new mod is staged separately; this document does not authorize installation.

## Original controls and menu purposes

All 32 general DBF controls keep their `native_stratagem_radial.*` IDs, types, declared defaults,
choices, slider ranges and steps. In particular, the original input interval remains **0–250 ms**.
All 37 exclusions keep the original MCM `kind_N` IDs. Private aliases
`native_stratagem_radial.mission_kind_N`, `hide_sos` and `hide_eagle_rearm` refer to those same values;
they never create additional controls. Native binding IDs remain unchanged.

| Purpose | Controls |
| --- | ---: |
| Combat HUD | 5 new |
| Position and ADS | 9 new |
| First-person anchors | 7 new |
| Selection | 4 original |
| Wheel appearance | 9 original |
| List filtering | 3 original |
| Weapon controls | 1 new (disabled) |
| Cooldown display | 7 original |
| Cooldown timers | 4 original |
| Input and terminals | 5 original |
| Mission exclusions | 37 original |

This is **91 unique controls in eleven categories**, split into14 pages. Exclusions use four
purpose pages; every page contains at most 13 controls. There are no inherited 82-control HUD+
catalog, discarded-merger controls, duplicate exclusion rows or secondary native MCM owner.

Single-page categories use MCM's direct-page navigation style, so each purpose appears once in
the sidebar. Mission exclusions remains a collapsible category with its four purpose pages.

The existing weapon strip and cooldown settings also govern their Bracket placement. All three
cooldown display modes, four timer positions, short-status styles/placements, balance and gap remain
operative. The gap control is labelled **Appearance / Cooldown spacing**: in Bracket it spaces the
complete cooldown group below combat; in the original layout it keeps its original bar-relative
meaning. Its ID/default/range/step are unchanged. Bracket anchor, scale, opacity and ADS offsets apply
to all integrated components. Quiet aiming hides only presentation, retaining data/transition history;
inspection reveals details. Turning Bracket off restores original placement and controls.
`MODEL-ANCHORS.md` documents separate gun/player attachment behavior.

## New HUD values

The Store returns scale and opacity as **percentages**. Divide them by 100 for rendering.
Position values are 1080p design pixels: multiply by `viewport.height / 1080`, independently of
the HUD size percentage. Positive X moves right; positive Y moves down. Aim offsets add to the
ordinary position in third-person aim and first-person.

| ID | Default | Domain / editing step |
| --- | --- | --- |
| `hud.enabled` | `true` | Boolean |
| `hud.density` | `1` | Quiet=1, Detailed=2 |
| `hud.heat_display` | `1` | Percentage=1, Bar=2, Hybrid=3 |
| `hud.heat_bar_vertical` | `false` | Vertical orientation for Bar/Hybrid; fills bottom to top |
| `hud.ads_minimal` | `true` | Boolean; Quiet aiming hides routine supporting detail |
| `hud.anchor` | `1` | Player and weapon=1, Reticle=2, Beside reticle=3 |
| `hud.cooldown_anchor` | `1` | Under health=1, Under ammo=2; follows that section |
| `hud.tfp_vitals_bone` | `1` | TrueFP: existing10 FPS bones plus78 named weapon nodes; old IDs retained |
| `hud.tfp_ammo_bone` | `1` | Same choices; disabled while Above health uses the health anchor |
| `hud.tfp_ammo_placement` | `1` | Right of anchor=1, Above health=2 |
| `hud.tfp_vitals_offset_x` | `0` | Health X; −600…600 design pixels; step5/fine1 |
| `hud.tfp_vitals_offset_y` | `0` | Health Y down; same range/steps |
| `hud.tfp_ammo_offset_x` | `0` | Ammo X; same range/steps |
| `hud.tfp_ammo_offset_y` | `0` | Ammo Y down; same range/steps; stacked spacing remains clear |
| `hud.anchor_damping_ms` | `80` | 0–300 ms; step10/fine1. Zero follows immediately |
| `hud.scale` | `100` | 80–125%; step 5%, fine step 1% |
| `hud.opacity` | `94` | 60–100%; step 1% |
| `hud.offset_x` | `0` | −600…600 design pixels; step 5, fine step 1 |
| `hud.offset_y` | `0` | −600…600 design pixels; step 5, fine step 1 |
| `hud.ads_offset_x` | `0` | −600…600 design pixels; step 5, fine step 1 |
| `hud.ads_offset_y` | `0` | −600…600 design pixels; step 5, fine step 1 |

The First-person anchors page groups each bone selector with its separate X/Y tuning. These offsets apply only while True First Person is positively detected, add to the global/aim offsets, and scale with resolution rather than HUD size. Above health inherits the health offsets once; ammo offsets then tune its position relative to the stack, with a minimum measured gap. The ammo-bone selector is disabled in that mode, while its X/Y sliders stay editable. `sampling/first_person_bones.lua` is the shared label/hash catalog; unavailable selected nodes use a current safe fallback.

Slider steps govern editing. Valid saved precision survives loading and unrelated whole-state
commits. Reset uses the schema's declared default, not the value imported at startup.

The former `hud.ads_expand` saved/console spelling remains a compatibility alias to
`hud.ads_minimal`. There is one menu row and one committed value; canonical spelling wins when both
are saved. The user explicitly changed aiming behavior from expansion to minimization.

## First import and precedence

Before the first own versioned save, general controls use this order, taking the first valid value:

1. Known values already present in the new mod's own file.
2. Original DBF `ModOptionsMenu.values`, or the original live provider when that file is absent.
3. Original LLL persisted preferences: `Settings/divers_best_friend/config.cfg`.
4. Original project defaults: `Mods/divers_best_friend/config/defaults.cfg`.
5. The new package's original DBF preference fallback, then declared schema defaults.

The original LLL files are JSON data, decoded without executing Lua. Persisted original preferences
overlay original defaults, and only the 32 established DBF keys are admitted. Original sibling paths
come from the new project's real `mod.dir` and `mod.config_dir`; conventional LocalAppData LLL paths
are the fallback. No settings file is opened for writing during import.

Exclusions follow Original DBF's authoritative versioned blacklist. Recognized versions 1, 2 and 3
of `DiversBestFriendBlacklist.log` import all 37 values, including false for absent kinds. Old kind
IDs are translated through the original catalog. Without that file, original menu values and old
blacklist slots supply the fallback. Explicit known values in the new own file still take precedence.
The historical reversed selection mode and release toggle remain migration-only inputs.

After the first successful save, `schema_version=1` makes **only the new own file authoritative**.
Original files, live providers, original JSON preferences and catalog migration data are no longer
read. Missing or invalid current fields use declared defaults. Unknown owned numeric/Boolean fields
remain private and survive subsequent saves. Future unsupported schema versions are refused.

The discarded merger's `dbfplusplus.cfg`, HUD+ preference file and failed combat settings are never
import sources. Original DBF, original LLL settings and original blacklist files are never rewritten
or synchronized by this mod.

## Transactions and ownership

`Store:apply(changes)` validates the complete batch and conflicting aliases before performing one
atomic replacement. It publishes values, one revision and callbacks only after persistence succeeds.
A failed write leaves committed values and callbacks unchanged; a no-op writes nothing. Windows
uses a flushed same-directory temporary file and `MoveFileExW` replacement; the POSIX test path uses
a same-directory rename. Unicode Win32 paths use the wide filesystem APIs.

`Store:dbf_options()` is a private dot-call facade for Original Core. Its registration method only
validates known domains; `on_change` returns the Boolean expected by original consumers. It has no
separate file, menu or registration owner. `Store:close()` retires subscriptions and rejects writes.
The MCM owner retains a refused cleanup handle and retries rather than adopting another owner's ID.

Injected storage supports `read()`, `write_atomic(text)` and optional `read_legacy(name)` for
`menu`/`blacklist`, plus `read_preferences()` returning original-default and original-user JSON text.
These seams let tests exercise actual MCM/Core behavior without accessing installed settings.

Heat Display in Combat HUD chooses Percentage (default), Bar or Hybrid. All three use the same
validated accumulated-heat fraction: cool is zero and maximum heat is full. The flat bar and its
HEAT label belong to the existing weapon role; no native heat icon or unverified gauge is substituted.
Hybrid keeps the percentage and adds the bar, with reserve details below it. Unknown true heat
stays unknown in every mode. Existing saved controls and bindings retain their IDs and values.

Vertical heat bar changes only Bar and Hybrid, keeping the original horizontal default. The fill
is exactly zero when cold and follows validated accumulated heat. At 60% heat it starts pulsing and
blending its base shared color token toward the danger token. Frequency and red blend increase with
heat up to overheat; the dim track remains visible. Unknown heat and weapon changes reset warning
state. The warning is presentation only and introduces no collector or input path.

Weapon controls adds one `weapon.heat_limiter` toggle (default false). It requests the native firing bridge independently of HUD enable/density/heat presentation. Native arming and fault acknowledgements determine whether protection is active. The internal raw-unit ceiling is99% with80% hysteresis. See `HEAT-LIMITER.md` for the native safety and acceptance gates.
