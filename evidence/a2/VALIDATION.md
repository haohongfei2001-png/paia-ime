# A2 evidence, in progress

Baseline: main 34c8d31e64f03032c8452f6467d8197158ab975e. Draft PR #2.

## Retained attempts

- ca8bdd7329453642ead47364d99aed7a2b18d4d1: run 37983029964, job 113998021979. Acquisition verified 28 private headers, Boost 1.89 and all pinned corpus resources. Native extension compilation failed because unchanged upstream headers trigger signed/unsigned warnings under our `-Werror`. Fixed by marking verified upstream header directories as system includes; strict warnings remain on our own code. Native constraint execution was SKIPPED, not passed. Artifact 11642455423.
- Same initial head: Linux C ABI guard 8 checks passed (SIMULATED only).

No INSTALLED_IME, LIVE_CLIENT or HUMAN_STUDY evidence. A2 remains incomplete until native matrix, synthetic host, independent review and exact-main checks finish.
