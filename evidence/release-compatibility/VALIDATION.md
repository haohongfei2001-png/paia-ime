# Release compatibility: checkpoint evidence

## Complete native implementation checkpoint

Source `b6c69a17622cb8e18f99eaf9bbbffdbdd8f0462e`, tree
`0de894638d2592e2d5c21328141aa49d3ec501f5`, passed all twelve existing public
macos-15 workflows. The [IMK job](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38093533310/job/114334639567)
ran 2026-10-10 23:05:46–23:29:50 UTC, all 24 steps successful. Its frozen-build
stage ran 23:19:14–23:21:19; the actual cross-version matrix ran
23:21:19–23:24:34. Queue/build/test duration is not input latency.

The base `d2f9d62b3d34dba79e958aa1b42e2437691f8d19` (PR20) independently
passed its own twelve exact-main workflows and private recovery before this node.
The successful new-source checkpoint is not replaced by that older acceptance.
Local whitespace, Python compilation, shell syntax, three pinned-resource/privacy
audits and the unchanged 308 reference-core checks also passed. Linux had no
Swift/AppKit; all native execution came from the macOS workflows.

## Observed results

- Six existing-store tests passed, including genuinely empty stores, missing
  authority, future formats, v1 byte preservation, competing handles and previous
  versus already-published interrupted-save outcomes. Four launch-parser and
  twelve candidate-publication tests passed. A canonical index changed during
  inspection is refused as stale; the private snapshot is closed, with no repair.
- The deterministic **SIMULATED_STAT_RACE** control passed with the new creation
  guard. Removing only the guard produced the expected one-test/two-assertion
  failure: an existing-only opener created authority. Exact source restoration
  and all six rebuilt green tests followed. Original failed-control logs remain.
- Frozen original N 0.3.0/build 1 retained 284 original tracked source files,
  111 app files and four XCTest-bundle files in full SHA inventories. Every source
  file's Git blob and SHA256 was independently compared to original `d2f9d62`.
  The harness's final inventory comparison passed after all processes, without
  recompiling or patching N. Its Boost headers were extracted by original N from
  the reverified pinned archive, not copied from N+1 build output.
- Original N's original XCTest/production modules ran five real-engine/AppKit
  stages: initial public creation, new-save restore, deleted-state restore,
  original save and established-data restore. N+1 ran two production-host
  save/delete stages. Each process executed exactly one named test and checked
  one main-engine attempt, zero main deployment and its stage marker.
- Five separate original N app preflights consumed new saves, new tombstones,
  explicitly upgraded authored v1 data, public current and public last-good.
  They checked personal-active state, exact selection reason/preset and, for
  selected public catalogs, the same generation as N+1's receipt. Authority
  bytes and inode/mode/link identities stayed unchanged during read stages.
- Two explicit N+1 production-store saves advanced settings revision 1→2 and
  authored legacy revision 7→8. Those save-only tests are SIMULATED, main entry
  zero. N did not generate the v1 fixture; its post-upgrade app preflight is a
  narrower smoke test than the complete current-v2 original-host restore oracle.
- Six successful new executable compatibility checks and 21 explicit refusals
  all reported zero main-engine entry, with the complete authored authority tree
  unchanged. Positives cover never-saved/current/legacy/tombstone/public-current/
  public-last-good cases. Negatives cover missing roots/slots/locks/markers,
  future or corrupt envelopes, marker-only interruption, symlink/hardlink paths,
  incompatible public source contract, both bad public generations, two held
  writers and four malformed argument forms. Successful checks use real isolated
  public-engine helper probes; they never launch the main engine or IMKServer.

## Retention and failure boundaries

All twelve complete raw job logs, job/run metadata and all twelve original
artifact ZIPs were downloaded and SHA256/CRC verified before expiry. The IMK
artifact contains 203 files, including full frozen source/app/test inventories,
runner environment, receipts, authority-tree snapshots, original expected-red
and restored outputs, all per-process logs and the machine-readable matrix.
These evidence ZIPs retain the binary inventories, not the runner-local app or
XCTest binary bodies. Rebuilding the pinned original source is a separate action.
The initial implementation checkpoint had no unexpected CI failure. Existing
source/dispatch/lock/quarantine expected-red controls remain visible; they are
not silently erased or counted as ordinary all-green test cases. A1's broad
selection retains its documented personal-only skip; the dedicated personal
workflow covers that configuration. None of the new cross-version stages skipped.

Read-only source review found and closed three issues before this checkpoint:
existing-only Lexicon initialization under a stat/open race, incomplete original
app selection assertions, and trusting copied extracted Boost headers. Native
independent review and final documentation-only head acceptance are separate.

## Scope and remaining gates

Labels: SIMULATED for store/codec/fault tests; ENGINE_NATIVE + APPKIT_HOST for
original/current production modules in XCTest; actual executable --preflight for
separate uninstalled app checks. Current validators perform flush barriers, and
helper probes allocate private scratch; authority preservation is not a global
no-filesystem-write claim. No new data/resource format was introduced.

This qualifies one frozen unsigned software/data pair on authored isolated data.
No INSTALLED_IME, LIVE_CLIENT, HUMAN_STUDY, signed updater, installed switch,
power-loss qualification, user profile, signing credentials or system input-source
change is claimed. Default vocabulary remains only 46 authored rows; the full
corpus is explicit unbundled research with unresolved production rights. See the
[contract](../../docs/RELEASE_COMPATIBILITY.md).

Final-head CI, independent final review, merge/exact-main acceptance and private
recovery are still pending when this source document is written. Their eventual
results must use their own SHAs and raw evidence, not reuse the implementation
checkpoint as if it covered subsequent code changes.
