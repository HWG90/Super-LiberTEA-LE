# DBF combat HUD

2026-11-06. Design proposal for the current **LLL / LuaJIT / Linux-Proton** DBF++.
The installed runtime is unchanged by this design work.

## Product direction

DBF is a compact combat instrument centered on the player's next action. It has one visual
language, one layout policy and one source of truth for the facts it presents. Existing native
selection, hotkeys, terminals and the HUD++ feature capabilities remain available, with the
new presentation owned by DBF.

The user chose **near the crosshair**, **contextual expansion**, and **Bracket**, then asked for
less visual activity. Centralized means shared
ownership as well as a coherent location; it does not mean every feature is always visible.

### Visual direction

- A clear aiming area remains around the actual reticle. The HUD sits outside that area and
  below it. Avoid weapon-following wobble and delayed motion in the default layout.
- Ammunition, heat or reload state gets the strongest hierarchy. Stable full health, recovered
  stamina, supplies, routine weapon labels and the full cooldown row are absent in the quiet
  default. Show supporting facts when they can affect the next action.
- Use the game's own FS Sinclair and native equipment/stratagem icons in the runtime. The
  browser study uses substitute icons and a fallback font; it is a layout/behavior study.
- Restrained off-white information, yellow for active selection or an actionable warning,
  and danger color for damage. Keep semantic tokens in a DBF-owned style module, with shared
  sizing/spacing/opacity. No per-feature color literals.
- Prefer open, light instruments with native-style backing only where readability requires
  it. Large opaque windows, ornamental blur, persistent labels and branding are unnecessary
  in the combat cluster. The title and scene controls in the study are preview scaffolding.
- **Bracket** is the selected geometry: vitals and ammunition sit on either side below the
  reticle. The revised study compares its quiet default with its original information density.
  Keep stable positions when elements hide; the remaining instruments must not jump or reflow.

### Quiet Bracket refinement

- The normal view shows the current ammo/heat value, with compact reload, jam/overheat or empty
  state when relevant. Omit permanent capacity, ammo bar, fire mode, magazine count and health
  percentage. Reveal those details on a deliberate inspection action or a meaningful change.
- Keep the health gauge visible while injured. Critical health appears immediately and stays
  readable; a sparse aesthetic must not suppress it. A critical no-stims cue remains visible.
- Stamina appears while sprinting/draining or meaningfully depleted. Use recovery hysteresis
  and a short stable-recovery hold before hiding it, so small fluctuations do not flicker.
- Supplies appear after use, when critically low, or when relevant to the held item. Coalesce
  changes and keep them visible long enough to read; do not pulse every frame or at every tick.
- Remove the persistent four-card cooldown ribbon and repeated READY text. Full names, charges,
  availability and timers belong in selection/inspection. Coalesce a completion event into one
  brief ready cue; do not cycle a backlog of notifications through the crosshair.
- Preserve adaptive heat/fuse/reload presentation. Fire mode can appear briefly after an
  intentional change. Use one actionable warning rather than duplicate color, text and counters.
- A user who wants more persistent information can choose it explicitly. Critical information
  still interrupts the quiet mode; transitions must not introduce input or data latency.

The browser study's scene selector pins example conditions for inspection. Its 900 ms reload
demonstration is simulated and is not a proposed game timing or responsiveness measurement.

The current `~/Projects/HD2-UI-Style/DESIGN.md` explicitly scopes its graphite restyle to
HellForge and excludes this non-HellForge stack. This proposal does not port that restyle.
The user's newest request authorizes a deliberate DBF HUD design; keep its tokens centralized
and preserve native typography/assets. Do not restyle the shared LLL manager or MCM.

## Context rules

