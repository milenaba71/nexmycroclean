const fs=require('fs'),assert=require('node:assert/strict'),{JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
const tick=()=>new Promise(r=>setTimeout(r,0));
function setup({supported=true,prefixed=false}={}){
 const dom=new JSDOM('<dialog open><form><label>Nota<textarea maxlength="2000"></textarea></label><button type="submit">Salva</button></form></dialog>',{runScripts:'outside-only',url:'https://example.test'}),w=dom.window,instances=[];
 class Speech{constructor(){instances.push(this)}start(){this.started=true}stop(){this.stopped=true}abort(){this.aborted=true}emit(items){this.onresult?.({results:items.map(([text,final=true])=>Object.assign([{transcript:text}],{isFinal:final}))})}end(){this.onend?.()}}
 if(supported)w[prefixed?'webkitSpeechRecognition':'SpeechRecognition']=Speech;
 w.eval(fs.readFileSync('dictation.js','utf8'));const input=w.document.querySelector('textarea');let active=true,busy=false;
 const voice=w.attachDictation(input,{isActive:()=>active,onBusy:v=>busy=v});input.closest('label').after(voice.element);
 const mic=voice.element.querySelector('button'),lang=voice.element.querySelector('select');return {w,dom,instances,input,voice,mic,lang,get busy(){return busy},deactivate(){active=false}};
}
(async()=>{
 let x=setup({supported:false});assert(x.mic.disabled);assert(x.voice.element.textContent.includes('tastiera'));assert(!x.input.readOnly);x.w.close();
 x=setup({prefixed:true});x.input.value='Nota esistente.';x.lang.value='fa-IR';x.mic.click();let rec=x.instances[0];assert.equal(rec.lang,'fa-IR');assert(x.busy);assert(x.input.readOnly);assert.equal(x.mic.type,'button');
 rec.emit([['testo provvisorio',false]]);assert.equal(x.input.value,'Nota esistente.');
 rec.emit([['خطای E42',true],['ancora',false]]);assert.equal(x.input.value,'Nota esistente. خطای E42');rec.emit([['خطای E42',true],['fine',true]]);assert.equal(x.input.value,'Nota esistente. خطای E42 fine');rec.emit([['خطای E42',true],['fine',true]]);assert.equal(x.input.value,'Nota esistente. خطای E42 fine','duplicate results must not duplicate text');
 let saves=0;x.w.document.addEventListener('submit',()=>saves++);x.input.form.dispatchEvent(new x.w.Event('submit',{bubbles:true,cancelable:true}));assert.equal(saves,0,'must stop before save');
 x.mic.click();assert(rec.stopped);assert(x.busy,'wait for final transcript');rec.emit([['خطای E42 fine finale',true]]);rec.end();assert(!x.busy);assert(!x.input.readOnly);assert.equal(saves,0);x.input.form.dispatchEvent(new x.w.Event('submit',{bubbles:true,cancelable:true}));assert.equal(saves,1);
 x.mic.click();rec=x.instances.at(-1);rec.onerror({error:'not-allowed'});assert(!x.busy);assert(x.voice.element.textContent.includes('Consenti il microfono'));assert(x.input.value.includes('finale'));
 x.mic.click();rec=x.instances.at(-1);const late=rec.onresult;x.w.document.querySelector('dialog').removeAttribute('open');await tick();assert(rec.aborted);assert(!x.busy);late({results:[Object.assign([{transcript:'late overwrite'}],{isFinal:true})]});assert(!x.input.value.includes('late overwrite'));
 x.w.document.querySelector('dialog').setAttribute('open','');x.input.value='';x.input.maxLength=5;x.mic.click();rec=x.instances.at(-1);rec.emit([['1234567',true]]);assert.equal(x.input.value,'12345');assert(rec.stopped);rec.end();
 x.input.value='';x.mic.click();rec=x.instances.at(-1);x.w.document.dispatchEvent(new x.w.Event('visibilitychange'));assert(rec.aborted);assert(!x.busy);
 x.mic.click();rec=x.instances.at(-1);x.input.remove();await tick();assert(rec.aborted);x.w.close();
 x=setup();x.mic.click();rec=x.instances.at(-1);const second=x.w.document.createElement('textarea');x.w.document.querySelector('form').append(second);const other=x.w.attachDictation(second);second.after(other.element);other.element.querySelector('button').click();assert(rec.aborted);assert(!x.busy);assert(other.busy);other.cancel();x.w.close();
 // Real chat: no automatic network call, no send while recording, cancel on navigation.
 x=setup();const target=x.w.document.createElement('div');x.w.document.body.append(target);let calls=[];
 x.w.appSupabase={rpc:async()=>({data:{total:0,canTrain:true,documents:[]}}),functions:{invoke:async(name,{body})=>{calls.push(body);return {data:{answer:'Ok',sources:[],remaining:9}}}}};
 x.w.eval(fs.readFileSync('assistant-memory.js','utf8'));await x.w.openCompanyAssistant(target,{active:()=>true,showQuota(){}});
 const btn=text=>[...target.querySelectorAll('button')].find(b=>b.textContent===text);btn('🎤 Detta').click();rec=x.instances.at(-1);rec.emit([['Domanda dettata',true]]);btn('Invia').click();assert.equal(calls.length,0);btn('⏹ Ferma').click();rec.end();assert.equal(calls.length,0);btn('Invia').click();await tick();assert.equal(calls[0].question,'Domanda dettata');btn('🎤 Detta').click();rec=x.instances.at(-1);btn('Memoria approvata').click();assert(rec.aborted);await tick();x.w.close();
 console.log('PASS: supported/prefixed/fallback, selected language, append and deduplicate, interim review, manual send/save, permissions, close/navigation/visibility cleanup, late events, length limits, one active mic, real chat');
})().catch(e=>{console.error(e);process.exit(1)});
