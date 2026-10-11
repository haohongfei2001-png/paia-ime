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

## Corrected-clock native result and retained first-key risk

Head `ca630d5a2289ca223731ad5a0391d426468484f7`, B1 run
[38100452479](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38100452479),
job 114355132099, passed. The 57-file complete archive SHA256 is
`f981756280f9be2fb33c05ea0a6225d42fa833d8558815bfd8dc25426cf478bd`.

Independent review decoded all 1,000,017 native records (32,000,544 bytes),
recomputed every aggregate/per-operation percentile/max and reconciled counters.
There were 911,616 key calls, 33,150 selections and 55,251 clears; 88,401 authored
episodes, 88,397 once-only commits, 4,995,761 assertions, all 32 schemas,
11,116 created/destroyed sessions, zero native-step failures, no discarded samples,
no containment failures and no before/after candidate drift. The separate actual
host XCTest passed 32 episodes/128 inserts. These are not installed-client events.

Key-only native p99 was 0.665 ms and owner p99 0.717 ms. Owner maximum 98.207 ms
is retained; all-operation owner counts above 2/16.7/33/100 ms were 450/2/1/0.
The maximum is record340, first `u` of first traditional Flypy workload session;
calibration reproduces that position at 86.314 ms. A local deterministic replay
of the schedule matched every native record kind when locating these tails.
The original “all-schemas-warmed” checkpoint name was overly strong: diagnostic
sessions were destroyed. It is corrected to diagnostic-sweep-complete and a
separate cold/warm/zero-owner lifetime diagnostic is added, without prewarming
or deleting the million workload’s first-key costs. Full G02/init/visible-latency
performance qualification remains open.

100 two-session RSS observations ranged 55,230,464–55,427,072 bytes; first to last
increased 147,456 bytes (144 KiB). Whole-process peak was 55,427,072 bytes. Replay
wall/CPU were 116.683/114.857 seconds, including harness work. Three startup
children measured only default Full/Simplified/ASCII (open-to-first-snapshot
4.161–6.620 ms), not all-mode cold startup. These cloud-runner observations are
not M1-budget acceptance. The exact-head native lifetime diagnostic, remaining
CI, final/main and recovery checks are still pending at this document revision.
