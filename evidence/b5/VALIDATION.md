# B5 validation record

Baseline main fde93f2e9618564fb1456caab61e11d1313ddb31, after B4 main checks and private recovery. Initial implementation adds same-lock known-outcome verification and an explicit native control, with no automatic Save retry or input-mode publication.

Eight new SettingsRecoveryTests methods cover synthetic filesystem/fault outcomes. Six SettingsRecoveryHostTests methods use the existing real engine and actual AppKit objects, while disk faults remain explicitly SIMULATED. The native suite shares one librime owner within its separately filtered process and creates isolated synthetic settings stores; it does not claim a full app restart or launch test.

Linux static A1/A2 resource/privacy audits and diff whitespace checks pass. Native tests and the two success/failure captures still require the official standard macOS run and actual pixel inspection. No native success is inferred from source assertions. Product-head, final-head and exact merged-main checks require independent results; all failures/skips and recovery limitations remain recorded.
