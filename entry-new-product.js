/* One-step product creation from an open entry lot. */
(function(){
 const E=window.EntryProduct={saving:false};
 const key=()=> 'mycro-entry-new:'+cloudUser.email+':'+current.id;
 E.mount=function(){
  if(!current||stage!=='Entrata')return;
  const section=document.getElementById('scan')?.closest('.lot-work-section');if(!section||document.getElementById('entryNewProduct'))return;
  const b=document.createElement('button');b.id='entryNewProduct';b.type='button';b.className='btn entry-new-product';b.textContent='+ Nuovo prodotto';
  b.hidden=!userCan('lots_work')||!!current.archived;b.onclick=E.open;
  section.querySelector('.scan')?.after(b);
 };
 E.open=function(){
  if(E.saving||lotBusy()||washBusy||dryBusy||prodBusy)return notify('Attendi la registrazione in corso.');
  if(!current||stage!=='Entrata'||current.archived||!userCan('lots_work'))return;
  if(!washChoice||!selectedProcessing())return notify('Scegli prima il percorso e il lavaggio.');
  const lot=current,storeKey=key();let pending=null;try{pending=JSON.parse(sessionStorage.getItem(storeKey))}catch{}
  const types=catalogRows('type').filter(t=>t.active);if(!types.length)return notify('Inserisci prima un tipo prodotto nelle anagrafiche.');
  const dialog=document.getElementById('modal');dialog.style.maxWidth='620px';
  show('<h2>Nuovo prodotto nel lotto</h2><p><b>'+esc(lotno(lot))+'</b><br>'+esc(lot.client)+' · '+esc(lot.departmentName||'Reparto non indicato')+'</p><form id="entryProductForm" style="display:block"><label style="display:grid;gap:8px">Tipo di capo<select id="entryProductType" required><option value="">Scegli il tipo…</option>'+types.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name)+'</option>').join('')+'</select></label><p>Il barcode progressivo viene creato automaticamente. Il prodotto viene salvato e registrato in questo lotto.</p><p id="entryProductError" role="alert"></p><div class="tools"><button class="btn" type="submit" id="entryProductSave">Salva e aggiungi al lotto</button><button class="btn secondary" type="button" id="entryProductCancel">Annulla</button></div></form>');
  const select=document.getElementById('entryProductType'),form=document.getElementById('entryProductForm'),err=document.getElementById('entryProductError');
  if(pending){select.value=pending.type_id;select.disabled=true;err.textContent='Verifica del precedente salvataggio: premi Salva per recuperare lo stesso prodotto, senza duplicarlo.'}
  const guard=e=>{if(E.saving)e.preventDefault()};dialog.addEventListener('cancel',guard);dialog.addEventListener('close',()=>dialog.removeEventListener('cancel',guard),{once:true});
  document.getElementById('entryProductCancel').onclick=()=>{if(!E.saving)dialog.close()};
  form.onsubmit=async e=>{
   e.preventDefault();if(E.saving)return;
   if(current?.id!==lot.id||stage!=='Entrata')return notify('Riapri il lotto in Entrata.');
   if(!pending){if(!select.value)return;const pair=washChoiceParts();pending={request_id:crypto.randomUUID(),lot_id:lot.id,type_id:select.value,program_id:pair?.[0]||null,machine_id:pair?.[1]||null,processing_id:pair?null:selectedProcessing()?.id};}
   try{sessionStorage.setItem(storeKey,JSON.stringify(pending))}catch{return notify('Impossibile conservare il salvataggio in questo browser. Riprova dopo aver abilitato la memoria del sito.')}
   E.saving=true;lotActionBusy=true;select.disabled=true;form.querySelectorAll('button').forEach(b=>b.disabled=true);err.textContent='Salvataggio…';
   try{
    await cloudFlush();
    const {data,error}=await appSupabase.rpc('laundry_entry_new_product',{p_payload:pending});if(error)throw Error(error.message);
    sessionStorage.removeItem(storeKey);cloudAccept(data,false);
    detail();try{await washRpc('read',{lotId:lot.id});washRender()}catch{}
    show('<h2>Prodotto aggiunto al lotto</h2><p><b>Barcode '+esc(data.saved_code)+'</b></p><p>'+esc(types.find(t=>t.id===pending.type_id)?.name||'')+' · '+esc(lotno(lot))+'</p><div class="tools"><button type="button" class="btn" id="entryProductLabel">Crea etichetta</button><button type="button" class="btn secondary" id="entryProductDone">Chiudi</button></div>');
    document.getElementById('entryProductLabel').onclick=()=>{dialog.close();prepareLabel({id:data.saved_id})};
    document.getElementById('entryProductDone').onclick=()=>{dialog.close();document.getElementById('scan')?.focus()};
   }catch(error){
    const message=error.message||'Errore di connessione';
    const known=/FORBIDDEN|LOT_NOT_WRITABLE|TYPE_REQUIRED|PROCESSING_REQUIRED|INVALID_PROGRAM_LINK|MACHINE_CAPACITY_REQUIRED|STATION_INACTIVE/.test(message);
    if(known){sessionStorage.removeItem(storeKey);pending=null;select.disabled=false}
    err.textContent=known?'Controlla il tipo, il percorso e i permessi, poi riprova. '+message:'Salvataggio da verificare. Premi di nuovo Salva: verrà recuperato lo stesso prodotto senza duplicati.';
    form.querySelectorAll('button').forEach(b=>b.disabled=false);
   }finally{E.saving=false;lotActionBusy=false}
  };
 };
 let queued=false;new MutationObserver(()=>{if(!queued){queued=true;queueMicrotask(()=>{queued=false;E.mount()})}}).observe(document.getElementById('app'),{childList:true,subtree:true});E.mount();
})();
