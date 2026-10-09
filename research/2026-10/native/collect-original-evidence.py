#!/usr/bin/env python3
"""Copy only this study's generated evidence from its known isolated Mac directory.
No profiles, input histories, installed bundles, credentials, or PAIA files are read.
The destination must be NEW. This script does not rerun or install an input method.
"""
from pathlib import Path
import argparse, hashlib, json, shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination',type=Path,help='New directory for original study files')
parser.add_argument('--source',type=Path,default=Path('/tmp/mac-ime-research-20261009-mPkcSY'))
a=parser.parse_args()
files=['NativeProbe.swift','native-results.json','rime_probe.py','rime-results.json',
       'rime_overlay_probe.py','rime-overlay-results.json','dictionary-ablation.json',
       'ModelAvailabilityProbe.swift','model-availability.txt','fixture-audit.md',
       'rime_probe_v0.py','rime-results-v0.json']
expected={
 'NativeProbe.swift':'b3bee608c1f5442da158a690898bf69f5469bc8ef848b6c3dceb81c3b1f2a05e',
 'native-results.json':'dbb195ee4360ff04af3e0b0e89f01c89cfe9f15eeeaa837e0af05dfba053b60d',
 'rime_probe.py':'9049b77bbf918343e5dbfe2efd9b2434297fc498a72e4dc2b94792db6245688f',
 'rime-results.json':'995254f2998c3be684035e01916225c8223d7b2fb7190234df52fb1820a1697e',
 'ModelAvailabilityProbe.swift':'c9c7b0203cdef69983b7546e187e0caf096cc453fa84ffcf3b9cbc16312ab952',
 'model-availability.txt':'51d0e44ca67ce46311df427afed07c90f9b33b1f8118a7440c958bc6813719ca'}
if a.destination.exists():parser.error('Destination already exists. Choose a new directory; no files overwritten.')
if not a.source.is_dir():parser.error('Original isolated research directory is unavailable. Do not substitute a private profile.')
payload={}
for name in files:
    p=a.source/name
    if p.is_symlink() or not p.is_file():parser.error('Missing or non-regular study file: '+name)
    data=p.read_bytes();digest=hashlib.sha256(data).hexdigest()
    if name in expected and digest!=expected[name]:parser.error('Evidence hash mismatch: '+name)
    payload[name]=(data,digest)
a.destination.mkdir(parents=True,exist_ok=False)
for name,(data,_) in payload.items():(a.destination/name).write_bytes(data)
(a.destination/'collected-hashes.json').write_text(json.dumps({name:digest for name,(_,digest) in payload.items()},indent=2)+'\n')
print(f'Copied {len(payload)} explicitly named study files. No installation or runtime configuration changed.')
