# LuaJIT boot runtime for Steam build 26251122

`hd2_luajit_runtime_8a19f22d787b667c.dll`: fcd57d52 with LLL's release label renamed to `R38-26251122-luajit.1`
in the embedded source; nothing else changed. Live from 2026-10-30 21:27 with the same handoff counts as fcd57d52.
fcd57d52 was live from 2026-10-29 15:21 ("handoff complete: 120 modules mirrored, 5 ports kept, 1799 natives, 4
forwarders, timed GC on") and is the rollback.

- Source: `../vm-poc` and `../vm-trace` at this commit, ported from the R6 baseline (previous commit) by evidence
  only: identical function bodies moved by their own delta, data globals checked by content, call targets decoded at
  moved sites, the Steam language table found by content (0x16FAA60 -> 0x16F9E10). Struct offsets are untouched.
  `vm-poc/prepare_resources.py` (new) regenerates `work/resource_witness.h` from the capture.
- Optional Quaternion / Matrix4x4 / box ports keep their 26088801 witnesses and are deferred on 26251122 with the
  originals bridged, as designed.
- Embedded LLL: `lll-26251122-luajit-ffi.lua` (sha256 ba2148a7..., release `R38-26251122-luajit.1`), made by
  `make_embedded_lll.py` from `../boot-r6-reconstruct/lll-r35-luajit-ffi.lua`. It checks that its build values alone
  still give fcd57d52's source 3952146e... before it applies the label.
- `probe_harness.c`: offline check under Wine against the 26251122 capture (10/10; controls fail both ways).
- `STAGE-RECEIPT.json`: what was staged, the rollback, and the live result.

## Rebuild

    SOURCE_DATE_EPOCH=$((0x6ae36ded)) bash build_runtime_26251122.sh <dir>/hd2_lua_environment.dll

The output must be named `hd2_lua_environment.dll` (the export table holds the name). Run from the update
workspace's `builds/26251122/runtime/` directory and the result is byte-identical to 8a19f22d... (fcd57d52... with
the 3952146e source); from any other directory only the debug info's working directory differs. `prepare_handoff.py`
embeds the LLL source named by `HD2_HANDOFF_LLL` and `HD2_HANDOFF_LLL_SHA256`. The generated `vm-poc/work/` files are gitignored:
the `prepare_*.py` generators recreate them from the 26251122 capture (paths point at the update workspace,
`~/Projects/Linux HD2 Mods/builds/26251122/runtime/images/`). Evidence, rewrite tools and the address maps live in
that workspace (`builds/26251122/runtime/`, `maps/boot-runtime*.json`).

## In-process build (LLL without native helpers)

`build_runtime_26251122_inproc.sh` adds `../vm-poc/lll_host.c` (`-DHD2ENV_LLL_HOST`): LLL's in-process Steam service
(LLL `native/steam_inproc.c`, copied with `steam_pointer.c` and `steam_keyboard.c` into `../vm-poc/lll_native/`,
pinned by `SHA256SUMS`), registered as `package.preload['hd2.lll_host']` before LLL runs. It embeds
`lll-26251122-luajit-inproc.lua` from `make_embedded_lll_inproc.py`: ba2148a7 with four substitutions (no launcher,
`transport_inproc.lua`, the cffi path `hd2-runtime:ffi`, the font reading memory through the service). In LuaJIT mode
LLL then starts no Steam helper or launcher and loads no cffi or nativeinfo DLL; the label stays
`R38-26251122-luajit.1`. Without `HD2ENV_LLL_HOST` the handoff is unchanged. Offline checks: LLL's
`native/test_steam_inproc.c` (Wine, against the real service) and `inproc_test/` (LLL's `platform.lua` over the runtime's
registration). Staging and rollback: `INPROC-STAGE.json`.

    python3 -I make_embedded_lll_inproc.py
    HD2_HANDOFF_LLL=$PWD/lll-26251122-luajit-inproc.lua HD2_HANDOFF_LLL_SHA256=<its sha256> python3 -I -B ../vm-poc/prepare_handoff.py
    cd "<update workspace>/builds/26251122/runtime" && SOURCE_DATE_EPOCH=$((0x6ae36ded)) bash <this folder>/build_runtime_26251122_inproc.sh <dir>/hd2_lua_environment.dll
