const fs=require('fs'),assert=require('node:assert/strict'),{JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
const tick=()=>new Promise(r=>setTimeout(r,0));
async function setup(canTrain){
 const dom=new JSDOM('<div id="target"></div>',{runScripts:'outside-only',url:'https://example.test'}),w=dom.window,target=w.document.getElementById('target'),calls=[];let docs=[],revision=0,fail=false;
 w.appSupabase={rpc:async(name,{p_action,p})=>{calls.push({action:p_action,p});if(p_action==='status'||p_action==='list')return {data:{canTrain,total:docs.length,documents:docs}};
  if(p_action==='save'){if(fail)return {error:{message:'KNOWLEDGE_CONFLICT'}};docs=[{...p,revision:++revision,updated_at:'2026-11-26T12:00:00Z'}];return {data:{saved:true}}}
  if(p_action==='archive'){docs=[];return {data:{saved:true}}}},functions:{invoke:async(name,{body})=>{calls.push({action:'chat',body});return {data:{answer:'<script>unsafe()</script>',sources:[{id:'doc',title:'Regola',revision:1,updatedAt:'2026-11-26T12:00:00Z'}],remaining:9}}}}};
 w.eval(fs.readFileSync('assistant-memory.js','utf8'));await w.openCompanyAssistant(target,{active:()=>true,showQuota(){}});
 const button=text=>[...target.querySelectorAll('button')].find(b=>b.textContent===text);
 return {w,target,calls,button,setFail:()=>fail=true};
}
(async()=>{
 let x=await setup(false);assert.equal(x.target.querySelector('textarea').dir,'auto');assert.equal(x.button('Insegna all’IA').hidden,true);x.target.querySelector('textarea').value='Come gestire un guasto?';x.button('Invia').click();x.button('Invia').click();await tick();assert.equal(x.calls.filter(c=>c.action==='chat').length,1);assert(!x.calls.some(c=>c.action==='save'));assert.equal(x.target.querySelectorAll('script').length,0);assert.equal(x.target.querySelector('section p').dir,'auto');assert(!x.button('Correggi / insegna la regola'));x.w.close();
 x=await setup(true);x.button('Insegna all’IA').click();let form=x.target.querySelector('form');form.querySelector('input').value='Cinghia motore';form.querySelector('textarea').value='Contattare il manutentore per verificare la cinghia.';
 form.dispatchEvent(new x.w.Event('submit',{bubbles:true,cancelable:true}));form.dispatchEvent(new x.w.Event('submit',{bubbles:true,cancelable:true}));await tick();assert.equal(x.calls.filter(c=>c.action==='save').length,1);assert.equal(x.calls.find(c=>c.action==='save').p.approved,true);assert(x.target.textContent.includes('Regola approvata e memorizzata'));
 x.button('Apri memoria').click();await tick();assert(x.target.textContent.includes('Cinghia motore'));x.button('Modifica').click();form=x.target.querySelector('form');assert(form.querySelector('textarea').value.includes('manutentore'));x.setFail();form.querySelector('textarea').value='Nuova istruzione da conservare anche se arriva un conflitto.';form.dispatchEvent(new x.w.Event('submit',{bubbles:true,cancelable:true}));await tick();assert(x.target.textContent.includes('aggiornata'));assert(form.querySelector('textarea').value.includes('Nuova istruzione'));
 x.button('Annulla').click();x.target.querySelector('textarea').value='Come gestire un guasto?';x.button('Invia').click();await tick();x.button('Correggi / insegna la regola').click();assert.equal(x.target.querySelector('form textarea').value,'','never approve model output automatically');assert.equal(x.calls.filter(c=>c.action==='save').length,2);
 x.w.close();
 x=await setup(false);const farsi='خطای E42 دستگاه LS3-08';x.target.querySelector('textarea').value=farsi;x.button('Invia').click();await tick();assert.equal(x.calls.find(c=>c.action==='chat').body.question,farsi);assert.equal(x.target.querySelector('section p').textContent,farsi);x.w.close();console.log('PASS: reader/trainer UI, conversation does not train, explicit approval, duplicate save prevention, editable memory, conflict preserves draft, correction starts unapproved, safe rendering');
})().catch(e=>{console.error(e);process.exit(1)});
