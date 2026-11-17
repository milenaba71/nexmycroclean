/* RFD8500 Bluetooth HID sends one EPC per terminated record. */
(function () {
  function allowed() {
    return current && stage === 'Entrata' && !current.archived && userCan('lots_work');
  }

  function mount() {
    const anchor = document.getElementById('entryNewProduct');
    if (!anchor || !allowed() || document.getElementById('rfidEntryButton')) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.id = 'rfidEntryButton';
    button.className = 'btn secondary';
    button.textContent = 'Leggi tag RFID';
    button.onclick = openReader;
    anchor.after(button);
  }

  function openReader() {
    if (!allowed() || lotBusy()) return;
    if (!washChoice || !selectedProcessing()) return notify('Scegli prima il percorso di lavaggio.');
    const lotId = current.id, lotLabel = lotno(current), route = washChoice;
    const tags = new Set();
    let scanning = false, goal = 0, duplicates = 0, overflow = 0;
    const products = new Map();
    for (const garment of db.garments) {
      if (['retired','bought_out'].includes(garment.lifecycleState)) continue;
      const epc = String(productBarcode(garment)).trim().toUpperCase();
      products.set(epc, products.has(epc) ? null : garment.id);
    }
    show('<h2>Lettura multipla RFID</h2><p><b>'+esc(lotno(current))+'</b> · '+esc(current.client)+' · '+esc(current.departmentName || 'Reparto non indicato')+'</p>'+
      '<label>Quanti tag vuoi leggere?<input id="rfGoal" type="number" min="1" step="1" inputmode="numeric" placeholder="Es. 20"></label>'+
      '<div class="tools"><button type="button" id="rfBegin" class="btn">Inizia lettura</button></div>'+
      '<section id="rfCapture" hidden><label>Ingresso pistola RFID<input id="rfInput" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Premi il grilletto"></label>'+
      '<p id="rfStatus" role="status"></p><details><summary>Tag raccolti</summary><ul id="rfList"></ul></details>'+
      '<button type="button" id="rfSave" class="btn" disabled>Registra nel lotto</button></section>'+
      '<button type="button" class="btn secondary" id="rfClose">Chiudi</button>');
    const modal = document.getElementById('modal');
    const get = id => document.getElementById(id);
    const input = get('rfInput'), status = get('rfStatus'), save = get('rfSave');
    function refresh() {
      const known = [...tags].filter(tag => products.get(tag)).length;
      status.textContent = tags.size+' / '+goal+' tag distinti · '+known+' riconosciuti · '+duplicates+' riletture'+(overflow?' · '+overflow+' letture oltre il limite':'')+(tags.size===goal?' · Obiettivo raggiunto. Rilascia il grilletto.':'');
      save.disabled = known === 0;
    }
    function add(raw) {
      const epc = raw.trim().toUpperCase();
      if (!scanning || !epc) return;
      if (!/^(?:[0-9A-F]{2})+$/.test(epc) || epc.length > 124) {
        status.textContent = 'Formato inatteso. Configura la pistola per inviare un EPC esadecimale seguito da Invio.';
        return;
      }
      if (tags.has(epc)) duplicates++;
      else if (tags.size >= goal) overflow++;
      else {
        tags.add(epc);
        const li = document.createElement('li');
        li.textContent = epc+' · '+(products.get(epc)?'Riconosciuto':'Da verificare');
        get('rfList').append(li);
      }
      refresh();
    }
    input.onkeydown = e => {
      if (e.key !== 'Enter' && e.key !== 'Tab') return;
      e.preventDefault(); e.stopPropagation();
      add(input.value); input.value = '';
    };
    input.onpaste = e => {
      e.preventDefault();
      const records = e.clipboardData.getData('text').split(/[\s,;]+/);
      records.forEach(add); input.value = '';
    };
    get('rfBegin').onclick = () => {
      goal = Number(get('rfGoal').value);
      if (!Number.isSafeInteger(goal) || goal < 1) return notify('Inserisci un numero intero maggiore di zero.');
      scanning = true; get('rfGoal').disabled = true; get('rfBegin').hidden = true;
      get('rfCapture').hidden = false; refresh(); input.focus();
    };
    get('rfClose').onclick = () => modal.close();
    save.onclick = async () => {
      if (input.value.trim()) { add(input.value); input.value = ''; }
      if (!scanning || lotBusy() || !allowed() || current.id !== lotId || washChoice !== route) return notify('Controlla il lotto e il percorso prima di registrare.');
      scanning = false;
      const batch = [...tags];
      const shield = event => {
        if (/^[0-9a-f]$/i.test(event.key) || event.key === 'Enter' || event.key === 'Tab') { event.preventDefault(); event.stopImmediatePropagation(); }
      };
      document.addEventListener('keydown', shield, true);
      modal.close();
      scanningBatch = true;
      const results = [];
      let saved = 0;
      try {
        for (const tag of batch) {
          if (!allowed() || current.id !== lotId || washChoice !== route || cloudStopped) break;
          const id = products.get(tag);
          let message;
          if (!id) message = 'Tag non associato in modo univoco';
          else if (current.rows.some(r=>r.code===id)) message = 'Già nel lotto';
          else {
            const error = await checkedProcess(id);
            message = error || 'Registrato';
            if (!error) saved++;
          }
          results.push(tag+' · '+message);
        }
      } catch (err) { results.push('Registrazione interrotta · '+err.message); }
      finally { document.removeEventListener('keydown', shield, true); scanningBatch = false; }
      if (current?.id === lotId) redrawLotKeepingScan();
      show('<h2>'+saved+' di '+batch.length+' capi registrati</h2><p>'+esc(lotLabel)+'</p><ol>'+results.map(r=>'<li>'+esc(r)+'</li>').join('')+'</ol><button type="button" class="btn" id="rfDone">Chiudi</button>');
      get('rfDone').onclick = () => modal.close();
    };
    get('rfGoal').focus();
  }
  new MutationObserver(mount).observe(document.getElementById('app'), {childList:true,subtree:true});
  mount();
})();
// The installed Android reader adds its button after the entry screen is drawn.
(function () {
  if (!navigator.userAgent.includes('MycrocleanRFID/')) return;
  document.addEventListener('click', event => {
    const tapped = event.target.closest?.('#nativeBulkProducts, #rfidEntryButton');
    const native = document.getElementById('nativeBulkProducts');
    if (!tapped || !native || !document.getElementById('entryNewProduct')) return;
    const block = message => { event.stopImmediatePropagation(); notify(message); };
    if (!current) return block('Seleziona il lotto da lavorare.');
    if (current.archived) return block('Questo lotto è archiviato.');
    if (stage !== 'Entrata') return block('Seleziona la fase Entrata per registrare i capi.');
    if (lotBusy() || washBusy || !washState) return block('Attendi il completamento dell’operazione in corso, poi tocca di nuovo RFID.');
    if (washChoice && selectedProcessing()) {
      if (tapped !== native) { event.stopImmediatePropagation(); native.click(); }
      return;
    }
    event.stopImmediatePropagation();
    const lotId = current.id;
    const routeField = document.getElementById('entryProcessing');
    if (!routeField) return notify('Il percorso di lavaggio è in caricamento. Riprova tra un momento.');
    const choices = Array.from(routeField.options).filter(o => o.value && !o.disabled);
    show('<h2>Scegli il percorso per la lettura RFID</h2><p><b>'+esc(lotno(current))+'</b> · '+esc(current.client)+'</p>'+
      '<form id="rfidRouteForm"><label>Lavaggio e macchina<select required data-native-select name="route"><option value="">Scegli il percorso…</option></select></label>'+
      '<button class="btn" type="submit">Continua con RFID</button><button class="btn secondary" type="button">Annulla</button></form>');
    const form = document.getElementById('rfidRouteForm'), modal = document.getElementById('modal');
    choices.forEach(o => form.elements.route.add(new Option(o.text, o.value)));
    form.querySelector('[type=button]').onclick = () => modal.close();
    form.onsubmit = e => {
      e.preventDefault();
      if (!current || current.id !== lotId || stage !== 'Entrata' || current.archived) {
        modal.close(); return notify('Il lotto è cambiato. Seleziona di nuovo la lettura RFID.');
      }
      if (lotBusy() || washBusy) return notify('Attendi il completamento dell’operazione in corso.');
      washSelect(form.elements.route.value);
      if (washChoice !== form.elements.route.value || !selectedProcessing()) return;
      modal.close();
      document.getElementById('nativeBulkProducts')?.click();
    };
  }, true);
})();

