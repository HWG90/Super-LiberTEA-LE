# Refactor validation — 2026-11-03

Source: Super-LiberTEA-LE `v1.0.3`, commit
`33baf36bc136bfe8759de087864fa67ed37afd1d`, on branch `refactor/hudplusplus-modules`.
The refactored bundle contains 86 named modules plus the LLL entry. Offline checks passed before
installation. Modular r1 was then installed in the LuaJIT Proton profile and exercised by the user;
the loader log and profiler stacks confirm the refactored code ran.

## Offline results

`python3 tools/build.py --check` and `python3 tools/check.py` pass. StyLua 2.6.0's formatting check
and `git diff --check` also pass.

| Check | Result |
| --- | --- |
| Deterministic build and archive/package tests | 14 passed |
| Upstream native data, settings and resource comparison | 12,491 scalar values preserved |
| Native access: pinned/refused/cached/scanned paths | 27 checks passed |
| Native bit helpers against the original implementation | 10,604 differential checks passed |
| Update/shutdown hook lifecycle | 8 cases passed |
| Call-colour queue order, reuse, wraparound and reset | Passed |
| Dependency propagation and optional ground previews | Passed |
| Protected-memory reads with fake VirtualQuery | All 9 cases passed, including the cross-page crash regression |
| Every Lua source file and generated addon | Compiles; addon loads without enabling native access |
| Generated source map | Every mapped span matches its source file |

Existing native call descriptors (181) are unchanged. The availability graph changes to follow the
new source modules and to include the formerly implicit world-HUD/weapon-3D dependency.

## Helper measurements

LuaJIT CPU time, median of three runs on this machine. Run `tests/test_native_bits.lua` with an
immutable upstream bundle and `--benchmark` to repeat. These measurements cover the helpers only;
they do not measure in-game frame rate, startup time or total HUD cost.

| Work | Original | Refactor |
| --- | ---: | ---: |
| 1,000,000 common flag checks | 0.020507 s | 0.005838 s |
| 1,000,000 high-bit flag checks | 0.087787 s | 0.004710 s |
| 10,000 archive-name hashes | 0.029025 s | 0.011872 s |

The common flag path uses one native `band` rather than up to 32 arithmetic iterations. Hashing the
main addon name uses 36 native XOR calls rather than 576 bit-by-bit iterations. Inputs outside the
flag helper's 32-bit integer domain retain the previous arithmetic behavior.

## Candidate artifact

Built from the existing HudPlusPlus build-26251122 port assets, with its GUID retained. All 36 other
archive resource payloads, GPU resources and stream bytes match the input. The old boot resource is
absent, and the archived HUD resource matches the generated bundle.

- Package folder: `out/HudPlusPlus-Modular-26251122-r1/`
- Importable ZIP: `out/HudPlusPlus-Modular-26251122-r1.zip`
- Bundle SHA-256: `537e430a2974f6315d93950b34857f84f9ee7b22514972704fee6e37e56cb770`
- ZIP SHA-256: `caf05cdf05941a13efea65ca5728e2dd56f554c7bc4145b8a3261bfd47b4db17`
- Receipts/log: `out/VALIDATION.json`, `out/validation.log` and the package's `BUILD-RECEIPT.json`

## In-game test and remaining verification

The user tested the installed refactor. The latest captured session ran for about 18 minutes, and
the loader reported the HudPlusPlus addon loaded. This confirms execution, rather than complete
feature-by-feature visual equivalence.

The existing statistical profiler groups the HUD with other archive scripts under `loader/other`
and prints detailed top-line samples only for slow windows. Its output cannot establish an overall
HUD timing or FPS improvement. A matched before/after capture is still needed for that measurement.

Detailed feature coverage remains to be recorded: Options and saved settings, weapon/3D/world HUD,
squad, trajectory and attack-area previews, hot joins, and repeated enable/disable with other mods'
update wrappers.
