#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a2-env.sh
# Same Apple clang/libc++ family and C++17 as the pinned official macOS build.
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  -dynamiclib Tools/G01Bridge/paia_g01.cc "$PAIA_RIME_LIBRARY" \
  -Wl,-rpath,"$(dirname "$PAIA_RIME_LIBRARY")" -o "$PAIA_G01_LIBRARY"
otool -L "$PAIA_G01_LIBRARY"
