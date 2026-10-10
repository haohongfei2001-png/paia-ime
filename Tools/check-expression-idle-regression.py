#!/usr/bin/env python3
"""Isolated CI mutation: prove the retained late-selection regression fails.
No install, server startup, profile or private text. Restore the exact source in finally.
"""
from pathlib import Path
import re, subprocess
path=Path('Sources/IMKHost/IMKSessionCoordinator.swift')
original=path.read_text()
start=original.index('        guard mark.length==0 else{return false}\n        // Idle expressions')
end=original.index('\n    }\n    public func hasCurrentTarget',start)
mutant=original[:start]+'        return mark.length==0'+original[end:]
try:
    path.write_text(mutant)
    result=subprocess.run(['swift','test','--filter','ExpressionIMKTests.ExpressionIMKTests/testStagedMarkedRangeCallbackSelectionChangeIsRefusedBeforeInsert'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    Path('evidence/expression-run/idle-regression-mutant.txt').write_text(result.stdout)
    print(result.stdout)
    assert result.returncode!=0, 'Unsafe former idle observation unexpectedly passed'
    assert re.search(r'Executed 1 test, with [1-9][0-9]* failures',result.stdout), 'Did not execute the expected failing native test'
    assert 'XCTAssertEqual failed: ("1") is not equal to ("0")' in result.stdout, 'Expected unsafe insertion was not observed'
    print('EXPRESSION_IDLE_REGRESSION_RED: former idle verifier issued one unsafe insert; failing fixture retained')
finally:
    path.write_text(original)
    assert path.read_text()==original
