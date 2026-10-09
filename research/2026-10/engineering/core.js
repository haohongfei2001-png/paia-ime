/* Original research reference kernel. NOT a pinyin engine, IMK server or PAIA client. */
(function(root){
'use strict';
const fixtures=Object.freeze({
  shiyan:['实验','试验','饰演','食盐','誓言'],
  nihao:['你好','妳好','拟好','你','逆号'],
  yanjiu:['研究','烟酒','眼睛','研修','验旧'],
  shujuku:['数据库','数据','书局'],
  shurufa:['输入法','输入'],
  linxiaotang:['林小棠','林小唐','林夕'],
  qwxg:['请勿修改','全无心肝','权威性'],
  liangzichanglun:['量子场论','量子'],
  wozaiyanjiuxingzhuangyinzi:['我在研究形状因子','我在研究形状音字'],
  mingtiantijiaoshiyanbaogao:['明天提交实验报告','明天提交试验报告']
});
function candidates(raw,privateMode=false){
 let out=fixtures[raw];
 if(privateMode&&raw==='linxiaotang')out=['林小唐','林夕'];
 if(privateMode&&raw==='qwxg')out=['全无心肝','权威性'];
 return (out||[raw]).filter(Boolean).map((text,index)=>({id:'fixture:'+raw+':'+index,text,engineIndex:index,role:out?'fixture':'literal',span:[0,raw.length]}));
}
class Session{
 constructor(){this.targetEpoch=1;this.generation=0;this.privacyEpoch=0;this.privateMode=false;this.raw='';this.caret=0;this.snapshot=null;this.highlight=0;this.operation=0;this.suspended=false;}
 setRaw(raw,caret=raw.length){
  if(typeof raw!=='string'||raw.length>512)return {ok:false,reason:'input_limit'};
  if(!Number.isInteger(caret)||caret<0||caret>raw.length)return {ok:false,reason:'invalid_caret'};
  if(raw===this.raw&&caret===this.caret)return {ok:true,changed:false};
  this.raw=raw;this.caret=caret;this.generation++;this.snapshot=null;this.highlight=0;return {ok:true,changed:true};
 }
 insert(char){return this.setRaw(this.raw.slice(0,this.caret)+char+this.raw.slice(this.caret),this.caret+char.length);}
 backspace(){if(this.caret===0)return {ok:true,changed:false};return this.setRaw(this.raw.slice(0,this.caret-1)+this.raw.slice(this.caret),this.caret-1);}
 move(n){return this.setRaw(this.raw,Math.max(0,Math.min(this.raw.length,this.caret+n)));}
 request(){return Object.freeze({target:this.targetEpoch,generation:this.generation,privacy:this.privacyEpoch});}
 current(t){return !!t&&!this.suspended&&t.target===this.targetEpoch&&t.generation===this.generation&&t.privacy===this.privacyEpoch;}
 publish(token,rows){
  if(!this.current(token)||this.snapshot||!this.raw)return false;
  if(!Array.isArray(rows)||rows.length>40)return false;
  const ids=new Set();
  for(const r of rows){if(!r||typeof r.id!=='string'||typeof r.text!=='string'||r.text.length>4096||ids.has(r.id)||!Number.isInteger(r.engineIndex)||r.engineIndex<0)return false;ids.add(r.id);}
  this.snapshot=Object.freeze({token,rows:Object.freeze(rows.map(r=>Object.freeze({...r,span:r.span?Object.freeze([...r.span]):null})))});return true;
 }
 refresh(){return this.publish(this.request(),candidates(this.raw,this.privateMode));}
 step(n){if(this.snapshot?.rows.length)this.highlight=(this.highlight+n+this.snapshot.rows.length)%this.snapshot.rows.length;}
 choose(index=this.highlight){
  if(!this.snapshot||!this.current(this.snapshot.token)||!Number.isInteger(index)||index<0||index>=this.snapshot.rows.length)return null;
  const candidate=this.snapshot.rows[index];return this.commit(candidate.text,'fixture-candidate',candidate.id);
 }
 commit(text,origin='literal',candidateID=null){
  if(this.suspended||!this.raw||typeof text!=='string')return null;
  const effect=Object.freeze({id:`${this.targetEpoch}:${++this.operation}`,target:this.targetEpoch,generation:this.generation,text,origin,candidateID,send:false});
  this.setRaw('');return effect;
 }
 cancel(){this.setRaw('');this.snapshot=null;}
 targetChanged(){this.targetEpoch++;this.generation++;this.raw='';this.caret=0;this.snapshot=null;this.highlight=0;}
 privacy(on){if(!!on===this.privateMode)return;this.privateMode=!!on;this.privacyEpoch++;this.generation++;this.snapshot=null;this.highlight=0;}
 suspend(){this.suspended=true;this.targetChanged();}
 resume(){this.suspended=false;this.targetChanged();}
}
class EffectSink{
 constructor(){this.seen=new Set();}
 apply(effect,target,write){if(!effect||effect.target!==target||effect.send!==false||this.seen.has(effect.id))return false;this.seen.add(effect.id);write(effect.text);return true;}
}
function makeLease({target,epoch,privacy,text,start,end,now=0}){
 if(typeof text!=='string'||text.length>200000||!Number.isInteger(start)||!Number.isInteger(end)||start<0||end<=start||end>text.length) return null;
 return {target,epoch,privacy,text,start,end,expires:now+30000,used:false};
}
function validateLease(lease,current,now=0){
 if(!lease||lease.used||now>=lease.expires)return false;
 return ['target','epoch','privacy','text','start','end'].every(k=>current[k]===lease[k]);
}
function applyLease(lease,current,replacement,now=0){
 if(typeof replacement!=='string'||replacement.length>200000||!validateLease(lease,current,now)||current.text.length-(lease.end-lease.start)+replacement.length>200000)return null;
 lease.used=true;return current.text.slice(0,lease.start)+replacement+current.text.slice(lease.end);
}
function placePanel(caret,size,screen,margin=8){
 if(![caret.x,caret.y,caret.height,size.width,size.height,screen.x,screen.y,screen.width,screen.height,margin].every(Number.isFinite)||screen.width<=2*margin||screen.height<=2*margin||size.width<=0||size.height<=0)return null;
 const width=Math.min(size.width,screen.width-2*margin),height=Math.min(size.height,screen.height-2*margin);
 const x=Math.max(screen.x+margin,Math.min(caret.x,screen.x+screen.width-width-margin));
 const below=caret.y+caret.height+6;
 const above=below+height>screen.y+screen.height-margin;
 const y=Math.max(screen.y+margin,Math.min(above?caret.y-height-6:below,screen.y+screen.height-height-margin));
 return {x,y,width,height,above};
}
function evidenceState(kind){return ({key:'not_sent',composition:'not_sent',commit:'not_sent',send_click:'intent_only',rendered_user_message:'observed_message',server_ack:'protocol_confirmed'})[kind]||'unknown';}
const api={Session,EffectSink,candidates,makeLease,validateLease,applyLease,placePanel,evidenceState};
if(typeof module!=='undefined'&&module.exports)module.exports=api;root.IMEStudy=api;
})(typeof globalThis!=='undefined'?globalThis:this);
