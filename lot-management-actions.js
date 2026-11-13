/* Make the existing archive/delete workflows visible in office and department. */
(function(){
 const A=window.LotManagement={};
 A.mount=function(){
  const app=document.getElementById('app');if(!app)return;
  if(!current){document.getElementById('lotManagementActions')?.remove();
   for(const fold of app.querySelectorAll('.office-more')){
    const cell=fold.parentElement;
    for(const b of [...fold.querySelectorAll('button')]){
     const action=b.getAttribute('onclick')||'';
     if(/archiveLot\(|planningDeleteDialog\('delete_lot'/.test(action))cell.insertBefore(b,fold);
    }
   }
   return;
  }
  const anchor=document.body.classList.contains('floor-mode')?document.getElementById('floorLotHeader'):app.querySelector('.heading');if(!anchor)return;
  let bar=document.getElementById('lotManagementActions');
  if(!bar){bar=document.createElement('div');bar.id='lotManagementActions';bar.className='tools';bar.style.cssText='display:flex;flex-wrap:wrap;gap:10px;margin:0 0 14px;padding:0';anchor.after(bar)}
  if(anchor.nextElementSibling!==bar)anchor.after(bar);
  const canArchive=userCan('lots_work'),canDelete=cloudUser?.role==='admin'&&userCan('planning_delete');
  const signature=[current.id,!!current.archived,canArchive,canDelete].join('|');if(bar.dataset.signature===signature)return;bar.dataset.signature=signature;bar.replaceChildren();
  const id=current.id;
  function add(label,action,danger){const b=document.createElement('button');b.type='button';b.className='btn';b.textContent=label;b.style.background=danger?'#c8232c':'#193c66';b.style.color='white';b.onclick=()=>{if(lotBusy()||washBusy||dryBusy||prodBusy)return notify('Attendi la registrazione in corso.');action()};bar.append(b)}
  if(canArchive)add(current.archived?'Ripristina lotto':'Archivia lotto',()=>current.archived?restoreArchivedLot(id):archiveLot(id),false);
  if(canDelete)add('Elimina lotto',()=>planningDeleteDialog('delete_lot',id),true);
 };
 const previous=render;render=function(...args){
  if(window.floor?.active&&floor.screen==='lot'&&!current){floor.screen='lots';floor.draw();return}
  return previous.apply(this,args);
 };
 let queued=false;new MutationObserver(()=>{if(!queued){queued=true;queueMicrotask(()=>{queued=false;A.mount()})}}).observe(document.getElementById('app'),{childList:true,subtree:true});A.mount();
})();
