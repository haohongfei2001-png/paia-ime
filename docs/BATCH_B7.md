# Batch B7: explicit known-character entry

Planned bounded scope: a caret-only native inspector for one known Unicode scalar, with an always-readable U+ identifier/name, system-font glyph preview, and separate explicit Insert/Cancel. This is not pronunciation/radical discovery, arbitrary sequence insertion, a font installation or selected-text replacement. It uses the existing inspector owner, target lease and single HostDispatcher commit path; ordinary input remains non-learning.

Accept U+ followed by 1–6 ASCII hexadecimal digits, or one literal scalar. Refuse control, format, unassigned/private-use, separator/mark, default-ignorable/noncharacter and explicitly blank symbol values. Do not trim or normalize. A visible identifier does not imply the platform has a glyph.

The initial checkpoint adds a failing target-identity regression before implementation: Swift String equality treats U+212B and U+00C5 as canonically equivalent, but externally changing one to the other must invalidate a prepared host effect. Exact text identity, caret boundaries, stale/reentrant callbacks, shared mode/settings/repair barriers and true native insertion will be tested before acceptance.

No new dictionary, model, font, service, input-source registration, private profile or persistent data is introduced. Native CI and actual captures, not planning text, determine completion.
