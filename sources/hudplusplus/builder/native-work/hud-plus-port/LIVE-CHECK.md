# First launch checks (HudPlusPlus, LuaJIT 26251122, build r9)

- LiveLuaLoader.log: `mods/hd2_hud/hd2_hud_plus: loaded` (not "enable failed").
- r9: the Options page shows (confirmed live with r8 + the 0x8b fix, 2026-11-03 14:00).
- r8: everything on. The first ground decal runs exe 0x4f1200 on a still-locked page (a function entry); a
  crash at that moment would point there. Check: Options page in the game menu, 3D weapon panel (ammo,
  reserve, backpack ammo such as flamethrower fuel), eagle/orbital attack preview, map pins; HUD+ stays
  running (no recorded errors).
- r7 ACCEPTED 2026-11-03 13:16 by the user in a mission ("yep"); live: running, 18459 world HUD frames, no errors.
- r7: HUD+ must stay on through a mission in third person (r6 switched itself off). Live check:
  `program` reached through the update upvalues, `running` stays true.
- r6: stratagem indicators and cooldowns (in the world HUD) and the backpack gauge show (new in r6).
- r5: squad status shows with other players (new in r5); reinforce markers still show (reinforce id now
  0x7f). Stratagem indicators/cooldowns do not show yet: they live in the world HUD, which waits on the backpack.
- r4: joining a mission in progress (hot join, other players' abilities) must not crash; r3 crashed there.
- Features on in r3/r4 (r3 added the trajectory preview to r2's list): body (health/stamina), call colour, corpse markers, kill pulse, reinforce markers,
  reticle, throw distance, weapon row HUD. Everything else is switched off by design until its values are found.
- Inferred values to read live: `component_card_ready` (0x1) and `stratagem_row_mission` (0x191).
- If the game crashes on load: switch the HUD+ row off in Arsenal and redeploy; the 0.2.9 original is
  untouched in the library.
- HUD+ writes no log under LLL. If nothing shows, read its panel live through LLtM: `program.panel.ready`
  and `program.weapon_hud.visible` must turn true in a mission (r1 stayed false: wrong HUD manager global).
