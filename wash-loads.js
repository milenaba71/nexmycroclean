/* One physical water load, with source lots and items preserved. */
function washLoadMembers(batch){return batch?.load_group_id?(washState?.batches||[]).filter(b=>b.load_group_id===batch.load_group_id):[batch].filter(Boolean)}
function washLoadQuantity(batch){return washLoadMembers(batch).reduce((n,b)=>n+Number(b.quantity||0),0)}
function washDistinctLoads(batches){const seen=new Set();return batches.filter(b=>{const key=b.load_group_id||b.id;if(seen.has(key))return false;seen.add(key);return true})}
const washIdentityBeforeLoads=washLotIdentity;
washLotIdentity=function(batch){const members=washLoadMembers(batch);return (batch?.load_group_id?'<b class="wash-mixed-label">Lotti misti · unico carico</b>':'')+members.map(b=>washIdentityBeforeLoads(b)+(members.length>1?'<small>'+b.quantity+' capi di questo carrello</small>':'')).join('')};
const washLabelBeforeLoads=washLotLabel;
washLotLabel=function(batch){return washLoadMembers(batch).map(washLabelBeforeLoads).join(' / ')};
washMachineBusy=function(id,exceptBatch){const own=washState?.batches.find(b=>b.id===exceptBatch);return (washState?.batches||[]).some(b=>b.machine_id===id&&b.id!==exceptBatch&&(!own?.load_group_id||b.load_group_id!==own.load_group_id)&&['running','blocked'].includes(b.state))};
const washCardBeforeLoads=washCard;
washCard=function(batch){return washCardBeforeLoads({...batch,quantity:washLoadQuantity(batch)})};
const washCorrectionBeforeLoads=washCorrectionDialog;
washCorrectionDialog=function(id,action){washCorrectionBeforeLoads(id,action);const b=washState?.batches.find(x=>x.id===id);if(b?.load_group_id)$('#modal h2')?.insertAdjacentHTML('afterend','<p class="notice">Carico unificato: questa operazione riguarda tutti i carrelli e i lotti del carico.</p>')};
const washMessageBeforeLoads=washMessage;
washMessage=function(e){return ({SELECT_AT_LEAST_TWO_CARTS:'Seleziona almeno due carrelli.',CART_PROGRAMS_DIFFERENT:'Puoi unire soltanto carrelli con lo stesso programma di lavaggio.',CARTS_CHANGED_REFRESH:'I carrelli sono cambiati. Aggiorna e selezionali nuovamente.',COMBINED_CAPACITY_EXCEEDED:'Il totale supera la capacità della lavatrice scelta.'})[e.message]||washMessageBeforeLoads(e)};
const WashLoads=window.WashLoads={selected:new Set(),saving:false};
WashLoads.eligible=b=>b.machine_kind==='water'&&!b.load_group_id&&!b.started_at&&['gathering','ready'].includes(b.state)&&Number(b.quantity)>0&&washCanOperate(b);
WashLoads.selection=()=> (washState?.batches||[]).filter(b=>WashLoads.selected.has(b.id)&&WashLoads.eligible(b));
WashLoads.toolbar=function(waiting){
 const valid=new Set(waiting.filter(WashLoads.eligible).map(b=>b.id));
 for(const id of WashLoads.selected)if(!valid.has(id))WashLoads.selected.delete(id);
 const rows=WashLoads.selection(),qty=rows.reduce((n,b)=>n+Number(b.quantity),0),same=new Set(rows.map(b=>b.program_id)).size===1;
 return '<div id="washLoadToolbar" class="wash-load-toolbar"><strong>'+rows.length+' carrelli selezionati · '+qty+' capi</strong><button class="floor-button primary" onclick="WashLoads.dialog()" '+(rows.length>1&&same?'':'disabled')+'>Unisci in una lavatrice</button><button class="floor-button" onclick="WashLoads.clear()">Deseleziona</button><p>Seleziona carrelli con lo stesso programma. '+(rows.length>1&&!same?'I programmi selezionati sono diversi.':'Lotti, clienti e reparti restano distinti.')+'</p></div>';
};
WashLoads.card=function(b){return '<div class="wash-load-choice">'+(WashLoads.eligible(b)?'<label><input type="checkbox" '+(WashLoads.selected.has(b.id)?'checked':'')+' onchange="WashLoads.pick(\''+b.id+'\',this.checked)" aria-label="Seleziona carrello da '+Number(b.quantity)+' capi"> Seleziona · '+Number(b.quantity)+' capi</label>':'')+washCard(b)+'</div>'};
WashLoads.pick=function(id,on){if(WashLoads.saving)return;if(on)WashLoads.selected.add(id);else WashLoads.selected.delete(id);const bar=$('#washLoadToolbar');if(bar)bar.outerHTML=WashLoads.toolbar((washState?.batches||[]).filter(b=>b.state!=='running'))};
WashLoads.clear=function(){WashLoads.selected.clear();floor.draw()};
WashLoads.dialog=function(){
 const rows=WashLoads.selection();if(rows.length<2||new Set(rows.map(b=>b.program_id)).size!==1)return notify('Seleziona almeno due carrelli con lo stesso programma.');
 const qty=rows.reduce((n,b)=>n+Number(b.quantity),0),program=washStartPrograms(rows[0]).find(t=>t.id===rows[0].program_id);
 if(!program)return notify('Programma non disponibile o durata da configurare.');
 const machines=(washState?.machines||[]).filter(m=>m.kind==='water'&&m.active!==false&&Number(m.capacity)>=qty&&!washMachineBusy(m.id)&&!(washState.tickets||[]).some(t=>t.machineId===m.id&&t.blocking&&t.status!=='closed'));
 WashLoads.pending={batchIds:rows.map(b=>b.id),programId:program.id,expectedQuantities:Object.fromEntries(rows.map(b=>[b.id,Number(b.quantity)]))};
 show('<h2>Unisci i carrelli in una lavatrice</h2><p><b>'+qty+' capi totali · '+rows.length+' carrelli</b></p><div class="wash-load-review">'+rows.map(b=>'<div>'+washIdentityBeforeLoads(b)+'<b>'+b.quantity+' capi</b></div>').join('')+'</div><p>Programma comune: <b>'+esc(program.name)+'</b> · '+program.value+' minuti</p><label>Lavatrice<select id="washLoadMachine" onchange="WashLoads.capacity()">'+(machines.map(m=>'<option value="'+esc(m.id)+'">'+esc(m.name)+' · '+qty+' / '+m.capacity+' capi</option>').join('')||'<option value="">Nessuna lavatrice libera con capacità sufficiente</option>')+'</select></label><p id="washLoadCapacity"></p><p>Conferma dopo avere caricato fisicamente i capi. L’avvio e le eventuali interruzioni riguarderanno tutto il carico.</p><div class="tools"><button class="btn" id="washLoadConfirm" onclick="WashLoads.start()" '+(machines.length?'':'disabled')+'>Conferma unione e avvia</button><button class="btn secondary" onclick="$(\'#modal\').close()">Annulla</button></div>');
 WashLoads.capacity();
};
WashLoads.capacity=function(){const m=washState?.machines.find(m=>m.id===$('#washLoadMachine')?.value),qty=Object.values(WashLoads.pending?.expectedQuantities||{}).reduce((a,b)=>a+b,0);$('#washLoadCapacity').textContent=m?qty+' capi su '+m.capacity+' · '+(Number(m.capacity)-qty)+' posti liberi':'Attendi una macchina libera oppure seleziona meno carrelli.'};
WashLoads.start=async function(){
 if(WashLoads.saving||washBusy||lotBusy())return;
 const machineId=$('#washLoadMachine')?.value;if(!machineId||!WashLoads.pending)return;
 WashLoads.saving=true;washBusy=true;$('#washLoadConfirm').disabled=true;
 try{await cloudFlush();await washRpc('merge_start',{...WashLoads.pending,machineId});WashLoads.selected.clear();$('#modal').close();notify('Carrelli uniti: lavaggio avviato in una sola lavatrice.');}
 catch(e){notify(washMessage(e));if($('#washLoadConfirm'))$('#washLoadConfirm').disabled=false}
 finally{washBusy=false;WashLoads.saving=false;await floor.refresh()}
};
