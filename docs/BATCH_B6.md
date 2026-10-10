# Batch B6: fully readable long candidates

This slice closes the bounded native long-candidate overflow gap in REPORT §9.1 and Batch B4. It preserves the existing vertical presentation, immutable engine CandidateRef, truthful page status and nonactivating panel. No new resource, setting, store, input-source installation or language decoder is introduced.

## Layout and selection

Each borderless native candidate button retains one TextKit layout for its complete title. The same glyph layout measures and draws the text, including system font fallback and multiline wrapping; no character-count estimates, manual Unicode slicing or ellipsis are used. Row heights reserve both normal and highlighted typography so navigation does not resize the same candidate page.

The vertical scroll document uses the actual content width with a legacy scrollbar reserved. The window is bounded by the supplied safe screen in logical points, including negative coordinates. The footer stays outside the scroll viewport and adds an explicit scroll hint when content overflows. An oversized highlighted row initially reveals its beginning; its full tail remains in the scroll document. Rendering the identical snapshot preserves the current scroll offset. A new engine generation reveals its highlighted row.

Invalid, non-finite or extremely small geometry hides the panel rather than showing stale/out-of-bounds content. A supplied rectangle must be at least 120 points wide and 96 high, and must leave at least 24 points for candidate content after the measured footer and padding. These conditions are minimum guards, not a promise that every 120×96 rectangle is usable. No mouse-position fallback or extra permission is used.

Buttons still invoke the engine selection path using their original CandidateRef. They cannot become first responder and the panel cannot become key. Scrolling and drawing do not commit, change an engine generation or write a personal store. Up/Down and PageUp/Down remain engine navigation; no competing keyboard scroll mapping is added.

## Verification

Run the same pinned resource preparation as B1, then `swift test --filter CandidateOverflowTests` in a fresh process. The dedicated B6 workflow uses standard macOS CI, with no input-source registration. A1/B1/B4 retain their original stale-action/focus/navigation assertions while finding the actual candidate buttons through the new view hierarchy.

A real explicitly authored 77-grapheme personal term is compiled through the existing B2 store and obtained from librime. It exercises actual native wrapping, overflowing start/tail inspection, exact current-snapshot selection by Space and button, repeated old actions and single commits. It does not establish the decoder's general accuracy or rare-word discovery.

Separate SIMULATED snapshots cover narrow/short/negative-origin rectangles, unbroken ASCII, English words, newlines, rare CJK, combining accents and emoji/ZWJ. Assertions inspect complete glyph-to-character coverage, horizontal line bounds, footer fit, reachable last glyph, stable highlight geometry and bounded panel hierarchy. Native captures are actually inspected, not treated as correct merely because a file exists.

[Validation](../evidence/b6/VALIDATION.md) records the intentional failing regression, exact native checkpoints and remaining limits. Scroll reachability uses programmatic native clip-view movement, not physical wheel/trackpad/scroller interaction. Physical input, keyboard-only full overflow review, VoiceOver, large-text/appearance and real multi-display matrices remain release gates. This remains an uninstalled research host, with no general language-quality, visible-latency or endurance claim.

The CI system font renders U+20000 as a missing-glyph box in the synthetic Unicode captures. Exact UTF-16/glyph coverage and preserved engine text do not establish readable font coverage for that character; rare-character font/identification support remains open. No font package is added.
