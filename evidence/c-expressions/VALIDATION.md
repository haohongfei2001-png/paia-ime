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
