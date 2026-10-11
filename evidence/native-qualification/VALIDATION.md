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

## Native owner-lifetime diagnostic and bounded correction

Head `6688b7ea0f11259d22c243afa0e2249198338edc`, B1 run
[38101398041](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38101398041),
job 114357883809 passed. Original 62-file artifact SHA256:
`2dc62d5187cad499d80a8f8768c2618a6b5bcb5a0dd6c02c0af720877b3c4ac8`.
Independent review verified the exact receipt, archive bytes, compiled inventory
and source lifecycle. Four owner timings were 153.602 / 0.064 / 0.127 / 99.577 ms;
native action timings were 153.392 / 0.026 / 0.065 / 99.475 ms. The final cold
reactivation's CPU was 98.576 ms. There were 24 real keys, 4 clears, 28 snapshots,
5 created/destroyed sessions, no native failure and unchanged candidates including
actual 輸入法 after every probe. The 153.602 ms observation exceeds 120 ms on this
hosted runner; it is retained, not dismissed by percentiles or earlier 98 ms.
The separate million again completed 1,000,017 operations and actual host
32 episodes/128 inserts; owner maximum was 90.054 ms. This checkpoint made no
production initialization change.

The next minimal correction uses a startup-owned cleared/no-learning native ID
on a fixed public traditional schema. Managed startup/lifetime/million paths
use this same initializer; unprimed controls and all prior raw records remain.
The extra owner is counted in RSS/lifecycle, initialization cost is included in
startup-ready time, and no host/user input is used. A deliberately modified
compiled-copy negative must fail after seven real C keys, clean the owner and
reject runtime retry. Public/restored-personal product tests additionally check
authority bytes, reactivation and close. Python verifier now passes 6 tests
locally. Swift/AppKit/native correction execution and final/main remain pending.

## Production initialization path: native result and another retained tail

Head `5275e9d97c55f652de8d7fc18aabb30379687d53`, B1 run
[38102452331](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38102452331),
job 114361012022 passed. Original 73-file artifact SHA256:
`6c81d82eb9aa37a80b7e56f9a04fc2b81617576e912d3852e2a29556bd60980c`.
Independent review verified every extracted byte and all million records.

Within this run's identical compiled pack, unprimed four-phase owner times were
95.724 / 0.062 / 0.065 / 105.304 ms. Production-initialized times were
0.190 / 0.067 / 0.125 / 0.238 ms, including reactivation after zero host owners.
The expected partial-initialization failure crossed seven successful C keys and
seven snapshots, with zero C failures/selection/clear, one created/destroyed owner,
and rejected same-process retry without counter changes. No learning/userdb or
resource modification was found. The actual bounded host again passed 32/128.

All 1,000,017 native operation records, 911,616 keys, 33,150 selections, 55,251
clears, 88,397 once-only commits, 4,995,763 assertions and 11,117 created/destroyed
native owners reconcile. The private owner's seven startup keys are outside the
million denominator and inside the actual cumulative counters. Timing binary
SHA256 is `bee5208139fa1aa3604c314dbb4a222e91d02d4bd5987696167e951477f4e50e`.
Key native/owner p99 were 0.608/0.643 ms, but owner maximum was **278.061 ms**.
This is retained, not treated as a pass against a per-key latency budget.

The maximum is zero-based record 44533, episode 3937, Full/Simplified
with Chinese punctuation (`paia_b1_full_punct`), fourth `shurufa`'s final `a`.
Native action was 278.019 ms, copy 0.022 ms. All-operation owner counts above
2/16.7/33/100 ms were 135/1/1/1. The next largest was 6.638 ms. Independent schedule
reconstruction found the same location at 0.092/0.110 ms in the earlier two
million runs; each run has 345 matching schema/scenario/final-key observations,
whose earlier maxima were 0.495/0.254 ms and managed maximum excluding this
preserved point was 0.527 ms. These cross-run controls share pinned source,
dictionary table/OpenCC and schedule, but independently compiled schema/prism
hashes differ, so they are not called byte-identical compiled-pack comparisons.
Without per-key CPU, this single tail cannot be assigned to either scheduler
noise or an algorithm regression.

All managed initialization receipts span 82.881–127.393 ms, including calibration;
three default startup open-to-first-snapshot observations are 85.871–109.567 ms.
These time the research runtime, not candidate resource checks/helper setup or a
whole installed service. Idle RSS with the retained owner is 29.64–34.19 MiB,
versus approximately 8 MiB in the earlier unprimed startup observations: there is
a real idle-memory tradeoff. Million steady RSS was 36.02–37.48 MiB, peak 37.52 MiB;
this is not a cross-machine memory-improvement claim. Replay wall/CPU were
105.197/102.219 seconds including harness work.

A separate fixed first-50k diagnostic is now added using the same seed/schedule,
managed initializer and immutable pack. Each operation retains the original wall
record plus a process-CPU bracket in a separate binary. It covers the original
position with its prefix and repeated same-scenario observations. Process CPU
includes measurement overhead and other threads, not native-thread CPU. No CPU
calls are added inside the million process's per-operation path. The diagnostic
cannot substitute for the million, remove the 278 ms point or qualify G02 if the
point does not recur. Python verifier 7/7 passes; new native execution, candidate
product lanes and final/main remain pending at this revision.

## Preserved candidate lifecycle counter failure

The same `5275e9d` checkpoint finished with 11 workflows successful and one real
IMK failure, run
[38102452335](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38102452335),
job 114361065707. Its public candidate stage reached actual initialization, G01
repair and mixed host operations, then the new post-close assertion found 71
bridge-owned sessions created versus 72 destroyed. Later candidate restarts,
resource publication/recovery, release compatibility and downstream IMK stages
were skipped. Earlier expected-red controls are separate from this genuine failure.

Independent source review identified a missing creation counter on successful
G01 trial ownership transfer. The existing live count and later destroy count
already included that returned native session. A bounded counter correction also
accounts for remaining exported trials actually released by cleanup_all_sessions.
It does not remove the assertion or change candidate selection/input semantics.
Counters explicitly describe shim-owned/exported native IDs; internal G01 scratch
and Mixed shadows are outside this diagnostic boundary. The extension-free million
has none of those excluded extension owners.

New native tests cover returned-trial cancellation, adoption, real failed-search
non-export, and a pending proposal closed with its runtime followed by late cancel
and repeated close. The close test has its own SwiftPM target and filtered test
process under the existing A2 job. Static independent review passed; actual macOS
execution and the failed IMK stage must still pass on a new head.

Local GCC strict C and ABI/ASan/UBSan checks pass with the explicit POSIX feature
macro. The first Linux C11 command omitted that macro and failed on declarations
of strdup/strnlen; its original output is retained. Compiler diagnostics were not
weakened. LeakSanitizer remains unavailable under the already recorded ptrace
boundary, so local leak detection is not claimed.
