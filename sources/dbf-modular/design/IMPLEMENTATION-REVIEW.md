# Implementation and review gates

Scope is Original DBF capabilities plus an independent modular Quiet Bracket HUD. Deployment and live-update state are recorded separately in dist receipts. The new source is at DBF-Modular; archived merger files remain separate.

The architecture/interfaces were reviewed by three component auditors before implementation.
Final implementation reviews are scoped as follows:

| Area | Independent review and checks |
|---|---|
| Original Core and seams | Original load/update order, private scope, explicit current services, original32+37 setting routes, byte-identical25 native modules, cleanup refusal retention. Core55/Core-Store57 fixtures pass. |
| Settings and actual MCM |79 controls/9 categories/12 bounded pages, exact original domains, one atomic Store, actual MCM transactions, original defaults+per-ID persisted preference import and own-version cutoff.977+240+74 checks plus the real-path Python test pass. |
| HUD and retained renderer | Pure policy/placement/layout plus actual native-call-shaped GUI fixture. ADS expansion, first-person pinning, reload/switch fallback, generic gauge semantics, font atlas, measured screen clamp, unboxed text/shadow tokens, unknown worlds and refused primitive cleanup.529 checks pass, including held-throwable zero-count behavior and one count display owner. |
| App and controller | Single lifecycle and update order, valid nested console schema, original DBF presenters preserved in every state, independent fallback cleanup attempts, second-pass geometry validation, refused teardown retained/retried.112 checks pass. |
| Read-only sampling/native bridge | Producer data and ABI witnesses are checked against the original HUD+ metadata. Fresh actor/wield/root/context/camera identity, actor-generation changes, throwable count/reserve semantics and known visibility demand gates pass84 actual-byte producer checks. Unsupported capacity/generic remaining stays unknown; no original DBF capability is removed. The guarded Native bridge passes333 checks with real FFI aligned buffers, synthetic target EXE/Game PE identities, fresh masked/executable witnesses, module replacement, failure paths and actual Session camera/context changes before projection. |
| Packaging | Deterministic loose runtime/source ZIPs, declared-module completeness, portable exact LLL loader preflight, immutable baseline and reference hashes, ZIP byte round-trip. |

Review fixes include body-anchor reload/unknown fallback; generic-gauge warning without unproven
reload instructions; original LLL persisted preferences; hiding own GUI even when an original DBF
fallback throws; validating translated geometry before drawing new HUD content; and freshness guards
for actor/weapon/camera changes. No second selection routine was added.

Windows settings replacement was additionally checked with standalone Windows LuaJIT in a fresh
`/tmp` Wine prefix, including Unicode paths. The game prefix was not used for those tests.

Run `python3 tools/check.py` for current exact results. An exact LLL project parser compiles and
instantiates the declared source while deliberately not calling enable/native access. A second
preflight against the local current LLL checkout also passed. None of these establish in-game
visual/input acceptance or a numerical performance improvement.

## Dev.2 user-directed update

Removed Bracket label plates while preserving subtle shadows and thin bars. Existing DBF weapon
strip and cooldown presenters remain governed by their original controls in all states; copied
option text and replacement claims are removed. Native heat normalization passes122 checks, with
current-game decrypted code calibration and an actual affected laser limit150 captured read-only.
The descriptor now supports acknowledged cleanup polling for future normal LLL live reloads.

Seven additional independent scoped reviews covered layout, additive ownership, heat policy,
settings preservation, heat producer, live cleanup and source/package readiness. No unresolved
material findings remain in those scopes. Exact live installation and observations need their
own receipt; source fixtures alone are not visual/performance acceptance.
