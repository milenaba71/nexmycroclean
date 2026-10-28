/* Stop the scan queue until the operator acknowledges a wrong customer/lot. */
function lotMismatchInfo(code,lot=current,phase=stage){
 if(!lot)return null;
 const id=resolveBarcode(code),g=db.garments.find(g=>g.id===id),row=lot.rows.find(r=>r.code===id);
 const others=db.lots.filter(l=>l.id!==lot.id&&(l.rows||[]).some(r=>r.code===id&&r.state!=='Uscito'));
 const same=(a,b)=>String(a||'').trim().toLocaleLowerCase('it')===String(b||'').trim().toLocaleLowerCase('it');
 if(g&&!same(g.client,lot.client))return {title:'QUESTO PRODOTTO È DI UN’ALTRA AZIENDA',g,lot,others,reason:'Il prodotto non appartiene all’azienda del lotto selezionato.'};
 if(others.length)return {title:'QUESTO PRODOTTO APPARTIENE A UN ALTRO LOTTO',g,lot,others,reason:'Il prodotto risulta ancora in un altro lotto non completato.'};
 if(phase!=='Entrata'&&!row)return {title:'QUESTO PRODOTTO NON È NEL LOTTO',g,lot,others,reason:'Non puoi registrare lavorazione o uscita: il prodotto non è presente in questo lotto.'};
 return null;
}
function showLotMismatch(code,info){return new Promise(resolve=>{
 const modal=$('#modal'),lot=info.lot||current,g=info.g;
 show(`<section class="lot-mismatch" role="alert"><div class="lot-mismatch-symbol" aria-hidden="true">⚠</div><h2 id="lotMismatchTitle" tabindex="-1">ATTENZIONE<br>${esc(info.title)}</h2><p class="lot-mismatch-code">Barcode: <strong>${esc(productBarcode(g)||code)}</strong></p><p>${esc(info.reason)}</p><dl><dt>Lotto che stai utilizzando</dt><dd>${esc(lot?lotno(lot):'—')} · ${esc(lot?.client||'—')}</dd><dt>Azienda del prodotto</dt><dd>${esc(g?.client||'Non disponibile')}</dd>${info.others?.length?'<dt>Lotto di appartenenza ancora aperto</dt><dd>'+info.others.map(l=>esc(lotno(l))+' · '+esc(l.client)).join('<br>')+'</dd>':''}</dl><p class="lot-mismatch-blocked">REGISTRAZIONE BLOCCATA<br><small>Il prodotto non è stato registrato in questo passaggio.</small></p><button type="button" class="btn" id="lotMismatchAcknowledge">Ho capito · continua scansioni</button></section>`);
 modal.style.maxWidth='820px';
 let done=false;const finish=()=>{if(done)return;done=true;modal.removeEventListener('close',onClose);modal.close();resolve();};
 const onClose=()=>{if(!modal.open)finish();};modal.addEventListener('close',onClose);$('#lotMismatchAcknowledge').onclick=finish;$('#lotMismatchTitle').focus();
});}
const checkedBeforeLotMismatch=checkedProcess;
checkedProcess=async function(code){
 const lotId=current?.id,phase=stage;
 try{await cloudFlush();cloudAccept(await cloudRequest(),false);}catch(e){return e.message;}
 if(current?.id!==lotId||stage!==phase)return 'Schermata cambiata: scansione non registrata.';
 let info=lotMismatchInfo(code);
 if(info){await showLotMismatch(code,info);return info.reason;}
 let error=await checkedBeforeLotMismatch(code);
 if(error&&/LOT_PRODUCT_CLIENT_MISMATCH|PRODUCT_ALREADY_IN_OPEN_LOT|PRODUCT_NOT_IN_LOT|altro cliente|altro lotto|non presente nel lotto|non è presente nel lotto/i.test(error)){
  // Also surface authoritative server rejections if another station changed the data.
  try{cloudAccept(await cloudRequest(),false);}catch{}
  info=lotMismatchInfo(code)||{title:'PRODOTTO NON COMPATIBILE CON QUESTO LOTTO',lot:current,reason:error,others:[],g:db.garments.find(g=>g.id===resolveBarcode(code))};
  await showLotMismatch(code,info);
 }
 return error;
};
const lotMismatchStyle=document.createElement('style');lotMismatchStyle.textContent='.lot-mismatch{border:3px solid #b92335;border-radius:16px;padding:clamp(14px,3vw,28px);background:#fff5f5;color:#6d1925;overflow-wrap:anywhere}.lot-mismatch-symbol{font-size:46px;line-height:1}.lot-mismatch h2{font-size:clamp(21px,3vw,30px);color:#ae162a;line-height:1.25;margin:14px 0}.lot-mismatch-code{font-size:21px}.lot-mismatch dl{background:white;padding:16px;border-radius:10px}.lot-mismatch dt{font-size:13px;margin-top:12px}.lot-mismatch dd{font-size:19px;font-weight:700;margin:4px 0}.lot-mismatch-blocked{font-size:19px;font-weight:800}.lot-mismatch-blocked small{font-size:14px;font-weight:400}.lot-mismatch .btn{width:100%;white-space:normal;background:#b92335}';document.head.appendChild(lotMismatchStyle);
