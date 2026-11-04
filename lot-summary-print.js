/* Print the same complete summary shown inside the lot, without page filters. */
(function(){
 const sectionColors=`
 .lot-summary-products{--section-color:#3b65a5;--section-tint:#eaf2ff}
 .lot-summary-sewing{--section-color:#a67919;--section-tint:#fff4cd}
 .sewing-products{--section-color:#8051a8;--section-tint:#f2e9fb}
 .sewing-details{--section-color:#337d69;--section-tint:#e7f5ef}
 .lot-summary-products,.lot-summary-sewing,.sewing-products,.sewing-details{border-top:5px solid var(--section-color);border-radius:12px;overflow:hidden;margin-bottom:24px}
 .lot-summary-products>.panelhead,.lot-summary-sewing>.panelhead,.sewing-products>.panelhead,.sewing-details>.panelhead{background:linear-gradient(110deg,var(--section-tint),#fff);padding:16px;gap:12px;flex-wrap:wrap}
 .lot-summary-products th,.lot-summary-sewing th,.sewing-products th,.sewing-details th{background:var(--section-tint)}
 .lot-summary-print-options{display:flex;gap:8px;flex-wrap:wrap}
 @media(max-width:640px){.lot-summary-print-options{width:100%}.lot-summary-print-options button{flex:1;white-space:normal}}
 @media print{.lot-summary-products,.lot-summary-sewing,.sewing-products,.sewing-details{-webkit-print-color-adjust:exact;print-color-adjust:exact}.lot-summary-print-options{display:none}}
 `;
 document.head.insertAdjacentHTML('beforeend','<style>'+sectionColors+'</style>');
 const previous=lotTypeSummary;
 function summaryBody(lot,withNotes=true){
   let html=previous(lot).replace('class="panel" aria-label="Riassunto prodotti per tipologia"','class="panel lot-summary-products" aria-label="Riassunto prodotti per tipologia"')
     .replace('<section class="panel"><div class="panelhead"><h2>Interventi reparto cucito','<section class="panel lot-summary-sewing"><div class="panelhead"><h2>Interventi reparto cucito');
   if(!withNotes)html=html.replace(/<(th|td) class="report-note">[\s\S]*?<\/\1>/g,'');
   return html;
 }
 lotTypeSummary=function(lot){return summaryBody(lot).replace('<h2>Riepilogo per tipo di prodotto</h2>',`<h2>Riepilogo per tipo di prodotto</h2><div class="lot-summary-print-options"><button type="button" class="btn secondary lot-summary-print" onclick="printLotSummary(${Number(lot.id)},true)">Stampa report con note</button><button type="button" class="btn secondary lot-summary-print" onclick="printLotSummary(${Number(lot.id)},false)">Stampa report senza note</button></div>`)};
 function productNotes(lot){const rows=lot.rows.filter(r=>String(r.notes||'').trim());return rows.length?`<section class="panel lot-summary-products"><div class="panelhead"><h2>Note dei prodotti nel lotto</h2></div><table><thead><tr><th>Codice prodotto / tag</th><th>Note</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${sewingProductLabel(r.code)}</td><td style="white-space:pre-wrap">${esc(r.notes)}</td></tr>`).join('')}</tbody></table></section>`:''}
 window.lotSummaryPrintHtml=function(lot,withNotes=true){return `<!doctype html><html lang="it"><head><meta charset="utf-8"><title>Riepilogo ${esc(lotno(lot))}</title><style>${sectionColors}@page{size:A4 landscape;margin:12mm}*{box-sizing:border-box}body{font:12px Arial,sans-serif;color:#20334c;margin:24px}h1{font-size:23px;color:#203b78}h2{font-size:16px;break-after:avoid}.panel{margin:20px 0}.panelhead{display:flex;gap:16px;align-items:center;flex-wrap:wrap}.muted,.bottom{color:#52647d}.bottom{margin:12px 0;line-height:1.5}.scroll{overflow:visible}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:1px solid #d7dfe9;padding:7px 4px;text-align:left;overflow-wrap:anywhere}th{background:#eef2f8}th:first-child{width:15%}thead{display:table-header-group}tr{break-inside:avoid}.lot-summary-print,.sewing-open,.sewing-products th:last-child,.sewing-products td:last-child{display:none}.tools{margin:16px 0}button{padding:12px;border:0;border-radius:6px;background:#203b78;color:white;cursor:pointer}@media print{body{margin:0;font-size:9px}.tools{display:none}th,td{padding:5px 3px}}</style></head><body><div class="tools"><button onclick="window.print()">Stampa / Salva come PDF</button></div><b>MYCROCLEAN</b><h1>Riepilogo lotto · ${esc(lotno(lot))}</h1><p><b>${esc(lot.client||'')}</b> · Ingresso: ${esc(lot.date||'—')} · Colli: ${esc(String(lot.colli??'—'))}<br>Ordine: ${esc(lot.airtableOrderCode||'—')} · Riferimento cliente: ${esc(lot.airtableCustomerOrder||'—')}</p><p>Generato il ${esc(new Date().toLocaleString('it-IT',{timeZone:'Europe/Rome'}))}. Quantità dell’intero lotto, indipendenti dai filtri della pagina.</p><p><b>Report ${withNotes?'con note':'senza note'}</b></p>${summaryBody(lot,withNotes)}${withNotes?productNotes(lot):''}<p class="bottom">Documento interno di riepilogo. Non è una fattura o un DDT.</p></body></html>`};
 window.printLotSummary=async function(id,withNotes=true){const popup=window.open('about:blank','_blank');if(!popup)return notify('Consenti l’apertura della finestra per stampare il riepilogo.');popup.opener=null;popup.document.body.textContent='Preparazione del riepilogo…';try{await cloudFlush();cloudAccept(await cloudRequest(),false);const lot=db.lots.find(l=>l.id===Number(id));if(!lot)throw Error('Lotto non disponibile.');if(popup.closed)return;popup.document.open();popup.document.write(lotSummaryPrintHtml(lot,withNotes));popup.document.close()}catch(e){if(!popup.closed)popup.document.body.textContent='Impossibile preparare il riepilogo: '+e.message;notify(e.message)}};
})();

