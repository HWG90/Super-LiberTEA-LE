# Live Lua Loader (LLL) R38

HWG90/LLL, branch `indev/lll-26568081`, commit `1cd9948dc34cf1756c54a046fd93a60e45da636b` (package `R38-26568081-luajit.1`; LLL still reports
`R38-26251122-luajit.1`, the name War Journalist checks). The Lua 5.1 LLL in the boot patch is composed from this
tree (`tools/build_steam_release.py`); the LuaJIT runtime embeds its in-process variant (see `../luajit-runtime`).
The drop-in boot patch is built by `package/lll-dropin/build_lll_boot.py`. The Megapack's conversions under
`bingus-conversions/` are the 26251122 ones; the 26568081 ports as shipped are in `../vanilla-plus-megapack`.
