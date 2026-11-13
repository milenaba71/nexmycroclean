/* Create numbered garments in entry with resumable, idempotent per-item saves. */
(function(){
 const E=window.EntryProduct={saving:false};
 E.deadline=async function(task,ms=25000){let timer;try{return await Promise.race([Promise.resolve(task),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('TIMEOUT')),ms)})])}finally{clearTimeout(timer)}};
 E.mount=function(){
  if(!current||stage!=='Entrata')return;
  const section=document.getElementById('scan')?.closest('.lot-work-section');if(!section||document.getElementById('entryNewProduct'))return;
  const b=document.createElement('button');b.id='entryNewProduct';b.type='button';b.className='btn entry-new-product';b.textContent='+ Nuovi prodotti';
  b.hidden=!userCan('lots_work')||!!current.archived;b.onclick=E.open;section.querySelector('.scan')?.after(b);
 };
 E.open=function(){
  if(E.saving||lotBusy()||washBusy||dryBusy||prodBusy)return notify('Attendi la registrazione in corso.');
  if(!current||stage!=='Entrata'||current.archived||!userCan('lots_work'))return;
  const lot=current,storeKey='mycro-entry-new:'+cloudUser.email+':'+lot.id;let job=null;
  try{job=JSON.parse(sessionStorage.getItem(storeKey))}catch{}
  if(job?.request_id)job={type_id:job.type_id,items:[job],saved:[]};
  if(!job&&(!washChoice||!selectedProcessing()))return notify('Scegli prima il percorso e il lavaggio.');
  const types=catalogRows('type').filter(t=>t.active);if(!types.length)return notify('Inserisci prima un tipo prodotto nelle anagrafiche.');
  const dialog=document.getElementById('modal');dialog.style.maxWidth='620px';
  show('<h2>Nuovi prodotti nel lotto</h2><p><b>'+esc(lotno(lot))+'</b><br>'+esc(lot.client)+' · '+esc(lot.departmentName||'Reparto non indicato')+'</p><form id="entryProductForm" style="display:block"><label style="display:grid;gap:8px">Tipo di capo<select id="entryProductType" required><option value="">Scegli il tipo…</option>'+types.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name)+'</option>').join('')+'</select></label><label style="display:grid;gap:8px;margin-top:14px">Quanti capi?<input id="entryProductQuantity" type="number" min="1" max="100" step="1" value="1" required></label><p>Un barcode diverso per ogni capo. Tutti i prodotti vengono aggiunti al lotto con lo stesso tipo, cliente, reparto e percorso. Fino a 100 capi per operazione.</p><p id="entryProductError" role="status" aria-live="polite"></p><div class="tools"><button class="btn" type="submit" id="entryProductSave">Crea prodotti e aggiungi al lotto</button><button class="btn secondary" type="button" id="entryProductCancel">Annulla</button></div></form>');
  const select=document.getElementById('entryProductType'),quantity=document.getElementById('entryProductQuantity'),form=document.getElementById('entryProductForm'),err=document.getElementById('entryProductError'),save=document.getElementById('entryProductSave');
  if(job){select.value=job.type_id;quantity.value=job.items.length;select.disabled=quantity.disabled=true;err.textContent=(job.saved?.length||0)+' di '+job.items.length+' capi già inseriti. Premi Riprendi per completare senza duplicati.';save.textContent='Riprendi inserimento'}
  const guard=e=>{if(E.saving)e.preventDefault()};dialog.addEventListener('cancel',guard);dialog.addEventListener('close',()=>dialog.removeEventListener('cancel',guard),{once:true});
  document.getElementById('entryProductCancel').onclick=()=>{if(!E.saving)dialog.close()};
  form.onsubmit=async e=>{
   e.preventDefault();if(E.saving)return;
   if(current?.id!==lot.id||stage!=='Entrata')return notify('Riapri il lotto in Entrata.');
   if(!job){
    const n=Number(quantity.value);if(!select.value||!Number.isInteger(n)||n<1||n>100){err.textContent='Scegli il tipo e una quantità intera da 1 a 100.';return}
    const pair=washChoiceParts(),base={lot_id:lot.id,type_id:select.value,program_id:pair?.[0]||null,machine_id:pair?.[1]||null,processing_id:pair?null:selectedProcessing()?.id};
    job={type_id:select.value,items:Array.from({length:n},()=>({...base,request_id:crypto.randomUUID()})),saved:[]};
   }
   const persist=()=>sessionStorage.setItem(storeKey,JSON.stringify(job));
   try{persist()}catch{return notify('Impossibile conservare il salvataggio nel browser. Abilita la memoria del sito e riprova.')}
   E.saving=true;lotActionBusy=true;select.disabled=quantity.disabled=true;form.querySelectorAll('button').forEach(b=>b.disabled=true);
   let lastData=null;
   try{
    err.textContent='Preparazione del salvataggio…';await E.deadline(cloudFlush());
    while(job.saved.length<job.items.length){
     err.textContent=job.saved.length+' di '+job.items.length+' capi inseriti. Creazione del prossimo barcode…';
     const controller=new AbortController();let result;
     try{let request=appSupabase.rpc('laundry_entry_new_product',{p_payload:job.items[job.saved.length]});if(request.abortSignal)request=request.abortSignal(controller.signal);result=await E.deadline(request)}finally{controller.abort()}
     const {data,error}=result;if(error)throw Error(error.message);
     if(!data?.saved_id)throw Error('Risposta del server incompleta.');
     lastData=data;job.saved.push(data.saved_id);persist();cloudAccept(data,false);
    }
    const codes=[...job.saved];sessionStorage.removeItem(storeKey);
    detail();
    show('<h2>'+codes.length+' prodotti aggiunti al lotto</h2><p>'+esc(types.find(t=>t.id===job.type_id)?.name||'')+' · '+esc(lotno(lot))+'</p><p>Barcode creati: '+codes.map(esc).join(', ')+'</p><div class="tools"><button type="button" class="btn" id="entryProductLabel">Crea tutte le etichette</button><button type="button" class="btn secondary" id="entryProductDone">Chiudi</button></div>');
    document.getElementById('entryProductLabel').onclick=()=>{dialog.close();openLabelEditor(codes)};
    document.getElementById('entryProductDone').onclick=()=>{dialog.close();document.getElementById('scan')?.focus()};
    void E.deadline(washRpc('read',{lotId:lot.id}),15000).then(()=>{if(current?.id===lot.id)washRender()}).catch(()=>notify('Prodotti salvati. Premi Aggiorna per ricaricare i carrelli.'));
   }catch(error){
    const message=error.message||'Errore di connessione';
    err.textContent=job.saved.length+' di '+job.items.length+' capi confermati. '+(/TIMEOUT|timeout|fetch|network|abort/i.test(message)?'Il server non ha risposto in tempo.':'Salvataggio interrotto: '+message)+ ' Premi Riprendi: i codici già creati non saranno duplicati.';
    save.textContent='Riprendi inserimento';form.querySelectorAll('button').forEach(b=>b.disabled=false);
   }finally{E.saving=false;lotActionBusy=false}
  };
 };
 let queued=false;new MutationObserver(()=>{if(!queued){queued=true;queueMicrotask(()=>{queued=false;E.mount()})}}).observe(document.getElementById('app'),{childList:true,subtree:true});E.mount();
})();
