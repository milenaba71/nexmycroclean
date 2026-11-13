/* Lot-level entry notes beside the existing scanner; preserve live scan handlers. */
(function(){
 const N=window.LotEntryNotes={drafts:new Map(),saving:false};
 const $id=id=>document.getElementById(id);
 function draft(lot){const key=String(lot.id);if(!N.drafts.has(key))N.drafts.set(key,{base:lot.notes||'',text:lot.notes||'',dirty:false,status:''});return N.drafts.get(key)}
 function text(el,value){if(el&&el.textContent!==value)el.textContent=value}
 N.mount=function(){
  if(N.owner!==cloudUser?.email){N.drafts.clear();N.owner=cloudUser?.email}
  if(!current||stage!=='Entrata')return;
  const scan=$id('scan'),row=scan?.closest('.scan');if(!row)return;
  const d=draft(current),key=String(current.id);let grid=row.closest('.entry-scan-notes');
  if(!grid){grid=document.createElement('div');grid.className='entry-scan-notes';row.before(grid);grid.append(row);const aside=document.createElement('section');aside.className='entry-lot-note';aside.innerHTML='<label for="entryLotNotes">Note del lotto</label><textarea id="entryLotNotes" rows="5" maxlength="4000" placeholder="Scrivi qui le note e le istruzioni per questo lotto…"></textarea><div class="entry-note-actions"><button type="button" class="btn" id="entryNotesSave">Salva note</button><button type="button" class="btn secondary" id="entryNotesReset">Annulla modifiche</button><span id="entryNotesStatus" role="status" aria-live="polite"></span></div>';grid.append(aside);
   $id('entryLotNotes').oninput=()=>{const value=draft(current);value.text=$id('entryLotNotes').value;value.dirty=value.text!==value.base;value.status=value.dirty?'Note da salvare':'';N.mount()};
   $id('entryNotesSave').onclick=N.save;$id('entryNotesReset').onclick=N.reset;
  }
  if(!d.dirty&&!N.saving){d.base=current.notes||'';d.text=d.base}
  const area=$id('entryLotNotes');if(area.value!==d.text)area.value=d.text;
  grid.dataset.lotId=key;
  const allowed=userCan('lots_work')&&!current.archived;
  area.disabled=N.saving||!allowed;
  $id('entryNotesSave').disabled=N.saving||!allowed||!d.dirty;
  $id('entryNotesReset').disabled=N.saving||!d.dirty;
  text($id('entryNotesStatus'),N.saving?'Salvataggio…':d.status||(!allowed?'Sola lettura':d.base?'Note salvate':''));
 };
 N.reset=function(){if(!current||N.saving)return;N.drafts.delete(String(current.id));N.mount()};
 N.save=async function(){
  if(N.saving||!current||!userCan('lots_work')||current.archived)return;
  if(lotBusy()||washBusy||dryBusy||prodBusy)return notify('Attendi il completamento dell’operazione in corso, poi salva le note.');
  const id=current.id,d=draft(current),value=d.text;if(!d.dirty)return;
  N.saving=true;lotActionBusy=true;N.mount();
  try{
   await cloudFlush();
   const snapshot=await cloudRequest(),lot=snapshot.db.lots.find(l=>l.id===id);
   if(!lot||lot.archived)throw Error('Il lotto non è più modificabile.');
   if((lot.notes||'')!==d.base){cloudAccept(snapshot,false);throw Error('Note aggiornate da un’altra postazione. Il tuo testo è conservato: copialo oppure premi Annulla modifiche per leggere le note aggiornate.')}
   const updated={...lot,notes:value,events:[...(lot.events||[]),{at:new Date().toISOString(),time:new Date().toLocaleString('it-IT'),action:'Note del lotto aggiornate',code:'',actor:cloudUser.name||cloudUser.email,actorEmail:cloudUser.email}]};
   const result=await cloudRequest('save',{revision:snapshot.revision,changes:{lots:[updated]}});
   cloudAccept({...snapshot,revision:result.revision,db:{...snapshot.db,lots:snapshot.db.lots.map(l=>l.id===id?updated:l)}},false);
   d.base=value;d.text=value;d.dirty=false;d.status='Note salvate';
  }catch(e){d.status='Non salvate: '+e.message;notify(e.message)}
  finally{N.saving=false;lotActionBusy=false;N.mount()}
 };
 let scheduled=false;
 const observer=new MutationObserver(()=>{if(scheduled)return;scheduled=true;queueMicrotask(()=>{scheduled=false;N.mount()})});
 const app=$id('app');if(app)observer.observe(app,{childList:true,subtree:true});
 window.addEventListener('beforeunload',e=>{if([...N.drafts.values()].some(d=>d.dirty)){e.preventDefault();e.returnValue=''}});
 N.mount();
})();
