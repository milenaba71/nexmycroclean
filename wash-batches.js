/* Entry-driven carts. Shared server state, no local-only machine reservations. */
let washState=null,washChoice='',washBusy=false,washLoading=false,washError='',washNoticeSeen=new Set();
function washKey(p,m){return encodeURIComponent(p)+'|'+encodeURIComponent(m)}
function washChoiceParts(){let key=activeScanJob?.washChoice??washChoice;return key?.includes('|')?key.split('|').map(decodeURIComponent):null}
function washPrograms(){return (washState?.types||[]).filter(t=>t.active!==false&&t.mode==='machine'&&['water','decon','dry'].includes(t.machineKind)&&(washState.stations||[]).some(s=>s.id===t.station&&s.active!==false))}
function washMachineBusy(id,exceptBatch){return (washState?.batches||[]).some(b=>b.machine_id===id&&b.id!==exceptBatch&&['running','blocked'].includes(b.state))}
function washOptions(){return washPrograms().flatMap(t=>{let link=washState.links.find(l=>l.program_id===t.id);if(!link||!ensureProcessing().some(p=>p.id===link.processing_id&&p.active))return [];return washState.machines.filter(m=>m.active!==false&&m.kind===t.machineKind).map(m=>({key:washKey(t.id,m.id),t,m,processingId:link.processing_id}))})}
function washMessage(e){return ({INVALID_PROGRAM_LINK:'Collega il programma alla lavorazione di entrata in Configura collegamenti.',MACHINE_CAPACITY_REQUIRED:'Imposta una capacità valida nella scheda della macchina.',CYCLE_DURATION_REQUIRED:'Imposta la durata del programma in Produzione → Tempi lavorazioni.',MACHINE_BUSY:'Macchina occupata. Attendi oppure scegli un’altra macchina compatibile.',MACHINE_UNAVAILABLE:'La macchina ha un guasto bloccante.',BATCH_PRODUCTS_ALREADY_PROCESSED:'Alcuni prodotti sono già lavorati o usciti: questa macchinata non può partire.',BATCH_ALREADY_FINISHED:'Ciclo già terminato.',BATCH_NOT_RUNNING:'Questa macchinata non è in corso.',CYCLE_ALREADY_ELAPSED:'Il tempo previsto è già trascorso. Per un nuovo trattamento usa il rilavaggio nel lotto.',PRODUCT_NOT_READY_FOR_EXIT:'Registra prima la piegatura nella fase 2.',PRODUCT_INTERVENTIONS_PENDING:'Completa riparazione, etichettatura, verifica o rilavaggio prima di segnare il prodotto pronto.',PRODUCT_ALREADY_EXITED:'Prodotto già uscito.',WASH_BATCH_IN_PROGRESS:'Prodotto nel carrello o in lavaggio: avvia la macchinata e attendi la fine prevista.',FORBIDDEN:'Il tuo ruolo non consente questa operazione.'})[e.message]||e.message}
async function washRpc(action,payload={}){let {data,error}=await appSupabase.rpc('laundry_wash_batches',{p_action:action,p_payload:payload});if(error)throw Error(washMessage(error));if(data?.batches){washState=data;washError='';washSyncChoices()}return data}
async function washRefresh(){if(washLoading||!cloudUser)return;washLoading=true;try{await cloudFlush();await washRpc('read',{lotId:current?.id});cloudAccept(await cloudRequest(),false);washRender();if(current&&$('#lotRows')){renderLotRows();let summaryPanel=$('#lotTypeCounts')?.closest('.panel');if(summaryPanel)summaryPanel.outerHTML=lotTypeSummary(current);}}catch(e){washError=washMessage(e);washRender()}finally{washLoading=false}}
const entryBeforeWashBatches=entryProcessing;
entryProcessing=function(){let opts=washOptions(),nonWash=ensureProcessing().filter(p=>p.active&&!p.wash);return `<div class="tools" style="align-items:end"><label style="display:grid;gap:8px;flex:1;min-width:0">Lavaggio e macchina *<select id="entryProcessing" aria-label="Lavaggio e macchina" onchange="washSelect(this.value)" ${lotWritable()?'':'disabled'}><option value="">${washState?'Scegli programma e macchina…':'Caricamento macchine…'}</option>${opts.map(o=>`<option value="${esc(o.key)}" ${washChoice===o.key?'selected':''}>${esc(o.t.name)} · ${esc(o.m.name)}${washMachineBusy(o.m.id)?' · In coda · Macchina occupata':''}${!o.m.capacity?' · Capacità da definire':''}${!o.t.value?' · Durata da definire':''}</option>`).join('')}${nonWash.map(p=>`<option value="plain:${esc(p.id)}" ${washChoice==='plain:'+p.id?'selected':''}>${esc(p.name)} · Senza macchina</option>`).join('')}</select></label><button type="button" class="link" onclick="washRefresh()">Aggiorna</button>${userCan('production_manage')?'<button type="button" class="link" onclick="washLinkDialog()">Configura collegamenti</button>':''}</div>`};
function washSelect(value){if(lotBusy()||washBusy){notify('Attendi le scansioni in corso.');return}if(value.includes('|')&&!washOptions().some(o=>o.key===value)){washSyncChoices();notify('Macchina non disponibile. Scegli un’altra macchina.');return}washChoice=value;let o=washOptions().find(o=>o.key===value);chosenProcessing=o?.processingId||(value.startsWith('plain:')?value.slice(6):'');if(current){current.entryProcessingId=chosenProcessing;current.entryWashChoice=value;save()}washRender();$('#scan')?.focus()}
const selectedBeforeWashBatches=selectedProcessing;
selectedProcessing=function(){let pair=washChoiceParts();if(pair){let o=washOptions().find(o=>o.t.id===pair[0]&&o.m.id===pair[1]);return ensureProcessing().find(p=>p.id===o?.processingId&&p.active)}return selectedBeforeWashBatches()};
const enqueueBeforeWashBatches=enqueueBarcode;
enqueueBarcode=function(value){if(washBusy||!washState)return notify('Attendi il caricamento di macchine e carrelli.');if(stage==='Entrata'&&!washChoice)return notify('Scegli prima lavaggio e macchina.');if(stage==='Entrata'&&washChoiceParts()){let o=washOptions().find(o=>o.key===washChoice);if(!o)return notify('Macchina non disponibile. Scegli un’altra macchina.');if(!o.m.capacity)return notify('Capacità macchina da definire in Produzione → Macchine.')}let before=scanQueue.length;enqueueBeforeWashBatches(value);/* drain starts synchronously: capture both the active and queued job */if(activeScanJob?.phase==='Entrata'&&activeScanJob.washChoice===undefined)activeScanJob.washChoice=washChoice;for(let j of scanQueue)if(j.phase==='Entrata'&&j.washChoice===undefined)j.washChoice=washChoice};
const requestBeforeWashBatches=cloudRequest;
cloudRequest=async function(action,payload){let pair=washChoiceParts();if(action==='lot_acquire'&&pair){return washRpc('acquire',{...payload,lotId:payload.lot_id,programId:pair[0],machineId:pair[1]})}return requestBeforeWashBatches(action,payload)};
const checkedBeforeWashBatches=checkedProcess;
checkedProcess=async function(code){let err=await checkedBeforeWashBatches(code);if(!err&&stage==='Entrata'&&washChoiceParts()){try{await washRpc('read',{lotId:current.id});washPopupReady()}catch(e){notify('Entrata salvata. Riepilogo carrelli da aggiornare: '+washMessage(e))}}return err};
const openBeforeWashBatches=openLot;
openLot=function(id){if(lotBusy()||washBusy)return notify('Attendi l’operazione in corso.');openBeforeWashBatches(id);if(current?.id!==id)return;washChoice=current.entryWashChoice||'';chosenProcessing=washOptions().find(o=>o.key===washChoice)?.processingId||(washChoice.startsWith('plain:')?washChoice.slice(6):'');detail();if(lotWritable()){washBusy=true;cloudFlush().then(()=>washRpc('switch',{lotId:id})).then(()=>{washRender();washPopupReady()}).catch(e=>{washError=washMessage(e);washRender()}).finally(()=>{washBusy=false;washRender()})}else void washRefresh()};
const detailBeforeWashBatches=detail;
detail=function(){detailBeforeWashBatches();washRender();if(!washState&&!washLoading)void washRefresh()};
function washTime(x){return x?new Date(x).toLocaleTimeString('it-IT',{timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit'}):'—'}
function washStatus(b){if(['gathering','ready'].includes(b.state)&&washMachineBusy(b.machine_id,b.id))return (b.state==='gathering'?'Carrello in preparazione · ':'Carrello pronto · ')+'In coda · '+b.machine_name;return {gathering:'Carrello in preparazione',ready:'Carrello pronto',running:'Ciclo in corso',estimated:'Lavaggio terminato (tempo previsto) · da lavorare in fase 2',blocked:'Ciclo interrotto · da riavviare'}[b.state]||b.state}
function washCard(b){let remaining=Math.max(0,Math.ceil((new Date(b.expected_end)-Date.now())/60000)),l=db.lots.find(l=>l.id===b.lot_id);return `<article class="wash-cart ${b.state}" data-wash-batch="${esc(b.id)}" data-wash-state="${esc(b.state)}"><div><b>${esc(b.program_name)} · ${esc(b.machine_name)}</b><small>${l?lotno(l):'Lotto '+b.lot_id} · ${esc(l?.client||'')}</small></div><strong>${b.quantity}/${b.capacity} prodotti</strong><p data-wash-timer>${washStatus(b)}${b.state==='running'?` · ${remaining} min · fine prevista ${washTime(b.expected_end)}`:''}</p>${['gathering','ready','blocked'].includes(b.state)&&userCan('production_execute')?`<button class="btn" onclick="washStartDialog('${b.id}')">${b.state==='blocked'?'Riavvia ciclo completo':b.quantity<b.capacity?'Avvia macchinata parziale':'Avvia macchinata'}</button>`:''}${b.state==='running'&&userCan('production_execute')?`<button class="btn secondary" onclick="washInterrupt('${b.id}')">Segnala interruzione</button>`:''}</article>`}
function washRender(){if(!current)return;let scan=$('#scan'),panel=scan?.closest('.panel');if(!panel)return;let root=$('#washCarts');if(!root){root=document.createElement('section');root.id='washCarts';root.className='lot-work-section';let entry=$('#entryProcessing')?.closest('.lot-work-section');if(entry)entry.after(root);else panel.querySelector('.steps')?.after(root)}let batches=(washState?.batches||[]).filter(b=>b.lot_id===current.id),o=washOptions().find(o=>o.key===washChoice);root.innerHTML=`<h2>Carrelli e macchinate</h2>${washError?`<p class="notice">${esc(washError)} <button class="link" onclick="washRefresh()">Riprova</button></p>`:''}${o?`<p>${esc(o.t.name)} · ${esc(o.m.name)} — capacità ${o.m.capacity||'da definire'} · ciclo ${o.t.value?o.t.value+' min':'da definire'}</p>`:''}<div class="wash-carts">${batches.map(washCard).join('')||'<p>Seleziona lavaggio e macchina, poi scansiona. Ogni carrello contiene solo prodotti di questo lotto e dello stesso programma.</p>'}</div>${lotWritable()&&batches.some(b=>b.state==='gathering')?'<button class="btn secondary" onclick="washFinishEntry()">Termina controllo in entrata</button>':''}<p class="muted">Passando a un altro lotto, i carrelli parziali diventano pronti. Puoi preparare altri carrelli per una macchina occupata: restano in coda e l’avvio si sblocca quando termina il ciclo precedente. Il tempo parte da “Avvia macchinata”. La fine è stimata dal programma, senza sensore sulla macchina.</p>`;if(washState&&stage==='Entrata'){let old=$('#entryProcessing');if(old&&document.activeElement!==old){let holder=old.closest('.tools');holder.outerHTML=entryProcessing()}}}
function washPopupReady(){if($('#modal').open)return;let b=(washState?.batches||[]).find(b=>b.state==='ready'&&!washNoticeSeen.has(b.id)&&washCanOperate(b));if(!b)return;washNoticeSeen.add(b.id);show(`<h2>Il tuo carrello è pronto</h2><p>${b.quantity} prodotti · ${esc(b.program_name)}</p><p>${esc(b.machine_name)} · ${esc(lotno(db.lots.find(l=>l.id===b.lot_id)||{id:b.lot_id,date:new Date().toISOString()}))}</p><div class="tools"><button class="btn" ${washQueueWaiting(b)?'disabled':''} onclick="washStartDialog('${b.id}')">${washQueueWaiting(b)?'In coda · Macchina occupata':'Carica e avvia macchinata'}</button><button class="btn secondary" onclick="$('#modal').close();$('#scan')?.focus()">Continua le scansioni</button></div>`)}
function washStartDialog(id){let b=washState?.batches.find(b=>b.id===id);if(!b)return;if(washQueueWaiting(b))return notify('Carrello in coda a '+b.machine_name+'. Attendi la fine del ciclo in corso.');let machines=washState.machines.filter(m=>m.kind===b.machine_kind&&m.active!==false&&Number(m.capacity)>=b.quantity&&!washMachineBusy(m.id,id));show(`<h2>${b.state==='blocked'?'Riavvia':'Avvia'} macchinata</h2><p>${b.quantity} prodotti · ${esc(b.program_name)}</p><label style="display:grid;gap:8px">Macchina<select id="washStartMachine">${machines.length?'':'<option value="">Nessuna macchina disponibile</option>'}${machines.map(m=>{let busy=washState.batches.find(x=>x.id!==id&&x.machine_id===m.id&&['running','blocked'].includes(x.state));return `<option value="${esc(m.id)}" ${m.id===b.machine_id?'selected':''}>${esc(m.name)}${busy?' · Occupata'+(busy.state==='running'?' fino alle '+washTime(busy.expected_end):' · ciclo interrotto'):''}</option>`}).join('')}</select></label><p>Premi Avvia quando la macchina parte realmente. ${b.state==='blocked'?'Il ciclo ripartirà con l’intera durata del programma.':''}</p><div class="tools"><button id="washStartButton" class="btn" ${machines.length?'':'disabled'} onclick="washStart('${id}')">Avvia macchinata</button><button class="btn secondary" onclick="$('#modal').close()">Annulla</button></div>`)}
async function washStart(id){if(!$('#washStartMachine')?.value||washMachineBusy($('#washStartMachine').value,id))return notify('Macchina non disponibile. Aggiorna e scegli una macchina libera.');if(washBusy||lotBusy())return notify('Attendi le scansioni in corso.');washBusy=true;let button=$('#washStartButton');if(button)button.disabled=true;try{await cloudFlush();await washRpc('start',{batchId:id,machineId:$('#washStartMachine').value,lotId:current?.id});$('#modal').close();await washRefresh();notify('Macchinata avviata. Il conteggio è condiviso con gli altri operatori.')}catch(e){notify(washMessage(e));if(button)button.disabled=false}finally{washBusy=false}}
async function washInterrupt(id){if(washBusy)return;washBusy=true;try{await cloudFlush();await washRpc('interrupt',{batchId:id,lotId:current?.id});await washRefresh();notify('Ciclo interrotto: la fine automatica è sospesa.')}catch(e){notify(washMessage(e))}finally{washBusy=false}}
async function washFinishEntry(){if(!lotMutationAllowed()||washBusy)return;washBusy=true;try{await cloudFlush();await washRpc('finish',{lotId:current.id});washRender();washPopupReady()}catch(e){notify(washMessage(e))}finally{washBusy=false}}
function washLinkDialog(){if(!userCan('production_manage'))return;let programs=washPrograms(),ps=ensureProcessing().filter(p=>p.active&&p.wash);show(`<h2>Collega programmi e lavaggi</h2><p>Una sola volta per programma. Capacità e durata si modificano in Produzione → Macchine / Tempi lavorazioni.</p><form onsubmit="washSaveLink(event)"><label class="wide">Programma<select name="programId" required>${programs.map(t=>`<option value="${esc(t.id)}">${esc(t.name)}${washState.links.some(l=>l.program_id===t.id)?' · Collegato':''}</option>`).join('')}</select></label><label class="wide">Lavorazione registrata in entrata<select name="processingId" required>${ps.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></label><div class="wide"><button class="btn">Salva collegamento</button> <button type="button" class="btn secondary" onclick="$('#modal').close()">Annulla</button></div></form><p>Se manca una lavorazione, aggiungila nella tabella Lavorazioni.</p>`)}
async function washSaveLink(e){e.preventDefault();let button=e.submitter;button.disabled=true;try{await washRpc('link',Object.fromEntries(new FormData(e.target)));$('#modal').close();if(current)detail();notify('Collegamento salvato.')}catch(err){notify(washMessage(err));button.disabled=false}}
const pDrawBeforeWashBatches=pDraw;pDraw=function(){pDrawBeforeWashBatches();if(page==='Produzione'&&!current&&['board','mine','machines'].includes(prodTab)){let el=document.createElement('section');el.id='productionWashCarts';el.innerHTML='<h2>Carrelli e macchinate dall’entrata</h2><div class="wash-carts">'+(washState?.batches||[]).filter(b=>b.state!=='estimated').map(washCard).join('')+'</div>';$('#prodBody')?.prepend(el)}};
const pLoadBeforeWashBatches=pLoad;pLoad=async function(){await washRpc('read');await pLoadBeforeWashBatches()};
const styleWash=document.createElement('style');styleWash.textContent='.wash-carts{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr));gap:12px}.wash-cart{border:1px solid #dce3f1;border-left:5px solid #315caa;border-radius:12px;padding:16px;background:white;overflow-wrap:anywhere}.wash-cart.ready{border-left-color:#d00078;background:#fff5fb}.wash-cart.estimated{border-left-color:#36866c}.wash-cart.blocked{border-left-color:#c73c32}.wash-cart small{display:block;margin:6px 0;color:#71809b}.wash-cart .btn{max-width:100%;white-space:normal}#washCarts h2{font-size:18px;margin-top:0}#washCarts p{font-size:13px}#entryProcessing{max-width:100%;width:100%}@media(max-width:760px){.wash-carts{grid-template-columns:1fr}.wash-cart .btn{width:100%}}';document.head.appendChild(styleWash);
// Background polling must not replace the page, selectors or open activity details.
let washPollBusy=false;
async function washPoll(){
 if(washPollBusy||washBusy||washLoading||!cloudUser||lotBusy()||cloudBusy||cloudQueue.length||$('#modal').open||document.hidden||!(current||page==='Produzione'))return;
 washPollBusy=true;
 try{
  const before=JSON.stringify(washState?.batches||[]),lotId=current?.id,view=page;
  await washRpc('read',{lotId});
  if(current?.id!==lotId||page!==view)return;
  washSyncChoices();
  for(const card of document.querySelectorAll('[data-wash-batch]')){
   const batch=washState.batches.find(b=>b.id===card.dataset.washBatch),timer=card.querySelector('[data-wash-timer]');
   if(!batch||!timer)continue;
   const minutes=Math.max(0,Math.ceil((new Date(batch.expected_end)-Date.now())/60000));
   timer.textContent=washStatus(batch)+(batch.state==='running'?' · '+minutes+' min · fine prevista '+washTime(batch.expected_end):'');
   if(card.dataset.washState!==batch.state||card.dataset.queueBusy!==String(washQueueWaiting(batch)))card.outerHTML=washCard(batch);
  }
  if(before!==JSON.stringify(washState.batches)&&!$('#washUpdates')){
   const host=$('#washCarts')||$('#productionWashCarts');
   if(host){const message=document.createElement('div');message.id='washUpdates';message.className='notice';message.innerHTML='Carrelli aggiornati. <button class="link" onclick="washApplyUpdates()">Mostra aggiornamenti</button>';host.append(message)}
  }
 }catch(e){washError=washMessage(e)}finally{washPollBusy=false}
}
async function washApplyUpdates(){const y=scrollY;if(current)await washRefresh();else await productionView();$('#washUpdates')?.remove();scrollTo(0,y)}
setInterval(()=>{void washPoll()},15000);
// Feed live machine occupancy to the existing finite-capacity planner.
const planBeforeWashBatches=PC.plan;
PC.plan=function(state,first,days=7,...rest){let reservations=[];for(let b of washState?.batches||[]){if(!['running','blocked'].includes(b.state))continue;let start=new Date(b.started_at),end=new Date(b.expected_end),startDay=start.toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}),endDay=end.toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'});for(let i=0;i<days;i++){let date=PC.dateAdd(first,i);if(date<startDay||(b.state==='running'&&date>endDay))continue;let minute=x=>{let text=x.toLocaleTimeString('it-IT',{timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit'});return PC.minute(text)};reservations.push({machineId:b.machine_id,date,start:date===startDay?minute(start):0,end:b.state==='blocked'||date<endDay?1440:minute(end)+1})}}return planBeforeWashBatches({...state,machineReservations:reservations},first,days,...rest)};
const pErrorBeforeWashBatches=pError;pError=function(e){return e.message==='WASH_BATCH_IN_PROGRESS'?washMessage(e):pErrorBeforeWashBatches(e)};

