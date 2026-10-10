#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/b1-env.sh
root="$(mktemp -d "$PWD/.build/mixed-probe.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir "$root/engine" "$root/control-user" "$root/projected-user"
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
# Negative control: run the prior unprojected selection algorithm over the same
# authored matrix, in a separate process/user directory. Only the specific native
# replay failure with verified source isolation qualifies; setup/crash is failure.
set +e
"$root/probe" "$PAIA_B1_SHARED" "$root/control-user" unprojected > "$root/control.log" 2>&1
control_status=$?
set -e
cat "$root/control.log"
test "$control_status" -eq 1
grep -Fq 'MIXED_NATIVE_PROBE_FAILED actual Chinese replay failed' "$root/control.log"
grep -Fq 'MIXED_NATIVE_FAILURE_SOURCE_UNCHANGED' "$root/control.log"
echo 'MIXED_NATIVE_UNPROJECTED expected native replay rejection; source preserved'
"$root/probe" "$PAIA_B1_SHARED" "$root/projected-user" projected
