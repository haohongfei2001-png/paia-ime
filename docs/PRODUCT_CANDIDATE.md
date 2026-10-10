# Integrated offline candidate: resource and data contract

## Scope and qualification

PR19 joins the already implemented input paths in the actual unsigned InputMethodKit application. `Tools/build-imk.sh` now builds `.build/PAIAInputMethod.app` as the integrated candidate, alongside the separately named `.build/PAIAInputMethodFixture.app` for the original two-schema resource-recovery experiment. The candidate contains **46 authored dictionary rows**, not the large research corpus or a daily-use language model. A default app can exercise Full/Flypy/Natural, Simplified/Traditional, punctuation, bounded fuzzy/typo policies, native retained G01 repair, explicit mixed input, settings, terms and exact expressions without research environment flags. Full vocabulary remains an explicitly configured, unbundled research lane with unresolved production rights.

This closes a source/build/integration gap. It does not establish installed IMK behavior, real-client C2/C3 permission, input latency/quality at production vocabulary scale, signing, distribution rights or everyday usability. The preflight and automated tests never construct `IMKServer`, install/register a source or change system preferences. Refer to [commit-bound evidence](../evidence/product-candidate/VALIDATION.md), not a previous checkpoint's green checks.

## Closed public resource pack

The separate format-2 `CandidateManifest` leaves the existing v1 publication/recovery contract unchanged. Its profile is `authored-candidate-v1`:

- 19 existing A1 rows plus 27 authored habit rows; no user input or external corpus words.
- Exactly three pinned Rime Ice spelling/preedit recipes and three pinned OpenCC s2t files. The build selects these six resources by fixed names, verifies size/SHA256, and does not recursively copy a research directory.
- 32 effective spelling/script/punctuation/fuzzy/correction schemas and eight prisms. Double-Pinyin correction is not invented; the independent typo control applies to Full Pinyin only.
- Exact root/subdirectory inventories, source/artifact names, resource ABI/header/engine identity and canonical manifest. Unexpected files, missing artifacts and corrupt bytes fail closed.
- The unchanged official librime binary is placed at its loader-local install-name alias. The built G01/mixed component has only `@loader_path` rpath and system-library dependencies. Engine, extension and helper are verified and copied to private owned snapshots before loading/execution.
- A helper compiles the sources; a separate helper proves real candidate selection/commit, punctuation, discriminating double-Pinyin behavior, policy negatives, G01 and mixed capabilities. Main startup is precompiled and performs zero deployment calls.

The [candidate source inventory](../Resources/candidate-sbom.json), [A1 lock](../Resources/a1-lock.json), [A2 immutable inputs](../Resources/A2/upstream-lock.json) and dependency notices identify source URLs, hashes and license declarations. Each build additionally records `candidate-inputs.json`, native probe receipt and the complete bundle file hash manifest. Hashes establish byte identity, not publisher authentication or a blanket license. Rime Ice spelling derivatives carry GPL source obligations; OpenCC maps carry Apache obligations. [Production dictionary clearance](PRODUCTION_DICTIONARY_GATE.md) remains separate.

## One data root, three independent authorities

Only a future normal service launch selects the current user's Application Support parent and fixed `paia-ime` leaf. Automated preflight uses a newly created private temporary parent; product tests supply new explicit CI parents. Existing research stores are never discovered or migrated.

The product root has a canonical layout marker, an existing-only writer lock, and settings/personal/expressions child slots whose markers bind them to that root. The implementation walks all ancestors with no-follow directory descriptors, preserves physical path spelling, checks ownership and permissions, and verifies inode/path identity before and after operations. Initial creation publishes a private staged root exclusively and acknowledges directory durability barriers. A missing slot, established store lock, or mismatched/missing marked authority is unavailable rather than reconstructed. Only a root actually created in this startup may create store locks; an interrupted initial setup can therefore leave an unavailable optional store rather than guessing a fresh state. Existing permissions are never repaired automatically.

