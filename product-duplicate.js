/* Duplicate descriptive data through the existing atomic new-product save. */
const productCardBeforeDuplicate=productCard;
productCard=async function(id){
 await productCardBeforeDuplicate(id);
 const form=$('#productForm');
 if(!id||!form||!$('#modal').open||!userCan('products_manage'))return;
 const button=document.createElement('button');button.type='button';button.className='btn secondary';button.id='duplicateProductButton';button.textContent='Duplica prodotto';
 button.onclick=()=>duplicateProduct(id,button);
 form.querySelector('button[type="submit"]')?.parentNode.append(button);
 const bulk=document.createElement('button');bulk.type='button';bulk.className='btn';bulk.id='bulkProductButton';bulk.textContent='Crea più prodotti ed etichette';bulk.onclick=()=>openBulkProductCopies(id);button.after(bulk);
};
async function duplicateProduct(id,button){
 if(!userCan('products_manage')||button?.disabled)return;
 if(button)button.disabled=true;
 try{
  await productCard(null);
  const form=$('#productForm'),g=db.garments.find(g=>g.id===id);
  if(!form||!$('#modal').open)return;
  if(!g){$('#modal').close();return notify('Prodotto originale non più disponibile.');}
  const raw=g.raw||{};
  const set=(name,value)=>{const el=form.elements.namedItem(name);if(!el)return;el.value=value??'';el.dispatchEvent(new Event('change',{bubbles:true}));};
  set('client',g.client);
  for(const name of ['name','type','dept','size','color','max']){
   const el=form.elements.namedItem(name);
   if(el?.tagName==='SELECT')el.innerHTML=masterOptions(name,g[name],g.client);
   set(name,g[name]==='Da definire'?'':g[name]);
  }
  for(const name of ['ARMADIO','POSIZIONE','MATRICOLA','INIZIALI','ESTERNA','LOTTO','NOTE','ACCESSORI NOTE'])set(name,raw[name]);
  set('rental',g.rental===true?'yes':g.rental===false?'no':'unknown');
  const contract=form.elements.namedItem('rentalContractId');
  if(contract){
   const ref=g.rentalContract,valid=ref&&rentalFormActiveContracts(form).some(k=>k.id===ref.contractId)&&rentalFormClient(form)?.id===ref.clientId;
   if(valid)set('rentalContractId',ref.contractId);
   else if(Object.hasOwn(g,'rentalContract'))set('rentalContractId','__stock__');
  }
  const accessories=String(raw.ACCESSORI||'').split(' | ').filter(Boolean);
  const menu=$('#productAccessoriesMenu');if(menu)menu.outerHTML=productAccessoriesDropdown(accessories,raw);
  form.elements.namedItem('ALLERGICO').checked=yes(raw.ALLERGICO);
  for(const name of ['SCARTO','SMARRITO','AL LIMITE ACCETTABILITA'])form.elements.namedItem(name).checked=false;
  set('wash',0);set('creation',new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}));set('personalization','');
  set('barcodeMode','manual');set('id','');
  form.elements.namedItem('id').readOnly=false;form.elements.namedItem('id').required=false;
  $('#modal h2').textContent='Duplica prodotto · '+productBarcode(g);
  const note=document.createElement('p');note.className='wide notice';note.textContent='Copia dei dati salvati del prodotto '+productBarcode(g)+'. Scansiona il nuovo tag oppure lascia il campo vuoto per generare un barcode automatico al salvataggio. Controlla i dati e premi Salva prodotto. Lavaggi, scarto, smarrimento e storico ripartono da zero; il prodotto originale rimane invariato.';form.prepend(note);
  rentalProductPreview(form);form.elements.namedItem('id').focus({preventScroll:true});
 }catch(error){notify('Duplicazione non completata. '+error.message);if(button)button.disabled=false;}
}

