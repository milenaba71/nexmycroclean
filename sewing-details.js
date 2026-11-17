/* Product-level sewing history shared by the lot overview, department and print. */
const sewingKindNames={repair:'Riparazione',relabel:'Etichettatura',verify:'Verifica'};
function sewingHasHistory(lot){return lot.rows.some(r=>r.repairWork?.length||r.lifecycleClosed||r.replacedBy)||(lot.events||[]).some(e=>/^(Intervento completato|Completata:)/i.test(e.action||''))}
function sewingProductLabel(code){const g=db.garments.find(g=>g.id===code),barcode=typeof productBarcode==='function'?productBarcode(g):g?.barcode;return `${productCodeLink(code,barcode||code)}${barcode&&barcode!==code?`<br><small>ID capo: ${esc(code)}</small>`:''}`}
function sewingDetailsPanel(lot,code){
 const rows=code===undefined?lot.rows:lot.rows.filter(r=>r.code===code),works=rows.flatMap(r=>(r.repairWork||[]).map(w=>({...w,code:r.code}))),events=(lot.events||[]).filter(e=>(code===undefined||e.code===code)&&/^(Intervento completato|Completata:)/i.test(e.action||'')),closed=rows.filter(r=>r.lifecycleClosed||r.replacedBy||r.disposition);
 const person=code=>{const g=db.garments.find(g=>g.id===code)||{};return `${esc(g.type||'—')} / ${esc(g.size||'—')}<br>${esc(g.name||'—')} · ${esc(g.dept||'—')}`};
 const table=(heads,body)=>`<div class="scroll sewing-detail-scroll"><table class="sewing-detail-table"><thead><tr>${heads.map(h=>`<th${h==='Note'?' class="report-note"':''}>${h}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`;
 const workedRows=rows.filter(r=>r.repair||r.relabel||r.verify||r.repairWork?.length||r.lifecycleClosed||r.replacedBy||events.some(e=>e.code===r.code));
 const overview=code===undefined&&workedRows.length?`<section class="panel sewing-products"><div class="panelhead"><h2>Prodotti e interventi · reparto cucito</h2><span>${workedRows.length} prodotti</span></div>${table(['Codice / utilizzatore','Tipo / reparto','Interventi eseguiti','Lavoro registrato','Eseguito da','Azioni'],workedRows.map(r=>{const g=db.garments.find(g=>g.id===r.code)||{},ws=r.repairWork||[],names=[...new Set(ws.map(w=>w.name))],operators=[...new Set(ws.map(w=>w.completedBy||w.completedByEmail).filter(Boolean))],pieces=ws.filter(w=>w.unit==='piece').reduce((n,w)=>n+Number(w.quantity||0),0),minutes=ws.reduce((n,w)=>n+Number(w.minutesHundredths||0),0);return `<tr><td>${sewingProductLabel(r.code)}<br>${esc(g.name||'—')}</td><td>${esc(g.type||'—')}<br>${esc(g.dept||'—')}</td><td>${names.map(n=>esc(n)).join('<br>')||'Vedi dettaglio attività'}${r.replacedBy?'<br>Sostituzione registrata':''}</td><td>${ws.length} interventi<br>${pieces} pezzi · ${repairMinutes(minutes)} minuti</td><td>${operators.map(n=>esc(n)).join('<br>')||'Vedi dettaglio attività'}</td><td><button type="button" class="btn secondary sewing-open" onclick="sewingOpenProduct(${repairCall(lot.id,r.code)})">Apri capo</button>${!r.repair&&(ws.some(w=>w.kind==='repair')||events.some(e=>e.code===r.code&&/ripar/i.test(e.action||'')))?'<span class="sewing-repaired">Riparato</span>':''}</td></tr>`}).join(''))}</section>`:'';
 return `${overview}<section class="panel sewing-details"><div class="panelhead"><h2>Interventi eseguiti per prodotto</h2><span>${works.length} interventi con consuntivo</span></div>${works.length?table(['Codice prodotto / tag','Prodotto / utilizzatore','Intervento eseguito','Quantità','Minuti','Importo a pezzi','Operatore / data','Note'],works.map(w=>`<tr><td>${sewingProductLabel(w.code)}</td><td>${person(w.code)}</td><td>${esc(sewingKindNames[w.kind]||'Intervento')}<br><b>${esc(w.name||'Non indicato')}</b></td><td>${esc(String(w.quantity??'—'))}${page==='Riparazioni'&&!lot.archived&&userCan('lots_work')&&w.id?'<br><button type="button" class="link sewing-open" data-lot="'+Number(lot.id)+'" data-code="'+esc(w.code)+'" data-work="'+esc(w.id)+'" onclick="editSewingWork(this)">Correggi intervento</button>':''}</td><td>${repairMinutes(w.minutesHundredths)}</td><td>${w.unit==='piece'?euro3(w.costMills):'Da valorizzare a minuti'}</td><td>${esc(w.completedBy||w.completedByEmail||'Non registrato')}<br>${w.completedAt?esc(repairDate(w.completedAt)):'Data non registrata'}</td><td class="report-note">${esc(w.notes||'—')}</td></tr>`).join('')):'<div class="bottom">Nessun intervento con consuntivo registrato.</div>'}
 ${events.length?`<h3>Completamenti registrati senza consuntivo</h3>${table(['Codice prodotto / tag','Attività completata','Operatore','Data / ora'],events.map(e=>`<tr><td>${sewingProductLabel(e.code||'—')}</td><td>${esc(e.action)}</td><td>${esc(e.actor||'Non registrato')}</td><td>${esc(e.time||e.at||'Non registrata')}</td></tr>`).join(''))}`:''}
 ${closed.length?`<h3>Sostituzioni e chiusure del capo</h3>${table(['Codice prodotto / tag','Prodotto / utilizzatore','Operazione','Motivo','Capo sostitutivo (ID)'],closed.map(r=>`<tr><td>${sewingProductLabel(r.code)}</td><td>${person(r.code)}</td><td>${esc(({replace:'Sostituzione',retire:'Dismissione',return:'Reso',employee_return:'Reso personale dimesso',buyout:'Riscatto'})[r.disposition]||r.disposition||'Chiusura capo')}</td><td>${esc(({size_change:'Cambio taglia',employee_left:'Personale dimesso',wear:'Usura normale',wash_limit:'Fine vita per lavaggi',breakage:'Rottura',permanent_stain:'Macchia permanente',improper_damage:'Danno improprio',lost:'Smarrimento',not_returned:'Mancato reso'})[r.discardReason]||r.discardReason||'—')}</td><td>${r.replacedBy?productCodeLink(r.replacedBy):'—'}</td></tr>`).join(''))}`:''}
 <div class="bottom">Ogni riga collega l’intervento al codice del prodotto. Le richieste ancora aperte non sono interventi eseguiti. Completamenti senza consuntivo e sostituzioni non aggiungono importi al totale.</div></section>`;
}
const repairTotalsBeforeProductDetails=repairTotalsPanel;
repairTotalsPanel=function(lot){return repairTotalsBeforeProductDetails(lot)+sewingDetailsPanel(lot)};
document.head.insertAdjacentHTML('beforeend','<style>.sewing-repaired{display:inline-block;margin:6px 0 6px 10px;padding:6px 10px;border-radius:8px;background:#dcfce7;color:#166534;font-weight:700;white-space:nowrap}.sewing-details{min-width:0;max-width:100%}.sewing-detail-scroll{max-width:100%;overflow:auto}.sewing-detail-table{min-width:850px}.sewing-detail-table td{white-space:normal;overflow-wrap:anywhere}.sewing-details h3{padding:0 16px}@media print{.sewing-open{display:none}.sewing-detail-table{min-width:0}.sewing-detail-scroll{overflow:visible}}</style>');

function sewingOpenProduct(id,code){if(window.floor?.active)floor.repairLot(id);else go('Riparazioni');repairProductDetail(id,code)}


function editSewingWork(button){
 const {lot:id,code,work:workId}=button.dataset;
 const lot=db.lots.find(l=>String(l.id)===id);
 const findWork=l=>l?.rows.find(r=>r.code===code)?.repairWork?.find(w=>w.id===workId);
 const original=findWork(lot);
 if(!original||lot.archived||!userCan('lots_work')||!lotMutationAllowed())return;
 const before=JSON.stringify(original);
 show('<h2>Correggi intervento</h2><p>'+esc(lotno(lot))+' · '+esc(code)+' · '+esc(original.name)+'</p><form id="sewingCorrection"><label>Quantità<input name="quantity" type="number" min="1" step="1" required></label><label>Minuti eseguiti<input name="minutes" type="number" min="0" step="0.01" required></label><label>Note<textarea name="notes" maxlength="500"></textarea></label><p role="alert"></p><button class="btn">Salva correzione</button></form>');
 const form=$('#sewingCorrection');
 form.elements.quantity.value=original.quantity;
 form.elements.minutes.value=(original.minutesHundredths||0)/100;
 form.elements.notes.value=original.notes||'';
 form.onsubmit=async e=>{
  e.preventDefault();if(!lotMutationAllowed()||!userCan('lots_work'))return;
  const quantity=form.elements.quantity.valueAsNumber,minutes=Math.round(form.elements.minutes.valueAsNumber*100),notes=form.elements.notes.value.trim();
  if(!Number.isSafeInteger(quantity)||quantity<1||!Number.isSafeInteger(minutes)||minutes<0)return;
  lotActionBusy=true;const save=e.submitter;save.disabled=true;
  try{
   await cloudFlush();cloudAccept(await cloudRequest(),false);
   const next=clone(db),target=next.lots.find(l=>String(l.id)===id),w=findWork(target);
   if(!userCan('lots_work')||!w||target.archived||JSON.stringify(w)!==before)throw Error('Intervento aggiornato. Riapri la scheda prima di correggere.');
   const cost=w.unit==='piece'?quantity*w.priceMills:0;
   if(!Number.isSafeInteger(cost))throw Error('Controlla la quantità e il prezzo.');
   const changes=[];
   if(quantity!==w.quantity)changes.push('quantità '+w.quantity+' → '+quantity);
   if(minutes!==w.minutesHundredths)changes.push('minuti '+repairMinutes(w.minutesHundredths)+' → '+repairMinutes(minutes));
   if(notes!==(w.notes||''))changes.push('note aggiornate');
   if(changes.length){
    Object.assign(w,{quantity,minutesHundredths:minutes,costMills:cost,notes});
    const event={action:'Correzione intervento · '+w.name+' · '+changes.join(', '),code,time:new Date().toLocaleString('it-IT',{timeZone:'Europe/Rome'}),actor:cloudUser.name,actorEmail:cloudUser.email,workId};
    (target.events??=[]).push(event);
    const result=await cloudRequest('save',{revision:cloudRevision,changes:cloudDelta(next)});
    cloudRevision=result.revision;db=next;cloudBase=clone(next);
   }
   $('#modal').close();
   if(repairProductCode===code)repairProductDetail(lot.id,code);else repairDetail(lot.id);
  }catch(error){form.querySelector('[role=alert]').textContent=error.message}
  finally{lotActionBusy=false;save.disabled=false}
 };
}
