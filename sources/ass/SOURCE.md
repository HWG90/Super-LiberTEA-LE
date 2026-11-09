# Diver's Best Friend (ASS) R46, LuaJIT 26251122 (LE build)

The LLL folder mod as shipped (plain LuaJIT; no native files). Built from
`native-work/dbf-ass-luajit/divers_best_friend` of the Linux HD2 workspace, branch `indev/optimistic-proskuriakova-e07a63`,
commit `c16101e5c4b41e43fe33b3702ad5bba951f2bed6` (with the HUD+ stratagem handoff fixes).
The LE build leaves out DBF-HUD's weapon readout that the port also started (six `src/weapon_status*.lua`
modules and their lines in main.lua; `package/build_package.py`, ASS_DROPPED and ASS_MAIN).
