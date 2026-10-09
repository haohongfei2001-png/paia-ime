from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'engineering/prototype-template.html').read_text(encoding='utf-8')
for marker,name in [('/*CORE*/','core.js'),('/*UI*/','ui.js')]:
    s=s.replace(marker,(root/'engineering'/name).read_text(encoding='utf-8'))
(root/'prototype.html').write_text(s,encoding='utf-8')
print('Built standalone, offline prototype.html')
