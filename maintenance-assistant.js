import './supabase/functions/lot-question/maintenance-core.js?v=20261126-maintenance';

/* Loaded only when the user opens maintenance in the assistant. */
window.openMaintenanceAssistant=async function(target,{active,showQuota,machine='',days=90}){
 let state,version=0,busy=false,filterNotice='';
 const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e};
 const button=(text,fn)=>{const b=el('button',text);b.type='button';b.className='btn secondary';b.onclick=fn;return b};
 const dt=v=>v?new Date(v).toLocaleString('it-IT',{timeZone:'Europe/Rome'}):'Non disponibile';
 const num=v=>Number(v).toLocaleString('it-IT',{maximumFractionDigits:1});
 const status={open:'Aperto',working:'In intervento',waiting:'Attesa ricambi',resolved:'Risolto da verificare',closed:'Risolto definitivamente'};
 target.textContent='Caricamento dello storico manutenzioni…';
 const controls=el('div'),result=el('div'),ai=el('div'),machineSelect=el('select'),period=el('select');
 machineSelect.setAttribute('aria-label','Macchina da analizzare');period.setAttribute('aria-label','Periodo manutenzione');
 for(const [v,label] of [[30,'Ultimi 30 giorni'],[90,'Ultimi 90 giorni'],[365,'Ultimi 365 giorni'],[0,'Tutto lo storico']]){const o=el('option',label);o.value=v;period.append(o)}period.value=String([0,30,90,365].includes(days)?days:90);
 function draw(){
  if(!active()||!state)return;version++;busy=false;analyze.disabled=false;ai.replaceChildren();result.replaceChildren();
  const r=MaintenanceCore.report(state,{days:Number(period.value),machineId:machineSelect.value});
  if(filterNotice)result.append(el('p',filterNotice));
  result.append(el('h3','Fermi e manutenzioni'),el('p','Dati aggiornati al '+dt(r.asOf)+'. '+(r.from?'Dal '+dt(r.from):'Tutto lo storico')+'.'),el('p',r.tickets.length+' segnalazioni considerate · '+num(r.minutes/60)+' ore di fermo documentate · '+r.recurrences.length+' gruppi ricorrenti.'));
  result.append(el('small','Ore solari, anche fuori turno; fermi sovrapposti sulla stessa macchina contati una volta. Archivi inclusi. Nessuna lettura automatica dei sensori.'));
  if(r.unknown)result.append(el('p','Storico parziale: '+r.unknown+' segnalazioni non permettono di ricostruire tutto il fermo. Le ore mostrate sono incomplete.'));
  if(r.excludedTests.length){const d=el('details');d.append(el('summary',r.excludedTests.length+' prove o possibili test esclusi'));for(const t of r.excludedTests)d.append(el('p',t.id+' · '+t.description));d.append(el('small','I vecchi ticket con “test” o “prova” nelle note sono esclusi in via prudenziale. Per includere un guasto reale, imposta Tipo segnalazione = Guasto reale nella sua scheda.'));result.append(d)}
  if(!r.tickets.length)result.append(el('p','Non ci sono segnalazioni operative nel periodo. Registra i guasti e gli interventi in Guasti e manutenzioni; lo storico si aggiornerà alle prossime consultazioni.'));
  for(const m of r.machines.filter(m=>m.tickets)){
   const section=el('section');section.style.cssText='border:1px solid #dce2ef;padding:12px;border-radius:10px;margin:12px 0';
   section.append(el('h4',m.name),el('p',m.newFaults+' nuove segnalazioni di guasto · '+m.planned+' manutenzioni programmate · '+m.reopens+' riaperture · '+num(m.minutes/60)+' ore di fermo'+(m.unknown?' (parziale)':'')),el('p',m.open+' ticket non chiusi definitivamente'+(m.blocking?' · Macchina segnalata ferma':'')));
   for(const g of r.recurrences.filter(g=>g.machineId===m.id))section.append(el('p','Ricorrenza: '+[g.component,g.errorCode].filter(Boolean).join(' · ')+' — '+g.occurrences+' aperture/riaperture. Ticket: '+g.ticketIds.join(', ')));
   const history=el('details');history.append(el('summary','Apri segnalazioni e interventi'));
   for(const t of r.tickets.filter(t=>t.machineId===m.id)){
    const d=el('details');d.append(el('summary',dt(t.createdAt)+' · '+(status[t.status]||t.status)+' · '+t.description),el('p','Ticket '+t.id));
    for(const [k,label] of [['component','Componente'],['errorCode','Errore'],['cause','Causa verificata'],['work','Intervento'],['parts','Ricambi'],['nextDate','Prossimo controllo']])if(t.maintenance?.[k])d.append(el('p',label+': '+t.maintenance[k]));
    for(const h of t.history)d.append(el('p',dt(h.at)+' · '+(status[h.status]||h.status)+' · '+h.note));history.append(d);
   }section.append(history);result.append(section);
  }
  result.append(el('small','Le ricorrenze numeriche raggruppano la stessa macchina, componente e codice errore. Descrizioni simili richiedono la valutazione IA e una verifica tecnica.'));
 }
 const analyze=button('Analizza ricorrenze con IA',async()=>{
  if(busy||!active())return;busy=true;analyze.disabled=true;const id=++version;
  ai.textContent='Analisi dello storico in corso…';
  try{
   const {data,error}=await appSupabase.functions.invoke('lot-question',{body:{maintenance:true,days:Number(period.value),machineId:machineSelect.value}});
   if(!active()||id!==version)return;
   if(error){const detail=await error.context?.json?.().catch(()=>null);if(!active()||id!==version)return;showQuota(detail?.remaining);throw Error(detail?.error||'Analisi non disponibile. Il riepilogo dello storico resta consultabile.')}
   showQuota(data.remaining);ai.replaceChildren();ai.append(el('h3','Valutazione IA'),el('p',data.summary));
   for(const f of data.findings||[]){const box=el('section');box.append(el('h4',f.title),el('p','Evidenze: '+f.evidence),el('p','Intervento proposto: '+f.recommendation),el('small','Ticket di riferimento: '+f.ticketIds.join(', ')));ai.append(box)}
   if(data.limitations)ai.append(el('p',data.limitations));
   ai.append(el('small','Analisi al '+dt(data.asOf)+'. Le proposte non modificano ticket, stato delle macchine o programmi di manutenzione.'));
  }catch(e){if(active()&&id===version)ai.textContent=e.message}
  finally{if(active()&&id===version){busy=false;analyze.disabled=false}}
 });
 async function load(){
  const id=++version;refresh.disabled=true;analyze.disabled=true;busy=true;ai.textContent='Aggiornamento…';
  try{
   const {data,error}=await appSupabase.rpc('laundry_maintenance_history');
   if(!active()||id!==version)return;if(error)throw error;
   const chosen=machineSelect.value;state=data;machineSelect.replaceChildren();const all=el('option','Tutte le macchine');all.value='';machineSelect.append(all);
   for(const m of state.machines){const o=el('option',m.name);o.value=m.id;machineSelect.append(o)}
   machineSelect.value=state.machines.some(m=>m.id===chosen)?chosen:'';
   if(machine){const matches=state.machines.filter(m=>m.name.toLowerCase().includes(machine.toLowerCase())||m.id===machine);if(matches.length===1)machineSelect.value=matches[0].id;else filterNotice='Il nome macchina nella domanda non è univoco o non è presente: seleziona la macchina dal menu. Per ora sono mostrate tutte.';machine=''}
   target.replaceChildren(controls,result,analyze,el('p','L’analisi invia a OpenAI solo dati di guasti e manutenzioni selezionati, incluse le note pertinenti. Consuma una delle 10 domande giornaliere. I riepiloghi non consumano domande.'),ai);draw();
  }catch(e){if(active()&&id===version){ai.textContent='Impossibile leggere lo storico. Verifica accesso e connessione, poi premi Aggiorna.';target.replaceChildren(controls,ai)}}
  finally{if(active())refresh.disabled=false}
 }
 const refresh=button('Aggiorna storico',load);
 controls.append(el('p','Macchina'),machineSelect,el('p','Periodo'),period,refresh);
 machineSelect.style.width=period.style.width='100%';machineSelect.onchange=()=>{filterNotice='';draw()};period.onchange=draw;
 await load();
};
