# B4 validation record

Baseline main 6fb5f850c3c7326a784bc56d3af6a2517ad83e1c, after complete B3 main verification and private recovery. This change keeps the engine, resource pins, settings and personal-store semantics unchanged.

Initial implementation adds a visible non-color selected marker, semibold/accent presentation, truthful current-page/hasMore footer and explicit non-focusable row buttons. Six native test methods cover real selection/navigation/click identity and a bounded repeat loop; one of those methods uses explicitly simulated Unicode values for presentation-only coverage.

Static A1/A2 privacy/resource audits and diff whitespace checks pass on the Linux authoring environment. Swift/AppKit tests and panel captures run on the official macOS runner; results for each code checkpoint are recorded below. Exact final-head and merged-main results require separate verification and are preserved in the private recovery snapshot; source assertions alone do not establish a runtime or image pass.

ENGINE_NATIVE means the existing real librime/strong-corpus engine produced candidates and selected text. APPKIT_HOST means actual AppKit objects received programmatic events/actions. SIMULATED labels the Unicode-only snapshot, not an engine decoder. No INSTALLED_IME, LIVE_CLIENT, physical-input, VoiceOver, human-efficiency or general-quality result is produced.

## Initial native checkpoint and capture limitation

Initial head 3ff47807a9174662ef6f8c2a1072ef3b4557fe1f passed B4 run 38004924861/job 114071400423: all six methods, zero failures/skips. The two PNG files were actually inspected and showed an unusable transparent/black rendering, so this checkpoint does not establish readable selected-row/page visual evidence. Those original PNGs and the full log are retained.

The subsequent change gives the panel content its own opaque native background (rather than relying only on the separate window background during view capture), reads Space's expected row from the immediately current snapshot, and adds direct window-deactivation/post-cancel hidden-state checks. These require their own exact-head native run and inspected captures; the initial green test report is not substituted.

## Opaque panel checkpoint

acea581cfe4df0db8724d97c8a264746b1ddaeba passed B4 run 38005345298/job 114072731120/artifact 11651350916, all six methods with zero failures/skips. The updated captures were inspected: background, second-row marker and Page 1/2 footer are visible, but the inline button style renders candidate text too faint in the non-key panel. The next change uses ordinary borderless native buttons with explicit attributed native title colors/font; it does not change action identities or focus. The faint captures remain preserved and are not presented as the final contrast result.

## Reviewed product checkpoint

Exact product head a376f1fa408842351c8630042ff5df9803a70d80 (tree 77efb87e683a4586656b6ead7fb37678ff1e48f2) passed independent static and image review and all six standard macOS workflows:

- B4 run 38005716872/job 114073923006/artifact 11651690020: six methods, zero failures/skips. Expected Space output comes from the immediately current engine highlight. Actual button/digit selection commits once; stale-page clicks retain the newer valid panel. Cancel, first-responder loss, window deactivation and mode invalidation remain inert to old controls. The bounded 160-key loop does not commit or grow the panel-window count.
- A1 run 38005716827: sanitizer ABI, state, ten engine and eight AppKit methods plus all 3,800 benchmark samples passed. One unrelated B2-unconfigured engine-filter skip remains recorded.
- A2 run 38005716893: 28 real constrained cases, full paired comparator and AppKit host passed.
- B1 run 38005716935: twelve native-control methods passed.
- B2 run 38005717069: ten governance, four file and five manager methods plus seven native stages passed.
- B3 run 38005716887: nine settings-store methods and nine fresh-process native stages passed.

Both actual B4 panel PNGs were independently opened and matched byte-for-byte to the job log. Normal candidate text is dark/readable; blue triangle and semibold identify Page 1's second row and Page 2's first row. The current-page/more footer is readable, with no clipping in these samples. Each capture is 240x150 RGBA with alpha 255 throughout. SHA-256: highlighted-second a466cd9c06652dd2fcfc8bf574b421dff138650f5ec5f7e6f06b201e78aeceda; next-page 4e954ba753b0abd9065baad9f26b3b1cded155be8e73b604a4a896100b2193ac. These light-appearance samples do not establish the untested display/appearance or physical-input matrix.

The initial 3ff4780 and intermediate acea581 heads also completed all six workflows successfully. Their rejected visual captures remain part of the evidence rather than being relabeled as successful final presentation. No test failure was observed on these three code checkpoints. The final evidence-only update leaves product/tests/workflows/resources unchanged; its own checks and exact merged-main checks are not inherited from this product result.
