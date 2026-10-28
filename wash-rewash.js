/* Rewash is a new machine cycle; its billing marker survives folding and exit. */
let rewashSaving=false;
const flagBeforeMachineRewash=setRegisteredFlag;
setRegisteredFlag=function(code,kind,value){
 if(kind!=='rewash')return flagBeforeMachineRewash(code,kind,value);
 const row=current?.rows.find(r=>r.code===code);if(!row)return;
 if(!value&&(row.rewashPending||Number(row.rewashCycles)>0)){notify('Il rilavaggio resta registrato per il conteggio.');renderLotRows();return;}
 if(value){renderLotRows();return machineRewashDialog(code);}
 return flagBeforeMachineRewash(code,kind,value);
};
const rowsBeforeMachineRewash=renderLotRows;
renderLotRows=function(){
 rowsBeforeMachineRewash();
 document.querySelectorAll('#lotRows input[aria-label^="Rilavaggio "]').forEach(input=>{
  const code=input.getAttribute('aria-label').slice('Rilavaggio '.length),row=current?.rows.find(r=>r.code===code);if(!row)return;
  if(row.rewashPending||Number(row.rewashCycles)>0)input.disabled=true;
  const host=input.closest('td');
  const count=document.createElement('small');count.style.display='block';count.textContent='Rilavaggi eseguiti: '+Number(row.rewashCycles||0);host.append(count);
  if(lotWritable()&&row.state!=='Uscito'&&row.washBatchId&&!row.rewashPending&&row.state!=='In lavaggio'){
   const button=document.createElement('button');button.type='button';button.className='link';button.textContent='Invia a rilavaggio';button.onclick=()=>machineRewashDialog(code);host.append(button);
  }
 });
};
async function machineRewashDialog(code){
 if(!lotMutationAllowed()||rewashSaving)return;
 const lotId=current.id;
 try{
  await cloudFlush();await washRpc('read',{lotId});cloudAccept(await cloudRequest(),false);
  if(current?.id!==lotId)return;
  const row=current.rows.find(r=>r.code===code),batch=washState.batches.find(b=>b.id===row?.washBatchId);
  if(!row||row.state==='Uscito')return notify('Il prodotto è già uscito o non è presente nel lotto.');
  if(!batch||batch.state!=='estimated')return notify('Attendi la fine della macchinata prima di inviare il prodotto a rilavaggio.');
  const options=washOptions(),selected=washKey(batch.program_id,batch.machine_id);
  show(`<h2>Invia a rilavaggio · ${esc(productBarcode(db.garments.find(g=>g.id===code))||code)}</h2><p>Il prodotto viene contato una volta nel nuovo carrello. Il lavaggio aggiuntivo si contabilizza alla fine del ciclo. Il flag Rilavaggio resterà visibile anche dopo la piegatura e l’uscita.</p><label style="display:grid;gap:8px">Programma e macchina<select id="rewashProgram">${options.map(o=>`<option value="${esc(o.key)}" ${o.key===selected?'selected':''}>${esc(o.t.name)} · ${esc(o.m.name)}${washMachineBusy(o.m.id)?' · In coda':''}</option>`).join('')}</select></label><div class="tools"><button id="rewashSaveButton" class="btn" ${options.length?'':'disabled'}>Metti nel carrello</button><button class="btn secondary" onclick="$('#modal').close()">Annulla</button></div>`);
  $('#rewashSaveButton').onclick=()=>queueMachineRewash(lotId,code,batch.id);
 }catch(e){notify(washMessage(e));}
}
async function queueMachineRewash(lotId,code,previousBatchId){
 if(rewashSaving||lotBusy())return;
 const selected=washOptions().find(o=>o.key===$('#rewashProgram')?.value);if(!selected)return notify('Scegli programma e macchina.');
 rewashSaving=true;const button=$('#rewashSaveButton');if(button)button.disabled=true;
 try{
  await cloudFlush();
  const {data,error}=await appSupabase.rpc('laundry_queue_rewash',{p_payload:{lotId,code,previousBatchId,programId:selected.t.id,machineId:selected.m.id}});
  if(error)throw Error(error.message);
  $('#modal').close();cloudAccept(data,false);await washRpc('read',{lotId});
  if(current?.id===lotId)detail();
  notify('Prodotto inserito nel carrello di rilavaggio. Il lavaggio aggiuntivo sarà conteggiato a fine ciclo.');
 }catch(e){notify(e.message==='REWASH_ALREADY_QUEUED'?'Prodotto già inserito in un altro carrello. Aggiorna il lotto.':washMessage(e));if(button)button.disabled=false;}
 finally{rewashSaving=false;}
}
