# Bounded IMK context: checkpoint evidence

Baseline exact main: `c2e6d85d87f5e24ff00b46731176779ac5e996b7`. Scope and limits: [context contract](../../docs/IMK_BOUNDED_CONTEXT.md). PR: [#15](https://github.com/haohongfei2001-png/paia-ime/pull/15). No system service, input source, user document, installed application, new corpus or model is involved.

## Actual source checkpoints

| Source | Actual result | Boundary |
|---|---|---|
| `006659f7112bfd8ced022e5d3e7f040ed12b2705` | 11 workflows succeeded; [IMK run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38056187372) failed | Native compile/preflight/C0 tests passed; ContextCore 7/0; ContextIMK 12 tests with 3 assertions failed in one emoji ZWJ case. Later research/basic/repair stages skipped. |
| `b20409f8e69a87d7237d520018a572ab4f3691cd` | All 12 workflows succeeded; [IMK run](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38056714516) completed | ContextCore 7/0; ContextIMK 12/0; existing 17 C0 tests, fixture test, nine basic-control processes and eight G01 tests also passed. Exact source SHA/resources/machine/SDK retained in logs. |

The final source additionally isolates each panel render and its presentation generation, strengthens permission/unsupported-key callback placement tests, and makes the old owned-lab dispatcher refuse the new exact-range reviewed effect. The previous green checkpoint does **not** cover these changes. Final acceptance requires the exact final PR head's native CI and independent review, then a separate exact-main run. [PR checks](https://github.com/haohongfei2001-png/paia-ime/pull/15/checks) and the PR acceptance record identify that final SHA; recovery includes its full logs/checks alongside these earlier checkpoints.

## What is actually exercised

- Raw NSString UTF-16 before lossy Swift conversion; invalid surrogates, actualRange/count mismatch, truncation, overflow and bounds; qualified empty-document/end-of-document evidence.
- Original and replacement grapheme joins: supplementary characters, decomposed accents, emoji/ZWJ, RI and Hangul joins, CRLF deletion, long ambiguous runs and retained-left LF reset. No full Unicode conformance or language-quality claim.
- Explicit menu capture into a context-only real InputSession; ordinary C0/retained actions cannot write through it. Longer/shorter/empty replacement uses the same effect reservation and exact finite range once.
- Independent C2/C3 permission and qualified cheap endpoint metadata. Default IMK bridge performs no context or length reads and cannot gain privilege from its synthetic bundle ID or implemented selectors. Fixed capture/review/Apply observations do not prove that arbitrary external getters are cheap or interruptible.
- Draft keys and rendering perform zero context/length reads. Native view remains non-key and the authored NSTextView remains first responder. Literal Unicode injection demonstrates event handling, not physical Chinese composition.
- Exact original units, selection, document revision, permission epoch and shifted output neighborhood checked at explicit boundaries. Revoked, stale, duplicate, reentrant, wrong-range and unknown-readback effects do not retry or clear text. Empty-deletion recovery stays visible.
- Full original/replacement review, actual scrolling overflow and accessible last glyph, without ellipsis replacing the complete accepted text. Per-render identity is tested independently of the engine/host effect identity.

## Native view evidence at b20409f

Both PNGs were decoded from post-XCTest log chunks, CRC-checked and opened. Each is 650 x 490, RGBA with alpha 255 throughout. The first view shows the complete authored original with more content below; the tail view reaches the complete replacement's final `末终` while Apply/Cancel remain visible. XCTest separately checks actual content height greater than viewport, positive scroll origin, and the last glyph inside the visible region.

- Review: 61,841 bytes; SHA256 `04b94b104990f92ac1cd0ba356745dcb4c9d03037a0dbded3881a6c6b9fbfb35`.
- Tail: 62,622 bytes; SHA256 `b26bb992951f7b4f925e5de3fa458df32cb03122d932d2defbbab4b1848cb45f`.

These are native content renders, not desktop screenshots or installed-client capture. The first failed run created render files but stopped before their log serialization; no pixel-inspection claim is made for that checkpoint. Its full failure log and artifact metadata remain retained.

## Retained failures and review findings

The first native failure was the overbroad control-character filter excluding ZWJ. The original byte-exact draft/result/caret assertions remain; source now allows literal ZWJ/ZWNJ while refusing actual control/function-key input with a visible unchanged-draft notice. No failed input was removed to make the suite green.

Independent review before the first CI corrected old refused-client menu identities, repeated failure downgrading an already-issued unknown write, and an inaccessible empty-deletion recovery. SDK inspection corrected inline-relative candidate geometry with idle zero. Further review strengthened immediate permission checks before reads, isolated reentrant presentation and refused exact-range effects in the unqualified lab consumer. These source/test reviews are distinct from actual native execution.

## Remaining gates

Evidence classes are ENGINE_NATIVE and APPKIT_HOST with authored protocol clients. C2/C3 is enabled only through an explicit synthetic qualification provider. There is no general public IMK document revision/CAS contract and no live-app allowlist here. Same-content target swaps, absent/reliable secure-field evidence, physical keys, framework-created controller lifecycle, live compatibility, VoiceOver and real user benefit require separate validation. The literal draft is not Pinyin composition or AI rewriting. Production dictionary grants, general language quality, visible latency, signed installation/update/migration/rollback/uninstall and D/E studies remain open.
