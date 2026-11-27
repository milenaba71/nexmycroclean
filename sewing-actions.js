/* Sewing writes are atomic and retryable, without replacing the shared database snapshot. */
function sewingApplyResult(result){
 const merge=(target,key,rows)=>{for(const row of rows){const i=target[key].findIndex(x=>String(x.id)===String(row.id));if(i<0)target[key].push(clone(row));else target[key][i]=clone(row)}};
 merge(db,'lots',[result.lot]);merge(db,'garments',result.products||[]);
 merge(cloudBase,'lots',[result.lot]);merge(cloudBase,'garments',result.products||[]);
 // A partial response cannot acknowledge unrelated changes made by other stations.
 if(result.baseRevision===cloudRevision)cloudRevision=result.revision;
 if(current?.id===result.lot.id)current=db.lots.find(l=>l.id===result.lot.id);
}
function sewingError(error){
 const messages={SEWING_DUPLICATE:'Questo intervento è già registrato sul capo. Scegli un altro tipo oppure conferma che vuoi ripeterlo.',SEWING_WORK_CHANGED:'Questo intervento è cambiato. Riapri il dettaglio prima di modificarlo.',SEWING_PRODUCT_CLOSED:'Il capo è già uscito o chiuso: non puoi riaprire la lavorazione.',SEWING_IN_WASH:'Il capo è ancora in lavaggio. Attendi il termine del ciclo.',SEWING_NOT_PENDING:'L’attività è già completata. Riapri il dettaglio per verificarla.',LOT_ARCHIVED:'Il lotto è archiviato.',INVALID_REPAIR_TYPE:'Seleziona un tipo di intervento attivo.',INVALID_SEWING:'Controlla quantità, minuti e note.',SEWING_REASON_REQUIRED:'Scrivi il motivo dell’eliminazione (almeno 3 caratteri).'};
 const message=String(error?.message||error||'');
 return Object.entries(messages).find(([key])=>message.includes(key))?.[1]||(/PERMISSION|FORBIDDEN/.test(message)?'Non hai il permesso di modificare le lavorazioni.':/UNAUTHORIZED|SESSION_REVOKED/.test(message)?'Accedi di nuovo per continuare.':message||'Salvataggio non completato. Riprova.');
}
async function sewingPerform(form,action,lotId,items,onSuccess){
 if(form.dataset.saving||!userCan('lots_work')||!lotMutationAllowed())return false;
 const controls=[...form.querySelectorAll('input,select,textarea,button')],previous=controls.map(x=>x.disabled);
 let alert=form.querySelector('[role=alert]');if(!alert){alert=document.createElement('p');alert.setAttribute('role','alert');form.append(alert)}
 alert.textContent='Salvataggio…';form.dataset.saving='true';lotActionBusy=true;controls.forEach(x=>x.disabled=true);
 let saved=false;
 try{
  await cloudFlush();
  const request=form.sewingRequest||(form.sewingRequest={action,payload:{requestId:crypto.randomUUID(),lotId,items}});
  let result;
  for(let attempt=0;attempt<2;attempt++){
   let response;try{response=await appSupabase.rpc('laundry_sewing_work',{p_action:request.action,p_payload:request.payload})}catch(error){error.uncertain=true;if(attempt===0)continue;throw error}
   if(!response.error){result=response.data;break}
   const error=response.error;error.uncertain=!error.code;
   if(!error.uncertain||attempt===1)throw error;
  }
  sewingApplyResult(result);saved=true;form.sewingRequest=null;form.dataset.uncertain='';
  $('#modal').close();lotActionBusy=false;onSuccess?.(result);
 }catch(error){
  form.dataset.uncertain=error.uncertain?'true':'';
  if(!error.uncertain)form.sewingRequest=null;
  alert.textContent=error.uncertain?'Conferma del salvataggio non ricevuta. Premi di nuovo Salva: la stessa richiesta sarà verificata senza aggiungere doppioni.':sewingError(error);
 }finally{
  delete form.dataset.saving;lotActionBusy=false;
  controls.forEach((x,i)=>x.disabled=form.dataset.uncertain==='true'?!(x.tagName==='BUTTON'&&x.type==='submit'):previous[i]);
 }
 return saved;
}
function sewingRedraw(id,code){if(repairProductCode===code)repairProductDetail(id,code);else repairDetail(id)}

