#!/usr/bin/env bash
# Build the LuaJIT boot runtime for 26251122 from runtime-modules/vm-poc. Same compile line as the reconstructed R6 build
# (reconstruct/build_runtime.sh, which reproduces the deployed 4eb60fd4… byte for byte), quoted for paths with spaces.
# The LuaJIT library and environment_gc64.c are the pinned R6 inputs; they hold no build-specific data.
# Usage: build_runtime_26251122.sh <output dll>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$(cd "$HERE/../vm-poc" && pwd)"; OUT="$1"
R="/home/goose/Documents/ChatGPT/Linux HD2/runtime-modules"; L="$R/live-load/2026-10-24"
SRCS=()
for f in engine_curve frame_routes lifecycle_routes boot_routes shutdown_routes gc_routes engine_steam engine_friends engine_voip engine_vectors engine_puc engine_resources; do SRCS+=("$V/$f.c"); done
x86_64-w64-mingw32-gcc -std=c11 -O2 -g -Wall -Wextra -Werror -shared -DHD2ENV_DLL \
  "-ffile-prefix-map=$V=$R/vm-poc" \
  "-I$L/build-gc64/LuaJIT/src" "-I$V" "-I$V/work" \
  "$L/build-boot-r6/environment_gc64.c" "${SRCS[@]}" \
  "$L/build-gc64/LuaJIT/src/libluajit.a" -Wl,--image-base=0x1e9650000 -o "$OUT"
