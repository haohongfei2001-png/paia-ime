# Batch B8: lossless keyboard boundary

Initial test-only checkpoint against B7 main. Native probes investigate middle-caret punctuation and non-ASCII/multi-scalar NSEvent handoff while the engine owns marked text. Tests use real pinned librime and separate real AppKit processes. Both probe groups run and preserve their real exit codes even if one fails.

The minimum safety contract is pre-mutation, visible refusal of unsupported actions while retaining the complete raw input, caret, candidates and native marked document. No silent suffix loss, automatic move-to-end, fabricated engine candidate or premature effect reservation is acceptable. A future compound insertion contract would need explicit engine/literal provenance, confirmed-segment preservation, commit-drain ownership, and safe partial-host-write handling. It is not claimed by these probes.

No new resources, dictionaries, fonts, service, input-source installation or persistent user data. Probe traces contain authored synthetic text only. Native outcomes will determine the implementation and retained limitations; source review alone is not proof of a failing runtime path.
