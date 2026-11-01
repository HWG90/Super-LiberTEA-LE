# LuaJIT boot runtime hd2_luajit_runtime_9a596e2f766ff92c.dll

The Linux HD2 workspace, branch `claude/runtime-lll-inproc`, commit `ccafae1a6403a58804ca24c5e3e04120e48a93f5`: the three folders the runtime is built
from. `runtime-modules/boot-26251122/INPROC-STAGE.json` gives the build command and the expected sha256
(9a596e2f766ff92ca3a7234f4fc7a9add5e2b0e5d1bb1c02acb65b2b1c68ef64). LuaJIT 2.1 itself is upstream LuaJIT (MIT),
linked as `libluajit.a`. `boot-handoff/tools/lua32` is the stock Lua 5.1.4 compiler that compiles the boot chunk.
