# B5 validation record

Baseline main fde93f2e9618564fb1456caab61e11d1313ddb31, after B4 main checks and private recovery. Initial implementation adds same-lock known-outcome verification and an explicit native control, with no automatic Save retry or input-mode publication.

Eight new SettingsRecoveryTests methods cover synthetic filesystem/fault outcomes. Seven SettingsRecoveryHostTests methods use the existing real engine and actual AppKit objects, while disk faults remain explicitly SIMULATED. The native suite shares one librime owner within its separately filtered process and creates isolated synthetic settings stores; it does not claim a full app restart or launch test.

Linux static A1/A2 resource/privacy audits and diff whitespace checks pass. Native tests and the two success/failure captures still require the official standard macOS run and actual pixel inspection. No native success is inferred from source assertions. Product-head, final-head and exact merged-main checks require independent results; all failures/skips and recovery limitations remain recorded.

## Initial native checkpoint

401708478b1af9edd4dae89b432e178bec223478 completed all seven standard macOS workflows successfully. B5 run 38007687301/job 114080170332/artifact 11652095359 passed eight store methods and the initial six native methods with zero failures/skips. The verified-save and blocked-save root-view PNGs were actually opened: both show committed synthetic “你好”; one shows the verified outcome with Save enabled, the other blocked Save with verification still available. They do not establish physical-input or power-loss behavior.

A1/A2/B1/B2/B3/B4 regression runs 38007687275/38007687267/38007687274/38007687286/38007687353/38007687318 also succeeded. The A1 broad engine filter's unrelated B2-unconfigured skip remains disclosed.

Review identified a non-authority UI edge: a store closed or resolved outside the controller could be re-enabled for verification by a later idle-control refresh. The subsequent change consults the store's actual pending state in the availability closure and refreshes the cached flag after refusal. A seventh native method covers both states during later real input. These changes require their own exact-head run; initial success is not inherited.
