
function lotCopyCodeButton(code) {
 return '<button type="button" class="link" data-copy-lot-code="'+esc(code)+'" aria-label="Copia codice '+esc(code)+'">Copia</button>';
}
document.addEventListener('click', async event => {
 const button=event.target.closest('[data-copy-lot-code]');
 if(!button)return;
 event.preventDefault();event.stopPropagation();
 const code=button.dataset.copyLotCode;
 try {
   await navigator.clipboard.writeText(code);
   button.textContent='Copiato';
 } catch(error) {
   const input=document.createElement('textarea');
   input.value=code;
   input.setAttribute('readonly','');
   input.style.cssText='position:fixed;left:0;top:0;width:1px;height:1px';
   document.body.append(input);input.select();
   const copied=document.execCommand('copy');
   input.remove();
   if(copied)button.textContent='Copiato';
   else {
     show('<h2>Copia codice</h2><input id="lotCopyFallback" readonly value="'+esc(code)+'"><p>Tieni premuto sul codice e scegli Copia.</p><button class="btn" onclick="document.getElementById(\'modal\').close()">Chiudi</button>');
     document.getElementById('lotCopyFallback').select();
   }
 }
});
/* Reparto: an operational view over the existing authenticated workflows. */
(function(){
const F=window.floor={active:false,screen:'home',phase:'entry',loading:false,error:'',feedback:null,stopped:false,request:0};
const phaseNames={entry:'Entrata',wash:'Lavaggio',dry:'Asciugatura',fold:'Piegatura',out:'Uscita',repair:'Reparto cucito'};
const attr=v=>esc(String(v));
const arg=v=>assetArg(v);
const busy=()=>lotBusy()||washBusy||dryBusy||prodBusy||cloudBusy;
const openRows=l=>(l.rows||[]).filter(r=>!['Uscito','Dismesso'].includes(r.state));
const foldRows=l=>openRows(l).filter(r=>r.washed&&!r.foldedAt&&(!r.requiresDrying||r.dryState==='done'));
const office=()=>cloudUser?.role==='admin'||userCan('production_manage');
function setMode(on){F.active=on;document.body.classList.toggle('floor-mode',on)}
function button(label,fn,kind='secondary',extra=''){return `<button type="button" class="floor-button ${kind}" onclick="${fn}" ${extra}>${label}</button>`}
function operator(){return prod?.operators?.find(o=>o.email===cloudUser?.email)}
function station(){const o=operator();if(!o)return 'Postazione da assegnare';return prod.stations?.find(s=>s.id===o.station)?.name||'Postazione da verificare'}
function top(title,phase){return `<div class="floor-top"><button class="floor-brand" onclick="floor.home()" aria-label="Microclean · Torna alla schermata iniziale"><span class="floor-logo-crop"><img src="assets/microclean-reparto-original.jpeg" alt="Microclean" width="1290" height="629"></span><span>REPARTO</span></button><div class="floor-person"><b>${esc(cloudUser?.name||'')}</b><span>${esc(station())}</span></div></div><nav class="floor-tabs" aria-label="Vista reparto">${waterVisible()?button('Reparto acqua','floor.water()',F.screen==='water'?'selected':'secondary'):''}<button class="floor-button ${['repairs','repair','ddt','mask','water'].includes(F.screen)?'':'selected'}" onclick="floor.home()">Lavoro</button><button class="floor-button ${['repairs','repair'].includes(F.screen)?'selected':''}" onclick="floor.repairs()">Reparto cucito</button><button class="floor-button ${F.screen==='ddt'?'selected':''}" onclick="floor.ddt()">DDT fornitori</button><button class="floor-button ${F.screen==='mask'?'selected':''}" onclick="floor.mask()">Mascherine</button></nav><div class="floor-title phase-${phase||'entry'}">${F.screen!=='home'?button('← Indietro', 'floor.back()'):''}<div><span class="floor-eyebrow">${current?esc(lotno(current)+' · '+current.client):'UNA COSA ALLA VOLTA'}</span><h1>${title}</h1></div>${button('Segnala un problema','floor.problem()','problem')}</div>`}
function shell(content,title,phase){$('#app').classList.remove('floor-lot','floor-repairs');$('#app').innerHTML=top(title,phase)+content+`<footer class="floor-footer">${button('Il mio lavoro','floor.work()')}${button('Istruzioni','floor.instructions()')}${button('Esempi e guida alla vista','floor.guide()')}${office()?button('Gestionale ufficio','floor.office()'):''}${button('Esci','standaloneLogout()')}</footer>`}
F.home=function(){if(busy())return notify('Attendi la registrazione in corso.');setMode(true);F.screen='home';F.feedback=null;current=null;page='Reparto';F.draw();void F.refresh()};
F.ddt=function(){if(busy())return notify('Attendi la registrazione in corso.');if(!window.DdtReturns)return notify('Ricarica la pagina per aprire i DDT.');setMode(true);F.screen='ddt';F.feedback=null;current=null;page='DDT fornitori · Airtable';DdtReturns.view()};
F.mask=function(){if(busy())return notify('Attendi la registrazione in corso.');if(!window.MaskStock)return notify('Ricarica la pagina per aprire le mascherine.');setMode(true);F.screen='mask';F.feedback=null;current=null;page='Mascherine · Confezionamento';MaskStock.view()};
F.decorateMask=function(){if(!F.active||F.screen!=='mask')return;const app=$('#app');app.querySelector('.heading')?.remove();const header=document.createElement('div');header.id='floorMaskHeader';header.innerHTML=top('Mascherine · Carico e scarico','entry')+'<div class="tools"><button class="floor-button" onclick="MaskStock.load()">Aggiorna giacenza</button><button class="floor-button" onclick="floor.instructions()">Come si usa</button></div>';app.prepend(header)};
F.decorateDdt=function(){if(!F.active||F.screen!=='ddt')return;const app=$('#app');app.classList.remove('floor-lot','floor-repairs');app.querySelector('.heading')?.remove();const header=document.createElement('div');header.id='floorDdtHeader';header.innerHTML=top('DDT fornitori · Rientri','entry')+'<p>Conta i pezzi ricevuti, scegli fornitore e DDT, poi premi Registra rientro.</p><button class="floor-button" onclick="DdtReturns.load()">Aggiorna elenco DDT</button>';app.prepend(header)};
F.back=function(){if(busy())return notify('Attendi la registrazione in corso.');if(F.screen==='repair'){if(repairProductCode)repairDetail(repairLotId);else F.repairs()}else if(F.screen==='lot')F.list(F.phase);else F.home()};
F.office=function(){if(busy())return notify('Attendi la registrazione in corso.');setMode(false);current=null;go('Dashboard')};
F.refresh=async function(){if(F.loading||busy())return;const request=++F.request,controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);F.loading=true;F.error='';try{await cloudFlush();const snap=await cloudBootDeadline(cloudRequest(),controller.signal);cloudAccept(snap,false);await cloudBootDeadline(Promise.all([pRpc('read'),washRpc('read'),dryRpc('read')]),controller.signal);}catch(e){F.error=pError(e)}finally{clearTimeout(timer);F.loading=false;if(F.active&&request===F.request){if(F.screen==='lot')F.decorate();else F.draw()}}};
F.draw=function(){if(!F.active||!cloudUser)return;if(F.screen==='ddt')return window.DdtReturns?.view();if(F.screen==='mask')return window.MaskStock?.view();if(F.screen==='lot')return F.decorate();if(F.screen==='machines')return drawMachines();if(F.screen==='water')return drawWater();if(F.screen==='lots')return drawLots();if(F.screen==='work')return drawWork();if(F.screen==='instructions')return;if(F.screen==='repairs')return drawRepairOverview();if(F.screen==='repair')return repairProductCode?drawRepairProduct(repairLotId,repairProductCode):drawRepairLot(repairLotId);
 const lots=db.lots.filter(l=>!l.archived&&(!l.rows.length||openRows(l).length));const batches=washState?.batches||[],dry=dryState?.carts||[];
 const counts=[lots.length,batches.filter(b=>(!waterVisible()||b.machine_kind==='water')&&['gathering','ready','blocked'].includes(b.state)).length+dry.filter(c=>!c.cycle||c.cycle.state==='blocked').length,lots.reduce((n,l)=>n+foldRows(l).length,0),lots.filter(readyForDispatch).reduce((n,l)=>n+openRows(l).length,0),db.lots.filter(l=>!l.archived).reduce((n,l)=>n+pendingRows(l).length,0)];
 shell(`<div class="floor-home-grid">${[['entry','1','Entrata','lotti aperti','floor.list(\'entry\')'],['wash','2',waterVisible()?'Reparto acqua':'Lavaggio e asciugatura','carrelli in attesa',waterVisible()?'floor.water()':'floor.machines()'],['fold','3','Piegatura','capi da controllare','floor.list(\'fold\')'],['out','4','Uscita','capi pronti','floor.list(\'out\')'],['repair','5','Reparto cucito','capi da controllare','floor.repairs()']].map(([phase,n,title,unit,fn],i)=>`<button class="floor-home-card phase-${phase}" onclick="${fn}"><span class="floor-step">${n}</span><h2>${title}</h2><strong>${i===1&&(!washState||!dryState)?'—':counts[i]}</strong><span>${unit}</span><span class="floor-card-link">Apri →</span></button>`).join('')}<button class="floor-home-card phase-entry" onclick="floor.ddt()"><span class="floor-step">DDT</span><h2>DDT fornitori</h2><span>Conta e registra i rientri manuali</span><span class="floor-card-link">Apri →</span></button><button class="floor-home-card phase-entry" onclick="floor.mask()"><span class="floor-step">MASK</span><h2>Mascherine</h2><span>Carica gli imbustati · Scarica 250 pezzi</span><span class="floor-card-link">Apri →</span></button></div>${F.error?`<div class="floor-warning" role="alert">Dati da aggiornare: ${esc(F.error)} ${button('Riprova','floor.refresh()')}</div>`:''}<p class="floor-updated">${F.loading?'Aggiornamento in corso…':'Dati condivisi del reparto. Verifica sempre il lotto prima di lavorare.'} ${button('Aggiorna','floor.refresh()')}</p>`,'Il tuo lavoro, da qui','entry');
};
F.list=function(phase){if(busy())return notify('Attendi la registrazione in corso.');F.phase=phase;F.screen='lots';F.feedback=null;current=null;page='Reparto';setMode(true);drawLots()};
function lotSignal(l){const rows=l.rows||[];if(rows.length&&rows.every(r=>['Uscito','Dismesso'].includes(r.state)))return {key:'finished',label:'Finito'};if(lotStatus(l)==='In lavorazione'||rows.some(r=>r.washed||r.foldedAt||['running','blocked','done'].includes(r.dryState)||r.state==='Dismesso'))return {key:'working',label:'In lavorazione'};return {key:'open',label:'Aperto'}}
const lotSearchText=value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('it-IT');
function lotSearchIndex(l,products){
 const dates=[l.date,l.due].map(v=>v&&!Number.isNaN(new Date(v).getTime())?new Date(v).toLocaleDateString('it-IT'):'');
 return lotSearchText([lotno(l),l.id,l.client,l.departmentName,l.departmentId,l.date,l.due,...dates,l.notes,l.colli,lotSignal(l).label,lotStatus(l),...(l.rows||[]).flatMap(r=>{const g=products.get(r.code)||{};return [r.code,g.barcode,...(g.barcodeAliases||[]),g.name,g.type,g.dept,g.size,g.color,r.notes,r.processingName,lotRowStatus(r)]})].join(' '));
}
function deliveryKey(lot){
 const planned=(prod?.calendars||[]).filter(c=>!c.cancelled&&c.lotId!=null&&Number(c.lotId)===Number(lot.id)&&c.due).map(c=>c.due).sort()[0];
 const due=lot.due||planned;
 if(!due)return '9999';
 return planned&&planned.slice(0,10)===due&&due.length===10?planned:due;
}

function mountPhaseRfid(scanRow) {
 if (!scanRow || !navigator.userAgent.includes('MycrocleanRFID/') ||
     !['fold','out'].includes(F.phase) || !userCan('lots_work') || !current || current.archived ||
     scanRow.querySelector('[data-phase-rfid]')) return;
 const button=document.createElement('button');
 button.type='button'; button.className='btn'; button.dataset.phaseRfid='1';
 button.textContent=F.phase==='fold'?'Scansiona piegatura RFID':'Scansiona uscita RFID';
 button.onclick=openPhaseRfid;
 scanRow.append(button);
}
async function openPhaseRfid() {
 if (busy() || F.stopped || F.loading) return notify('Attendi il termine dell’operazione in corso.');
 const phase=F.phase, lotId=current?.id, operation=phase==='fold'?'piegatura':'uscita';
 const valid=()=>F.active && F.screen==='lot' && F.phase===phase && current?.id===lotId &&
   !current.archived && stage===(phase==='fold'?'Lavorazione':'Uscita') && userCan('lots_work');
 if(!valid()) return;
 if(phase==='out'&&!readyForDispatch(current)) return notify('Completa tutti i capi prima di registrare l’uscita del lotto.');
 if(phase==='out'){
   try{
     const quality=await window.LotQuality.rpc('read',{lot_id:lotId});
     if(!valid()) return;
     if(quality.enabled&&!openRows(current).some(row=>quality.released.includes(row.code))){
       show('<h2>Uscita RFID in attesa del controllo qualità</h2><p>'+esc(lotno(current))+' · '+esc(current.client)+'</p><p>Per registrare le uscite serve un controllo qualità conforme che comprenda i capi da spedire.</p><button class="btn" id="rfidOpenQuality">Controllo qualità</button> <button class="btn secondary" id="rfidCloseQuality">Chiudi</button>');
       $('#rfidOpenQuality').onclick=()=>window.LotQuality.open(lotId);
       $('#rfidCloseQuality').onclick=()=>$('#modal').close();
       return;
     }
   }catch(error){return notify('Verifica qualità prima della lettura RFID: '+error.message);}
 }
 const modal=$('#modal'), lotLabel=lotno(current);
 show('<h2>Registra '+operation+' RFID</h2><p>'+esc(lotno(current))+' · '+esc(current.client)+'</p>'+
   '<form id="phaseRfidForm"><label>Numero massimo di tag<input name="goal" type="number" value="100" min="1" max="1000" required></label><button class="btn">Inizia lettura</button></form>'+
   '<p id="phaseRfidStatus" role="status"></p><button class="btn" id="phaseRfidApply" hidden></button> <button class="btn secondary" id="phaseRfidClose">Chiudi</button>');
 const form=$('#phaseRfidForm'),status=$('#phaseRfidStatus'),apply=$('#phaseRfidApply');
 let token='', tags=[],goal=0;
 function received(event){
   const result=event.detail;
   if(!token||result?.token!==token||!modal.open||!form.isConnected) return;
   token=''; form.hidden=false;
   if(!valid()){status.textContent='Lotto o fase cambiati. Riapri la lettura.';return;}
   if(!Array.isArray(result.tags)||result.tags.length>goal||!result.tags.every(t=>typeof t==='string'&&/^(?:[A-F0-9]{2}){1,62}$/.test(t))){
     status.textContent='Lettura non valida. Ripeti la scansione.';return;
   }
   tags=[...new Set(result.tags)];
   if(!tags.length){status.textContent='Nessun tag letto.';return;}
   form.hidden=true;status.textContent=tags.length+' tag letti.';
   apply.textContent='Registra '+operation;apply.hidden=false;
 }
 window.addEventListener('mycro-rfid-result',received);
 modal.addEventListener('close',()=>window.removeEventListener('mycro-rfid-result',received),{once:true});
 $('#phaseRfidClose').onclick=()=>modal.close();
 form.onsubmit=e=>{
   e.preventDefault();if(!valid())return;
   goal=Number(form.elements.goal.value);
   token=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
   location.href='mycro-rfid://scan?count='+goal+'&token='+token;
 };
 apply.onclick=async()=>{
   if(!valid()||busy()||F.stopped||F.loading)return notify('Attendi e verifica il lotto prima di registrare.');
   apply.disabled=true; modal.close(); scanningBatch=true;
   let saved=0, index=0, interrupted='';
   const issues=[],seen=new Set();
   try{
     await cloudFlush();cloudAccept(await cloudRequest(),false);
     for(;index<tags.length;index++){
       const epc=tags[index];
       if(!valid()) throw Error('Lotto o fase cambiati.');
       const {rows}=await productsRead({mode:'lookup',code:epc});
       if(!valid()) throw Error('Lotto o fase cambiati.');
       if(rows.length!==1){issues.push(epc+' · '+(rows.length?'associazione ambigua':'tag sconosciuto'));continue;}
       const id=rows[0].id,row=current.rows.find(r=>r.code===id);
       if(!row){issues.push(epc+' · fuori lotto');continue;}
       if(seen.has(id)||['Uscito','Dismesso'].includes(row.state)||(phase==='fold'&&row.foldedAt)){
         issues.push(epc+' · già elaborato o dismesso');continue;
       }
       if(phase==='out'&&!readyForDispatch(current)) throw Error('Il lotto ha ancora capi da completare.');
       productsHydrate(rows);productRemote.pinned=[id];
       const error=await checkedProcess(id);
       if(error){issues.push(epc+' · '+error);continue;}
       await cloudFlush();seen.add(id);saved++;
     }
   }catch(e){interrupted='Interrotto al tag '+(index+1)+' di '+tags.length+'. '+e.message;}
   finally{scanningBatch=false;}
   if(valid())detail();
   show('<h2>Riepilogo '+operation+' RFID</h2><p>'+esc(lotLabel)+
     ' · Registrati: '+saved+' su '+tags.length+'</p>'+(interrupted?'<p>'+esc(interrupted)+'</p>':'')+
     (issues.length?'<ul>'+issues.map(m=>'<li>'+esc(m)+'</li>').join('')+'</ul>':'')+
     '<button class="btn" id="phaseRfidDone">Chiudi</button>');
   $('#phaseRfidDone').onclick=()=>modal.close();
 };
}

function readyForDispatch(lot){
 const rows=openRows(lot);
 return rows.length>0&&rows.every(r=>lotReady(r)&&r.completed&&!pendingFlags(r).length&&(!r.requiresDrying||r.dryState==='done'));
}
function labelsPending(lot){return openRows(lot).filter(r=>r.relabel)}
function foldingLabels(lot){
 const rows=labelsPending(lot);
 if(!rows.length)return '<p>Nessun capo da etichettare.</p>';
 const products=new Map(db.garments.map(g=>[g.id,g]));
 return '<details class="floor-missing" open><summary>Da etichettare · '+rows.length+'</summary>'+rows.map(r=>{
  const garment=products.get(r.code);
  return '<div>'+productCodeLink(r.code)+'<span>'+esc(garment?.type||'Tipo non indicato')+'</span><small>'+esc(garment?.name||'')+'</small></div>';
 }).join('')+'</details>';
}
function drawLots(){
 const lots=db.lots.filter(l=>!l.archived&&(F.phase==='entry'?true:F.phase==='fold'?openRows(l).some(r=>!r.foldedAt||r.relabel):readyForDispatch(l))).sort((a,b)=>(F.phase==='entry'?0:deliveryKey(a).localeCompare(deliveryKey(b)))||Number(b.id)-Number(a.id));
 const products=new Map(db.garments.map(g=>[g.id,g]));
 F.lotSearchRows=lots.map(l=>({lot:l,text:lotSearchIndex(l,products)}));
 shell(`${F.phase==='entry'?`<div class="floor-new-lot">${button('Apri nuovo lotto','floor.newLot()','primary',userCan('lots_create')?'':'disabled')}${!userCan('lots_create')?'<p>Creazione lotti riservata agli operatori abilitati.</p>':''}</div>`:''}<p class="floor-lead">Scegli il lotto. Controlla reparto e cliente prima di scansionare.</p>
 <div class="floor-lot-search"><label for="floorLotSearch">Cerca lotti</label><div><input id="floorLotSearch" type="search" value="${esc(F.lotQuery||'')}" placeholder="Numero lotto, reparto, azienda, codice capo, utilizzatore…" oninput="floor.searchLots(this.value)"><button type="button" class="floor-button" onclick="floor.clearLotSearch()">Azzera ricerca</button></div><p id="floorLotSearchCount" role="status" aria-live="polite"></p></div>
 ${F.phase==='entry'?'<p class="floor-lot-legend"><span class="legend-open">Aperto</span><span class="legend-working">In lavorazione</span><span class="legend-finished">Finito</span></p>':''}<div class="floor-lots" id="floorLotResults"></div>`,phaseNames[F.phase],F.phase);
 F.drawLotResults();
}
F.searchLots=function(value){F.lotQuery=value;F.drawLotResults()};
F.clearLotSearch=function(){F.lotQuery='';const input=$('#floorLotSearch');if(input)input.value='';F.drawLotResults();input?.focus()};
F.drawLotResults=function(){
 const host=$('#floorLotResults');if(!host)return;
 const words=lotSearchText(F.lotQuery||'').trim().split(/\s+/).filter(Boolean);
 const all=F.lotSearchRows||[],lots=all.filter(x=>words.every(w=>x.text.includes(w))).map(x=>x.lot);
 $('#floorLotSearchCount').textContent=lots.length+' lotti trovati su '+all.length;
 host.innerHTML=lots.map(l=>`<button data-floor-lot-id="${Number(l.id)}" class="floor-lot-choice phase-${F.phase} ${F.phase==='entry'?'floor-lot-'+lotSignal(l).key:''}" onclick="floor.openLot(${Number(l.id)},'${F.phase}')">
 <span class="floor-lot-identity"><small>REPARTO</small><strong>${esc(l.departmentName||'Reparto non indicato')}</strong></span>
 <span class="floor-lot-identity floor-lot-client"><small>CLIENTE</small><strong>${esc(l.client||'Cliente non indicato')}</strong></span>
 <span>${esc(lotno(l))}</span>${F.phase==='entry'?`<span class="floor-lot-state">${lotSignal(l).label}</span>`:''}
 <span>${F.phase==='fold'?foldRows(l).length+' da piegare · '+labelsPending(l).length+' da etichettare':l.rows.length+(l.rows.length===1?' capo nel lotto':' capi nel lotto')} · ${esc(deliveryKey(l)==='9999'?'Consegna da definire':'Consegna '+lotDeliveryDate(deliveryKey(l)))}</span><b>Apri →</b></button>`).join('')||'<div class="floor-empty">'+(words.length?'Nessun lotto corrisponde alla ricerca.':'Nessun lotto in attesa per questa fase.')+'</div>';
};
F.openLot=async function(id,phase){if(!db.lots.some(l=>l.id===Number(id)))return notify('Lotto non disponibile. Aggiorna i dati.');if(busy())return notify('Attendi la registrazione in corso.');if(phase==='out'&&!readyForDispatch(db.lots.find(l=>l.id===Number(id))))return notify('Il lotto ha ancora capi da completare.');if(F.productsLot!==Number(id)){F.productsLot=Number(id);F.productQuery='';F.productPage=1}F.phase=phase;F.screen='lot';F.feedback=null;setMode(true);openLot(Number(id));if(!current)return;lotSetStage({entry:'Entrata',fold:'Lavorazione',out:'Uscita',repair:'Riparazioni'}[phase]);await F.refresh();F.focus()};
F.newLot=async function(){if(busy()||F.creatingLot)return notify('Attendi la registrazione in corso.');if(!userCan('lots_create'))return notify('Non hai il permesso di creare lotti.');try{await newLot()}catch(e){notify(e.message)}};
const floorCreateLot=createLot;createLot=async function(e){if(!F.active)return floorCreateLot(e);if(!userCan('lots_create')){e.preventDefault();return notify('Non hai il permesso di creare lotti.')}if(F.creatingLot){e.preventDefault();return}F.creatingLot=true;try{return await floorCreateLot(e)}finally{F.creatingLot=false;if(F.active&&F.screen==='lot')F.decorate()}};
const floorOpenCreatedLot=openLot;openLot=function(id){if(F.active&&F.creatingLot){F.screen='lot';F.phase='entry';F.feedback=null;F.productQuery='';F.productPage=1;F.productsLot=Number(id);F.productsOpen=false;}return floorOpenCreatedLot(id)};
F.focus=function(){if(!F.active||F.screen!=='lot'||F.stopped||$('#modal').open)return;const focused=document.activeElement;if(focused&&focused!==document.body&&focused.id!=='scan'&&focused.matches('input,select,textarea,button,a'))return;$('#scan')?.focus({preventScroll:true})};
function entryCart(){
 const choice=washChoiceParts();
 const batches=(washState?.batches||[]).filter(b=>b.lot_id===current?.id&&b.program_id===choice?.[0]&&b.machine_id===choice?.[1]&&['gathering','ready','blocked'].includes(b.state));
 return batches.find(b=>b.state==='gathering')||batches.at(-1);
}
function progress(){
 const b=entryCart(),o=washOptions().find(o=>o.key===washChoice),q=b?.quantity||0,cap=b?.capacity||o?.m.capacity;
 const allowed=!!b&&q>0&&washCanOperate(b),waiting=b&&washQueueWaiting(b);
 return `<div class="floor-counter phase-entry"><span>CARRELLO IN PREPARAZIONE</span>${washLotIdentity(b||{lot_id:current?.id})}<strong>${q} <small>/ ${cap||'—'} capi</small></strong><span>${esc(b?.program_name||o?.t.name||'Scegli il programma e la macchina qui sopra')}</span><progress value="${q}" max="${cap||1}" aria-label="Riempimento carrello"></progress><div class="floor-start-actions">${button('Avvia macchina','floor.startEntryMachine()','primary',allowed?'':'disabled')}<p>${!b||!q?'Scansiona almeno un capo per avviare la macchina.':!allowed?'Avvio riservato agli operatori abilitati.':waiting?esc(washOccupiedLabel(b))+'. La macchina scelta è occupata. Puoi scegliere un’altra macchina libera compatibile oppure attendere.':'Puoi avviare anche un carrello parziale. Scegli macchina e programma, poi conferma la partenza.'}</p></div></div>`;
}
F.startEntryMachine=function(){
 if(!F.active||F.screen!=='lot'||F.phase!=='entry'||!current)return;
 if(busy())return notify('Attendi la registrazione in corso.');
 const b=entryCart();
 if(!b||!(b.quantity>0))return notify('Scansiona almeno un capo nel carrello selezionato.');
 if(!washCanOperate(b))return notify(washSkillMessage());
 washStartDialog(b.id);
};
function phaseProgressMarkup(lot,phase,garments,lastCode){
 const folding=phase==='fold', doneLabel=folding?'Piegati':'Usciti', leftLabel=folding?'Da piegare':'Da uscire';
 const products=new Map(garments.map(g=>[g.id,g])), groups=new Map();
 let done=0,total=0;
 for(const row of lot.rows){
   if(row.state==='Dismesso')continue;
   const g=products.get(row.code);
   const type=String(g?.type||row.type||'Tipo non indicato').trim()||'Tipo non indicato';
   const key=type.toLocaleLowerCase('it');
   if(!groups.has(key))groups.set(key,{type,done:0,left:[]});
   const group=groups.get(key);
   const finished=row.state==='Uscito'||(folding&&(row.foldedAt||(!row.washBatchId&&row.completed)));
   total++;
   if(finished){group.done++;done++;}
   else group.left.push(productBarcode(g)||row.code);
 }
 const last=products.get(lastCode);
 const lastLine=lastCode?'<p><b>Ultimo capo registrato</b> · '+esc(last?.type||'Tipo non indicato')+' · '+esc(productBarcode(last)||lastCode)+'</p>':'';
 const body=[...groups.values()].sort((a,b)=>a.type.localeCompare(b.type,'it')).map(g=>{
   const label=g.left.length?'<details><summary>'+esc(g.type)+'</summary>'+g.left.map(code=>'<div><code>'+esc(code)+'</code></div>').join('')+'</details>':esc(g.type);
   return '<tr><td>'+label+'</td><td>'+g.done+'</td><td>'+g.left.length+'</td></tr>';
 }).join('');
 return '<h2>'+ (folding?'Piegatura':'Uscita')+' · '+esc(lotno(lot))+'</h2><p><b>'+done+' '+doneLabel.toLowerCase()+' · '+(total-done)+' '+leftLabel.toLowerCase()+'</b> · '+total+' capi nel lotto</p>'+lastLine+
   (body?'<table style="width:100%;table-layout:auto;min-width:0"><thead><tr><th>Tipologia</th><th>'+doneLabel+'</th><th>'+leftLabel+'</th></tr></thead><tbody>'+body+'</tbody></table>':'');
}
function updatePhaseProgress(){
 const host=document.getElementById('floorPhaseProgress');
 if(!host||!current||!['fold','out'].includes(F.phase))return;
 const markup=phaseProgressMarkup(current,F.phase,db.garments,F.lastPhaseScan?.lot===current.id&&F.lastPhaseScan.phase===F.phase?F.lastPhaseScan.code:null);
 if(host._progressMarkup!==markup){host.innerHTML=markup;host._progressMarkup=markup;}
}
function exitSummary(){const rows=current.rows.filter(r=>r.state!=='Dismesso'),loaded=rows.filter(r=>r.state==='Uscito').length,missing=rows.filter(r=>r.state!=='Uscito'),working=missing.filter(r=>!lotReady(r)).length;return `<div class="floor-exit-numbers"><div><strong>${loaded}</strong><span>CARICATI</span></div><div><strong>${working}</strong><span>IN LAVORAZIONE</span></div><div><strong>${missing.length}</strong><span>MANCANTI</span></div></div><p class="floor-explain">Mancanti alla spedizione: capi del lotto non ancora usciti, compresi quelli in lavorazione. Non indica uno smarrimento.</p><details class="floor-missing" open><summary>Chi manca alla spedizione</summary>${missing.map(r=>{const g=db.garments.find(g=>g.id===r.code);return `<div><b>${esc(g?.name||'Utilizzatore non indicato')}</b><span>${esc(g?.type||'')} · ${esc(g?.size||'')} · ${esc(productBarcode(g)||r.code)}</span><small>${esc(lotRowStatus(r))}</small></div>`}).join('')||'<p>Tutti i capi del lotto sono stati caricati.</p>'}</details>`}
F.decorate=function(){if(!F.active||F.screen!=='lot'||!current)return;const app=$('#app');app.classList.add('floor-lot');app.dataset.floorPhase=F.phase;app.querySelector('#floorLotHeader')?.remove();const header=document.createElement('div');header.id='floorLotHeader';header.innerHTML=top(phaseNames[F.phase],F.phase);app.prepend(header);
 const scan=$('#scan'),scanRow=scan?.closest('.scan');if(scan){scan.placeholder='Scansiona qui il codice';scan.setAttribute('aria-label','Scansiona il codice del capo');scan.autocomplete='off';scan.disabled=F.stopped||!userCan('lots_work')||(F.phase==='entry'&&!F.entryReady());scanRow?.classList.add('floor-scan-row');mountPhaseRfid(scanRow);const section=scanRow?.closest('.lot-work-section'),panel=section?.closest('.lot-workspace');if(section&&panel&&panel.firstElementChild!==section)panel.prepend(section);}
 app.querySelector('.floor-missing')?.remove();app.querySelector('#floorLotSummary')?.remove();const summary=document.createElement('section');summary.id='floorLotSummary';summary.innerHTML=F.phase==='entry'?progress():F.phase==='out'?exitSummary():`<p class="floor-lead">Controlla e piega il capo. Poi scansiona il tag.</p>${foldingLabels(current)}${feedbackMarkup()}`;header.after(summary);if(['fold','out'].includes(F.phase)){const counts=document.createElement('section');counts.id='floorPhaseProgress';counts.className='panel';counts.style.padding='12px';summary.prepend(counts);updatePhaseProgress();}if(F.phase==='out'){const missing=summary.querySelector('.floor-missing');if(missing)app.append(missing);}
 if(F.phase!=='fold'&&F.feedback){const feedback=document.createElement('div');feedback.innerHTML=feedbackMarkup();summary.append(feedback)}
 if(!$('#floorLotTools')){const tools=document.createElement('div');tools.id='floorLotTools';tools.className='floor-lot-tools';tools.innerHTML=(F.phase==='entry'&&userCan('lots_create')?button('Apri nuovo lotto','floor.newLot()','primary'):'')+button('Il mio lavoro','floor.work()')+button('Cambia lotto','floor.list(\''+F.phase+'\')')+button('Reparto cucito del lotto','floor.repairLot('+current.id+')')+button('Aggiorna','floor.refresh()')+(F.phase==='fold'?button('Vedi 4 esempi','floor.examples(0)'):'');app.append(tools)}
 if(!userCan('production_execute'))app.querySelectorAll('button[onclick^="washStartDialog"],button[onclick^="washInterrupt"]').forEach(b=>b.disabled=true);
 if(F.phase==='entry'){const carts=$('#washCarts');if(carts)for(const card of carts.querySelectorAll('[data-wash-batch]')){const b=washState?.batches.find(b=>b.id===card.dataset.washBatch);card.hidden=!b||!['gathering','ready','blocked','running'].includes(b.state);for(const btn of card.querySelectorAll('button[onclick^="washStartDialog"]'))btn.hidden=!b||!['gathering','ready','blocked'].includes(b.state);card.querySelectorAll('button[onclick*="delete_batch"]').forEach(el=>el.hidden=true)} }
 F.entryOrder();F.entryTypeSummary();F.productList();F.focus();
};
F.entryReady=function(){if(!washState||!washChoice)return false;const option=washOptions().find(o=>o.key===washChoice);return !!(option&&Number(option.m.capacity)>0)||washChoice.startsWith('plain:')&&ensureProcessing().some(p=>p.id===washChoice.slice(6)&&p.active&&!p.wash)};
F.entryOrder=function(){if(F.phase!=='entry')return;const route=$('#entryProcessing')?.closest('.lot-work-section'),scan=$('#scan'),section=scan?.closest('.lot-work-section'),panel=section?.closest('.lot-workspace'),summary=$('#floorLotSummary');if(!route||!section||!panel||route===section)return;route.classList.add('floor-route');if(!route.querySelector('.floor-route-title'))route.insertAdjacentHTML('afterbegin','<h2 class="floor-route-title">1. Scegli il percorso e il tipo di lavaggio</h2>');panel.prepend(route);route.after(summary);summary.after(section);if(!section.querySelector('.floor-scan-step'))section.insertAdjacentHTML('afterbegin','<h2 class="floor-scan-step">2. Scansiona il codice del capo</h2>');let help=section.querySelector('.floor-route-help');if(!help){help=document.createElement('p');help.className='floor-route-help';help.setAttribute('role','status');section.querySelector('.floor-scan-step').after(help)}const ready=F.entryReady();help.textContent=ready?'Percorso scelto. Ora puoi scansionare i capi.':'Prima scegli il percorso qui sopra. Poi potrai scansionare il codice.';scan.placeholder=ready?'Scansiona qui il codice':'Scegli prima il percorso';section.querySelectorAll('.scan button').forEach(b=>b.disabled=!ready||F.stopped||!userCan('lots_work'));};
function entryTypeCounts(lot,garments){
 const products=new Map((garments||[]).map(g=>[String(g.id),g])),counts=new Map(),seen=new Set();
 for(const row of lot?.rows||[]){
  const code=String(row.code);if(seen.has(code))continue;seen.add(code);
  const label=String(products.get(code)?.type||'Tipo non indicato').trim()||'Tipo non indicato';
  const key=label.toLocaleLowerCase('it-IT'),group=counts.get(key)||{label,count:0};group.count++;counts.set(key,group);
 }
 return {total:seen.size,groups:[...counts.values()].sort((a,b)=>a.label.localeCompare(b.label,'it'))};
}
function entryPendingSummary(rows){
 const counts=new Map(Object.keys(flagLabels).map(key=>[key,new Set()]));
 for(const row of rows){
  for(const key of pendingFlags(row))counts.get(key).add(row.code);
 }
 const badges=[...counts].filter(([,codes])=>codes.size).map(([key,codes])=>
  '<span><b>'+codes.size+'</b> '+flagLabels[key]+'</span>');
 return '<div class="floor-entry-total">Interventi da fare</div><div class="floor-entry-types">'+
  (badges.join('')||'<span>Nessun intervento aperto</span>')+'</div>';
}
F.entryPendingSummary=entryPendingSummary;
F.entryTypeSummary=function(){
 const existing=$('#floorEntryTypes');
 if(!F.active||F.screen!=='lot'||F.phase!=='entry'||!current){existing?.remove();return}
 const heading=$('#app .floor-scan-step');if(!heading)return;
 let host=existing;if(!host){host=document.createElement('div');host.id='floorEntryTypes';host.setAttribute('role','status');host.setAttribute('aria-live','polite');heading.after(host)}
 const latest=current.rows?.at(-1)?.code;
 if(F.entryCountLot===current.id&&latest!==F.entryCountLatest)F.productPage=1;
 F.entryCountLot=current.id;F.entryCountLatest=latest;
 const {total,groups}=entryTypeCounts(current,db.garments);
 const html='<div class="floor-entry-total">Capi entrati nel lotto <strong>'+total+'</strong></div><div class="floor-entry-types">'+(groups.map(g=>'<span><b>'+g.count+'</b> '+esc(g.label)+'</span>').join('')||'<span>Nessun capo acquisito</span>')+'</div>';
 const summary=html+entryPendingSummary(current.rows);
 if(host.innerHTML!==summary)host.innerHTML=summary;
};

function feedbackMarkup(){const f=F.feedback||{tone:'ready',title:'PRONTO',message:'Leggi un codice. Aspetta la risposta prima del capo successivo.'};return `<section class="floor-feedback ${f.tone}" role="status" aria-live="polite"><strong>${f.title}</strong><p>${esc(f.message)}</p>${f.name?`<b>${esc(f.name)}</b>`:''}${f.bin?`<div class="floor-bin">CESTO ${esc(f.bin)}</div>`:''}</section>`}
function asideFor(r,g){if(!r?.discardForReturn&&(r?.discard||g&&productIsDiscard(g)))return ['SCARTI DA VERIFICARE','Capo segnalato come scarto. Chiedi al responsabile.'];if(r?.repair)return ['RIPARAZIONI','Riparazione ancora aperta. Non registrare la piegatura.'];if(r?.rewashPending)return ['RILAVAGGIO','Il capo deve essere rilavato.'];if(r?.relabel)return ['ETICHETTE','Etichettatura da completare.'];if(r?.verify||r?.replacement)return ['VERIFICHE','Serve il controllo del responsabile.'];return null}
function acknowledge(title,message,tone='stop',bin){F.ack=(F.ack||0)+1;F.stopped=true;return new Promise(resolve=>{show(`<section class="floor-feedback ${tone}" role="alertdialog" aria-labelledby="floorAlertTitle"><h2 id="floorAlertTitle">${title}</h2><p>${esc(message)}</p>${bin?`<div class="floor-bin">CESTO ${esc(bin)}</div>`:''}<p>Questo passaggio non è stato registrato.</p><button type="button" class="floor-button" id="floorAcknowledge">${tone==='stop'?'HO CAPITO':'MESSO DA PARTE'}</button></section>`);const modal=$('#modal');const prevent=e=>e.preventDefault();const key=e=>{if(e.key==='Enter'||e.key==='Tab'){e.preventDefault();e.stopPropagation()}};modal.addEventListener('cancel',prevent);modal.addEventListener('keydown',key,true);$('#scan')?.setAttribute('disabled','');$('#floorAcknowledge').onclick=()=>{modal.removeEventListener('cancel',prevent);modal.removeEventListener('keydown',key,true);F.stopped=false;modal.close();$('#scan')?.removeAttribute('disabled');resolve();F.focus()}})}
const oldMismatch=showLotMismatch;showLotMismatch=function(code,info){if(!F.active)return oldMismatch(code,info);F.feedback={tone:'stop',title:'FERMATI',message:info.reason};return acknowledge('FERMATI',info.reason+' Codice: '+code)};
const oldAlert=timedProductAlert;timedProductAlert=async function(title,lines,seconds,code){if(title==='Attenzione prodotto'&&['Lavorazione','Uscita'].includes(stage)&&current?.rows.find(r=>r.code===code)?.discardForReturn){
 lines=lines.filter(line=>!line.startsWith('Prodotto segnato come SCARTO.')&&!line.startsWith('Limite lavaggi RAGGIUNTO O SUPERATO:'));
 if(!lines.length)return true;
}if(!F.active)return oldAlert(title,lines,seconds,code);F.feedback={tone:'stop',title:'FERMATI',message:lines.join(' ')};await acknowledge('FERMATI',lines.join(' ')+' Codice: '+code);return false};
// Existing mismatch checks refresh the snapshot before warningCheck is called.
// This hook routes an already-flagged garment without an extra full database read.
const oldWarning=warningCheck;warningCheck=async function(code){if(F.active&&F.screen==='lot'&&stage==='Lavorazione'){const g=db.garments.find(g=>g.id===code),r=current?.rows.find(r=>r.code===code),aside=asideFor(r,g);if(aside){F.feedback={tone:'aside',title:'METTI DA PARTE',message:aside[1],name:g?.name,bin:aside[0]};await acknowledge('METTI DA PARTE',aside[1],'aside',aside[0]);return aside[1]}}return oldWarning(code)};
const oldChecked=checkedProcess;checkedProcess=async function(code){if(!F.active||F.screen!=='lot')return oldChecked(code);const phase=stage,ackBefore=F.ack||0;try{const error=await oldChecked(code),g=db.garments.find(g=>g.id===code);if(error){if((F.ack||0)===ackBefore){F.feedback={tone:'stop',title:'FERMATI',message:error,name:g?.name};await acknowledge('FERMATI',error)}}else {if(current&&['Lavorazione','Uscita'].includes(phase))F.lastPhaseScan={lot:current.id,phase:phase==='Uscita'?'out':'fold',code};updatePhaseProgress();F.feedback={tone:'done',title:'FATTO',message:phase==='Lavorazione'?'Piegatura registrata. Passa al capo successivo.':phase==='Uscita'?'Uscita registrata. Passa al capo successivo.':'Capo registrato nel carrello.',name:g?.name};}return error}catch(e){F.feedback={tone:'stop',title:'FERMATI',message:e.message};await acknowledge('FERMATI',e.message);return e.message}};
const oldEnqueue=enqueueBarcode;enqueueBarcode=function(value){if(F.active&&F.stopped)return;if(F.active&&F.screen==='lot'&&F.phase==='entry'&&!F.entryReady())return notify('Scegli prima il percorso e il tipo di lavaggio.');return oldEnqueue(value)};
function machineInfo(m){const fault=prod?.tickets?.some(t=>t.machineId===m.id&&t.blocking!==false&&t.status!=='closed');if(fault)return {tone:'fault',title:'GUASTO',detail:'Avvio bloccato'};if(m.active===false)return {tone:'off',title:'NON DISPONIBILE',detail:'Macchina disattivata'};const wash=washState?.batches?.find(b=>b.machine_id===m.id&&['running','blocked'].includes(b.state));const dry=dryState?.carts?.find(c=>c.cycle?.machine_id===m.id&&['running','blocked'].includes(c.cycle.state))?.cycle;const cycle=wash||dry;if(cycle){if(cycle.state==='blocked')return {tone:'fault',title:'INTERROTTO',detail:'Da verificare prima di riavviare'+(wash?' · '+washLotLabel(wash):'')};return {tone:'running',title:Math.max(0,Math.ceil((new Date(cycle.expected_end)-Date.now())/60000))+' MIN',detail:'Tempo rimasto previsto'+(wash?' · '+washLotLabel(wash):'')}}const task=prod?.tasks?.find(t=>['running','paused'].includes(t.status)&&prod.plan?.allocations?.some(a=>a.taskId===t.id&&a.machineId===m.id));if(task)return {tone:'running',title:'OCCUPATO',detail:'Attività avviata · verifica il lavoro assegnato'};return {tone:'free',title:'LIBERO',detail:(m.capacity||'—')+' capi di capacità'}}
F.machineInfo=machineInfo;
F.machines=function(){if(busy())return notify('Attendi la registrazione in corso.');setMode(true);F.screen='machines';current=null;page='Reparto';drawMachines();void F.refresh()};

function waterDate(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())}
function waterAssigned(op,date=waterDate()){
 if(!op||op.active===false)return false;
 const changes=(prod?.overrides||[]).filter(x=>x.email===op.email&&x.date===date);
 if(changes.length)return !changes.some(x=>x.absent)&&changes.some(x=>pStationKind(x.station)==='water');
 return pStationKind(op.station)==='water';
}
function waterVisible(){return office()||(prod?.operators||[]).some(o=>o.email===cloudUser?.email&&waterAssigned(o))}
function waterRoster(){
 const date=waterDate();
 return (prod?.operators||[]).filter(o=>waterAssigned(o,date)).map(o=>{
  const slots=PC.daySlots(prod,o,date).slots.filter(s=>pStationKind(s.station)==='water');
  return {op:o,slots};
 }).filter(x=>x.slots.length);
}
F.water=function(){
 if(busy())return notify('Attendi la registrazione in corso.');
 if(!waterVisible())return notify('Vista riservata agli operatori assegnati al Reparto acqua e ai responsabili.');
 setMode(true);F.screen='water';current=null;page='Reparto';drawWater();void F.refresh();
};
function drawWater(){
 if(!waterVisible()){shell('<p class="floor-empty">Non risulti assegnato al Reparto acqua. Chiedi al responsabile di verificare la postazione e le variazioni giornaliere.</p>','Reparto acqua','wash');return}
 const machines=(prod?.machines||[]).filter(m=>['water','dryer'].includes(m.kind));
 const washes=washDistinctLoads((washState?.batches||[]).filter(b=>b.machine_kind==='water'&&['gathering','ready','running','blocked'].includes(b.state)));
 const dryers=(dryState?.carts||[]).filter(dryActive);
 const waiting=washes.filter(b=>b.state!=='running'),dryWaiting=dryers.filter(c=>c.cycle?.state!=='running');
 const deadlines=new Map(db.lots.map(l=>[String(l.id),deliveryKey(l)]));
 const washDue=b=>washLoadMembers(b).map(m=>deadlines.get(String(m.lot_id))||'9999').sort()[0]||'9999';
 waiting.sort((a,b)=>washDue(a).localeCompare(washDue(b)));
 dryWaiting.sort((a,b)=>(deadlines.get(String(a.lotId))||'9999').localeCompare(deadlines.get(String(b.lotId))||'9999'));
 const roster=waterRoster();
 function machineCard(m){
  const status=machineInfo(m),isDry=m.kind==='dryer';
  const cycles=isDry?dryers.filter(c=>c.cycle?.machine_id===m.id&&c.cycle.state==='running').map(dryCard):washes.filter(b=>b.machine_id===m.id&&b.state==='running').map(washCard);
  return '<article class="floor-machine '+status.tone+' phase-'+(isDry?'dry':'wash')+'"><span class="floor-machine-phase">'+(isDry?'ESSICCATOIO':'LAVATRICE AD ACQUA')+'</span><h2>'+esc(m.name)+'</h2><strong><i aria-hidden="true"></i>'+esc(status.title)+'</strong><p>'+esc(status.detail)+'</p>'+cycles.join('')+'</article>';
 }
 const free=machines.filter(m=>machineInfo(m).tone==='free'),other=machines.filter(m=>machineInfo(m).tone!=='free');
 shell('<section class="water-queue floor-carts phase-wash"><h2>Carrelli da lavare · '+waiting.length+'</h2><div class="wash-carts">'+(waiting.map(WashLoads.card).join('')||'<p>Nessun carrello da lavare.</p>')+'</div>'+WashLoads.toolbar(waiting)+'</section>'+
 '<section class="water-queue floor-carts phase-dry"><h2>Carrelli da asciugare · '+dryWaiting.length+'</h2><div class="wash-carts">'+(dryWaiting.map(dryCard).join('')||'<p>Nessun carrello da asciugare.</p>')+'</div></section>'+
 '<h2>Macchine libere · '+free.length+'</h2><div class="floor-machines">'+(free.map(machineCard).join('')||'<p>Nessuna macchina libera.</p>')+'</div>'+
 (other.length?'<h2>Macchine in uso o non disponibili</h2><div class="floor-machines">'+other.map(machineCard).join('')+'</div>':'')+
 '<div class="floor-water-toolbar">'+(userCan('production_execute')?button('Avvia macchina','WaterStart.open()','primary'):'')+button('Aggiorna','floor.refresh()')+'</div>'+
 '<section class="floor-water-people"><h2>Operatori del reparto acqua · oggi</h2>'+ (roster.map(({op,slots})=>'<span><b>'+esc(pMember(op.email))+'</b> · '+slots.map(s=>PC.clock(s.start)+'–'+PC.clock(s.end)).join(' / ')+'</span>').join('')||'<p>Nessun operatore con turno valido assegnato oggi al reparto acqua.</p>')+'</section>'+
 (F.error?'<p class="floor-warning" role="alert">'+esc(F.error)+'</p>':''),'Reparto acqua','wash');
 document.querySelectorAll('#app button[onclick*="delete_batch"]').forEach(b=>b.hidden=true);
}

