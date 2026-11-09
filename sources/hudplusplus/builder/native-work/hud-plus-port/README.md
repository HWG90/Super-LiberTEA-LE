# HudPlusPlus on build 26251122

**Modular checkout:** this is the original port research/build record. For edits to the refactored
runtime, use [`../../../README.md`](../../../README.md) and `../../../tools/build.py`; this historical
builder reads the original bundle and local captures rather than the editable `src/` modules.

HudPlusPlus is HD2 HUD+ 0.2.9 rebuilt for game build 26251122 and renamed (2026-11-03) because nearly
everything in it was re-derived or changed. Arsenal shows it as "HudPlusPlus" (package folder
`HudPlusPlus-LuaJIT-26251122`); its GUID, LLL addon name `mods/hd2_hud/hd2_hud_plus` and settings file are
unchanged, so existing profile rows and settings carry over.

HUD+ 0.2.9 (Nexus 15298, file 69465) was made for the LuaJIT build 25480438. It needs LuaJIT and FFI,
so on 26251122 it runs only under LLL's LuaJIT boot (Arsenal profile "LuaJIT Proton").

## What the port changes

- **Values:** HUD+ finds about 1,250 native values (functions, globals, struct offsets, counts) with
  771 byte patterns. They are re-resolved for 26251122 and baked in, with the build pin moved to
  26251122's `helldivers2.exe` and `game.dll`. On that build HUD+ uses the baked values and never scans.
- **Unresolved values** are listed in `game.data.unresolved`. On the pinned build HUD+ reports them as
  missing, and its own feature graph switches off every module that needs one.
- **Other builds:** HUD+ refuses ("unsupported-build") instead of scanning. A scan reads code pages the
  protection runtime has not decrypted yet.
- **Start-up:** HUD+'s boot script `f476df93691895fa` is dropped (LLL owns the boot resource). The bundle
  `mods/hd2_hud/hd2_hud_plus` gets an `-- HD2-Addon:` header. LLL loads it as an archive addon, and its
  `on_enable` calls `entry.start(_G)` as the boot script did.
- **Assets:** textures and materials are copied byte for byte.
- **Stratagems and weapons:** HUD+ has no item lists. It reads the game's own tables, so new items
  appear once bounds, strides and enum ids are right (e.g. SOS stratagem 0x91→0x95, 2 new explosion
  kinds, weapon data registry 730→746 slots, eagle 20→22, projectile weapons 542→556).

## How values were found (`data/`, `tools/`)

1. `tools/resolve_offline.lua` runs HUD+'s own resolver (`native.signatures`) over the 26251122
   captures (`builds/26251122/capture/*.merged.bin`).
