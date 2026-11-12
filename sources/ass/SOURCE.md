# Diver's Best Friend (ASS) R46, LuaJIT 26568081 (LE build)

The LLL folder mod as shipped (plain LuaJIT; no native files). Built from
`native-work/dbf-ass-luajit/divers_best_friend` of the Linux HD2 workspace, branch `indev/dbf-ass-26568081`,
commit `fb2e47b3fc2319e4b7c3f8f51a2dbeba72220603` (the port to game build 26568081).
The LE build leaves out DBF-HUD's weapon readout that the port also started (six `src/weapon_status*.lua`
modules and their lines in main.lua; `package/build_package.py`, ASS_DROPPED and ASS_MAIN).
