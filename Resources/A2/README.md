# A2 research resource boundary

Rime Ice core-only adaptation, not stock Rime Ice. The full five default Chinese dictionaries (1,873,509 rows) retain upstream order and frequencies. Build-time cache only: no corpus or compiled dictionary is bundled in apps, commits, CI artifacts or recovery archives. No benchmark answer is appended.

Pin: iDvel/rime-ice `da1fbe602e38f26db846fa10120ee64c2b0324c0`, 2026-10-05. GPL-3.0-only declaration and heterogeneous attribution retained in the lock and Licenses/a2. Mixed imported-source rights are **not production-redistribution cleared** (notably Wiktionary/BLCU imported revisions/grants, one common-word source, and Tencent historical grant verification).

The preparation script derives only spelling algebra/preedit rules from pinned GPL schemas into ignored research data. It excludes Lua, English/radical dictionaries, optional grammar model and plugins. Traditional output is standard OpenCC s2t from the simplified corpus; it is not Taiwan-localized or a Traditional-native dictionary. OpenCC text-config adaptation changes only file format references, not conversion mappings.

The typed C++ extension is bound to the exact A1 binary, source headers, Boost and libc++ ABI. The generated bridge-only build_config.h disables logging includes without changing object member layout. This is a private version-specific research interface, not a stable librime extension API.

The later closed B1 spelling policies preserve the original A2 comparator.
`spelling-policy.json` records the exact 37 active full-Pinyin typo derivations
and four explicitly named fuzzy-initial derivations from the same pinned GPL
schema. It is derived schema code, not a new corpus. Corresponding upstream
notices remain in `Licenses/a2`. Independent policy prisms are build-time only;
default legacy spelling and double-Pinyin typo behavior are unchanged. A separate
27-row authored HabitFixture is used only for exhaustive bounded rule controls,
never appended to the research dictionary or bundled as production vocabulary.
