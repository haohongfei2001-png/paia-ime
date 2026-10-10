#!/usr/bin/env python3
"""Source/fixture linkage, not native validation or publisher authentication."""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/ResourceCore/ResourcePreset.swift').read_text()
embedded=re.findall(r'files\["([^"]+)"\] = Data\(#"""\n(.*?)\n"""#\.utf8\) \+ Data\(\[10\]\)',source,re.S)
assert len(embedded)==3
for name,text in embedded:
    assert (text+'\n').encode()==(root/'Resources/Dictionaries/A1Fixture'/name).read_bytes(),name
lock=json.loads((root/'Resources/a1-lock.json').read_text())
contract=(root/'Sources/ResourceCore/ResourceManifest.swift').read_text()
assert 'engineSHA="'+lock['engine']['binarySha256']+'"' in contract
assert 'headerSHA="'+lock['headerSha256']+'"' in contract
assert 'deployer_initialize' not in (root/'Sources/EngineBridge/ResourceProbe.swift').read_text()
for path in (root/'Sources/ResourceCore').glob('*.swift'):
    for forbidden in ['import LexiconCore','import SettingsCore','import ExpressionCore','URLSession','NSPasteboard']:
        assert forbidden not in path.read_text(),(path,forbidden)
print('Resource source pins and original-fixture bytes verified; native compilation/probes require macOS CI.')
