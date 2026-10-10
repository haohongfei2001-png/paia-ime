# Consolidated input habits and spelling contract

Original scope: REPORT sections 6.4, 7 and 8.2. Baseline is mixed-input main
`4a2cc9db13133720618ad3e2e736730d4a8bc7f4`. This node consolidates required ordinary
input settings and protocol behavior; it does not create a new character manager.

## Native checkpoint and final capability increment

Head `7d4f085f6ad6cc68d4890e4257ac14c8b3626d8b` passed all twelve existing
public standard macOS workflows; every job and step succeeded without skips.
[Commit-bound validation](../evidence/input-habits/VALIDATION.md) records actual
engine/host counts and the separately pending final increment. Old green runs
do not qualify that later source. These remain the only CI workflows.
Initial source review found and fixed three owner boundaries: unrelated management
retirement resetting an explicit activation mode, same-counter foreign-driver menu
tokens, and selection/foreign-mark changes during the palette hide callback. New
tests for each passed at the qualified checkpoint.

### Independent bounded spelling controls

`fuzzyInitials` is the explicit closed n/l, z/zh, c/ch, s/sh preset. Rules run on
phonetic syllables before double-Pinyin key mapping. It is not arbitrary rule import
or automatic language detection. `fullPinyinCorrection` controls the exact 37 active
typo derivations in the pinned Full-Pinyin speller. The UI labels its scope and
disables it for Flypy/Natural, retaining the preference without altering double
keys. Turning it off does not promise every mistyped input has no candidate;
abbreviations, prefix completion, other readings and orthographic aliases remain.

The generic native `translator/enable_correction` remains false. That runtime
option cannot disable static spelling algebra compiled into an existing prism.
Eight distinct effective spelling policies produce eight prisms and 32 schemas
across script/punctuation variants. Defaults retain old schema/prism names and
the old spelling algebra. Variants never share a prism with different algebra.
No deployment happens per key. Public-fixture policy controls are explicitly disabled and show no active typo toggle. Unsupported public-fixture settings fail preparation
and retain the previous configuration. Personal exact-reading overlays are carried
through all new Full/Simplified variants; their own exact prisms do not silently
become fuzzy. After a personal edit, each variant falls back to its matching public
baseline until the next launch.

The new fixed recipe is derived from the same GPL-3.0-only pinned Rime Ice schemas,
with notices and provenance retained. No new dictionary was imported. The original
A2 comparator and source locks stay unchanged. A separate 27-row authored fixture
uses the same actual speller to test finite positive/negative controls; it is never
added to the full research corpus. Existing unbundled research data provide separate
real-engine positive-path checks, not production language-quality acceptance.

### Settings and application initial mode

Canonical `paia.settings.v2` adds only the two closed policy booleans and at most
16 explicit application-ID initial-mode rules. IDs have bounded ASCII syntax and
exact case-sensitive matching. The global default applies if identity is unavailable
or unmatched. No app scan, title/document read or permissions inference occurs.

An old v1 file is verified against its original four-field schema, digest and exact
canonical bytes before defaults are added in memory. Reads never rewrite it or
increment its revision. An explicit Save writes v2 under the existing single writer
and known-outcome verification contract. The existing store initialization marker
remains unchanged, avoiding an unsafe two-file migration. Corrupt/unknown/duplicate
fields and unconfirmed writes remain conservative failures without retry.

The IMK bridge reads this activation's public client bundle identifier once. An
identity getter that reenters activation, finish, deactivate, close or key handling
cannot publish the old owner. Initial mode is per driver/activation and survives
ordinary idle engine recreation; an explicit current-activation mode action does
not change another driver. Unrelated personal/expression management retirement
preserves it. A deliberate global configuration change retains the existing all-idle
gate and prepares the next engine before retiring old idle sessions. It never changes
an active composition.

### System character entry

The actual IMK menu has an explicit system Emoji & Symbols action. It is available
only for a qualified idle C0 binding. A per-driver nonce and activation/generation
consume the action before callbacks. Target ownership is checked again after hiding
the IME presentation. The action calls the public AppKit character palette; the OS
owns any eventual character choice and insertion. No IME commit, clipboard access,
focus polling, enhanced context permission, custom radical database or new font is
added. The existing known-U+ feature remains a separate qualified path.

Tests inject the palette callback to prove gating and lack of IME writes; they do
not prove actual OS-panel focus, character selection or installed-app insertion.

### v/ü and double-Pinyin boundaries

Ordinary spelling uses v to represent ü. Corresponding actual codes/targets are
tested for all declared schemes, including nv/lv, lve/lue or lt, nve/nue or nt,
xi'an versus xian/xm, and double-Pinyin zero-initial sequences. Single-key candidate
diagnostics retain actual candidate type and canonical code; a prefix completion
is not mislabeled a complete single-key encoding.

Direct Unicode ü in ordinary composing spelling remains unsupported: idle passes
it to the host, active composition refuses unchanged, and literal input preserves
it (including combining diaeresis). It is not silently normalized to v. Supporting
that direct phonetic input requires a separately validated source-to-engine mapping,
Return, editing and repair contract; neither ASCII SessionCore nor librime's speller
currently provides it.

## Actual checkpoint evidence

- Static pinned recipe: exact 37-rule removal, four preserved orthographic aliases,
  unchanged default algebra, collision-free 32 schemas/eight prisms.
- ENGINE_NATIVE finite authored control: 928 actual selected/drained commits,
  144 exhaustive target-negative cases, 48 separately labeled single-key diagnostics,
  all 32 effective schemas. Positive alternative spellings retain the same canonical
  phonetic code; an incomplete negative search fails instead of proving absence.
- ENGINE_NATIVE research: 272 same-meaning and 28 policy-positive actual commits;
  separate whole-source Return and stale-candidate checks. No quality inference.
- APPKIT_HOST: eight actual driver/client/settings tests, with a SIMULATED system
  palette callback; two owners, direct ü boundary, migration-save UI, getter/lifecycle
  reentrancy, stale/foreign actions and target changes. Actual OS palette is untested.
- Five additional settings migration/identity/known-save-outcome tests; all previous
  mixed, G01, resource, expression, context and basic-input regressions remain enabled.

The final increment disables unsupported public-fixture policy UI, preserves the
internal legacy default when that UI is visually off, and tests a real literal-mode
button action. It also carries the research capability into the basic-controls test
workspace and adds eight personal-overlay commits plus eight configured public-baseline
commits after explicit personal mutation. Those additions must pass their own exact
head; the earlier checkpoint does not claim they executed.

No installed input source, normal IMKServer startup, signing/notarization, production
corpus clearance, real-app compatibility, physical-key/VoiceOver/display scaling,
visible latency/energy, human efficiency or long-duration certification follows from
this source. No new paid resource, hot-path network, implicit learning/private input
archive, AI or PAIA dependency. These remain product qualification/release gates.
