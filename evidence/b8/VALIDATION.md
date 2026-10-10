# B8 validation record

Baseline: B7 exact main `1d9d2815182cbf5e0ac9577f0a0fdf9c0136bed2`. No engine extension, dictionary hash, resource, persistence or learning policy changes.

## Actual red checkpoint

Test-only `a7f24ac9b59d7854522a5b24f0a54b2dcd2955ae` left product code unchanged. B8 run `38016853330`/job `114108923778` failed both fresh-process probes: 138 assertions in one ENGINE_NATIVE method and 48 assertions across two APPKIT_HOST methods. Both exit codes are 1, not swallowed by the pipeline. The other nine workflows passed this exact head. The later B8 native application build was not run after failure.

The 24 engine cases cover Full/Flypy/Natural, Simplified/Traditional, punctuation modes and comma/period at raw caret 2. Every case cleared the raw suffix and committed only the prefix, with Chinese comma included when enabled. Four native middle-caret fixtures confirmed the lost suffix in the actual document. Four Unicode fixtures observed literal text appended and marked ownership removed while the engine retained raw input; the fifth, fullwidth U+FF51, was instead interpreted as a Left keysym. Full failure logs and all 33 authored observations are retained in the private recovery.

## Initial passing checkpoint, before cancellation review

Exact source `f92ef48a7eab5f9fe7b892ca48e51a015db091e6`, tree `46fa22803036c2b7e9f3ac56de0b7644bf717074`, passed all ten original standard macOS workflows separately. The B8 machine reports macOS 15.7.9 (24G830), arm64, Apple Swift 6.1.2. Independent source, complete native log and actual-pixel review passed. Linux authoring audits/diff checks are static evidence only. Run/job/artifact identities are recorded in [reviewed-checks.json](reviewed-checks.json).

- B8 run `38018181472`/job `114113064400`: three real-engine and eight AppKit methods, zero failures/skips, `bridge_status=0 host_status=0`, then PAIANativeLab build success. All original 33 observations retain the composition and make no insertion.
- A1 run `38018181634`: ABI guards, four state methods, ten engine methods, nine host methods and 3,800 benchmark samples passed. Its broad engine filter retains the one explicit unrelated B2-unconfigured skip.
- A2 run `38018181679`: 28 constrained cases, paired comparator and native host passed.
- B1 `38018181487`, B2 `38018181562`, B3 `38018181514`, B4 `38018181682`, B5 `38018181543`, B6 `38018181737` and B7 `38018181550` all succeeded. Their full logs remain available, not replaced by the focused B8 result.

## Integration held for additional ownership regressions

Documentation-only `4319c70ac44167c22e0d22512fa19ccaa6971095` also passed ten workflows, but no merge occurred: further independent source review found cancellation could unmark a newer owner during a synchronous callback. Test-only `194043430361e9892c07f30bdfbcace3d02561a4`, B8 run `38019245568`/job `114116330945`, recorded seven failed assertions across three newly added native methods. It proved foreign-mark unmarking, actual deletion of `keepword` by Option-Delete after focus changed, and replacement of a newer dispatcher installed by a factory callback. The prior eight host methods and three bridge methods passed; `bridge_status=0 host_status=1`.

Expanded test-only `5e50c0d4000ed206958326d40ee68de6db9a938a`, B8 run `38019936067`/job `114118473152`, exercised Escape, marked updates and commit callbacks too. Twelve host methods recorded 26 failed assertions, including the prior seven. The three bridge methods passed. Both test-only heads passed the other nine workflows; their later B8 native application builds did not run after failure. These failures remain separate from green checkpoints.

## First ownership fix and compatibility regression

Source `1ef3218e013a6dbf5537f5da9f848e95fbf47bb6`, tree `503413bb270a1208b2dc63490249ff9a2828171b`, passed B8 run `38020360821`/job `114119797389`: three bridge and eighteen AppKit methods, no failures/skips, both exit codes zero and native app build success. Independent source/log/actual-image review confirmed the identified ownership gaps were closed by native regressions. However, A1 run `38020360823` failed two assertions in the existing selected-grapheme raw-Return method: the correct `AnihaoB` document and single insertion remained, but the strict write-result check returned false and ended the session. A1's benchmark after this failure was not run. The other nine workflows succeeded; this head is not a full pass.

The compatibility follow-up retains every original assertion and adds an authored before/after native diagnostic plus exact caret, no-mark and zero-length-mark assertions. Exact `34ee9480cac417bfe7d6bb270243263f5162e65f`, A1 run `38021026961`/job `114121825238`, passed and recorded: before `Ani haoB`, mark `{1,6}`, selection `{7,0}`; after `AnihaoB`, selection `{6,0}`, empty mark `{7,0}`, hasMarked=false. The native view retains an empty mark location distinct from the correct caret. Only a projected unmarked result tolerates that empty location; document UTF-8, selection, hasMarked=false and mark length zero remain required. Entry snapshots and all actual marked compositions still compare exact ranges. This is compatibility with observed NSTextView metadata, not a universal protocol guarantee or permission to ignore an actual foreign mark. A1's full 3,800-sample benchmark also completed at this head.

