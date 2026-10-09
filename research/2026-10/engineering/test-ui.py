"""Offline Chromium interaction tests. No live IME, model, PAIA or user data."""
from pathlib import Path
import json, hashlib, datetime, traceback
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parent.parent
source=(R/'prototype.html').read_text()
results=[]; requests=[]; errors=[]
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
    ctx=browser.new_context(viewport={'width':1440,'height':1000},device_scale_factor=1)
    page=ctx.new_page();page.set_default_timeout(1800)
    page.on('request',lambda r:requests.append(r.url))
    page.on('pageerror',lambda e:errors.append(str(e)))
    def reset():
        page.goto('about:blank')
        page.set_content(source,wait_until='load')
    def scene(x):
        page.keyboard.press('Escape')
        page.locator('[data-scene="'+x+'"]').click()
    def check(name,fn):
        try:fn();results.append({'name':name,'passed':True});print('PASS',name,flush=True)
        except Exception as e:
            results.append({'name':name,'passed':False,'error':str(e)});print('FAIL',name,str(e)[:300],flush=True)
        (R/'evidence/ui-progress.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
    def demand(v,msg='assertion failed'):
        if not v:raise AssertionError(msg)
    def compose(raw='shiyan'):
        scene('typing');page.locator('#raw').fill(raw)
    def selected_draft(text):
        page.locator('#draft').fill(text)
        page.locator('#draft').evaluate('(e)=>{e.focus();e.setSelectionRange(0,e.value.length);e.dispatchEvent(new Event("select"));}')
    reset()
    check('initial-candidate-hidden',lambda:demand(not page.locator('#candidatePanel').is_visible()))
    def candidate_space():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').press('Space');demand(page.locator('#draft').input_value()==b+'实验');demand(page.locator('#raw').input_value()=='')
    check('real-key-space-inserts-fixture-once',candidate_space)
    def candidate_number():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').press('2');demand(page.locator('#draft').input_value()==b+'试验')
    check('number-key-selects-displayed-row',candidate_number)
    def candidate_arrow():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').press('ArrowDown');page.locator('#raw').press('Space');demand(page.locator('#draft').input_value()==b+'试验')
    check('arrow-highlight-then-space',candidate_arrow)
    def candidate_tab():
        compose();page.locator('#raw').press('Tab');demand(page.locator('#candidateList [aria-selected="true"]').inner_text().endswith('试验'))
    check('composition-tab-belongs-to-fixture-selector',candidate_tab)
    def raw_enter():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').press('Enter');demand(page.locator('#draft').input_value()==b+'shiyan')
    check('return-retains-raw-no-form-send',raw_enter)
    def escape():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').press('Escape');demand(page.locator('#draft').input_value()==b);demand(page.locator('#raw').input_value()=='')
    check('escape-does-not-delete-committed-draft',escape)
    def limit():
        compose();b=page.locator('#draft').input_value();page.locator('#raw').fill('a'*513);page.locator('#raw').press('Space');demand(page.locator('#draft').input_value()==b);demand(len(page.locator('#raw').input_value())>=513)
    check('oversize-input-cannot-select-old-candidate',limit)
    def no_panel_during_native():
        compose();page.locator('#raw').dispatch_event('compositionstart');demand(not page.locator('#candidatePanel').is_visible());b=page.locator('#draft').input_value();page.locator('#raw').press('Enter');demand(page.locator('#draft').input_value()==b);page.locator('#raw').dispatch_event('compositionend')
    check('synthetic-native-composition-fence',no_panel_during_native)
    def recall_block():
        compose();page.locator('#openRecall').click();demand(not page.locator('#recallPanel').is_visible());demand(page.locator('#raw').input_value()=='shiyan')
    check('recall-does-not-auto-commit-pending-pinyin',recall_block)
    def recall_full():
        scene('recall');b=page.locator('#draft').input_value();text=page.locator('#expressionPreview').inner_text();page.locator('#insertExpression').click();demand(page.locator('#draft').input_value()==b+text);demand(text.endswith('不要把假设写成结论。'))
    check('recall-inserts-exact-full-terminal-negation',recall_full)
    def recall_none():
        scene('recall');page.locator('#query').fill('never-found-82736');demand(page.locator('#insertExpression').is_disabled());demand('不会生成' in page.locator('#results').inner_text())
    check('recall-empty-does-not-fabricate-history',recall_none)
    def recall_stale():
        reset();scene('recall');page.locator('.lab').evaluate('(e)=>e.open') or page.locator('.lab summary').click();page.locator('#drift').click();b=page.locator('#draft').input_value();page.locator('#insertExpression').click();demand(page.locator('#draft').input_value()==b);demand('已经改变' in page.locator('#toast').inner_text())
    check('recall-refuses-host-text-drift',recall_stale)
    def recall_target():
        reset();scene('recall');page.locator('.lab').evaluate('(e)=>e.open') or page.locator('.lab summary').click();page.locator('#targetDrift').click();b=page.locator('#draft').input_value();page.locator('#insertExpression').click();demand(page.locator('#draft').input_value()==b)
    check('recall-refuses-new-target',recall_target)
    def recall_cancel():
        scene('recall');page.locator('#query').press('Escape');demand(not page.locator('#recallPanel').is_visible());demand(page.locator('#expressionPreview').inner_text()=='')
    check('recall-cancel-clears-private-preview',recall_cancel)
    def private():
        scene('private');page.locator('#raw').fill('linxiaotang');demand(page.locator('#candidateList button').first.inner_text().endswith('林小唐'));page.locator('#openRecall').click();demand(not page.locator('#recallPanel').is_visible())
    check('private-mode-keeps-basic-input-no-personal-recall',private)
    def assist_apply():
        scene('assist');page.locator('#applyAssist:not([disabled])').wait_for(state='visible');page.locator('#applyAssist').click();demand(page.locator('#draft').input_value()=='请检查实验报告，预算为12.5万元，不要改变结论。');demand(page.locator('#revisedText').get_attribute('data-result') is None)
    check('selected-edit-preserves-number-negation-clears-result',assist_apply)
    def assist_stale():
        scene('assist');page.locator('#applyAssist:not([disabled])').wait_for(state='visible');page.locator('.lab').evaluate('(e)=>e.open') or page.locator('.lab summary').click();page.locator('#drift').click();b=page.locator('#draft').input_value();page.locator('#applyAssist').click();demand(page.locator('#draft').input_value()==b);demand('拒绝' in page.locator('#assistStatus').inner_text())
    check('selected-edit-refuses-text-drift',assist_stale)
    def assist_selection():
        scene('assist');page.locator('#applyAssist:not([disabled])').wait_for(state='visible');page.locator('#draft').evaluate('(e)=>{e.setSelectionRange(0,2);e.dispatchEvent(new Event("select"));}');b=page.locator('#draft').input_value();page.locator('#applyAssist').click();demand(page.locator('#draft').input_value()==b)
    check('selected-edit-refuses-selection-drift',assist_selection)
    def unavailable():
        reset();page.locator('.lab').evaluate('(e)=>e.open') or page.locator('.lab summary').click();page.locator('#modelUnavailable').check();scene('assist');demand('模型不可用' in page.locator('#assistStatus').inner_text());demand(page.locator('#applyAssist').is_disabled());demand('实脸' in page.locator('#draft').input_value())
    check('model-unavailable-no-cloud-fallback',unavailable)
    def late():
        reset();scene('assist');scene('private');page.wait_for_timeout(600);demand(not page.locator('#assistPanel').is_visible());demand(page.locator('#revisedText').inner_text()=='');demand(page.locator('#revisedText').get_attribute('data-result') is None)
    check('late-synthetic-result-cannot-revive-after-private',late)
    def save():
        scene('typing');selected_draft('本次只改实脸，不要改12.5。');page.locator('#saveSelection').click();page.locator('#confirmSave').click();page.locator('#openRecall').click();page.locator('#query').fill('本次只改');demand(page.locator('#expressionPreview').inner_text()=='本次只改实脸，不要改12.5。');demand('未发送确认' in page.locator('#results').inner_text())
    check('explicit-save-retains-original-not-sent-event',save)
    def remove():
        page.locator('#deleteExpression').click();demand(page.locator('#insertExpression').is_disabled())
    check('remove-expression-cannot-be-recalled-again',remove)
    def repair():
        scene('repair');page.locator('#repairchoices button').nth(1).click();demand(page.locator('#segments').inner_text().replace('\n','')=='我在烟酒形状因子');page.locator('#repairchoices button').first.click();demand(page.locator('#segments').inner_text().replace('\n','')=='我在研究形状因子')
    check('local-span-specimen-keeps-both-other-segments',repair)
    def onboard():
        page.locator('#onboarding').click();demand('1 / 3' in page.locator('#onstep').inner_text());page.locator('#onnext').click();page.locator('#onnext').click();page.locator('#onnext').click();demand(not page.locator('#onboardModal').is_visible())
    check('three-onboarding-pages-complete-without-install',onboard)
    def modal():
        page.locator('#settings').click();page.keyboard.press('Escape');demand(not page.locator('#settingsModal').is_visible());demand(page.evaluate('document.activeElement.id')=='raw')
    check('settings-escape-restores-input-focus',modal)
    # Screenshots are new captures of this exact source. Layout matrix only checks viewport containment.
    for width,height in [(1440,1000),(1280,800),(768,900),(390,844),(320,640)]:
        page.set_viewport_size({'width':width,'height':height})
        for theme in ['light','dark']:
            page.evaluate('(x)=>document.documentElement.dataset.theme=x',theme)
            for state,panel in [('typing','candidatePanel'),('recall','recallPanel'),('assist','assistPanel')]:
                reset();page.evaluate('(x)=>document.documentElement.dataset.theme=x',theme)
                scene(state)
                if state=='typing':page.locator('#raw').fill('shiyan')
                page.wait_for_timeout(100)
                def geometry(panel=panel):
                    box=page.locator('#'+panel).bounding_box();demand(box is not None)
                    demand(box['x']>=-1 and box['y']>=-1 and box['x']+box['width']<=width+1 and box['y']+box['height']<=height+1,str(box))
                check(f'layout-{width}x{height}-{theme}-{state}',geometry)
    page.set_viewport_size({'width':1440,'height':1000});reset()
    for name,state in [('typing','typing'),('repair','repair'),('recall','recall'),('assist','assist')]:
        scene(state)
        if state=='typing':page.locator('#raw').fill('shiyan')
        page.wait_for_timeout(500 if state=='assist' else 120)
        page.screenshot(path=str(R/'evidence'/f'prototype-{name}.png'),full_page=True)
    scene('typing');page.locator('#theme').click();page.locator('#raw').fill('shiyan');page.wait_for_timeout(120);page.screenshot(path=str(R/'evidence/prototype-dark.png'),full_page=True)
    check('no-page-runtime-errors',lambda:demand(not errors,str(errors)))
    check('zero-network-requests-during-test',lambda:demand(not requests,str(requests)))
    out={'kind':'standalone offline HTML prototype; fixed fixture conversion and fixed edit, not native IME/AI/PAIA','generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'browser':browser.version,'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'total':len(results),'requests':requests,'page_errors':errors,'cases':results}
    (R/'evidence/ui-results.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
    print(json.dumps({**out,'cases':[r for r in results if not r['passed']]},ensure_ascii=False,indent=2));browser.close()
    raise SystemExit(1 if out['failed'] else 0)
