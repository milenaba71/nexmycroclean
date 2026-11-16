/* Ask about lot quantities. All operational records stay in the active session. */
(function () {
  const metrics = {all:'capi', entered:'capi entrati', fold:'capi pronti da piegare', repair:'capi da riparare', relabel:'capi da etichettare', verify:'capi da verificare', out:'capi usciti'};
  const examples = new Map([
    ['Lavoro svolto per utente', 'users'],
    ['Quanti capi ci sono nei lotti attivi?', 'all'],
    ['Quanti capi sono entrati?', 'entered'],
    ['Quanti capi sono ancora da piegare?', 'fold'],
    ['Quanti capi sono usciti?', 'out'],
    ['Quanti capi sono da riparare?', 'repair'],
    ['Quanti capi sono da etichettare?', 'relabel']
  ]);
  const allowed = () => typeof cloudUser !== 'undefined' && (cloudUser?.isSuperAdmin || cloudUser?.role === 'admin') && !document.body.classList.contains('floor-mode');
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
    if(plan.metric==='users'){userWork(target);return}
    target.replaceChildren();
    if (!Object.hasOwn(metrics,plan.metric)) {
      target.textContent='Posso contare i capi per lotto, cliente, reparto e intervento. Prova a indicare uno di questi criteri.';
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
  const button=document.createElement('button');button.type='button';button.textContent='🤖';button.setAttribute('aria-label','Apri assistente Mycroclean');button.title='Chiedi al gestionale';
  button.style.cssText='position:fixed;right:12px;bottom:56px;z-index:20;border:1px solid #ccd7e4;border-radius:50%;background:white;height:44px;width:44px;font-size:23px;cursor:pointer';
  const dialog=document.createElement('dialog');dialog.style.cssText='width:min(92vw,500px);max-height:80vh;overflow:auto;padding:18px;border:1px solid #ccd7e4;border-radius:12px';
  dialog.innerHTML='<h2>Chiedi al gestionale</h2><p>Consulta i capi dei lotti non archiviati per cliente, reparto o intervento.</p><div data-examples></div><label>Domanda<input type="text" maxlength="450" style="width:100%" placeholder="Quanti capi da riparare ha Marelli?"></label><small>La domanda libera viene interpretata da OpenAI. I conteggi vengono calcolati nel gestionale.</small><p><button class="btn" type="button" data-ask>Chiedi</button> <button class="btn secondary" type="button" data-close>Chiudi</button></p><div role="status"></div>';
  const target=dialog.querySelector('[role=status]'),input=dialog.querySelector('input'),ask=dialog.querySelector('[data-ask]');
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
      if(error)throw Error();
      answer(data,target);
    } catch {if(dialog.open&&id===generation)target.textContent='Domande libere al momento indisponibili. Puoi usare le domande qui sopra.'}
    finally {if(id===generation)ask.disabled=false}
  };
  input.onkeydown=e=>{if(e.key==='Enter')ask.click()};
  dialog.querySelector('[data-close]').onclick=()=>dialog.close();
  dialog.onclose=()=>{generation++;ask.disabled=false;target.replaceChildren();input.value=''};
  button.onclick=()=>{if(allowed())dialog.showModal()};
  function refresh(){button.hidden=!allowed();if(button.hidden&&dialog.open)dialog.close()}
  document.body.append(button,dialog);refresh();
  new MutationObserver(refresh).observe(document.querySelector('#app'),{childList:true});
  new MutationObserver(refresh).observe(document.body,{attributes:true,attributeFilter:['class']});
})();
