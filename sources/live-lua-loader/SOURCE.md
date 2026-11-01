# Live Lua Loader (LLL) R38

HWG90/LLL, branch `LLL_JIT_Live`, commit `8b25fad588bd31c774e49ce78bcf83999776ed57` (tag `R38-26251122-luajit.2`).
The Lua 5.1 LLL in the boot patch is composed from this tree (`tools/build_steam_release.py`); the LuaJIT runtime
embeds its in-process variant (see `../luajit-runtime`). The drop-in boot patch is built by `package/lll-dropin/`.
