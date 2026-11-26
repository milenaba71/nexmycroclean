const fs=require('fs'),assert=require('node:assert/strict'),{JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
const tick=()=>new Promise(r=>setTimeout(r,0));
(async()=>{
 const dom=new JSDOM('<div id="target"></div>',{runScripts:'outside-only'}),w=dom.window,target=w.document.getElementById('target');
 w.eval(fs.readFileSync('supabase/functions/lot-question/maintenance-core.js','utf8'));w.eval(fs.readFileSync('maintenance-assistant.js','utf8').replace(/^import .*;\n/gm,''));
 let calls=[],allowed=true,resolveAI;
 const state={asOf:'2026-11-26T10:00:00Z',machines:[{id:'m',name:'Macchina 1'},{id:'n',name:'Macchina 2'}],tickets:[{id:'t',machineId:'m',description:'<script>bad()</script>',createdAt:'2026-11-25T10:00:00Z',status:'open',blocking:true,history:[{at:'2026-11-25T10:00:00Z',status:'open',blocking:true,note:'Guasto'}]}]};
 w.appSupabase={rpc:async name=>{calls.push(name);return {data:state}},functions:{invoke:async(name,args)=>{calls.push(args.body);return new Promise(r=>resolveAI=r)}}};
 await w.openMaintenanceAssistant(target,{active:()=>allowed,showQuota(){},machine:'Macchina 1',days:30});
 assert.equal(calls.length,1);assert.equal(target.querySelectorAll('script').length,0);assert.equal(target.querySelector('select').value,'m');assert(target.textContent.includes('24 ore'));
 const analyze=[...target.querySelectorAll('button')].find(b=>b.textContent.includes('Analizza'));analyze.click();analyze.click();assert.equal(calls.length,2);assert.equal(calls[1].days,30);
 resolveAI({data:{asOf:state.asOf,summary:'<img onerror="bad()">',findings:[{title:'Ricorrenza',evidence:'Guasto',recommendation:'Controllo',ticketIds:['t']}],limitations:'Verificare'}});await tick();assert(target.textContent.includes('<img onerror'));assert.equal(target.querySelectorAll('img').length,0);
 analyze.click();const select=target.querySelector('select');select.value='n';select.dispatchEvent(new w.Event('change'));resolveAI({data:{summary:'RISPOSTA VECCHIA',findings:[]}});await tick();assert(!target.textContent.includes('RISPOSTA VECCHIA'));assert(target.textContent.includes('Non ci sono segnalazioni operative'));
 analyze.click();allowed=false;resolveAI({data:{summary:'CHIUSO',findings:[]}});await tick();assert(!target.textContent.includes('CHIUSO'));w.close();
 // Exercise the real ticket form and submit handler, not a replica.
 const formDom=new JSDOM('<dialog id="modal"></dialog>',{runScripts:'outside-only'}),v=formDom.window;
 Object.assign(v,{ProductionCore:{},render(){},detail(){},userCan:()=>true,cloudUser:{role:'operator'},clone:x=>structuredClone(x),esc:s=>String(s??'').replace(/</g,'&lt;'),notify(){},show:html=>{v.document.querySelector('#modal').innerHTML=html},$:s=>v.document.querySelector(s)});
 v.HTMLDialogElement.prototype.close=function(){};
 v.eval(fs.readFileSync('production.js','utf8')+`\nprod={machines:[{id:'m',name:'M1'}],tickets:[]};pDraw=()=>{};pRpc=async(a,p)=>{window.saved={a,p}};window.testForm=()=>pEditTicket('', 'm');`);
 v.testForm();const form=v.document.querySelector('form');assert(form);form.elements.namedItem('note').value='Cinghia rotta';form.elements.namedItem('maintenance_component').value='Cinghia';form.elements.namedItem('maintenance_cause').value='Usura';
 form.dispatchEvent(new v.Event('submit',{bubbles:true,cancelable:true}));await tick();assert.equal(v.saved.a,'ticket');assert.equal(v.saved.p.maintenance.component,'Cinghia');assert.equal(v.saved.p.maintenance.kind,'fault');assert.equal(v.saved.p.maintenance.cause,'Usura');v.close();
 console.log('PASS: report rendering, filters, no automatic IA call, duplicate prevention, escaped content, stale/closed responses ignored, real ticket form submits structured data');
})().catch(e=>{console.error(e);process.exit(1)});
