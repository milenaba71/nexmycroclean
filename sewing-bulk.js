/* Multi-product sewing work: one revision-checked save, one audit entry per garment. */
(function(){
 let selected=new Set(),lotId=null;
 const kinds=['repair','relabel','verify'];
 function eligible(l,r,k){return !l.archived&&!['Uscito','Dismesso'].includes(r.state)&&(!k||r[k])&&kinds.some(x=>r[x])&&!repairWashMessage(l.id,r.code)}
 function names(r){return [...new Set((r.repairWork||[]).map(w=>w.completedBy||w.completedByEmail).filter(Boolean))].join(', ')}
 const labelCodes=new Set();
 let labelLot=null;
 function labelTools(lot,container){
  if(!container)return;
  if(labelLot!==lot.id){labelCodes.clear();labelLot=lot.id}
  const rows=lot.rows.filter(r=>r.relabel&&!['Uscito','Dismesso'].includes(r.state));
  const allowed=new Set(rows.map(r=>r.code));
  for(const code of labelCodes)if(!allowed.has(code))labelCodes.delete(code);
  if(!rows.length)return;
  const panel=document.createElement('section');panel.dataset.sewingBulk='';panel.className='panel';
  panel.innerHTML='<h2>Etichette da fare</h2><div class="tools"></div><div class="tools"><button type="button" class="btn secondary" data-all>Seleziona tutto</button><button type="button" class="btn secondary" data-clear>Deseleziona tutto</button><button type="button" class="btn" data-print></button></div>';
  const print=panel.querySelector('[data-print]');
  function count(){print.disabled=!labelCodes.size;print.textContent='Stampa etichette selezionate ('+labelCodes.size+')'}
  const boxes=[];
  for(const row of rows){
   const label=document.createElement('label'),box=document.createElement('input'),card=document.createElement('button');
   box.type='checkbox';box.checked=labelCodes.has(row.code);boxes.push(box);
   label.append(box,document.createTextNode(' '+repairCode(row.code)));
   box.onchange=()=>{if(box.checked)labelCodes.add(row.code);else labelCodes.delete(row.code);count()};
   card.type='button';card.className='link';card.textContent='Scheda prodotto';card.onclick=()=>showGarment(row.code);
   const item=document.createElement('div');item.append(label,card);panel.querySelector('.tools').append(item);
  }
  if(userCan('products_manage')){
   const add=document.createElement('button');add.type='button';add.className='btn secondary';add.textContent='Nuovo prodotto';add.onclick=()=>newGarment();print.before(add);
  }
  panel.querySelector('[data-all]').onclick=()=>{rows.forEach((r,i)=>{labelCodes.add(r.code);boxes[i].checked=true});count()};
  panel.querySelector('[data-clear]').onclick=()=>{labelCodes.clear();boxes.forEach(box=>box.checked=false);count()};
  print.onclick=()=>openLabelEditor([...labelCodes]);count();container.before(panel);
 }
 const sewingGo=go;
 go=function(destination){
  if(destination==='Etichette'&&window.floor?.active&&floor.screen==='repair'){
   show('<h2>Editor etichette</h2><button type="button" class="btn secondary" onclick="this.closest(&quot;dialog&quot;).close()">Torna al cucito</button><iframe title="Editor etichette Mycroclean" src="etichette.html?v=20261109-text-style" style="width:100%;height:75vh;border:0"></iframe>');
   const modal=document.getElementById('modal'),width=modal.style.width,max=modal.style.maxWidth;
   modal.style.width='96vw';modal.style.maxWidth='1400px';
   modal.addEventListener('close',()=>{modal.style.width=width;modal.style.maxWidth=max},{once:true});
   return;
  }
  return sewingGo(destination);
 };
 function decorate(){
  if(page!=='Riparazioni'||repairProductCode||repairLotId===null)return;
  const l=db.lots.find(l=>l.id===Number(repairLotId));if(!l)return;
  if(lotId!==l.id){selected.clear();lotId=l.id}
  selected=new Set([...selected].filter(c=>l.rows.some(r=>r.code===c&&eligible(l,r))));
  document.querySelectorAll('[data-sewing-bulk]').forEach(e=>e.remove());
  const summary=document.querySelector('#app .sewing-products');
  if(summary&&userCan('lots_work')){const head=document.createElement('th');head.dataset.sewingBulk='';head.textContent='Seleziona';summary.querySelector('thead tr').prepend(head);for(const row of summary.querySelectorAll('tbody tr')){const b=row.querySelector('.sewing-open'),m=b?.getAttribute('onclick').match(/decodeURIComponent\('([^']*)'\)/);if(!m)continue;const code=decodeURIComponent(m[1]),r=l.rows.find(r=>r.code===code),cell=document.createElement('td');cell.dataset.sewingBulk='';if(r&&eligible(l,r)){const box=document.createElement('input');box.type='checkbox';box.setAttribute('aria-label','Seleziona capo '+repairCode(code));box.checked=selected.has(code);box.style='width:24px;height:24px';box.onchange=()=>{box.checked?selected.add(code):selected.delete(code);decorate()};cell.append(box)}else cell.textContent='—';row.prepend(cell)}}
  const cards=[...document.querySelectorAll('#app .repair-card,#app .floor-product-card')];
  for(const card of cards){const b=card.querySelector('button[onclick*="repairProductDetail("]');if(!b)continue;const m=b.getAttribute('onclick').match(/decodeURIComponent\('([^']*)'\)/);if(!m)continue;const code=decodeURIComponent(m[1]),r=l.rows.find(r=>r.code===code);if(!r)continue;
   const el=document.createElement('div');el.dataset.sewingBulk='';const n=names(r);if(n){const p=document.createElement('p');p.textContent='Riparato da: '+n;el.append(p)}
   if(userCan('lots_work')&&eligible(l,r)){const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.checked=selected.has(code);box.style='width:24px;height:24px;margin-right:10px';box.onchange=()=>{box.checked?selected.add(code):selected.delete(code);decorate()};label.append(box,document.createTextNode('Seleziona capo'));el.prepend(label)}card.prepend(el);
  }
  labelTools(l,summary||document.querySelector('#app .repair-cards,#app .floor-product-cards'));
  if(!userCan('lots_work'))return;
  const bar=document.createElement('div');bar.dataset.sewingBulk='';bar.className='tools';bar.innerHTML='<button class="btn secondary" id="sewingSelectAll">Seleziona tutto</button><button class="btn secondary" id="sewingClear">Deseleziona tutto</button><button class="btn" id="sewingBulkOpen">Ripara selezionati</button><span id="sewingBulkCount" role="status"></span>';
  const container=summary?.querySelector('.sewing-detail-scroll')||document.querySelector('#app .repair-cards,#app .floor-product-cards');if(!container)return;container.before(bar);
  $('#sewingSelectAll').onclick=()=>{selected=new Set(l.rows.filter(r=>eligible(l,r)).map(r=>r.code));decorate()};$('#sewingClear').onclick=()=>{selected.clear();decorate()};$('#sewingBulkOpen').onclick=open;updateCount();
 }
 function updateCount(){const count=$('#sewingBulkCount'),b=$('#sewingBulkOpen');if(count)count.textContent=selected.size+' capi selezionati';if(b)b.disabled=!selected.size||lotActionBusy}
 function open(){if(!lotMutationAllowed()||!userCan('lots_work')||!selected.size)return;show(`<h2>Ripara ${selected.size} capi selezionati</h2><p>Riparato da: <b>${esc(cloudUser.name||cloudUser.email)}</b></p><p>Lo stesso intervento sarà registrato sui capi indicati nel riepilogo qui sotto. Quantità e minuti sono <b>per singolo capo</b>. Viene chiusa solo l’attività scelta.</p><form id="sewingBulkForm"><label>Attività da completare<select name="kind">${kinds.map(k=>`<option value="${k}">${esc(repairKinds[k])}</option>`).join('')}</select></label><label>Tipo intervento<select name="type" required onchange="repairWorkDefaults(this.form)"><option value="">Seleziona…</option>${repairTypes().filter(t=>t.repairActive).map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')}</select></label><label>Quantità per capo<input name="quantity" type="number" min="1" step="1" value="1" required oninput="repairWorkDefaults(this.form)"></label><label>Minuti per capo<input name="minutes" type="number" min="0" step="0.01" value="0" required></label><p id="repairWorkPrice" class="wide"></p><div id="sewingBulkPreview" class="wide" role="status"></div><label class="wide">Note per ogni capo<textarea name="notes" maxlength="500"></textarea></label><p class="wide" id="sewingBulkError" role="alert"></p><div class="wide"><button class="btn">Salva intervento sui selezionati</button><button type="button" class="btn secondary" onclick="document.querySelector('#modal').close()">Annulla</button></div></form>`);const codes=[...selected],id=lotId;const form=$('#sewingBulkForm');const l=db.lots.find(l=>l.id===id);form.elements.kind.value=kinds.find(k=>codes.some(c=>l.rows.some(r=>r.code===c&&eligible(l,r,k))))||'repair';form.addEventListener('change',()=>preview(form,id,codes));form.addEventListener('input',()=>preview(form,id,codes));form.onsubmit=e=>submit(e,id,form.sewingCodes||[]);preview(form,id,codes)}
 function preview(form,id,codes){
  const l=db.lots.find(l=>l.id===id),kind=form.elements.kind.value,ready=[],excluded=[];
  for(const code of codes){const r=l?.rows.find(r=>r.code===code);if(r&&eligible(l,r,kind))ready.push(code);else excluded.push({code,reason:!r?'Capo non disponibile':repairWashMessage(id,code)||(['Uscito','Dismesso'].includes(r.state)?r.state:l.archived?'Lotto archiviato':'Attività “'+repairKinds[kind]+'” non aperta')})}
  form.sewingCodes=ready;
  $('#sewingBulkPreview').innerHTML='<b>'+ready.length+' di '+codes.length+' capi saranno lavorati</b><p>'+ready.map(c=>esc(repairCode(c))).join(', ')+'</p>'+(excluded.length?'<p>Restano esclusi:</p><ul>'+excluded.map(x=>'<li>'+esc(repairCode(x.code))+' · '+esc(x.reason)+'</li>').join('')+'</ul>':'')+(!ready.length?'<p>Scegli un’altra attività oppure modifica la selezione.</p>':'');
  const b=form.querySelector('button:not([type])');b.textContent='Salva intervento su '+ready.length+' capi';b.disabled=!ready.length||lotActionBusy;
  const t=repairTypes().find(t=>t.id===form.elements.type.value),q=Number(form.elements.quantity.value);if(t&&t.unit==='piece'&&Number.isFinite(q))$('#repairWorkPrice').textContent='Importo per capo: '+euro3(t.priceMills*q)+' · Totale '+ready.length+' capi: '+euro3(t.priceMills*q*ready.length);
 }
 async function submit(e,id,codes){e.preventDefault();if(!lotMutationAllowed()||!userCan('lots_work'))return;const f=new FormData(e.target),kind=f.get('kind'),quantity=Number(f.get('quantity')),minutes=Number(f.get('minutes')),err=$('#sewingBulkError');err.textContent='';if(!codes.length||!kinds.includes(kind)||!Number.isSafeInteger(quantity)||quantity<1||!Number.isFinite(minutes)||minutes<0)return err.textContent='Controlla quantità e minuti.';lotActionBusy=true;e.submitter.disabled=true;
  try{await cloudFlush();const l=db.lots.find(l=>l.id===id),t=repairTypes().find(t=>t.id===f.get('type')&&t.repairActive);if(!l||!t)throw Error('Seleziona un tipo di intervento attivo.');const rows=codes.map(c=>l.rows.find(r=>r.code===c));if(rows.some(r=>!r||!eligible(l,r,kind)))throw Error('Alcuni capi non hanno questa attività aperta o non sono lavorabili. Rivedi la selezione.');
   const next=clone(db),target=next.lots.find(l=>l.id===id),at=new Date().toISOString();for(const code of codes){const r=target.rows.find(r=>r.code===code),work={id:crypto.randomUUID(),repairTypeId:t.id,name:t.name,unit:t.unit,priceMills:t.unit==='piece'?t.priceMills:0,quantity,minutesHundredths:Math.round(minutes*100),costMills:t.unit==='piece'?t.priceMills*quantity:0,kind,notes:String(f.get('notes')||'').trim(),completedAt:at,completedBy:cloudUser.name,completedByEmail:cloudUser.email};(r.repairWork??=[]).push(work);r[kind]=false;const event={action:'Intervento eseguito · '+t.name+' · '+quantity+' · '+repairMinutes(work.minutesHundredths)+' min · '+euro3(work.costMills),code,time:new Date(at).toLocaleString('it-IT',{timeZone:'Europe/Rome'}),actor:cloudUser.name||'',actorEmail:cloudUser.email||''};target.events.push(event);const g=next.garments.find(g=>g.id===code);if(g)(g.history??=[]).push({...event,lot:lotno(target)})}
   const result=await cloudRequest('save',{revision:cloudRevision,changes:cloudDelta(next)});cloudRevision=result.revision;db=next;cloudBase=clone(next);codes.forEach(c=>selected.delete(c));$('#modal').close();repairDetail(id);notify(codes.length+' capi: intervento salvato.');
  }catch(error){err.textContent=error.message;e.submitter.disabled=false}finally{lotActionBusy=false;updateCount()}
 }
 const old=repairDetail;repairDetail=function(...args){const result=old(...args);decorate();return result};
 if(window.floor){const draw=floor.draw;floor.draw=function(...args){const r=draw.apply(this,args);decorate();return r}}
})();
