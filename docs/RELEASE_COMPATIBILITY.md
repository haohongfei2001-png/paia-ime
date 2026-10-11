# Existing-data compatibility and frozen executable qualification

This node continues the original HANDOFF release/update/rollback gate. It does
not install, register, launch an IMKServer, sign or automatically replace software.
The default resource pack still has **46 authored rows**. Full vocabulary remains
explicit, unbundled research; corpus rights and daily-use quality are unresolved.

## Exact engineering entry

The unsigned candidate 0.3.1/build 2 accepts only:

```
PAIAInputMethod --compatibility-check --isolated-parent /absolute/existing/parent
```

This explicit engineering check never discovers a HOME profile. It opens an
existing product root, all three stores and any selected public-resource catalog.
Missing locks/slots/markers, corrupt or unknown envelopes, unsafe links and held
writers refuse the check. Legitimately never-saved settings/expressions remain
absent. Normal input startup keeps its existing optional-store fail-soft behavior;
the strict check is separate and cannot silently treat an unavailable store as
empty. Personal initialization additionally requires an explicitly creating open,
even if a writer lock appears between its presence check and open.

The three production validators and their descriptors are shared with normal
startup. Their locks remain held throughout public-resource verification. The
catalog writer lock is also retained. Existing validators perform flush barriers;
component verification and helper probes create private scratch. Therefore this
is an **authority-byte-preserving assessment**, not a no-filesystem-writes claim.
No migration, repair, publication or save retry occurs. Original v1 settings bytes
are retained until an explicit settings save writes the already-existing v2 form.

Bundled/current/recorded-last-good selection uses the same pinned source policy
and real child-engine probes as runtime. A healthy recorded last-good is a valid
result, with its reason in the receipt. An incompatible catalog source contract
refuses before fallback; there is no silent third bundled fallback. The receipt
contains versions, format/revision metadata and a public reference, not personal
text or paths. It returns before controller, NSApplication, main engine or server
entry. It is point-in-time evidence, not an installer transaction, future CAS,
publisher authentication or protection from arbitrary same-user code.

## Real N → N+1 → N test boundary

N is frozen from original main `d2f9d62b3d34dba79e958aa1b42e2437691f8d19`,
version 0.3.0/build 1. Its original app and original XCTest bundle are built once.
All original tracked source Git blobs and all app/test-bundle SHA256 hashes are
recorded and compared afterward, including after a failed stage. No N source is
patched; it never receives N+1 flags or libraries. N+1 is the current candidate.
The versions deliberately retain the same existing data and public-source
formats. This does not qualify a future format or changed source contract.

`Tools/test-release-compatibility.py` runs independently launched processes:

- N's original real-engine/AppKit test creates the empty authored product root;
  N+1's production UI/store path explicitly saves settings, two terms and exact
  Unicode text. N's actual app preflight and original host test consume the new
  bytes. N+1 deletes terms/expression; original N consumes the tombstones without
  relearning or resurrecting them. Read stages compare complete authority bytes,
  inode/mode/link identities before and after.
- Original N saves established data; N+1 explicitly advances its settings revision
  without changing values; original N's real host reads and uses it unchanged.
- A separately labelled **authored legacy v1 envelope** is assessed without
  mutation, explicitly saved as v2 by N+1, then read by N's actual app preflight.
  N did not generate the v1 fixture. That preflight is a narrower smoke test than
  the complete current-v2 host restore oracle.
- N+1 publishes fixed baseline/updated public resources; the actual original N app
  uses current and recorded-last-good with the same current personal authority.
- Existing-only unit tests and the actual new app entry reject corrupt/future
  formats, missing authority, interrupted marker-only saves, unsafe links,
  competing writers and malformed flags. Before-publication and after-publication
  interruption tests distinguish the previous and valid published generations;
  neither implies every interruption must restore old data. Uncertain handles
  remain quarantined.

The race regression temporarily instruments only the observed stat result, then
removes the creation guard for an expected-red control. It restores exact source
bytes. This is a deterministic **SIMULATED** stat/open race, not a claim of a
successfully timed OS race. The frozen N executable/test source is never mutated.

The direct macOS test invocation follows SwiftPM's own `-XCTest` test selector
[implementation](https://github.com/swiftlang/swift-package-manager/blob/swift-6.1-RELEASE/Sources/Commands/SwiftTestCommand.swift).
Its test-only loader paths use the installed official SDK platform directories,
following [TestingSupport](https://github.com/swiftlang/swift-package-manager/blob/swift-6.1-RELEASE/Sources/Commands/Utilities/TestingSupport.swift).
Every stage checks both its explicit marker and one executed test; an empty filter
cannot pass. Actual app preflights and XCTest-host commits are separately labelled.
The existing public macos-15 workflow runs the suite; no new runner or service.

## Observed implementation checkpoint

The b6c69a1 source checkpoint passed all twelve macOS workflows: five original N
host stages, two N+1 save/delete stages, five original app preflights, two explicit
store saves, six successful checks and 21 authority-preserving refusals. Frozen
source/app/test inventories and the expected-red/restored controls were retained
and verified. See the linked evidence for exact source/run IDs and final-head/main
status; these counts do not establish installed software transitions.

## Remaining release gates

Native CI and a frozen unsigned executable comparison do not qualify installed
software switching, real application clients, signed/notarized updates,
registration/uninstallation, crash/power-loss durability, production corpus rights,
large-dictionary quality/performance, accessibility or human efficiency. Actual
user-Mac installation and security-sensitive actions need their separate process.
See [commit-bound evidence](../evidence/release-compatibility/VALIDATION.md).
