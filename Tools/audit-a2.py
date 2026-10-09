#!/usr/bin/env python3
"""Static source/lock checks; not proof of whole-machine runtime network absence."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
lock=json.loads((root/'Resources/A2/upstream-lock.json').read_text())
assert lock['totalDefaultChineseDictionaryRows']==1873509
for item in lock['resources']+lock['privateHeaders']:
    assert len(item['sha256'])==64 and item['url'].startswith('https://raw.githubusercontent.com/')
    assert 'localPath' not in item
assert lock['boost']['sha256']=='9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93'
for p in list((root/'Sources').rglob('*'))+list((root/'Tools/G01Bridge').rglob('*')):
    if p.suffix not in ('.c','.cc','.swift'):continue
    text=p.read_text()
    for forbidden in ['URLSession','NSURLConnection','CGEvent','AXUIElement','UserDefaults','NSPasteboard','NSLog(']:
        assert forbidden not in text,(str(p),forbidden)
prepare=(root/'Tools/prepare-a2.py').read_text()
assert 'enable_user_dict: false' in prepare # _no_learning alone is not an upstream learning guard.
assert 'enable_word_completion: true' in prepare
assert 'max_sentences:' not in prepare # requires newer upstream; exact binary is 1.16.0.
print('A2 static pin/privacy checks passed; no installed-IME or runtime-traffic claim.')
