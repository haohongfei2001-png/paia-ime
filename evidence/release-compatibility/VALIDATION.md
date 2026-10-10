# Release compatibility: checkpoint evidence

## Draft source checkpoint

Base: `d2f9d62b3d34dba79e958aa1b42e2437691f8d19` (PR20 exact-main all twelve
workflows succeeded and complete private recovery was verified before this node).
Current source changes are uncommitted at this writing; **native validation is
pending**. Linux checks passed source diff whitespace, Python compilation, shell
syntax, three pinned-resource/privacy audits and the unchanged 308 reference-core
checks. These are not Swift/AppKit execution.

The new suite is configured for six strict-store tests, four launch-parser tests,
twelve candidate-update core tests, a deterministic expected-red existing-only
race control, and independently launched N/N+1 processes. Intended successful
matrix: five original N host stages, two N+1 host save/delete stages, five actual
N app preflights, two explicit N+1 store saves, six positive compatibility checks
and twenty-one negative app-entry checks. These are expected counts, not results.

The frozen original N source is `d2f9d62b3d34dba79e958aa1b42e2437691f8d19`;
its original 0.3.0/build 1 app/test artifacts are hash-inventoried before/after.
N+1 is 0.3.1/build 2. No new data format or resource source contract is introduced.
All test data is authored and isolated. Private inputs, installed service, paid
models, signing credentials and system input-source settings are absent.

Labels: SIMULATED for store/codec/fault tests; ENGINE_NATIVE + APPKIT_HOST for
original or current production modules in XCTest; actual executable --preflight
for the separate uninstalled app checks. A strict compatibility success performs
real child-engine probes but zero main-engine attempts. No INSTALLED_IME,
LIVE_CLIENT or HUMAN_STUDY evidence is claimed. See the
[contract and limitations](../../docs/RELEASE_COMPATIBILITY.md).

All first failures, expected-red outputs and skipped stages will be retained with
exact head/main SHAs. Final-head CI, independent review, merge/main acceptance and
private recovery remain pending for this new node.
