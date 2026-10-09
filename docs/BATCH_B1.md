# B1 native research controls (Draft)

This is a small Batch B lab slice, not the full basic product or an installed IME. The A1 bundled app keeps its tiny fixture. A2's comparison schema/data remain unchanged. B1 derives twelve separate research schemas in an ignored cache; corpus and compiled dictionary files are never added to the app or CI artifacts.

## Run on macOS after A1/A2 preparation

```sh
python3 Tools/prepare-b1.py
source .build/b1-env.sh
swift test --filter NativeControlTests
swift run PAIANativeLab
```

Set no flags to keep the default A1 fixture app. B1 requires the explicit PAIA_B1_RESEARCH flag and all verified external research paths. Every launch creates isolated temporary user data with learning disabled. Settings are session-only in this slice.

## Controls

Full pinyin, Flypy and Natural Code each have Simplified and standard Traditional output. Literal mode delegates ordinary text editing to NSTextView, preserving case, paths and digits. The Chinese punctuation lane routes comma/question/exclamation/semicolon through real native librime punctuation. Dots, colons, quotation marks, slashes and other symbols remain ASCII in this slice; it does not infer code/URL/decimal context or claim a complete punctuation policy.

Configuration changes are refused while a composition or repair is active. Commit or cancel first. A new engine session invalidates all old candidate/target identities. Return retains the established raw-input commit contract; Commit Chinese uses the real engine composition commit. No synthetic delete/backspace events edit another application.

Enable Keep composition for repair while idle. Confirm an engine candidate, then select Repair confirmed segment. Targets come from A2's actual engine spans; text is not split by Chinese character count. Enter replacement raw spelling and desired engine text. Preview searches actual paths without writing the document. Accept updates only owned marked text; Commit Chinese remains separate. Conflict, incomplete and unsupported statuses preserve the original without unlocking the suffix automatically.

## Focus and identity boundaries

The synthetic host has an explicit same-window inspector lease. Host writes are prohibited while it is suspended. Only exact owned inspector views may receive that temporary focus; ordinary focus loss, external text/selection change, app/window loss or session change invalidates it. Acceptance restores the original text view and verifies its exact marked/text/selection identity before transfer. The two inspector inputs are dedicated NSTextViews, avoiding the transient identity of AppKit's shared field editor. There is no nil-responder, shared-editor or delegate-based exemption. See [Apple’s shared field-editor lifecycle](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextEditing/Tasks/FieldEditor.html). This custom in-process protocol is not a claim that arbitrary installed IMK clients support the same handoff.

Displayed target/candidate/accept controls retain their original action identities. A queued old control must not act on a newly rendered target or proposal. Cancellation, editing either field and closing the inspector destroy an unaccepted trial session.

## Verification scope

Native tests run actual AppKit control actions and real librime. They check schema outputs, literal/punctuation semantics, marked text, single commit, focus changes and stale controls. Accessibility checks cover native labels/control state/defined key equivalents only. Physical keyboard/pointer interaction, visual layout on real displays and VoiceOver are not verified by these in-process checks.

Read `evidence/b1/VALIDATION.md` for exact heads and failures. Initial repair-focus tests failed and remain recorded. Draft status persists until exact-final-head tests, A1/A2 regression and independent review finish.

Later Batch B work still includes explicit user-dictionary governance, rare-character workflows, persistent settings, update/recovery behavior and installed-input-source compatibility. Production corpus redistribution clearance is still outstanding; no private profile, paid resource, signing credential, input-source preference or PAIA change is part of B1.
