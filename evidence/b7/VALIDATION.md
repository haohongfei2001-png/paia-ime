# B7 validation record

Baseline: B6 exact main 0d457abf7a244f2ce48a85532223a8cc5a80fe53, with eight successful main workflows and verified private recovery. No dictionary/resource hashes, engine extension or persistence semantics change.

## Retained regression and first-product failure

Test-only f2a20ed8e6026495661aa8e6c88fa133e2edec1c leaves old production code untouched. A1 run 38013532698/job 114098698020 failed ten assertions in the new canonical-equivalent target-edit method. Both U+212B→U+00C5 and the reverse could incorrectly receive a prepared real-engine commit because Swift String equality treats them as equivalent. The eight prior host methods passed, as did the other seven workflows. A1's later benchmark stage did not run after this failure; it is not a complete passing A1 result.

Independent source review of the new inspector found that cancelling could restore focus before revoking an old Insert/repair Accept capability. The final ordering revokes both preview types before synchronous restoration, keeps the shared lease/kind barrier alive, and rejects nested preview/accept actions during dismissal. Cancel→old Insert, Cancel→old repair Accept and renewed-preview callbacks now have native regression coverage. This finding was static, not a separately executed red checkpoint.

First product 0afca38558618e52d9cf1a3d7a5273f6b0991e31 compiled and passed the other eight workflows. B7 run 38014449206/job 114101514510 passed five pure methods but failed nine assertions in one of ten host methods. NSTextView normalized requested split-grapheme and multiple zero-length ranges into one safe caret, contrary to the fixture assumption; an opened inspector then contaminated the rest of that fixture. The correction isolates native windows and verifies observable normalization. The identical validSingleCaret policy used in production is tested directly against the original invalid ranges. Native nonempty-selection and changed-selection rejection remain required. No host state is forged or safety guard relaxed. Full logs and the first capture are retained.

## Reviewed passing checkpoint

Exact source dd21e93dfc99d34e062f31c89d31b1b2fd38db36, tree a37e0da775484c86d7c5ec058d5b4f059cd3db42, passed independent source/actual-image review and all nine standard macOS workflows. The B7 machine reports macOS 15.7.9 (24G830), arm64, Apple Swift 6.1.2. Linux authoring audits and diff checks are static evidence only.

- B7 run 38014922745/job 114102960807/artifact 11655714814: five pure scalar/session methods and ten real synthetic-AppKit methods, zero failures/skips; native app build passed. Tests include 24 spelling/script/punctuation/literal configurations, supplementary U+20000 insertion at an emoji-adjacent caret, exact UTF-16 selection, stale/repeated actions, next normal real-engine commit, context-joining refusal, field/target/focus changes, pre/post-focus reentrancy, two cancellation directions and direct shared mode/settings/repair barriers.
- A1 run 38014922881: ABI sanitizer guards, four state methods, ten engine methods, nine host methods including the formerly red exact-text identity check, and 3,800 fixed-workload samples passed. The broad engine filter retains its one explicit unrelated B2-unconfigured skip.
- A2 run 38014922787: 28 constrained engine cases, paired comparator and native host passed.
- B1 run 38014922849: twelve native control/repair/focus methods passed.
- B2 run 38014922873: ten governance, four file and five manager methods plus seven native stages passed.
- B3 run 38014922803: nine settings-store methods and nine fresh-process stages passed.
- B4 run 38014922789: six navigation/presentation methods passed, including 160 repeated actions.
- B5 run 38014922809: eight settings-save verification and seven native methods passed.
- B6 run 38014922780: four native long-candidate methods and app build passed.

## Evidence categories and visual result

SIMULATED covers pure scalar validation/session binding/reservation and illegal-range/context guards. APPKIT_HOST covers actual NSTextView/controller behavior in an uninstalled synthetic application, including AppKit's range normalization. ENGINE_NATIVE is used by the prepared real session and next normal Chinese commit; explicit U+ insertion itself is a literal action, not a new decoder or a fabricated engine candidate.

Both first-product and reviewed exact-head captures were actually opened. U+20000, its complete CJK UNIFIED IDEOGRAPH-20000 name, the visible missing-glyph box, explanatory system-font warning and separate Preview/Cancel/Insert controls are readable without clipping or overlap. The capture SHA-256 is 5ad7e1afb9ccd3089874d50820d08b2e4fb3404a4af32441e15aa0b864bb9bf7 at both heads. The document is unchanged while preview is shown. Exact scalar insertion and once-only behavior are asserted by the native tests, not inferred from the image.

## Limits and final-tree handling

Known U+ entry does not discover rare characters from phonetics/radicals, install fonts or guarantee glyph coverage. The platform's Unicode database controls classification/names. Unsupported scalars and context joins are explicitly refused; arbitrary sequences and selected-text replacement are outside this slice. System Character Palette integration, physical keyboard/pointer events, full keyboard-only/VoiceOver interaction, installed/live-client compatibility, general language quality, human efficiency, visible-response latency and endurance remain unverified. No atomic compare-and-swap across unobservable application mutations is claimed.

The final evidence change is documentation-only. Its exact CI and the exact merged-main workflows are independently checked and saved with the private recovery, including the full initial failure, first-product failure, source/license locks, raw benchmark/comparator results and actual captures. Earlier green results do not substitute for final-head or main checks. Nothing is registered as a system input source; no personal input, font/model package, store contents, credentials or corpus binary is added.
