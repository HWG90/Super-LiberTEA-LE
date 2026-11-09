# DBF Modular — Quiet Bracket

A new, separate LLL mod based on the verified Original DBF R46. The first HUD is the saved Quiet
Bracket: ammo to the right of the crosshair, a thicker health bar and thin stamina track to the left, fixed supply
slots, and brief reload/ready cues. Quiet aiming hides routine detail. It is an editable source
candidate for **Steam Helldivers2 build26251122, LuaJIT LLL on Linux/Proton**.

Original DBF is backed up; its routines run inside DBF Modular. The separate standalone addon is
disabled to prevent duplicate input owners. The discarded DBF++ merger remains archived. Current
installation evidence is recorded in `dist/LLL-INSTALL-RECEIPT.json` and any later live-update receipt.

## What is implemented

- Original DBF selection: native/Wedge/List modes, filters and exclusions, original hotkeys,
  confirm/hold-release selection, paced/instant input, cooldown views/timers, sounds, weapon options
  and terminal controls. Native selection/input/ABI algorithms remain the original implementation.
- One API-1 lifecycle: settings, Original Core, then one read-only HUD pass. MBM remains the sole
  owner of stratagem navigation. The HUD adds only an optional unbound `dbf_modular.inspect` action.
- Quiet/Detailed density; Player and weapon, Reticle or Beside Reticle placement; independent ADS
  offsets, scale and opacity. Hip ammo/options follow the head; third-person aim transitions them
  to the weapon bone. First-person ADS places vitals left and ammo right of the current sights, automatically clearing validated weapon/optic bounds with a padded minimum gap. Bone-local offsets inherit animation transforms while text stays upright. Anchor
  dampening is adjustable from0–300ms. True First Person has separate FPS/weapon bone lists and X/Y sliders for health and ammo, with health left of its anchor and ammo either to the right or stacked above health. Missing models fall back independently; critical visibility
  and readouts remain immediate. A hidden reticle uses the viewport center.
- Contextual health, stamina and supply visibility with short holds; critical injury/no-stim cues;
  inspection details; one coalesced stratagem-ready cue. Quiet aiming keeps ammo/heat, reload
  warnings, critical health and recent-damage/no-stim cues, hiding routine options/cooldowns and
  supporting details. Inspection or Detailed reveals them. Selection, death, ship, menus, focus
  loss and hidden HUD suspend Bracket.
- One settings store and MCM owner: all69 original controls plus21 HUD controls and one Heat limiter in11 categories.
  Existing DBF bindings retain their IDs. Original DBF settings import until the first own versioned save; new writes go only to
  the new mod's own file. See `design/SETTINGS.md`.
- Retained screen GUI primitives, cached native-font measurements and token-based colours from
  HD2-UI-Style. Unchanged renderer frames make no primitive updates or native text measurements
  in the fixture. This is an offline behavior result, not a game/FPS measurement.

Bracket now places DBF's original weapon strip and cooldowns in one group near the crosshair.
Option icons sit below ammo and follow the gun; vitals follow the player. Cooldown tiles and timers
attach beneath health by default, or beneath ammo through **Position and ADS → Cooldown placement**.
They follow the selected section's model anchor, scale, opacity and ADS offsets. Stable shelves
prevent changing digits or contextual visibility from shifting them relative to that section.

The existing DBF renderers, data and settings remain authoritative: all cooldown views, timer
positions, charge counts, short-status groups, balancing and spacing still work. No extra collector
or input handler is added. Quiet aiming hides only presentation, preserving sampled data and
transition/charge history. A component that cannot fit safely or whose native placement is unknown
keeps its original screen position. Disabling Bracket restores the original layouts. Shared labels
are retired only after native placement has been restored. Bracket labels and option icons are
unboxed, with subtle token text shadows, a5px health bar without a number and a thin stamina bar; native cooldown artwork remains. Supply counts use the native syringe and equipped-grenade artwork. Thin open side brackets group the visible vitals and supplies, with cooldowns outside.

Laser heat is distinct from ammo: the verified native heat value is divided by its actual weapon
or entity-override heat limit, then shown as0–100%. A cold laser never reports EMPTY or RELOAD.
The current affected laser was measured live with a limit of150; raw heat must not be mistaken for
an already-normalized percentage. Unknown heat remains unknown.

## Edit the HUD

The full loose source is in `dbf_modular/`; no bundle needs unpacking.