let bulkCopiesBusy=false,bulkCopiesSource=null,bulkCopiesRequest=null;
function bulkCopiesStorageKey(id){return 'mycro-product-copies:'+cloudUser.email+':'+id}
function openBulkProductCopies(id){
 if(!userCan('products_manage'))return notify('Non hai il permesso di creare prodotti.');
 if(bulkCopiesBusy||lotBusy())return notify('Attendi le registrazioni in corso.');
 const g=db.garments.find(g=>g.id===id);if(!g)return notify('Riapri la scheda prodotto.');
 bulkCopiesSource=id;bulkCopiesRequest=null;
 try{const saved=JSON.parse(sessionStorage.getItem(bulkCopiesStorageKey(id))||'null');if(saved?.source===id&&Number.isInteger(saved.quantity)&&saved.quantity>=1&&saved.quantity<=200&&typeof saved.token==='string')bulkCopiesRequest=saved}catch{}
 show(`<h2>Crea più prodotti ed etichette</h2><p>Modello salvato · <b>${esc(productBarcode(g))}</b></p><p>${esc([g.type,g.size,g.color,g.client,g.dept,g.name].filter(Boolean).join(' · '))}</p><p>Ogni nuovo capo avrà un barcode progressivo diverso e una data di creazione automatica. I dati descrittivi saranno uguali al modello; lavaggi e storico partiranno da zero. Il contratto di noleggio viene mantenuto solo se attivo, altrimenti i nuovi capi saranno in scorta.</p><form id="bulkCopiesForm" onsubmit="createBulkProductCopies(event)"><label class="wide">Quantità di nuovi prodotti da creare<input name="quantity" type="number" min="1" max="200" step="1" required value="${bulkCopiesRequest?.quantity||20}" ${bulkCopiesRequest?'readonly':''}></label><p class="wide">La quantità indica nuovi capi aggiuntivi: il prodotto modello resta nell’elenco. Usa i dati già salvati nella scheda.</p>${bulkCopiesRequest?'<p class="wide notice">Riprendi la richiesta precedente. Se era già stata completata, verranno riaperte le stesse etichette senza creare altri prodotti.</p>':''}<p class="wide" id="bulkCopiesStatus" role="status"></p><div class="wide"><button class="btn" type="submit">${bulkCopiesRequest?'Riprendi creazione ed etichette':'Crea prodotti ed etichette'}</button> <button class="btn secondary" type="button" onclick="$(\'#modal\').close()">Chiudi</button></div></form>`);
}
async function createBulkProductCopies(e){
 e.preventDefault();if(bulkCopiesBusy||!userCan('products_manage'))return;
 const form=e.target,quantity=Number(form.elements.quantity.value),status=$('#bulkCopiesStatus');
 if(!Number.isInteger(quantity)||quantity<1||quantity>200){status.textContent='Inserisci una quantità intera da 1 a 200.';return}
 if(!bulkCopiesRequest)bulkCopiesRequest={source:bulkCopiesSource,quantity,token:crypto.randomUUID()};
 // Retain the same request token across retries, including uncertain network outcomes.
 try{sessionStorage.setItem(bulkCopiesStorageKey(bulkCopiesSource),JSON.stringify(bulkCopiesRequest))}catch{status.textContent='Il browser non consente di conservare la richiesta. Abilita l’archiviazione del sito prima di creare i prodotti.';return}
 form.elements.quantity.readOnly=true;form.querySelectorAll('button').forEach(b=>b.disabled=true);
 bulkCopiesBusy=true;lotActionBusy=true;status.textContent=`Creazione di ${quantity} prodotti e preparazione etichette…`;
 let result;
 try{
  await cloudFlush();
  const {data,error}=await appSupabase.rpc('laundry_copy_products',{p_source_id:bulkCopiesRequest.source,p_quantity:bulkCopiesRequest.quantity,p_request_id:bulkCopiesRequest.token,p_revision:cloudRevision});
  if(error)throw Error(error.message);
  if(!Array.isArray(data?.created_ids)||data.created_ids.length!==bulkCopiesRequest.quantity)throw Error('Risposta incompleta. Premi Riprendi per verificare la stessa richiesta.');
  result=data;cloudAccept(data,false);
  sessionStorage.removeItem(bulkCopiesStorageKey(bulkCopiesSource));bulkCopiesRequest=null;
 }catch(error){
  const message=String(error.message);status.textContent=/REVISION_CONFLICT/.test(message)?'I dati sono cambiati. Chiudi, premi Aggiorna dati e riapri questo comando per riprendere la stessa richiesta.':/INVALID_CLIENT/.test(message)?'Il cliente del prodotto non è disponibile o è disattivato. Verifica l’anagrafica.':/FORBIDDEN|UNAUTHORIZED|SESSION_REVOKED/.test(message)?'Accesso non autorizzato o sessione scaduta. Accedi nuovamente.':'Creazione da verificare. '+message+' Riprova: la stessa richiesta non crea duplicati.';
  form.querySelector('button[type="submit"]').textContent='Riprendi creazione ed etichette';
 }finally{bulkCopiesBusy=false;lotActionBusy=false;form.querySelectorAll('button').forEach(b=>b.disabled=false)}
 if(!result)return;
 $('#modal').close();labelSelection.clear();result.created_ids.forEach(id=>labelSelection.add(id));garmentPage=0;
 try{const rows=result.created_ids.map(id=>db.garments.find(g=>g.id===id));if(rows.some(g=>!g))throw Error('Aggiorna i prodotti prima di aprire le etichette.');sessionStorage.setItem('mycro-label-transfer',JSON.stringify(rows.map(labelRow)));go('Etichette');notify(`${result.created_count} prodotti disponibili in Prodotti. Etichette pronte, una per ciascun barcode.`)}
 catch(error){render();notify(`${result.created_count} prodotti creati. Apri Etichette selezionate per stampare. ${error.message}`)}
}