| Context | DBF presentation |
| --- | --- |
| Normal combat | Current ammo/heat; injured health and depleted stamina only. Stable supplies and cooldown details hidden. No duplicate weapon row or cooldown cards. |
| Aiming / ADS | Collapse to the smallest relevant weapon readout; damage and critical supplies can still interrupt. Preserve scope/reticle visibility. |
| Reload / low ammo | Immediate state/count change, short actionable cue; no repeating attention animation. |
| Stratagem selection | Expand DBF's selected wheel/list using the same availability and timer model. Show selected name, code, and confirm/cancel feedback. |
| Throwable / beacon held | Show that item's useful trajectory/impact/distance and own strike-area cue. Clear it on release, cancellation, switch or invalid context. |
| Squad / world event | Show a concise relevant cue in a consistent location; ready events coalesce into one cue, and advanced persistent markers remain opt-in. |
| Full-screen menu / hidden HUD | Suspend combat presentation and unnecessary sampling. Selection/input ownership must remain correct. |
| Ship / no controlled player | Combat instruments hidden; retain only required lifecycle/context checks and the independent terminal behavior. |

Every datum has one owner and one chosen presentation. Repeated values in a selection-expanded
view must replace or explicitly supersede their compact counterparts. World-space capabilities
remain world-space when that is useful; they follow the same context and visual policy.

## Evidence from the existing implementation

This proposal is based on the current working tree, including its installed uncommitted fixes.
Do not restart from `be314ef` alone. On audit, all 136 runtime files matched the installed copy.

- `integration/lifecycle.lua` has one loader descriptor, but schedules DBF and HUD separately.
  `dbf/main.lua` additionally schedules the weapon strip and terminal loop.
- `dbf/src/weapon_status_reader.lua` samples weapon facts independently of `hud/product.lua`.
  The strip asks `dbf/src/hud_plus.lua` for already-created HUD cells to deduplicate options.
  That is a presentation compatibility seam, not a shared combat model.
- 3D weapon/vital displays, additions to the vanilla weapon row, and DBF's strip retain separate
  geometry and visibility. Both the DBF cooldown dock and HUD weapon cooldown cards default on.
- Attack areas, trajectories/impact, squad/markers and other feedback largely default on.
  Having the capabilities does not justify showing all of them together by default.
- `integration/settings_layout.lua` improves navigation, but its DBF/HUD sections still expose
  the two inherited products. The new public controls should describe player intent.
- Retained setters in `hud/game/ui.lua`, pose caching in `hud/game/world_stage.lua`, guarded
  native access, bounded closed-dock discovery, and revision-gated settings are useful work
  to retain. A blanket rewrite of these helpers would discard existing optimizations.
- The current private import, true-default reset, cleanup-retry and saved-settings fixes are
  part of the baseline. Preserve them throughout migration.

## Runtime architecture

```text
Guarded native services
          |
Shared context generation + demanded domain samples
          |
DBF presentation policy / layout / interaction state
          |
Retained screen HUD + native widget + world-cue backends
```

### One context and model

`context` establishes session/world generation, valid native roots, controlled player, mission,
menu/ADS/foreground state and input ownership. Domain adapters produce reusable records for
weapon/equipment, vitals/pack/supplies, stratagem availability, squad/events and preview inputs.

Sample a demanded domain once per scheduled tick. Consumers receive a model with validity,
generation and revision, never another renderer's widgets. Reuse buffers and tables, and clear
invalid facts immediately. Share lookup/build evidence and guarded reads while preserving each
existing native operation's validation contract.

Selection and terminals remain action consumers, with explicit ownership and held-input cleanup.
They must not depend on the presence or identity of a HUD widget. Remove method substitution and
widget introspection after the replacement path proves its behavior.

### One presentation policy

A DBF presenter selects visible information, warnings, layout, priority and context transitions.
Its style/layout modules own all geometry and semantic tokens. A model revision can change a
number without recomputing the layout. A style or resolution change invalidates style/layout
once. Presentation never performs an independent weapon/native scan.

Keep screen drawing and native/world primitives behind small retained backends. Reuse the
existing cached setters. Create primitives when the view becomes necessary; update changed
properties; keep bounded pools; retire only resources belonging to the current generation.

### Responsiveness and cost

- Input, selection feedback and visible context transitions run every frame. Do not apply a
  blanket 10 Hz throttle to the new HUD. A fast click must not wait on a slow discovery poll.
- Reuse post-game/native HUD facts or supported change signals for visible ammunition/reload
  where available. Validate the sample phase before claiming same-frame accuracy. A narrow
  fallback read can run every visible frame when needed.
