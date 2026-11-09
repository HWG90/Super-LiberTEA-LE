# War Journalist (Proton) 1.4.0

HWG90/DBF_PhotoMode, branch `codex/wj-proton-lua51-parity-20261106` (the Proton line with the Lua 5.1 changes
merged in), commit `71eec8afc94f21be0cad3a3bb4b02c840d22439f`. The LLL folder mod `dbf_freecam` is built by
`python3 tools/build_proton_candidate.py` (build 20261106.0355-71eec8a). Its two native bridges
(`hd2_nativeinfo_c1578203689e39b9.dll`, `hd2_nativeinfo_8db3d96f8c3cbb24.dll`) come from `tools/build_steam_native_bridge.py`
and `tools/build_steam_scene_bridge.py`. The 1.2.0 assets (compiled game resources) ship as they are; their shader
sources are under `freecam/assets/`.