| Change | File |
|---|---|
| Element visibility, holds, Quiet aiming | `dbf_modular/hud/policy.lua` |
| Bracket spacing, text sizes, fixed slots | `dbf_modular/hud/bracket_layout.lua` |
| Shared combat/weapon/cooldown placement and bounds | `dbf_modular/hud/composition.lua` |
| Original option sprites and cooldown tile presenters | `dbf_modular/src/weapon_status_strip.lua`, `src/cooldown_dock.lua` |
| Body/reticle placement and screen bounds | `dbf_modular/hud/anchor.lua` |
| Editable player/weapon bone-local attachment offsets | `dbf_modular/sampling/attachments.lua` |
| Read-only mission/aim/weapon facts | `dbf_modular/sampling/session.lua` |
| Drawing, native font binding and retained GUI | `dbf_modular/render/screen_gui.lua`, `render/pool.lua` |
| Native syringe/current-grenade artwork and ownership | `dbf_modular/render/supply_icons.lua` |
| Menu categories, ranges and defaults | `dbf_modular/settings/schema.lua` |
| Original DBF lifecycle | `dbf_modular/core/dbf.lua` |
| App lifecycle and the single HUD pass | `dbf_modular/engine/app.lua`, `hud/controller.lua` |

Coordinates in the design/settings are1080p pixels, positive Y down. Engine drawing uses physical
screen pixels, positive Y up; layout converts once and scales by screen height. `hud.scale=100`
is1× and `hud.opacity=94` is94%. ADS offsets add to the normal offsets. Fixed colours come from
`dbf_modular/ui/style.lua` tokens, copied unchanged from the shared kit.

`reference/original-dbf/` is the immutable41-file baseline. `design/quiet-bracket/` preserves the
selected visual study. The latest user direction restores Quiet ADS collapse and adds separate
animated model anchors; see `design/MODEL-ANCHORS.md`. No rejected design is enabled.

## Build and checks

Requires Python3 and LuaJIT on the build host:

```sh
python3 tools/check.py
python3 tools/build.py
```

The build checks every declared source, native preservation, actual Store/Core and MCM integration,
actual policy/anchor/layout/renderer behavior, ownership failures, and the exact LLL folder loader.
ZIP members are round-tripped byte-for-byte. `dist/` contains a loose LLL package, a complete source
ZIP and hashes. ZIP generation is deterministic. Nothing installs or launches the game.

Runtime dependencies: LLL with native FFI, MBM v2+ (v4 native bindings supported), and
DBF-MCM API1 for the menu. Drawing uses the original game-native font and artwork. This Lua source package does not require
the old HUD+ custom-resource companion, redistribute game resources or install another copy of a
shared framework. Existing installed asset companions are left untouched. Disable standalone DBF and DBF++ before enabling this candidate: they share the
original native selection ownership and must run exclusively. A runtime duplicate-provider check
also refuses a second owner. Follow `design/LIVE-CHECK.md` for the eventual preview.

## Evidence and limits

The original baseline and restored installation are hash-verified. Offline suites cover actual
components and failure paths; Win32 settings replacement was additionally exercised with standalone
Windows LuaJIT in an isolated temporary Wine prefix. These checks do not establish in-game font
appearance, anchor alignment, input acceptance or performance. Those remain a separate live test.
Capacity and heat are not guessed. This first sampler publishes native counts/reserve and leaves
capacity/generic remaining absent because the required charge/reload witnesses are not yet part of
the small sampler. The policy supports a future validated remaining value without labelling it heat.
The original weapon strip remains in charge of all weapon options. Verified heat has its own
read-only collector; generic gauge/charge values are never labelled heat.

Updates prefer LLL live reload: stage and back up first, acknowledge existing owner cleanup and
public disable, swap the complete folder, then enable. Cleanup refusal retains owners for retry;
never force-delete loader records. MCM and game asset packages are not reloaded by this update.

Native Heat Limiter source is under `native/heat_limiter/`, owned by Core rather than Bracket. Its arming, per-shot/beam gates and final in-game acceptance are documented in `design/HEAT-LIMITER.md`. Build with `python3 tools/build_heat_limiter.py` (Zig0.14.1 and Wine); that command tests only a fresh disposable Wine prefix and never installs into the game.

The native Heat Limiter experiment is withheld after the dev.12 observation test crashed. The HUD package excludes its DLL, its menu toggle is disabled, and its production profile prevents loading even if a prior preference says enabled. Native source and incident evidence are retained for investigation; this build provides no overheat prevention.
