# B8 validation record

Baseline: B7 exact main `1d9d2815182cbf5e0ac9577f0a0fdf9c0136bed2`. No engine extension, dictionary hash, resource, persistence or learning policy changes.

## Actual red checkpoint

Test-only `a7f24ac9b59d7854522a5b24f0a54b2dcd2955ae` left product code unchanged. B8 run `38016853330`/job `114108923778` failed both fresh-process probes: 138 assertions in one ENGINE_NATIVE method and 48 assertions across two APPKIT_HOST methods. Both exit codes are 1, not swallowed by the pipeline. The other nine workflows passed this exact head. The later B8 native application build was not run after failure.

The 24 engine cases cover Full/Flypy/Natural, Simplified/Traditional, punctuation modes and comma/period at raw caret 2. Every case cleared the raw suffix and committed only the prefix, with Chinese comma included when enabled. Four native middle-caret fixtures confirmed the lost suffix in the actual document. Five Unicode fixtures observed literal text appended and marked ownership removed while the engine retained raw input; fullwidth U+FF51 was instead interpreted as a Left keysym. Full failure logs and all 33 authored observations are retained in the private recovery.

## Reviewed product checkpoint

Exact source `f92ef48a7eab5f9fe7b892ca48e51a015db091e6`, tree `46fa22803036c2b7e9f3ac56de0b7644bf717074`, passed all ten original standard macOS workflows separately. The B8 machine reports macOS 15.7.9 (24G830), arm64, Apple Swift 6.1.2. Independent source, complete native log and actual-pixel review passed. Linux authoring audits/diff checks are static evidence only. Run/job/artifact identities are recorded in [reviewed-checks.json](reviewed-checks.json).

- B8 run `38018181472`/job `114113064400`: three real-engine and eight AppKit methods, zero failures/skips, `bridge_status=0 host_status=0`, then PAIANativeLab build success. All original 33 observations retain the composition and make no insertion.
- A1 run `38018181634`: ABI guards, four state methods, ten engine methods, nine host methods and 3,800 benchmark samples passed. Its broad engine filter retains the one explicit unrelated B2-unconfigured skip.
- A2 run `38018181679`: 28 constrained cases, paired comparator and native host passed.
- B1 `38018181487`, B2 `38018181562`, B3 `38018181514`, B4 `38018181682`, B5 `38018181543`, B6 `38018181737` and B7 `38018181550` all succeeded. Their full logs remain available, not replaced by the focused B8 result.

## Verified behavior and pixels

ENGINE_NATIVE checks pre-mutation no-op refusal at start/middle/confirmed composition, exact snapshot/generation/candidate references/timing, continued engine spelling and controls, explicit selection, raw Return and pending-effect rejection. This is a bounded safety refusal, not a new decoder.

APPKIT_HOST uses actual NSTextView, native key-event objects, focus changes, notifications and synchronous effect callbacks in an uninstalled synthetic host. It checks unchanged document/marked/selection state without marked-text writes on refusal; readable status and subsequent clearing; idle/literal Unicode (including a fresh uninitialized session); physical controls; nested Escape/new input/external edit/focus during refusal; ownership loss after insertion; recursive mark apply; no later unmark or unhandled punctuation fallback after lost ownership; and no replay of a reserved insertion. Authored fixtures and programmatic native calls do not establish physical keyboard behavior.

Both captures were actually opened and independently inspected. Marked `nihao` remains visible, and the complete refusal/recovery sentence is readable without clipping. PNG bytes exactly match contiguous Base64 blocks from the job log:

- middle-refusal SHA-256 `4dc3eb61fcd2be70a91041744301d8c30053536c9923642de07cf3c431528af9` (24 blocks).
- unicode-refusal SHA-256 `eee9c9fb679d039b205d68bc583f960b1be47f35cfa3812bb61d8e0c116c427c` (23 blocks).

These pixels demonstrate presentation; the native assertions establish unchanged state and once-only behavior. B8 adds no separate simulated UI claim; earlier pure state/geometry tests keep their own evidence categories.

## Retained limitations and final-tree handling

Full middle-punctuation/Unicode compound composition is still open. Users must explicitly move to the end or use Return/Escape as described by the warning and then enter unsupported text again. The app never performs these recovery actions automatically. Lowercase spelling, apostrophe delimiter and explicit candidate/control actions continue through the real engine.

Post-call ownership checks cannot make native host calls atomic or undo an already issued insertion. They do not detect every unannounced mutation within a native call. The stricter AppKit fallback guard covers engine-returned unhandled events; older Command/Option and literal-mode direct cancellation behavior is unchanged. General language quality, installed/live-client compatibility, physical keyboard/pointer/VoiceOver behavior, complete accessibility, full application launch, visible latency, endurance, signed updates and install/uninstall remain unverified. No implicit learning, archive, network hot path or persistent input log is added.

The final evidence change is documentation-only. Its exact ten CI workflows and the exact merged-main workflows must be checked independently and saved in the private recovery before final acceptance. Earlier green evidence is not a substitute. Retain full failed and passing logs, source/license/resource locks, raw benchmark/comparator results, captures and baseline-to-main patch. The research corpus is not packaged and its production redistribution clearance remains unresolved.
