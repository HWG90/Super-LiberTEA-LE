# Editing HudPlusPlus

## Find the right file

| Change | Start here |
| --- | --- |
| Option label, default, choice or range | `src/game/options.lua` |
| Feature visibility and appearance | The corresponding `src/features/<feature>.lua` |
| Built-in menu construction | `src/features/menu.lua`, then `src/game/menu_rows.lua` |
| Health/stamina and backpack gauges | `src/features/body.lua`, `src/features/pack.lua`, `src/game/gauge.lua` |
| Weapon display | `src/features/weapon_hud.lua`, `src/features/weapon_3d.lua`, `src/game/weapon_panel.lua` |
| Stratagem display and cooldowns | `src/features/stratagem*.lua`, `src/features/world_hud.lua` |
| Native value or structure field | `src/data/numbers.lua` and the owning game adapter |
| Native function descriptor | `src/data/calls.lua` |
| Addon discovery/hash | `src/core/archive.lua` |
| Addon contracts/lifecycle dispatch | `src/core/addons.lua` |
| Settings parsing or persistence | `src/core/settings.lua`, `src/core/settings_file.lua` |
| Runtime start/stop or update hook | `src/entry.lua`, `src/core/runtime.lua`, `src/addon.lua` |
| Feature construction or frame order | `src/product.lua` |

## Module conventions

Each file returns its public table and imports another module with `require("group.name")`. A new
`src/features/example.lua` is bundled automatically as `features.example`; there is no second source
manifest to maintain. Module filenames use lowercase letters, digits and underscores. `src/addon.lua`
is the special top-level LLL entry rather than an imported module.

Imports inside the generated bundle use a private cache and fall back to the loader's require for
LuaJIT's `ffi` and `bit` modules and external archive addons. Do not install modules into global
`package.loaded`: other mods share that namespace.

## Add or change a feature

1. Keep game-state reading in an existing game adapter when one already supplies the value. Keep
   rendering/visibility in the feature file. The native call boundary stays in `native.access`.
2. Create the feature in `Product.new` and wire its update, draw and cleanup at the relevant frame
   phase. Preserve ordering: equipment, native inputs, sampling and previews share state.
3. Add settings to `game.options`. Existing IDs are persistent keys in `hd2_hud_widgets.cfg`; renaming
   an ID requires a settings migration. Toggle choices use numeric indices starting at zero.
4. Maintain `src/data/uses.lua` for native values used by a module and `src/data/requires.lua` for its
   feature dependencies. `core.dependencies` uses these to turn off features with missing native data.
5. Add a focused regression for changed behavior, rebuild, then run `tools/check.py`.

Only constructor dependencies should make an entire feature unavailable. Keep optional sibling
features optional, and tolerate their absence in the coordinating code.

## Native code reuse

Use the existing `access.read` readers and `access.call.judge`, `.ui` or `.world` ports. Their routine
descriptors already cover engine projection, raycasts, projectile stepping, widgets, menus and game
tables. `native.channel` supplies guarded memory access and platform services. Keep memory reads
behind those guards: an address can fall on an unreadable protected page even in a running mission.

`game.flight`'s thrown-object simulation and `game.ability_script`/`game.x64`'s introspection have active
callers. They are not duplicate versions of the projectile native and cannot be deleted merely
because related native functions exist. A native replacement needs a matching contract and evidence
for its arguments, return values and lifetime.

The supplied binding values target build 26568081. Updating a function or offset needs new build
evidence; the original research tools and evidence remain under `builder/`. The immutable upstream
comparison intentionally fails if native binding data or existing settings/resource definitions change.
Review such a migration explicitly and update its baseline separately from a runtime refactor.

A game update is such a migration. `migrations/<old>-to-<new>.json` lists the old and the new value of
every number the update moved, plus the build pin and the numbers digest; `tests/test_bundle.lua`
accepts exactly those differences from the upstream bundle and fails on any other, and on a listed value
that is not at its recorded old or new value. The file is written by the port's asserted rewrite script
from its evidence map (see [PORT-26568081.md](PORT-26568081.md)), never by hand, and never to make a
check pass: the pin in `src/data/pin.lua` moves only after every value behind it has been remapped.
`src/data/patterns.lua` and the call heads in `src/data/calls.lua` are not build pins: a pinned build
uses the baked numbers and never scans, and any other build is refused.

## Debug a generated stack trace

The line map `lua/56e46a6dc1df0a13.map.json` records each module's `first_line`, `last_line` and source
file. For a line inside that span, the source line is `bundle_line - first_line + 1`. Editing the
generated bundle directly is temporary: rebuilding replaces it from `src/`.

Use a fresh output folder when rebuilding a package. Existing outputs are retained until you choose
to remove them, so a previous candidate remains available for comparison.
