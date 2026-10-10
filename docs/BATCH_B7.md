# Batch B7: explicit known-character entry

This bounded native lab slice provides a caret-only native inspector for one known Unicode scalar, with an always-readable U+ identifier/name, system-font glyph preview, and separate explicit Insert/Cancel. This is not pronunciation/radical discovery, arbitrary sequence insertion, a font installation or selected-text replacement. It uses the existing inspector owner, target lease and single HostDispatcher commit path; ordinary input remains non-learning.

Accept U+ followed by 1–6 ASCII hexadecimal digits, or one literal scalar. Refuse control, format, unassigned/private-use, separator/mark, default-ignorable/noncharacter and explicitly blank symbol values (U+2800/U+1D159). Grapheme extenders and emoji modifiers are refused. The inserted scalar must preserve its own grapheme boundaries in the target context, so regional-indicator pairs, Hangul jamo joins and attachment to a following combining mark are also refused. Do not trim or normalize. A visible identifier does not imply the platform has a glyph.

The initial checkpoint proved a target-identity regression before implementation: Swift String equality treats U+212B and U+00C5 as canonically equivalent, but externally changing one to the other must invalidate a prepared host effect. Exact text identity, caret boundaries, stale/reentrant callbacks, shared mode/settings/repair barriers and true native insertion are covered by the exact-head verification record.

No new dictionary, model, font, service, input-source registration, private profile or persistent data is introduced. Native CI and actual captures, not planning text, determine completion.

## Identity and cancellation

Host target text and the preview input use exact UTF-8 identity, not canonical-equivalent Swift String equality. Preview is bound to one initialized idle session, target epoch, input generation and dictionary revision. Acceptance latches before focus restoration and rechecks the original host, lease, preview, exact input, caret and session binding afterward. An effect uses the existing reservation and sole insertText call; it is never automatically retried.

Both repair and character inspectors share the existing owner and mode/settings barriers. Dismissal revokes all preview capabilities before restoring focus and rejects nested preview/accept actions during dismissal. This ordering addresses an independent review finding, including Cancel→old Insert and Cancel→old repair Accept. It does not claim an atomic compare-and-swap across every possible application mutation.

## Verification boundaries

The dedicated B7 workflow runs five pure scalar/session methods and ten real synthetic-AppKit methods, including 24 configurations, exact supplementary-scalar insertion, normal engine continuation, caret/context refusal, stale actions, foreign focus, reentrant cancellation/acceptance, and shared settings/mode barriers. APPKIT_HOST uses the real prepared librime environment; the explicit scalar is literal input, not an engine-decoded rare-word candidate. The Unicode target-identity regression remains in A1.

Initial f2a20ed8e6026495661aa8e6c88fa133e2edec1c reproduced the canonical-equivalent external-edit bug: A1 run 38013532698 failed ten assertions in the new method, while the eight old host methods and other seven workflows passed. The reviewed implementation subsequently passed all nine workflows. Local privacy/resource audits are static only.

Known U+ entry does not close phonetic/radical rare-word discovery, system-font coverage, system Character Palette integration, full keyboard/VoiceOver interaction, installed-client compatibility or language quality. No font is installed. The preview always exposes the ASCII U+ identity and warns about missing glyphs.

Unicode properties follow the platform Swift Unicode database; see Apple's [grapheme extender](https://developer.apple.com/documentation/swift/unicode/scalar/properties-swift.struct/isgraphemeextend) and [emoji modifier](https://developer.apple.com/documentation/swift/unicode/scalar/properties-swift.struct/isemojimodifier) definitions.

The first product checkpoint 0afca385 compiled all native sources and passed the other eight workflows. B7's five pure methods passed; ten host methods ran with nine failures in one selection fixture. The fixture incorrectly assumed NSTextView retained split-grapheme and multiple zero-length ranges. Actual macOS normalized them to one safe caret, so subsequent fixture operations inherited an open inspector. The corrected tests isolate windows, assert actual native normalization without forged host state, retain native nonempty-selection/changed-target refusal, and directly test all invalid ranges through the same pure validSingleCaret policy used by the controller. The failure log and capture are retained; that first B7 run remains failed.

[Validation](../evidence/b7/VALIDATION.md) records the exact reviewed head, native results, independently inspected capture and retained failures. Final-head and merged-main checks are verified separately; earlier success is never inherited by a changed tree.
