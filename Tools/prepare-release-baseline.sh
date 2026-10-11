#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
baseline=d2f9d62b3d34dba79e958aa1b42e2437691f8d19
destination="$PWD/.build/release-n-source"
test ! -e "$destination"
if ! git cat-file -e "$baseline^{commit}"; then
  git fetch --no-tags --depth=1 origin "$baseline"
fi
test "$(git rev-parse "$baseline^{commit}")" = "$baseline"
mkdir -m 700 "$destination"
git archive "$baseline" | tar -x -C "$destination"
# Reuse only already downloaded public research caches. The untouched baseline
# preparer verifies its own lock file again; nothing enters the shipped pack.
mkdir "$destination/.build"
cp -R .build/a2-cache "$destination/.build/"
# Do not copy extracted Boost headers: the baseline preparer re-extracts its
# own headers from the reverified pinned archive rather than trusting N+1 output.
(
  cd "$destination"
  python3 Tools/prepare-a1.py
  python3 Tools/prepare-a2.py
  bash Tools/build-imk.sh
  swift build --build-tests
)
python3 Tools/release-inventory.py freeze
