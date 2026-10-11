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

## First real Mac checkpoint: preserved timing failure

Initial head `16d2d5b59aff509677bd2346da853d90a405f310`, B1 run
[38099791225](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38099791225),
job 114353162198. Actual native Swift/debug host and release tool compile passed;
existing B1 controls, 5 supervisor tests and 2 pure schedule/record tests passed.

Separate deployment and all three fresh-process startup children succeeded.
Calibration completed 10,001 native operations (9,115 key, 332 selection, 554
clear), 886 episodes and 884 once-only commits, with 50,675 assertions, no native
step failure, complete 32-schema coverage, stable candidate diagnostics and
balanced final lifecycle. The supervisor then FAILED before starting the million:
record index 340 had owner 84,518,083 ns versus native action 84,451,000 ns plus
C copy 80,000 ns, a 12,917 ns component-over-owner discrepancy. All 10,001 raw
records and full 44-file artifact remain intact, SHA256
`223ccd58f3608dc9cd4a55cc1a0cb12cb203cd486bf14116d76cf7e8ecbdd9c5`.

The nested timers used two different clocks: Swift DispatchTime and C
CLOCK_MONOTONIC. The correction shares the C clock for owner and components,
including the old A1 benchmark. It does not clamp values, delete the outlier,
relax the containment assertion or change the million denominator. New exact-head
native execution remains pending. No million or bounded host result exists for
the initial checkpoint; earlier gates did not make the B1 run successful.
