/* Compact office presentation. Move live controls without replacing listeners or data. */
(function(){
 function arrange(){
  if(!current||document.body.classList.contains('floor-mode'))return;
  const app=document.getElementById('app'),panel=app.querySelector('.lot-workspace'),heading=app.querySelector('.heading');
  if(!panel||!heading)return;
  panel.classList.add('office-detail-workspace');heading.classList.add('office-detail-heading');
  let identity=heading.querySelector('h1')?.parentElement;
  if(identity&&!identity.querySelector('.office-detail-department')){let p=document.createElement('p');p.className='office-detail-department';p.textContent=current.departmentName||'Reparto non indicato';identity.append(p)}
  for(const notice of app.querySelectorAll(':scope > .notice'))if(/^Reparto:/.test(notice.textContent.trim()))notice.hidden=true;
  let menu=heading.querySelector('.office-detail-menu');
  if(!menu){menu=document.createElement('details');menu.className='office-detail-menu';menu.innerHTML='<summary>Gestione e report</summary><div></div>';heading.append(menu)}
  const destination=menu.querySelector('div');
  for(const button of [...heading.querySelectorAll('button')]){
   if(menu.contains(button))continue;
   const action=button.getAttribute('onclick')||'';
   if(/lotClose\(|lotAddProducts\(/.test(action))continue;
   destination.append(button);
  }
  let line=panel.querySelector(':scope > .office-entry-line');
  if(!line){line=document.createElement('div');line.className='office-entry-line';panel.querySelector('.steps')?.after(line)}
  const scan=panel.querySelector('#scan')?.closest('.lot-work-section'),treatment=panel.querySelector('#entryProcessing')?.closest('.lot-work-section');
  if(treatment&&treatment!==scan&&treatment.parentElement!==line)line.append(treatment);
  if(scan&&scan.parentElement!==line)line.append(scan);
  line.classList.toggle('office-scan-only',!treatment||treatment===scan);
  if(scan){scan.classList.add('office-scan-section');const input=scan.querySelector('#scan');input?.setAttribute('placeholder','Scansiona oppure digita e premi Invio');}
  if(treatment)treatment.classList.add('office-treatment-section');
  const carts=panel.querySelector('#washCarts');
  if(carts){
   if(carts.previousElementSibling!==line)line.after(carts);
   let help=carts.querySelector(':scope > .office-cart-help');
   const paragraphs=[...carts.querySelectorAll(':scope > p.muted')];
   if(paragraphs.length&&!help){help=document.createElement('details');help.className='office-cart-help';help.innerHTML='<summary>Come funzionano carrelli e tempi</summary>';carts.append(help);paragraphs.forEach(p=>help.append(p))}
   for(const card of carts.querySelectorAll('.wash-cart')){
    if(card.querySelector('.office-cart-actions'))continue;
    const secondary=[...card.querySelectorAll('button')].filter(b=>!/washQuickStart\(|washStartDialog\(|washInterrupt\(/.test(b.getAttribute('onclick')||''));
    if(secondary.length){let fold=document.createElement('details');fold.className='office-cart-actions';fold.innerHTML='<summary>Altre azioni</summary>';card.append(fold);secondary.forEach(b=>fold.append(b))}
   }
  }
  const filters=panel.querySelector('.mobile-filter-fold');if(filters&&!filters.dataset.officeCompact){filters.dataset.officeCompact='true';filters.open=false;filters.querySelector('summary').textContent='Altri filtri · stato, note e segnalazioni'}
  const pageTools=app.querySelector('#pageTools');
  if(pageTools&&!pageTools.closest('.office-detail-exports')){let fold=document.createElement('details');fold.className='office-detail-exports';fold.innerHTML='<summary>Esporta dati della scheda</summary>';panel.after(fold);fold.append(pageTools)}
 }
 const previous=detail;detail=function(...args){const result=previous.apply(this,args);arrange();return result};
 let queued=false;new MutationObserver(()=>{if(queued)return;queued=true;queueMicrotask(()=>{queued=false;arrange()})}).observe(document.getElementById('app'),{childList:true,subtree:true});
 arrange();
})();
