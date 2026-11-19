/* Edit lot identity without replacing products, work history or scans. */
let lotEditState=null,lotEditSaving=false;
const lotEditFields=['client','departmentId','departmentName','colli','date','due','airtableOrderId','airtableOrderCode','airtableCustomerOrder'];
function lotEditVersion(l){return JSON.stringify(lotEditFields.map(k=>l[k]??null))}
async function editLotDetails(){
 if(!current||!userCan('lots_work')||current.archived||lotEditSaving)return;
 const lot=clone(current);lotEditState={id:lot.id,base:lotEditVersion(lot),lot,ordersReady:false};
 show(`<h2>Modifica dati · ${esc(lotno(lot))}</h2><form id="lotEditForm" onsubmit="saveLotDetails(event)">
 <label>Azienda / cliente<select name="client" required ${lot.calendarId?'disabled':''}>${ensureClients().filter(c=>c.active!==false||c.name===lot.client).map(c=>`<option value="${esc(c.name)}" ${c.name===lot.client?'selected':''}>${esc(c.name)}</option>`).join('')}</select></label>
 <label>Reparto<select name="departmentId" ${lot.calendarId?'disabled':''}></select></label>
 <label>Colli<input name="colli" type="number" min="1" step="1" required value="${esc(String(lot.colli||1))}"></label>
 <label>Data ingresso<input name="date" type="date" required value="${esc(lot.date||'')}"></label>
 <label class="wide">Ordine Airtable<select name="airtableOrderId" disabled><option value="${esc(lot.airtableOrderId||'')}">${esc(lotOrderSummary(lot)||'Caricamento ordini…')}</option></select></label>
 <label>Data consegna<input name="due" type="date" value="${esc((lot.due||'').slice(0,10))}"></label>
 <p class="wide" id="lotEditDueHelp"></p>
 <p class="wide">${lot.calendarId?'Azienda e reparto sono collegati a un appuntamento del calendario. ':''}Il cambio azienda è consentito solo se i capi presenti appartengono all’azienda scelta. I prodotti e le lavorazioni registrate restano nel lotto.</p>
 <p class="wide" id="lotEditError" role="alert"></p><div class="wide"><button class="btn" type="submit">Salva modifiche</button> <button class="btn secondary" type="button" onclick="$('#modal').close()">Annulla</button></div></form>`);
 const form=$('#lotEditForm'),state=lotEditState;
 function departments(){const values=calendarDepartments(clientByName(form.elements.client.value)?.id,lot.departmentId||'');form.elements.departmentId.innerHTML=pOptions(values,form.elements.client.value===lot.client?lot.departmentId||'':'','Generale / senza reparto')}
 function orders(){const id=clientByName(form.elements.client.value)?.id,select=form.elements.airtableOrderId,old=select.value,choices=airtableOrders.filter(o=>airtableOrderClientId(o)===id);select.innerHTML='<option value="">Nessun ordine associato</option>'+choices.map(o=>`<option value="${esc(o.id)}">${esc(o.code||o.customerOrder||o.id)}</option>`).join('');if(old&&!choices.some(o=>o.id===old)&&form.elements.client.value===lot.client){const option=new Option(lot.airtableOrderCode||'Ordine collegato',old);select.append(option)}select.value=[...select.options].some(o=>o.value===old)?old:'';select.disabled=false;lotEditDue(form)}
 departments();form.elements.client.onchange=()=>{departments();if(state.ordersReady)orders()};form.elements.airtableOrderId.onchange=()=>lotEditDue(form);lotEditDue(form);
 try{await loadAirtableOrders(true);if(!form.isConnected||lotEditState!==state)return;state.ordersReady=true;orders()}
 catch(e){if(form.isConnected){form.querySelector('#lotEditError').textContent='Ordini non caricati: puoi correggere gli altri dati mantenendo il collegamento esistente.';form.elements.client.disabled=true}}
}
function lotEditDue(form){const id=form.elements.airtableOrderId.value,order=airtableOrders.find(o=>o.id===id),due=form.elements.due;due.readOnly=!!id;if(order)due.value=(order.due||'').slice(0,10);form.querySelector('#lotEditDueHelp').textContent=id?(due.value?'Consegna acquisita automaticamente dall’ordine Airtable.':'La data di consegna manca nell’ordine Airtable. Inseriscila in Airtable.'):''}
async function saveLotDetails(event){
 event.preventDefault();if(lotEditSaving||!lotEditState)return;
 const form=event.target,state=lotEditState,err=form.querySelector('#lotEditError'),button=form.querySelector('[type="submit"]');
 lotEditSaving=true;lotActionBusy=true;button.disabled=true;err.textContent='Salvataggio…';
 try{
  await cloudFlush();const snapshot=await cloudRequest(),lot=snapshot.db.lots.find(l=>l.id===state.id);
  if(!lot||lot.archived)throw Error('Il lotto non è più modificabile.');
  if(lotEditVersion(lot)!==state.base)throw Error('I dati sono stati aggiornati da un’altra postazione. Chiudi e riapri Modifica dati lotto.');
  const client=form.elements.client.value,colli=Number(form.elements.colli.value),departmentId=form.elements.departmentId.value,orderId=form.elements.airtableOrderId.value;
  if(!Number.isSafeInteger(colli)||colli<1)throw Error('Inserisci un numero intero di colli, almeno 1.');
  if(client!==lot.client&&lot.calendarId)throw Error('Correggi prima l’appuntamento collegato nel calendario.');
  const order=airtableOrders.find(o=>o.id===orderId),clientRecord=snapshot.db.clientRecords.find(c=>c.name===client);
  if(!clientRecord)throw Error('Seleziona un’azienda valida.');
  if(order&&airtableOrderClientId(order)!==clientRecord.id)throw Error('L’ordine Airtable appartiene a un’altra azienda.');
  const departments=calendarDepartments(clientRecord.id,lot.departmentId||''),departmentName=departments.find(d=>String(d[0])===departmentId)?.[1]||null;
  const updated={...lot,client,colli,date:form.elements.date.value,due:order?(order.due||null):form.elements.due.value||null,departmentId:departmentId||null,departmentName,airtableOrderId:orderId||null,airtableOrderCode:order?.code||(orderId===lot.airtableOrderId?lot.airtableOrderCode:null),airtableCustomerOrder:order?.customerOrder||(orderId===lot.airtableOrderId?lot.airtableCustomerOrder:null)};
  if(!orderId)delete updated.dueSource;
  updated.events=[...(lot.events||[]),{at:new Date().toISOString(),time:new Date().toLocaleString('it-IT'),action:'Dati lotto corretti · '+lotEditFields.filter(k=>JSON.stringify(lot[k]??null)!==JSON.stringify(updated[k]??null)).join(', '),code:'',actor:cloudUser.name||cloudUser.email,actorEmail:cloudUser.email}];
  await cloudRequest('save',{revision:snapshot.revision,changes:{lots:[updated]}});
  cloudAccept(await cloudRequest(),false);$('#modal').close();detail();cloudDecorate();notify('Dati del lotto aggiornati.');
 }catch(e){err.textContent=e.message.includes('LINKED_CALENDAR_CLIENT')?'Correggi prima l’appuntamento collegato nel calendario.':e.message}
 finally{lotEditSaving=false;lotActionBusy=false;button.disabled=false}
}
