# Consolidated IMK basic-controls validation

Status: authored implementation; native CI pending. Baseline f5b7bcfc71576d036dfbcc61a110f2fb9e426edd.

This node integrates the existing basic modes, explicit SettingsStore Save/defaults/Verify workflow, and explicit LexiconStore manager into the separate InputMethodKit app. It does not add a second engine or a second host-write path. All controls share a process-wide idle gate; modes prepare a real empty session before publication, and every old idle binding retires before AppKit presentation callbacks.

Default bundle remains the authored A1 fixture. Unsupported schemas are refused, not mapped to fixture candidates. The existing pinned research corpus and G01 extension are used only when explicitly selected before startup; they remain unbundled. No ordinary key accesses either persistent store. Literal mode returns false only after verified idle ownership release; host-side text insertion in synthetic tests is labelled explicitly.

Planned ENGINE_NATIVE / APPKIT_HOST evidence: 24 combinations of Full/Flypy/Natural, Simplified/Traditional, literal/Chinese, and ASCII/bounded Chinese punctuation; cross-controller composition blocking; engine preparation failures; callback reentry; explicit overlay retirement and import preview/apply; fresh-process settings restore; previous/published/unresolved save verification. The same original 17 IMK protocol tests and all prior workflows remain required.

No normal IMKServer startup, framework-created controller, installed source, live cross-process client, physical-input, VoiceOver, language-quality or visible-latency acceptance is claimed. Known-character insertion and G01 inspector integration still need their own bounded IMK capability contracts. Resource installation/update/rollback and installed compatibility remain separate gates. Failed/skipped/cancelled runs will be retained, not converted to success by a later run.
