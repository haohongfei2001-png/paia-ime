# Ordinary mixed-input implementation checkpoint

Original REPORT 6.4/8 and HANDOFF 5 require lossless Chinese mixed with English, code and Unicode. Baseline is resource-startup main df871e48bc3a5df450f7b600280e964c8e1cc511. This branch begins with an isolated **ENGINE_NATIVE feasibility probe**, not an exposed mixed-input product feature. Existing B8 refusals, G01 validators and app/host paths are unchanged.

Pinned librime source a251145d3aafa33871824a40bbec04c966bd8b56 has a relevant boundary: `ConcreteEngine::Compose` normally rebuilds from the prefix before its byte caret, while `GetPreedit` may display the remaining full-input suffix and `GetCommitText` uses composition input. Therefore a correct-looking preedit is not proof of a complete final commit. Native navigation/deletion is byte-wise; ordinary key forwarding cannot safely edit arbitrary Unicode graphemes.

`Tools/probe-mixed.sh` compiles a disposable test executable against the already pinned engine, headers and G01 helpers. It is not linked into the app. It replays actual selected Chinese candidates, preserves their spans/surfaces/phonetic codes, and introduces a distinctly typed identity candidate **only** for explicit authored literal bytes. It never puts the expected Chinese answer into a synthetic candidate. Fresh trials retain the full native caret/input; future logical-caret and typed-layout ownership remain separate implementation work.

The first planned checkpoint uses full/Simplified research data with two genuine Chinese anchors, including a deliberately non-first first-anchor choice. Fourteen literals at start/middle/end exercise English, identifier, URL, path, versions, decimals, times, formula, punctuation, fullwidth Latin, supplementary Han, decomposed acute and skin-tone/ZWJ emoji. Recomposition, five independent whole-literal reconstruction variants, exhausted replay, a genuinely unconfirmed Pinyin suffix and later actual selection are checked. The partial-suffix case also uses the alternate Chinese choice in that run. Every successful case verifies actual native commit text and an empty second commit read; source sessions remain unchanged. Independent whole-span reconstruction is neither a chained mixed-state edit test nor grapheme-caret/backspace UI qualification.

No native result is claimed until the exact-source macOS workflow runs. Keep any failures and unsupported cases. The next integration gate requires typed origin/layout, active-span candidate identity, grapheme-safe editing, complete Return semantics, source leases, bounds and latency, then existing one-effect native AppKit/IMK callback tests. Traditional/filter boundaries, other spelling schemes, editing within unconfirmed spelling, candidate/menu movement and long suffixes are separately required. Do not weaken current safety guards or choose a new multi-engine composition architecture merely to make this initial probe green.

No new corpus/library, system installation, normal IMKServer startup, private input, model/network hot path, payment or public release. Existing unbundled research dictionary provenance and production-license gate remain unchanged.

First checkpoint df8a1b53792f8022128992e31966fa7b7e2f0197 failed the standalone probe's C++ compilation in [IMK run 38063272967](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38063272967). The upstream C-oriented `RIME_STRUCT` macro expands to `{0}`, triggering three missing-field-initializer diagnostics under the probe's unchanged `-Werror`. No mixed native case executed; later basic/repair stages in that workflow were skipped. Full failed log and job/artifact metadata are retained. The fix uses C++ `{}` zero-initialization followed by the same upstream `RIME_STRUCT_INIT` size initialization; no warning suppression or assertion removal.

Checkpoint 9517f16709dfb1e19dc50076ce4bcba8614fe02e compiled but [IMK run 38063636808](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38063636808) stopped before `main`: the official archive filename `librime.1.16.0.dylib` differs from its embedded `@rpath/librime.1.dylib` install-name. The probe now creates only that filename alias in its disposable owned engine directory, with an executable-local rpath. Engine bytes, signatures and system loader settings are unchanged. No mixed case had executed at this failed checkpoint either; skipped downstream stages are retained rather than called passed.

