# First-person renderer capability investigation

Target: the combined Goose Gadget Kit candidate for Steam build **26251122**. Investigation performed from local source, existing API captures and existing SDK bridges only. No game process was queried, no rendering property was changed and no new interception point was introduced.

## Result

The inspected surface supports the existing owned gameplay-camera FOV and near-plane policies, plus qualified per-mesh visibility/shadow-pass changes. It does **not yet establish a usable viewmodel-only projection, depth range or isolated render layer** for the native first-person arms and weapon.

That is a statement about the investigated evidence, not a claim that Helldivers 2's renderer has no such facility internally. The API inventory is historical and names alone cannot qualify a current native call. Generic render-target, shader-pass and post-projection APIs remain candidates for further investigation; they are not an implemented anti-clipping feature.

The implemented conservative path is therefore per-resource hip and normal-aim near clipping, independent of saved placement, with full native ADS forwarded unchanged. This can hide nearby armor/rig edges. It cannot make the weapon immune to walls or establish independent viewmodel/world FOV.

## Evidence and scope

The following current candidate sources were inspected:

- `native/near_clip/native_ads_near.cpp`, especially `observe`, `setter_hook`, `api_slot` and the binary contract.
- `native/first_person/native_ads_fov.cpp`, especially `source`, `binary_contract`, owned camera/request binding and the existing FOV setter policy.
- `native/first_person/native_ads_camera.cpp`, especially the documented `CameraAPI+0x28` quaternion consumption, `direct_camera_parent`, `remember_native` and the native6 exact-forward branch. The former camera-pin implementation is retired and is not an available rendering facility.
- `native/first_person/native_ads_editor.cpp` / `.h`, `src/first_person/pose.lua` and `src/first_person/backend.lua` pose configuration. These describe a common native rig transform; they expose no admitted renderer-layer or per-mesh projection configuration.
- `src/first_person/head_visibility.lua`, especially SDK binding qualification, explicit `default` / `shadow_caster` contexts and pass-mask ownership/restoration.
- `src/first_person/model_shadow_source.lua`, which inventories native FPS arms/clothing, gun and linked children with world, parent and generation checks.
- `src/first_person/menu.lua`, whose per-weapon clipping profiles resolve into the existing near-clip policy.
- `docs/first-person-upstream-TECHNICAL.md` and the migrated native-map documents as historical provenance. Their old addresses/build labels are not treated as current qualification.

Existing external captures and bridges inspected:

| Artifact | Evidence it provides | Limit |
|---|---|---|
| `/home/goose/Documents/ChatGPT/Linux HD2/native-work/native-bindings-live.tsv` | 1,874 named binding records; Camera, Viewport, Renderer, Mesh, Material and RenderDataComponent surfaces | Historical capture without a current-build identity proof in the TSV; some records explicitly report a non-executable binding |
| `/home/goose/Documents/ChatGPT/Linux HD2/native-work/war-journalist-live-bindings.tsv` | Same binding inventory | Byte-identical to the preceding TSV; this is not independent corroboration |
| `/home/goose/Projects/Super-LiberTEA-LE/sources/live-lua-loader/sdk/hd2se/src/stingray_bridge.lua` | A guarded world/entity/resource/position observation bridge | Its adapter does not expose first-person render-layer or projection controls |
| `/home/goose/Projects/Super-LiberTEA-LE/sources/war-journalist-proton/freecam/windows_lens.lua` | Existing bounded observation of an application's render submission to find its camera shading environment | This is not a verified model-only draw pass; merely wrapping the render submission does not isolate arms/weapon geometry |
| `/home/goose/Projects/Super-LiberTEA-LE/sources/war-journalist-proton/freecam/engine_scene_resources.lua` | Qualified stock `linear_depth` and `output_target` resources for a scene overlay | Existing full-scene resources are not a dedicated first-person depth/color surface |
| `/home/goose/Documents/Codex/2026-11-07/tr/work/true-fp-vignette-sdk-readonly.lua.result.log` | Prior build26251122 `RenderDataComponent` vignette-class observations | The script inventories a particular environment component; it is not an exhaustive renderer-property registry inventory |

Both historical TSV inventories have SHA-256 `0a4a334b1a4df2b4d8aa976dc5be455833ec28955c350eb723b33bd1e9e1575e` (208,732 bytes). They are used to locate candidate API names, not to authorize calls or reuse their native addresses.

## What is verified by the current implementation

### Camera FOV is an owned camera-lens operation