// WebView bridge for installed Zebra readers. Loaded before the bundled fallback.
(function () {
  if (!navigator.userAgent.includes('MycrocleanRFID/') || window.mycroBulkInstalled) return;
  window.mycroBulkInstalled = true;
  let pending = null;
  function mount() {
    if (typeof userCan !== 'function') return;
    const lotButton = document.querySelector('#entryNewProduct');
    if (!(lotButton ? userCan('lots_work') : userCan('products_manage'))) return;
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
    const valid = () => (!inLot ? userCan('products_manage') :
      (current && current.id === lot.id && !current.archived && stage === 'Entrata' && washChoice === route && userCan('lots_work')));
    show('<h2>Registra capi RFID</h2>'+(lot?'<p>'+esc(lotno(lot))+' · '+esc(lot.client)+'</p>':'')+
      '<form id="nativeRfidForm"><label>Cliente<select required name="client"><option value=""></option>'+options(lot?[lot.client]:clientNames())+'</select></label>'+
      '<label>Reparto<input name="dept"></label>'+
      (lot?'<label>Modalità di lettura<select name="batchType" data-native-select><option value="">Leggi tutto · tipologie miste</option></select></label>':'')+
      '<label>Numero massimo di capi da leggere<input name="goal" type="number" required min="1" max="1000" step="1" value="100"></label>'+
      '<button class="btn" type="submit">Inizia lettura</button></form><p id="nativeRfidStatus" role="status"></p>'+
      '<div id="rfidUnknown"></div><button class="btn" id="nativeRfidSave" hidden></button> <button class="btn secondary" id="nativeRfidClose">Chiudi</button>');
    const modal = document.getElementById('modal'), form = document.getElementById('nativeRfidForm');
    const status = document.getElementById('nativeRfidStatus'), save = document.getElementById('nativeRfidSave');
    const close = document.getElementById('nativeRfidClose');
    if (lot) { form.elements.client.value = lot.client; form.elements.dept.value = lot.departmentName || ''; }
    const typeField = form.elements.batchType;
    if (typeField) {
      for (const t of catalogRows('type').filter(t=>t.active)) {
        typeField.add(new Option('Per tipologia · '+t.name,t.name));
      }
    }
    let batchType = '';
    const differentType = product => batchType && String(product.type || '').trim().toLowerCase() !== batchType.trim().toLowerCase();
    let tags=[], next=0, created=0, existing=0, entered=0, skipped=0, failures=[], busy=false;
    let client, dept, reviewed=false;
    const choices=new Map();
    const unknown=document.getElementById('rfidUnknown');
    const saveLabel=lot?'Registra ingresso nel lotto':'Salva prodotti';
    async function review() {
      await cloudFlush();
      cloudAccept(await cloudRequest(),false);
      const missing=[];
      let known=0, ambiguous=0, mismatched=0;
      for(const epc of tags){
        if(!form.isConnected || !modal.open || !valid()) throw Error('La sessione di lettura è cambiata.');
        // Preview only. Unrelated changes in other lots must not invalidate the scanned list.
        // Each EPC is looked up again with revision checks before anything is written.
        const {data,error}=await productRpcOriginal('laundry_products_query',{p:{mode:'lookup',code:epc}});
        if(error) throw Error(error.message);
        const rows=data.rows;
        if(!rows.length)missing.push(epc);
        else if(rows.length===1){if(differentType(rows[0]))mismatched++;else known++;}
        else ambiguous++;
      }
      choices.clear(); unknown.textContent='';
      if(missing.length && userCan('products_manage')){
        const available=catalogRows('type').filter(t=>t.active);
        const template=document.createElement('select');
        template.setAttribute('data-native-select','');
        template.add(new Option('Scegli la tipologia…',''));
        template.add(new Option('Salta questo tag','__skip__'));
        available.forEach(t=>template.add(new Option(t.name,t.name)));
        if(missing.length>1){
          const label=document.createElement('label');
          label.textContent='Applica una tipologia a tutti i tag nuovi';
          const all=template.cloneNode(true);
          all.value=batchType;
          all.onchange=()=>{for(const field of choices.values())field.value=all.value;};
          label.append(all);unknown.append(label);
        }
        for(const epc of missing){
          const label=document.createElement('label');
          label.textContent='Tipo di prodotto per il nuovo tag '+epc;
          const select=template.cloneNode(true);
          select.value=batchType;
          label.append(select);unknown.append(label);choices.set(epc,select);
        }
      }
      status.textContent=known+' già in Prodotti · '+missing.length+' nuovi'+(ambiguous?' · '+ambiguous+' con associazione ambigua':'');
      if(batchType) status.textContent+=' · Tipologia scelta: '+batchType+(mismatched?' · '+mismatched+' di altra tipologia da escludere':'');
      if(missing.length && !userCan('products_manage')) status.textContent+=' · Per creare i nuovi prodotti serve un utente abilitato.';
      reviewed=true; save.textContent=saveLabel;
    }
    close.onclick = () => modal.close();
    form.onsubmit = event => {
      event.preventDefault();
      if (!valid()) return notify('Riapri il lotto e controlla il percorso.');
      client=form.elements.client.value; dept=form.elements.dept.value.trim();
      batchType=typeField?.value || '';
      const goal=Number(form.elements.goal.value);
      const token=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
      pending = {token, receive: result => {
        if (!modal.open || !form.isConnected || !valid()) return;
        const ids=Array.from(new Set(result));
        if (!ids.length || ids.length>goal || !ids.every(id=>typeof id==='string' && /^(?:[A-F0-9]{2}){1,62}$/.test(id))) return;
        tags=ids; form.hidden=true;
        status.textContent='Cerco '+tags.length+' tag in Prodotti…';
        save.textContent='Verifica tag';
        save.hidden=false; save.click();
      }};
      location.href='mycro-rfid://scan?count='+goal+'&token='+token;
    };
    save.onclick=async () => {
      if (busy || !tags.length || !valid()) return;
      busy=true; save.disabled=close.disabled=true;
      const guard=e=>e.preventDefault();
      modal.addEventListener('cancel',guard);
      try {
        if(!reviewed){await review();return;}
        const incomplete=[...choices].find(([,field])=>!field.value);
        if(incomplete){status.textContent='Scegli la tipologia oppure «Salta questo tag» per '+incomplete[0];incomplete[1].focus();return;}
        await cloudFlush();
        cloudAccept(await cloudRequest(),false);
        for (;next<tags.length;next++) {
          if (!valid()) throw Error('Lotto o percorso cambiato.');
          const epc=tags[next];
          status.textContent='Registrazione '+(next+1)+' di '+tags.length;
          const matches=(await productsRead({mode:'lookup',code:epc})).rows;
          if(matches.length>1){failures.push(epc+' · più prodotti associati');continue;}
          let id;
          if(matches.length && differentType(matches[0])){failures.push(epc+' · altra tipologia: '+(matches[0].type||'non indicata'));continue;}
          if(matches.length){productsHydrate(matches);id=matches[0].id;existing++;}
          else {
            const type=choices.get(epc)?.value;
            if(!type || type==='__skip__' || !userCan('products_manage')){failures.push(epc+' · nuovo, ingresso saltato');continue;}
            const product={id:epc,client,type,dept,name:'',size:'Da definire',color:'Da definire',wash:0,max:80,rental:null,history:[],
              raw:{CODICE:epc,TIPO:type,AZIENDA:client,REPARTO:dept,'NUMERO LAVAGGI':0,'LAVAGGI MASSIMI':80}};
            const response=await appSupabase.rpc('laundry_product_save',{p_payload:{revision:cloudRevision,original_id:null,mode:'manual',product}});
            if(response.error) {
              if(/BARCODE_ALREADY_EXISTS/.test(response.error.message)){failures.push(epc+' · codice già assegnato');continue;}
              throw Error(response.error.message);
            }
            cloudAccept(response.data,false);
            id=response.data.saved_id; await productsLoadIds([id]); created++;
          }
          if(lot) {
            if(!valid())throw Error('Lotto o percorso cambiato.');
            if(current.rows.some(r=>r.code===id)){skipped++;continue;}
            productRemote.pinned=[id];
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
        save.textContent=reviewed?'Riprendi':'Riprova verifica';
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
