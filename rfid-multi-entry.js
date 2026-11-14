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