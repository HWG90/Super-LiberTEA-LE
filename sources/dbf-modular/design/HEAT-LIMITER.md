> Live acceptance withdrawn: dev.12 crashed during enforce=0 observation. Stable dev.10 was restored through acknowledged live cleanup. The next HUD build disables this control, blocks native loading and excludes the helper DLL. See dist/incidents/dev.12/INCIDENT.json. No strict-prevention claim is currently supported.

# Heat Limiter: native firing bridge

Status: dev.11 enforcement approval withdrawn after live crash and a separate native cleanup safety finding. Exact dev.10 runtime is restored. Native V2 is being implemented; no limiter is currently installed.
The user explicitly selected strict prevention through a new native firing bridge on 2026-11-07,
rather than a conservative post-update trigger cutoff.

## Integration and ownership

This is a new Core gameplay capability, separate from the read-only HUD. It retains the sole LLL
lifecycle, Original DBF input bindings, settings owner, and original native modules. No second Lua
update wrapper, mouse capture, generated click, heat reset, lock override, or ammunition refund.

One Core-owned adapter loads a build-specific native helper and owns its generation lease. Its
configuration identifies the current local actor using the original reader's full identity record.
Weapon fields are initial hints: each native callback resolves the CURRENT selected weapon itself,
so hot weapon switches do not wait for the original reader's100ms refresh. The helper revalidates
local player, inventory/selector, record bytes, component row, resource/configuration and gameplay
state before each intervention. Different actors/weapons
forward unchanged. Unknown ownership suspends protection explicitly and never authorizes writes.

A new Weapon controls category adds one Heat limiter toggle (default off). The native admission ceiling is99%
with80% cooling hysteresis. These are raw heat units divided by the exact current native limit;
percentage/bar/hybrid presentation remains independent. A checked toggle is not evidence of native
arming: native status and explicit acknowledgements determine active protection.

## Native decisions

Use native callbacks, never engine-to-LuaJIT callbacks. All called/hooked entries, consumers and PE
identity are pinned to build26251122; unavailable or changed witnesses refuse installation/arming.
Each decision reads current heat and computes the actual next native float32 quantum. Equality at
or above the ceiling is rejected before emission. Recheck every admitted shot, including catch-up
bursts. No assumption about Lua cadence, frame rate, or a cached percentage is sufficient.

Current proven seams:

- Heat-shot entry76dc40 wraps the actual projectile-emission call and then adds configuration+74.
  Its caller's catch-up loop depends on the native shot scheduler advancing. A refusal MUST retire
  the pending shot through a proven cancellation/scheduler path; a bare early return can spin that
  loop indefinitely. This is a mandatory implementation/review gate.
- Windup76ec10 and thermal step76e3f0 receive the actual per-row dt in XMM2. Continuous gain is
  float32(dt * config+78) while charge>=positive config+94. Heat/lock remain native-owned.
- Native stopa75700 on the validated current avatar context propagates normal fire release and
  clears the selected heat component's request48. The thermal loop latches request9 after advancing
  heat, so request48 cancellation alone leaves a same-phase tail.
- Active beam activity can survive can_fire=false. The bridge must cancel the current firing intent
  and stop the physical beam as well as refuse new shots. Native world-beam stop124f1d0 retires
  matching physical/effect/audio entries; component activity must also retire through its normal
  update or a separately proven intent cancellation.

Six native hooks cover shot admission, windup, heat integration, beam update, beam emission and
upstream can-fire queries. There is no global input-consumption lease or extra input-update hook.
The physical trigger may remain held; actual weapon firing is gated in its native consumers.

An emergency power cut may cancel owned firing request/charge (including charge->0) as part of
stopping actual firing, then run the original windup/thermal/cooling/effect processing. This is an
intentional abrupt power-off, not a reset/clamp of accumulated heat. It must also stop real beam
emission, so no firing continues with its heat processing suppressed.

## Lifecycle and evidence gates

Versioned POD Config/Status ABI and generation token. Begin/Bind acknowledge arming; End must disarm, restore all six original code patches, drain counted
in-flight callbacks and acknowledge inactive forwarding. It retains the process-pinned DLL and six
trampolines instead of freeing code that a thread could already be approaching. Re-enable reuses
those allocations. No MinHook removal or uninitialization is performed by production cleanup. Preserve token/library/storage on any
unknown or refused cleanup; Core cannot retire dependent owners first. A process-pinned inactive
trampoline is acceptable only when ownership and exact original forwarding are verified.

Before live installation: independent immutable-source review, portable thermal/admission fixtures,
foreign-identity and failure injection coverage, real MinHook/trampoline smoke test in an isolated
Wine prefix, complete existing source checks, exact packaged hashes and a rollback receipt.

Final acceptance requires an actual projectile laser and a continuous beam: hold firing to cutoff,
verify raw heat stays below native maximum and the physical shot/beam stops, cool/resume, switch
weapons, menu/death/focus transitions, disable/re-enable and acknowledged live reload. Native
counters, package hashes and fixtures do not substitute for that in-game acceptance.

The strict candidate covers the witnessed local projectile and continuous/pulsed beam consumers. An observed uncovered secondary heat-only callback explicitly disarms as unsupported; it forwards native accounting and cannot claim prevention after that heat has already committed. Enforcement also requires callbacks on the validated game thread. These capabilities must be checked live before protection is reported as accepted.

Live observation on2026-11-07 passed with enforcement off: matched windup/heat/beam callbacks, no thread or ownership faults, and positive End acknowledgement restoring all six patches. Physical projectile/beam cutoff remains a separate acceptance step.

## V2 correction after the dev.11 incident

The recorded anonymous-thread crash signature predates this bridge; it does not prove a limiter or
first-person cause. Independently, destructive stop calls from a readiness query can re-enter an
active native update and reorder cleanup. The V1 source approval is superseded by
`dist/incidents/dev.11/INCIDENT.json`. Its packages are quarantined.

V2 must remove every explicit NativeStop/WorldStop call. CanFire is pure admission. A beam cutoff
temporarily suppresses its continuation byte only at the OUTER BeamTick entry, preserving previous
held/active fields for the original component transition, world-beam stop and held-state clear.
A full-owner forced-denial scope spans that original call, independently of heat hysteresis.
The byte is restored with a fresh component identity and positive readback acknowledgement.
Publish the global borrow ledger before the first write; unknown restoration retains ownership.
End may not restore the byte or disable dependent CanFire/Emit hooks while the borrowed original
call is in flight. Pending restore denial precedes the ordinary retiring fast path.

Thermal intent/charge cancellation runs only through owned scalar fields and original thermal
processing. Actual heat and lock remain native. Physical-stop-pending is distinct from cooling
hysteresis: a low-heat large-dt rejection still needs a completed normal beam cleanup. Full entry
budget includes continuous and first-pulse heat. Nested queries must not charge that pulse twice.
Per-emission refusal never runs destructive engine functions and must preserve bounded schedulers.
