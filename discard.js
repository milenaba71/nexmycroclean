function productIsDiscard(g){return !!g&&(yes(g.raw?.SCARTO)||Number(g.wash)>=Number(g.max))}
function lotDiscardCell(g,row){let discard=row.discard||productIsDiscard(g);return `<td>${discard?'<span role="img" aria-label="Scarto" title="Scarto: segnalato nel lotto, nella scheda prodotto o per limite lavaggi raggiunto" style="display:inline-flex;align-items:center;gap:7px;color:#b91343;font-weight:700"><span style="width:13px;height:13px;border-radius:50%;background:#e52242;display:inline-block"></span>Scarto</span>':'<span class="muted">—</span>'}</td>`}

function normalizeDiscardFlags(){for(let g of db.garments){if(Number(g.wash)>=Number(g.max)){g.raw={...g.raw,SCARTO:'SI'}}}}
const saveBeforeDiscardFlag=save;save=function(){normalizeDiscardFlags();return saveBeforeDiscardFlag()};
