# True First Person 0.5.39 — live acceptance

Status: **0.5.39 live acceptance pending**. The user accepted0.5.38: FPS drop gone, natural motion, and F8 arms/gun-only preview plus cancel working.0.5.39 restores F8's original appearance and changes read-fault recovery/visibility ownership. Native camera and animation math stay unchanged; the fresh helper build still needs visual and FPS regression checks.

Camera pinning is retired: the native game camera and look input are authoritative. First Person does not force an eye camera through actions or vehicles.

F11 toggles True First Person. Preserve existing placement and motion preferences initially; test optional defaults/presets separately. Native ADS checks require the First Person → native ADS option. Record its prior value and restore it afterward if testing changes it.

| Sequence | Required result | Evidence |
|---|---|---|
| Same-scene F11 off/on, profiling off | No material mod-induced frame-time loss; preserve natural motion | 0.5.36:107/85FPS;0.5.38 user reports drop gone;0.5.39 pending |
| Enter/release ADS, reverse halfway, repeat while firing, then reload | Continuous weapon/view/FOV handoff; native recoil/reload and grip remain intact | Pending user observation + bounded diagnostics |
| Change supported zoom selections repeatedly, including during ADS handoff | No placement restart or unexpected view switch; separately measure zoom-dependent native sensitivity (unresolved) | Pending |
| Primary → secondary → support → back | Correct saved/default placement; no old-weapon delta or drifting attachments | Pending |
| Sprint → aim; dive → stand; crouch/prone | Native animation remains natural; vertical look remains available | Pending |
| Enter/exit a vehicle and use an interaction | Native action/vehicle camera is allowed; no mod-forced rotation, shoulder stretch or stale camera owner after returning | Pending |
| Open/close F8, edit preview, cancel and save | Cursor owns look while editing; natural animation persists; cancel restores saved placement; save affects only the chosen target | Pending |
| Comfort/Natural/Custom and family-default option | Presets are usable; Custom restores the original slider choices; saved weapon/global placements keep priority | Pending |
| Per-weapon hip/normal-aim clipping, then native ADS | Chosen weapon clearance applies, other weapons retain theirs, native sights/hands are not cut by custom clipping | Pending |
| Respawn, changed player/world, Photo Mode | Old owners retire; deliberate Photo handoff; safe automatic return without stale writes | Pending |
| Frame hitch / low and high rates | No accumulated look, transition oscillation or persistent stuck view | Frame-rate/hitch math fixtures passed; live observation pending |

Read-only diagnostics: `NativeADSCameraTest.diagnostics()` and `.recovery_status()`. The history is bounded to720 rows and stores copied scalar state, never live SDK handles or native cdata. Independent look is removed. The positional fallback helper has no shared transition epoch. FOV/pose epoch fields report acknowledged publication, not proof of simultaneous render consumption. A difference can identify a handoff worth inspecting; it is not by itself a visible bug.

For a genuine native read error, verify cleanup is acknowledged before paced retries and fresh same-player authorization. Unknown/build/signature faults never grant retry authority. Known acknowledged owner/profile retirement follows the separate lifecycle path documented in `first-person-native-read-recovery.md`; it does not authorize writes through an old handle. After the finite retry allowance, the affected capability remains suspended/unavailable until an explicit off/on session; user look is never smoothed to hide an error.

A completed record should identify the weapon, action sequence, whether native ADS was enabled, observed outcome, diagnostic counters and any follow-up. Do not mark this matrix accepted solely from a package hash or synthetic test.
