/* PDF text is read locally; only reviewed text is saved through the existing protected RPC. */
(()=>{
 const base='https://cdn.jsdelivr.net/npm/pdfjs-dist@5.7.284/';
 let library;
 async function loadLibrary(){
  if(!library)library=import(base+'build/pdf.mjs').then(lib=>{lib.GlobalWorkerOptions.workerSrc=base+'build/pdf.worker.min.mjs';return lib}).catch(e=>{library=null;throw e});
  return library;
 }
 function split(text,limit=3800){
  const parts=[];let rest=text.trim();
  while(rest.length>limit){let end=rest.lastIndexOf('\n',limit);if(end<limit/2)end=rest.lastIndexOf(' ',limit);if(end<limit/2)end=limit;if(/[\uD800-\uDBFF]/.test(rest[end-1]))end--;parts.push(rest.slice(0,end));rest=rest.slice(end).trimStart()}
  if(rest){if(rest.length<10&&parts.length)parts[parts.length-1]+='\n'+rest;else parts.push(rest)}return parts;
 }
 async function extract(file,{active=()=>true,progress=()=>{},getLibrary=loadLibrary}={}){
  if(!file||!file.name?.toLowerCase().endsWith('.pdf'))throw Error('Seleziona un file PDF.');
  if(!file.size||file.size>10*1024*1024)throw Error('Il PDF deve avere dimensione massima di 10 MB.');
  const bytes=new Uint8Array(await file.arrayBuffer());
  if(!new TextDecoder().decode(bytes.slice(0,1024)).includes('%PDF-'))throw Error('Il file non è un PDF valido.');
  if(!active())throw Error('Importazione annullata.');
  let loadingTimer;const lib=await Promise.race([getLibrary(),new Promise((_,reject)=>{loadingTimer=setTimeout(()=>reject(Error('Lettore PDF non disponibile. Controlla la connessione e riprova.')),20000)})]).finally(()=>clearTimeout(loadingTimer));if(!active())throw Error('Importazione annullata.');
  const task=lib.getDocument({data:bytes,isEvalSupported:false,disableFontFace:true,enableXfa:false,stopAtErrors:true,cMapUrl:base+'cmaps/',cMapPacked:true,standardFontDataUrl:base+'standard_fonts/'});
  let timer;const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{reject(Error('Lettura del PDF troppo lenta. Prova un documento più piccolo.'));void task.destroy()},45000)});
  try{return await Promise.race([(async()=>{
   const pdf=await task.promise;if(pdf.numPages>50)throw Error('Il PDF supera 50 pagine. Dividilo in documenti più piccoli.');
   const sections=[],unreadable=[];let count=0;
   for(let page=1;page<=pdf.numPages;page++){
    if(!active())throw Error('Importazione annullata.');progress(page,pdf.numPages);
    const sheet=await pdf.getPage(page),content=await sheet.getTextContent();
    const text=content.items.filter(item=>typeof item.str==='string').map(item=>item.str+(item.hasEOL?'\n':' ')).join('').replace(/[ \t]+\n/g,'\n').trim();sheet.cleanup();
    count+=text.length;if(count>80000)throw Error('Il PDF supera 80.000 caratteri. Dividilo in documenti più piccoli.');
    if(text.length<10){unreadable.push(page);continue}
    for(const body of split(text))sections.push({page,body});
   }
   if(!sections.length)throw Error('Non è stato trovato testo leggibile. Per PDF scansionati o fotografati usa una copia con testo selezionabile (OCR).');
   return {sections,unreadable,pages:pdf.numPages};
  })(),timeout])}catch(e){if(e?.name==='PasswordException')throw Error('Il PDF è protetto da password. Carica una copia senza protezione.');throw e}finally{clearTimeout(timer);await task.destroy().catch(()=>{})}
 }
 window.AssistantPDF={split,extract};
 window.openAssistantPDF=async function(target,{active,rpc,setBusy,back,getLibrary}){
  const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e};
  const button=(text,fn)=>{const b=el('button',text);b.type='button';b.className='btn secondary';b.onclick=fn;return b};
  const label=(text,input)=>{const l=el('label',text);l.style.cssText='display:block;margin:8px 0';input.style.cssText='display:block;width:100%;max-width:100%;box-sizing:border-box';l.append(input);return l};
  const file=el('input'),title=el('input'),preview=el('div'),status=el('p'),confirm=el('input');file.type='file';file.accept='.pdf,application/pdf';title.maxLength=100;confirm.type='checkbox';status.setAttribute('role','status');
  let busy=false,rows=[],warnings=[],fileName='';
  const pending=()=>rows.filter(r=>!r.saved&&r.include.checked);
  const lock=value=>{busy=value;setBusy(value);file.disabled=title.disabled=read.disabled=cancel.disabled=confirm.disabled=value;for(const row of rows){row.area.disabled=row.include.disabled=value||row.saved}approve.disabled=value||!confirm.checked||!pending().length};
  const cancel=button('Torna a Insegna all’IA',()=>{if(!busy)back()});
  const read=button('Leggi PDF',async()=>{
   if(busy||!active())return;const chosen=file.files?.[0];if(!chosen){status.textContent='Scegli prima il file PDF.';return}
   lock(true);rows=[];preview.replaceChildren();confirm.checked=false;fileName=chosen.name;
   try{
    const access=await rpc('status');if(!access.canTrain)throw Error('Solo il Super amministratore può caricare documenti nella memoria.');
    if(!active())return;
    const result=await extract(chosen,{active,getLibrary,progress:(page,total)=>{if(active())status.textContent='Lettura pagina '+page+' di '+total+'…'}});
    if(!active())return;warnings=result.unreadable;title.value=chosen.name.replace(/\.pdf$/i,'').slice(0,100);
    if(warnings.length)preview.append(el('p','Attenzione: pagine senza testo leggibile, escluse dall’importazione: '+warnings.join(', ')+'. Controlla se contengono immagini o istruzioni da trascrivere.'));
    result.sections.forEach((section,index)=>{
     const item=el('section'),include=el('input'),area=el('textarea'),state=el('p');include.type='checkbox';include.checked=true;area.value=section.body;area.maxLength=4000;area.rows=6;area.dir='auto';
     const heading=el('label');heading.append(include,document.createTextNode(' Includi pagina '+section.page+' · sezione '+(index+1)));item.style.cssText='border:1px solid #dce2ef;border-radius:8px;padding:12px;margin:12px 0';item.append(heading,label('Testo da verificare e correggere',area),state);preview.append(item);
     const row={id:crypto.randomUUID(),page:section.page,index:index+1,include,area,state,saved:false};rows.push(row);include.onchange=()=>{confirm.checked=false;approve.disabled=true};area.oninput=()=>{confirm.checked=false;approve.disabled=true};
    });
    status.textContent=result.pages+' pagine lette · '+rows.length+' sezioni da verificare. Nessun contenuto è ancora stato memorizzato.';
   }catch(e){if(active())status.textContent=e.message||'Impossibile leggere il PDF.'}finally{lock(false)}
  });
  const approve=button('Approva e memorizza le sezioni selezionate',async()=>{
   if(busy||!active()||!confirm.checked)return;const selected=pending(),name=title.value.trim();if(!selected.length)return;
   if(name.length<3){status.textContent='Inserisci un titolo di almeno 3 caratteri.';return}
   if(selected.some(r=>r.area.value.trim().length<10||r.area.value.trim().length>4000)){status.textContent='Ogni sezione selezionata deve contenere da 10 a 4.000 caratteri.';return}
   // Freeze the approved payload for this attempt; retry uses the same UUID (no duplicate insert).
   for(const row of selected)row.payload={id:row.id,revision:0,approved:true,title:(name.slice(0,85)+' · p.'+row.page+' §'+row.index).slice(0,120),body:row.area.value.trim(),source:('PDF: '+fileName.slice(0,240)+' · pagina '+row.page).slice(0,300)};
   lock(true);
   try{
    const access=await rpc('status');if(!access.canTrain)throw Error('Autorizzazione alla memoria non disponibile.');
    for(const row of selected){
     if(!active())break;
     await rpc('save',row.payload);row.saved=true;row.state.textContent='Memorizzata';status.textContent=rows.filter(r=>r.saved).length+' sezioni memorizzate.';
    }
    if(active())status.textContent=rows.filter(r=>r.saved).length+' sezioni memorizzate. '+pending().length+' sezioni selezionate ancora da salvare. Le sezioni approvate sono disponibili all’IA.';
   }catch(e){if(active())status.textContent=rows.filter(r=>r.saved).length+' sezioni memorizzate. Salvataggio interrotto: '+(/KNOWLEDGE_CONFLICT/.test(e.message||'')?'una sezione risulta già presente. Verifica in Memoria approvata prima di riprovare.':e.message||'riprova')+'. Le sezioni non salvate restano qui.'}finally{lock(false)}
  });
  approve.disabled=true;confirm.onchange=()=>{approve.disabled=busy||!confirm.checked||!pending().length};title.oninput=()=>{confirm.checked=false;approve.disabled=true};
  file.onchange=()=>{rows=[];preview.replaceChildren();confirm.checked=false;approve.disabled=true;status.textContent='File selezionato. Premi Leggi PDF.'};
  const consent=el('label');consent.style.display='block';consent.append(confirm,document.createTextNode(' Ho verificato il testo, le eventuali pagine escluse e approvo queste sezioni come procedure aziendali.'));
  target.replaceChildren(el('h3','Carica PDF nella memoria IA'),el('p','PDF con testo selezionabile: massimo 10 MB, 50 pagine e 80.000 caratteri. Immagini, grafici e scansioni non vengono letti. Verifica sempre l’anteprima, soprattutto tabelle e impaginazioni a colonne.'),el('small','Il file viene letto nel browser. Si memorizzano solo le sezioni di testo approvate con nome file e pagina; il PDF originale non viene archiviato. Le sezioni potranno essere inviate a OpenAI quando pertinenti a una domanda.'),label('File PDF',file),read,label('Titolo del documento',title),preview,consent,approve,cancel,status);
 };
})();
