/* Duplicate descriptive data through the existing atomic new-product save. */
const productCardBeforeDuplicate=productCard;
productCard=async function(id){
 await productCardBeforeDuplicate(id);
 const form=$('#productForm');
 if(!id||!form||!$('#modal').open||!userCan('products_manage'))return;
 const button=document.createElement('button');button.type='button';button.className='btn secondary';button.id='duplicateProductButton';button.textContent='Duplica prodotto';
 button.onclick=()=>duplicateProduct(id,button);
 form.querySelector('button[type="submit"]')?.parentNode.append(button);
};
async function duplicateProduct(id,button){
 if(!userCan('products_manage')||button?.disabled)return;
 if(button)button.disabled=true;
 try{
  await productCard(null);
  const form=$('#productForm'),g=db.garments.find(g=>g.id===id);
  if(!form||!$('#modal').open)return;
  if(!g){$('#modal').close();return notify('Prodotto originale non più disponibile.');}
  const raw=g.raw||{};
  const set=(name,value)=>{const el=form.elements.namedItem(name);if(!el)return;el.value=value??'';el.dispatchEvent(new Event('change',{bubbles:true}));};
  set('client',g.client);
  for(const name of ['name','type','dept','size','color','max']){
   const el=form.elements.namedItem(name);
   if(el?.tagName==='SELECT')el.innerHTML=masterOptions(name,g[name],g.client);
   set(name,g[name]==='Da definire'?'':g[name]);
  }
  for(const name of ['ARMADIO','POSIZIONE','MATRICOLA','INIZIALI','ESTERNA','LOTTO','NOTE','ACCESSORI NOTE'])set(name,raw[name]);
  set('rental',g.rental===true?'yes':g.rental===false?'no':'unknown');
  const contract=form.elements.namedItem('rentalContractId');
  if(contract){
   const ref=g.rentalContract,valid=ref&&rentalFormActiveContracts(form).some(k=>k.id===ref.contractId)&&rentalFormClient(form)?.id===ref.clientId;
   if(valid)set('rentalContractId',ref.contractId);
   else if(Object.hasOwn(g,'rentalContract'))set('rentalContractId','__stock__');
  }
  const accessories=String(raw.ACCESSORI||'').split(' | ').filter(Boolean);
  const menu=$('#productAccessoriesMenu');if(menu)menu.outerHTML=productAccessoriesDropdown(accessories,raw);
  form.elements.namedItem('ALLERGICO').checked=yes(raw.ALLERGICO);
  for(const name of ['SCARTO','SMARRITO','AL LIMITE ACCETTABILITA'])form.elements.namedItem(name).checked=false;
  set('wash',0);set('creation',new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}));set('personalization','');
  set('barcodeMode','manual');set('id','');
  form.elements.namedItem('id').readOnly=false;form.elements.namedItem('id').required=true;
  $('#modal h2').textContent='Duplica prodotto · '+productBarcode(g);
  const note=document.createElement('p');note.className='wide notice';note.textContent='Copia dei dati salvati del prodotto '+productBarcode(g)+'. Scansiona o inserisci il numero del nuovo tag, controlla i dati e premi Salva prodotto. Nessun numero viene generato automaticamente. Lavaggi, scarto, smarrimento e storico ripartono da zero; il prodotto originale rimane invariato.';form.prepend(note);
  rentalProductPreview(form);
 }catch(error){notify('Duplicazione non completata. '+error.message);if(button)button.disabled=false;}
}
