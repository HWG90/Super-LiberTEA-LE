# HudPlusPlus — editable modular source

Refactored from [Super-LiberTEA-LE v1.0.3](https://github.com/HWG90/Super-LiberTEA-LE/tree/v1.0.3/sources/hudplusplus),
commit `33baf36bc136bfe8759de087864fa67ed37afd1d`. HD2 HUD Plus 0.2.9 was created by DDRK1ng;
the HudPlusPlus build-26251122 port is credited in [SOURCE.md](SOURCE.md). This work keeps those credits.

The original 10,610-line distribution bundle is now generated from named, formatted Lua files. Edit
[`src/`](src), then rebuild. The game still loads one archive addon, so runtime module loading does not
depend on loose files, disk paths or a new loader. The resource name, settings IDs and menu resource keys
are retained. The target is Linux/Proton with LLL's LuaJIT boot and Helldivers 2 build **26568081**; the
refactor itself was made and validated on 26251122, and [PORT-26568081.md](PORT-26568081.md) records the
move to the current build.

## Source layout

| Folder/file | Responsibility |
| --- | --- |
| `src/addon.lua` | LLL enable/disable entry |
| `src/entry.lua` | Open native access, settings, addons and the runtime |
| `src/product.lua` | Construct features and coordinate ordered frame phases |
| `src/core/` | Runtime hooks, settings, addon contracts, archive discovery and dependency checks |
| `src/features/` | Individual HUD features: squad, reticle, weapon display, trajectory, etc. |
| `src/game/` | Game-facing readers, UI, equipment and simulation adapters |
| `src/native/` | Guarded memory access, FFI calls, bytes and the optional signature resolver |
| `src/data/` | Build-specific addresses, call descriptors, fingerprints and availability metadata |
| `build/bundle.lua` | Private module loader template |
| `lua/` | Generated distribution bundle and source line map |
| `migrations/` | Reviewed old and new value of every native value a game update moved |
| `tools/` | Portable build, package and offline check commands |
| `builder/` | Original port research, evidence and address re-derivation tools |

See [EDITING.md](EDITING.md) for common changes and module contracts.

## Build and check

Run these commands from this folder. The commands also accept absolute paths from another directory.
Bundling and packaging need only Python 3. The offline checks also need LuaJIT and Git, or an original
release bundle supplied with `--upstream`.

```sh
python3 tools/build.py
python3 tools/build.py --check
python3 tools/check.py
```

`build.py` sorts module names and writes the same bytes for the same source. The adjacent `.map.json`
maps bundle line numbers back to named files. `--check` writes nothing and fails when the bundle or
map is outdated. `check.py` compares native data, settings and resource IDs to the recorded upstream
commit, compiles every module, loads the addon without enabling native access, and runs the focused
behavior and packaging regressions. Native values may differ from the upstream commit only where a file
in `migrations/` records the old and the new value. No check starts or modifies the game.

To check a source-only download without Git history:

```sh
python3 tools/check.py --upstream /path/to/original-v1.0.3/56e46a6dc1df0a13.lua
```

Formatting is optional and separate from building. `.stylua.toml` defines the style; the formatter used
for this refactor was StyLua 2.6.0. The generated bundle and original research tools are excluded.

## Build a candidate package

The repository's source folder does not contain the texture/material payloads. Supply an
existing **HudPlusPlus build-26251122 package** containing its manifest and archive companions:

```sh
python3 tools/package.py \
  --assets-from /path/to/HudPlusPlus-LuaJIT-26251122 \
  --bundle lua/56e46a6dc1df0a13.lua \
  --out out/HudPlusPlus-LuaJIT-26568081 \
  --guid 2100b4f4-9d02-5ed7-86a7-7450c344f661 \
  --line-map lua/56e46a6dc1df0a13.map.json
```

The output directory must be new. The command refuses a bundle that differs from current source,
replaces the HUD Lua resource, removes the old boot resource if present, and copies all other resource
payloads and companion assets unchanged. Without `--guid` it keeps the supplied manifest GUID; a
package for another game build sits beside the old one in Arsenal and takes its own (the port derives
it as UUID v5, DNS namespace, of `goose.hd2_hud_plus.luajit.<build>`). `--note FILE.json` stores a JSON
object in the receipt. A receipt records input/output hashes. It creates a candidate package;
installation is a separate step.

For runtime edits, use these tools. The historical `builder/.../build_port.py` rebuilds the old port
from its original inputs and local capture paths; it does not consume `src/`.

## Changes in this refactor

- Separated the bundle into lifecycle, settings, addon discovery, features, game adapters, native
  access and build metadata. Removed the `options` forwarding module, unused import and redundant
  module wrapper functions.
- Reused LuaJIT's built-in bit operations for archive hashing and 32-bit flags, retaining the original
  arithmetic fallback for inputs outside that range.
- Reused the call-colour pending table rather than allocating a replacement each update.
- Load the signature resolver only when a permitted fallback needs it. Supported-build startup and
  unsupported-build refusal leave it unloaded.
- Detach owned update/shutdown hooks on stop. Hooks beneath another mod's wrapper become inert while
  preserving that mod's call chain.
- Extracted dependency checks and documented frame phases without changing sampling order. Ground
  previews also tolerate an unavailable trajectory feature; its dependency edge is now explicit.
- Preserved the existing 181 native call descriptors and the guarded memory-read behavior. Active
  ability-script decoding, flight simulation and build validation remain because their callers use them.

Offline validation, the candidate package and subsequent user test are recorded in
[VALIDATION.md](VALIDATION.md). The installed refactor ran in-game; complete visual coverage and a
matched before/after frame-performance measurement remain to be recorded.
