/* Office lot overview. Existing lot operations, permissions and history remain authoritative. */
let officeLotSort='due';
function officeLotText(value){return String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('it')}
function officeLotRows(){
 const words=officeLotText(lotListSearch).split(/\s+/).filter(Boolean);
 const products=words.length?new Map(db.garments.map(g=>[String(g.id),g])):null;
 return db.lots.filter(l=>!l.archived&&(!lotListState||lotStatus(l)===lotListState)&&(!lotMetric||matchesLotMetric(l))).filter(l=>{
  if(!words.length)return true;
  const text=officeLotText([lotno(l),l.id,l.client,l.departmentName,l.date,l.due,l.airtableOrderCode,l.airtableCustomerOrder,l.notes,...l.rows.flatMap(r=>{const g=products.get(String(r.code));return [r.code,r.notes,g?.name,g?.barcode,g?.dept,g?.type]})].join(' '));
  return words.every(w=>text.includes(w));
 }).sort((a,b)=>officeLotSort==='newest'?Number(b.id)-Number(a.id):officeLotSort==='client'?String(a.client).localeCompare(String(b.client),'it')||Number(b.id)-Number(a.id):String(a.due||'9999').localeCompare(String(b.due||'9999'))||Number(b.id)-Number(a.id));
}
const officePreviousLotListRows=lotListRows;
lotListRows=function(history){return history?officePreviousLotListRows(true):officeLotRows()};
function officeLotFilter(state){lotListState=state;lotMetric='';lotTable()}
function officeLotClear(){lotListSearch='';lotListState='';lotMetric='';const input=$('#officeLotSearch');if(input)input.value='';lotTable()}
function officeLotDue(l){
 const today=new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}),date=String(l.due||'').slice(0,10);
 const late=date&&date<today&&lotStatus(l)!=='Chiuso';
 return `<span class="office-due ${late?'overdue':''}">${l.due?esc(lotDeliveryDate(l.due)):'Da definire'}</span>${late?'<small class="office-late">Consegna scaduta</small>':date===today?'<small>Consegna oggi</small>':''}`;
}
lotsView=function(){
 $('#app').innerHTML=`<section class="office-lots" aria-label="Lotti · vista ufficio">${heading('Lotti','Cerca il lotto, controlla la consegna e apri la scheda per lavorarlo.',`<div class="office-head-actions"><button class="btn secondary" onclick="go('Storico')">Archivio lotti</button>${lotWritable()?'<button class="btn office-primary" onclick="newLot()">＋ Nuovo lotto</button>':''}</div>`)}
 <div class="panel office-lot-panel"><div class="office-lot-filters">
 <label class="office-lot-search" for="officeLotSearch">Cerca nei lotti<input id="officeLotSearch" class="search" type="search" value="${esc(lotListSearch)}" placeholder="Numero lotto, reparto, cliente, codice capo…" oninput="lotListSearch=this.value;lotTable()"></label>
 <label>Ordina per<select data-native-select onchange="officeLotSort=this.value;lotTable()"><option value="due" ${officeLotSort==='due'?'selected':''}>Consegna più vicina</option><option value="newest" ${officeLotSort==='newest'?'selected':''}>Lotti più recenti</option><option value="client" ${officeLotSort==='client'?'selected':''}>Cliente A–Z</option></select></label>
 <details class="office-export"><summary>Esporta</summary><div><button class="btn secondary" onclick="exportLotList(false)">CSV · tutti i risultati</button><button class="btn secondary" onclick="exportCurrentView('xlsx')">Excel · pagina visibile</button></div></details>
 </div><div id="officeLotStates" class="office-lot-states" aria-label="Filtra per stato"></div>
 <div class="office-result-line"><span id="officeLotCount" role="status" aria-live="polite"></span><button type="button" class="link" onclick="officeLotClear()">Azzera filtri</button></div>
 <div class="scroll" id="lotTable"></div></div></section>`;
 lotTable();
};
const officePreviousRenderLotList=renderLotList;
renderLotList=function(history){
 if(history||!$('.office-lots'))return officePreviousRenderLotList(history);
 const rows=officeLotRows(),active=db.lots.filter(l=>!l.archived),writable=lotWritable(),canDelete=cloudUser?.role==='admin'&&userCan('planning_delete');
 $('#officeLotStates').innerHTML=[['','Tutti'],['Aperto','Aperti'],['In lavorazione','In lavorazione'],['Chiuso','Chiusi']].map(([state,label])=>`<button type="button" class="office-state-tab" aria-pressed="${lotListState===state}" onclick="officeLotFilter('${state}')">${label}<span>${active.filter(l=>!state||lotStatus(l)===state).length}</span></button>`).join('');
 $('#officeLotCount').textContent=rows.length+' '+(rows.length===1?'lotto':'lotti')+(lotListSearch||lotListState?' trovati':' nell’elenco')+(lotMetric?' · '+lotMetricLabels[lotMetric]:'');
 $('#lotTable').innerHTML=`<table class="office-lot-table"><thead><tr><th>Lotto</th><th>Stato / ingresso</th><th>Consegna</th><th>Prodotti</th><th>Interventi aperti</th><th>Azioni</th></tr></thead><tbody>${rows.map(l=>{
 const out=l.rows.filter(r=>r.state==='Uscito').length,n=l.rows.length,state=lotStatus(l),entry=l.rows.filter(r=>r.state==='Entrato').length,wash=l.rows.filter(r=>r.state==='In lavaggio').length,work=l.rows.filter(r=>r.state==='In lavorazione').length;
 const flags=[['repair','Da riparare'],['relabel','Da etichettare'],['verify','Da verificare'],['rewash','Rilavaggio']].map(([key,label])=>[label,l.rows.filter(r=>r.state!=='Uscito'&&r[key]).length]).filter(([,count])=>count);
 return `<tr><td><button type="button" class="link code lot-number-link office-lot-title" onclick="openLot(${Number(l.id)})">${esc(lotno(l))}</button><small class="office-lot-client">${esc(l.client)}</small><small class="office-lot-department">${esc(l.departmentName||'Reparto non indicato')}</small></td>
 <td><span class="office-status ${state==='Chiuso'?'closed':state==='Aperto'?'open':'working'}">${state}</span><small>Ingresso ${esc(lotDate(l.date))}</small></td>
 <td>${officeLotDue(l)}</td><td><strong>${n} ${n===1?'capo':'capi'}</strong><small>${out} usciti · ${n-out} da uscire</small><progress max="${n||1}" value="${out}" aria-label="${out} prodotti usciti su ${n}"></progress><details class="office-quantity"><summary>Dettaglio quantità</summary><div>${entry} in entrata<br>${wash} in lavaggio<br>${work} in lavorazione<br>${out} usciti</div></details></td>
 <td>${flags.length?flags.map(([label,count])=>`<span class="office-issue">${count} ${label.toLowerCase()}</span>`).join(''):'<span class="muted">Nessun intervento segnalato</span>'}<small>${repairMinutes(lotRepairTotals(l).minutes)} min di riparazioni registrati</small></td>
 <td><button class="btn office-primary" onclick="openLot(${Number(l.id)})">Apri lotto →</button><details class="office-more"><summary>Altre azioni</summary><div><button class="btn secondary" onclick="openLotRepairs(${Number(l.id)})">Reparto cucito</button>${writable?`<button class="btn secondary" onclick="archiveLot(${Number(l.id)})">Archivia lotto</button>`:''}${canDelete?`<button class="btn office-danger" onclick="planningDeleteDialog('delete_lot',${Number(l.id)})">Elimina lotto</button>`:''}</div></details></td></tr>`;
 }).join('')||'<tr><td colspan="6" class="empty">Nessun lotto trovato. Prova un’altra ricerca o azzera i filtri.</td></tr>'}</tbody></table>`;
};
lotTable=function(){renderLotList(false)};
if(typeof cloudUser!=='undefined'&&cloudUser&&page==='Lotti'&&!current&&!document.body.classList.contains('floor-mode'))lotsView();
