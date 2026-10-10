# C exact-expression evidence ledger

Baseline: main 893fc3887414f1f27a3a5662c3f2c2ec86322110 (PR12, all eleven exact-main workflows success). Prior recovery remains separate.

Current implementation: native CI pending. Linux static pin/privacy audits and diff whitespace checks pass; no local Swift/AppKit execution is claimed.

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
