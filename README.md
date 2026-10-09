# PAIA IME

An independent **macOS Chinese input method** project. PAIA is an optional future integration, not a dependency for typing.

## Status

**A1/A2 native engine research and B1 controls implemented; B2 explicit personal-lexicon and B3 explicit-settings labs implemented. System IME not installed.** The design/research package includes native AppKit test-probe code, a real librime engine experiment report, a browser prototype and bounded test evidence. An offline prototype and a synthetic AppKit host are **not** an installed macOS input source. Comparative user experience and accuracy versus WeChat/Sogou/Apple have not been established.

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

[B1 controls and focus contract](docs/BATCH_B1.md) adds an explicit research launch with Full/Flypy/Natural, Simplified/Traditional, literal text, a bounded punctuation mode and a real constrained-repair inspector. Preview is separate from marked-text acceptance and final engine commit. [B1 evidence](evidence/b1/VALIDATION.md) records native control tests, inspected synthetic-view capture and retained failures. This is one Batch B lab slice; subsequent B2/B3 sections cover explicit local persistence, while rare-character workflows and complete update/recovery remain open.

## Batch B2 explicit personal lexicon

[B2 manual terms, protected deletions and reviewed imports](docs/BATCH_B2.md) connects an isolated explicit store to real read-only engine dictionaries and a native management window. Ordinary typing does not learn. Changes disable the personal overlay until a verified next launch; Full/Simplified overlays deliberately gate unsupported mixed-dictionary repair. [B2 evidence](evidence/b2/VALIDATION.md) distinguishes each code checkpoint and retains failures.

## Batch B3 explicit settings and mode recovery

[B3 preference and recovery boundaries](docs/BATCH_B3.md) saves only four ordinary settings through a separate explicit Save control. New engine modes are prepared before replacing the current session; corrupt preferences and unconfirmed writes preserve usable input without silent overwrite or retry. [B3 evidence](evidence/b3/VALIDATION.md) records real native mode/restore stages, shared storage-identity hardening and the inspected synthetic view. Full signed update/install/recovery and physical-client validation remain open.

## Batch B4 visible native candidate navigation

[B4 selected-row and page presentation](docs/BATCH_B4.md) keeps the visible selection aligned with the real engine snapshot, adds honest current-page status, and preserves immutable candidate actions. [B4 validation](evidence/b4/VALIDATION.md) separates native navigation from synthetic presentation checks and tracks exact-head evidence.

## Batch A1 engineering contract

Read **REPORT → VALIDATION → CODEX_HANDOFF**. Build the native Swift/AppKit/InputMethodKit project structure and a real, version-locked librime C API bridge; prove key → composition → candidate → engine selection → single commit in an isolated AppKit host before asserting system-IME compatibility. Never replace the input engine with the webpage's fixed examples.

To rerun the existing standalone synthetic state-core tests:

```bash
node research/2026-10/engineering/test-core.cjs
```

No ordinary keystroke or commit may silently create a second PAIA archive event. Do not modify the separate PAIA repository without explicit authorization.

## Distribution

Public repository visibility is not a blanket open-source license. Review dependencies, dictionaries, fonts, model weights and platform requirements before copying or distributing production components.
