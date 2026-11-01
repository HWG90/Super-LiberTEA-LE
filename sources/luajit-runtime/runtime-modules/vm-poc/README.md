# LuaEnvironment replacement core: standalone proof

2026-10-24, build 26088801. This proof loads **all nine distinct stock Lua chunks
found across 3,522 bundled primary archives** and runs **LLL Poll Cache 0.1.3 unchanged**, using
one LuaJIT state on the creating thread. The mod's actual functions produce
machine-code traces. There is no worker VM, worker API, or rewritten mod routine.

**The game's LuaEnvironment has not been replaced in a running game.** This is
the implemented replacement core and an executable integration fixture. The
native backend is a C fixture. Steam and Friends/Presence adapters are implemented,
and seven SteamVoip room/client bindings are ported as a partial adapter;
their original comparisons used service fixtures. Later live probes now cover four
real Steam callbacks, a mounted stock module and the native Vector2 binding.
No game files or running game process were changed by the standalone harnesses.
Native Windows is untested; the Win64
results below are under Wine. A subsequent [live loader test](../live-load/2026-10-24/README.md)
loaded this FR1 DLL inside the game, where state creation failed because the
required low-address allocation was unavailable. A separate GC64 diagnostic
candidate executed real JIT code on the game thread and closed cleanly. That
temporary-state test does not establish replacement of the game's main VM.

The [native Vector2 live proof](../live-load/2026-10-24/LIVE-VECTOR2-VALIDATION.json)
compares 82 results with the original callbacks inside Helldivers 2 under Proton.
All 26 exposed functions, basic operators, metadata and component access are
ported in `vector2.inc`, using the engine's real temporary allocator and float
formatter through `engine_vectors.c`. A LuaJIT-created vector was read and changed
by the original engine callback, then read back by LuaJIT. The state closed and
the exact native pool cursor was restored. This does not complete the core
registrar: boxes, other vector/userdata bindings and startup wiring remain.
Named element access rejects out-of-range indexes instead of copying the
original unchecked memory access.

The [native temporary-pool proof](../live-load/2026-10-24/LIVE-TEMP-VALIDATION.json)
adds replacement Script checkpoints and cleanup before the frame adapter calls
update/render. Actual game checks covered cursor rewind/reuse, four update/render
pairs, GC preserving native values, original constructors for four native types,
ring wrap and refusal of unknown tags without mutation. All borrowed bytes and
metadata were restored. These were manual calls to frame targets in the game;
no routes were patched. Checkpoint writes reject unaligned or out-of-range
counts rather than reproduce unchecked native cursor corruption.

The subsequent [overflow live proof](../live-load/2026-10-24/LIVE-OVERFLOW-VALIDATION.json)
validated two real native pages allocated by replacement Vector2 callbacks under
controlled pressure. The checked original native cleanup helper releases pages;
the pointer array remains owned by the environment, as in the original. The
probe then released its newly created array and verified current outstanding
allocation count and bytes returned exactly to zero. All borrowed ring bytes
and metadata were restored. The same candidate passed Vector2 parity and inline
lifetime checks, including a terminal wrap marker. This is actual allocator
integration, not a full workload/performance test or installed VM replacement.

The [Vector3 live proof](../live-load/2026-10-24/LIVE-VECTOR3-VALIDATION.json)
adds all 42 exposed functions in `vector3.inc`, with the real 16-byte native
layout and allocator. Call `hd2env_register_vector3` after the Vector2 host/pool
registration. Both types share the same lightuserdata registry metatable;
operators dispatch by native tag. The 136 Vector3 observations and 82 Vector2
regressions matched the running game, including original callback read/write
round trips. Five update/render pairs verified Vector3 expiration and exact
borrowed-pool restoration. Vector3Box and the other type families remain.
Scalar `tostring` formatting differs between the two runtimes; comparison labels
use explicit formatting, and runtime-wide string-conversion parity is not claimed.

## Implemented boundary

[environment.c](environment.c) owns state creation, library registration,
resource loading, protected calls, callback registration, and destruction
through the public Lua API. It exposes an opaque environment through
[environment.h](environment.h). Its LuaJIT instance is private to the library;
no PUC state, TValue, closure, registry index, or callback is reused.

The following are functional replacements in the standalone host, **not
installed detours or ABI-compatible substitutes for the original C++ methods**:

| Traced engine path, EXE RVA | Implemented replacement |
| --- | --- |
| Constructor `0x4ed280`, state creation `0x4ed3a2` | `hd2env_create`, `luaL_newstate` |
| Setup `0x4ec740`, loader insertion `0x4ec410` | `initialize`, public API registration, loader slot 2 |
| Resource loaders `0x4eb970`, `0x4ede40` | `resource_loader`, `resource_dofile`, backend resource resolution and exact-byte source translation |
| Named call `0x4f0450`, protection `0x4ee5e0` | `hd2env_require`, `hd2env_call`, typed `hd2env_invoke`, `lua_cpcall` |
| Syntax-only string check `0x4ed600` | `hd2env_check`, compilation without execution |
| Teardown `0x4ed570` | `hd2env_destroy`, `lua_close` with backend still alive |

Same-thread ownership, balanced stacks after errors, preserved Lua table
identity, stable fixture userdata across garbage collection, coroutine calls,
and teardown callbacks are exercised. Reentrant host entries and access from
another thread are refused. This policy still needs auditing against real
engine callback recursion. Assets and backend context must outlive the state.

`hd2env_invoke` passes nil, boolean, number, byte strings, and opaque native
pointer values without exposing Lua stack internals. It preserves trailing nils;
result strings are copied and released by `hd2env_results_free`, and remain valid
after GC or destruction of the environment. Tests cover partial-copy cleanup,
unsupported results, argument/result limits, missing callbacks, non-string Lua
errors, and subsequent recovery. The owned-value API below carries tables,
closures and full userdata. Both APIs execute synchronously in the same VM.

