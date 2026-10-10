# Consolidated IMK basic-controls validation

Status: implementation and native integration evidence. The exact current PR/main checks remain authoritative; historical checkpoints below are not substituted for later code. Baseline f5b7bcfc71576d036dfbcc61a110f2fb9e426edd.

This node integrates the existing basic modes, explicit SettingsStore Save/defaults/Verify workflow, and explicit LexiconStore manager into the separate InputMethodKit app. It does not add a second engine or a second host-write path. All controls share a process-wide idle gate; modes prepare a real empty session before publication, and every old idle binding retires before AppKit presentation callbacks.

Default bundle remains the authored A1 fixture. Unsupported schemas are refused, not mapped to fixture candidates. The existing pinned research corpus and G01 extension are used only when explicitly selected before startup; they remain unbundled. No ordinary key accesses either persistent store. Literal mode returns false only after verified idle ownership release; host-side text insertion in synthetic tests is labelled explicitly.

ENGINE_NATIVE / APPKIT_HOST evidence at the named checkpoints: 24 combinations of Full/Flypy/Natural, Simplified/Traditional, literal/Chinese, and ASCII/bounded Chinese punctuation; cross-controller composition blocking; engine preparation failures; callback reentry; explicit overlay retirement and import preview/apply; fresh-process settings restore; previous/published/unresolved save verification; opened and oversized personal-authority quarantine. The same original 17 IMK protocol tests and all prior workflows remain required.

No normal IMKServer startup, framework-created controller, installed source, live cross-process client, physical-input, VoiceOver, language-quality or visible-latency acceptance is claimed. Known-character insertion and G01 inspector integration still need their own bounded IMK capability contracts. Resource installation/update/rollback and installed compatibility remain separate gates. Failed/skipped/cancelled runs will be retained, not converted to success by a later run.

## First native checkpoint ae2f23d

The actual release bundle and authored no-server preflight compiled/ran successfully. Test compilation then failed because two XCTest throwing-autoclosure assertions inferred throwing callback bodies when assigned to nonthrowing hooks. No new basic-control native tests executed at this checkpoint. Explicit do/catch assertions replace those callback bodies; the fix does not suppress failures. A source review also separated the synthetic authority-failure settings directories so prior saved Flypy settings cannot contaminate those baseline-input assertions. Exact run logs and cancellations are preserved in the private recovery evidence.

## Second native checkpoint baa1241

The original 17 IMK protocol tests and actual A1 service-environment fixture test passed. The real research `controls` test passed all 24 mode combinations and its management/race/store assertions. The broad Swift test filter also selected the fixture class in the same module; its attempted second RimeRuntime initialization correctly failed with code 7. Remaining fresh-process stages therefore did not run. The workflow now uses the exact research test identifier, retaining the separate fresh-process fixture invocation. No engine lifetime guard was weakened. The first settings capture's stdout Base64 was interleaved by XCTest output and is not a verified image; capture records now use the same stderr write form as established native tests.

## Third native checkpoint 328ec4a

All 11 workflows passed on this checkpoint (see reviewed-checks.json). The IMK workflow passed: release bundle/preflight, original 17 protocol tests, one actual fixture-environment test, and all nine fresh-process research stages, each executing one test with zero failures. The 24 mode combinations are a submatrix of the controls stage, not 24 independent test methods. The settings PNG was structurally valid and opened, but its root background was transparent so it cannot serve as an opaque readable UI capture. Preferences now paint the native window background and bound text widths; the next exact-source capture must be inspected. The final refinement also labels the resource status as a startup snapshot, tests all four punctuation commits plus period/colon passthrough, and requires actual stage markers plus executed-test counts in CI. Those refinements are not covered by the earlier green run.

## Acceptance boundary

Final-source acceptance requires all 11 applicable macOS workflows, each real research stage's executed-test marker, independent review of the source delta/native results, and inspection of the final opaque settings capture. Merge is followed by the same exact-main CI and a private, verified source/patch/evidence recovery. No new third-party resource or license is added; existing pins and notices remain authoritative.