// Change only the options: keep the scan field, page and scroll position intact.
function washSyncChoices(){
 const select=document.getElementById('entryProcessing');if(!select||stage!=='Entrata')return;
 if(washChoice.includes('|')&&!washOptions().some(o=>o.key===washChoice)){
  washChoice='';chosenProcessing='';
 }
 const holder=document.createElement('div');holder.innerHTML=entryProcessing();
 const next=holder.querySelector('select');
 if(next&&select.innerHTML!==next.innerHTML){select.innerHTML=next.innerHTML;select.value=washChoice;}
}

const washCardBeforeCorrections=washCard;
washCard=function(b){
 let html=washCardBeforeCorrections(b);
 if(b.state==='estimated')return html;
 let actions='';
 if(['running','blocked'].includes(b.state)&&userCan('production_execute'))actions+=`<button class="btn secondary" onclick="washCorrectionDialog('${b.id}','reset_batch')">Ferma e riprendi le scansioni</button>`;
 if(cloudUser?.role==='admin')actions+=`<button class="link" onclick="washCorrectionDialog('${b.id}','delete_batch')">Elimina macchinata</button>`;
 return html.replace('</article>',`<div class="tools">${actions}</div></article>`);
};
function washCorrectionDialog(id,action){
 const b=washState?.batches.find(x=>x.id===id);if(!b)return;
 if(action==='delete_batch'&&cloudUser?.role!=='admin')return;
 show(`<h2>${action==='delete_batch'?'Elimina macchinata':'Ferma e riprendi le scansioni'}</h2><p>${esc(b.program_name)} · ${esc(b.machine_name)} · ${b.quantity} prodotti</p><p>La macchina fisica va fermata dalla pulsantiera. Il gestionale annulla il conteggio e riporta i prodotti nel carrello, conservando le scansioni del lotto. ${action==='delete_batch'?'La macchinata viene eliminata e sostituita da un carrello da preparare.':''}</p><p>Il prossimo avvio farà ripartire l’intera durata del programma.</p><div class="tools"><button class="btn" id="washCorrectionButton" onclick="washCorrect('${id}','${action}')">Conferma · macchina ferma</button><button class="btn secondary" onclick="$('#modal').close()">Annulla</button></div>`);
}
async function washCorrect(id,action){
 if(washBusy||lotBusy())return notify('Attendi le scansioni in corso.');
 const batch=washState?.batches.find(b=>b.id===id);if(!batch)return;
 washBusy=true;const button=$('#washCorrectionButton');if(button)button.disabled=true;
 try{
  await cloudFlush();await washRpc(action,{batchId:id,lotId:batch.lot_id});
  $('#modal').close();
  if(current){washChoice=washKey(batch.program_id,batch.machine_id);await washRefresh();$('#scan')?.focus()}
  else if(page==='Produzione')await productionView();
  notify('Prodotti conservati nel carrello. Puoi riprendere le scansioni.');
 }catch(e){notify(washMessage(e));if(button)button.disabled=false}finally{washBusy=false}
}


