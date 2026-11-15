(function () {
  const title = 'Magazzino sacchetti';
  const officeVisible = () => cloudUser && !window.floor?.active &&
    (cloudUser.role === 'admin' || userCan('production_manage'));
  let version = 0;
  const rpc = async (action, p = {}) => {
    if (!officeVisible()) throw new Error('Magazzino disponibile nella vista ufficio.');
    const {data,error} = await appSupabase.rpc('laundry_bag_stock',{action,p});
    if (error) throw new Error(error.message);
    return data;
  };
  const text = value => esc(String(value ?? '')).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  async function view() {
    const token = ++version, app = $('#app');
    app.innerHTML = heading(title,'Giacenze e consumi alla conferma di uscita dei capi.')+'<div class="panel" id="bagView" style="padding:16px">Caricamento…</div>';
    const panel = $('#bagView');
    try {
      const data = await rpc('read');
      if (!officeVisible() || token !== version || !panel.isConnected) return;
      const {bags,rules,history} = data;
      const names = new Map(bags.map(b=>[b.id,b.name]));
      const choices = bags.map(b=>'<option value="'+text(b.id)+'">'+text(b.name)+'</option>').join('');
      const typeChoices = catalogRows('type').filter(t=>t.active).map(t=>'<option value="'+text(t.id)+'">'+text(t.name)+'</option>').join('');
      const manage = userCan('products_manage');
      const form = (id,fields,caption) => '<form id="'+id+'" style="display:flex;align-items:end;gap:8px;flex-wrap:wrap;margin:12px 0">'+fields+'<button class="btn">'+caption+'</button></form>';
      const bagField = '<label>Sacchetto<select required name="bag">'+choices+'</select></label>';
      const table = (heads,rows,empty) => rows.length?'<div class="scroll"><table><thead><tr>'+heads.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+rows.map(c=>'<tr>'+c.map(v=>'<td>'+v+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>':'<p>'+empty+'</p>';
      panel.innerHTML = '<button id="bagRefresh" class="btn secondary">Aggiorna giacenza</button><h2>Giacenza in pezzi</h2>'+
        table(['Sacchetto','Disponibili'],bags.map(b=>[text(b.name),'<b>'+text(b.stock)+'</b>'+(b.stock<0?' · Verifica i carichi':'')]),'Inserisci il primo tipo di sacchetto.')+
        (manage?form('bagCreate','<label>Nuovo tipo di sacchetto<input required maxlength="120" name="name"></label>','Aggiungi sacchetto'):'')+
        (manage&&bags.length?form('bagMove',bagField+'<label>Movimento<select name="sign"><option value="1">Carico</option><option value="-1">Rettifica in diminuzione</option></select></label><label>Pezzi<input required type="number" min="1" max="2147483647" step="1" name="quantity"></label><label>Causale<input name="note" required maxlength="250" placeholder="Es. inventario iniziale"></label>','Registra movimento'):'')+
        '<h2>Distinta base</h2><p>Il capo usa il sacchetto della sua tipologia. Una regola sul singolo codice ha precedenza.</p>'+
        table(['Associazione','Capo','Sacchetto','Pezzi per uscita',...(manage?['']:[])],rules.map((r,i)=>[r.scope==='type'?'Tipologia':'Prodotto',text(r.label),text(names.get(r.bag)),text(r.quantity),...(manage?['<button class="link" data-rule="'+i+'">Rimuovi</button>']:[])]),'Nessuna associazione configurata.')+
        (manage&&bags.length?form('bagRule','<label>Applica a<select name="scope"><option value="type">Tipologia</option><option value="product">Singolo prodotto</option></select></label><label id="bagType">Tipo capo<select name="type" required>'+typeChoices+'</select></label><label id="bagProduct" hidden>Barcode / tag<input name="product" disabled></label>'+bagField+'<label>Pezzi per capo<input name="quantity" type="number" min="1" max="1000" required value="1"></label>','Salva associazione'):'')+
        '<h2>Ultimi 100 movimenti</h2>'+table(['Data','Sacchetto','Pezzi','Causale','Lotto','Codice capo'],history.map(m=>[text(new Date(m.at).toLocaleString('it-IT')),text(names.get(m.bag)),text(m.delta),text(m.note||'Uscita capo'),m.lot?text(lotno({id:m.lot})):'',text(m.product)]),'Nessun movimento registrato.')+'<p role="alert" id="bagError"></p>';
      $('#bagRefresh').onclick = view;
      async function write(button,action,p) {
        button.disabled=true;
        try {await rpc(action,p); if(panel.isConnected) await view();}
        catch(e){if(panel.isConnected){$('#bagError').textContent=e.message;notify(e.message);button.disabled=false;}}
      }
      function bind(id, action, payload) {
        const f=document.getElementById(id);
        if(f) f.onsubmit=e=>{e.preventDefault();write(f.querySelector('button'),action,payload(Object.fromEntries(new FormData(f))));};
      }
      bind('bagCreate','create',p=>p);
      let request=crypto.randomUUID();
      if($('#bagMove')) $('#bagMove').oninput=()=>{request=crypto.randomUUID();};
      bind('bagMove','move',p=>({...p,quantity:Number(p.quantity)*Number(p.sign),request}));
      bind('bagRule','rule',p=>({...p,target:p[p.scope]}));
      const scope=panel.querySelector('[name=scope]');
      if(scope)scope.onchange=()=>{
        const product=scope.value==='product';
        $('#bagType').hidden=product;$('#bagProduct').hidden=!product;
        $('#bagType select').disabled=product;$('#bagProduct input').disabled=!product;$('#bagProduct input').required=product;
      };
      panel.querySelectorAll('[data-rule]').forEach(b=>b.onclick=()=>{
        const r=rules[Number(b.dataset.rule)];
        if(confirm('Rimuovere l’associazione per '+r.label+'?'))write(b,'remove',{scope:r.scope,target:r.target});
      });
    } catch(e){if(panel.isConnected)panel.textContent=e.message;}
  }
  const before=render;
  render=function(...args){
    const result=before.apply(this,args);
    const nav=$('#nav');
    if(!officeVisible()){
      $('#bagStockNav')?.remove();
      return result;
    }
    if(nav && !$('#bagStockNav')){
      const b=document.createElement('button');b.id='bagStockNav';b.textContent=title;b.onclick=()=>{if(officeVisible())go(title);};
      nav.appendChild(b);
    }
    if(page===title && !current)view();
    return result;
  };
})();
