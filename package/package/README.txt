Super LiberTEA - LE (Linux Edition) 1.0.6                     Helldivers 2 Steam build 26568081

LINUX / PROTON ONLY. IT WILL NOT WORK ON NATIVE WINDOWS (system error 577 for the LuaJIT runtime and cffi DLLs).
One HD2 Arsenal mod. Import it, deploy it, play.

WHAT IS INSIDE
  Live Lua Loader R38 (LuaJIT)       R38-26568081-luajit.1: hands the game's Lua over to LuaJIT and runs the mods below
  Mod Configuration Menu (DBF-MCM)   0.1.74-luajit.8: the in-game settings menu the other mods use
  DBF Modular 0.1.0-dev.25           Diver's Best Friend R46 with the Bracket HUD (the default DBF choice)
  Diver's Best Friend (ASS) R46      stratagem wheel and list selection, cooldown dock, hotkeys (the other DBF choice)
  Vanilla Plus Megapack v42          all 25 of its mods, LuaJIT 26568081 port (includes Mod Options Menu and Mod Bindings Menu)
  Goose Bridge Combat                0.1.17-experimental-26568081.1 (experimental)
  War Journalist (Proton) 1.4.0      Photo Mode with bone posing and saved poses (build bfbaca9), with the 1.2.0 assets
  Goose Gadget Kit LE                @GADGET@ with only the Spawner (and its loadout editor) and First Person pages
  Nova Weapon FOV 0.1.0              the LAS-44 Nova keeps its 3.5x look at the 2.5x and 1x scope zooms
  DiverKit 8.14.31 r11               loadout presets, randomizer, Transmog support
  HD2 Transmog Foundation 0.2.4      armor, helmet and cape looks with independent stats
  Smarter Guard Dogs & Sentries 5.2.0

INSTALL (game closed)
1. In HD2 Arsenal disable any other Live Lua Loader, Bingus Shared Loader, Boot Mod Loader or Chef Shared
   Loader, and any separate copy of the mods above (LLL runs their loaders itself).
2. Import this ZIP. Every option is on; pick the sub-options you want (Transmog, Guard Dogs), and the DBF in
   "Live Lua Loader R38 (LuaJIT) + LLL mods": DBF Modular (default) or Diver's Best Friend R46 LE. Only one DBF runs.
3. Keep it LAST in the load order (with first-mod priority on, keep it FIRST), then Purge / Deploy.
4. Start the game. The Mod Configuration Menu holds the settings of every mod.

WHAT THE FIRST START WRITES
Everything goes to %LOCALAPPDATA%\LLL\Helldivers2 inside the game's Proton prefix, i.e.
  steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2
- LLL's own files, exactly as LLL R38-26568081-luajit.1 writes them: the LuaJIT runtime, cffi, nativeinfo,
  the Steam helper and launcher, Native\luajit-boot.enable and Service\game-root.txt.
  Logs\LLL-files.log: "R38-26568081-luajit.1 files: 0 written, 7 in place" on later starts.
  Coming from 1.0.4, the first start switches a Native\luajit-boot.enable that names 1.0.4's runtime to the new
  one, once; "off" and any other name are kept. The old build's files stay beside the new ones.
- The LLL mods, into Mods\dbf_mcm, Mods\dbf_modular or Mods\divers_best_friend (your DBF choice),
  Mods\goose_bridge_combat, Mods\dbf_freecam, Mods\goose_temporary_unlocks and Mods\goose_nova_weapon_fov. A mod folder is installed when it has no manifest.json, and kept up to date
  while it holds what this package wrote. If you installed another build of one of these mods yourself, that
  folder is left alone, and so is any file you changed. A folder that holds only a development shim (a main.lua
  that loads the mod from a file elsewhere by drive path) is moved to Backups\<mod>-shim-<time> as it is, and the
  mod installed. SuperLiberTEA\<mod>.txt records what was written; a file an earlier release wrote and this one
  no longer ships is removed, unless you changed it. Switching the DBF choice moves the other DBF folder to
  Backups\<mod>-superlibertea-<time> when this package wrote it; a DBF you installed yourself is left alone and
  reported (turn one off in LLL.cfg: only one DBF can run).
  Logs\SuperLiberTEA-files.log: "Super LiberTEA - LE 1.0.6 mods: 0 written, N in place" on later starts,
  followed by "set aside: ..." or "left alone: ..." when it moved or skipped something.
Settings live in LLL\Helldivers2\Settings and are never touched.

TURNING THINGS OFF
- Arsenal options (Megapack mods, Guard Dogs parts, Transmog parts, DiverKit, the WJ assets):
  untick them in Arsenal, then Purge / Deploy. Keep "Live Lua Loader R38 (LuaJIT) + LLL mods" on.
