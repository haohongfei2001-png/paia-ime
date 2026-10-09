'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),crypto=require('node:crypto'),path=require('node:path');
const K=require('./core.js'),checks=[];function test(name,f){try{f();checks.push({name,passed:true});}catch(e){checks.push({name,passed:false,error:String(e)});}}
function fresh(raw='shiyan'){const s=new K.Session();s.setRaw(raw);s.refresh();return s;}
test('space-ready-selects-first-fixture',()=>{const s=fresh();assert.equal(s.choose().text,'实验');assert.equal(s.raw,'');});
test('number-selects-exact-frozen-row',()=>assert.equal(fresh().choose(1).text,'试验'));
test('invalid-row-does-not-commit',()=>{const s=fresh();assert.equal(s.choose(9),null);assert.equal(s.raw,'shiyan');});
test('candidate-list-is-frozen',()=>assert.throws(()=>{fresh().snapshot.rows[0].text='tamper';}));
test('same-generation-late-ranking-cannot-move-target',()=>{const s=fresh();assert.equal(s.publish(s.request(),K.candidates('nihao')),false);assert.equal(s.choose().text,'实验');});
test('old-raw-response-refused',()=>{const s=fresh(),t=s.request();s.setRaw('nihao');assert.equal(s.publish(t,K.candidates('shiyan')),false);});
test('old-caret-response-refused',()=>{const s=fresh(),t=s.request();s.move(-1);assert.equal(s.publish(t,K.candidates('shiyan')),false);});
test('old-target-response-refused',()=>{const s=fresh(),t=s.request();s.targetChanged();s.setRaw('shiyan');assert.equal(s.publish(t,K.candidates('shiyan')),false);});
test('privacy-revokes-old-response',()=>{const s=fresh(),t=s.request();s.privacy(true);assert.equal(s.publish(t,K.candidates('shiyan')),false);});
test('private-generic-name-does-not-use-personal-fixture',()=>{const s=fresh('linxiaotang');s.privacy(true);s.refresh();assert.equal(s.choose().text,'林小唐');});
test('private-recall-abbreviation-not-used',()=>assert.equal(K.candidates('qwxg',true)[0].text,'全无心肝'));
test('return-raw-is-explicit-not-send',()=>{const s=fresh(),e=s.commit(s.raw);assert.equal(e.text,'shiyan');assert.equal(e.send,false);});
test('escape-only-clears-uncommitted',()=>{const s=fresh();s.cancel();assert.equal(s.choose(),null);assert.equal(s.raw,'');});
test('unknown-raw-has-literal-fallback',()=>assert.equal(K.candidates('zzunknown')[0].text,'zzunknown'));
test('mid-string-insert',()=>{const s=fresh('shyan');s.setRaw(s.raw,2);s.insert('i');assert.equal(s.raw,'shiyan');});
test('backspace-from-caret',()=>{const s=fresh();s.setRaw(s.raw,3);s.backspace();assert.equal(s.raw,'shyan');});
test('left-boundary-no-underflow',()=>{const s=fresh();s.move(-500);s.backspace();assert.equal(s.caret,0);assert.equal(s.raw,'shiyan');});
test('suspend-refuses-effects',()=>{const s=fresh();s.suspend();assert.equal(s.commit('实验'),null);});
test('resume-owns-new-target',()=>{const s=fresh(),t=s.targetEpoch;s.suspend();s.resume();assert.ok(s.targetEpoch>t);assert.equal(s.suspended,false);});
test('reject-oversize-raw',()=>{const s=fresh();assert.equal(s.setRaw('a'.repeat(513)).ok,false);});
test('duplicate-row-identity-rejected',()=>{const s=new K.Session();s.setRaw('a');const r={id:'a',text:'甲',engineIndex:0};assert.equal(s.publish(s.request(),[r,r]),false);});
test('invalid-engine-index-rejected',()=>{const s=new K.Session();s.setRaw('a');assert.equal(s.publish(s.request(),[{id:'a',text:'甲',engineIndex:-1}]),false);});
test('effect-only-once',()=>{const s=fresh(),e=s.choose(),sink=new K.EffectSink();let body='';assert.equal(sink.apply(e,s.targetEpoch,x=>body+=x),true);assert.equal(sink.apply(e,s.targetEpoch,x=>body+=x),false);assert.equal(body,'实验');});
test('wrong-target-no-effect',()=>{const s=fresh(),sink=new K.EffectSink();assert.equal(sink.apply(s.choose(),99,()=>assert.fail()),false);});
test('unknown-write-outcome-does-not-auto-retry',()=>{const s=fresh(),e=s.choose(),sink=new K.EffectSink();assert.throws(()=>sink.apply(e,s.targetEpoch,()=>{throw Error('ack lost');}));assert.equal(sink.apply(e,s.targetEpoch,()=>assert.fail()),false);});
const before={target:1,epoch:4,privacy:0,text:'A👩🏽‍💻实脸报告，不要改变结论。',start:8,end:12};
test('nonempty-explicit-selection-required',()=>assert.equal(K.makeLease({...before,end:before.start}),null));
test('unchanged-lease-admitted',()=>assert.equal(K.validateLease(K.makeLease(before),before),true));
for(const field of ['target','epoch','privacy','text','start','end'])test('changed-'+field+'-refused',()=>assert.equal(K.validateLease(K.makeLease(before),{...before,[field]:typeof before[field]==='number'?before[field]+1:before[field]+'x'}),false));
test('expired-lease-refused',()=>assert.equal(K.validateLease(K.makeLease(before),before,30000),false));
test('apply-preserves-prefix-suffix',()=>{const l=K.makeLease(before);assert.equal(K.applyLease(l,before,'实验报告'),before.text.slice(0,8)+'实验报告'+before.text.slice(12));assert.equal(K.applyLease(l,before,'again'),null);});
test('final-body-budget-refused-without-consuming',()=>{const c={...before,text:'a'.repeat(200000),start:1,end:2},l=K.makeLease(c);assert.equal(K.applyLease(l,c,'b'.repeat(2)),null);assert.equal(l.used,false);});
test('input-evidence-is-not-message-evidence',()=>{for(const x of ['key','composition','commit'])assert.equal(K.evidenceState(x),'not_sent');assert.equal(K.evidenceState('send_click'),'intent_only');assert.equal(K.evidenceState('rendered_user_message'),'observed_message');assert.equal(K.evidenceState('server_ack'),'protocol_confirmed');});
test('invalid-screen-refuses-anchor',()=>{assert.equal(K.placePanel({x:0,y:0,height:10},{width:100,height:50},{x:0,y:0,width:12,height:12}),null);});
let geometryCases=0;
for(const width of [320,390,768,1280,1920])for(const height of [320,600,900])for(const ox of [-1920,0])for(const location of [0,.5,1])for(const size of [{width:280,height:88},{width:410,height:390},{width:520,height:850}]){
 const screen={x:ox,y:0,width,height},p=K.placePanel({x:ox+width*location,y:height*location,height:22},size,screen);geometryCases++;
 test('geometry-'+geometryCases,()=>{assert.ok(p);assert.ok(p.x>=ox+8);assert.ok(p.y>=8);assert.ok(p.x+p.width<=ox+width-8+.001);assert.ok(p.y+p.height<=height-8+.001);});
}
const output={kind:'synthetic reference-kernel tests; not native IMK or Chinese-engine validation',generated_at:new Date().toISOString(),node:process.version,source_sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'core.js'))).digest('hex'),checks:checks.length,geometry_cases:geometryCases,passed:checks.filter(x=>x.passed).length,failed:checks.filter(x=>!x.passed).length,cases:checks};
fs.writeFileSync(path.join(__dirname,'../evidence/core-results.json'),JSON.stringify(output,null,2));console.log(JSON.stringify({...output,cases:checks.filter(x=>!x.passed)},null,2));process.exitCode=output.failed?1:0;
