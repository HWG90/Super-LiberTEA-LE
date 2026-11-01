# Bridge Combat, original design, on game 26251122

The user's Bridge Combat 0.1.17 (Windows, LLL, game 6AB3B43F; GooseGadgets `Bridge Combat/terminal-0.1.14`,
released 2026-10-19) rebuilt for Steam build 26251122 with the two support weapons added since. Nothing of the
LuaJIT-era redesign is in it: no admission helper, no aim/fire patches, no startup gate, no per-frame input-owner
checks, no "complete contract" code reads before every call. One module is new, because of what 7.2.0 changed.

## What 7.2.0 changed

The pre-7.2.0 exe (`helldivers2.exe.backup`, 2026-10-18, stamp 6AB382E4, 14.9 MB) is WinLicense-protected
(`.winlice`, `.vm_sec` sections) and its code is readable once loaded. The 7.2.0 exe (26088801 and 26251122,
28.7 MB) imports `preloader.dll`, which maps `bin/runtime.dll`; that runtime keeps each game.dll/exe code page
encrypted (PAGE_NOACCESS) until the first time the game executes it. The original reads a function's prologue
before calling it, so on the ship, before any mission, it cannot check or call: the weapon wheel (six pages), the
support drop (`+0x9c0300`), the ammo pickup page, the stamina bar constructor.

`src/code_warmup.lua` + `src/code_warmup_sites.lua`: for every game.dll page any witness of this tree or of the
DLL sits on (46 pages), one one-byte `ret` on that page, found in the decrypted capture by following the code
from real call and jump targets, with the eight bytes at the site. Once the runtime has observed the ship actor,
`main.lua` steps the warm-up one page per frame: a still-unreadable page is VirtualQuery-checked (committed,
PAGE_NOACCESS, image or mapped), logged, then gets one FFI call to its `ret`; the game's own handler decrypts
the page; the eight bytes are read back and must match. The hotkey waits for the warm-up. No game memory is
written. Checked live 2026-10-30 03:04 through LLtM, on the ship inside a frame: page `+0x9c0000` went from
protection 1 to 0x20 and read back as the capture. Build `.1` ran the whole table inside the loader's enable at
boot and the process ended there three times (no dump, no shutdown line); `.2` is the stepped form.

## How the port was made

| Step | Tool | Evidence |
|---|---|---|
| Lua addresses | `unport.py` | every address line of the original matched (addresses masked) to the proven LuaJIT port, literals copied in order; 283 lines; the rest listed |
| Hand-finished lines | `assemble.py` `HAND`, `HAND_ONLY`, `KEEP` | each names the line, the old literal, the new one and where it comes from |
| Witnesses | `maps/bridge/witnesses.py` (verify) | every located witness of the assembled tree is `same` against the 26251122 capture (`out/verify-original-lua.json`); the DLL source likewise (`out/verify-original-dll.json`) |
| Weapon menu DLL | `unport_cpp.py`, `build_dll.py` | the release `weapon_menu.cpp` with health/stamina bars; 32 shared ABI rows from the two recorded maps (6AB3B43F→26088801 probe mappings ∘ 26088801→26251122 literals-wm), which equal the ported rows; the four vitals functions at −0x17EDB0 with prologues from the capture; Zig 0.14.1, x86_64-windows-gnu |
| DLL fixture | `build_dll.py` | the release fixture moved the same way; every mode under Wine (`dll/build-receipt.json`) |
| Lua fixtures | `port_fixtures.py`, `run_lua_fixtures.py` | the release fixtures given the sources' own build-constant substitutions; run with LuaJIT (`out/lua-fixture-results.json`) |

Decisions that are not address swaps:
- `support_catalogue.lua`, `terminal_icons.lua`: the port's files (LAS-44 Nova, AMW-20 Apex, icons 34 and 35).
- `backend.lua`: 412 base locomotion definitions (408 on 6AB3B43F); the control-word readability window starts at `pc+0xFD8` (the row moved by 8 bytes; the port read it 8 bytes late, harmless but wrong).
- `animation_blend.lua`, `animation_controller.lua`: the port's files. On 26088801 and later the blend-pair definition table is not loaded, so `supported=false` and the controller skips that step. `blend_pairs_fixture.lua` is therefore not run.
- `runtime.lua` `photo_state`: the current War Journalist publishes `DBF_PHOTO_MODE_OWNER`; that branch is added ahead of the original discovery.
- `main.lua`: the warm-up runs once in `start()` before the runtime is built; `start_off` behaviour (0.1.16+) is kept.
- Not run: `ffi_binding_cache_fixture.lua`, `runtime_registry_fixture.lua` (older compat trees the package does not ship).

## Files

- `out/goose_bridge_combat/`: the assembled package; `out/goose_bridge_combat-RECEIPT.json` its hashes and counts.
- `dll/`: moved DLL source and fixture, `BridgeCombatWeaponMenu-<sha12>.dll`, `build-receipt.json`.
- Stage and install: `builds/26251122/mods/bridge-combat/stage_original.py`, `install-original.sh [--revert]` (game closed).
