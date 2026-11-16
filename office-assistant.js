/* Ask about lot quantities. All operational records stay in the active session. */
(function () {
  const metrics = {all:'capi', repair:'capi da riparare', relabel:'capi da etichettare', verify:'capi da verificare', out:'capi usciti'};
  const examples = new Map([
    ['Quanti capi ci sono nei lotti attivi?', 'all'],
    ['Quanti capi sono da riparare?', 'repair'],
    ['Quanti capi sono da etichettare?', 'relabel']
  ]);
  const allowed = () => typeof cloudUser !== 'undefined' && (cloudUser?.isSuperAdmin || cloudUser?.role === 'admin') && !document.body.classList.contains('floor-mode');
  const fold = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  function answer(plan, target) {
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
      const count=lot.rows.filter(row=>plan.metric==='all'||(plan.metric==='out'?row.state==='Uscito':row.state!=='Uscito'&&row[plan.metric]===true)).length;
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
    } catch {if(dialog.open&&id===generation)target.textContent='Domande libere al momento indisponibili. Puoi usare le tre domande qui sopra.'}
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
