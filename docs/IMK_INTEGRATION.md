# Uninstalled IMK engineering integration

Baseline B8 main: `61d262cf2aeaf3839c32a5aac59a74ae685688fd`.

This stage implements the original REPORT sections 10/16 and HANDOFF C0 service path rather than another lab-only UI feature. It preserves PAIANativeLab and adds a separate PAIAInputMethod executable/bundle, real IMKInputController overrides, a restricted IMKTextInput bridge and the existing serialized librime/InputSession owner. It is not yet a daily-use alpha or installed input source.

## Boundaries

`Tools/build-imk.sh` compiles and assembles an unsigned bundle inside `.build/`. `PAIAInputMethod --preflight` verifies Objective-C controller discovery, bundle metadata and the actual bundled engine/fixture plus accessory-agent policy and a real non-key candidate panel without constructing IMKServer or entering its service event loop. Normal entry contains an IMKServer startup path, but it is not run in this stage. IMKServer construction publishes a service connection; it is not a pure no-side-effect object test. Neither path installs an input source. Do not copy into Input Methods folders, invoke TIS/LaunchServices registration, sign, alter preferences/security or use private profiles.

The bundled original A1 fixture is intentionally tiny. The full research corpus remains unbundled and its production redistribution clearance remains unresolved. This artifact is engineering integration, not general Chinese input quality certification.

## Restricted C0 contract

- Initial client capability requires a finite collapsed selection and no foreign mark. Nonempty/unknown selections are not adopted; engine state is not created. No whole-document or surrounding-context read is permitted.
- Client object identity, controller activation and session/candidate generations bind the current operation. They are not a stable document identifier. Only self-owned marked text and this operation's precomputed output span are read, at most 16,384 UTF-16 units. Length, exact bytes, marked range and selection must match.
- Every write uses the verified finite insertion/marked replacement range and precomputed output ranges. Getters and writes can reenter; an old operation stops after ownership loss and does no cleanup. It never adopts a callback's unexpected state as its prediction.
- CommitEffect is reserved before the only insert call. This is at-most-once invocation, not exactly-once delivery. Unknown/failed readback retires the owner with no retry, trailing clear or cross-target write. Transient original spelling and pending-effect information are retained in memory; explicit read-only inspection does not paste or replay.
- `commitComposition` and matching `deactivateServer` use the existing raw-Return policy and retire that composition. This preserves the complete raw spelling, not already selected Chinese conversion, and is not `commitEngineComposition`. Stale/foreign callbacks cannot bind to another active client. Closing retires without text cleanup.
- Idle unhandled events pass through. Command/Option/Control during composition generally request a verified raw flush; the explicit Option+Space recall shortcut instead refuses unchanged; unknown outcome consumes the event rather than continuing against an uncertain target. B8 unsupported middle punctuation/Unicode keeps the composition unchanged, with a same-target candidate warning when geometry is available and status in the input-method menu.
- Geometry comes from the client line rectangle. No mouse-position, global event tap or extra permissions are used. A same-activation recent rectangle is the only positioning fallback; missing geometry hides the panel. Identical proxy/document ABA and unobservable changes between protocol calls remain limitations, not atomicity guarantees.

## Evidence and remaining work

New Swift/Objective-C tests use actual NSTextView behind an IMKTextInput fixture and real librime. They exercise the same coordinator and adapter called by the framework controller. That is APPKIT_HOST / ENGINE_NATIVE with a synthetic protocol client, not proof of framework-created controller lifecycle, cross-process traffic, physical input or installed third-party hosts. Controller overrides and normal service entry are compiled; actual service startup is untested here. Every failed compile/test remains a failure; exact PR/main CI and independent review are required.

The original service/host milestone preceded complete B integration. The consolidated node below wires the existing modes, bounded punctuation, explicit settings and personal lexicon through that IMK path. Production resource choice, known-character/G01 interaction, broader mixed input/discovery/keyboard accessibility and staged update/recovery still require evidence. C remains explicit original-expression storage/retrieval and capability-graded selection editing. D/E retain real compatibility, physical/VoiceOver, long-term/efficiency studies, signed distribution, migration/rollback and uninstall. No lab pass closes those gates.

