#!/usr/bin/env python3
"""Explicit offline research tooling. Never called by product preparation or input."""
import argparse, gzip, hashlib, io, json, re, unicodedata, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RESOURCE=ROOT/'Resources/DictionaryExperiment'
FIELDS={'kMandarin','kHanyuPinyin'}
def digest(data):return hashlib.sha256(data).hexdigest()
def checked(data,item):
    if len(data)!=item['bytes'] or digest(data)!=item['sha256']:raise ValueError('input digest/size mismatch')
    return data
def snapshot(readings):
    text=readings.decode('utf-8')
    if '# Unicode Version 17.0.0\n' not in text:raise ValueError('wrong Unicode release')
    result=[]
    for number,line in enumerate(text.splitlines(),1):
        if line.startswith('#'):continue
        fields=line.split('\t')
        if len(fields)>=2 and fields[1] in FIELDS:
            if len(fields)!=3 or not re.fullmatch(r'U\+[0-9A-F]{4,6}',fields[0]):raise ValueError('invalid source record')
            result.append(f'{number}\t{line}\n')
    if not result:raise ValueError('empty reading source')
    return ''.join(result).encode('utf-8')
def pack(data):
    # GzipFile fixes OS=255 across supported Python/macOS/Linux versions.
    # The historical snapshot was Python 3.12 gzip.compress, whose OS byte=3.
    out=io.BytesIO()
    with gzip.GzipFile(fileobj=out,mode='wb',filename='',compresslevel=9,mtime=0) as stream:stream.write(data)
    result=bytearray(out.getvalue());result[9]=3
    return bytes(result)
def spelling(value):
    nfd=unicodedata.normalize('NFD',value.lower()).replace('u\u0308','v')
    # Circumflex ê is kept distinct from e by rejecting it, not silently aliased.
    nfd=''.join(c for c in nfd if c not in '\u0300\u0301\u0304\u030c')
    if not re.fullmatch('[a-zv]+',nfd):raise ValueError('unsupported reading')
    return nfd

def convert(data):
    rows=set();unsupported=[];previous=0;source_count=0
    for line in data.decode('utf-8').splitlines():
        fields=line.split('\t')
        if len(fields)!=4:raise ValueError('invalid snapshot columns')
        number,code,field,value=fields
        if not number.isdigit() or int(number)<=previous:raise ValueError('source line order')
        previous=int(number);source_count+=1
        if field not in FIELDS or not re.fullmatch(r'U\+[0-9A-F]{4,6}',code):raise ValueError('invalid snapshot identity')
        scalar=int(code[2:],16)
        if scalar>0x10ffff or 0xd800<=scalar<=0xdfff:raise ValueError('invalid scalar')
        if field=='kMandarin':readings=value.split()
        else:
            readings=[]
            for group in value.split():
                if not re.fullmatch(r'[0-9]{5}\.[0-9]{2,3}(?:,[0-9]{5}\.[0-9]{2,3})*:[^:]+',group):raise ValueError('invalid dictionary-location reading')
                readings.extend(group.split(':')[1].split(','))
        if not readings:raise ValueError('empty reading')
        for reading in readings:
            try:code_spelling=spelling(reading)
            except ValueError:unsupported.append({'sourceLine':previous,'codePoint':code,'reading':reading});continue
            rows.add((scalar,code_spelling))
    if not rows:raise ValueError('no usable readings')
    header='# Unicode 17 character-reading experiment; Unicode License V3; uniform weights, NOT frequency.\n---\nname: paia_unihan_experiment\nversion: "17.0.0"\nsort: original\n...\n'
    body=''.join(f'{chr(scalar)}\t{reading}\t1\n' for scalar,reading in sorted(rows))
    return (header+body).encode(),{'sourceRows':source_count,'uniqueCharacterReadings':len(rows),'unsupported':unsupported,'weightPolicy':'uniform 1, not corpus frequency','tonePolicy':'strip four Mandarin tone marks; ü to v; reject remaining non-ASCII including ê'}
def verify():
    lock=json.loads((RESOURCE/'source-lock.json').read_text())
    compressed=checked((RESOURCE/'unihan-reading-snapshot.tsv.gz').read_bytes(),lock['snapshot'])
    data=gzip.decompress(compressed);checked(data,lock['snapshotText'])
    checked((RESOURCE/'UNICODE-LICENSE-V3.txt').read_bytes(),lock['license'])
    dictionary,report=convert(data);checked(dictionary,lock['generatedDictionary'])
    return lock,data,dictionary,report

def main():
    p=argparse.ArgumentParser();p.add_argument('--archive',type=Path);p.add_argument('--output',type=Path);args=p.parse_args()
    lock,data,dictionary,report=verify()
    if args.archive:
        archive=checked(args.archive.read_bytes(),lock['archive'])
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            if z.namelist().count('Unihan_Readings.txt')!=1:raise ValueError('ambiguous readings member')
            readings=checked(z.read('Unihan_Readings.txt'),lock['readings'])
        rebuilt=snapshot(readings)
        if rebuilt!=data or pack(rebuilt)!=(RESOURCE/'unihan-reading-snapshot.tsv.gz').read_bytes():raise ValueError('snapshot not reproducible')
    if args.output:
        args.output.mkdir(parents=True,exist_ok=False)
        (args.output/'paia_unihan_experiment.dict.yaml').write_bytes(dictionary)
        (args.output/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
