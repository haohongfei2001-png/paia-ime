# B4 validation record

Baseline main 6fb5f850c3c7326a784bc56d3af6a2517ad83e1c, after complete B3 main verification and private recovery. This change keeps the engine, resource pins, settings and personal-store semantics unchanged.

Initial implementation adds a visible non-color selected marker, semibold/accent presentation, truthful current-page/hasMore footer and explicit non-focusable row buttons. Six native test methods cover real selection/navigation/click identity and a bounded repeat loop; one of those methods uses explicitly simulated Unicode values for presentation-only coverage.

Static A1/A2 privacy/resource audits and diff whitespace checks pass on the Linux authoring environment. Swift/AppKit tests and panel captures require the official macOS runner and are pending; no runtime or image-inspection pass is implied by source assertions. Exact current-head, independent review, final-head and merged-main results must be verified separately before completion.

ENGINE_NATIVE means the existing real librime/strong-corpus engine produced candidates and selected text. APPKIT_HOST means actual AppKit objects received programmatic events/actions. SIMULATED labels the Unicode-only snapshot, not an engine decoder. No INSTALLED_IME, LIVE_CLIENT, physical-input, VoiceOver, human-efficiency or general-quality result is produced.

## Initial native checkpoint and capture limitation

Initial head 3ff47807a9174662ef6f8c2a1072ef3b4557fe1f passed B4 run 38004924861/job 114071400423: all six methods, zero failures/skips. The two PNG files were actually inspected and showed an unusable transparent/black rendering, so this checkpoint does not establish readable selected-row/page visual evidence. Those original PNGs and the full log are retained.

The subsequent change gives the panel content its own opaque native background (rather than relying only on the separate window background during view capture), reads Space's expected row from the immediately current snapshot, and adds direct window-deactivation/post-cancel hidden-state checks. These require their own exact-head native run and inspected captures; the initial green test report is not substituted.

## Opaque panel checkpoint

acea581cfe4df0db8724d97c8a264746b1ddaeba passed B4 run 38005345298/job 114072731120/artifact 11651350916, all six methods with zero failures/skips. The updated captures were inspected: background, second-row marker and Page 1/2 footer are visible, but the inline button style renders candidate text too faint in the non-key panel. The next change uses ordinary borderless native buttons with explicit attributed native title colors/font; it does not change action identities or focus. The faint captures remain preserved and are not presented as the final contrast result.
