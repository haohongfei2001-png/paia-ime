# B6 validation record

Baseline is B5 main 39f6201da8bf6c26794d767f47e42e92d0a28877, after all seven exact-main workflows and private recovery. No resource hashes or persistence semantics change.

## Regression before the layout change

Exact test-only head d8ddb38f68fc4c883c3af08ed80ab8290224bfbc leaves the old production panel untouched. B6 run 38011130487/job 114091137330/artifact 11653580146 compiled successfully, then failed two native methods with twelve layout assertions: the panel exceeded supplied safe-screen bounds and candidate row heights could not contain measured text. The actual captured long-engine view was inspected; the full-width panel was incompatible with the requested 360-point safe screen. The authored term really came from librime; its subsequent once-only commit and stale-button assertions passed. A printed stage marker is not a passing test result.

A2/B1/B2/B3/B4/B5 workflows succeeded at this regression checkpoint. The queued/running A1 workflow was superseded and cancelled by the next product push; it is not recorded as a pass. Full failure log, actual PNG and all check metadata are retained for recovery.

## Native product checkpoints

The native product change must pass its own exact-head tests, independent review and actual rendered-image inspection. Linux resource/privacy audits and whitespace checks are static evidence only. Final documentation and exact merged-main checks remain separate; no prior checkpoint's success is inherited.

The first product head 03d30e228b28727808fc6d6082cfa14c63457729 compiled, and B4 navigation passed, but B6 run 38011436351/job 114092116141 failed four-method execution with eight assertions. Six came from an overstrict harness assertion: a fully visible row shorter than the viewport need not be top-aligned; the actual visible rectangle extended 19 points above its bounds. The corrected test requires full row intersection when fitting and exact top alignment only when oversized. Two required a key host window without first activating the isolated NSApplication; the harness now establishes and asserts that prerequisite before testing ownership retention. These failures and all four captures remain retained, not relabeled as passing.

The actual first-product captures show upright wrapped text, explicit scroll status, and accessible beginning/tail. U+20000 displays a platform missing-glyph box; exact text/layout coverage is not evidence of that character's readable font coverage. The final record retains this rare-character/font limitation.

Checkpoint 0a0a313ec20c5340901093fad1a6296b53921937 passed all layout, text coverage and narrow-footer assertions; B6 still failed three key-window prerequisite/retention assertions because the synthetic host did not become key. Activating NSApplication and pumping only Foundation RunLoop was insufficient. The next harness processes the actual AppKit event queue for a bounded interval and reports active/canBecomeKey/isKey explicitly. No production focus policy is weakened and this failed run remains preserved.

## Reviewed passing checkpoint

Exact 095fdbcded5759fe8e9952a2191e6fb9ad8d186e (tree 21de29c2ad8e443564396b88fc61b56416d728ca) passed independent complete 12-file review and all eight standard macOS workflows. Production code is unchanged from 03d30e2; the later changes establish the test host's actual activation and strengthen visibility/footer checks.

- B6 run 38012098428/job 114094160907/artifact 11654515509: four native methods, zero failures/skips; native application build passed. The actual event queue established active=true, canBecomeKey=true, isKey=true. Subsequent layout, scroll, Space and button selection retained the host key window and editor first responder. No key-window state is forged and setup does not run during the behavior being checked.
- A1 run 38012098482: sanitizer ABI, state, ten engine and eight AppKit methods plus 3,800 benchmark samples passed. The broad engine filter retains its one unrelated B2-unconfigured skip.
- A2 run 38012098412: 28 real constrained cases, full paired comparator and native host passed.
- B1 run 38012098479: twelve control/focus/repair methods passed.
- B2 run 38012098420: ten governance, four file and five manager methods plus seven native stages passed.
- B3 run 38012098453: nine settings-store methods and all nine fresh-process stages passed.
- B4 run 38012098471: six navigation/presentation methods passed, including 160 repeated actions.
- B5 run 38012098445: eight store and seven native save-verification methods passed.

All five B6 exact-head captures were independently opened: complete wrapped long-term view, oversized selected beginning, reachable selected tail, multiline Unicode tail and 120-point-wide fixed footer. The synthetic term is explicitly authored; its real engine selection proves presentation/commit mechanics, not discovery or language quality. The previous red/cancelled checkpoints remain included in the private recovery.

Capture SHA-256 values:
- long-engine: a171d48b4dc8a94b146f65970797f209f5d9828210ae205de8043a014fd78fe6
- long-engine-start: 1abfeb4bc2ead8ac03a58c8ec7e95ff84f4a3a48c5a9e7eb49fb5d32c7dfa5d1
- long-engine-tail: be56a90e26915ab284e89f8c0d136584fc127ea1f26d91c42c947973330cf380
- unicode-tail: b9dff8e5d3d1a8d68a7cb5a8755281bcb3a946cfa714a447d16fcf57a9dde618
- narrow-footer: 33c57c158c02d621339d8e22452c3af0698d2e950bbe6dbd056d0388c4cb1de3

The final change records evidence only; it changes no product, test, workflow or resource. Final-head and exact merged-main results remain separately verified and recorded in recovery metadata. Neither all-green CI nor complete glyph-to-character coverage closes U+20000 font availability, physical scrolling/input, keyboard-only full overflow review, VoiceOver, real display/appearance matrices, installed/live-client compatibility, general language quality or visible-response latency.
