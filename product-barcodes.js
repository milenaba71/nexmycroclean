
function productProcessingDepartment(g){
 const setting=g?.raw?.['REPARTO PIEGATURA']||'';
 if(setting==='Acqua')return 'water';
 if(setting==='Cantieri')return 'site';
 if(['Clean room','Light clean room','Clean + Light'].includes(setting))return 'clean';
 const type=String(g?.type||'').trim().toUpperCase();
 if(!type||type==='DA DEFINIRE')return '';
 if(type==='TUTA')return 'clean';
 if(type==='TUTA DA CONFEZIONARE')return 'sewing';
 return /^(?:CAMIC(?:E|I)|GAMBAL[EI]|MASCHERIN[AE]|CAPPUCC(?:IO|I)|MASK|MASKBOTTONI|10MASK)(?:$|[^A-Z0-9])/.test(type)?'clean':'water';
}
function addProductProcessingFields(form,g,admin){
 const field=document.createElement('fieldset');field.className='wide';
 field.innerHTML='<legend>Tipo lavorazione</legend><label>Reparto<select name="foldDepartment"><option value="">Automatico dalla tipologia</option><option value="Acqua">Lavaggio ad acqua</option><option value="Cantieri">Cantieri</option><option value="Clean">Clean room / Light clean room</option></select></label><div data-clean-options><label><input type="checkbox" name="foldClean"> Clean room</label><label><input type="checkbox" name="foldLight"> Light clean room</label></div><p data-processing-note></p>';
 const setting=g?.raw?.['REPARTO PIEGATURA']||'',select=field.querySelector('select'),clean=field.querySelector('[name="foldClean"]'),light=field.querySelector('[name="foldLight"]');
 select.value=['Acqua','Cantieri'].includes(setting)?setting:setting?'Clean':'';
 clean.checked=['Clean room','Clean + Light'].includes(setting);light.checked=['Light clean room','Clean + Light'].includes(setting);
 const update=()=>{
  field.querySelector('[data-clean-options]').hidden=select.value!=='Clean';
  select.setCustomValidity(select.value==='Clean'&&!clean.checked&&!light.checked?'Scegli Clean room, Light clean room o entrambe.':'');
  const automatic=productProcessingDepartment({type:form.elements.namedItem('type')?.value});
  field.querySelector('[data-processing-note]').textContent=select.value==='Clean'?'Clean room e Light clean room confluiscono nella piegatura clean room.':select.value?'La pianificazione segue il reparto scelto.':'Destinazione automatica: '+({water:'piegatura in reparto acqua',clean:'piegatura in clean room',sewing:'reparto cucito',site:'cantieri'}[automatic]||'tipologia da definire')+'.';
 };
 field.querySelectorAll('input,select').forEach(el=>{el.disabled=!admin;el.addEventListener('change',update)});
 form.elements.namedItem('type')?.addEventListener('change',update);
 form.elements.namedItem('type')?.closest('label')?.after(field);
 if(!field.isConnected)form.append(field);
 update();
}
/* Editable public barcodes with stable internal product references. */
function productBarcode(g){return g?.barcode||g?.id||''}
const resolveBeforeEditableBarcode=resolveBarcode;
resolveBarcode=function(value){let code=String(value||'').trim(),same=s=>String(s).toLowerCase()===code.toLowerCase();let match=db.garments.find(g=>same(productBarcode(g)))||db.garments.find(g=>g.id===code)||db.garments.find(g=>(g.barcodeAliases||[]).some(same));return match?.id||resolveBeforeEditableBarcode(value)};
const labelRowBeforeEditableBarcode=labelRow;labelRow=function(g){return {...labelRowBeforeEditableBarcode(g),CODICE:productBarcode(g)}};
const productValueBeforeEditableBarcode=productValue;productValue=function(g,key){return key==='id'?productBarcode(g):productValueBeforeEditableBarcode(g,key)};
const mappedBeforeEditableBarcode=mapped;mapped=function(row){let g=mappedBeforeEditableBarcode(row),existing=db?.garments?.find(v=>v.id===resolveBarcode(g.id));if(existing){g.id=existing.id;g.barcode=productBarcode(existing);g.barcodeAliases=clone(existing.barcodeAliases||[]);g.raw.CODICE=g.barcode}return g};
let editableBarcodeCardRequest=0;
const productCardBeforeEditableBarcode=productCard;
productCard=async function(id){let request=++editableBarcodeCardRequest;await productCardBeforeEditableBarcode(id);if(request!==editableBarcodeCardRequest)return;let form=$('#productForm');if(!form||!$('#modal').open)return;let g=db.garments.find(g=>g.id===id),input=form.elements.namedItem('id'),admin=userCan('products_manage');form.productSaveOriginal=g?clone(g):null;form.productSaveRevision=cloudRevision;let mode=document.createElement('input');mode.type='hidden';mode.name='barcodeMode';mode.value='manual';form.append(mode);input.disabled=!admin;input.readOnly=!admin;input.required=!!id;input.value=g?productBarcode(g):'';input.placeholder=id?'Scansiona o inserisci il numero del tag':'Scansiona il tag oppure lascia vuoto per barcode automatico';input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();form.elements.namedItem('name')?.focus()}});if(g)$('#modal h2').textContent='Scheda prodotto · '+productBarcode(g);let note=document.createElement('p');note.className='wide';note.textContent='Tag letto dalla tavoletta o inserito: viene registrato esattamente quel codice. Campo vuoto su un nuovo capo: il gestionale genera un barcode numerico al salvataggio.';form.prepend(note);addProductProcessingFields(form,g,admin);if(!id)input.focus({preventScroll:true})};
// Retry only unrelated global revision changes; never overwrite a changed garment.
function productSaveFingerprint(value){
 if(Array.isArray(value))return '['+value.map(productSaveFingerprint).join(',')+']';
 if(value&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+productSaveFingerprint(value[k])).join(',')+'}';
 return JSON.stringify(value);
}
async function saveProductWithRevisionRetry(payload,original){
 for(let attempt=0;attempt<3;attempt++){
  const result=await appSupabase.rpc('laundry_product_save',{p_payload:payload});
  if(!result.error)return result.data;
  if(!/REVISION_CONFLICT/.test(result.error.message||''))throw Error(result.error.message);
  const fresh=await cloudRequest();
  if(payload.original_id){
   const latest=fresh.db.garments.find(g=>g.id===payload.original_id);
   if(!original||!latest||productSaveFingerprint(latest)!==productSaveFingerprint(original))throw Error('PRODUCT_CHANGED_DURING_EDIT');
  }
  payload={...payload,revision:fresh.revision};
 }
 throw Error('PRODUCT_SAVE_BUSY');
}
saveProduct=async function(e,id){e.preventDefault();if(!userCan('products_manage'))return notify('Operazione riservata agli amministratori.');let form=e.target,f=new FormData(form),button=e.submitter,print=button?.name==='print',mode='manual',g=id?clone(form.productSaveOriginal||db.garments.find(g=>g.id===id)):{raw:{},history:[]},code=String(f.get('id')||'').trim();if(id&&!code)return notify('Scansiona o inserisci il numero del tag.');mode=code?'manual':'auto';const dept=f.get('foldDepartment');if(dept==='Clean'&&!f.has('foldClean')&&!f.has('foldLight'))return notify('Scegli Clean room, Light clean room o entrambe.');g.raw??={};if(f.has('foldDepartment'))g.raw['REPARTO PIEGATURA']=dept==='Clean'?(f.has('foldClean')&&f.has('foldLight')?'Clean + Light':f.has('foldLight')?'Light clean room':'Clean room'):String(dept||'');let wash=Number(f.get('wash')),max=Number(f.get('max'));if(!Number.isInteger(wash)||wash<0||!Number.isInteger(max)||max<1)return notify('Controlla numero e limite lavaggi.');Object.assign(g,{id:code,name:f.get('name').trim(),dept:f.get('dept').trim(),size:f.get('size').trim()||'Da definire',color:f.get('color').trim()||'Da definire',type:f.get('type').trim()||'Da definire',client:f.get('client').trim(),wash,max,rental:f.get('rental')==='unknown'?null:f.get('rental')==='yes'});for(let key of ['ARMADIO','POSIZIONE','MATRICOLA','INIZIALI','ESTERNA','LOTTO','NOTE','ACCESSORI NOTE'])g.raw[key]=String(f.get(key)||'').trim();for(let key of ['SCARTO','AL LIMITE ACCETTABILITA','ALLERGICO','SMARRITO'])g.raw[key]=f.has(key)?'SI':'NO';Object.assign(g.raw,{CODICE:code,'NOME E COGNOME':g.name,REPARTO:g.dept,TAGLIA:g.size,COLORE:g.color,TIPO:g.type,AZIENDA:g.client,'NUMERO LAVAGGI':wash,'LAVAGGI MASSIMI':max,DATA:dateLabel(f.get('creation')),'DATA DI CREAZIONE':dateLabel(f.get('creation')),'DATA DI PERSONALIZZAZIONE':dateLabel(f.get('personalization')),'DATA PRESUNTA NASCITA INDUMENTO':dateLabel(f.get('estimatedBirthDate')),GESTIONE:ownership(g),ACCESSORI:f.getAll('accessories').join(' | ')});try{if(typeof prepareProductRental==='function')prepareProductRental(g,form,id)}catch(error){return notify(error.message)}form.querySelectorAll('button[type="submit"]').forEach(b=>b.disabled=true);try{await cloudFlush();let data=await saveProductWithRevisionRetry({revision:form.productSaveRevision??cloudRevision,original_id:id||null,mode,product:g},form.productSaveOriginal);$('#modal').close();cloudAccept(data);notify('Prodotto salvato · '+data.saved_code);if(print)prepareLabel(db.garments.find(g=>g.id===data.saved_id))}catch(error){let message=String(error.message);notify(/BARCODE_ALREADY_EXISTS|duplicate key/.test(message)?'Barcode già utilizzato da un altro prodotto.':/PRODUCT_CHANGED_DURING_EDIT/.test(message)?'Questo prodotto è cambiato mentre la scheda era aperta. I valori inseriti restano qui: controllali prima di riaprire la scheda.':/PRODUCT_SAVE_BUSY|REVISION_CONFLICT/.test(message)?'Aggiornamento in corso. Premi di nuovo Salva: i dati inseriti sono conservati.':/PRODUCT_IN_OPEN_LOT_CLIENT_CHANGE/.test(message)?'Completa prima il lotto aperto per cambiare cliente al prodotto.':'Salvataggio non completato. '+message);form.querySelectorAll('button[type="submit"]').forEach(b=>b.disabled=false)}};
// Keep selection keys and references stable, while displaying the editable barcode.
function showEditableBarcodeCells(selector){document.querySelectorAll(selector).forEach(cell=>{if(cell.matches('[data-product-card]')||cell.querySelector('[data-product-card]'))return;let g=db.garments.find(g=>g.id===cell.textContent.trim());if(g)cell.innerHTML=productCodeLink(g)})}
const garmentTableBeforeEditableBarcode=garmentTable;garmentTable=function(){garmentTableBeforeEditableBarcode();showEditableBarcodeCells('#garmentTable td.code')};
const renderLotRowsBeforeEditableBarcode=renderLotRows;renderLotRows=function(){renderLotRowsBeforeEditableBarcode();showEditableBarcodeCells('#lotRows .code')};
if(window.XLSX?.utils){let original=XLSX.utils.json_to_sheet;XLSX.utils.json_to_sheet=function(rows,...rest){return original.call(this,rows.map(row=>{let g=db.garments.find(g=>g.id===row.CODICE);return g?{...row,CODICE:productBarcode(g)}:row}),...rest)}}
const printLotBeforeEditableBarcode=printLot;printLot=function(){printLotBeforeEditableBarcode();showEditableBarcodeCells('#modal tbody td:first-child')};
const repairDetailBeforeEditableBarcode=repairDetail;repairDetail=function(id){repairDetailBeforeEditableBarcode(id);showEditableBarcodeCells('#app td.code')};
const editNotesBeforeEditableBarcode=editLotRowNotes;editLotRowNotes=function(id){editNotesBeforeEditableBarcode(id);let g=db.garments.find(g=>g.id===id);if(g&&$('#modal h2'))$('#modal h2').textContent='Note nel lotto · '+productBarcode(g)};

