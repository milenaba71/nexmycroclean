function productIsDiscard(g){return !!g&&(yes(g.raw?.SCARTO)||Number(g.wash)>=Number(g.max))}
function lotDiscardCell(g,row){let discard=row.discardForReturn||row.discard||productIsDiscard(g);return `<td>${discard?'<span role="img" aria-label="Scarto" title="Scarto: segnalato nel lotto, nella scheda prodotto o per limite lavaggi raggiunto" style="display:inline-flex;align-items:center;gap:7px;color:#b91343;font-weight:700"><span style="width:13px;height:13px;border-radius:50%;background:#e52242;display:inline-block"></span>Scarto</span>':'<span class="muted">—</span>'}</td>`}

function normalizeDiscardFlags(){for(let g of db.garments){if(Number(g.wash)>=Number(g.max)){g.raw={...g.raw,SCARTO:'SI'}}}}
const saveBeforeDiscardFlag=save;save=function(){normalizeDiscardFlags();return saveBeforeDiscardFlag()};

// A customer-owned garment is returned physically, without retiring its tag.
const customerDiscardNote='SCARTO · Da restituire al cliente';
function setCustomerDiscardReturn(row,garment,value){
 if(garment?.rental!==false)throw Error('Questa opzione è riservata ai capi di proprietà del cliente.');
 const lines=String(row.notes||'').split('\n').filter(line=>line.trim()!==customerDiscardNote);
 const notes=lines.join('\n').trim();
 const next=value?[notes,customerDiscardNote].filter(Boolean).join('\n'):notes;
 if(next.length>2000)throw Error('Le note sono troppo lunghe: accorciale per aggiungere la segnalazione di scarto.');
 row.discardForReturn=!!value;
 row.notes=next;
}
function customerDiscardOption(row,garment,writable){
 const owned=garment?.rental===false;
 const reason=owned?'':garment?.rental===true?'Non disponibile per capi a noleggio.':'Imposta prima Proprietà cliente nella scheda prodotto.';
 return `<label><input type="checkbox" data-floor-flag="discardForReturn" ${row.discardForReturn?'checked':''} ${writable&&owned?'':'disabled'} onchange="floor.flag(${arg(row.code)},'discardForReturn',this.checked)"> Scarto · da restituire al cliente</label>${reason?`<p class="muted">${reason}</p>`:''}`;
}