Each store receives a duplicated already-open child descriptor plus a root/slot authority guard. It does not reopen a URL and accidentally create files in a replacement path. Post-publication uncertainty remains explicit; no automatic retry or overwrite is added. An existing settings/expression store with neither initialization marker nor JSON is the original legitimate never-saved state. If both are coherently removed while retaining the writer lock, that state is indistinguishable from never-saved; this contract does not claim detection of arbitrary multi-file erasure or a same-user rewrite of the full authority. There is no secret backup or restoration. A bad optional store disables that store while public typing remains available. A second product process may use public input but cannot become a second writer. Directory replacement, changed authority and same-bytes/different-inode read races are rejected.

Ordinary keystrokes do not save settings, learn terms or archive expressions. Existing explicit native Save, Add/import-preview, delete/no-relearn, full-expression review and once-only insertion controls are reused. Per-application initial mode preferences affect new activations only. No management window or background sync service was added.

## Explicit personal terms and startup

The parent exports one frozen `LexiconCodec` envelope, then the verified helper receives only that immutable snapshot. No authoritative store path or writer descriptor is passed to it, and helper code never opens a store. The child uses a clean environment and close-on-exec descriptors; it is not an OS-sandboxed security boundary and still runs as the same user. Its derived manifest binds the exact public base, personal revision and SHA256, compiler version, and fixed pin/ordinary tiers. Only the eight Full/Simplified overlay schemas and enumerated personal artifacts may differ from the base. All other public artifacts must match exactly.

A second helper probes the derived pack, all public policy schemas, eight plain fallback aliases and bounded ordinary/pinned samples. It is not an exhaustive personal-vocabulary quality guarantee. The parent rechecks authority after preparation; the final check occurs after resource/component hashing and immediately before the main engine entry. Stale/deleted/replaced authority or helper failure selects the pristine public snapshot without restoring earlier personal bytes. A failure after main native entry consumes that process's sole attempt and never retries another engine in the same process.

Personal changes during a running process retire its sessions and disable its derived overlay until restart. Public baseline schemas remain available; deleted terms are not resurrected by rollback. Full/Simplified personal overlays deliberately disable G01/mixed because multi-dictionary proof is not qualified. Other public modes retain their genuine native capabilities. G01 and mixed API availability are checked separately, including table size/version/function pointers; a G01-only extension cannot advertise mixed input.

Preparation is startup-only and may be slow: verified bytes, child compilation and probes run before the sole main engine entry. There is no background resource downloader, hot switch, automatic model update or timed C++ interruption. Helper timeouts terminate/reap the isolated child before fallback, subject to the OS's process semantics. Main-process startup latency with large personal lexicons and installed-service behavior remain unqualified.

## Reproducible uninstalled checks

Use the existing pinned A1/A2 preparation and public macos-15 IMK workflow. `build-imk.sh --fixture-only` retains the earlier A1-only bundle build for tests that do not need the candidate. The default full build needs the already approved pinned G01 build headers/Boost and fixed recipe/map inputs; it adds no paid service or runner.

The candidate checks include closed data/resource unit tests, malformed ABI tables, actual bundle preflight, relocation outside `.build` under a clean environment, and semantic/integrity negatives. Independent processes exercise public modes, explicit saves, restored personal terms and expressions, deletion/tombstones, corrupt settings, missing or entirely erased personal authority, a second writer, helper failure, final-check authority changes and replaced roots. Deliberate read-race and routing mutants must first fail the relevant assertions, restore exact source bytes, rebuild and pass. The logs retain these expected red controls and any genuine failures.

ENGINE_NATIVE covers actual fixed librime/compiler/helper behavior. APPKIT_HOST covers actual native controls and an authored NSTextView-backed IMK protocol client. File-system fault seams and malformed ABI tables remain SIMULATED. None is installed-client acceptance.

## Remaining product nodes

1. Qualify or replace production vocabulary with a rights-cleared source set and the same fixed comparison/quality benchmarks. Do not substitute a GPL wrapper for the underlying corpus permissions.
2. Complete release package identity/signing and an explicitly authorized install/uninstall/recovery exercise, then actual apps, keyboard layouts, focus/lifecycle behavior, accessibility, multiple screens and visible latency. Real-client contextual reading/replacement stays off until separately qualified.
3. Close the original acceptance matrix at production scale: sentence quality, suffix/repair/mixed bounds, long personal resources, failure recovery and user-confirmed interaction quality. Current finite authored tests cannot establish these outcomes.

No new AI integration, public deployment or independent character-management product is implied by this node.
