# Batch A1: native engine / synthetic host

This branch implements only A1 from `research/2026-10/CODEX_HANDOFF.md`. It is an isolated native lab, not an installed system input method. The InputMethodKit controller is a compilation-only lifecycle skeleton; no IMKServer is launched. No live-client, VoiceOver, physical mouse, system input source or end-to-end visible latency claim is made.

## Reproduce on macOS 13+ (CI uses standard macos-15)

```
python3 Tools/audit-a1.py
python3 Tools/prepare-a1.py
source .build/a1-env.sh
bash Tools/build-lab.sh
swift test --filter SessionCoreTests
swift test --skip-build --filter EngineTests
swift test --skip-build --filter AppKitHostTests
swift run -c release paia-benchmark > benchmark.json
```

Engine and host suites run in separate processes because librime has one process-wide runtime lifetime. Every test process uses a fresh temporary user directory. Fixture compilation happens at startup before any input session. The native lab can be run from its build bundle; do not copy it into Input Methods. Do not run an installer, register input sources, change preferences, disable security or read any user Profile.

## Boundaries

- SessionCore is pure Swift value state. Each displayed row binds session, target epoch, input generation, dictionary revision and page-local engine index. Every selection returns to `select_candidate_on_current_page`, never inserts displayed candidate text itself. The C API cannot report exact per-candidate raw spans; the value is explicitly unavailable. A2 constrained decoding is not claimed.
- One global C mutex serializes the entire runtime, session lifetime, key/selection and borrowed-buffer copy. All required API fields must fully fit data_size and be nonnull. The official full 1.16.0 header is vendored with its license. Every successful get_context/get_commit is freed after copying. Invalid data suspends the session; no guessed output or retry.
- Return preserves raw letters and consumes the key; Space/digits use visible engine mappings. Backspace/Delete/caret/page changes go through the engine. Idle navigation/Tab/Return and Command are passed to the host. No CGEvent, network, model, PAIA or clipboard path exists.
- A commit must be reserved once before the main-thread NSTextView insertText call. The reservation is non-replayable even if a future real client's outcome is uncertain. Stale target/generation effects are rejected. No whole-document identity is inferred from UUIDs.
- Unicode conversion distinguishes UTF-8, UTF-16 and graphemes; invalid scalar or grapheme boundaries are rejected. Marked text changes only the synthetic NSTextView's own marked/selected range.
- Temporary librime build/installation metadata is allowed; user dictionary and learning are disabled, no key/body logging or implicit archives. Build-time downloads are separate from the key path. Source scans are structural checks, not packet capture proof.
- No timeout pretends to terminate C++. In-process stalls remain a reliability risk for subsequent G02 stress testing. This short benchmark is not a tail-latency certification.

## Resources and measurement

`Resources/a1-lock.json` pins all fixture files/header/notices by SHA256 and the official macOS universal engine archive. The tiny artificial dictionary exists to test bridge semantics, paging, Unicode and reproducibility. It is not a modern competitive pinyin corpus and has no accuracy-comparison significance. `Resources/dependency-notices.json` records static dependency provenance; no optional engine plugins, models or third-party dictionaries are extracted.

The benchmark keeps all measured key latencies and failures, records inputs, source SHA, OS, engine, dictionary, sample count, warmup and clean learning state. It reports separate process_key time, commit/context copy-and-free time and total Swift session time. UI layout, host protocol, compositor and visible presentation are explicitly unmeasured.

## Evidence classification

- SIMULATED: pure SessionCore/Unicode and ABI table guards.
- ENGINE_NATIVE: real pinned librime conversions, engine selection, paging, lifetime and benchmark.
- APPKIT_HOST: actual AppKit NSTextView marked/insert protocol in a synthetic in-process host.
- INSTALLED_IME / LIVE_CLIENT / HUMAN_STUDY: not run, out of A1 scope.

See the exact-commit CI run and preserved logs for pass/fail results. Failed runs remain in Actions; never use a previous commit's green result for a later source. No signed release or installable product is delivered by this branch.
