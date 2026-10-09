# B1 native controls, work in progress

Baseline main: 5994a16172f79d4127abf900793217aaa9f6c584. Draft PR #3.

- 477364a09bda44edf5c2c1bc489a6f135c474fbe: B1 run 37986391131/job 114009325222 FAILED. All six schema/output choices and literal/Chinese punctuation native control tests passed. Repair-inspector entry failed in four methods (16 assertions); it was not accepted as working UI. A1 regression run 37986391243 succeeded. Native failure logs are retained. Independent review additionally found deterministic Accept focus-restoration self-cancellation and stale-resume UI cleanup problems; both fixed in subsequent changes. Extra field-editor/marked-range diagnostics and retained-control tests were added without weakening assertions.

No physical mouse/VoiceOver, installed input source, live-client or user-quality claim. Research data remains in a separate unbundled B1 cache, and A2 comparison schemas remain unchanged.

- a46a02c00343c4f989cca0520d5c757378ea8d1e: run 37986745196/job 114010508632 FAILED at compile. A diagnostic used unqualified Swift type(of:) inside a test class that already defines type(_:_:), causing name resolution failure. Qualified the standard-library function; native tests on this head were SKIPPED. A1/A2 workflows failed at the same shared test compilation and are not counted as regression passes.

- e474a741e3d70ad06f0219ac5c6f263d1d4ad618: run 37987020771/job 114011438177 FAILED (7 methods, 44 assertions). Native diagnostic traces identified the real transition: owned NSTextField → shared NSTextView field editor while its delegate is still nil. The initial validator rejected that intermediate responder and cleared the composition. The fix scopes that specific nested field-editor transition to the already-approved outer owned-control request, then validates the final active editor/target. It does not generally allow arbitrary nil-delegate responders or unrelated focus. Marked-range and selected-range invariants remain asserted.

- cd65d393495d01a7f143dedcf0b6edb85f4515f9: run 37987393102/job 114012683087 FAILED before all eight methods could exercise their behaviors. A newly added target-row scroll view activated its width constraint before joining the root view hierarchy, raising AppKit's common-ancestor exception. Moved constraint activation after attachment; no screenshot or focus-validation pass is inferred from this run. Added adversarial nested foreign/nil focus and transition-state-reset assertions, plus literal-mode supplementary-plane, combining-mark and emoji coverage.
