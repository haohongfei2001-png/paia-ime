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
- Idle unhandled events pass through. Command/Option/Control during composition first request a verified raw flush; unknown outcome consumes the event rather than continuing against an uncertain target. B8 unsupported middle punctuation/Unicode keeps the composition unchanged, with a same-target candidate warning when geometry is available and status in the input-method menu.
- Geometry comes from the client line rectangle. No mouse-position, global event tap or extra permissions are used. A same-activation recent rectangle is the only positioning fallback; missing geometry hides the panel. Identical proxy/document ABA and unobservable changes between protocol calls remain limitations, not atomicity guarantees.

## Evidence and remaining work

New Swift/Objective-C tests use actual NSTextView behind an IMKTextInput fixture and real librime. They exercise the same coordinator and adapter called by the framework controller. That is APPKIT_HOST / ENGINE_NATIVE with a synthetic protocol client, not proof of framework-created controller lifecycle, cross-process traffic, physical input or installed third-party hosts. Controller overrides and normal service entry are compiled; actual service startup is untested here. Every failed compile/test remains a failure; exact PR/main CI and independent review are required.

The original service/host milestone precedes complete B integration: existing modes/settings/explicit lexicon, production resource choice, mixed punctuation, discovery/keyboard accessibility and staged update/recovery still require product wiring and evidence. C remains explicit original-expression storage/retrieval and capability-graded selection editing. D/E retain real compatibility, physical/VoiceOver, long-term/efficiency studies, signed distribution, migration/rollback and uninstall. No lab pass closes those gates.

## Minimal remaining product path

1. **This engineering node:** compile the actual IMK bundle/controller/adapter and verify its bounded client protocol with the real engine. An unsigned, fixture-only .app is reproducibly buildable. Normal IMKServer launch, framework-created controllers and user applications remain untested; this does not close installed Batch B.
2. **One consolidated basic-product integration:** wire existing modes, punctuation, explicit settings/term governance and known-character entry into the actual input-method path; complete required keyboard access, mixed-input behavior and resource staging/last-good recovery. Choose a production-redistributable dictionary with explicit provenance before bundling it. Cosmetic candidate polish is deferrable; wrong-target writes, lost input and unconfirmed effects are blockers. Installation and the live-host matrix need their separately authorized environment/process.
3. **Local Batch C loop:** explicitly save exact original expressions, review the full result and use it once; then capability-graded selected-text editing. Existing term governance is the prerequisite. Do not replace exact original text with a synthesized recollection. AI, voice and PAIA remain separate external conditions, not hidden dependencies of local typing.
4. **D/E admission:** actual application compatibility, physical keyboard/VoiceOver, long-run and human-efficiency/quality evidence; license-cleared signed distribution, update/migration/rollback and uninstall. These gates cannot be closed by synthetic tests or a new UI slice.

The original REPORT/HANDOFF remain authoritative. This is a consolidated critical path, not new product scope or a claim that A2's language-quality/efficiency questions are answered.
