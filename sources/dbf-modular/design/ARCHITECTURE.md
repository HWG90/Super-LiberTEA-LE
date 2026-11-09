# DBF Modular: original DBF and Quiet Bracket

User scope: create a fresh backup of Original DBF, create a new mod retaining all DBF capabilities,
build our own modular HUD using HUD+'s anchoring/positioning/ADS flexibility, and implement the saved
Bracket design. This supersedes the abandoned full HUD+ merger. The latest request restores Quiet
ADS collapse and selects separate player/weapon bone anchors. `MODEL-ANCHORS.md` defines this
extension and supersedes earlier shared-anchor/ADS-expansion prose.

Working identity: **DBF Modular**, `dbf_modular`. Target: Steam HD2 build26251122, LLL LuaJIT,
Linux/Proton. Do not reuse the existing unrelated `dbf_hud` ID. No publication or installation of
this new mod is implied. Standalone Original DBF R46 is restored and enabled while this is built.

## Proven baseline and boundaries

`reference/original-dbf/` is an immutable41-file copy of R46-luajit.2-26251122. BASELINE.json hashes
all41 files and records the fresh backup and restoration receipt. Old release prose referring to
25480438 is historical; the manifest and guarded native port determine the26251122 target.

The original main already has one LLL lifecycle and the order Entry -> weapon information ->
terminal. Preserve that composition as a plain `core/dbf.lua` component under `engine/app.lua`,
with one descriptor. Its scope-local entry callback is not another loader update hook.

Keep original DBF's native selection/input/release/pointing/rendering algorithms and bindings.
Do not import the failed merger's frame engine, raw-wheel picker, option merger or HUD+ products.
No HUD module registers Next/Previous/Confirm, polls the wheel or submits stratagem input. MBM
remains the single navigation source. Original standalone DBF and DBF Modular are exclusive.

Preserve Wedge/native wheel/List, all cooldown views/timer styles, filters,37 mission exclusions,
hotkeys, paced/instant input, confirm/hold-release behavior, sounds, weapon options and terminal
routines. Native ABI values and before-write guards stay exact. Preserve32 general settings and37
exclusions and original binding IDs. Palette-only changes required by the latest user AGENTS are
separately recorded and use the copied HD2-UI-Style kit; never restyle adjacent mods.

## Components

- `main.lua` returns the sole app descriptor. `engine/app.lua` owns lifecycle, settings, Core and HUD.
- `core/dbf.lua` factors the original main's bodies/load order/cleanup. It exposes explicit read-only
  services for its already-created native backend and last decorated selection snapshot. Do not
  read nil exports captured at original entry load, inspect widgets or search functions/upvalues.
- `sampling/session.lua` builds validated mission/player/HUD/aim facts from that shared backend.
  It publishes current identity and generation, including controlled-actor replacement under the same HUD root. Unknown facts stay unknown and immediately hide
  the new HUD. Mutation/cleanup guards use fresh reads; invalidation never discards owned storage.
- `hud/controller.lua` schedules one sample -> policy -> placement/layout -> render. No child addon.
- `hud/policy.lua` controls Quiet/Detailed/inspection/ADS and contextual holds. It is independent of
  geometry and contains no memory reads or drawing. Critical injury/no-stim cues interrupt Quiet.
- `hud/anchor.lua` supplies screen/reticle/body/weapon positions in physical screen pixels. Use
  HUD+'s validated aim/anchor rules, not its products, picker, settings or world-UI engine.
- `hud/bracket_layout.lua` owns retained geometry for hip, third-person aim and first-person profiles.
  Profiles affect role placement and Quiet/inspection content. Bound each complete measured group.
- `render/screen_gui.lua` owns one retained engine screen GUI, native FS Sinclair font, token colours,
  primitive IDs and cleanup. Draw in Gui.resolution pixel space, scale 1080p design units by h/1080.
  Do not attach beneath the1x1 native crosshair node or divide by its extent.
- `settings/{schema,store,menu}.lua` has one schema, MCM owner and atomic store. A private dot-call
  facade serves original DBF consumers. No second native menu registration or legacy settings writer.

Original DBF core source remains recognizable. Limit behavior changes to composition, explicit
read-only services/presentation gates, settings persistence adapters and token-only palette changes.
Keep existing native/input contracts intact and test the actual components, not hand-shaped substitutes.

## Anchor and aim contract

The existing guarded avatar-controller identity is checked before action bits: first_person48 and
 aiming82 are distinct; firing/throwing/melee engaged is not ADS. Publish hip, third-person-aim or
first-person profile and known/unknown status. The original DBF camera/input controller stays untouched.

Default: separate animated player/weapon attachments. Reticle and Beside Reticle remain choices,
with independent ADS offsets, scale and opacity. First-person ADS aligns its primary rows with the current sight line. Third-person
following uses verified unit/node ownership, full affine bone-local point transforms and current
camera projection. Reload/switch/heat do not disable a still-current player attachment. Missing gun
data falls back independently; cooldowns follow the selected health/ammo section. Clamp each complete group
within the viewport. Fresh native function-body witnesses exclude adjacent padding.

