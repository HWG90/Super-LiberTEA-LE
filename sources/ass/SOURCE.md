# Diver's Best Friend (ASS) R46, LuaJIT 26251122 (LE build)

The LLL folder mod as shipped (plain LuaJIT; no native files). Built from
`native-work/dbf-ass-luajit/divers_best_friend` of the Linux HD2 workspace, commit `ee120fba73893be85dadf71f665fc1f8b97252d4`.
The LE build leaves out DBF-HUD's weapon readout that the port also started (six `src/weapon_status*.lua`
modules and their lines in main.lua; `package/build_package.py`, ASS_DROPPED and ASS_MAIN).
