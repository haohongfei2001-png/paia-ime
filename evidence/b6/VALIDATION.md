# B6 validation record

Baseline is B5 main 39f6201da8bf6c26794d767f47e42e92d0a28877, after all seven exact-main workflows and private recovery. No resource hashes or persistence semantics change.

## Regression before the layout change

Exact test-only head d8ddb38f68fc4c883c3af08ed80ab8290224bfbc leaves the old production panel untouched. B6 run 38011130487/job 114091137330/artifact 11653580146 compiled successfully, then failed two native methods with twelve layout assertions: the panel exceeded supplied safe-screen bounds and candidate row heights could not contain measured text. The actual captured long-engine view was inspected; the full-width panel was incompatible with the requested 360-point safe screen. The authored term really came from librime; its subsequent once-only commit and stale-button assertions passed. A printed stage marker is not a passing test result.

A2/B1/B2/B3/B4/B5 workflows succeeded at this regression checkpoint. The queued/running A1 workflow was superseded and cancelled by the next product push; it is not recorded as a pass. Full failure log, actual PNG and all check metadata are retained for recovery.

## Product verification in progress

The native product change must pass its own exact-head tests, independent review and actual rendered-image inspection. Linux resource/privacy audits and whitespace checks are static evidence only. Final documentation and exact merged-main checks remain separate; no prior checkpoint's success is inherited.

The first product head 03d30e228b28727808fc6d6082cfa14c63457729 compiled, and B4 navigation passed, but B6 run 38011436351/job 114092116141 failed four-method execution with eight assertions. Six came from an overstrict harness assertion: a fully visible row shorter than the viewport need not be top-aligned; the actual visible rectangle extended 19 points above its bounds. The corrected test requires full row intersection when fitting and exact top alignment only when oversized. Two required a key host window without first activating the isolated NSApplication; the harness now establishes and asserts that prerequisite before testing ownership retention. These failures and all four captures remain retained, not relabeled as passing.

The actual first-product captures show upright wrapped text, explicit scroll status, and accessible beginning/tail. U+20000 displays a platform missing-glyph box; exact text/layout coverage is not evidence of that character's readable font coverage. The final record retains this rare-character/font limitation.

Checkpoint 0a0a313ec20c5340901093fad1a6296b53921937 passed all layout, text coverage and narrow-footer assertions; B6 still failed three key-window prerequisite/retention assertions because the synthetic host did not become key. Activating NSApplication and pumping only Foundation RunLoop was insufficient. The next harness processes the actual AppKit event queue for a bounded interval and reports active/canBecomeKey/isKey explicitly. No production focus policy is weakened and this failed run remains preserved.
