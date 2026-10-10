"""Closed build-time policies over the already hash-verified research speller.

Regex recipes derive from pinned Rime Ice (GPL-3.0-only), identified in the JSON.
Nothing here runs per key, accepts user rules or modifies the A2 comparator.
"""
from pathlib import Path
import json,re

POLICY=json.loads((Path(__file__).resolve().parents[1]/'Resources/A2/spelling-policy.json').read_text())
FUZZY=POLICY['fuzzyInitials']
TYPO=POLICY['fullPinyinTypo']

def suffix(kind,fuzzy=False,correction=True):
    if kind not in ('full','flypy','natural') or type(fuzzy) is not bool or type(correction) is not bool:
        raise ValueError('closed spelling policy required')
    return ('_fuzzy' if fuzzy else '')+('_strict' if kind=='full' and not correction else '')

def variants(kind):
    return [(fuzzy,correction) for fuzzy in (False,True) for correction in ((True,False) if kind=='full' else (True,))]

def speller(text,kind,fuzzy=False,correction=True):
    suffix(kind,fuzzy,correction)
    if text.count('  algebra:\n')!=1:raise ValueError('missing unique speller algebra')
    result=text
    if kind=='full':
        marker='### 自动纠错'
        if text.count(marker)!=1:raise ValueError('unexpected pinned correction section')
        head,tail=text.split(marker)
        lines=tail.splitlines(keepends=True)
        active=[re.match(r'^\s*-\s+(derive/\S+)',line).group(1) for line in lines if re.match(r'^\s*-\s+(derive/\S+)',line)]
        if active!=TYPO or len(active)!=37:raise ValueError('pinned typo rules changed')
        if not correction:
            result=head+marker+''.join(line for line in lines if not re.match(r'^\s*-\s+derive/',line))
        # Orthographic v/u aliases and existing abbreviations precede the typo block.
        if not result.startswith(head+marker):raise ValueError('orthographic rules changed')
    if fuzzy:
        result=result.replace('  algebra:\n','  algebra:\n'+''.join('    - '+rule+'\n' for rule in FUZZY),1)
    if not fuzzy and (correction or kind!='full') and result!=text:raise ValueError('legacy spelling changed')
    return result
