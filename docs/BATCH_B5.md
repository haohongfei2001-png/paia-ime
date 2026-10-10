# B5 explicit verification of an unconfirmed settings save

B3 deliberately stops saving after any unconfirmed write. B5 adds one native “Verify last save” action for that same still-open settings authority. It never restarts the application, opens a replacement path, retries Save, changes input mode or writes settings bytes. This is outcome verification, not corrupt-file restoration or general update/recovery.

## Known outcomes only

After validating the current authority and expected revision, SettingsStore retains the exact proposed envelope for that attempt. It records the attempt before creating/writing staging so an early failure is also identifiable. Rejected stale revisions or invalid authorities create no attempt. A successful Save clears the attempt; a failed attempt blocks another Save until explicitly verified.

Verification holds the original root descriptor and writer lock. It revalidates the selected root and linked lock identity, reads only bounded ordinary single-link files without following symlinks, checks linked file identity and unchanged file metadata after reading/flushing, applies file/directory durability barriers, and revalidates root/lock identity. Even a previously empty authority requires an explicit directory barrier. This remains a between-operation integrity check, not an adversarial filesystem compare-and-swap guarantee.

Only two outcomes can resolve the attempt:
- Exact previous envelope and expected marker, or the known previous absence of both files: the previous state remains; the attempted change was not saved.
- Exact proposed envelope and valid marker: that attempted revision is verified published.

Any other valid generation, corrupt data, missing established file, orphan marker, unsafe file, replaced root/lock or unsuccessful durability barrier remains blocked and unchanged. Verification does not invent a rollback, clean up corruption, replace the selected root or silently adopt arbitrary valid settings. The fault-injection facility is one-shot for tests only; production launches do not set it.

## Native action boundaries

The action is available only after a failed Save with a known pending attempt. Startup-unavailable settings provide no verification route. Engine composition, foreign AppKit marked text, repair and closed windows refuse the action, including direct invocation despite a disabled control. A verified outcome updates only the saved revision and Save availability; the current mode, dispatcher and composition generation are preserved. Repeated callbacks after resolution are inert. A later Save is a new explicit operation.

Existing B1/B2/B3 launch configuration is unchanged. No input, candidate, repair content, path, client identity or permission is persisted. No new resource, dependency, network path or paid service is introduced.

## Verification and limits

[Evidence](../evidence/b5/VALIDATION.md) separates eight store/fault tests from six real-engine/AppKit control tests. Store tests cover previous-empty/previous-saved/published outcomes, orphan/corrupt/missing/unexpected authority, unsafe paths and one-writer continuity. Native tests use the existing strong-corpus engine, prove input still works before/after verification, and preserve single-commit and target identity. Captures contain authored synthetic text only.

Faults are injected; these are not power-loss experiments. The same process keeps the original lock throughout verification. Full app launch, physical keyboard/pointer, VoiceOver, installed/live clients, real disk-failure durability, encryption, secure deletion, signed updates, migration and corrupt-file restoration remain unverified or out of this slice. Existing corpus redistribution and general language-quality limits remain open.
