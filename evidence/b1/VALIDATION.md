# B1 native controls, work in progress

Baseline main: 5994a16172f79d4127abf900793217aaa9f6c584. Draft PR #3.

- 477364a09bda44edf5c2c1bc489a6f135c474fbe: B1 run 37986391131/job 114009325222 FAILED. All six schema/output choices and literal/Chinese punctuation native control tests passed. Repair-inspector entry failed in four methods (16 assertions); it was not accepted as working UI. A1 regression run 37986391243 succeeded. Native failure logs are retained. Independent review additionally found deterministic Accept focus-restoration self-cancellation and stale-resume UI cleanup problems; both fixed in subsequent changes. Extra field-editor/marked-range diagnostics and retained-control tests were added without weakening assertions.

No physical mouse/VoiceOver, installed input source, live-client or user-quality claim. Research data remains in a separate unbundled B1 cache, and A2 comparison schemas remain unchanged.
