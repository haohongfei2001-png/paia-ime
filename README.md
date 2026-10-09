# PAIA IME

An independent **macOS Chinese input method** project. PAIA is an optional future integration, not a dependency for typing.

## Status

**Flagship research imported; native system IME not yet implemented.** The design/research package includes native AppKit test-probe code, a real librime engine experiment report, a browser prototype and bounded test evidence. An offline prototype and a synthetic AppKit host are **not** an installed macOS input source. Comparative user experience and accuracy versus WeChat/Sogou/Apple have not been established.

## Research / 研究资料

- [Full flagship design report / 完整旗舰研究报告](research/2026-10/REPORT.md)
- [Illustrated HTML report / 图文版报告](research/2026-10/REPORT.html)
- [Offline interactive prototype / 离线交互原型](research/2026-10/prototype.html) — download raw HTML and open locally
- [Codex engineering handoff / 工程交接](research/2026-10/CODEX_HANDOFF.md)
- [Verification and limitations / 验证边界](research/2026-10/VALIDATION.md)
- [Native AppKit probe](research/2026-10/native/README.md)
- [Licensing notice / 许可证边界](research/2026-10/licenses/NOTICE.md)
- [Import completeness record / 导入记录](research/2026-10/IMPORT_NOTES.md)

## Next engineering milestone: Batch A1

Read **REPORT → VALIDATION → CODEX_HANDOFF**. Build the native Swift/AppKit/InputMethodKit project structure and a real, version-locked librime C API bridge; prove key → composition → candidate → engine selection → single commit in an isolated AppKit host before asserting system-IME compatibility. Never replace the input engine with the webpage's fixed examples.

To rerun the existing standalone synthetic state-core tests:

```bash
node research/2026-10/engineering/test-core.cjs
```

No ordinary keystroke or commit may silently create a second PAIA archive event. Do not modify the separate PAIA repository without explicit authorization.

## Distribution

Public repository visibility is not a blanket open-source license. Review dependencies, dictionaries, fonts, model weights and platform requirements before copying or distributing production components.
