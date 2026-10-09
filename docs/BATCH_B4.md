# B4 visible native candidate navigation

A bounded presentation slice on the same B1/B2/B3 research host. The row chosen by Space now has a visible triangle, semibold font and accent color. The triangle carries the distinction without relying on color. The marker and accessibility selected value are computed from the same immutable engine snapshot. Every button continues to retain its original CandidateRef; rendering a newer page never changes what an old button means. A stale click re-renders the valid current snapshot instead of hiding its current page; an invalid/empty engine snapshot still hides the panel.

The footer reports the engine's current page (one-based for display) and whether more candidates are available. It does not invent a total page count. The panel remains nonactivating and cannot become key; row buttons refuse first responder. Navigation is still processed by librime through LabTextView's existing key mapping, not by a separate UI cursor or decoder.

Launch exactly as documented for the existing B1/B2/B3 lab. No new launch flag, resource, library, model, network operation or persistence behavior is required. Ordinary input and navigation remain non-learning. This does not install a system input source.

## Verification

The B4 workflow uses the same pinned engine and B1 strong-corpus preparation in a separate filtered test process. Actual key-event dispatch exercises Up/Down, PageDown/PageUp, Space, digit selection, programmatic candidate-button selection, old-page clicks, cancellation, focus loss and mode invalidation. Expected committed text is read from the engine snapshot immediately before selection. A 160-navigation-action loop verifies no commit, preserved focus and bounded panel count; it is not an endurance or latency benchmark.

Two captures render the actual separate CandidatePanel content view, showing the second highlighted row and a next-page state. They contain synthetic query outputs only. A separate synthetic Unicode snapshot checks astral/combining/emoji titles and end-page wording; those rows are explicitly SIMULATED and are not claimed as corpus decoding results.

[Validation](../evidence/b4/VALIDATION.md) records exact-head results and retained failures. Programmatic NSEvents and performClick are APPKIT_HOST evidence, not physical-keyboard/mouse or VoiceOver validation. Actual display positioning, clipping under very long candidates, multiple displays/scales/appearances, installed clients, visible latency, general language quality and complete Batch B readiness remain open.
