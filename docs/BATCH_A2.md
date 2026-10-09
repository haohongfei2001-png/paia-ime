# Batch A2: bounded native constrained editing

This is an engine/host feasibility implementation. It is not an installed input source, a full constrained-Viterbi decoder, a competitor-best-operation comparison, or proof of user-visible superiority. The ordinary native app still uses the A1 typing UI; interactive repair controls belong to the next UI stage. No AI, PAIA, private profile, system input-source preference, signing credential or paid runner is involved.

## Reproduce on macOS

```sh
python3 Tools/audit-a1.py
python3 Tools/audit-a2.py
python3 Tools/prepare-a1.py
python3 Tools/prepare-a2.py
bash Tools/build-g01.sh
source .build/a2-env.sh
swift test --filter ConstraintCoreTests
swift run -c release paia-constraints
swift test --skip-build --filter ConstraintHostTests
```

Each process owns one librime runtime, with a new temporary user directory. All lab schemas set `translator/enable_user_dict: false`. `_no_learning` alone is **not** an upstream learning guarantee. Initialization/deployment and build-time network acquisition are separate from the key/repair hot path. The harness prints only authored synthetic inputs/results; production input logging is not added.

## Actual engine contract

- `repairChoices` returns actual candidate indices, raw UTF-8 spans, displayed text and explicit enumeration completeness. Each selection is an issued, generation-bound capability. A fabricated/unissued index or a superseded list cannot select a different candidate.
- `repairAnchors` returns immutable target identities bound to session, target/privacy epoch, input generation, raw string, dictionary revision and request generation. `prepareRepair` accepts that displayed target, not an index automatically rebound to a newer composition.
- Source anchors are actual confirmed engine candidates. Genuine `Sentence::word_lengths` supplies raw spans; genuine dictionary codes preserve readings. For filtered sentences, an isolated whole-raw replay must emit matching spans/codes and the identical complete filtered output before finer targets are exposed. Opaque dictionary phrases are not arbitrarily split.
- A trial creates a fresh engine session with the same schema/options, disables auto-commit, and sets the **complete** edited raw string. It replays hard left anchors, explores real target candidate paths (including resegmentation), then replays shifted right anchors. It never truncates the suffix to make a candidate appear valid.
- Every selection invokes the engine. Successful complete raw coverage and final engine preview are checked. Concatenated strings are used only to verify constraints, never to form a host commit or fabricate a candidate.
- A successful trial remains an owned engine session. Acceptance rechecks its lease and snapshot before atomically swapping the entire owned session. No composition containing translator-owned pointers is moved between engines. Cancellation, stale replies and failed trials preserve the original session.
- A proposal updates marked text only. Final `commitEngineComposition` invokes the real engine commit API; the existing SessionCore reserves the effect once before the AppKit host inserts it.

## Failure meanings and limits

`constraintConflict` (20) means no path in this configured emitted-candidate replay domain, **not** a proof over every latent language-model lattice. Upstream translation prunes paths; fixed-anchor replay is deterministic. `searchIncomplete` (21) means a candidate/step budget was reached. `unsupportedSegmentation` (22) means a source span/filter mapping could not be safely reproduced. These retain the original raw/confirmed composition. The caller retains the proposed edit separately and may explicitly request whole-sentence recomputation; no hidden unlocking occurs.

A maximum of 2,048 counted engine/search operations and 4,096 raw bytes bounds work and storage, **not wall-clock time**. Individual synchronous C++ calls are not safely interruptible. No timeout pretends to cancel them. A blocked call still blocks the serialized owner. Output grapheme alignment must be separately checked before future per-segment visual highlighting.

The typed extension is pinned to librime 1.16.0's exact release digest, source/header closure, Boost 1.89 and Apple libc++ ABI. It verifies the same `rime_get_api` runtime identity. Both release architectures export the required symbols; current native execution evidence is ARM64 only. A future engine update requires revalidation, not a version-string-only compatibility claim.

## Strong baseline and measurement

The research comparator is Rime Ice **core-only adaptation**, commit `da1fbe602e38f26db846fa10120ee64c2b0324c0`. All five default Chinese dictionaries (1,873,509 rows, not unique phrases) retain upstream order/frequencies. Full pinyin, Flypy and Natural Code spelling rules derive from the pinned schemas. Native OpenCC s2t provides Traditional output. Lua, English/radical dictionaries, optional models and stock Rime Ice UX are excluded and are not claimed equivalent.

Both lanes use identical engine, corpus, options and fresh nonlearning state. Six vocabulary probes compare the top page before repair and record expected ranks, including a held-out composed term. The paired benchmark begins from the same confirmed composition, uses five warmups and fifty measured corrections per lane, and checks equal final engine output. Its baseline is explicit cancel/retype, not the best available cursor-edit workflow. Reported p50/p95/p99 are synthetic correction-through-engine-commit CPU/wall durations on a cloud runner; startup and whole case setup are separate. No physical key-to-visible latency, language accuracy distribution, blind human efficiency or superiority over Apple/WeChat/Sogou is established.

## Resource and redistribution boundary

See `Resources/A2/upstream-lock.json`, `Resources/A2/README.md`, and `Licenses/a2/`. Immutable sources, SHA-256, source roles and mixed provenance are retained. Generated runtime files receive a combined content-derived revision. Original corpus rows and compiled dictionaries stay in ignored build caches and are excluded from app/CI/recovery artifacts. Rime Ice's GPL declaration does not resolve every imported source's grant; production redistribution remains uncleared. The artificial filter fixture is original test data, never injected into the modern comparator corpus.

## Evidence

See [A2 validation and retained failures](../evidence/a2/VALIDATION.md) and [exact-head CI](https://github.com/haohongfei2001-png/paia-ime/actions/workflows/batch-a2.yml). Categories remain separate: `SIMULATED`, `ENGINE_NATIVE`, `APPKIT_HOST`. No `INSTALLED_IME`, `LIVE_CLIENT` or `HUMAN_STUDY` evidence is claimed.