2. `tools/rederive.py` re-derives patterns that no longer match. For each one it:
   - disassembles the old bytes;
   - locates the old function in `native-work/evidence/game-pre1020.dll` (HUD+'s own build);
   - aligns instruction shapes into the new image, breaking ties with operand values, known globals
     and migrated callees;
   - falls back to `migrate_rvas.py` hints and, when the 26251122 page was never captured, to the
     26088801 image (game.dll code did not move; values only).
3. Padding masked: many patterns span `int3` padding that the protector refills each build
   (`data/rederive/rederive-pad.json`).
4. `data/manual-26251122.json`: values found by hand, each with the new site it was read at.
5. `tools/component_map.py`: the per-component accessors are one template, so each one is pinned to
   its type's registry table, with old and new tables aligned by their capacity sequence. This caught
   weapon_data_find landing on the heat accessor.
6. Gates in `build_port.py`: every call target must match its recorded head (up to refilled padding),
   be explained in `HEAD_EXPLAINED`, or come from the component map; colliding targets are dropped.

## Build

    python3 -I build_port.py --dry-run      # writes REPORT-26251122.json
    python3 -I build_port.py                # writes ~/.config/hd2arsenal/mods/HD2-HUD-Plus-0.2.9-LuaJIT-26251122

The builder refuses while a core module (`game.panel/ui/weapon/weapon_options/equipment/world_inputs`
and what they require) has an unresolved value, because HUD+ would refuse to start.

## State (2026-11-03, r9)

- All 1253 values resolved; nothing unresolved; no module off. Package r8 is in the Arsenal library
  (version "0.2.9 · LuaJIT 26251122 r9") and in the LuaJIT Proton profile.
- r9: in game r8 stopped when HUD+ built its Options page ("menu-bound-setting"): menu_inert_setting had
  been re-derived as 0x64, a setting with a description. The settings descriptor table (12 groups of
  0xd8-byte records walked by menu_descriptor) still has 0x8b unchanged and inert (value type 0,
  description 0), as are 0x8c-0x91; pinned 0x8b. Live with 0x8b the page showed (user, 14:00).
- r8: the last 68 values (plus 4 delivery extras) re-derived offline by four parallel subagents, each
  value re-checked here against the images and recorded in `data/manual-26251122.json` with evidence:
  Options page (23; menu_finish_simple by its tail-jump caller, bodies identical), 3D weapon panel (17;
  reload handlers via the action-script dispatcher and id-aligned scripts, bodies identical; magazine
  offsets unchanged), eagle/bombardment preview (18; bombardment_manager by reference usage, pattern
  table byte-identical, heading float moved settings+0x1c -> +0x28), stratagem pick, map-pin enums and
  mesh offsets (unchanged), line_object_add_circle exe 0x4f1200 (exe unwind records give a function entry
  there with HUD+'s prologue; add_line's shift agrees). Its page stays locked in normal play. HUD+ checks
  no heads on a pinned build (settle() runs only after a scan), so its first ground decal calls that
  entry and the game unlocks the page, as for its own first call.
  Builder: a hand-proven value now stands over a distrusted pattern; a call target on an uncaptured page
  passes only if listed in UNCAPTURED_CALLS with proof it is a function entry; manual values may be lists. With
  weapon_3d resolved the world_hud `wanted` stop-gap drops out: r8's code is HUD+'s own plus r4's guard.
- r7: in game r6's HUD+ switched itself off mid-mission (Runtime.running false; HUD+ stops on any step error
  and reports nowhere under LLL). Found live with LLtM wrappers around its components and natives:
  1. `unit_alive` (exe) was 0x984cc0, one of 6 wrappers fitting HUD+'s short head; the world HUD's
     third-person body check faulted inside it ("C++ exception" in pcall). The real one, 0x1f4cb0, calls
     the same unit lookup (0xa06a0) as unit_world_pose and sits at the Unit functions' shift (-0xa200).
     New gate: a call target whose shift is outside its neighbours' (below/above) is refused.
  2. features.world_hud require()s features.weapon_3d, which HUD+'s data does not list, so the off
     weapon_3d ran inside it and hit a nil magazine value. The builder now finds such hidden requires;
     this one is answered by rewriting weapon_3d's `wanted` to false, any other refuses the build.
  Both fixes ran live 13:04-13:07: 20208 unit_alive calls, 9300 world HUD frames, no fault.
- r6: page 0x819000 decrypted when the user fired an Arc Thrower (2026-11-03 07:51) and was captured
  07:52. HUD+'s whole 611-byte arc fire-row pattern matches; all five arc values equal 0.2.9 (map 0x48,
  rows +0x70, stride 0x28, interval +0xc, wait +0x8). Backpack and world HUD (stratagem indicators and
  cooldowns) are on, plus weapon cycle. Still off: 3D weapon HUD (game.reload: distrusted action-script
  handlers), eagle attack preview (game.delivery/eagles/attackers), map pins (resource_inputs), stratagem
  pick (stratagem_input_avatar), ground decals, the Options page (game.menu_rows).
- r5: page 0x16b1000 was first captured 2026-11-03 07:37, in a squad mission (hot join). The game ran it
  itself, so solo play really does skip it. The squad/stratagem-card HUD update is 1580 of 1583 instructions
  identical to 0.2.9 (shift -0x17f110). New from HUD+'s own sites: card size 0x14f0, squad slots 0x7ef0 / 0x678,
  squad death 0xa3f8, stratagem_record 0x11fc750 (the HUD function's own call; its head reads the history count
  at +0x2d800 = 32 x the new stride 0x16c0), history data +0x38. card_ready 0x1 and row_mission 0x191 are
  confirmed by pattern. Corrected: dead_label 0xf887a2ea (HUD+'s site 0x16b135a, as 0.2.9; r4 had a wrong
  re-derivation, unused while squad was off) and reinforce_stratagem 0x7f (manual pin: the site 0x16b1b90
  matches 0.2.9's 0x1830ca0; the offset-masked pattern also hits unrelated 0x6b86a2, where r4's 0x66 came
  from). Squad status is on. The stratagem and stratagem_cooldown modules resolve, but HUD+ draws them only
  inside features.world_hud, which requires features.pack -> game.pack -> the five arc_weapon values. So the
  stratagem indicators and cooldowns stay hidden until page 0x819000 is captured: the arc fire row continues
  there (interval/wait are the disp8s at new 0x8190a6/0x8190ac, 0.2.9 0xc/0x8). Its captured part (to
  0x818fff) is 121 of 121 instructions identical to 0.2.9 (shift +0xcb80); the first real ret on the page is
  far in, so the page is left to the game (fire an arc weapon). `arc_weapon_tail` in live-targets flags it.
