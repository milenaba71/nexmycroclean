/* Repair execution waits for the associated wash cycle. */
function repairWashMessage(id,code){
 const row=db.lots.find(l=>l.id===id)?.rows.find(r=>r.code===code);if(!row)return '';
 const batch=washState?.batches.find(b=>b.id===row.washBatchId);
 if(batch){if(!['running','blocked'].includes(batch.state))return '';return `In lavaggio · ${batch.machine_name}${batch.state==='blocked'?' · Ciclo interrotto':''}`;}
 if(row.state==='In lavaggio'||['running','blocked'].includes(row.washBatchState))return 'In lavaggio · Caricamento del nome macchina…';
 return '';
}
function repairWashDecorate(){
 if(page!=='Riparazioni'||repairLotId===null)return;
 document.querySelectorAll('[data-repair-wash-message]').forEach(e=>e.remove());
 for(const b of document.querySelectorAll('#app button[onclick]')){
  const action=b.getAttribute('onclick'),m=action.match(/(?:repairProductDetail|registerRepairWork)\((\d+),decodeURIComponent\('([^']*)'\)/);if(!m)continue;
  const message=repairWashMessage(Number(m[1]),decodeURIComponent(m[2]));
  const container=b.closest('.repair-card')||b.closest('.panel');
  if(message){if(action.startsWith('registerRepairWork')){if(!b.dataset.washLocked)b.dataset.washWasDisabled=String(b.disabled);b.dataset.washLocked='true';b.disabled=true;}
   if(container&&!container.querySelector('[data-repair-wash-message]')){const p=document.createElement('p');p.dataset.repairWashMessage='true';p.className='notice';p.setAttribute('role','status');p.textContent=message+' · Riparazione bloccata fino al termine del lavaggio.';container.append(p);}
  }else if(b.dataset.washLocked){b.disabled=b.dataset.washWasDisabled==='true';delete b.dataset.washLocked;delete b.dataset.washWasDisabled;}
 }
}
let repairWashRefreshing=false;
async function repairWashRefresh(){if(repairWashRefreshing||page!=='Riparazioni'||!cloudUser)return;repairWashRefreshing=true;try{await washRpc('read',{lotId:repairLotId});repairWashDecorate()}catch(e){notify('Stato lavaggio non aggiornato. '+washMessage(e))}finally{repairWashRefreshing=false}}
const repairLotBeforeWashLock=repairDetail;repairDetail=function(...args){repairLotBeforeWashLock(...args);repairWashDecorate();void repairWashRefresh()};
const repairProductBeforeWashLock=repairProductDetail;repairProductDetail=function(...args){repairProductBeforeWashLock(...args);repairWashDecorate();void repairWashRefresh()};
const registerBeforeWashLock=registerRepairWork;registerRepairWork=function(id,code,...args){const m=repairWashMessage(id,code);if(m)return notify(m);return registerBeforeWashLock(id,code,...args)};
const saveBeforeWashLock=saveRepairWork;saveRepairWork=function(e,id,code,...args){const m=repairWashMessage(id,code);if(m){e.preventDefault();return notify(m)}return saveBeforeWashLock(e,id,code,...args)};
const finishBeforeWashLock=finishWithoutRepairCost;finishWithoutRepairCost=function(id,code,...args){const m=repairWashMessage(id,code);if(m)return notify(m);return finishBeforeWashLock(id,code,...args)};
setInterval(()=>{if(page==='Riparazioni'&&!document.hidden&&!$('#modal').open)void repairWashRefresh()},15000);