## Reviewed final product

Exact product `34ee9480cac417bfe7d6bb270243263f5162e65f`, tree `c64cd06b685284e368eef0339638e858009e0c17`, passed all ten workflows with the compatibility change and unchanged foreign-owner regressions. [ownership-checks.json](ownership-checks.json) records complete run/job/artifact identities for this source, separately from the initial passing checkpoint.

- B8 `38021026989`/job `114121825900`/artifact `11657897947`: three bridge plus eighteen native host methods, zero failures/skips, both exit codes zero and PAIANativeLab build success.
- A1 `38021026961`: ABI guards, four state, ten engine and nine host methods, exact native Return diagnostic and 3,800 benchmark samples. One unrelated B2-unconfigured skip remains explicit.
- A2 `38021026978`: 28 cases, paired comparator and native host.
- B1 `38021026954`, B2 `38021026952`, B3 `38021027025`, B4 `38021026946`, B5 `38021026962`, B6 `38021026972` and B7 `38021026991`: all success.

## Verified behavior and pixels

ENGINE_NATIVE checks pre-mutation no-op refusal at start/middle/confirmed composition, exact snapshot/generation/candidate references/timing, continued engine spelling and controls, explicit selection, raw Return and pending-effect rejection. This is a bounded safety refusal, not a new decoder.

APPKIT_HOST uses actual NSTextView, native key-event objects, focus changes, notifications and synchronous effect callbacks in an uninstalled synthetic host. It checks unchanged document/marked/selection state without marked-text writes on refusal; readable status and subsequent clearing; idle/literal Unicode (including a fresh uninitialized session); physical controls; nested Escape/new input/external edit/focus during refusal; ownership loss after insertion; recursive mark apply; no later unmark or unhandled punctuation fallback after lost ownership; and no replay of a reserved insertion. Authored fixtures and programmatic native calls do not establish physical keyboard behavior.

The expanded tests cover foreign state installed during cancellation, Escape, nonempty marked updates and insertion; focus-loss Option-Delete; factory replacement/reentry and changed targets; retirement without native edits; nested newer key and host-edit events; normal Option-Delete and repeated literal typing; and a real plain-NSTextView oracle for pre-existing foreign marks. Every native write is checked against its precomputed document/caret/marked result before the old event may continue or adopt ownership. Discarded/replaced dispatchers retire without clearing new native text. Older event tickets cannot render/hide a newer candidate panel or issue later cleanup.

Both captures were actually opened and independently inspected. Marked `nihao` remains visible, and the complete refusal/recovery sentence is readable without clipping. PNG bytes exactly match contiguous Base64 blocks from the job log:

- middle-refusal SHA-256 `4dc3eb61fcd2be70a91041744301d8c30053536c9923642de07cf3c431528af9` (24 blocks).
- unicode-refusal SHA-256 `eee9c9fb679d039b205d68bc583f960b1be47f35cfa3812bb61d8e0c116c427c` (23 blocks).

These pixels demonstrate presentation; the native assertions establish unchanged state and once-only behavior. B8 adds no separate simulated UI claim; earlier pure state/geometry tests keep their own evidence categories.

## Retained limitations and final-tree handling

Full middle-punctuation/Unicode compound composition is still open. Users must explicitly move to the end or use Return/Escape as described by the warning and then enter unsupported text again. The app never performs these recovery actions automatically. Lowercase spelling, apostrophe delimiter and explicit candidate/control actions continue through the real engine.

Post-call ownership checks cannot make native host calls atomic or undo an already issued insertion. They do not detect every unobservable mutation within a native call. Command/Option and literal input retain explicit cancellation semantics, but their AppKit continuation now requires the projected native state and current event/dispatcher identities. General language quality, installed/live-client compatibility, physical keyboard/pointer/VoiceOver behavior, complete accessibility, full application launch, visible latency, endurance, signed updates and install/uninstall remain unverified. No implicit learning, archive, network hot path or persistent input log is added.

The final evidence change is documentation-only. Its exact ten CI workflows and the exact merged-main workflows must be checked independently and saved in the private recovery before final acceptance. Earlier green evidence is not a substitute. Retain full failed and passing logs, source/license/resource locks, raw benchmark/comparator results, captures and baseline-to-main patch. The research corpus is not packaged and its production redistribution clearance remains unresolved.
