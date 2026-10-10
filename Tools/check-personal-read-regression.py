#!/usr/bin/env python3
"""Prove the former post-read authority gap, then restore exact source bytes."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
source=root/'Sources/LexiconCore/LexiconStore.swift';original=source.read_bytes()
text=original.decode();start=text.index('        var after=stat(),linked=stat()\n',text.index('try afterReadBeforeVerification?(name)'))
end=text.index('        return data\n',start)
assert 'fstatat(rootFD,name' in text[start:end]
try:
    source.write_text(text[:start]+text[end:])
    result=subprocess.run(['swift','test','--filter','ProductDataTests/testPersonalAuthorityReplacedDuringReadCannotReturnOldSnapshot'],cwd=root,capture_output=True,text=True,timeout=180)
    sys.stdout.write(result.stdout);sys.stdout.write(result.stderr)
    assert result.returncode!=0 and 'XCTAssertThrowsError failed' in result.stdout+result.stderr,'former read-race guard removal was not detected'
finally:
    source.write_bytes(original)
assert source.read_bytes()==original
print('PERSONAL_READ_REGRESSION expected red without post-read identity check; exact source restored')
