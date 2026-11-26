/* Ask about lot quantities. All operational records stay in the active session. */
(function () {
  const metrics = {all:'capi', entered:'capi entrati', fold:'capi pronti da piegare', repair:'capi da riparare', relabel:'capi da etichettare', verify:'capi da verificare', out:'capi usciti'};
  const examples = new Map([
    ['Fermi macchina e manutenzioni', 'maintenance'],
    ['Lavoro svolto per utente', 'users'],
    ['Quanti capi ci sono nei lotti attivi?', 'all'],
    ['Quanti capi sono entrati?', 'entered'],
    ['Quanti capi sono ancora da piegare?', 'fold'],
    ['Quanti capi sono usciti?', 'out'],
    ['Quanti capi sono da riparare?', 'repair'],
    ['Quanti capi sono da etichettare?', 'relabel']
  ]);
  const allowed = () => typeof cloudUser !== 'undefined' && (cloudUser?.isSuperAdmin || cloudUser?.role === 'admin' || cloudUser?.permissions?.assistant_edit===true) && (!document.body.classList.contains('floor-mode') || cloudUser?.isSuperAdmin || cloudUser?.permissions?.assistant_edit===true);
  const fold = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  function matchesMetric(row, metric) {
    if (metric==='all' || metric==='entered') return true;
    if (metric==='out') return row.state==='Uscito';
    if (metric==='fold') {
      return !['Uscito','Dismesso'].includes(row.state) && row.washed && !row.foldedAt &&
        (!row.requiresDrying || row.dryState==='done');
    }
    return row.state!=='Uscito' && row[metric]===true;
  }
  function userWork(target) {
    const container=document.createElement('section');
    target.replaceChildren(container);
    const filter=document.createElement('input');
    filter.type='search';filter.placeholder='Cerca utente';filter.setAttribute('aria-label','Cerca utente');
    const label=document.createElement('label'),archived=document.createElement('input');
    archived.type='checkbox';label.append(archived,' Includi lotti archiviati');
    const result=document.createElement('div');
    container.append(filter,label,result);
    let records=[],errors=0,loading=false,version=0;
    function record(name,action,lot,code,time){
      records.push({name:name||'Non registrato',action,lot:lotno(lot),code:code||'',time:time||''});
    }
    function draw(){
      const groups=new Map();
      for(const r of records){
        if(!fold(r.name).includes(fold(filter.value)))continue;
        if(!groups.has(r.name))groups.set(r.name,[]);
        groups.get(r.name).push(r);
      }
      result.replaceChildren();
      for(const [name,rows] of [...groups].sort(([a],[b])=>a.localeCompare(b,'it'))){
        const details=document.createElement('details'),summary=document.createElement('summary');
        summary.textContent=name+' · '+rows.length+' operazioni registrate';
        details.append(summary);
        details.ontoggle=()=>{
          if(!details.open||details.children.length>1)return;
          const list=document.createElement('ul');
          for(const r of rows){
            const li=document.createElement('li');
            const when=/^\d{4}-/.test(r.time)?new Date(r.time).toLocaleString('it-IT'):r.time;
            li.textContent=[r.action,r.lot,r.code,when].filter(Boolean).join(' · ');
            list.append(li);
          }
          details.append(list);
        };
        result.append(details);
      }
      const status=document.createElement('p');
      status.textContent=loading?'Caricamento aperture e avvii macchina…':errors?'Riepilogo parziale: aperture e avvii macchina indisponibili per '+errors+' lotti.':groups.size?'':'Nessuna operazione registrata per questa selezione.';
      result.append(status);
    }
    async function load(){
      const request=++version;
      const active=()=>request===version&&target.contains(container)&&allowed()&&dialog.open;
      const lots=db.lots.filter(l=>archived.checked||!l.archived);
      records=[];errors=0;loading=true;
      for(const lot of lots){
        const folded=new Set();
        for(const e of lot.events||[]){
          if(/piegatura|piegato/i.test(e.action||''))folded.add(String(e.code));
          record(LotActors.name(e.actor||e.actorEmail,lot),e.action||'Operazione',lot,e.code,e.at||e.time);
        }
        for(const row of lot.rows||[]){
          if(row.foldedAt&&!folded.has(String(row.code)))record(LotActors.name(row.foldedBy,lot),'Piegatura',lot,row.code,row.foldedAt);
          for(const w of row.repairWork||[])record(LotActors.name(w.completedBy||w.completedByEmail,lot),w.name||'Riparazione',lot,row.code,w.completedAt);
        }
      }
      draw();
      for(let i=0;i<lots.length&&active();i+=4){
        await Promise.all(lots.slice(i,i+4).map(async lot=>{
          try{
            const {data,error}=await appSupabase.rpc('laundry_lot_operator_summary',{p_lot_id:lot.id});
            if(!active())return;
            if(error||!data)throw Error();
            if(data.creator)record(data.creator.name,'Apertura lotto',lot,'',data.creator.at);
            for(const m of [...data.machines,...data.dryers])record(m.operator,'Avvio '+m.machine+' · '+m.program,lot,'',m.started_at);
          }catch{if(active())errors++}
        }));
      }
      if(active()){loading=false;draw()}
    }
    filter.oninput=draw;archived.onchange=load;load();
  }
  function answer(plan, target) {
    if(plan.action==='edit'){previewEdit(plan,target);return}
    if(plan.metric==='users'){userWork(target);return}
    if(plan.metric==='maintenance'){
      const id=generation,active=()=>dialog.open&&id===generation&&allowed();
      target.textContent='Apertura manutenzioni…';
      import('./maintenance-assistant.js?v=20261126-maintenance').then(()=>{if(active())window.openMaintenanceAssistant(target,{active,showQuota,machine:plan.machine||'',days:plan.days})}).catch(()=>{if(active())target.textContent='Impossibile aprire le manutenzioni. Riprova.'});return;
    }
    target.replaceChildren();
    if (!Object.hasOwn(metrics,plan.metric)) {
      target.textContent='Posso analizzare fermi macchina e manutenzioni, oppure contare i capi per lotto, cliente, reparto e intervento. Per modificare, indica un solo codice prodotto o numero lotto e un solo valore. Campi supportati: nome utilizzatore, taglia, colore e note prodotto; colli, date e note lotto.';
      return;
    }
    let total=0;
    const sources=document.createElement('ul');
    for(const lot of db.lots) {
      if (lot.archived || (plan.lot && String(lot.id)!==String(plan.lot)) ||
          !fold(lot.client).includes(fold(plan.client)) || !fold(lot.departmentName).includes(fold(plan.department))) continue;
      const count=lot.rows.filter(row=>matchesMetric(row,plan.metric)).length;
      if(!count)continue;
      total+=count;
      const li=document.createElement('li');li.textContent=lotno(lot)+' · '+lot.client+' · '+(lot.departmentName||'Reparto non indicato')+' · '+count;
      sources.append(li);
    }
    const heading=document.createElement('strong');heading.textContent=total+' '+metrics[plan.metric]+' nei lotti non archiviati';
    target.append(heading,sources);
  }
  const editLabels={name:'Nome utilizzatore',size:'Taglia',color:'Colore',notes:'Note',colli:'Colli',date:'Data ingresso',due:'Data consegna'};
  function editError(error){
    const message=String(error?.message||error||'');
    if(/PERMISSION_DENIED|FORBIDDEN/.test(message))return 'Non hai l’abilitazione Assistente IA e/o il permesso necessario su prodotti o lotti.';
    if(/ASSISTANT_EDIT_CONFLICT/.test(message))return 'Il record è cambiato. Nessuna modifica salvata: ripeti la richiesta per verificare i valori aggiornati.';
    if(/TARGET_NOT_UNIQUE|INVALID_LOT_ID/.test(message))return 'Prodotto o lotto non individuato in modo univoco. Indica il codice o numero esatto.';
    if(/AIRTABLE_DELIVERY_MANAGED/.test(message))return 'La consegna di questo lotto viene da Airtable: correggila nell’ordine collegato.';
    if(/CALENDAR_DATE_MANAGED/.test(message))return 'Correggi la data nell’appuntamento collegato al lotto.';
    if(/LOT_ARCHIVED/.test(message))return 'Il lotto è archiviato e non è modificabile dall’assistente.';
    if(/INVALID_|UNSUPPORTED_FIELD/.test(message))return 'Modifica non supportata o valore non valido. Usa la scheda del prodotto o del lotto.';
    return 'Operazione non completata. '+message;
  }
  async function previewEdit(plan,target){
    const id=generation;
    if(!userCan('assistant_edit')){target.textContent='Il tuo utente non è abilitato alle modifiche tramite assistente.';return}
    target.textContent='Verifica del record e dei permessi…';
    try{
      const {data,error}=await appSupabase.rpc('laundry_assistant_edit',{p_action:'preview',p:plan});
      if(!dialog.open||id!==generation||!allowed())return;
      if(error)throw error;
      target.replaceChildren();
      const heading=document.createElement('h3');heading.textContent=data.label;
      const field=document.createElement('p');field.textContent=editLabels[data.field]||data.field;
      const before=document.createElement('p');before.textContent='Valore attuale: '+(data.before??'Non indicato');
      const after=document.createElement('p');after.textContent='Nuovo valore: '+data.value;
      const status=document.createElement('p');status.setAttribute('role','status');
      target.append(heading,field,before,after,status);
      if(data.unchanged){status.textContent='Il valore è già quello richiesto. Nessuna modifica necessaria.';return}
      status.textContent='Controlla il valore: il salvataggio avviene soltanto dopo la tua conferma.';
      const confirm=document.createElement('button'),cancel=document.createElement('button');
      confirm.type=cancel.type='button';confirm.className='btn';cancel.className='btn secondary';
      confirm.textContent='Conferma modifica';cancel.textContent='Annulla';
      target.append(confirm,cancel);
      cancel.onclick=()=>{generation++;target.textContent='Modifica annullata. Nessun dato salvato.'};
      let saving=false;
      confirm.onclick=async()=>{
        if(saving||id!==generation||!allowed())return;
        saving=true;confirm.disabled=true;cancel.disabled=true;ask.disabled=true;
        status.textContent='Salvataggio…';
        try{
          const result=await appSupabase.rpc('laundry_assistant_edit',{p_action:'commit',p:{entity:data.entity,target:data.target,field:data.field,value:data.value,version:data.version,confirmed:true}});
          if(result.error)throw result.error;
          if(dialog.open&&id===generation){confirm.remove();cancel.remove();status.textContent=result.data.saved?'Modifica salvata.':'Il valore era già aggiornato.'}
        }catch(e){if(dialog.open&&id===generation){status.textContent=editError(e);confirm.remove();cancel.remove()}}
        finally{saving=false;if(id===generation)ask.disabled=false}
      };
    }catch(e){if(dialog.open&&id===generation)target.textContent=editError(e)}
  }
  const button=document.createElement('button');button.type='button';button.textContent='🤖';button.setAttribute('aria-label','Apri assistente Mycroclean');button.title='Chiedi al gestionale';
  button.style.cssText='position:fixed;right:12px;bottom:56px;z-index:20;border:1px solid #ccd7e4;border-radius:50%;background:white;height:44px;width:44px;font-size:23px;cursor:pointer';
  const dialog=document.createElement('dialog');dialog.style.cssText='width:min(92vw,500px);max-height:80vh;overflow:auto;padding:18px;border:1px solid #ccd7e4;border-radius:12px';
  dialog.innerHTML='<h2>Chiedi al gestionale</h2><p>Consulta i lotti oppure analizza guasti ricorrenti, fermi e manutenzioni delle macchine.</p><div data-examples></div><p data-quota aria-live="polite">Massimo 10 domande libere al giorno per utente abilitato.</p><label>Domanda<input type="text" maxlength="450" style="width:100%" placeholder="Quanti capi da riparare ha Marelli?"></label><small>La domanda viene interpretata da OpenAI. I conteggi restano nel gestionale; per analizzare manutenzioni, vengono inviate le relative note e i riepiloghi selezionati. Le modifiche richiedono abilitazione e conferma; nessun salvataggio automatico.</small><p><button class="btn" type="button" data-ask>Chiedi</button> <button class="btn secondary" type="button" data-close>Chiudi</button></p><div role="status"></div>';
  const target=dialog.querySelector('[role=status]'),input=dialog.querySelector('input'),ask=dialog.querySelector('[data-ask]');
  const quotaLabel=dialog.querySelector('[data-quota]');
  function showQuota(remaining){
    if(Number.isInteger(remaining))quotaLabel.textContent='Domande libere rimaste oggi: '+remaining+' su 10. Rinnovo a mezzanotte (Italia).';
  }
  async function refreshQuota(){
    const id=generation;
    const {data}=await appSupabase.functions.invoke('lot-question',{body:{statusOnly:true}});
    if(dialog.open&&id===generation&&allowed()&&data){
      showQuota(data.remaining);
      if(data.configured===false)quotaLabel.textContent+=' Lettura IA da configurare.';
    }
  }
  let generation=0;
  for(const [question,metric] of examples) {
    const example=document.createElement('button');example.type='button';example.className='link';example.textContent=question;
    example.onclick=()=>{if(!allowed())return;generation++;ask.disabled=false;input.value=question;answer({metric},target)};
    dialog.querySelector('[data-examples]').append(example);
  }
  ask.onclick=async()=>{
    if(!allowed()||!input.value.trim()||ask.disabled)return;
    const question=input.value.trim(),id=++generation;
    if(examples.has(question)){answer({metric:examples.get(question)},target);return}
    ask.disabled=true;target.textContent='Lettura della domanda…';
    try {
      const {data,error}=await appSupabase.functions.invoke('lot-question',{body:{question}});
      if(!dialog.open||id!==generation||!allowed())return;
      if(error){
        const detail=await error.context?.json?.().catch(()=>null);
        if(!dialog.open||id!==generation||!allowed())return;
        showQuota(detail?.remaining);
        if(detail?.error){target.textContent=detail.error;return}
        throw Error();
      }
      showQuota(data.remaining);
      answer(data,target);
    } catch {if(dialog.open&&id===generation)target.textContent='Domande libere al momento indisponibili. Puoi usare le domande qui sopra.'}
    finally {if(id===generation)ask.disabled=false}
  };
  input.onkeydown=e=>{if(e.key==='Enter')ask.click()};
  dialog.querySelector('[data-close]').onclick=()=>dialog.close();
  dialog.onclose=()=>{generation++;ask.disabled=false;target.replaceChildren();input.value=''};
  button.onclick=()=>{if(allowed()){dialog.showModal();quotaLabel.textContent='Massimo 10 domande libere al giorno per utente abilitato.';refreshQuota().catch(()=>{})}};
  function refresh(){button.hidden=!allowed();if(button.hidden&&dialog.open)dialog.close()}
  document.body.append(button,dialog);refresh();
  new MutationObserver(refresh).observe(document.querySelector('#app'),{childList:true});
  new MutationObserver(refresh).observe(document.body,{attributes:true,attributeFilter:['class']});
})();