- Timers use a sampled state plus local interpolation/display boundaries; do not rescan the
  entire native tree just to decrement a displayed second. Interpolation is display-only:
  native readiness, availability, charges, timer spans and phase changes remain authoritative.
  Retain the existing cooldown denominator/count fixes. Resynchronize on pause, owner/context
  changes and stale data; an estimated timer reaching zero must not make an action available.
- Keep cold discovery, binding checks and slow-moving squad state on bounded schedules, with
  immediate invalidation/wake on context changes. Preserve existing beneficial 4/10/30 Hz
  distinctions where they serve real data needs.
- Trajectory simulation, raycasts, world scans and projection run only when a visible feature
  needs them. A disabled preview makes no preview-specific reads/calls.
- No file IO or native-tree discovery in primitive setters. Keep persisted settings polling
  and revision gating; those are not the first suspected performance bottleneck.
- Animate emphasis only on transitions and keep it brief. No perpetual tween to follow an
  anchor, no heavy blur and no unnecessary steady-state allocation or geometry rebuild.

## Settings and compatibility

Public pages should be **Combat HUD**, **Selection**, **Context cues**, **Behavior**, and
**Advanced**, organized by what the player experiences. Offer a coherent default and a few
high-value controls: layout/position, scale, opacity, contextual density and selection mode.
Keep specialist feature controls accessible in Advanced rather than presenting two products.

Preserve existing setting IDs, unknown saved values, binding IDs, blacklist protections and
the native guards. New presentation policy may map legacy display choices into the new model;
show that mapping and retain a reversible legacy mode during migration. Do not silently erase
151 settings, apply a new preset over saved values, or remove a capability to reduce a count.

Hide a vanilla element only after DBF has a valid replacement for it. On missing data, failure,
disable or owner loss, promptly hide safely owned replacement views and release valid input
leases. Restore native geometry/visibility only after the existing ownership and safe-close
checks; never write through stale roots. Keep restoration pending when a native selection-menu
animation makes cleanup unsafe. Honor cleanup refusal and retry semantics; never discard a
still-owned HUD generation.

## Delivery slices and acceptance

1. **Baseline and model:** instrument the installed baseline; add shared context/domain adapters
   while keeping visuals stable. Verify value parity, generation invalidation and native guards.
2. **Combat replacement:** implement the chosen near-reticle geometry and contextual rules for
   weapon/vitals/supplies, with a retained renderer and fallback. Suppress the corresponding old
   combat presenters only when this replacement is valid. Review combat/ADS/vehicle/reload states.
3. **Selection and cooldowns:** one stratagem model feeds DBF selection and its compact summary.
   Retire duplicate cooldown cards and widget-cell inspection; preserve hotkeys and cancel/release.
4. **Context cues and settings:** route world capabilities through common demand/visibility,
   introduce intent-based controls, and migrate preferences reversibly. Test menus, hot joins,
   weapon swaps, missing data, disable/re-enable and failed cleanup.
5. **Cost and feel:** compare identical scenes and toggles on the same build, capture actual
   in-game views, save/reload preferences and review responsiveness before replacing the stable
   default. Keep the original DBF backup and the current installed amalgam available for rollback.

Measure per-phase CPU wall time (including synchronous native calls), p50/p95/p99, native reads,
native calls, allocations/GC, primitive create/destroy and property updates. Cover ship, quiet
mission, combat, ADS, selection, weapon switch, preview active and HUD hidden. Report render/GPU
cost separately when measurable; Lua sample share is not total frame time or an FPS speedup.

Structural acceptance: one context sample per frame, one sample of each demanded domain per
scheduled tick, no duplicate facts on screen, zero redundant DBF-generated property writes,
zero steady-state background rebuilds, bounded primitive pools and one DBF screen-GUI owner per
world. Native ticks can reset fields and legitimately require a value to be reasserted; preserve
that behavior and count it separately from avoidable writes. Numbers must be measured against
the baseline before claiming a speedup or adopting an absolute budget.

## Current deliverable

A local interactive design study now compares Quiet Bracket with its original density across
combat, aiming, sprinting, injury, low supplies, ready events, selection, reload, throw preview
and ship. Fire/reload, explicit detail reveal and selection feedback are simulated. It
does not execute native code, sample a game, implement a new runtime HUD or establish performance.
No installed mod files are changed by this proposal.