const sewingRegisterBeforeActions=registerRepairWork;
registerRepairWork=function(id,code,kind='repair'){
 const lot=db.lots.find(l=>l.id===id),row=lot?.rows.find(r=>r.code===code);
 if(!row||lot.archived||!userCan('lots_work')||['Uscito','Dismesso'].includes(row.state)||row.lifecycleClosed||row.replacedBy||!lotMutationAllowed())return;
 sewingRegisterBeforeActions(id,code,kind);
 const form=$('#modal form');if(!form||!$('#modal').open)return;
 form.insertAdjacentHTML('afterbegin','<p class="wide"><b>'+esc(sewingKindNames[kind])+'</b> · “Salva e aggiungi altro” mantiene aperta questa attività. “Salva intervento e completa” la chiude.</p>');
 form.insertAdjacentHTML('beforeend','<label class="wide"><span><input type="checkbox" name="allowRepeat"> Confermo di ripetere un intervento già registrato</span></label><p class="wide" role="alert"></p>');
};
saveRepairWork=async function(e,id,code,kind){
 e.preventDefault();const form=e.target;
 if(form.sewingRequest){const req=form.sewingRequest;return sewingPerform(form,req.action,id,req.payload.items,()=>{sewingRedraw(id,code);if(req.payload.items[0].complete===false)registerRepairWork(id,code,kind)})}
 const f=new FormData(form),quantity=Number(f.get('quantity')),minutes=Math.round(Number(f.get('minutes'))*100),another=e.submitter?.name==='another';
 if(!f.get('type')||!Number.isSafeInteger(quantity)||quantity<1||quantity>100000||!Number.isSafeInteger(minutes)||minutes<0||minutes>100000000)return notify('Controlla tipo, quantità e minuti.');
 await sewingPerform(form,'add',id,[{code,kind,typeId:f.get('type'),quantity,minutesHundredths:minutes,notes:String(f.get('notes')||'').trim(),complete:!another,allowRepeat:f.has('allowRepeat')}],()=>{sewingRedraw(id,code);if(another)registerRepairWork(id,code,kind)});
};
finishWithoutRepairCost=function(id,code,kind){
 const form=$('#modal form');if(!form)return;
 return sewingPerform(form,'complete',id,[{code,kind}],()=>sewingRedraw(id,code));
};

editSewingWork=function(button){
 const {lot:id,code,work:workId}=button.dataset,lot=db.lots.find(l=>String(l.id)===String(id));
 const original=lot?.rows.find(r=>r.code===code)?.repairWork?.find(w=>w.id===workId);
 if(!original||lot.archived||!userCan('lots_work')||!lotMutationAllowed())return;
 const expected=clone(original);
 show('<h2>Correggi intervento</h2><p>'+esc(lotno(lot))+' · '+esc(code)+' · '+esc(original.name)+'</p><form id="sewingCorrection"><label>Quantità<input name="quantity" type="number" min="1" max="100000" step="1" required></label><label>Minuti eseguiti<input name="minutes" type="number" min="0" max="1000000" step="0.01" required></label><label>Note<textarea name="notes" maxlength="500"></textarea></label><p role="alert"></p><button class="btn">Salva correzione</button><button type="button" class="btn danger" id="sewingDeleteFromEdit">Elimina intervento</button></form>');
 const form=$('#sewingCorrection');form.elements.quantity.value=original.quantity;form.elements.minutes.value=(original.minutesHundredths||0)/100;form.elements.notes.value=original.notes||'';
 $('#sewingDeleteFromEdit').onclick=()=>deleteSewingWork(button);
 form.onsubmit=e=>{e.preventDefault();return sewingPerform(form,'edit',lot.id,[{code,workId,expected,quantity:form.elements.quantity.valueAsNumber,minutesHundredths:Math.round(form.elements.minutes.valueAsNumber*100),notes:form.elements.notes.value.trim()}],()=>sewingRedraw(lot.id,code))};
};
function deleteSewingWork(button){
 const {lot:id,code,work:workId}=button.dataset,lot=db.lots.find(l=>String(l.id)===String(id)),row=lot?.rows.find(r=>r.code===code),work=row?.repairWork?.find(w=>w.id===workId);
 if(!work||lot.archived||!userCan('lots_work')||!lotMutationAllowed())return;
 const expected=clone(work),canReopen=!['Uscito','Dismesso'].includes(row.state)&&!row.lifecycleClosed&&!row.replacedBy;
 const hasOther=row.repairWork.some(w=>w.id!==workId&&w.kind===work.kind);
 show('<h2>Elimina intervento registrato per errore</h2><p><b>'+esc(code)+' · '+esc(work.name)+'</b><br>Quantità '+esc(String(work.quantity))+' · '+repairMinutes(work.minutesHundredths)+' minuti<br>'+esc(work.completedBy||'')+' · '+esc(repairDate(work.completedAt))+'</p><p>La registrazione sarà tolta dai totali. Il motivo e l’operatore resteranno nello storico.</p><form id="sewingDelete"><label class="wide">Dopo l’eliminazione<select name="reopen"><option value="no">Elimina solo la registrazione errata</option>'+(canReopen?'<option value="yes">Elimina e rimetti l’attività da fare</option>':'')+'</select></label><label class="wide">Motivo<textarea name="reason" minlength="3" maxlength="500" required placeholder="Es. intervento inserito due volte"></textarea></label><p role="alert"></p><div class="wide"><button class="btn danger">Conferma eliminazione</button><button type="button" class="btn secondary" onclick="document.querySelector(\'#modal\').close()">Annulla</button></div></form>');
 const form=$('#sewingDelete');form.elements.reopen.value=canReopen&&!hasOther?'yes':'no';
 form.onsubmit=e=>{e.preventDefault();return sewingPerform(form,'delete',lot.id,[{code,workId,expected,reopen:form.elements.reopen.value==='yes',reason:form.elements.reason.value.trim()}],()=>sewingRedraw(lot.id,code))};
}
