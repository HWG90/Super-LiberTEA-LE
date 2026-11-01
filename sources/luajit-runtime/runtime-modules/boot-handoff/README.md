# LuaJIT boot handoff (build 26088801)

LLL R35 owns the game's boot script (`f476df93691895fa`, deployed as
`data/9ba626afa44a3aa3.patch_94`). The installed boot is LLL's exact source with
`prologue.lua` in front, compiled by a 32-bit stock Lua 5.1.4. That compiler
reproduces the original LLL chunk byte for byte, so the game ABI is exact.

- **Marker absent** (`%LOCALAPPDATA%/LLL/Helldivers2/Native/luajit-boot.enable`, whose first line names the runtime DLL):
  the prologue does nothing and LLL runs in PUC exactly as before.
- **Marker present:** the prologue loadlibs `hd2_luajit_runtime_<sha16>.dll`
  (`luaopen_hd2_luajit_boot`, `vm-poc/handoff.inc`). That creates LuaJIT, keeps the
  validated ports, bridges every other native and runs LLL's exact source in LuaJIT. It then points the engine's
  `init/update/render/shutdown` at LuaJIT. Any failure before LLL starts in
  LuaJIT falls back to LLL in PUC. The runtime log is `LLL/Helldivers2/Logs/LuaJITBoot.log`.

Enable: `python3 enable_boot.py <runtime.dll>`. Disable: `python3 enable_boot.py --disable` (no game files touched). Full rollback (game and Arsenal closed):

    python3 install_boot_patch.py --rollback backups/20261024-205934

Rebuild: `python3 build_boot_patch.py <32-bit lua> <runtime dll>`, then
`python3 install_boot_patch.py` (dry run) and `--apply`.
Offline checks of all three prologue paths passed (absent marker, unavailable
runtime, successful handoff). Not yet booted in the game.
