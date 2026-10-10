# C exact-expression evidence ledger

Baseline: main 893fc3887414f1f27a3a5662c3f2c2ec86322110 (PR12, all eleven exact-main workflows success). Prior recovery remains separate.

Initial implementation status before first run: native CI was pending. Linux static pin/privacy audits and diff whitespace checks pass; no local Swift/AppKit execution is claimed.

Pre-CI independent source review found and the writer addressed:
- uncertain manager publication could rebase a draft or duplicate/resurrect a record after Verify;
- failed/offscreen full-review presentation had no acknowledgement gate;
- inherited idle verifier could miss a selection changed by the following markedRange getter;
- repeated Verify could quarantine a successfully resolved store, and invalid editor input unnecessarily blocked correction.

New regression tests retain these cases. A CI-only former-verifier mutation must produce an actual failing native insertion test before the fixed source suite runs. No pre-CI source review finding is labelled as an already executed native test.

No installation, normal IMKServer startup, private profile/input, global keyboard permission, new dependency/resource, model/PAIA call, signing or paid resource is included.

## First pushed native checkpoint c1bfef1

At c1bfef110c602928d3c6774c90977a4df412c54c, the real IMK release bundle compiled and all 11 exact store/core tests passed. The deliberate former-verifier test executed 1 test with 2 expected failures, including one unsafe host insertion, then restored source successfully. The fixed native suite passed its first seven tests, but crashed with signal 11 during the UI test before a suite completion summary. Remaining tests were not accepted as executed/passed; the whole workflow failed. The emitted UI PNG was interrupted and fails its IDAT checksum, so it is not visual acceptance evidence. Run 38049747530 / job 114206312668; complete log retained privately with the checkpoint recovery.

The synthetic host window omitted the standard `isReleasedWhenClosed=false` ARC ownership setting used by the other retained test windows. The next checkpoint sets it, adds UI phase diagnostics, and writes the PNG to an isolated test artifact for serialization after XCTest completes. This is a targeted suspected crash fix, not a claim of confirmed cause until the rerun.

The next checkpoint also quarantines pending-before-publication snapshots until explicit verification, with store/manager reload assertions, and records the separate production dictionary provenance gate.

## Successful C checkpoint 3fedd0a

At 3fedd0a9ff073910a7b9436cc56419820facb7fb (tree 97b528a14f3b020d8c05d5e366e2145f98ba5d7f), All twelve exact-head workflows succeeded. C run 38050172393 / job 114207532601 (artifact 11669102217, digest sha256:f463a889795c420d59e412603bb646391023668e7cb6f8e88761b5c7a70ca37a) passed release compilation, all 11 store/core tests, the deliberate 1-test/2-failure former-verifier regression, source restoration and all 14 fixed real-engine/IMK protocol tests. UI phases captured/cancelled/manager-open/saved/before-cleanup completed and XCTest exited successfully. The combined window-lifetime fix and separated capture removed the observed crash on this rerun; the original run has no stack trace, so a unique root cause is not asserted.

The writer opened the accepted 620x430 opaque AppKit full-review render: original text, first-save/update timestamps, revision, unknown sent time, scroll area and explicit Use/Cancel controls are readable. PNG bytes 94,010; SHA256 a6ec0ec7cdf65a5357d3284ac2e1f8ef2c8db98609709a96e9250c7d0ba47d7a. It is a native view-content render, not an installed input source. Core/store assertions use authored records and injected file faults. Driver tests use real librime plus actual NSTextView-backed IMKTextInput; injected presentation acknowledgements in most tests are not visual proof.

The final acceptance refinement keeps product source unchanged and strengthens the native UI test with actual panel-hide wiring, long-review last-glyph visibility and a separate tail capture. It also checks unknown JSON keys/oversized envelopes. Exact final-head and merged-main workflows and independent source/native/pixel acceptance must be retained separately; an older green head is not substituted for these changed tests.
