# Local validation, 2026-10-09

Environment: Debian GNU/Linux 13 x86_64; gcc available; Swift/AppKit unavailable.

- Strict C compilation: passed with -std=gnu11 -Wall -Wextra -Werror.
- SIMULATED ABI guards: 8 passed with AddressSanitizer + UndefinedBehaviorSanitizer and ASAN_OPTIONS=detect_leaks=0.
- Initial combined sanitizer invocation failed: LeakSanitizer cannot run under this executor's ptrace. Leak detection was explicitly disabled for the rerun; no leak-free claim is made. Original diagnostic: `LeakSanitizer has encountered a fatal error; LeakSanitizer does not work under ptrace`.
- Resource SHA256 and narrow static privacy/source audit: passed.
- Python tool syntax: passed.
- Local ENGINE_NATIVE / APPKIT_HOST: NOT RUN; macOS required. See exact-commit CI results; never infer native success from these checks.

All native test inputs are repository-authored artificial fixtures. No private profiles, system installation, input preferences, network hot path, PAIA connection or models were used.

## First macOS CI attempt

[Run 37977881640](https://github.com/haohongfei2001-png/paia-ime/actions/runs/37977881640), head ed71f2b: official archive/header checks and native C sanitizer guards passed. Swift app build failed on main-actor initialization and unavailable NSBeep symbol. Engine/host/benchmark skipped. Fixed by explicit MainActor entry and NSSound.beep; later exact-head CI must validate the correction.

## Second macOS CI attempt

[Run 37978051438](https://github.com/haohongfei2001-png/paia-ime/actions/runs/37978051438), head 500529e: native app build, C sanitizers and all 4 pure state/Unicode tests passed. Eight of nine real-engine test methods passed, including actual candidate selection, paging, one-shot commits and Unicode. The caret/edit test had three related failed assertions: upstream ordinary Left moved by syllable (4→2), while A1 requires raw-character movement (4→3). The adapter now uses the engine's documented keypad LeftByChar/RightByChar bindings; assertions were retained. Host/benchmark steps were skipped on that failed run.

## Third macOS CI attempt

[Run 37978365691](https://github.com/haohongfei2001-png/paia-ime/actions/runs/37978365691), head e555183: native build, sanitizers, all 4 pure tests and all 9 real-engine tests passed. Five AppKit tests passed; the new window-resignation/queued-button lifecycle test terminated with signal 11, so APPKIT_HOST did not pass and benchmark was skipped. Follow-up makes window ownership explicit (`isReleasedWhenClosed=false`) and invalidates state before any potentially reentrant host mutation. The full test remains enabled; only a successful rerun can establish the fix.

## Fourth macOS CI attempt

[Run 37978701669](https://github.com/haohongfei2001-png/paia-ime/actions/runs/37978701669), head 060d86f: native build, sanitizer guards, 4/4 pure tests, 9/9 engine tests, and 6/6 AppKit host tests all passed. The benchmark terminated while serializing an Any-typed dictionary containing an Optional/SwiftValue; no timing result from that failed run is reported. The report is now a fully typed Codable structure, preserving all samples and explicit failure information; all native checks remain enabled.
