# Credits and source boundaries

- **HWG90 / Goose** — Original DBF, project direction, game testing and the saved Bracket direction.
- **DDRK1ng** — original HD2 HUD Plus. This project borrows its verified read-only anchoring,
  positioning, action-bit and native UI metadata concepts through the HudPlusPlus reference at
  commit `9a416e1213660fcc2eb3ef436162ad8dad5a0396`. Only five read-only native getters and selected
  fields are used. HUD+'s product/runtime/world-UI/camera/input engine is not included.
- **CowboyBingus and contributors** — original loader/bindings/settings infrastructure and modding
  groundwork. MBM and the current LLL/DBF-MCM remain separately installed dependencies.
- **HD2-UI-Style** — unchanged shared Lua token/geometry kit in `dbf_modular/ui/style.lua`.
- **LLL and DBF-MCM contributors** — exact source snapshots under `reference/lll/` and
  `reference/mcm/` used only by offline tests; no second framework is loaded by the addon.
- **Arrowhead / HELLDIVERS2 team** — game engine, native font/artwork and widgets referenced from
  the installed game. No game binaries, DLLs or extracted texture pack are included.
- AI-assisted implementation and independent component review are disclosed; game/visual approval
  remains the user's live test.

`design/BASELINE.json` and
`design/POSITIONING-SOURCES.json` record the imported baseline and metadata provenance.

The optional native Heat Limiter statically includes MinHook (BSD-2-Clause), pinned to commit c3fcafdc10146beb5919319d0683e44e3c30d537. Complete unmodified source and provenance are in `native/heat_limiter/vendor/minhook/`; the LLL package includes `native/MinHook-LICENSE.txt`.
