# B4 validation record

Baseline main 6fb5f850c3c7326a784bc56d3af6a2517ad83e1c, after complete B3 main verification and private recovery. This change keeps the engine, resource pins, settings and personal-store semantics unchanged.

Initial implementation adds a visible non-color selected marker, semibold/accent presentation, truthful current-page/hasMore footer and explicit non-focusable row buttons. Six native test methods cover real selection/navigation/click identity and a bounded repeat loop; one of those methods uses explicitly simulated Unicode values for presentation-only coverage.

Static A1/A2 privacy/resource audits and diff whitespace checks pass on the Linux authoring environment. Swift/AppKit tests and panel captures require the official macOS runner and are pending; no runtime or image-inspection pass is implied by source assertions. Exact current-head, independent review, final-head and merged-main results must be verified separately before completion.

ENGINE_NATIVE means the existing real librime/strong-corpus engine produced candidates and selected text. APPKIT_HOST means actual AppKit objects received programmatic events/actions. SIMULATED labels the Unicode-only snapshot, not an engine decoder. No INSTALLED_IME, LIVE_CLIENT, physical-input, VoiceOver, human-efficiency or general-quality result is produced.
