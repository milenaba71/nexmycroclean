const fs=require('fs'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
async function setup(enabled){
 const dom=new JSDOM('<div id="app"></div>',{runScripts:'outside-only'}),w=dom.window,calls=[];
 w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false;this.onclose?.()};
 w.cloudUser={role:'admin',permissions:{assistant_edit:enabled}};w.userCan=()=>enabled;
 w.appSupabase={functions:{invoke:async(_,args)=>({data:args.body.statusOnly?{remaining:10,configured:true}:{action:'edit',entity:'lot',target:'56',field:'colli',value:3,remaining:9}})},rpc:async(name,args)=>{calls.push(args);return {data:args.p_action==='preview'?{entity:'lot',target:'56',field:'colli',value:3,before:1,label:'Lotto 56 <script>bad()</script>',version:'hash'}:{saved:true}}}};
 w.eval(fs.readFileSync('office-assistant.js','utf8'));w.document.querySelector('button[aria-label]').click();
 w.document.querySelector('dialog input').value='Metti 3 colli nel lotto 56';w.document.querySelector('[data-ask]').click();await tick();await tick();return {w,calls};
}
(async()=>{
 let {w,calls}=await setup(false);assert.equal(calls.length,0);assert.match(w.document.querySelector('[role=status]').textContent,/non è abilitato/);w.close();
 ({w,calls}=await setup(true));assert.deepEqual(calls.map(x=>x.p_action),['preview']);assert.equal(w.document.querySelectorAll('script').length,0);
 const btn=[...w.document.querySelectorAll('button')].find(b=>b.textContent==='Conferma modifica');btn.click();btn.click();await tick();assert.equal(calls.filter(x=>x.p_action==='commit').length,1);assert.equal(calls[1].p.confirmed,true);assert.match(w.document.querySelector('dialog').textContent,/Modifica salvata/);w.close();
 ({w,calls}=await setup(true));[...w.document.querySelectorAll('button')].find(b=>b.textContent==='Annulla').click();assert.equal(calls.length,1);assert.match(w.document.querySelector('dialog').textContent,/Nessun dato salvato/);w.close();
 console.log('PASS: disabled users, preview-only, explicit confirmation, double click, cancel, escaped AI labels');
})().catch(e=>{console.error(e);process.exit(1)});
