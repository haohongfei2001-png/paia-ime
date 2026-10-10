# PAIA IME

An independent **macOS Chinese input method** project. PAIA is an optional future integration, not a dependency for typing.

## Status

**Native research slices A1/A2 and B1–B8 implemented; uninstalled IMK engineering, basic-mode/explicit-management integration, the local exact-expression loop, retained-composition G01 repair and qualified bounded-context review added. System IME not installed.** The design/research package includes native AppKit test-probe code, a real librime engine experiment report, a browser prototype and bounded test evidence. An offline prototype and a synthetic AppKit host are **not** an installed macOS input source. Comparative user experience and accuracy versus WeChat/Sogou/Apple have not been established.

## Research / 研究资料

- [Full flagship design report / 完整旗舰研究报告](research/2026-10/REPORT.md)
- [Illustrated HTML report / 图文版报告](research/2026-10/REPORT.html)
- [Offline interactive prototype / 离线交互原型](research/2026-10/prototype.html) — download raw HTML and open locally
- [Codex engineering handoff / 工程交接](research/2026-10/CODEX_HANDOFF.md)
- [Verification and limitations / 验证边界](research/2026-10/VALIDATION.md)
- [Native AppKit probe](research/2026-10/native/README.md)
- [Licensing notice / 许可证边界](research/2026-10/licenses/NOTICE.md)
- [Import completeness record / 导入记录](research/2026-10/IMPORT_NOTES.md)

## Native Batch A1 lab