The additional trace finds compile/eval entry points `0x4ed640` and `0x4ed710`
returning an engine LuaObject containing a state pointer, stack index, and error
flag. Original consumers cannot use that representation with this core. They
still need routing to the new ownership/access APIs before any detour is valid.
The protected wrapper also maintains a thread-local current-object pointer and
calls a native error reporter expecting the old object. That TLS/reporting path
must be adapted too. Six entry contracts and nine call witnesses are recorded in
[native-entry-contracts.json](../vm-trace/native-entry-contracts.json).

## Owned values for native callers

[objects.inc](objects.inc), compiled into the environment library, implements
`hd2env_object_*`. Native callers can compile and retain functions, call them
with retained arguments, inspect/index tables, preserve actual Lua error objects,
clone ownership, and release it. Tables, functions, userdata, cdata, threads and
nil retain their Lua identity. Handles contain an environment identity and a
monotonic object identity; they expose no VM pointers or registry indexes.
Released identities cannot be revived by reuse of registry slots, and foreign
environment identities are refused. The API honors Lua's own stack limits;
65-argument and 65-result cases are covered.

Owned results must be released on the creating thread, or are reclaimed when
the environment is destroyed. A result array can then be disposed with a null
environment. A bitwise handle copy borrows its ownership; use `object_clone` for
an independent lifetime. Primitive values can be copied out with `object_read`.
Indexing honors Lua metamethods, and failed operations restore the host stack.

[OBJECT-VALIDATION.json](dist/OBJECT-VALIDATION.json) records functional tests
against the actual shared Linux/Win64 libraries and the PUC reference, including
the existing native userdata/C-function adapters and stock bytecode translation.
Separate fault harnesses run 400 cases per runtime, failing both C bookkeeping
allocations and Lua allocations during initialization and calls. Partial results
roll back without losing existing ownership. A pre-created rollback closure
avoids allocating another closure while handling memory exhaustion. The Linux
fault harness also passes AddressSanitizer, UndefinedBehaviorSanitizer and leak
detection; the linked LuaJIT library itself is not sanitizer-instrumented.

This supplies the core operations needed by native LuaObject consumers. The
original engine's LuaObject consumers and error reporting still require
adaptation; the 16-byte opaque handle is not a drop-in engine LuaObject. The frame
caller sections below now have an independently tested replacement boundary.

The test harnesses dynamically load the actual produced Linux shared library
and Win64 DLL. The DLL contains LuaJIT; it does not need a separate `lua51.dll`
or CFFI. LuaJIT's standard libraries provide `bit`, `jit`, and `ffi` in this
replacement state. This does not add those capabilities to the existing game VM.

## Captured native update and render callers

[frame_routes.c](frame_routes.c) checks the complete pinned caller bytes and
plans replacements for the update section `0x6ce5c4..0x6ce66e` and render section
`0x6ce694..0x6ce6d0`. It replaces inline PUC stack operations and LuaObject argument
construction while preserving the original prologues, epilogues and surrounding
native hooks. The planner never writes an image or changes memory protections.
Any mismatching byte anywhere in either captured function refuses the plan.

[frames.inc](frames.inc) implements `hd2env_bind_frames` in the actual environment
library. It associates an opaque native environment address with its replacement
state on the creating thread and supplies Win64 GC/update/render entry points.
With native vectors registered, the address must match their owner and the
checked host invalidates that native pool before update/render. Otherwise it
remains opaque. Each update resolves the current global function, preserving mods' ability to wrap/replace it; the float argument
in XMM1 is promoted to a Lua number. Associations are removed at teardown.
Duplicate associations, cross-thread operations and recursive frame calls are
refused. Missing associations and recursion increment a per-thread diagnostic
counter. The embedding host must monitor it and restore routes before unloading
the library.

The collection callback is optional: NULL selects the captured timed scheduler
with replacement VM collection. An adapted error reporter is required.
Callbacks may call the public environment API; destruction and unbinding remain
refused until the frame callback returns. A reporter receives a copied diagnostic
string, **not** the original engine LuaObject or its TLS context. The original
timed PUC GC routine `0x5eb310` is replaced by the scheduler described below;
native settings and profiler wiring remain incomplete.

[frame_tests.c](frame_tests.c) executes the captured machine instructions in an
owned image with only the needed pages accessible. Both old state pointers target
an inaccessible page. All transitive native calls are controlled C stubs; the
original caller instructions invoke the replacement library's entry points
directly. Code pages are read/execute during execution, writable only for setup
and byte-for-byte restoration. This is not a live process patch or installer.

[FRAME-VALIDATION.json](dist/FRAME-VALIDATION.json) records 4,000 complete LLL
frames through these callers on Linux with the Win64 ABI and under Wine, with
unchanged Poll Cache producing attributable machine code. Focused tests cover
float promotion, optional native hooks, Lua errors and recovery, global function
replacement, association ownership/thread/lifetime, recursive entry refusal and
restoration. The PUC reference independently passes the focused caller tests.
Native Windows, original transitive helper behavior, exception unwinding across
the copied code, and live-game integration are not established.

The calling convention follows Microsoft's
[x64 ABI documentation](https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170).
Captured-byte provenance and the remaining integration limits are in
[frame-route-evidence.json](frame-route-evidence.json).

## Captured native construction and destruction

[lifecycle_routes.c](lifecycle_routes.c) plans replacement of the constructor's
VM-only section `0x4ed3a2..0x4ed54f` and the destructor's close call at
`0x4ed582..0x4ed58a`. Complete captured constructor/destructor bytes are guarded.
The constructor keeps the original native allocator initialization, resource
manager pointer, buffer metadata, GC configuration defaults and error-reporter
fields. PUC state creation and PUC-specific registry/library setup are replaced.
Both old state-pointer fields remain null; the replacement is found through the
external native-address association.

[lifecycle.inc](lifecycle.inc) provides a thread-local native factory configured
before construction. The host creates a fresh environment with the appropriate
assets/backend and supplies an error reporter and optional collection override. Ownership
then transfers to the bridge. Factory replacement/clearing and separate frame
unbinding are refused while a native-owned state exists. Creation failures invoke
a required host fatal handler and abort if that handler returns, so partially
initialized native objects cannot continue. No loader or hooks are installed by
configuring this factory.

