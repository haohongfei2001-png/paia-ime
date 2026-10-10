# Mixed-input validation

Baseline: `df871e48bc3a5df450f7b600280e964c8e1cc511` (PR16).
Implementation and final-source/exact-main status: [PR17](https://github.com/haohongfei2001-png/paia-ime/pull/17).
This record is commit-bound. Earlier green runs do not qualify later source.

## Qualified broader checkpoint

Head `c715add1a9676763f88be58ccc8e003a25c3059b`, tree
`173b07bd341701e6b4eb39d61651e01bef6c6437`: all 12 existing workflows succeeded.
The [IMK run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38068420577)
completed build, preflight, protocol client, resources, bounded context, mixed,
basic-controls and retained-repair stages without a skipped stage.

- ENGINE_NATIVE: projected probe 98 scenarios = 96 genuine commits and two
  exhausted-budget refusals. A separate old-route process reproduces the actual
  `user_id` middle replay failure and verifies its source is unchanged. The 14
  literals run at front/middle/end with two actual Chinese choices; successful
  cases drain one commit and verify an empty second drain.
- ENGINE_NATIVE: direct native owner matrix makes 20 commits, covering left/right
  selection order, partial raw coverage, foreign/stale/revoked capabilities,
  explicit UTF8 lengths and malformed input, zero-budget refusal then deliberate
  success, literal-only Unicode and 128 independent proofs. Sealed receipts cannot
  commit twice. This direct matrix alone does not test the exported C table.
- ENGINE_NATIVE: ten Swift bridge tests traverse the actual exported C ABI,
  serialized engine owner and SessionCore effect gate. The 12 exposed research
  schemas plus full-Pinyin initials make 32 converted commits and 32 complete
  source Return effects. They cover ordinary/confirmed-prefix adoption, navigation,
  reopen, identical-raw span identities, chained grapheme editing and 128 genuine
  suffix proofs. Four internal validation faults occur **after real native
  success**, checking retirement of consumed native capabilities rather than
  replacing engine output with a mock.
- ENGINE_NATIVE + APPKIT_HOST: six tests use actual NSTextView and the production
  IMK driver/action/effect path. They include explicit literal intent and Option-L,
  real candidate selection, complete source Return, long suffix selection,
  stale/reentrant actions, ownership loss and unknown insertion outcome without
  retry. Production action dispatch is not an OS menu click or installed service.
- SIMULATED: ten pure draft/effect tests use authored proof IDs; they verify source
  byte/display UTF16/grapheme maps, canonical byte distinctions, cross-origin join
  refusal, immutable edit/reopen bounds and exact whole-effect guards. A seventh
  host-target test checks bounded/incomplete panel-footer semantics with authored
  candidate presentation data. It is not native candidate-exhaustion evidence.
- SIMULATED: [A1 sanitizer run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38068420612)
  frees authored mixed list/selection/import/text allocations after runtime close
  and repeats the zeroed-struct free under Address/Undefined sanitizers. The local
  Linux LeakSanitizer startup failed under ptrace; the same local binary passed
  with only leak detection disabled. No Linux leak or engine coverage is claimed.

Actual IMK log reports ten bridge tests with zero failures (10.949 seconds test
time, 22.415 including startup) and seven host-target tests with zero failures
(6.256 seconds test time, 15.516 including startup). The old 98-case native
probe's `total_us=71472` excludes the owner/Swift/host matrices. None is a visible
latency percentile, end-to-end performance acceptance or competitor comparison.

## Final increment awaiting its own run

Independent whole-diff source review passed ownership, exact effect, capability
retirement, native selection provenance, bounds and output lifetime. It also
identified a coverage gap: the earlier lifecycle case finished only after Return
had emptied the draft. A separate test now starts nonempty mixed composition and
directly finishes/deactivates at front/middle (four combinations), then attempts
an old menu action and another finish. It requires complete original source, one
insert and a retired session. Review of that final test passed, but it must run
on its own exact head. Final configured counts are ten pure, ten bridge and eight
host-target tests (seven real paths and one SIMULATED presentation case).

## Retained failures and earlier checkpoints

- `df8a1b5`, [run 38063272967](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38063272967):
  C++ initialization warnings failed compilation under unchanged `-Werror`; no
  mixed case executed. Fixed C++ initialization, without disabling warnings.
- `9517f16`, [run 38063636808](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38063636808):
  dylib install-name/archive-name mismatch aborted before main. Fixed a local
  alias/rpath in the owned disposable engine folder, without modifying the engine.
- `109663c`, [run 38064040303](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38064040303):
  actual Chinese replay failed at the wrong last-menu frontier. Fixed trial-only
  caret projection and exact selected-span verification; source and G01 guards
  remain unchanged.
- `938f8b6`, [run 38064531605](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38064531605):
  48 normal-choice scenarios ran before an incorrectly predicted RAG negative
  failed to reproduce. Partial-suffix and alternate groups had not run. Replaced
  that false expectation with the separate whole-old-route `user_id` control;
  never count the invalid expected negatives as passing cases.
- `160430a`, [run 38065091290](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38065091290):
  all 12 workflows succeeded; actual negative control plus projected 98 qualified.
- `7277956`, [run 38066439154](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38066439154):
  all 12 succeeded; added 20 direct native owner commits and nine pure tests.
- `0708806`, [run 38067490851](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38067490851):
  all 12 succeeded; first seven actual Swift/ABI and four real host-path tests.

Full failed logs, cancelled/skipped job results and exact checkpoint metadata are
retained in the private recovery evidence. The first four checkpoint totals were
respectively 7 success/1 failure/4 cancelled, 8/1/3, 10/1/1 and 11/1/0. A cancelled
or skipped stage is never promoted to success by a later explanation.

## Boundaries and remaining product gates

- Literal intent is explicit. Independent spelling projections break contextual
  whole-sentence ranking across literal boundaries; this is not an English/URL
  language detector or production language-quality acceptance.
- Confirmed-span interior editing requires explicit reopen. Cross-origin grapheme
  joins that cannot retain safe provenance are refused unchanged. Candidate rows
  are bounded at 64, with incomplete search displayed honestly. Logical budgets
  bound work counters but cannot safely interrupt an in-flight C++ call.
- Default fixture bundles do not expose the optional research capability. Existing
  personal overlays that disable G01 also disable it. No new dictionary or runtime
  dependency, hot-path network, automatic learning, hidden recording or paid API.
- Independent typo/fuzzy controls, per-app initial mode, rare-character discovery,
  and focused same-meaning v/ü/apostrophe/double-Pinyin checks remain basic gates.
  Existing upstream spelling algebra already includes some correction behavior.
- Production corpus provenance/redistribution, strong same-data language comparisons,
  the original human-reviewed task/stress/long-duration study targets and full
  visible latency/energy acceptance remain open.
- No actual OS menu clicking, physical typing, VoiceOver/200% display qualification,
  installed input source, real-app C0/C2/C3 compatibility, signing/notarization,
  system registration, signed update, migration/rollback or uninstall acceptance.
  CI compiles an unsigned bundle and uses preflight without constructing IMKServer.

Original research REPORT/VALIDATION/HANDOFF and their manifest are unchanged.
