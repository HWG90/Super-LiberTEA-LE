# LuaJIT boot runtime hd2_luajit_runtime_d6c1aec33706b30e.dll

The Linux HD2 workspace, branch `indev/runtime-26568081`, commit `427ebdfb96719ef94ca3e2e41c7234ff919cf418`: the three folders the runtime is built
from. `runtime-modules/boot-26568081/build_runtime_26568081_inproc.sh` is the build; the shipped DLL's sha256 is
d6c1aec33706b30ead9d335f0ae759219141af1322770a383e09c6d32b28b309. LuaJIT 2.1 itself is upstream LuaJIT (MIT),
linked as `libluajit.a`. `boot-handoff/tools/lua32` is the stock Lua 5.1.4 compiler that compiles the boot chunk.
