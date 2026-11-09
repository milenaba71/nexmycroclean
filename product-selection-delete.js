/* Reuse product selection across pages. The database enforces permission and dependencies. */
let productDeletePending=[],productDeleteBusy=false;
function canDeleteProducts(){return cloudUser?.role==='admin'&&userCan('products_delete')}
const selectionBeforeDelete=updateProductSelection;
updateProductSelection=function(){selectionBeforeDelete();const bar=$('#productSelectionTools');if(!bar)return;let b=$('#deleteSelectedProducts');if(!canDeleteProducts()){b?.remove();return}if(!b){b=document.createElement('button');b.id='deleteSelectedProducts';b.type='button';b.className='btn';b.onclick=productDeleteDialog;bar.append(b)}b.textContent='Elimina selezionati ('+labelSelection.size+')';b.disabled=productDeleteBusy||labelSelection.size===0};
function productDeleteDialog(){
 if(!canDeleteProducts())return notify('Non hai il permesso di eliminare prodotti.');
 if(productDeleteBusy||lotBusy())return notify('Attendi le operazioni in corso.');
 productDeletePending=[...labelSelection];if(!productDeletePending.length)return notify('Seleziona almeno un prodotto.');
 show(`<h2>Elimina ${productDeletePending.length} prodotti selezionati</h2><p>La selezione comprende tutte le pagine, anche i prodotti non visibili con i filtri attuali.</p><p>Confermi la cancellazione definitiva dei prodotti selezionati? Quelli con lavaggi, storico, lotti, lavorazioni, noleggi o ordini collegati saranno mantenuti. I barcode eliminati non saranno riutilizzati automaticamente.</p><ul style="max-height:200px;overflow:auto">${productDeletePending.slice(0,50).map(id=>{const g=db.garments.find(g=>g.id===id);return `<li>${esc(g?productBarcode(g):id)}${g?' · '+esc([g.type,g.size,g.client].filter(Boolean).join(' · ')):''}</li>`}).join('')}</ul>${productDeletePending.length>50?`<p>Altri ${productDeletePending.length-50} prodotti selezionati.</p>`:''}<form onsubmit="confirmProductDeletion(event)"><p class="wide" role="status" id="productDeleteStatus"></p><div class="wide"><button class="btn" type="submit">Conferma eliminazione</button> <button class="btn secondary" type="button" onclick="$('#modal').close()">Annulla</button></div></form>`);
}
async function confirmProductDeletion(e){
 e.preventDefault();if(productDeleteBusy||!canDeleteProducts()||!productDeletePending.length)return;
 const ids=productDeletePending.slice(),skipped=[];let removed=0,processed=0,errorMessage='';
 productDeleteBusy=true;lotActionBusy=true;e.target.querySelectorAll('button').forEach(b=>b.disabled=true);
 try{
  await cloudFlush();
  for(let offset=0;offset<ids.length;offset+=500){
   const status=$('#productDeleteStatus');if(status)status.textContent=`Controllo ed eliminazione · ${processed} di ${ids.length} elaborati…`;
   const {data,error}=await appSupabase.rpc('laundry_delete_products',{p_ids:ids.slice(offset,offset+500),p_revision:cloudRevision});
   if(error)throw Error(error.message);
   if(!Array.isArray(data?.deleted_ids)||!Array.isArray(data?.skipped))throw Error('Risposta incompleta. Aggiorna i dati prima di riprovare.');
   cloudAccept(data,false);for(const id of data.deleted_ids)labelSelection.delete(id);
   for(const item of data.skipped)if(item.reason==='Prodotto non più presente')labelSelection.delete(item.id);
   removed+=data.deleted_ids.length;skipped.push(...data.skipped);processed+=Math.min(500,ids.length-offset);
  }
 }catch(error){errorMessage=/REVISION_CONFLICT/.test(error.message)?'I dati sono cambiati da un’altra postazione. Aggiorna i dati prima di riprovare.':/PERMISSION_DENIED|FORBIDDEN/.test(error.message)?'Permesso di eliminazione non disponibile.':error.message}
 finally{productDeleteBusy=false;lotActionBusy=false;productDeletePending=[]}
 render();cloudDecorate();
 show(`<h2>Eliminazione prodotti</h2><p>${removed} prodotti eliminati su ${ids.length} selezionati.</p>${skipped.length?`<p>Prodotti mantenuti o non più presenti</p><ul style="max-height:300px;overflow:auto">${skipped.map(p=>`<li>${esc(p.id)} · ${esc(p.reason)}</li>`).join('')}</ul>`:''}${errorMessage?`<p role="alert">Operazione interrotta. ${esc(errorMessage)} Le eliminazioni già confermate restano valide. I prodotti non elaborati rimangono selezionati; in caso di errore di rete, aggiorna per verificare l’esito.</p>`:''}<button class="btn secondary" onclick="$('#modal').close()">Chiudi</button>`);
}
