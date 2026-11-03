# HudPlusPlus r9, LuaJIT 26251122

HudPlusPlus is HD2 HUD Plus 0.2.9 by DDRK1ng (Nexus Mods, helldivers2/mods/15298) rebuilt for game build 26251122
and renamed. `builder/native-work/hud-plus-port` (Linux HD2 workspace, branch `indev/hud-plus-search-815c13`, commit
`56de6814df1ef29aa0aee943f02b96e986abd013`) builds the Arsenal mod from HUD+ 0.2.9: `build_port.py`, the data it reads (`data/`, with
`manual-26251122.json` giving the evidence for every value found by hand), `tools/` and `tests/`. Its README.md
describes the method; LIVE-CHECK.md lists the first-launch checks. `lua/` holds the Lua the shipped patch
carries, named by resource key (1 file).

The modular refactor in this checkout uses `src/` as its editable source and `tools/build.py` to
generate that same resource-keyed bundle. `tools/package.py` builds a candidate from existing assets;
the original `builder/` pipeline remains research/reference and does not consume the modular source.
See `README.md`, `EDITING.md` and `UPSTREAM.json` for the workflow and exact upstream provenance.