The current FOV contract qualifies build26251122's setter/getter and the expected `CameraAPI+0x80` call. The setter stores the camera's FOV; `source` reads the current game FOV setting. Calls are filtered by the owned camera, request and local player, and full native ADS has its own pass-through/transition handling.

This establishes control over the presented gameplay camera's lens. It does not establish a separate projection matrix selected only for arms or gun meshes. The native rig's presentation-distance calculations and common placement transforms are also distinct from a model-only renderer projection.

### Near clipping changes the gameplay camera's near plane

The near helper qualifies the current setter at EXE `0x2DCFA0`, getter, dispatch slot `CameraAPI+0x68` and the game's exact `0.05` constant. Its callback only replaces an exact game-origin native-near submission to the owned camera when the first-person kind-6 request is current. Normal aim can use an independent configured distance. `View::ADS` forwards the native value unchanged; unrelated callers, values and cameras are preserved.

The effect is camera-wide clipping close to the eye. It is not collision detection, depth-test disablement, or an arms-only near plane. Raising it can cut hands or sights, which is why the settings are bounded, per weapon/stance and native ADS remains native.

### Mesh visibility and shadow contexts are qualified

`head_visibility.lua` verifies the SDK setter, native context hashes and pass-mask layout before using `Unit.set_mesh_visibility`. Only the `default` and `shadow_caster` contexts used by the existing feature are qualified. It preserves other mask bits and restores only changes it still owns. The model-shadow source proves the FPS rig and linked model parents; it does not detach or move them.

These facilities can hide local head/armor pieces and prevent FPS models casting world shadows while preserving the body representation. No qualification in these sources proves that an arbitrary named pass can supply a separate first-person projection or clear depth before drawing those models.

## Candidate APIs that remain unproven

The historical capture contains **31 Camera**, **6 Viewport**, **9 Renderer** and **22 Mesh** binding names. It contains no binding name with `viewmodel`, `first_person` or `firstperson`. That absence only describes the names captured, not unnamed engine internals or generic component properties.

| Candidate | Why it could be relevant | Why it is not sufficient evidence |
|---|---|---|
| `Camera.set_post_projection_transform`, `Camera.set_projection_type`, `Camera.set_frustum[_half_angles]` | Explicit camera projection manipulation | They target a camera. No inspected source proves a projection selected only for the native viewmodel while the world uses the same gameplay camera |
| `Mesh.set_explicit_sort_value` | Draw ordering | Draw order alone does not prove a separate depth buffer, disabled world occlusion or independent FOV |
| `Mesh.set_shader_pass_flag`, `Material.set_shader_pass_flag` | Per-object/per-material pass selection | The relevant pass names, semantics, current-build call contract and restoration behavior are unqualified. Toggling guessed flags would be unsafe and may affect world/shadow rendering |
| `Application.create_render_target`, `Application.render_world`, `Viewport.register_render_resource`, `Viewport.set_output_render_target` | Potential building blocks for a second render surface | The captures do not prove mesh isolation, native FPS animation ownership, output composition order, appropriate depth semantics or a safe gameplay integration lifecycle |
| `RenderDataComponent.get_property` / `.set_property` | Generic renderer component data | No captured component schema identifies an admitted first-person primitive/projection property. The proven vignette class is unrelated |

`Application.render_config` and `World.set_shader_pass_flag` explicitly fail executable-binding qualification in that old inventory. Their names are not permission to call them.

## Safe next steps if dedicated rendering is pursued

1. Inventory current-build names and component/resource metadata read-only under the existing qualified Update boundary; preserve a current executable/game identity with the capture. Never invoke a setter solely because its name appears in a table.
2. Inspect the stock renderer/viewport configuration and FPS unit/material metadata offline for an existing first-person pass or projection parameter. A generic render target is insufficient: prove which meshes it renders and where it composites into the gameplay view.
3. Require an explicit owner-local API or existing writable data contract that can change only the first-person representation, preserve the native rig/attachments and restore on camera/weapon/world replacement. If that cannot be proved without a new inline hook or individual-bone distortion, do not enable the feature under this task's constraints.
4. Before integration, prove independent world/viewmodel FOV and near-plane behavior, world-wall occlusion semantics, muzzle/optic integrity, body shadows, weapon swaps, native ADS, Photo ownership and cleanup. Synthetic API tests alone cannot establish the visual result.

Until those proofs exist, keep the implemented per-weapon clipping settings and common native-rig placement. No fake independent-FOV or depth-layer switch is added to the menu, and no universal anti-clipping claim is made.
