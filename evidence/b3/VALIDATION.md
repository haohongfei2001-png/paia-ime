# B3 validation record

Baseline main b45f8bae15d847209c5855253db9250515fe4164. PR #5 opened Draft.

## Initial code checkpoint

068e3821ad9df292a952751619906b787314e9e0: all five macOS workflows succeeded. B3 run 37998967038/job 114052068121/artifact 11647848418 passed six settings-store methods and nine fresh-process native stages (controls, save, restore, restore_failed, save_unknown, overlay_disabled, settings_corrupt, settings_missing, personal_corrupt), with zero failures/skips. The controls stage exercises all 24 spelling/script/literal/punctuation combinations against the native engine or NSTextView. Separate mode-application and Save, current-config retention on failed creation, composition/repair save guards and unknown-save suspension passed.

A1/A2/B1/B2 regression runs 37998967002/37998967030/37998967009/37998966990 succeeded. A1 retains its unrelated explicit B2 configuration skip; no B3 native success is inferred from that filter.

The initial settings root-view PNG was inspected. Save/defaults buttons and persistence status were visible; the editor was blank in that capture. A subsequent capture assertion/order change verifies and displays committed synthetic text before accepting improved visual evidence. It does not retroactively change this checkpoint.

## Reviewed code checkpoint

0c8cd9cc39f0461a97d83fd0ecaa01aaebd10179 passed both independent static reviews and all five exact-head workflows:

- B3 run 37999781104/job 114054754564/artifact 11648074702: nine settings-store methods and all nine fresh-process native stages passed with zero failures/skips. The dirty returned engine session is rejected and ended, the prior configuration can still commit once, and closed-window stale actions cannot write or rebuild a session. The improved synthetic view was visually inspected: committed “你好”, mode controls, separate Save/defaults controls and persistence status are visible. PNG SHA-256: 72fdfdd50d0c8251c0aac5707c7c054401ae702e0e1e67cf140087ad274cbfd7.
- A1 run 37999781085/job 114054754326/artifact 11647859327: sanitizer ABI, state, ten engine and six AppKit host tests, native app and full 3,800-sample benchmark passed. Its broad engine filter retains the one unrelated B2-configuration skip.
- A2 run 37999781111/job 114054754311/artifact 11648603696: lease, all 28 native constraint cases, both full-corpus paired benchmark arms and AppKit host passed.
- B1 run 37999781123/job 114054754390/artifact 11648039409: all twelve native control methods passed, including focus/repair and idle controls.
- B2 run 37999781087/job 114054754218/artifact 11648890960: ten lexicon governance, four file/cleanup and five manager methods plus seven native stages passed. The new selected-root and scratch-replacement sentinel cases passed. The four file methods are executed twice by current filters and counted once here.

The documentation-only checkpoint 4b32a6499f6e565d598a2cb45a1de956dac61538 also passed all five exact-head workflows (A1 38000550276, A2 38000550267, B1 38000550277, B2 38000550271, B3 38000550278). That checkpoint did not contain the previously missing foreign-mark regression below; its green checks do not cover the later fix.

## Foreign marked-text regression found before merge

Tests-only head 0960769065ca689265fcbc6bbd183067b3c0bf64 reproduced a real AppKit API-boundary defect: HostDispatcher adopted a mark already present at construction, then cleared it on empty update/invalidation; literal-mode settings guards saw an empty engine and allowed mode/default/Save actions during that unowned mark.

- A1 run 38001026306/job 114058837077 failed the new host method with 11 assertion failures (seven total methods, the existing six passed). The following benchmark step was skipped because of this failure, not counted as passed.
- B3 run 38001026316/job 114058836963 passed all nine store methods but failed controls with 12 assertions, including cascading checks after the unintended Save. The later eight fresh-process stages did not execute. Both complete failing logs are retained.

The fix refuses existing marks at dispatcher construction (ending the rejected engine session), refuses renewal while an unowned mark remains, and routes the existing nil-dispatcher path back to AppKit. Mode/Save/defaults consider host marked text busy; engine actions require their own current target. Added factory-count tests verify no new session while marked and successful renewal after the original owner unmarks. Exact fixed-head and merged-main native checks are required separately; earlier successes are not inherited. This uses synthetic text via actual NSTextView APIs, not a live third-party IME compatibility test.

## Ownership fix verified at 5d36c23

Exact head 5d36c23813910d6e2a6abc9362dcaa883db6733b (tree ff7eddb5237b756184be26d94d818fb5dc266d38) passed both independent static reviews and all five native workflows:

- A1 run 38001410715/job 114060100628/artifact 11649106934: eight AppKit methods including both new ownership/renewal regressions passed; existing state, sanitizer ABI, engine and 3,800-sample benchmark passed. The unrelated B2-unconfigured engine-filter skip remains explicit.
- A2 run 38001410772/job 114060100766/artifact 11649806991: all 28 real constraints, paired full-corpus benchmark and AppKit tests passed.
- B1 run 38001410751/job 114060100568/artifact 11649132717: all twelve control/focus/repair methods passed.
- B2 run 38001410720/job 114060100789/artifact 11649617681: ten governance, four file and five manager methods plus seven native stages passed.
- B3 run 38001410687/job 114060100711/artifact 11649817141: nine store methods and all nine fresh-process native stages passed. The previously failing literal foreign-mark checks now pass without removing or weakening the assertions. No B3 failure or skip remains at this head.

The new B3 view capture was inspected and again contains committed “你好” plus Save/defaults/status controls; its pixels match the earlier improved PNG (same SHA-256 listed above). The API-simulated foreign owner is tested in-process, not pictured as a real installed IME. This later evidence-only commit does not change Sources/Tests/Resources/Tools/Package.swift/research; final-head and merged-main checks are nevertheless verified separately and retained in the private recovery snapshot.

## Review-led additions verified at 0c8cd9c

Selected-root replacement guards for settings and B2 lexicon authority; identity-bound B2 scratch cleanup; first-save and marker/integrity/duplicate-key/revision fault cases; a returned dirty real session rejected and ended without harming the old dispatcher; closed-window settings action invalidation. These passed their own new-head macOS run listed above. Review findings and any failures/skips remain in the private recovery logs rather than being hidden by earlier green checks.

SIMULATED covers codec/filesystem fault injection and failed-session setup. ENGINE_NATIVE/APPKIT_HOST cover real sessions, candidate/commit output and actual AppKit objects. No INSTALLED_IME, LIVE_CLIENT, physical-input, VoiceOver, HUMAN_STUDY or general quality evidence is produced. The Linux editor does not run Swift/AppKit; only static source/resource checks run there. No real personal preferences, input, dictionary corpus or compiled personal state is uploaded.