The destructor preserves native temporary-buffer cleanup before Lua close,
then Lua finalizers, host backend-release notification, and native allocator
cleanup in that order. Host backend data stays alive through the finalizers.
The eight-byte close-site patch requires a rel32-reachable target; the local
fixture prepares a nearby leaf jump stub. A future installer must provide and
own that stub rather than assuming the DLL is within branch range.

[validate_lifecycle.py](validate_lifecycle.py) runs captured construction,
4,000 LLL frames, captured destruction, and a second construction/destruction
at the same native address. The second state runs one stock frame. It also
checks failure termination in a separate process, full-byte guards, resource
argument forwarding, native metadata, finalizer order and restoration.
This lifecycle fixture invokes stock boot and Lua shutdown through the core.
The separate captured-boot fixture below now covers the native boot caller;
the captured game-shutdown method is covered separately below.
Allocator, resource and engine backends remain fixtures. The factory is prepared
by the standalone executable, not by an early game loader.
The current Linux/Win64-under-Wine results and source/binary fingerprints are in
[LIFECYCLE-VALIDATION.json](dist/LIFECYCLE-VALIDATION.json).

## Captured native boot

[boot_routes.c](boot_routes.c) guards the complete `0x6cdd70..0x6ce57b` boot
function and plans 13 patches. Native allocator/global bookkeeping, API setup,
plugin initialization, and binary-config `boot_script` selection stay in the
captured routine. Direct PUC stack operations, eight registrar calls, config
assignment and require/init use replacement entries. The missing-key branch
passes an explicit null pointer rather than an uninitialized stack value.

[boot.inc](boot.inc) requires eight typed registration adapters, then configuration,
then boot-script require/init, in that order. Factories bind this policy before
returning a fresh state. Frames before completed initialization are refused;
missing, recursive or failed boot stages invoke the required native fatal handler.
Callbacks can use public core operations but cannot destroy their environment.
The Steam and Friends stages now call the registrar ports described below,
including their native context stores. The other six registration stages require
real adapters; their test bodies remain fixtures.

[boot_config.inc](boot_config.inc) reads the traced native dynamic-options layout
through a required bounded host reader. It skips deleted rows and unsupported
types, normalizes booleans, and narrows numbers from double to float to double,
as the original code does. Names follow the original C-string behavior; empty
names and duplicate assignments are preserved. Assignments honor Lua metamethods
and execute under protection. Limits are 1,048,576 rows and 65,535 bytes per name;
invalid reads, excessive lengths and Lua errors fail boot.

[validate_boot.py](validate_boot.py) executes the captured boot instructions in
an owned image using the actual shared library/DLL. Both old state fields stay
null. It checks register/stack argument forwarding including the six-argument
Network registrar, native setup, plugin ordering, configuration, stock require/init,
and complete-byte patch refusal/restoration. Then the same state loads assembled
LLL and unchanged Poll Cache for 4,000 captured frames. A second fresh state
boots with non-object options and runs one stock frame. Nine separate failure
cases verify rejection before returning to native boot.

[BOOT-VALIDATION.json](dist/BOOT-VALIDATION.json) records Linux, Wine and PUC
reference results. Native transitive helpers, underlying Steam interfaces, six other registrar
bodies and plugin bodies are fixtures. The config key and selected stock alias are fixture inputs, not proof
of the installed game's configuration. Real plugin VM APIs, native resources,
full callback parity and early loading remain unfinished; captured native shutdown is validated separately.
This planner is not installed in any game process.

## Stock scripts and unchanged mod

`prepare.py` fingerprints the installed EXE and game.dll, extracts nine stock
PUC chunks, and recovers source with pinned **unluac v1.2.3.569**, using
`--nodebug` for stripped chunks. LuaJIT compiles that recovered source. This is
not bytecode-header patching or direct execution of PUC bytecode in LuaJIT.

Two resource paths are verified against their game hashes. The others are
explicit test aliases, including `stock/boot`; they do not establish the real
boot-script selection. The complete archive census includes 3,522 bundled
primary archives, 111 installed loose archives, and 174 original mod archives,
with zero read/parse errors. Nine distinct stock chunks occur 11 times across
the bundles. See [runtime inventory](../vm-trace/runtime-inventory.json).

The three additional stock modules are editor/debug boot, vector-field global
direction, and reflection probes. Their top-level bodies load, and vector-field
world creation/destruction is exercised. Their complete engine-driven behavior
is not yet tested. The ordinary stock boot remains small; loading these modules
does not constitute a full game startup.

The reference executable instead runs the **original stock bytecode** in PUC
Lua 5.1.4, changing only its four-byte `size_t` encoding to the reference host's
eight-byte encoding. Both runtimes use the same fixture callbacks and scenarios.
All exercised assertions and native-call counts agree. Unexercised branches
are not proven equivalent by source recovery alone.

`load_compat.lua` is embedded into the environment library. Known stock PUC
chunks also work through `loadstring`, split-reader `load`, `loadfile`, and the
Lua file searcher used by `require`, including mode checks and custom environments.
Unknown PUC chunks are rejected. The backend's `read_resource` callback accepts
engine-framed version-1 bytecode and version-2 source resources, leaving mount
precedence with the engine. Tests show a source override wins over the cached
stock asset and invalid frames/mutated bytecode fail cleanly. No live engine
resolver is attached yet.

The installed Steam LLL boot is a separate 573,046-byte PUC wrapper. Its recovered
source does **not** compile, and it contains configured PUC CFFI/native-info
initializers. It is deliberately absent from the translation cache. A new
LuaJIT-aware bootstrap is assembled from LLL source instead. Assessment evidence is in
[INSTALLED-BOOT-ASSESSMENT.json](dist/INSTALLED-BOOT-ASSESSMENT.json).

## Full LLL bootstrap