- One LLL mod: set it to false in LLL\Helldivers2\LLL.cfg, for example ["goose_bridge_combat"] = false,
  inside the "enabled" table. LLL then skips that folder.
- LuaJIT off, LLL on: write the word off into Native\luajit-boot.enable and restart (deleting the file does not
  work: the next start writes it again). LLL then runs in the game's Lua 5.1.

REMOVE
Disable the mod in Arsenal and Purge / Deploy. To clear the files too, delete LLL\Helldivers2\SuperLiberTEA and
the Mods folders above, and LLL's files listed in LLL's README.

KNOWN LIMITS
- Steam build 26568081 only. After a game update LLL, the runtime and the mods check the game's exe and
  game.dll and refuse to run until they are updated.
- Better Lobby Management (Megapack): Lobby Region and squad messages are off on this game build.
- Bridge Combat is experimental. Gadget Kit's Spawner works as local host in a solo mission.
- War Journalist captures screenshots with its Linux host worker; Wine's capture API is a stub.

CHANGES
1.0.6  Diver's Best Friend R46 LE is back, ported to Steam build 26568081: pick your DBF in Arsenal again, DBF
       Modular (the default) or Diver's Best Friend R46 LE; switching moves the other one to Backups. HudPlusPlus
       Modular for build 26568081, as a separate download.
1.0.5  For Steam build 26568081 (the game update of 2026-11-11). Live Lua Loader R38-26568081-luajit.1 and every
       mod re-ported to the new build: DBF-MCM luajit.8, DBF Modular dev.25, Bridge Combat 26568081.1, War
       Journalist (Proton) 1.4.0, Nova Weapon FOV, DiverKit r11, Transmog, Smarter Guard Dogs & Sentries and the
       Megapack's 25 mods. Gadget Kit LE on @GADGET@: smoother True First Person (weapon offset pop guard, hitch-proof
       transitions, eased aim gait). DBF Modular is the one DBF: Diver's Best Friend R46 LE and HudPlusPlus are not
       in this release (no build for the new game version yet); a Diver's Best Friend that 1.0.4 installed moves
       to Backups.
1.0.4  Pick your DBF in Arsenal: DBF Modular (new, the default) or Diver's Best Friend R46 LE; switching moves the
       other one to Backups. War Journalist 1.4.0 (Proton). Gadget Kit LE on @GADGET@ (the rebuilt first-person
       camera). Nova Weapon FOV, new. DBF-MCM luajit.7 (faster menus). DiverKit r10 and Transmog: loadouts prepare
       weapon and stratagem selection before Apply. Diver's Best Friend R46: HUD+ stratagem handoff fixes. Know Your
       Constellation: the forecast panel keeps the player card and bottom prompts clear. HudPlusPlus Modular.
1.0.3  HudPlusPlus, HD2 HUD Plus 0.2.9 rebuilt for build 26251122, as a separate download. Gadget Kit LE's spawner:
       a support weapon that cannot be delivered ends its request instead of holding every later one, and a refused
       request shows its reason instead of "Action completed".
1.0.2  War Journalist 1.3.4 (Proton) with bone posing: pose a diver bone by bone in the Subject tab and keep up to
       99 poses. Bridge Combat .12: Armory weapon swaps no longer crash, and combat starts in multiplayer sessions.
       Diver's Best Friend no longer starts DBF-HUD's weapon readout (published R46 never had it); the first start
       removes its six files from your Mods folder. Gadget Kit LE's First Person starts again (four of its modules
       were left out of the LE manifest since 1.0.0). LLL Compat Test (loader test mods) is gone. Each item is also
       a separate download on the release page.
1.0.1  The Megapack no longer names a folder on the packaging machine (a helper DLL path its code never used).
       A Mods folder that holds only a development shim is moved to Backups and the mod installed: on the
       packaging machine, Diver's Best Friend failed to load from such a shim.
1.0.0  First release.

SEPARATE DOWNLOADS
The release page also has each item on its own: Live Lua Loader and the Arsenal mods as Arsenal zips, the LLL mods
(DBF-MCM, DBF Modular, Diver's Best Friend, Bridge Combat, War Journalist, Gadget Kit LE, Nova Weapon FOV) as folders
for LLL\Helldivers2\Mods (install one DBF only).
HudPlusPlus (HD2 HUD Plus 0.2.9 rebuilt for build 26568081) is only a separate download: an Arsenal mod that needs
Live Lua Loader, with its row before the loader's.
Use either this package or the separate downloads, not both.

CREDITS AND SOURCE
CREDITS.txt names every author. LICENSES\ holds the licence notices. FILES-SHA256.txt lists this archive.
Source of every item: https://github.com/HWG90/Super-LiberTEA-LE
