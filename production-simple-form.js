/* Keep planning selections separate from recorded execution states. */
(function(){
 const original=pEditTask;
 const labels={pending:'Da eseguire',running:'In corso',paused:'In pausa',completed:'Completata',cancelled:'Annullata'};
 const style=document.createElement('style');
 style.textContent=`#productionForm .planning-summary,#productionForm .planning-settings{border:1px solid #dce2ef;border-radius:14px;padding:16px;min-width:0}#productionForm .planning-settings summary{cursor:pointer;font-weight:700;color:#293f78}#productionForm .planning-settings .prod-check{display:flex;flex-direction:row;align-items:center;gap:10px;margin:6px 0;padding:10px;width:100%;box-sizing:border-box;text-align:left;overflow-wrap:anywhere}#productionForm .planning-settings input[type=checkbox]{width:22px;height:22px;min-width:22px;margin:0;flex:0 0 22px}#productionForm .planning-settings fieldset{min-width:0;margin:12px 0}#productionForm .planning-state-row{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:10px 0;border-bottom:1px solid #edf0f5;overflow-wrap:anywhere}#productionForm .planning-state{padding:5px 9px;border-radius:8px;background:#edf0f5;white-space:nowrap;font-size:.9em}#productionForm .planning-state[data-state=completed]{background:#e5f4e9;color:#28603a}#productionForm .planning-state[data-state=running]{background:#e8efff;color:#244c9b}#productionForm .planning-help{font-size:.9em;color:#59677f;line-height:1.5}#productionForm .planning-summary h3{margin:0 0 10px}@media(max-width:600px){#productionForm .planning-state-row{align-items:flex-start;flex-direction:column;gap:6px}}`;
 document.head.append(style);
 pEditTask=function(id){
  original(id);
  const form=document.getElementById('productionForm');if(!form)return;
  const task=prod.tasks.find(t=>t.id===id);
  const lots=form.querySelector('#prodTaskLots')?.closest('label');
  const items=form.querySelector('#prodTaskItems');
  const dependencies=form.querySelector('input[name=dependsOn]')?.closest('fieldset')||[...form.querySelectorAll('fieldset')].find(f=>f.querySelector('legend')?.textContent==='Attività da completare prima');
  if(!lots||!items||!dependencies)return;
  const overview=document.createElement('section');overview.className='wide planning-summary';overview.setAttribute('aria-label','Stato registrato delle attività');
  form.insertBefore(overview,lots);
  const settings=document.createElement('details');settings.className='wide planning-settings';settings.open=!id;
  settings.innerHTML='<summary>Modifica collegamenti · prodotti e fasi precedenti</summary><p class="planning-help">Queste caselle scelgono quali prodotti includere e quali attività attendere. Non completano le lavorazioni e non si spuntano automaticamente.</p>';
  form.insertBefore(settings,lots);settings.append(lots,items,dependencies);
  dependencies.querySelector('legend').textContent='Scegli le attività da attendere';
  function refresh(){
   const selected=[...form.querySelectorAll('input[name=dependsOn]:checked')].map(i=>prod.tasks.find(t=>t.id===i.value)).filter(Boolean);
   const count=form.querySelectorAll('input[name=items]:checked').length;
   const status=task?.status||'pending';
   overview.innerHTML=`<h3>Riepilogo attività</h3><div class="planning-state-row"><strong>Stato registrato</strong><span class="planning-state" data-state="${esc(status)}">${esc(labels[status]||status)}</span></div><p>${count?count+(count===1?' prodotto selezionato':' prodotti selezionati'):'Previsione senza prodotti selezionati'}</p><strong>Fasi da attendere</strong>${selected.length?selected.map(t=>`<div class="planning-state-row"><span>${esc(pTaskName(t))}</span><span class="planning-state" data-state="${esc(t.status||'pending')}">${esc(labels[t.status]||'Da eseguire')}</span></div>`).join(''):'<p>Nessuna fase precedente collegata.</p>'}<p class="planning-help">Gli stati mostrano quanto registrato nel gestionale all’apertura della scheda. Per eseguire il lavoro usa le azioni dell’attività: qui modifichi soltanto la pianificazione.</p>`;
  }
  form.addEventListener('change',refresh);refresh();
 };
})();
