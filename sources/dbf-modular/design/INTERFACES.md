# Implementation interfaces

All plain components use colon lifecycle methods; no module except engine/app.lua returns an API-1
addon descriptor. Runtime root is dbf_modular/. Original src/ paths remain so native imports do not
need wholesale rewriting. No writes to reference/original-dbf/. Installation/live-update state is recorded separately in dist receipts.

## Core

`Core.new(mod, {settings, globals, report})` -> object with `enable()`, `update(dt)`, `close()` and
`services()`. Settings is the one Store. Preserve original Main update order and original guards.
`close()` returns false,reason when required cleanup refuses, true when complete. Retain dependent
owners on refusal. Normal unknown/idle update is not a lifecycle failure.

`services()` returns an explicit read-only record:
- backend: the ALREADY-CREATED original native backend (nil until initialized).
- api: original DBF diagnostics facade.
- snapshot: last already-decorated selection snapshot (nil if unknown); do not resample for HUD.
- weapon: the original weapon-information sample/readout (nil if unknown).
- cooldowns: the original already-collected decorated cooldown snapshot with `.rows` (nil if unknown).
- presentation: current core render-policy record.
- layout: current placement handover/restore-pending record, or nil for original placement.

Narrow entry getter captures live upvalues, not original table exports containing initial nils.
`set_presentation({weapon_options=true,cooldowns=true})` gates only existing DBF views, not gameplay
sampling or input and never vanilla. Defaults preserve original views. Original DBF settings remain authoritative. Quiet aiming temporarily hides routine presentation
while collectors/input continue; inspection, hipfire or disabling Bracket reveals it. The latest
explicit user instruction overrides the earlier always-visible rule.
No renderer replacement claim may suppress an original presenter; Quiet ADS is an explicit visibility policy. Original option reader remains
single owner; split sample/present if needed, leaving old update() as equivalent composition.

`weapon_metrics(edge,gap)` returns the original strip's measured physical extent, count, root and
source revision. `cooldown_layout(options)` returns a reused packet from the existing cooldown
model with identity/generation/sourceRevision, complete current-and-target bounds, native tiles and
shared text/line primitives. Options carry font/measure, scale, pixel and fixed combat bounds.
`set_layout(strip_spec,packet,anchor,opacity)` places those same original presenters, requiring
explicit acknowledgments and fresh native ownership. `clear_layout()` restores their original
presentation immediately without a second sample or lost model state. Failed restoration retains
`layout.restore_pending` and blocks new placement. Placement never changes presentation flags; Quiet aiming controls visibility separately.

Settings seams: core's private scope overrides dbf_options_menu/canary_settings to use the Store
facade. Mission exclusions use the same Store and protections, not the old log writer. Native
behavior remains original; no raw-wheel navigation adapter or new input router.

## Settings

`Store.new(mod, globals, optional_storage)`; `get(id)`, `set(id,value)`, `apply(changes)`,
`on_change(id,callback)`, `dbf_options()` and `close()`. Dot-call facade supports original get/set/
register_option(validation only)/on_change. Core IDs retain native_stratagem_radial.* spellings.
Schema exposes original32 keys and37 exclusions, exact types/defaults/ranges, and twenty-one HUD IDs:
`hud.enabled`, `hud.density`(Quiet=1,Detailed=2), `hud.anchor`(Player and weapon=1,Reticle=2,Beside=3),
`hud.scale`, `hud.opacity`, `hud.offset_x`, `hud.offset_y`, `hud.ads_minimal`, `hud.ads_offset_x`,
`hud.ads_offset_y`, `hud.cooldown_anchor`(Under health=1,Under ammo=2),
`hud.anchor_damping_ms`(0–300ms; default80), `hud.heat_display`(Percentage=1, Bar=2, Hybrid=3; default1), `hud.heat_bar_vertical`(Boolean; defaultfalse). Additional True First Person IDs are `hud.tfp_vitals_bone`, `hud.tfp_ammo_bone`, `hud.tfp_ammo_placement`, `hud.tfp_vitals_offset_x/y` and `hud.tfp_ammo_offset_x/y`. The pure `sampling/first_person_bones.lua` catalog supplies both selectors and sampler lookup; no game access occurs when the settings schema loads. Role offsets use1080p design pixels independently of HUD size. Scale/opacity use percent units in UI.

`Menu.new(store,get_mcm)` with update()/close(); one dbf_modular owner. Definitions must be available
before Native Core starts. Original settings migration only; no discarded-merger/HUD file imports.

## HUD model and rendering

