# PAIA IME

An independent **macOS Chinese input method** project. PAIA is an optional future integration, not a dependency for typing.

## Status

**Batch A1 native engine / synthetic AppKit lab implemented; system IME not installed.** The design/research package includes native AppKit test-probe code, a real librime engine experiment report, a browser prototype and bounded test evidence. An offline prototype and a synthetic AppKit host are **not** an installed macOS input source. Comparative user experience and accuracy versus WeChat/Sogou/Apple have not been established.

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

## Batch A1 engineering contract

Read **REPORT → VALIDATION → CODEX_HANDOFF**. Build the native Swift/AppKit/InputMethodKit project structure and a real, version-locked librime C API bridge; prove key → composition → candidate → engine selection → single commit in an isolated AppKit host before asserting system-IME compatibility. Never replace the input engine with the webpage's fixed examples.

To rerun the existing standalone synthetic state-core tests:

```bash
node research/2026-10/engineering/test-core.cjs
```

No ordinary keystroke or commit may silently create a second PAIA archive event. Do not modify the separate PAIA repository without explicit authorization.

## Distribution

Public repository visibility is not a blanket open-source license. Review dependencies, dictionaries, fonts, model weights and platform requirements before copying or distributing production components.
