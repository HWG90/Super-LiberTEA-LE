# Native camera helper remake

Native build and independent source review passed. The camera fixture passed54 groups, the pure correction fixture passed14 groups, and the production DLL ABI smoke passed. Installation and live acceptance are recorded separately; these checks do not establish a visually accepted result.

The starting point is the pre-pin 0.5.32 on-foot helper. The later persistent action/vehicle eye camera and independent raw-look integrator are removed. The earlier helper's normal on-foot fallback remains because it handles firearm gaps and camera handoffs.

The rebuilt native6 path forwards the original camera position pointer and bytes. It does not write the caller's quaternion scratch, apply camera-only bob or kick, or filter native look/recoil. The native rig, hands and weapon remain animated by the game. The fallback changes only a qualified normal4 camera's positional correction; it does not change bone transforms or rotate the view.

A fully qualified native6 parent reference is converted into the current body-root frame. A bounded, short positional correction can then follow fresh root movement during the return to the normal on-foot fallback. Ownership, registry generations, request identity, graph, action and parent-space checks remain required; invalid/retired data cannot seed a later owner. Queued callbacks from a retired generation cannot publish into a newly armed session.

Interpolation uses a high-resolution clock. Windows' coarse tick clock can have roughly10–16ms resolution, which is unsuitable as the blend phase at high refresh rates. This is a reason to use QPC, not proof of the user's reported jitter's cause. Sources: [Windows time](https://learn.microsoft.com/en-us/windows/win32/sysinfo/windows-time), [QueryPerformanceCounter](https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancecounter).

The performance work batches adjacent protected reads and avoids camera quaternion conversion/writes that the native6 path no longer needs. Synthetic tests measure the actual protected-read count, transferred bytes and callback timing. The fair comparison includes the old production presentation/kick configuration and the new qualified handoff history, rather than comparing a bare old passthrough with an active new policy. Wine fixture timing is not an in-game FPS measurement.

Existing configuration and saved placement files are not migrated or reset. Camera-only motion/kick preferences remain stored but are not applied by this path. Weapon motion controls, F8 placement, native ADS, effect suppression and aiming-marker preferences remain independent.

Zoom-dependent native input sensitivity is still unresolved. The removed raw-look integrator is not reintroduced to conceal that limitation. A separate upstream lens/depth design exists as offline research and is not enabled by this camera remake.

Live checks must include F11 off/on from a fresh launch, enter/release/reverse ADS while moving/firing, weapon swaps and reload, posture changes and normal action/vehicle handoff. Observe arms/weapon cohesion and placement as well as the view. A passing synthetic fixture or package hash cannot replace those checks.

Matched synthetic protected-read counts (calls / bytes per callback):

| Path | Pre-pin0.5.32 default | Rebuilt helper |
|---|---:|---:|
| Native first-person idle / ADS |57 /446B|64 /651B|
| Native first-person firing / kick decay |84 /662B|64 /651B|
| On-foot fallback |113 /779B|102 /1197B|

The final registry-header closing check accounts for one additional32-byte read per owner check. These final counts are derived from the measured source and that reviewed change; timing was not rerun for that last change. Idle/ADS reads increase to qualify fresh handoff history. Timing samples overlap, so no universal speedup is claimed. The normal Update also stops sending camera-only motion packets; saved values stay stored.