function drawMachines(){const machines=prod?.machines||[];shell(`<p class="floor-lead">Scegli il carrello. Il programma propone una macchina compatibile e libera.</p><div class="floor-machines">${machines.map(m=>{const s=machineInfo(m);return `<article class="floor-machine ${s.tone} phase-${m.kind==='dryer'?'dry':'wash'}"><span class="floor-machine-phase">${m.kind==='dryer'?'ASCIUGATURA':'LAVAGGIO'}</span><h2>${esc(m.name)}</h2><strong><i aria-hidden="true"></i>${s.title}</strong><p>${esc(s.detail)}</p></article>`}).join('')||'<div class="floor-empty">Macchine da caricare o configurare.</div>'}</div><section class="floor-carts phase-wash"><h2>Lavaggio · carrelli pronti</h2>${washDistinctLoads((washState?.batches||[]).filter(b=>['ready','blocked','running'].includes(b.state))).map(b=>washCard(b)).join('')||'<p>Nessun carrello pronto.</p>'}</section><section class="floor-carts phase-dry"><h2>Asciugatura · dopo il lavaggio ad acqua</h2>${(dryState?.carts||[]).filter(dryActive).map(dryCard).join('')||'<p>Nessun carrello da asciugare.</p>'}</section><p class="floor-explain">I minuti sono una stima. I pulsanti registrano l’avvio: non comandano la macchina reale.</p>${F.error?`<p role="alert">${esc(F.error)}</p>`:''}`, 'Lavaggio e asciugatura','wash');document.querySelectorAll('#app button[onclick*="delete_batch"]').forEach(b=>b.hidden=true);if(!userCan('production_execute'))document.querySelectorAll('#app button[onclick^="washStartDialog"],#app button[onclick^="washInterrupt"]').forEach(b=>b.disabled=true)}
const oldWashRefresh=washRefresh;washRefresh=async function(...args){const result=await oldWashRefresh(...args);if(F.active&&F.screen==='machines')F.draw();return result};
const oldDryAfter=dryAfterChange;dryAfterChange=async function(...args){const result=await oldDryAfter(...args);if(F.active&&['machines','water','work'].includes(F.screen))F.draw();return result};
function propose(selectId,ownMachine){if(!F.active)return;const s=document.getElementById(selectId);if(!s)return;const machines=prod?.machines||[];const options=[...s.options].filter(o=>o.value&&(machineInfo(machines.find(m=>m.id===o.value)||{id:o.value}).tone==='free'||(o.value===ownMachine&&!prod?.tickets?.some(t=>t.machineId===o.value&&t.blocking===true&&!['closed','resolved'].includes(t.status))))).sort((a,b)=>(machines.find(m=>m.id===a.value)?.capacity||Infinity)-(machines.find(m=>m.id===b.value)?.capacity||Infinity));for(const option of [...s.options])if(option.value&&!options.includes(option))option.disabled=true;if(!options.length){s.value='';const b=document.getElementById(selectId==='dryMachine'?'dryStartButton':'washStartButton');if(b)b.disabled=true;}if(options.length){const currentOption=options.find(o=>o.value===s.value);s.value=(currentOption||options[0]).value;const p=document.createElement('p');p.className='floor-proposal';p.textContent='Macchina proposta: '+s.selectedOptions[0].textContent+'. Controlla che sia quella usata realmente.';s.parentElement.after(p)}}
const oldWashStart=washStartDialog;washStartDialog=function(id){if(F.active&&!userCan('production_execute'))return notify('Avvio riservato agli operatori autorizzati.');oldWashStart(id);propose('washStartMachine')};const oldDryStart=dryStartDialog;dryStartDialog=function(id){oldDryStart(id);propose('dryMachine',dryState?.carts.find(c=>c.batchId===id)?.cycle?.state==='blocked'?dryState.carts.find(c=>c.batchId===id).cycle.machine_id:null)};
F.problem=function(){if(userCan('tickets_manage')){if(!prod)return notify('Carica prima i dati delle macchine con Aggiorna.');pEditTicket();return}show('<h2>Segnala un problema</h2><p>Avvisa il responsabile indicando:</p><ul><li>La macchina o il numero del lotto.</li><li>Che cosa è successo.</li><li>Il codice del capo, se presente.</li></ul><p>Il tuo account non può aprire ticket. Nessuna segnalazione è stata inviata automaticamente.</p>'+button('HO CAPITO',"document.querySelector('#modal').close()"))};
F.work=function(){if(busy())return;setMode(true);current=null;page='Reparto';F.screen='work';drawWork();void F.refresh()};
function drawWork(){const tasks=(prod?.tasks||[]).filter(t=>{const assigned=t.status==='pending'&&t.assignee?t.assignee:prod?.plan?.allocations?.find(a=>a.taskId===t.id)?.email||t.assignee;return assigned===cloudUser.email&&!['completed','cancelled'].includes(t.status)}).sort(pTaskPriorityOrder);shell(`<p class="floor-lead">Apri il lavoro assegnato. Il timer personale misura il tuo lavoro; il timer macchina parte con Avvia lavaggio o Avvia asciugatura.</p><div class="floor-work">${tasks.map(t=>pTaskCard(t,true)).join('')||'<p class="floor-empty">Non hai attività assegnate.</p>'}</div>`,'Il mio lavoro','entry');document.querySelectorAll('.floor-work [data-prod-action="lot"],.floor-work [data-prod-action="repairLot"]').forEach(b=>{const t=prod.tasks.find(t=>t.id===b.closest('[data-task-id]')?.dataset.taskId);b.onclick=e=>{e.stopPropagation();const type=pType(t?.typeId);if(type?.mode==='machine')return F.machines();if(pTaskLotAction(t)==='repairLot')return F.repairLot(Number(b.dataset.prodId));return F.openLot(Number(b.dataset.prodId),pStationKind(type?.station)==='entry'?'entry':pStationKind(type?.station)==='out'?'out':'fold')}})}
F.repairLot=function(id){if(busy())return;setMode(true);current=null;page='Riparazioni';F.screen='repair';repairDetail(id)};
function repairHeader(title){if(!F.active||F.screen!=='repair')return;$('#app').classList.remove('floor-lot','floor-repairs');$('#app .heading')?.remove();const h=document.createElement('div');h.innerHTML=top(title,'fold');$('#app').prepend(h);$('#app').classList.add('floor-repairs');}
const floorOldRepairDetail=repairDetail;repairDetail=function(...args){if(F.active&&F.screen==='repair')return drawRepairLot(...args);const r=floorOldRepairDetail(...args);repairHeader('Interventi del lotto');return r};
const floorOldRepairProduct=repairProductDetail;repairProductDetail=function(...args){if(F.active&&F.screen==='repair')return drawRepairProduct(...args);const r=floorOldRepairProduct(...args);repairHeader('Intervento sul capo');return r};
const floorProductionAction=pAction;pAction=async function(action,id){
 if(F.active&&action==='taskDetail')F.detailTask=id;
 if(F.active&&['lot','repairLot'].includes(action)){
  $('#modal').close();
  if(action==='repairLot')return F.repairLot(Number(id));
  const task=prod?.tasks?.find(t=>t.id===F.detailTask),type=pType(task?.typeId);
  if(type?.mode==='machine')return F.machines();
  return F.openLot(Number(id),pStationKind(type?.station)==='entry'?'entry':pStationKind(type?.station)==='out'?'out':'fold');
 }
 return floorProductionAction(action,id);
};
const floorOldPDraw=pDraw;pDraw=function(...args){if(F.active&&F.screen==='water')return drawWater();if(F.active&&F.screen==='work')return drawWork();return floorOldPDraw(...args)};
F.instructions=function(){if(busy())return;setMode(true);current=null;F.screen='instructions';page='Istruzioni';window.drawOperatingInstructions()};
F.decorateInstructions=function(){if(!F.active||F.screen!=='instructions')return;$('#app').classList.remove('floor-lot','floor-repairs');$('#app .heading')?.remove();const h=document.createElement('div');h.innerHTML=top('Istruzioni','entry');$('#app').prepend(h);};

