/* Explicit field patches; stable product IDs and selection across pages. */
let productEditPending=[],productEditBusy=false;
const productEditFields=[['client','Cliente / azienda'],['dept','Reparto'],['type','Tipo prodotto'],['size','Taglia'],['color','Colore'],['name','Nome utilizzatore'],['ARMADIO','Armadio'],['POSIZIONE','Posizione'],['ESTERNA','Etichetta esterna'],['estimatedBirthDate','Data presunta nascita indumento'],['NOTE','Note']];
const selectionBeforeBulkEdit=updateProductSelection;
updateProductSelection=function(){selectionBeforeBulkEdit();const bar=$('#productSelectionTools');if(!bar)return;let b=$('#editSelectedProducts');if(!userCan('products_manage')){b?.remove();return}if(!b){b=document.createElement('button');b.id='editSelectedProducts';b.type='button';b.className='btn secondary';b.onclick=productEditDialog;bar.append(b)}b.textContent='Modifica selezionati ('+labelSelection.size+')';b.disabled=productEditBusy||!labelSelection.size};
function productEditOptions(key){
 if(key==='client')return ensureClients().filter(c=>c.active!==false).map(c=>c.name);
 if(key==='dept')return [...new Set(catalogRows('dept').filter(d=>d.active).map(d=>d.name))].sort((a,b)=>a.localeCompare(b,'it'));
 return catalogRows(key).filter(r=>r.active).map(r=>r.name);
}
async function productEditDialog(){
 if(!userCan('products_manage')||productEditBusy)return;
 if(lotBusy())return notify('Attendi le operazioni in corso.');
 productEditPending=[...labelSelection];if(!productEditPending.length)return notify('Seleziona almeno un prodotto.');
 productEditBusy=true;
 try{await cloudFlush();cloudAccept(await cloudRequest(),false);
 show(`<h2>Modifica ${productEditPending.length} prodotti selezionati</h2><p>La selezione comprende tutte le pagine, anche i prodotti nascosti dai filtri attuali.</p><p><b>Spunta soltanto i campi da modificare.</b> Un campo spuntato e lasciato vuoto cancella quel valore, dove consentito. Gli altri campi restano invariati.</p><form id="productBulkEditForm" onsubmit="confirmProductEdit(event)" style="display:block">${productEditFields.map(([key,label])=>{const select=['client','dept','type','size','color'].includes(key);const control=select?`<select name="${key}" aria-label="${label}"><option value="">${key==='dept'?'Nessun reparto (svuota)':'Seleziona…'}</option>${productEditOptions(key).map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('')}</select>`:key==='NOTE'?'<textarea name="NOTE" aria-label="Note" maxlength="5000" rows="3"></textarea>':`<input name="${key}" type="${key==='estimatedBirthDate'?'date':'text'}" aria-label="${label}" maxlength="150">`;return `<div style="margin:14px 0"><label style="display:flex;align-items:center;gap:8px;margin-bottom:6px"><input type="checkbox" name="apply" value="${key}" style="width:auto"> Modifica ${label}</label>${control}</div>`}).join('')}<p>Per cambiare cliente, verifica anche il reparto. I capi in lotti aperti o collegati a noleggi e ordini non verranno trasferiti. Barcode, RFID e date di creazione restano invariati.</p><p id="productEditStatus" role="status"></p><div class="tools"><button type="submit" class="btn">Rivedi e applica modifiche</button><button type="button" class="btn secondary" onclick="$('#modal').close()">Annulla</button></div></form>`);
 }catch(e){notify(e.message)}finally{productEditBusy=false;updateProductSelection()}
}
function productEditPatch(form){const data=new FormData(form),patch={};for(const key of data.getAll('apply')){if(!productEditFields.some(([k])=>k===key))throw Error('Campo non valido.');const value=String(data.get(key)||'').trim();if(['client','type','size','color'].includes(key)&&!value)throw Error('Seleziona un valore per '+productEditFields.find(([k])=>k===key)[1]+'.');patch[key]=value;}if(!Object.keys(patch).length)throw Error('Spunta almeno un campo da modificare.');return patch}
async function confirmProductEdit(e){
 e.preventDefault();if(productEditBusy||!userCan('products_manage'))return;
 let patch;try{patch=productEditPatch(e.target)}catch(error){$('#productEditStatus').textContent=error.message;return}
 const ids=productEditPending.slice();
 const summary=Object.entries(patch).map(([key,value])=>productEditFields.find(([k])=>k===key)[1]+': '+(value||'(svuota)')).join('\n');
 if(!confirm('Applicare queste modifiche a '+ids.length+' prodotti?\n\n'+summary))return;
 productEditBusy=true;lotActionBusy=true;let updated=0,unchanged=0,processed=0,skipped=[],errorText='';
 e.target.querySelectorAll('button,input,select,textarea').forEach(el=>el.disabled=true);
 try{await cloudFlush();for(let offset=0;offset<ids.length;offset+=500){$('#productEditStatus').textContent='Salvataggio: '+processed+' di '+ids.length+' prodotti elaborati…';const {data,error}=await appSupabase.rpc('laundry_edit_products',{p_ids:ids.slice(offset,offset+500),p_patch:patch,p_revision:cloudRevision});if(error)throw Error(error.message);if(!Array.isArray(data?.updated_ids)||!Array.isArray(data?.unchanged_ids)||!Array.isArray(data?.skipped))throw Error('Risposta incompleta. Aggiorna i dati per verificare il risultato.');cloudAccept(data,false);for(const id of [...data.updated_ids,...data.unchanged_ids])labelSelection.delete(id);updated+=data.updated_ids.length;unchanged+=data.unchanged_ids.length;skipped.push(...data.skipped);processed+=Math.min(500,ids.length-offset);}}
 catch(error){errorText=/REVISION_CONFLICT/.test(error.message)?'I dati sono cambiati da un’altra postazione. Aggiorna prima di riprovare.':/INVALID_CATALOG_VALUE|INVALID_CLIENT/.test(error.message)?'Una voce anagrafica non è più disponibile. Aggiorna e selezionala nuovamente.':/FORBIDDEN|PERMISSION_DENIED/.test(error.message)?'Non hai il permesso di modificare i prodotti.':error.message;}
 finally{productEditBusy=false;lotActionBusy=false;productEditPending=[]}
 render();cloudDecorate();show(`<h2>Modifica multipla prodotti</h2><p>${updated} aggiornati · ${unchanged} già conformi · ${skipped.length} non modificati.</p>${skipped.length?`<ul style="max-height:260px;overflow:auto">${skipped.map(p=>`<li>${esc(p.id)} · ${esc(p.reason)}</li>`).join('')}</ul>`:''}${errorText?`<p role="alert">Operazione interrotta. ${esc(errorText)} Le modifiche già confermate restano salvate. In caso di errore di rete, aggiorna i dati per verificare l’esito.</p>`:''}<p>I prodotti non modificati rimangono selezionati.</p><button class="btn secondary" onclick="$('#modal').close()">Chiudi</button>`);
}
