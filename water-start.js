/* Compact water start: select a cart by lot identity, never render garment rows. */
(function(){
 const W=window.WaterStart={};
 W.rows=()=>washDistinctLoads((washState?.batches||[]).filter(b=>b.machine_kind==='water'&&['gathering','ready','blocked'].includes(b.state)&&Number(b.quantity)>0&&washCanOperate(b)));
 W.label=b=>washLoadMembers(b).map(washLotLabel).join(' / ')+' · '+b.program_name;
 W.summary=b=>'<div class="water-start-summary">'+washLoadMembers(b).map(x=>{const l=db.lots.find(l=>String(l.id)===String(x.lot_id));return '<div><strong>'+esc(l?lotno(l):'Lotto '+x.lot_id)+'</strong><div>Cliente: '+esc(l?.client||'Cliente non disponibile')+'</div><div>Reparto: '+esc(l?.departmentName||'Reparto non indicato')+'</div></div>'}).join('')+'</div>';
 W.open=function(id){
  if(!userCan('production_execute'))return notify('Avvio riservato agli operatori autorizzati.');
  const rows=W.rows(),b=rows.find(b=>b.id===id)||rows[0];
  if(!b)return show('<h2>Avvia macchina</h2><p>Nessun carrello ad acqua da avviare.</p><button class="btn secondary" onclick="document.querySelector(\'#modal\').close()">Chiudi</button>');
  washStartDialog(b.id);
  const heading=document.querySelector('#modal h2');if(!heading)return;
  const label=document.createElement('label');label.style.cssText='display:grid;gap:8px;margin:12px 0';label.textContent='Lotto · cliente · reparto · tipo di lavaggio';
  const select=document.createElement('select');select.id='waterStartCart';
  rows.forEach(r=>{const option=document.createElement('option');option.value=r.id;option.textContent=W.label(r);option.selected=r.id===b.id;select.append(option)});
  select.onchange=()=>W.open(select.value);label.append(select);heading.after(label);
 };
})();