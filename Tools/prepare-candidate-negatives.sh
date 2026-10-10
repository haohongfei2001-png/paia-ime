#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .build/a1-env.sh
root=.build/candidate-negative-components
test ! -e "$root"
mkdir "$root"
python3 - "$root" <<'PY'
from pathlib import Path
import sys
source=Path('Tools/G01Bridge/paia_g01.cc').read_text();marker='#include "paia_mixed.cc"'
assert source.count(marker)==1
(Path(sys.argv[1])/'g01-only.cc').write_text(source.replace(marker,'// Authored ABI-negative build: independent mixed table intentionally absent.'))
PY
cp "$PAIA_RIME_LIBRARY" "$root/librime.1.dylib"
clang++ -std=c++17 -stdlib=libc++ -Wall -Wextra -Werror -Wno-unused-parameter \
  -ISources/CRimeShim/include -ISources/CRimeShim -isystem .build/a2-headers/src -isystem .build/a2-boost \
  -dynamiclib "$root/g01-only.cc" "$PAIA_RIME_LIBRARY" -Wl,-rpath,@loader_path \
  -Wl,-install_name,@rpath/paia-g01.dylib -o "$root/paia-g01.dylib"
otool -L "$root/paia-g01.dylib"
echo 'CANDIDATE_NEGATIVE_COMPONENT compiled authored G01-only table; never bundled as a supported candidate component'
