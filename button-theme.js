/* Mark only selection, label and deletion actions; leave navigation unchanged. */
(function(){
 const selector='button,input[type="button"],input[type="submit"],input[type="reset"],a.btn,a[role="button"]';
 function mark(el){
  if(el.closest('aside,nav')||el.classList.contains('step')||el.getAttribute('role')==='tab'){el.classList.remove('action-operational','action-destructive');return;}
  const label=[el.textContent,el.value,el.getAttribute('aria-label'),el.getAttribute('title')].filter(Boolean).join(' ');
  const action=[el.id,el.getAttribute('onclick'),...Array.from(el.attributes).filter(a=>a.name.startsWith('data-')).map(a=>a.name+' '+a.value)].filter(Boolean).join(' ');
  const formAction=el.tagName==='BUTTON'&&(!el.type||el.type==='submit')||el.type==='submit'?el.form?.getAttribute('onsubmit')||'':'';
  const destructive=/\b(elimina\w*|cancella\w*|rimuovi)\b/i.test(label)||/delete|remove/i.test(action+' '+formAction);
  const operational=/\b(seleziona\w*|deseleziona\w*|selezionati|selezionate)\b/i.test(label)||/\b(crea|stampa|genera|anteprima)\b.*\betichett/i.test(label);
  el.classList.toggle('action-operational',operational&&!destructive);
  el.classList.toggle('action-destructive',destructive);
 }
 function scan(root){if(root.nodeType!==1&&root.nodeType!==9)return;if(root.matches?.(selector))mark(root);root.querySelectorAll(selector).forEach(mark)}
 scan(document);
 new MutationObserver(records=>{const roots=new Set();for(const r of records){if(r.type==='characterData'){const button=r.target.parentElement?.closest(selector);if(button)mark(button)}else{const parent=r.target.closest?.(selector);if(parent)mark(parent);r.addedNodes.forEach(n=>{if(n.nodeType===1)roots.add(n)})}}roots.forEach(scan)}).observe(document.documentElement,{childList:true,subtree:true,characterData:true});
})();
