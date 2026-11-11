# Experimental native zoom input normalization

This candidate is isolated from the installed combined Gadget Kit 0.5.39.
The profile opt-in is not enabled. Hook integration, protected atomic cleanup and lifecycle fixtures passed
offline; these receipts do not establish in-game behavior.

The user authorizes an SDK pointer hook and excludes inline patching. The
candidate uses UnitAPI+0x90 at the captured native6 return site 0x11184DE.
The existing UnitAPI+0 getter provides completion at 0x1119924. Native
camera orientation, lens state, animations, input buffers, input history,
steering, context offsets and saved sensitivity preferences remain untouched.

For each axis the captured native look path combines filtered player input U,
inversion I, the lens-derived factor R, saved device sensitivity D, and native
steering S as X = D * (R * (I * U)) + S. The desired counterfactual removes
only R: T = D * (I * U) + S. A private copy of the native 144-byte camera
preset supplies a candidate gain g' = g * T / X. The implementation checks the
actual separate SSE rounding points, context contribution, pitch gate and
native gain integration before publishing either axis.

Zero evaluator time still permits native look integration through the
separate global time value. It is included in the math fixtures and cannot
be treated as a frame without input.

Singular, poorly conditioned, unsupported or excessive-error inputs use the
native preset. Gains are never clamped and reported as a successful inverse.
The private preset preserves all bytes except yaw/pitch gains +4/+8. The
captured FOV helper does not consume those gains; the outer blend consumer's
+0x8C value must stay immutable, including across cache reuse.

Private records must be addressable by the captured unsigned 32-bit index
times 144 calculation, above the pinned game image's native preset table.
Publication and restoration compare the exact owned request index. Completion
must identify the actual native R15 request, caller stack, thread and lease
generation. Restoration precedes the existing getter's depth observation.
End retains pending cleanup, including ambiguous retired rows; no retirement-only
acknowledgment assumes that every future row copy resets the preset index.
Foreign row/index/pointer owners win. Clone
backing remains pinned or quarantined whenever reader completion is unproved.

With zero native steering, a fixed g/R correction is published even at idle;
it does not depend on the predicted raw input/history. With nonzero steering,
the copied values used for prediction are sampled before native filtering.
No source proof currently excludes every concurrent input/steering update.
A post-completion history comparison can detect a changed filter result and
disable further input-dependent normalization; it cannot undo an angle already evaluated.
This ordering dependency remains an explicit limit of the experiment.

Config (104 bytes) and ordinary Stats (80 bytes) retain ABI2. Input-enabled
Validate/Begin entry points are separate from legacy four-slot operation.
Optional InputStats is a separate 96-byte ABI1 and is read only on explicit
request, never by ordinary per-frame health polling.

Validation receipts currently available:

- `dist/zoom-input-math/math-build.json`: independent native SSE filter model
  and private execution of captured SSE2 and AVX/FMA exp code.
- `dist/zoom-input-math/gain-build.json`: independent full gain/context/gate
  arithmetic, including explicit unsupported cases and pitch clamp bounds.
- `dist/native-input/build.json`: 130 native fixture groups, a separate real
  request-unmap test and actual production ABI smoke passed. The new field CAS
  has an explicit static SEH leaf, independently checked in the production DLL.
  Synthetic timing is separate from game FPS; unchanged legacy dispatch CAS
  catchability was not qualified by this new field guard.
- No live hook test has occurred.
