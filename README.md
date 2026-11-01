# Super LiberTEA - LE (Linux Edition)

![Super LiberTEA - LE](package/package/icon.png)

One HD2 Arsenal mod that brings Live Lua Loader with LuaJIT and a full set of mods to Helldivers 2 on Linux. Import it, deploy it, play.

**Linux / Proton only. Helldivers 2 Steam build 26251122 only.** It will not work on native Windows.

## What's inside

| Item | Version |
|---|---|
| Live Lua Loader R38 (LuaJIT) | R38-26251122-luajit.2 |
| LLL Compat Test | Chef Shared Loader / Boot Mod Loader test mods |
| Mod Configuration Menu (DBF-MCM) | 0.1.74-luajit.5 |
| Diver's Best Friend (ASS) | R46, LuaJIT 26251122 |
| Vanilla Plus Megapack ("Bingus Pack") | v42, all 25 mods, LuaJIT 26251122 |
| Goose Bridge Combat | 0.1.17-experimental-26251122.10 (experimental) |
| War Journalist (Proton) with assets | 1.3.3, WJ-Proton branch (9613fcf), assets 1.2.0 |
| Goose Gadget Kit LE | 0.5.10, Spawner and First Person only |
| DiverKit | Alpha 8.14.31, LuaJIT 26251122 r6 |
| HD2 Transmog Foundation | 0.2.4, LuaJIT 26251122 |
| Smarter Guard Dogs & Sentries | 5.2.0, LuaJIT 26251122 |

## Install

1. Download `Super-LiberTEA-LE-1.0.0-26251122.zip` from [Releases](../../releases).
2. Close the game. In HD2 Arsenal, disable any other Live Lua Loader, Bingus Shared Loader, Boot Mod Loader or Chef Shared Loader, and any separate copy of the mods above.
3. Import the zip. Every option is on; pick the sub-options you want (Transmog, Guard Dogs).
4. Keep it **last** in the load order (with first-mod priority on, keep it first), then Purge / Deploy.
5. Start the game. The Mod Configuration Menu holds every mod's settings.

The first start writes LLL's files and the LLL mods into `%LOCALAPPDATA%\LLL\Helldivers2` inside the game's Proton prefix (`steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2`). If you already installed your own build of one of those mods, it is left alone. `README.txt` in the zip explains what is written, how to turn a single mod off and how to remove everything.

## Source

Everything that goes into the zip is here, item by item. Each folder's `SOURCE.md` names the repository, branch and commit it came from.

| Folder | What |
|---|---|
| `sources/live-lua-loader` | LLL, HWG90/LLL `LLL_JIT_Live` at 8b25fad |
| `sources/luajit-runtime` | the LuaJIT boot runtime `hd2_luajit_runtime_9a596e2f766ff92c.dll` |
| `sources/lll-compat-test` | LLL Compat Test |
| `sources/dbf-mcm` | DBF-MCM |
| `sources/ass` | Diver's Best Friend (ASS) |
| `sources/vanilla-plus-megapack` | the Megapack's 25 mods as ported (Lua) |
| `sources/bridge-combat` | Bridge Combat and its weapon menu DLL builder |
| `sources/war-journalist-proton` | War Journalist, HWG90/DBF_PhotoMode `WJ-Proton` at 9613fcf |
| `sources/gadget-kit` | Goose Gadget Kit 0.5.10 (the LE changes are in `package/gadget-kit-le`) |
| `sources/diverkit`, `sources/transmog`, `sources/smarter-guard-dogs` | the ported mods' Lua, by option |
| `package/` | how the zip is built: `build_package.py`, the boot install block `mods_install.lua`, its Wine test, and `lll-dropin/` (LLL's drop-in boot patch builder) |

`package/RECEIPT.json` records every input and output hash of the release build; `SHA256SUMS.txt` has the zip's hash.

## Credits

See [CREDITS.md](CREDITS.md). The Megapack, Smarter Guard Dogs & Sentries, DiverKit and Transmog are other authors' mods, ported to LuaJIT and this game build; all credit for the mods themselves goes to them. There is no repository-wide licence: each item keeps its own (see the licence files in each folder and `LICENSES/` in the zip).
