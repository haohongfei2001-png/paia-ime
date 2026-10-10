#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/b1-env.sh
# Exact same official engine, source headers and compiler family as G01; no new resource.
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  Tools/MixedProbe/main.cc "$PAIA_RIME_LIBRARY" \
  -Wl,-rpath,"$(dirname "$PAIA_RIME_LIBRARY")" -o .build/paia-mixed-probe
user="$(mktemp -d "$PWD/.build/mixed-probe-user.XXXXXX")"
trap 'rm -rf "$user"' EXIT
.build/paia-mixed-probe "$PAIA_B1_SHARED" "$user"
