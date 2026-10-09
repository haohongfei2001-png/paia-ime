#!/usr/bin/env python3
"""Narrow source/resource guard, not a runtime network interception claim."""
from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]
lock=json.loads((r/'Resources/a1-lock.json').read_text())
for item in lock['files']:
 assert hashlib.sha256((r/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']
for p in (r/'Sources').rglob('*'):
 if p.suffix not in ('.swift','.c'):continue
 text=p.read_text()
 for forbidden in ['URLSession','NSURLConnection','CGEvent','AXUIElement','UserDefaults','NSPasteboard','print(effect','print(value','NSLog(']:
  assert forbidden not in text,(p,forbidden)
assert 'enable_user_dict: false' in (r/'Resources/Dictionaries/A1Fixture/paia_a1.schema.yaml').read_text()
assert 'IMKServer(' not in (r/'Sources/NativeIME/main.swift').read_text()
print('A1 static privacy/resource checks passed; no runtime traffic claim or installed-IME evidence.')
