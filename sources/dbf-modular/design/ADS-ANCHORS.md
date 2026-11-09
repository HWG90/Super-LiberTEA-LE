# ADS and anchor motion

Current behavior requested by the user:
- Hipfire ammo/options follow the proven head attachment; vitals follow that player attachment.
- Third-person aim moves ammo/options to the current weapon bone.
- First-person aim puts vitals left and ammo right of the current sight line.
- Cooldowns follow the selected health/ammo side, defaulting to health.
- Anchor dampening is adjustable0–300ms, default80ms;0 follows immediately.

The FPS handle comes from the validated avatar controller+0x10c0. Resolve the semantic weapon
attachment hash0x4FDD3337 through the already witnessed Unit.node API. Require the native camera's
current kind6 request to match the current actor, wielded weapon and body engine handle, and recheck
controller/FPS field, queue/request bytes, actor, wield, HUD context and camera through final projection.
The existing raw native first-person bit remains unchanged. A separately proven viewmodel_active
annotation supports custom TrueFPV cameras while aiming; camera6 without aiming retains hip policy.
Ordinary third-person kind4 aim continues the body/gun path without depending on an FPS rig.

The rig attachment pivot can lie outside the screen even when its mesh extends into view. An explicit
editable calibration0.5 model units forward along its own basis supplies the UI attachment point.
This is a projected bone-local point, not a mesh silhouette or bounds claim. Current live evidence in
LIVE-FPS-CALIBRATED-dev.6 confirms the exact FPS handle/node/current camera owners and an in-viewport
projection. No camera/FOV change, render-pose write, world-unit scan or new native ABI is introduced.

A reused Tracker filters validated screen XY once per role per frame with1-exp(-dt/tau), before
viewport/reticle clamping. Its only history is screen scalars and identity tokens. Stable actor/wield
identity blends head-to-gun-to-FPS transitions; changed global owner, camera, context, viewport,
attachment or current weapon resets history. Unknown/fallback positions snap and clear that role.
Quiet hidden roles keep current history. Readouts, warning detection, visibility and native timers
are not damped. Reticle/Beside screen anchoring remains intentional and bypasses model damping.

Cooldown icons and labels consume the same selected-side anchor. Retained label updates keep their
GUI/font/primitive IDs during movement; destructive changes still require native restoration first.
A moving layout must not postpone the native250ms timer deadline: only an actual tick advances it.
Cached native children are explicitly shown again when the whole row returns after Quiet aiming.

The latest FP layout follows the sights rather than the lower weapon attachment. The current
reticle/crosshair-root center is the sight reference; a hidden ADS crosshair explicitly falls back to
known viewport center. Keep the same validated FPS classification and hip/TP bone paths. Ammo aligns
using its current measured ink center and vitals using the health-track center. Filter that primary
reference position once, derive group origins from its local center, then clamp complete bounds.
Current font measurements and stable virtual references cover Quiet-hidden cells; retained old slot
content is never an alignment source. Reserve/options/cooldowns hang below the chosen primary row.
Existing user offsets remain additive and are not rewritten by this layout update.

Adaptive first-person clearance uses conservative current weapon-family bounds, including attached
optics, rather than treating the 1x1 crosshair root or zoom label as optic dimensions. The optional
read-only collector proves current Unit generations, world and bounded parent/child links before
copying visible mesh bounds, projects copied corners with the current camera, and retires the result
on any ownership, camera, graph or read-budget failure. Main HUD sampling and input continue when
this optional geometry is unknown. A roomier minimum gap is the explicit fallback.

The measured physical-pixel exclusion is padded by HUD-scaled spacing and applied to the current
measured inner edges of each complete role. It grows outward immediately when needed for clearance;
inward movement uses the existing dampening. Resolution and HUD scale are applied once. No mesh
silhouette or exact optic-aperture claim is made: the exclusion conservatively encloses the visible
weapon family at sight height. Original option strips and selected-side cooldowns follow their role.

The HUD requests adaptive sight clearance explicitly. On these FP frames the aiming point comes
from the reticle, so the unconsumed FPS-bone screen projection is omitted. Current camera-request,
controller, FPS handle, actor and wield proofs remain, and final full owner/tree guards still
authorize publication. The direct diagnostic sampling path may still project that bone. Hip and
third-person model anchors retain their existing projection. All three FP anchor choices may
measure the optic; screen choices keep hip/TP bone sampling disabled.

Refined sight clearance retains each complete projected OBB as its own eight-point polygon. The
layout computes a conservative convex hull, intersects it with the configured sight-height band,
then combines only occupied horizontal spans. Lower gun/stock extents cannot widen the aperture
merely because they lie in a global rectangular union. Every corner and Unit must still be current;
clipped geometry stays unknown. A separately labeled layout fallback may hold the last measured
insets within the same FP owner and viewport to avoid spacing jitter, without claiming current
geometry or retaining a world pose.
