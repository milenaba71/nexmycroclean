/* Shared label templates. Product rows never leave the editor through this API. */
(function(){
 'use strict';
 const clone=value=>JSON.parse(JSON.stringify(value));
 let snapshot={revision:0,payload:{presets:{},current:null}},ready=false,busy=false,changed=false,applying=false;
 const status=document.getElementById('labelCloudStatus');
 const shield=document.createElement('div');
 shield.style.cssText='position:fixed;inset:0;background:#fffffff2;z-index:10000;display:flex;align-items:center;justify-content:center;padding:24px;font:16px Arial';
 document.body.appendChild(shield);
 function message(text){status.textContent=text;}
 function block(text){shield.textContent=text;shield.hidden=false;shield.style.display='flex';}
 function unblock(){shield.hidden=true;shield.style.display='none';}
 function errorText(error){const text=String(error.message||error);return text.includes('REVISION_CONFLICT')?'Un collega ha aggiornato i layout. Le tue modifiche non sono state salvate. Esportale se vuoi conservarle, poi premi Aggiorna dal server e ripeti la modifica.':text.includes('INVALID_LABEL_LAYOUT')?'Layout non valido o troppo grande (massimo 5 MB complessivi).':text;}
 async function request(action,p){
  if(window.parent===window||typeof window.parent.labelLayoutsRequest!=='function')throw Error('Apri l’editor dal gestionale ed effettua l’accesso con un utente abilitato alle etichette.');
  return window.parent.labelLayoutsRequest(action,p);
 }
 function legacy(){try{return JSON.parse(localStorage.getItem(PRESETS_KEY)||'{}')}catch{return {}}}
 function hasLegacy(){try{return Object.keys(legacy()).length>0||!!localStorage.getItem(LS_KEY)||!!localStorage.getItem(FT_KEY)}catch{return false}}
 const C=window.LabelCloud={
  presets:()=>clone(snapshot.payload.presets),
  dirty(){if(!ready||applying)return;changed=true;message('Modifiche non salvate · Premi Salva layout condiviso');},
  async save(presets){
   if(!ready||busy){message('Attendi il caricamento dei layout dal server.');return false;}
   busy=true;block('Salvataggio dei layout condivisi…');
   try{
    const payload={presets:clone(presets),current:currentPreset()};
    snapshot=await request('save',{revision:snapshot.revision,payload});
    changed=false;message('Salvato sul server · Condiviso con gli utenti abilitati');return true;
   }catch(error){changed=true;message('Non salvato · '+errorText(error));alert(errorText(error));return false;}
   finally{busy=false;unblock();}
  },
  async load(){
   if(busy)return;
   if(changed&&!confirm('Ricaricare i layout condivisi e abbandonare le modifiche non salvate?'))return;
   busy=true;block('Caricamento layout condivisi dal server…');
   try{
    const next=await request('read',{});
    snapshot=next;applying=true;
    if(next.payload.current)applyPreset(next.payload.current);
    refreshPresetSelect();changed=false;ready=true;
    message('Layout sul server · Condivisi con gli utenti abilitati');
    document.getElementById('btnLegacyLayouts').hidden=!hasLegacy();unblock();
   }catch(error){
    message('Caricamento non riuscito · '+errorText(error));
    if(ready)unblock();else{
     shield.textContent=errorText(error)+' ';
     const retry=document.createElement('button');retry.textContent='Riprova';retry.onclick=()=>C.load();shield.appendChild(retry);
     const link=document.createElement('a');link.href='./';link.target='_top';link.textContent='Apri gestionale';link.style.marginLeft='16px';shield.appendChild(link);
    }
   }finally{busy=false;applying=false;}
  },
  async importLegacy(){
   if(!ready||busy)return;
   if(!confirm('Copiare sul server i vecchi layout di questo browser e renderli disponibili agli utenti abilitati? I nomi già esistenti saranno conservati.'))return;
   try{
    const presets=C.presets(),old=legacy();
    const layout=localStorage.getItem(LS_KEY),texts=localStorage.getItem(FT_KEY);
    if(layout||texts)old['Layout locale recuperato']={layout:layout?JSON.parse(layout):clone(DEFAULT_LAYOUT),freetexts:texts?JSON.parse(texts):[]};
    for(const [name,value] of Object.entries(old)){
     let key=name.slice(0,120),n=1;while(Object.prototype.hasOwnProperty.call(presets,key))key=name.slice(0,120)+' (recuperato '+(n++)+')';
     Object.defineProperty(presets,key,{value,enumerable:true,configurable:true,writable:true});
    }
    if(!await C.save(presets))return;
    refreshPresetSelect();
    // Remove legacy browser storage only after server acknowledgement.
    for(const key of [PRESETS_KEY,LS_KEY,FT_KEY])localStorage.removeItem(key);
    document.getElementById('btnLegacyLayouts').hidden=true;
    message('Vecchi layout recuperati sul server. Seleziona il modello dall’elenco.');
   }catch(error){alert('Recupero non completato: '+errorText(error));}
  }
 };
 document.getElementById('btnReloadLayouts').onclick=()=>C.load();
 document.getElementById('btnLegacyLayouts').onclick=()=>C.importLegacy();
 const settings=new Set(['formato','perRiga','hmm','rollW','rollH','rollGap']);
 document.addEventListener('input',event=>{if(settings.has(event.target.id)||event.target.closest('#toggles'))C.dirty();});
 document.addEventListener('change',event=>{if(settings.has(event.target.id)||event.target.closest('#toggles'))C.dirty();});
 window.addEventListener('beforeunload',event=>{if(changed||busy){event.preventDefault();event.returnValue='';}});
 C.load();
})();
