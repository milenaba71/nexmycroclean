function canDeleteProductionTypes(){
  return cloudUser?.role==='admin' &&
    (cloudUser.isSuperAdmin || cloudUser.permissions?.production_type_delete===true);
}

const renderTypesBeforeDeletion=pTypes;
pTypes=function(){
  renderTypesBeforeDeletion();
  if(!canDeleteProductionTypes())return;
  const body=$('#prodBody');
  const tools=body.querySelector('.tools');
  tools.insertAdjacentHTML('beforeend',`
    <label class="prod-check"><input type="checkbox" data-select-all-types>Seleziona tutte</label>
    <button type="button" class="btn secondary" data-delete-selected-types disabled>Elimina selezionate</button>`);
  const batch=tools.querySelector('[data-delete-selected-types]');
  const all=tools.querySelector('[data-select-all-types]');
  const selected=()=>[...body.querySelectorAll('[data-delete-type-pick]:checked')].map(input=>input.value);
  const refresh=()=>{
    const count=selected().length;
    batch.disabled=!count;
    batch.textContent=count?'Elimina selezionate ('+count+')':'Elimina selezionate';
    const total=body.querySelectorAll('[data-delete-type-pick]').length;
    all.disabled=!total;
    all.checked=total>0&&count===total;
    all.indeterminate=count>0&&count<total;
  };
  body.querySelectorAll('.prod-grid .prod-panel').forEach((card,index)=>{
    const type=prod.types[index];
    if(!type||['entry','fold','exit','repair-unknown'].includes(type.id)
      ||prod.tasks.some(task=>task.typeId===type.id)
      ||washState?.links?.some(link=>link.program_id===type.id)
      ||washState?.batches?.some(batch=>batch.program_id===type.id))return;
    card.querySelector('.prod-content').insertAdjacentHTML('beforeend',`
      <div class="prod-actions">
        <label class="prod-check"><input type="checkbox" data-delete-type-pick value="${esc(type.id)}">Seleziona</label>
        <button type="button" class="link" data-delete-one-type>Elimina</button>
      </div>`);
    card.querySelector('[data-delete-one-type]').onclick=()=>confirmProductionTypeDeletion([type.id]);
    card.querySelector('[data-delete-type-pick]').onchange=refresh;
  });
  all.onchange=()=>{
    for(const input of body.querySelectorAll('[data-delete-type-pick]'))input.checked=all.checked;
    refresh();
  };
  batch.onclick=()=>confirmProductionTypeDeletion(selected());
  refresh();
};

function confirmProductionTypeDeletion(ids){
  if(!canDeleteProductionTypes()||!ids.length)return;
  const types=prod.types.filter(type=>ids.includes(type.id));
  if(types.length!==ids.length)return notify('L’elenco è cambiato. Aggiorna e riprova.');
  const revision=prodRevision;
  show(`<h2>Elimina ${types.length===1?'lavorazione':'lavorazioni'}</h2>
    <p>Verranno eliminate queste voci dai Tempi delle lavorazioni.</p>
    <ul>${types.map(type=>'<li>'+esc(type.name)+'</li>').join('')}</ul>
    <p id="productionTypeDeleteError" class="prod-risk" role="alert"></p>
    <div class="prod-actions"><button type="button" class="btn" id="confirmProductionTypeDeletion">Conferma eliminazione</button>
    <button type="button" class="btn secondary" onclick="$('#modal').close()">Annulla</button></div>`);
  const button=$('#confirmProductionTypeDeletion');
  const message=$('#productionTypeDeleteError');
  button.onclick=async()=>{
    if(prodBusy)return;
    prodBusy=true;
    button.disabled=true;
    try{
      const {error}=await appSupabase.rpc('laundry_production_type_delete',{p_ids:ids,p_revision:revision});
      if(error)throw Error(error.message);
      $('#modal').close();
      notify(types.length===1?'Lavorazione eliminata.':types.length+' lavorazioni eliminate.');
      try{await pRpc('read');pDraw()}catch{notify('Eliminazione salvata. Premi Aggiorna per ricaricare l’elenco.')}
    }catch(error){
      message.textContent=({
        PRODUCTION_TYPE_IN_USE:'Una voce è collegata a un’attività o a un programma. Rimuovila dalla selezione oppure disattivala.',
        STANDARD_TYPE_REQUIRED:'Una voce è necessaria per i percorsi standard.',
        REVISION_CONFLICT:'I dati sono cambiati. Chiudi, aggiorna l’elenco e riprova.',
        SELECTION_CHANGED:'L’elenco è cambiato. Aggiorna e riprova.',
      })[error.message]||pError(error);
    }finally{prodBusy=false;button.disabled=false}
  };
}
