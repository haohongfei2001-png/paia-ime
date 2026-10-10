# B3 explicit settings and safe mode recovery

This lab slice saves four closed ordinary preferences: Full/Flypy/Natural spelling, Simplified/Traditional output, literal mode and the existing bounded Chinese punctuation mode. Input text, candidates, marked ranges, repair parameters/hold state, client identity, resource paths, schema names and personal-overlay permissions are never settings fields. The app remains uninstalled; this is not the full Batch B product or a signed update/recovery system.

## Explicit launch

After A1/A2 resources, G01 and B1 preparation:

```sh
source .build/b1-env.sh
export PAIA_B3_SETTINGS=1
export PAIA_B3_STORE="$PWD/.build/my-explicit-settings"
swift run PAIANativeLab
```

B3 requires an explicit B1 or B2 research launch. For B2, use its separate explicitly selected personal-lexicon directory as documented in BATCH_B2.md. Do not reuse one directory for both authorities. Without the B3 flag, preference behavior remains session-only. No profile discovery, system preference change, standard preferences database, background synchronization or implicit save is added.

The mode controls apply only to the current session. “Save current settings” is a separate explicit operation. “Restore session defaults” changes only the current session, not the saved file. Closing a window does not save. Both actions refuse active composition/repair and closed-window callbacks, including actions invoked despite a disabled control.

## Prepare before publishing a mode

A new mode is resolved through the current environment's closed configuration, then a real engine session is created and refreshed. Its initial raw/preedit must be empty and no commit may be pending. Only after successful engine validation and owned-focus restoration is the configuration/dispatcher published and the old session ended. Factory errors, dirty/ended returned sessions and focus failure never publish the new configuration. A still-valid old session remains usable. If focus had already invalidated it, subsequent input creates a new session under the retained old configuration; old identities are not revived. Successful changes invalidate prior candidate/repair actions.

Existing marked text owned by the AppKit text system also makes mode/Save/defaults actions busy, even when the engine is empty (for example in literal mode). A dispatcher never adopts a mark already present at construction. Session renewal refuses a remaining unowned mark and leaves subsequent keys to AppKit; only the original owner resolves it. Engine Commit/Cancel/Repair controls do not become available for that foreign mark. The regression uses actual NSTextView marked-text APIs with synthetic text; it does not establish interoperability with a live third-party input method.

## Persistence and recovery boundaries

A dedicated SettingsCore stores a closed canonical JSON envelope, limited to 4 KiB, nesting eight and a bounded monotonic revision. A SHA-256 digest detects corruption, not an author's authenticity. Unknown keys/version/enums/types, duplicate/noncanonical encodings and bad integrity fail closed. No arbitrary strings can become engine paths or permissions.

Only explicit Save writes preferences. A fresh selected directory may receive a writer lock at startup, but no settings record is created until Save. Established authorities require their initialized marker. A missing established record is corruption, not a new empty store. Unavailable/corrupt settings leave the existing file untouched and use already-verified session defaults. If the saved mode cannot create a usable session, defaults stay active and the saved record remains unchanged. Default engine startup failure is still a startup failure, not a successful fallback claim.

The single writer refuses special files and changed generation/lock/root identities. Private staging is flushed before atomic publication, followed by a directory barrier. Failures during initialization/publication quarantine the handle; further writes require explicit verification, with no automatic retry. B5 adds same-handle verification for a known failed attempt; restarting still verifies the selected authority at startup. A failed Save does not destroy the current input session. Save stays disabled after an unknown result, even as later typing refreshes control states. Reopening a corrupt file does not silently repair or overwrite it; a separate healthy selected directory is needed unless the bounded B5 known-outcome verification applies; corrupt-file restoration remains unimplemented.

Shared hardening also revalidates the B2 lexicon's selected root and the owned scratch-generation identity before cleanup. This prevents the tested between-operation move/recreate-path cases. It is not a race-proof compare-and-swap against an adversary renaming paths between filesystem calls. Legitimate macOS ancestor symlinks are not indiscriminately prohibited.

## Verification and limits

[Validation evidence](../evidence/b3/VALIDATION.md) separates pure codec/store failure injection, real native engine selection, and AppKit control behavior. The native suite runs each saved-state stage in a fresh process, respecting librime's one-runtime-per-process lifetime. It covers all 24 combinations, factory/prepared-session failures, active composition/repair guards, Save/defaults distinction, no typing-triggered persistence, corrupt/missing settings and existing B2 active/disabled/unavailable overlay rules. Fixed injected failures are simulations within an actual native host, not real disk power-loss experiments.

The captured view contains authored synthetic data only. In-process controls, text and labels are tested; physical keyboard/pointer, VoiceOver, display/appearance matrices, installed IMK clients and visible latency remain unverified. NativeIME opt-in wiring is compiled; tests construct the same controller/environment components directly, not the app's full launch event loop. Persistence is local plaintext, not encryption or secure deletion. No migration, last-good-backup restoration, signed software update, install/uninstall or automatic repair is claimed.

B2's Full/Simplified-only personal overlay and unsupported mixed-dictionary G01 remain unchanged. Resource pins/notices, unbundled core-only research corpus and unresolved production redistribution clearance remain those of A1/A2/B1/B2. This slice adds no downloaded dependency or paid service.
