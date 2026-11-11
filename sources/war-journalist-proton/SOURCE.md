# War Journalist (Proton) 1.4.0

HWG90/DBF_PhotoMode, branch `indev/wj-proton-26568081` (the Proton line, ported to game build 26568081),
commit `bfbaca96a50022d0a51447ea1287dd57ce87da3c`. The LLL folder mod `dbf_freecam` is built by `python3 tools/build_proton_candidate.py`
(build 20261111.1439-bfbaca9). Its two native bridges (`hd2_nativeinfo_85c81f8434fb71a6.dll`, `hd2_nativeinfo_d1b77f77f5bafd40.dll`)
come from `tools/build_steam_native_bridge.py` and `tools/build_steam_scene_bridge.py`. The 1.2.0 assets (compiled
game resources) ship as they are; their shader sources are under `freecam/assets/`.
