#!/usr/bin/env python3
"""Detect reconstruction of erased established stores; restore every source."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
paths=[root/'Sources'/path for path in ['SettingsCore/SettingsStore.swift','LexiconCore/LexiconStore.swift','ExpressionCore/ExpressionStore.swift']]
original={path:path.read_bytes() for path in paths}
protected='O_RDWR|(allowCreateLock ? O_CREAT:0)|O_NOFOLLOW'
try:
    for path,data in original.items():
        text=data.decode();assert text.count(protected)==1
        path.write_text(text.replace(protected,'O_RDWR|O_CREAT|O_NOFOLLOW'))
    result=subprocess.run(['swift','test','--filter','ProductDataTests/testEstablishedSlotLosingAllStoreFilesCannotBecomeFresh'],cwd=root,capture_output=True,text=True,timeout=180)
    sys.stdout.write(result.stdout);sys.stdout.write(result.stderr)
    assert result.returncode!=0 and 'XCTAssertThrowsError failed' in result.stdout+result.stderr,'former empty-store reconstruction was not detected'
finally:
    for path,data in original.items():path.write_bytes(data)
assert all(path.read_bytes()==data for path,data in original.items())
print('PRODUCT_EMPTY_REGRESSION expected red without established-store lock guard; all exact sources restored')
