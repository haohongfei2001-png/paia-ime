#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'This probe requires macOS with Xcode Command Line Tools.' >&2; exit 2; fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ime-appkit-study.XXXXXX")"
# Does not register an input source, launch an installer, read user text, or use a network.
xcrun swiftc "$ROOT/NativeProbe.swift" -o "$WORK/probe"
"$WORK/probe" > "$WORK/result.json"
cat "$WORK/result.json"
printf '\nGenerated results remain in %s\n' "$WORK"
