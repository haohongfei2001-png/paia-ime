# Native reliability and resource qualification

This engineering node implements the original REPORT §15.3 million-event replay
and separates native timing/resource measurements requested by HANDOFF §4. It
uses the same pinned, explicit unbundled strong research corpus and 32 B1 schemas.
No corpus is newly distributed or claimed cleared for production. The candidate
bundle still defaults to 46 authored dictionary rows.

## Reproduce without installation

Use the existing public macos-15 B1 workflow. It keeps its 35-minute job ceiling
and runs no server, input-source registration, user profile, signing operation,
new runner/service or model. After the existing pinned A1/A2/B1 preparation:

```
source .build/b1-env.sh
swift test --filter QualificationCoreTests
swift build -c release --product paia-qualification
python3 Tools/test-native-qualification.py
python3 Tools/run-native-qualification.py
```

`swift test` builds the separate QualificationHostTests bundle, which the
supervisor invokes with `--skip-build` only after the native replay completes.
All runtime user directories are fresh disposable directories created by the
supervisor. All test text is authored. Logs, every completed binary timing record,
receipts, input/compiled/user-directory inventories and failures are retained
under evidence/b1-run/qualification. Corpus and engine binary bodies are excluded.

## Fixed native gate and independent oracles

A separate child deploys the authored A1 schema and all 32 research schemas,
then closes. Its exact compiled output and pinned source/OpenCC inputs are
inventoried. Each measured child uses a reverified copied precompiled tree,
`schemas: []`, `g01Library: nil`, and zero deploy calls. The existing verified
extension guard is unchanged. Ordinary engine/session behavior is measured;
retained G01 and typed-mixed extension correctness keep their dedicated suites.

Three fresh-process startup runs, specifically default Full/Simplified/ASCII,
are separate from deployment. They do not qualify every mode’s first input. A
separate native lifetime diagnostic observes first traditional Flypy `u`, a
same-session warmed key, a new traditional session while a simplified sentinel
still lives, and reactivation after all native sessions are destroyed. It checks
identical candidates and exact native counters; it asserts no performance
threshold. This unprimed control remains in a separate process. A managed
comparison uses the exact production initialization method described below;
startup, calibration and endurance use that method too. Then a fresh
process performs at least 10,000 native input operations as calibration. Another
fresh process must perform at least 1,000,000, finishing its final episode.
Calibration is never substituted for the million or used to shrink the denominator.
The declared seed drives xorshift64/Fisher-Yates ordering of eight authored cases
per schema; all 32 schemas repeat. Repetition establishes endurance, not a
million independent language tasks or the required 3,000 human-reviewed samples.

The same InputSession owner performs real typing, raw-character caret movement,
insertion/deletion, engine candidate selection, paging/highlighting, literal
Return and cancellation. Expected whole-word conversions are independently
authored; exact raw-byte editing and literal returns have separate oracles.
Single-syllable paging avoids pretending that arbitrary multi-syllable partial
candidates must immediately commit. Before/after candidate signatures are a
same-schema/options/learning determinism diagnostic, not an independent language
accuracy benchmark.

C counters under the existing serial mutex count actual process-key, select,
clear and snapshot calls. Their deltas must equal recorded native operations;
refresh-only diagnostic reads are separate. Stale/foreign candidate rejections,
idle passthrough, unsupported Unicode, pending-effect blocking, cross-session
reservation rejection and duplicate reservation checks cannot inflate the native
denominator. A second live session is reread through the C API at checkpoints,
not compared only to its cached Swift value. Lifecycle counters must balance.
The native `_no_learning` option is read, compiled `enable_user_dict: false` is
checked, post-shutdown user directories are inventoried, and userdb artifacts
fail the run. These are bounded architecture/behavior checks, not a whole-device
network capture or universal no-persistence proof.

## Honest timing and resource boundaries

Owner and nested C measurements use the same C CLOCK_MONOTONIC function.
Mixing Swift DispatchTime and that C clock produced a real calibration failure;
the original records remain, and the component-within-owner assertion is retained.
The older A1 benchmark now also uses that shared clock.

Each completed operation produces four little-endian UInt64 words (32 bytes):
operation kind (1 key, 2 selection, 3 clear), owner duration, native action
duration, C commit/context copy duration, all in nanoseconds. At most 256 KiB of
records are buffered in the measured process; flushing and assertions occur
after the per-operation owner timer. Episode autorelease pools bound harness
objects. Percentiles are computed by the separate supervisor after child exit.
No sample trimming, percentile-only evidence or reused timing from owner-only
refusal is allowed. A failed attempted operation remains failed/incomplete in
its receipt/log and the job fails; it is never silently dropped from a pass.

- Owner duration includes InputSession locking/policy, native action, native
  commit/context copy, Swift decoding/state work and shim snapshot freeing.
- Native action is not universally `process_key`: selection also validates the
  current engine page; clear is counted separately.
- C copy includes upstream get/free commit/context and malloc/string copying.
  Swift decoding and shim snapshot freeing are outside that component.
- Disk record flushing, validation, JSON checkpoints, host/UI/rendering and
  observer diagnostics are outside the owner timer. Whole replay wall/CPU
  includes its harness work and is separately recorded.
- Current task RSS is distinct from Darwin whole-process peak RSS. All schemas
  are exercised by a diagnostic sweep before steady checkpoints, but those
  temporary sessions are destroyed, so this does not guarantee that every lazy
  native cache remains warm. Managed checkpoints have two host sessions plus
  one private native initialization owner; all three are included in counters and
  RSS. Startup idle has zero host sessions and one private native owner. These
  measurements permit inspection of growth, not automatic diagnosis of a leak. Library code is intentionally retained until process exit.
