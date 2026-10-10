# Consolidated input-habits validation

Baseline: `4a2cc9db13133720618ad3e2e736730d4a8bc7f4` (PR17).
Implementation and final-source/exact-main status: [PR18](https://github.com/haohongfei2001-png/paia-ime/pull/18).
Original REPORT sections 6.4, 7 and 8.2 define the scope. Original research files
and their manifest remain unchanged. Evidence below is bound to its source.

## Qualified initial checkpoint

Head `7d4f085f6ad6cc68d4890e4257ac14c8b3626d8b`, tree
`e0cdf8d48ee721975186fd9e67e0f6aa1f034ceb`: all twelve existing public macos-15
workflows succeeded, including every job/step; no skipped stage. The [IMK run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38072808503)
compiled the unsigned native bundle, ran its preflight without constructing
IMKServer, and passed protocol, resource recovery, context, habits, mixed input,
basic controls and retained G01 repair. Complete logs/checks/artifact metadata are
retained in private recovery; summary counts below were read from actual logs.

- ENGINE_NATIVE finite authored corpus: 32 schemas, 928 actual engine-selected
  and drained commits, 144 exhaustive target-negative cases, and 48 single-key
  diagnostics. The 27-row dictionary is separately authored and isolated from
  research data. Eight distinct effective policies use eight distinct prisms.
  Fuzzy n/l, z/zh, c/ch and s/sh work both ways under all three declared schemes.
  Full-Pinyin typo pairs retain the same canonical phonetic codes as normal forms.
  Negative search must finish within its explicit bound; incomplete search fails.
  Candidate type/code is retained for single-key a/e/o observations rather than
  assuming a key is a complete double-Pinyin encoding. Original dictionaries,
  schema source commits/hashes and notices stay pinned.
- ENGINE_NATIVE existing research resources: 272 same-meaning commits across all
  32 schemas and 28 separate fuzzy/typo-positive commits. Four tests passed; three
  traverse actual engine sessions, while schema/preference identity is SIMULATED.
  v/ü meaning, apostrophe segmentation, full/double codes, both scripts, complete
  raw Return and stale selection are checked. These positive cases are not proof
  of exhaustive candidate absence or production language quality.
- ENGINE_NATIVE + APPKIT_HOST: eight actual production-driver/NSTextView tests
  passed. They check two independent application owners, current-activation mode
  preservation, stale/foreign menu actions, five app-identity getter reentries,
  selection/foreign-mark/lifecycle changes during hide, literal Unicode boundaries,
  and native settings actions with explicit persistence. The system character
  palette callback is SIMULATED; there is no actual OS-panel focus/selection test.
- SIMULATED store/codec: five new InputHabitSettingsTests plus nine existing
  SettingsCoreTests passed in the [B3 run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38072807369).
  v1 bytes/digest/schema are checked before memory-only defaults. Only explicit
  Save publishes v2. Bound application IDs, corruption/unknown/duplicate fields,
  and unconfirmed migration-save outcomes preserve the old conservative contract.

The four research tests report 17.632 seconds test time (32.294 including setup);
eight host tests report 0.272 seconds (15.542 including setup). These complete-suite
timings are neither per-key latency percentiles nor visible/installed measurements.
No failing/cancelled/skipped CI stage was observed in this initial checkpoint.

## Independently reviewed final increment

Source review passed the full settings/owner/speller change after identifying and
fixing three issues before initial publication: unrelated management retirement
resetting a current activation mode, same-counter foreign-driver menu capabilities,
and missing post-hide target revalidation before palette opening. The initial
native tests for these fixes all passed. Another review corrected a test API misuse
(multi-character text sent to a single-scalar ordinary-key API) before publication.

Final source adds an explicit workspace spelling-policy capability. Research
resources provide it; authored/precompiled public fixtures do not. Unsupported
controls are disabled and show no active correction state. Other mode actions
retain the internal default instead of mistaking the visually off checkbox for
a request for strict spelling. A real fixture literal-button test checks this.

The research basic-controls workspace now propagates the same capability. Its
existing controls stage adds eight actual personal-overlay commits, then eight
configured public-baseline commits after explicit personal mutation disables the
overlay until next launch. It verifies once-only insertion, no settings autosave,
and disabled/enabled repair capability respectively. These common-spelling cases
prove baseline availability in eight configurations; policy-sensitive behavior is
proved separately by the authored matrix, not by these eight commits. Source review
checks that the fallback passes both policy flags. Workflow markers require the
complete matrix. These final changes require a separate exact-head run; the initial
checkpoint is not their acceptance. PR18 records final-head and exact-main results.

## Retained local failures and boundaries

Two local static preparation/assertion mistakes were fixed before initial
publication, with failure records retained: the transfer added one trailing newline
to each pinned schema (removed only after exact hash confirmation), and an alias
assertion omitted its pinned leading caret (corrected to require all four exact
anchored aliases). Neither was native execution. Linux had no Swift/AppKit/engine
environment; all native results above came from the explicit macOS CI lanes.

Independent controls are bounded: fuzzy is one closed initial preset; correction
controls only the pinned 37 Full-Pinyin typo rules. Double-Pinyin typo correction
is not claimed. Direct Unicode ü is not normalized as ordinary phonetic input:
idle passes through, active composition refuses unchanged, literal mode preserves
the actual bytes, including combining diaeresis. Ordinary v spelling is tested.

Production corpus provenance/redistribution, strong same-data quality comparisons,
original human efficiency/stress/long-duration targets, visible latency/energy,
OS menu/physical keyboard/VoiceOver/200% display tests, and installed real-app
C0/C2/C3 compatibility remain open. Current C2/C3 production capability stays off.
System character entry delegates eventual character discovery/insertion to macOS;
it does not qualify the system repertoire, fonts or a custom radical lookup.

The bundle remains an unsigned authored-fixture engineering artifact. No system
input-source registration, signing/notarization, installed update/migration/
rollback/uninstall or production distribution is accepted here. No new runner,
paid API, hot-path network, automatic learning, private input history, AI or PAIA
dependency is added. C++ logical budgets still cannot safely interrupt native calls.
