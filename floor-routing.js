/* Shared delivery ordering and folding destinations. No product data is changed. */
function lotDeliveryKey(lot){
 const planned=(prod?.calendars||[]).filter(c=>!c.cancelled&&c.lotId!=null&&String(c.lotId)===String(lot?.id)&&c.due).map(c=>c.due).sort()[0];
 const due=lot?.due||planned;
 return !due?'9999':planned&&due.length===10&&planned.slice(0,10)===due?planned:due;
}
function lotDeliveryOrder(a,b){return lotDeliveryKey(a).localeCompare(lotDeliveryKey(b))||Number(a?.id||0)-Number(b?.id||0)}
function cartDeliveryKey(cart){
 const members=cart.lotId!=null?[{lot_id:cart.lotId}]:typeof washLoadMembers==='function'?washLoadMembers(cart):[cart];
 return members.map(m=>lotDeliveryKey(db.lots.find(l=>String(l.id)===String(m.lot_id)))).sort()[0]||'9999';
}
function cartDeliveryOrder(a,b){return cartDeliveryKey(a).localeCompare(cartDeliveryKey(b))||String(a.id||a.batchId||'').localeCompare(String(b.id||b.batchId||''))}
function taskDeliveryKey(task){const lots=(task.items||[]).map(i=>db.lots.find(l=>String(l.id)===String(i.lotId))).filter(Boolean);return lots.length?lots.map(lotDeliveryKey).sort()[0]:task.due||'9999'}
function foldingDepartment(row,state){
 const batch=(state?.batches||[]).find(b=>b.id===row.washBatchId);
 let kind=batch?.machine_kind;
 if(!kind){const kinds=[...new Set((state?.links||[]).filter(l=>l.processing_id===row.processingId).map(l=>(state.types||[]).find(t=>t.id===l.program_id)?.machineKind).filter(Boolean))];if(kinds.length===1)kind=kinds[0];}
 if(kind==='water')return 'water';
 if(kind==='decon'||kind==='dry')return 'clean';
 const name=String(row.processingName||'').toLowerCase();
 if(/decontamin|clean room|secco/.test(name))return 'clean';
 if(/acqua/.test(name)||row.requiresDrying)return 'water';
 return 'unknown';
}
