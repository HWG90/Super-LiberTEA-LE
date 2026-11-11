# Current performance acceptance — 0.5.39

The user accepted0.5.38 after a same-scene F11 comparison: **FPS drop is gone; motion natural**. A read-only active runtime check confirmed the expected helper identities and2641steady/23full Head observations without a model-shadow error. F8 arms/gun-only preview and cancel were also accepted. No temporary profiler is attached.

0.5.39 retains the steady visibility/phase optimizations and native animation/camera math. Its camera read-fault correction preserves the measured healthy64reads/651bytes native6 and102reads/1197bytes normal4, with no failure-only mapping query on success. This is an offline read-count comparison; fresh0.5.39 FPS/motion regression acceptance is still pending because native binaries change. FOV and scoped blur similarly query page mappings only after an actual owner-read failure.

The following historical report records the original evidence and0.5.38 path changes. Its pending labels describe that earlier preparation, not the later user acceptance above.

# First Person performance follow-up — 0.5.38

The user confirmed107 FPS with F11 off and85 FPS with it on in0.5.36, including after all temporary profiling was removed. That is about21% lower FPS, or2.42ms more time per frame. The natural camera and animation baseline remains accepted. The remaining slowdown is not marked resolved.

## Lua changes

The steady native6 visibility path observes current player ownership, flags, epoch, Unit registry generations, world, appearance, backpack, SDK bindings, every participating renderer resource and mesh membership, masks, kept clothing, weapon descriptor and complete cached parent/child/sibling endpoints. If these match the last fully qualified observation and no mesh requires a write, it returns without repeating full model snapshots and alignment walks. It closes its observation with fresh player, registry, appearance and generation checks. Any mismatch or unreadable data immediately takes the existing full path. That path retains per-row ownership and foreign-mask history and refreshes kept membership. Writes and cleanup still require the original current guards.

Shared transition publication sends only bounded scalars to an exactly owned helper handle during the qualified Update. It no longer repeats the game's full snapshot and rig walk solely to publish private phase state. Native callbacks retain fresh graph/dispatch/owner guards; actual Lua motion writes retain their own current proof. Identical packets are coalesced only within the same Update, lease, alignment, helper and handle. Any changed action or phase republishes; every new Update refreshes the expiring heartbeat. Failed or throwing publications are never cached.

## Offline evidence and limits

Across100 steady source-backed visibility fixture frames, full model snapshots change200→0 and alignment-context walks1200→0, with zero SDK writes in both versions. Total player plus full snapshot calls change300→200; two fresh player observations per new steady frame remain. The byte fixture mocks the internal full snapshot/alignment chains, so its raw callback read count is not a production timing comparison.68 Head cases cover topology, appearance, backpack, mesh/mask/ownership changes, foreign-mask history and cleanup.

The matched controller phase/motion publication fixture changes3→1 full snapshots,3→1 rig walks,187→77 protected reads and2→1 native phase publications.16 focused transition cases cover ownership, changed phases, lease generations, frame boundaries and failed publications. These are bounded path comparisons, not a whole-frame speedup or live FPS result.

All native helper files and source hashes match0.5.36. No hook, ABI, camera pin, input integration, animation, placement or settings change is introduced. Full Lua/CFFI, menu/hotkey, syntax, closure and package checks are recorded separately. Live acceptance requires a clean restart and a same-scene F11 off/on comparison without profiling, plus walking, firing, reloading and ADS.

## Previous0.5.36 work

# First Person performance correction — 0.5.36

The0.5.35 camera/rig was reported natural and stable, followed by a serious FPS loss only with F11 enabled. This update retains that camera and rig and addresses measured Lua work and a separate native animation-lock issue. It does not reintroduce camera pinning, independent look or another hook.

## Live baseline

A four-second, automatically restored instrumented0.5.35 capture recorded389 Updates:

- First Person Lua Update:3.55ms mean; timings include instrumentation overhead.
- Full backend snapshots:15.37 per Update,130.8us average inclusive time.
- Backend protected reads:2477 per Update.
- Head visibility Update:about1.00ms; motion0.53ms; controller0.41ms.
- Existing native camera profile:400 samples,12.4us mean/23us p99, including the original setter and excluding lock waiting.

Nested timings overlap and must not be summed. The capture identifies CPU work; it is not a GPU or whole-frame profiler. Profiling wrappers were restored and no saved settings were changed.

## Changes

Healthy recovery previously created a fresh full snapshot before asking whether a retry existed. It repeated that for every healthy policy and also sampled an empty outer recovery ledger. The new predicates inspect only recovery state. A fresh proof still runs for a genuine retry and for failure classification. Actual controller/policy write guards are retained. Old-owner recovery state comes from the already acquired origin or existing presentation observer; an old pointer is never granted mutation authority.

The native branch-rotation SDK hook previously took the FP policy lock before filtering unit and node, holding it through unrelated engine calls. Other actors and bones now forward directly without that lock. The actual FPS branch still checks the captured generation under the lock; foreign writers invalidate its older restoration cache, and End drains owned work. The existing interception slots and ABI remain unchanged.

Head visibility uses constant-time operations for its known byte masks1/2 instead of32 interpreted bit-loop iterations per operation. All256 native masks are checked through hide/restore. A short live arithmetic comparison did not isolate a timing improvement, so this is bounded CPU cleanup rather than a claimed FPS gain. Discovery, attachment, generation and write/readback checks stay unchanged.

## Verification and limits

The real Update orchestrator's100-frame A/B fixture reduces recovery/presentation full snapshots from800 to100, preserving100 controller and500 policy Updates. Pending cleanup, changed owners, later-frame restart, stale proofs and actual retry revalidation remain covered.

The editor fixture passes96 native groups and actual production DLL ABI smoke. Concurrent tests prove unrelated rotations can forward while an owned original setter is blocked, while owned cleanup still waits. An8-worker synthetic400000-call comparison reduces foreign lock acquisitions from400000 to0; two zero-work-original timing rounds changed from71.3–71.8ms to6.1–6.4ms. This demonstrates lock isolation, not an in-game FPS multiplier.

All Lua/CFFI, shared-menu/hotkey, syntax and package checks are recorded in the release validation. Live acceptance must compare the same scene with F11 off and on, including ordinary native ADS with F11 off. The optimized live FPS result remains pending until that check.
