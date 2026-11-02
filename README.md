# Super LiberTEA - LE (Linux Edition)

![Super LiberTEA - LE](package/package/icon.png)

One HD2 Arsenal mod that brings Live Lua Loader with LuaJIT and a full set of mods to Helldivers 2 on Linux. Import it, deploy it, play.

**Linux / Proton only. Helldivers 2 Steam build 26251122 only.** It will not work on native Windows.

## What's inside

| Item | Version |
|---|---|
| Live Lua Loader R38 (LuaJIT) | R38-26251122-luajit.2 |
| Mod Configuration Menu (DBF-MCM) | 0.1.74-luajit.5 |
| Diver's Best Friend (ASS) | R46, LuaJIT 26251122, without DBF-HUD's weapon readout |
| Vanilla Plus Megapack ("Bingus Pack") | v42, all 25 mods, LuaJIT 26251122 |
| Goose Bridge Combat | 0.1.17-experimental-26251122.12 (experimental) |
| War Journalist (Proton) with assets | 1.3.4 with bone posing (09a0940), assets 1.2.0 |
| Goose Gadget Kit LE | 0.5.10, Spawner and First Person only |
| DiverKit | Alpha 8.14.31, LuaJIT 26251122 r6 |
| HD2 Transmog Foundation | 0.2.4, LuaJIT 26251122 |
| Smarter Guard Dogs & Sentries | 5.2.0, LuaJIT 26251122 |

## Install

1. Download `Super-LiberTEA-LE-1.0.2-26251122.zip` from [Releases](../../releases).
2. Close the game. In HD2 Arsenal, disable any other Live Lua Loader, Bingus Shared Loader, Boot Mod Loader or Chef Shared Loader, and any separate copy of the mods above.
3. Import the zip. Every option is on; pick the sub-options you want (Transmog, Guard Dogs).
4. Keep it **last** in the load order (with first-mod priority on, keep it first), then Purge / Deploy.
5. Start the game. The Mod Configuration Menu holds every mod's settings.

The first start writes LLL's files and the LLL mods into `%LOCALAPPDATA%\LLL\Helldivers2` inside the game's Proton prefix (`steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2`). If you already installed your own build of one of those mods, it is left alone; a folder that only holds a development shim (a `main.lua` that loads the mod from a file elsewhere) is moved to `LLL/Helldivers2/Backups` and the mod installed. A file an earlier release wrote and this one no longer ships is removed, unless you changed it. `README.txt` in the zip explains what is written, how to turn a single mod off and how to remove everything.

## Separate downloads

Each item is also on the release page on its own. Use either the full package or the separate downloads, not both. Every separate zip has a `SUPER-LIBERTEA-LE.txt` with its install steps and what it needs.

| Download (`Super-LiberTEA-LE-<version>-26251122-…`) | Install |
|---|---|
| `Live-Lua-Loader-R38-LuaJIT.zip` | Arsenal mod, last in the load order. Everything else needs it |
| `War-Journalist-Assets.zip`, `DiverKit.zip`, `Smarter-Guard-Dogs.zip`, `Vanilla-Plus-Megapack.zip`, `Transmog.zip` | Arsenal mods |
| `DBF-MCM.zip`, `Divers-Best-Friend.zip`, `Bridge-Combat.zip`, `War-Journalist-Proton.zip`, `Gadget-Kit-LE.zip` | LLL mods: extract the folder into `%LOCALAPPDATA%\LLL\Helldivers2\Mods` in the game's Proton prefix |

Diver's Best Friend uses Mod Bindings Menu (in the Megapack); War Journalist uses its assets; Gadget Kit LE's pages are in DBF-MCM.

## Source

Everything that goes into the zip is here, item by item. Each folder's `SOURCE.md` names the repository, branch and commit it came from.

| Folder | What |
|---|---|
| `sources/live-lua-loader` | LLL, HWG90/LLL `LLL_JIT_Live` at 8b25fad |
| `sources/luajit-runtime` | the LuaJIT boot runtime `hd2_luajit_runtime_9a596e2f766ff92c.dll` |
| `sources/dbf-mcm` | DBF-MCM |
| `sources/ass` | Diver's Best Friend (ASS) |
| `sources/vanilla-plus-megapack` | the Megapack's 25 mods as ported (Lua) |
| `sources/bridge-combat` | Bridge Combat and its weapon menu DLL builder |
| `sources/war-journalist-proton` | War Journalist, HWG90/DBF_PhotoMode bone-posing line (on `WJ-Proton`) at 09a0940 |
| `sources/gadget-kit` | Goose Gadget Kit 0.5.10 (the LE changes are in `package/gadget-kit-le`) |
| `sources/diverkit`, `sources/transmog`, `sources/smarter-guard-dogs` | the ported mods' Lua, by option |
| `package/` | how the zip is built: `build_package.py`, the boot install block `mods_install.lua`, its Wine test, and `lll-dropin/` (LLL's drop-in boot patch builder) |

`package/RECEIPT.json` records every input and output hash of the release build; `SHA256SUMS.txt` has the zip's hash.

## Changes

- **1.0.2**: War Journalist 1.3.4 with bone posing (pose a diver bone by bone in the Subject tab, keep up to 99 poses). Bridge Combat .12: Armory weapon swaps no longer crash, and combat starts in multiplayer sessions. Diver's Best Friend no longer starts DBF-HUD's weapon readout, which published R46 never had; the first start removes its files. Gadget Kit LE's First Person starts again: four of its modules were missing from its manifest since 1.0.0. LLL Compat Test is gone. Every item is also a separate download.
- **1.0.1**: the Megapack no longer names a folder on my machine (a helper DLL path its code never used), and a mod folder that only holds a development shim is moved to `Backups` and replaced with the real mod. On my machine, Diver's Best Friend failed to load from such a shim.
- **1.0.0**: first release.

## Credits

See [CREDITS.md](CREDITS.md). The Megapack, Smarter Guard Dogs & Sentries, DiverKit and Transmog are other authors' mods, ported to LuaJIT and this game build; all credit for the mods themselves goes to them. There is no repository-wide licence: each item keeps its own (see the licence files in each folder and `LICENSES/` in the zip).
