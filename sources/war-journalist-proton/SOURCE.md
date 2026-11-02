# War Journalist (Proton) 1.3.4, bone posing

HWG90/DBF_PhotoMode, branch `claude/wj-proton-bone-posing` (the bone-posing line on top of `WJ-Proton` 9613fcf),
commit `09a0940cb45ebcc5dbe2b7e4bbe043ef1df77f7b`. The LLL folder mod `dbf_freecam` is built by
`python3 tools/build_proton_candidate.py` (build 20261102.1740-09a0940). Its two native bridges
(`hd2_nativeinfo_c1578203689e39b9.dll`, `hd2_nativeinfo_8db3d96f8c3cbb24.dll`) come from `tools/build_steam_native_bridge.py`
and `tools/build_steam_scene_bridge.py`. The 1.2.0 assets (compiled game resources) ship as they are; their shader
sources are under `freecam/assets/`.
