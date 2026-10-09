# B3 validation record

Baseline main b45f8bae15d847209c5855253db9250515fe4164. PR #5 opened Draft.

## Initial code checkpoint

068e3821ad9df292a952751619906b787314e9e0: all five macOS workflows succeeded. B3 run 37998967038/job 114052068121/artifact 11647848418 passed six settings-store methods and nine fresh-process native stages (controls, save, restore, restore_failed, save_unknown, overlay_disabled, settings_corrupt, settings_missing, personal_corrupt), with zero failures/skips. The controls stage exercises all 24 spelling/script/literal/punctuation combinations against the native engine or NSTextView. Separate mode-application and Save, current-config retention on failed creation, composition/repair save guards and unknown-save suspension passed.

A1/A2/B1/B2 regression runs 37998967002/37998967030/37998967009/37998966990 succeeded. A1 retains its unrelated explicit B2 configuration skip; no B3 native success is inferred from that filter.

The initial settings root-view PNG was inspected. Save/defaults buttons and persistence status were visible; the editor was blank in that capture. A subsequent capture assertion/order change verifies and displays committed synthetic text before accepting improved visual evidence. It does not retroactively change this checkpoint.

## Review-led additions awaiting new-head evidence

Selected-root replacement guards for settings and B2 lexicon authority; identity-bound B2 scratch cleanup; first-save and marker/integrity/duplicate-key/revision fault cases; a returned dirty real session rejected and ended without harming the old dispatcher; closed-window settings action invalidation. These require their own macOS run. Review findings and any failures/skips remain in the private recovery logs rather than being hidden by earlier green checks.

SIMULATED covers codec/filesystem fault injection and failed-session setup. ENGINE_NATIVE/APPKIT_HOST cover real sessions, candidate/commit output and actual AppKit objects. No INSTALLED_IME, LIVE_CLIENT, physical-input, VoiceOver, HUMAN_STUDY or general quality evidence is produced. The Linux editor does not run Swift/AppKit; only static source/resource checks run there. No real personal preferences, input, dictionary corpus or compiled personal state is uploaded.
