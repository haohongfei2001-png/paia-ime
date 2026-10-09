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
