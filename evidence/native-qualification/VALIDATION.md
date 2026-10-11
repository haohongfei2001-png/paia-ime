# Native qualification checkpoints

Baseline main: `724489972285286be60fef5c7bab72b8bc980fee`.

Implementation checkpoint: pending first Mac CI. No million native event result
or resource/latency success is claimed by this initial document.

Local Linux checks: Python supervisor verifier 5/5, A1/A2 pin/privacy audits,
Python parsing and diff whitespace checks pass. Native Swift/AppKit is unavailable
locally. The clang command was unavailable. GCC strict C compilation and the ABI harness
pass; ASan/UBSan pass with leak detection disabled because LeakSanitizer itself
fails under this executor’s ptrace. The original sanitizer failure is retained;
this is not a successful local leak check. macOS CI keeps its original sanitizer
configuration. SIMULATED verifier inputs
include a forced disposable child timeout/reap, truncated records, wrong native
denominators, impossible component duration and symlink/byte changes.

The existing B1 public standard macos-15 lane now builds the release tool and
runs independent deployment, three startup children, 10k calibration, fixed
million replay and bounded 32-episode IMK protocol host. Full logs/records and
expected-red verifier controls remain available in each exact-SHA artifact.

[Contract and limits](../../docs/NATIVE_QUALIFICATION.md). ENGINE_NATIVE and
APPKIT_HOST remain distinct from INSTALLED_IME/LIVE_CLIENT/HUMAN_STUDY. The
research corpus is explicit and unbundled; default candidate remains 46 authored
rows. All other original release/quality/long-duration gates remain open.