[assemble_bootstrap.py](assemble_bootstrap.py) creates a factory from maintained
LLL sources without changing the shared checkout or mod files. It runs the stock
boot through the verified source cache, captures the actual LuaJIT libraries,
and executes the full LLL startup/update/shutdown chain. The host supplies an
LLL service configuration or a platform factory. It is not an archive that can
be installed into the current PUC VM.

The existing `jit_budget` policy uses public `jit.opt` controls. Old private
`jit_State` churn patches are excluded. The PUC CFFI initializer is absent; the
font resolver receives a LuaJIT FFI reader instead of loading the PUC native-info
helper. Under Wine, that reader successfully reads an owned buffer and refuses
an owned PAGE_NOACCESS allocation. The actual game font descriptor and live
service/UI paths remain untested.

[BOOTSTRAP-VALIDATION.json](dist/BOOTSTRAP-VALIDATION.json) records the complete
assembled loader running through the built shared library on Linux and under
Wine. Its 4,000 frame entries now use an owned function and owned argument.
The unchanged Poll Cache installs on the normal update chain, detects an
edit, produces attributable machine-code traces, supports the existing explicit
cleanup/reload path, and restores owned hooks on shutdown. Its unchanged
restart-only manifest still prevents enable toggles and automatic reload.
A small separate conformance fixture tests normal enable/disable/hot reload and
`require('ffi')`, `require('bit')`, and `require('jit')` inside a loaded mod.
The platform filesystem and engine inputs are fixtures; no game startup is
claimed by this test.

## Original LuaJIT bytecode compatibility

The original mod archives contain 73 distinct chunk bodies, including two
LuaJIT bytecode chunks using **FR1**, the older frame layout. The first GC64
prototype rejected both. A dedicated pinned runtime is now built with
`LUAJIT_DISABLE_GC64`, matching that layout without editing the original chunks.
All 73 original mod chunks and all nine recovered stock chunks compile under
this runtime on Linux and Win64 under Wine. The GC64 negative control still
rejects both binaries. This is syntax/bytecode acceptance; those original mod
chunks were not executed by the compatibility audit.

This matches the older VM's constrained GC-managed address space rather than
providing GC64's larger heap. New FR2-only binary modules still need source or
separate conversion. The new layout probe confirms this runtime remains
incompatible with PUC internals: LuaJIT's top/base/global-reference offsets are
`0x18/0x10/0x08`, compared with PUC's `0x10/0x18/0x20`. See
[layout-verification-fr1.json](../vm-trace/layout-verification-fr1.json) and
[COMPATIBILITY.json](dist/COMPATIBILITY.json).

LLL Poll Cache's five package files come directly from the existing LLL
`build_poll_cache.runtime_files()` builder. They are copied byte-for-byte and
checked again after testing. The proof uses the real LLL project loader,
manager, lifecycle, and catalog-watch dependency with an in-memory platform
fixture. It tests normal installation, fingerprinting, refresh deduplication,
change detection, and shutdown restoration. Fixture state and the scenario
driver are separate from the unchanged mod assets.

## Native callback adaptation

The C adapters cover the exercised Application, animation-curve, Wwise bank,
world, and event operations. Their fixture backend provides deterministic
results. Wwise's fixture handle representation is **not yet a verified engine
ABI**. Visualization, vector/rotation operations, and other Unit calls remain
unimplemented; their branches are not exercised.

The animation-curve adapter has additional current-build evidence:

- Original Lua closure thunk: EXE `0x3f38b0`, wrapper `0x3f32e0`.
- UnitRef is decoded from tagged lightuserdata with a right shift of two.
- String object/parameter names use the upper 32 bits of Murmur64.
- The independent native C API is `int(uint32_t unit, uint32_t object,
  uint32_t parameter, uint32_t index, float *out)` at `0x1f8390`.
- Its current UnitApi slot is **`0x430`** at table `0x28703e0`. The older SDK's
  field offset must not be used for this build.

[engine_curve.c](engine_curve.c) prepares only that binding. It checks readable
image regions, PE identity, the table pointer, and all 156 function bytes. A
captured matching image passes; 13 invalid-input/mutation cases are rejected.
The standalone Win64 executable is rejected without changing its backend.
These checks identify a candidate; they do not prove the validity of its live
engine context, transitive callees, or runtime behavior. No native game function
was called. Boxed Idstring arguments still need their own adapters.

## Captured native game shutdown

[shutdown_routes.c](shutdown_routes.c) guards the complete 1,019-byte game
destructor at `0x6cd470..0x6cd86b`, verified identical in both saved captures.
Three patches replace the named Lua shutdown call, inline PUC full collection,
and old collector threshold store. The native hook comparison between those
sections remains in place, with its condition flags intact. Plugin, handle,
service, global, buffer and allocator cleanup remains in the original caller.

[shutdown.inc](shutdown.inc) resolves the native environment through the existing
lifecycle association. It calls the current global `shutdown` and uses protected
`lua_gc(LUA_GCCOLLECT)` directly. It never reads the old PUC state or delegates
collection to a modifiable Lua global. Once shutdown starts, native frames and
repeated/out-of-order shutdown entries are refused. Lua callback errors are
reported and collection still runs. Propagated collector errors stop through
the factory fatal handler before native services are torn down.

The pinned LuaJIT catches finalizer errors and sends its ERRFIN event; its full
collection continues. PUC reference finalizer errors propagate and reach the
fatal handler. Both outcomes are tested explicitly. This is preserved runtime
behavior, not a claim of identical finalizer error semantics. Original native
TLS/error reporting and native exception unwinding remain unvalidated.

[shutdown_tests.c](shutdown_tests.c) executes the full captured destructor after
captured construction and frames, including 4,000 frames of unchanged Poll Cache
with attributable machine code. Four cycles cover every combination of the two
native hook conditions, present/absent services, plugin rows with/without
callbacks and objects, native handles, zeroed globals and exact teardown order.
Unreachable userdata finalizes before service cleanup; reachable userdata
finalizes at environment close while the host backend remains alive. Both old
state fields point at an inaccessible page. The old collector code pages are
also inaccessible, and the Lua `collectgarbage` global deliberately throws.
Six invalid sequencing/lifetime subprocesses exit through the expected fatal
handler. The byte patches restore exactly and pass their original guards again.

