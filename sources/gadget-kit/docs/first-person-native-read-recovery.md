# Qualified native owner-read recovery

This update keeps the accepted0.5.38 camera, native animations and steady visibility/phase optimizations. It changes how camera, FOV and scoped-blur helpers report qualified owner-data read failures, and how their Lua managers preserve those causes through cleanup. No native camera pin, independent look integration, new hook or ABI is introduced.

## Fault boundary

Previously the core helpers declared native error3 but never emitted it. Actual owner reads which failed were reported as an ownership mismatch, so the typed temporary-read retry branch was unreachable. Camera also treated a disarmed read-fault callback as an ordinary waiting state, bypassing retry pacing. FOV could publish a phase before polling health, replacing callback error3 with a control-call rejection. Cleanup could replace the causal read error with its own pending-End code.

Each native helper now scopes read-fault evidence to one invocation of its owner-data guard. A failed or short ReadProcessMemory operation is classified as3 only if a failure-only VirtualQuery confirms the complete attempted span is committed and readable. Invalid numeric bounds, invalid pointer values, unreadable/unmapped/guarded pages and readable-but-mismatched owner data remain unsafe. Code, source, configuration, graph, dispatch and diagnostic reads outside this owner guard do not acquire retry authority. The scope is cleared on return and restored across nesting. Successful reads perform no mapping query.

The native callback still disarms on failed ownership and forwards the supplied native data. Any owned reservation remains only for cleanup until End acknowledges it. No stale data, camera quaternion, model transform or slot is replayed to recover a failed read.

## Lua ordering and lifecycle

The managers preserve the fresh numeric callback/Begin cause before End can replace the helper's last operation error. FOV reads and classifies health before publishing a transition or rebinding an existing handle. A genuine3 reaches the bounded recovery ledger; cleanup remains owned while pending. A retry requires acknowledged cleanup, backoff, an owned Update and a fresh safe same-player proof with no foreign camera owner. Unknown core faults are fatal; unknown optional faults remain unavailable for the explicit session.

Known acknowledged owner/profile retirement is a distinct existing lifecycle path: camera error0/known owner7, the waiting FOV owner-retirement path, and scoped-blur retirement7/8 may release their old generation while manual intent waits. They grant no authority to write through an old handle. A later arm still requires a completely fresh current configuration and the native ownership/graph/dispatch guards. This exception must not be described as permission to retry arbitrary ownership, signature or unknown faults.

## Verification and limits

Native fixtures cause real OS reads to fail on private allocated buffers, then exercise the real exported Validate/Begin and callback/statistics paths. They check transient3, permanent/unmapped/invalid/semantic/code/source/dispatch/token negatives, full-span page boundaries, post-original-call rollback, exact native forwarding, retained cleanup ownership and nonsticky error reporting. Production DLL smoke checks the real binary ABIs and unsafe failures independently of the fixture build.

A separate-process bridge feeds the captured native callback health into the actual Lua5.1/CFFI adapters and managers, then through the real recovery ledger. Its clean and pending-End cases verify cleanup acknowledgement, pacing, refusal of a changed-player proof and later rearm. The native executable and Lua VM are separate processes; this is a numeric error-contract integration check, not live game fault injection.

The healthy camera comparison retains64 protected reads/651bytes for native6 and102/1197bytes for normal4 in both38 and this candidate, with zero failure-classification mapping queries on success. TLS/local fault bookkeeping remains. This does not establish unchanged game FPS; a fresh same-scene live comparison is still required after installation.

Native zoom-dependent input sensitivity remains unresolved. Existing rendered lens and viewmodel depth adjustments are not a verified input-sensitivity fix. The dedicated viewmodel projection/depth-layer investigation remains unqualified; per-resource near clipping continues to affect the gameplay camera's near plane.
