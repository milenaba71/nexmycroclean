const fields={client:'Cliente / Azienda',dept:'Reparto',name:'Utilizzatore',ARMADIO:'Armadio',POSIZIONE:'Posizione',MATRICOLA:'Matricola',type:'Tipo',size:'Taglia',color:'Colore',INIZIALI:'Iniziali'};
const norm=s=>s.trim().replace(/\s+/g,' ').toLocaleLowerCase('it');
async function jpeg(file){
  const url=URL.createObjectURL(file);
  try {
    const image=new Image(); image.src=url; await image.decode();
    const scale=Math.min(1,2000/Math.max(image.width,image.height));
    const canvas=document.createElement('canvas'); canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));
    canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.84));
    if(!blob||blob.size>3000000)throw Error('Fotografa più da vicino un solo cartellino.');
    return blob;
  } finally {URL.revokeObjectURL(url)}
}
export async function readPhoto(input,api){
  const file=input.files[0];if(!file)return;
  const form=input.form, panel=input.closest('section'), status=panel.querySelector('output');
  const review=panel.querySelector('.photo-review');review.replaceChildren();
  input.disabled=true;status.textContent='Lettura della foto in corso…';
  try{
    const {data,error}=await api.functions.invoke('product-photo',{body:await jpeg(file),headers:{'Content-Type':'image/jpeg'}});
    if(error)throw Error('Lettura non disponibile. Riprova oppure compila la scheda a mano.');
    if(!form.isConnected)return;
    const proposals=[];
    for(const [key,label] of Object.entries(fields)){
      const value=data?.[key],field=form.elements.namedItem(key);
      if(typeof value!=='string'||!value.trim()||!field||field.disabled||field.readOnly)continue;
      const row=document.createElement('label'),box=document.createElement('input');
      box.type='checkbox';box.checked=!field.value;
      row.append(box,document.createTextNode(' '+label+' · '+value));review.append(row);
      proposals.push({key,label,value,box});
    }
    status.textContent=proposals.length?'Controlla i valori e seleziona quelli da inserire.':'Nessun dato leggibile. Prova una foto più nitida.';
    if(!proposals.length)return;
    const apply=document.createElement('button');apply.type='button';apply.className='btn secondary';apply.textContent='Inserisci nella scheda';review.append(apply);
    apply.onclick=()=>{
      const misses=[];let count=0,clientMismatch=false;
      for(const {key,label,value,box} of proposals){
        if(!box.checked)continue;
        const el=form.elements.namedItem(key);if(!el||el.disabled||el.readOnly)continue;
        let next=value;
        if(el.tagName==='SELECT'){
          const options=[...el.options].filter(o=>!o.disabled&&norm(o.value)===norm(value));
          if(options.length!==1||(key==='dept'&&clientMismatch)){misses.push(label+' · '+value);if(key==='client')clientMismatch=true;continue}
          next=options[0].value;
        }
        if(el.value!==next){el.value=next;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))}
        count++;
      }
      review.replaceChildren();status.textContent=count+' campi inseriti. '+(misses.length?'Da scegliere in anagrafica: '+misses.join(', ')+'. ':'')+'Controlla e premi Salva prodotto.';
    };
  }catch(err){status.textContent=err.message}finally{input.value='';input.disabled=false}
}
