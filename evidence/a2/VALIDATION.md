# A2 evidence, in progress

Baseline: main 34c8d31e64f03032c8452f6467d8197158ab975e. Draft PR #2.

## Retained attempts

- ca8bdd7329453642ead47364d99aed7a2b18d4d1: run 37983029964, job 113998021979. Acquisition verified 28 private headers, Boost 1.89 and all pinned corpus resources. Native extension compilation failed because unchanged upstream headers trigger signed/unsigned warnings under our `-Werror`. Fixed by marking verified upstream header directories as system includes; strict warnings remain on our own code. Native constraint execution was SKIPPED, not passed. Artifact 11642455423.
- Same initial head: Linux C ABI guard 8 checks passed (SIMULATED only).

No INSTALLED_IME, LIVE_CLIENT or HUMAN_STUDY evidence. A2 remains incomplete until native matrix, synthetic host, independent review and exact-main checks finish.

- c2a4afa7fee476b67e19facd75cc93346fc05f93: run 37983267841/job 113998820500 passed extension link, 2 pure tests, native matrix CLI, and 2 AppKit constraint-host tests; artifact 11642515813. A1 regression run 37983267725/job 113998819784 also passed. This is an intermediate tree: independent review identified public stale-target and candidate-capability boundaries, fixed in subsequent changes; its green checks are not final-tree evidence.
- Local Linux ASan/UBSan initially hit LeakSanitizer's ptrace limitation. Re-running with `ASAN_OPTIONS=detect_leaks=0` passes 8 C ABI checks; this is not a local leak-check pass. macOS CI keeps the default sanitizers.
- Local optional resource preparation could not finish through the cloud shell network; native CI independently fetched and hash-verified the exact inputs. A direct connector-artifact signed download returned HTTP 403 in the shell; GitHub artifact remains preserved, and subsequent CI prints bounded synthetic JSON to the job log as well.

- 4caa233f5e3ef38fd6ff6d73248c90c277e46795: run 37983770864/job 114000519932 passed 26 native matrix/comparator cases, 2 pure lease tests and 2 AppKit host tests. This includes the three independent-review API fixes, typo transposition/missing-letter correction and 130 preserved anchors (128-word suffix). 50 measured paired corrections per lane after 5 warmups had zero failures: cancel/retype p50/p95/p99 9.112375/10.382791/15.109125 ms; constrained replay 0.694292/0.996834/1.039625 ms. Startup+six-schema deployment 7318.624833 ms. These are synthetic correction+engine-commit workloads on a cloud ARM64 runner, not key-to-visible latency or a competitor-best-operation user study. Subsequent filtered-Sentence/code-identity changes still require fresh exact-head evidence.

- a0fc48462dc66dee16f00b1fa783ef428d60c67a: A2 run 37984124759/job 114001700428 and A1 run 37984124589 passed. The new genuine-code-preserving filtered-Sentence replay succeeds on the whole Traditional sentence test. This establishes one independently replayable filtered mapping, not all OpenCC boundaries; a deliberately non-replayable cross-word fixture is added next.