Checkpoint 109663c7819ad32148fddf7944a09065023d4516 entered the native probe but [IMK run 38064040303](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38064040303) failed with `actual Chinese replay failed`; it did not qualify the matrix. Initial mixed input can contain multiple unselected engine segments, whose last menu is not necessarily the intended first Chinese span. The next trial-only change projects the native caret to each intended Chinese anchor end before actual selection, then restores complete native input. It never moves the original source caret. Per-case diagnostics and an explicit unchanged-source rejection of the old unprojected path are added (planned total 100 cases). Native verification of this fix remains required; no failed/skipped stage becomes a pass by this explanation.

In a mixed trial, `Select` itself can restore the full caret and move the last-menu frontier beyond the selected anchor. The probe-specific selection helper therefore checks actual candidate span/text/nonempty phonetic code, calls real `Context::Select`, verifies that exact selected anchor, and ultimately verifies the full typed layout and drained commit. It does not reuse G01's single-frontier postcondition or weaken the production G01 helper.

Checkpoint 938f8b6a90816dafcb3e45e2f19e732fbfb51a2f passed the 42 ordinary-choice literal/position cases, five independent reconstruction variants and exhausted-work test, then [IMK run 38064531605](https://github.com/haohongfei2001-png/paia-ime/actions/runs/38064531605) failed an incorrectly anticipated negative fixture: that specific unprojected RAG-middle case did **not** reproduce the earlier replay failure. The partial-suffix and alternate-choice groups had not run; this is not a 98-case pass. Instead of presuming the failing input, the next checkpoint executes the whole former unprojected algorithm in its own process/user directory with per-case diagnostics. That control must reproduce the specific native replay failure with verified unchanged source (setup failures/crashes do not qualify), followed by all 98 projected cases succeeding in a separate process. The invalid two anticipated negatives are not counted as passing tests. Resource preparation/probe steps move earlier in the same existing job for faster diagnostic feedback; the twelve workflows, runner allocation and existing app/host assertions are unchanged.

## Owner API and typed-value checkpoint (implementation in progress)

The next source checkpoint introduces a separate optional C ABI table in the
same pinned extension. It keeps the original G01 ABI unchanged. Opaque mixed
owners hold immutable schema/options, a single active disposable projection,
and bounded genuine-selection proofs. Projection and proof capabilities use
process-wide non-reused counters. Chinese proofs can only be issued after
actual native selection, with exact source coverage, surface and nonempty
phonetic code. Explicit literals have separate typed provenance.

The full-source replay validates every proof, span, native input and composition
input before requesting a real commit. It verifies the drained value and an
empty second drain, then seals the owner against a second commit. Failure before
success preserves the draft/proofs; Swift publication failure after a sealed
native result must retire the operation rather than manufacture a second effect.
This is not yet wired to the Swift input owner or visible IMK controls.

A new native API matrix is configured for 20 full commits: 16 combinations of
literal and left/right confirmation order, partial raw coverage, foreign/stale
capabilities, literal-only Unicode, and 128 independently selected suffix proofs.
It also checks zero-budget rejection and deliberate subsequent success, malformed
UTF8/embedded NUL rejection, revoked proof and sealed-result replay refusal.
These new cases have not run until exact-head CI records them.

MixedDraft is a pure typed value with complete original source, a separate
literal/spelling/verified-surface display, stable span IDs, source-byte and
host-UTF16 maps, bounded replacement and explicit selected-span reopen.
Its nine configured tests use simulated proof IDs and are not engine evidence.
Cross-origin grapheme joins and a caret that would land inside a newly joined
following grapheme are refused unchanged. Limits are 4096 source bytes,
256 spans, 16384 display UTF16 units and 65536 display bytes. Linux GNU C11
syntax checks of the shim pass; Swift/AppKit and the C++ extension still require
macOS CI. The first strict-C11 Linux attempt lacked POSIX declarations and found
new misleading indentation; indentation was corrected and GNU C11 used to
match the existing POSIX source. This was not an engine or macOS execution.
