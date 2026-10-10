#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/habit-env.sh
root="$(mktemp -d "$PWD/.build/habit-probe.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir "$root/engine" "$root/user"
ln -s "$PAIA_RIME_LIBRARY" "$root/engine/librime.1.dylib"
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  Tools/HabitProbe/main.cc "$PAIA_RIME_LIBRARY" -Wl,-rpath,"$root/engine" -o "$root/probe"
otool -L "$root/probe"
"$root/probe" "$PAIA_HABIT_SHARED" "$root/user"