// Queueing is preparation, not a reservation or an automatic physical start.
// The server serializes start operations and rejects overlapping machine cycles.
function washQueueWaiting(batch){
 return ['gathering','ready'].includes(batch.state)&&washMachineBusy(batch.machine_id,batch.id);
}
const washCardBeforeQueue=washCard;
washCard=function(batch){
 let html=washCardBeforeQueue(batch),waiting=washQueueWaiting(batch);
 html=html.replace('data-wash-batch=', 'data-queue-busy="'+String(waiting)+'" data-wash-batch=');
 if(waiting){
  html=html.replace(/<button class="btn" onclick="washStartDialog\('[^']+'\)">[^<]*<\/button>/,
   '<button class="btn secondary" disabled>In coda · Macchina occupata</button>');
  const active=washState.batches.find(b=>b.machine_id===batch.machine_id&&b.id!==batch.id&&['running','blocked'].includes(b.state));
  const info=active?.state==='running'?'Fine prevista '+washTime(active.expected_end)+'. Il pulsante di avvio si abilita al termine.':'Ciclo interrotto: la macchina resta occupata fino alla risoluzione.';
  html=html.replace('<p data-wash-timer>','<p class="muted" data-queue-info>'+info+'</p><p data-wash-timer>');
 }
 return html;
};


