/* Persistent approved knowledge; conversation stays in this open panel only. */
window.openCompanyAssistant=async function(target,{active,showQuota}){
 const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e};
 const btn=(text,fn)=>{const b=el('button',text);b.type='button';b.className='btn secondary';b.onclick=fn;return b};
 const label=(text,input)=>{const l=el('label',text);l.append(input);input.style.width='100%';return l};
 const errorText=e=>/KNOWLEDGE_CONFLICT/.test(e?.message||'')?'La regola è stata aggiornata. Il tuo testo resta qui: riapri la memoria per confrontare la versione attuale.':/FORBIDDEN|PERMISSION_DENIED|SUPER_ADMIN/.test(e?.message||'')?'Questa operazione richiede il Super amministratore.':e?.message||'Operazione non completata.';
 let canTrain=false,epoch=0,sending=false,saving=false;const history=[];
 const nav=el('div'),view=el('div'),chat=el('div'),thread=el('div'),input=el('textarea'),status=el('p');input.maxLength=2000;input.rows=3;input.placeholder='Chiedi una procedura o descrivi il problema…';status.setAttribute('role','status');
 const teach=btn('Insegna all’IA',()=>edit());teach.hidden=true;
 const chatButton=btn('Chat aziendale',()=>{epoch++;view.replaceChildren(chat)}),memoryButton=btn('Memoria approvata',()=>list());
 nav.append(chatButton,memoryButton,teach);
 function paragraph(text){const p=el('p',text);p.style.whiteSpace='pre-wrap';return p}
 function message(who,text,sources=[],question=''){
  const box=el('section');box.style.cssText='border:1px solid #dce2ef;border-radius:10px;padding:12px;margin:12px 0;overflow-wrap:anywhere';box.append(el('strong',who),paragraph(text));
  if(sources.length){const d=el('details');d.append(el('summary','Fonti aziendali utilizzate'));for(const s of sources)d.append(el('p',s.title+' · versione '+s.revision+' · '+new Date(s.updatedAt).toLocaleDateString('it-IT')));box.append(d)}
  if(who==='IA'&&canTrain)box.append(btn('Correggi / insegna la regola',()=>edit({title:question.slice(0,120),body:'',source:'Correzione approvata dal Super amministratore'})));
  thread.append(box);
 }
 const send=btn('Invia',async()=>{
  const question=input.value.trim();if(!question||sending||!active())return;sending=true;send.disabled=true;status.textContent='L’IA sta consultando la memoria approvata…';
  try{
   const {data,error}=await appSupabase.functions.invoke('mycroclean-assistant',{body:{question,history:history.slice(-12)}});
   if(!active())return;
   if(error){const detail=await error.context?.json?.().catch(()=>null);if(!active())return;showQuota(detail?.remaining);throw Error(detail?.error||'Servizio IA non disponibile.')}
   showQuota(data.remaining);message('Tu',question);message('IA',data.answer,data.sources,question);
   history.push({role:'user',content:question},{role:'assistant',content:data.answer.slice(0,4000)});if(history.length>12)history.splice(0,history.length-12);
   if(input.value.trim()===question)input.value='';status.textContent='Risposta ricevuta. Le regole permanenti cambiano solo con Approva e memorizza.';
  }catch(e){if(active())status.textContent=errorText(e)}finally{if(active()){sending=false;send.disabled=false}}
 });
 const clear=btn('Nuova conversazione',()=>{if(sending)return;history.length=0;thread.replaceChildren();input.value='';status.textContent='Conversazione azzerata. La memoria approvata resta salvata.'});
 chat.append(el('h3','La tua IA Mycroclean'),el('p','Parla delle procedure e dei problemi aziendali. L’IA consulta le regole approvate e distingue le proposte dalle informazioni confermate.'),el('small','Le domande, il contesto recente e le regole pertinenti vengono inviati a OpenAI. Questa conversazione si azzera chiudendo il pannello; la memoria approvata resta nel gestionale.'),thread,label('Messaggio',input),send,clear,status);
 input.onkeydown=e=>{if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)){e.preventDefault();send.click()}};
 target.replaceChildren(nav,view);view.append(chat);
 async function rpc(action,p={}){const r=await appSupabase.rpc('laundry_assistant_knowledge',{p_action:action,p});if(r.error)throw r.error;return r.data}
 async function list(query=''){
  if(saving)return;const id=++epoch;view.textContent='Caricamento memoria…';
  try{const data=await rpc('list',{query});if(!active()||id!==epoch)return;canTrain=data.canTrain;teach.hidden=!canTrain;
   const search=el('input');search.value=query;search.maxLength=120;const results=el('div');
   view.replaceChildren(el('h3','Memoria aziendale approvata'),el('p',data.total+' regole attive. Le regole approvate sono consultabili dagli utenti abilitati all’assistente.'),label('Cerca nelle regole',search),btn('Cerca',()=>list(search.value)),results);
   for(const d of data.documents){const box=el('section');box.style.cssText='border-bottom:1px solid #dce2ef;padding:12px 0';const details=el('details');details.append(el('summary',d.title+' · v'+d.revision),paragraph(d.body),el('p','Fonte: '+(d.source||'Inserimento del Super amministratore')));box.append(details);if(canTrain)box.append(btn('Modifica',()=>edit(d)),btn('Disattiva regola',async()=>{if(saving)return;saving=true;try{await rpc('archive',{id:d.id,revision:d.revision});saving=false;if(active()&&id===epoch)list(query)}catch(e){if(active())box.append(paragraph(errorText(e)))}finally{saving=false}}));results.append(box)}
   if(!data.documents.length)results.append(el('p','Nessuna regola trovata. Usa Insegna all’IA per inserire la prima procedura.'));
   if(data.documents.length===100)results.append(el('p','Mostrate le prime 100 regole. Usa la ricerca per restringere l’elenco.'));
  }catch(e){if(active()&&id===epoch)view.replaceChildren(paragraph(errorText(e)),btn('Riprova',()=>list(query)))}
 }
 function edit(doc={}){
  if(!canTrain||saving)return;const id=++epoch,draft={id:doc.id||crypto.randomUUID(),revision:doc.revision||0};
  const form=el('form'),title=el('input'),body=el('textarea'),source=el('input'),result=el('p');
  title.required=true;title.minLength=3;title.maxLength=120;title.value=doc.title||'';body.required=true;body.minLength=10;body.maxLength=4000;body.rows=10;body.value=doc.body||'';source.maxLength=300;source.value=doc.source||'';
  body.placeholder='Scrivi la procedura corretta: quando si applica, cosa fare, eccezioni ed eventuale verifica del responsabile.';
  const save=el('button','Approva e memorizza');save.type='submit';save.className='btn';
  const cancel=btn('Annulla',()=>{if(!saving){epoch++;view.replaceChildren(chat)}});
  form.append(label('Titolo della regola',title),label('Istruzione aziendale verificata',body),label('Fonte / documento di riferimento',source),el('p','Approvando rendi questa regola disponibile all’IA per gli utenti abilitati. Nessun prodotto, lotto o macchina viene modificato.'),save,cancel,result);
  view.replaceChildren(el('h3',doc.id?'Aggiorna ciò che l’IA sa':'Insegna all’IA'),form);
  form.onsubmit=async e=>{e.preventDefault();if(saving||!active()||id!==epoch)return;saving=true;save.disabled=cancel.disabled=chatButton.disabled=memoryButton.disabled=teach.disabled=true;result.textContent='Memorizzazione…';
   try{await rpc('save',{...draft,title:title.value,body:body.value,source:source.value,approved:true});if(active()&&id===epoch){view.replaceChildren(el('h3','Regola approvata e memorizzata'),el('p','L’IA potrà consultarla dalle prossime domande. Non è necessario riaddestrare il modello.'),btn('Torna alla chat',()=>{epoch++;view.replaceChildren(chat)}),btn('Apri memoria',()=>list()))}}
   catch(e){if(active()&&id===epoch)result.textContent=errorText(e)}finally{saving=false;save.disabled=cancel.disabled=chatButton.disabled=memoryButton.disabled=teach.disabled=false}
  };
 }
 try{const data=await rpc('status');if(active()){canTrain=data.canTrain;teach.hidden=!canTrain;status.textContent=data.total?'Memoria disponibile: '+data.total+' regole approvate.':'La memoria è vuota: il Super amministratore può iniziare con Insegna all’IA.'}}catch(e){if(active())status.textContent=errorText(e)}
};