See [A1 build, tests, resource pins and evidence boundaries](docs/BATCH_A1.md). The Swift package contains a pure session core, Unicode boundary checks, real serialized librime C ABI, synthetic NSTextView host, native candidate panel and reproducible benchmark. It does not register an input source. [Native CI](https://github.com/haohongfei2001-png/paia-ime/actions/workflows/batch-a1.yml) separates state, engine and AppKit results; read the run for the exact commit.

## Native Batch A2 constrained-editing research

[Constrained editing contract and reproducible full-corpus benchmark](docs/BATCH_A2.md) documents the actual version-pinned C++ capability extension, transactional whole-session replay, target/candidate identity guards and native AppKit proof. [A2 evidence](evidence/a2/VALIDATION.md) retains failures and exact source references. It is a bounded engine experiment, not a product-quality or installed-IME claim.

## Batch B1 native research controls

[B1 controls and focus contract](docs/BATCH_B1.md) adds an explicit research launch with Full/Flypy/Natural, Simplified/Traditional, literal text, a bounded punctuation mode and a real constrained-repair inspector. Preview is separate from marked-text acceptance and final engine commit. [B1 evidence](evidence/b1/VALIDATION.md) records native control tests, inspected synthetic-view capture and retained failures. This is one Batch B lab slice; subsequent B2/B3 sections cover explicit local persistence, while B7 provides bounded known-U+ entry and broader rare-character discovery and complete update/recovery remain open.

## Batch B2 explicit personal lexicon

[B2 manual terms, protected deletions and reviewed imports](docs/BATCH_B2.md) connects an isolated explicit store to real read-only engine dictionaries and a native management window. Ordinary typing does not learn. Changes disable the personal overlay until a verified next launch; Full/Simplified overlays deliberately gate unsupported mixed-dictionary repair. [B2 evidence](evidence/b2/VALIDATION.md) distinguishes each code checkpoint and retains failures.

## Batch B3 explicit settings and mode recovery

[B3 preference and recovery boundaries](docs/BATCH_B3.md) saves only four ordinary settings through a separate explicit Save control. New engine modes are prepared before replacing the current session; corrupt preferences and unconfirmed writes preserve usable input without silent overwrite or retry. [B3 evidence](evidence/b3/VALIDATION.md) records real native mode/restore stages, shared storage-identity hardening and the inspected synthetic view. Full signed update/install/recovery and physical-client validation remain open.

## Batch B4 visible native candidate navigation

[B4 selected-row and page presentation](docs/BATCH_B4.md) keeps the visible selection aligned with the real engine snapshot, adds honest current-page status, and preserves immutable candidate actions. [B4 validation](evidence/b4/VALIDATION.md) separates native navigation from synthetic presentation checks and tracks exact-head evidence.

## Batch B5 explicit settings-save verification

[B5 known-outcome verification](docs/BATCH_B5.md) checks an unconfirmed Save under the same writer lock, accepting only the known prior or attempted envelope. The explicit native action preserves current input mode and never retries the write. [B5 validation](evidence/b5/VALIDATION.md) distinguishes injected filesystem failures from real engine/AppKit behavior.

## Batch B6 fully readable long candidates

[B6 bounded native wrapping and scrolling](docs/BATCH_B6.md) keeps complete candidate glyphs reachable inside the supplied safe screen while preserving engine selection and editor focus. [B6 validation](evidence/b6/VALIDATION.md) retains the real failing regression and distinguishes authored-engine, synthetic-geometry and native-render evidence.

## Batch B7 explicit known-character entry

[B7 caret-only Unicode preview and insertion](docs/BATCH_B7.md) shows an explicit U+ identity/name and font warning before a separate once-only Insert action. It shares the existing inspector, mode/settings barriers and host effect path. [B7 validation](evidence/b7/VALIDATION.md) retains the canonical-equivalent target-edit regression, cancellation review finding and native selection-normalization failure. Phonetic/radical discovery and font repertoire remain open.

## Batch B8 composition-safe keyboard boundary

[B8 pre-mutation refusal and text/control separation](docs/BATCH_B8.md) protects remaining raw spelling and marked text from unsupported middle-caret punctuation and Unicode events. Visible recovery stays explicit; no automatic commit, retry or caret move is added. [B8 validation](evidence/b8/VALIDATION.md) retains the original native data-loss observations and checks synchronous host callback ownership. The subsequent explicit typed mixed-input path below now covers bounded compound insertion; ordinary unqualified forwarding keeps these conservative guards.

## InputMethodKit engineering integration

[The separate input-method bundle and bounded client adapter](docs/IMK_INTEGRATION.md) add a real IMKInputController, shared event/lifecycle driver and IMKTextInput bridge. Native CI builds the unsigned app, verifies its bundled real engine without starting IMKServer, and exercises an NSTextView-backed protocol client. [Integration evidence](evidence/imk/VALIDATION.md) preserves the first failing expectation, actual engine comparison and ownership regressions. The shared IMK workspace now connects the existing basic modes, explicit settings save/verification and personal term governance under a process-wide idle gate; [basic-controls evidence](evidence/imk-basics/VALIDATION.md) records the actual native stages and retained failures. The default bundle still contains only the tiny authored fixture, while explicitly selected research resources remain unbundled. Contextual known-character interaction is implemented below for explicitly qualified synthetic clients; production resources, staged update/recovery and installed compatibility remain open. The supported fully-confirmed G01 interaction is integrated below.

## Explicit exact-expression loop

[Complete manual save, local lookup, full source review and once-only insertion](docs/EXACT_EXPRESSIONS.md) now share the actual IMK driver. Ordinary input never creates saved expressions; unknown storage/insertion outcomes do not retry. [C evidence](evidence/c-expressions/VALIDATION.md) retains the former unsafe idle-verifier red test, initial UI-test crash and exact native reruns. The optional store is explicitly chosen at startup. This remains authored-protocol/ENGINE_NATIVE/APPKIT_HOST evidence, with no installed service or AI/PAIA dependency. Qualified selected-text capture is a separate capability slice below. [Production vocabulary provenance](docs/PRODUCTION_DICTIONARY_GATE.md) is a separate release gate, not solved by source hashes or by installing the current fixture app.

## Retained-composition segment repair

[Explicit one-shot retention, real target alternatives and native full review](docs/IMK_RETAINED_REPAIR.md) integrate the existing G01 engine into the same IMK event/effect path. Option+Left/Right navigates authentic fully-confirmed anchors; Apply changes only owned marked text, and Chinese commit remains separate. No shared mode, fake candidate text, personal-overlay fallback or implicit retry is added. [Native checkpoint evidence](evidence/imk-repair/VALIDATION.md) distinguishes bounded/incomplete search, real engine/host tests and native view renders from installed/live-client and performance/quality claims.

## Explicit bounded context and reviewed editing

[Contextual known-character entry and manual selection review](docs/IMK_BOUNDED_CONTEXT.md) use bounded actualRange/raw-UTF-16 evidence, conservative grapheme checks, a non-key in-memory draft and the same once-only IMK effect dispatcher. C2 read and C3 replace permission are separate. Production bridges stay disabled for this advanced feature until their capabilities are genuinely qualified; current evidence uses authored revision-aware clients. [Native checkpoints and retained failures](evidence/imk-context/VALIDATION.md) distinguish the original ZWJ failure, corrected real AppKit/engine tests and full-review images. This literal draft is not a second Pinyin engine, AI rewrite or installed/live-app certification.

## Batch A1 engineering contract

Read **REPORT → VALIDATION → CODEX_HANDOFF**. Build the native Swift/AppKit/InputMethodKit project structure and a real, version-locked librime C API bridge; prove key → composition → candidate → engine selection → single commit in an isolated AppKit host before asserting system-IME compatibility. Never replace the input engine with the webpage's fixed examples.

To rerun the existing standalone synthetic state-core tests:

```bash
node research/2026-10/engineering/test-core.cjs
```

No ordinary keystroke or commit may silently create a second PAIA archive event. Do not modify the separate PAIA repository without explicit authorization.

## Distribution

Public repository visibility is not a blanket open-source license. Review dependencies, dictionaries, fonts, model weights and platform requirements before copying or distributing production components.

## Recoverable fixture-resource startup (commit-bound native evidence)

The next original resource-update node adds offline two-schema fixture compilation, complete artifact verification, isolated native probes, versioned current/last-good publication and precompiled startup selection. Existing sessions keep their resource snapshot until the next launch. The default uninstalled bundle uses only the authored fixture; no production corpus, personal rollback, hot reload or signed updater claim. See [resource startup contract and evidence boundary](docs/RESOURCE_STARTUP.md). The 2699995 native checkpoint passed its real compiler/probe/startup recovery suite; final-source and exact-main acceptance are separate, recorded at PR16.

## Lossless explicit mixed-input composition

[Typed Chinese/literal composition](docs/MIXED_INPUT.md) preserves the complete
original source while confirming real Chinese candidates around English, paths,
identifiers, punctuation and Unicode. It uses one input owner and one host effect,
with actual native proof replay, explicit literal intent, grapheme-safe edits,
stale-action refusal and whole-source Return. [Commit-bound mixed evidence](evidence/mixed/VALIDATION.md)
records the actual C ABI/Swift/NSTextView path, 12 research schemas, bounded search,
128-span suffix cases and all initial failures. Default fixture bundles without
the research extension do not expose the capability. This does not qualify
installed apps, complete language quality, independent typo/fuzzy policies,
rare-character discovery or production corpus redistribution.
