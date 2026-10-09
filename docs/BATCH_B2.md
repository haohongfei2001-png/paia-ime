# B2 explicit personal lexicon lab

B2 adds a native manual-term manager and isolated read-only personal dictionaries to B1. It remains an unsigned, uninstalled research app. It does not complete all of Batch B, establish general language quality, or provide automatic learning.

## Explicit launch and operation

After the pinned A1/A2 preparation and G01 build described in their guides:

```sh
python3 Tools/prepare-b1.py
source .build/b1-env.sh
export PAIA_B2_RESEARCH=1
export PAIA_B2_STORE="$PWD/.build/my-explicit-lab-lexicon"
swift run PAIANativeLab
```

Choose a dedicated local lab directory, not an existing input-method profile. The app opens no other personal store. The default A1 app and B1 launch remain separate. Open “Manage explicit personal terms…” only while composition and repair are idle. Add/edit/pin/delete/restore require explicit controls; editing fields alone never saves. Entries are shown in pages of 50. Imports use the selected JSON file, display additions and protected/conflicting records, and require a separate Apply. Cancel, closing the window and stale controls cannot apply a later preview. Export includes tombstones and should be kept private.

A successful mutation immediately disables the current personal overlay and ends its existing sessions. Public-baseline input remains available. A subsequent app launch compiles the new generation before creating input sessions; no live dictionary rebuild or per-key filesystem scan occurs. A corrupt/missing established authority opens only the public baseline, never an older personal generation. If compilation or artifact verification fails, the B2 launch fails; it does not silently label a partial generation healthy. Relaunching the separate B1 lab remains available.

## Identity, deletion and integrity

A term has a UUID, exact Unicode surface, explicit reading and aliases, Full/Simplified scope, pin, creation time, local revision, and optional deletion time/no-relearn tombstone. Surface alone is not identity. Same-surface different readings and same-reading different people remain separate. Equal effective surface/readings are rejected, and only one overlapping reading may be explicitly pinned. There are no inferred pronunciations or usage counters. Readings currently validate lowercase ASCII token shape, not a complete phonetic lexicon.

Limits are 1,000 records including tombstones, 1 MiB canonical envelope, 80 graphemes/1,024 UTF-8 bytes per surface, twelve reading tokens and eight aliases. TSV-control, newline, bidi embedding/override/isolate and comment-header injection is rejected. Supplementary characters, combining sequences and emoji remain intact. These are lab bounds, not final product promises.

The single writer uses a filesystem lock. Its own records must be ordinary non-symlink, non-hard-linked files. Canonical UTF-8 JSON has closed envelope keys and SHA-256 integrity; alternate encodings, excessive nesting, extra fields and oversized data fail closed. This checksum detects corruption, not a malicious author's identity or authenticity. Imports accept this versioned canonical format only, not arbitrary Rime/Lua packages.

Import previews bind frozen selected bytes, digest, store instance and local revision. Changed IDs/content are conflicts, not overwrite instructions. Re-importing the same term is idempotent despite locally rebased revisions. Existing tombstones block older positive records, including same-key records with another ID. Only explicit Restore revives a term. Deletion removes the personal contribution; it does not remove an equal public-dictionary word. Tombstones retain content intentionally and are not physical erasure.

Mutations write a private staging file, request a full file flush, atomically rename the authority, then request a directory barrier. Unknown post-publication outcomes block further operations and require reopening verification; they are never retried automatically. Explicit management reads also verify that the authority still matches the owned generation. There is no automatic backup rollback that can undo a deletion. Tests inject failures around publication; they do not emulate every filesystem, actual power loss, or hardware durability.

## Real engine integration and scope

Personal rows generate separate ordinary/pinned read-only dictionaries with their own full-pinyin prisms. The pinned tier has higher translator quality; this is tested as relative ordering for the same full span, not universal first place across arbitrary sentences. Aliases are explicit additional readings. No answer strings bypass librime candidate selection or its commit API. Ordinary typing/selection never writes LexiconStore and all translator user dictionaries remain disabled.

The overlay is enabled only for Full/Simplified, with both B1 punctuation choices. Flypy, Natural Code and Traditional use the unchanged public baseline. The private G01 extension's numeric syllable codes are dictionary-local: constrained repair is explicitly unsupported in an active mixed personal overlay. Baseline schemas retain G01. Extending that capability needs separate engine work and evidence; this slice does not claim it.

The verified B1 full-corpus baseline is copied to an owned generation. Compilation verifies every expected nonempty regular table/reverse/prism/schema before activation. Personal text appears only in validated data rows, never schema names or executable scripts. Generation identity includes the canonical store digest and baseline revision.

## Retention and failure cleanup

The selected store contains its authoritative JSON and a managed `.paia-b2-derived-v1` namespace. Derived rows and compiled data are local plaintext, not encrypted or secure-erased. Each generation receives a flushed UUID/PID ownership marker before personal data is written. Runtime close ends tracked sessions, finalizes librime, then removes its generation. Failed post-construction verification uses the same order.

At startup a bounded scan examines at most 128 immediate children and removes at most sixteen recognized dead-PID generations. Deletion failures are reported without blocking fresh startup. Unknown markers, live/reused PIDs, inaccessible entries and generations beyond the scan budget can remain. This is best-effort crash cleanup, not guaranteed crash erasure. Corrupt-authority fallback uses a separate public-only temporary namespace and does not reuse old personal output. No source corpus, personal store, generated personal dictionary or real input is uploaded in CI artifacts.

## Resources and remaining verification

B2 adds no downloaded dependency. Source/license/digest pins remain in `Resources/a1-lock.json`, `Resources/dependency-notices.json`, `Resources/A2/upstream-lock.json`, `Licenses/` and generated A1/A2/B1 manifests. The authored B2 terms are synthetic mechanism fixtures, not unseen-data accuracy tests. The full Rime Ice core corpus remains unbundled research data; mixed-source production redistribution clearance is still unresolved. Personal imports imply no redistribution license.

Read [exact-head evidence and failures](../evidence/b2/VALIDATION.md). Tests separate store/fault simulations, real engine results and actual AppKit objects. The manager capture is a synthetic root view, not a desktop screenshot. Native labels and control actions are exercised; physical pointer/keyboard, VoiceOver, native file-panel completion/cancellation, appearance/size matrix, installed IMK clients and visible latency are not established. Persistent settings, full rare-character discovery, signed update/rollback/install/uninstall, expression storage and optional services remain later stages.
