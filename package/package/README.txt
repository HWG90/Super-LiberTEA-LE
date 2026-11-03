Super LiberTEA - LE (Linux Edition) 1.0.3                     Helldivers 2 Steam build 26251122

LINUX / PROTON ONLY. IT WILL NOT WORK ON NATIVE WINDOWS (system error 577 for the LuaJIT runtime and cffi DLLs).
One HD2 Arsenal mod. Import it, deploy it, play.

WHAT IS INSIDE
  Live Lua Loader R38 (LuaJIT)       R38-26251122-luajit.2: hands the game's Lua over to LuaJIT and runs the mods below
  Mod Configuration Menu (DBF-MCM)   0.1.74-luajit.5: the in-game settings menu the other mods use
  Diver's Best Friend (ASS) R46      stratagem wheel and list selection, cooldown dock, hotkeys (no DBF-HUD weapon readout)
  Vanilla Plus Megapack v42          all 25 of its mods, LuaJIT 26251122 port (includes Mod Options Menu and Mod Bindings Menu)
  Goose Bridge Combat                0.1.17-experimental-26251122.12 (experimental)
  War Journalist (Proton) 1.3.4      Photo Mode with bone posing (build 09a0940), with the 1.2.0 assets
  Goose Gadget Kit LE                0.5.10 with only the Spawner and First Person pages
  DiverKit 8.14.31 r6                loadout presets, randomizer, Transmog support
  HD2 Transmog Foundation 0.2.4      armor, helmet and cape looks with independent stats
  Smarter Guard Dogs & Sentries 5.2.0

INSTALL (game closed)
1. In HD2 Arsenal disable any other Live Lua Loader, Bingus Shared Loader, Boot Mod Loader or Chef Shared
   Loader, and any separate copy of the mods above (LLL runs their loaders itself).
2. Import this ZIP. Every option is on; pick the sub-options you want (Transmog, Guard Dogs).
3. Keep it LAST in the load order (with first-mod priority on, keep it FIRST), then Purge / Deploy.
4. Start the game. The Mod Configuration Menu holds the settings of every mod.

WHAT THE FIRST START WRITES
Everything goes to %LOCALAPPDATA%\LLL\Helldivers2 inside the game's Proton prefix, i.e.
  steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2
- LLL's own files, exactly as LLL R38-26251122-luajit.2 writes them: the LuaJIT runtime, cffi, nativeinfo,
  the Steam helper and launcher, Native\luajit-boot.enable and Service\game-root.txt.
  Logs\LLL-files.log: "R38-26251122-luajit.2 files: 0 written, 7 in place" on later starts.
- The LLL mods, into Mods\dbf_mcm, Mods\divers_best_friend, Mods\goose_bridge_combat, Mods\dbf_freecam and
  Mods\goose_temporary_unlocks. A mod folder is installed when it has no manifest.json, and kept up to date
  while it holds what this package wrote. If you installed another build of one of these mods yourself, that
  folder is left alone, and so is any file you changed. A folder that holds only a development shim (a main.lua
  that loads the mod from a file elsewhere by drive path) is moved to Backups\<mod>-shim-<time> as it is, and the
  mod installed. SuperLiberTEA\<mod>.txt records what was written; a file an earlier release wrote and this one
  no longer ships is removed, unless you changed it.
  Logs\SuperLiberTEA-files.log: "Super LiberTEA - LE 1.0.3 mods: 0 written, 254 in place" on later starts,
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
the five Mods folders above, and LLL's files listed in LLL's README.

KNOWN LIMITS
- Steam build 26251122 only. After a game update LLL, the runtime and the mods check the game's exe and
  game.dll and refuse to run until they are updated.
- Bridge Combat is experimental. Gadget Kit's Spawner works as local host in a solo mission.
- War Journalist captures screenshots with its Linux host worker; Wine's capture API is a stub.

CHANGES
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
(DBF-MCM, Diver's Best Friend, Bridge Combat, War Journalist, Gadget Kit LE) as folders for LLL\Helldivers2\Mods.
HudPlusPlus (HD2 HUD Plus 0.2.9 rebuilt for build 26251122) is only a separate download: an Arsenal mod that needs
Live Lua Loader, with its row before the loader's.
Use either this package or the separate downloads, not both.

CREDITS AND SOURCE
CREDITS.txt names every author. LICENSES\ holds the licence notices. FILES-SHA256.txt lists this archive.
Source of every item: https://github.com/HWG90/Super-LiberTEA-LE
