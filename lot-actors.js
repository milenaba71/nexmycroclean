/* Read-only attribution, using recorded actors rather than the current viewer. */
(function(){
 const A=window.LotActors={cache:new Map(),loading:new Set()};
 A.name=function(value,lot){
  if(!value)return 'Non registrato';
  if(!String(value).includes('@'))return String(value);
  const event=(lot?.events||[]).find(e=>e.actorEmail===value&&e.actor&&!String(e.actor).includes('@'));
  const operator=typeof prod!=='undefined'?prod?.operators?.find(o=>o.email===value):null;
  return event?.actor||operator?.name||(cloudUser?.email===value?cloudUser.name:null)||value;
 };
 A.creatorMarkup=function(lot){const v=A.cache.get(String(lot.id))?.data?.creator;return '<small class="lot-actor-creator">Aperto da: <b>'+esc(v?.name||(cloudUser?.role==='admin'?'Non registrato':'Dato non disponibile'))+'</b>'+(v?.at?' · '+esc(new Date(v.at).toLocaleString('it-IT')):'')+'</small>'};
 A.latest=function(lot,code,pattern){return [...(lot.events||[])].reverse().find(e=>String(e.code)===String(code)&&pattern.test(e.action||''))};
 A.rowMarkup=function(lot,row){
  const entry=A.latest(lot,row.code,/^Entrata\b/i),fold=A.latest(lot,row.code,/piegatura|piegato/i),exit=A.latest(lot,row.code,/^Uscita\b|^Smistamento in uscita/i);
  const lines=[];
  if(entry)lines.push(['Entrata',A.name(entry.actor||entry.actorEmail,lot)]);
  if(row.foldedAt||fold)lines.push(['Piegatura',A.name(fold?.actor||row.foldedBy||fold?.actorEmail,lot)]);
  for(const w of row.repairWork||[])lines.push([w.name||'Riparazione',A.name(w.completedBy||w.completedByEmail,lot)]);
  if(exit||row.state==='Uscito')lines.push(['Uscita',A.name(exit?.actor||exit?.actorEmail,lot)]);
  return lines.length?'<div class="lot-row-actors">'+lines.map(([label,name])=>'<div>'+esc(label)+': <b>'+esc(name)+'</b></div>').join('')+'</div>':'';
 };
 A.load=function(id){
  if(cloudUser?.role!=='admin'||A.loading.has(String(id)))return;
  const key=String(id),cached=A.cache.get(key),rev=cloudRevision;
  if(cached&&cached.rev===rev&&Date.now()-cached.at<30000)return;
  if(cached?.error&&Date.now()-cached.at<30000)return;
  A.loading.add(key);A.cache.set(key,{...cached,rev,at:Date.now()});
  EntryProduct.deadline(appSupabase.rpc('laundry_lot_operator_summary',{p_lot_id:id}),15000).then(({data,error})=>{
   if(error)throw Error(error.message);A.cache.set(key,{data,rev,at:Date.now()});
  }).catch(()=>{A.cache.set(key,{...cached,rev,at:Date.now(),error:true})}).finally(()=>{A.loading.delete(key);A.mount();if(window.LotEntryNotes)LotEntryNotes.mount()});
 };
 A.mount=function(){
  if(A.owner!==cloudUser?.email){A.cache.clear();A.owner=cloudUser?.email}
  if(!current)return;
  const app=document.getElementById('app');if(!app||!app.querySelector('#floorLotHeader,#lotRows'))return;
  A.load(current.id);
  const heading=document.body.classList.contains('floor-mode')?app.querySelector('#floorLotHeader .floor-title h1'):app.querySelector('.heading h1');
  if(heading){let label=heading.parentElement.querySelector(':scope > .lot-actor-heading');if(!label){label=document.createElement('div');label.className='lot-actor-heading';heading.after(label)}const html=A.creatorMarkup(current);if(label.innerHTML!==html)label.innerHTML=html}
  for(const card of app.querySelectorAll('[data-wash-batch]')){
   const id=card.dataset.washBatch,b=(washState?.batches||[]).find(x=>x.id===id);if(!b)continue;
   const known=A.cache.get(String(b.lot_id))?.data?.machines?.find(x=>x.id===id);
   const html=b.started_at?'Avviata da: <b>'+esc(known?.operator||A.name(b.started_by,current))+'</b> · '+esc(new Date(b.started_at).toLocaleString('it-IT')):'Avvio non ancora registrato';
   let label=card.querySelector('.machine-actor');if(!label){label=document.createElement('div');label.className='machine-actor';card.append(label)}if(label.innerHTML!==html)label.innerHTML=html;
  }
  for(const tr of app.querySelectorAll('#lotRows tbody tr')){
   const cell=tr.querySelector('.code');if(!cell)continue;const code=(cell.querySelector('button,a')||cell).textContent.trim();
   const row=current.rows.find(r=>r.code===code||productBarcode(db.garments.find(g=>g.id===r.code))===code);if(!row)continue;
   const html=A.rowMarkup(current,row);let label=tr.querySelector('.office-row-actors');
   if(!label){label=document.createElement('div');label.className='office-row-actors';cell.append(label)}if(label.innerHTML!==html)label.innerHTML=html;
  }
  let panel=document.getElementById('lotActorHistory');
  if(!panel){panel=document.createElement('details');panel.id='lotActorHistory';panel.className='lot-actor-history';panel.innerHTML='<summary>Chi ha fatto cosa · utenti e operazioni</summary><div class="lot-actor-content"></div>';app.append(panel)}
  const records=[];
  const summary=A.cache.get(String(current.id))?.data;
  if(summary?.creator)records.push(['Apertura lotto','',summary.creator.name,summary.creator.at]);
  for(const e of current.events||[])records.push([e.action||'Operazione',e.code||'',A.name(e.actor||e.actorEmail,current),e.at||e.time||'']);
  for(const row of current.rows||[]){
   for(const w of row.repairWork||[])records.push([w.name||'Riparazione',row.code,A.name(w.completedBy||w.completedByEmail,current),w.completedAt||'']);
   if(row.foldedAt&&!A.latest(current,row.code,/piegatura|piegato/i))records.push(['Piegatura',row.code,A.name(row.foldedBy,current),row.foldedAt]);
  }
  for(const m of [...(summary?.machines||[]),...(summary?.dryers||[])])records.push(['Avvio '+m.machine+' · '+m.program,'',m.operator,m.started_at]);
  const html='<div style="overflow:auto"><table><thead><tr><th>Operazione</th><th>Codice capo</th><th>Utente</th><th>Data e ora</th></tr></thead><tbody>'+records.map(([action,code,name,time])=>'<tr><td>'+esc(action)+'</td><td>'+esc(code)+'</td><td><b>'+esc(name)+'</b></td><td>'+esc(/^\d{4}-/.test(time)?new Date(time).toLocaleString('it-IT'):time)+'</td></tr>').join('')+'</tbody></table></div>'+(A.cache.get(String(current.id))?.error?'<p>Riepilogo apertura e macchine non disponibile. Riprova con Aggiorna.</p>':'');
  const content=panel.querySelector('.lot-actor-content');if(content.innerHTML!==html)content.innerHTML=html;
 };
 const priorDry=dryCard;dryCard=function(c){let html=priorDry(c);if(!c.cycle?.started_at)return html;const known=A.cache.get(String(c.lotId))?.data?.dryers?.find(x=>x.id===c.cycle.id);return html.replace('</article>','<small class="machine-actor">Avviata da: <b>'+esc(known?.operator||A.name(c.cycle.started_by,db.lots.find(l=>l.id===c.lotId)))+'</b></small></article>')};
 const priorIdentity=washLotIdentity;washLotIdentity=function(b){const original=priorIdentity(b);if(!b.started_at)return original;const known=A.cache.get(String(b.lot_id))?.data?.machines?.find(x=>x.id===b.id);return original+'<small>Avviata da: <b>'+esc(known?.operator||A.name(b.started_by,db.lots.find(l=>l.id===b.lot_id)))+'</b></small>'};
 let queued=false;new MutationObserver(()=>{if(!queued){queued=true;queueMicrotask(()=>{queued=false;A.mount()})}}).observe(document.getElementById('app'),{childList:true,subtree:true});A.mount();
})();