- r4 = r3's values plus a read guard. On 2026-11-03 07:14 a hot join crashed the game in LuaJIT's string hash:
  HUD+'s reinforce walker (`game.reinforcement` -> `game.ability_script` code_reader) read 16 bytes at
  game+0xf74ff1, 15 bytes of a readable page plus the first byte of a no-access one (0xf75000 - 15; a `ret`
  sits there). `Channel:text` read memory with a plain `ffi.string`. `build_port.py` now rewrites it to ask
  VirtualQuery about every page a read touches and answer nil for one that is not committed and readable;
  HUD+'s decoder already treats nil as a failed read. `tests/test_channel_text.lua <bundle>` checks it with a
  fake VirtualQuery (r3 fails 6 of 9 cases, r4 passes all).
- On: weapon row HUD, health and stamina, reticle, throw distance, trajectory preview, stratagem indicators
  and cooldowns (world HUD), backpack, squad status, call colour, kill pulse, corpse and reinforce markers.
  r8: everything on.
- r1 loaded but drew nothing: `roots_hud_manager_rva` had been re-derived onto `hud_scene_manager`'s global
  (0x2ce1508, a 1-of-3 alignment), so the HUD manager never read as built and HUD+'s panel never turned
  ready. r2 takes 0x2e28788 from a field-use vote (rip loads whose register then takes +0x24e334/+0x24e340;
  the same vote gives 0.2.9's own 0x346d538 on its build) and a live read in a mission. The collision gate
  now covers globals too: two different 0.2.9 globals on one new address are refused.
- r3 adds hand values (`data/manual-26251122.json`): booster loop (0x2cb6240, 21 rows of 0x38, +0x20),
  flat picture material, explosive kind (+0x24 at new 0x8db27a), guide length (+0x7c at new 0xa29ae4, the
  eagle record grew), shield waits (+0x50/0x88/+0x4c at new 0x65a8f0), and 0.2.9's ammo icon material back
  (r2's came from a different function).
- Waiting on encrypted pages:
  - game 0x16b1000: the middle of the squad/stratagem-card HUD update (0x16b0ab3-0x16b25d3, 0.2.9's
    0x182fbc3 shifted by -0x17f110; both neighbouring pages match it instruction for instruction). It holds
    card size/ready, row mission, squad slots/death and stratagem_record_find, which keep stratagem,
    cooldown, squad and world HUD off. Solo play may never run it. **Do not touch it with a `ret` call.** On
    2026-11-03 07:01 a raw FFI call to the c3 byte at 0x16b10fa (the ModRM byte of `movaps xmm0,xmm11`,
    41 0f 28 c3) crashed the game: the minidump shows an unhandled execute fault at game+0x16b10fa, so the
    protection runtime did not decrypt the page for it. Bridge's warm-up (`goose_bridge_combat`
    `src/code_warmup.lua`) only touches real `ret` instructions reached by code flow, and those work; this
    page has none (0.2.9 has no ret in that span). Every saved 26088801 image has the page encrypted too
    (entropy 7.96), so it has to come from a session where the game runs that code (likely a squad with
    other players), or the values have to be found in other code. Retried 07:10 in one session: a real ret at
    0x16b0364 (`pop rbp; ret`) decrypted page 0x16b0000 (protection 0x1 to 0x20, bytes as captured), then
    0x16b10fa crashed again with the same dump. The rule is the site, not the game state.
  - game 0x819000: the tail of the arc-weapon fire row (interval, wait); map/rows/stride are confirmed
    unchanged at 0x818e4a. It blocks backpack and, with the action scripts, the 3D HUD.
- HUD+ keeps no log under LLL (no report_event). To see its state live, find its Runtime through the
  upvalues of the global `update` chain with LLtM (`program.panel.ready`, `program.weapon_hud.visible`).