Root-owned sampler produces a reused model (all values current, nil means unknown):
```
{
 known, identity, generation, time, in_mission, alive, hud_visible, menu_open, blocked,
 aim={known,first_person,aiming,switching,true_first_person,viewmodel_unit,weapon_unit},
 viewport={width,height}, reticle={known,x,y}, anchor_context, anchor_camera,
 sight_clearance={known,identity,generation,context,camera,follow_token,source,bounds,polygons},
 anchors={body={known,x,y,clipped},weapon={known,x,y,clipped}},
 weapon={known,entity,count,remaining,capacity,reserve,reloading,throwing,ammo_kind,heat_weapon,heat,
         heat_current,heat_limit,heat_locked,fire_mode,rpm,rpm_index,
         ammo_mode,zoom,zoom_index},
 health,stamina,stims,throwables,
 cooldowns={...already sampled original rows...},
 font={font,atlas,material}, world
}
```
Reticle/anchor positions and viewport are physical pixels with bottom-left/Y-up coordinates.
generation advances on validated HUD/context or controlled-actor identity changes.
health/stamina/remaining are finite0..1 or nil. Generic remaining is never labeled heat. Capacity
is supplied only by the original reader's validated fact. Aim bits remain independent. world is a
validated Stingray world handle for a retained GUI, not a newly created world-UI slot.

HUD settings getter may be the Store itself; Policy/Layout must not write settings. `Policy.new()`
with `update(model, settings, dt, inspect)` -> reused view containing visible/profile/details and
module visibility/data. Profiles are hip, aim and first_person, unknown aiming never guessed. Quiet aiming intentionally
minimizes routine details; inspection/Detailed reveal them. `MODEL-ANCHORS.md` defines role-aware
anchor, local affine offset and independent group-bound contracts.
`Anchor.resolve(model,settings,viewport,bounds)` -> verified/clamped anchor or nil,reason; no native
calls in pure anchor math. `Layout.new():update(view,settings,viewport,anchor,measure)` -> reused
named primitive/layout records and complete measured bounds. Document exact returned fields in
module comments/tests and send Root the finalized calling contract.

`Renderer.new({globals,report,before_change})` with `viewport()`, `measure(font,text,size)`, `render(model,view,layout)`
and `close()`. Use known original screen GUI call: World.create_screen_gui(world,'scale',1,1),
Gui.resolution() in physical pixels, and font/atlas/material descriptor from backend.dock_font(sr).
Bind the native atlas once per font/GUI lifetime using the same native material setup as the
original cooldown renderer. Retain only HEX IDs; resolve temporary IdString64 at immediate calls.
Reuse the proven GUI lease/primitive-ledger technique with a unique dbf_modular pool; unknown worlds
are not proof of retirement. Never create/destroy unchanged primitives each frame. Apply all fixed
colours through ui/style.lua tokens. Font baseline/appearance need live acceptance, not mock claims.

Root controller owns optional inspect binding dbf_modular.inspect; no other HUD input. It runs
sample->policy->anchor/layout->renderer once after Core.update, preserving original presenters.
`hud/composition.lua` adds native presenter bounds to that single pass. `before_change` requires
positive native restoration before removing/recreating dependent `cooldown/` primitives, hiding, rebuilding
or closing their shared GUI. Existing same-ID/kind/font primitives update in place during motion. Controller close restores native placement before HUD-owned GUI/native
projection buffers and Core native teardown. Stock HUD untouched.

Heat is a distinct validated0..1 accumulated-heat fraction: current/native limit. Native driver
flags and source-proven mixed-type exceptions select it; nonreloadable and generic gauges do not.
The heat collector is read-only and validates component identity, limits and current-build witnesses.

Native supply artwork is a separate read-only-data presenter: Session publishes current `supply_icons.stims`/`.throwables` texture/dimension records fenced by HUD identity, context and generation. Layout includes the two image bounds beside numeric counts and exports physical-pixel placement; unavailable icons use descriptive text. `render/supply_icons.lua` owns only its two sprite nodes, never moves or suppresses the stock HUD, and must acknowledge hide/close before dependent HUD retirement. Native texture dimensions preserve aspect ratio. The original weapon strip remains the only weapon-options presenter and sits directly below the ammo value.

Heat Limiter live acceptance is withdrawn after dev.12 observation-mode crash. Its production profile is unavailable and is checked before any helper factory/load; the menu control is disabled and the HUD archive excludes its DLL. Keeping the experiment's source or offline ABI tests is not an active overheat-prevention capability.

True First Person role DTOs `anchors.tfp_vitals` and `anchors.viewmodel` carry `unit_domain`, unit, node, bone_choice/hash and complete actor/camera/context/generation tokens. Domain fps is checked against the fresh `aim.viewmodel_unit`; domain weapon against the independently fenced `aim.weapon_unit`. The shared bone catalog's `resolve(choice)` returns hash, calibration name and domain without game access. First10 choices retain their meanings; named weapon choices append with stable IDs.
