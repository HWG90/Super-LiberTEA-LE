# Animated model anchors

Current user direction supersedes the earlier ADS expansion proposal: weapon values/options follow
their own gun anchor, vitals/supplies follow the player's animated bone, and Quiet aiming hides
routine detail. Keep the HUD flat and legible, with the same unboxed text, shadows and thin bars.

## Sampling

Reuse the original guarded actor and currently wielded weapon identity. The DBF record+16 unit
reference remains an identity reference; native Unit calls use the distinct engine handle freshly
read from the pinned record+12 field and revalidated through projection. Resolve the existing player
head node by semantic name; use the current weapon-data fire node rather than a guessed bone index.
Read each current bone's full affine pose to transform its local attachment offset, then project
the resulting point through the current game camera. The raw basis carries animation rotation and
scale; it must not be normalized as though it were a billboard. Glyphs stay screen-upright.

`sampling/attachments.lua` owns editable bone-local calibration offsets. Native offsets stay in
`sampling/build.lua`. All calls retain PE/module, executable-page and function-body witnesses;
`ANCHOR-WITNESSES-dev.4.json` records the fresh capture. Unit/actor, gun/component/node, camera and
HUD context must remain current through the final projection. Never cache a pose or raw world point.

Body validity is independent of weapon reload/switch/heat state. Hip ammo follows the current head;
third-person aim transitions it to the current weapon bone. First-person ADS uses the current native aim point or known screen center for sight-aligned
flanks (vitals left, ammo right). The controller-owned
FPS handle and current native camera request must agree with the current actor, weapon and body.
Missing/stowed/replaced models fall back safely for the affected role. No world UI, new camera,
extra input routine, gameplay write or per-frame world-unit scan is introduced.

## Geometry and visibility

Three local groups: weapon (ammo, reserve/capacity, native option strip), vitals (health, stamina,
stims, throwables), and central (shared reticle reference). Reload cues follow ammo; ready cues follow
the selected cooldown group beneath its complete bar. Resolve and clamp each complete group independently. Global and
ADS pixel offsets apply once after bone projection. Cooldowns attach beneath health by default or
beneath ammo through `hud.cooldown_anchor`, sharing that complete group and its animated anchor.
Stable logical shelves prevent contextual visibility or digit changes from moving the row locally.
Unknown bone data falls back only for that role. Unknown global ownership retains the existing safe
cleanup/fallback behavior. Complete text, shadow, native icon and badge bounds remain measured.

Quiet aiming keeps ammo/heat, reload warnings, critical health, a brief fresh-damage cue and an
injured no-stim warning. It hides routine capacity/reserve, options, cooldowns, stamina and supply
counts. Inspection or Detailed mode reveals them. Native collectors/input continue while hidden;
the existing data model and transition/charge history are retained. Intentional hiding never causes
the original viewport view to reappear as a placement fallback.

Original HUD controls remain. `hud.ads_minimal` replaces the old expansion spelling;
saved `hud.ads_expand` and its console route remain aliases without a second menu row. Model-aware
positioning is the new default anchor. Existing saved choices remain valid; this user's live update
selects model anchoring and enables minimal Quiet aiming as explicitly requested.

## Acceptance

Exercise real affine projection with rotated/scaled matrices, malformed poses, unavailable nodes,
identity changes during calls, independent player/gun motion, reloads, heat weapons, swaps, HUD/camera
replacement, first-person sight alignment and full viewport bounds. Verify Quiet/inspection/Detailed changes
through the actual controller/Core and retained renderer. Package and live reload only after focused
tests, full source checks and independent review. Live runtime activity is separate from visual
acceptance and performance measurement.

## True First Person selected model anchors

Detect the public running True First Person mode independently of native ADS bits, then prove DBF's current actor, wield, camera request, controller and FPS rig before native getters and final publication. Do not change the provider or camera.

Health, stamina and supplies use `hud.tfp_vitals_bone`; ammo, heat and weapon controls use `hud.tfp_ammo_bone`. Both default to Weapon chassis. The shared pure-data catalog `sampling/first_person_bones.lua` supplies ten source-proven choices: Weapon chassis, both wrists, both elbows, both shoulders, chest and both clavicles. Existing choices1..3 retain their saved IDs; added choices append without reordering. Chassis uses the existing model-local0.5 forward calibration because its raw attachment pivot can lie behind the eye; arm nodes use zero local offset. These are editable attachment calibrations, not measured optic geometry. Resolve hashes on the current unit; never retain node indices or old poses.

The displayed health bar center sits one HUD gap left of its selected point. Right-of-sight ammo places the measured primary center one gap right of its selected point. Each filters its physical reference before inverting the current text/bar geometry, so changing digits, fonts or heat presentation cannot disturb the attachment.

`hud.tfp_ammo_placement` also offers Above health. That mode uses the effective health anchor and stacks the complete ammo/options group above the displayed health group with a measured gap. The independent ammo-bone preference remains saved and its menu row is disabled until Right of anchor is selected again. At zero ammo X offset, the complete visible ammo/heat/coil/options envelope is horizontally centered over the health/stamina/supply bracket; centering the percentage glyph alone is insufficient. Cooldown widths do not change that horizontal reference, while their full bounds still participate in vertical spacing and viewport limits. Explicit ammo X tuning offsets that centered column. A stacked pair clamps together when required; ordinary roles keep independent placement. Cooldowns retain their selected health/ammo section and all original controls.

Sample at most two selected model points per frame. Identical node/calibration selections reuse this frame's copied coordinates; Above health needs only the health point. No pose persists across frames. Selected hash/calibration participate in point identity and smoothing resets. Provider, actor, weapon, camera and FPS-unit changes invalidate old points. Missing projection withdraws only that role's coordinates, with current safe fallback and no stale-pose reuse. Visibility remains under Quiet/Detailed/inspection policy; text stays upright. Ordinary hip, third-person aim and native ADS layouts are unchanged outside True First Person.

Separate `hud.tfp_vitals_offset_x/y` and `hud.tfp_ammo_offset_x/y` are resolution-scaled1080p design pixels, positive X right and Y down. They apply once after model projection and before filtering physical primary references, independently of HUD scale. Global/ADS offsets remain additive. Current fallback roles retain their offsets while True First Person is proven; other modes and the reticle do not receive them. Above health uses the health offset on the shared filtered placement and applies ammo XY relative to its measured stack, with no second filter; positive ammo Y stops at the minimum measured gap. Zero offsets preserve the previous layout. Role-offset, bone and mode edits reset motion even with zero frame time.

## Weapon-rig anchors

The previous DBF HUD editor's78 named weapon hashes are appended after the ten existing FPS-rig choices. IDs1..10 keep their prior labels and meaning. Weapon: StingrayEntityRoot (0x4A182741) is the equipped gun's origin. It is a different unit from the FPS rig's identically hashed root. The shared catalog carries `unit_domain` (fps or weapon); selected hashes resolve on that current unit only. These are the old editor's named entries, not a dynamic list of every unnamed node on the currently held resource. Availability varies by weapon and pose.

Both roles can use either domain. FPS points match the independently verified `aim.viewmodel_unit`; gun points match the independently published `aim.weapon_unit`. Every gun Unit getter requires the complete fresh gun ownership proof. A complete FPS mode/camera/actor/wield fence precedes the batch and final publication. Domain, actual engine handle, hash and full model-local calibration form the deduplication key. Only identical current-frame points are shared. Missing/clipped nodes use current fallback; no old pose or other rig's identically named node is substituted. No new native API or per-frame node enumeration is introduced.