- Runtime open, first session, first key and warmed first key are separate from
  compilation. Fresh process does not mean cold filesystem/OS cache. Three
  samples are observations, not startup-tail qualification.
- Hosted runner latency/RSS/2-second idle-CPU observations do not qualify the
  specified M1 budget, physical visible latency, battery use or long idle usage.

The supervisor has explicit child deadlines. Timeout kills and reaps only the
isolated test process group, preserves available checkpoints, and fails the run.
It does not make a blocked in-process C++ call safely interruptible. If actual
stall/loss/growth evidence appears, investigate it before declaring G02 qualified.

## Separate bounded host replay

32 authored schema episodes use the production IMKControllerDriver, actual
NSEvent and an NSTextView-backed IMKTextInput client. They check Unicode prefix
preservation, one-time engine and literal commits, paging/stale/duplicate choice,
wrong-client callbacks, switching clients, and foreign-mark takeover after an
uncertain insert. Clients and their read/write instrumentation are recreated
per episode. This is APPKIT_HOST, separate from the million ENGINE_NATIVE gate.
It is not an IMKServer-created controller, installed source or external app test.

Outstanding release gates remain production resource rights, real strong-baseline
language/efficiency tests, M1/visible resource budgets, installed application/OS/
accessibility matrices, eight-hour continuous and 500-hour real use, signing,
notarization, installation/update/uninstallation qualification. See the original
REPORT and PRODUCTION_DICTIONARY_GATE rather than inferring product readiness
from a green machine replay.

## Observed first-traditional-key tail

The clock-corrected million replay observed 98.207 ms owner / 98.109 ms native
at record 340: first `u` in the first traditional Flypy workload session. Its
separate calibration observed the same position at 86.314 / 86.217 ms. All tail
records are retained. This is a real synchronous engine tail, not a claim of
visible latency and not made acceptable simply by a sub-2-ms p99.

The pinned librime Simplifier stores OpenCC by configuration via weak ownership;
OpenCC initializes its configuration on first conversion. A prior diagnostic
sweep whose sessions are destroyed cannot guarantee preloading for later owners.
This source behavior fits the repeatable observed tail; the independent
cold/warm/zero-owner reactivation diagnostic tests that lifecycle hypothesis.
The lifetime diagnostic reproduced 153.602 ms cold, 0.064 ms same-session,
0.127 ms new session with sentinel retained, and 99.577 ms after all owners were
destroyed. The last phase used 98.576 ms CPU. This strongly supports the lifecycle
mechanism; the exact internal call stack was not profiled. The original records
and their real first-key risk are retained. Full G02 release qualification remains
open. The native replay gate is distinct from those product-performance gates.

Pinned source inspection uses engine commit
`a251145d3aafa33871824a40bbec04c966bd8b56` from Resources/a1-lock.json:
[Simplifier first-conversion initialization](https://github.com/rime/librime/blob/a251145d3aafa33871824a40bbec04c966bd8b56/src/rime/gear/simplifier.cc#L34-L55),
[weak cache lookup/creation](https://github.com/rime/librime/blob/a251145d3aafa33871824a40bbec04c966bd8b56/src/rime/gear/simplifier.cc#L313-L341),
[shared filter / weak map ownership](https://github.com/rime/librime/blob/a251145d3aafa33871824a40bbec04c966bd8b56/src/rime/gear/simplifier.h#L36-L53).
The source mechanism is verified; attribution of the observed latency remains an
inference supported by the explicit owner-lifetime experiment, not a CPU profile.

## Bounded production initialization correction

After deployment and extension capability checks, before an IMK workspace/client
is published, the candidate runtime and explicit research environments create one
private native owner on the fixed public Full/Traditional/ASCII schema. It sends
only authored `shurufa`, checks each real raw prefix, no commit and actual top
`輸入法`, clears, and verifies empty raw/preedit/candidates and `_no_learning`.
It retains only the native ID until runtime close: no InputSession retain cycle,
SessionCore, host binding, candidate capability, effect or stored input body.
Ordinary A1 and compile-only runtimes retain their default unprimed behavior.
Candidate personal overlays are Full/Simplified only; this private owner always
uses the public traditional schema, so personal disable/deletion remains effective.

This relocates synchronous conversion initialization into startup; it does not
remove its cost. Runtime-ready and open-to-first-snapshot timings include it,
and RSS/native counters include the retained owner. The managed four-phase
comparison retains one private owner when all host owners retire. The million
still records every subsequent key, including each mode's first host key, with
its baseline established after disclosed initialization. No sample is trimmed.

A separate deliberately invalid compiled copy disables only the traditional
filter option. It must cross seven successful C keys, fail the actual conversion
oracle, destroy the private owner, retain startupAttempts=1, and reject a second
initialization as PAIA_BUSY without touching counters. Its changed path and
before/after hashes are saved. This is an expected-red partial-initialization
control, not a verified candidate pack or an OpenCC mid-load failure test.
The original measured resource inventory must remain byte-identical.
Product candidate public/save/restore/delete/deleted stages verify the same
constructor receipt, two traditional reactivations after zero host owners,
unchanged authority bytes, existing overlay-disable behavior and balanced
idempotent close. The research host lane likewise counts its private owner.

The correction's exact-head native tests are pending at this revision. No claim
of M1/visible latency, all-mode startup tails, total startup budget, installed use,
eight-hour reliability or release readiness follows from moving initialization.
