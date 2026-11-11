#!/usr/bin/env bash
# Build the in-process LuaJIT boot runtime for 26568081: build_runtime_26568081.sh's exact compile line plus
# ../vm-poc/lll_host.c (LLL's in-process Steam service, HD2ENV_LLL_HOST) and bcrypt for its handshake hash check.
# The embedded LLL must be lll-26568081-luajit-inproc.lua (prepare_handoff.py with HD2_HANDOFF_LLL); the vendored LLL
# sources must match ../vm-poc/lll_native/SHA256SUMS.
# Usage: build_runtime_26568081_inproc.sh <output dll>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$(cd "$HERE/../vm-poc" && pwd)"; OUT="$1"
R="/home/goose/Documents/ChatGPT/Linux HD2/runtime-modules"; L="$R/live-load/2026-10-24"
(cd "$V/lll_native" && sha256sum --quiet -c SHA256SUMS)
grep -q '^#define HANDOFF_LLL_SHA256 "'"$(sha256sum "$HERE/lll-26568081-luajit-inproc.lua" | cut -d' ' -f1)"'"$' "$V/work/handoff_assets.h" \
  || { echo "work/handoff_assets.h does not embed lll-26568081-luajit-inproc.lua: run prepare_handoff.py with HD2_HANDOFF_LLL" >&2; exit 1; }
# environment_gc64.c is ../vm-poc/environment.c for the GC64 LuaJIT (two lines differ). Every build up to 43e3c88d
# compiled the r6 copy; HD2_ENVIRONMENT_FROM_SOURCE=1 derives it from this tree's environment.c into work/ instead
# (the derivation of environment.c at 810b8a94 equals the r6 copy byte for byte).
ENVIRONMENT="$L/build-boot-r6/environment_gc64.c"
if [ "${HD2_ENVIRONMENT_FROM_SOURCE:-}" = 1 ]; then
  ENVIRONMENT="$V/work/environment_gc64.c"
  sed -e '/^#define LUAJIT_DISABLE_GC64$/d' \
      -e 's/^_Static_assert(!LJ_GC64,"collector adapter requires the pinned FR1 runtime");$/_Static_assert(LJ_GC64,"live candidate requires GC64");/' \
      "$V/environment.c" > "$ENVIRONMENT"
  grep -q '^_Static_assert(LJ_GC64,"live candidate requires GC64");$' "$ENVIRONMENT" \
    || { echo "environment.c no longer has the FR1 lines the GC64 derivation replaces" >&2; exit 1; }
fi
SRCS=()
for f in engine_curve frame_routes lifecycle_routes boot_routes shutdown_routes gc_routes engine_steam engine_friends engine_voip engine_vectors engine_puc engine_resources lll_host; do SRCS+=("$V/$f.c"); done
x86_64-w64-mingw32-gcc -std=c11 -O2 -g -Wall -Wextra -Werror -shared -DHD2ENV_DLL -DHD2ENV_LLL_HOST \
  "-ffile-prefix-map=$V=$R/vm-poc" \
  "-I$L/build-gc64/LuaJIT/src" "-I$V" "-I$V/work" \
  "$ENVIRONMENT" "${SRCS[@]}" \
  "$L/build-gc64/LuaJIT/src/libluajit.a" -lbcrypt -Wl,--image-base=0x1e9650000 -o "$OUT"
