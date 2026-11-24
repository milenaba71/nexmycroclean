/* Customer price lists are saved with contracts through the existing authorized client save. */
let rentalPriceDraft=null;
function rentalPriceLists(c){return Array.isArray(c?.rentalPriceLists)?c.rentalPriceLists:[]}
function rentalLinkedPriceList(c,k){return rentalPriceLists(c).find(p=>p.id===k?.priceListId)}
function rentalPriceLabel(p){return p.name+' · v'+p.version}
function rentalPriceTable(p){
 if(!p)return '<p>Nessun listino collegato al contratto.</p>';
 return '<h3>'+esc(rentalPriceLabel(p))+'</h3>'+(p.notes?'<p style="white-space:pre-wrap">'+esc(p.notes)+'</p>':'')+'<div class="scroll"><table><thead><tr><th>Tipo prodotto</th><th>Valore capo €</th><th>Canone € / capo / mese</th><th>Lavaggio</th></tr></thead><tbody>'+p.rows.map(r=>'<tr><td>'+esc(r.typeName)+'</td><td>'+assetMoney(r.priceCents)+'</td><td>'+(r.feeMills==null?'Da definire':euro3(r.feeMills))+'</td><td>'+(r.washMode==='included'?'Incluso nel canone':r.washMode==='extra'?(r.washPriceMills==null?'Extra · da definire':euro3(r.washPriceMills)+' / capo'):'Da definire')+'</td></tr>').join('')+'</tbody></table></div>';
}
function rentalPriceListsPanel(c,k){
 const selected=rentalLinkedPriceList(c,k),editable=rentalAdmin()&&c.active!==false&&k.status!=='closed';
 return '<section class="rental-price-lists"><h3>Listino del contratto</h3><p>Prezzi concordati per tipo di prodotto. Puoi riutilizzare un listino negli altri contratti dello stesso cliente.</p>'+(editable?'<div class="tools"><button class="btn" onclick="rentalPriceEdit('+assetArg(k.id)+')">＋ Crea listino</button><button class="btn secondary" onclick="rentalPriceLinkDialog('+assetArg(k.id)+')" '+(rentalPriceLists(c).length?'':'disabled')+'>Collega listino esistente</button>'+(selected?'<button class="btn secondary" onclick="rentalPriceEdit('+assetArg(k.id)+','+assetArg(selected.id)+')">Modifica listino · nuova versione</button>':'')+'</div>':'')+rentalPriceTable(selected)+(k.priceListId&&!selected?'<p role="alert">Il listino collegato non è disponibile. Controlla il collegamento.</p>':'')+'<p>Il collegamento registra gli accordi del contratto. I valori già congelati sui capi restano nello storico.</p></section>';
}
function rentalPriceContext(contractId){
 if(!rentalAdmin())throw Error('Non hai il permesso di gestire contratti e listini.');
 const c=rentalClient(),k=rentalContract(c,contractId);
 if(!c||!k)throw Error('Contratto non disponibile.');
 if(c.active===false||k.status==='closed')throw Error('Cliente disattivato o contratto chiuso: listino in sola lettura.');
 return {c,k};
}
function rentalPriceRowMarkup(r={}){
 const options=catalogRows('type').filter(t=>t.active||t.id===r.typeId),input=(name,value,step)=>'<input name="'+name+'" type="number" min="0" step="'+step+'" value="'+(value==null?'':value)+'" placeholder="Da definire">';
 return '<div class="rental-price-row panel" style="padding:14px"><div class="tools" style="align-items:end;flex-wrap:wrap"><label style="min-width:180px;flex:1">Tipo prodotto *<select name="typeId" required><option value="">Scegli tipo</option>'+options.map(t=>'<option value="'+esc(t.id)+'" '+(r.typeId===t.id?'selected':'')+'>'+esc(t.name)+'</option>').join('')+'</select></label><label>Valore capo (€)'+input('price',r.priceCents==null?null:(r.priceCents/100).toFixed(2),'0.01')+'</label><label>Canone (€ / capo / mese)'+input('fee',r.feeMills==null?null:(r.feeMills/1000).toFixed(3),'0.001')+'</label><label>Lavaggi<select name="washMode" onchange="rentalPriceWashToggle(this)">'+[['unknown','Da definire'],['included','Inclusi'],['extra','Prezzo extra']].map(([v,l])=>'<option value="'+v+'" '+((r.washMode||'unknown')===v?'selected':'')+'>'+l+'</option>').join('')+'</select></label><label data-wash-price '+(r.washMode==='extra'?'':'hidden')+'>Prezzo lavaggio (€ / capo)'+input('washPrice',r.washPriceMills==null?null:(r.washPriceMills/1000).toFixed(3),'0.001')+'</label><button type="button" class="link" onclick="this.closest(\'.rental-price-row\').remove()">Rimuovi riga</button></div></div>';
}
function rentalPriceWashToggle(select){select.closest('.rental-price-row').querySelector('[data-wash-price]').hidden=select.value!=='extra'}
function rentalPriceAddRow(){const target=document.getElementById('rentalPriceRows');if(target.children.length>=100)return notify('Un listino può contenere al massimo 100 tipi.');target.insertAdjacentHTML('beforeend',rentalPriceRowMarkup())}
function rentalPriceEdit(contractId,listId){
 try{
  const {c,k}=rentalPriceContext(contractId),p=listId?rentalPriceLists(c).find(p=>p.id===listId):null;
  if(listId&&!p)throw Error('Listino non disponibile.');
  rentalPriceDraft={clientId:c.id,id:k.id,expected:JSON.stringify(k),mode:'edit',sourceId:p?.id||null,newListId:crypto.randomUUID()};
  rentalModal('<h2>'+(p?'Nuova versione del listino':'Crea listino')+'</h2><p>'+esc(c.name)+' · Contratto '+esc(k.number)+'</p><form id="rentalPriceForm"><label class="wide">Nome listino *<input name="name" required maxlength="120" value="'+esc(p?.name||'')+'" placeholder="Es. Noleggio indumenti 2026"></label><div class="wide" id="rentalPriceRows">'+(p?.rows||[{}]).map(rentalPriceRowMarkup).join('')+'</div><button type="button" class="btn secondary wide" onclick="rentalPriceAddRow()">＋ Aggiungi tipo prodotto</button><label class="wide">Note e condizioni<textarea name="notes" maxlength="3000" rows="3">'+esc(p?.notes||'')+'</textarea></label>'+(p?'<p class="wide">La nuova versione sarà collegata a questo contratto. Gli altri contratti manterranno la versione precedente.</p>':'')+'<p id="rentalPriceError" class="wide" role="alert"></p><div class="wide tools"><button type="submit" class="btn" name="saveMode" value="link">Salva e collega al contratto</button><button type="submit" class="btn secondary" name="saveMode" value="only">Salva solo listino</button><button type="button" class="btn secondary" onclick="document.querySelector(\'#modal\').close()">Annulla</button></div></form>');
  document.getElementById('rentalPriceForm').onsubmit=rentalPriceSave;
 }catch(e){notify(e.message)}
}
function rentalPriceReadForm(form){
 const f=new FormData(form),rows=[...form.querySelectorAll('.rental-price-row')].map(el=>{
  const get=n=>el.querySelector('[name="'+n+'"]').value,typeId=get('typeId'),type=catalogRows('type').find(t=>t.id===typeId);
  const price=rentalParseMoney(get('price')),washMode=get('washMode');
  if(price!=null&&price%10)throw Error('Il valore del capo ammette al massimo due decimali.');
  return {typeId,typeName:type?.name||'',priceCents:price==null?null:price/10,feeMills:rentalParseMoney(get('fee')),washMode,washPriceMills:washMode==='extra'?rentalParseMoney(get('washPrice')):null};
 });
 const p={name:String(f.get('name')||'').trim(),notes:String(f.get('notes')||'').trim(),rows};rentalPriceValidate(p);return p;
}
function rentalPriceValidate(p){
 if(!p.name||p.name.length>120||p.notes.length>3000)throw Error('Controlla nome e note del listino.');
 if(!Array.isArray(p.rows)||!p.rows.length||p.rows.length>100)throw Error('Inserisci da 1 a 100 tipi di prodotto.');
 const seen=new Set();
 for(const r of p.rows){
  if(!r.typeId||!r.typeName||seen.has(r.typeId))throw Error('Scegli un tipo per ogni riga, senza ripeterlo.');seen.add(r.typeId);
  if(!['unknown','included','extra'].includes(r.washMode))throw Error('Modalità lavaggio non valida.');
  for(const n of [r.priceCents,r.feeMills,r.washPriceMills])if(n!==null&&(!Number.isSafeInteger(n)||n<0))throw Error('Importo non valido.');
  if(r.washMode==='extra'&&r.washPriceMills===null)throw Error('Inserisci il prezzo del lavaggio extra.');
  if(r.priceCents===null&&r.feeMills===null&&r.washPriceMills===null&&r.washMode!=='included')throw Error('Inserisci almeno un prezzo o indica lavaggi inclusi per ogni tipo.');
 }
}
function rentalPriceApply(c,draft,p,id,link){
 const k=rentalCurrentEditable(c,draft);
 if(!k||c.active===false||k.status==='closed')throw Error('Cliente disattivato o contratto chiuso.');
 rentalPriceValidate(p);
 const source=draft.sourceId?rentalPriceLists(c).find(x=>x.id===draft.sourceId):null;
 if(draft.sourceId&&!source)throw Error('Listino di origine non disponibile.');
 if(rentalPriceLists(c).some(x=>x.id===id))throw Error('Listino già salvato.');
 const familyId=source?.familyId||source?.id||id,version=1+Math.max(0,...rentalPriceLists(c).filter(x=>(x.familyId||x.id)===familyId).map(x=>x.version||1));
 const value={...p,id,familyId,version,createdAt:new Date().toISOString(),createdBy:cloudUser.email};
 (c.rentalPriceLists??=[]).push(value);
 if(link){k.priceListId=id;k.updatedAt=value.createdAt}
 rentalEvent(c,link?'Listino creato e collegato':'Listino creato',k,{listId:id,name:p.name,version,previousListId:JSON.parse(draft.expected).priceListId||null});return value;
}
async function rentalPriceSave(e){
 e.preventDefault();if(rentalSaving)return;if(rentalPriceDraft?.mode!=='edit')return;rentalPriceDraft.newListId??=crypto.randomUUID();const form=e.target,draft={...rentalPriceDraft};
 const buttons=[...form.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);
 try{
  const p=rentalPriceReadForm(form),id=draft.newListId,link=e.submitter?.value!=='only';
  await mutateRentalClient(draft.clientId,c=>rentalPriceApply(c,draft,p,id,link));
  document.querySelector('#modal').close();rentalClientId=draft.clientId;rentalFinanceTabs.set(draft.id,'prices');rentalClientView();notify(link?'Listino salvato e collegato al contratto.':'Listino salvato. Puoi collegarlo dalla scheda Listini.');
 }catch(error){form.querySelector('#rentalPriceError').textContent=error.message;buttons.forEach(b=>b.disabled=false)}
}
function rentalPriceLinkDialog(contractId){
 try{
  const {c,k}=rentalPriceContext(contractId);
  rentalPriceDraft={clientId:c.id,id:k.id,expected:JSON.stringify(k),mode:'link'};
  rentalModal('<h2>Collega listino al contratto</h2><p>'+esc(c.name)+' · '+esc(k.number)+'</p><form id="rentalPriceLinkForm"><label class="wide">Listino<select name="listId"><option value="">Nessun listino collegato</option>'+rentalPriceLists(c).slice().reverse().map(p=>'<option value="'+esc(p.id)+'" '+(p.id===k.priceListId?'selected':'')+'>'+esc(rentalPriceLabel(p))+'</option>').join('')+'</select></label><div class="wide" id="rentalPricePreview"></div><p class="wide" role="alert" id="rentalPriceError"></p><div class="wide tools"><button class="btn" type="submit">Salva collegamento</button><button class="btn secondary" type="button" onclick="document.querySelector(\'#modal\').close()">Annulla</button></div></form>');
  const form=document.getElementById('rentalPriceLinkForm'),select=form.elements.listId;
  const preview=()=>{document.getElementById('rentalPricePreview').innerHTML=rentalPriceTable(rentalPriceLists(c).find(p=>p.id===select.value))};select.onchange=preview;preview();form.onsubmit=rentalPriceLinkSave;
 }catch(e){notify(e.message)}
}
function rentalPriceLinkApply(c,draft,listId){
 const k=rentalCurrentEditable(c,draft);
 if(!k||c.active===false||k.status==='closed')throw Error('Cliente disattivato o contratto chiuso.');
 const p=listId?rentalPriceLists(c).find(p=>p.id===listId):null;if(listId&&!p)throw Error('Scegli un listino di questo cliente.');
 const before=k.priceListId||null;k.priceListId=listId||null;k.updatedAt=new Date().toISOString();rentalEvent(c,listId?'Listino collegato':'Collegamento listino rimosso',k,{before,after:listId||null,name:p?.name||''});
}
async function rentalPriceLinkSave(e){
 e.preventDefault();if(rentalSaving)return;const form=e.target,draft={...rentalPriceDraft};if(draft.mode!=='link')return;
 const listId=String(new FormData(form).get('listId')||''),buttons=[...form.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);
 try{await mutateRentalClient(draft.clientId,c=>rentalPriceLinkApply(c,draft,listId));document.querySelector('#modal').close();rentalClientId=draft.clientId;rentalFinanceTabs.set(draft.id,'prices');rentalClientView();notify('Collegamento listino salvato.')}
 catch(error){form.querySelector('#rentalPriceError').textContent=error.message;buttons.forEach(b=>b.disabled=false)}
}