## Minimal remaining product path

1. **This engineering node:** compile the actual IMK bundle/controller/adapter and verify its bounded client protocol with the real engine. An unsigned, fixture-only .app is reproducibly buildable. Normal IMKServer launch, framework-created controllers and user applications remain untested; this does not close installed Batch B.
2. **Basic-product integration:** this node wires modes, bounded punctuation and explicit settings/term governance into the input-method path. Known-character entry still needs bounded adjacent-grapheme evidence; complete required keyboard access, mixed-input behavior and resource staging/last-good recovery. Choose a production-redistributable dictionary with explicit provenance before bundling it. Cosmetic candidate polish is deferrable; wrong-target writes, lost input and unconfirmed effects are blockers. Installation and the live-host matrix need their separately authorized environment/process.
3. **Local Batch C loop:** [explicit exact-expression save/review/use-once](EXACT_EXPRESSIONS.md) is integrated and natively tested; capability-graded selected-text editing remains open. Existing term governance is the prerequisite. Do not replace exact original text with a synthesized recollection. AI, voice and PAIA remain separate external conditions, not hidden dependencies of local typing.
4. **D/E admission:** actual application compatibility, physical keyboard/VoiceOver, long-run and human-efficiency/quality evidence; license-cleared signed distribution, update/migration/rollback and uninstall. These gates cannot be closed by synthetic tests or a new UI slice.

The original REPORT/HANDOFF remain authoritative. This is a consolidated critical path, not new product scope or a claim that A2's language-quality/efficiency questions are answered.

## Consolidated basic controls

`IMKWorkspace` is shared by every production controller. The menu opens the same explicit settings and term governance components used by the native lab, with a process-wide action-time idle boundary. A failed mode preparation leaves the prior idle session/configuration intact; a callback during preparation invalidates the attempted transition. No management action commits, clears or replays host text. A closed controller is excluded from management ownership while retaining its transient recovery.

The default bundle has only the authored fixture. To exercise the existing unbundled research schemas, explicitly prepare A1/A2/G01/B1 resources and set `PAIA_IMK_RESEARCH=1` before startup. `PAIA_B2_RESEARCH=1` and an explicit `PAIA_B2_STORE` select the personal store; `PAIA_B3_SETTINGS=1` and an explicit `PAIA_B3_STORE` select settings. These are isolated development paths, not profile discovery or production installation. Missing/corrupt authority does not trigger an automatic overwrite or second engine initialization. Do not start the normal service merely to exercise this lane: CI uses protocol fixtures and the preflight branch only.

Literal mode releases only a verified idle target and returns the event to the host; it never simulates a second insert. A mode action prepares and refreshes the requested real schema before publication. The fixture factory refuses unavailable spelling/script/punctuation modes. Save/defaults/Verify last save use the existing closed settings format, explicit save and no-retry semantics. Personal add/edit/pin/delete/restore/import actions reacquire the global gate at action time, including delayed file-panel completion. Corrupt, changed or oversized authority disables the old overlay without host cleanup. Closed controllers retain recovery but do not prevent unrelated idle management forever.

See [consolidated native evidence](../evidence/imk-basics/VALIDATION.md) and the exact commit's [IMK workflow](https://github.com/haohongfei2001-png/paia-ime/actions/workflows/imk-integration.yml). The original 17 protocol tests, an actual fixture factory test and nine separate-process research stages are distinct from the 24 mode combinations within one controls stage. All use authored fixtures/stores; the management screenshot is native view rendering, not an installed-client screenshot.

The C node adds an optional isolated `PAIA_C_STORE` at startup and an explicit expression manager. It does not change default dictionary distribution or start the system service. See [production source-grant gates](PRODUCTION_DICTIONARY_GATE.md) before treating the research corpus as releasable vocabulary.
