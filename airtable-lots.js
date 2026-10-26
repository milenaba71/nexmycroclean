/* Order links belong to each laundry lot, independently of product production references. */
function lotOrderLabel(l){return [l.airtableOrderCode,l.airtableCustomerOrder].filter(Boolean).join(' · ')||l.airtableOrderId||''}
let airtableLotDialogRequest=0,airtableLotCreating=false;
const newLotBeforeOrders=newLot;
newLot=async function(orderId=''){
 if(!lotWritable())return notify('Il tuo ruolo consente la sola consultazione.');
 let request=++airtableLotDialogRequest;
 newLotBeforeOrders();
 let form=$('#modal form'),client=form.elements.client;
 client.innerHTML=ensureClients().filter(c=>c.active!==false).map(c=>`<option>${esc(c.name)}</option>`).join('');
 form.elements.due.value=new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'});
 let label=document.createElement('label');label.className='wide';label.innerHTML='Ordine cliente Airtable<select name="airtableOrderId" disabled><option value="">Caricamento ordini…</option></select>';
 let note=document.createElement('p');note.className='wide notice';note.textContent='Puoi creare più lotti per lo stesso ordine.';client.parentNode.after(label);label.after(note);
 let select=label.querySelector('select'),submit=form.querySelector('button:not([type="button"])');submit.disabled=!!orderId;
 try{
  await loadAirtableOrders(true);
  if(request!==airtableLotDialogRequest||!form.isConnected)return;
  let order=airtableOrders.find(o=>o.id===orderId),c=order&&db.clientRecords.find(c=>c.id===airtableOrderClientId(order)&&c.active!==false);
  if(orderId&&!c){note.textContent='Prima abbina il cliente dell’ordine in Ordini clienti → Abbina clienti.';return}
  if(c){client.value=c.name;client.dispatchEvent(new Event('change'));if(order.due)form.elements.due.value=order.due}
  const update=()=>{let id=clientByName(client.value)?.id,old=select.value;let choices=airtableOrders.filter(o=>airtableOrderClientId(o)===id);select.innerHTML='<option value="">Nessun ordine associato</option>'+choices.map(o=>`<option value="${o.id}">${esc(o.code)} · ${esc(o.customerOrder||'')} · ${esc(o.status||'')}</option>`).join('');select.value=choices.some(o=>o.id===old)?old:'';select.disabled=false;select.dispatchEvent(new Event('change'));note.textContent=choices.length?'Scegli l’ordine del cliente. Puoi suddividerlo in più lotti.':'Nessun ordine abbinato a questo cliente. Controlla Abbina clienti nella sezione Ordini clienti.'};
  update();client.addEventListener('change',update);if(orderId){select.value=orderId;select.dispatchEvent(new Event('change'))}submit.disabled=false;
 }catch(error){if(form.isConnected){select.innerHTML='<option value="">Ordini non disponibili</option>';note.textContent=error.message+(orderId?' Riprova prima di creare il lotto.':' Puoi creare un lotto senza ordine.');submit.disabled=!!orderId}}
};
const createLotBeforeOrders=createLot;
createLot=async function(e){
 let form=e.target,id=form.elements.namedItem('airtableOrderId')?.value;
 if(!id)return createLotBeforeOrders(e);
 e.preventDefault();if(airtableLotCreating)return;airtableLotCreating=true;let button=e.submitter;if(button)button.disabled=true;
 let created=false;
 try{
  await cloudFlush();let f=new FormData(form),o=airtableOrders.find(o=>o.id===id),c=clientByName(f.get('client'));
  if(!o||airtableOrderClientId(o)!==c?.id)throw Error('L’ordine non appartiene al cliente del lotto.');
  let {data,error}=await appSupabase.rpc('laundry_airtable_lot_create',{p_payload:{revision:cloudRevision,client:f.get('client'),colli:+f.get('colli'),due:f.get('due'),airtableOrderId:id}});
  if(error)throw Error(/REVISION_CONFLICT/.test(error.message)?'Dati aggiornati da un’altra postazione. Ricarica e riprova.':/AIRTABLE/.test(error.message)?'Controlla l’ordine e l’abbinamento del cliente prima di riprovare.':error.message);
  created=true;$('#modal').close();cloudAccept(await cloudRequest(),false);openLot(data.lot.id);cloudDecorate();notify('Lotto creato e collegato a '+o.code);
 }catch(error){notify(created?'Lotto creato. Ricarica la pagina per visualizzarlo.':error.message);if(button&&!created)button.disabled=false}finally{airtableLotCreating=false}
};
const detailBeforeOrders=detail;detail=function(){detailBeforeOrders();if(!current?.airtableOrderId)return;let p=document.createElement('div');p.className='notice';p.id='lotAirtableOrder';let b=document.createElement('button');b.className='link';b.textContent='Ordine cliente: '+lotOrderLabel(current);let id=current.airtableOrderId;b.onclick=async()=>{try{await loadAirtableOrders(true);showAirtableOrder(id)}catch(e){notify(e.message)}};p.append(b);$('#app').prepend(p)};
const showAirtableOrderBeforeLots=showAirtableOrder;showAirtableOrder=function(id){showAirtableOrderBeforeLots(id);let o=airtableOrders.find(o=>o.id===id);if(!o)return;let section=document.createElement('section'),lots=db.lots.filter(l=>l.airtableOrderId===id);section.className='wide';section.innerHTML=`<h3>${lots.length} lotti collegati</h3>${lots.map(l=>`<p><button class="link" data-order-lot="${l.id}">${lotno(l)}</button> · ${lotStatus(l)}${l.archived?' · Storico':''} · ${l.rows.length} entrati · ${l.rows.filter(r=>r.state==='Uscito').length} usciti</p>`).join('')||'<p>Nessun lotto ancora aperto per questo ordine.</p>'}${lotWritable()?'<button type="button" class="btn" id="newLotFromOrder">＋ Apri lotto per questo ordine</button>':''}`;$('#modal h2').after(section);section.querySelectorAll('[data-order-lot]').forEach(b=>b.onclick=()=>{$('#modal').close();page='Lotti';openLot(+b.dataset.orderLot)});section.querySelector('#newLotFromOrder')?.addEventListener('click',()=>newLot(id))};
