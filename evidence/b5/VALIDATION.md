# B5 validation record

Baseline main fde93f2e9618564fb1456caab61e11d1313ddb31, after B4 main checks and private recovery. Initial implementation adds same-lock known-outcome verification and an explicit native control, with no automatic Save retry or input-mode publication.

Eight new SettingsRecoveryTests methods cover synthetic filesystem/fault outcomes. Seven SettingsRecoveryHostTests methods use the existing real engine and actual AppKit objects, while disk faults remain explicitly SIMULATED. The native suite shares one librime owner within its separately filtered process and creates isolated synthetic settings stores; it does not claim a full app restart or launch test.

Linux static A1/A2 resource/privacy audits and diff whitespace checks pass. Native runs and actual success/failure-view inspections are recorded by exact checkpoint below; source assertions alone do not establish success. Final-head and exact merged-main checks require separate results, retained in the private recovery snapshot. All failures/skips and recovery limitations remain explicit.

## Initial native checkpoint

401708478b1af9edd4dae89b432e178bec223478 completed all seven standard macOS workflows successfully. B5 run 38007687301/job 114080170332/artifact 11652095359 passed eight store methods and the initial six native methods with zero failures/skips. The verified-save and blocked-save root-view PNGs were actually opened: both show committed synthetic “你好”; one shows the verified outcome with Save enabled, the other blocked Save with verification still available. They do not establish physical-input or power-loss behavior.

A1/A2/B1/B2/B3/B4 regression runs 38007687275/38007687267/38007687274/38007687286/38007687353/38007687318 also succeeded. The A1 broad engine filter's unrelated B2-unconfigured skip remains disclosed.

Review identified a non-authority UI edge: a store closed or resolved outside the controller could be re-enabled for verification by a later idle-control refresh. The subsequent change consults the store's actual pending state in the availability closure and refreshes the cached flag after refusal. A seventh native method covers both states during later real input. These changes require their own exact-head run; initial success is not inherited.

## Reviewed product checkpoint

Exact 8f8d7ff9dd2eefeb115d6b5571f6a8db84b22be4 (tree 3e6e3a124657c44847fe14bea9ed820c92fbe112) passed independent complete static review and all seven standard macOS workflows:

- B5 run 38009657066/job 114086465946/artifact 11652538839: eight store methods plus all seven native methods passed, zero failures/skips. The new closed/separately resolved store case stays unavailable during subsequent real input. Same-lock verification preserves the exact current mode, dispatcher, session key and input generation; only a later separate Save increments the verified revision.
- A1 run 38009657075: sanitizer ABI, state, ten engine and eight AppKit methods plus all 3,800 benchmark samples passed; the unrelated B2-unconfigured engine-filter skip remains recorded.
- A2 run 38009657116: 28 real constrained cases, full paired comparator and AppKit host passed.
- B1 run 38009657071: twelve control/focus/repair methods passed.
- B2 run 38009657325: ten governance, four file and five manager methods plus seven native stages passed.
- B3 run 38009657085: nine settings-store methods and all nine fresh-process stages passed.
- B4 run 38009657160: all six navigation/presentation methods passed.

Both new B5 PNGs were actually opened and are byte-identical to the independently inspected initial captures. Verified-save SHA-256: 2270df9c4543cccd31d3d609bf25b1e4c27d679358ee7230c7ce5620f5db2a12. Blocked-save SHA-256: ef75603054ec791ba2322a9d9369c99978c38234aa997ff7ce2f887fe11aa3be. A visible native success/failure state does not imply real disk-failure, full-launch or installed-client validation.

No test failure occurred on the two code checkpoints. Deliberately injected failure outcomes are asserted as failures of the attempted operation, not swallowed test failures. The final evidence-only update changes no product, tests, workflow or resource; exact final-head and merged-main verification remain separate from this product checkpoint.
