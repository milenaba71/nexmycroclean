(function () {
  if (window.mycroBulkInstalled) return;
  window.mycroBulkInstalled = true;
  let pending = null;
  function mount() {
    if (typeof userCan !== 'function' || !userCan('products_manage')) return;
    const lotButton = document.querySelector('#entryNewProduct');
    const anchor = lotButton || document.querySelector('#app [onclick="newGarment()"]');
    if (!anchor || document.getElementById('nativeBulkProducts')) return;
    const button = document.createElement('button');
    button.id = 'nativeBulkProducts';
    button.className = 'btn';
    button.textContent = 'Registra capi RFID';
    button.onclick = () => open(Boolean(lotButton));
    anchor.after(button);
  }
  function open(inLot) {
    const lot = inLot ? current : null;
    if (inLot && (!lot || lot.archived || stage !== 'Entrata' || lotBusy() || !selectedProcessing()))
      return notify('Apri il lotto in Entrata e scegli il percorso.');
    const route = inLot ? washChoice : null;
    const valid = () => userCan('products_manage') && (!inLot ||
      (current && current.id === lot.id && !current.archived && stage === 'Entrata' && washChoice === route && userCan('lots_work')));
    show('<h2>Registra capi RFID</h2>'+(lot?'<p>'+esc(lotno(lot))+' · '+esc(lot.client)+'</p>':'')+
      '<form id="nativeRfidForm"><label>Cliente<select required name="client"><option value=""></option>'+options(lot?[lot.client]:clientNames())+'</select></label>'+
      '<label>Reparto<input name="dept"></label><label>Tipo di capo<select required name="type"><option value=""></option>'+options(types)+'</select></label>'+
      '<label>Quanti capi vuoi leggere?<input name="goal" type="number" required min="1" max="1000" step="1" value="100"></label>'+
      '<button class="btn" type="submit">Inizia lettura</button></form><p id="nativeRfidStatus" role="status"></p>'+
      '<button class="btn" id="nativeRfidSave" hidden></button> <button class="btn secondary" id="nativeRfidClose">Chiudi</button>');
    const modal = document.getElementById('modal'), form = document.getElementById('nativeRfidForm');
    const status = document.getElementById('nativeRfidStatus'), save = document.getElementById('nativeRfidSave');
    const close = document.getElementById('nativeRfidClose');
    if (lot) { form.elements.client.value = lot.client; form.elements.dept.value = lot.departmentName || ''; }
    let tags=[], next=0, created=0, existing=0, entered=0, skipped=0, failures=[], busy=false;
    let client, type, dept;
    close.onclick = () => modal.close();
    form.onsubmit = event => {
      event.preventDefault();
      if (!valid()) return notify('Riapri il lotto e controlla il percorso.');
      client=form.elements.client.value; type=form.elements.type.value; dept=form.elements.dept.value.trim();
      const goal=Number(form.elements.goal.value);
      const token=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
      pending = {token, receive: result => {
        if (!modal.open || !form.isConnected || !valid()) return;
        const ids=Array.from(new Set(result));
        if (ids.length!==goal || !ids.every(id=>typeof id==='string' && /^(?:[A-F0-9]{2}){1,62}$/.test(id))) return;
        tags=ids; form.hidden=true;
        status.textContent=tags.length+' tag distinti · '+client+' · '+type;
        save.textContent=lot?'Salva prodotti e registra nel lotto':'Salva prodotti';
        save.hidden=false;
      }};
      location.href='mycro-rfid://scan?count='+goal+'&token='+token;
    };
    save.onclick=async () => {
      if (busy || !tags.length || !valid()) return;
      busy=true; save.disabled=close.disabled=true;
      const guard=e=>e.preventDefault();
      modal.addEventListener('cancel',guard);
      try {
        await cloudFlush();
        cloudAccept(await cloudRequest(),false);
        for (;next<tags.length;next++) {
          if (!valid()) throw Error('Lotto o percorso cambiato.');
          const epc=tags[next];
          status.textContent='Registrazione '+(next+1)+' di '+tags.length;
          const matches=(await productsRead({mode:'lookup',code:epc})).rows;
          if(matches.length>1){failures.push(epc+' · più prodotti associati');continue;}
          let id;
          if(matches.length){id=matches[0].id;existing++;}
          else {
            const product={id:epc,client,type,dept,name:'',size:'Da definire',color:'Da definire',wash:0,max:80,rental:null,history:[],
              raw:{CODICE:epc,TIPO:type,AZIENDA:client,REPARTO:dept,'NUMERO LAVAGGI':0,'LAVAGGI MASSIMI':80}};
            const response=await appSupabase.rpc('laundry_product_save',{p_payload:{revision:cloudRevision,original_id:null,mode:'manual',product}});
            if(response.error) {
              if(/BARCODE_ALREADY_EXISTS/.test(response.error.message)){failures.push(epc+' · codice già assegnato');continue;}
              throw Error(response.error.message);
            }
            cloudAccept(response.data,false);
            id=response.data.saved_id; created++;
          }
          if(lot) {
            if(!valid())throw Error('Lotto o percorso cambiato.');
            if(current.rows.some(r=>r.code===id)){skipped++;continue;}
            const error=await checkedProcess(id);
            if(error) failures.push(epc+' · '+error);
            else {await cloudFlush();entered++;}
          }
        }
        status.textContent='Prodotti creati: '+created+' · già registrati: '+existing+(lot?' · inseriti nel lotto: '+entered+' · già presenti: '+skipped:'');
        if(failures.length)status.textContent+=' · Da verificare: '+failures.join(' / ');
        save.hidden=true;
      } catch(err) {
        status.textContent='Interrotto al tag '+(next+1)+' di '+tags.length+'. '+err.message;
        save.textContent='Riprendi';
      } finally {
        busy=false;save.disabled=close.disabled=false;modal.removeEventListener('cancel',guard);
        if(!form.isConnected) {show('<h2>Registrazione RFID</h2><p>'+esc(status.textContent)+'</p><button class="btn" onclick="document.getElementById(\'modal\').close()">Chiudi</button>');}
      }
    };
    modal.addEventListener('close',()=>{pending=null;if(!busy && next>0)render();},{once:true});
  }
  window.addEventListener('mycro-rfid-result',e=>{
    if(pending && e.detail && pending.token===e.detail.token && Array.isArray(e.detail.tags)){
      const receive=pending.receive;pending=null;receive(e.detail.tags);
    }
  });
  new MutationObserver(mount).observe(document.body,{childList:true,subtree:true});
  mount();
})();