Run `vm-poc shutdown` or `vm-poc.exe shutdown`. Linux, Wine, PUC reference and C
address/undefined-behavior/leak checks are recorded in
[SHUTDOWN-VALIDATION.json](dist/SHUTDOWN-VALIDATION.json). All native service,
plugin, allocator and filesystem implementations remain fixtures. The captured
boot and shutdown tests are separate fixtures; no game loader is installed.
This implements shutdown full collection. Timed frame collection is implemented
separately below; a complete live-game replacement remains unfinished.

## Timed frame garbage collection

[gc_policy.h](gc_policy.h), [gc_policy.inc](gc_policy.inc) and
[gc_runtime.inc](gc_runtime.inc) implement the scheduling policy captured at
`0x5eb310..0x5eb536`. It tracks current/previous peak allocation and minimum
live-memory estimates, computes a float growth ratio, forces full collection
above the configured threshold, and interpolates a bounded time budget.
Each frame performs at least one incremental step and at most 5,000, stopping
when the monotonic counter exceeds the deadline. Completed cycles rotate history.

The pinned FR1 runtime's own headers supply a read-only live-memory estimate;
total bytes are cross-checked against the public API before scheduling. The
constructor sets pause 200 and step multiplier 20 once. Subsequent mod changes
remain effective. Collection uses public `lua_gc` step/full/stop operations
inside the protected environment boundary, with automatic GC stopped again
after success or error. Lua's mutable `collectgarbage` global is not used.
The implementation follows the pinned [LuaJIT GC API source](https://github.com/LuaJIT/LuaJIT/blob/a4c064539ea931274d407e1249b4bb575424a0f4/src/lj_api.c).

[gc_routes.c](gc_routes.c) validates all 550 original function bytes before
planning its entry replacement. The adapter accepts the native collector wrapper
address and supports the unchanged forwarding entry at `0x6cd140`; neither entry
dereferences the old native state. Existing frame, boot, lifecycle and shutdown
harnesses now invoke this scheduler.

`vm-poc gc` compares 300 deterministic scheduling cases with the complete
captured original instructions. Those comparisons use synthetic PUC fields and
clock/collector/profiler functions. Separate tests in the same exported library
exercise real collection, 100 unreachable userdata finalizers, runtime-specific
finalizer errors, native routes with inaccessible old state, all 550 byte guards,
wrong-thread/missing associations, invalid clocks, reentry and rollback.
[GC-VALIDATION.json](dist/GC-VALIDATION.json) records results and C sanitizer scope.

This reproduces scheduling decisions, not identical collector work units or
pause durations across LuaJIT and PUC. Engine profiler output and
`Script.configure_garbage_collection` still need wiring; the latter is traced in
[gc-settings-intake.json](../vm-trace/gc-settings-intake.json). Early installation,
complete callbacks and live-game/native-Windows acceptance are still missing.

## Native Steam registration and callbacks

[native_steam.h](native_steam.h), [engine_steam.c](engine_steam.c) and
[steam.inc](steam.inc) implement all 11 bindings in registrar `0x7f4c10`.
`hd2env_register_steam` writes the original native context slot at EXE+`0x2860608`,
creates/reuses the registry `Steam` table, and installs replacement Lua callbacks.
The table retains `__index`, `_name`, and `stingray.Steam` behavior. A null service
writes null and leaves the Lua table unchanged, matching the original registrar.
The native slot remains engine-owned and is not cleared when a state closes.

Calls resolve the current service and its traced Win64 vtable slots at call time.
They invoke the service directly, without passing a Lua state or calling an old
PUC wrapper. Public Lua API operations implement the argument/result conversions:
16-digit lowercase hexadecimal IDs; optional hexadecimal user-name lookup;
signed 32-bit app/event IDs; number/string-to-app conversion with the original
64-bit truncation and low-word behavior; nil for missing names/events; and all
20 traced language mappings, including normalization and fallback to `en`.
`open_url` forwards the string/number conversion or null as the original does.

A host supplies bounded memory reads, the context-slot write, and executable-entry
validation. The current-EXE Windows helper uses `VirtualQuery` and refuses this
standalone executable. Before registration, the port checks PE identity, all
bytes of the registrar/callback/module-helper witnesses, and the relocated
language table and strings. This identifies the supported implementation; it does
not establish the lifetime or correctness of a live native service instance.
The embedding host must keep the image, service, vtable, code and strings stable.

One undefined original case is intentionally rejected: an unparseable
`user_name` ID raises a Lua error instead of using the original unchecked
`sscanf` output. Returned native names are limited to 1 MiB. Inaccessible memory
and non-callable methods raise protected Lua errors rather than dereferencing them.

[STEAM-VALIDATION.json](dist/STEAM-VALIDATION.json) records 65 comparisons against
the captured original callback bodies across Linux, Wine and the PUC reference.
The originals run against owned PUC-like slots, never the replacement state.
Native service methods and PUC/CRT support helpers are fixtures, so this is not
full original-runtime or live-service acceptance. The cases cover every callback,
all language mappings, numeric edge cases, native arguments, registry identity,
null/repeated/multiple-state registration, error recovery and 4,040 changed-byte
refusals. AddressSanitizer, UndefinedBehaviorSanitizer and leak checks cover the
C core and fixtures; LuaJIT and the captured machine code are uninstrumented.
The captured native boot fixture also exercises this registrar in its Steam stage.

## Native Friends and Presence registration

[native_friends.h](native_friends.h), [engine_friends.c](engine_friends.c) and
[friends.inc](friends.inc) port registrar `0x7f0f60`: ten Friends callbacks,
four Presence callbacks and 28 constants. Registration preserves the native
context slot at EXE+`0x28605f0`, both registry modules, namespace attachment,
cached table identity and the null-service path. The captured boot test calls
this registrar at stage 6.

Callbacks use protected public Lua operations and the traced Win64 native
boundaries. Direct Steam calls use the existing context getter and vtable.
Seven existing non-Lua helpers retain native name lookup, playing-game queries,
invitation queues and lobby/server formatting. These helpers receive native
values only; they never receive the replacement `lua_State`.

The implementation preserves category selection at service+`0xc0`, one-based
friend indices, numeric truncation/wrapping, hexadecimal IDs, optional-string
defaults, zero-result presence/query branches and invitation result counts.
The 96-byte invitation result has the native 16-byte alignment. SteamLobby
arguments require the original metatable identity and native pointer layout.
For `playing_game`, the captured callback repeats `app_id` in `mod_id`; this
observed behavior is preserved. The evidence records this separately from the
native result's actual mod field.

Malformed IDs, invalid/undersized lobby userdata and unterminated invitation
text raise Lua errors. Returned native strings are limited to 1 MiB. Overflowing
server-number text has defined uint32 conversion; no claim is made about matching
undefined overflowing `scanf` behavior. The embedding host must keep all native
objects, interfaces, code and returned memory stable during calls.

[FRIENDS-VALIDATION.json](dist/FRIENDS-VALIDATION.json) records 101 differential
cases across Linux, Wine and the PUC reference, plus 15,361 code-byte mutation
refusals and C address/undefined-behavior/leak sanitizer checks. Original Lua
callback machine code runs unchanged in an owned image. PUC/CRT support, direct
Steam interfaces and native helper bodies are fixtures. Tests cover all fourteen
callbacks, all playing-game flag combinations, zero/two/four invitation results,
lobby light userdata with the SteamLobby metatable, server strings, partial base-0
scans, state writes, registry identity, registration order and multiple environments.
Native SteamLobby creation still belongs to the unported Network stage.
No invitations or presence updates are sent.
Native helper internals and the real game service still need integration testing.


## Partial SteamVoip room and client bindings

[native_voip.h](native_voip.h), [engine_voip.c](engine_voip.c) and
[voip.inc](voip.inc) implement `hd2env_register_voip_views`: two Room queries
and all five Client bindings. This is a partial API and **does not replace the
SteamVoip boot registrar**. Room creation, join/leave, member mutation and
update/callback bridging remain unported because their native helper bodies
are unavailable in the current captures.

The adapter snapshots live member IDs in native slot order, preserves the
zero-result behavior of empty `broken_members`, borrows full/light userdata
pointers and uses public Lua APIs. Client selection retains the four original
native helper entry points. Their single-member hash lookup still needs a
verified body; no current-process host factory is provided for this partial API.

`vm-poc voip-views` compares seven bindings with captured original callback
machine code across 175 cases. The original native selection helpers also execute
unchanged. PUC/CRT/temporary allocation and native hash lookup are fixtures.
Full userdata tests use an existing eight-byte wrapper and do not exercise
native `join_room`. Byte guards cover 8,799 bytes. See
[VOIP-VALIDATION.json](dist/VOIP-VALIDATION.json) and the
[native investigation](../vm-trace/VOIP-INVESTIGATION.md) for exact limits.

There is no automatic release, `__gc` or pointer invalidation. The engine owns
the manager slot and client lifetime. The host must stabilize native code/data
for the complete call. Missing IDs, invalid userdata, inaccessible memory and
excessive collection sizes raise Lua errors. Six boot registrar bodies remain
incomplete; the partial views are deliberately not counted as a finished stage.

## Validation and results

[dist/VALIDATION.json](dist/VALIDATION.json) records the complete run, hashes,
reference effects, and limitations. [dist/NATIVE-VALIDATION.json](dist/NATIVE-VALIDATION.json)
records the read-only binding checks. Each platform has a build receipt and
individual logs. The suite runs one PUC reference and three paired JIT-on/off
runs on each target, with 4,000 host frames per run. A separate short-lived state
tests the resource-provider contract before the main stock/mod state is created.
Two additional short-lived states test cross-environment object ownership.
Stock scripts and the running mod share one state; there are no workers.

`jit.attach` attributes traces to the unchanged mod's `src/poll_cache.lua`.
`jit.util.tracemc` confirms generated machine code. The observer and scenario
driver are kept interpreted. Every JIT-off control reports zero traces.

The receipts record live trace counts, generated machine-code bytes, and paired
median JIT-on/off CPU timings for the synthetic Poll Cache workload. Counts and
timings vary between runs. These are neither game FPS measurements nor
predictions of total game performance. The separate full-bootstrap run exercises
the complete loader lifecycle and owned frame entries, a different workload.

## Frozen standalone Windows test

The latest local package is [2026-10-24-gc-poc.zip](../test-builds/2026-10-24-gc-poc.zip).
Extract it outside the game installation, keep the EXE and DLL together, and run
`./vm-poc.exe shutdown` in PowerShell. Success returns exit code 0 and prints
`POC_SHUTDOWN` with pass results, four states and 4,003 frames, plus `POC_JIT`
with nonzero mod traces. The first state runs unchanged Poll Cache for 4,000
frames. Run `./vm-poc.exe boot` for the separate captured boot test,
`./vm-poc.exe steam` for 65 Steam comparisons, `./vm-poc.exe friends` for
101 Friends/Presence comparisons, or `./vm-poc.exe voip-views` for 175 partial
SteamVoip comparisons. Redirect output with `*> shutdown.log` to retain
evidence. The package includes checksums and test
receipts. Native Windows acceptance is still pending; no game is launched or
modified. Remove the extracted folder to remove this standalone test. Earlier
frozen packages are preserved; Friends r2 supersedes r1 with the original module
registration order restored.

Package SHA-256: `08df5dc9541606e69b53e0986e11f8968e89d6ba8da4e95897e56b3283abe1bf`.
Run `./vm-poc.exe gc *> gc.log` for the timed collector comparisons; one intentional
finalizer error is expected in that focused test. All eleven validation suites
passed against this build on Linux and under Wine;
reference and sanitizer checks are recorded in the individual receipts.

## Reproduce locally

From `/home/goose/Documents/ChatGPT/Linux HD2`:

```bash
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-trace/inventory_runtime.py
python3 runtime-modules/vm-poc/build_runtime.py --platform all
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_frames.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_gc.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_lifecycle.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_boot.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_steam.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_friends.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_voip.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/prepare_shutdown.py
python3 runtime-modules/vm-poc/prepare_vectors.py
python3 runtime-modules/vm-poc/build.py --platform all
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_lifecycle.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_boot.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_steam.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_friends.py
python3 runtime-modules/vm-poc/validate_voip.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_shutdown.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_frames.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_gc.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate.py
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-poc/validate_bootstrap.py
python3 runtime-modules/vm-poc/validate_objects.py
python3 runtime-modules/vm-poc/validate_compatibility.py
python3 runtime-modules/vm-trace/check_layout.py --fr1
PYTHONPATH=/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/python-deps \
  python3 runtime-modules/vm-trace/trace_native_entries.py
```

Prerequisites are the pinned LuaJIT vendor checkout, the prior
Lua 5.1.4 reference build/capture, current local game files, the LLL checkout,
Python with its existing archive dependencies, Java, GCC, the Win64 cross
compiler, and Wine. `build_runtime.py` creates dedicated FR1 runtime trees;
`build.py` verifies and links their static libraries and records input hashes.
The separate worker prototype's GC64 trees are unchanged. Wine uses
the isolated `runtime-modules/build/wine-prefix`, not the game's prefix.

`work/`, `vendor/`, and `dist/` are ignored local outputs. Recovered stock source
and embedded test executables are local research artifacts, not a redistributable
mod package. The standalone environment DLL does not embed game scripts. Its
LuaJIT copyright notice is copied beside it.


## Persistent Vector3Box, 13:58 EDT

`hd2env_register_vector3box` follows Vector2/Vector3 registration and validates
current native witnesses. It creates LuaJIT-owned full userdata with the native
12-byte float payload, keeping VM headers separate. The box module is its
metatable, as in the original; `unbox()` copies into the real temporary pool.

The same candidate passed 70 box comparisons, 136 Vector3 comparisons and 82
Vector2 comparisons in the running game. Original engine callbacks read and
mutated a LuaJIT-unboxed vector while its persistent box stayed unchanged.
Five manual update/render pairs confirmed temporary expiration, persistent box
survival and weak-reference GC, with exact borrowed-pool restoration. Separately,
a box retained only through `HD2Object` survived 90 actual host frames with GC
on each tick; releasing its handle let it collect. The state closed and another
90 original game frames passed. No engine routes were patched.

The initial box comparison found one mismatch in the existing global `tostring`
wrapper: the engine returns `[no value (deleted)]` for no arguments, whereas
LuaJIT's standard function raises an error. R1 fixes that case; its exact string
and result count are now tested. General scalar conversion precision differences
remain. Invalid single-source constructor/store arguments fail explicitly rather
than reproducing native unchecked reads.

[Live receipt](../live-load/2026-10-24/LIVE-VECTOR3BOX-VALIDATION.json),
[parity and native round trip](../live-load/2026-10-24/vector3box_live_r1.live.log),
[actual host frames and owned userdata](../live-load/2026-10-24/vector3box_host_frames_live.live.log), and
[candidate provenance](../live-load/2026-10-24/VECTOR3BOX-R1-BUILD.json).

Full stock boot, main-VM replacement, unchanged-mod acceptance and native Windows
remain unverified. This candidate is for live integration diagnostics.


## Shared Vector4 and Quaternion payload, 14:04 EDT

The live callback intake confirmed that Vector4 and Quaternion use the same
20-byte payload (`0x58235806` plus four floats) and native metatable. Quaternion
identity even formats as `Vector4(0, 0, 0, 1)`. The new Vector4 registrar implements
all 30 public functions on that representation, with tag dispatch preserving
Vector2 and Vector3 operations.

- Batch 831: 103 Vector4 observations matched exactly. The original Vector4 and
  Quaternion callbacks read a LuaJIT-created value; original Quaternion
  `set_xyzw` changed it to `(-9.5, -8.25, 6.25, 1)`, which LuaJIT read back.
- Batch 832: five manual update/render pairs expired mixed Vector2/3/4 values.
  GC preserved live values; the probe removed its frame binding, closed its state
  and restored every borrowed byte and all pool metadata.
- Batches 833–835: 136 Vector3, 82 Vector2 and 70 Vector3Box comparisons and their
  original engine round trips still passed with Vector4 installed.
- Batch 836: another 90 healthy original game frames passed, with temp count zero.

[Live receipt](../live-load/2026-10-24/LIVE-VECTOR4-VALIDATION.json),
[Vector4 parity and original Quaternion round trip](../live-load/2026-10-24/vector4_live.live.log), and
[candidate provenance](../live-load/2026-10-24/VECTOR4-BUILD.json).

Quaternion's LuaJIT function registration is still missing; shared data-format
interop does not establish those functions. The callback intake and initial
linear disassembly are saved in `vm-trace/quaternion-callback-intake.*` for the
next adapter. Matrix4x4, full stock boot and unchanged mods in a replaced main
VM remain unverified. No game routes were patched; native Windows is untested.

## Quaternion registrar, 16:51 EDT

Quaternion now has its own LuaJIT registrar on the shared Vector4 payload:
28 of 30 public functions are ported. `matrix4x4` and `from_matrix4x4` still
raise an explicit error, because they return or accept native Matrix4x4 values
and that family is not ported yet.

- Every ported body follows the original float evaluation order, traced from
  build 26088801. Eleven come from the static captures. `normalize`, `inverse`,
  `conjugate`, `dot`, `lerp` and `slerp` sit on a page packed on disk and
  uncommitted in the earlier capture. They were traced from a read-only in-game
  dump (batch 849). That dump equals the mapped capture wherever the capture
  has code.
- `slerp`, `angle`, `decompose`, the Euler conversions and `look` call the game's
  own pure helpers: CRT `atan2f`/`asinf`/`acosf`/`sinf`, the Euler→quaternion
  helper `0x66be20` and the basis→quaternion helper `0x66bc40`. Each call first
  checks a 32-byte witness. These helpers read only the float buffers passed to
  them and never touch a Lua state.
- The tracing corrected three black-box fits from r5. `slerp` divides the
  weighted sum by sin θ last and was up to 1.2e-7 off. `lerp` evaluates
  `(b−a)·t + a`, or `(a+b)·t − a` for opposite signs. `inverse` treats a zero norm
  as 1 instead of producing NaN.
- Batch 850 (r7): all 335 comparisons across 28 functions match exactly,
  including NaN, zero and degenerate `look` inputs. Batch 848 (r6) had matched
  all 162 newly traced rows before slerp was corrected.
- Batches 851–854: 103 Vector4, 82 Vector2, 136 Vector3 and 70 Vector3Box
  comparisons and their original-engine round trips stayed identical, with
  Quaternion registered.
- Batch 856: five update/render pairs expired Quaternions created by the
  replacement's `from_euler_angles_xyz` and `look` alongside Vector2/3/4. Every
  borrowed byte and all metadata were restored. Batch 855 failed only on a stale
  temp-byte expectation in the test itself; its cleanup also restored everything.
- Batch 857: another 90 healthy original game frames passed, with temp count zero.

[Live receipt](../live-load/2026-10-24/LIVE-QUATERNION-R7-VALIDATION.json),
[comparison log](../live-load/2026-10-24/quaternion_live_r7.live.log),
[candidate provenance](../live-load/2026-10-24/QUATERNION-R7-BUILD.json). Regenerate witnesses
with `python3 vm-poc/prepare_quaternion.py`. QuaternionBox, full-userdata
arguments, Matrix4x4, full stock boot and unchanged mods in a replaced main VM
remain unverified. No game routes were patched; native Windows is untested.

## Matrix4x4 registrar, 17:20 EDT

Matrix4x4 is now bound to the real native temporary pool. Its payload is tag
`0x7fd2e074` followed by 16 row-major floats; the rows are x/right, y/forward,
z/up and translation. 41 of 42 public functions are ported. `lerp` raises an
explicit error: it is traced but not ported, and no stock script or installed
mod uses it. Quaternion's `matrix4x4` and `from_matrix4x4` are now complete
too, so Quaternion is 30 of 30.

- Two code pages (`0x438000`–`0x439fff`) are unpacked by the game on first
  execution. They were dumped read-only after exercising the original callbacks
  (batch 861). The dump matches the mapped capture wherever that capture has code.
- Long float bodies were translated mechanically, one IEEE operation per C
  statement. `multiply` and the quaternion→matrix packing use a lane-tracking
  translator, checked against a hand mapping (0 mismatches over 10⁶ random
  inputs). `inverse` and `rotation` call the game's pure helpers `0x66ca00` and
  `0x66bfc0`. `to_string`/`tostring` use the engine formatter.
- Witnesses for replaced callbacks on unpacked-on-demand pages are now optional:
  they are checked only when the page is resident. A fresh game session refused
  Quaternion registration (batch 863) because those pages were unreadable before
  the game had run them. Witnesses for helpers the port calls stay mandatory.
- Batch 867 (r5): 376 of 382 comparisons match exactly. `axis(m,0)` and
  `element(m,5,…)` are intended differences: the original reads out of bounds,
  while the port refuses. The original's shared metamethods operate on a matrix
  by its leading floats (`m.x`, `m*m`, `m+m`, `-m` → Vector4); the port refuses
  these. That gap is unused by stock scripts and installed mods.
- Batch 874: the original engine read a Matrix4x4 created by the replacement
  (translation, scale, element). Original `set_translation`, `set_element` and
  `set_scale` then mutated it, and LuaJIT read the result back.
- Batches 875–879: the Vector4/2/3/3Box regressions and the full Quaternion suite
  (335/335) stayed identical, with Matrix4x4 registered.
- Batch 880: five update/render pairs expired matrices alongside the other types,
  with exact restoration. Batch 881: 90 healthy original frames followed.

[Live receipt](../live-load/2026-10-24/LIVE-MATRIX4X4-VALIDATION.json),
[comparison log](../live-load/2026-10-24/matrix4x4_live_r5.live.log),
[round trip](../live-load/2026-10-24/matrix4x4_roundtrip_live.live.log),
[candidate provenance](../live-load/2026-10-24/MATRIX4X4-R5-BUILD.json). Regenerate witnesses
with `python3 vm-poc/prepare_matrix4x4.py`. Matrix4x4Box/QuaternionBox, full
stock boot and unchanged mods in a replaced main VM remain unverified. No game
routes were patched; native Windows is untested.

## Remaining game integration

A real game run requires an early native bootstrap, a complete inventory of
engine VM entries, and routing those entries to this core before state creation.
The captured update/render routes above are only one part of that change and
must not be installed alone.
The captured native boot route now bypasses its direct PUC layout accesses,
but its required registration adapters and plugin VM interfaces remain incomplete;
replacing the constructor alone still corrupts memory. The C++ environment's other resources
and destruction must be preserved while replacing its VM-facing methods.

The earlier live binding census contains **1,874 exposed names**. Prefix bytes
for 1,490 match saved images; 384 lack a confirmed saved prefix. This is a
surface inventory, not a complete call graph or current live validation. See
[binding-inventory.json](../vm-trace/binding-inventory.json).

The remaining engine callbacks need adaptation, including userdata/vector
representations and callback recursion. The resource loader needs the real
archive resolver, native LuaObject consumers need routing to the new ownership/accessors,
and the new LLL bootstrap must be connected to the actual engine/service.
Finally, real game init/update/shutdown and an unchanged mod
must pass with trace and frame-cost evidence. This proof establishes source/mod
execution in one replacement state, not those remaining integration steps.

References: [prior engine trace](../vm-trace/TRACE.md),
[LuaJIT C API](https://luajit.org/ext_c_api.html),
[LuaJIT compiler controls](https://luajit.org/ext_jit.html),
[unluac](https://sourceforge.net/projects/unluac/).