// Every intervention keeps its original lot, garment identity and server controls.
const flagLabels={repair:'Da riparare',relabel:'Da etichettare',verify:'Da verificare',replacement:'Sostituzione richiesta',discardReview:'Scarto da verificare',rewash:'Rilavaggio'};
const previousDiscardPending=repairDiscardPending;
repairDiscardPending=function(row){return row?.discardForReturn?false:previousDiscardPending(row)};
const previousReturnStatus=lotRowStatus;
lotRowStatus=function(row){
 const label=previousReturnStatus(row);
 return row.discardForReturn&&!label.includes('Scarto')?label+' · Scarto':label;
};
function pendingFlags(r){if(['Uscito','Dismesso'].includes(r.state))return [];return Object.keys(flagLabels).filter(k=>k==='discardReview'?repairDiscardPending(r):k==='rewash'?!!r.rewashPending:!!r[k]);}
function pendingRows(l){return (l?.rows||[]).filter(r=>pendingFlags(r).length)}
function flagBadges(r){return sewingRepairedBadge(r,current?.rows.includes(r)?current.events:[])+pendingFlags(r).map(k=>`<span class="floor-flag">${flagLabels[k]}</span>`).join('')}
function garmentLine(r){const g=db.garments.find(g=>g.id===r.code);return `${productCodeLink(r.code)}<p>${esc(g?.name||'Utilizzatore non indicato')}</p><p>${esc(g?.type||'Tipo non indicato')} · ${esc(g?.size||'—')} · ${esc(g?.dept||'Reparto non indicato')}</p>`}
F.repairs=function(){if(busy())return notify('Attendi la registrazione in corso.');setMode(true);current=null;repairProductCode=null;F.screen='repairs';page='Reparto';drawRepairOverview();void F.refresh()};
function sewingDeparture(lot,today,now){
 const due=deliveryKey(lot);
 if(due==='9999')return '<strong>Partenza da definire</strong>';
 const day=due.slice(0,10);
 const late=day<today||(day===today&&due.length>=16&&due.slice(11,16)<now);
 const label=late?'Partenza scaduta':day===today?'Parte oggi':'Deve partire il';
 const color=late?'#9f1239':day===today?'#854d0e':'#163b65';
 return '<strong style="color:'+color+'">'+label+' · '+esc(lotDeliveryDate(due))+'</strong>';
}
function drawRepairOverview(){const clock=new Date(),today=clock.toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}),now=clock.toLocaleTimeString('it-IT',{timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit'});const lots=db.lots.filter(l=>!l.archived&&(pendingRows(l).length||sewingHasHistory(l))).sort((a,b)=>deliveryKey(a).localeCompare(deliveryKey(b))||Number(a.id)-Number(b.id));const worked=lots.filter(l=>!pendingRows(l).length);shell(`<p class="floor-lead">Qui arrivano riparazioni, etichette, verifiche, sostituzioni, scarti da verificare e rilavaggi.</p><div class="floor-lots">${lots.filter(l=>pendingRows(l).length).map(l=>`<button class="floor-lot-choice phase-repair" onclick="floor.repairLot(${Number(l.id)})">${sewingDeparture(l,today,now)}<span>${esc(lotno(l))}</span><strong>${esc(l.client)}</strong><span>${pendingRows(l).length} capi con interventi aperti</span><span>${Object.keys(flagLabels).map(k=>{const n=pendingRows(l).filter(r=>pendingFlags(r).includes(k)).length;return n?n+' '+flagLabels[k].toLowerCase():''}).filter(Boolean).join(' · ')}</span><b>Apri interventi →</b></button>`).join('')||'<p class="floor-empty">Nessun intervento aperto.</p>'}</div><details id="workedSewingLots" ${F.workedSewingOpen?'open':''} ontoggle="floor.workedSewingOpen=this.open"><summary><b>Lotti già lavorati · ${worked.length}</b></summary><div class="floor-lots">${worked.map(l=>`<button class="floor-lot-choice phase-repair" onclick="floor.repairLot(${Number(l.id)})"><span>${esc(lotno(l))}</span><strong>${esc(l.client)}</strong><b>Apri storico interventi →</b></button>`).join('')||'<p>Nessun lotto già lavorato.</p>'}</div></details>${F.error?`<p class="floor-warning">${esc(F.error)}</p>`:''}${button('Aggiorna','floor.refresh()')}`,'Reparto cucito','repair')}
function drawRepairLot(id){repairLotId=Number(id);repairProductCode=null;const l=db.lots.find(l=>l.id===repairLotId);if(!l)return F.repairs();const rows=pendingRows(l);shell(`<p class="floor-lead">${esc(lotno(l))} · ${esc(l.client)} · ${rows.length} capi da controllare</p><div class="floor-product-cards">${rows.map(r=>`<article class="floor-product-card">${garmentLine(r)}<div>${flagBadges(r)}</div>${window.LotActors?LotActors.rowMarkup(l,r):''}${button('Apri capo',`repairProductDetail(${repairCall(l.id,r.code)})`)}</article>`).join('')||'<p class="floor-empty">Tutti gli interventi del lotto sono completati. Gli interventi eseguiti restano nello storico.</p>'}</div>${sewingDetailsPanel(l)}${button('Elenco completo del lotto',`floor.openLotProducts(${l.id})`)}`,'Interventi del lotto','repair');}
function drawRepairProduct(id,code){repairLotId=Number(id);repairProductCode=code;const l=db.lots.find(l=>l.id===repairLotId),r=l?.rows.find(r=>r.code===code);if(!r)return drawRepairLot(id);const flags=pendingFlags(r),writable=!l.archived&&userCan('lots_work')&&!['Uscito','Dismesso'].includes(r.state),review=flags.includes('discardReview')||flags.includes('replacement');shell(`<p class="floor-lead">${esc(lotno(l))} · ${esc(l.client)}</p><article class="floor-product-card">${garmentLine(r)}<div>${flagBadges(r)}</div>${r.notes?`<p>Note: ${esc(r.notes)}</p>`:''}<div class="floor-repair-actions">${['repair','relabel','verify'].filter(k=>r[k]).map(k=>button({repair:'Registra riparazione eseguita',relabel:'Registra etichettatura eseguita',verify:'Registra verifica eseguita'}[k],`registerRepairWork(${repairCall(id,code)},'${k}')`,'secondary',writable?'':'disabled')).join('')}${!r.repair&&writable&&!review&&(r.repairWork?.some(work=>work.kind==='repair')||(l.events||[]).some(event=>event.code===code&&/^(Intervento completato|Completata:).*ripar/i.test(event.action||'')))?button('Aggiungi un’altra riparazione',`registerRepairWork(${repairCall(id,code)},'repair')`,'secondary'):''}${review?(userCan('products_manage')?button('Valuta scarto / sostituzione',`assetReplace(${arg(code)})`):'<p>Scarto e sostituzione: conferma riservata al responsabile abilitato.</p>'):''}${flags.includes('rewash')?button('Apri entrata per il rilavaggio',`floor.openLot(${id},'entry')`):''}${button('Segnalazioni e note',`floor.openLotProducts(${id},${arg(code)})`)}</div></article>${sewingDetailsPanel(l,code)}`,'Intervento sul capo','repair');repairWashDecorate();void repairWashRefresh();}
F.openLotProducts=async function(id,code){if(busy())return notify('Attendi la registrazione in corso.');F.productsOpen=true;await F.openLot(id,'entry');if(code)F.flags(code);else $('#floorProducts')?.scrollIntoView({block:'start'})};
const productPageSizes=[10,50,100,1000];
try{const stored=Number(localStorage.getItem('mycroclean.reparto.pageSize'));F.productPageSize=productPageSizes.includes(stored)?stored:10}catch{F.productPageSize=10}
F.productPage=1;
F.productList=function(){if(!F.active||F.screen!=='lot'||!current)return;let panel=$('#floorProducts');if(!panel){panel=document.createElement('details');panel.id='floorProducts';panel.className='floor-products';panel.open=!!F.productsOpen;panel.innerHTML='<summary>Elenco capi del lotto</summary><label>Cerca codice o utilizzatore<input id="floorProductSearch" type="search" placeholder="Codice, nome, tipo o reparto"></label><div class="floor-pagination"><label>Capi per pagina<select id="floorProductPageSize" data-native-select aria-label="Capi per pagina" onchange="floor.setProductPageSize(this.value)"><option value="10">10</option><option value="50">50</option><option value="100">100</option><option value="1000">1.000</option></select></label><button type="button" class="floor-button" id="floorProductPrevious" onclick="floor.productPageTo(floor.productPage-1)">Precedente</button><span id="floorProductPage" role="status"></span><button type="button" class="floor-button" id="floorProductNext" onclick="floor.productPageTo(floor.productPage+1)">Successiva</button></div><p id="floorProductCount" role="status"></p><div id="floorProductCards" class="floor-product-list"></div>';panel.ontoggle=()=>F.productsOpen=panel.open;const scan=$('#scan')?.closest('.lot-work-section');if(scan)scan.after(panel);else $('#app').append(panel);$('#floorProductSearch').value=F.productQuery||'';$('#floorProductSearch').oninput=e=>{F.productQuery=e.target.value;F.productPage=1;F.drawProducts()};}F.drawProducts();};
F.foldListed=function(id,code,control){
 if(!F.active||F.screen!=='lot'||F.phase!=='fold'||stage!=='Lavorazione'||current?.id!==id||current.archived||!userCan('lots_work'))return;
 if(busy()||F.stopped)return notify('Attendi la conferma della registrazione in corso.');
 const row=current.rows.find(r=>r.code===code);
 if(!row||!foldRows(current).includes(row))return notify('Aggiorna il lotto per verificare lo stato del capo.');
 control.disabled=true;
 try{enqueueBarcode(code)}finally{control.disabled=false;}
};
F.drawProducts=function(){if(!current||!$('#floorProductCards'))return;const query=(F.productQuery||'').trim().toLocaleLowerCase('it'),rows=(F.phase==='entry'?[...current.rows].reverse():current.rows).filter(r=>{const g=db.garments.find(g=>g.id===r.code);return [r.code,productBarcode(g),g?.name,g?.type,g?.size,g?.dept,r.notes].join(' ').toLocaleLowerCase('it').includes(query)}),limit=F.productPageSize||10,pages=Math.max(1,Math.ceil(rows.length/limit));F.productPage=Math.max(1,Math.min(F.productPage||1,pages));const start=(F.productPage-1)*limit;$('#floorProductPageSize').value=String(limit);$('#floorProductPage').textContent='Pagina '+F.productPage+' di '+pages;$('#floorProductPrevious').disabled=F.productPage===1;$('#floorProductNext').disabled=F.productPage===pages;$('#floorProductCount').textContent=rows.length+' capi trovati / '+current.rows.length+' inseriti nel lotto';$('#floorProducts summary').textContent='Elenco capi del lotto · '+current.rows.length;$('#floorProductCards').innerHTML=rows.length?`<table class="floor-products-table"><caption class="floor-list-caption">Capi del lotto</caption><thead><tr><th scope="col">Codice</th><th scope="col">Utilizzatore</th><th scope="col">Tipo / Taglia</th><th scope="col">Reparto</th><th scope="col">Stato e segnalazioni</th><th scope="col">Azioni</th></tr></thead><tbody>${rows.slice(start,start+limit).map(r=>{const g=db.garments.find(g=>g.id===r.code);return `<tr><td data-label="Codice"><strong style="user-select:text;-webkit-user-select:text">${esc(productBarcode(g)||r.code)}</strong> ${lotCopyCodeButton(productBarcode(g)||r.code)}</td><td data-label="Utilizzatore">${esc(g?.name||'Non indicato')}</td><td data-label="Tipo / Taglia">${esc(g?.type||'Non indicato')}<small>${esc(g?.size||'—')}</small></td><td data-label="Reparto">${esc(g?.dept||'Non indicato')}</td><td data-label="Stato e segnalazioni">${badge(esc(lotRowStatus(r)))}<div>${flagBadges(r)}</div>${r.notes?`<p class="floor-list-note">${esc(r.notes)}</p>`:''}</td><td class="floor-list-actions">${F.phase==='fold'&&!current.archived&&userCan('lots_work')&&r.washed&&!r.foldedAt&&!['Uscito','Dismesso'].includes(r.state)&&(!r.requiresDrying||r.dryState==='done')?button('Conferma piegatura',`floor.foldListed(${Number(current.id)},${arg(r.code)},this)`,'primary'):''}${button('Segnalazioni e note',`floor.flags(${arg(r.code)})`,'primary floor-product-notes')}${F.phase==='entry'&&userCan('lots_work')?button('Rimuovi dal lotto',`EntryRemove.open([${arg(r.code)}])`,'problem floor-product-remove'):''}</td></tr>`}).join('')}</tbody></table>`:'<p>Nessun capo trovato.</p>';};
F.setProductPageSize=function(value){const size=Number(value);if(!productPageSizes.includes(size))return;F.productPageSize=size;F.productPage=1;try{localStorage.setItem('mycroclean.reparto.pageSize',String(size))}catch{}F.drawProducts()};
F.productPageTo=function(page){F.productPage=page;F.drawProducts();$('#floorProducts')?.scrollIntoView({block:'start'})};
const floorRows=renderLotRows;renderLotRows=function(...args){const r=floorRows(...args);if(F.active&&F.screen==='lot'){F.entryTypeSummary();updatePhaseProgress();F.drawProducts()}return r};
F.flags=function(code){const r=current?.rows.find(r=>r.code===code);if(!r)return;const writable=userCan('lots_work')&&!['Uscito','Dismesso'].includes(r.state);show(`<h2>Segnalazioni del capo</h2>${garmentLine(r)}<p>Spunta gli interventi necessari. I capi segnalati compaiono in Reparto cucito.</p><div class="floor-flag-options">${db.garments.find(g=>g.id===code)?.rental===false?`<label><input type="checkbox" ${r.discardForReturn?'checked':''} ${writable?'':'disabled'} onchange="floor.flag(${arg(code)},'discardForReturn',this.checked)"> Scarto da restituire al cliente · mantieni il tag</label>`:''}${Object.entries(flagLabels).map(([k,label])=>`<label><input type="checkbox" data-floor-flag="${k}" ${pendingFlags(r).includes(k)?'checked':''} ${writable&&!(k==='discardReview'&&(r.discard||productIsDiscard(db.garments.find(g=>g.id===code))))?'':'disabled'} onchange="floor.flag(${arg(code)},'${k}',this.checked)"> ${label}</label>`).join('')}</div><p>Scarto da verificare invia il capo al controllo. Non dismette il capo e non trasferisce il tag.</p><p id="floorFlagStatus" role="status"></p>${button('Note del capo',`editLotRowNotes(${arg(code)})`,'secondary',writable?'':'disabled')}${userCan('products_manage')&&!['Uscito','Dismesso'].includes(r.state)?button('Valuta scarto / sostituzione',`assetReplace(${arg(code)})`):''}${button('Chiudi',"document.querySelector('#modal').close()")}`)};
F.flag=async function(code,kind,value){if(!userCan('lots_work')||busy()||F.flagSaving){if(!F.flagSaving)F.flags(code);return notify('Operazione non disponibile: verifica permessi o attendi il salvataggio.');}const id=current?.id,r=current?.rows.find(r=>r.code===code);if(!r||['Uscito','Dismesso'].includes(r.state)||(kind!=='discardForReturn'&&!Object.hasOwn(flagLabels,kind)))return;F.flagSaving=true;$('#modal').querySelectorAll('input,button').forEach(b=>b.disabled=true);try{await cloudFlush();cloudAccept(await cloudRequest(),false);const row=current?.rows.find(r=>r.code===code);if(!userCan('lots_work')||current?.id!==id||!row||['Uscito','Dismesso'].includes(row.state))throw Error('Il capo è cambiato. Aggiorna il lotto.');if(kind==='discardForReturn'){
 if(db.garments.find(g=>g.id===code)?.rental!==false)throw Error('Questa opzione è riservata ai capi di proprietà del cliente.');
 row.discardForReturn=value;
 log(value?'Scarto da restituire al cliente':'Annullata restituzione come scarto',code);detail();
}else if(kind==='discardReview'){row.discardReview=value;if(value)row.verify=true;log(value?'Richiesta: scarto da verificare':'Rimossa richiesta: scarto da verificare',code);detail();}else setRegisteredFlag(code,kind,value);await cloudFlush();F.flags(code);$('#floorFlagStatus').textContent='Salvato. Elenco Reparto cucito aggiornato.';}catch(e){if(!cloudStopped){F.flags(code);$('#floorFlagStatus').textContent='Non salvato: '+e.message;}notify(e.message);}finally{F.flagSaving=false}};
const examples=[['ready','PRONTO','Controlla e piega il capo. Poi scansiona.','Giulia Rossi · Camice M'],['done','FATTO','Piegatura registrata. Passa al capo successivo.','Giulia Rossi · Camice M'],['aside','METTI DA PARTE','Riparazione ancora aperta.','Marco Bianchi · Pantalone L','RIPARAZIONI'],['stop','FERMATI','Il capo appartiene a un altro cliente. Non registrarlo in questo lotto.','Elena Verdi · Camice S']];
F.examples=function(i){const [tone,title,message,name,bin]=examples[i];show(`<div class="floor-example"><p class="floor-example-label">ESEMPIO ${i+1} / 4 · NOMI INVENTATI · NESSUNA REGISTRAZIONE</p><section class="floor-feedback ${tone}"><h2>${title}</h2><p>${message}</p><b>${name}</b>${bin?`<div class="floor-bin">CESTO ${bin}</div>`:''}</section><div class="floor-example-nav">${button(i===3?'HO CAPITO':'Esempio successivo',i===3?"document.querySelector('#modal').close()":'floor.examples('+(i+1)+')')}${button('Chiudi esempio',"document.querySelector('#modal').close()")}</div></div>`)};
F.guide=function(){show(`<h2>Reparto e ufficio</h2><p>Stessi dati e stessi controlli. Cambia il modo di lavorare sullo schermo.</p><div class="scroll"><table><thead><tr><th>Reparto</th><th>Ufficio</th></tr></thead><tbody><tr><td>Scansioni, carrelli, cicli e capi da consegnare</td><td>Clienti, contratti, listini e addebiti</td></tr><tr><td>Lavoro assegnato e segnalazione problemi</td><td>Ruoli, permessi, abilità, turni e pianificazione</td></tr><tr><td>Esito chiaro: FATTO, METTI DA PARTE, FERMATI</td><td>Storici, verifiche, scarti e sostituzioni</td></tr></tbody></table></div><h3>Le sei regole</h3><ol><li>Un colore stabile per ogni fase.</li><li>Un’azione principale per schermata.</li><li>Pulsanti grandi e parole brevi.</li><li>Conferma visibile per ogni scansione.</li><li>Un errore bloccante richiede HO CAPITO.</li><li>Numeri reali: mai simulazioni nel lavoro.</li></ol><h3>Quattro passi per introdurla</h3><ol><li>Il responsabile verifica permessi, abilità e turni.</li><li>Etichetta i cesti fisici: RIPARAZIONI, ETICHETTE, VERIFICHE, RILAVAGGIO, SCARTI DA VERIFICARE.</li><li>Prova un lotto completo con un operatore, controllando ogni passaggio.</li><li>Usa la vista reparto e mantieni configurazione e amministrazione in ufficio.</li></ol><p>La vista semplificata non aggiunge permessi e non limita da sola l’accesso ai dati.</p>${button('Vedi 4 esempi di piegatura','floor.examples(0)')}${button('Chiudi',"document.querySelector('#modal').close()")}`)};
const oldDetail=detail;detail=function(...args){const result=oldDetail(...args);F.decorate();return result};
const oldWashRender=washRender;washRender=function(...args){const result=oldWashRender(...args);F.decorate();return result};
const oldRender=render;render=function(...args){$('#app')?.classList.remove('floor-lot','floor-repairs');if(F.active&&(['repairs','repair','ddt','mask'].includes(F.screen)||page==='Reparto'&&!current)){F.draw();return}const result=oldRender(...args);if(cloudUser&&!$('#floorNav')){const b=document.createElement('button');b.id='floorNav';b.textContent='Vista reparto';b.onclick=F.home;$('#nav')?.prepend(b)}return result};
const oldAccept=cloudAccept;let firstUser=null;cloudAccept=function(result,redraw=true){const first=result?.user?.email!==firstUser;if(first){firstUser=result?.user?.email;if(result?.user?.role==='operator'&&!result?.user?.permissions?.production_manage){setMode(true);F.screen='home';page='Reparto';current=null}}const out=oldAccept(result,redraw);if(first&&F.active)setTimeout(()=>void F.refresh(),0);return out};
const oldLogin=standaloneLogin;standaloneLogin=function(...args){setMode(false);firstUser=null;F.request++;return oldLogin(...args)};
const oldGo=go;go=function(destination){if(F.active){if(destination==='Mascherine · Confezionamento')return F.mask();if(destination==='DDT fornitori · Airtable')return F.ddt();if(destination==='Riparazioni')return F.repairs();if(destination==='Istruzioni')return F.instructions();if(destination==='Produzione')return F.work();if(destination==='Lotti')return F.list(F.phase);if(destination!=='Reparto')return F.home()}return oldGo(destination)};
document.addEventListener('pointerdown',e=>{if(F.active&&F.screen==='lot'&&!e.target.closest('input,select,textarea,button,a,summary,dialog'))setTimeout(F.focus,0)});
setInterval(()=>{if(F.active&&['machines','work'].includes(F.screen)&&!$('#modal').open&&!busy())void F.refresh()},15000);
})();




