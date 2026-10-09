from pathlib import Path
import re, base64, html
from markdown_it import MarkdownIt
R=Path(__file__).resolve().parent.parent
text=(R/'REPORT.md').read_text()
# Plain public URLs become clickable resources, preserving source attribution.
text=re.sub(r'(?m)^(https?://[^\s]+)(\s*)$',lambda m:'<'+m.group(1)+'>'+m.group(2),text)
md=MarkdownIt('commonmark',{'html':True}).enable('table')
body=md.render(text)
nav=[]; index=0
def heading(m):
    global index
    index+=1;label=re.sub('<[^>]+>','',m.group(1));key=f'section-{index}'
    nav.append((key,label));return f'<h2 id="{key}">{m.group(1)}</h2>'
body=re.sub(r'<h2>(.*?)</h2>',heading,body)
# Keep report all-in-one so screenshots survive a standalone download.
images=[]
for n,label in [('typing','普通输入：固定示例候选'),('repair','句内修正：保留两侧的交互演示'),('recall','我的表达：原话、来源与全文插入'),('assist','选文修改：先预览，再应用'),('dark','深色模式：同一交互与层级')]:
    data=base64.b64encode((R/f'evidence/prototype-{n}.png').read_bytes()).decode()
    images.append(f'<figure><img loading="lazy" src="data:image/png;base64,{data}" alt="{label}"><figcaption>{label}。此图来自本次交付网页原型，不是已注册的Mac输入法。</figcaption></figure>')
gallery='<section class="gallery"><h2 id="gallery">交互原型 · 实际截图</h2><p>打开 prototype.html 可操作。以下为同一版本的真实浏览器截图；转换、历史和修改均为固定演示数据。</p>'+''.join(images)+'</section>'
body=body.replace('<h2 id="section-2">',gallery+'<h2 id="section-2">',1)
navhtml=''.join(f'<a href="#{key}">{html.escape(label)}</a>' for key,label in nav)
css='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:#263544;background:#f9f8f5;font:16px/1.95 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}a{color:#31658b;text-decoration:none;overflow-wrap:anywhere}a:hover{text-decoration:underline}aside{position:fixed;left:0;top:0;bottom:0;width:246px;overflow:auto;padding:28px 20px;background:#f1f1ed;border-right:1px solid #e3e5e4;font-size:12px;line-height:1.6}aside b{font-size:14px;display:block;margin-bottom:20px}aside a{display:block;margin:8px 0;color:#536676}main{overflow-wrap:anywhere;min-width:0;max-width:1150px;margin-left:246px;padding:62px 64px 96px}h1{font-size:38px;line-height:1.5;font-weight:600;letter-spacing:-.02em;margin:0 0 26px}h2{font-size:26px;font-weight:550;line-height:1.5;border-top:1px solid #dfe4e6;padding-top:38px;margin-top:50px;scroll-margin-top:20px}h3{font-size:20px;font-weight:550;margin-top:30px}p{margin:16px 0}strong{font-weight:650}table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.75;display:block;overflow:auto;margin:24px 0}th{background:#eef2f4;font-weight:600}th,td{border:1px solid #dce3e7;padding:11px 14px;text-align:left;vertical-align:top}th:first-child,td:first-child{min-width:95px}code{font:13px/1.6 ui-monospace,SFMono-Regular,Consolas,monospace;overflow-wrap:anywhere;background:#f0f2f4;padding:2px 4px;border-radius:4px}pre{background:#eef2f4;border-radius:10px;padding:20px;overflow:auto}pre code{background:none;padding:0;white-space:pre}ul,ol{padding-left:24px}figure{margin:28px 0;background:white;border:1px solid #e0e5e7;border-radius:10px;overflow:hidden}figure img{display:block;width:100%;height:auto}figcaption{font-size:12px;line-height:1.7;color:#667989;padding:12px 17px}.toplinks{display:flex;gap:14px;flex-wrap:wrap;font-size:13px;margin-bottom:35px}.toplinks a{padding:7px 12px;border:1px solid #ccdce5;border-radius:6px;background:#f5f9fc}.stamp{font-size:11px;color:#75838a;letter-spacing:.12em;margin-bottom:22px}.gallery{margin-top:36px}body:has(:target){}@media(max-width:1000px){aside{position:static;width:auto;max-height:210px;border-bottom:1px solid #dde3e6;padding:20px}aside a{display:inline-block;margin:3px 10px 3px 0}main{margin:0;padding:32px 24px}h1{font-size:30px}}@media print{aside,.toplinks{display:none}main{margin:0;padding:0;max-width:none}body{font-size:11pt;background:white}h1{font-size:25pt}h2{font-size:18pt;break-after:avoid}h3{break-after:avoid}table{font-size:9pt}figure{break-inside:avoid}a{color:inherit}pre{white-space:pre-wrap}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}'''
page='<!doctype html><html lang="zh-CN"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'"><title>Mac 原生中文输入法 · 旗舰研究与设计</title><style>'+css+'</style><aside><b>Mac 输入法 / 旗舰研究</b><a href="#gallery">原型实际截图</a>'+navhtml+'</aside><main><div class="stamp">PRODUCT × ENGINEERING · RESEARCH EDITION · 2026.10</div><div class="toplinks"><a href="prototype.html">打开交互原型</a><a href="CODEX_HANDOFF.md">Codex 工程交接</a><a href="VALIDATION.md">验证与限制</a></div>'+body+'</main></html>'
(R/'REPORT.html').write_text(page)
print('REPORT.html',len(page),'characters')