Do not copy WorldStage: it claims a world-UI slot and changes UI-camera state. Extract read-only
anchor/projection concepts for the flat HUD. No extra camera.capture, pointer or input controller.
Perspective tilt is not implied by a projected flat HUD.

## Quiet Bracket and aiming

Use `design/quiet-bracket/` as the saved baseline, not Original density, Crescent or vertical studies.
At1080p around the reticle (preview coordinates Y-down; renderer converts once to Y-up): ammo x+65,
top+30, font30; left vitals x-145..-65, health top+53(80x3), stamina top+62(80x2), supplies top+74;
reload cue beneath the ammo counter, with reserve below it; one coalesced ready cue beneath the
complete cooldown bar, following its selected health/ammo anchor. Keep stable slots, no flex reflow.

Quiet hipfire: current known weapon count/generic native gauge, injured health, depleted/draining
stamina and relevant/changed/critical supplies. Unknown heat/capacity stays unknown; native gauge
fill must not be mislabeled as heat. Use native counts and preserve reload/charge exclusions.

Quiet ADS hides routine capacity/reserve, options, cooldowns, stamina and supplies. Keep ammo/heat,
reload warnings, critical health, recent damage and an injured no-stim warning. Inspection and
Detailed show fuller details. Original selection supersedes compact combat details while open. Menus,
ship/death/hidden HUD/unknown ownership suspend combat drawing and unnecessary sampling.

Original option icons and cooldown information retain their ORIGINAL DBF display owner and settings.
The user's subsequent layout request integrates these presenters into Bracket through placement-only
APIs. The strip sits below the ammo details; the complete cooldown component sits below fixed combat
shelves. Gun values/options and player vitals now follow separate bones; cooldowns attach beneath the selected
health/ammo section. All share ADS offsets, scale and opacity. `hud/composition.lua` measures each complete
group including native sprites, labels and charge badges, with reticle clearance.
Dense or unknown components retain their original layout independently; no mode or feature is dropped.
New weapon-option text is not copied into Bracket; the original strip remains authoritative. A
brief ready-event cue adds information without introducing another cooldown collector/ribbon.

Native cooldown artwork stays native, while timers/headings/separators use Bracket's retained GUI
and font. Native placement must acknowledge restoration before those dependent labels are changed,
hidden, rebuilt or destroyed. Failure retains the existing owners and fences the next layout attempt.
The original data model, selection/input and native timer cadence stay under Core ownership.

The current user explicitly requests unboxed Bracket text, subtle token shadows and thin bars.
Do not reintroduce per-label plates via the shared kit. Native heat is separately classified and
calibrated to the actual per-weapon limit; zero heat is not empty ammunition.

The first candidate leaves VANILLA subtrees visible. No speculative stock-HUD suppression. A
replacement needs measured bounds/native font and live visual acceptance before it can own a stock role.

## Settings

Eleven purposes: Combat HUD; Position and ADS; First-person anchors; Selection; Wheel appearance; List filtering; Weapon controls;
Cooldown display; Cooldown timers; Input and terminals; Mission exclusions. Paginate exclusions.
Keep all69 original controls. Keep enable, Quiet/Detailed density, anchor, scale, opacity,
X/Y position, minimal Quiet aiming, ADS X/Y position, cooldown side, anchor dampening and heat display, three True First Person anchor/layout choices and four independent role offsets, plus Heat limiter (91 controls). Optional inspect binding gets its
own stable `dbf_modular.inspect` ID; it does not shadow DBF controls. Missing optional binding has
ADS/Detailed fallbacks.

Own file: dbf_modular.cfg. Import original DBF menu/preferences/blacklist once. Do not import the
82 HUD+ settings, failed combat controls or discarded merger canonical state. Preserve explicit
false/zero, current original preferences and unknown owned numeric fields. The first own versioned
save ends import. One atomic write and one MCM owner; failures do not change committed state.

## Gates and ownership

1. Architecture review: Original lifecycle/input, selected anchoring, design/settings audits agree
   with the boundaries above before implementation.
2. Original Core fixtures preserve input/instant/hold/native ABI; lifecycle refusal retains all
   dependent HUD/native owners. Settings cover all69 routes and actual MCM transactions.
3. Actual producer tests for sampling/model/layout/render, including all aim modes, unknowns,
   first-person sight flanks, reload/switch fallback,1080p/4K/ultrawide and full measured bounds.
4. Retained renderer tests show no unchanged-frame recreation, no per-frame IO and failure-safe
   ownership. Primitive failure cannot hide vanilla or discard a live GUI owner.
5. Independent review: no material unresolved finding before candidate packaging.
6. Actual LLL folder preflight and deterministic loose package containing complete editable source.
7. Separate live preview leaves vanilla visible; screenshot/native-size and input acceptance are
   required before replacing the stable installation. No FPS claim from mocks or file hashes.

Original backup/restore is complete. New mod source is isolated at DBF-Modular; implementation
starts only after this architecture's scoped review. The discarded merger remains archived.

## Native Heat Limiter extension

The user explicitly requested strict prevention through a new native firing bridge. `HEAT-LIMITER.md` extends the former presentation-only scope with one Core-owned gameplay component, one new Weapon controls toggle, and a build-specific native generation. Original `src/` native/input algorithms stay immutable; the HUD remains read-only.
