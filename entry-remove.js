/* Correct mistaken entry without deleting the garment master record. */
(function(){
 const R=window.EntryRemove={busy:false};
 R.open=function(codes){
  if(R.busy||lotBusy()||washBusy||dryBusy||prodBusy)return notify('Attendi la registrazione in corso.');
  if(!current||stage!=='Entrata'||!userCan('lots_work')||current.archived)return;
  const id=current.id,rows=current.rows.filter(r=>codes.includes(r.code));if(!rows.length)return notify('Seleziona almeno un capo.');
  const products=new Map(db.garments.map(g=>[g.id,g])),dialog=document.getElementById('modal');dialog.style.maxWidth='650px';
  show('<h2>Rimuovi dal lotto</h2><p>Rimuovere '+rows.length+' capi da <b>'+esc(lotno(current))+'</b>? Le schede restano in Prodotti. Carrelli e conteggi saranno aggiornati.</p><div style="max-height:180px;overflow:auto">'+rows.map(r=>'<p><b>'+esc(productBarcode(products.get(r.code))||r.code)+'</b> · '+esc(products.get(r.code)?.type||'')+'</p>').join('')+'</div><p id="entryRemoveError" role="alert"></p><div class="tools"><button type="button" class="btn" style="background:#c8232c;color:white" id="entryRemoveConfirm">Rimuovi dal lotto</button><button type="button" class="btn secondary" id="entryRemoveCancel">Annulla</button></div>');
  document.getElementById('entryRemoveCancel').onclick=()=>{if(!R.busy)dialog.close()};
  const guard=e=>{if(R.busy)e.preventDefault()};dialog.addEventListener('cancel',guard);dialog.addEventListener('close',()=>dialog.removeEventListener('cancel',guard),{once:true});
  document.getElementById('entryRemoveConfirm').onclick=async()=>{
   if(R.busy||current?.id!==id)return;R.busy=true;lotActionBusy=true;
   dialog.querySelectorAll('button').forEach(b=>b.disabled=true);const err=document.getElementById('entryRemoveError');err.textContent='Rimozione in corso…';
   try{
    await EntryProduct.deadline(cloudFlush());
    const controller=new AbortController();let response;
    try{response=await EntryProduct.deadline(appSupabase.rpc('laundry_remove_entry_products',{p_payload:{lot_id:id,codes:rows.map(r=>r.code)}}).abortSignal(controller.signal))}finally{controller.abort()}
    if(response.error)throw Error(response.error.message);
    cloudAccept(response.data,false);for(const r of rows)lotPicks.delete(r.code);
    dialog.close();detail();notify(response.data.removed_count+' capi rimossi dal lotto. Le schede prodotto sono conservate.');
    void EntryProduct.deadline(washRpc('read',{lotId:id}),15000).then(()=>{if(current?.id===id)washRender()}).catch(()=>notify('Rimozione salvata. Premi Aggiorna per ricaricare i carrelli.'));
   }catch(e){const msg=String(e.message);err.textContent=/PRODUCT_ALREADY_PROCESSED|WASH_ALREADY_STARTED/.test(msg)?'Il capo è già in lavorazione o il ciclo è stato avviato: non può essere rimosso come errore di entrata.':/PRODUCT_IN_PRODUCTION_PLAN/.test(msg)?'Il capo è già collegato alla pianificazione. Rimuovi prima la relativa pianificazione.':/FORBIDDEN/.test(msg)?'Non hai il permesso di modificare questo lotto.':'Rimozione non confermata. Puoi riprovare senza duplicare operazioni. '+msg;dialog.querySelectorAll('button').forEach(b=>b.disabled=false)}
   finally{R.busy=false;lotActionBusy=false}
  };
 };
 R.mount=function(){
  if(!current||stage!=='Entrata'||!userCan('lots_work')||current.archived)return;
  const bar=document.querySelector('.lot-selection-bar');if(!bar)return;
  let b=document.getElementById('entryRemoveSelected');if(!b){b=document.createElement('button');b.id='entryRemoveSelected';b.type='button';b.className='btn';b.style.background='#c8232c';b.style.color='white';b.textContent='Rimuovi selezionati dal lotto';b.onclick=()=>R.open([...lotPicks]);bar.append(b)}
  b.disabled=R.busy||!lotPicks.size;
 };
 let pending=false;new MutationObserver(()=>{if(!pending){pending=true;queueMicrotask(()=>{pending=false;R.mount()})}}).observe(document.getElementById('app'),{childList:true,subtree:true});R.mount();
})();