// Water-department skill controls machine start as well as the existing execute permission.
function washCanOperate(batch){
 if(!userCan('production_execute'))return false;
 if(batch?.machine_kind!=='water')return true;
 const program=(washState?.types||[]).find(t=>t.id===batch.program_id);
 return !!program&&(washState?.admin===true||(washState?.myStations||[]).includes(program.station));
}
function washSkillMessage(){return 'Avvio riservato agli operatori abilitati a Reparto Acqua con permesso di eseguire la produzione.'}
const washCardBeforeSkills=washCard;washCard=function(batch){let html=washCardBeforeSkills(batch);if(!washCanOperate(batch))html=html.replace(/<button\b[^>]*onclick="(?:washStartDialog|washInterrupt)\([^\"]*"[^>]*>[^<]*<\/button>/g,'<p class="muted">'+washSkillMessage()+'</p>');return html};
const washStartDialogBeforeSkills=washStartDialog;washStartDialog=function(id){const b=washState?.batches.find(x=>x.id===id);if(!washCanOperate(b))return notify(washSkillMessage());return washStartDialogBeforeSkills(id)};
const washStartBeforeSkills=washStart;washStart=async function(id){const b=washState?.batches.find(x=>x.id===id);if(!washCanOperate(b))return notify(washSkillMessage());return washStartBeforeSkills(id)};
const washMessageBeforeSkills=washMessage;washMessage=function(e){return String(e.message||e).includes('STATION_SKILL_REQUIRED')?washSkillMessage():washMessageBeforeSkills(e)};
