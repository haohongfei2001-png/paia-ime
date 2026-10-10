# Exact local expressions: consolidated C product node

Status: implementation under review; native compilation and CI pending. This is not installed-IME, live-client, human-study or production-release evidence.

The original HANDOFF/REPORT asks for explicit complete-expression save and recall at the input point, separate from ordinary pinyin and sent-message records. This node integrates that path into the existing IMK driver, not a parallel host writer. No model or PAIA is involved.

## Run the isolated lane

Build with existing `Tools/prepare-a1.py` and `Tools/build-imk.sh`. The default bundle retains only the authored fixture and existing notices. The optional explicit startup environment `PAIA_C_STORE=/absolute/isolated/directory` opens one exclusive local expression store; omission leaves saving/recall unavailable. Do not use a private profile, register an input source, install or start the normal service for these tests. Research dictionaries are not required or bundled.

In the IMK settings window, open “Manage exact local expressions”. Manually enter or paste the complete expression into that editor, optionally give up to eight comma-separated lookup aliases/pinyin, and explicitly Save. No programmatic clipboard, host selection, screen, previous commit or message capture populates it. An editor draft stays in controller memory across window close, and is released on service shutdown; it is not silently saved.

When this input method receives Option+Space while its current client is idle, recall opens without a key window or hidden marked placeholder. During composition the shortcut is consumed without committing or clearing it. Query text and user-supplied aliases are matched locally, case/diacritic-insensitively only for lookup. No generated surrogate, automatic transliteration or fuzzy semantic search is claimed. Up/down selects, Return opens full review, a separate non-repeated Return or “Use exact text once” applies it. Escape cancels. Page Up/Down and scrolling read the complete review. List snippets are explicitly previews; insertion always uses the reviewed exact original. Modifier shortcuts release the idle client to the host after cancelling recall. When the optional store is absent/unavailable, idle Option+Space retains host passthrough in both Chinese and literal modes. The system may intercept Option+Space; there is no global event monitor.

## Identity, source and storage

`ExpressionCore` keeps ID, global/record revision, exact text, aliases, actual record creation/first-save/update times and fixed `manualSaved` source. `sourceCreatedAt` and `sentAt` are explicit null: the source's original authorship and sending are not observed. Edits keep first-save time and advance update/revision. Deletion drops body/aliases from the current authority while retaining an ID/revision/time tombstone; it does not claim to erase OS backups, snapshots or storage media. No sync/import can resurrect a deleted ID in this node.

Text is never normalized, trimmed, truncated or rewritten. Exact comparisons use UTF-8 bytes, not Swift canonical-equivalent String equality. Limits are 16,384 UTF-16 units per expression (also independently enforced at host effect), eight 128-unit aliases, 2,000 total records including tombstones, and an 8 MiB canonical envelope. Over-limit values are refused. The codec checks canonical encoding/digest, closed source semantics, unique IDs, timestamps, revisions and nesting. No dictionary or model files are added.

The store adapts the existing settings-store boundary: selected root and held writer-lock identities, no-follow/regular/single-link authority, bounded reads, exact expected bytes, staging, atomic file rename and file/directory durability barriers. Unknown publication quarantines recall; explicit Verify only checks that same handle's prior versus attempted bytes and writes no authority. Orphan initialization, unrelated valid data, corrupt or replaced authority remain blocked. Store IO happens at startup or explicit management, never on typing/query/review/insertion. The immutable catalog represents the last verified authority, not live polling for out-of-process file edits.

The manager freezes edits while its own publication is unresolved. Successful verification reconciles the specific saved/deleted record; it must not turn a repeated Save into a duplicate/new-ID resurrection. Reloading does not silently rebase an old selected draft to a newer revision. Active recall blocks management process-wide until cancelled. All idle engine owners retire before catalog publication callbacks.

## One text effect and bounded host capability

Driver state owns query/list/full-review tokens, record ID/revision/digest and catalog epoch. The session binding includes session, target, input/privacy generations and dictionary revision. A presentation must acknowledge the exact review token before it can be accepted; failed/offscreen/reentrant presentation cannot authorize insertion. Acceptance consumes that token before any client/presentation callback.

`explicitExpression` effects go through the existing SessionCore pending-operation reservation and IMKSessionCoordinator.apply dispatcher. Panel/manager code never calls a host insert. The idle client must still have the expected empty selection and no foreign mark. Repeated bounded selection/mark observations catch a selection changed inside the late markedRange callback. CI deliberately restores the former verifier temporarily and requires the native regression to fail, then restores exact source and runs the fixed suite. This is not atomic compare-and-swap: a cross-process host can still change after the last read, or silently reuse a callback object/document without notification. Only the existing C0 lifecycle-scoped contract is claimed; no stable global document identity or C2/C3 selected-range capability is invented.

Writes use an explicit finite insertion range, then exact bounded output-span readback. Unknown/truncated readback or lifecycle reentry retires the session without retry or cleanup; transient issued text can be inspected from the existing recovery menu, but is never replayed. Full context/document length and surrounding text are not read. After a confirmed insertion, ordinary real-engine input continues.

## Evidence and remaining scope

`expressions.yml` uses the existing public standard macOS runner, real pinned librime and authored NSTextView-backed IMKTextInput clients. Core/store tests and native driver/UI tests are separate. Native panel screenshots are view renders, not installed-service screenshots. Source-level tests with injected acknowledgement callbacks do not by themselves prove a visible panel; the actual AppKit panel test supplies that narrower proof.

Still open: G01 retained-composition controls and known-character contextual proof in the IMK path; selected-host capture and reviewed C2/C3 editing; licensed production dictionary release; installed/live compatibility, physical keys/VoiceOver, long-run quality/performance and user-efficiency studies; signed installer/update/rollback/uninstall. This node neither purchases/uses AI nor clears those gates.
