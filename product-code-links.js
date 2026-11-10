/* Product identifiers always open the same card, using the stable internal ID. */
function productCodeLink(product,label){
 const id=String(typeof product==='object'?product?.id||'':product||'');
 if(!id||id==='—')return esc(label||id||'—');
 const g=typeof product==='object'?product:db.garments.find(item=>item.id===id);
 const text=label??(g?productBarcode(g):id);
 return '<button type="button" class="link code product-code-link" data-product-card="'+esc(id)+'" title="Apri scheda prodotto" aria-label="'+esc('Apri scheda prodotto '+text)+'" onclick="event.stopPropagation();showGarment(this.dataset.productCard)">'+esc(text)+'</button>';
}
