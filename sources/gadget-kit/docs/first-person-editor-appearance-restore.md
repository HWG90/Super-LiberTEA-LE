# Original Gadget Kit F8 appearance

This isolated change restores the original non-HellForge F8 appearance from
the pre0.5.35 source saved in
`work/install-backups/tfp-seamless-20261109T063218Z/source/src/first_person/placement_editor.lua`.
That backup's draw function is recoverable in full; no replacement design was
invented. Panel and hit geometry, plain text, original capitalization, equal
square button fills, original palette and footer accent come from that source.

The current installed0.5.38 source is the functional baseline. Only its draw
function and palette binding change. All remaining editor code is identical,
including weapon/action identity, preview/save/cancel, translation and rotation,
reset-all, family defaults, capture ownership, foreground checks and cleanup.
The current family-aware Reset branch is retained rather than copied backward.
Settings, motion presets and the runtime/menu remain unchanged.

DESIGN.md explicitly scopes its restyle to HellForge and lists Gadget Kit as
out of scope. The earlier broader AGENTS instruction still requires colours
through tokens. This change satisfies that token constraint with a narrowly
scoped `editor_legacy_tokens` table in the existing UI helper, outside its
generated HellForge block. Its five RGB values and opacity are copied exactly
from the original editor; drawing contains no RGB literals. F8 no longer
requests the helper's HellForge rounded geometry, palette or synthetic bold.

No canonical, installed, current workspace, hotpath or recovery files are
changed by preparing this candidate. Offline command/fixture acceptance does
not establish a live or on-screen result; no install or game calls occur here.
