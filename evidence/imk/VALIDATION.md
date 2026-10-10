# Uninstalled IMK integration evidence

Baseline B8 main: `61d262cf2aeaf3839c32a5aac59a74ae685688fd`. The original pinned A1 librime binary, authored fixture, licenses and ordinary-input non-learning policy are unchanged. No new external resource or package is added.

## First native checkpoint, retained failure

Exact source `5686e1c41edb94910d40aa5342c39d83a711d72d`, IMK run `38042676360` / job `114185884415`, built the unsigned input-method bundle and passed its real-engine `--preflight`. The preflight explicitly did not construct IMKServer.

Fifteen protocol methods ran: fourteen passed and one failed. `testIdlePassThroughAndActivationIsolation` expected one insertion after `shi` + Space in the tiny A1 fixture but observed zero. This failure is retained, not changed into a blanket zero-insertion assertion. Nine older workflows succeeded. B3 run `38042676341` was cancelled by the later branch update during its native fresh-process stage; its earlier successful substeps do not make that workflow a pass. Complete logs and all terminal identities are retained in the recovery.

The first Objective-C fixture compile also emitted five protocol warnings: `windowLevel` had an NSInteger/CGWindowLevel mismatch, and four required IMKTextInput methods were missing. Exact SDK declarations were taken from the compiler output, the fixture was completed, and protocol/return-type warnings are now errors. The initial `find` command did not emit framework headers through the SDK symlink; the later workflow explicitly reads the InputMethodKit headers and Carbon IMKInputSession.h.

## Reviewed product and direct-engine diagnosis

Exact source `b513405ba7b164828872d13f145ea54ad7319c76`, tree `38c758955b0a9b13d900bda8aca53f47cc3662e4`, IMK run `38043161707` / job `114187290021`, passed bundle compilation, unregistered preflight and all **17 native protocol methods**, with zero failures or skips. The runner reports macOS 15.7.9 (24G830), arm64 and Apple Swift 6.1.2. All eleven workflows passed this exact product source, including the complete B3 fresh-process stage. [Reviewed checks](reviewed-checks.json) record their distinct run/job/artifact identities.

The original `shi` input is preserved in a separate differential test against an independent real InputSession. Actual output is `handled=true, commit=false, raw=shi, preedit=shi`; the adapter agrees, makes no insertion, and retains the native marked range and selection. Fixed assertions require raw `shi` and a matching nonempty mark when there is no commit, so two paths simultaneously losing input would fail. The full-spelling isolation scenario uses `shijie`, asserts that stale candidate/foreign-client callbacks change neither snapshot nor native mark, and then commits `世界` exactly once. The dictionary and engine behavior were not modified to make the test pass. The schema enables completion, so lack of a standalone dictionary row alone was not used as proof of the original result.

## Ownership regressions and independent review

The production coordinator checks exact finite ranges, owned text bytes, session identity and activation after protocol getters/writes. The shared event driver adds event-generation and in-flight activation leases. Review identified and corrected stale idle caret ownership, loss of newly accepted raw spelling in recovery, nested modifier passthrough, presentation takeover, stale geometry fallback, same-client rebind revival and lifecycle callbacks arriving during activation getters.

In the last case, current client identity was not yet published, so finish/deactivate had been ignored. The fix binds pending client/coordinator/ticket before getters; matching lifecycle invalidates only that activation, with no host write. The regression covers both selected/marked getters and both lifecycle callbacks, zero session factory/write, superseded activation and foreign-client isolation. Review findings are source-derived counterexamples; they are not mislabeled as separate native red executions. Final source/log review is retained with the recovery.

Other native methods cover real raw → marked → candidate → single commit, stale candidates, raw lifecycle flush, foreign marks/nonempty selections, Unicode UTF-8/UTF-16, unsupported middle input, all bounded getter/write callbacks, unknown insertion outcomes, truncated reads, changed selection, idle host edits, presentation reentry and geometry failure. Every string is authored synthetic test data. The Objective-C fixture is backed by actual NSTextView and implements IMKTextInput; the controller forwards to the same tested driver. No framework-created controller or service connection is constructed by these tests.

## Final-tree acceptance and limits

The final evidence checkpoint changes documentation and logs the bundle hash manifest; Swift/Objective-C product and test source remain the reviewed b513405 tree. Exact final PR and merged-main CI must each reach their own terminal state before acceptance. The private recovery records every run/job/artifact, full failure/cancellation/pass logs, resource/license locks, benchmark/comparator arrays, native diagnostics and an independently reconstructed baseline-to-main patch. Intermediate green checks do not substitute for the final tree.

ENGINE_NATIVE and APPKIT_HOST with a synthetic IMK protocol client are distinct from INSTALLED_IME, LIVE_CLIENT and HUMAN_STUDY. Normal IMKServer launch is compiled but untested. The bundle has only the tiny A1 fixture; production dictionary redistribution clearance, full basic-product wiring, installed/live applications, physical keyboard/pointer, VoiceOver, full accessibility, language quality, visible latency/endurance, signing/notarization, updates and uninstall remain open. No installation, preferences/security change, private profile, network hot path, clipboard read, implicit learning or input log was added. Bounded post-call readback is not atomic and cannot undo an already issued insertion; unknown effects are never retried.
