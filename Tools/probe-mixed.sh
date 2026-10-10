#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/b1-env.sh
root="$(mktemp -d "$PWD/.build/mixed-probe.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir "$root/engine" "$root/user"
# The verified archive member librime.1.16.0.dylib advertises this install-name.
# Resolve it only inside this disposable probe tree; do not rewrite/sign binaries
# or alter system loader configuration. The pinned engine bytes remain unchanged.
ln -s "$PAIA_RIME_LIBRARY" "$root/engine/librime.1.dylib"
# Exact same official engine, source headers and compiler family as G01; no new resource.
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  Tools/MixedProbe/main.cc "$PAIA_RIME_LIBRARY" \
  -Wl,-rpath,"$root/engine" -o "$root/probe"
otool -L "$root/probe"
"$root/probe" "$PAIA_B1_SHARED" "$root/user"
