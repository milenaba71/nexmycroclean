/* The same department image follows its label across floor and planning views. */
(function(){
const assets={water:'assets/reparto-piegatura-acqua.png',decon:'assets/reparto-lavaggio.png'};
function kind(text){if(/\bacqua\b/i.test(text))return 'water';if(/\bdec\b|\bdecontaminazione\b/i.test(text))return 'decon';return null}
function decorate(){for(const el of document.querySelectorAll('#app h1,#app h2,#app .phase-label,#app .floor-tabs button,#app .floor-person>span')){
 const key=kind(el.textContent),existing=el.querySelector('[data-department-symbol]');
 if(!key){existing?.remove();continue}
 // A department card may already carry the full-size supplied image.
 const card=el.closest('.floor-fold-department,.floor-home-card,.floor-wash-department');
 if(card&&card.querySelector(':scope > .floor-department-icon')){existing?.remove();continue}
 if(existing){if(existing.getAttribute('src')!==assets[key])existing.setAttribute('src',assets[key]);continue}
 const img=document.createElement('img');img.src=assets[key];img.alt='';img.width=36;img.height=36;img.className='department-symbol';img.dataset.departmentSymbol=key;el.prepend(img);
}}
const style=document.createElement('style');style.textContent='.department-symbol{width:36px;height:36px;object-fit:contain;vertical-align:middle;margin-right:9px;background:white;border-radius:6px;flex:none}.floor-wash-department h2 .department-symbol{display:block;width:100px;height:100px;margin:0 0 12px}.phase-label .department-symbol{width:28px;height:28px}';document.head.append(style);
let queued=false;new MutationObserver(()=>{if(queued)return;queued=true;queueMicrotask(()=>{queued=false;decorate()})}).observe(document.querySelector('#app'),{childList:true,subtree:true});decorate();
})();
